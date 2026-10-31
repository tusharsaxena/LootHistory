-- testkit/mock_ace.lua — the Ace fakes of the universal mock (revision 47): CallbackHandler-1.0,
-- AceEvent-3.0's event half, AceConsole-3.0's print mixins, AceTimer-3.0, AceConsole-3.0, AceEvent-3.0
-- and AceAddon-3.0.
--
-- Moved out of `mock_base.lua`, unchanged, at revision 47 (LK-M2-PEEL of Ka0sAddonsCommonTasks
-- docs/2026-10-31-FINDINGS_REMEDIATION), on the seam CLAUDE.md's band census named: that file sat 35
-- lines from `layout-§1`'s cap. Its fidelity rules bind this file. AceGUI stays there, inside the
-- builder, because it closes over the frames that file tracks.
--
-- Loaded by `mock_base.lua` from its own folder, like `mock_record.lua`, and not opt-in for the same
-- reason: every suite reads these fakes. Answers the seven names the builder calls; each `make*`
-- takes the mock and builds a fresh surface, so this chunk holds no state of its own.

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
-- The build a target belongs to rides on its `__events` table's METATABLE, because these functions
-- are shared by every build and have no closure to hold it in. Not a table keyed by `__events`:
-- through kit revision 22 it was a process-wide weak-keyed one, and its value (the build) reaches
-- its own key again through AceEvent's `embeds`. Lua 5.1 has no ephemerons, so that entry could
-- never be collected, and neither could any build or any instance ever embedded in one -- a
-- consumer building a fresh instance per case held all 1,678 of them to the end of the run. On the
-- metatable the reference lives and dies with the table itself. `__events` carries no metatable of
-- its own and a table's metatable is invisible to `next` and `pairs`, so its contents read as before.
local function buildOf(events)
  local mt = getmetatable(events)
  return mt and mt.__kitBuild
end

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
  -- Kit revision 39: the handler is ALSO kept where unregister never reaches, so that
  -- `M.__fireUnconditional` can still find a method-name or function handler after a stand-down.
  local mt = getmetatable(self.__events)
  if mt then mt.__kitEver = mt.__kitEver or {}; mt.__kitEver[event] = method end
  local build = buildOf(self.__events)
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
  local build = buildOf(self.__events)
  if build then build.events:unregister(self, event) end
  return self
end

-- Cleared IN PLACE, so a table a test captured stays the live one. Messages are untouched, as
-- they are in the client: AceEvent keeps the two in separate CallbackHandler registries.
local function unregisterAllEvents(self)
  for k in pairs(self.__events) do self.__events[k] = nil end
  local build = buildOf(self.__events)
  if build then build.events:unregisterAll(self) end
  -- A target that is ALSO a frame carries the two raw tables, and `UnregisterAllEvents` on a frame
  -- clears those in the client too. Embedding replaced this method, so without these two lines an
  -- embedded frame's raw and per-unit registrations survived the one call whose whole meaning is
  -- that nothing is registered any more -- which would leave the registration set non-empty for a
  -- reason that has nothing to do with the addon under test.
  if type(self.__frameEvents) == "table" then self.__frameEvents = {} end
  if type(self.__unitEvents) == "table" then self.__unitEvents = {} end
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
  -- A second Embed in the same build keeps the never-cleared handler record (kit revision 39).
  local old = getmetatable(target.__events)
  setmetatable(target.__events, { __kitBuild = build, __kitEver = old and old.__kitEver })
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
  AceAddon.frame = M.__stubFrame()
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

return {
  makeAceTimer = makeAceTimer, makeAceConsole = makeAceConsole, makeAceEvent = makeAceEvent,
  makeAceAddon = makeAceAddon, embedEvents = embedEvents,
  printMixin = printMixin, printfMixin = printfMixin,
}
