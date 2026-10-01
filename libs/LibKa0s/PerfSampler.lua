-- LibKa0s-Perf-1.0 — the capture: the Shape B brackets, the combat-gated measurement windows, the
-- FPS sampler that drives them, and the perf hold's Suspend / Resume.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF Perf.lua ─────────────────────────────────────
--
-- Because of `layout-§1`. Perf.lua stood at 1307 lines after issue #7's first peel moved the
-- command surface to PerfCommands.lua, still in the 1000–1500 band, and the issue's own seam was
-- the sampler. It moved here unchanged at Perf minor 14 with the two things it shares state with:
-- the Shape B brackets, whose open depth every window edge resets, and the hold the windows take
-- and give back. What it reads of lib:New's closure is passed in, and the four per-run tables
-- P.Reset replaces (the FPS arms and the completion pair among them) are read through getters, so
-- a reset is seen here exactly as it was when this code sat inside the closure.
--
-- It is NOT a major of its own: it is part of `LibKa0s-Perf-1.0`, guarded with PerfPanel.lua's
-- multi-file idiom, so a capture from one vendored copy never pairs with a probe from another
-- without saying so. A payload without this file still builds instances: the brackets are inert,
-- every command answers one line naming the missing file, and nothing runs (Perf.lua's stub).

local lib = LibStub and LibStub("LibKa0s-Perf-1.0", true)
if not lib then return end

local SAMPLER_MINOR = 1
-- Paired on the PROBE's minor as well as this file's own, as PerfCommands.lua is: a capture that
-- attached to an older probe would install windows written against members that probe may not
-- have, and nothing would say the two came from different vendored copies.
if lib.__samplerMinor and lib.__samplerMinor >= SAMPLER_MINOR
  and lib.__samplerShellMinor == lib.MINOR then return end
lib.__samplerMinor      = SAMPLER_MINOR
lib.__samplerShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.PerfSampler = SAMPLER_MINOR

--- Install the capture on one instance. Called by lib:New with the instance and the closure values
--- the capture reads: `ctx.d` (the descriptor, whose `lifecycle` is the latch), `ctx.hold` (the
--- latch key this module owns), `ctx.publishState` (repaint and tell the host), and `ctx.arms` and
--- `ctx.completed`, getters for the FPS arms and the arm-completion pair, which P.Reset replaces.
--- Returns the function P.Reset calls to close every open bracket.
function lib.__installSampler(P, ctx)
  local d, publishState = ctx.d, ctx.publishState
  local arms, done = ctx.arms, ctx.completed
  local lc, HOLD = d.lifecycle, ctx.hold

  -- Shape B's open slots, innermost last (performance-§2). Touched only while `P.on` is true, so a
  -- dormant probe neither allocates into it nor reads it.
  --
  -- A HIGH-WATER FREE LIST, not a stack of fresh tables. `slots[i]` is the slot for nesting depth
  -- i and is built ONCE, the first time any capture in this session nests that deep; `openDepth`
  -- is how many of them are open right now, and it is what bounds every read below rather than
  -- `#slots`. The old shape allocated `{ key = key, t0 = ... }` per Open, which is one table per
  -- bracketed call for the length of a window — garbage the collector then walks during the very
  -- capture that is trying to hold everything else still and read somebody else's frame cost.
  -- Depth is small and bounded by the host's own nesting (two, in every descriptor shipped), so
  -- the list stops growing after the first few brackets and the steady state allocates nothing.
  local slots = {}
  local openDepth = 0

  --- Open a Shape B bracket on `key` (performance-§2). Pair with P.Close(key) on EVERY exit.
  ---
  --- STATE THE COST HONESTLY, because the docstring this replaces did not. This pair is NOT free
  --- when capture is off: it is two real Lua calls plus the boolean test inside each. The inline
  --- Shape A bracket —
  ---
  ---     local t0 = P.on and debugprofilestop()
  ---     ...
  ---     if t0 then P.Note("paintBar", debugprofilestop() - t0) end
  ---
  --- — costs one upvalue read, one field read and one boolean test, and NO call at all. Shape A is
  --- therefore the default and is mandatory on anything running per frame or per combat-log event;
  --- the earlier claim here that the pair cost "one boolean test and nothing else, and allocates
  --- nothing on either path" was simply false, and a docstring that says so is a defect rather
  --- than a description to trust.
  ---
  --- What the pair buys is a MULTI-EXIT region: four exits do not each repeat
  --- `if t0 then P.Note(key, debugprofilestop() - t0) end`. That ergonomic difference is not
  --- cosmetic — a host's four-exit poll had its instrumentation omitted precisely because the exits
  --- made it awkward, and the omission then cost 73.9 ms of unattributed time in the first live
  --- capture. Where a multi-exit region is ALSO a hot path, restructure it to one exit and use
  --- Shape A rather than paying two calls a frame.
  ---
  ---     P.Open("pollSpell")
  ---     if not pollable(id) then P.Close("pollSpell") return nil end
  ---     ...
  ---     P.Close("pollSpell")
  ---     return state
  ---
  --- Open TAKES THE KEY (it did not, through minor 6, and the reading was handed back to the call
  --- site instead). A slot with no identity cannot be matched to its Close and cannot name a parent
  --- for a bracket opened inside it, so the containment performance-§3 requires was unknowable from
  --- the pair. With the key here, a bracket opened inside another records its parent OBSERVED.
  ---
  --- Deliberately NOT a closure-returning Bracket(key): a closure per bracket would allocate on a
  --- path whose entire contract is costing nothing when the probe is off, and `P.on` is read
  --- directly by every call site precisely so it stays a plain boolean raw field. P.Note is
  --- unchanged, so a host already calling it directly keeps working untouched.
  ---
  --- THE ACTIVE ARM COSTS, and the figure is stated here for the same reason the off-path figure
  --- is: the docstring above told the truth about the arm nobody pays for and said nothing at all
  --- about the arm a capture actually runs. With `P.on` true the pair is two calls, one table
  --- index into the free list, two field writes, a linear scan back through the open slots to find
  --- the match, and a P.Note. It ALLOCATES NOTHING in the steady state — slots are reused from a
  --- high-water free list (see its declaration above) and P.Note allocates one bucket per KEY, not
  --- per call. Measured over 10,000 active pairs at depth one: 0.0 KB, against 1406.2 KB for the
  --- per-Open table this replaced (`tests/test_perf_isolation.lua`, both arms). The scan is O(open
  --- depth), which is two in every descriptor this collection ships; a host nesting brackets
  --- dozens deep on a per-frame path is outside what Shape B is for and should use Shape A.
  function P.Open(key)
    if not P.on then return end
    if key == nil then
      error(lib.MAJOR .. ": Perf.Open requires a bucket key (got nil)", 2)
    end
    openDepth = openDepth + 1
    local slot = slots[openDepth]
    if not slot then
      slot = {}
      slots[openDepth] = slot
    end
    slot.key = key
    slot.t0  = debugprofilestop()
  end

  --- Close the bracket P.Open(key) opened, recording its elapsed ms under `key` and the key of the
  --- bracket enclosing it as the OBSERVED parent. A Close with the probe off, or with no matching
  --- open slot, is a silent no-op — that is what lets an early exit carry one unconditional
  --- statement instead of its own `if`.
  ---
  --- An exit that forgot its Close leaves a slot below this one. Those slots are DISCARDED here
  --- rather than closed at a stop time they never reached: crediting a leaked bracket with the
  --- elapsed time of whatever ran after it would put a fabricated number in the report, and a
  --- fabricated number is worse than a missing one.
  function P.Close(key)
    if not P.on then return end
    local ms = debugprofilestop()
    local at
    for i = openDepth, 1, -1 do
      if slots[i].key == key then at = i break end
    end
    if not at then return end
    local slot = slots[at]
    -- The parent is read BEFORE the depth drops, because dropping it is now the whole of the
    -- discard: a leaked slot is not niled, it is simply left above `openDepth` where nothing
    -- reads it and the next Open at that depth overwrites it in place.
    local parent = at > 1 and slots[at - 1].key or nil
    openDepth = at - 1
    P.Note(key, ms - slot.t0, parent)
  end

  -- ── Measurement windows + the FPS sampler ──────────────────────────────────────────────────
  --
  -- An experiment is a sequence of explicitly-armed, COMBAT-GATED windows:
  --
  --     perf.Start(label)     begin the experiment (samples nothing yet)
  --     perf.Measure("a")     arm window A - starts the moment combat does, ends when it does
  --     perf.Measure("b")     arm window B - same, with the host suspended
  --     perf.Stop()           report both windows and hand back the record
  --
  -- Why windows rather than sampling continuously and splitting by suspend state (the original
  -- design): continuous sampling silently folds every difference between the arms into the result.
  -- Two real captures were lost to exactly that - one where the active arm was ~78% combat against a
  -- suspended arm at ~100%, and one where the arms ran 72.3s and 59.2s. Both produced a delta that
  -- described the environment rather than the addon. A window that opens on PLAYER combat and closes
  -- when it ends measures a comparable slice by construction, and lets the user walk to the pull,
  -- reset a dungeon, or wait out a respawn between arms without contaminating anything.
  --
  -- Combat is read from UnitAffectingCombat("player") on the sampler's own OnUpdate rather than from
  -- the combat EVENTS, deliberately: P.Suspend() calls the host's suspend callback, which is free to
  -- unregister the host's event frames - so window B, the suspended arm, would never see
  -- PLAYER_REGEN_DISABLED fire if this polled events instead. Polling a cheap C call on a frame that
  -- only exists during an experiment sidesteps that entirely.
  --
  -- Window A maps to the `active` arm and window B to `suspended`, so the record schema and the delta
  -- computation are unchanged. `measure b` suspends the host and `measure a` resumes it, so the two
  -- windows differ by the host and nothing else - there is no way to forget the suspend.

  -- Window token -> FPS arm.
  P.EXPERIMENTS = { a = "active", b = "suspended" }

  -- Reverse map, so every message names the experiment the way the user typed it.
  P.LABELS = { active = "A", suspended = "B" }

  local sampler

  -- Created on first experiment and reused. The OnUpdate script is attached only while an
  -- experiment is running - an idle instance must not pay for a per-frame callback that exists
  -- purely to measure.
  local function ensureSampler()
    if sampler then return sampler end
    if type(CreateFrame) ~= "function" then return nil end
    -- Created under the CALLING HOST's ownership, never shared between instances. A shared sampler
    -- would bill its OnUpdate to whichever addon created it — the precise attribution failure this
    -- library exists to work around.
    sampler = CreateFrame("Frame", d.name .. "PerfSampler")
    sampler:Hide()
    return sampler
  end

  function P.__sampler() return sampler end

  -- Blizzard's stopwatch, driven so the user has an on-screen timer for the window actually being
  -- measured. Called as Lua functions rather than by running "/sw play" as a macro: RunMacroText is
  -- protected and would taint or fail outright in combat, whereas these FrameXML helpers are plain
  -- and safe to call mid-fight. Every one is existence-checked, so a client that has renamed or
  -- removed them degrades to no stopwatch rather than an error mid-capture.
  local function stopwatch(action)
    if action == "reset" then
      if type(Stopwatch_Clear) == "function" then Stopwatch_Clear() end
      if StopwatchFrame and StopwatchFrame.Show then StopwatchFrame:Show() end
    elseif action == "play" then
      if type(Stopwatch_Play) == "function" then Stopwatch_Play() end
    elseif action == "pause" then
      if type(Stopwatch_Pause) == "function" then Stopwatch_Pause() end
    end
  end

  local function inCombat()
    return UnitAffectingCombat and UnitAffectingCombat("player") and true or false
  end

  -- Both a chat line and a debug line, deliberately. These fire mid-combat, when the debug console is
  -- usually not what the user is looking at — the chat line is what tells them the recording actually
  -- started — while the console line is what survives into the copied log for later analysis.
  local function openWindow()
    P.recording = P.armed
    P.armed = false
    -- A bracket leaked by a host error in an earlier window must not parent this window's
    -- brackets, so the open depth starts clean at each window edge.
    openDepth = 0
    P.on = true              -- the brackets record only inside an experiment
    stopwatch("play")
    publishState()
    P.Announce("Experiment |cFFFFFF00%s|r |cff40ff40RECORDING|r \226\128\148 combat started",
        P.LABELS[P.recording] or P.recording)
  end

  local function closeWindow()
    local w = P.recording
    P.recording = false
    P.on = false
    openDepth = 0
    stopwatch("pause")
    if not w then return end
    done()[w] = true
    publishState()
    local a = arms()[w]
    P.Announce("Experiment |cFFFFFF00%s|r |cffff4040ENDED|r \226\128\148 %s, %s frames, %s fps",
        P.LABELS[w] or w, ("%.1fs"):format(a.seconds), a.frames,
        ("%.1f"):format(a.seconds > 0 and (a.frames / a.seconds) or 0))
  end

  local function onUpdate(_, elapsed)
    if not P.run then return end
    local combat = inCombat()

    -- Open first, then fall THROUGH to accumulate: the frame that opens a window is itself an
    -- in-combat frame and belongs in the sample. Returning after openWindow() silently dropped it,
    -- which is invisible over a 60s pull but wrong, and wrong in a way that biases both arms.
    if not P.recording then
      if not (P.armed and combat) then return end
      openWindow()
    end

    if combat then
      local a = arms()[P.recording]
      a.seconds = a.seconds + elapsed
      a.frames  = a.frames + 1
    else
      closeWindow()
    end
  end

  --- Begin an experiment. Samples nothing until a window is armed with Measure().
  function P.Start(label)
    P.Reset()
    P.label = label or false
    P.run = true
    P.armed, P.recording = false, false
    P.on = false
    -- Lifecycle lines are never gated behind a host debug flag, unlike a host's own debug logging
    -- (that gate exists to keep the host quiet while idle). A perf run is explicit user action, so
    -- a user who started a run should not have to have debug logging enabled first to see it working.
    P.context = P.Context()
    P.Log("run started \226\128\148 %s", P.label or "unlabeled")
    for _, line in ipairs(P.ContextLines(P.context)) do P.Log(line) end
    local s = ensureSampler()
    if s then
      s:SetScript("OnUpdate", onUpdate)
      s:Show()
    end
    publishState()
  end

  --- Arm a measurement window. Returns the arm name, or nil plus the offending token.
  ---
  --- Re-arming a window that already has data ZEROES it first, so a botched pull can simply be redone
  --- with the same command instead of silently averaging into the previous attempt.
  function P.Measure(token)
    if not P.run then return nil, "no experiment" end
    local arm = P.EXPERIMENTS[tostring(token or ""):lower()]
    if not arm then return nil, "unknown window" end

    if P.recording then closeWindow() end

    -- The suspend state IS the independent variable, so it is set here rather than left to the
    -- user: window B with the host still running would look like a null result.
    if arm == "suspended" then P.Suspend() else P.Resume() end

    local a = arms()[arm]
    a.seconds, a.frames = 0, 0
    done()[arm] = false          -- re-arming redoes the step, so it is no longer done
    P.armed = arm
    stopwatch("reset")
    P.Log("experiment %s armed (addon %s) \226\128\148 waiting for combat",
        P.LABELS[arm] or arm, arm == "suspended" and "SUSPENDED" or "active")
    publishState()
    return arm
  end

  --- End the experiment and hand back the assembled record. Detaches the sampler so the OnUpdate cost
  --- goes away entirely rather than idling.
  ---
  --- DOES NOT RESUME. If Experiment B ran, the host is still inert when this returns, and a Stop()
  --- with no Resume() after it leaves the addon dead until a /reload. That is deliberate rather than
  --- an oversight: SUBS.finish resumes BEFORE it saves, so an error in Save or FormatReport cannot
  --- strand the host — and it can only order it that way if Stop() leaves the suspend state alone.
  --- A host driving this API directly instead of through OnCommand owns the matching Resume().
  function P.Stop()
    if P.recording then closeWindow() end
    local fpsArms = arms()
    P.run = false
    P.armed = false
    P.on = false
    stopwatch("pause")
    P.Log("run finished \226\128\148 A %s / %s frames, B %s / %s frames",
        ("%.1fs"):format(fpsArms.active.seconds), fpsArms.active.frames,
        ("%.1fs"):format(fpsArms.suspended.seconds), fpsArms.suspended.frames)
    if sampler then
      sampler:SetScript("OnUpdate", nil)
      sampler:Hide()
    end
    publishState()
    return P.BuildRecord(P.label)
  end

  --- Abandon a run. Everything measured is discarded — nothing is saved to the ring — the host is
  --- restored, and the counters are zeroed so the next Start() begins clean.
  ---
  --- Deliberately does NOT go through closeWindow(): that marks the experiment completed and announces
  --- it ENDED, which would be a lie about a run being thrown away.
  function P.Cancel()
    if not (P.run or P.armed or P.recording) then return false end

    P.run, P.armed, P.recording = false, false, false
    P.on = false
    stopwatch("pause")
    if sampler then
      sampler:SetScript("OnUpdate", nil)
      sampler:Hide()
    end
    -- Restore before zeroing: Resume() lets the host republish its own state, and that needs to
    -- happen whatever else follows.
    if P.suspended then P.Resume() end
    P.Reset()
    P.label = false
    -- The context stamp goes with the run it described. Left standing, a `perf report` after a
    -- cancel prints empty buckets wearing the discarded run's character, realm and zone — a record
    -- that looks like a capture of somewhere nobody measured.
    P.context = nil
    P.Log("run CANCELED \226\128\148 measurements discarded, nothing saved")
    publishState()
    return true
  end

  -- ── Suspend / resume ─────────────────────────────────────────────────────────────────────
  --
  -- TWO HOLDS ON ONE LATCH, and this arm owns exactly one of them. The host owns what "inert"
  -- means — its `standDown` is what these two reach, through the latch — and this module owns only
  -- when the `perf` hold is taken and when it is given back. It keeps NO suspended boolean: the
  -- latch's answer is the answer, because the session where the player disables the addon halfway
  -- through a capture is the session where a second boolean and the latch disagree, and whichever
  -- was written last decides whether the addon comes back.
  --
  -- Two rules the host contract depends on, both learned the hard way and both documented in the
  -- README:
  --
  --   * Suspend MUST make the addon inert WITHOUT a reload. Reloading or disabling an addon shifts
  --     shared-frame ownership, which is the confound that makes the built-in Addon Profiler
  --     useless for this question.
  --   * Visibility MUST be enforced at the source — a `perf.suspended` check inside the host's own
  --     show-decision — rather than by imperatively hiding frames here. Otherwise a combat
  --     transition, a target swap or a settings change re-shows a bar behind suspend's back.

  function P.Suspend()
    if lc:IsHeld(HOLD) then return false end
    P.Log("addon SUSPENDED \226\128\148 inert")
    -- Taking the hold is what runs the host's teardown, and only if this is the FIRST hold. An
    -- addon the player has already disabled is already inert, so Experiment B measures exactly what
    -- it means to measure and nothing is torn down twice.
    lc:Hold(HOLD)
    return true
  end

  --- Release the perf hold. NOT a stand-up: whether the addon actually comes back is the latch's
  --- decision, not this module's, and it says no while `disabled` is still taken. The log line
  --- follows the answer rather than announcing a restore that did not happen — a player reading
  --- "events and frames restored" over an addon that is still off has been told the opposite of
  --- what occurred, and will go looking for the bug in the wrong addon.
  function P.Resume()
    if not lc:IsHeld(HOLD) then return false end
    if lc:Release(HOLD) then
      P.Log("addon RESUMED \226\128\148 events and frames restored")
    else
      P.Log("perf hold RELEASED \226\128\148 the addon stays down, another hold is still taken")
    end
    return true
  end

  return function() openDepth = 0 end
end
