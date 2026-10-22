-- LibKa0s-Sim-1.0 — the in-client simulator's shell: the Compat answer seam.
--
-- ── WHY THIS IS A LIBRARY ────────────────────────────────────────────────────────────────────
--
-- Three hosts (DropWatcher today; LootHistory and BankLedger next) simulate the client the same
-- way: every client read and every outward action goes through the host's own Compat table, and
-- while a simulation runs that table answers from the simulator instead of the client. DropWatcher
-- wrote the seam first (core/SimSeam.lua); the other two would have copied it. The owner ruled the
-- seam, the session and the step machine into one major with one set of semantics (LibKa0s#54,
-- the design challenge's OWNER_SCOPE C), so a fix to "a guarded member never reaches the client"
-- is made once.
--
-- ── THE SEAM ─────────────────────────────────────────────────────────────────────────────────
--
-- Sim:NewSeam(compat, opts) wraps the host's Compat table IN PLACE, once, at file load: every
-- function member not in opts.pure becomes a closure whose idle path is one upvalue-field test,
--
--   if state.active and (g or not state.bypass) then return answer(key, live, g, ...) end
--   return live(...)
--
-- so an idle seam costs one table read per call and allocates nothing. While a bound session is
-- active, `answer` hands the call to the key's provider as provider(fallback, ...), where fallback
-- is opts.guarded[key] or the live member; with no provider, fallback(...) answers. A guarded member
-- never reaches the client while active, inside Live included, and a provider's first argument is
-- the guarded answer, never live. Idle, a guarded member calls live.
--
-- The seam's active flag is driven only by a bound session (Sim:New, below). Until one binds and
-- starts, the seam is idle.
--
-- ── THE SESSION ──────────────────────────────────────────────────────────────────────────────
--
-- Sim:New(d) runs when the host's simulator module loads and binds the seam it is handed: one seam
-- binds one session, and a second New on it raises. The instance's members are colon-called
-- closures over a private state table, so nothing a host can index mutates them:
--
--   Start(opts)      -> ok, line   unknown scenario, already running, refusal (inside seam:Live),
--                                  the stood-down backstop; then the session, STARTED, prepare.
--                                  The scenarios are read at call time (a def listed after New
--                                  starts, checked as New checks), and prepare gets a copy of the
--                                  caller's opts, extra fields kept (minor 2)
--   Stop(reason)     -> bool       the two-phase stop below; re-entrancy-safe (OWNER_SCOPE C.1)
--   Fire(event, ...) -> n          deliver under pcall, only while live and not stood down
--   After(delay, fn) -> handle     a timer that dies with its session; handle:Cancel() forgets it
--   OnStopGuarded(fn), OnStop(fn), AddListener(fn), DeliverForCleanup(event, ...),
--   IsActive(), IsDelivering(), Session(), Status()
--
-- THE STOP, in order. `stopping` is set as Stop is entered, which is what makes a Stop from inside
-- deliver, a listener, an OnStop callback or a second call a no-op answering false. Every step
-- after the first is pcalled, so one that raises never skips the rest:
--   (1) cancel the run and every session timer; (2) stopping: IsActive() stays true and the seam
--   still answers, but Fire and After refuse; (3) the OnStopGuarded list; (4) the seam off, the
--   session and delivering cleared, the cleanup phase entered; (5) the OnStop list, where
--   DeliverForCleanup is legal; (6) the cleanup phase left, the panel hidden when stood down or
--   repainted, listeners told; (7) the stop line and one debug line with the event count.
--
-- `ready()`, the callback prepare is handed, is bound to the session that issued it: a ready()
-- from an earlier session (after a restart, or a stop then a start) and a second ready() from
-- this one are both ignored (C.1).
--
-- ── THE HOST CONTRACT (OWNER_SCOPE C.4) ──────────────────────────────────────────────────────
--
-- Host members never hang on the library instance. The host keeps its own table (for example
-- NS.SimHost) for its Status extras, HistoryLog, MarkGUID, SetRestriction and the like, and holds
-- the seam separately for SetProvider. Host fields of a running session go on the session table
-- itself (Session(), the host bag); the library's own fields there are read-only by convention.
--
-- Timeline, verb and panel members are installed here as fallbacks (Steps and PanelRows answer {},
-- RunVerb prints NO_TIMELINE and answers false, "absent"), and SimTimeline.lua and SimPanel.lua
-- overwrite them through the lib.__AttachTimeline / lib.__AttachPanel handshake New calls, the way
-- Perf's no-panel fallbacks work. The handshake's ctx table is library-internal, not contract.
--
-- ── WHAT IT DELIBERATELY IS NOT ──────────────────────────────────────────────────────────────
--
--   * no query of the active state or of a key's guarded status on the seam (OWNER_SCOPE C.7):
--     the session answers whether it is active, and a host knows its own guarded keys;
--   * no auto-wrap metatable on the host's table (C.8): a member added or replaced after NewSeam
--     shows up in seam:Unwrapped(), and every host suite asserts that list is empty;
--   * no restriction or chat-lockdown simulation (C.9): that is host code (DropWatcher);
--   * no SavedVariables: the library never reads or writes one; session-only stores are the host's;
--   * no behavior flags: every host difference is data, a host callback with one meaning, or a
--     presentation argument.
--
-- ── PAYLOAD WEIGHT ───────────────────────────────────────────────────────────────────────────
--
-- Whole-folder vendoring ships this major into every consumer. Its file bodies only define
-- functions: no frame, timer or event registration exists until NewSeam or New is called (and no
-- timer until a session calls After), so a host that never simulates pays parse time and nothing
-- else.
--
-- Depends on LibStub and LibKa0s-Core-1.0. No Core member is called; the gate keeps the payload's
-- presence a single question.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Sim-1.0", 2
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR
lib.MODULES = lib.MODULES or {}
lib.MODULES.Sim = MINOR

local type, pairs, ipairs, tostring, tonumber, select, error, pcall, xpcall, unpack, rawget, rawequal =
  type, pairs, ipairs, tostring, tonumber, select, error, pcall, xpcall, unpack, rawget, rawequal
local sort, concat = table.sort, table.concat

-- seam -> its private state; compat -> true once wrapped. Weak-keyed, and no value refers back to
-- its key (Lua 5.1 weak keys are not ephemerons), so a host that drops its compat table and seam
-- lets both be collected. Sim:New (the session) reaches a seam's state through STATE, and that is
-- the only route to its active flag.
local STATE = setmetatable({}, { __mode = "k" })
local WRAPPED = setmetatable({}, { __mode = "k" })

--- Pack a call's answers with their count, so nil holes survive the unpack.
local function pack(...) return { n = select("#", ...), ... } end

--- The error and its stack as one string: the client's debugstack, else Lua's own traceback.
local function traceback(e)
  local msg = tostring(e)
  local ds = rawget(_G, "debugstack")
  if type(ds) == "function" then return msg .. "\n" .. tostring(ds(3)) end
  local dbg = rawget(_G, "debug")
  if type(dbg) == "table" and type(dbg.traceback) == "function" then return dbg.traceback(msg, 3) end
  return msg .. "\n(no stack available)"
end

--- Answer member `key` for an active session: its provider handed the fallback, or the fallback.
local function answer(state, key, live, g, ...)
  local fallback = g or live
  local provider = state.providers[key]
  if provider then return provider(fallback, ...) end
  return fallback(...)
end

--- One wrapped member. The idle path is the single upvalue-field test the header describes.
local function wrap(state, key, live, g)
  return function(...)
    if state.active and (g or not state.bypass) then return answer(state, key, live, g, ...) end
    return live(...)
  end
end

--- Raise unless `opts` describes a seam NewSeam can build.
local function checkOpts(compat, opts)
  if type(compat) ~= "table" then error(MAJOR .. ": NewSeam(compat, opts): compat must be a table", 3) end
  if type(opts) ~= "table" then error(MAJOR .. ": NewSeam(compat, opts): opts must be a table", 3) end
  if type(opts.name) ~= "string" or opts.name == "" then
    error(MAJOR .. ": NewSeam: opts.name must be a non-empty string", 3)
  end
  if opts.debug ~= nil and type(opts.debug) ~= "function" then
    error(MAJOR .. ": NewSeam(" .. opts.name .. "): opts.debug must be a function", 3)
  end
  if WRAPPED[compat] then
    error(MAJOR .. ": NewSeam(" .. opts.name .. "): this compat table is already wrapped", 3)
  end
end

--- The keys NewSeam wraps: every function member not in `pure`, sorted.
local function wrappableKeys(compat, pure)
  local keys = {}
  for key, member in pairs(compat) do
    if type(member) == "function" and not pure[key] then keys[#keys + 1] = key end
  end
  sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

--- Raise on a guarded entry that names no wrapped member or whose answer is not a function.
local function checkGuarded(name, guarded, isKey)
  for key, fn in pairs(guarded) do
    if not isKey[key] then
      error(MAJOR .. ": NewSeam(" .. name .. "): guarded key '" .. tostring(key)
        .. "' is not a wrapped member (pure, unknown or not a function)", 3)
    end
    if type(fn) ~= "function" then
      error(MAJOR .. ": NewSeam(" .. name .. "): guarded['" .. tostring(key) .. "'] must be a function", 3)
    end
  end
end

--- Write one line to the state's debug sink. A sink that raises never masks the caller's error.
local function debugLine(state, fmt, ...)
  local sink = state.debug
  if type(sink) == "function" then pcall(sink, "Sim", fmt, ...) end
end

--- seam:Live's body: run fn with bypass on, restore it on every exit, keep the original error.
local function liveCall(state, fn, ...)
  if type(fn) ~= "function" then error(MAJOR .. ": " .. state.name .. ": Live(fn): fn must be a function", 3) end
  local args, trace = pack(...), nil
  local function run() return fn(unpack(args, 1, args.n)) end
  local function onError(e) trace = traceback(e); return e end
  local was = state.bypass
  state.bypass = true
  local out = pack(xpcall(run, onError))
  state.bypass = was
  if not out[1] then
    debugLine(state, "%s: Live raised: %s", state.name, trace or tostring(out[2]))
    error(out[2], 0)
  end
  return unpack(out, 2, out.n)
end

--- The seam's four members, closed over its state. Dot-defined with an ignored self, so a
--- LibStub upgrade never matters to an instance a host already holds.
local function seamMembers(state, compat)
  local seam = {}
  function seam.SetProvider(_, key, fn)
    if not state.isKey[key] then
      error(MAJOR .. ": " .. state.name .. ": SetProvider: '" .. tostring(key)
        .. "' is not a wrapped member (pure, unknown or not a function)", 2)
    end
    if fn ~= nil and type(fn) ~= "function" then
      error(MAJOR .. ": " .. state.name .. ": SetProvider('" .. key .. "'): the provider must be a function", 2)
    end
    if fn ~= nil and state.providers[key] ~= nil then
      error(MAJOR .. ": " .. state.name .. ": SetProvider('" .. key
        .. "'): the key already has a provider; release it with nil first", 2)
    end
    state.providers[key] = fn
  end
  function seam.Live(_, fn, ...) return liveCall(state, fn, ...) end
  function seam.Keys()
    local out = {}
    for i, key in ipairs(state.keys) do out[i] = key end
    return out
  end
  function seam.Unwrapped()
    local out = {}
    for key, member in pairs(compat) do
      if type(member) == "function" and not state.pure[key] and not rawequal(state.wrappers[key], member) then
        out[#out + 1] = key
      end
    end
    sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
  end
  return seam
end

--- Wrap the host's Compat table in place, once, and answer its seam.
--- @param compat table the host's own Compat table
--- @param opts table { name = string, pure = {[key]=true}?, guarded = {[key]=fn}?, debug = fn? }
--- @return table seam with SetProvider(key, fn), Live(fn, ...), Keys() and Unwrapped()
function lib:NewSeam(compat, opts)   -- luacheck: ignore 212/self
  checkOpts(compat, opts)
  local pure, guarded = opts.pure or {}, opts.guarded or {}
  local keys = wrappableKeys(compat, pure)
  local isKey = {}
  for _, key in ipairs(keys) do isKey[key] = true end
  checkGuarded(opts.name, guarded, isKey)

  local state = {
    name = opts.name, debug = opts.debug, active = false, bypass = false,
    pure = pure, keys = keys, isKey = isKey, providers = {}, wrappers = {},
  }
  for _, key in ipairs(keys) do
    local w = wrap(state, key, compat[key], guarded[key])
    state.wrappers[key] = w
    compat[key] = w
  end
  local seam = seamMembers(state, compat)
  STATE[seam] = state
  WRAPPED[compat] = true
  return seam
end


-- ── STRINGS ──────────────────────────────────────────────────────────────────────────────────
--
-- Built-in English, every key overridable through the descriptor's `L`, read with rawget (tr,
-- below). SimTimeline.lua and SimPanel.lua add their own keys to the same table. STARTED is
-- neutral on purpose: "nothing is saved" is the host's guarantee, never the library's, so each
-- host overrides it with its own line.

lib.STRINGS = lib.STRINGS or {}
for key, line in pairs({
  STARTED          = "Simulation started (%s).",
  STOPPED          = "Simulation stopped.",
  STOPPED_RESTART  = "Simulation stopped to restart.",
  STOPPED_ERROR    = "Simulation stopped: it failed to build. The debug log has the error.",
  STOPPED_REASON   = "Simulation stopped (%s).",
  ALREADY_RUNNING  = "A simulation is already running.",
  STOOD_DOWN       = "A simulation cannot start while the addon is disabled.",
  UNKNOWN_SCENARIO = "Unknown scenario '%s'. Scenarios: %s.",
  NOT_RUNNING      = "No simulation is running.",
  NO_TIMELINE      = "The simulator's timeline is not loaded (SimTimeline.lua).",
}) do lib.STRINGS[key] = line end

-- The stop reasons with a library line of their own. Every other reason, `standDown` included,
-- prints STOPPED_REASON unless the host's stopText names it.
local LIBRARY_STOP = { stop = "STOPPED", restart = "STOPPED_RESTART", error = "STOPPED_ERROR" }

-- ── the descriptor ───────────────────────────────────────────────────────────────────────────

local REQUIRED = {
  { "name", "string" }, { "seam", "table" }, { "slash", "string" }, { "deliver", "function" },
  { "isStoodDown", "function" }, { "scenarios", "table" }, { "prepare", "function" }, { "play", "function" },
}
local OPTIONAL = {
  refusal = "function", gate = "function", verbs = "table", why = "table", usage = "table",
  statusLine = "function", stopText = "table", L = "table", print = "function", debug = "function",
  panel = "table",
}
-- Presentation only. No `button`, no `tooltip` (the library's own button and GameTooltip) and no
-- `store` (the panel position is session-only): OWNER_SCOPE C.7 and C.11.
local PANEL_FIELDS = {
  title = true, stepLabel = true, stepTip = true, startTip = true, stopTip = true, anchorTo = true, check = true,
}

--- Raise, naming the descriptor field, unless d[key] has type `wanted`. Perf's required() style.
local function required(d, key, wanted)
  if type(d[key]) ~= wanted then
    error(("%s: New: descriptor.%s must be a %s"):format(MAJOR, key, wanted), 4)
  end
end

--- Raise unless every optional field present has its type (stepDelay: a number or a function).
local function checkOptional(d)
  for key, wanted in pairs(OPTIONAL) do
    if d[key] ~= nil and type(d[key]) ~= wanted then
      error(("%s: New: descriptor.%s must be a %s"):format(MAJOR, key, wanted), 4)
    end
  end
  local delay = d.stepDelay
  if delay ~= nil and type(delay) ~= "number" and type(delay) ~= "function" then
    error(MAJOR .. ": New: descriptor.stepDelay must be a number or a function", 4)
  end
end

-- The scenario checks are New's and Start's alike (minor 2: Start reads the scenarios live, so a
-- def listed after New is checked on its first Start). Both callers sit at the same depth, so the
-- error level is fixed: this function (1), its caller (2), checkDescriptor or startRefusal (3), New
-- or Start (4), and the host's call site (5).

--- Raise, naming `verb`, unless sc carries a names list and a defs table.
local function checkShape(sc, verb)
  if type(sc) ~= "table" or type(sc.names) ~= "table" or type(sc.defs) ~= "table" then
    error(("%s: %s: descriptor.scenarios must carry a names list and a defs table"):format(MAJOR, verb), 5)
  end
end

--- Raise, naming `verb`, unless the listed scenario `name` has a def with a timeline; answer the def.
local function checkDef(sc, name, verb)
  local def = sc.defs[name]
  local at = ("%s: %s: descriptor.scenarios.defs.%s"):format(MAJOR, verb, tostring(name))
  if type(def) ~= "table" then error(at .. " is missing", 5) end
  if type(def.timeline) ~= "function" then error(at .. ".timeline must be a function", 5) end
  if def.sizes ~= nil and type(def.sizes) ~= "table" then error(at .. ".sizes must be a list", 5) end
  return def
end

--- Raise unless every scenario listed when New runs has a def with a timeline. An empty list is
--- accepted: a host may fill its scenarios after New, and Start reads them at call time.
local function checkScenarios(sc)
  checkShape(sc, "New")
  for _, name in ipairs(sc.names) do checkDef(sc, name, "New") end
end

--- Raise on a panel field that is not presentation.
local function checkPanel(panel)
  if panel == nil then return end
  for key in pairs(panel) do
    if not PANEL_FIELDS[key] then
      error(("%s: New: descriptor.panel.%s is not a panel field (title, stepLabel, stepTip, startTip, "
        .. "stopTip, anchorTo, check)"):format(MAJOR, tostring(key)), 4)
    end
  end
end

--- Validate the whole descriptor; answer the seam's private state.
local function checkDescriptor(d)
  if type(d) ~= "table" then error(MAJOR .. ": New(d): the descriptor must be a table", 3) end
  for _, field in ipairs(REQUIRED) do required(d, field[1], field[2]) end
  checkOptional(d)
  checkScenarios(d.scenarios)
  checkPanel(d.panel)
  local seamState = STATE[d.seam]
  if not seamState then error(MAJOR .. ": New: descriptor.seam must come from Sim:NewSeam", 3) end
  if seamState.bound then
    error(MAJOR .. ": New: descriptor.seam (" .. seamState.name .. ") is already bound: one seam binds one session", 3)
  end
  return seamState
end

-- ── the session's private helpers (S is one instance's private state) ────────────────────────

--- A library string, or the host's override for it. rawget, NOT a plain index: every Ka0s locale
--- table answers an unknown key with the key itself through a metatable, and a plain index would
--- take that for an override of every key (Perf's tr, the KickCD perf-panel defect).
local function tr(S, key)
  local L = S.d.L
  local v = type(L) == "table" and rawget(L, key) or nil
  if type(v) == "string" then return v end
  return lib.STRINGS[key] or key
end

--- Print one line through d.print, read at call time, else the default chat frame.
local function say(S, line)
  local p = S.d.print
  if type(p) == "function" then return p(line) end
  local frame = DEFAULT_CHAT_FRAME
  if frame and frame.AddMessage then frame:AddMessage(line) end
end

--- One SIM debug line through d.debug, read at call time. A sink that raises is ignored.
local function debugOut(S, fmt, ...)
  local sink = S.d.debug
  if type(sink) == "function" then pcall(sink, "SIM", fmt, ...) end
end

--- Tell every listener, each under pcall, that something moved.
local function notify(S)
  for _, fn in ipairs(S.listeners) do
    local ok, err = pcall(fn, S.sim)
    if not ok then debugOut(S, "listener failed: %s", tostring(err)) end
  end
end

--- Run `fn(...)` as one stop step: under pcall, a failure a debug line naming the step.
local function step(S, label, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then debugOut(S, "stop step %s failed: %s", label, tostring(err)) end
end

--- Run every registered stop callback, each its own step.
local function runList(S, list, label, ...)
  for i = 1, #list do step(S, label .. " #" .. i, list[i], ...) end
end

--- A one-shot client timer and its canceler: C_Timer.NewTimer, else C_Timer.After with a flag.
local function newTimer(delay, fn)
  local ct = C_Timer
  if type(ct) ~= "table" then return nil end
  if ct.NewTimer then return ct.NewTimer(delay, fn) end
  if not ct.After then return nil end
  local box = { off = false }
  ct.After(delay, function() if not box.off then fn() end end)
  function box.Cancel() box.off = true end
  return box
end

--- Cancel the run (the timeline's hook) and every live session timer. Stop's step (1).
local function cancelAll(S)
  local hook = S.ctx.cancelRun
  if type(hook) == "function" then step(S, "cancelRun", hook) end
  local live = {}
  for handle in pairs(S.timers) do live[#live + 1] = handle end
  for _, handle in ipairs(live) do handle:Cancel() end
end

--- Stop's step (4): the seam off, the session and delivering cleared, the cleanup phase entered.
local function seamOff(S)
  S.seamState.active = false
  S.session, S.delivering, S.ready, S.startOpts = nil, false, false, nil
  S.cleanup = true
end

--- Stop's step (6): leave the cleanup phase; hide the panel when stood down, else repaint it.
local function leaveCleanup(S)
  S.cleanup = false
  if S.d.isStoodDown() then S.sim:HidePanel() else S.sim:RefreshPanel() end
end

--- The line a stop prints: the host's stopText, the library's line for its own reasons, or the
--- generic reason line.
local function stopLine(S, reason)
  local hostText = S.d.stopText
  local line = type(hostText) == "table" and rawget(hostText, reason) or nil
  if type(line) == "string" then return line end
  local key = LIBRARY_STOP[reason]
  if key then return tr(S, key) end
  return tr(S, "STOPPED_REASON"):format(tostring(reason))
end

--- The def of the scenario `name`, read from d.scenarios at call time (minor 2): nil when `name`
--- is not listed; a listed name whose def is malformed raises as New does (a host programming error).
local function liveDef(S, name)
  local sc = S.d.scenarios
  checkShape(sc, "Start")
  for _, listed in ipairs(sc.names) do
    if listed == name then
      local def = checkDef(sc, name, "Start")   -- not a tail call: the error level counts this frame
      return def
    end
  end
  return nil
end

--- The line refusing Start(opts), or nil and the scenario's def when it may start. In order:
--- unknown scenario (the live names), already running, the host's refusal read inside seam:Live,
--- stood down.
local function startRefusal(S, opts)
  local d, name = S.d, opts.scenario
  local def = liveDef(S, name)
  if not def then
    return tr(S, "UNKNOWN_SCENARIO"):format(tostring(name), concat(d.scenarios.names, ", "))
  end
  if S.session or S.stopping then return tr(S, "ALREADY_RUNNING") end
  if d.refusal then
    local line = S.seam:Live(d.refusal, opts)
    if line ~= nil and line ~= false then return tostring(line) end
  end
  if d.isStoodDown() then return tr(S, "STOOD_DOWN") end
  return nil, def
end

--- A shallow copy of the caller's start opts with scenario, size and seed set to the resolved
--- values (minor 2), so a host's own start fields reach its prepare. The library reads no other
--- field, and the caller's table is never written.
local function resolvedOpts(opts, size, seed)
  local out = {}
  for k, v in pairs(opts) do out[k] = v end
  out.size, out.seed = size, seed
  return out
end

--- A seed for a session the host gave none: time-derived, and different on every call.
local function freshSeed(S)
  S.seeds = S.seeds + 1
  return ((time() or 0) * 7919 + S.seeds) % 2147483647
end

--- The ready() prepare is handed, bound to this session: a stale or second call is ignored (C.1).
local function readyFor(S, session)
  return function()
    if S.session ~= session or S.stopping or S.ready then return end
    S.ready = true
    debugOut(S, "ready: %s", tostring(session.scenario))
    notify(S)
  end
end

--- Run the host's prepare under pcall; an error stops the session with reason `error`.
local function runPrepare(S, session, def, opts)
  local ok, err = pcall(S.d.prepare, session, def, opts, readyFor(S, session))
  if ok then return end
  debugOut(S, "prepare failed: %s", tostring(err))
  if S.session == session then S.sim:Stop("error") end
end

-- ── the session's members ────────────────────────────────────────────────────────────────────

--- Start, Stop and the two predicates.
local function installLifecycle(sim, S)
  function sim.Start(_, opts)
    opts = type(opts) == "table" and opts or {}
    local line, def = startRefusal(S, opts)
    if line then say(S, line); return false, line end
    local size = def.sizes and (tonumber(opts.size) or 0) or nil
    local seed = tonumber(opts.seed) or freshSeed(S)
    local session = { sim = true, scenario = opts.scenario, size = size, seed = seed, startedAt = time(), events = 0 }
    S.session, S.ready, S.delivering = session, false, false
    S.startOpts = resolvedOpts(opts, size, seed)   -- Restart's copy (ctx.startOpts), apart from prepare's
    S.seamState.active = true
    local started = tr(S, "STARTED"):format(tostring(def.label or opts.scenario))
    say(S, started)
    debugOut(S, "started %s (size %s, seed %s)", tostring(opts.scenario), tostring(size), tostring(seed))
    runPrepare(S, session, def, resolvedOpts(opts, size, seed))
    if S.session ~= session then return false end   -- it ended inside prepare; its stop line printed
    notify(S)
    return true, started
  end

  function sim.Stop(_, reason)
    if S.stopping or not S.session then return false end
    reason = (type(reason) == "string" and reason ~= "") and reason or "stop"
    local session = S.session
    S.stopping = true                                     -- (2), set first: the re-entrancy guard
    cancelAll(S)                                          -- (1)
    runList(S, S.guarded, "guarded", session)             -- (3) the seam still answers
    seamOff(S)                                            -- (4)
    runList(S, S.onStop, "onStop", session, reason)       -- (5) DeliverForCleanup is legal
    step(S, "panel", leaveCleanup, S)                     -- (6)
    notify(S)
    step(S, "print", function() say(S, stopLine(S, reason)) end)   -- (7)
    debugOut(S, "stopped (%s): %d events", reason, session.events)
    S.stopping = false
    return true
  end

  function sim.IsActive() return S.session ~= nil end
  function sim.IsDelivering() return S.delivering == true end
  function sim.Session() return S.session end
end

--- Fire, DeliverForCleanup and After.
local function installDelivery(sim, S)
  function sim.Fire(_, event, ...)
    local session = S.session
    if not session or S.stopping then return 0 end
    if S.d.isStoodDown() then sim:Stop("standDown"); return 0 end   -- the self-stop backstop
    session.events = session.events + 1
    debugOut(S, "event %s", tostring(event))
    local outer = S.delivering
    S.delivering = true
    local ok, n = pcall(S.d.deliver, event, ...)
    S.delivering = (S.session == session) and outer or false
    if not ok then
      debugOut(S, "deliver %s failed: %s", tostring(event), tostring(n))
      return 0
    end
    return tonumber(n) or 0
  end

  function sim.DeliverForCleanup(_, event, ...)
    if not S.cleanup or S.d.isStoodDown() then return 0 end
    debugOut(S, "cleanup event %s", tostring(event))
    local ok, n = pcall(S.d.deliver, event, ...)
    if not ok then
      debugOut(S, "cleanup deliver %s failed: %s", tostring(event), tostring(n))
      return 0
    end
    return tonumber(n) or 0
  end

  function sim.After(_, delay, fn)
    local session = S.session
    if not session or S.stopping then return nil end
    if type(fn) ~= "function" then error(MAJOR .. ": " .. S.d.name .. ": After(delay, fn): fn must be a function", 2) end
    local handle = {}
    local timer = newTimer(tonumber(delay) or 0, function()
      if not S.timers[handle] then return end
      S.timers[handle] = nil
      if S.session ~= session or S.stopping then return end
      local ok, err = pcall(fn)
      if not ok then debugOut(S, "timer failed: %s", tostring(err)) end
    end)
    if not timer then return nil end
    function handle.Cancel()
      S.timers[handle] = nil
      timer:Cancel()
    end
    S.timers[handle] = true
    return handle
  end
end

--- The permanent, ordered registrations, and Status.
local function installRegistrations(sim, S)
  local function adder(list, member)
    return function(_, fn)
      if type(fn) ~= "function" then error(MAJOR .. ": " .. S.d.name .. ": " .. member .. "(fn): fn must be a function", 2) end
      list[#list + 1] = fn
    end
  end
  sim.OnStopGuarded = adder(S.guarded, "OnStopGuarded")
  sim.OnStop = adder(S.onStop, "OnStop")
  sim.AddListener = adder(S.listeners, "AddListener")

  function sim.Status()
    local s = S.session
    local t = { active = s ~= nil, ready = S.ready, pos = 0, total = 0, playing = false, paused = false, settling = false }
    if s then t.scenario, t.size, t.seed, t.startedAt, t.events = s.scenario, s.size, s.seed, s.startedAt, s.events end
    local extra = S.ctx.status
    if type(extra) == "function" then extra(t) end
    return t
  end
end

--- Fallbacks for every timeline, verb and panel member, which SimTimeline.lua and SimPanel.lua
--- overwrite when they attach. A host can call any of them whether or not those files loaded.
local function installFallbacks(sim, S)
  local function absent() return false, "absent" end
  function sim.Steps() return {} end
  function sim.Step() return nil, "absent" end
  sim.Run, sim.Pause, sim.Resume, sim.Restart = absent, absent, absent, absent
  function sim.RunVerb()
    say(S, tr(S, "NO_TIMELINE"))
    return false, "absent"
  end
  function sim.ShowPanel() return false end
  function sim.HidePanel() end
  function sim.TogglePanel() return false end
  function sim.RefreshPanel() end
  function sim.ResetPanelPosition() end
  function sim.IsPanelShown() return false end
  function sim.PanelRows() return {} end
end

--- The attach handshake's internal table: what SimTimeline.lua and SimPanel.lua read and the
--- fields SimTimeline.lua sets on it (cancelRun, Stop's step 1; status, filling Status()'s timeline
--- fields; runTo, the click-ahead SimPanel.lua drives, which is never an instance member).
--- startOpts (minor 2) answers a fresh copy of the live session's resolved start opts, the host's
--- extra fields included, or nil while idle: what Restart starts again with.
local function newCtx(S)
  return {
    d = S.d,
    tr = function(key) return tr(S, key) end,
    print = function(line) return say(S, line) end,
    debug = function(fmt, ...) return debugOut(S, fmt, ...) end,
    notify = function() return notify(S) end,
    session = function() return S.session end,
    stopping = function() return S.stopping end,
    ready = function() return S.ready end,
    startOpts = function()
      if not S.startOpts then return nil end
      local out = {}
      for k, v in pairs(S.startOpts) do out[k] = v end
      return out
    end,
  }
end

--- Bind one session to the seam the descriptor names and answer its instance.
--- @param d table the descriptor (docs/api/Sim): name, seam, slash, deliver, isStoodDown, scenarios,
---   prepare, play are required
--- @return table sim
function lib:New(d)   -- luacheck: ignore 212/self
  local seamState = checkDescriptor(d)
  local sim = {}
  local S = {
    d = d, sim = sim, seam = d.seam, seamState = seamState, seeds = 0,
    session = nil, stopping = false, cleanup = false, delivering = false, ready = false,
    timers = {}, guarded = {}, onStop = {}, listeners = {},
  }
  S.ctx = newCtx(S)
  seamState.bound = true
  -- Once bound, Live's traceback goes to the session's own debug sink, as a SIM line.
  seamState.debug = function(_, fmt, ...) debugOut(S, fmt, ...) end
  installLifecycle(sim, S)
  installDelivery(sim, S)
  installRegistrations(sim, S)
  installFallbacks(sim, S)
  if lib.__AttachTimeline then lib.__AttachTimeline(sim, S.ctx) end
  if lib.__AttachPanel then lib.__AttachPanel(sim, S.ctx) end
  return sim
end
