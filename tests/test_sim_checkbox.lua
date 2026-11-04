local T = _G.LH_TEST
local NS, M, Loader = T.NS, T.mocks, T.Loader
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse
local H = dofile("tests/sim_support.lua").new(T)

-- The Master controls *Sim mode* checkbox (R6-SIM; LibKa0s OptionsCompose minor 19, R6-SIM-L;
-- Ka0sAddonsCommonTasks docs/2026-11-03-SMOKE_ROUND6/ R6_ADDENDUM_SIM_RENAME_FINISH.md). The box is
-- the library's row, driven by the SAME two functions the launcher's Sim mode entry carries
-- (NS.IsSimMode, NS.ToggleSim, core/LauncherSetup.lua), so the box, the launcher entry and `/lh sim`
-- are one act; modules/Sim.lua's listener calls O.RefreshScalars when the sim starts or ends, so a
-- sim started anywhere else shows on an open page.
--
-- The owner's seventh smoke round (R7-SIM, Ka0sAddonsCommonTasks docs/2026-11-04-SMOKE_ROUND7 call
-- 2): "checked while the sim window is open and/or a sim is running", unchecked when neither. So
-- NS.IsSimMode answers window shown OR sim running; ticking opens the sim window as a bare `/lh sim`
-- does, so the box stays ticked; unticking stops a running sim and hides the window; and the
-- window's OnShow and OnHide refresh the page, as the sim's start and stop do.
--
-- This slot runs after tests/test_sim_slash.lua, with the whole addon brought up; every case stops
-- the session it starts and closes the panel.

local Sim = NS.Sim
local PATH = "state.sim"

local function printed(fragment)
  for _, line in ipairs(M.__printed()) do
    if line:find(fragment, 1, true) then return true end
  end
  return false
end

local function clean(body)
  H.withClient(function()
    H.withQueue(function()
      H.settle()
      M.__resetPrinted()
      local ok, err = pcall(body)
      Sim:Stop("stop")
      Sim:HidePanel()
      H.settle()
      if not ok then error(err, 0) end
    end)
  end)
end

-- Count O.RefreshScalars calls while `body` runs. The listener looks the refresher up at call time.
local function countingRefresh(body)
  local O = NS.Options
  local real, n = O.RefreshScalars, 0
  O.RefreshScalars = function(...) n = n + 1; return real(...) end
  local ok, err = pcall(body, function() return n end)
  O.RefreshScalars = real
  if not ok then error(err, 0) end
end

test("sim checkbox: the launcher and the Master controls spec share one NS pair", function()
  -- red under: the launcher pair built inline again (two copies that can drift), or the Master
  -- controls spec passing its own functions rather than the launcher's (releasing.md, R6-REL2 item 1).
  assertEqual(type(NS.IsSimMode), "function", "NS.IsSimMode")
  assertEqual(type(NS.ToggleSim), "function", "NS.ToggleSim")
  local launcher = Loader.readFile("core/LauncherSetup.lua")
  assertTrue(launcher:match("isSimMode%s*=%s*NS%.IsSimMode") ~= nil, "the launcher takes NS.IsSimMode")
  assertTrue(launcher:match("toggleSim%s*=%s*NS%.ToggleSim") ~= nil, "the launcher takes NS.ToggleSim")
  local schema = Loader.readFile("settings/Schema.lua")
  assertTrue(schema:match("isSimMode%s*=%s*NS%.IsSimMode") ~= nil, "MasterControls takes NS.IsSimMode")
  assertTrue(schema:match("toggleSim%s*=%s*NS%.ToggleSim") ~= nil, "MasterControls takes NS.ToggleSim")
end)

test("sim checkbox: the row is the composed session-only Sim mode, opening the line after Test mode", function()
  local S = NS.Schema
  local testAt, simAt
  for i, row in ipairs(S.Schema) do
    if row.path == "state.testMode" then testAt = i end
    if row.path == PATH then simAt = i end
  end
  assertTrue(simAt ~= nil, "state.sim row missing: MasterControls got no isSimMode/toggleSim")
  assertEqual(simAt, testAt + 1, "Sim mode comes directly after Test mode")
  local row = S.Schema[simAt]
  assertEqual(row.label, "Sim mode")
  assertEqual(row.group, "Master controls")
  assertEqual(row.type, "bool")
  assertTrue(row.sessionOnly == true, "session-only: a reload ends the sim")
  assertTrue(row.default == false, "default false, so Reset all settings stops a running sim")
  assertTrue(row.startsLine == true, "Test mode sits in the second column, so Sim mode opens the next line")
  assertTrue(type(row.tooltip) == "string" and row.tooltip:find("/lh sim", 1, true) ~= nil,
    "the host note names the verb: " .. tostring(row.tooltip))
  assertFalse(S.VetoedFromResetAll(row), "Reset all settings walks the row")
end)

