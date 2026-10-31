-- tests/test_browser_filterbar.lua — the History window's filter bar under the timeline ledger: per-tab
-- filters and holders, the one-line controls, the bar filling the window and the Character filter.
-- Moved out of tests/test_browser.lua, whose withFixture, withSettings and withGripWindow are copied below.
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local B = NS.Browser

local function withFixture(records, fn)
  local savedTest, savedViews = NS.State.testRecords, NS.Util.DeepCopy(NS.db.profile.savedViews)
  local savedFilter, savedDd = B.activeFilter, B._dd
  NS.State.testRecords = records
  local ok, err = pcall(fn)
  NS.State.testRecords, NS.db.profile.savedViews = savedTest, savedViews
  B.activeFilter, B._dd = savedFilter, savedDd
  if not ok then error(err, 0) end
end

local function withSettings(patch, fn)
  local s = NS.db.profile.settings
  local saved = {}
  for k, v in pairs(patch) do saved[k] = s[k]; s[k] = v end
  local ok, err = pcall(fn)
  for k in pairs(patch) do s[k] = saved[k] end
  if not ok then error(err) end
end

local function withGripWindow(fn)
  withSettings({ visibility = "always", locked = false }, function()
    local s = NS.db.profile.settings
    local savedWindow = s.window
    B:Show()
    local f = B:GetWindow()
    local gw, gh = f:GetWidth(), f:GetHeight()
    local ok, err = pcall(fn, f)
    f:SetSize(gw, gh)
    s.window = savedWindow
    B:Hide()
    if not ok then error(err, 0) end
  end)
end

-- ── timeline ledger P3: date options, per-tab filters, holders, the remembered pick ────────────
-- Every case that opens the window does it under visibility "always" (withSettings) and leaves
-- History selected; savedView and global.holdings are parked and put back.

