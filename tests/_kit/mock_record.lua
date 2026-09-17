-- testkit/mock_record.lua — the recording half of the universal mock (revision 22).
--
-- `mock_base.lua` builds the client; this file makes what the client was told ASSERTABLE. Everything
-- here answers one of five questions about an addon at a moment in time:
--
--   * what is it REGISTERED for            `M.__registrations()`
--   * what is still going to WAKE UP       `M.__timers()`
--   * what is on SCREEN                    `M.__shownFrames()`
--   * what has it WRITTEN to disk          `M.__svWrites()`
--   * what has it SAID to the player       `M.__printed()`
--
-- WHY THOSE FIVE, AND WHY THEY ARRIVED TOGETHER. An addon that has been switched off has to answer
-- "nothing" to all five, and until this revision a suite could ask only the first two, badly. That
-- is not a coverage gap; it is what made the question unaskable. Eleven addons in this collection
-- implement "disabled" as a DRAW GATE: the frames go away, the registrations stay, and the client
-- goes on walking the addon's registration list on every UNIT_AURA in a twenty-five-man raid,
-- building the argument frame, entering Lua and running the comparison that decides to leave. From
-- outside, that is indistinguishable from an addon that genuinely stood down — which is exactly how
-- the draw gate survived eleven audits. A suite written against a handler's early return CANNOT
-- tell the two apart, because an early return is what a draw gate does. A suite written against
-- THIS registry can, and that is the whole reason these members exist.
--
-- FIDELITY RULE 3, RESTATED WITH TEETH: a mock that does not REMOVE on unregister makes the
-- assertion unfalsifiable in the opposite direction. A no-op `RegisterUnitEvent` lets a widened or
-- dropped per-unit filter pass; a `UnregisterAllEvents` that records nothing lets an addon that
-- never unregistered pass a test whose whole subject is unregistering. Both halves are recorded
-- here and in `mock_base.lua`'s frame stub, which is why `M.__fireUnconditional` exists beside
-- `M.__fire`: the first proves a survivor WOULD have been caught, and without it "no handler ran"
-- is a claim about the harness rather than about the addon.
--
-- WHY IT IS A FILE OF ITS OWN. `mock_base.lua` sat one line under `layout-§1`'s 1500-line cap, so
-- this surface could not be added to it without a breach and a census row. The cut is not arbitrary
-- to fit, though — the seam was already there. Everything in this file is either a survey of what
-- the mock remembers, or one of the two fakes those surveys read THROUGH: `AceDB-3.0`, because a
-- SavedVariables write has to land somewhere before it can be reported, and `AceBucket-3.0`,
-- because a bucket registration is a registration a stand-down has to remove and nothing in the
-- kit modeled one. The timer queue moves with them for the same reason: `M.__timers` is the record
-- of what is scheduled, and it belongs with the other four records rather than beside the clock.
--
-- Installed by `mock_base.lua` itself rather than opted into the way `mock_ids.lua` is. An opt-in
-- survey is a survey a consumer forgets to switch on, and a stand-down suite that runs against a
-- mock with no registry does not fail — it passes, over an empty table, which is the one outcome
-- worse than no suite at all.

