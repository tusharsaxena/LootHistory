local _, NS = ...
NS.Ledger = NS.Ledger or {}
local Ledger = NS.Ledger

-- Pure ledger primitives: no WoW API, no SavedVariables. Everything the Reconciler decides is built
-- from these so it can be pinned headless (timeline-ledger spec §5.1).

local KIND_PREFIX = { ITEM = "i:", CURRENCY = "c:" }
local PREFIX_KIND = { i = "ITEM", c = "CURRENCY" }

function Ledger.ThingKey(kind, id)
  if kind == "GOLD" then return "g" end
  return KIND_PREFIX[kind] .. tostring(id)
end

function Ledger.ParseThingKey(key)
  if key == "g" then return "GOLD", nil end
  local p, id = tostring(key):match("^([ic]):(%d+)$")
  if not p then return nil end
  return PREFIX_KIND[p], tonumber(id)
end

Ledger.DirSign = { IN = 1, OUT = -1, MOVE = 0 }

local function byKey(a, b) return tostring(a.key) < tostring(b.key) end

-- Signed per-key change from `old` to `new` ({[key]=count} maps; nil reads as empty). Sorted by
-- tostring(key) so callers and tests can index the result; a key whose count did not move is omitted.
-- NB the order is lexical ("10" < "2"): callers need a STABLE order, not a numeric one.
function Ledger.Diff(old, new)
  old, new = old or {}, new or {}
  local out = {}
  for k, n in pairs(new) do
    local d = n - (old[k] or 0)
    if d ~= 0 then out[#out + 1] = { key = k, delta = d } end
  end
  for k, o in pairs(old) do
    if new[k] == nil and o ~= 0 then out[#out + 1] = { key = k, delta = -o } end
  end
  table.sort(out, byKey)
  return out
end

-- ── Phase 2: classification (timeline-ledger spec §5.1, §5.3, §5.5) ──────────────────────────
-- Everything the Reconciler decides about a settled change, as pure functions over count maps.

Ledger.CLAIM_TTL       = 5     -- a chat claim waits this long for its holdings delta
Ledger.CLAIM_WAIT      = 1.5   -- a gain waits this long for its chat claim (delta-first case)
Ledger.SETTLE_TIMEOUT  = 6     -- a one-sided change at an open bank/mailbox/AH waits this long (BankLedger)
Ledger.COALESCE_WINDOW = 60    -- a same-key row younger than this is amended, not appended

-- Pairing order: sources and sinks are matched in this fixed order so the output is deterministic.
Ledger.CONTAINER_ORDER = { "bags", "equipped", "bank", "tabs", "mail", "auctions" }
-- Escrow: things that are the holder's but not in hand. Arrivals here are holdings-only (no row)
-- until resolved: a take from mail, a sale or a return from the auction house.
Ledger.ESCROW = { mail = true, auctions = true }

local ESCROW = Ledger.ESCROW

local function sortedIDs(maps)
  local seen, ids = {}, {}
  for _, m in ipairs(maps) do
    for id in pairs(m) do if not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
  end
  table.sort(ids)
  return ids
end

-- One item's per-container deltas split into sources (went down) and sinks (went up).
local function splitDeltas(id, list, before, after)
  local src, snk = {}, {}
  for _, c in ipairs(list) do
    local d = (after[c][id] or 0) - (before[c][id] or 0)
    if d < 0 then src[#src + 1] = { c = c, n = -d } elseif d > 0 then snk[#snk + 1] = { c = c, n = d } end
  end
  return src, snk
end

-- Match sources to sinks. An escrow source only MOVEs its own-origin count; the rest of what it
-- hands to a non-escrow sink is a gain from outside (mail from another player, a won auction).
local function pairWithin(id, src, snk, own, moves)
  local gain = 0
  for _, s in ipairs(src) do
    for _, t in ipairs(snk) do
      if s.n > 0 and t.n > 0 and not (ESCROW[s.c] and ESCROW[t.c]) then
        local q = math.min(s.n, t.n)
        local movable = q
        if ESCROW[s.c] then movable = math.min(q, (own and own[s.c] and own[s.c][id]) or 0) end
        if movable > 0 then moves[#moves + 1] = { id = id, qty = movable, from = s.c, to = t.c } end
        gain = gain + (q - movable)
        s.n, t.n = s.n - q, t.n - q
      end
    end
  end
  return gain
end

function Ledger.ClassifyItems(before, after, own)
  local moves, net = {}, {}
  local arrivals, exits = { mail = {}, auctions = {} }, {}
  local list, maps = {}, {}
  for _, c in ipairs(Ledger.CONTAINER_ORDER) do
    if before[c] and after[c] then
      list[#list + 1] = c
      maps[#maps + 1] = before[c]; maps[#maps + 1] = after[c]
    end
  end
  for _, id in ipairs(sortedIDs(maps)) do
    local src, snk = splitDeltas(id, list, before, after)
    local d = pairWithin(id, src, snk, own, moves)
    for _, s in ipairs(src) do
      if s.n > 0 then
        if s.c == "auctions" then exits[id] = (exits[id] or 0) + s.n
        elseif s.c ~= "mail" then d = d - s.n end   -- mail gone without landing: it never counted
      end
    end
    for _, t in ipairs(snk) do
      if t.n > 0 then
        if ESCROW[t.c] then arrivals[t.c][id] = (arrivals[t.c][id] or 0) + t.n else d = d + t.n end
      end
    end
    if d ~= 0 then net[id] = d end
  end
  return moves, net, arrivals, exits
end

local function byTostring(x, y) return tostring(x) < tostring(y) end

-- `n` moved `q` toward zero; zero is stored as no entry.
local function shrink(n, q)
  n = n + ((n < 0) and q or -q)
  if n == 0 then return nil end
  return n
end

-- Inter-holder pairing (char <-> §warband): opposite-sign changes of one thing on the two holders
-- are a transfer for the smaller magnitude. Both nets are reduced in place; zeros are removed.
function Ledger.PairHolders(a, netA, b, netB)
  local keys = {}
  for k in pairs(netA) do
    if netB[k] then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys, byTostring)
  local out = {}
  for _, k in ipairs(keys) do
    local x, y = netA[k], netB[k]
    if (x < 0) ~= (y < 0) then
      local q = math.min(math.abs(x), math.abs(y))
      local from, to = b, a
      if x < 0 then from, to = a, b end
      out[#out + 1] = { key = k, qty = q, from = from, to = to }
      netA[k], netB[k] = shrink(x, q), shrink(y, q)
    end
  end
  return out
end

-- ── Claims ──────────────────────────────────────────────────────────────────────────────────
-- claims[thingKey] = array of { qty, expires, row }. Posted by the chat paths after they write a
-- rich row; consumed by the Reconciler against a positive delta of the same thing.

function Ledger.PostClaim(claims, key, qty, row, now)
  local list = claims[key]
  if not list then list = {}; claims[key] = list end
  list[#list + 1] = { qty = qty, expires = now + Ledger.CLAIM_TTL, row = row }
end

function Ledger.ClaimAvailable(claims, key, now)
  local n = 0
  for _, c in ipairs(claims[key] or {}) do if c.expires >= now then n = n + c.qty end end
  return n
end

function Ledger.ConsumeClaim(claims, key, gain, now)
  local list = claims[key]
  if not list or gain <= 0 then return gain, nil end
  local matched, i = nil, 1
  while i <= #list and gain > 0 do
    local c = list[i]
    if c.expires < now then
      table.remove(list, i)
    else
      local take = math.min(gain, c.qty)
      gain, c.qty = gain - take, c.qty - take
      matched = matched or {}
      matched[#matched + 1] = c.row
      if c.qty == 0 then table.remove(list, i) else i = i + 1 end
    end
  end
  if #list == 0 then claims[key] = nil end
  return gain, matched
end

function Ledger.PruneClaims(claims, now)
  for key, list in pairs(claims) do
    for i = #list, 1, -1 do if list[i].expires < now then table.remove(list, i) end end
    if #list == 0 then claims[key] = nil end
  end
end

-- ── Coalescing and the settle hold ──────────────────────────────────────────────────────────
function Ledger.CoalesceKey(holder, key, dir, reason, route)
  return table.concat({ holder, tostring(key), dir, reason, route or "" }, "\001")
end

function Ledger.Amendable(entry, now)
  return entry ~= nil and (now - entry.ts) < Ledger.COALESCE_WINDOW
end

-- Hold the baseline (write nothing, keep the dirty bits) while a change is plausibly half-done:
-- a one-sided move at an open bank/mailbox/AH (the other side is a server round-trip away), or a
-- gain whose chat claim has not arrived yet. Each wait is bounded; past it the pass commits.
function Ledger.ShouldHold(oneSided, unclaimedGain, holdSince, now)
  if not (oneSided or unclaimedGain) then return false end
  local waited = holdSince and (now - holdSince) or 0
  if oneSided and waited < Ledger.SETTLE_TIMEOUT then return true end
  if unclaimedGain and waited < Ledger.CLAIM_WAIT then return true end
  return false
end

function Ledger.Signed(dir, qty) return (qty or 0) * (Ledger.DirSign[dir] or 0) end

-- ── Reasons (timeline-ledger spec §5.4) ─────────────────────────────────────────────────────
local DECONSTRUCT_SOURCE = { DISENCHANT = true, MILLING = true, PROSPECTING = true }

local function stampApplies(o, kind, dir, now)
  return o and o.expires >= now and (not o.dirs or o.dirs[dir]) and (not o.kinds or o.kinds[kind])
end

-- MERCHANT_REASON[dir == "OUT"][kind == "ITEM"]: at a merchant an item going out is sold and gold
-- going out buys; anything else is coming in, where an item was vendored and gold is the sale.
local MERCHANT_REASON = {
  [true] = { [true] = "SELL", [false] = "BUY" },
  [false] = { [true] = "VENDOR", [false] = "SELL" },
}

-- The scopes gold going out is spent under, first match wins.
local GOLD_OUT_SCOPES = {
  { "trainer", "TRAINING" }, { "taxi", "TRAVEL" }, { "auction", "AH_POST_FEE" }, { "mailbox", "MAIL_SEND" },
}

local function goldOutReason(s)
  for _, e in ipairs(GOLD_OUT_SCOPES) do
    if s[e[1]] then return e[2] end
  end
  return nil
end

local function scopeReason(kind, dir, s)
  if s.guildBank then return dir == "OUT" and "GUILD_DEPOSIT" or "GUILD_WITHDRAW" end
  if s.merchant then return MERCHANT_REASON[dir == "OUT"][kind == "ITEM"] end
  if kind == "GOLD" and dir == "OUT" then return goldOutReason(s) end
  return nil
end

local function inferItemLoss(c)
  local l = c.loot
  if l and l.expires >= c.now and DECONSTRUCT_SOURCE[l.source] then return "DECONSTRUCT" end
  if c.craftUntil and c.craftUntil >= c.now then return "CRAFT_REAGENT" end
  if c.consumable then return "CONSUME" end
  return nil
end

function Ledger.PickReason(kind, dir, c)
  if c.forced then return c.forced end
  if stampApplies(c.out, kind, dir, c.now) then return c.out.reason end
  if c.currencySrc then return c.currencySrc end
  local s = c.scopes or {}
  local r = scopeReason(kind, dir, s)
  if r then return r end
  if kind == "ITEM" and dir == "OUT" then r = inferItemLoss(c); if r then return r end end
  if dir == "IN" then
    local l = c.loot
    if l and l.expires >= c.now then return l.source end
    if s.mailbox then return "MAIL" end
    if s.auction then return "AH" end
  end
  return "OTHER"
end

function Ledger.CurrencyReason(name, dir)
  if not name then return nil end
  local map = NS.Constants.CURRENCY_SOURCE_REASON[dir == "IN" and "gain" or "loss"]
  return map and map[name] or nil
end

-- ── Daily rollup cells (timeline-ledger spec §4.3) ───────────────────────────────────────────
--
-- daily[day][holder][thingKey] = { c = close, i = gained, o = lost }. SPARSE twice over: a cell
-- exists only for a (day, holder, thing) that changed, and inside it a field exists only when it is
-- non-zero / known. `c` is the holder's total of the thing at the end of that day as far as the
-- addon has seen; the Timeline carries the last `c` forward across days with no cell.

local DAY_FMT = "%Y-%m-%d"

-- The local calendar day of `ts`. "YYYY-MM-DD" is zero-padded, so plain string comparison orders
-- days chronologically -- PruneDaily and the Timeline's day walk both rely on that.
function Ledger.DayKey(ts) return date(DAY_FMT, ts) end

function Ledger.RowThingKey(r)
  local kind = NS.Util.RowKind(r)
  if kind == "GOLD" then return "g" end
  local id = (kind == "CURRENCY") and r.currencyID or r.itemID
  if id == nil then return nil end
  return Ledger.ThingKey(kind, id)
end

local function cellOf(daily, day, holder, key)
  local d = daily[day]
  if not d then d = {}; daily[day] = d end
  local h = d[holder]
  if not h then h = {}; d[holder] = h end
  local c = h[key]
  if not c then c = {}; h[key] = c end
  return c
end

function Ledger.RollupClose(daily, day, holder, key, close)
  cellOf(daily, day, holder, key).c = close
end

function Ledger.RollupFlow(daily, day, holder, key, dir, qty)
  if not qty or qty <= 0 then return end
  if dir == "IN" then
    local c = cellOf(daily, day, holder, key); c.i = (c.i or 0) + qty
  elseif dir == "OUT" then
    local c = cellOf(daily, day, holder, key); c.o = (c.o or 0) + qty
  end
end

-- Newest close per (holder, key) across `days` (sorted ascending), as last[holder][key].
local function lastCloses(daily, days)
  local last = {}
  for _, day in ipairs(days) do
    for holder, things in pairs(daily[day]) do
      local h = last[holder] or {}
      last[holder] = h
      for key, cell in pairs(things) do
        if cell.c ~= nil then h[key] = cell.c end
      end
    end
  end
  return last
end

-- Drop days before `cutoffDay`. What a pruned day knew that the Timeline still needs is each
-- thing's last close -- without it a balance that did not move after the cutoff would draw nothing
-- until its next change -- so the newest pruned close is folded onto the cutoff day, unless that
-- day already has a close of its own (which is newer). In/out tallies are not folded.
function Ledger.PruneDaily(daily, cutoffDay)
  local old = {}
  for day in pairs(daily) do
    if day < cutoffDay then old[#old + 1] = day end
  end
  if #old == 0 then return 0 end
  table.sort(old)
  local last = lastCloses(daily, old)
  for _, day in ipairs(old) do daily[day] = nil end
  for holder, things in pairs(last) do
    for key, c in pairs(things) do
      local d = daily[cutoffDay]
      local cell = d and d[holder] and d[holder][key]
      if not (cell and cell.c ~= nil) then Ledger.RollupClose(daily, cutoffDay, holder, key, c) end
    end
  end
  return #old
end

function Ledger.ForgetHolderDaily(daily, holder)
  local removed = 0
  for day, holders in pairs(daily) do
    local things = holders[holder]
    if things then
      for _ in pairs(things) do removed = removed + 1 end
      holders[holder] = nil
      if next(holders) == nil then daily[day] = nil end
    end
  end
  return removed
end

-- Clear the tallies of one holder's touched cells on a held day, marking each key wanted (w).
-- Answers how many cells were named.
local function clearTouchedCells(cells, keys, w)
  local n = 0
  for key in pairs(keys) do
    w[key] = true
    local c = cells and cells[key]
    if c then c.i, c.o = nil, nil end
    n = n + 1
  end
  return n
end

-- Phase 1 of RecomputeFlows: clear every touched cell on a day the rollup still holds. Answers
-- want[holder][key] (the things worth reading a row for) and the number of cells cleared.
local function clearTouched(daily, touched)
  local want, n = {}, 0
  for day, holders in pairs(touched) do
    local d = daily[day]
    if d then
      for holder, keys in pairs(holders) do
        local w = want[holder] or {}
        want[holder] = w
        n = n + clearTouchedCells(d[holder], keys, w)
      end
    end
  end
  return want, n
end

-- Phase 2 for one row: fold it back in when its (day, holder, thing) was touched and the day is held.
local function refoldRow(daily, touched, want, r)
  local dir, holder = NS.Util.RowDir(r), NS.Util.RowHolder(r)
  local w = dir ~= "MOVE" and r.ts and want[holder]
  local key = w and Ledger.RowThingKey(r)
  if not (key and w[key]) then return end
  local day = Ledger.DayKey(r.ts)
  local t = daily[day] and touched[day]
  local h = t and t[holder]
  if h and h[key] then Ledger.RollupFlow(daily, day, holder, key, dir, r.quantity) end
end

-- Rebuild the in/out tallies of the cells named in touched[day][holder][key] from `rows` (the v13
-- step, timeline-ledger Phase 7): each such cell's `i` / `o` is cleared and re-summed from every IN /
-- OUT row of that day, holder and thing, so a tally always matches the rows that produced it. A day
-- the rollup no longer holds (pruned) is skipped, never recreated, and a close is never touched.
-- Answers the number of cells rebuilt.
function Ledger.RecomputeFlows(daily, rows, touched)
  local want, n = clearTouched(daily, touched)
  if n == 0 then return 0 end
  for _, r in ipairs(rows) do refoldRow(daily, touched, want, r) end
  return n
end

-- ── Holder moves (timeline-ledger Phase 7, owner decision 2026-10-06) ──
-- A `from` / `to` end is "<holder>/<container>". Neither a PlayerKey nor "§warband" carries a "/",
-- so the holder is everything before the last one.
function Ledger.LocationHolder(loc)
  if type(loc) ~= "string" then return nil end
  return loc:match("^(.*)/[^/]*$")
end

local function containerOf(loc)
  return type(loc) == "string" and loc:match("/([^/]*)$") or nil
end

-- The five reasons a move between two holders is written under (an OUT on the sender, an IN on the
-- receiver). Published for test mode's History sample, which writes its holder moves the same way.
local HOLDER_MOVE_REASON = { WARBAND_DEPOSIT = true, WARBAND_WITHDRAW = true, ALT_MAIL = true,
  ALT_TRADE = true, CURRENCY_TRANSFER = true }
Ledger.HOLDER_MOVE_REASON = HOLDER_MOVE_REASON

-- The reason a stored move between two different holders takes (the v13 step). The Warband end
-- names the direction; between characters, a mail end means ALT_MAIL, a currency CURRENCY_TRANSFER,
-- and anything else, which the row cannot tell apart, reads as ALT_TRADE. A row already carrying a
-- holder-move reason keeps it.
function Ledger.HolderMoveReason(r, fromH, toH)
  if HOLDER_MOVE_REASON[r.source] then return r.source end
  local warband = NS.Constants.WARBAND_HOLDER
  if toH == warband then return "WARBAND_DEPOSIT" end
  if fromH == warband then return "WARBAND_WITHDRAW" end
  local mail = NS.Constants.Container.MAIL
  if containerOf(r.from) == mail or containerOf(r.to) == mail then return "ALT_MAIL" end
  if NS.Util.RowKind(r) == "CURRENCY" then return "CURRENCY_TRANSFER" end
  return "ALT_TRADE"
end
