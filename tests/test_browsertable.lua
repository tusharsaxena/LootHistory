local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- The UI binds a cell by finding its column and calling valueFn; these cases drive that exact
-- path through the public COLUMNS model.
local function cell(key, record)
  for _, col in ipairs(NS.BrowserTable.COLUMNS) do
    if col.key == key then return col.valueFn(record) end
  end
  error("no such column: " .. tostring(key))
end




test("BrowserTable: CellText renders each column", function()
  local r = { ts = 1000, itemName = "Sword", quantity = 3, quality = 4,
              source = "KILL", zone = "Valley", char = "Ka0z-Realm" }
  assertEqual(cell("item", r), "Sword")
  assertEqual(cell("qty", r), "3")
  assertEqual(cell("quality", r), "Epic")
  assertEqual(cell("source", r), "Kill")
  assertEqual(cell("zone", r), "Valley")
  assertEqual(cell("char", r), "Ka0z-Realm") -- full Name-Realm shown
  assertEqual(cell("time", r), os.date("%H:%M", r.ts))
  assertEqual(cell("date", r), os.date("%d-%b-%Y", r.ts))
end)

test("BrowserTable: iLvl column shows level only when present", function()
  assertEqual(cell("ilvl", { itemLevel = 489 }), "489")
  assertEqual(cell("ilvl", {}), "")
end)

test("BrowserTable: Bound column renders no text (icon-driven)", function()
  assertEqual(cell("bound", { bound = "BOP" }), "")
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

  for _, key in ipairs({ "UNBOUND", "BOE", "BOP", "WARBAND", "WARBAND_UE" }) do
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
  assertEqual(cell("item", r), "Linen Cloth")
  assertEqual(cell("item", {}), "?")
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
  assertEqual(cell("auction", { auctionPrice = { tsm = { dbmarket = 12345 } } }),
    NS.Util.FormatMoney(12345))
  assertEqual(cell("auction", {}), "")
  NS.db.global.settings.auction = nil
end)

test("BrowserTable: MinFrameWidth accounts for the AH column (>= 1212)", function()
  -- R4-6 narrowed Date 76→66 and Time 38→32 (−16px), dropping the column-derived floor to 1196;
  -- widening Vendor Price and Auction Price 72→80 (+16px total) restored it to 1212 — comfortably
  -- past the old 1160 toolbar floor and wide enough for the money columns. B:MinWidth() takes the
  -- wider of this and the toolbar-fit floor (TOOLBAR_MIN 1116), and the static Export button fills
  -- the slack to the bar's right edge: (1212-12) - (976+8) = 216.
  assertEqual(NS.BrowserTable:MinFrameWidth(), 1212)
  assertTrue(NS.BrowserTable:MinFrameWidth() >= 1160,
    "AH column must keep the frame past the old 1160 floor")
  assertEqual(NS.Browser:MinWidth(), 1212)
  assertTrue(NS.Browser:MinWidth() >= 1116, "must be at least the toolbar-fit floor")
  assertEqual(NS.Browser:ExportWidth(), 216)
end)

test("BrowserTable: quality column is blank for a currency row", function()
  local colByKey = {}
  for _, c in ipairs(NS.BrowserTable.COLUMNS) do colByKey[c.key] = c end
  local currencyRow = { currencyID = 3008, itemName = "Valorstones", itemType = "Currency", quantity = 40 }
  local itemRow = { itemID = 111, itemName = "Sword", quality = 4 }
  assertEqual(colByKey.quality.valueFn(currencyRow), "")           -- no misleading "Poor"
  assertEqual(colByKey.quality.valueFn(itemRow), NS.Compat.QualityLabel(4))
  assertEqual(colByKey.type.valueFn(currencyRow), "Currency")      -- Type filter works
end)

-- ── Grouping: keys, labels and edge cases ──────────────────────────────────────

-- The shared table state is global to the addon, so every case below parks and restores it.
local function withTableState(fn)
  local BT = NS.BrowserTable
  local g, c, ga, sk, sa = BT.groupBy, BT.collapsed, BT.groupAsc, BT.sortKey, BT.sortAsc
  local ok, err = pcall(fn)
  BT.groupBy, BT.collapsed, BT.groupAsc = g, c, ga
  BT.sortKey, BT.sortAsc = sk, sa
  if not ok then error(err, 0) end
end

test("BrowserTable: group keys are namespaced, so a zone can share a source's name", function()
  withTableState(function()
    -- A zone literally called "Kill" must not collapse together with the Kill source.
    local BT = NS.BrowserTable
    BT.collapsed, BT.groupAsc = {}, true
    BT.groupBy = "source"
    local srcKey = BT:GroupRecords({ { source = "KILL", zone = "Kill" } })[1].key
    BT.groupBy = "zone"
    local zoneKey = BT:GroupRecords({ { source = "KILL", zone = "Kill" } })[1].key
    assertTrue(srcKey ~= zoneKey, "collapsed state must never collide across group modes")
  end)
end)

