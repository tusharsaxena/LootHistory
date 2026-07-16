local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- itemString field layout: itemID(1) : 11 fields : numBonusIDs(13) : bonusID1..N.
-- Fixtures below keep exactly 11 fields between itemID and the bonus count.

test("Export: BoundLabel maps tokens and nil", function()
  assertEqual(NS.Export:BoundLabel(nil), "Not Bound")
  assertEqual(NS.Export:BoundLabel("NONE"), "Not Bound")
  assertEqual(NS.Export:BoundLabel("BOE"), "Bind on Equip")
  assertEqual(NS.Export:BoundLabel("WARBAND"), "Warbound")
end)

test("Export: WowheadLink with bonus IDs", function()
  local link = "|cffa335ee|Hitem:210501:0:0:0:0:0:0:0:0:0:0:0:3:6652:1498:11144:::|h[X]|h|r"
  assertEqual(NS.Export:WowheadLink({ itemLink = link }),
    "https://www.wowhead.com/item=210501?bonus=6652:1498:11144")
end)

test("Export: WowheadLink without bonuses is bare", function()
  local link = "|cff9d9d9d|Hitem:6948:0:0:0:0:0:0:0:0:0:0:0:0:::|h[Hearthstone]|h|r"
  assertEqual(NS.Export:WowheadLink({ itemLink = link }), "https://www.wowhead.com/item=6948")
end)

test("Export: WowheadLink falls back to itemID, then empty", function()
  assertEqual(NS.Export:WowheadLink({ itemID = 12345 }), "https://www.wowhead.com/item=12345")
  assertEqual(NS.Export:WowheadLink({}), "")
end)

test("Export: CSV header order — ts,date,time first; renamed raw + human siblings; link last", function()
  local csv = NS.Export:CSV({})
  local header = csv:match("^(.-)\r\n")
  assertEqual(header,
    "ts,date,time,char,classFile,itemID,itemName,quality,qualityRaw,itemLevel,bound," ..
    "sellPrice,sellPriceRaw,itemType,itemSubType,quantity,source,zone,wowheadLink")
end)

test("Export: CSV omits itemLink, sourceDetail, mapID, subzone, confidence", function()
  local header = NS.Export:CSV({}):match("^(.-)\r\n")
  for _, col in ipairs({ "itemLink", "sourceDetail", "mapID", "subzone", "confidence" }) do
    assertTrue(header:find(col, 1, true) == nil, col .. " must not be a column")
  end
end)

test("Export: CSV row emits friendly bound + quotes commas", function()
  local rec = { ts = 1000, itemName = "Sword, Big", bound = "BOP", itemID = 7 }
  local csv = NS.Export:CSV({ rec })
  assertTrue(csv:find('"Sword, Big"', 1, true) ~= nil, "quotes the comma field")
  assertTrue(csv:find("Bind on Pickup", 1, true) ~= nil, "friendly bound label")
end)

test("Export: CSV date + time columns are FormatDate/FormatClock(ts)", function()
  local csv = NS.Export:CSV({ { ts = 1000, itemID = 1 } })
  assertTrue(csv:find(NS.Util.FormatDate(1000), 1, true) ~= nil, "date column present")
  assertTrue(csv:find(NS.Util.FormatClock(1000), 1, true) ~= nil, "time column present")
end)

test("Export: CSV quality is human label beside numeric qualityRaw", function()
  local row = NS.Export:CSV({ { ts = 1, quality = 4, itemID = 1 } }):match("\r\n(.-)\r\n")
  assertTrue(row:find(NS.Compat.QualityLabel(4), 1, true) ~= nil, "human quality label present")
  assertTrue(row:find(",4,", 1, true) ~= nil, "numeric qualityRaw present")
end)

test("Export: CSV sellPrice is 'Ng Ns Nc' beside raw copper", function()
  -- 12g 34s 56c = 123456 copper.
  local row = NS.Export:CSV({ { ts = 1, sellPrice = 123456, itemID = 1 } }):match("\r\n(.-)\r\n")
  assertTrue(row:find("12g 34s 56c", 1, true) ~= nil, "formatted money present")
  assertTrue(row:find(",123456,", 1, true) ~= nil, "raw copper present")
end)

test("Export: CSV emits one header + one row per record, CRLF-terminated", function()
  local csv = NS.Export:CSV({ { ts = 1, itemID = 1 }, { ts = 2, itemID = 2 } })
  local n = select(2, csv:gsub("\r\n", "\r\n"))
  assertEqual(n, 3)  -- header + 2 rows, each CRLF-terminated
end)

-- ── Insights CSV (issue #15) ─────────────────────────────────────────────────────
-- Build a Stats result off a tiny known history so the analytics-CSV assertions are deterministic.
local function insightsStats()
  NS.db.global.blacklist = {}
  NS.db.global.history = {
    { ts = 1000, char = "A-Realm", itemID = 1, itemName = "Red, Potion",
      quality = 4, source = "KILL",      mapID = 10, zone = "Zone A", sellPrice = 500, quantity = 1 },
    { ts = 2000, char = "A-Realm", itemID = 2, itemName = "Blue Cloak",
      quality = 2, source = "KILL",      mapID = 10, zone = "Zone A", sellPrice = 100, quantity = 2 },
    { ts = 3000, char = "B-Realm", itemID = 3, itemName = "Green Ring",
      quality = 3, source = "CONTAINER", mapID = 20, zone = "Zone B", sellPrice = 50,  quantity = 1 },
  }
  return NS.Database:Stats({})
end

test("Export: InsightsCSV header is Section,Label,Count,Value; CRLF-terminated", function()
  local csv = NS.Export:InsightsCSV(insightsStats())
  assertEqual(csv:match("^(.-)\r\n"), "Section,Label,Count,Value")
  assertTrue(csv:sub(-2) == "\r\n", "CRLF-terminated")
end)

test("Export: InsightsCSV summary reports the record count", function()
  local csv = NS.Export:InsightsCSV(insightsStats())
  assertTrue(csv:find("Summary,Records,3,", 1, true) ~= nil, "records row present")
end)

test("Export: InsightsCSV By Source uses labels + carries the value column", function()
  local csv = NS.Export:InsightsCSV(insightsStats())
  -- Kill has 2 records; value = 500*1 + 100*2 = 700 copper → "0g 7s 0c" (Export money format).
  assertTrue(csv:find("By Source,Kill,2,0g 7s 0c", 1, true) ~= nil, "source label + count + value")
  assertTrue(csv:find("By Source,Container,1,", 1, true) ~= nil, "second source present")
end)

test("Export: InsightsCSV quotes a label containing a comma", function()
  local csv = NS.Export:InsightsCSV(insightsStats())
  assertTrue(csv:find('"Red, Potion"', 1, true) ~= nil, "comma-bearing item name quoted")
end)

test("Export: InsightsCSV omits blacklisted items (via Stats/ActiveHistory)", function()
  NS.db.global.blacklist = {}
  NS.db.global.history = {
    { ts = 1, char = "A-Realm", itemID = 1, itemName = "Kept",   quality = 3, source = "KILL", quantity = 1 },
    { ts = 2, char = "A-Realm", itemID = 2, itemName = "Hidden", quality = 3, source = "KILL", quantity = 1 },
  }
  NS.db.global.blacklist = { [2] = true }
  local csv = NS.Export:InsightsCSV(NS.Database:Stats({}))
  assertTrue(csv:find("Summary,Records,1,", 1, true) ~= nil, "blacklisted record excluded")
  NS.db.global.blacklist = {}
end)
