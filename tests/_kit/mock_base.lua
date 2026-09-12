-- testkit/mock_base.lua — the universal half of every Ka0s addon's WoW-API mock.
--
-- Returns a BUILDER, so each run gets a fresh, isolated environment. An addon's own
-- tests/wow_mock.lua calls this and then overwrites the handful of keys that are genuinely its own
-- (bag APIs, spell APIs, absorb APIs, …). Plain per-key overwrite — no merge machinery, because the
-- builder hands back a fresh table every call and readability is worth more than cleverness here.
--
-- WHAT BELONGS HERE: an API every addon in the collection touches, or would if it grew a window.
-- WHAT DOES NOT: anything only one addon calls. A mock that stubs every addon's APIs for everyone
-- is one more thing every future test has to reason about, and it hides a missing stub behind a
-- neighbor's.
--
-- ── Fidelity rules, which are the whole reason this is one file rather than eight ──────────────
--
-- 1. A stub that silently succeeds is worse than no stub. If production code branches on a return
--    value, the mock must return something a branch can distinguish — not the frame, not nil.
-- 2. Getters used in ARITHMETIC or CONCATENATION must return real numbers and strings.
--    LibKa0s-Options-1.0's scrollbar patch multiplies GetHeight() and concatenates GetName();
--    both raise on a table, and the metatable's blanket "return the frame" would supply
--    exactly that.
-- 3. Anything a test needs to OBSERVE must be recorded, not no-opped. Event registration, script
--    handlers and widget creation order are all load-bearing for at least one suite: a no-op
--    RegisterUnitEvent would let a widened or dropped per-unit filter pass the entire suite.
-- 4. Anything a test needs to DRIVE must be fireable. `__fire` on frames and on AceGUI widgets is
--    what makes the lazy first-OnShow render and the OnValueChanged write path reachable at all.
-- 5. Model the awkward real behavior, not the convenient one. AceDB's copyDefaults merges in place
--    and AceConsole's Embed clobbers a same-named custom Print and Printf — all are reproduced
--    here, because each has already caused a real bug that a friendlier mock would have hidden.
--
-- ── Known divergence, deliberately kept ────────────────────────────────────────────────────────
--
-- `CreateTexture` and `CreateFontString` answer from the metatable and so return the FRAME ITSELF
-- rather than a distinct object. WhatGroup's and KickCD's mocks make distinct objects and treat it
-- as a correctness requirement, and they are right — a font string and its parent are not one
-- object, and the aliasing has already forced a workaround in LibKa0s's own PerfPanel.lua (which
-- records `__label`/`__state` on the button instead of asking the FontString).
--
-- It is kept for now because changing it is not a harness change: AbsorbTracker's tests/perf.lua
-- memoizes frame proxies specifically BECAUSE `bar.valueText` and `bar.statusBar` are the same
-- table, so distinct objects move the api/iter parity figure, and tests/test_display.lua counts
-- Show/Hide calls that currently land on one shared object. Fixing it is a deliberate change with
-- its own test updates and a fresh parity baseline — not something to smuggle into an extraction.

local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = deepcopy(v) end
  return r
end

-- The atlas sizes this kit publishes, and the one table `SetAtlas` reads.
--
-- THESE ARE A FIXTURE, NOT A MEASUREMENT. Nothing here has been read off a client; they are stand-in
-- figures chosen so that art the client draws at different heights answers at different heights here
-- too, which is the only property a geometry assertion can actually rest on. A test must therefore
-- read the figure it expects OUT of this table rather than hard-coding it -- a case pinned to the
-- literal 28 is a case that goes red for the wrong reason the day a real measurement corrects it.
--
-- The two tab families are the reason the table exists at all. `OptionsWidgets.lua`'s row pitch is
-- the UNSELECTED tab art's own height, measured through a probe texture, and the selected art is
-- taller; a fixture that answered one number for both could not fail a selection-invariance
-- assertion, which is how anti-patterns #70 shipped green. The 28/33 pair is the one LibKa0s's own
-- tab suite has used as its stand-in since the strip was written, kept so the two agree.
--
-- It is a single shared table on purpose: that is what "kit-published" means here, and a consumer
-- that needs an atlas the collection has not needed yet adds it in its own tests/wow_mock.lua. A
-- test that mutates it is mutating it for every instance in the process, and owes it a restore.
local ATLAS_SIZES = {
  ["Options_Tab_Left"]          = { 12,  28 },
  ["Options_Tab_Middle"]        = { 20,  28 },
  ["Options_Tab_Right"]         = { 12,  28 },
  ["Options_Tab_Active_Left"]   = { 12,  33 },
  ["Options_Tab_Active_Middle"] = { 20,  33 },
  ["Options_Tab_Active_Right"]  = { 12,  33 },
  ["Options_InnerFrame"]        = { 256, 256 },
  ["Options_HorizontalDivider"] = { 256, 8 },
}

-- A universal frame stub: any PascalCase method is a no-op returning the frame itself; other
-- (lowercase/custom) field access misses through to nil so addon code can stash custom fields.
local function stubFrame()
  local f = { __shown = false, __scripts = {} }
  -- Track shown state so IsShown/Toggle behave (a debug console's visibility checkbox reads it).
  -- Every other capitalized method still no-ops through the metatable below.
  function f:Show() self.__shown = true; return self end
  function f:Hide() self.__shown = false; return self end
  function f:SetShown(v) self.__shown = not not v; return self end
  function f:IsShown() return self.__shown end
  function f:IsVisible() return self.__shown end

  -- Enabled state, TRACKED rather than no-opped. The metatable below answers any capitalized
  -- call with the frame itself, so `IsEnabled()` came back truthy no matter what SetEnabled was
  -- told -- and an `assertFalse(b:IsEnabled())` could never fail, in this repo or in any
  -- consumer's suite. Same fidelity rule as GetHeight/GetWidth (rule 2: return real values, not
  -- the frame), applied to the one boolean it was missed on. Blizzard's own tab groups mark the
  -- selected tab by DISABLING it, which is what turns this from a gap into a blocker.
  f.__enabled = true
  function f:SetEnabled(v) self.__enabled = not not v; return self end
  function f:Enable() self.__enabled = true; return self end
  function f:Disable() self.__enabled = false; return self end
  function f:IsEnabled() return self.__enabled end

  -- Store handlers instead of discarding them, and expose __fire so a test can drive the lazy
  -- OnShow paths a settings panel depends on (the deferred body render, and the first-OnShow
  -- Defaults-button build — options-ui-§5). A no-op SetScript made those unreachable.
  function f:SetScript(name, fn) self.__scripts[name] = fn; return self end
  function f:GetScript(name) return self.__scripts[name] end
  function f:HookScript(name, fn)
    local prev = self.__scripts[name]
    self.__scripts[name] = function(...)
      if prev then prev(...) end
      return fn(...)
    end
    return self
  end
  function f:__fire(name, ...)
    local fn = self.__scripts[name]
    if fn then return fn(self, ...) end
  end

  -- Geometry and naming must return real values, not the frame (fidelity rule 2). Deliberately NOT
  -- defining the setters (SetSize/SetWidth/...): tests spy on those by rawsetting a recorder and
  -- rawsetting nil to restore, which would erase an explicit definition for good.
  function f:GetName() return nil end
  -- GEOMETRY IS RECORDED HERE, AND ANSWERED ONLY WHERE A TEST ASKED FOR IT. `__geomLive` is the
  -- whole of the opt-in/flip split, and it is one word wide on purpose: at the flip revision the
  -- `self.__geomLive and` falls out of these two lines and every frame answers what was recorded on
  -- it. That is a real behavioral change to a mock roughly 308 test files across ten repositories
  -- lean on -- every assertion that passes today BECAUSE geometry answers zero flips with it -- so
  -- it is its own revision with its own adoption, sharing it with nothing. Revision 15 planned it
  -- as revision 16; revision 16 carried the Ace-fake fixes instead, and revision 17 the Ace
  -- surfaces six consumer harnesses migrate onto, so the flip is the next revision that ships it
  -- alone, 18 at the earliest.
  function f:GetHeight() return (self.__geomLive and self.__geomH) or 0 end
  function f:GetWidth() return (self.__geomLive and self.__geomW) or 0 end

  -- The opt-in, and the ONLY thing that arms a frame. It has to be the test's call and not
  -- production's: `OptionsWidgets.lua` measures its tab pitch by calling `SetAtlas` on a probe
  -- texture it builds itself, so a `SetAtlas` that armed geometry on its own would silently switch
  -- that measurement on in every suite in the collection -- which is the flip, arriving by accident,
  -- three revisions early. Arm with no arguments and let production dress the frame, or hand it the
  -- two numbers directly; both are the same switch.
  function f:__setGeom(w, h) self.__geomW, self.__geomH, self.__geomLive = w, h, true; return self end

  -- `SetAtlas` RECORDS what it was told, always: the atlas name, and -- when `useAtlasSize` asks for
  -- it, which is the same argument that makes a real texture take the art's dimensions -- the size
  -- the fixture publishes for that art. Recording is unconditional and answering is not, so a test
  -- can assert which art a widget dressed itself in without arming anything, and a test that wants
  -- the measurement live arms the frame first.
  --
  -- An atlas the fixture does not publish leaves the geometry as it found it, because the client
  -- draws nothing for an unknown atlas rather than collapsing the texture to zero; answering 0 there
  -- would be indistinguishable from a frame nobody ever dressed, which is fidelity rule 1's failure
  -- mode rather than fidelity.
  function f:SetAtlas(name, useAtlasSize)
    self.__atlas = name
    local size = ATLAS_SIZES[name]
    if useAtlasSize and size then self.__geomW, self.__geomH = size[1], size[2] end
    return self
  end

  -- Record RegisterUnitEvent's (event -> unit tokens) instead of no-opping it (fidelity rule 3):
  -- an addon that registers per-unit events ONLY for enabled units is only trustworthy if a test
  -- can see exactly which units each frame registered. UnregisterAllEvents is likewise explicit —
  -- the metatable's blanket no-op would leave a disabled unit's registrations visibly in place and
  -- make the gating untestable.
  f.__unitEvents = {}
  function f:RegisterUnitEvent(event, ...) self.__unitEvents[event] = { ... }; return self end
  function f:UnregisterAllEvents() self.__unitEvents = {}; return self end

  setmetatable(f, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then
      return function() return f end
    end
    return nil
  end })
  return f