test("BrowserTable: a missing zone/character/type groups under 'Unknown'", function()
  withTableState(function()
    local BT = NS.BrowserTable
    BT.collapsed, BT.groupAsc = {}, true
    for mode, prefix in pairs({ zone = "Zone", char = "Character", type = "Type" }) do
      BT.groupBy = mode
      assertEqual(BT:GroupRecords({ { ts = 1 } })[1].label, prefix .. ": Unknown")
    end
  end)
end)

test("BrowserTable: a blank zone string groups under 'Unknown' too, not a nameless group", function()
  withTableState(function()
    -- Compat.GetZone answers "" (not nil) when the client has no zone text yet, so an empty string
    -- must land in the same bucket as a missing one — the Zone filter's Unknown option covers both.
    local BT = NS.BrowserTable
    BT.groupBy, BT.collapsed, BT.groupAsc = "zone", {}, true
    assertEqual(BT:GroupRecords({ { ts = 1, zone = "" } })[1].label, "Zone: Unknown")
  end)
end)

test("BrowserTable: day groups key on the ISO date but read as the Date column", function()
  withTableState(function()
    local BT = NS.BrowserTable
    BT.groupBy, BT.collapsed, BT.groupAsc = "day", {}, true
    local ts = 1700000000
    local header = BT:GroupRecords({ { ts = ts } })[1]
    assertEqual(header.label, "Day: " .. NS.Util.FormatDate(ts))
    assertTrue(header.key:find(os.date("%Y-%m-%d", ts), 1, true) ~= nil,
      "the stable key stays ISO so collapsed state survives a format change")
  end)
end)

test("BrowserTable: day groups run chronologically, not alphabetically", function()
  withTableState(function()
    local BT = NS.BrowserTable
    BT.groupBy, BT.collapsed, BT.groupAsc = "day", {}, true
    local day = 86400
    local base = 1700000000
    local list = BT:GroupRecords({ { ts = base + 2 * day }, { ts = base }, { ts = base + day } })
    assertEqual(list[1].label, "Day: " .. NS.Util.FormatDate(base))
    assertEqual(list[5].label, "Day: " .. NS.Util.FormatDate(base + 2 * day))
  end)
end)

test("BrowserTable: records with no quality group under an em-dash", function()
  withTableState(function()
    local BT = NS.BrowserTable
    BT.groupBy, BT.collapsed, BT.groupAsc = "quality", {}, true
    assertEqual(BT:GroupRecords({ { ts = 1 } })[1].label, "Quality: \226\128\148")
  end)
end)

