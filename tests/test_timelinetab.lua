local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- The Timeline tab (timeline-ledger spec §8.1): the view over NS.TimelineModel. The model's numbers
-- are pinned in test_timeline; this suite pins what the tab paints from them and how it is wired --
-- the tab order, the Character filter, pooling, the line cap, the Search-box picker, the remembered
-- pick, the per-tab filter graying and the hover path.
--
-- Every window case runs through `case`, which puts back what the plan's snippets would otherwise
-- leave behind (addenda, Global): the holdings and daily stores, the Rollup key index, the saved
-- view's `timelineThing` (SetThing materializes the saved view), the session pick, the line cap and
-- the Character scope. It then returns the browser to History and closes it, because a window left
-- on screen keeps repainting under the suites that run next. The chunk has no global `time`, so the
-- seeds read os.time().

local function case(name, fn)
  test(name, function()
    local g, p = NS.db.global, NS.db.profile
    local holdings, daily, keys = g.holdings, g.daily, NS.Rollup and NS.Rollup._keys
    local view = p.savedView
    local hadView = type(view) == "table"
    local viewThing = hadView and view.timelineThing or nil
    local thing, maxLines = NS.Timeline and NS.Timeline.thing, p.settings.timelineMaxLines
    local char = NS.Browser:CurrentFilter().char
    if NS.Rollup then NS.Rollup._keys = nil end
    local ok, err = pcall(fn)
    if NS.Browser._search then NS.Browser._search:SetText("") end
    if NS.Browser.activeFilter then NS.Browser.activeFilter.text = nil end
    NS.Browser:SetCharSet(char)
    NS.Browser:SelectTab("History"); NS.Browser:Hide()
    g.holdings, g.daily = holdings, daily
    if NS.Rollup then NS.Rollup._keys = keys end
    if hadView then p.savedView = view; view.timelineThing = viewThing else p.savedView = nil end
    if NS.Timeline then NS.Timeline.thing = thing end
    p.settings.timelineMaxLines = maxLines
    if not ok then error(err, 0) end
  end)
end

local function seed()
  NS.db.global.holdings, NS.db.global.daily = {}, {}
  local t = os.time()
  NS.Holdings:ApplyMoney("Mock-Realm", 50000, t - 86400)
  NS.Holdings:ApplyMoney("Mock-Realm", 70000, t)
  NS.Holdings:ApplyMoney("Alt-Realm", 10000, t)
end

local function open()
  NS.Browser:Show()
  NS.Browser:SetCharSet(nil)
  NS.Browser:SelectTab("Timeline")
  NS.Timeline:SetThing("g")
  NS.Timeline:Layout(640, 320)
end

test("Timeline tab: registered between Insights and Holdings", function()
  local names = NS.Browser:Tabs()
  assertEqual(names[3], "Timeline"); assertEqual(names[4], "Holdings")
end)

case("Timeline tab: Total plus one line per holder; the Character filter narrows it", function()
  seed(); open()
  assertEqual(NS.Timeline:VisibleSeriesCount(), 3)
  NS.Browser:SetCharSet({ ["Alt-Realm"] = true })
  assertEqual(NS.Timeline:VisibleSeriesCount(), 2)
end)

