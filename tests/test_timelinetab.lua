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
-- view's `timelineThing` and `timelineTotalOnly` (SetThing materializes the saved view), the session
-- pick, the session hidden-line set, the line cap and the Character scope. It then returns the browser to History and closes it, because a window left
-- on screen keeps repainting under the suites that run next. The chunk has no global `time`, so the
-- seeds read os.time().

local function case(name, fn)
  test(name, function()
    local g, p = NS.db.global, NS.db.profile
    local holdings, daily, keys = g.holdings, g.daily, NS.Rollup and NS.Rollup._keys
    local view = p.savedView
    local hadView = type(view) == "table"
    local viewThing = hadView and view.timelineThing or nil
    local viewTotalOnly = hadView and view.timelineTotalOnly or nil
    local thing, maxLines = NS.Timeline and NS.Timeline.thing, p.settings.timelineMaxLines
    local hidden = NS.Timeline and NS.Timeline.hidden
    if NS.Timeline then NS.Timeline.hidden = {} end
    local char = NS.Browser:CurrentFilter().char
    if NS.Rollup then NS.Rollup._keys = nil end
    local ok, err = pcall(fn)
    if NS.Browser._search then NS.Browser._search:SetText("") end
    if NS.Browser.activeFilter then NS.Browser.activeFilter.text = nil end
    NS.Browser:SetCharSet(char)
    NS.Browser:SelectTab("History"); NS.Browser:Hide()
    g.holdings, g.daily = holdings, daily
    if NS.Rollup then NS.Rollup._keys = keys end
    if hadView then
      p.savedView = view; view.timelineThing = viewThing; view.timelineTotalOnly = viewTotalOnly
    else p.savedView = nil end
    if NS.Timeline then NS.Timeline.thing, NS.Timeline.hidden = thing, hidden end
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

-- Smoke LED-9: the owner saw faint green text ("Cou...", "<Tr...") over the Holdings header and over
-- History rows after visiting the Timeline. A Timeline region parented outside its pane would stay
-- on screen once the pane hides, so the Timeline is built fresh under tests/region_trace.lua on a
-- traced pane, drawn (chart, strip, legend, open suggestion list), and then every region it made
-- must read as hidden by the client's rule once History, and then Holdings, is the tab shown.
local RT = dofile("tests/region_trace.lua")

case("Timeline tab: nothing it draws stays visible over History or Holdings (LED-9)", function()
  seed()
  NS.Browser:Show()
  local win, TL = NS.Browser:GetWindow(), NS.Timeline
  local savedPane, saved = win.panes.Timeline, {}
  for k, v in pairs(TL) do
    if type(k) == "string" and k:match("^%l") and type(v) ~= "function" then saved[k] = v end
  end
  for k in pairs(saved) do TL[k] = nil end
  local ok, err = pcall(function()
    local made = RT.Trace(function()
      local pane = T.mocks.CreateFrame("Frame", nil, win)
      pane:Hide(); win.panes.Timeline = pane
      NS.Browser:SetCharSet(nil)
      NS.Browser:SelectTab("Timeline")
      TL:SetThing("g"); TL:Layout(640, 320)
      TL:RenderSuggestions("gol")
    end)
    assertTrue(RT.ShownText(made) > 0, "the Timeline drew labels while it was the tab shown")
    for _, tab in ipairs({ "History", "Holdings" }) do
      NS.Browser:SelectTab(tab)
      local leaks = RT.Leaks(made)
      assertEqual(#leaks, 0, tab .. " shown, still visible: " .. table.concat(leaks, ", "))
    end
  end)
  win.panes.Timeline = savedPane
  for k, v in pairs(TL) do
    if type(k) == "string" and k:match("^%l") and type(v) ~= "function" then TL[k] = nil end
  end
  for k, v in pairs(saved) do TL[k] = v end
  if not ok then error(err, 0) end
end)

-- ── line toggles (P8): the Total-only toggle and the click-to-toggle legend ──

local function legendButton(key)
  for _, b in ipairs(NS.Timeline.legendButtons or {}) do if b.key == key then return b end end
end

local TOTAL = "__total"

case("Timeline tab: one legend button per series, Total first, reused across rebuilds", function()
  seed(); open()
  local btns = NS.Timeline.legendButtons
  assertEqual(#btns, #NS.Timeline.model.series)
  assertEqual(btns[1].key, TOTAL)
  local b1 = btns[1]
  NS.Timeline:ToggleSeries("Alt-Realm")
  assertEqual(#NS.Timeline.legendButtons, 3, "a hidden line keeps its legend entry")
  local free, active = NS.Pool.Counts(NS.Timeline.legendPool)
  assertEqual(free + active, 3, "the toggle rebuilt the legend from the pool")
  assertTrue(NS.Timeline.legendButtons[1] == b1 or NS.Timeline.legendButtons[2] == b1
    or NS.Timeline.legendButtons[3] == b1, "a pooled button came back")
end)

case("Timeline tab: a legend click hides the line, dims its entry and a second click restores it", function()
  seed(); open()
  legendButton("Alt-Realm"):__fire("OnClick")
  assertEqual(NS.Timeline:VisibleSeriesCount(), 2)
  local _, _, _, a = legendButton("Alt-Realm").fs:GetTextColor()
  assertEqual(a, 0.4, "a hidden entry is dimmed")
  assertEqual(#NS.Timeline.chart.__data.series, 2, "the chart draws only what is visible")
  legendButton("Alt-Realm"):__fire("OnClick")
  assertEqual(NS.Timeline:VisibleSeriesCount(), 3)
  _, _, _, a = legendButton("Alt-Realm").fs:GetTextColor()
  assertEqual(a, 1)
end)

case("Timeline tab: Total only hides every holder; off restores the set shown before", function()
  seed(); open()
  NS.Timeline:ToggleSeries("Alt-Realm")
  assertFalse(NS.Timeline:TotalOnlyShown())
  NS.Timeline:SetTotalOnly(true)
  assertEqual(NS.Timeline:VisibleSeriesCount(), 1)
  assertTrue(NS.Timeline:TotalOnlyShown()); assertTrue(NS.Timeline.totalOnlyBtn.checked)
  NS.Timeline:SetTotalOnly(false)
  assertEqual(NS.Timeline:VisibleSeriesCount(), 2)
  assertTrue(NS.Timeline:IsHidden("Alt-Realm")); assertFalse(NS.Timeline:IsHidden("Mock-Realm"))
  assertFalse(NS.Timeline.totalOnlyBtn.checked)
end)

case("Timeline tab: hiding every holder by hand reads as Total only, and showing one clears it", function()
  seed(); open()
  legendButton("Alt-Realm"):__fire("OnClick")
  legendButton("Mock-Realm"):__fire("OnClick")
  assertTrue(NS.Timeline.totalOnlyBtn.checked)
  assertEqual(NS.Browser:ViewField("timelineTotalOnly"), true)
  legendButton("Mock-Realm"):__fire("OnClick")
  assertFalse(NS.Timeline.totalOnlyBtn.checked)
  assertEqual(NS.Browser:ViewField("timelineTotalOnly"), false)
  -- under Total only, clicking a holder shows that one line and leaves the rest hidden
  NS.Timeline:SetTotalOnly(true)
  legendButton("Alt-Realm"):__fire("OnClick")
  assertFalse(NS.Timeline:IsHidden("Alt-Realm")); assertTrue(NS.Timeline:IsHidden("Mock-Realm"))
  assertFalse(NS.Timeline.totalOnlyBtn.checked)
  -- the toggle button itself
  NS.Timeline.totalOnlyBtn:__fire("OnClick")
  assertTrue(NS.Timeline:TotalOnlyShown())
end)

-- Where the strip's bars sit, in order: the in/out strip is the Total's flow whatever is hidden.
local function stripXs()
  local out = {}
  for i, bar in ipairs(NS.Timeline.stripPool.active) do out[i] = bar:__lastPoint().x end
  return out
end

case("Timeline tab: every line hidden shows the empty state, not an axis", function()
  -- Review Focus 1
  seed()
  -- seed() writes closes only; give today an in/out so the strip has a bar to keep
  local daily, today = NS.db.global.daily, NS.Ledger.DayKey(os.time())
  daily[today] = daily[today] or {}
  daily[today]["Mock-Realm"] = daily[today]["Mock-Realm"] or {}
  local cell = daily[today]["Mock-Realm"].g or {}
  daily[today]["Mock-Realm"].g = cell
  cell.i, cell.o = 20000, 5000
  open()
  local xs = stripXs()
  assertTrue(#xs > 0, "the strip draws with lines shown")
  NS.Timeline:SetTotalOnly(true)
  legendButton(TOTAL):__fire("OnClick")
  NS.Timeline:Layout(640, 320)
  assertEqual(NS.Timeline:VisibleSeriesCount(), 0)
  assertTrue(NS.Timeline.emptyMsg:IsShown())
  assertEqual(NS.Timeline.emptyMsg:GetText(), "All lines hidden \226\128\148 click a legend entry to show it.")
  assertEqual(NS.Timeline.chart:GetPlotRect(), nil, "no axes drawn")
  local hiddenXs = stripXs()
  assertEqual(#hiddenXs, #xs, "the in/out strip stays with every line hidden")
  for i = 1, #xs do assertEqual(hiddenXs[i], xs[i], "and its bars do not move") end
  assertEqual(#NS.Timeline.legendButtons, 3, "the legend stays to bring a line back")
  assertFalse(NS.Timeline.totalOnlyBtn.checked, "the Total is hidden too")
  NS.Timeline:OnHover(1)
  legendButton(TOTAL):__fire("OnClick")
  NS.Timeline:Layout(640, 320)
  assertFalse(NS.Timeline.emptyMsg:IsShown())
  assertTrue(NS.Timeline.chart:GetPlotRect() ~= nil)
end)

case("Timeline tab: the hidden set survives a change of thing and range, and ignores absent holders", function()
  seed(); open()
  NS.Timeline:ToggleSeries("Alt-Realm")
  NS.Timeline.hidden["Gone-Realm"] = true
  NS.Timeline:SetThing("c:3008")
  NS.Timeline:SetThing("g")
  assertTrue(NS.Timeline:IsHidden("Alt-Realm"))
  assertEqual(NS.Timeline:VisibleSeriesCount(), 2)
  NS.Timeline:ToggleSeries("Mock-Realm")
  assertTrue(NS.Timeline:TotalOnlyShown(), "a holder not in this chart does not count")
end)

case("Timeline tab: Total only is remembered in the saved view, the per-line set is not", function()
  -- Review Focus 3
  seed(); open()
  NS.Timeline:SetTotalOnly(true)
  assertEqual(NS.Browser:ViewField("timelineTotalOnly"), true)
  assertEqual(NS.Browser:CaptureView().timelineTotalOnly, true, "a Save keeps it")
  NS.Timeline.hidden = {}   -- what a /reload leaves of the session set
  NS.Timeline:Refresh()
  assertEqual(NS.Timeline:VisibleSeriesCount(), 1)
  assertTrue(NS.Timeline.totalOnlyBtn.checked)
  NS.Timeline:SetTotalOnly(false)
  assertEqual(NS.Browser:ViewField("timelineTotalOnly"), false)
  assertEqual(NS.Timeline:VisibleSeriesCount(), 3)
end)

case("Timeline tab: the hover tooltip lists only the visible lines", function()
  seed(); open()
  NS.Timeline:ToggleSeries("Alt-Realm")
  local tt, labels = T.mocks.GameTooltip, {}
  local saved = rawget(tt, "AddDoubleLine")
  tt.AddDoubleLine = function(_, l) labels[#labels + 1] = l end
  local ok, err = pcall(function() NS.Timeline:OnHover(#NS.Timeline.model.hoverXs) end)
  tt.AddDoubleLine = saved
  if not ok then error(err, 0) end
  local got = table.concat(labels, ",")
  assertTrue(got:find("Total", 1, true) ~= nil, got)
  assertTrue(got:find("Alt", 1, true) == nil, "a hidden line is not in the tooltip: " .. got)
end)
