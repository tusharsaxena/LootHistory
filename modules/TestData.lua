local _, NS = ...
NS.TestData = NS.TestData or {}
local TD = NS.TestData

-- Test mode's ledger half (timeline-ledger P6, smoke TM-1). /lh test fills History and Insights from
-- BrowserTable:BuildTestData; this fills the Holdings and Timeline tabs the same way, with two
-- session-only stores published beside NS.State.testRecords:
--   * NS.State.testHoldings -- db.global.holdings' shape: five holders (four of the History sample's
--     characters and the Warband), the sample's thirty items, three currencies and gold;
--   * NS.State.testDaily -- db.global.daily's shape: SPAN_DAYS of closes and gained/lost tallies.
-- Read paths reach them through NS.Holdings:ActiveStore and NS.Rollup:ActiveStore, as History's do
-- through Database:ActiveHistory. No write path (Apply*, Credit*, the rollup writer) sees them.
--
-- Deterministic: the History sample's PRNG under a fixed seed, never math.random, so two builds for
-- one `now` are equal. Each series is walked BACKWARDS from what the holder holds now, so today's
-- close is the holdings figure, every earlier close is the later one with that day's flows undone,
-- and the sample rows' own gains and losses are folded into the tallies of the day they fell on.

local C = NS.Constants
local WARBAND = C.WARBAND_HOLDER
local SPAN_DAYS = 120
local GOLD = 10000   -- copper

-- The History sample's "mains" (its class weights, top four), keyed as BuildTestData keys a row.
local CLASSES = { "MAGE", "WARRIOR", "ROGUE", "PRIEST" }
local function charKey(cls) return cls:sub(1, 1) .. cls:sub(2):lower() .. "-Ravencrest" end

-- One fixed look per sample item: type and quality are functions of the id, never the PRNG stream.
local TYPES = { "Armor", "Consumable", "Tradegoods", "Weapon", "Quest", "Gem", "Recipe" }
local WARBAND_TYPES = { Tradegoods = true, Gem = true, Recipe = true }

-- Three real currencies under their own names, so a hover's tooltip agrees with the row.
local CURRENCIES = {
  { id = 3008, name = "Valorstones",        quality = 3 },
  { id = 2815, name = "Resonance Crystals", quality = 3 },
  { id = 2803, name = "Undercoin",          quality = 1 },
}

local function sample() return NS.BrowserTable.TestSample end

