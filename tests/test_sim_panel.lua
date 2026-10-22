local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse
local H = dofile("tests/sim_support.lua").new(T)

-- modules/SimPanel.lua (LootHistory#37, LibKa0s#53 #54; req-lh-sim.md §6): the simulation step
-- panel's LootHistory half, and the History window's simulation marker. The panel itself (its
-- rows, states, controls, click-ahead, stale-click guard and placement order) is LibKa0s-Sim-1.0's
-- and pinned by the library's own suites; these cases read it through NS.Sim:PanelRows and the
-- built frame (`LootHistorySimPanel`, filed by tests/wow_mock.lua under M.__namedFrames) and assert
-- what is LootHistory's: the descriptor's fields, rows that track the timeline, the click-ahead
-- through the ledger gate, a typed step repainting, the run controls and the picker, a position
-- that never reaches NS.db, and the SIMULATION marker on the History window.
--
-- This slot runs after tests/test_sim_store.lua, with the whole addon brought up; every case stops
-- the session it starts and leaves the History window and the panel closed.

local Sim, Host, B = NS.Sim, NS.SimHost, NS.Browser

local function panel() return M.__namedFrames["LootHistorySimPanel"] end

local function slash(line) NS.Slash:OnSlash(line) end

local function printed(fragment)
  for _, line in ipairs(M.__printed()) do
    if line:find(fragment, 1, true) then return true end
  end
  return false
end

local function labels(rows)
  local out = {}
  for i, row in ipairs(rows) do out[i] = row.label end
  return table.concat(out, "|")
end

local function states(rows)
  local out = {}
  for i, row in ipairs(rows) do out[i] = row.state end
  return table.concat(out, ",")
end

-- Tooltip lines ({ left, right } pairs or strings) as one string.
local function tipText(list)
  local out = {}
  for i, line in ipairs(list or {}) do
    out[i] = type(line) == "table" and (tostring(line[1]) .. ": " .. tostring(line[2])) or tostring(line)
  end
  return table.concat(out, " | ")
end

-- Advance the clock until `done()` holds (the ledger settles between steps), at most `limit` ticks.
local function until_(done, limit)
  for _ = 1, limit or 400 do
    if done() then return true end
    H.advance(0.25)
  end
  return done()
end

-- Run body with the client's item answers, an empty timer queue and a clean world; never leave a
-- session, the panel or the window behind.
local function clean(body)
  local s = NS.db.profile.settings
  local savedVis = s.visibility
  s.visibility = "always"
  H.withClient(function()
    H.withQueue(function()
      H.settle()
      M.__resetPrinted()
      local ok, err = pcall(body)
      Sim:Stop("stop")
      Sim:HidePanel()
      Sim:ResetPanelPosition()
      B:Hide()
      H.settle()
      s.visibility = savedVis
      if not ok then error(err, 0) end
    end)
  end)
end

local function start(name)
  local ok, line = Sim:Start({ scenario = name or "loot", seed = 7 })
  assertTrue(ok, "scenario " .. tostring(name) .. " starts: " .. tostring(line))
end

-- ── the descriptor ───────────────────────────────────────────────────────────────────────────

test("sim panel: the descriptor carries LootHistory's presentation fields and nothing else", function()
  local keys = {}
  for k in pairs(Host.PANEL) do keys[#keys + 1] = k end
  table.sort(keys)
  -- No button, no tooltip (OWNER_SCOPE C.7) and no store (C.11).
  assertEqual(table.concat(keys, ","), "anchorTo,check,startTip,stepLabel,stepTip,stopTip,title")
  assertEqual(Host.PANEL.title(), "Ka0s Loot History - Simulation")
  assertEqual(Host.PANEL.check, NS.Icon("confirm"), "the done tick is the catalog's confirm icon")
end)

test("sim panel: anchorTo is the History window while it is shown, else nil (the panel floats)", function()
  clean(function()
    B:Show()
    assertTrue(Host.PANEL.anchorTo() == B:GetWindow(), "shown: dock beside the History window")
    B:Hide()
    assertEqual(Host.PANEL.anchorTo(), nil, "hidden: no anchor")
  end)
end)

-- ── rows ─────────────────────────────────────────────────────────────────────────────────────

test("sim panel: idle, the rows preview the picked scenario's steps with their commands and tips", function()
  clean(function()
    -- The picker follows the last session's scenario: a loot session leaves it on loot.
    start("loot")
    Sim:Stop("stop")
    local r = Sim:PanelRows()
    assertEqual(labels(r), "Start: Open world: kill, lockbox, quest|Kill: Rookery Bat|"
      .. "Lockbox: open " .. Host.World.ITEMS.cache.name .. "|Quest: turn in|Stop simulation")
    assertEqual(states(r), "ready,locked,locked,locked,locked")
    assertEqual(r[1].command, "/lh sim start loot")
    assertEqual(r[2].command, "/lh sim step")
    assertEqual(r[#r].command, "/lh sim stop")
    assertEqual(tipText(r[2].tip), "Injects: LOOT_OPENED (Creature GUID) | "
      .. " : Two CHAT_MSG_LOOT lines, one before its bag burst and one after | "
      .. " : A poor item under the threshold, then CHAT_MSG_MONEY")
    assertTrue(tipText(r[1].tip):find("nothing is saved", 1, true) ~= nil, "Start says nothing is saved")
    assertTrue(tipText(r[#r].tip):find("Ends: the simulation", 1, true) ~= nil, "Stop says what it ends")
  end)
end)

test("sim panel: the rows track the timeline, and a run step's tip names the rows it recorded", function()
  clean(function()
    start("loot")
    assertEqual(states(Sim:PanelRows()), "done,ready,locked,locked,cancel")
    assertTrue(Sim:Step() ~= nil, "the first step plays")
    assertTrue(until_(H.settled), "the ledger settles")
    local r = Sim:PanelRows()
    assertEqual(states(r), "done,done,ready,locked,cancel")
    local tip = tipText(r[2].tip)
    assertTrue(tip:find("Recorded: 4 rows", 1, true) ~= nil, "the kill recorded four rows: " .. tip)
    assertTrue(tip:find("x3 (Kill)", 1, true) ~= nil, "a recorded row names its quantity and source: " .. tip)
    assertTrue(tip:find("Ran ", 1, true) ~= nil, "the library adds when it ran: " .. tip)
  end)
end)

-- ── the built panel ──────────────────────────────────────────────────────────────────────────

test("sim panel: `/lh sim` opens it with LootHistory's title; `/lh sim panel` toggles it", function()
  clean(function()
    slash("sim")
    assertTrue(Sim:IsPanelShown(), "the bare verb opens the panel")
    assertEqual(panel().title:GetText(), "Ka0s Loot History - Simulation")
    slash("sim panel")
    assertFalse(Sim:IsPanelShown())
    slash("sim panel")
    assertTrue(Sim:IsPanelShown())
  end)
end)

test("sim panel: clicking a row ahead plays every step up to it, waiting out the ledger gate", function()
  clean(function()
    start("loot")
    assertTrue(Sim:ShowPanel())
    local buttons = panel().__rowButtons
    buttons[4]:__fire("OnClick")   -- Start, Kill, Lockbox, [Quest]: the third step
    assertTrue(until_(function() return Sim:Status().pos == 3 end), "the click-ahead reached the clicked row: "
      .. Sim:Status().pos)
    assertEqual(Sim:Status().pos, 3, "and stopped there")
    assertEqual(buttons[2].__state, "done")
    assertEqual(buttons[3].__state, "done")
  end)
end)

test("sim panel: a typed `/lh sim step` repaints the shown panel", function()
  clean(function()
    start("loot")
    assertTrue(Sim:ShowPanel())
    local buttons = panel().__rowButtons
    assertEqual(buttons[2].__state, "ready")
    slash("sim step")
    assertEqual(buttons[2].__state, Sim:Status().settling and "busy" or "done", "the played row repaints")
    assertEqual(buttons[3].__state, Sim:Status().settling and "locked" or "ready")
  end)
end)

test("sim panel: while the ledger settles, the gate holds the next step and says so", function()
  clean(function()
    start("loot")
    assertTrue(Sim:ShowPanel())
    slash("sim step")
    NS.Reconciler._pending = NS.Reconciler._pending or true
    M.__resetPrinted()
    slash("sim step")
    assertTrue(printed("The ledger is still settling: the next step waits for it."), "the gate's own line")
    assertEqual(Sim:Status().pos, 1, "the step did not advance")
    assertTrue(Sim:Status().settling, "Status reports settling")
    assertEqual(panel().__rowButtons[2].__state, "busy", "the row at pos is busy while the gate holds")
    if NS.Reconciler._pending == true then NS.Reconciler._pending = nil end
  end)
end)

test("sim panel: the controls run, pause, resume, restart and stop through the typed verbs", function()
  clean(function()
    start("loot")
    assertTrue(Sim:ShowPanel())
    local c = panel().controls
    assertTrue(c:IsShown(), "running: the controls")
    assertFalse(panel().picker:IsShown(), "running: no picker")
    c.run:__fire("OnClick")
    assertTrue(Sim:Status().playing, "Run all plays")
    c.pause:__fire("OnClick")
    assertTrue(Sim:Status().paused, "Pause pauses")
    c.pause:__fire("OnClick")
    assertFalse(Sim:Status().paused, "the same button resumes")
    assertTrue(until_(function() return not Sim:Status().playing end), "the run finishes")
    assertEqual(Sim:Status().pos, Sim:Status().total, "every step ran")
    local seed = Sim:Status().seed
    c.restart:__fire("OnClick")
    assertTrue(Sim:IsActive(), "Restart starts again")
    assertEqual(Sim:Status().pos, 0, "from the first step")
    assertTrue(Sim:Status().seed ~= seed, "with a fresh seed")
    c.stop:__fire("OnClick")
    assertFalse(Sim:IsActive(), "Stop ends it")
    assertTrue(panel().picker:IsShown(), "idle again: the picker")
  end)
end)

test("sim panel: the picker starts the chosen scenario", function()
  clean(function()
    assertTrue(Sim:ShowPanel())
    local pk = panel().picker
    pk.scenario.onSelect("key")
    assertEqual(Sim:PanelRows()[1].label, "Start: Mythic+ key")
    assertEqual(Sim:PanelRows()[1].command, "/lh sim start key")
    pk.start:__fire("OnClick")
    assertTrue(Sim:IsActive(), "Start starts it")
    assertEqual(Sim:Session().scenario, "key")
  end)
end)

test("sim panel: a drag is remembered for the session only, and ResetPanelPosition redocks it", function()
  clean(function()
    local before = H.serialize({ NS.db.global, NS.db.profile })
    B:Show()
    assertTrue(Sim:ShowPanel())
    local f = panel()
    assertEqual(f.__dock, "right", "docked beside the shown History window")
    -- The mock records SetPoint; the library reads the dropped point back through GetPoint(1).
    f.GetPoint = function(self)
      local p = self.__points[#self.__points]
      return p.point, p.relativeTo, p.relativePoint, p.x, p.y
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", nil, "TOPLEFT", 40, -60)
    f:__fire("OnDragStop")
    assertEqual(f.__dock, "dragged")
    Sim:HidePanel(); Sim:ShowPanel()
    assertEqual(f.__dock, "dragged", "the dragged point holds for the session")
    assertEqual(H.serialize({ NS.db.global, NS.db.profile }), before,
      "nothing written to SavedVariables (OWNER_SCOPE C.11)")
    Sim:ResetPanelPosition()
    assertEqual(f.__dock, "right", "reset forgets the point and redocks beside the window")
    f.GetPoint = nil
  end)
end)

-- ── the marker on the History window (preview-mode, H8) ──────────────────────────────────────

local SIM_STRIP = "SIMULATION: an invented world drives the real capture; nothing is saved. /lh sim stop ends it."

test("sim marker: while a session runs the window wears SIMULATION in cyan, the strip and the footer", function()
  clean(function()
    B:Show()
    local f = B:GetWindow()
    assertFalse(f.testBadge:IsShown(), "idle: no badge")
    start("loot")
    assertTrue(f.testBadge:IsShown(), "running: the badge")
    assertEqual(f.testBadge:GetText(), "SIMULATION")
    local r, g, b = f.testBadge:GetTextColor()
    assertEqual(("%.1f,%.1f,%.1f"):format(r, g, b), "0.3,0.8,1.0", "in its own color")
    assertTrue(f.testStrip:IsShown(), "the strip")
    assertEqual(f.testStrip.text:GetText(), SIM_STRIP)
    assertEqual(B._footer:GetText():match("^Simulating: loot \194\183 step 0/3"), "Simulating: loot \194\183 step 0/3")
    Sim:Step()
    assertTrue(B._footer:GetText():find("step 1/3", 1, true) ~= nil, "a step repaints the footer: "
      .. B._footer:GetText())
  end)
end)

test("sim marker: the stop takes the badge, the strip and the footer line down", function()
  clean(function()
    B:Show()
    local f = B:GetWindow()
    start("loot")
    Sim:Stop("stop")
    assertFalse(f.testBadge:IsShown(), "no badge")
    assertFalse(f.testStrip:IsShown(), "no strip")
    assertTrue(B._footer:GetText():find("^Showing") ~= nil, "the footer is the count again: " .. B._footer:GetText())
  end)
end)

test("sim marker: test mode and the simulation never show together", function()
  clean(function()
    B:Show()
    local f, BT = B:GetWindow(), NS.BrowserTable
    start("loot")
    BT:SetTestMode(true)
    assertFalse(BT.testMode, "test mode is refused while a simulation runs")
    assertEqual(f.testBadge:GetText(), "SIMULATION")
    Sim:Stop("stop")
    assertTrue(BT:SetTestMode(true), "test mode starts once the simulation is over")
    assertEqual(f.testBadge:GetText(), "TEST MODE", "the badge is test mode's")
    local r = f.testBadge:GetTextColor()
    assertEqual(r, 1, "in its red")
    assertEqual(f.testStrip.text:GetText(), "TEST MODE: a sample loot history, not yours. Combat ends it.")
    local ok = Sim:Start({ scenario = "loot", seed = 7 })
    assertFalse(ok, "a simulation is refused in test mode")
    assertEqual(f.testBadge:GetText(), "TEST MODE")
    BT:SetTestMode(false)
  end)
end)
