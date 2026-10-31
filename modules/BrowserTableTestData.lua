local _, NS = ...

-- The History sample behind test mode: BrowserTable:BuildTestData and BrowserTable.TestSample, moved
-- verbatim out of modules/BrowserTable.lua, which keeps the switch (SetTestMode). Loaded directly
-- after it. modules/TestData.lua reads TestSample at its file load, so this file stays above that one.

local BrowserTable = NS.BrowserTable
local C = NS.Constants

-- Synthetic dataset for /lh test. A deliberately NON-uniform spread so the Insights charts read
-- like real play: weighted-random sources/qualities/classes/zones/types/timestamps, a handful of
-- "hot" items that drop often over a long tail, and keystone/hour peaks. A deterministic PRNG
-- (fixed seed, NOT math.random) keeps the data byte-identical every run so the headless tests stay
-- stable. A short seed pass first guarantees every source/quality/class/binding appears and the
-- range spans >14 days regardless of how the dice fall.
local TEST_BINDINGS = {
  { key = nil,       name = "Unbound" },
  { key = "BOE",     name = "Bind on Equip" },
  { key = "BOP",        name = "Bind on Pickup" },
  { key = "WARBAND",    name = "Warbound" },
  { key = "WARBAND_UE", name = "Warbound Until Equipped" },
}
local TEST_CLASSES = {
  "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
  "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}
-- Midnight (12.0.x) zones — Quel'Thalas region.
local TEST_ZONES = {
  { name = "Silvermoon City",    mapID = 110 },
  { name = "Eversong Woods",     mapID = 94 },
  { name = "Isle of Quel'Danas", mapID = 122 },
  { name = "Zul'Aman",           mapID = 781 },
  { name = "Harandar",           mapID = 2400 },
  { name = "Tirisfal Glades",    mapID = 18 },
}
-- Weighted distributions ({ value, weight }) — larger weight ⇒ appears more, so no two bars match.
local TEST_SOURCE_W = {
  { "KILL", 30 }, { "CONTAINER", 22 }, { "QUEST", 16 }, { "MPLUS", 15 }, { "VENDOR", 10 },
  { "ROLL", 9 }, { "MAIL", 8 }, { "TRADE", 7 }, { "DISENCHANT", 7 }, { "AH", 6 },
  { "CRAFT", 6 }, { "MILLING", 5 }, { "PROSPECTING", 5 }, { "OTHER", 4 },
}
local TEST_QUALITY_W = { { 0, 8 }, { 1, 14 }, { 2, 26 }, { 3, 22 }, { 4, 12 }, { 5, 4 } }
local TEST_CLASS_W = {  -- a few "mains" dominate the play time
  { "MAGE", 14 }, { "WARRIOR", 12 }, { "ROGUE", 10 }, { "PRIEST", 9 }, { "DRUID", 9 },
  { "PALADIN", 8 }, { "HUNTER", 8 }, { "DEATHKNIGHT", 6 }, { "SHAMAN", 6 }, { "WARLOCK", 6 },
  { "MONK", 5 }, { "DEMONHUNTER", 5 }, { "EVOKER", 4 },
}
local TEST_ZONE_W = { { 1, 24 }, { 2, 18 }, { 4, 16 }, { 3, 12 }, { 6, 10 }, { 5, 8 } } -- index into TEST_ZONES
local TEST_TYPE_W = {
  { "Armor", 22 }, { "Consumable", 20 }, { "Tradegoods", 18 }, { "Weapon", 14 },
  { "Quest", 10 }, { "Gem", 8 }, { "Recipe", 6 },
}
-- Representative subtypes per item type, so the SubType column/filter has variety in test mode.
-- Chosen deterministically off idBase (never the RNG stream) to keep the synthetic data stable.
local TEST_SUBTYPES = {
  Armor      = { "Cloth", "Leather", "Mail", "Plate" },
  Weapon     = { "One-Handed Swords", "Daggers", "Staves", "Bows" },
  Consumable = { "Potion", "Food & Drink", "Flask" },
  Tradegoods = { "Herb", "Cloth", "Metal & Stone", "Leather" },
  Gem        = { "Cut Gem", "Uncut Gem" },
  Recipe     = { "Tailoring", "Alchemy", "Blacksmithing" },
  Quest      = { "Quest" },
}
local TEST_SUBTYPES_MISC = { "Other", "Junk" }
local TEST_KEY_W = {  -- keystone levels cluster around the mid keys
  { 2, 4 }, { 3, 6 }, { 4, 8 }, { 5, 10 }, { 6, 11 }, { 7, 12 }, { 8, 11 }, { 9, 9 },
  { 10, 8 }, { 11, 6 }, { 12, 5 }, { 13, 4 }, { 14, 3 }, { 15, 2 }, { 16, 1 }, { 18, 1 }, { 20, 1 },
}
local TEST_HOUR_W = {}  -- evening-leaning hour-of-day curve
do
  local w = { [0] = 2, [1] = 1, [2] = 1, [3] = 1, [4] = 1, [5] = 1, [6] = 2, [7] = 3,
              [8] = 4, [9] = 5, [10] = 6, [11] = 6, [12] = 7, [13] = 6, [14] = 5, [15] = 5,
              [16] = 6, [17] = 8, [18] = 11, [19] = 13, [20] = 14, [21] = 12, [22] = 9, [23] = 5 }
  for h = 0, 23 do TEST_HOUR_W[#TEST_HOUR_W + 1] = { h, w[h] } end
end
-- Item pool: the first 8 are "hot" (recur often), the rest a long tail. Name is keyed off the id.
local TEST_ITEM_NAMES = {
  "Sunwell Cinder", "Thalassian Warblade", "Ley-Woven Cloak", "Void-Touched Shard",
  "Everlight Crystal", "Duskweave Bracers", "Arcane Reservoir", "Bloodgem Signet",
  "Runeblade of Quel'Thalas", "Felflame Ember", "Silvermoon Sigil", "Manaforge Core",
  "Nightfall Pendant", "Amani Warspear", "Sunstrider Medallion", "Auric Bar",
  "Ravaged Sunhawk Plume", "Eversong Petal", "Twilight Opal", "Dawnthread Bolt",
  "Spellfire Cindersilk", "Harandar Relic", "Quel'dorei Warglaive", "Mana-Etched Band",
  "Sanctified Reliquary", "Shadowflame Tome", "Emberglow Sapphire", "Wretched Fel Dust",
  "Highborne Codex", "Sindorei Banner",
}
local TEST_DAY = 86400
local TEST_SPAN_DAYS = 20   -- drops are spread over roughly the last 20 days
local TEST_HOT_ITEMS = 8

-- Minimal-standard (Park–Miller) LCG: products stay < 2^46, so the double arithmetic is exact and
-- the sequence is identical on every platform. rng(n) returns an integer in [1, n].
local function testRng(seed)
  local state = seed % 2147483647
  if state <= 0 then state = state + 2147483646 end
  return function(n)
    state = (state * 16807) % 2147483647
    return (state % n) + 1
  end
end
-- Weighted pick from a { {value, weight}, ... } table.
local function testPick(rng, weighted)
  local total = 0
  for _, e in ipairs(weighted) do total = total + e[2] end
  local roll, acc = rng(total), 0
  for _, e in ipairs(weighted) do
    acc = acc + e[2]
    if roll <= acc then return e[1] end
  end
  return weighted[#weighted][1]
end

-- The per-field derivations behind one synthetic record. Each takes the PRNG explicitly (no
-- upvalue capture) and every one of them draws a FIXED number of values in a fixed order — the
-- generated dataset is only byte-identical run to run because the call order into `rng` never
-- moves, so these must be called from `make` in exactly the sequence written there.

-- Skewed item pool: ~45% of drops land on one of the hot items, the rest on the long tail.
local function testItemID(rng)
  return (rng(100) <= 45) and rng(TEST_HOT_ITEMS)
         or (TEST_HOT_ITEMS + rng(#TEST_ITEM_NAMES - TEST_HOT_ITEMS))
end

-- Seconds back from now: weighted day (a third of drops cluster onto the last few days) plus an
-- evening-leaning hour-of-day.
local function testAge(rng)
  local dayOffset = rng(TEST_SPAN_DAYS) - 1
  if rng(3) == 1 then dayOffset = rng(5) - 1 end
  local secInto = testPick(rng, TEST_HOUR_W) * 3600 + (rng(60) - 1) * 60 + (rng(60) - 1)
  return dayOffset * TEST_DAY + secInto
end

-- Gear drops one at a time; junk stacks, and the cheapest junk stacks highest.
local function testQuantity(rng, q, isGear)
  if isGear then return 1 end
  return (q <= 1) and (1 + rng(19)) or (1 + rng(4))
end

local function testVendorPrice(rng, q)
  return (q * q + 1) * (200 + rng(1800)) + rng(500) -- wide, quality-skewed value spread
end

-- ~70% of drops carry an AH price map; the other 30% draw nothing at all.
local function testAuctionPrice(rng, q)
  return (rng(100) <= 70) and {
    tsm = { dbmarket = (q * q + 1) * (600 + rng(6000)) + rng(1500),
            dbminbuyout = (q * q + 1) * (400 + rng(5000)) },
    oribos = { market = (q * q + 1) * (500 + rng(6000)) },
  } or nil
end

-- Subtype is a deterministic function of the item id, so a given item always looks the same.
local function testSubType(ty, idBase)
  local list = TEST_SUBTYPES[ty] or TEST_SUBTYPES_MISC
  return list[(idBase % #list) + 1]
end

-- The sample's universe, shared with test mode's ledger half (modules/TestData.lua), so the Holdings
-- and Timeline samples hold the same items, under the same names, as the History sample's rows.
BrowserTable.TestSample = { itemNames = TEST_ITEM_NAMES, rng = testRng, subType = testSubType, idBase = 100000 }

-- The other end of a sample holder-move row: the Warband for a warband move, else the sample class
-- after the row's own (wrapping), as that character's Name-Realm and its class.
local function moveOtherEnd(r)
  if r.source == "WARBAND_DEPOSIT" or r.source == "WARBAND_WITHDRAW" then
    return C.WARBAND_HOLDER, nil
  end
  local k = 1
  while TEST_CLASSES[k] and TEST_CLASSES[k] ~= r.classFile do k = k + 1 end
  local otherClass = TEST_CLASSES[(k % #TEST_CLASSES) + 1]
  return otherClass:sub(1, 1) .. otherClass:sub(2):lower() .. "-Ravencrest", otherClass
end

-- The container a move lands in on its receiver: the Warband's tabs, an alt's mail for ALT_MAIL,
-- else the receiver's bags.
local function moveInto(r, toH)
  local CT = C.Container
  if toH == C.WARBAND_HOLDER then return CT.TABS end
  if r.source == "ALT_MAIL" then return CT.MAIL end
  return CT.BAGS
end

-- Turn sample row `r` (an OUT on its character) into the n-th holder-move pair: `r` becomes the
-- sender's OUT and the returned copy the receiver's IN, under one pairId.
local function pairHolderMove(r, n)
  local W, CT = C.WARBAND_HOLDER, C.Container
  local other, otherClass = moveOtherEnd(r)
  local fromH, toH = r.char, other
  if r.source == "WARBAND_WITHDRAW" then fromH, toH = W, r.char end
  local gain = NS.Util.DeepCopy(r)
  r.holder, gain.holder, gain.dir = fromH, toH, "IN"
  if toH == other and otherClass then gain.char, gain.classFile = other, otherClass end
  r.from, r.to = fromH .. "/" .. ((fromH == W) and CT.TABS or CT.BAGS), toH .. "/" .. moveInto(r, toH)
  gain.from, gain.to = r.from, r.to
  r.pairId = r.ts .. ":" .. n
  gain.pairId = r.pairId
  return gain
end

-- Timeline ledger Phase 7: a move between two holders is an OUT on the sender and an IN on the
-- receiver under the same reason and pairId, never a MOVE pair. Each holder-move row the seed walk
-- wrote (an OUT on its character) is turned into that pair: the Warband is the other end of a
-- warband move (the sender of a withdraw), the next sample class the other end of an alt move.
-- Draws nothing from the PRNG, so the rows before it are the ones the walk always made.
local function holderMoves(out)
  local n = 0
  for i = 1, #out do
    local r = out[i]
    if NS.Ledger.HOLDER_MOVE_REASON[r.source] then
      n = n + 1
      out[#out + 1] = pairHolderMove(r, n)
    end
  end
end

function BrowserTable:BuildTestData()
  local now = time()
  local rng = testRng(0x10A75AFE)   -- fixed seed → identical dataset every run
  local out = {}

  -- Build one record from the pivot values; everything else is derived and jittered. The locals
  -- below are drawn in the order the record constructor used to evaluate them — do not reorder.
  local function make(source, q, cls, bindIdx)
    local b      = TEST_BINDINGS[bindIdx]
    local zone   = TEST_ZONES[testPick(rng, TEST_ZONE_W)]
    local ty     = testPick(rng, TEST_TYPE_W)
    local isGear = (ty == "Armor" or ty == "Weapon")
    local idBase = testItemID(rng)
    local age    = testAge(rng)
    local qty    = testQuantity(rng, q, isGear)
    -- gear only; scales with quality. The short-circuit is load-bearing: non-gear must draw nothing.
    local ilvl    = isGear and (560 + q * 12 + rng(40)) or nil
    local vendor  = testVendorPrice(rng, q)
    local auction = testAuctionPrice(rng, q)
    local subType = testSubType(ty, idBase)
    local detail  = (source == "MPLUS") and { keystoneLevel = testPick(rng, TEST_KEY_W) } or nil
    local conf    = (rng(100) <= 14) and "INFERRED" or "CERTAIN"
    out[#out + 1] = {
      ts = now - age,
      char = cls:sub(1, 1) .. cls:sub(2):lower() .. "-Ravencrest",
      classFile = cls,
      itemID = 100000 + idBase,
      itemName = TEST_ITEM_NAMES[idBase],
      quality = q,
      quantity = qty,
      itemLevel = ilvl,
      bound = b.key,
      vendorPrice = vendor,
      auctionPrice = auction,
      itemType = ty,
      itemSubType = subType,
      source = source,
      sourceDetail = detail,
      zone = zone.name,
      mapID = zone.mapID,
      confidence = conf,
    }
    -- A ledger reason in the seed walk is a loss (TRANSFER a transfer within one character), so the
    -- preview shows the Direction column and the gains-vs-losses charts with real shapes. A holder
    -- move's receiving half is added by holderMoves below, once the walk is done.
    if C.LEDGER_REASON[source] then
      local rec = out[#out]
      rec.dir = (source == "TRANSFER") and "MOVE" or "OUT"
      rec.kind, rec.holder = "ITEM", rec.char
      if source == "TRANSFER" then
        rec.from, rec.to = rec.char .. "/" .. C.Container.BAGS, rec.char .. "/" .. C.Container.BANK
      end
    end
  end

  -- 1) Coverage seed: guarantee every source/quality/class/binding appears at least once and that
  --    the timestamps reach both ends of the window (the tests assert full coverage + >14d span).
  local seedN = math.max(#C.SourceOrder, #TEST_CLASSES, #TEST_BINDINGS, 6, TEST_SPAN_DAYS)
  for i = 1, seedN do
    make(C.SourceOrder[((i - 1) % #C.SourceOrder) + 1], (i - 1) % 6,
         TEST_CLASSES[((i - 1) % #TEST_CLASSES) + 1], ((i - 1) % #TEST_BINDINGS) + 1)
    out[#out].ts = now - ((i - 1) % TEST_SPAN_DAYS) * TEST_DAY - rng(80000) -- walk the full span
  end

  -- 2) Weighted bulk: the mass of the dataset, fully weighted-random so every pivot comes out uneven.
  for _ = 1, 260 do
    make(testPick(rng, TEST_SOURCE_W), testPick(rng, TEST_QUALITY_W),
         testPick(rng, TEST_CLASS_W), rng(#TEST_BINDINGS))
  end

  holderMoves(out)
  return out
end
