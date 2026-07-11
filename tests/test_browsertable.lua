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
