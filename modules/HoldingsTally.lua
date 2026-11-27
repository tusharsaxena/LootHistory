local _, NS = ...
NS.HoldingsTally = NS.HoldingsTally or {}
local T = NS.HoldingsTally

-- The holdings tally (#34, spec section 5): who on the account holds one thing, and where. The
-- holdings tooltip (modules/HoldingsTip.lua) and the public API (modules/HoldingsAPI.lua) read it.
--
-- TWO LAYERS. The SAVED store (NS.Holdings:SavedStore, never test mode's sample, never the
-- simulator's session table) is read once per thing into a cached entry, keyed by numeric id in two
-- maps, so no thing-key string is built on the hot path. The LIVE overlay -- the logged-in
-- character's bags and bank, and the warband bank where C.FEATURE.warbandBank, from
-- NS.Compat.LiveItemCounts; a currency from NS.Compat.CurrencyQuantity -- is composed on every call
-- and never cached, so the player's own bag changes need no event.
--
-- THE CACHE is wiped on HOLDINGS_CHANGED (the Reconciler is its one sender), on SETTINGS_CHANGED
-- with reason `ledger` or `profile` (trackLedger can flip), on Disable, and when it would grow past
-- C.TIP_CACHE_MAX things. Another holder's counts change only on a flush, and a flush never runs in
-- combat, so a cached entry is never stale in combat.
--
-- Reads NS.Holdings, NS.Compat, NS.Reconciler and NS.Util at call time only.

local C = NS.Constants
local WARBAND = C.WARBAND_HOLDER
local CONT = C.Container
local BAGS, BANK, TABS = CONT.BAGS, CONT.BANK, CONT.TABS
local DAY = 86400

-- Every container, in the Holdings tab's order (modules/HoldingsTab.lua ORDER), for the fixed key
-- loops that clear and fill a pooled output row.
local ALL = { CONT.BAGS, CONT.EQUIPPED, CONT.BANK, CONT.MAIL, CONT.AUCTIONS, CONT.TABS }

T._items, T._currencies, T._gen, T._size = {}, {}, 0, 0

--- Drop every cached entry: both maps are replaced, and the generation moves on.
function T:Invalidate()
  self._items, self._currencies = {}, {}
  self._gen = self._gen + 1
  self._size = 0
end

-- ── the zero-suspect rule (spec section 5.3) ──────────────────────────────────────────────────

--- The value one live-overlaid container shows, and whether it came from the store.
---   live nil                      -> stored  (no API, secret, Forever)
---   readable                      -> live    (at the banker the client is authoritative)
---   live 0 while stored above 0   -> stored  (the client has not loaded that bank this session;
---                                             ruling R8's bank guard, modules/Reconciler.lua)
---   otherwise                     -> live
function T._resolve(live, stored, readable)
  if live == nil then return stored, true end
  if readable then return live, false end
  if live == 0 and (stored or 0) > 0 then return stored, true end
  return live, false
end
local resolve = T._resolve

local function readable(part)
  local R = NS.Reconciler
  return R ~= nil and R.IsReadable ~= nil and R:IsReadable(part) == true
end

-- ── building an entry (a cache miss) ──────────────────────────────────────────────────────────

local function storedItems(e, id)
  local src = e and e.items and e.items[id]
  if not src then return nil, 0 end
  local copy, n = {}, 0
  for c, k in pairs(src) do copy[c] = k; n = n + k end
  return copy, n
end

local function newRow(holder, e, isMe)
  local meta = e and e.meta
  return { holder = holder, isMe = isMe, isWarband = holder == WARBAND,
           classFile = meta and meta.classFile or nil, scanned = e and e.scanned or nil }
end

-- Every holder with a nonzero stored count, plus the live holders even at zero, so the overlay can
-- lift them: the logged-in character always, and the warband where its bank is a feature.
local function buildItem(id)
  local me, rows = NS.Util.PlayerKey(), {}
  local liveWarband = C.FEATURE.warbandBank
  local store = NS.Holdings:SavedStore()
  for h, e in pairs(store) do
    local stored, n = storedItems(e, id)
    local isMe = h == me
    if n ~= 0 or isMe or (h == WARBAND and liveWarband) then
      local row = newRow(h, e, isMe)
      row.stored, row.storedCount = stored, n
      rows[#rows + 1] = row
    end
  end
  if store[me] == nil then rows[#rows + 1] = newRow(me, nil, true) end
  if liveWarband and store[WARBAND] == nil then rows[#rows + 1] = newRow(WARBAND, nil, false) end
  return { rows = rows, count = #rows }
end

-- A currency's live holder is the warband for an account-wide one (Scanner.ScanCurrencies' split),
-- otherwise the logged-in character.
local function buildCurrency(id)
  local me, rows = NS.Util.PlayerKey(), {}
  local liveHolder = NS.Compat.CurrencyIsAccountWide(id) and WARBAND or me
  local store = NS.Holdings:SavedStore()
  for h, e in pairs(store) do
    local n = e.currency and e.currency[id] or 0
    if n ~= 0 or h == liveHolder then
      local row = newRow(h, e, h == me)
      row.storedCount, row.isLive = n, h == liveHolder
      rows[#rows + 1] = row
    end
  end
  if store[liveHolder] == nil then
    local row = newRow(liveHolder, nil, liveHolder == me)
    row.storedCount, row.isLive = 0, true
    rows[#rows + 1] = row
  end
  return { rows = rows, count = #rows, liveHolder = liveHolder }
end

-- The cached entry for `id` in map `key` ("_items" or "_currencies"); a cache hit allocates nothing.
local function entryFor(self, key, id, build)
  local e = self[key][id]
  if e then return e end
  if self._size >= C.TIP_CACHE_MAX then self:Invalidate() end
  e = build(id)
  e.gen = self._gen
  self[key][id] = e
  self._size = self._size + 1
  return e
end

--- The cached entry for an item or currency, building it on a miss (a seam for the suites and for
--- the tooltip's replay memo, which lives on the entry).
function T:ItemEntry(itemID) return entryFor(self, "_items", itemID, buildItem) end
function T:CurrencyEntry(currencyID) return entryFor(self, "_currencies", currencyID, buildCurrency) end

-- ── composing a call ──────────────────────────────────────────────────────────────────────────

-- The scratch output: OUT holds references to pooled rows, POOL[i] keeps its containers table, and
-- both are valid until the next call (callers copy or paint before calling again).
local OUT, POOL = {}, {}

local function pooled(i)
  local o = POOL[i]
  if not o then o = { _c = {} }; POOL[i] = o end
  local c = o._c
  for j = 1, #ALL do c[ALL[j]] = nil end
  o.count, o.staleContainer, o.staleAt = 0, nil, nil
  return o
end

local function claim(o, row)
  o.holder, o.isMe, o.isWarband, o.classFile = row.holder, row.isMe, row.isWarband, row.classFile
end

-- Note container `c` holding `v` on `o`; a value that came from the store is a staleness candidate:
-- the oldest scan at or past one day wins, and a container never scanned is not reported.
local function put(o, row, c, v, fromStore, now)
  if not v or v <= 0 then return end
  o._c[c] = v
  o.count = o.count + v
  if not fromStore then return end
  local t = row.scanned and row.scanned[c]
  if t and now - t >= DAY and (o.staleAt == nil or t < o.staleAt) then
    o.staleContainer, o.staleAt = c, t
  end
end

local function fillItem(o, row, live, now)
  local stored = row.stored
  for j = 1, #ALL do
    local c = ALL[j]
    local s = stored and stored[c]
    local v, fromStore = s, true
    if row.isMe and c == BAGS then
      v, fromStore = resolve(live.bags, s, true)
    elseif row.isMe and c == BANK and live.bank ~= nil then
      v, fromStore = resolve(live.bank, s, readable("bank"))
    elseif row.isWarband and c == TABS and live.account ~= nil and C.FEATURE.warbandBank then
      v, fromStore = resolve(live.account, s, readable("tabs"))
    end
    put(o, row, c, v, fromStore, now)
  end
end

local LIVE = {}

-- Characters first by count descending, then holder ascending; the warband last
-- (NS.Holdings:Holders' order).
local function byCount(a, b)
  if a.isWarband ~= b.isWarband then return b.isWarband end
  if a.count ~= b.count then return a.count > b.count end
  return a.holder < b.holder
end

-- Trim OUT to `n` and sort it in place; returns the total.
local function finish(n, prev)
  for i = n + 1, prev do OUT[i] = nil end
  table.sort(OUT, byCount)
  local total = 0
  for i = 1, n do total = total + OUT[i].count end
  return total
end

--- Who holds base item `itemID`, and where. `now` defaults to time() (the staleness clock).
--- @return number total, table rows, number n  rows[i] = { holder, isMe, isWarband, classFile,
---   count, containers, staleContainer, staleAt }; rows is scratch, valid until the next call.
function T:Item(itemID, now)
  local prev = #OUT
  if type(itemID) ~= "number" then finish(0, prev); return 0, OUT, 0 end
  local entry = self:ItemEntry(itemID)
  LIVE.bags, LIVE.bank, LIVE.account = NS.Compat.LiveItemCounts(itemID)
  now = now or time()
  local n, rows = 0, entry.rows
  for i = 1, #rows do
    local o = pooled(n + 1)
    fillItem(o, rows[i], LIVE, now)
    if o.count > 0 then
      claim(o, rows[i]); o.containers = o._c
      n = n + 1; OUT[n] = o
    end
  end
  return finish(n, prev), OUT, n
end

--- Who holds currency `currencyID`. The live holder's count is the client's quantity when it
--- answers, else the stored count; a count from the store a day or more old is stale (the age
--- alone: staleContainer stays nil). Same returns as T:Item, with containers nil.
function T:Currency(currencyID, now)
  local prev = #OUT
  if type(currencyID) ~= "number" then finish(0, prev); return 0, OUT, 0 end
  local entry = self:CurrencyEntry(currencyID)
  local q = NS.Compat.CurrencyQuantity(currencyID)
  now = now or time()
  local n, rows = 0, entry.rows
  for i = 1, #rows do
    local row = rows[i]
    local live = row.isLive and q ~= nil
    local count = live and q or row.storedCount
    if count > 0 then
      local o = pooled(n + 1)
      claim(o, row); o.containers, o.count = nil, count
      local t = row.scanned and row.scanned.currency
      if not live and t and now - t >= DAY then o.staleAt = t end
      n = n + 1; OUT[n] = o
    end
  end
  return finish(n, prev), OUT, n
end

-- ── lifecycle (slash-commands-§7) ─────────────────────────────────────────────────────────────

--- One private bus target: HOLDINGS_CHANGED for any holder, and SETTINGS_CHANGED for `ledger` and
--- `profile`, each wiping the cache.
function T:Enable()
  if self.__ev or not NS.bus then return end
  self.__ev = NS.NewBusTarget()
  self.__ev:RegisterMessage(NS.MSG.HOLDINGS_CHANGED, function() T:Invalidate() end)
  self.__ev:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, reason)
    if reason == "ledger" or reason == "profile" then T:Invalidate() end
  end)
end

--- The stand-down half: the cache goes, and the private bus target goes wholesale.
function T:Disable()
  self:Invalidate()
  if not self.__ev then return end
  self.__ev:UnregisterAllMessages()
  self.__ev:UnregisterAllEvents()
  self.__ev = nil
end
