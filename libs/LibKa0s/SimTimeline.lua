-- LibKa0s-Sim-1.0 — the step machine: a scenario's timeline played one step at a time, behind the
-- host's gate, by hand (Step), on a timer (Run), or back to back up to a row (RunTo, internal).
-- And the verbs that drive it from the slash line (RunVerb).
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF Sim.lua ──────────────────────────────────────
--
-- Sim.lua is the shell every host needs (the seam, the session, Fire, After and the stop); this
-- file is the part that walks a timeline, and the verbs and the panel drive it. It is NOT a major
-- of its own: it is part of `LibKa0s-Sim-1.0`, paired on the shell's minor with Perf's multi-file
-- idiom, so a step machine from one vendored copy never attaches to a shell from another without
-- saying so. A payload without this file still builds sessions: Sim.lua's fallbacks answer every
-- member below (`Step` answers nil, "absent"), and nothing plays.
--
-- ── THE ATTACH ───────────────────────────────────────────────────────────────────────────────
--
-- Sim:New calls lib.__AttachTimeline(sim, ctx) after installing its fallbacks, and this file
-- overwrites them. ctx is the handshake's internal table (Sim.lua's newCtx), not contract. This
-- file reads ctx.d, tr, print, debug, notify, session, stopping and ready, and sets three fields
-- on it: `cancelRun` (Stop's step 1), `status` (fills Status()'s timeline fields) and `runTo`.
--
-- ── THE MEMBERS ──────────────────────────────────────────────────────────────────────────────
--
--   Steps()   -> the live list ({} idle). Built from def.timeline(def, {scenario, size, seed}) the
--                first time a session is read; the library adds ranAt, detail and index to a step
--                that has run, and writes nothing else into it.
--   Step()    -> step | nil, code   notRunning, building (until the session's ready()), done,
--                settling (the gate is closed: its line or SETTLING printed, pos not advanced).
--                On success: pos advances, play runs under pcall, the step is stamped, STEP_LINE
--                printed, listeners told. A play error counts the step as run with detail ERROR,
--                pauses the run and prints STEP_FAILED, answering nil, "failed".
--   Run()     -> true | false, code   notRunning, building, playing, done. Clears paused and plays
--                to the end: each tick checks the gate; closed re-polls after GATE_POLL without
--                advancing, open plays a step and sets the next tick after stepDelay(step).
--   Pause()   -> notPlaying; cancels the pending tick (no orphan timer).
--   Resume()  -> notPaused; calls Run.
--   Restart() -> notRunning; Stop("restart"), then Start{scenario, size} with a fresh seed. A
--                refusal is printed by Start and answered false, "refused".
--   RunVerb(line) -> ok, code   the typed grammar every host's `/<slash> sim` shares, printed
--                through d.print: the generic verbs, then d.verbs, else the usage (the verbs
--                section below). The click path is the typed path: the panel calls RunVerb, or
--                RunTo, which prints the same per-step lines.
--
-- When a step that plays is the last one, FINISHED is printed (formatted with d.slash) and
-- listeners are told, whichever of Step, Run or RunTo played it.
--
-- RunTo IS SIM-INTERNAL (OWNER_SCOPE C.7). It is a file-local function handed to SimPanel.lua as
-- ctx.runTo, never an instance member: it plays every step up to and including `index`, back to
-- back with no stepDelay, polling a closed gate the way Run does, and is synchronous while the gate
-- stays open. A step failure or a done / notRunning answer ends it. It occupies Run's `playing`
-- slot (C.2): while a RunTo poll is pending, Run and a second RunTo answer "playing", and Pause and
-- Stop cancel it.
--
-- THE SESSION TOKEN (C.1). Step, every Run tick and RunTo capture the session before play and bail
-- if it changed during play (a Stop, or a Restart, from inside the host's play): no stamp, no
-- STEP_LINE, no next tick.
--
-- Every timer is the session's own `sim:After`, so it dies with the session. There is no schema
-- row for the step delay: a host passes a fixed constant or a function (OWNER_SCOPE C.11).

local lib = LibStub and LibStub("LibKa0s-Sim-1.0", true)
if not lib then return end

local TIMELINE_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own, as Perf's attach files are: a step
-- machine attached to an older shell would read ctx fields that shell may not hand over.
if lib.__timelineMinor and lib.__timelineMinor >= TIMELINE_MINOR
  and lib.__timelineShellMinor == lib.MINOR then return end
lib.__timelineMinor      = TIMELINE_MINOR
lib.__timelineShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.SimTimeline = TIMELINE_MINOR

local type, tostring, tonumber, pcall, ipairs, rawget, floor =
  type, tostring, tonumber, pcall, ipairs, rawget, math.floor

-- How long a Run tick or a RunTo waits before asking a closed gate again, in seconds.
local GATE_POLL = 0.25
-- The pause after a step before Run plays the next one, when the host names none.
local DEFAULT_DELAY = 2

lib.STRINGS = lib.STRINGS or {}
for key, line in pairs({
  BUILDING    = "The simulation is still building its world.",
  PLAYING     = "The simulation is already playing.",
  NOT_PLAYING = "The simulation is not playing.",
  NOT_PAUSED  = "The simulation is not paused.",
  DONE        = "Every step of the simulation has run.",
  SETTLING    = "Waiting for the simulated world to settle.",
  STEP_LINE   = "Simulation step %d of %d: %s.",
  STEP_FAILED = "Simulation step %d of %d failed: %s. The run is paused; the debug log has the error.",
  FINISHED    = "Simulation finished: %s stop ends it.",
  ERROR       = "error",
  -- The verbs (RunVerb, below). Every USAGE_* line is formatted with d.slash.
  STATUS_IDLE    = "Simulation: idle. Scenarios: %s.",
  STATUS_RUNNING = "Simulation: %s, seed %s, step %d of %d, %s.",
  STATUS_SIZE    = "%s (size %s)",
  STATUS_RANDOM  = "random",
  STATE_BUILDING = "building",
  STATE_PLAYING  = "playing",
  STATE_PAUSED   = "paused",
  STATE_SETTLING = "settling",
  STATE_WAITING  = "waiting for a step",
  STATE_DONE     = "finished",
  VERB_FAILED    = "Simulation verb '%s' failed. The debug log has the error.",
  USAGE_BARE     = "%s: the status, this usage and the step panel.",
  USAGE_START    = "%s start <scenario> [size]: start a simulation.",
  USAGE_RUN      = "%s run: play every step, pausing between them.",
  USAGE_STEP     = "%s step: play the next step.",
  USAGE_PAUSE    = "%s pause: pause a run.",
  USAGE_RESUME   = "%s resume: resume a paused run.",
  USAGE_RESTART  = "%s restart: start the same scenario again with a fresh seed.",
  USAGE_STOP     = "%s stop: end the simulation.",
  USAGE_STATUS   = "%s status: where the simulation stands.",
  USAGE_PANEL    = "%s panel: show or hide the step panel.",
}) do lib.STRINGS[key] = line end

-- ── one session's run (R) ────────────────────────────────────────────────────────────────────
--
-- T is one instance's step machine; T.R is the run of the session it last read. R is replaced
-- whenever the session changes and dropped at stop, so nothing of an old session's run survives
-- into a new one, and a closure that captured R can tell it has gone stale (T.R ~= R).

--- Build a session's steps from its scenario's pure timeline. A raising or non-table timeline is a
--- debug line and an empty list.
local function buildSteps(ctx, session)
  local def = ctx.d.scenarios.defs[session.scenario]
  local opts = { scenario = session.scenario, size = session.size, seed = session.seed }
  local ok, steps = pcall(def.timeline, def, opts)
  if ok and type(steps) == "table" then return steps end
  ctx.debug("timeline %s failed: %s", tostring(session.scenario), tostring(steps))
  return {}
end

--- The run of the live session, built on first read; nil while idle or stopping.
local function current(T)
  local ctx = T.ctx
  local session = ctx.session()
  if not session or ctx.stopping() then return nil end
  local R = T.R
  if not R or R.session ~= session then
    R = { session = session, steps = buildSteps(ctx, session), pos = 0,
      playing = false, paused = false, settling = false, timer = nil, said = false }
    T.R = R
  end
  return R
end

--- True while R is still the live session's run.
local function live(T, R)
  return T.R == R and T.ctx.session() == R.session and not T.ctx.stopping()
end

--- Cancel R's pending tick or poll, if any.
local function cancelTimer(R)
  local handle = R.timer
  R.timer = nil
  if handle then handle:Cancel() end
end

--- A step's label: the host's panel.stepLabel when it gives one, else step.label or step.kind.
local function labelOf(T, step, i, steps)
  local panel = T.ctx.d.panel
  local fn = type(panel) == "table" and panel.stepLabel or nil
  if type(fn) == "function" then
    local ok, text = pcall(fn, step, i, steps)
    if ok and text ~= nil then return tostring(text) end
  end
  return tostring(step.label or step.kind)
end

--- The host's gate for R's session: open (true) or closed, and its line. No gate is always open; a
--- gate that raises is closed, with a debug line.
local function gateOpen(T, R)
  local gate = T.ctx.d.gate
  if type(gate) ~= "function" then return true end
  local ok, open, line = pcall(gate, R.session)
  if not ok then
    T.ctx.debug("gate failed: %s", tostring(open))
    return false
  end
  return open and true or false, line
end

--- Mark R settling. The line prints when `say` is set (Step, every call) or on the first closed
--- answer of a settling spell (Run and RunTo, so a poll does not repeat it four times a second).
local function settle(T, R, line, say)
  local was = R.settling
  R.settling = true
  if say or not R.said then
    R.said = true
    T.ctx.print(line ~= nil and tostring(line) or T.ctx.tr("SETTLING"))
  end
  if not was then T.ctx.notify() end
end

--- The run is over: clear the playing slot and say so.
local function finish(T, R)
  cancelTimer(R)
  R.playing, R.settling = false, false
  T.ctx.print(T.ctx.tr("FINISHED"):format(tostring(T.ctx.d.slash)))
  T.ctx.notify()
end

--- A play error: the step counts as run with detail ERROR, the run pauses, STEP_FAILED prints.
local function failStep(T, R, step, err)
  local ctx = T.ctx
  step.ranAt, step.detail, step.index = time(), ctx.tr("ERROR"), R.pos
  cancelTimer(R)
  R.playing, R.paused, R.settling = false, true, false
  ctx.debug("step %d failed: %s", R.pos, tostring(err))
  ctx.print(ctx.tr("STEP_FAILED"):format(R.pos, #R.steps, labelOf(T, step, R.pos, R.steps)))
  ctx.notify()
end

--- Play R's next step, the gate already open. Answers the step, or nil and a code.
local function playNext(T, R)
  local ctx = T.ctx
  R.settling, R.said = false, false
  R.pos = R.pos + 1
  local i, steps = R.pos, R.steps
  local step = steps[i]
  local session = R.session                    -- the token, captured before play
  local ok, detail = pcall(ctx.d.play, step, session)
  if not live(T, R) then return nil, "notRunning" end   -- stopped or restarted inside play
  if not ok then
    failStep(T, R, step, detail)
    return nil, "failed"
  end
  step.ranAt, step.detail, step.index = time(), detail, i
  ctx.print(ctx.tr("STEP_LINE"):format(i, #steps, labelOf(T, step, i, steps)))
  ctx.notify()
  if i >= #steps then finish(T, R) end
  return step
end

--- Why R cannot play a step now, or nil when it can (the gate aside).
local function blocked(T, R)
  if not R then return "notRunning" end
  if not T.ctx.ready() then return "building" end
  if R.pos >= #R.steps then return "done" end
  return nil
end

--- Step's body, shared by the member and the two players: the code, the gate, then the step.
local function stepOnce(T, R, say)
  local code = blocked(T, R)
  if code then return nil, code end
  local open, line = gateOpen(T, R)
  if not open then
    settle(T, R, line, say)
    return nil, "settling"
  end
  return playNext(T, R)
end

--- The step delay after `step`: d.stepDelay as a number, or as fn(step), read now; default 2.
local function delayAfter(T, step)
  local delay = T.ctx.d.stepDelay
  if type(delay) == "function" then
    local ok, v = pcall(delay, step)
    if not ok then T.ctx.debug("stepDelay failed: %s", tostring(v)) end
    delay = ok and tonumber(v) or nil
  end
  delay = tonumber(delay) or DEFAULT_DELAY
  return delay > 0 and delay or 0
end

--- Set R's one pending timer to call fn(T, R) after `delay`, through the session's After.
local function schedule(T, R, delay, fn)
  cancelTimer(R)
  local handle
  handle = T.sim:After(delay, function()
    if R.timer ~= handle then return end
    R.timer = nil
    if live(T, R) and R.playing then fn(T, R) end
  end)
  R.timer = handle
end

--- One Run tick: the gate, then a step, then the next tick after the step's delay.
local function tick(T, R)
  local step, code = stepOnce(T, R, false)
  if not live(T, R) or not R.playing then return end
  if code == "settling" then return schedule(T, R, GATE_POLL, tick) end
  if step then schedule(T, R, delayAfter(T, step), tick) end
end

--- One RunTo pass: steps back to back up to R.target, polling a closed gate.
local function runToPass(T, R)
  while live(T, R) and R.playing and R.pos < R.target do
    local step, code = stepOnce(T, R, false)
    if code == "settling" then return schedule(T, R, GATE_POLL, runToPass) end
    if not step then return end   -- failed (paused), done, or the session changed
  end
  if live(T, R) and R.playing then
    R.playing, R.settling = false, false
    T.ctx.notify()
  end
end

--- RunTo: Sim-internal, handed to the panel as ctx.runTo (OWNER_SCOPE C.7).
local function runTo(T, index)
  local R = current(T)
  local code = blocked(T, R)
  if code then return false, code end
  if R.playing then return false, "playing" end
  index = floor(tonumber(index) or 0)
  if index > #R.steps then index = #R.steps end
  if index <= R.pos then return false, "done" end
  R.paused, R.playing, R.target = false, true, index
  T.ctx.notify()
  runToPass(T, R)
  return true
end

-- ── the members ──────────────────────────────────────────────────────────────────────────────

--- Steps and Step.
local function installStep(sim, T)
  function sim.Steps()
    local R = current(T)
    return R and R.steps or {}
  end

  function sim.Step()
    return stepOnce(T, current(T), true)
  end
end

--- Run, Pause, Resume and Restart.
local function installRun(sim, T)
  function sim.Run()
    local R = current(T)
    local code = blocked(T, R)
    if code then return false, code end
    if R.playing then return false, "playing" end
    R.paused, R.playing, R.target = false, true, nil
    T.ctx.notify()
    tick(T, R)
    return true
  end

  function sim.Pause()
    local R = current(T)
    if not R or not R.playing then return false, "notPlaying" end
    cancelTimer(R)
    R.playing, R.paused, R.settling = false, true, false
    T.ctx.notify()
    return true
  end

  function sim.Resume()
    local R = current(T)
    if not R or not R.paused then return false, "notPaused" end
    R.paused = false
    return sim:Run()
  end

  function sim.Restart()
    local R = current(T)
    if not R then return false, "notRunning" end
    local scenario, size = R.session.scenario, R.session.size
    sim:Stop("restart")
    if not sim:Start({ scenario = scenario, size = size }) then return false, "refused" end
    return true
  end
end

-- ── the verbs: sim:RunVerb(line) -> ok, code ────────────────────────────────────────────────
--
-- One grammar for every host's `/<slash> sim`, printed through d.print. The generic verbs come
-- first: the empty line (status, usage, and the panel opened), `start <name> [size]`, the six
-- controls, `status` and `panel`. Then the host's d.verbs, as { parse = fn(words) -> cmd|nil,
-- run = fn(cmd, sim) -> ok, code, free = bool? }, where words[1] is the verb (lowercased). Anything
-- else prints the usage. There is NO `help` verb (OWNER_SCOPE C.7): `help` is an unknown word.
--
-- FREE VERBS run idle: the empty line, status, start and panel, and a host verb marked free. Every
-- other verb prints NOT_RUNNING while no session is active.
--
-- WHY LINES. A failure code prints the library's line for it (WHY, below) or else d.why[code].
-- SILENT codes print nothing more, because their line has printed already: `refused` (Start's own
-- refusal line), `failed` (STEP_FAILED), and `usage` (the usage itself). A typed `step` whose gate
-- is closed answers `settling` after Step printed the gate's line, so that one is silent too.
--
-- Host wiring is one Slash-1.0 feature-verb row, `{"sim", desc, function(rest) NS.Sim:RunVerb(rest)
-- end}`, which the dispatcher refuses while the addon is disabled. Slash only: no launcher entry
-- and no key binding (OWNER_SCOPE C.11). Documented in docs/api/Sim, not enforced here.

local CONTROLS = { run = "Run", step = "Step", pause = "Pause", resume = "Resume", restart = "Restart", stop = "Stop" }
local WHY = { notRunning = "NOT_RUNNING", building = "BUILDING", playing = "PLAYING", done = "DONE",
  settling = "SETTLING", notPlaying = "NOT_PLAYING", notPaused = "NOT_PAUSED" }
local SILENT = { refused = true, failed = true, usage = true }
local USAGE = { "USAGE_BARE", "USAGE_START", "USAGE_RUN", "USAGE_STEP", "USAGE_PAUSE", "USAGE_RESUME",
  "USAGE_RESTART", "USAGE_STOP", "USAGE_STATUS", "USAGE_PANEL" }

--- The line's words, split on whitespace, the first lowercased (the verb).
local function wordsOf(line)
  local words = {}
  for w in tostring(line or ""):gmatch("%S+") do words[#words + 1] = w end
  if words[1] then words[1] = words[1]:lower() end
  return words
end

--- Print the WHY line for a failure code, unless it is silent or has no line.
local function why(ctx, code)
  if code == nil or SILENT[code] then return end
  local key = WHY[code]
  local line = key and ctx.tr(key) or nil
  if not line then
    local host = ctx.d.why
    line = type(host) == "table" and rawget(host, code) or nil
  end
  if line ~= nil then ctx.print(tostring(line)) end
end

--- Print the usage: every USAGE_* line formatted with d.slash, then the host's d.usage lines.
local function printUsage(ctx)
  local slash = tostring(ctx.d.slash)
  for _, key in ipairs(USAGE) do ctx.print(ctx.tr(key):format(slash)) end
  if type(ctx.d.usage) == "table" then
    for _, line in ipairs(ctx.d.usage) do ctx.print(tostring(line)) end
  end
  return false, "usage"
end

--- The state word of a live status.
local function stateWord(ctx, st)
  if not st.ready then return ctx.tr("STATE_BUILDING") end
  if st.settling then return ctx.tr("STATE_SETTLING") end
  if st.total > 0 and st.pos >= st.total then return ctx.tr("STATE_DONE") end
  if st.playing then return ctx.tr("STATE_PLAYING") end
  if st.paused then return ctx.tr("STATE_PAUSED") end
  return ctx.tr("STATE_WAITING")
end

--- The library's status line for Status() `st`.
local function statusText(ctx, st)
  if not st.active then
    return ctx.tr("STATUS_IDLE"):format(table.concat(ctx.d.scenarios.names, ", "))
  end
  local scenario = tostring(st.scenario)
  if st.size ~= nil then
    local size = st.size == 0 and ctx.tr("STATUS_RANDOM") or tostring(st.size)
    scenario = ctx.tr("STATUS_SIZE"):format(scenario, size)
  end
  return ctx.tr("STATUS_RUNNING"):format(scenario, tostring(st.seed), st.pos, st.total, stateWord(ctx, st))
end

--- Print the status line, then the host's d.statusLine(status, session): a line or a list.
local function printStatus(sim, ctx)
  local st = sim:Status()
  ctx.print(statusText(ctx, st))
  local extra = ctx.d.statusLine
  if type(extra) ~= "function" then return true end
  local ok, more = pcall(extra, st, ctx.session())
  if not ok then
    ctx.debug("statusLine failed: %s", tostring(more))
  elseif type(more) == "table" then
    for _, line in ipairs(more) do ctx.print(tostring(line)) end
  elseif more ~= nil then
    ctx.print(tostring(more))
  end
  return true
end

--- The scenario a typed name means: an exact name, else the one that matches it ignoring case.
local function scenarioNamed(ctx, name)
  local names = ctx.d.scenarios.names
  for _, known in ipairs(names) do if known == name then return known end end
  local lower = name:lower()
  for _, known in ipairs(names) do
    if type(known) == "string" and known:lower() == lower then return known end
  end
  return name
end

--- `start <name> [size]`.
local function verbStart(sim, ctx, words)
  if not words[2] then return printUsage(ctx) end
  local ok = sim:Start({ scenario = scenarioNamed(ctx, words[2]), size = tonumber(words[3]) })
  if not ok then return false, "refused" end   -- Start printed its line
  return true
end

--- One of the six controls, with a session live: its own lines, then its WHY line on a failure.
local function verbControl(sim, ctx, verb)
  local a, code
  if verb == "stop" then
    a = sim:Stop("stop")
    if not a then code = "notRunning" end
  else
    a, code = sim[CONTROLS[verb]](sim)
  end
  if a then return true end
  if not (verb == "step" and code == "settling") then why(ctx, code) end   -- Step printed the gate's line
  return false, code
end

--- A host verb from d.verbs: the free rule, parse, then run, each under pcall.
local function verbHost(sim, ctx, spec, words)
  if not spec.free and not sim:IsActive() then
    why(ctx, "notRunning")
    return false, "notRunning"
  end
  local ok, cmd = pcall(spec.parse, words)
  if ok and cmd == nil then return printUsage(ctx) end
  local done, code
  if ok then ok, done, code = pcall(spec.run, cmd, sim) end
  if not ok then
    ctx.debug("verb %s failed: %s", tostring(words[1]), tostring(done or cmd))
    ctx.print(ctx.tr("VERB_FAILED"):format(tostring(words[1])))
    return false, "error"
  end
  if done then return true end
  why(ctx, code)
  return false, code
end

--- RunVerb's body: the generic grammar, then the host's verbs, then the usage.
local function runVerb(sim, ctx, line)
  local words = wordsOf(line)
  local verb = words[1]
  if not verb then
    printStatus(sim, ctx)
    printUsage(ctx)
    sim:ShowPanel()
    return true
  end
  if verb == "status" then return printStatus(sim, ctx) end
  if verb == "panel" then sim:TogglePanel(); return true end
  if verb == "start" then return verbStart(sim, ctx, words) end
  if CONTROLS[verb] then
    if not sim:IsActive() then
      why(ctx, "notRunning")
      return false, "notRunning"
    end
    return verbControl(sim, ctx, verb)
  end
  local host = ctx.d.verbs
  local spec = type(host) == "table" and rawget(host, verb) or nil
  if type(spec) == "table" and type(spec.parse) == "function" and type(spec.run) == "function" then
    return verbHost(sim, ctx, spec, words)
  end
  return printUsage(ctx)
end

--- Attach the step machine to one instance. Called by Sim:New with the instance and the
--- handshake's internal ctx (Sim.lua); overwrites the shell's fallbacks.
function lib.__AttachTimeline(sim, ctx)
  local T = { sim = sim, ctx = ctx, R = nil }
  installStep(sim, T)
  installRun(sim, T)
  function sim.RunVerb(_, line) return runVerb(sim, ctx, line) end

  -- Stop's step (1): cancel the pending tick or poll and forget the run.
  ctx.cancelRun = function()
    local R = T.R
    T.R = nil
    if R then
      cancelTimer(R)
      R.playing, R.paused, R.settling = false, false, false
    end
  end

  -- Status()'s timeline fields.
  ctx.status = function(t)
    local R = current(T)
    if not R then return end
    t.pos, t.total = R.pos, #R.steps
    t.playing, t.paused, t.settling = R.playing, R.paused, R.settling
  end

  -- Sim-internal: the panel's click-ahead (SimPanel.lua). Never an instance member.
  ctx.runTo = function(index) return runTo(T, index) end
end