end

-- ── CallbackHandler-1.0, the registry AceEvent is built on ─────────────────────────────────────
--
-- Revision 17. AceEvent is two CallbackHandler registries, one for game events and one for
-- messages, and every dispatch rule a consumer's harness had hand-rolled is CallbackHandler's:
--
--   * `method` defaults to the event's own name; a string is called as `self[method](self, ...)`,
--     a function as `method(...)`; the optional `arg`, when present, goes in front of the event.
--   * one callback per (event, target): a second registration on the same target overwrites.
--   * a NEW registration made while the registry is dispatching is queued and applied when the
--     outermost dispatch returns, so the newcomer does not hear the event already in flight.
--   * `onUsed(event)` runs when an event gets its FIRST registrant, after the callback is stored.
--     AceEvent's events registry asks the frame for the event there, which is where the client
--     raises on a name it does not know.
--
-- One divergence, kept: CallbackHandler dispatches through securecallfunction, which reports a
-- handler's error to the error handler and carries on. Here the dispatch carries on too, and the
-- first error is then raised out of it. A harness that swallowed it would be a stub that silently
-- succeeds (fidelity rule 1).

--- The callable CallbackHandler stores for one registration. `n` is how many varargs followed the
--- method, because CallbackHandler tells "arg is nil" apart from "no arg" by counting.
---
--- The optional argument is named `extra`, not `arg` as CallbackHandler names it: under Lua 5.1's
--- vararg compatibility every `function(...)` declares a hidden local `arg`, which would shadow
--- an upvalue of that name inside the closures below and hand every handler nil.
local function callbackFor(names, self, method, n, extra, lib)
  if type(method) ~= "string" and type(method) ~= "function" then
    error("Usage: " .. names[1] .. "(\"eventname\", \"methodname\"): 'methodname' - string or function expected.", 4)
  end
  if type(method) == "string" then
    if type(self) ~= "table" then
      error("Usage: " .. names[1] .. "(\"eventname\", \"methodname\"): self was not a table?", 4)
    elseif self == lib then
      error("Usage: " .. names[1] .. "(\"eventname\", \"methodname\"): do not use Library:" .. names[1]
        .. "(), use your own 'self'", 4)
    elseif type(self[method]) ~= "function" then
      error("Usage: " .. names[1] .. "(\"eventname\", \"methodname\"): 'methodname' - method '"
        .. tostring(method) .. "' not found on self.", 4)
    end
    if n >= 1 then return function(...) self[method](self, extra, ...) end end
    return function(...) self[method](self, ...) end
  end
  local st = type(self)
  if st ~= "table" and st ~= "string" and st ~= "thread" then
    error("Usage: " .. names[1] .. "(self or \"addonId\", eventname, method): 'self or addonId': table or string or thread expected.", 4)
  end
  if n >= 1 then return function(...) method(extra, ...) end end
  return method
end

local Callbacks = {}
Callbacks.__index = Callbacks

--- A fresh registry. `names` = { RegisterName, UnregisterName, UnregisterAllName } for the usage
--- messages; `lib` is the library the registry belongs to, which CallbackHandler refuses as a `self`.
local function newCallbacks(names, onUsed, lib)
  return setmetatable({ events = {}, recurse = 0, names = names, onUsed = onUsed, lib = lib }, Callbacks)
end

function Callbacks:register(target, eventname, method, ...)
  if type(eventname) ~= "string" then
    error("Usage: " .. self.names[1] .. "(eventname, method[, arg]): 'eventname' - string expected.", 3)
  end
  local fn = callbackFor(self.names, target, method or eventname, select("#", ...), (...), self.lib)
  local list = self.events[eventname]
  local first = not (list and next(list))
  if (list and list[target]) or self.recurse < 1 then
    if not list then list = {}; self.events[eventname] = list end
    list[target] = fn
    if first and self.onUsed then self.onUsed(eventname) end
    return
  end
  self.queue = self.queue or {}
  self.queue[eventname] = self.queue[eventname] or {}
  self.queue[eventname][target] = fn
end

function Callbacks:unregister(target, eventname)
  if not target or (self.lib ~= nil and target == self.lib) then
    error("Usage: " .. self.names[2] .. "(eventname): bad 'self'", 3)
  end
  if type(eventname) ~= "string" then
    error("Usage: " .. self.names[2] .. "(eventname): 'eventname' - string expected.", 3)
  end
  local list = self.events[eventname]
  if list then list[target] = nil end
  local queued = self.queue and self.queue[eventname]
  if queued then queued[target] = nil end
end

--- CallbackHandler's UnregisterAll takes any number of targets (`t:UnregisterAllMessages()` passes
--- one), and refuses none at all, or the library alone.
function Callbacks:unregisterAll(...)
  local n = select("#", ...)
  if n < 1 then
    error("Usage: " .. self.names[3] .. "([whatFor]): missing 'self' or \"addonId\" to unregister events for.", 3)
  end
  if n == 1 and self.lib ~= nil and (...) == self.lib then
    error("Usage: " .. self.names[3] .. "([whatFor]): supply a meaningful 'self' or \"addonId\"", 3)
  end
  for i = 1, n do
    local target = select(i, ...)
    for _, list in pairs(self.events) do list[target] = nil end
    for _, list in pairs(self.queue or {}) do list[target] = nil end
  end
end

--- Apply the registrations queued during a dispatch, firing onUsed for an event that was empty.
function Callbacks:flushQueue()
  local queue = self.queue
  self.queue = nil
  for eventname, callbacks in pairs(queue) do
    local list = self.events[eventname] or {}
    self.events[eventname] = list
    local first = next(list) == nil
    for target, fn in pairs(callbacks) do
      list[target] = fn
      if first and self.onUsed then self.onUsed(eventname); first = false end
    end
  end
end

--- Dispatch `eventname` to every registrant, in registry order. Answers how many ran.
---
--- A handler that raises costs only itself: the dispatch carries on to the rest, as
--- securecallfunction lets CallbackHandler carry on, and the FIRST error is raised once the
--- dispatch is done -- the same shape as the AceAddon cascade's errorCollector below.
function Callbacks:fire(eventname, ...)
  local list = self.events[eventname]
  if not (list and next(list)) then return 0 end
  local outer = self.recurse
  self.recurse = outer + 1
  local ran, first = 0, nil
  local key, fn = next(list)
  while fn do
    ran = ran + 1
    local ok, err = pcall(fn, eventname, ...)
    if not ok and first == nil then first = err end
    key, fn = next(list, key)
  end
  self.recurse = outer
  if self.queue and outer == 0 then self:flushQueue() end
  if first ~= nil then error(first, 0) end
  return ran
end

-- ── AceEvent-3.0's EVENT half ──────────────────────────────────────────────────────────────────
--
-- ONE implementation for both places the client puts it: the object `NewAddon` returns (AceAddon
-- embeds AceEvent into it) and any target `AceEvent:Embed(t)` is called on, which is the
-- `NS.NewBusTarget()` shape a module registers its own game events on. Before revision 16 only the
-- first had it, so a module doing what `events-frames-taint-§1` asks errored headlessly.
--
-- Recorded rather than no-opped (fidelity rule 3): an addon that registers a target/focus event
-- only while that unit is enabled has gating a test cannot see unless the mock remembers what is
-- registered right now. `__events[event]` is the handler, or `true` when none was given, and a test
-- fires one the way CallbackHandler fires a function ref: `handler(event, ...)`.
--
-- Validated as CallbackHandler validates, because a registration the client refuses must not pass
-- headlessly (fidelity rule 1): the event must be a string; the method defaults to the event's own
-- name; it must be a function or a string; and a string must name a function `self` carries NOW.
-- So `t:RegisterEvent("PLAYER_LOGIN")` on a target with no `PLAYER_LOGIN` method raises, as does
-- `t:RegisterEvent(e, "OnTypo")`. What is recorded is unchanged -- the handler as given, or `true`
-- -- so a string method is recorded as the string, and the optional `arg` form is accepted and not
-- recorded. Firing a string method is `t[method](t, event, ...)`, CallbackHandler's own call.
--
-- Module-level functions rather than closures made per target, so the two call sites share the
-- very same functions and cannot drift apart. tests/test_mock_base.lua asserts the identity.
--
-- SINCE REVISION 17 the recorder is also a real registration. Beside `__events` each event is
-- registered in the build's CallbackHandler-shaped registry (newCallbacks, below), which is what
-- `M.__fireEvent` dispatches through and what refuses an event the client does not know. The
-- recorder's contract is unchanged: `__events[event]` is still the handler as given, or `true`.
-- The build a target belongs to is found through BUILD_OF, keyed by its `__events` table, because
-- these functions are shared by every build and have no closure to hold it in.
local BUILD_OF = setmetatable({}, { __mode = "k" })