case("Timeline tab: refresh twice recycles Lines and pooled rows", function()
  -- Review Focus 5 (the host half)
  seed(); open()
  local made = #NS.Timeline.chart.__madeLines
  local f1, a1 = NS.Pool.Counts(NS.Timeline.legendPool)
  local s1, b1 = NS.Pool.Counts(NS.Timeline.stripPool)
  assertTrue(a1 > 0, "the legend drew nothing")
  NS.Timeline:Refresh(); NS.Timeline:Layout(640, 320)
  assertEqual(#NS.Timeline.chart.__madeLines, made, "no new Line objects")
  local f2, a2 = NS.Pool.Counts(NS.Timeline.legendPool)
  local s2, b2 = NS.Pool.Counts(NS.Timeline.stripPool)
  assertEqual(f1 + a1, f2 + a2); assertEqual(s1 + b1, s2 + b2)
end)

case("Timeline tab: maxLines caps the holders drawn", function()
  NS.db.global.holdings, NS.db.global.daily = {}, {}
  for i = 1, 5 do NS.Holdings:ApplyMoney(("H%d-Realm"):format(i), i, os.time()) end
  NS.Schema:Set("settings.timelineMaxLines", 2)
  open()
  assertEqual(NS.Timeline:VisibleSeriesCount(), 3, "two holders and the Total")
end)

case("Timeline tab: typing in Search offers matching things, Gold first", function()
  seed(); open()
  NS.Browser._search:SetText("gol")
  NS.Browser._search:__fire("OnTextChanged")
  local keys = NS.Timeline:SuggestionKeys()
  assertEqual(keys[1], "g")
  NS.Browser._search:SetText(""); NS.Browser._search:__fire("OnTextChanged")
  assertEqual(#NS.Timeline:SuggestionKeys(), 0, "no text, no suggestion list")
end)

case("Timeline tab: the pick is remembered in the saved view", function()
  seed(); open()
  NS.Timeline:SetThing("c:3008")
  assertEqual(NS.Browser:ViewField("timelineThing"), "c:3008")
  NS.Timeline.thing = nil
  assertEqual(NS.Timeline:Thing(), "c:3008")
end)

case("Timeline tab: grays every filter but Search, Date and Character", function()
  seed(); open()
  local dd = NS.Browser._dd
  assertTrue(dd.date:IsEnabled()); assertTrue(dd.char:IsEnabled()); assertTrue(NS.Browser._search:IsEnabled())
  for _, k in ipairs({ "group", "dir", "bound", "quality", "type", "subtype", "source", "zone" }) do
    assertFalse(dd[k]:IsEnabled(), k .. " is not a Timeline filter")
  end
  assertFalse(NS.Browser._exportBtn:IsEnabled())
end)

case("Timeline tab: a hover with no model or index hides the tooltip and does not raise", function()
  seed(); open()
  NS.Timeline:OnHover(nil)
  NS.Timeline:OnHover(1)
end)

test("Schema: timelineMaxLines is a 2-16 slider under Interface, default 8", function()
  local row = NS.Schema:FindRow("settings.timelineMaxLines")
  assertTrue(row ~= nil)
  assertEqual(row.default, 8); assertEqual(row.min, 2); assertEqual(row.max, 16)
  assertEqual(row.group, "Interface"); assertEqual(row.widget, "Slider")
end)

case("Timeline tab: a live repaint drops a hover left up, so the next tick re-hovers on the new data", function()
  -- The chart only re-fires onHover when the nearest index changes; without the drop a coalesced
  -- HOLDINGS_CHANGED repaint under a resting cursor kept the old model's tooltip and crosshair.
  seed(); open()
  local chart, seen = NS.Timeline.chart, {}
  local real = NS.Timeline.OnHover
  NS.Timeline.OnHover = function(self, i) seen[#seen + 1] = i or false; return real(self, i) end
  local ok, err = pcall(function()
    local left, _, w = chart:GetPlotRect()
    local px = left + w
    assertTrue(chart:HoverAtPixel(px) ~= nil, "the hover lands on a point")
    local idx = chart:HoverIndex()
    NS.Timeline:Refresh(); NS.Timeline:Layout(640, 320)
    assertEqual(chart:HoverIndex(), nil, "the repaint drops the hover")
    assertEqual(seen[#seen], false, "and tells the host, which hides the tooltip")
    local n = #seen
    assertEqual(chart:HoverAtPixel(px), idx)
    assertEqual(#seen, n + 1, "the same pixel re-fires onHover against the new model")
  end)
  NS.Timeline.OnHover = real
  if not ok then error(err, 0) end
end)
