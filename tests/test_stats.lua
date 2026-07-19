local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue =
  T.test, T.assertEqual, T.assertTrue

local T1 = 1600000000
local T2 = T1 + 3 * 86400   -- three days later → distinct day bucket

local function seedStats()
  NS.db.global.history = {
    { ts = T1, char = "A-Realm", itemID = 10, itemName = "Sword",
      quality = 4, source = "KILL",      zone = "Valley" },
    { ts = T1, char = "A-Realm", itemID = 10, itemName = "Sword",
      quality = 4, source = "KILL",      zone = "Valley" },
    { ts = T2, char = "B-Realm", itemID = 20, itemName = "Cloak",
      quality = 2, source = "CONTAINER", zone = "Cavern" },
    { ts = T2, char = "B-Realm", itemID = 30, itemName = "Ring",
      quality = 3, source = "KILL",      zone = "Valley" },
  }
end

test("Stats: bySource / byQuality counts", function()
  seedStats()
  local s = NS.Database:Stats({})
  assertEqual(s.bySource.KILL, 3)
  assertEqual(s.bySource.CONTAINER, 1)
  assertEqual(s.byQuality[4], 2)
  assertEqual(s.byQuality[3], 1)
  assertEqual(s.byQuality[2], 1)
end)

test("Stats: byDay buckets via date()", function()
  seedStats()
  local s = NS.Database:Stats({})
  assertEqual(s.byDay[os.date("%Y-%m-%d", T1)], 2)
  assertEqual(s.byDay[os.date("%Y-%m-%d", T2)], 2)
end)

test("Stats: byZone counts", function()
  seedStats()
  local s = NS.Database:Stats({})
  assertEqual(s.byZone.Valley, 3)
  assertEqual(s.byZone.Cavern, 1)
end)

test("Stats: byItem aggregates by itemID with name/quality", function()
  seedStats()
  local s = NS.Database:Stats({})
  assertEqual(s.byItem[10].count, 2)
  assertEqual(s.byItem[10].itemName, "Sword")
  assertEqual(s.byItem[10].quality, 4)
  assertEqual(s.byItem[20].count, 1)
end)

test("Stats: totals (records/distinct/first/last)", function()
  seedStats()
  local s = NS.Database:Stats({})
  assertEqual(s.totals.records, 4)
  assertEqual(s.totals.distinctItems, 3)
  assertEqual(s.totals.distinctChars, 2)
  assertEqual(s.totals.firstTs, T1)
  assertEqual(s.totals.lastTs, T2)
end)

test("Stats: topZones / topItems ordered by count desc", function()
  seedStats()
  local s = NS.Database:Stats({})
  assertEqual(s.topZones[1].zone, "Valley")
  assertEqual(s.topZones[1].count, 3)
  assertEqual(s.topItems[1].itemID, 10) -- count 2 wins
  assertEqual(s.topItems[2].itemID, 30) -- tie on count 1 → higher quality (q3) first
  assertEqual(s.topItems[3].itemID, 20)
end)

test("Stats: respects the filter", function()
  seedStats()
  local s = NS.Database:Stats({ source = "KILL" })
  assertEqual(s.totals.records, 3)
  assertEqual(s.bySource.KILL, 3)
  assertEqual(s.bySource.CONTAINER, nil)
  assertEqual(s.totals.distinctItems, 2) -- items 10 and 30
end)

