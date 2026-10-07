local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- The Holdings tab (timeline-ledger spec §8.2). BuildModel carries every decision and is pure, so
-- most of this suite never touches a frame; the last case opens the window to pin that the pooled
-- rows are recycled rather than reallocated on refresh.

local function seed()
  NS.db.global.holdings = {}
  NS.Holdings:ApplyContainer("A-Realm", "bags", { [7] = 2 }, { [7] = "|Hitem:7|h[Apple]|h" }, 100)
  NS.Holdings:ApplyContainer("B-Realm", "bank", { [7] = 9 }, {}, 50)
  NS.Holdings:ApplyMoney("A-Realm", 10000, 100)
end

test("HoldingsTab: model lists things collapsed by default", function()
  seed()
  local lines = NS.HoldingsTab.BuildModel({}, {}, "name")
  local things = 0
  for _, l in ipairs(lines) do if l.kind == "thing" then things = things + 1 else error("holder line while collapsed") end end
  assertEqual(things, 2)   -- Apple + Gold
end)

test("HoldingsTab: expanding a thing adds one line per holder", function()
  seed()
  local lines = NS.HoldingsTab.BuildModel({}, { ["i:7"] = true }, "total")
  assertEqual(lines[1].key, "g")            -- total sort: gold 10000 first
  local holders = 0
  for _, l in ipairs(lines) do if l.kind == "holder" then holders = holders + 1 end end
  assertEqual(holders, 2)
end)

test("HoldingsTab: character filter narrows holders", function()
  seed()
  local lines = NS.HoldingsTab.BuildModel({ char = { ["B-Realm"] = true } }, { ["i:7"] = true }, "name")
  for _, l in ipairs(lines) do
    if l.kind == "holder" then assertEqual(l.holder, "B-Realm") end
    if l.kind == "thing" then assertTrue(l.key ~= "g") end   -- B has no gold
  end
end)

test("HoldingsTab: container and age formatting", function()
  assertEqual(NS.HoldingsTab.FormatContainers({ tabs = 100, bags = 12, bank = 40 }), "Bags 12 · Bank 40 · Warband 100")
  assertEqual(NS.HoldingsTab.FormatAge(1000, 1030), "now")
  assertEqual(NS.HoldingsTab.FormatAge(1000, 1000 + 3 * 3600), "3 h")
  assertEqual(NS.HoldingsTab.FormatAge(1000, 1000 + 2 * 86400), "2 d")
end)