test("Browser: date options offer 90 days and 1 year after 30 days", function()
  local vals = {}
  for _, o in ipairs(NS.Browser._dateOptions) do vals[#vals + 1] = o.value end
  assertEqual(table.concat(vals, ","), "all,today,7d,30d,90d,1y")
end)

test("Browser: _filterHonored - no set honors everything, a set honors only its keys", function()
  local f = NS.Browser._filterHonored
  assertTrue(f(nil, "bound")); assertTrue(f({}, "bound"))
  assertTrue(f({ filters = { date = true } }, "date"))
  assertFalse(f({ filters = { date = true } }, "bound"))
  assertFalse(f({ filters = { date = true } }, "search"))
end)

test("Browser: a tab grays the controls it does not honor, and History restores them", function()
  NS.Browser:RegisterTab{ name = "ZGray", order = 98, filters = { date = true }, build = function() end }
  local ok, err = pcall(withSettings, { visibility = "always" }, function()
    NS.Browser:Show()
    NS.Browser:SelectTab("ZGray")
    local dd = NS.Browser._dd
    assertTrue(dd.date:IsEnabled())
    assertFalse(dd.bound:IsEnabled()); assertFalse(dd.char:IsEnabled()); assertFalse(dd.group:IsEnabled())
    assertFalse(NS.Browser._search:IsEnabled()); assertFalse(NS.Browser._exportBtn:IsEnabled())
    assertTrue(dd.bound:IsShown(), "grayed, never hidden: the bar does not reflow between tabs")
    NS.Browser:SelectTab("History")
    assertTrue(dd.bound:IsEnabled()); assertTrue(NS.Browser._search:IsEnabled())
    assertTrue(NS.Browser._exportBtn:IsEnabled())
  end)
  NS.Browser:SelectTab("History")
  NS.Browser:_UnregisterTabForTest("ZGray")
  NS.Browser:Hide()
  if not ok then error(err, 0) end
end)

test("Browser: the Holdings tab grays Date, Source, Bound and Zone, and keeps Group live", function()
  local ok, err = pcall(withSettings, { visibility = "always" }, function()
    NS.Browser:Show(); NS.Browser:SelectTab("Holdings")
    local dd = NS.Browser._dd
    for _, k in ipairs({ "date", "source", "bound", "zone", "dir" }) do
      assertFalse(dd[k]:IsEnabled(), k .. " is not a Holdings filter")
    end
    for _, k in ipairs({ "quality", "type", "subtype", "char", "group" }) do
      assertTrue(dd[k]:IsEnabled(), k .. " is a Holdings filter")
    end
  end)
  NS.Browser:SelectTab("History")
  NS.Browser:Hide()
  if not ok then error(err, 0) end
end)

test("Browser: a holders tab lists holders, with the warband as Warband", function()
  local savedHoldings = NS.db.global.holdings
  NS.db.global.holdings = {}
  local ok, err = pcall(function()
    local W = NS.Constants.WARBAND_HOLDER
    NS.Holdings:ApplyMoney(W, 5, 1)
    NS.Holdings:ApplyMoney("Alt-Realm", 5, 1)
    local labels = {}
    for _, o in ipairs(NS.Browser._options.char(true)) do labels[o.value] = o.label end
    assertTrue(labels[W] ~= nil and labels[W]:find("Warband", 1, true) ~= nil)
    assertTrue(labels["Alt-Realm"] ~= nil)
    assertTrue(labels["current"] ~= nil, "the Current preset stays")
  end)
  NS.db.global.holdings = savedHoldings
  if not ok then error(err, 0) end
end)

test("Browser: a holder picked on Holdings stays on Holdings; History keeps its own Character scope", function()
  -- One Character control, two option sources. The warband is a holder and never a history row, so
  -- carried to History it would filter every row out under a raw-key label. Since P11 each tab keeps
  -- its own Character scope, so the pick never reaches History at all.
  local g = NS.db.global
  local savedHoldings, savedHistory = g.holdings, g.history
  local savedChar = B.activeFilter and B.activeFilter.char
  local W = NS.Constants.WARBAND_HOLDER
  g.holdings = {}
  g.history = {
    { ts = 100, itemID = 1, quality = 2, source = "KILL", char = "Alt-Realm" },
    { ts = 200, itemID = 2, quality = 2, source = "KILL", char = "Alt-Realm" },
  }
  local ok, err = pcall(withSettings, { visibility = "always" }, function()
    NS.Holdings:ApplyMoney(W, 5, 1)
    B:Show(); B:SelectTab("History")
    B:SetCharSet(nil)
    B:SelectTab("Holdings")
    B:SetCharSet({ [W] = true })
    assertTrue(B.activeFilter.char[W], "a Holdings pick")
    B:SelectTab("History")
    local char = B.activeFilter.char
    assertTrue(char == nil or not char[W], "History's own scope comes back, without the warband")
    assertFalse(NS.Browser._dd.char._selected[W], "and the dropdown follows")
    local rows = NS.Database:QueryList(NS.BrowserTable:CurrentRecords(), NS.BrowserTable.filter)
    assertEqual(#rows, 2, "the filter does not hide every row")
    B:SelectTab("Holdings")
    assertTrue(B.activeFilter.char and B.activeFilter.char[W], "Holdings keeps its pick")
    B:SetCharSet(nil)
  end)
  B:SelectTab("History")
  B:SetCharSet(savedChar)
  B:Hide()
  g.holdings, g.history = savedHoldings, savedHistory
  if not ok then error(err, 0) end
end)

test("Browser: SetViewField remembers a field with no Save, from a copy of the stock view", function()
  local p = NS.db.profile
  local saved = p.savedViews
  p.savedViews = nil
  local ok, err = pcall(function()
    NS.Browser:SetViewField("timelineThing", "c:3008", "Timeline")
    assertEqual(NS.Browser:ViewField("timelineThing", "Timeline"), "c:3008")
    local slot = p.savedViews.Timeline
    assertEqual(slot.groupBy, NS.Browser._stockView.groupBy, "everything else is stock")
    assertTrue(slot ~= NS.Browser._stockView, "a copy, never the stock table itself")
    assertEqual(NS.Browser._stockView.timelineThing, nil)
    assertEqual(p.savedViews.History, nil, "only the named tab's view is written")
  end)
  p.savedViews = saved
  if not ok then error(err, 0) end
end)

test("Browser: CaptureView on the Timeline keeps its remembered pick", function()
  local p = NS.db.profile
  local saved = NS.Util.DeepCopy(p.savedViews)
  p.savedViews = nil
  local ok, err = pcall(withSettings, { visibility = "always" }, function()
    NS.Browser:Show(); NS.Browser:SelectTab("Timeline")
    NS.Browser:SetViewField("timelineThing", "i:7", "Timeline")
    assertEqual(NS.Browser:CaptureView().timelineThing, "i:7")
    NS.Browser:SelectTab("History")
    assertEqual(NS.Browser:CaptureView().timelineThing, nil, "History's view carries no Timeline field")
  end)
  NS.Browser:SelectTab("History"); NS.Browser:Hide()
  p.savedViews = saved
  if not ok then error(err, 0) end
end)

test("Browser: DateRange reads the Date dropdown, all when there is none", function()
  local ok, err = pcall(withSettings, { visibility = "always" }, function()
    NS.Browser:Show()
    NS.Browser._dd.date:SelectValue("90d")
    assertEqual(NS.Browser:DateRange(), "90d")
    NS.Browser._dd.date:SelectValue("all")
    assertEqual(NS.Browser:DateRange(), "all")
  end)
  NS.Browser:Hide()
  if not ok then error(err, 0) end
end)

-- ── One-line filter controls (timeline-ledger P4 Task 1) ───────────────────────────────────────
-- Owner feedback: "Direction: 2 selected" and "Quality: Common+" wrapped onto a second line inside
-- their dropdowns. Each control is now as wide as the widest label it can show, its label never
-- wraps, Direction and Bound share one width, and the window floor is what the two rows need.

local FILTER_DD = { "group", "dir", "date", "bound", "quality", "type", "subtype", "source", "zone",
                    "char" }
local ROW2_DD = { "date", "bound", "quality", "type", "subtype", "source", "zone", "char" }

test("filter bar: every dropdown label is one non-wrapping line", function()
  -- red under: the library's collapsed label left at the client default, which wraps.
  withGripWindow(function()
    for _, k in ipairs(FILTER_DD) do
      local fs = B._dd[k].text
      assertEqual(fs:GetWordWrap(), false, k .. ": the label must not word-wrap")
      assertEqual(fs:GetMaxLines(), 1, k .. ": the label is one line")
    end
  end)
end)

test("filter bar: Direction and Bound are the same width", function()
  -- red under: the fixed 104 / 96 widths the bar was built with.
  withGripWindow(function()
    assertEqual(B._dd.dir:GetWidth(), B._dd.bound:GetWidth())
    -- The mock's CreateTexture hands back the frame itself, so the library's 12px arrow lands on the
    -- dropdown's own size; only a width set AFTER the build (the fit pass) reads back here.
    assertTrue(B._dd.dir:GetWidth() >= 104, "Direction keeps at least its shipped width")
  end)
end)

test("filter bar: each width covers the widest label that control can show", function()
  -- A 6px-per-character measurer stands in for the client's font metrics, which the mock answers 0.
  -- red under: widths that ignore the labels (the old fixed table).
  local function measure(_, text) return #text * 6 end
  local w, pad = B._filterWidths(measure), B._DD_PAD
  local function covers(key, label)
    assertTrue(w[key] >= #label * 6 + pad, key .. " must fit '" .. label .. "'")
  end
  covers("dir", "Direction: 3 selected")
  covers("bound", "Warbound Until Equipped")
  covers("quality", "Quality: " .. NS.Item.QualityLabel(2) .. "+")
  covers("quality", "Quality: 9 selected")
  covers("char", "Character: Current")
  covers("group", "Group: Character")
  covers("source", "Source: All")
  assertEqual(w.dir, w.bound, "Direction and Bound share the larger width")
  assertEqual(w.group, w.date, "Group stays aligned over the Date dropdown below it")
  -- Never narrower than the widths the bar shipped with, even when the font measures nothing.
  local floor = B._filterWidths(function() return 0 end)
  for _, k in ipairs(FILTER_DD) do assertTrue(w[k] >= floor[k], k .. " never shrinks below its floor") end
end)

test("filter bar: the window floor fits both rows at the built widths", function()
  withGripWindow(function()
    local dd, gap, margins = B._dd, 8, 12
    local row2 = 0
    for _, k in ipairs(ROW2_DD) do row2 = row2 + dd[k]:GetWidth() end
    row2 = row2 + (#ROW2_DD - 1) * gap + gap + B._exportBtn:GetWidth()
    assertTrue(B._minW >= row2 + margins, "row 2 (eight dropdowns + Export) must fit the floor")
    local row1 = dd.group:GetWidth() + gap + dd.dir:GetWidth() + gap + B._SEARCH_MIN
      + gap + B._exportBtn:GetWidth()   -- the Save/Reset/Clear cluster spans Export's width
    assertTrue(B._minW >= row1 + margins, "row 1 (Group, Direction, Search, the cluster) must fit")
    assertEqual(B._minW, B:MinWidth(), "the frame floor is the measured toolbar floor")
  end)
end)

test("filter bar: a saved window narrower than the floor is widened on restore", function()
  -- An older build saved a smaller size; restoring it must clamp to the new minimum.
  withGripWindow(function(f)
    NS.db.profile.settings.window = { point = "CENTER", x = 0, y = 0, w = 600, h = 200 }
    B:AdoptProfile()
    assertEqual(f:GetWidth(), B._minW)
    assertEqual(f:GetHeight(), B.SKIN.minH)
  end)
end)

-- ── The filter bar fills the window (timeline-ledger P6 Task 3) ────────────────────────────────
-- Owner feedback: the controls stopped ~120px short of the right border while the left gap was
-- ~6px. Row 2 (eight dropdowns + Export) now spans the bar exactly: every control keeps its
-- measured base width b_i and is scaled by ONE ratio r = A / sum(b_i), A = the bar width less the
-- inter-control gaps, floored at 1; Export takes the rounding remainder. Row 1 sits on row 2's grid.

local LAYOUT_ROW2 = { "date", "bound", "quality", "type", "subtype", "source", "zone", "char",
                      "export" }
local function sixPx(_, text) return #text * 6 end

-- The bar width at which row 2 exactly fits its base widths (r == 1).
local function baseBarWidth(widths)
  local L = B._filterBarLayout(widths, 0)
  local sum = 0
  for _, k in ipairs(LAYOUT_ROW2) do sum = sum + L.base[k] end
  return sum + (#LAYOUT_ROW2 - 1) * B._FILTER_GAP
end

local function rightEdge(L) return L.x.export + L.w.export end

test("filter bar layout: at the base width r == 1 and row 2 ends at the bar's right edge", function()
  -- red under: the static Export that stopped short of the right border.
  local widths = B._filterWidths(sixPx)
  local barW = baseBarWidth(widths)
  local L = B._filterBarLayout(widths, barW)
  assertEqual(L.r, 1)
  for _, k in ipairs(LAYOUT_ROW2) do assertEqual(L.w[k], L.base[k], k .. " keeps its base width") end
  assertEqual(L.x.date, 0, "row 2 starts at the bar's left edge (the window's left margin)")
  assertEqual(rightEdge(L), barW, "row 2 ends at the bar's right edge: right gap == left gap")
  assertEqual(L.base.export, 120, "Export's base width is its 120px floor")
end)

test("filter bar layout: a wider window scales every control by the same ratio", function()
  local widths = B._filterWidths(sixPx)
  local barW = baseBarWidth(widths) + 300
  local L = B._filterBarLayout(widths, barW)
  local gaps, sum = (#LAYOUT_ROW2 - 1) * B._FILTER_GAP, 0
  for _, k in ipairs(LAYOUT_ROW2) do sum = sum + L.base[k] end
  local r = (barW - gaps) / sum
  assertTrue(math.abs(L.r - r) < 1e-9, "r = available / sum of base widths")
  assertTrue(L.r > 1, "the controls grow")
  for i, k in ipairs(LAYOUT_ROW2) do
    if i < #LAYOUT_ROW2 then
      assertEqual(L.w[k], math.floor(L.base[k] * r), k .. " is floor(b * r)")
    else
      assertTrue(L.w[k] >= math.floor(L.base[k] * r), "Export takes the rounding remainder")
      assertTrue(L.w[k] - L.base[k] * r < #LAYOUT_ROW2, "the remainder is only rounding")
    end
  end
  -- Each control starts one gap after the previous one ends; row 2 ends exactly at the right edge.
  for i = 2, #LAYOUT_ROW2 do
    local p, k = LAYOUT_ROW2[i - 1], LAYOUT_ROW2[i]
    assertEqual(L.x[k], L.x[p] + L.w[p] + B._FILTER_GAP, k .. " sits one gap after " .. p)
  end
  assertEqual(L.x.date, 0)
  assertEqual(rightEdge(L), barW, "right gap == left gap at any width")
end)

test("filter bar layout: row 1 sits on row 2's grid", function()
  local widths = B._filterWidths(sixPx)
  for _, extra in ipairs({ 0, 300, 457 }) do
    local L = B._filterBarLayout(widths, baseBarWidth(widths) + extra)
    local G = B._FILTER_GAP
    assertEqual(L.x.group, L.x.date); assertEqual(L.w.group, L.w.date)
    assertEqual(L.x.dir, L.x.bound); assertEqual(L.w.dir, L.w.bound)
    -- Save · Reset · Clear span exactly Export's x-range, gaps G, the three widths equal (the
    -- left-most absorbs at most 2px of rounding).
    assertEqual(L.x.save, L.x.export)
    assertEqual(L.x.reset, L.x.save + L.w.save + G)
    assertEqual(L.x.clear, L.x.reset + L.w.reset + G)
    assertEqual(L.x.clear + L.w.clear, rightEdge(L), "the cluster ends where Export ends")
    assertEqual(L.w.reset, L.w.clear)
    assertTrue(L.w.save - L.w.clear >= 0 and L.w.save - L.w.clear <= 2, "three equal buttons")
    -- The search box fills between Direction and the cluster.
    assertEqual(L.x.search, L.x.dir + L.w.dir + G)
    assertEqual(L.x.search + L.w.search, L.x.save - G)
    assertTrue(L.w.search >= B._SEARCH_MIN, "the search box keeps its minimum")
  end
end)

test("filter bar layout: a bar narrower than the base never shrinks a control", function()
  local widths = B._filterWidths(sixPx)
  local L = B._filterBarLayout(widths, baseBarWidth(widths) - 200)
  assertEqual(L.r, 1)
  for _, k in ipairs(LAYOUT_ROW2) do assertEqual(L.w[k], L.base[k], k .. " stays at its base") end
end)

-- A fresh bar built into a scratch host, with every FontString measuring 6px a character (the
-- mock's font measures 0), so the base widths are real measurements. The window's singleton bar
-- state is put back afterwards.
local function withMeasuredBar(fn)
  local saved = {}
  local KEYS = { "_dd", "_search", "_onSearchText", "_autocomplete", "_exportBtn", "_ddWidths", "_bar", "_barCtl",
                 "_barW" }
  for _, k in ipairs(KEYS) do saved[k] = B[k] end
  local mocks = T.mocks
  local realCreateFrame = mocks.CreateFrame
  mocks.CreateFrame = function(...)
    local f = realCreateFrame(...)
    local realCFS = f.CreateFontString
    f.CreateFontString = function(self, ...)
      local fs = realCFS(self, ...)
      fs.GetUnboundedStringWidth = function(s) return #(s:GetText() or "") * 6 end
      return fs
    end
    return f
  end
  local ok, err = pcall(function()
    local host = realCreateFrame("Frame")
    B:BuildFilterBar(host)
    mocks.CreateFrame = realCreateFrame
    fn(host)
  end)
  mocks.CreateFrame = realCreateFrame
  for _, k in ipairs(KEYS) do B[k] = saved[k] end
  if not ok then error(err, 0) end
end

local function placed(ctl)
  local p = ctl:__lastPoint()
  return p.x, ctl:GetWidth(), p
end

test("filter bar: the built bar fills the bar width at the base width and 300px wider", function()
  withMeasuredBar(function(host)
    local widths = B._ddWidths
    assertTrue(widths.char > 146, "the scratch build measured its labels (6px a character)")
    for _, extra in ipairs({ 0, 300 }) do
      local barW = baseBarWidth(widths) + extra
      B:LayoutFilterBar(barW)
      local L = B._filterBarLayout(widths, barW)
      local ctl = { group = B._dd.group, dir = B._dd.dir, search = B._search,
                    export = B._exportBtn }
      for _, k in ipairs(LAYOUT_ROW2) do ctl[k] = ctl[k] or B._dd[k] end
      for k, c in pairs(ctl) do
        local x, w, p = placed(c)
        assertEqual(p.point, "TOPLEFT", k .. " is anchored by its top-left corner")
        assertEqual(p.relativeTo, host, k .. " is anchored to the bar itself")
        assertEqual(x, L.x[k], k .. " x at +" .. extra)
        assertEqual(w, L.w[k], k .. " width at +" .. extra)
      end
      local ex, ew = placed(B._exportBtn)
      assertEqual(ex + ew, barW, "Export ends at the bar's right edge at +" .. extra)
      local dx = placed(B._dd.date)
      assertEqual(dx, 0, "Date starts at the bar's left edge")
      if extra == 0 then assertEqual(L.r, 1) end
    end
  end)
end)

test("filter bar: resizing the window re-lays the bar out to its new width", function()
  -- red under: a bar laid out once at build time, which leaves the gap on the right as it widens.
  withGripWindow(function(f)
    local w = B._minW + 300
    f:SetSize(w, B.SKIN.minH)
    f:__fire("OnSizeChanged", w, B.SKIN.minH)
    local ex, ew = placed(B._exportBtn)
    assertEqual(ex + ew, w - 12, "row 2 ends 6px in from the right border, as it starts on the left")
    assertEqual((placed(B._dd.date)), 0)
    local cx, cw = placed(B._barCtl.clear)
    assertEqual(cx + cw, w - 12, "the Save/Reset/Clear cluster ends there too")
  end)
end)

-- ── Timeline ledger Phase 7: the Character filter matches the row's holder (Review Focus 4) ──────
test("Browser: Character Current shows the character's half of a warband move, Warband the other", function()
  local W = NS.Constants.WARBAND_HOLDER
  local me = NS.Util.PlayerKey()
  local rows = {
    { ts = 100, char = me, holder = W, dir = "OUT", kind = "GOLD", itemName = "Gold", quantity = 500,
      source = "WARBAND_WITHDRAW", from = W .. "/tabs", to = me .. "/bags", pairId = "100:1" },
    { ts = 100, char = me, holder = me, dir = "IN", kind = "GOLD", itemName = "Gold", quantity = 500,
      source = "WARBAND_WITHDRAW", from = W .. "/tabs", to = me .. "/bags", pairId = "100:1" },
  }
  withFixture(rows, function()
    -- The list offers the Warband, under the name a player reads.
    local labels = {}
    for _, o in ipairs(NS.Browser._options.char(false)) do labels[o.value] = o.label end
    assertEqual(labels[W], "Warband")
    assertTrue(labels[me] ~= nil)
    -- "Character: Current" is the set { [me] = true }.
    local mine = NS.Database:Query({ char = { [me] = true } })
    assertEqual(#mine, 1); assertEqual(mine[1].holder, me); assertEqual(mine[1].dir, "IN")
    local wb = NS.Database:Query({ char = { [W] = true } })
    assertEqual(#wb, 1); assertEqual(wb[1].holder, W); assertEqual(wb[1].dir, "OUT")
    assertEqual(#NS.Database:Query({}), 2, "Character: All shows both halves")
  end)
end)

-- LH-18 (review F-002 / LH-R-02): the filter bar's dropdown-option kit (the seven option builders,
-- `withAll`, the Bound labels and `dataset`) lives in modules/BrowserWidgets.lua, which publishes
-- them on NS.Browser for modules/Browser.lua to bind as file-scope locals at load. So it must load
-- DIRECTLY before Browser.lua, and every member it moved must still be on NS.Browser.
test("Browser: BrowserWidgets.lua loads directly before Browser.lua, members intact", function()
  local files = {}
  for line in assert(io.open("LootHistory.toc", "r")):lines() do
    line = line:gsub("\r$", "")
    if line ~= "" and not line:find("^#") then files[#files + 1] = line end
  end
  local at
  for i, path in ipairs(files) do if path == "modules\\Browser.lua" then at = i end end
  assertTrue(at ~= nil, "the TOC loads modules\\Browser.lua")
  assertEqual(files[at - 1], "modules\\BrowserWidgets.lua", "the option kit loads right before Browser.lua")
  for _, k in ipairs({ "source", "char", "itemType", "itemSubType", "zone", "quality", "bound" }) do
    assertEqual(type(B._options[k]), "function", "NS.Browser._options." .. k)
  end
  assertEqual(type(B._withAll), "function", "NS.Browser._withAll")
  assertEqual(type(B._dataset), "function", "NS.Browser._dataset")
  assertEqual(#B._boundOrder, 5, "NS.Browser._boundOrder")
  assertEqual(B._boundLabel.BOE, "Bind on Equip", "NS.Browser._boundLabel")
end)