--- Install the recording surfaces onto a half-built mock.
---
--- `ctx` is `mock_base.lua`'s own build context, and everything in it is internal to that file:
---
---   frames     table     the build's weak set of every frame it made, keyed by frame.
---   libs       table     the LibStub fake's registry, so this file can add its two.
---   events     table     the game-event CallbackHandler registry (`[event] = { [target] = fn }`).
---   messages   table     the message CallbackHandler registry, same shape.
---   aceTimer   table     the AceTimer-3.0 fake, for its `activeTimers`.
return function(M, ctx)
  local deepcopy = M.__deepcopy

  -- A stable number for any table the surveys below have to ORDER. Frames carry `__seq`, but an
  -- AceEvent target, a timer handle and a bucket handle are plain tables with nothing to sort on,
  -- and every survey here has to come back in the same order twice or a suite asserting on one is
  -- asserting on somebody else's hash seed. Assigned on first sight, weak-keyed, never reused.
  local ids, idSeq = setmetatable({}, { __mode = "k" }), 0
  local function idOf(t)
    if type(t) ~= "table" then return 0 end
    local id = ids[t]
    if not id then
      idSeq = idSeq + 1
      id = idSeq
      ids[t] = id
    end
    return id
  end

  -- ── timers ───────────────────────────────────────────────────────────────────────────────
  -- Scheduled one-shot timers, recorded so tests can inspect coalescing and fire them on demand.
  --
  -- CANCELLATION IS HONORED (revision 17). A queue entry is skipped once it has been canceled -- a
  -- C_Timer.NewTimer handle through its own `Cancel`, an AceTimer handle through CancelTimer -- and
  -- `__fireTimers` answers how many entries actually RAN, so "three events, one pass" and "the
  -- pending timer was canceled" are both assertable. Until 17, NewTimer's Cancel was a no-op and
  -- a canceled debounce still fired, which is the bug a debounce test exists to catch. Both kinds
  -- record it on the handle as `handle.cancelled`, AceTimer's own field name.
  -- THE QUEUE IS ALSO CALLABLE (revision 22). `M.__timers` is, as it always was, the array of
  -- entries waiting for `__fireTimers`, and every existing suite keeps indexing it. CALLED --
  -- `M.__timers()` -- it answers the LIVE set instead: every armed AceTimer handle, every
  -- un-canceled C_Timer ticker, and every frame carrying an OnUpdate script. The two are different
  -- questions and both are needed. The queue answers "what is pending"; the live set answers "is
  -- anything still going to wake up", which is the question a stood-down addon has to answer NO to
  -- and which a pending-queue read cannot: a repeating ticker that has just fired is absent from
  -- the queue for a moment and is still very much alive.
  --
  -- A metatable rather than a second member because the name is the answer: `M.__timers` is where
  -- every consumer already looks for timers, and a `M.__liveTimers()` beside it would be a second
  -- place to look and a second thing to forget. `newTimerQueue` exists because `__fireTimers`
  -- REPLACES the table, and a bare `{}` there would silently drop the call metamethod.
  local function liveTimers()
    local out, seen = {}, {}
    local function add(handle)
      if handle == nil or seen[handle] then return end
      seen[handle] = true
      out[#out + 1] = handle
    end
    for _, t in ipairs(M.__timers) do
      if not (t.cancelled or (t.timer and t.timer.cancelled)) then add(t.timer or t) end
    end
    for handle, timer in pairs(ctx.aceTimer and ctx.aceTimer.activeTimers or {}) do
      if not timer.cancelled then add(type(handle) == "table" and handle or timer) end
    end
    for f in pairs(ctx.frames) do
      if f.__scripts and f.__scripts.OnUpdate ~= nil then add(f) end
    end
    table.sort(out, function(a, b) return idOf(a) < idOf(b) end)
    return out
  end
  local function newTimerQueue()
    return setmetatable({}, { __call = liveTimers })
  end
  M.__timers = newTimerQueue()
  M.__fireTimers = function()
    local due = M.__timers
    M.__timers = newTimerQueue()
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
  -- ── the SavedVariables fake, and the writes that land in it ──────────────────────────────

  -- Every SavedVariables root the AceDB fake has handed out, in creation order.
  local svRoots = {}

  -- AceDB-3.0 with a WORKING profile surface. A bare {global, profile} stub leaves an addon's
  -- entire `profile` verb untestable: the handler bails at `if not db.SetProfile` before touching a
  -- single subcommand, so a broken switch/copy/delete passes the suite silently. Model enough of
  -- the real lib to exercise it — a named profile store, switch/copy/delete/reset, and the
  -- OnProfileChanged / OnProfileCopied / OnProfileReset callbacks AceDB fires via CallbackHandler.
  ctx.libs["AceDB-3.0"] = {
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
      -- The SavedVariables root this db is a view onto, remembered so `M.__svWrites()` has a tree
      -- to diff. One entry per db, under the global name the addon asked for, because the report a
      -- suite reads has to say WHICH file a write landed in when a host keeps two.
      svRoots[#svRoots + 1] = { name = type(tbl) == "string" and tbl or "<table>", sv = sv }

      db.sv      = sv
      db.global  = sv.global
      db.profile = ensureProfile(current)

      -- `key` is the third argument AceDB-3.0 hands the callback, and it is NOT always the active
      -- profile: OnProfileChanged carries the profile switched TO, but OnProfileCopied carries the
      -- SOURCE of the copy (`self.callbacks:Fire("OnProfileCopied", self, name)`, AceDB-3.0.lua
      -- CopyProfile). Through revision 17 this fired every event with the active profile, so a
      -- copy of "Raid" into "Default" reached the handler as a copy of "Default" — fidelity rule 5.
      -- Revision 18 passes each event its own key. OnProfileReset carries NONE, as AceDB-3.0's
      -- ResetProfile fires it (`self.callbacks:Fire("OnProfileReset", self)`); through revision 18
      -- it carried the active profile, so a handler reading its third argument on a reset passed
      -- here and got nil in the client (revision 19). Vararg, so a keyless event hands the callback
      -- exactly two arguments, as CallbackHandler does.
      local function fire(event, ...)
        for _, cb in ipairs(callbacks[event] or {}) do cb(event, db, ...) end
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
        fire("OnProfileChanged", current)
      end

      db.ResetProfile = function()
        -- Wipe in place: the real lib keeps the profile table's identity across a reset, so
        -- anything holding a reference to db.profile keeps seeing the live table.
        local p = sv.profiles[current]
        for k in pairs(p) do p[k] = nil end
        copyDefaults(p, defaults and defaults.profile)
        fire("OnProfileReset")   -- the db alone, as AceDB-3.0 fires it (revision 19)
      end

      db.CopyProfile = function(_, name)
        local src = sv.profiles[name]
        if not src or name == current then return end
        local p = sv.profiles[current]
        for k in pairs(p) do p[k] = nil end
        for k, v in pairs(deepcopy(src)) do p[k] = v end
        fire("OnProfileCopied", name)   -- the SOURCE, as AceDB-3.0 fires it (revision 18)
      end

      db.DeleteProfile = function(_, name)
        if name == current then return end
        sv.profiles[name] = nil
      end

      return db
    end,
  }

  --- Watch a SavedVariables root this file did not create. A host that writes a global directly —
  --- LibKa0s-Perf-1.0's record ring is the collection's example, `_G[descriptor.sv]` — never goes
  --- through AceDB, so its writes would be invisible to the survey below. Naming the global here
  --- puts it in the same report. Takes the GLOBAL NAME, because the table under it may not exist
  --- yet at the moment a suite wants to start watching, and re-resolved on every read for the same
  --- reason.
  function M.__watchSv(name)
    svRoots[#svRoots + 1] = { name = name, global = name }
    return M.__resetSvWrites()
  end

  local function rootOf(entry)
    if entry.global then return _G[entry.global] end
    return entry.sv
  end

  -- The baseline every report is measured against: a deep snapshot of every watched root, taken at
  -- the last `__resetSvWrites()`.
  --
  -- A SNAPSHOT DIFF, NOT AN INTERCEPTION, and the reason is Lua 5.1 rather than taste. A recording
  -- proxy over `db.profile` would have to keep the data in a shadow table to see a write to a key
  -- that already exists — `__newindex` fires only for an ABSENT key — and 5.1 has no `__pairs`, so
  -- every `for k, v in pairs(db.profile)` in production code would then iterate nothing. That is a
  -- mock that silently changes what the addon does, which is worse than one that reports a little
  -- less. What the diff cannot see is a write of the IDENTICAL value over itself; what it is asked
  -- to prove is that a stood-down addon wrote NOTHING, and a write that changed nothing changed
  -- nothing. Where a suite needs the stronger claim, it writes a sentinel first and asserts the
  -- sentinel survived.
  local baseline = {}

  local function snapshot()
    local out = {}
    for i, entry in ipairs(svRoots) do out[i] = deepcopy(rootOf(entry)) end
    return out
  end

  --- Re-baseline. Every write from here on is a write this report will carry.
  function M.__resetSvWrites()
    baseline = snapshot()
    return M
  end

  local function walk(prefix, now, was, out)
    if type(now) ~= "table" then return end
    for k, v in pairs(now) do
      local path = prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
      -- Spelled out rather than folded into an `and`/`or` chain. A stored `false` is a perfectly
      -- good value and `x and false or nil` yields nil, which would report every unticked checkbox
      -- in the addon as a fresh write on every single report.
      local old
      if type(was) == "table" then old = was[k] end
      if type(v) == "table" then
        walk(path, v, old, out)
      elseif v ~= old then
        out[#out + 1] = { path = path, value = v }
      end
    end
    -- A key that WAS there and is not any more is a write too: `db.profile.x = nil` is how a
    -- setting is cleared, and a report that only saw additions would call that no write at all.
    if type(was) == "table" then
      for k, v in pairs(was) do
        local path = prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
        if now[k] == nil and type(v) ~= "table" then out[#out + 1] = { path = path, value = nil } end
      end
    end
  end

  --- Every write that reached a watched SavedVariables tree since the last reset, as
  --- `{ path, value }` in path order. `path` is dotted and carries the root's global name first,
  --- so two databases in one addon are told apart in the report rather than in the reader's head.
  function M.__svWrites()
    local out = {}
    for i, entry in ipairs(svRoots) do
      walk(entry.name, rootOf(entry), baseline[i], out)
    end
    table.sort(out, function(a, b) return a.path < b.path end)
    return out
  end

  -- ── what reached the player ──────────────────────────────────────────────────────────────

  local printed = {}

  --- Record a line the addon emitted. Called for you by the chat frame below; exported because a
  --- host whose printer does not end at `DEFAULT_CHAT_FRAME` — one that writes to its own console
  --- window, say — otherwise has a printer this survey cannot see, and "zero lines printed" would
  --- then be a statement about the harness.
  function M.__recordPrint(line)
    printed[#printed + 1] = tostring(line)
    return line
  end

  function M.__printed()
    local out = {}
    for i, line in ipairs(printed) do out[i] = line end
    return out
  end

  function M.__resetPrinted()
    printed = {}
    return M
  end

  -- The chat frame's own AddMessage, defined rather than answered by the frame stub's metatable.
  -- Through revision 21 it returned the frame and remembered nothing, so every line an addon
  -- printed went into the void: a suite could assert that a HANDLER ran, never that the player was
  -- told something. One addon in the collection prints to chat on entering combat while disabled,
  -- and that line is invisible to every assertion that does not exist here.
  function M.DEFAULT_CHAT_FRAME:AddMessage(text)
    M.__recordPrint(text)
    return self
  end

  -- ── AceBucket-3.0 ────────────────────────────────────────────────────────────────────────
  --
  -- A bucket is a REGISTRATION, and until this revision the kit had no model of one at all — so an
  -- addon that coalesced its UNIT_AURA traffic through AceBucket had a registration set no suite
  -- could see, and a stand-down that forgot `UnregisterAllBuckets` passed every test in its repo.
  --
  -- Modeled as the real one is, in the one respect that matters here: the events are watched, and
  -- the callback runs LATER, on the bucket's interval, with a table of the units seen. It is
  -- deliberately not modeled beyond that — no message buckets fanning into event buckets, no
  -- shared frame — because what a suite asks a bucket is "are you still registered" and "did you
  -- fire", and a fuller fake would be a second implementation of a library nobody is testing.
  local buckets = {}

  local function makeAceBucket()
    local AceBucket = { embeds = {} }

    local function registerBucket(self, kind, events, interval, callback)
      local list = {}
      if type(events) == "table" then
        for _, e in ipairs(events) do list[#list + 1] = e end
      else
        list[1] = events
      end
      if type(callback) == "string" then
        if type(self[callback]) ~= "function" then
          error("Usage: RegisterBucket(event, interval, callback): 'callback' - method '"
            .. callback .. "' not found on self.", 3)
        end
      elseif type(callback) ~= "function" then
        error("Usage: RegisterBucket(event, interval, callback): 'callback' - string or function expected.", 3)
      end
      local handle = { target = self, kind = kind, events = list,
                       interval = tonumber(interval) or 0.1, callback = callback }
      buckets[handle] = handle
      return handle
    end

    function AceBucket.RegisterBucketEvent(self, events, interval, callback)
      return registerBucket(self, "bucket", events, interval, callback)
    end
    function AceBucket.RegisterBucketMessage(self, messages, interval, callback)
      return registerBucket(self, "bucketMessage", messages, interval, callback)
    end
    function AceBucket.UnregisterBucket(_, handle)
      if buckets[handle] == nil then return false end
      buckets[handle] = nil
      return true
    end
    function AceBucket.UnregisterAllBuckets(self)
      for handle in pairs(buckets) do
        if handle.target == self then buckets[handle] = nil end
      end
    end
    function AceBucket.Embed(_, target)
      AceBucket.embeds[target] = true
      target.RegisterBucketEvent    = AceBucket.RegisterBucketEvent
      target.RegisterBucketMessage  = AceBucket.RegisterBucketMessage
      target.UnregisterBucket       = AceBucket.UnregisterBucket
      target.UnregisterAllBuckets   = AceBucket.UnregisterAllBuckets
      return target
    end
    function AceBucket.OnEmbedDisable(_, target) AceBucket.UnregisterAllBuckets(target) end
    return AceBucket
  end

  ctx.libs["AceBucket-3.0"] = makeAceBucket()

  --- Queue one bucket's callback the way the real library queues it: on the bucket's own interval,
  --- with the table of arguments seen in the window. Onto the kit's one timer queue, so a bucket
  --- left armed on a stood-down addon shows up in `M.__timers()` exactly like any other timer.
  local function fireBucket(handle, arg)
    handle.__pending = handle.__pending or {}
    handle.__pending[arg or true] = (handle.__pending[arg or true] or 0) + 1
    if handle.__armed then return end
    handle.__armed = true
    M.__timers[#M.__timers + 1] = { fn = function()
      local payload = handle.__pending
      handle.__pending, handle.__armed = nil, nil
      -- A bucket the addon unregistered between the event and the tick does NOT call back. Real
      -- AceBucket cancels its timer on UnregisterBucket; here the queue entry survives and the
      -- guard is what makes the two agree.
      if buckets[handle] == nil then return end
      if type(handle.callback) == "string" then
        handle.target[handle.callback](handle.target, payload)
      else
        handle.callback(payload)
      end
    end, delay = handle.interval }
  end

  -- ── the registration survey ──────────────────────────────────────────────────────────────

  --- Every LIVE registration this build holds, as `{ target, kind, event, unit }`, in a stable
  --- order. `kind` is one of:
  ---
  ---   "event"          AceEvent `RegisterEvent` on an embedded target
  ---   "message"        AceEvent `RegisterMessage` — the addon bus
  ---   "bucket"         AceBucket `RegisterBucketEvent` / `RegisterBucketMessage`
  ---   "frame"          a RAW `frame:RegisterEvent`
  ---   "unit"           `frame:RegisterUnitEvent`, one row PER UNIT TOKEN
  ---
  --- Per unit token rather than per event, because the per-unit filter is the thing a stand-down
  --- most often widens by accident: an addon that re-registers `UNIT_AURA` for every unit instead
  --- of the enabled ones has the same event count and a different registration set.
  ---
  --- ENTRIES ARE REMOVED ON THE CORRESPONDING UNREGISTER, and on `UnregisterAllEvents`. That is
  --- the half that makes an assertion falsifiable in the useful direction: a registry that only
  --- ever grew would report a perfectly torn-down addon as still watching everything, and a suite
  --- written against it would be tuned until it passed — which means tuned until it no longer
  --- asks the question.
  function M.__registrations()
    local out = {}
    local function push(target, kind, event, unit)
      out[#out + 1] = { target = target, kind = kind, event = event, unit = unit }
    end
    for event, list in pairs(ctx.events.events) do
      for target in pairs(list) do push(target, "event", event) end
    end
    for message, list in pairs(ctx.messages.events) do
      for target in pairs(list) do push(target, "message", message) end
    end
    for handle in pairs(buckets) do
      for _, event in ipairs(handle.events) do push(handle.target, handle.kind, event) end
    end
    for f in pairs(ctx.frames) do
      for event in pairs(f.__frameEvents or {}) do push(f, "frame", event) end
      for event, units in pairs(f.__unitEvents or {}) do
        if #units == 0 then
          push(f, "unit", event)
        else
          for _, unit in ipairs(units) do push(f, "unit", event, unit) end
        end
      end
    end
    table.sort(out, function(a, b)
      local ia, ib = idOf(a.target), idOf(b.target)
      if ia ~= ib then return ia < ib end
      if a.kind ~= b.kind then return a.kind < b.kind end
      if a.event ~= b.event then return a.event < b.event end
      return tostring(a.unit) < tostring(b.unit)
    end)
    return out
  end

  --- Fire `event` at the LIVE registration set only — every AceEvent target registered for it,
  --- every bucket watching it, and every frame whose raw or per-unit registration is still in
  --- place. Answers how many handlers ran.
  ---
  --- This is the honest half of the pair. The client fires an event at whoever is registered for
  --- it, and nothing else, so a suite that drove handlers directly would be testing its own ability
  --- to call functions.
  function M.__fire(event, ...)
    local ran = ctx.events:fire(event, ...)
    local seen = {}
    for _, reg in ipairs(M.__registrations()) do
      if reg.event == event then
        if reg.kind == "bucket" or reg.kind == "bucketMessage" then
          for handle in pairs(buckets) do
            if handle.target == reg.target and not seen[handle] then
              for _, e in ipairs(handle.events) do
                if e == event then seen[handle] = true; fireBucket(handle, (...)); ran = ran + 1 end
              end
            end
          end
        elseif (reg.kind == "frame" or reg.kind == "unit") and not seen[reg.target] then
          local onEvent = reg.target.__scripts and reg.target.__scripts.OnEvent
          if onEvent then
            seen[reg.target] = true
            onEvent(reg.target, event, ...)
            ran = ran + 1
          end
        end
      end
    end
    return ran
  end

  --- Fire `event` AT `target` whether or not it is still registered.
  ---
  --- The falsification half, and it is not a convenience. `M.__fire` over an empty registry runs
  --- nothing, so "no SavedVariables write, no printed line, no frame shown" is true of a correctly
  --- stood-down addon AND of a harness that lost the ability to dispatch at all. Firing at a target
  --- whose registration has been removed is what proves a survivor WOULD have been caught: the
  --- handler is still there, it is simply no longer reachable from the client, and this reaches it
  --- anyway. A suite that omits this step is asserting on its own silence.
  function M.__fireUnconditional(target, event, ...)
    if type(target) ~= "table" then return 0 end
    local scripts = rawget(target, "__scripts")
    if scripts and scripts.OnEvent then
      scripts.OnEvent(target, event, ...)
      return 1
    end
    local events = rawget(target, "__events")
    local handler = events and events[event]
    if type(handler) == "function" then handler(event, ...); return 1 end
    if type(handler) == "string" and type(target[handler]) == "function" then
      target[handler](target, event, ...)
      return 1
    end
    -- LAST RESORT: the method named for the event. AceEvent's default method IS the event's own
    -- name, and the recorded handler is removed on unregister -- correctly, because that is what
    -- makes the registration set falsifiable -- so by the time this member is worth calling there
    -- is nothing left in `__events` to find. The method itself is still on the addon table, which
    -- is precisely the survivor this is here to reach: a handler that merely early-returns is
    -- still a handler, and the client would still have paid to call it.
    if type(target[event]) == "function" then
      target[event](target, event, ...)
      return 1
    end
    return 0
  end

  -- ── what is on screen ────────────────────────────────────────────────────────────────────

  --- Every frame this build made that is currently shown, in creation order.
  ---
  --- Creation order rather than `pairs` order because a suite compares this list against one taken
  --- earlier — "every frame that was shown is now hidden" — and two lists of the same frames in
  --- two different orders are a diff nobody can read.
  function M.__shownFrames()
    local out = {}
    for f in pairs(ctx.frames) do
      if f.__shown then out[#out + 1] = f end
    end
    table.sort(out, function(a, b) return (a.__seq or 0) < (b.__seq or 0) end)
    return out
  end

  M.__resetSvWrites()
  return M
end