test("BrowserTable: ToggleCollapse flips a group shut and open again", function()
  withTableState(function()
    local BT = NS.BrowserTable
    BT.groupBy, BT.collapsed, BT.groupAsc = "source", {}, true
    local recs = { { source = "KILL" }, { source = "KILL" } }
    local key = BT:GroupRecords(recs)[1].key
    BT:ToggleCollapse(key)
    assertEqual(#BT:GroupRecords(recs), 1, "a collapsed group emits its header only")
    BT:ToggleCollapse(key)
    assertEqual(#BT:GroupRecords(recs), 3, "reopening restores the rows")
    assertEqual(BT.collapsed[key], nil, "the reopened key is cleared, not left as false")
  end)
end)

test("BrowserTable: collapsing one group leaves its siblings open", function()
  withTableState(function()
    local BT = NS.BrowserTable
    BT.groupBy, BT.collapsed, BT.groupAsc = "source", {}, true
    local recs = { { source = "KILL" }, { source = "VENDOR" } }
    BT:ToggleCollapse(BT:GroupRecords(recs)[1].key)
    local list = BT:GroupRecords(recs)
    assertEqual(#list, 3)          -- Kill header, Vendor header, Vendor row
    assertTrue(list[1].collapsed)
    assertTrue(not list[2].collapsed)
  end)
end)

test("BrowserTable: SetGroupBy sets the mode, and nil means flat", function()
  withTableState(function()
    local BT = NS.BrowserTable
    BT:SetGroupBy("zone")
    assertEqual(BT.groupBy, "zone")
    BT:SetGroupBy(nil)
    assertEqual(BT.groupBy, "none")
  end)
end)

-- ── Sorting ────────────────────────────────────────────────────────────────────

test("BrowserTable: clicking the grouped column flips the group order, not the row sort", function()
  withTableState(function()
    local BT = NS.BrowserTable
    BT.groupBy, BT.groupAsc = "source", true
    BT.sortKey, BT.sortAsc = "date", false
    BT:SetSort("source")
    assertFalse(BT.groupAsc, "the group order flipped")
    assertEqual(BT.sortKey, "date", "the row sort was left alone")
    assertFalse(BT.sortAsc)
  end)
end)

test("BrowserTable: grouping by day maps the click to the Date column", function()
  withTableState(function()
    local BT = NS.BrowserTable
    BT.groupBy, BT.groupAsc = "day", true
    BT:SetSort("date")
    assertFalse(BT.groupAsc, "Day grouping is driven by the Date header")
  end)
end)

test("BrowserTable: an unsortable or unknown column key is ignored", function()
  withTableState(function()
    local BT = NS.BrowserTable
    BT.groupBy = "none"
    BT.sortKey, BT.sortAsc = "date", false
    BT:SetSort("nosuchcolumn")
    assertEqual(BT.sortKey, "date")
    assertFalse(BT.sortAsc)
  end)
end)

test("BrowserTable: SortRecords returns a new array and leaves the input alone", function()
  withTableState(function()
    local BT = NS.BrowserTable
    BT.sortKey, BT.sortAsc = "qty", true
    local recs = { { quantity = 3 }, { quantity = 1 } }
    local sorted = BT:SortRecords(recs)
    assertTrue(sorted ~= recs, "the caller's array is not the sorted one")
    assertEqual(recs[1].quantity, 3, "the input order is untouched")
    assertEqual(sorted[1].quantity, 1)
  end)
end)

test("BrowserTable: sorting by a column no record fills still keeps every row", function()
  withTableState(function()
    local BT = NS.BrowserTable
    BT.sortKey, BT.sortAsc = "ilvl", false
    local sorted = BT:SortRecords({ { ts = 1 }, { ts = 2 }, { ts = 3 } })
    assertEqual(#sorted, 3, "missing values sort as 0 rather than dropping the row")
    assertEqual(sorted[1].ts, 1, "an all-equal sort preserves the original order")
  end)
end)

test("BrowserTable: the vendor and auction columns sort by copper, not by their text", function()
  withTableState(function()
    local BT = NS.BrowserTable
    BT.sortKey, BT.sortAsc = "vendor", false
    -- "9c" sorts above "1g 0s 0c" lexically; numerically it must not.
    local sorted = BT:SortRecords({ { vendorPrice = 9 }, { vendorPrice = 10000 } })
    assertEqual(sorted[1].vendorPrice, 10000)
  end)
end)

-- ── Cell rendering edges ───────────────────────────────────────────────────────

test("BrowserTable: an unrecognized source still shows something in the Source column", function()
  assertEqual(cell("source", { source = "FUTURE_SOURCE" }), "FUTURE_SOURCE")
  assertEqual(cell("source", {}), "Other")
end)

test("BrowserTable: the vendor column is blank when no price was recorded", function()
  assertEqual(cell("vendor", {}), "")
  assertEqual(cell("vendor", { vendorPrice = 0 }), "")
end)

test("BrowserTable: the auction column is blank when no price map was captured", function()
  assertEqual(cell("auction", {}), "")
end)

test("BrowserTable: quantity defaults to 1 when a record omits it", function()
  assertEqual(cell("qty", {}), "1")
end)

test("BrowserTable: type and subtype cells are blank rather than nil-crashing", function()
  assertEqual(cell("type", {}), "")
  assertEqual(cell("subtype", {}), "")
end)

test("BrowserTable: the Character cell prefixes a class icon when the class is known", function()
  local withClass = cell("char", { char = "Ka0z-Realm", classFile = "MAGE" })
  local without  = cell("char", { char = "Ka0z-Realm" })
  assertEqual(without, "Ka0z-Realm", "an unknown class renders the bare name")
  assertTrue(#withClass > #without, "a known class prefixes inline icon markup")
  assertTrue(withClass:find("Ka0z-Realm", 1, true) ~= nil, "the full Name-Realm is still shown")
end)

test("BrowserTable: ClassIconMarkup is empty for an unknown class", function()
  assertEqual(NS.BrowserTable:ClassIconMarkup(nil), "")
  assertEqual(NS.BrowserTable:ClassIconMarkup("NOTACLASS"), "")
end)

-- ── Column model ───────────────────────────────────────────────────────────────

test("BrowserTable: every column is fully described and uniquely keyed", function()
  local seen = {}
  for _, col in ipairs(NS.BrowserTable.COLUMNS) do
    assertFalse(seen[col.key], col.key .. " is defined twice")
    seen[col.key] = true
    assertTrue(type(col.valueFn) == "function", col.key .. " has no value function")
    assertTrue(type(col.desc) == "string" and col.desc ~= "", col.key .. " has no tooltip")
    assertTrue(type(col.align) == "string", col.key .. " has no alignment")
  end
end)

test("BrowserTable: Character is the last column and Item is the flexing one", function()
  -- Documented ordering contract: new columns are inserted BEFORE Character.
  local cols = NS.BrowserTable.COLUMNS
  assertEqual(cols[#cols].key, "char")
  local flex
  for _, col in ipairs(cols) do if col.flex then flex = col.key end end
  assertEqual(flex, "item", "exactly the Item column absorbs the spare width")
end)

test("BrowserTable: every column except the flexing one reserves a width", function()
  for _, col in ipairs(NS.BrowserTable.COLUMNS) do
    if col.flex then
      assertEqual(col.width, 0)
    else
      assertTrue(col.width > 0, col.key .. " needs a fixed width")
    end
  end
end)

-- ── Synthetic dataset ──────────────────────────────────────────────────────────

test("BrowserTable: the synthetic dataset is byte-identical between builds", function()
  -- A fixed-seed PRNG (not math.random) is what keeps the /lh test data — and these tests — stable.
  local a, b = NS.BrowserTable:BuildTestData(), NS.BrowserTable:BuildTestData()
  assertEqual(#a, #b)
  for i = 1, #a do
    assertEqual(a[i].itemName, b[i].itemName, "record " .. i .. " differs")
    assertEqual(a[i].source, b[i].source)
    assertEqual(a[i].quality, b[i].quality)
    assertEqual(a[i].vendorPrice, b[i].vendorPrice)
  end
end)

test("BrowserTable: every synthetic record carries the fields the table and charts read", function()
  for _, r in ipairs(NS.BrowserTable:BuildTestData()) do
    assertTrue(type(r.ts) == "number" and r.ts > 0)
    assertTrue(type(r.char) == "string" and r.char:find("-", 1, true) ~= nil, "char is Name-Realm")
    assertTrue(type(r.itemName) == "string" and r.itemName ~= "")
    assertTrue(type(r.itemID) == "number")
    assertTrue(type(r.quantity) == "number" and r.quantity >= 1)
    assertTrue(type(r.vendorPrice) == "number" and r.vendorPrice > 0)
    assertTrue(type(r.mapID) == "number")
    assertTrue(type(r.zone) == "string" and r.zone ~= "")
  end
end)

test("BrowserTable: only gear carries an item level in the synthetic dataset", function()
  for _, r in ipairs(NS.BrowserTable:BuildTestData()) do
    local isGear = r.itemType == "Armor" or r.itemType == "Weapon"
    if isGear then
      assertTrue(r.itemLevel ~= nil, "gear must have an ilvl")
    else
      assertEqual(r.itemLevel, nil, r.itemType .. " must not have an ilvl")
    end
  end
end)

test("BrowserTable: only Mythic+ records carry a keystone level", function()
  for _, r in ipairs(NS.BrowserTable:BuildTestData()) do
    if r.source ~= "MPLUS" then
      assertEqual(r.sourceDetail, nil, "a non-M+ drop has no keystone detail")
    end
  end
end)

test("BrowserTable: synthetic confidence is always one of the two enum values", function()
  for _, r in ipairs(NS.BrowserTable:BuildTestData()) do
    assertTrue(r.confidence == "CERTAIN" or r.confidence == "INFERRED", "got " .. tostring(r.confidence))
  end
end)

test("BrowserTable: every synthetic auction map is pickable by the priority cascade", function()
  local priced = 0
  for _, r in ipairs(NS.BrowserTable:BuildTestData()) do
    if r.auctionPrice then
      local price = NS.AuctionPrice:Pick(r.auctionPrice)
      assertTrue(price ~= nil and price > 0, "a captured map must yield a price")
      priced = priced + 1
    end
  end
  assertTrue(priced > 0, "some synthetic drops must carry AH prices")
end)

test("BrowserTable: a large all-ties sort keeps every row in its original order", function()
  -- Lua 5.1's table.sort is not stable, and its quicksort only scrambles at size. Three rows can
  -- come out ordered by luck; forty cannot — this is what pins the explicit index tiebreak.
  withTableState(function()
    local BT = NS.BrowserTable
    BT.sortKey, BT.sortAsc = "quality", false
    local recs = {}
    for i = 1, 40 do recs[i] = { ts = i, quality = 3 } end
    local sorted = BT:SortRecords(recs)
    for i = 1, 40 do
      assertEqual(sorted[i].ts, i, "row " .. i .. " moved despite an equal sort key")
    end
  end)
end)