test("HoldingsTab: tab is registered after History and Insights", function()
  local names = NS.Browser:Tabs()
  assertEqual(names[#names], "Holdings")
end)

test("HoldingsTab: attach builds rows and recycles them on refresh", function()
  -- Adapted from the plan's snippet: the window is closed again on every path, because a browser
  -- left on screen keeps repainting under the panel suites that run next and skews their counts.
  -- The pool's free/active split is also pinned, since an equal row count alone passes a refresh
  -- that allocates a fresh frame per line every time. The window opens scoped to the logged-in
  -- character (Mock-Realm), who holds nothing in this seed, so the scope is widened for the case
  -- and put back after.
  seed()
  local savedChar = NS.Browser:CurrentFilter().char
  local ok, err = pcall(function()
    NS.Browser:Show(); NS.Browser:SetCharSet(nil); NS.Browser:SelectTab("Holdings")
    local first = NS.HoldingsTab:VisibleRowCount()
    local _, active = NS.Pool.Counts(NS.HoldingsTab.rows)
    NS.HoldingsTab:Refresh()
    assertEqual(NS.HoldingsTab:VisibleRowCount(), first)
    assertTrue(first >= 2)
    local free2, active2 = NS.Pool.Counts(NS.HoldingsTab.rows)
    assertEqual(active2, active); assertEqual(free2, 0, "a refresh re-acquired every released row")
  end)
  NS.Browser:SetCharSet(savedChar); NS.Browser:SelectTab("History"); NS.Browser:Hide()
  if not ok then error(err, 0) end
end)

test("HoldingsTab: HOLDINGS_CHANGED does not rebuild the pane once the window is closed", function()
  -- red under: the handler gating on pane:IsShown() -- closing the browser with Holdings as the
  -- last tab leaves the pane shown inside a hidden window, and every Reconciler flush then ran a
  -- full off-screen BuildModel (AH-price lookups included). The kit's IsVisible does not walk
  -- parents, so the pane is told what the client would answer: shown, but not visible.
  seed()
  local savedChar = NS.Browser:CurrentFilter().char
  local realRefresh, calls = NS.HoldingsTab.Refresh, 0
  local pane, realVisible
  local ok, err = pcall(function()
    NS.Browser:Show(); NS.Browser:SetCharSet(nil); NS.Browser:SelectTab("Holdings")
    pane = NS.HoldingsTab.pane
    assertTrue(pane ~= nil, "the Holdings pane was not attached")
    NS.HoldingsTab.Refresh = function(self, ...) calls = calls + 1; return realRefresh(self, ...) end
    NS.bus:SendMessage(NS.MSG.HOLDINGS_CHANGED, "A-Realm")
    assertEqual(calls, 1, "the visible pane did not repaint on HOLDINGS_CHANGED")
    NS.Browser:Hide()
    realVisible = pane.IsVisible
    pane.IsVisible = function() return false end
    assertTrue(pane:IsShown(), "the case needs the pane still shown inside the hidden window")
    NS.bus:SendMessage(NS.MSG.HOLDINGS_CHANGED, "A-Realm")
    assertEqual(calls, 1, "HOLDINGS_CHANGED rebuilt the Holdings pane while the window was closed")
  end)
  NS.HoldingsTab.Refresh = realRefresh
  if pane and realVisible then pane.IsVisible = realVisible end
  NS.Browser:Show(); NS.Browser:SetCharSet(savedChar); NS.Browser:SelectTab("History"); NS.Browser:Hide()
  if not ok then error(err, 0) end
end)

-- ---------------------------------------------------------------------------
-- Row actions and "Forget this character" (timeline ledger P3, spec §8.2)
-- ---------------------------------------------------------------------------
-- Adapted from the plan's snippets: each store-touching case runs through `keep`, which puts the
-- holdings and daily stores and the Rollup key index back as it found them (addenda, Global); the
-- chunk has no global `time`, so the seeds read os.time().

local assertFalse = T.assertFalse

local function keep(fn)
  local g = NS.db.global
  local holdings, daily, keys = g.holdings, g.daily, NS.Rollup and NS.Rollup._keys
  local ok, err = pcall(fn)
  g.holdings, g.daily = holdings, daily
  if NS.Rollup then NS.Rollup._keys = keys end
  if not ok then error(err, 0) end
end

local function captureChanged(fn)
  local got, orig = {}, NS.bus.SendMessage
  NS.bus.SendMessage = function(self, msg, a, ...)
    if msg == NS.MSG.HOLDINGS_CHANGED then got[#got + 1] = a end
    return orig(self, msg, a, ...)
  end
  local ok, err = pcall(fn)
  NS.bus.SendMessage = orig
  if not ok then error(err, 0) end
  return got
end

local function labels(items)
  local out = {}
  for _, it in ipairs(items) do out[(it.label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))] = it end
  return out
end

test("Holdings row actions: a thing line offers Show in Timeline", function()
  local a = labels(NS.HoldingsTab.RowActions({ kind = "thing", key = "c:3008" }))
  assertTrue(a["Show in Timeline"] ~= nil and a["Show in Timeline"].enabled)
  assertEqual(a["Forget this character"], nil, "a thing line is not a character")
end)

test("Holdings row actions: Forget is offered for an alt, never for the warband or the logged-in character", function()
  local alt = labels(NS.HoldingsTab.RowActions({ kind = "holder", key = "g", holder = "Alt-Realm" }))
  assertTrue(alt["Forget this character"].enabled)
  local wb = labels(NS.HoldingsTab.RowActions({ kind = "holder", key = "g", holder = NS.Constants.WARBAND_HOLDER }))
  assertFalse(wb["Forget this character"].enabled)
  local me = labels(NS.HoldingsTab.RowActions({ kind = "holder", key = "g", holder = NS.Util.PlayerKey() }))
  assertFalse(me["Forget this character"].enabled)
end)

test("Holdings row actions: Forget is disabled in test mode, even for an alt", function()
  local prev = NS.State.testHoldings
  NS.State.testHoldings = {}
  local ok, err = pcall(function()
    local alt = labels(NS.HoldingsTab.RowActions({ kind = "holder", key = "g", holder = "Alt-Realm" }))
    assertFalse(alt["Forget this character"].enabled, "test mode must never offer to forget a real character")
  end)
  NS.State.testHoldings = prev
  if not ok then error(err, 0) end
end)

test("Forget this character: drops holdings and rollup cells, keeps history rows, announces once", function()
  keep(function()
    NS.db.global.holdings, NS.db.global.daily = {}, {}
    local t = os.time()
    NS.Holdings:ApplyMoney("Alt-Realm", 100, t)
    NS.Holdings:ApplyMoney("Keep-Realm", 5, t)
    -- A rollup cell for the alt whether or not the write hook is live in this harness.
    NS.Ledger.RollupClose(NS.db.global.daily, NS.Ledger.DayKey(t), "Alt-Realm", "g", 100)
    local hist = #NS.db.global.history
    local got = captureChanged(function() assertTrue(NS.Reconciler:ForgetHolder("Alt-Realm")) end)
    assertEqual(NS.Holdings:Get("Alt-Realm"), nil)
    for _, holders in pairs(NS.db.global.daily) do assertEqual(holders["Alt-Realm"], nil) end
    assertTrue(NS.Holdings:Get("Keep-Realm") ~= nil)
    assertEqual(#NS.db.global.history, hist)
    assertEqual(#got, 1); assertEqual(got[1], "Alt-Realm")
  end)
end)

test("Forget this character: a holder with nothing stored is a no-op and announces nothing", function()
  keep(function()
    NS.db.global.holdings, NS.db.global.daily = {}, {}
    local ok
    local got = captureChanged(function() ok = NS.Reconciler:ForgetHolder("Nobody-Realm") end)
    assertFalse(ok); assertEqual(#got, 0)
  end)
end)

test("Forget this character: refuses the logged-in character and the warband", function()
  local ok, why = NS.Reconciler:ForgetHolder(NS.Util.PlayerKey())
  assertFalse(ok); assertEqual(why, "current")
  ok, why = NS.Reconciler:ForgetHolder(NS.Constants.WARBAND_HOLDER)
  assertFalse(ok); assertEqual(why, "warband")
end)

test("Forget popup: registered, and its accept forgets the holder it carries", function()
  keep(function()
    local d = T.mocks.StaticPopupDialogs["KA0S_LOOTHISTORY_FORGET_HOLDER"]
    assertTrue(d ~= nil and d.text:find("%s", 1, true) ~= nil)
    NS.db.global.holdings, NS.db.global.daily = {}, {}
    NS.Holdings:ApplyMoney("Alt-Realm", 1, os.time())
    d.OnAccept(nil, { holder = "Alt-Realm" })
    assertEqual(NS.Holdings:Get("Alt-Realm"), nil)
  end)
end)

-- ---------------------------------------------------------------------------
-- Metadata columns, banding, tooltips and the header (timeline ledger P4 polish, Task 2)
-- ---------------------------------------------------------------------------
-- Adapted from the plan's list: the kit's CreateFontString answers the frame itself (mock_base's
-- "Known divergence"), so a header's FontStrings cannot be enumerated; the header is pinned through
-- its cell set and the text each cell was given (HT:HeaderLabels). Tooltips are recorded by swapping
-- the mock GameTooltip's methods for recorders, since the stub's own methods no-op.

local mocks = T.mocks

-- Run `fn` with the item API describing a cached piece of gear and the AH price sources answering
-- one price, then put every swapped function back.
local function withGear(fn)
  local item, AP = mocks.C_Item, NS.AuctionPrice
  local saved = { item.GetItemInfoInstant, item.GetItemInfo, item.GetDetailedItemLevelInfo, AP.GatherAll, AP.Pick }
  item.GetItemInfoInstant = function() return 7, "Armor", "Cloth", "INVTYPE_HEAD", nil, 4 end
  item.GetItemInfo = function(l)
    return "Apple", l, 3, 600, nil, "Armor", "Cloth", nil, "INVTYPE_HEAD", nil, 50
  end
  item.GetDetailedItemLevelInfo = function() return 610 end
  AP.GatherAll = function() return { mock = { unit = 1234 } } end
  AP.Pick = function(_, map) return map and map.mock and map.mock.unit, map and "mock:unit" end
  local ok, err = pcall(fn)
  item.GetItemInfoInstant, item.GetItemInfo, item.GetDetailedItemLevelInfo, AP.GatherAll, AP.Pick =
    saved[1], saved[2], saved[3], saved[4], saved[5]
  if not ok then error(err, 0) end
end

local function byKey(lines)
  local out = {}
  for _, l in ipairs(lines) do if l.kind == "thing" then out[l.key] = l end end
  return out
end

test("HoldingsTab: an item line carries iLvl, quality label, type, subtype and the AH unit price", function()
  withGear(function()
    seed()
    local l = byKey(NS.HoldingsTab.BuildModel({}, {}, "name"))["i:7"]
    assertEqual(l.ilvl, 610)
    assertEqual(l.qualityLabel, NS.Item.QualityLabel(3))
    assertEqual(l.itemType, "Armor"); assertEqual(l.itemSubType, "Cloth")
    assertEqual(l.ahUnit, 1234)
    assertEqual(l.value, 1234 * 11, "value is the picked unit price times the held total")
  end)
end)

test("HoldingsTab: a non-gear item has no iLvl", function()
  seed()   -- the stock mock item is a consumable (class 0, no equip slot)
  assertEqual(byKey(NS.HoldingsTab.BuildModel({}, {}, "name"))["i:7"].ilvl, nil)
end)

test("HoldingsTab: a currency line reads Currency / its category, with no iLvl or AH price", function()
  keep(function()
    NS.db.global.holdings = {}
    NS.Holdings:ApplyCurrency("A-Realm", { [3008] = 40 }, 100)
    local l = byKey(NS.HoldingsTab.BuildModel({}, {}, "name"))["c:3008"]
    assertEqual(l.itemType, NS.Constants.CURRENCY_TYPE)
    assertEqual(l.itemSubType, NS.Compat.CurrencyCategory(3008))
    assertEqual(l.ilvl, nil); assertEqual(l.ahUnit, nil)
    assertEqual(l.qualityLabel, NS.Item.QualityLabel(4))
  end)
end)

test("HoldingsTab: the gold line reads Gold with no subtype, quality, iLvl or AH price", function()
  seed()
  local l = byKey(NS.HoldingsTab.BuildModel({}, {}, "name"))["g"]
  assertEqual(l.itemType, "Gold"); assertEqual(l.itemSubType, nil)
  assertEqual(l.qualityLabel, nil); assertEqual(l.ilvl, nil); assertEqual(l.ahUnit, nil)
end)

test("HoldingsTab: stripes alternate per thing and an expanded thing's holders keep its stripe", function()
  seed()
  local lines = NS.HoldingsTab.BuildModel({}, { ["i:7"] = true, g = true }, "name")
  -- name sort: Gold (1 holder), then the item (2 holders; the stock mock names every item "Item Name")
  local seen = {}
  for _, l in ipairs(lines) do seen[#seen + 1] = l.kind .. ":" .. l.stripe end
  assertEqual(table.concat(seen, ","), "thing:1,holder:1,thing:2,holder:2,holder:2")
end)

test("HoldingsTab: header sorts by every column and a second click flips the direction", function()
  local HT = NS.HoldingsTab
  local saved = { HT.sortKey, HT.sortAsc }
  local ok, err = pcall(function()
    seed()
    local function firstKey() return HT.BuildModel({}, {}, HT.sortKey, HT.sortAsc)[1].key end
    HT:SetSort("name")
    if HT.sortKey ~= "name" or HT.sortAsc ~= true then HT:SetSort("name") end
    assertEqual(HT.sortAsc, true); assertEqual(firstKey(), "g")     -- Gold before Item Name
    HT:SetSort("name")
    assertEqual(HT.sortAsc, false); assertEqual(firstKey(), "i:7")
    HT:SetSort("total")                                              -- numeric: starts descending
    assertEqual(HT.sortAsc, false); assertEqual(firstKey(), "g")      -- 10000 copper beats 11
    HT:SetSort("total")
    assertEqual(HT.sortAsc, true); assertEqual(firstKey(), "i:7")
    for _, col in ipairs(HT.COLUMNS) do
      HT:SetSort(col.key)
      assertEqual(HT.sortKey, col.key)
      assertTrue(#HT.BuildModel({}, {}, HT.sortKey, HT.sortAsc) == 2, col.key .. " sort lost a line")
    end
  end)
  HT.sortKey, HT.sortAsc = saved[1], saved[2]
  if not ok then error(err, 0) end
end)

test("HoldingsTab: columns hide right to left as the pane narrows; Name, Total and Value stay", function()
  local HT = NS.HoldingsTab
  local function keys(w)
    local out = {}
    for _, c in ipairs(HT.ColumnLayout(w)) do out[#out + 1] = c.key end
    return table.concat(out, ",")
  end
  assertEqual(keys(2000), "name,ilvl,quality,type,subtype,ah,total,value")
  local narrow = keys(1)
  assertEqual(narrow, "name,total,value")
  -- Somewhere between, AH price goes before SubType, SubType before Type, and so on.
  local prev = 8
  for w = 2000, 1, -10 do
    local n = #HT.ColumnLayout(w)
    assertTrue(n <= prev, "a narrower pane showed more columns")
    prev = n
    local s = keys(w)
    if not s:find("subtype", 1, true) then assertTrue(not s:find(",ah,", 1, true), "AH stayed after SubType went") end
    if not s:find(",type,", 1, true) then assertTrue(not s:find("subtype", 1, true), "SubType stayed after Type went") end
  end
end)

-- Record GameTooltip's calls for the length of `fn`.
local function recordTooltip(fn)
  local tt, calls, saved = mocks.GameTooltip, {}, {}
  for _, m in ipairs({ "SetOwner", "SetHyperlink", "SetCurrencyByID", "AddLine", "Show", "Hide" }) do
    saved[m] = rawget(tt, m)
    tt[m] = function(_, a) calls[#calls + 1] = m .. "(" .. tostring(a) .. ")"; return tt end
  end
  local ok, err = pcall(fn)
  for m, f in pairs(saved) do tt[m] = f end
  for _, m in ipairs({ "SetOwner", "SetHyperlink", "SetCurrencyByID", "AddLine", "Show", "Hide" }) do
    if saved[m] == nil then tt[m] = nil end
  end
  if not ok then error(err, 0) end
  return table.concat(calls, " ")
end

test("HoldingsTab: hovering a thing shows the right tooltip for an item, a currency and gold", function()
  local HT, owner = NS.HoldingsTab, {}
  local got = recordTooltip(function()
    HT.ShowTooltip(owner, { kind = "thing", thingKind = "ITEM", id = 7, link = "|Hitem:7|h[Apple]|h" })
  end)
  assertTrue(got:find("SetHyperlink(|Hitem:7|h[Apple]|h)", 1, true) ~= nil, got)
  got = recordTooltip(function() HT.ShowTooltip(owner, { kind = "thing", thingKind = "ITEM", id = 7 }) end)
  assertTrue(got:find("SetHyperlink(item:7)", 1, true) ~= nil, got)
  got = recordTooltip(function() HT.ShowTooltip(owner, { kind = "thing", thingKind = "CURRENCY", id = 3008 }) end)
  assertTrue(got:find("SetCurrencyByID(3008)", 1, true) ~= nil, got)
  got = recordTooltip(function()
    HT.ShowTooltip(owner, { kind = "thing", thingKind = "GOLD", key = "g", name = "Gold", total = 10000 })
  end)
  assertTrue(got:find("AddLine(Gold)", 1, true) ~= nil, got)
  assertTrue(got:find("SetHyperlink", 1, true) == nil and got:find("SetCurrencyByID", 1, true) == nil, got)
  got = recordTooltip(function() HT.ShowTooltip(owner, { kind = "holder", key = "g", holder = "A-Realm" }) end)
  assertEqual(got, "", "a holder line has no tooltip")
end)

test("HoldingsTab: the pane's rows hover and leave through the tooltip; the header holds exactly the column labels", function()
  seed()
  local HT = NS.HoldingsTab
  local savedChar = NS.Browser:CurrentFilter().char
  local saved = { HT.sortKey, HT.sortAsc }
  local scroll, savedWidth
  local ok, err = pcall(function()
    NS.Browser:Show(); NS.Browser:SetCharSet(nil); NS.Browser:SelectTab("Holdings")
    HT.sortKey, HT.sortAsc = "name", true
    scroll = HT.scroll; savedWidth = rawget(scroll, "GetWidth")
    -- The kit's frames measure 0 wide; a wide pane is asked for, so every column is laid out.
    HT.scroll.GetWidth = function() return 2000 end
    HT:Refresh()
    -- Header: one cell per column, each carrying its own label, the sorted one with its arrow.
    local texts = HT:HeaderLabels()
    assertEqual(#texts, #HT.COLUMNS)
    for i, col in ipairs(HT.COLUMNS) do
      local plain = texts[i]:gsub("%s*|T.-|t", "")
      assertEqual(plain, col.label)
      assertEqual(texts[i] ~= col.label, col.key == "name", col.key .. " arrow")
    end
    -- Rows: every acquired row hovers without error, gold included, and leaving hides the tooltip.
    local rows = HT:Rows()
    assertTrue(#rows >= 2)
    local got = recordTooltip(function()
      for _, row in ipairs(rows) do
        row:GetScript("OnEnter")(row)
        row:GetScript("OnLeave")(row)
      end
    end)
    assertTrue(got:find("AddLine(Gold)", 1, true) ~= nil, got)
    assertTrue(got:find("Hide", 1, true) ~= nil, got)
  end)
  HT.sortKey, HT.sortAsc = saved[1], saved[2]
  if scroll then scroll.GetWidth = savedWidth end
  NS.Browser:SetCharSet(savedChar); NS.Browser:SelectTab("History"); NS.Browser:Hide()
  if not ok then error(err, 0) end
end)

test("HoldingsTab: with no GameTooltip the tooltip shims draw nothing and do not raise", function()
  local saved = mocks.GameTooltip
  mocks.GameTooltip = nil
  local ok, err = pcall(function()
    assertFalse(NS.HoldingsTab.ShowTooltip({}, { kind = "thing", thingKind = "ITEM", id = 7 }))
    assertFalse(NS.HoldingsTab.ShowTooltip({}, { kind = "thing", thingKind = "GOLD", name = "Gold", total = 1 }))
    NS.Compat.HideTooltip()
  end)
  mocks.GameTooltip = saved
  if not ok then error(err, 0) end
end)

-- ---------------------------------------------------------------------------
-- Group-by (timeline ledger P6, Task 2)
-- ---------------------------------------------------------------------------
-- Holdings keeps its OWN group value (HT.groupBy), so a Holdings pick never moves History's
-- BrowserTable.groupBy; a mode Holdings does not support reads as None.

local W = NS.Constants.WARBAND_HOLDER

-- Gear (item 7: Rare, Armor/Cloth) held by A, B and the warband; gold and a currency on A.
local function seedGroups()
  NS.db.global.holdings = {}
  NS.Holdings:ApplyContainer("A-Realm", "bags", { [7] = 2 }, { [7] = "|Hitem:7|h[Apple]|h" }, 100)
  NS.Holdings:ApplyContainer("B-Realm", "bank", { [7] = 9 }, {}, 50)
  NS.Holdings:ApplyContainer(W, "tabs", { [7] = 5 }, {}, 80)
  NS.Holdings:ApplyMoney("A-Realm", 10000, 100)
  NS.Holdings:ApplyCurrency("A-Realm", { [3008] = 40 }, 100)
end

-- "<label> (count)" for every header, in order, and the thing keys under each.
local function headers(lines)
  local out = {}
  for _, l in ipairs(lines) do
    if l.kind == "header" then out[#out + 1] = l.label .. " (" .. l.count .. ")" end
  end
  return table.concat(out, " | ")
end
local function members(lines)
  local out, cur = {}, nil
  for _, l in ipairs(lines) do
    if l.kind == "header" then cur = l.label; out[cur] = {}
    elseif l.kind == "thing" then local m = out[cur]; m[#m + 1] = l.key .. "=" .. l.total end
  end
  for k, v in pairs(out) do out[k] = table.concat(v, ",") end
  return out
end

test("HoldingsTab group: Quality headers by rank (highest first), N = things in the group", function()
  withGear(function() keep(function()
    seedGroups()
    local lines = NS.HoldingsTab.BuildModel({}, {}, "name", nil, "quality", {})
    local Q = NS.Item.QualityLabel
    assertEqual(headers(lines), "Quality: " .. Q(4) .. " (1) | Quality: " .. Q(3) .. " (1) | Quality: \226\128\148 (1)")
    local m = members(lines)
    assertEqual(m["Quality: " .. Q(3)], "i:7=16", "the item keeps its all-holders total")
    assertEqual(m["Quality: \226\128\148"], "g=10000")
  end) end)
end)

test("HoldingsTab group: Type and SubType headers are alphabetical", function()
  withGear(function() keep(function()
    seedGroups()
    local lines = NS.HoldingsTab.BuildModel({}, {}, "name", nil, "type", {})
    assertEqual(headers(lines), "Type: Armor (1) | Type: Currency (1) | Type: Gold (1)")
    -- A header-less currency list names no currency category, so the currency shares Unknown with
    -- gold (no subtype). Set here rather than leaned on: the category cache now follows the list.
    local savedList = mocks.__currencyList
    mocks.__currencyList = { { id = 3008, name = "Valorstones" } }
    NS.Compat.CurrencyListChanged()
    local ok, err = pcall(function()
      assertEqual(NS.Compat.CurrencyCategory(3008), nil)
      assertEqual(headers(NS.HoldingsTab.BuildModel({}, {}, "name", nil, "subtype", {})),
        "SubType: Cloth (1) | SubType: Unknown (2)")
    end)
    mocks.__currencyList = savedList
    NS.Compat.CurrencyListChanged()
    if not ok then error(err, 0) end
  end) end)
end)

test("HoldingsTab group: Type & SubType reads 'Type: <Type> · <SubType>', a currency its category, gold bare", function()
  withGear(function() keep(function()
    seedGroups()
    local M = " \194\183 "
    local lines = NS.HoldingsTab.BuildModel({}, {}, "name", nil, "typesub", {})
    assertEqual(NS.Compat.CurrencyCategory(3008), "The War Within")
    assertEqual(headers(lines), "Type: Armor" .. M .. "Cloth (1) | Type: Currency" .. M .. "The War Within (1)"
      .. " | Type: Gold (1)")
    local m = members(lines)
    assertEqual(m["Type: Armor" .. M .. "Cloth"], "i:7=16", "the item keeps its all-holders total")
    assertEqual(NS.HoldingsTab.GroupMode("typesub"), "typesub")
  end) end)
end)

test("HoldingsTab group: Character lists a thing under every holder with that holder's count, Warband last", function()
  withGear(function() keep(function()
    seedGroups()
    local lines = NS.HoldingsTab.BuildModel({}, {}, "total", nil, "char", {})
    assertEqual(headers(lines), "Character: A-Realm (3) | Character: B-Realm (1) | Character: Warband (1)")
    local m = members(lines)
    assertEqual(m["Character: A-Realm"], "g=10000,c:3008=40,i:7=2", "sorted by total within the group")
    assertEqual(m["Character: B-Realm"], "i:7=9")
    assertEqual(m["Character: Warband"], "i:7=5")
  end) end)
end)

test("HoldingsTab group: under Character an expanded thing lists only that holder's containers", function()
  keep(function()
    seedGroups()
    local HT = NS.HoldingsTab
    local lines = HT.BuildModel({}, {}, "name", nil, "char", {})
    local key
    for _, l in ipairs(lines) do
      if l.kind == "thing" and l.key == "i:7" and l.holder == "B-Realm" then key = l.expandKey end
    end
    assertTrue(key ~= nil, "a Character-grouped thing line carries its own expand key")
    local holderLines = {}
    for _, l in ipairs(HT.BuildModel({}, { [key] = true }, "name", nil, "char", {})) do
      if l.kind == "holder" then holderLines[#holderLines + 1] = l end
    end
    assertEqual(#holderLines, 1, "only the B group's copy expanded")
    assertEqual(holderLines[1].holder, "B-Realm"); assertEqual(holderLines[1].count, 9)
    assertEqual(holderLines[1].containers.bank, 9)
  end)
end)

test("HoldingsTab group: a collapsed group keeps its header and count and hides its members", function()
  keep(function()
    seedGroups()
    local HT = NS.HoldingsTab
    local open = HT.BuildModel({}, {}, "name", nil, "char", {})
    local aKey
    for _, l in ipairs(open) do if l.kind == "header" and l.label == "Character: A-Realm" then aKey = l.key end end
    local lines = HT.BuildModel({}, {}, "name", nil, "char", { [aKey] = true })
    assertEqual(headers(lines), "Character: A-Realm (3) | Character: B-Realm (1) | Character: Warband (1)")
    assertEqual(lines[1].collapsed, true)
    assertEqual(lines[2].kind, "header", "the A group's members are hidden")
    assertEqual(#lines, #open - 3)
  end)
end)

test("HoldingsTab group: stripes run per thing across groups; headers carry none; holders keep the parent's", function()
  withGear(function() keep(function()
    seedGroups()
    local lines = NS.HoldingsTab.BuildModel({}, { ["i:7"] = true }, "name", nil, "type", {})
    local seen = {}
    for _, l in ipairs(lines) do seen[#seen + 1] = l.kind .. ":" .. tostring(l.stripe) end
    -- Armor (the item, three holders), then Currency, then Gold
    assertEqual(table.concat(seen, ","),
      "header:nil,thing:1,holder:1,holder:1,holder:1,header:nil,thing:2,header:nil,thing:3")
  end) end)
end)

test("HoldingsTab group: an unsupported mode reads as None and leaves History's group alone", function()
  keep(function()
    seedGroups()
    local HT, BT = NS.HoldingsTab, NS.BrowserTable
    for _, mode in ipairs({ "day", "source", "zone", "dir", "holder", "bogus" }) do
      for _, l in ipairs(HT.BuildModel({}, {}, "name", nil, mode, {})) do
        assertTrue(l.kind ~= "header", mode .. " grouped the Holdings view")
      end
    end
    local savedBT, savedHT = BT.groupBy, HT.groupBy
    BT.groupBy = "zone"
    HT:SetGroupBy("day")
    assertEqual(HT.groupBy, "none")
    HT:SetGroupBy("subtype")
    assertEqual(HT.groupBy, "subtype")
    assertEqual(BT.groupBy, "zone", "a Holdings pick never moves History's group")
    BT.groupBy, HT.groupBy = savedBT, savedHT
  end)
end)

test("HoldingsTab group: the Group dropdown is live on Holdings, offers only its modes, and keeps History's pick", function()
  local HT, BT, B = NS.HoldingsTab, NS.BrowserTable, NS.Browser
  local savedChar = B:CurrentFilter().char
  local savedBT, savedHT, savedCollapsed = BT.groupBy, HT.groupBy, HT.collapsed
  local ok, err = pcall(function() keep(function()
    seedGroups()
    B:Show(); B:SetCharSet(nil)
    BT:SetGroupBy("zone"); B._dd.group:SelectValue("zone")
    B:SelectTab("Holdings")
    local dd = B._dd.group
    assertTrue(dd:IsEnabled(), "Group is a Holdings control")
    local vals = {}
    for _, o in ipairs(dd._options) do vals[#vals + 1] = o.value end
    assertEqual(table.concat(vals, ","), "none,quality,type,subtype,typesub,char")
    assertEqual(dd._value, "none", "Holdings shows its own group, not History's Zone")
    dd.onSelect("char")
    assertEqual(HT.groupBy, "char"); assertEqual(BT.groupBy, "zone")
    -- 3 headers + 5 thing lines (A: gold, currency, item; B: item; Warband: item)
    assertEqual(HT:VisibleRowCount(), 8)
    local first = HT:Rows()[1]
    assertEqual(first.line.kind, "header")
    first:GetScript("OnClick")(first, "LeftButton")
    assertEqual(HT:VisibleRowCount(), 5, "clicking a header collapses its group")
    B:SelectTab("History")
    assertEqual(B._dd.group._value, "zone", "History's own pick comes back")
    assertTrue(#B._dd.group._options > 5, "History offers every mode again")
    B:SelectTab("Holdings")
    assertEqual(B._dd.group._value, "char"); assertEqual(HT:VisibleRowCount(), 5, "collapse is remembered")
  end) end)
  BT.groupBy, HT.groupBy, HT.collapsed = savedBT, savedHT, savedCollapsed
  B:SetCharSet(savedChar); B:SelectTab("History"); B._dd.group:SelectValue(savedBT); B:Hide()
  if not ok then error(err, 0) end
end)
