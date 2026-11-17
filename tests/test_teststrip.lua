-- tests/test_teststrip.lua — the History window's test-mode strip (LootHistory#36, LibKa0s#48).
--
-- While test mode is on, the window wears the library's W.TestStrip docked directly under the title
-- bar (`dock = "title"`, Widgets minor 27; preview-mode's *Where the strip sits*, standard v2.110.0,
-- through NS.MakeTestStrip, core/WidgetsSetup.lua), and everything below the title bar (the tab
-- strip, the filter bar and every pane) moves down by the strip's own `strip:BodyOffset()`. Until the
-- v1.105.0 adoption (AD-88-LH) the strip hung under the filter bar and only the panes moved, by
-- NS.TestStripReserve(); these cases pin the docked rule in its place. The
-- red TEST MODE badge beside the title marks test mode only on a degraded install, where there is no
-- strip (the preview-mode header-word rule, v2.87.0). Both strings route through NS.L. Its own suite
-- rather than more cases in tests/test_browser.lua, which then sat just under layout-§1's cap.
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local STRIP_TEXT = "TEST MODE: a sample loot history, not yours. Combat ends it."

-- The pane's TOPLEFT y offset, from the mock's recorded anchors (the last TOPLEFT wins).
local function paneTop(pane)
  local y
  for _, p in ipairs(pane.__points or {}) do
    if p.point == "TOPLEFT" then y = p.y end
  end
  return y
end

-- The library's published strip height: what a shown, title-docked strip moves the body by.
local function stripHeight()
  return T.mocks.LibStub("LibKa0s-Widgets-1.0").TEST_STRIP.HEIGHT
end

