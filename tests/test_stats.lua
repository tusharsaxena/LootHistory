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
end)
