local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local EMDASH = "\226\128\148"

test("BrowserTable: CellText renders each column", function()
  local r = { ts = 1000, itemName = "Sword", quantity = 3, quality = 4,
              source = "KILL", sourceName = "Ovi'nax", zone = "Valley", char = "Ka0z-Realm" }
  assertEqual(NS.BrowserTable:CellText("item", r), "Sword")
  assertEqual(NS.BrowserTable:CellText("qty", r), "3")
  assertEqual(NS.BrowserTable:CellText("quality", r), "Epic")
  assertEqual(NS.BrowserTable:CellText("source", r), "Kill")
  assertEqual(NS.BrowserTable:CellText("from", r), "Ovi'nax")
  assertEqual(NS.BrowserTable:CellText("zone", r), "Valley")
  assertEqual(NS.BrowserTable:CellText("char", r), "Ka0z") -- realm stripped for display
  assertEqual(NS.BrowserTable:CellText("time", r), os.date("%H:%M", r.ts))
  assertEqual(NS.BrowserTable:CellText("date", r), os.date("%m/%d/%y", r.ts))
end)

test("BrowserTable: iLvl column shows level only when present", function()
  assertEqual(NS.BrowserTable:CellText("ilvl", { itemLevel = 489 }), "489")
  assertEqual(NS.BrowserTable:CellText("ilvl", {}), "")
end)

test("BrowserTable: Bound column renders no text (icon-driven)", function()
  assertEqual(NS.BrowserTable:CellText("bound", { bound = "BOP" }), "")
end)

test("BrowserTable: bound legend adds a line per state", function()
  local lines = {}
  local fakeTip = { AddLine = function(_, text) lines[#lines + 1] = text end }
  NS.BrowserTable:AddBoundLegend(fakeTip)
  assertEqual(#lines, 5)
  assertTrue(lines[1]:find("Not Bound", 1, true) ~= nil)
  assertTrue(lines[5]:find("Warbound", 1, true) ~= nil)
end)

test("BrowserTable: test data covers every bound state", function()
  local data = NS.BrowserTable:BuildTestData()
  assertTrue(#data >= 10)
  local seen = {}
  for _, r in ipairs(data) do seen[r.bound or "UNBOUND"] = true end
  for _, key in ipairs({ "UNBOUND", "BOE", "BOP", "ACCOUNT", "WARBAND" }) do
    assertTrue(seen[key], "test data missing bound state " .. key)
  end
end)

test("BrowserTable: From column falls back to em-dash", function()
  assertEqual(NS.BrowserTable:CellText("from", { source = "OTHER" }), EMDASH)
end)

test("BrowserTable: Item column falls back to link name then '?'", function()
  local r = { itemLink = "|cff1eff00|Hitem:1::::|h[Linen Cloth]|h|r" }
  assertEqual(NS.BrowserTable:CellText("item", r), "Linen Cloth")
  assertEqual(NS.BrowserTable:CellText("item", {}), "?")
end)

test("BrowserTable: BuildDisplayList yields one row entry per filtered record", function()
  T.seedDatabase() -- 4 records
  NS.BrowserTable.filter = {}
  local list = NS.BrowserTable:BuildDisplayList()
  assertEqual(#list, 4)
  assertEqual(list[1].kind, "row")
  assertTrue(list[1].record ~= nil)

  NS.BrowserTable.filter = { source = "KILL" }
  assertEqual(#NS.BrowserTable:BuildDisplayList(), 2)
end)

test("BrowserTable: SortRecords orders by active column, stable on ties", function()
  local BT = NS.BrowserTable
  local recs = {
    { ts = 100, quality = 2, itemName = "b" },
    { ts = 200, quality = 4, itemName = "a" },
    { ts = 300, quality = 2, itemName = "c" },
  }
  BT.sortKey, BT.sortAsc = "quality", true
  local asc = BT:SortRecords(recs)
  assertEqual(asc[1].quality, 2)
  assertEqual(asc[2].quality, 2)
  assertEqual(asc[3].quality, 4)
  -- stable: the two quality-2 rows keep input order (ts 100 before ts 300)
  assertEqual(asc[1].ts, 100)
  assertEqual(asc[2].ts, 300)

  BT.sortAsc = false
  local desc = BT:SortRecords(recs)
  assertEqual(desc[1].quality, 4)
  assertEqual(desc[3].quality, 2)

  -- lexical sort on a text column
  BT.sortKey, BT.sortAsc = "item", true
  local byName = BT:SortRecords(recs)
  assertEqual(byName[1].itemName, "a")
  assertEqual(byName[3].itemName, "c")
end)

test("BrowserTable: SetSort toggles direction on same column, resets on new", function()
  local BT = NS.BrowserTable
  BT.sortKey, BT.sortAsc = "date", false  -- known starting state
  BT:SetSort("item")          -- text column → ascending on first click
  assertEqual(BT.sortKey, "item")
  assertTrue(BT.sortAsc)
  BT:SetSort("item")          -- re-click toggles
  assertTrue(not BT.sortAsc)
  BT:SetSort("qty")           -- numeric column → descending on first click
  assertEqual(BT.sortKey, "qty")
  assertTrue(not BT.sortAsc)
  -- restore default sort for subsequent tests
  BT.sortKey, BT.sortAsc = "date", false
end)