-- The shared mock answers a texture with its frame (the kit's known divergence), so the strip's own
-- SetHeight is overwritten by its icon's SetSize. While `fn` runs, both strips answer the height the
-- library sets on them, so BodyOffset reads the strip's real height; put back after.
local function withStripHeights(f, fn)
  local strips = { f.testStrip, f.simStrip }
  for _, s in ipairs(strips) do rawset(s, "GetHeight", function() return stripHeight() end) end
  local ok, err = pcall(fn)
  for _, s in ipairs(strips) do rawset(s, "GetHeight", nil) end
  if not ok then error(err, 0) end
end

-- Every band below the title bar, by its TOPLEFT y: the 1px anchor the tab strip hangs from, the
-- filter bar and each pane.
local function bodyTops(f)
  local out = { divider = paneTop(f.dividerBar), filter = paneTop(f.filterHost) }
  for name, pane in pairs(f.panes) do out["pane " .. name] = paneTop(pane) end
  return out
end

-- Runs fn(B, f, BT) in `ns` with the visibility setting at "always" and test mode off, the window
-- open; always leaves test mode off and the window closed.
local function withWindow(ns, fn)
  local B, BT = ns.Browser, ns.BrowserTable
  local s = ns.db.profile.settings
  local savedVis = s.visibility
  s.visibility = "always"
  local ok, err = pcall(function()
    if BT.testMode then BT:SetTestMode(false) end
    B:Show()
    fn(B, B:GetWindow(), BT)
  end)
  if BT.testMode then BT:SetTestMode(false) end
  B:Hide()
  s.visibility = savedVis
  if not ok then error(err, 0) end
end

test("test strip: test mode on shows the strip with its L text, moves the body down and hides the badge",
  function()
    withWindow(NS, function(_, f, BT)
      local base = bodyTops(f)
      assertTrue(f.testStrip ~= nil, "the library is present in this run, so the strip must exist")
      withStripHeights(f, function()
        assertFalse(f.testStrip:IsShown(), "off: no strip")
        assertTrue(BT:SetTestMode(true), "test mode must start")
        assertTrue(f.testStrip:IsShown(), "on: the strip is shown")
        assertEqual(f.testStrip.text:GetText(), STRIP_TEXT)
        assertEqual(f.testStrip.kind, "test", "the strip is the library's test flavor")
        assertFalse(f.simStrip:IsShown(), "test mode: no simulation strip")
        assertFalse(f.testBadge:IsShown(), "on: the strip is the marker, so no title badge")
        local off = f.testStrip:BodyOffset()
        assertEqual(off, stripHeight(), "a shown title-docked strip offsets the body by its own height")
        for band, y in pairs(bodyTops(f)) do
          assertEqual(y, base[band] - off, band .. " moves down by the strip's BodyOffset")
        end
      end)
    end)
  end)

test("test strip: test mode off hides the strip and the badge and puts the body back", function()
  withWindow(NS, function(_, f, BT)
    local base = bodyTops(f)
    assertTrue(BT:SetTestMode(true))
    assertTrue(BT:SetTestMode(false))
    assertFalse(f.testStrip:IsShown(), "off: the strip is hidden")
    assertFalse(f.testBadge:IsShown(), "off: the badge is hidden")
    assertFalse(f.simStrip:IsShown(), "off: no simulation strip")
    assertEqual(f.testStrip:BodyOffset(), 0, "a hidden strip offsets nothing")
    for band, y in pairs(bodyTops(f)) do
      assertEqual(y, base[band], band .. " is back at its base")
    end
  end)
end)

test("test strip: Show while already in test mode moves the body down", function()
  -- The B:Show path (it calls B:UpdateTestStrip) rather than the dataset-swap path.
  withWindow(NS, function(B, f, BT)
    local base = paneTop(f.panes.History)
    withStripHeights(f, function()
      assertTrue(BT:SetTestMode(true))
      B:Hide()
      f.testStrip:Hide()
      for _, pane in pairs(f.panes) do pane:ClearAllPoints() end
      B:Show()
      assertTrue(f.testStrip:IsShown(), "re-shown in test mode: the strip is back")
      assertEqual(paneTop(f.panes.History), base - stripHeight())
    end)
  end)
end)

-- The strip's anchors as the library's docking left them (the last of each point wins).
local function stripPoints(strip)
  local byPoint = {}
  for _, p in ipairs(strip.__points or {}) do byPoint[p.point] = p end
  return byPoint
end

test("test strip: the strip is docked directly under the title bar, and hovering it explains test mode",
  function()
  withWindow(NS, function(_, f)
    assertTrue(type(f.testStrip.BodyOffset) == "function" and type(f.testStrip.Place) == "function",
      "the strip is docked by the library (DockTestStrip gives it Place and BodyOffset)")
    local byPoint = stripPoints(f.testStrip)
    for point, rel in pairs({ TOPLEFT = "BOTTOMLEFT", TOPRIGHT = "BOTTOMRIGHT" }) do
      local p = byPoint[point]
      assertTrue(p ~= nil, "the strip has a " .. point .. " anchor")
      assertTrue(p.relativeTo == f.titleBar, point .. " is anchored to the title bar")
      assertEqual(p.relativePoint, rel)
      assertEqual(p.y, 0, point .. " sits flush under the title bar")
    end
    local tip = T.mocks.GameTooltip
    local lines = {}
    local stockAdd, stockSet = tip.AddLine, tip.SetText
    rawset(tip, "AddLine", function(_, line) lines[#lines + 1] = line end)
    rawset(tip, "SetText", function(_, line) lines[#lines + 1] = line end)
    local ok, err = pcall(function()
      f.testStrip:__fire("OnEnter")
      assertTrue(tip:IsShown(), "hover shows the tooltip")
      f.testStrip:__fire("OnLeave")
      assertFalse(tip:IsShown(), "leaving hides it")
    end)
    rawset(tip, "AddLine", stockAdd); rawset(tip, "SetText", stockSet)
    if not ok then error(err, 0) end
    assertEqual(table.concat(lines, "|"), "Test mode|Shows: sample loot, holdings and timeline"
      .. "|Ended by: combat, /lh test, the launcher menu")
  end)
end)

test("test strip: each mode strip is docked under the title bar and explains its own mode", function()
  withWindow(NS, function(_, f)
    assertEqual(f.simStrip.kind, "sim", "the simulation strip is the library's sim flavor")
    local byPoint = stripPoints(f.simStrip)
    assertTrue(byPoint.TOPLEFT and byPoint.TOPLEFT.relativeTo == f.titleBar, "docked under the title bar")
    assertEqual(byPoint.TOPRIGHT and byPoint.TOPRIGHT.y, 0)
    local tip = T.mocks.GameTooltip
    local stockSet = tip.SetText
    local titles = {}
    rawset(tip, "SetText", function(_, line) titles[#titles + 1] = line end)
    local ok, err = pcall(function()
      f.simStrip:__fire("OnEnter"); f.simStrip:__fire("OnLeave")
      f.testStrip:__fire("OnEnter"); f.testStrip:__fire("OnLeave")
    end)
    rawset(tip, "SetText", stockSet)
    if not ok then error(err, 0) end
    assertEqual(table.concat(titles, "|"), "SIM|Test mode", "each strip's tooltip names its mode")
  end)
end)

-- A second, complete environment (library + addon), so a window can be built AFTER an NS.L
-- override: the strip and the badge take their text once, when the window is first built.
local function freshEnv(withLibrary)
  local mocks = dofile("tests/wow_mock.lua")()
  mocks.DEFAULT_CHAT_FRAME.AddMessage = function() end
  -- The degraded close glyph sets its own face from this global, which the shared mock leaves unset.
  mocks.STANDARD_TEXT_FONT = mocks.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  local L = dofile("tests/_kit/loader.lua")
  L.addonName = "LootHistory"
  local ns = {}
  if withLibrary then L.loadAll(L.xmlFiles("libs/LibKa0s/LibKa0s.xml"), ns, mocks) end
  L.loadAll(L.tocFiles("LootHistory.toc"), ns, mocks)
  ns:InitDB()
  return ns
end

test("test strip: the strip text comes from NS.L", function()
  local ns = freshEnv(true)
  ns.L[STRIP_TEXT] = "STRIP override"
  withWindow(ns, function(_, f)
    assertEqual(f.testStrip.text:GetText(), "STRIP override")
  end)
end)

test("test strip: degraded (no Widgets): no strip, no shift, the badge still shows", function()
  local ns = freshEnv(false)
  ns.L["TEST MODE"] = "BADGE override"
  assertEqual(ns.MakeTestStrip(nil, "x"), nil, "no library: the seam answers nil")
  -- The SavedVariables global is the shared suite's, so its history is parked: a degraded row has
  -- no mono face for its direction glyph (C.FONT_MONO comes from Media), which is not this case.
  local g = ns.db.global
  local savedHistory = g.history
  g.history = {}
  local ok, err = pcall(withWindow, ns, function(B, f, BT)
    local base = bodyTops(f)
    assertEqual(f.testStrip, nil, "a degraded window has no strip")
    -- The footer degrades too (AD-89-LH): NS.MakeFooter's bare footer, no hairline, both lines kept.
    assertTrue(f.footer ~= nil and f.footer.line == nil, "a degraded window wears the bare footer")
    assertTrue(B._footer == f.footer.left and B._dbFooter == f.footer.right, "with both of its lines")
    assertTrue((B._dbFooter:GetText() or ""):find("^Database ~") ~= nil, "the size line still reads")
    assertEqual(f.simStrip, nil, "nor a simulation strip")
    -- The flag and the repaint B:OnDatasetChanged makes, without the sample rows (see above).
    BT.testMode = true
    B:UpdateTestStrip()
    assertTrue(f.testBadge:IsShown(), "the badge still marks it")
    assertEqual(f.testBadge:GetText(), "BADGE override", "the badge text comes from NS.L")
    for band, y in pairs(bodyTops(f)) do assertEqual(y, base[band], band .. " does not move") end
    BT.testMode = false
  end)
  g.history = savedHistory
  if not ok then error(err, 0) end
end)
