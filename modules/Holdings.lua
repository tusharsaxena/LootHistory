local _, NS = ...
-- luacheck: ignore 212/self
NS.Holdings = NS.Holdings or {}
local Holdings = NS.Holdings

-- The holdings ledger (timeline-ledger spec §4.2): db.global.holdings[holder]. Account-wide; one
-- writer (the Reconciler, through the Apply* calls, plus the Credit* writes it makes for an own
-- alt's transfer or escrow); every reader goes through this API. Every one of those writes reports
-- each total it changed to the daily rollup (NS.Rollup:NoteClose, timeline-ledger P3), so the
-- rollup's closes are exactly this store.

local C = NS.Constants
local WARBAND = C.WARBAND_HOLDER

-- The rollup's close seam (timeline-ledger P3, plan "Phase 2 contract"): every total that changes
-- here is reported once, after the write, so the Timeline's daily close is exactly this store.
local function noteClose(holder, key, ts, n)
  if NS.Rollup and NS.Rollup.NoteClose then NS.Rollup:NoteClose(holder, key, ts, n) end
end

local function itemTotal(row)
  local n = 0
  if row then for _, k in pairs(row) do n = n + k end end
  return n
end

-- A holder is partial from genesis until its gate container (bank / warband tabs) is first read;
-- the Timeline draws that stretch dashed, so the moment it ends is recorded once.
local function endPartial(e, holder, container, ts)
  local gate = (holder == WARBAND) and C.Container.TABS or C.Container.BANK
  if container == gate and e.meta.genesis and e.meta.partial and not e.meta.completeAt then
    e.meta.partial, e.meta.completeAt = false, ts
  end
end

function Holdings:Store()
  local g = NS.db and NS.db.global
  if not g then return {} end
  g.holdings = g.holdings or {}
  return g.holdings
end

-- The store every READ path resolves against (the Holdings tab, the Timeline, the Character list,
-- /lh's holdings search): test mode's session-only sample (NS.State.testHoldings, modules/TestData.lua)
-- while it is on, otherwise the live store -- as Database:ActiveHistory is for the loot rows. Every
-- write (Get with create, Apply*, Credit*, ForgetHolder, the rollup seed) stays on Store().
function Holdings:ActiveStore()
  return (NS.State and NS.State.testHoldings) or self:Store()
end

-- One holder's entry for DISPLAY (class color, meta). Get is the writers' accessor and stays live.
function Holdings:View(holder)
  return self:ActiveStore()[holder]
end

function Holdings:Get(holder, create)
  local s = self:Store()
  local e = s[holder]
  if not e and create then
    e = { meta = {}, scanned = {}, items = {}, currency = {}, links = {} }
    s[holder] = e
  end
  return e
end

function Holdings:ApplyContainer(holder, container, counts, links, ts)
  local e = self:Get(holder, true)
  local touched = {}
  for id, row in pairs(e.items) do
    local want = counts[id]
    if row[container] ~= want then
      row[container] = want; touched[id] = true
      if next(row) == nil then e.items[id] = nil end
    end
  end
  for id, n in pairs(counts) do
    local row = e.items[id]
    if not row then row = {}; e.items[id] = row end
    if row[container] ~= n then row[container] = n; touched[id] = true end
  end
  for id, link in pairs(links or {}) do e.links[id] = link end
  e.scanned[container] = ts
  e.meta.lastSeen = ts
  endPartial(e, holder, container, ts)
  local changed = false
  for id in pairs(touched) do
    changed = true
    noteClose(holder, "i:" .. id, ts, itemTotal(e.items[id]))
  end
  return changed
end

function Holdings:ApplyCurrency(holder, map, ts)
  local e = self:Get(holder, true)
  local old, changed = e.currency, false
  for id, n in pairs(map) do
    if old[id] ~= n then changed = true; noteClose(holder, "c:" .. id, ts, n) end
  end
  for id in pairs(old) do
    if map[id] == nil then changed = true; noteClose(holder, "c:" .. id, ts, 0) end
  end
  e.currency = map
  e.scanned.currency, e.meta.lastSeen = ts, ts
  return changed
end

function Holdings:ApplyMoney(holder, copper, ts)
  local e = self:Get(holder, true)
  local changed = e.money ~= copper
  e.money = copper
  e.scanned.money, e.meta.lastSeen = ts, ts
  if changed then noteClose(holder, "g", ts, copper or 0) end
  return changed
end

function Holdings:MarkGenesis(holder, ts)
  local e = self:Get(holder, true)
  e.meta.genesis = e.meta.genesis or ts
  local gate = (holder == WARBAND) and C.Container.TABS or C.Container.BANK
  e.meta.partial = e.scanned[gate] == nil
end

function Holdings:ItemCounts(holder)
  local e, out = self:Get(holder), {}
  if not e then return out end
  for id, row in pairs(e.items) do
    local n = 0; for _, c in pairs(row) do n = n + c end
    out[id] = n
  end
  return out
end

function Holdings:Holders()
  local chars, hasWarband = {}, false
  for h in pairs(self:ActiveStore()) do
    if h == WARBAND then hasWarband = true else chars[#chars + 1] = h end
  end
  table.sort(chars)
  if hasWarband then chars[#chars + 1] = WARBAND end
  return chars
end

-- One holder's count of `thingKey`, with its container split and the oldest scan feeding it.
local function holderCount(e, kind, id)
  if kind == "GOLD" then return e.money or 0, nil, e.scanned.money end
  if kind == "CURRENCY" then return e.currency[id] or 0, nil, e.scanned.currency end
  local row = e.items[id]
  if not row then return 0 end
  local n, oldest, split = 0, nil, {}
  for c, k in pairs(row) do
    n = n + k; split[c] = k
    local t = e.scanned[c]
    if t and (not oldest or t < oldest) then oldest = t end
  end
  return n, split, oldest
end

function Holdings:Total(thingKey, holderSet)
  local kind, id = NS.Ledger.ParseThingKey(thingKey)
  local total, rows = 0, {}
  if not kind then return 0, rows end
  for h, e in pairs(self:ActiveStore()) do
    if not holderSet or holderSet[h] then
      local n, split, at = holderCount(e, kind, id)
      if n ~= 0 then
        total = total + n
        rows[#rows + 1] = { holder = h, count = n, containers = split, scannedAt = at }
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.holder < b.holder
  end)
  return total, rows
end

-- Display fields for a thing. Uncached items keep a row: name falls back to the link's bracket text,
-- then to "item:<id>" (Review Focus 2).
local function describe(key, kind, id, link)
  -- Test mode names a sample thing the way the History sample does, not by the live client's item.
  local sample = NS.State.testHoldings and NS.TestData and NS.TestData.Describe(key)
  if sample then return sample end
  if kind == "GOLD" then return { name = _G.GOLD or "Gold", itemType = _G.GOLD or "Gold" } end
  if kind == "CURRENCY" then
    return { name = NS.Compat.CurrencyName(id) or ("currency:" .. id), quality = NS.Compat.CurrencyQuality(id),
             itemType = C.CURRENCY_TYPE, itemSubType = NS.Compat.CurrencyCategory(id) }
  end
  local _, name, quality = NS.Compat.GetItemInfo(link or ("item:" .. id))
  local itemType, itemSubType = NS.Compat.GetItemTypeInfo(link or id)
  return { name = name or ("item:" .. id), quality = quality, itemType = itemType, itemSubType = itemSubType, key = key }
end

-- The display fields for one thing key, for surfaces that hold a key and not a Search row (the
-- Timeline's title and its picker's rollup-only suggestions). Uses any holder's last-seen link.
function Holdings:Describe(key)
  local kind, id = NS.Ledger.ParseThingKey(key)
  if not kind then return { name = tostring(key) } end
  local link
  if kind == "ITEM" then
    for _, e in pairs(self:ActiveStore()) do link = link or (e.links and e.links[id]) end
  end
  return describe(key, kind, id, link)
end

local function setPasses(set, v) return not set or next(set) == nil or (v ~= nil and set[v]) end

-- Every thing key any holder in `store` holds, and the first last-seen link per item id.
local function heldThings(store)
  local seen, links = {}, {}
  for _, e in pairs(store) do
    for id in pairs(e.items) do seen["i:" .. id] = true; links[id] = links[id] or e.links[id] end
    for id in pairs(e.currency) do seen["c:" .. id] = true end
    if e.money then seen.g = true end
  end
  return seen, links
end

-- Whether a thing's display fields `d` pass the lowered search `text` (nil: no text) and the
-- filter's quality, type and subtype sets.
local function thingPasses(d, filter, text)
  return (not text or d.name:lower():find(text, 1, true))
    and setPasses(filter.quality, d.quality) and setPasses(filter.itemType, d.itemType)
    and setPasses(filter.itemSubType, d.itemSubType)
end

function Holdings:Search(filter)
  filter = filter or {}
  local holderSet = (filter.char and next(filter.char)) and filter.char or nil
  local text = filter.text and filter.text ~= "" and filter.text:lower() or nil
  local seen, links = heldThings(self:ActiveStore())
  local out = {}
  for key in pairs(seen) do
    local kind, id = NS.Ledger.ParseThingKey(key)
    local d = describe(key, kind, id, links[id])
    if thingPasses(d, filter, text) then
      local total, rows = self:Total(key, holderSet)
      if total ~= 0 then
        out[#out + 1] = { key = key, kind = kind, id = id, name = d.name, quality = d.quality,
          itemType = d.itemType, itemSubType = d.itemSubType, total = total, holders = rows, link = links[id] }
      end
    end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

function Holdings:ForgetHolder(holder)
  local s = self:Store()
  if s[holder] == nil then return false end
  s[holder] = nil
  return true
end

-- Credit an own alt's stored currency for a transfer this character just made, so the alt's next
-- login does not read the arrival as untracked drift. Only a holder whose currency was ever scanned:
-- an alt with no baseline gets the amount as part of its genesis instead.
function Holdings:CreditCurrency(holder, id, qty)
  local e = self:Get(holder)
  if not (e and e.scanned.currency) then return false end
  local v = (e.currency[id] or 0) + qty
  e.currency[id] = (v > 0) and v or nil
  noteClose(holder, "c:" .. id, time(), e.currency[id] or 0)
  return true
end

-- Escrow bookkeeping (timeline-ledger spec §3 `mail`/`auctions`): how much of a holder's mail came
-- from an own source (an alt's send, a returned auction), gold mailed in from an alt, and auctions
-- that left the AH without yet resolving to a sale or a return. Persisted: a mail can sit for weeks.
function Holdings:Escrow(holder)
  local e = self:Get(holder, true)
  e.escrow = e.escrow or { mailOwn = {}, mailMoney = 0, exits = {} }
  return e.escrow
end

-- The part of `mailOwn` an own alt sent (timeline-ledger Phase 7): taking it is that alt's move
-- landing, an IN ALT_MAIL, where the rest of mailOwn (an auction's return) is a MOVE. Created on
-- first use, so escrow written before it existed reads as "no alt mail".
function Holdings:MailAlt(holder)
  local esc = self:Escrow(holder)
  esc.mailAlt = esc.mailAlt or {}
  return esc.mailAlt
end

-- Put `qty` of `id` into a holder's escrow container without a scan (a send to an alt, a post).
-- The column's scanned time is left alone: the next real scan is authoritative.
function Holdings:CreditEscrow(holder, container, id, qty, own)
  local e = self:Get(holder)
  if not e then return false end
  local row = e.items[id]
  if not row then row = {}; e.items[id] = row end
  row[container] = (row[container] or 0) + qty
  if own then
    local esc = self:Escrow(holder)
    esc.mailOwn[id] = (esc.mailOwn[id] or 0) + qty
  end
  noteClose(holder, "i:" .. id, time(), itemTotal(e.items[id]))
  return true
end
