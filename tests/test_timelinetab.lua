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
-- views (SetThing materializes the Timeline's), the session pick, the session hidden-line set and
-- the line cap. It then returns the browser to History, forgets the Timeline's parked filter state
-- (its own Character scope and Search, P11) and closes it, because a window left on screen keeps
-- repainting under the suites that run next. The chunk has no global `time`, so the seeds read os.time().

local function case(name, fn)
  test(name, function()
    local g, p = NS.db.global, NS.db.profile
    local holdings, daily, keys = g.holdings, g.daily, NS.Rollup and NS.Rollup._keys
    local views = NS.Util.DeepCopy(p.savedViews)
    local thing, maxLines = NS.Timeline and NS.Timeline.thing, p.settings.timelineMaxLines
    local hidden = NS.Timeline and NS.Timeline.hidden
    if NS.Timeline then NS.Timeline.hidden = {} end
    if NS.Rollup then NS.Rollup._keys = nil end
    local ok, err = pcall(fn)
    if NS.Browser._search then NS.Browser._search:SetText("") end
    if NS.Browser.activeFilter then NS.Browser.activeFilter.text = nil end
    NS.Browser:SelectTab("History"); NS.Browser._forgetLive("Timeline"); NS.Browser:Hide()
    g.holdings, g.daily = holdings, daily
    if NS.Rollup then NS.Rollup._keys = keys end
    p.savedViews = views
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
  NS.Browser:SelectTab("Timeline")
  NS.Browser:SetCharSet(nil)   -- the Timeline's own Character scope (P11)
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
  -- The list is the shared Search autocomplete now (P9); tests/test_autocomplete.lua pins its pick.
  seed(); open()
  assertEqual(NS.Browser:Suggest("gol")[1].value, "g")
  assertEqual(#NS.Browser:Suggest(""), 0, "no text, no suggestion list")
end)

case("Timeline tab: the pick is remembered in the saved view", function()
  seed(); open()
  NS.Timeline:SetThing("c:3008")
  assertEqual(NS.Browser:ViewField("timelineThing", "Timeline"), "c:3008")
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
-- traced pane, drawn (chart, strip, legend), and then every region it made
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
  assertEqual(NS.Browser:ViewField("timelineTotalOnly", "Timeline"), true)
  legendButton("Mock-Realm"):__fire("OnClick")
  assertFalse(NS.Timeline.totalOnlyBtn.checked)
  assertEqual(NS.Browser:ViewField("timelineTotalOnly", "Timeline"), false)
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
  assertEqual(NS.Browser:ViewField("timelineTotalOnly", "Timeline"), true)
  assertEqual(NS.Browser:CaptureView().timelineTotalOnly, true, "a Save keeps it")
  NS.Timeline.hidden = {}   -- what a /reload leaves of the session set
  NS.Timeline:Refresh()
  assertEqual(NS.Timeline:VisibleSeriesCount(), 1)
  assertTrue(NS.Timeline.totalOnlyBtn.checked)
  NS.Timeline:SetTotalOnly(false)
  assertEqual(NS.Browser:ViewField("timelineTotalOnly", "Timeline"), false)
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

-- ── the in/out strip's tooltip (P8) ──

-- seed() writes closes only: today gets an in/out, yesterday keeps a close and no flow.
local function seedFlow(i, o)
  seed()
  local daily, today = NS.db.global.daily, NS.Ledger.DayKey(os.time())
  daily[today] = daily[today] or {}
  daily[today]["Mock-Realm"] = daily[today]["Mock-Realm"] or {}
  local cell = daily[today]["Mock-Realm"].g or {}
  daily[today]["Mock-Realm"].g = cell
  cell.i, cell.o = i, o
  return today
end

-- Records what the strip's hover puts on GameTooltip, and puts the methods back.
local function spyTooltip(fn)
  local tt, got = T.mocks.GameTooltip, { lines = {}, doubles = {}, hides = 0 }
  local names = { "SetOwner", "GetOwner", "AddLine", "AddDoubleLine", "Hide" }
  local saved = {}
  for _, n in ipairs(names) do saved[n] = rawget(tt, n) end
  tt.SetOwner = function(_, owner, anchor) got.owner, got.anchor = owner, anchor end
  tt.GetOwner = function() return got.owner end
  got.lineRGB = {}
  tt.AddLine = function(_, text, r, g, b)
    got.lines[#got.lines + 1] = text; got.lineRGB[#got.lines] = { r, g, b }
  end
  tt.AddDoubleLine = function(_, l, r, lr, lg, lb, rr, rg, rb)
    got.doubles[#got.doubles + 1] = { l = l, r = r, lc = { lr, lg, lb }, rc = { rr, rg, rb } }
  end
  tt.Hide = function(self) got.hides = got.hides + 1; self.__shown = false; return self end
  local ok, err = pcall(fn, got)
  for _, n in ipairs(names) do rawset(tt, n, saved[n]) end
  if not ok then error(err, 0) end
  return got
end

case("Timeline tab: hovering a day's strip column shows its Gained / Lost / Net, and OnLeave hides it", function()
  local today = seedFlow(20000, 5000)
  open()
  local bars = NS.Timeline.stripPool.active
  assertEqual(#bars, 1, "one hit region for the one day with a flow")
  local bar = bars[1]
  assertEqual(bar.flow.day, today)
  local G, L = NS.Constants.TIMELINE.GAIN, NS.Constants.TIMELINE.LOSS
  local got = spyTooltip(function(g)
    bar:__fire("OnEnter")
    assertTrue(g.owner == bar, "the tooltip belongs to the column")
    bar:__fire("OnLeave")
  end)
  assertEqual(got.lines[1], os.date("%d %b %Y", NS.TimelineModel.DayStart(today)) .. " \194\183 Total")
  assertEqual(#got.doubles, 3)
  assertEqual(got.doubles[1].l, "Gained"); assertEqual(got.doubles[1].r, "+" .. NS.Util.FormatMoney(20000))
  assertEqual(got.doubles[2].l, "Lost"); assertEqual(got.doubles[2].r, "-" .. NS.Util.FormatMoney(5000))
  assertEqual(got.doubles[3].l, "Net"); assertEqual(got.doubles[3].r, "+" .. NS.Util.FormatMoney(15000))
  assertEqual(got.doubles[1].rc[1], G[1]); assertEqual(got.doubles[2].rc[1], L[1])
  assertEqual(got.doubles[3].rc[2], G[2], "a positive net is green")
  assertTrue(got.hides >= 1, "OnLeave hides the tooltip")
end)

case("Timeline tab: the strip tooltip stays the Total's with lines hidden", function()
  seedFlow(20000, 5000)
  open()
  NS.Timeline:SetTotalOnly(true)
  legendButton(TOTAL):__fire("OnClick")
  NS.Timeline:Layout(640, 320)
  local bar = NS.Timeline.stripPool.active[1]
  local got = spyTooltip(function() bar:__fire("OnEnter") end)
  assertEqual(got.doubles[3].r, "+" .. NS.Util.FormatMoney(15000))
end)

case("Timeline tab: a day with no flow has no strip hit region; regions are pooled across redraws", function()
  seedFlow(20000, 5000)
  open()
  local before = {}
  for i, b in ipairs(NS.Timeline.stripPool.active) do
    before[i] = b
    assertTrue(b.flow.i > 0 or b.flow.o > 0, "every region is a day with a flow")
    assertTrue(b:GetScript("OnEnter") ~= nil and b:GetScript("OnLeave") ~= nil, "every bar is a hover region")
  end
  assertEqual(#before, #NS.Timeline.model.flows)
  local f1, a1 = NS.Pool.Counts(NS.Timeline.stripPool)
  for _ = 1, 3 do NS.Timeline:Refresh(); NS.Timeline:Layout(640, 320) end
  local f2, a2 = NS.Pool.Counts(NS.Timeline.stripPool)
  assertEqual(f1 + a1, f2 + a2, "no new frames across redraws")
  assertEqual(a2, a1)
  for i, b in ipairs(NS.Timeline.stripPool.active) do assertTrue(b == before[i], "the same frame comes back") end
end)

case("Timeline tab: a repaint under a strip tooltip re-shows it, and one whose day went hides it", function()
  seedFlow(20000, 5000)
  open()
  -- Refresh lays out at the pane's own size, which the mock answers as 0: give it one, so the repaint
  -- draws the strip as the client would.
  local pane = NS.Timeline.pane
  local gw, gh = rawget(pane, "GetWidth"), rawget(pane, "GetHeight")
  pane.GetWidth, pane.GetHeight = function() return 640 end, function() return 320 end
  local bar = NS.Timeline.stripPool.active[1]
  local got
  local ok, err = pcall(function() got = spyTooltip(function(g)
    bar:__fire("OnEnter")
    g.doubles = {}
    NS.Timeline:Refresh()
    assertEqual(#g.doubles, 3, "a live repaint re-shows the tooltip against the new data")
    local today = NS.Ledger.DayKey(os.time())
    local cell = NS.db.global.daily[today]["Mock-Realm"].g
    cell.i, cell.o = 0, 0
    NS.Timeline:Refresh(); NS.Timeline:Layout(640, 320)
  end) end)
  pane.GetWidth, pane.GetHeight = gw, gh
  if not ok then error(err, 0) end
  assertTrue(got.hides >= 1, "the day's region is gone, so its tooltip goes too")
  assertEqual(NS.Timeline.flowTipOwner, nil)
end)

case("Timeline tab: the chart's hover ending does not hide the strip's tooltip", function()
  seedFlow(20000, 5000)
  open()
  local bar = NS.Timeline.stripPool.active[1]
  local got = spyTooltip(function(g)
    bar:__fire("OnEnter")
    NS.Timeline:OnHover(nil)
    assertEqual(g.hides, 0, "the strip's tooltip stays up")
    NS.Timeline:OnHover(#NS.Timeline.model.hoverXs)
    assertTrue(g.owner == NS.Timeline.chart, "a chart hover takes the tooltip")
    assertEqual(NS.Timeline.flowTipOwner, nil)
    NS.Timeline:OnHover(nil)
  end)
  assertEqual(got.hides, 1, "and its end hides the chart's own")
end)

case("Timeline tab: smoother lines -- 6 px per point reaches the chart and the lines are 2 px (Total 2.5)", function()
  seed(); open()
  local chart = NS.Timeline.chart
  assertEqual(chart.__opts.pxPerPoint, 6, "the point spacing reaches the chart")
  for _, sr in ipairs(chart.__data.series) do
    if sr.thickness ~= 2.5 then assertEqual(sr.thickness, 2, "a holder line is 2 px") end
  end
  local top = 0
  for _, sr in ipairs(chart.__data.series) do if sr.thickness > top then top = sr.thickness end end
  assertEqual(top, 2.5, "Total keeps the heavier line")
end)

case("Timeline tab: the wider point spacing thins a 120-day series to fewer points", function()
  local Math = T.mocks.LibStub("LibKa0s-Widgets-1.0").ChartMath
  local width = 600
  local px = NS.Constants.TIMELINE.PX_PER_POINT
  assertEqual(px, 6)
  local old, new = Math.Budget(width, 2), Math.Budget(width, px)
  assertEqual(new, 100); assertTrue(new < old, "fewer points than the 2 px default")
  local pts = {}
  for i = 1, 120 do pts[i] = { x = i, y = (i == 60) and 500 or (i % 7) } end
  local out = Math.Downsample(pts, new)
  assertTrue(#out <= new and #out < 120, "the 120-day series is thinned")
  local hasSpike = false
  for _, p in ipairs(out) do if p.y == 500 then hasSpike = true end end
  assertTrue(hasSpike, "thinning keeps the spike")
end)

-- ── the legend's tooltip and spacing (P10) ──

case("Timeline tab: a legend entry's tooltip is the holder's color, its holding and the hint", function()
  seed()
  NS.db.global.holdings["Mock-Realm"].meta.classFile = "MAGE"
  open()
  local b = legendButton("Mock-Realm")
  local got = spyTooltip(function(g)
    b:__fire("OnEnter")
    assertTrue(g.owner == b, "the tooltip belongs to the entry")
    b:__fire("OnLeave")
  end)
  local cc = T.mocks.RAID_CLASS_COLORS.MAGE
  assertEqual(got.lines[1], "Mock-Realm")
  assertEqual(got.lineRGB[1][1], cc.r); assertEqual(got.lineRGB[1][3], cc.b)
  assertEqual(#got.doubles, 1)
  assertEqual(got.doubles[1].l, "Holding"); assertEqual(got.doubles[1].r, NS.Util.FormatMoney(70000))
  assertEqual(got.lines[2], "Click to hide/show")
  assertEqual(got.lineRGB[2][1], 0.5, "the hint is gray")
  assertTrue(got.hides >= 1, "OnLeave hides it")
  got = spyTooltip(function() legendButton(TOTAL):__fire("OnEnter") end)
  assertEqual(got.lines[1], "Total")
  assertEqual(got.lineRGB[1][1], 1); assertEqual(got.lineRGB[1][2], 0.82)
  assertEqual(got.doubles[1].l, "Holding"); assertEqual(got.doubles[1].r, NS.Util.FormatMoney(80000))
  NS.Browser:SetCharSet({ ["Alt-Realm"] = true })
  got = spyTooltip(function() legendButton(TOTAL):__fire("OnEnter") end)
  assertEqual(got.doubles[1].l, "Holding (all shown characters)", "the Total line is the filter's")
  assertEqual(got.doubles[1].r, NS.Util.FormatMoney(10000))
end)

case("Timeline tab: the Warband's legend tooltip wears the Warband's series color", function()
  seed()
  NS.Holdings:ApplyMoney(NS.Constants.WARBAND_HOLDER, 30000, os.time())
  open()
  local got = spyTooltip(function() legendButton(NS.Constants.WARBAND_HOLDER):__fire("OnEnter") end)
  local W = NS.Constants.TIMELINE.WARBAND
  assertEqual(got.lines[1], "Warband")
  assertEqual(got.lineRGB[1][1], W[1]); assertEqual(got.lineRGB[1][2], W[2]); assertEqual(got.lineRGB[1][3], W[3])
  assertEqual(got.doubles[1].r, NS.Util.FormatMoney(30000))
end)

-- Gives every legend label a nonzero width (6 px a glyph; the mock's font measures 0) and lays the
-- legend out again at `w`.
local function measuredLegend(w)
  for _, b in ipairs(NS.Timeline.legendPool.active) do
    b.fs.GetUnboundedStringWidth = function(s) return #(s:GetText() or "") * 6 end
  end
  NS.Timeline:Layout(w, 320)
  return NS.Timeline.legendButtons
end

local function legendGaps(btns)
  local gaps = {}
  for i = 2, #btns - 1 do
    local a, b = btns[i]:__lastPoint(), btns[i + 1]:__lastPoint()
    if a.y == b.y then gaps[#gaps + 1] = b.x - (a.x + btns[i]:GetWidth()) end
  end
  return gaps
end

case("Timeline tab: legend entries sit one even gap apart, the Total keeping its slot", function()
  seed()
  NS.Holdings:ApplyMoney("Third-Realm", 5000, os.time())
  open()
  local btns = measuredLegend(640)
  assertEqual(#btns, 4)
  assertEqual(btns[1]:__lastPoint().x, 0); assertEqual(btns[2]:__lastPoint().x, 120, "the Total's gap is today's")
  assertEqual(btns[2]:GetWidth(), #"Mock-Realm" * 6, "an entry is as wide as its label")
  local gaps = legendGaps(btns)
  assertEqual(#gaps, 2)
  assertTrue(gaps[1] > 0, "a real gap")
  assertEqual(gaps[1], gaps[2], "every character gap is the same")
end)

case("Timeline tab: the Warband's legend entry takes the same gap as a character's", function()
  seed()
  NS.Holdings:ApplyMoney(NS.Constants.WARBAND_HOLDER, 90000, os.time())
  open()
  local btns = measuredLegend(640)
  assertEqual(btns[2].key, NS.Constants.WARBAND_HOLDER, "the richest holder, first after the Total")
  assertEqual(btns[2]:GetWidth(), #"Warband" * 6)
  local gaps = legendGaps(btns)
  assertEqual(#gaps, 2)
  assertEqual(gaps[1], gaps[2], "Warband to the first character is the character-to-character gap")
end)

case("Timeline tab: a legend too wide for the pane wraps to a second row and the body makes room", function()
  seed()
  NS.Holdings:ApplyMoney("Third-Realm", 5000, os.time())
  open()
  local btns = measuredLegend(240)
  local first
  for _, b in ipairs(btns) do
    if b:__lastPoint().y == -16 then first = first or b end
  end
  assertTrue(first ~= nil, "an entry wrapped one legend row down")
  assertEqual(first:__lastPoint().x, 0, "the wrapped row starts at the left")
  assertEqual(btns[#btns]:__lastPoint().y, -16, "and the rest follow it on that row")
  assertEqual(NS.Timeline.legend:GetHeight(), 32, "the legend grew a row")
  -- The chart's bottom edge, not the strip's: the mock's CreateTexture hands back the frame itself,
  -- so the strip's axis texture clears the strip's own anchors on every repaint.
  local cp
  for _, p in ipairs(NS.Timeline.chart.__points) do if p.point == "BOTTOMRIGHT" then cp = p end end
  assertEqual(cp.y, 56 + 32 + 2 * 6, "the plot sits above the strip and both legend rows")
  for _, b in ipairs(btns) do
    local p = b:__lastPoint()
    assertTrue(p.x + b:GetWidth() <= 236, "every entry fits its row")
  end
  measuredLegend(640)
  assertEqual(NS.Timeline.legend:GetHeight(), 16, "and back to one row when it fits")
end)
