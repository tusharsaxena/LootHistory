local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- The Search box's autocomplete on every tab (P9): the seam (NS.MakeAutocomplete), the list's
-- placement under the shared Search box, the per-tab providers (B:Suggest routing to the active tab
-- spec's `suggest`) and picks (`pick`), and that the Timeline's own picker list is gone.
--
-- The list widget itself (keyboard, focus, debounce, pooling) is LibKa0s's and pinned by its own
-- suite; this one pins what this addon feeds it and does with a pick. Every case runs through
-- `case`, which puts back what it touched: the Search text and the shared filter's text, the
-- Character scope, the loot sample, the holdings and daily stores, the Rollup key index, the saved
-- view's Timeline fields and the session pick; then it returns the browser to History and closes it.

local B = NS.Browser

local function case(name, fn)
  test(name, function()
    local g, p = NS.db.global, NS.db.profile
    local holdings, daily, keys = g.holdings, g.daily, NS.Rollup and NS.Rollup._keys
    local testRecords = NS.State.testRecords
    local view = p.savedView
    local hadView = type(view) == "table"
    local viewThing = hadView and view.timelineThing or nil
    local thing = NS.Timeline and NS.Timeline.thing
    local char = B:CurrentFilter().char
    if NS.Rollup then NS.Rollup._keys = nil end
    local ok, err = pcall(fn)
    if B._autocomplete then B._autocomplete:Close() end
    B:SetSearchText("")
    B:SetCharSet(char)
    B:SelectTab("History"); B:Hide()
    NS.State.testRecords = testRecords
    g.holdings, g.daily = holdings, daily
    if NS.Rollup then NS.Rollup._keys = keys end
    if hadView then p.savedView = view; view.timelineThing = viewThing else p.savedView = nil end
    if NS.Timeline then NS.Timeline.thing = thing end
    if not ok then error(err, 0) end
  end)
end

-- Loot rows: two Robes (one name, offered once), a currency, a gold row and an Axe.
local RECORDS = {
  { ts = 1000, char = "Mock-Realm", itemName = "Robe of Rot", quality = 3, itemID = 11 },
  { ts = 1100, char = "Mock-Realm", itemName = "Robe of Rot", quality = 3, itemID = 11 },
  { ts = 1200, char = "Alt-Realm", itemName = "Greater Robe", quality = 4, itemID = 12 },
  { ts = 1300, char = "Mock-Realm", itemName = "Resonance Crystals", quality = 2, currencyID = 2815 },
  { ts = 1400, char = "Mock-Realm", itemName = "Gold", kind = "GOLD", quantity = 500 },
  { ts = 1500, char = "Alt-Realm", itemName = "Axe of Ro", quality = 2, itemID = 13 },
}

local function open(tab)
  B:Show()
  B:SetCharSet(nil)
  B:SelectTab(tab)
end

local function texts(items)
  local out = {}
  for i, it in ipairs(items or {}) do out[i] = it.text end
  return out
end

-- Gold, a currency (the mock names 3008 "Valorstones", quality 4) and an item (the mock names every
-- item "Item Name").
local function seedHoldings()
  NS.db.global.holdings, NS.db.global.daily = {}, {}
  local t = os.time()
  NS.Holdings:ApplyContainer("Mock-Realm", "bags", { [7] = 2 }, {}, t)
  NS.Holdings:ApplyCurrency("Mock-Realm", { [3008] = 5 }, t)
  NS.Holdings:ApplyMoney("Mock-Realm", 70000, t)
end

-- ── the seam and the list's placement ──

test("Autocomplete: the seam answers a library handle on a real box, nil without one", function()
  local box = T.mocks.CreateFrame("EditBox")
  local h = NS.MakeAutocomplete(box, { provider = function() return {} end })
  assertTrue(h ~= nil and type(h.Close) == "function", "no handle for a real box")
  h:Release()
  assertEqual(NS.MakeAutocomplete({}, { provider = function() return {} end }), nil)
end)

case("Autocomplete: typing in Search opens the list directly under the box, as wide as it", function()
  -- Review Focus 2: the list is anchored to BOTH the Search box's bottom corners, so it is the box's
  -- width and follows it through every filter-bar relayout (FB-1) with no handler of its own (the
  -- library parents it to the box, so it takes the window's scale too).
  NS.State.testRecords = RECORDS
  open("History")
  local box, h = B._search, B._autocomplete
  assertTrue(h ~= nil, "the Search box has no autocomplete")
  box:SetText("rob"); box:__fire("OnTextChanged", true)
  T.mocks.__fireTimers()
  assertTrue(h:IsShown(), "typing opened no list")
  assertEqual(texts(h.__items)[1], "Robe of Rot")
  local list = h.__list
  local byPoint = {}
  for _, pt in ipairs(list.__points) do byPoint[pt.point] = pt end
  assertEqual(byPoint.TOPLEFT.relativeTo, box); assertEqual(byPoint.TOPLEFT.relativePoint, "BOTTOMLEFT")
  assertEqual(byPoint.TOPRIGHT.relativeTo, box); assertEqual(byPoint.TOPRIGHT.relativePoint, "BOTTOMRIGHT")
end)

case("Autocomplete: switching tabs closes the list", function()
  NS.State.testRecords = RECORDS
  open("History")
  local box, h = B._search, B._autocomplete
  box:SetText("rob"); box:__fire("OnTextChanged", true)
  T.mocks.__fireTimers()
  assertTrue(h:IsShown())
  B:SelectTab("Holdings")
  assertFalse(h:IsShown(), "the History list stayed open over Holdings")
end)

-- ── History and Insights ──

case("Autocomplete: History offers distinct item and currency names, prefix matches first, no Gold", function()
  NS.State.testRecords = RECORDS
  open("History")
  local items = B:Suggest("ro")
  -- "Robe of Rot" starts with "ro"; "Axe of Ro" and "Greater Robe" only contain it. Gold never shows.
  local got = texts(items)
  assertEqual(got[1], "Robe of Rot")
  assertEqual(#got, 3, table.concat(got, ", "))
  assertEqual(got[2], "Axe of Ro"); assertEqual(got[3], "Greater Robe")
  assertEqual(texts(B:Suggest("gold"))[1], nil, "a gold row was offered as a name")
  assertEqual(texts(B:Suggest("reso"))[1], "Resonance Crystals", "currency names are offered")
  assertEqual(#B:Suggest("   "), 0, "blank text offers nothing")
end)

case("Autocomplete: History rows carry their quality's color", function()
  NS.State.testRecords = RECORDS
  open("History")
  local robe = B:Suggest("robe of")[1]
  local want = NS.Analytics._qualityColor(3)
  assertEqual(robe.color[1], want[1]); assertEqual(robe.color[2], want[2]); assertEqual(robe.color[3], want[3])
end)

case("Autocomplete: History's names follow the other filters, with the typed text set aside", function()
  NS.State.testRecords = RECORDS
  open("History")
  B:SetCharSet({ ["Alt-Realm"] = true })
  local got = texts(B:Suggest("ro"))
  assertEqual(#got, 2, table.concat(got, ", "))   -- Axe of Ro, Greater Robe: Alt-Realm's rows only
  assertEqual(got[1], "Axe of Ro")
end)

case("Autocomplete: History reads the test-mode sample, not the live history", function()
  NS.State.testRecords = { { ts = 1, char = "Mock-Realm", itemName = "Sample Spoon", quality = 2, itemID = 5 } }
  open("History")
  assertEqual(texts(B:Suggest("spoon"))[1], "Sample Spoon")
  NS.State.testRecords = RECORDS
  assertEqual(#B:Suggest("spoon"), 0, "the sample outlived the dataset swap")
end)

case("Autocomplete: a History pick puts exactly that name in Search and applies it", function()
  NS.State.testRecords = RECORDS
  open("History")
  B._search:SetText("rob")
  B.activeFilter.text = "rob"
  B:PickSuggestion({ text = "Robe of Rot", value = "Robe of Rot" })
  assertEqual(B._search:GetText(), "Robe of Rot")
  assertEqual(B.activeFilter.text, "Robe of Rot")
  assertEqual(NS.BrowserTable.matchCount, 2, "the table did not apply the picked name")
end)

case("Autocomplete: Insights offers the same names and picks the same way", function()
  -- Insights' charts are pinned by test_analytics_layout on a private instance; the live pane is not
  -- drawn here (its pools are never built in this harness), so it is marked built and its refresh
  -- counted rather than run.
  NS.State.testRecords = RECORDS
  B:Show()
  local pane = B:GetWindow().panes.Insights
  local wasBuilt, realRefresh, refreshed = pane._built, NS.Analytics.Refresh, 0
  pane._built = true
  NS.Analytics.Refresh = function() refreshed = refreshed + 1 end
  local ok, err = pcall(function()
    open("Insights")
    assertEqual(texts(B:Suggest("ro"))[1], "Robe of Rot")
    refreshed = 0
    B:PickSuggestion({ text = "Greater Robe", value = "Greater Robe" })
    assertEqual(B._search:GetText(), "Greater Robe")
    assertEqual(B.activeFilter.text, "Greater Robe")
    assertEqual(refreshed, 1, "the pick did not repaint Insights exactly once")
    B:SelectTab("History")
  end)
  NS.Analytics.Refresh, pane._built = realRefresh, wasBuilt
  if not ok then error(err, 0) end
end)

-- ── Holdings ──

case("Autocomplete: Holdings offers what Holdings search finds, Gold included, and picks the name", function()
  seedHoldings()
  open("Holdings")
  local items = B:Suggest("o")
  local got = texts(items)
  assertEqual(#got, 2, table.concat(got, ", "))
  assertEqual(got[1], "Gold"); assertEqual(got[2], "Valorstones")
  local want = NS.Analytics._qualityColor(4)
  assertEqual(items[2].color[1], want[1]); assertEqual(items[2].color[3], want[3])
  B:PickSuggestion(B:Suggest("valor")[1])
  assertEqual(B._search:GetText(), "Valorstones")
  assertEqual(B.activeFilter.text, "Valorstones")
end)

-- ── Timeline ──

case("Autocomplete: Timeline offers things, Gold first when it matches", function()
  seedHoldings()
  open("Timeline")
  local items = B:Suggest("o")
  assertEqual(items[1].value, "g")
  assertEqual(items[2].value, "c:3008")
  assertEqual(items[2].text, "Valorstones")
  assertEqual(B:Suggest("gol")[1].value, "g")
  assertEqual(#B:Suggest(""), 0, "no text, no suggestion list")
end)

case("Autocomplete: a Timeline pick charts the thing and keeps its name in Search", function()
  seedHoldings()
  open("Timeline")
  NS.Timeline:SetThing("g")
  B:PickSuggestion(B:Suggest("valor")[1])
  assertEqual(NS.Timeline:Thing(), "c:3008")
  assertEqual(NS.Browser:ViewField("timelineThing"), "c:3008", "the pick was not remembered")
  assertEqual(B._search:GetText(), "Valorstones")
  assertEqual(NS.Timeline.model.key, "c:3008", "the chart was not repainted on the pick")
  -- The same name again changes no filter text, so the pick repaints the chart itself.
  NS.Timeline:SetThing("g")
  assertEqual(NS.Timeline.model.key, "g")
  B:PickSuggestion(B:Suggest("valor")[1])
  assertEqual(NS.Timeline.model.key, "c:3008", "a pick that left Search unchanged did not repaint")
end)

test("Autocomplete: the Timeline's own picker list is gone", function()
  local TL = NS.Timeline
  assertEqual(TL.RenderSuggestions, nil); assertEqual(TL.SuggestionKeys, nil)
  assertEqual(TL.suggest, nil, "the old suggestion frame is still built")
  local fh = assert(io.open("modules/Timeline.lua", "rb"))
  local src = fh:read("*a"); fh:close()
  assertFalse(src:find("makeSuggestRow", 1, true) ~= nil, "makeSuggestRow is still in modules/Timeline.lua")
  assertFalse(src:find("RenderSuggestions", 1, true) ~= nil, "RenderSuggestions is still in modules/Timeline.lua")
end)

-- ── routing ──

case("Autocomplete: a tab with no suggest, or with Search grayed, offers nothing", function()
  NS.State.testRecords = RECORDS
  B:RegisterTab{ name = "Plain", order = 90, filters = { date = true }, build = function() end }
  B:RegisterTab{ name = "Grayed", order = 91, filters = { date = true },
    suggest = function() return { { text = "x" } } end, build = function() end }
  local ok, err = pcall(function()
    open("Plain")
    assertEqual(B:Suggest("ro"), nil)
    B:SelectTab("Grayed")
    assertEqual(B:Suggest("ro"), nil, "a tab whose Search is grayed offered a list")
    B:PickSuggestion({ text = "x" })   -- no pick: must not raise
  end)
  B:_UnregisterTabForTest("Plain"); B:_UnregisterTabForTest("Grayed")
  if not ok then error(err, 0) end
end)