local function registerEvent(self, event, handler, ...)
  if type(event) ~= "string" then
    error("Usage: RegisterEvent(eventname, method[, arg]): 'eventname' - string expected.", 2)
  end
  local method = handler or event
  if type(method) ~= "string" and type(method) ~= "function" then
    error("Usage: RegisterEvent(\"eventname\", \"methodname\"): 'methodname' - string or function expected.", 2)
  end
  if type(method) == "string" and type(self[method]) ~= "function" then
    error("Usage: RegisterEvent(\"eventname\", \"methodname\"): 'methodname' - method '"
      .. method .. "' not found on self.", 2)
  end
  self.__events[event] = handler or true
  local build = BUILD_OF[self.__events]
  -- Recorded FIRST, then registered: CallbackHandler stores the callback before AceEvent's OnUsed
  -- asks the frame for the event, so an unknown event leaves its registration behind exactly as
  -- the client does.
  if build then build.events:register(self, event, handler, ...) end
  return self
end

local function unregisterEvent(self, event)
  if type(event) ~= "string" then
    error("Usage: UnregisterEvent(eventname): 'eventname' - string expected.", 2)
  end
  self.__events[event] = nil
  local build = BUILD_OF[self.__events]
  if build then build.events:unregister(self, event) end
  return self
end

-- Cleared IN PLACE, so a table a test captured stays the live one. Messages are untouched, as
-- they are in the client: AceEvent keeps the two in separate CallbackHandler registries.
local function unregisterAllEvents(self)
  for k in pairs(self.__events) do self.__events[k] = nil end
  local build = BUILD_OF[self.__events]
  if build then build.events:unregisterAll(self) end
  return self
end

--- Stamp the event half onto `target`, pointing `target.__events` at the target's table in
--- `registry`. The registry is one per mock build, keyed by target, because the real one lives
--- inside the library rather than on the target: a second Embed in the same build forgets nothing,
--- and a target table reused by a later build starts with nothing registered, as a fresh client
--- library would -- the same per-build isolation the message bus has. `build` is that build's
--- context, `{ events = <callbacks>, M = <env> }`.
local function embedEvents(target, registry, build)
  registry[target] = registry[target] or {}
  target.__events = registry[target]
  BUILD_OF[target.__events] = build
  target.RegisterEvent = registerEvent
  target.UnregisterEvent = unregisterEvent
  target.UnregisterAllEvents = unregisterAllEvents
  return target
end

-- ── AceConsole-3.0's print mixins ──────────────────────────────────────────────────────────────
--
-- Both mixins end in one local, as they do in the real file: `consolePrint(self, frame, ...)`
-- renders "|cff33ff99<self>|r:" followed by every argument, space-joined. Each mixin treats a first
-- argument carrying an `AddMessage` member as the frame to print to; Printf then formats what is
-- left with string.format.
--
-- Called BARE -- `NS.Print(msg)`, `NS.Printf(fmt, ...)`, which is how an addon that forgot to take
-- its own printer back after NewAddon ends up calling these -- the first argument lands in `self`.
-- The message or the format string renders green with a trailing colon, and Printf formats what
-- FOLLOWS it, raising exactly as string.format does when nothing follows.
--
-- The default frame is the harness process's DEFAULT_CHAT_FRAME global, read at call time, and a
-- nil one prints nothing: the convention this kit's Print has always had.
local function consolePrint(self, frame, ...)
  local parts = { "|cff33ff99" .. tostring(self) .. "|r:" }
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  if frame then frame:AddMessage(table.concat(parts, " ")) end
end

local function isChatFrame(v) return type(v) == "table" and v.AddMessage ~= nil end

local function printMixin(self, ...)
  if isChatFrame((...)) then return consolePrint(self, (...), select(2, ...)) end
  return consolePrint(self, DEFAULT_CHAT_FRAME, ...)
end

local function printfMixin(self, ...)
  if isChatFrame((...)) then return consolePrint(self, (...), string.format(select(2, ...))) end
  return consolePrint(self, DEFAULT_CHAT_FRAME, string.format(...))
end

-- ── AceTimer-3.0 (revision 17) ─────────────────────────────────────────────────────────────────
--
-- AceTimer-3.0.lua's surface on the kit's one timer queue. The real library schedules every timer
-- through C_Timer.After; the kit's C_Timer.After IS a push onto `M.__timers`, so a timer lands
-- there as `{ fn = timer.callback, delay = <delay>, timer = <handle> }` and `M.__fireTimers()` runs
-- it. It pushes straight onto the queue rather than through `M.C_Timer.After`, because the real
-- library captured C_Timer.After when it loaded: a consumer that later replaces `C_Timer.After`
-- with a no-op (to keep some other deferral from running) must not silence AceTimer with it.
--
-- The handle is AceTimer's own table -- `object`, `func`, `looping`, `delay`, `ends`, `callback`,
-- the arguments. A handle CancelTimer has taken back carries `handle.cancelled = true`, under
-- AceTimer's own field name: it is a third-party API identifier, not prose, and the prose gate
-- carries a ratified exemption for it (CLAUDE.md -> Documented deviations).
-- `delay` is floored at 0.01, as the real one floors it for C_Timer.
local TIMER_MIXINS = { "ScheduleTimer", "ScheduleRepeatingTimer", "CancelTimer", "CancelAllTimers", "TimeLeft" }

