-- tests/test_teststrip.lua — the History window's test-mode strip (LootHistory#36, LibKa0s#48).
--
-- While test mode is on, the window wears the library's W.TestStrip under the filter bar (through
-- NS.MakeTestStrip, core/WidgetsSetup.lua) and every pane moves down by NS.TestStripReserve(); the
-- red TEST MODE badge beside the title stays. Both strings route through NS.L. Its own suite
-- rather than more cases in tests/test_browser.lua, which sits just under layout-§1's cap.
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

test("test strip: test mode on shows the strip with its L text, shifts the panes and shows the badge",
  function()
    withWindow(NS, function(_, f, BT)
      local base = {}
      for name, pane in pairs(f.panes) do base[name] = paneTop(pane) end
      assertTrue(f.testStrip ~= nil, "the library is present in this run, so the strip must exist")
      assertFalse(f.testStrip:IsShown(), "off: no strip")
      assertTrue(BT:SetTestMode(true), "test mode must start")
      assertTrue(f.testStrip:IsShown(), "on: the strip is shown")
      assertEqual(f.testStrip.text:GetText(), STRIP_TEXT)
      assertTrue(f.testBadge:IsShown(), "on: the title badge stays")
      local reserve = NS.TestStripReserve()
      assertTrue(reserve > 0, "a present library reserves room")
      for name, pane in pairs(f.panes) do
        assertEqual(paneTop(pane), base[name] - reserve, name .. " pane moves down by the reserve")
      end
    end)
  end)

test("test strip: test mode off hides the strip and the badge and puts the panes back", function()
  withWindow(NS, function(_, f, BT)
    local base = {}
    for name, pane in pairs(f.panes) do base[name] = paneTop(pane) end
    assertTrue(BT:SetTestMode(true))
    assertTrue(BT:SetTestMode(false))
    assertFalse(f.testStrip:IsShown(), "off: the strip is hidden")
    assertFalse(f.testBadge:IsShown(), "off: the badge is hidden")
    for name, pane in pairs(f.panes) do
      assertEqual(paneTop(pane), base[name], name .. " pane is back at its base")
    end
  end)
end)

test("test strip: Show while already in test mode reserves the space", function()
  -- The B:Show path (it calls B:UpdateTestStrip) rather than the dataset-swap path.
  withWindow(NS, function(B, f, BT)
    local base = paneTop(f.panes.History)
    assertTrue(BT:SetTestMode(true))
    B:Hide()
    f.testStrip:Hide()
    for _, pane in pairs(f.panes) do pane:ClearAllPoints() end
    B:Show()
    assertTrue(f.testStrip:IsShown(), "re-shown in test mode: the strip is back")
    assertEqual(paneTop(f.panes.History), base - NS.TestStripReserve())
  end)
end)

test("test strip: the strip hangs under the filter bar, and hovering it explains test mode", function()
  withWindow(NS, function(_, f)
    local byPoint = {}
    for _, p in ipairs(f.testStrip.__points or {}) do byPoint[p.point] = p end
    for point, rel in pairs({ TOPLEFT = "BOTTOMLEFT", TOPRIGHT = "BOTTOMRIGHT" }) do
      local p = byPoint[point]
      assertTrue(p ~= nil, "the strip has a " .. point .. " anchor")
      assertTrue(p.relativeTo == f.filterHost, point .. " is anchored to the filter bar")
      assertEqual(p.relativePoint, rel)
      assertEqual(p.y, -2)
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

test("test strip: the strip and the badge text come from NS.L", function()
  local ns = freshEnv(true)
  ns.L[STRIP_TEXT] = "STRIP override"
  ns.L["TEST MODE"] = "BADGE override"
  withWindow(ns, function(_, f)
    assertEqual(f.testStrip.text:GetText(), "STRIP override")
    assertEqual(f.testBadge:GetText(), "BADGE override")
  end)
end)

test("test strip: degraded (no Widgets): no strip, no shift, the badge still shows", function()
  local ns = freshEnv(false)
  assertEqual(ns.MakeTestStrip(nil, "x"), nil, "no library: the seam answers nil")
  assertEqual(ns.TestStripReserve(), 0, "no library: nothing reserved")
  -- The SavedVariables global is the shared suite's, so its history is parked: a degraded row has
  -- no mono face for its direction glyph (C.FONT_MONO comes from Media), which is not this case.
  local g = ns.db.global
  local savedHistory = g.history
  g.history = {}
  local ok, err = pcall(withWindow, ns, function(B, f, BT)
    local base = {}
    for name, pane in pairs(f.panes) do base[name] = paneTop(pane) end
    assertEqual(f.testStrip, nil, "a degraded window has no strip")
    -- The flag and the repaint B:OnDatasetChanged makes, without the sample rows (see above).
    BT.testMode = true
    B:UpdateTestStrip()
    assertTrue(f.testBadge:IsShown(), "the badge still marks it")
    for name, pane in pairs(f.panes) do assertEqual(paneTop(pane), base[name], name .. " does not move") end
    BT.testMode = false
  end)
  g.history = savedHistory
  if not ok then error(err, 0) end
end)
