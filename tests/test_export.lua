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

test("Export: CSV header has all fields plus date + wowheadLink", function()
  local csv = NS.Export:CSV({})
  local header = csv:match("^(.-)\r\n")
  assertTrue(header:find("^ts,char,") ~= nil, "starts with ts,char")
  assertTrue(header:find(",subzone,confidence,date,wowheadLink$") ~= nil, "ends with derived cols")
end)

test("Export: CSV row emits friendly bound + quotes commas", function()
  local rec = { ts = 1000, itemName = "Sword, Big", bound = "BOP", itemID = 7 }
  local csv = NS.Export:CSV({ rec })
  assertTrue(csv:find('"Sword, Big"', 1, true) ~= nil, "quotes the comma field")
  assertTrue(csv:find("Bind on Pickup", 1, true) ~= nil, "friendly bound label")
end)

test("Export: CSV date column is FormatDate(ts)", function()
  local rec = { ts = 1000, itemID = 1 }
  local csv = NS.Export:CSV({ rec })
  assertTrue(csv:find(NS.Util.FormatDate(1000), 1, true) ~= nil, "date column present")
end)

test("Export: CSV emits one header + one row per record, CRLF-terminated", function()
  local csv = NS.Export:CSV({ { ts = 1, itemID = 1 }, { ts = 2, itemID = 2 } })
  local n = select(2, csv:gsub("\r\n", "\r\n"))
  assertEqual(n, 3)  -- header + 2 rows, each CRLF-terminated
end)