local function makeAceTimer(M)
  local AceTimer = { activeTimers = {}, embeds = {} }
  local active = AceTimer.activeTimers

  local function queue(delay, timer)
    M.__timers[#M.__timers + 1] = { fn = timer.callback, delay = delay, timer = timer }
  end

  local function new(self, loop, func, delay, ...)
    if delay < 0.01 then delay = 0.01 end
    local timer = { object = self, func = func, looping = loop, argsCount = select("#", ...),
                    delay = delay, ends = M.GetTime() + delay, ... }
    active[timer] = timer
    timer.callback = function()
      if timer.cancelled then return end
      if type(timer.func) == "string" then
        timer.object[timer.func](timer.object, unpack(timer, 1, timer.argsCount))
      else
        timer.func(unpack(timer, 1, timer.argsCount))
      end
      if timer.looping and not timer.cancelled then
        -- AceTimer's drift compensation takes "how late was this run" off the next delay. In the
        -- client a run is never early; headlessly a pass runs wherever the test left the clock,
        -- usually before the due time, and an unclamped `now` read that as the timer being early
        -- and grew the delay by a period every pass. Clamped, the delay is AceTimer's own answer
        -- for an on-time run, and `ends` is taken from the clock as the real one takes it.
        local now = math.max(M.GetTime(), timer.ends)
        local ndelay = timer.delay - (now - timer.ends)
        if ndelay < 0.01 then ndelay = 0.01 end
        queue(ndelay, timer)
        timer.ends = M.GetTime() + ndelay
      else
        active[timer.handle or timer] = nil
      end
    end
    queue(delay, timer)
    return timer
  end

  local function check(self, func, delay, api)
    if not func or not delay then
      error("AceTimer-3.0: " .. api .. "(callback, delay, args...): 'callback' and 'delay' must have set values.", 3)
    end
    if type(func) == "string" then
      if type(self) ~= "table" then
        error("AceTimer-3.0: " .. api .. "(callback, delay, args...): 'self' - must be a table.", 3)
      elseif not self[func] then
        error("AceTimer-3.0: " .. api .. "(callback, delay, args...): Tried to register '" .. func
          .. "' as the callback, but it doesn't exist in the module.", 3)
      end
    end
  end

  function AceTimer.ScheduleTimer(self, func, delay, ...)
    check(self, func, delay, "ScheduleTimer")
    return new(self, nil, func, delay, ...)
  end
  function AceTimer.ScheduleRepeatingTimer(self, func, delay, ...)
    check(self, func, delay, "ScheduleRepeatingTimer")
    return new(self, true, func, delay, ...)
  end
  function AceTimer.CancelTimer(_, id)
    local timer = active[id]
    if not timer then return false end
    timer.cancelled = true
    active[id] = nil
    return true
  end
  function AceTimer.CancelAllTimers(self)
    for k, v in next, active do
      if v.object == self then AceTimer.CancelTimer(self, k) end
    end
  end
  function AceTimer.TimeLeft(_, id)
    local timer = active[id]
    if not timer then return 0 end
    return timer.ends - M.GetTime()
  end
  -- No fake here reads its receiver: a consumer that wraps one calls through with its own table as
  -- `self` (PanelMaster's AceEvent wrapper does exactly that), so the library is its closure.
  function AceTimer.Embed(_, target)
    AceTimer.embeds[target] = true
    for _, name in ipairs(TIMER_MIXINS) do target[name] = AceTimer[name] end
    return target
  end
  function AceTimer.OnEmbedDisable(_, target) target:CancelAllTimers() end
  return AceTimer
end

-- ── AceConsole-3.0 (revision 17) ───────────────────────────────────────────────────────────────
--
-- The mixins are the five the real Embed stamps less `GetArgs`, a string parser no consumer calls
-- and nobody should reimplement untested: Print and Printf (the one shared local above),
-- RegisterChatCommand and UnregisterChatCommand. `AceConsole.commands` is the real table
-- (`[command] = "ACECONSOLE_<COMMAND>"`), and `AceConsole:__slash(command, input)` runs a command
-- the way typing it would.
--
-- The client writes the handler into the global `SlashCmdList` and the alias into
-- `SLASH_ACECONSOLE_<COMMAND>1`. The fake does that too, but ONLY where the environment already
-- models `SlashCmdList` as a table: inventing the global would flip the branch of any host that
-- checks for it, and at least one consumer asserts its mock has none. The handler is always kept
-- on the library, in `AceConsole.__slashCmdList`, which is what `__slash` reads.
local CONSOLE_MIXINS = { "Print", "Printf", "RegisterChatCommand", "UnregisterChatCommand" }

local function makeAceConsole(M)
  local AceConsole = { embeds = {}, commands = {}, weakcommands = {}, __slashCmdList = {},
                       Print = printMixin, Printf = printfMixin }

  function AceConsole.RegisterChatCommand(self, command, func, persist)
    if type(command) ~= "string" then
      error([[Usage: AceConsole:RegisterChatCommand( "command", func[, persist ]): 'command' - expected a string]], 2)
    end
    if persist == nil then persist = true end
    local name = "ACECONSOLE_" .. command:upper()
    local handler = func
    if type(func) == "string" then
      handler = function(input, editBox) self[func](self, input, editBox) end
    end
    AceConsole.__slashCmdList[name] = handler
    if type(M.SlashCmdList) == "table" then
      M.SlashCmdList[name] = handler
      M["SLASH_" .. name .. "1"] = "/" .. command:lower()
    end
    AceConsole.commands[command] = name
    if not persist then
      AceConsole.weakcommands[self] = AceConsole.weakcommands[self] or {}
      AceConsole.weakcommands[self][command] = func
    end
    return true
  end

  function AceConsole.UnregisterChatCommand(_, command)
    local name = AceConsole.commands[command]
    if not name then return end
    AceConsole.__slashCmdList[name] = nil
    if type(M.SlashCmdList) == "table" then
      M.SlashCmdList[name] = nil
      M["SLASH_" .. name .. "1"] = nil
    end
    AceConsole.commands[command] = nil
  end

  function AceConsole.IterateChatCommands() return pairs(AceConsole.commands) end

  --- Harness seam: run `/command input` the way the client would. Raises for a command nobody
  --- registered, which is the answer a typo in a test deserves.
  function AceConsole.__slash(_, command, input, editBox)
    local handler = AceConsole.__slashCmdList[AceConsole.commands[command] or ""]
    if not handler then error("AceConsole: no chat command '" .. tostring(command) .. "' is registered", 2) end
    return handler(input, editBox)
  end

  function AceConsole.Embed(_, target)
    for _, name in ipairs(CONSOLE_MIXINS) do target[name] = AceConsole[name] end
    AceConsole.embeds[target] = true
    return target
  end
  function AceConsole.OnEmbedEnable(_, target)
    for command, func in pairs(AceConsole.weakcommands[target] or {}) do
      target:RegisterChatCommand(command, func, false)
    end
  end
  function AceConsole.OnEmbedDisable(_, target)
    for command in pairs(AceConsole.weakcommands[target] or {}) do target:UnregisterChatCommand(command) end
  end
  return AceConsole
end

-- ── AceEvent-3.0 (revision 17) ─────────────────────────────────────────────────────────────────
--
-- Two CallbackHandler registries, as in AceEvent-3.0.lua: `events` for game events, `messages` for
-- the addon bus. Embed stamps all seven mixins. The event half is the module-level trio above, so
-- it stays the same three functions on every target; the message half is one set of closures per
-- build, shared by every target in it. `M.__msgRegistry` publishes `messages.events`,
-- `[message] = { [target] = callable }`, where a function registered with no arg is stored as
-- itself, exactly as CallbackHandler stores it. OnEmbedDisable tears both halves down, which is
-- what AceAddon's DisableAddon asks of it.
--
-- The events registry's onUsed is the client's frame:RegisterEvent: for an event in
-- `M.__badEvents` it raises `Attempt to register unknown event "<NAME>"`, on the event's first
-- registrant only, after the callback is stored -- because that is where and when the client
-- raises. `M.__badEvents` is read at call time, so a test that swaps the table is heard.
local EVENT_NAMES   = { "RegisterEvent", "UnregisterEvent", "UnregisterAllEvents" }
local MESSAGE_NAMES = { "RegisterMessage", "UnregisterMessage", "UnregisterAllMessages" }

local function makeAceEvent(M, eventRegistry)
  local AceEvent = { embeds = {} }
  local build = { M = M }
  build.events = newCallbacks(EVENT_NAMES, function(event)
    local bad = M.__badEvents
    if type(bad) == "table" and bad[event] then
      error("Attempt to register unknown event \"" .. event .. "\"", 4)
    end
  end, AceEvent)
  local messages = newCallbacks(MESSAGE_NAMES, nil, AceEvent)
  AceEvent.events, AceEvent.messages = build.events, messages

  local function registerMessage(self, message, method, ...) messages:register(self, message, method, ...) end
  local function unregisterMessage(self, message) messages:unregister(self, message) end
  local function unregisterAllMessages(...) messages:unregisterAll(...) end
  local function sendMessage(_, message, ...) messages:fire(message, ...) end
  -- The library object carries the registry's API as CallbackHandler publishes it onto AceEvent:
  -- `AceEvent.RegisterMessage("addonId", msg, fn)` is the addonId form, and a method NAME
  -- registered with the library itself as self is refused, as the real one refuses it.
  AceEvent.RegisterMessage, AceEvent.UnregisterMessage = registerMessage, unregisterMessage
  AceEvent.UnregisterAllMessages, AceEvent.SendMessage = unregisterAllMessages, sendMessage

  function AceEvent.Embed(_, target)
    embedEvents(target, eventRegistry, build)
    target.RegisterMessage = registerMessage
    target.UnregisterMessage = unregisterMessage
    target.UnregisterAllMessages = unregisterAllMessages
    target.SendMessage = sendMessage
    AceEvent.embeds[target] = true
    return target
  end
  function AceEvent.OnEmbedDisable(_, target)
    target:UnregisterAllEvents()
    target:UnregisterAllMessages()
  end
  return AceEvent, build
end

-- ── AceAddon-3.0 (revision 17) ─────────────────────────────────────────────────────────────────
--
-- AceAddon-3.0.lua's object model: NewAddon honoring its mixin list, GetAddon, the module surface
-- (NewModule and the thirteen other mixins), and the lifecycle, driven the way the client drives
-- it -- ADDON_LOADED and PLAYER_LOGIN on `AceAddon.frame`, so a test writes
-- `AceAddon.frame:__fire("OnEvent", "PLAYER_LOGIN")`. InitializeAddon, EnableAddon and
-- DisableAddon are the real public members, so a harness that wants only the enable cascade calls
-- `AceAddon:EnableAddon(addon)`, which is what the client's PLAYER_LOGIN does per addon.
--
-- Libraries are embedded through the environment's own `M.LibStub`, read at call time, because the
-- real EmbedLibrary asks LibStub: a consumer that wraps or replaces one of the fakes gets its
-- version embedded, and one that replaced LibStub gets its own registry consulted.
--
-- TWO DIVERGENCES, both deliberate.
--
-- 1. NewAddon(target) -- EXACTLY one argument, a table: the kit's own calling convention before
--    revision 17 -- keeps revision 16's behavior: every mixin stamped, none of the object model.
--    The real one raises on it. It is kept for safety, for a harness still calling it that way; any
--    other call without a string name goes through the real validation and raises.
-- 2. An error inside OnInitialize / OnEnable / OnDisable / OnModuleCreated is caught, as the
--    client catches it, and the cascade carries on to the next object. The client then hands it to
--    geterrorhandler(); the kit raises the FIRST such error from the outermost call once the
--    cascade has finished. An error handler that swallowed it would pass every suite.
local EARLY_LOAD = {
  Blizzard_DebugTools = true, Blizzard_TimeManager = true, Blizzard_BattlefieldMap = true,
  Blizzard_MapCanvas = true, Blizzard_SharedMapDataProviders = true, Blizzard_CombatLog = true,
}

local function addonToString(self) return self.name end
local function isModuleFalse() return false end
local function isModuleTrue() return true end

--- The raise-after-the-cascade half of divergence 2: `safecall` records, `outermost` reports.
local function errorCollector()
  local c = { errors = {}, depth = 0 }
  local function record(err) c.errors[#c.errors + 1] = err; return err end
  function c.safecall(fn, ...)
    if type(fn) ~= "function" then return end
    local n, args = select("#", ...), { ... }
    return xpcall(function() return fn(unpack(args, 1, n)) end, record)
  end
  function c.outermost(fn)
    return function(...)
      c.depth = c.depth + 1
      local ok, result = pcall(fn, ...)
      c.depth = c.depth - 1
      local first
      if c.depth == 0 then first = c.errors[1]; c.errors = {} end
      if not ok then error(result, 0) end
      if first ~= nil then error(first, 0) end
      return result
    end
  end
  return c
end

--- The module surface every named addon and module carries, and the lifecycle half of the lib.
local function addonMixins(AceAddon, c)
  local m = {}
  local function queuedForInit(addon)
    for _, queued in ipairs(AceAddon.initializequeue) do if queued == addon then return true end end
    return false
  end
  local function refuseAfterModules(self, api)
    if next(self.modules) then
      error("Usage: " .. api .. ": cannot change the module defaults after a module has been registered.", 3)
    end
  end

  local createModule = c.outermost(function(self, name, prototype, ...)
    local module = AceAddon:NewAddon(("%s_%s"):format(self.name or tostring(self), name))
    module.IsModule = isModuleTrue
    module:SetEnabledState(self.defaultModuleState)
    module.moduleName = name
    if type(prototype) == "string" then AceAddon:EmbedLibraries(module, prototype, ...)
    else AceAddon:EmbedLibraries(module, ...) end
    AceAddon:EmbedLibraries(module, unpack(self.defaultModuleLibraries))
    if not prototype or type(prototype) == "string" then prototype = self.defaultModulePrototype end
    if type(prototype) == "table" then
      local mt = getmetatable(module)
      mt.__index = prototype
      setmetatable(module, mt)
    end
    c.safecall(self.OnModuleCreated, self, module)
    self.modules[name] = module
    self.orderedModules[#self.orderedModules + 1] = module
    return module
  end)

  function m.NewModule(self, name, prototype, ...)
    if type(name) ~= "string" then
      error(("Usage: NewModule(name, [prototype, [lib, lib, lib, ...]): 'name' - string expected got '%s'."):format(type(name)), 2)
    end
    local pt = type(prototype)
    if pt ~= "string" and pt ~= "table" and pt ~= "nil" then
      error(("Usage: NewModule(name, [prototype, [lib, lib, lib, ...]): 'prototype' - table (prototype), string (lib) or nil expected got '%s'."):format(pt), 2)
    end
    if self.modules[name] then
      error(("Usage: NewModule(name, [prototype, [lib, lib, lib, ...]): 'name' - Module '%s' already exists."):format(name), 2)
    end
    return createModule(self, name, prototype, ...)
  end
  function m.GetModule(self, name, silent)
    if not self.modules[name] and not silent then
      error(("Usage: GetModule(name, silent): 'name' - Cannot find module '%s'."):format(tostring(name)), 2)
    end
    return self.modules[name]
  end
  function m.GetName(self) return self.moduleName or self.name end
  function m.Enable(self)
    self:SetEnabledState(true)
    if not queuedForInit(self) then return AceAddon:EnableAddon(self) end
  end
  function m.Disable(self)
    self:SetEnabledState(false)
    return AceAddon:DisableAddon(self)
  end
  function m.EnableModule(self, name) return self:GetModule(name):Enable() end
  function m.DisableModule(self, name) return self:GetModule(name):Disable() end
  function m.SetDefaultModuleLibraries(self, ...)
    refuseAfterModules(self, "SetDefaultModuleLibraries(...)")
    self.defaultModuleLibraries = { ... }
  end
  function m.SetDefaultModuleState(self, state)
    refuseAfterModules(self, "SetDefaultModuleState(state)")
    self.defaultModuleState = state
  end
  function m.SetDefaultModulePrototype(self, prototype)
    refuseAfterModules(self, "SetDefaultModulePrototype(prototype)")
    if type(prototype) ~= "table" then
      error(("Usage: SetDefaultModulePrototype(prototype): 'prototype' - table expected got '%s'."):format(type(prototype)), 2)
    end
    self.defaultModulePrototype = prototype
  end
  function m.SetEnabledState(self, state) self.enabledState = state end
  function m.IterateModules(self) return pairs(self.modules) end
  function m.IterateEmbeds(self) return pairs(AceAddon.embeds[self]) end
  function m.IsEnabled(self) return self.enabledState end
  return m
end

--- Run `hook` (OnEmbedInitialize / OnEmbedEnable / OnEmbedDisable) on every library `addon` embedded.
local function embedHooks(M, AceAddon, c, addon, hook)
  for _, libname in ipairs(AceAddon.embeds[addon]) do
    local lib = M.LibStub(libname, true)
    if lib then c.safecall(lib[hook], lib, addon) end
  end
end

--- The three lifecycle steps and the frame that drives them.
local function addonLifecycle(M, AceAddon, c)
  AceAddon.InitializeAddon = c.outermost(function(_, addon)
    c.safecall(addon.OnInitialize, addon)
    embedHooks(M, AceAddon, c, addon, "OnEmbedInitialize")
  end)
  AceAddon.EnableAddon = c.outermost(function(_, addon)
    if type(addon) == "string" then addon = AceAddon:GetAddon(addon) end
    if AceAddon.statuses[addon.name] or not addon.enabledState then return false end
    AceAddon.statuses[addon.name] = true
    c.safecall(addon.OnEnable, addon)
    if AceAddon.statuses[addon.name] then
      embedHooks(M, AceAddon, c, addon, "OnEmbedEnable")
      for _, module in ipairs(addon.orderedModules) do AceAddon:EnableAddon(module) end
    end
    return AceAddon.statuses[addon.name]
  end)
  AceAddon.DisableAddon = c.outermost(function(_, addon)
    if type(addon) == "string" then addon = AceAddon:GetAddon(addon) end
    if not AceAddon.statuses[addon.name] then return false end
    AceAddon.statuses[addon.name] = false
    c.safecall(addon.OnDisable, addon)
    if not AceAddon.statuses[addon.name] then
      embedHooks(M, AceAddon, c, addon, "OnEmbedDisable")
      for _, module in ipairs(addon.orderedModules) do AceAddon:DisableAddon(module) end
    end
    return not AceAddon.statuses[addon.name]
  end)

  local loggedIn = false
  local onEvent = c.outermost(function(_, event, arg1)
    local loaded = event == "ADDON_LOADED" and (arg1 == nil or not EARLY_LOAD[arg1])
    if not (loaded or event == "PLAYER_LOGIN") then return end
    if event == "PLAYER_LOGIN" then loggedIn = true end
    -- The client asks IsLoggedIn() here, which is what enables a load-on-demand addon whose
    -- ADDON_LOADED arrives after the login. Read at call time; the flag is the fallback for an
    -- environment that models no IsLoggedIn.
    local now = loggedIn or (type(M.IsLoggedIn) == "function" and M.IsLoggedIn() and true or false)
    while #AceAddon.initializequeue > 0 do
      local addon = table.remove(AceAddon.initializequeue, 1)
      if event == "ADDON_LOADED" then addon.baseName = arg1 end
      AceAddon:InitializeAddon(addon)
      AceAddon.enablequeue[#AceAddon.enablequeue + 1] = addon
    end
    if not now then return end
    while #AceAddon.enablequeue > 0 do AceAddon:EnableAddon(table.remove(AceAddon.enablequeue, 1)) end
  end)
  AceAddon.frame = stubFrame()
  AceAddon.frame:SetScript("OnEvent", onEvent)
end

local function makeAceAddon(M, legacy)
  local AceAddon = {
    addons = {}, statuses = {}, initializequeue = {}, enablequeue = {},
    embeds = setmetatable({}, { __index = function(t, k) t[k] = {}; return t[k] end }),
  }
  local c = errorCollector()
  local mixins = addonMixins(AceAddon, c)
  local pmixins = { defaultModuleState = true, enabledState = true, IsModule = isModuleFalse }

  --- Never reads its receiver: a consumer that wraps the fake calls it with its own table as self.
  function AceAddon.NewAddon(_, objectorname, ...)
    -- Exactly ONE argument, a table, is the pre-17 calling convention. Anything else -- a nil name
    -- with libraries after it, or no argument at all -- goes through the real validation and raises.
    if type(objectorname) == "table" and select("#", ...) == 0 then return legacy(objectorname) end
    local object, name, firstLib = nil, objectorname, 1
    if type(objectorname) == "table" then object, name, firstLib = objectorname, (...), 2 end
    if type(name) ~= "string" then
      error(("Usage: NewAddon([object,] name, [lib, lib, lib, ...]): 'name' - string expected got '%s'."):format(type(name)), 2)
    end
    if AceAddon.addons[name] then
      error(("Usage: NewAddon([object,] name, [lib, lib, lib, ...]): 'name' - Addon '%s' already exists."):format(name), 2)
    end
    object = object or {}
    object.name = name
    local meta = {}
    for k, v in pairs(getmetatable(object) or {}) do meta[k] = v end
    meta.__tostring = addonToString
    setmetatable(object, meta)
    AceAddon.addons[name] = object
    object.modules, object.orderedModules, object.defaultModuleLibraries = {}, {}, {}
    for k, v in pairs(mixins) do object[k] = v end
    for k, v in pairs(pmixins) do object[k] = object[k] or v end
    AceAddon:EmbedLibraries(object, select(firstLib, ...))
    AceAddon.initializequeue[#AceAddon.initializequeue + 1] = object
    return object
  end

  function AceAddon.GetAddon(_, name, silent)
    if not silent and not AceAddon.addons[name] then
      error(("Usage: GetAddon(name): 'name' - Cannot find an AceAddon '%s'."):format(tostring(name)), 2)
    end
    return AceAddon.addons[name]
  end
  function AceAddon.EmbedLibrary(_, addon, libname, silent, offset)
    local lib = M.LibStub(libname, true)
    if not lib and not silent then
      error(("Usage: EmbedLibrary(addon, libname, silent, offset): 'libname' - Cannot find a library instance of %q."):format(tostring(libname)), offset or 2)
    elseif lib and type(lib.Embed) == "function" then
      lib:Embed(addon)
      local list = AceAddon.embeds[addon]
      list[#list + 1] = libname
      return true
    elseif lib then
      error(("Usage: EmbedLibrary(addon, libname, silent, offset): 'libname' - Library '%s' is not Embed capable"):format(libname), offset or 2)
    end
  end
  function AceAddon.EmbedLibraries(_, addon, ...)
    for i = 1, select("#", ...) do AceAddon:EmbedLibrary(addon, (select(i, ...)), false, 4) end
  end
  function AceAddon.IterateAddons() return pairs(AceAddon.addons) end
  function AceAddon.IterateAddonStatus() return pairs(AceAddon.statuses) end

  addonLifecycle(M, AceAddon, c)
  return AceAddon
end

return function()
  local M = {}

  -- Exposed so an addon's own mock can build extra frame-shaped objects (GameTooltip stand-ins,
  -- StopwatchFrame, …) without duplicating the stub.
  M.__stubFrame = stubFrame
  M.__deepcopy  = deepcopy
  -- Published, not private: a consumer's suite reads the height it expects out of this rather than
  -- restating it, and a consumer that needs an atlas nobody has needed yet adds the entry here.
  M.__atlasSizes = ATLAS_SIZES

  -- ── time / string ────────────────────────────────────────────────────────────────────────
  M.__now = 0
  M.time = os.time
  M.date = os.date
  M.GetTime = function() return M.__now end
  M.format = string.format
  -- Millisecond CPU clock backing the perf brackets (LibKa0s-Perf-1.0). Driven off a settable
  -- counter rather than a real clock so a test can assert on EXACT bucket totals — a wall-clock
  -- reading would make every timing assertion flaky. Tests advance it via M.__profileMs.
  M.__profileMs = 0
  M.debugprofilestop = function() return M.__profileMs end
  M.wipe = function(t) if type(t) == "table" then for k in pairs(t) do t[k] = nil end end return t end
  M.tinsert = table.insert
  M.tremove = table.remove
  -- `strsplit` and `strtrim` are deliberately absent. Neither consumer of this kit calls them, and a
  -- hand-rolled reimplementation of a WoW string function that nothing exercises is a subtly-wrong
  -- shared helper waiting to be adopted. The addon that first needs one adds it to its own extender
  -- with a test, and it graduates here once a second addon wants the same behavior.

  -- Scheduled one-shot timers, recorded so tests can inspect coalescing and fire them on demand.
  --
  -- CANCELLATION IS HONORED (revision 17). A queue entry is skipped once it has been canceled -- a
  -- C_Timer.NewTimer handle through its own `Cancel`, an AceTimer handle through CancelTimer -- and
  -- `__fireTimers` answers how many entries actually RAN, so "three events, one pass" and "the
  -- pending timer was canceled" are both assertable. Until 17, NewTimer's Cancel was a no-op and
  -- a canceled debounce still fired, which is the bug a debounce test exists to catch. Both kinds
  -- record it on the handle as `handle.cancelled`, AceTimer's own field name.
  M.__timers = {}
  M.__fireTimers = function()
    local due = M.__timers
    M.__timers = {}
    local ran = 0
    for _, t in ipairs(due) do
      if not (t.cancelled or (t.timer and t.timer.cancelled)) then
        ran = ran + 1
        t.fn()
      end
    end
    return ran
  end
  M.C_Timer = {
    After = function(delay, fn) M.__timers[#M.__timers + 1] = { fn = fn, delay = delay } end,
    NewTimer = function(delay, fn)
      local t = { fn = fn, delay = delay }
      t.Cancel = function() t.cancelled = true end
      t.IsCancelled = function() return t.cancelled == true end
      M.__timers[#M.__timers + 1] = t
      return t
    end,
  }

  -- ── unit / world ─────────────────────────────────────────────────────────────────────────
  M.__unitExists = { player = true, target = false, focus = false }
  M.UnitExists = function(unit) return M.__unitExists[unit] == true end
  M.InCombatLockdown = function() return false end
  M.GetLocale = function() return "enUS" end

  -- Capture-context lookups (LibKa0s-Perf-1.0). Settable so a test can assert the recorded context
  -- is the character's rather than a hard-coded string.
--
  -- Class lives here too, and `UnitClass` reads it rather than returning a literal: the localized
  -- NAME and the uppercase TOKEN are different strings, and a stub that returned the token for both
  -- let a context field silently render as "?" in every test that claimed to cover it. Repos whose
  -- suites assert on a particular class override these two fields in their own extender.
  M.__context = {
    name = "Testchar", realm = "Testrealm", level = 80,
    class = "Mage", classToken = "MAGE",
    spec = "Blood", zone = "Silvermoon City", subZone = "Falconwing Square",
    inInstance = false, instanceType = "none", inGroup = false, inRaid = false, groupSize = 0,
  }
  M.UnitClass = function() return M.__context.class, M.__context.classToken end
  M.UnitName = function() return M.__context.name end
  M.GetRealmName = function() return M.__context.realm end
  M.UnitLevel = function() return M.__context.level end
  M.GetZoneText = function() return M.__context.zone end
  M.GetSubZoneText = function() return M.__context.subZone end
  M.GetSpecialization = function() return 1 end
  M.GetSpecializationInfo = function() return 250, M.__context.spec end
  M.IsInInstance = function() return M.__context.inInstance, M.__context.instanceType end
  M.IsInRaid = function() return M.__context.inRaid end
  M.IsInGroup = function() return M.__context.inGroup end
  M.GetNumGroupMembers = function() return M.__context.groupSize end
  M.__inCombat = false
  M.UnitAffectingCombat = function() return M.__inCombat end

  -- NOTE: `C_AddOns` is deliberately NOT stubbed here.
  --
  -- It is the target of every addon's Compat metadata shim, and those shims are tested by swapping
  -- `_G.C_AddOns` to nil to drive the deprecated-global fallback branch. The loader env resolves
  -- mocks BEFORE _G, so a base-level stub would shadow the swap and make the fallback branch
  -- unreachable — silently, as three passing-then-failing cases in AbsorbTracker's test_compat
  -- demonstrated. An addon (or LibKa0s itself, for a perf record's `interface` field) stubs it in
  -- its own extender, where the addon's own tests can see and manage it.

  -- Blizzard's stopwatch, which a perf run drives as its visible arm indicator. Universal because
  -- every addon in the collection vendors the whole LibKa0s folder, Perf included.
  --
  -- Recorded as an ORDERED LOG rather than as counters: which of clear/play/pause fired, and in what
  -- order, is the only observable difference between an armed window and a recording one. Counters
  -- would report the same totals for a correct run and one that played before it cleared.
  M.__stopwatch = {}
  local function sw(action) return function() M.__stopwatch[#M.__stopwatch + 1] = action end end
  M.Stopwatch_Clear, M.Stopwatch_Play, M.Stopwatch_Pause = sw("clear"), sw("play"), sw("pause")
  M.StopwatchFrame = stubFrame()

  -- ── UI ───────────────────────────────────────────────────────────────────────────────────
  M.UIParent = stubFrame()
  -- The ARGUMENTS are recorded, not discarded (fidelity rule 3). A frame's global name is
  -- load-bearing in real code and not merely decorative: UIPanelScrollFrameTemplate derives its
  -- scrollbar children's names from its parent's, and UISpecialFrames is a list of global NAMES,
  -- so "did this frame get the name it needs" is a question a suite has to be able to ask. It
  -- could not, and a copy window shipped for five versions with the answer unpinned.
  --
  -- Recorded on the frame rather than returned through GetName(), which stays nil-answering:
  -- LibKa0s-Options-1.0's scrollbar patch CONCATENATES GetName(), and handing it a real string
  -- would change a code path rather than observe one.
  M.CreateFrame = function(frameType, name, parent, template)
    local f = stubFrame()
    f.__frameType, f.__name, f.__parent, f.__template = frameType, name, parent, template
    return f
  end
  M.UISpecialFrames = {}
  M.DEFAULT_CHAT_FRAME = stubFrame()
  M.StaticPopupDialogs = {}
  M.StaticPopup_Show = function() end
  M.GameTooltip = stubFrame()
  M.hooksecurefunc = function() end
  M.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
  M.PlaySound = function() end

  -- Record the canvas frames as they are registered. This is the only public seam a test has for
  -- reaching the real page panels built by an addon's settings pages, which is what makes it
  -- possible to fire their OnShow and exercise the genuine deferred render.
  M.__mainPanel     = nil
  M.__subcategories = {}   -- [displayName] = panel frame
  -- Blizzard's settings WINDOW, distinct from the Settings registration API below. Present rather
  -- than absent, and its Close is RECORDED (fidelity rule: anything a test needs to observe must
  -- be observable): a panel's combat guard closes this window, and the only thing distinguishing
  -- that from a guard which merely printed is seeing the close land. Left nil, the branch is
  -- unreachable and the case passes either way.
  M.__settingsClosed = 0
  M.SettingsPanel = stubFrame()
  function M.SettingsPanel:Close() M.__settingsClosed = M.__settingsClosed + 1 end

  M.Settings = {
    RegisterCanvasLayoutCategory = function(panel)
      M.__mainPanel = panel
      return { GetID = function() return 1 end }
    end,
    RegisterCanvasLayoutSubcategory = function(_parent, panel, name)
      M.__subcategories[name] = panel
      return {}
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
  }

  -- ── LibStub + the Ace fakes ──────────────────────────────────────────────────────────────
  local libs = {}
  -- Exposed so an addon's own mock can register additional library fakes (AceDBOptions,
  -- AceConfigDialog, LibSharedMedia) without reaching through LibStub's closure.
  M.__libs = libs

  -- AceDB-3.0 with a WORKING profile surface. A bare {global, profile} stub leaves an addon's
  -- entire `profile` verb untestable: the handler bails at `if not db.SetProfile` before touching a
  -- single subcommand, so a broken switch/copy/delete passes the suite silently. Model enough of
  -- the real lib to exercise it — a named profile store, switch/copy/delete/reset, and the
  -- OnProfileChanged / OnProfileCopied / OnProfileReset callbacks AceDB fires via CallbackHandler.
  libs["AceDB-3.0"] = {
    -- `tbl` is the real signature's first arg: either the STRING name of a global SavedVariables
    -- table (what an addon passes: `AceDB:New("<Addon>DB", ...)`), or an actual table. Resolving it
    -- against `_G` (rather than always starting fresh) is what lets a test seed the global with a
    -- legacy profile and then drive the REAL InitDB path against real AceDB merge-in-place
    -- semantics, instead of only against a bespoke plain table that never triggers them.
    New = function(_, tbl, defaults)
      local sv
      if type(tbl) == "string" then
        sv = _G[tbl]
        if not sv then
          sv = {}
          _G[tbl] = sv
        end
      else
        sv = tbl or {}
      end
      sv.profiles = sv.profiles or {}
      sv.global = sv.global or {}

      local db = {}
      local current, callbacks = "Default", {}

      -- Faithful (if simplified) copy of AceDB-3.0's copyDefaults: recurse into every TABLE-valued
      -- default, creating the dest sub-table if it is missing, but only ever fill a SCALAR leaf
      -- when the dest does not already have it. An existing user value always wins — this is the
      -- exact merge-in-place behavior that makes a naive `if profile.x == nil then migrate()`
      -- guard unreachable, because a bare read of db.profile has already populated it.
      local function copyDefaults(dest, src)
        for k, v in pairs(src or {}) do
          if type(v) == "table" then
            if type(dest[k]) ~= "table" then dest[k] = {} end
            copyDefaults(dest[k], v)
          elseif dest[k] == nil then
            dest[k] = v
          end
        end
      end

      local function ensureProfile(name)
        sv.profiles[name] = sv.profiles[name] or {}
        copyDefaults(sv.profiles[name], defaults and defaults.profile)
        return sv.profiles[name]
      end

      copyDefaults(sv.global, defaults and defaults.global)
      -- Real AceDB-3.0 exposes the whole raw SavedVariables table as db.sv, and that is how a
      -- migration reaches `sv.profiles` to lift EVERY saved profile rather than just the active
      -- one. Note the fidelity that matters: profiles are only merged with the defaults by
      -- ensureProfile when they are actually activated, so a pre-seeded, never-activated profile
      -- stays exactly as the SavedVariables file had it — un-stamped, which is precisely the case a
      -- per-profile lift has to handle.
      db.sv      = sv
      db.global  = sv.global
      db.profile = ensureProfile(current)

      local function fire(event)
        for _, cb in ipairs(callbacks[event] or {}) do cb(event, db, current) end
      end

      -- CallbackHandler shape: db.RegisterCallback(target, event, fn) — dot-called, so the
      -- registering object arrives as the first arg.
      db.RegisterCallback = function(_target, event, fn)
        callbacks[event] = callbacks[event] or {}
        callbacks[event][#callbacks[event] + 1] = fn
      end

      db.GetCurrentProfile = function() return current end

      db.GetProfiles = function()
        local names = {}
        for name in pairs(sv.profiles) do names[#names + 1] = name end
        table.sort(names)
        return names
      end

      db.SetProfile = function(_, name)
        if name == current then return end
        current = name
        db.profile = ensureProfile(name)
        fire("OnProfileChanged")
      end

      db.ResetProfile = function()
        -- Wipe in place: the real lib keeps the profile table's identity across a reset, so
        -- anything holding a reference to db.profile keeps seeing the live table.
        local p = sv.profiles[current]
        for k in pairs(p) do p[k] = nil end
        copyDefaults(p, defaults and defaults.profile)
        fire("OnProfileReset")
      end

      db.CopyProfile = function(_, name)
        local src = sv.profiles[name]
        if not src or name == current then return end
        local p = sv.profiles[current]
        for k in pairs(p) do p[k] = nil end
        for k, v in pairs(deepcopy(src)) do p[k] = v end
        fire("OnProfileCopied")
      end

      db.DeleteProfile = function(_, name)
        if name == current then return end
        sv.profiles[name] = nil
      end

      return db
    end,
  }

  -- The event half's recorder, fresh per build and shared by NewAddon and AceEvent:Embed below:
  -- [target] = { [event] = handler or true }. Weak-keyed, so a target nobody holds is not kept.
  local eventRegistry = setmetatable({}, { __mode = "k" })

  -- Event names this fake client does not know. Registering one raises on its first registrant,
  -- as retail does (revision 17; see makeAceEvent). Read at call time, so a test may swap the table.
  M.__badEvents = {}

  -- AceEvent-3.0: both CallbackHandler registries (makeAceEvent, above). A no-op Embed would hide
  -- the whole (message, target) clobber class of bug (architecture-§4): the real lib keys callbacks
  -- by (message, target) through one shared registry, so a SendMessage on any embedded object fans
  -- out to every target that registered that message, and two receivers on ONE target overwrite
  -- each other. Fresh per build for isolation.
  local AceEvent, eventBuild = makeAceEvent(M, eventRegistry)
  libs["AceEvent-3.0"] = AceEvent
  -- Published harness seams: the message registry, and a game event fired the way AceEvent's own
  -- frame fires one -- to every target registered for it, as `handler(event, ...)` or
  -- `target[method](target, event, ...)`. Answers how many handlers ran.
  M.__msgRegistry = AceEvent.messages.events
  M.__fireEvent = function(event, ...) return eventBuild.events:fire(event, ...) end

  -- Revision 16's NewAddon, kept for a caller that passes no name (divergence 1 in makeAceAddon).
  local function legacyNewAddon(target)
    local noop = function() end
    -- AceEvent's event half, recorded -- the same three functions an `AceEvent:Embed` target gets
    -- (see embedEvents above).
    embedEvents(target, eventRegistry, eventBuild)
    target.RegisterChatCommand = noop
    target.ScheduleTimer = function(_, fn, delay)
      local timer = { fn = fn, delay = delay }
      M.__timers[#M.__timers + 1] = timer
      return timer
    end
    target.ScheduleRepeatingTimer = function() return {} end
    -- Honored since the 2026-09-12 review: the handle is the queue entry, so marking it is what
    -- makes __fireTimers skip it.
    target.CancelTimer = function(_, handle)
      if type(handle) == "table" then handle.cancelled = true end
    end
    -- Faithfully mirror AceConsole-3.0's Embed: its mixins are :Print AND :Printf, stamped onto
    -- the addon object and clobbering any same-named custom NS.Print or NS.Printf. Called as
    -- `NS.Print(msg)`, AceConsole treats the message as `self` and renders "|cff33ff99<msg>|r:" —
    -- green, trailing colon, no tag. The addon must reclaim BOTH after NewAddon; reproducing the
    -- clobber here lets the tests exercise the real production print path instead of a clean one
    -- the client never uses.
    target.Print = printMixin
    target.Printf = printfMixin
    return target
  end
  libs["AceAddon-3.0"] = makeAceAddon(M, legacyNewAddon)

  -- AceGUI-3.0. Without this the options toolkit's widget makers all return early and the schema →
  -- widget translation layer is untestable. Widgets here are inert data recorders rather than
  -- frames: they remember what was set on them and, crucially, expose __fire so a test can drive
  -- the OnValueChanged / OnMouseUp / OnValueConfirmed callbacks the way a real click would — which
  -- is what exercises the read → write → refresh loop.
  --
  -- `aceGUI` is declared here and built below, so a widget's `:Release()` can reach it.
  local aceGUI
  local function makeWidget(wtype)
    local w = {
      type      = wtype,
      children  = {},
      callbacks = {},
      -- AceGUI's documented per-widget scratch table, cleared in place by Release.
      userdata  = {},
      frame     = stubFrame(),
    }
    -- WidgetBase.Release: the method form of AceGUI:Release, which correct code may call instead.
    function w:Release() return aceGUI:Release(self) end
    function w:SetLabel(v) self.labelText = v; return self end
    function w:SetText(v) self.text = v; return self end
    function w:SetValue(v) self.value = v; return self end
    function w:GetValue() return self.value end
    function w:SetList(items, order) self.list, self.order = items, order; return self end
    function w:SetColor(r, g, b, a) self.color = { r = r, g = g, b = b, a = a }; return self end
    function w:SetHasAlpha(v) self.hasAlpha = v; return self end
    function w:SetDisabled(v) self.disabled = v and true or false; return self end
    function w:SetSliderValues(mn, mx, st) self.min, self.max, self.step = mn, mx, st; return self end
    function w:SetIsPercent(v) self.isPercent = v; return self end
    function w:SetWidth(v) self.width = v; return self end
    function w:SetHeight(v) self.height = v; return self end
    function w:SetRelativeWidth(v) self.relativeWidth = v; return self end
    function w:SetFullWidth(v) self.fullWidth = v and true or false; return self end
    function w:SetLayout(v) self.layout = v; return self end
    function w:SetAutoAdjustHeight(v) self.autoAdjustHeight = v; return self end
    function w:SetImage(...) self.image = { ... }; return self end
    function w:SetImageSize(...) self.imageSize = { ... }; return self end
    function w:SetMaxLetters(v) self.maxLetters = v; return self end
    function w:SetCallback(name, fn) self.callbacks[name] = fn; return self end
    function w:AddChild(child) self.children[#self.children + 1] = child; return self end
    function w:ReleaseChildren() self.children = {}; return self end
    function w:DoLayout() self.layoutCount = (self.layoutCount or 0) + 1; return self end
    -- AceGUI invokes a callback as fn(widget, eventName, ...); mirror that exactly, because the
    -- makers destructure it as function(_, _, value).
    function w:__fire(name, ...)
      local fn = self.callbacks[name]
      if fn then return fn(self, name, ...) end
    end

    if wtype == "ScrollFrame" then
      -- The always-shown-scrollbar patch reaches into these three by name and does real work with
      -- them.
      w.scrollbar   = stubFrame()
      w.scrollframe = stubFrame()
      w.content     = stubFrame()
      w.content.original_width = 400
      w.localstatus = { offset = 0 }
      function w:FixScroll() self.fixScrollCount = (self.fixScrollCount or 0) + 1 end
      function w:MoveScroll(v) self.movedTo = v end
      function w:SetScroll(v) self.scrolledTo = v end
    end
    return w
  end

  aceGUI = {
    -- Populated by RegisterWidgetType. Empty by default, which models
    -- AceGUI-3.0-SharedMediaWidgets being absent: a dropdown maker asks GetWidgetVersion about
    -- LSM30_* and falls back to a plain Dropdown when it comes back nil.
    WidgetRegistry   = {},
    __widgetVersions = {},
    -- AceGUI:RegisterLayout's table, keyed by the upper-cased name (revision 17).
    LayoutRegistry   = {},
  }
  -- The version table under its real name as well (revision 17). The SAME table, not a copy: the
  -- kit has always kept it as `__widgetVersions`, and a host that reads AceGUI's own field --
  -- ConsumableMaster's fake grew one for exactly that -- must see what RegisterWidgetType wrote.
  aceGUI.WidgetVersions = aceGUI.__widgetVersions
  function aceGUI.RegisterLayout(_, name, fn)
    assert(type(fn) == "function")
    if type(name) == "string" then name = name:upper() end
    aceGUI.LayoutRegistry[name] = fn
  end
  function aceGUI.GetLayout(_, name)
    if type(name) == "string" then name = name:upper() end
    return aceGUI.LayoutRegistry[name]
  end
  -- Every widget this factory hands out, in creation order. Harness-side only — no production code
  -- knows it exists. It is the only way a test can reach a widget on a page whose ctx the toolkit
  -- keeps private, which is why a button's onClick once shipped unreachable and therefore untested.
  aceGUI.__created = {}
  function aceGUI:Create(wtype)
    local ctor = self.WidgetRegistry[wtype]
    local w = ctor and ctor() or makeWidget(wtype)
    self.__created[#self.__created + 1] = w
    return w
  end
  function aceGUI:GetWidgetVersion(wtype) return self.__widgetVersions[wtype] end
  function aceGUI:RegisterWidgetType(wtype, ctor, version)
    self.WidgetRegistry[wtype]   = ctor
    self.__widgetVersions[wtype] = version
  end

  -- AceGUI:Release, in the real one's order (AceGUI-3.0.lua): guarded against a release reached
  -- from inside its own release, the frame hidden, "OnRelease" fired while the widget still has its
  -- children and its callbacks, the children released, the widget's own :OnRelease() run, and only
  -- then the widget wiped: `userdata` and the callbacks cleared in place, so a widget handed back
  -- cannot fire a stale handler or carry stale data; the size fields the real one nils (`width`,
  -- `height`, `relWidth`, `relHeight`, `noAutoHeight`, plus `relativeWidth`, this fake's recorder
  -- for SetRelativeWidth) dropped; the frame's points cleared and its parent reset to UIParent.
  -- LibKa0s's OptionsWidgets.lua relies on that order: it hides its band texture from an OnRelease
  -- callback. On top of the real behavior sits the recorder a test needs and the client does not:
  -- `w.__released = true`, and `AceGUI.__released` listing every widget taken back, in order.
  --
  -- Two differences, both deliberate. The real one parks the widget in a pool a later `Create` may
  -- hand back; this factory never reuses a widget, so a `Create` after a Release is always fresh.
  -- And the children go through the widget's own `ReleaseChildren`, which on a widget from this
  -- factory forgets them rather than releasing each one: making it release them is a change to
  -- every re-rendering panel in the collection, and a revision of its own.
  --
  -- Two raises, both as in the client (fidelity rule 1). `nil` raises on the first index. A second
  -- Release of the same widget raises "Attempt to Release Widget that is already released", which
  -- the real one raises from delWidget at its END, after re-running the steps above; because this
  -- factory never reuses a widget, the fake can tell at the top and raises before touching it.
  aceGUI.__released = {}
  function aceGUI:Release(widget)
    if widget.isQueuedForRelease then return end
    if widget.__released then error("Attempt to Release Widget that is already released", 2) end
    widget.isQueuedForRelease = true
    if widget.frame then widget.frame:Hide() end
    if widget.__fire then widget:__fire("OnRelease") end
    if widget.ReleaseChildren then widget:ReleaseChildren() end
    if widget.OnRelease then widget:OnRelease() end
    for _, bag in ipairs({ widget.userdata, widget.callbacks }) do
      if type(bag) == "table" then
        for k in pairs(bag) do bag[k] = nil end
      end
    end
    widget.width, widget.height, widget.relativeWidth = nil, nil, nil
    widget.relWidth, widget.relHeight, widget.noAutoHeight = nil, nil, nil
    if widget.frame then
      widget.frame:ClearAllPoints()
      widget.frame:SetParent(M.UIParent)
    end
    widget.__released = true
    self.__released[#self.__released + 1] = widget
    widget.isQueuedForRelease = nil
  end
  M.__makeAceGUIWidget = makeWidget
  libs["AceGUI-3.0"] = aceGUI

  -- Real surfaces since revision 17 (makeAceTimer, makeAceConsole, above). Until then both Embeds
  -- returned the target untouched, so only the NewAddon target ever had a timer or a printer.
  libs["AceTimer-3.0"] = makeAceTimer(M)
  libs["AceConsole-3.0"] = makeAceConsole(M)

  -- LibStub. The Ace libraries are fakes looked up from `libs`; vendored LibKa0s modules register
  -- for real through NewLibrary, exactly as they do in the client.
  --
  -- STRICT about the silent flag, matching the real LibStub. A lookup table that never raised meant
  -- `LibStub("LibKa0s-Options-1.0")` — written WITHOUT `, true` — resolved to nil headlessly and
  -- passed the whole suite green, then hard-errored in the client in exactly the install the
  -- degradation stubs exist to protect. Every soft-optional lookup passes `, true`; a missing one
  -- is a bug, and this is the only thing that can say so.
  local minors = {}
  M.LibStub = setmetatable({
    GetLibrary = function(_, major, silent)
      if libs[major] == nil and not silent then
        error("Cannot find a library instance of " .. tostring(major))
      end
      return libs[major], minors[major]
    end,
    NewLibrary = function(_, major, minor)
      minor = tonumber(minor)
      if minors[major] and minors[major] >= minor then return nil end
      libs[major] = libs[major] or {}
      minors[major] = minor
      return libs[major], minors[major]
    end,
  }, { __call = function(self, major, silent) return self:GetLibrary(major, silent) end })

  return M
end