local function itemLook(idBase)
  local ty = TYPES[((idBase - 1) % #TYPES) + 1]
  local gear = (ty == "Armor" or ty == "Weapon")
  return { name = sample().itemNames[idBase], itemType = ty, gear = gear,
    quality = gear and (2 + idBase % 3) or (idBase % 4), itemSubType = sample().subType(ty, idBase) }
end

--- The display fields for one sample thing key (Holdings' describe shape), or nil when the key is
--- not part of the sample. Holdings reads this while the sample is the active store, so a held row
--- names the item the History sample names, not whatever the live client has under that id.
function TD.Describe(key)
  local kind, id = NS.Ledger.ParseThingKey(key)
  if kind == "ITEM" then
    local idBase = id - sample().idBase
    if not sample().itemNames[idBase] then return nil end
    local look = itemLook(idBase)
    return { name = look.name, quality = look.quality, itemType = look.itemType,
      itemSubType = look.itemSubType, key = key }
  end
  if kind == "CURRENCY" then
    for _, c in ipairs(CURRENCIES) do
      if c.id == id then
        return { name = c.name, quality = c.quality, itemType = C.CURRENCY_TYPE, itemSubType = "Sample" }
      end
    end
  end
  return nil
end

-- ── holdings ──

local function newHolder(genesis, now, classFile)
  return { meta = { genesis = genesis, partial = false, lastSeen = now, classFile = classFile },
    scanned = {}, items = {}, currency = {}, links = {} }
end

-- Where a held item sits: gear is worn or in the bags or bank, the rest in the bags or bank.
local function placeItem(rng, e, id, look, n)
  local where
  if look.gear then
    where = ({ C.Container.EQUIPPED, C.Container.BAGS, C.Container.BANK })[rng(3)]
  else
    where = (rng(3) == 1) and C.Container.BANK or C.Container.BAGS
  end
  e.items[id] = { [where] = n }
end

local function stack(rng, look)
  if look.gear then return rng(2) end
  return (look.quality <= 1) and (10 + rng(190)) or (1 + rng(40))
end

-- Scan stamps a few hours apart, so the Holdings tab's age column reads like real logins.
local function stampScans(rng, e, now)
  local cs = C.Container
  for _, c in ipairs({ cs.BAGS, cs.EQUIPPED, cs.BANK, "currency", "money" }) do
    e.scanned[c] = now - rng(48) * 3600
  end
end

local function buildHoldings(rng, genesis, now)
  local S, out = sample(), {}
  for _, cls in ipairs(CLASSES) do
    local e = newHolder(genesis, now, cls)
    for idBase = 1, #S.itemNames do
      local look = itemLook(idBase)
      -- The hot items (the first eight) are on every character, so their lines always compare.
      if idBase <= 8 or rng(100) <= 40 then placeItem(rng, e, S.idBase + idBase, look, stack(rng, look)) end
    end
    for _, c in ipairs(CURRENCIES) do
      if rng(100) <= 80 then e.currency[c.id] = 20 + rng(2400) end
    end
    e.money = (20000 + rng(280000)) * GOLD + rng(9999)
    stampScans(rng, e, now)
    out[charKey(cls)] = e
  end
  -- The Warband: reagents, gems and recipes in the bank tabs, warband gold, one account currency.
  local w = newHolder(genesis, now, nil)
  for idBase = 1, #S.itemNames do
    local look = itemLook(idBase)
    if WARBAND_TYPES[look.itemType] then w.items[S.idBase + idBase] = { [C.Container.TABS] = 20 + rng(400) } end
  end
  w.currency[CURRENCIES[3].id] = 100 + rng(900)
  w.money = (150000 + rng(600000)) * GOLD
  w.scanned[C.Container.TABS], w.scanned.currency, w.scanned.money = now - 7200, now - 7200, now - 7200
  out[WARBAND] = w
  return out
end

-- ── daily ──

-- SPAN_DAYS day keys, oldest first. Noon of each date, so a daylight-saving day cannot skip one.
local function dayKeys(now)
  local t, out = date("*t", now), {}
  for back = SPAN_DAYS - 1, 0, -1 do
    out[#out + 1] = NS.Ledger.DayKey(time({ year = t.year, month = t.month, day = t.day - back, hour = 12 }))
  end
  return out
end

-- The sample rows' own flows, by holder, thing and day, for the series that hold that thing.
local function rowFlows(records, held)
  local out = {}
  for _, r in ipairs(records or {}) do
    local h, key, dir = NS.Util.RowHolder(r), NS.Ledger.RowThingKey(r), NS.Util.RowDir(r)
    if h and key and held[h] and held[h][key] and dir ~= "MOVE" then
      local day = NS.Ledger.DayKey(r.ts)
      out[h] = out[h] or {}
      out[h][key] = out[h][key] or {}
      local f = out[h][key][day] or { i = 0, o = 0 }
      out[h][key][day] = f
      if dir == "OUT" then f.o = f.o + (r.quantity or 0) else f.i = f.i + (r.quantity or 0) end
    end
  end
  return out
end

-- A day's own movement for one kind of thing: { chance%, max } for a gain and for a loss; an item's
-- max is 0, meaning a fifth of what the holder ends up with.
local SWING = {
  g = { gain = { 75, 2500 * GOLD }, loss = { 55, 1800 * GOLD } },
  c = { gain = { 35, 60 },          loss = { 20, 80 } },
  i = { gain = { 15, 0 },           loss = { 10, 0 } },
}

local function roll(rng, spec, final)
  if rng(100) > spec[1] then return 0 end
  return rng(math.max(2, spec[2] > 0 and spec[2] or math.floor(final / 5)))
end

-- One series, newest day first: close(d-1) = close(d) - gained(d) + lost(d). A loss is raised when
-- undoing a day would leave less than nothing, so no close is ever negative.
local function walk(rng, daily, days, holder, key, final, flows)
  local swing = SWING[key:sub(1, 1)]
  local close = final
  for i = #days, 1, -1 do
    local day = days[i]
    local f = flows and flows[day]
    local gain = roll(rng, swing.gain, final) + (f and f.i or 0)
    local loss = roll(rng, swing.loss, final) + (f and f.o or 0)
    local before = close - gain + loss
    if before < 0 then loss, before = loss - before, 0 end
    if gain > 0 or loss > 0 or i == 1 then
      daily[day] = daily[day] or {}
      daily[day][holder] = daily[day][holder] or {}
      daily[day][holder][key] = { c = close, i = (gain > 0) and gain or nil, o = (loss > 0) and loss or nil }
    end
    close = before
  end
end

local function heldKeys(e)
  local out = {}
  for id, row in pairs(e.items) do
    local n = 0
    for _, k in pairs(row) do n = n + k end
    out["i:" .. id] = n
  end
  for id, n in pairs(e.currency) do out["c:" .. id] = n end
  out.g = e.money or 0
  return out
end

-- Sorted, so the PRNG meets the series in one order on every run (pairs order is not stable).
local function sortedKeys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out)
  return out
end

--- Build both sample stores for `now` from the History sample `records`. Returns holdings, daily.
function TD.Build(records, now)
  local rng = sample().rng(0x7E57DA7A)   -- fixed seed: identical stores every run
  local days = dayKeys(now)
  local genesis = time({ year = tonumber(days[1]:sub(1, 4)), month = tonumber(days[1]:sub(6, 7)),
    day = tonumber(days[1]:sub(9, 10)), hour = 12 })
  local holdings = buildHoldings(rng, genesis, now)
  local held = {}
  for h, e in pairs(holdings) do held[h] = heldKeys(e) end
  local flows, daily = rowFlows(records, held), {}
  for _, h in ipairs(sortedKeys(held)) do
    for _, key in ipairs(sortedKeys(held[h])) do
      walk(rng, daily, days, h, key, held[h][key], flows[h] and flows[h][key])
    end
  end
  return holdings, daily
end

--- Publish the sample stores beside test mode's `records` (BrowserTable:SetTestMode), or clear them
--- with nil. Session-only, like the records: nothing here is ever written to SavedVariables.
function TD.Publish(records)
  if records then
    NS.State.testHoldings, NS.State.testDaily = TD.Build(records, time())
  else
    NS.State.testHoldings, NS.State.testDaily = nil, nil
  end
end