test("Stats: empty dataset yields zeroed totals", function()
  NS.db.global.history = {}
  local s = NS.Database:Stats({})
  assertEqual(s.totals.records, 0)
  assertEqual(s.totals.distinctItems, 0)
  assertEqual(s.totals.firstTs, nil)
  assertEqual(#s.topItems, 0)
  assertEqual(#s.topZones, 0)
  assertEqual(s.totals.totalValue, 0)
  assertEqual(s.totals.epicPlus, 0)
  assertEqual(s.totals.bestDrop, nil)
  assertEqual(#s.topItemsByValue, 0)
end)

-- Richer seed exercising the value + breakdown fields.
local function seedValueStats()
  NS.db.global.history = {
    { ts = T1, char = "A-Realm", classFile = "MAGE", itemID = 10, itemName = "Sword",
      quality = 4, itemLevel = 200, bound = "BOP", vendorPrice = 100, quantity = 1,
      itemType = "Weapon", source = "KILL", zone = "Valley", confidence = "CERTAIN",
      sourceDetail = { keystoneLevel = 10 } },
    { ts = T1, char = "A-Realm", classFile = "MAGE", itemID = 20, itemName = "Herb",
      quality = 1, vendorPrice = 5, quantity = 20, itemType = "Tradegoods",
      source = "CONTAINER", zone = "Valley", confidence = "INFERRED" },
    { ts = T2, char = "B-Realm", classFile = "ROGUE", itemID = 30, itemName = "Ring",
      quality = 3, itemLevel = 180, bound = "BOE", vendorPrice = 50, quantity = 1,
      itemType = "Armor", source = "KILL", zone = "Cavern", confidence = "CERTAIN" },
  }
end

test("Stats: vendor value (vendorPrice × quantity) totals + by source/zone", function()
  seedValueStats()
  local s = NS.Database:Stats({})
  assertEqual(s.totals.totalValue, 250)      -- 100 + 5*20 + 50
  assertEqual(s.totals.totalQuantity, 22)    -- 1 + 20 + 1
  assertEqual(s.valueBySource.KILL, 150)     -- 100 + 50
  assertEqual(s.valueBySource.CONTAINER, 100)
  assertEqual(s.valueByZone.Valley, 200)
  assertEqual(s.byItem[10].value, 100)
end)

test("Stats: byType / byBound / byChar / byConfidence / byKeystone", function()
  seedValueStats()
  local s = NS.Database:Stats({})
  assertEqual(s.byType.Weapon, 1)
  assertEqual(s.byType.Tradegoods, 1)
  assertEqual(s.byBound.BOP, 1)
  assertEqual(s.byBound.UNBOUND, 1)          -- the herb carries no bound
  assertEqual(s.byChar["A-Realm"].count, 2)
  assertEqual(s.byChar["A-Realm"].value, 200)
  assertEqual(s.byChar["A-Realm"].classFile, "MAGE")
  assertEqual(s.byConfidence.CERTAIN, 2)
  assertEqual(s.byConfidence.INFERRED, 1)
  assertEqual(s.byKeystone[10], 1)
end)

test("Stats: hour/weekday buckets sum to record count (TZ-independent)", function()
  seedValueStats()
  local s = NS.Database:Stats({})
  local hSum, wSum = 0, 0
  for _, c in pairs(s.byHour) do hSum = hSum + c end
  for _, c in pairs(s.byWeekday) do wSum = wSum + c end
  assertEqual(hSum, 3)
  assertEqual(wSum, 3)
end)

test("Stats: highlights + topItemsByValue", function()
  seedValueStats()
  local s = NS.Database:Stats({})
  assertEqual(s.totals.epicPlus, 1)                 -- only the q4 Sword
  assertEqual(s.totals.bestDrop.itemName, "Sword")  -- ilvl 200 > 180
  assertEqual(s.totals.richestDrop.value, 100)      -- Sword & Herb tie at 100; first wins
  assertEqual(s.totals.busiestDay.count, 2)
  assertEqual(s.totals.activeDays, 2)
  -- value order: Sword(100) & Herb(100) tie → lower itemID first; Ring(50) last.
  assertEqual(s.topItemsByValue[1].itemID, 10)
  assertEqual(s.topItemsByValue[3].itemID, 30)
end)

test("Analytics.SummaryLine formats range and count", function()
  assertEqual(NS.Analytics.SummaryLine("30d", 1423), "computed range=30d, 1423 records")
end)

test("Stats: value uses auctionPrice when present, else vendorPrice", function()
  local recs = {
    { ts = 1, quality = 3, quantity = 2, vendorPrice = 10, auctionPrice = { tsm = { dbmarket = 100 } }, source = "KILL", itemID = 1, char = "A-R" },
    { ts = 2, quality = 3, quantity = 1, vendorPrice = 50,                                            source = "KILL", itemID = 2, char = "A-R" },
  }
  NS.State.testRecords = recs
  local s = NS.Database:Stats()
  NS.State.testRecords = nil
  -- 100*2 (auction) + 50*1 (vendor fallback) = 250
  assertEqual(s.totals.totalValue, 250)
  assertEqual(s.valueBySource.KILL, 250)
  assertEqual(s.totals.richestDrop.value, 200)   -- the auction-priced stack
end)
