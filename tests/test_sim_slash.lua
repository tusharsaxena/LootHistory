local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse
local H = dofile("tests/sim_support.lua").new(T)

-- `/lh sim` (LootHistory#37, LibKa0s-Sim-1.0's H7; req-lh-sim.md §8): one NS.COMMANDS row, a
-- FEATURE verb the disabled gate refuses, whose grammar is the library's (start, run, step, pause,
-- resume, restart, stop, status, panel; no help verb) plus LootHistory's host verb `loot [n]`. With
-- no library the session stub answers the collection's one line.
--
-- This slot runs after tests/test_sim_panel.lua, with the whole addon brought up; every case stops
-- the session it starts and closes the panel.

local Sim = NS.Sim

local function slash(line) NS.Slash:OnSlash(line) end

local function printed(fragment)
  for _, line in ipairs(M.__printed()) do
    if line:find(fragment, 1, true) then return true end
  end
  return false
end

local function assertPrinted(fragment, label)
  assertTrue(printed(fragment), (label or "missing line") .. ": " .. fragment .. "\n  printed: "
    .. table.concat(M.__printed(), " | "))
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

local function until_(done)
  for _ = 1, 400 do
    if done() then return true end
    H.advance(0.25)
  end
  return done()
end

test("sim slash: NS.COMMANDS carries one `sim` row, and it is a feature verb", function()
  local rows = {}
  for _, c in ipairs(NS.COMMANDS) do if c[1] == "sim" then rows[#rows + 1] = c end end
  assertEqual(#rows, 1, "one row")
  assertEqual(rows[1][2], "In-game simulator: /lh sim start <scenario>")
end)

test("sim slash: bare `/lh sim` prints the status and the usage and opens the panel", function()
  clean(function()
    slash("sim")
    assertPrinted("Simulation: idle. Scenarios: loot, key, vendor, ah, bank, social.")
    assertPrinted("/lh sim start <scenario> [size]: start a simulation.")
    assertPrinted("/lh sim loot [n]: n loot lines now, from a kill (1 to 10, default 3).", "the host's usage line")
    assertTrue(Sim:IsPanelShown())
  end)
end)

test("sim slash: start, step, run, pause, resume, status, restart and stop each act", function()
  clean(function()
    slash("sim start loot")
    assertTrue(Sim:IsActive(), "start")
    assertPrinted("Simulation started (Open world: kill, lockbox, quest): nothing is saved")
    slash("sim step")
    assertEqual(Sim:Status().pos, 1, "step")
    assertTrue(until_(H.settled), "the ledger settles")
    slash("sim run")
    assertTrue(Sim:Status().playing, "run")
    slash("sim pause")
    assertTrue(Sim:Status().paused, "pause")
    slash("sim resume")
    assertFalse(Sim:Status().paused, "resume")
    assertTrue(until_(function() return not Sim:Status().playing end), "the run finishes")
    M.__resetPrinted()
    slash("sim status")
    assertPrinted("Simulation: loot, seed ")
    assertPrinted("step 3 of 3, finished.")
    slash("sim restart")
    assertTrue(Sim:IsActive(), "restart")
    assertEqual(Sim:Status().pos, 0)
    slash("sim stop")
    assertFalse(Sim:IsActive(), "stop")
    assertPrinted("Simulation stopped.")
  end)
end)

test("sim slash: a control with no session says so; an unknown word or `help` prints the usage", function()
  clean(function()
    slash("sim step")
    assertPrinted("No simulation is running.")
    M.__resetPrinted()
    slash("sim help")
    assertPrinted("/lh sim stop: end the simulation.", "help is an unknown word: the usage")
    M.__resetPrinted()
    slash("sim start nowhere")
    assertPrinted("Unknown scenario 'nowhere'.")
  end)
end)

test("sim slash: `loot [n]` plays n self-loot lines from a kill into the session", function()
  clean(function()
    slash("sim start loot")
    -- A typed start plays on its own since LibKa0s v1.76.0 (SimTimeline 3): let the scenario's
    -- run finish before counting the loot verb's rows (minimum re-true at the re-vendor, LH-RV).
    assertTrue(until_(function() return not Sim:Status().playing end), "the started run finishes")
    assertTrue(until_(H.settled))
    local before = #NS.Database:History()
    slash("sim loot 2")
    assertPrinted("Simulated a kill's 2 loot lines.")
    assertTrue(until_(H.settled), "the ledger settles")
    local rows = NS.Database:History()
    assertEqual(#rows - before, 2, "two rows, in the session store")
    for i = before + 1, #rows do assertEqual(rows[i].source, "KILL", "a kill's loot") end
    assertTrue(NS.SimStores.history == rows, "the session's own history")
    M.__resetPrinted()
    slash("sim loot")
    assertPrinted("Simulated a kill's 3 loot lines.", "three by default")
  end)
end)

test("sim slash: `loot` refuses a bad count, a word, and no session, each with its line", function()
  clean(function()
    slash("sim loot 2")
    assertPrinted("No simulation is running.")
    slash("sim start loot")
    M.__resetPrinted()
    slash("sim loot 0")
    assertPrinted("/lh sim loot takes a count from 1 to 10.")
    M.__resetPrinted()
    slash("sim loot 11")
    assertPrinted("/lh sim loot takes a count from 1 to 10.")
    M.__resetPrinted()
    slash("sim loot many")
    assertPrinted("/lh sim start <scenario> [size]: start a simulation.", "a word prints the usage")
  end)
end)

test("sim slash: refused while the addon is disabled, on the one line, and nothing starts", function()
  clean(function()
    NS.Schema:Set("settings.enabled", false)
    M.__resetPrinted()
    local ok, err = pcall(function()
      slash("sim start loot")
      assertFalse(Sim:IsActive(), "nothing started")
      local lines = M.__printed()
      assertEqual(#lines, 1, "exactly one line: " .. table.concat(lines, " | "))
      assertTrue(lines[1]:find("Ka0s Loot History is disabled", 1, true) ~= nil, lines[1])
      slash("sim")
      assertFalse(Sim:IsPanelShown(), "the bare verb does not open the panel either")
    end)
    NS.Schema:Set("settings.enabled", true)
    if not ok then error(err, 0) end
  end)
end)

test("sim slash: with no LibKa0s-Sim-1.0 the stub answers the collection's line", function()
  local stub = NS.SimHost.NewSimStub(function(line) NS.Print(line) end)
  NS.Sim = stub
  M.__resetPrinted()
  local ok, err = pcall(function()
    slash("sim start loot")
    assertPrinted("The simulator needs LibKa0s-Sim-1.0.")
    assertFalse(stub:IsActive())
  end)
  NS.Sim = Sim
  if not ok then error(err, 0) end
end)