test("sim checkbox: ticking acts exactly as a bare `/lh sim`, and the open window keeps it ticked", function()
  -- red under: NS.IsSimMode answering the session alone (R6-SIM's rule), which read unticked here.
  clean(function()
    Sim:HidePanel()
    assertEqual(NS.Schema:Get(PATH), false, "no window and no sim: the box reads unticked")
    NS.Schema:Set(PATH, true)
    -- The bare verb's own acts: the status line and the panel, never a scenario the box picked.
    assertTrue(printed("Simulation: idle."), "the bare verb's status: " .. table.concat(M.__printed(), " | "))
    assertTrue(Sim:IsPanelShown(), "the sim panel opens, as `/lh sim` opens it")
    assertFalse(Sim:IsActive(), "the box starts no scenario of its own")
    assertEqual(NS.Schema:Get(PATH), true, "the sim window is open, so the box stays ticked (R7-SIM)")
    assertTrue(NS.IsSimMode(), "the launcher's Sim mode entry reads the same pair")
    NS.Slash:OnSlash("sim start loot")
    assertEqual(NS.Schema:Get(PATH), true, "a running sim reads ticked")
  end)
end)

test("sim checkbox: the window open and idle reads ticked; closing it unticks the box (R7-SIM)", function()
  clean(function()
    NS.Slash:OnSlash("sim")
    assertTrue(Sim:IsPanelShown(), "`/lh sim` opens the window")
    assertFalse(Sim:IsActive(), "idle")
    assertEqual(NS.Schema:Get(PATH), true, "window open, idle: the box reads ticked")
    -- The window's own close button and Escape hide the frame directly, never through HidePanel.
    local frame = M.__namedFrames.LootHistorySimPanel
    assertTrue(frame ~= nil, "the library's LootHistorySimPanel frame")
    frame:Hide()
    assertFalse(Sim:IsPanelShown(), "the frame hid")
    assertEqual(NS.Schema:Get(PATH), false, "no window and no sim: the box reads unticked")
    assertFalse(NS.IsSimMode(), "and so does the launcher's entry")
  end)
end)

test("sim checkbox: a running sim with its window hidden reads ticked (R7-SIM)", function()
  clean(function()
    NS.Slash:OnSlash("sim start loot")
    Sim:HidePanel()
    assertFalse(Sim:IsPanelShown(), "the window is hidden")
    assertTrue(Sim:IsActive(), "hiding the window does not stop the sim")
    assertEqual(NS.Schema:Get(PATH), true, "running: the box reads ticked with the window hidden")
    assertTrue(NS.IsSimMode(), "and so does the launcher's entry")
  end)
end)

test("sim checkbox: unticking over an open, idle window closes it (R7-SIM)", function()
  -- red under: NS.ToggleSim running the bare verb again from on, which leaves the window open.
  clean(function()
    NS.Slash:OnSlash("sim")
    assertEqual(NS.Schema:Get(PATH), true, "window open: ticked")
    M.__resetPrinted()
    NS.Schema:Set(PATH, false)
    assertFalse(Sim:IsPanelShown(), "unticking closes the sim window")
    assertFalse(printed("Simulation: idle."), "and does not run the bare verb again")
    assertEqual(NS.Schema:Get(PATH), false, "the box reads unticked")
  end)
end)

test("sim checkbox: the sim window's OnShow and OnHide refresh the settings page (R7-SIM)", function()
  -- red under: dropping NS.WatchSimWindow's frame hooks (core/LauncherSetup.lua, called from
  -- modules/SimPanel.lua's anchorTo), so a window opened from the slash verb or
  -- the launcher, or closed with its own close button or Escape, left an open page stale.
  clean(function()
    NS.Slash:OnSlash("sim")
    local frame = M.__namedFrames.LootHistorySimPanel
    assertTrue(frame ~= nil, "the library's LootHistorySimPanel frame")
    countingRefresh(function(count)
      local before = count()
      frame:__fire("OnShow")
      assertTrue(count() > before, "OnShow refreshes the page")
      local shown = count()
      frame:Hide()
      frame:__fire("OnHide")
      assertTrue(count() > shown, "OnHide refreshes the page")
    end)
  end)
end)

test("sim checkbox: unticking stops the sim and closes its window; an untick while off does nothing", function()
  clean(function()
    NS.Slash:OnSlash("sim start loot")
    assertTrue(Sim:IsActive(), "started")
    Sim:ShowPanel()
    NS.Schema:Set(PATH, false)
    assertFalse(Sim:IsActive(), "unticking stops it")
    assertTrue(printed("Simulation stopped."), "the stop verb's own line")
    assertFalse(Sim:IsPanelShown(), "and closes the sim window, so one untick leaves the box unticked (R7-SIM)")
    assertEqual(NS.Schema:Get(PATH), false, "unticked")
    M.__resetPrinted()
    NS.Schema:Set(PATH, false)
    assertEqual(#M.__printed(), 0, "off and unticked: no toggle, no line (Reset all settings never starts one)")
    assertFalse(Sim:IsPanelShown(), "and no panel")
  end)
end)

test("sim checkbox: a start or stop from elsewhere signals the settings refresh", function()
  clean(function()
    countingRefresh(function(count)
      local before = count()
      NS.Slash:OnSlash("sim start loot")
      assertTrue(count() > before, "a slash start refreshes the open page")
      local started = count()
      NS.SimStop("combat")
      assertTrue(count() > started, "a self-stop refreshes it too")
    end)
  end)
end)

test("sim checkbox: with the stub session the box reads unticked and ticking says the stub's line", function()
  local stub = NS.SimHost.NewSimStub(function(line) NS.Print(line) end)
  NS.Sim = stub
  M.__resetPrinted()
  local ok, err = pcall(function()
    assertEqual(NS.Schema:Get(PATH), false)
    NS.Schema:Set(PATH, true)
    assertTrue(printed("The simulator needs LibKa0s-Sim-1.0."), table.concat(M.__printed(), " | "))
    assertEqual(NS.Schema:Get(PATH), false)
  end)
  NS.Sim = Sim
  if not ok then error(err, 0) end
end)
