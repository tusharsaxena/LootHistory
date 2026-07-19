local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue


test("BrowserTable: CellText renders each column", function()
  local r = { ts = 1000, itemName = "Sword", quantity = 3, quality = 4,
              source = "KILL", zone = "Valley", char = "Ka0z-Realm" }
  assertEqual(NS.BrowserTable:CellText("item", r), "Sword")
  assertEqual(NS.BrowserTable:CellText("qty", r), "3")
  assertEqual(NS.BrowserTable:CellText("quality", r), "Epic")
  assertEqual(NS.BrowserTable:CellText("source", r), "Kill")
  assertEqual(NS.BrowserTable:CellText("zone", r), "Valley")
  assertEqual(NS.BrowserTable:CellText("char", r), "Ka0z-Realm") -- full Name-Realm shown
  assertEqual(NS.BrowserTable:CellText("time", r), os.date("%H:%M", r.ts))
  assertEqual(NS.BrowserTable:CellText("date", r), os.date("%d-%b-%Y", r.ts))
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

test("BrowserTable: test data covers every bound state, source, quality, class", function()
  local data = NS.BrowserTable:BuildTestData()
  assertTrue(#data >= 100, "expected at least 100 test records, got " .. #data)

  local bound, source, quality, class = {}, {}, {}, {}
  local minTs, maxTs
  for _, r in ipairs(data) do
    bound[r.bound or "UNBOUND"] = true
    source[r.source] = true
    quality[r.quality] = true
    class[r.classFile] = true
    if not minTs or r.ts < minTs then minTs = r.ts end
    if not maxTs or r.ts > maxTs then maxTs = r.ts end
  end

  for _, key in ipairs({ "UNBOUND", "BOE", "BOP", "ACCOUNT", "WARBAND" }) do
    assertTrue(bound[key], "test data missing bound state " .. key)
  end
  -- Every SourceType is represented (incl. the deconstruct/AH/ROLL/CRAFT sources).
  for _, s in ipairs(NS.Constants.SourceOrder) do
    assertTrue(source[s], "test data missing source " .. s)
  end
  -- Full quality spread Poor(0)..Legendary(5).
  for q = 0, 5 do
    assertTrue(quality[q], "test data missing quality " .. q)
  end
  -- A range of classes so class coloring / per-character breakdowns have variety.
  local classCount = 0
  for _ in pairs(class) do classCount = classCount + 1 end
  assertTrue(classCount >= 10, "expected >=10 distinct classes, got " .. classCount)
  -- Spans at least 14 days for the range selector / time charts.
  assertTrue((maxTs - minTs) >= 14 * 86400, "test data should span >= 14 days")
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

test("BrowserTable: GroupRecords partitions into headers + rows with counts", function()
  local BT = NS.BrowserTable
  local recs = {
    { ts = 300, source = "KILL", zone = "A" },
    { ts = 200, source = "KILL", zone = "B" },
    { ts = 100, source = "VENDOR", zone = "A" },
  }
  BT.groupBy, BT.collapsed, BT.groupAsc = "source", {}, true
  local list = BT:GroupRecords(recs)
  -- header(Kill), row, row, header(Vendor), row  = 5 entries; groups sorted alphabetically
  assertEqual(#list, 5)
  assertEqual(list[1].kind, "header")
  assertEqual(list[1].label, "Source: Kill")  -- header is "<Column>: <Value>"
  assertEqual(list[1].count, 2)
  assertEqual(list[2].kind, "row")
  assertEqual(list[4].kind, "header")
  assertEqual(list[4].label, "Source: Vendor")
  assertEqual(list[4].count, 1)
end)

test("BrowserTable: group order toggles asc/desc, sorted by the grouped column", function()
  local BT = NS.BrowserTable
  local recs = {
    { source = "VENDOR" }, { source = "KILL" }, { source = "CONTAINER" },
  }
  BT.groupBy, BT.collapsed = "source", {}

  BT.groupAsc = true
  local asc = BT:GroupRecords(recs)
  assertEqual(asc[1].label, "Source: Container") -- Container < Kill < Vendor
  assertEqual(asc[3].label, "Source: Kill")
  assertEqual(asc[5].label, "Source: Vendor")

  BT.groupAsc = false
  local desc = BT:GroupRecords(recs)
  assertEqual(desc[1].label, "Source: Vendor")
  assertEqual(desc[5].label, "Source: Container")

  -- Quality groups sort numerically (Poor→Epic), not alphabetically by label.
  BT.groupBy, BT.groupAsc = "quality", true
  local q = BT:GroupRecords({ { quality = 4 }, { quality = 0 }, { quality = 2 } })
  assertEqual(q[1].label, "Quality: Poor")
  assertEqual(q[3].label, "Quality: Uncommon")
  assertEqual(q[5].label, "Quality: Epic")

  BT.groupBy, BT.groupAsc = "none", true -- restore
end)

test("BrowserTable: collapsed group emits only its header", function()
  local BT = NS.BrowserTable
  local recs = {
    { ts = 300, source = "KILL" },
    { ts = 200, source = "KILL" },
  }
  BT.groupBy = "source"
  local key = BT:GroupRecords(recs)[1].key
  BT.collapsed = { [key] = true }
  local list = BT:GroupRecords(recs)
  assertEqual(#list, 1)                 -- header only, rows hidden
  assertEqual(list[1].collapsed, true)
end)

test("BrowserTable: groupBy none yields a flat row list", function()
  local BT = NS.BrowserTable
  BT.groupBy, BT.collapsed = "none", {}
  local list = BT:GroupRecords({ { ts = 1 }, { ts = 2 } })
  assertEqual(#list, 2)
  assertEqual(list[1].kind, "row")
end)

test("BrowserTable: test mode filters the synthetic dataset", function()
  local BT = NS.BrowserTable
  -- Test mode publishes the synthetic dataset to State; every read-path query resolves to it.
  BT.testMode, NS.State.testRecords = true, BT:BuildTestData()
  BT.groupBy, BT.collapsed, BT.filter = "none", {}, {}
  local all = #BT:BuildDisplayList()
  assertTrue(all > 0)

  BT.filter = { source = "KILL" }
  local killed = BT:BuildDisplayList()
  assertTrue(#killed > 0)
  assertTrue(#killed < all)                 -- the filter actually narrows the test data
  for _, e in ipairs(killed) do assertEqual(e.record.source, "KILL") end
  assertEqual(BT.matchCount, #killed)

  -- Insights reads the same override: Stats aggregates the test dataset, not the live history.
  local stats = NS.Database:Stats({})
  assertEqual(stats.totals.records, all)
  assertTrue(stats.bySource.KILL and stats.bySource.KILL > 0)

  BT.testMode, NS.State.testRecords, BT.filter = false, nil, {} -- restore shared state
end)

test("BrowserTable: OrderedFilteredRecords returns filtered rows in order, no headers", function()
  local BT = NS.BrowserTable
  local savedFilter, savedGroup = BT.filter, BT.groupBy
  NS.db.global.history = {
    { ts = 300, itemID = 3, quality = 4, source = "KILL", char = "A" },
    { ts = 100, itemID = 1, quality = 2, source = "KILL", char = "A" },
    { ts = 200, itemID = 2, quality = 4, source = "KILL", char = "A" },
  }
  BT.groupBy, BT.sortKey, BT.sortAsc = "none", "date", true
  BT:SetFilter({ quality = { [4] = true } })
  local out = BT:OrderedFilteredRecords()
  assertEqual(#out, 2)             -- only the two epics
  assertEqual(out[1].itemID, 2)    -- ts 200 before ts 300 ascending
  assertEqual(out[2].itemID, 3)
  BT.filter, BT.groupBy = savedFilter, savedGroup
end)

test("BrowserTable.RenderSummary is a single coalesced line", function()
  local s = NS.BrowserTable.RenderSummary(84, 1423, 2, "zone", "date", false)
  assertTrue(s:find("84/1423 rows", 1, true) ~= nil, "reports matched/total")
  assertTrue(s:find("group=zone", 1, true) ~= nil, "reports group")
  assertTrue(s:find("sort=date desc", 1, true) ~= nil, "reports sort key + direction")
  assertTrue(s:find("filters=2", 1, true) ~= nil, "reports active filter count")
  assertTrue(s:find("\n") == nil, "one line only, no newline")
end)

test("BrowserTable: auction column shows the picked price from the map", function()
  NS.db.global.settings.auction = { enabled = true, priority = { "tsm:dbmarket" } }
  assertEqual(NS.BrowserTable:CellText("auction", { auctionPrice = { tsm = { dbmarket = 12345 } } }),
    NS.Util.FormatMoney(12345))
  assertEqual(NS.BrowserTable:CellText("auction", {}), "")
  NS.db.global.settings.auction = nil
end)

test("BrowserTable: MinFrameWidth accounts for the AH column (>= 1212)", function()
  assertTrue(NS.BrowserTable:MinFrameWidth() >= 1212,
    "AH column must widen the frame past the old 1160 floor")
end)
