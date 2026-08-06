-- LibKa0s-Perf-1.0 — a repeatable A/B performance capture for World of Warcraft addons.
--
-- The value here is not the bucket counter. It is the PROTOCOL: two combat-gated measurement
-- windows over the same fight, differing only in whether the host addon is inert, with load order
-- and shared-frame ownership held fixed. WoW's own Addon Profiler cannot answer "is this cost even
-- ours?", because it bills a shared library's dispatch frame to whichever addon created it — so
-- enabling and disabling addons moves the blame around. Suspending changes only whether the host's
-- code runs.
--
-- Every instance owns its own frames. A lib-level shared frame would reproduce that exact
-- attribution pathology: the measuring instrument corrupting the attribution it exists to fix.
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on NO ADDON FRAMEWORK — that second half is the part
-- worth protecting. Core embeds nothing either, so an addon that is not on the Ace substrate can
-- still adopt this probe; what the Core dependency costs is one vendored sibling file, and
-- re-vendoring is whole-folder, so it is never separately missing in practice.

-- Refuse rather than degrade when Core is missing or too old. Failing here means the host's own
-- setup stub reports "perf is not installed" honestly, instead of the probe registering and then
-- nil-erroring mid-run in whichever addon the user happened to be using.
local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Perf-1.0", 7
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

-- Which version of each FILE in this major is actually live, so version skew is discoverable at
-- runtime rather than by reading source. LibStub resolves one winner per major, but a major spanning
-- several files can end up with files from different vendored copies — and with six addons each
-- carrying their own copy, "which panel is attached to which probe?" is a question someone will need
-- answered from in-game. Not reset on upgrade: a newer file writes its own key over the old value.
-- Every file in this major MUST register here, and its number MUST rise on every released change to
-- that file. See docs/releasing.md.
lib.MODULES = lib.MODULES or {}
lib.MODULES.Perf = MINOR

-- Record schema emitted by BuildRecord. See docs/record-schema.md.
lib.SCHEMA = 2

-- Default depth of the SavedVariables capture ring. Small on purpose: these are diagnostic
-- snapshots read by hand, not telemetry.
lib.DEFAULT_RING = 10

-- ── JSON encoding ──────────────────────────────────────────────────────────────────────────
--
-- Hand-rolled because Lua has none built in and the addon vendors no JSON library for one
-- diagnostic path. The data is flat, finite and entirely ours, so the general-purpose hazards
-- (cycles, sparse arrays, NaN) cannot arise from BuildRecord's output.
--
-- Object keys are emitted SORTED. Lua's pairs() order is unspecified and varies between runs, so
-- unsorted output would make two otherwise-identical captures diff as different files.

local function encodeNumber(v)
    if v ~= v or v == math.huge or v == -math.huge then return "0" end   -- NaN / inf → 0
    if v == math.floor(v) and math.abs(v) < 1e15 then
        return ("%d"):format(v)
    end
    return ("%.4f"):format(v)
end

local ESCAPES = {
    ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
    ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function encodeString(v)
    local out = v:gsub('[%c"\\]', function(c)
        return ESCAPES[c] or ("\\u%04x"):format(c:byte())
    end)
    return '"' .. out .. '"'
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    return keys
end

--- Encode a Lua value as JSON. Tables with a non-empty array part encode as arrays; every other
--- table encodes as an object with sorted keys. Unsupported types encode as null.
function lib.EncodeJSON(value)
    local t = type(value)
    if value == nil then return "null" end
    if t == "boolean" then return value and "true" or "false" end
    if t == "number" then return encodeNumber(value) end
    if t == "string" then return encodeString(value) end
    if t ~= "table" then return "null" end

    if #value > 0 then
        local parts = {}
        for i = 1, #value do parts[i] = lib.EncodeJSON(value[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end

    local parts = {}
    for _, k in ipairs(sortedKeys(value)) do
        parts[#parts + 1] = encodeString(k) .. ":" .. lib.EncodeJSON(value[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- ── Strings ────────────────────────────────────────────────────────────────────────────────
--
-- Every user-visible string routes through here so a host can override any of them via the
-- optional `L` table, keyed identically. Hosts on the Ka0s standard pass their NS.L; hosts that
-- are not localised pass nothing and get these.

lib.STRINGS = {
  PANEL_TITLE_SUFFIX = " \226\128\148 Perf Run",
  STEP_START    = "Start perf run",
  STEP_MEASURE_A = "Measure A (with the addon)",
  STEP_MEASURE_B = "Measure B (without the addon)",
  STEP_FINISH   = "Finish perf run",
  STEP_REPORT   = "Report",
  STEP_DUMP     = "JSON Dump",
  STEP_CANCEL   = "Cancel perf run",
}

-- ── Output ─────────────────────────────────────────────────────────────────────────────────
--
-- Perf output is deliberately NOT gated on a host debug flag, unlike a host's own debug logging.
-- That gate exists to keep the addon quiet while idle, and a perf run is explicit user action —
-- none of this executes unless someone typed the host's perf command.
--
-- The console form is stripped of color escapes: the Copy window mirrors the buffer verbatim, and
-- color codes in a log destined for analysis are noise. Stateless, so these live above :New()
-- alongside the JSON encoder.

local function stripColors(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Arguments are rendered through Core rather than a private stringifier. The one this file used to
-- carry branched on type(), and a combat-protected "secret" value IS a string or a number — so it
-- returned the secret untouched and the line raised much later, inside the host's
-- table.concat(buffer, "\n") when someone pressed Copy. One implementation, one place to be wrong.
local function render(fmt, ...)
    if select("#", ...) == 0 then return fmt end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = core.SafeToString((select(i, ...))) end
    return fmt:format(unpack(parts))
end

-- ── Record assembly ────────────────────────────────────────────────────────────────────────

-- Derive the reportable figures for one FPS arm. An arm that never ran (e.g. `suspended` in a
-- capture where the user never suspended) yields zeros rather than nil, so the record shape is
-- fixed and consumers never branch on presence.
local function deriveArm(a)
    local seconds, frames = a.seconds, a.frames
    return {
        seconds    = seconds,
        frames     = frames,
        avgFps     = seconds > 0 and (frames / seconds) or 0,
        msPerFrame = frames > 0 and (seconds * 1000 / frames) or 0,
    }
end

-- The interface version this capture was taken on, as a number.
--
-- GetBuildInfo's FOURTH return, NOT GetAddOnMetadata(name, "Interface"). Blizzard does not serve
-- `Interface` through the addon-metadata API — it serves Title, Notes, Author, Version and X-* —
-- so the old read answered nil and every record stamped `"interface":0`. It shipped that way and
-- was caught only by reading a live capture: this repo's own case pinned the field at 120007 and
-- passed throughout, because the mock returned "120007" for any field asked of it.
--
-- The semantics shift slightly and for the better: this is the CLIENT's interface version rather
-- than the host's TOC line. For a current addon they agree, and when they disagree the client's is
-- the one that explains the capture. A client without GetBuildInfo degrades to 0 rather than
-- erroring mid-run.
local function interfaceVersion()
  if type(GetBuildInfo) ~= "function" then return 0 end
  local _, _, _, toc = GetBuildInfo()
  return tonumber(toc) or 0
end

-- ── Report sections ────────────────────────────────────────────────────────────────────────
--
-- One function per section of P.FormatReport, each handed that function's own `add` closure so the
-- line ORDER and every format string stay exactly where they were. `add`, `record`, `P` and the
-- active seconds are passed rather than closed over, so these are three functions built at file
-- load rather than three per host.

local FPS_ARMS = { "active", "suspended" }

-- The FPS arms, then the delta between them: the headline the whole harness exists to produce. An
-- arm that never ran reads "(not sampled)", never zeros — zeros would look like a measured result.
local function addFpsLines(add, f)
  for _, name in ipairs(FPS_ARMS) do
    local a = f[name]
    if a.frames > 0 then
      add("%-10s %7.1fs  %6d frames  %6.1f fps  %6.2f ms/frame",
          name .. ":", a.seconds, a.frames, a.avgFps, a.msPerFrame)
    else
      add("%-10s (not sampled)", name .. ":")
    end
  end
  if f.active.frames > 0 and f.suspended.frames > 0 then
    add("%-10s %45s%+6.2f ms/frame", "delta:", "", f.deltaMsPerFrame)
  else
    add("delta:     (needs both arms \226\128\148 arm Experiment B mid-capture)")
  end
end

-- Buckets in declared order, indented by nesting depth. `secs` is the ACTIVE seconds only: no
-- bucket can accrue while suspended, so including that arm would understate every rate.
local function addBucketLines(add, P, record, secs)
  local function depthOf(key)
    local n, parent = 0, record.buckets[key] and record.buckets[key].within or P.BUCKET_WITHIN[key]
    while parent and n < 8 do                        -- the guard is against a malformed descriptor
      n, parent = n + 1, P.BUCKET_WITHIN[parent]
    end
    return n
  end

  add("")
  add("%-14s %8s %10s %10s %9s", "bucket", "calls", "total ms", "ms/s", "max ms")
  for _, key in ipairs(P.BUCKET_ORDER) do
    local b = record.buckets[key]
    if b then
      local name = ("  "):rep(depthOf(key)) .. key
      add("%-14s %8d %10.2f %10.3f %9.3f",
          name, b.calls, b.totalMs, secs > 0 and (b.totalMs / secs) or 0, b.maxMs)
    end
  end
end

-- Nested totals are not disjoint and must never be summed. Spelling out which contains which beats
-- trusting the reader to notice the indentation.
--
-- The sentence per bucket says what the CAPTURE knows, never what the descriptor merely claims
-- (performance-§3). A `within` in the descriptor is a claim about where the work runs, written once
-- and read months later beside numbers it is supposed to explain; until the call site passes its
-- parent, nothing has confirmed it. Three states, and the library must not collapse them:
--
--   observed              the call site passed this parent, so the containment is a fact
--   declared, unobserved  the descriptor claims it and no call site confirmed it
--   declared X, seen in Y the two disagree — a defect in the descriptor or in the call site
--
-- The old wording printed the first form for all three, which is how AbsorbTracker's descriptor
-- carried `appearance` and `visibility` inside a `repaintPass` neither ever ran in, through every
-- archived capture, with the report asserting the containment as fact each time.
local function nestingSentence(key, declared, observed, mixed)
  if mixed then
    return ("%s observed inside more than one parent (first: %s)"):format(key, tostring(observed))
  elseif observed and declared and observed ~= declared then
    return ("%s declares itself within %s but was observed inside %s"):format(key, declared, observed)
  elseif observed then
    return ("%s observed inside %s"):format(key, observed)
  end
  return ("%s declares itself within %s \226\128\148 not observed"):format(key, declared)
end

local function addNestingNote(add, P, record)
  local pairsOut = {}
  for _, key in ipairs(P.BUCKET_ORDER) do
    local b = record.buckets[key]
    -- The record's own `within` first, so a capture read back off the ring reports the nesting IT
    -- was built with rather than whatever the live descriptor declares now.
    local declared = b and (b.within or P.BUCKET_WITHIN[key]) or nil
    local observed = b and b.observedWithin or nil
    if b and (declared or observed) then
      pairsOut[#pairsOut + 1] = nestingSentence(key, declared, observed, b.observedMixed)
    end
  end
  if #pairsOut > 0 then
    add("(buckets nest: %s \226\128\148 do not sum)", table.concat(pairsOut, ", "))
  end
end

-- ── Instances ──────────────────────────────────────────────────────────────────────────────

-- One step's state, at the one precedence the panel encodes: busy > done > ready > locked.
-- Returns the STATE STRINGS and never the values it was handed, so a truthy `completed.active`
-- table can never leak into the result.
local function stepState(busy, done, ready)
  if busy then return "busy" end
  if done then return "done" end
  if ready then return "ready" end
  return "locked"
end

-- The three measurement arms, derived from the live run flags — which is where all of Progress's
-- precedence used to live, spelled out as three six-to-eight-term ternary chains. `P` is a perf
-- instance and `completed` its arm-completion pair; both are passed rather than closed over so
-- this stays one function built at file load instead of one per host.
--
-- `finished` comes back too: the review actions read it, and recomputing it there would be a second
-- copy of the same rule.
local function armStates(P, completed)
  local aBusy = (P.armed == "active") or (P.recording == "active")
  local bBusy = (P.armed == "suspended") or (P.recording == "suspended")
  local finished = (not P.run) and (completed.active or completed.suspended)

  local a   = stepState(aBusy, completed.active, P.run and not bBusy)
  local b   = stepState(bBusy, completed.suspended, P.run and completed.active and not aBusy)
  -- `finish` genuinely has no busy state — nothing arms it — so it is passed nil rather than
  -- given an invented one.
  local fin = stepState(nil, finished, P.run and completed.suspended and not bBusy)
  return a, b, fin, finished
end

local function required(d, key, wanted)
  if type(d[key]) ~= wanted then
    error(("LibKa0s-Perf: descriptor.%s must be a %s"):format(key, wanted), 3)
  end
end

--- Create a perf instance for one host addon. Every instance owns its own sampler frame, bucket
--- table, FPS arms and panel — see the header on why that is non-negotiable.
function lib:New(descriptor)
  local d = descriptor or {}
  required(d, "name", "string")
  required(d, "sv", "string")
  required(d, "suspend", "function")
  required(d, "resume", "function")

  local P = {}

  -- Optional host sinks, resolved once so the hot-ish paths do not re-branch on presence.
  local noop     = function() end
  local hostLog  = type(d.log)     == "function" and d.log     or function(line) print(line) end
  local hostPrint= type(d.print)   == "function" and d.print   or function(line) print(line) end
  local showLog  = type(d.showLog) == "function" and d.showLog or noop
  local onChange = type(d.onChange)== "function" and d.onChange or noop
  local L        = d.L or {}
  -- rawget, NOT a plain index. Every Ka0s host's locale table carries a metatable fallback that
  -- answers an unknown key WITH THE KEY (the standard mandates it — anti-patterns #2), so a plain
  -- index accepts that synthesized string for every key, these STRINGS become unreachable, and the
  -- panel renders STEP_START / PANEL_TITLE_SUFFIX verbatim. That is not hypothetical: it shipped in
  -- KickCD's perf panel. rawget asks the only question that matters — did the host actually put a
  -- value here? PerfPanel.lua takes `tr` as a parameter, so fixing it here fixes the panel too.
  local function tr(key)
    local v = rawget(L, key)
    if type(v) == "string" then return v end
    return lib.STRINGS[key] or key
  end

  -- Everything below reads `lib`, never `self`. A LibStub minor upgrade mutates the shared library
  -- table in place, so `lib` is the one source of truth inside this closure — every internal read
  -- (BuildRecord's schema stamp included) goes through it rather than through a per-instance copy.

  -- Mirrored onto the instance as a convenience snapshot: call sites that hold only `NS.Perf` should
  -- not have to reach back through LibStub for the schema number or the encoder. It is taken once,
  -- at :New() time — a minor upgrade after that point changes `lib.SCHEMA` but not this copy.
  P.SCHEMA     = lib.SCHEMA
  P.EncodeJSON = lib.EncodeJSON

  P.descriptor = d
  P.name    = d.name
  P.slash   = d.slash or ("/" .. d.name:lower())
  P.title   = d.title or d.name

  -- Clamped to at least one record. A ring of 0 would empty itself on the very Save that wrote the
  -- record, while `finish` still announced the capture as saved — the one failure mode where the
  -- user has no reason to look for the data until it is long gone.
  local ring = tonumber(d.ring) or lib.DEFAULT_RING
  P.ringMax = ring >= 1 and ring or 1

  -- Report order, and the declared nesting. Membership controls only PRESENTATION — Note() accepts
  -- any key, so a bracket nobody declared still records, it just does not print.
  --
  -- Validated per entry rather than trusted: an entry with no `key` used to raise a raw "table index
  -- is nil" from inside the loop, which tells a host nothing about which of its buckets is wrong.
  P.BUCKET_ORDER, P.BUCKET_WITHIN = {}, {}
  for i, b in ipairs(d.buckets or {}) do
    if type(b) ~= "table" or type(b.key) ~= "string" then
      error(("LibKa0s-Perf: descriptor.buckets[%d].key must be a string"):format(i), 2)
    end
    P.BUCKET_ORDER[#P.BUCKET_ORDER + 1] = b.key
    if b.within then P.BUCKET_WITHIN[b.key] = b.within end
  end

  -- Capture running? Read directly by every bracket call site, so it must stay a plain boolean
  -- field on a plain table — no metatable, no accessor.
  P.on        = false
  P.suspended = false
  P.run       = false     -- between Start() and Stop()
  P.armed     = nil       -- window armed, waiting for combat
  P.recording = nil       -- window currently recording

  local buckets   = {}
  local completed = { active = false, suspended = false }
  local reviewed  = { report = false, dump = false }
  local fpsArms   = {
    active    = { seconds = 0, frames = 0 },
    suspended = { seconds = 0, frames = 0 },
  }

  --- Record one bracketed measurement of `ms` into bucket `key`.
  ---
  --- `parentKey` is OPTIONAL and is the bucket this work actually ran inside — the containment the
  --- capture OBSERVED, as against the `within` the descriptor merely declares (performance-§3).
  --- Omit it and the record carries the declared parent flagged as unobserved; pass it and the
  --- record can confirm the declaration, or contradict it. Every call site written against the old
  --- two-argument form keeps working unchanged, which is why the parent is taken here rather than
  --- inferred from a bracket stack no deployed call site opens.
  function P.Note(key, ms, parentKey)
    -- A nil key used to reach `buckets[key] = b` and raise a bare "table index is nil" from inside
    -- this file, which names neither the host, the library nor the offending bracket. Framed like
    -- every other descriptor error instead, and blamed on the CALLER (level 2) — the typo is at the
    -- bracket, not here.
    if key == nil then
      error(MAJOR .. ": Perf.Note requires a bucket key (got nil)", 2)
    end
    local b = buckets[key]
    if not b then
      b = { calls = 0, totalMs = 0, maxMs = 0 }
      buckets[key] = b
    end
    b.calls   = b.calls + 1
    b.totalMs = b.totalMs + ms
    if ms > b.maxMs then b.maxMs = ms end
    if parentKey ~= nil then
      -- First observation wins and every later one is compared against it. Overwriting would report
      -- whichever call site happened to run last as though it were the only one, which is the same
      -- class of silent false claim this whole change exists to end.
      if b.observedWithin == nil then
        b.observedWithin = parentKey
      elseif b.observedWithin ~= parentKey then
        b.observedMixed = true
      end
    end
  end

  -- Shape B's open slots, innermost last (performance-§2). Touched only while `P.on` is true, so a
  -- dormant probe neither allocates into it nor reads it.
  local openStack = {}

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
  --- directly by every call site precisely so it stays a plain boolean on a plain table. P.Note is
  --- unchanged, so a host already calling it directly keeps working untouched.
  function P.Open(key)
    if not P.on then return end
    if key == nil then
      error(MAJOR .. ": Perf.Open requires a bucket key (got nil)", 2)
    end
    openStack[#openStack + 1] = { key = key, t0 = debugprofilestop() }
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
    for i = #openStack, 1, -1 do
      if openStack[i].key == key then at = i break end
    end
    if not at then return end
    local slot = openStack[at]
    for i = #openStack, at, -1 do openStack[i] = nil end
    P.Note(key, ms - slot.t0, at > 1 and openStack[at - 1].key or nil)
  end

  function P.Reset()
    buckets   = {}
    -- Emptied in place rather than rebound: P.Open and P.Close close over this table, and a fresh
    -- one here would leave them pushing into the old copy for the rest of the session.
    for i = #openStack, 1, -1 do openStack[i] = nil end
    completed = { active = false, suspended = false }
    reviewed  = { report = false, dump = false }
    fpsArms   = {
      active    = { seconds = 0, frames = 0 },
      suspended = { seconds = 0, frames = 0 },
    }
  end

  -- Test seams: expose the live tables without letting callers swap them out.
  function P.__buckets()   return buckets   end
  function P.__fpsArms()   return fpsArms   end
  function P.__completed() return completed end
  function P.__reviewed()  return reviewed  end

  --- Console only. Phase transitions and anything else worth having in the copied log.
  function P.Log(fmt, ...)
    hostLog(stripColors(render(fmt, ...)))
  end

  --- Chat AND console. For what the user must see while looking at the game rather than at the
  --- console — recording starting and ending mid-combat, above all.
  function P.Announce(fmt, ...)
    local msg = render(fmt, ...)
    hostPrint(msg)
    hostLog(stripColors(msg))
  end

  -- Something moved: repaint the panel, then let the host republish on its own bus if it cares.
  -- The panel refreshes DIRECTLY rather than via a message — it owns the state it renders, so the
  -- bus hop the addon-local version used was never load-bearing.
  local function publishState()
    if P.RefreshPanel then P.RefreshPanel() end
    onChange()
  end

  --- Note that a review action has been run, so the panel can mark it without disabling it. Called
  --- by the slash handlers, so a typed command and a click mark it identically.
  function P.MarkReviewed(key)
    if reviewed[key] == nil or reviewed[key] then return false end
    reviewed[key] = true
    publishState()
    return true
  end

  --- The run as a list of step states, for the panel to render. Lives here rather than in the panel
  --- so the progression is testable without frames, and so the panel stays a dumb renderer.
  ---
  --- Strictly linear: exactly one step is `ready` at a time. `locked` steps are not yet reachable,
  --- `busy` is armed-or-recording, `done` is finished. The slash verbs are NOT gated this way — a
  --- run that cannot complete Experiment B can still be closed with the host's finish command.
  function P.Progress()
    local a, b, fin, finished = armStates(P, completed)

    -- `used` is green like `done` but stays clickable: these are read-only actions worth repeating.
    -- Checked before `finished`: `finish` can close a run with neither arm ever armed (an aborted
    -- attempt closed out rather than left dangling), and `report`/`dump` are reachable as typed
    -- commands regardless — a mark earned that way must stick rather than read as still-locked.
    local function review(key)
        if reviewed[key] then return "used" end
        if not finished then return "locked" end
        return "ready"
    end

    return {
        -- Clickable whenever there is no run in flight, so the panel is the entry point rather than
        -- something you can only reach once you already knew the command. `done` while a run is
        -- active; ready again afterwards, since starting another is the obvious next thing.
        start = P.run and "done" or "ready",
        measureA = a, measureB = b, finish = fin,
        report = review("report"), dump = review("dump"),
        -- Its own state, not "ready": it sits outside the linear progression and the panel colors
        -- it separately, so it never reads as the next step to take. Only offered while there is
        -- actually a run to abandon — after `finish` the run is saved and there is nothing left to
        -- cancel, and a live-looking button that discards nothing is just a way to worry someone.
        cancel = (P.run or P.armed or P.recording) and "cancel" or "locked",
    }
  end

  -- Who / where / what, captured once at the start of a run. A saved capture is read weeks later,
  -- and "119 fps" means nothing without knowing it was a Blood DK soloing a dummy rather than a
  -- healer in a 20-man. Every lookup is existence-checked so the headless harness (and any client
  -- that renames one of these) degrades to "?" rather than erroring at the start of a capture.
  local function groupContext()
      local inInstance, instanceType
      if IsInInstance then inInstance, instanceType = IsInInstance() end
      local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
      local base = "solo"
      if IsInRaid and IsInRaid() then
          base = ("raid (%d)"):format(n)
      elseif IsInGroup and IsInGroup() then
          base = ("party (%d)"):format(n)
      end
      if inInstance and instanceType and instanceType ~= "none" then
          return base .. " / " .. instanceType
      end
      return base
  end

  function P.Context()
      local ctx = {
          character = "?", realm = "?", class = "?", spec = "?",
          level = 0, zone = "?", subZone = "", group = "solo",
      }
      if UnitName then ctx.character = UnitName("player") or "?" end
      if GetRealmName then ctx.realm = GetRealmName() or "?" end
      if UnitClass then ctx.class = (UnitClass("player")) or "?" end
      if UnitLevel then ctx.level = UnitLevel("player") or 0 end
      if GetSpecialization and GetSpecializationInfo then
          local index = GetSpecialization()
          if index then
              local _, name = GetSpecializationInfo(index)
              ctx.spec = name or "?"
          end
      end
      if GetZoneText then ctx.zone = GetZoneText() or "?" end
      if GetSubZoneText then ctx.subZone = GetSubZoneText() or "" end
      ctx.group = groupContext()
      return ctx
  end

  --- The context as display lines, shared by the chat ack and the report so they cannot drift.
  function P.ContextLines(ctx)
      if not ctx then return {} end
      local where = ctx.zone or "?"
      if ctx.subZone and ctx.subZone ~= "" then where = where .. " \226\128\148 " .. ctx.subZone end
      return {
          ("who:       %s-%s, level %s %s %s"):format(ctx.character, ctx.realm,
              tostring(ctx.level), ctx.spec, ctx.class),
          ("where:     %s"):format(where),
          ("group:     %s"):format(ctx.group),
      }
  end

  --- Assemble the capture into the shared record schema (docs/record-schema.md).
  function P.BuildRecord(label)
    local active, suspended = deriveArm(fpsArms.active), deriveArm(fpsArms.suspended)

    -- Positive delta = the addon costs this much per frame. Only meaningful when BOTH arms ran;
    -- with one arm empty its msPerFrame is 0 and the delta would read as the whole frame time, so
    -- report zero instead of a number that invites a wrong conclusion.
    local delta = 0
    if active.frames > 0 and suspended.frames > 0 then
        delta = active.msPerFrame - suspended.msPerFrame
    end

    -- `within` is what the descriptor DECLARED; `observedWithin` is what the capture actually saw,
    -- and it is absent exactly when no call site passed a parent. Both travel, so a record read
    -- back months later answers "was that nesting ever confirmed?" without the addon's source in
    -- hand. Additive within schema 2 — a reader of an older record sees the same fields it always
    -- did, and a bucket nobody supplied a parent for is missing the key the same way an undeclared
    -- bucket is missing `within` (docs/record-schema.md).
    local out = {}
    for key, b in pairs(buckets) do
      out[key] = {
        calls          = b.calls,
        totalMs        = b.totalMs,
        maxMs          = b.maxMs,
        within         = P.BUCKET_WITHIN[key],
        observedWithin = b.observedWithin,
        observedMixed  = b.observedMixed,
      }
    end

    return {
      schema    = lib.SCHEMA,
      addon     = d.name,
      source    = "ingame",
      version   = d.version or "?",
      interface = interfaceVersion(),
      timestamp = time and time() or 0,
      label     = label or "",
      buckets   = out,
      fps       = { active = active, suspended = suspended, deltaMsPerFrame = delta },
      context   = P.context,
    }
  end

  --- Append a record to the host's SavedVariables ring, trimming the oldest past ringMax.
  ---
  --- Writes _G[sv] directly rather than going through the host's settings DB. A perf ring inside an
  --- AceDB profile tree would be copied by "copy profile", wiped by "reset profile", and would swap
  --- out from under a capture on a profile switch — none of which is wanted for diagnostics.
  ---
  --- A ring stored under a different schema is DISCARDED rather than migrated: these are diagnostic
  --- snapshots, not user data, and a half-converted record is worse than an absent one.
  function P.Save(record)
    local db = _G[d.sv]
    if type(db) ~= "table" then
      db = {}
      _G[d.sv] = db
    end
    if db.schema ~= lib.SCHEMA then
      local dropped = db.runs and #db.runs or 0
      if dropped > 0 then
        P.Log("perf ring was schema %s, now %s \226\128\148 discarded %s old record(s)",
          tostring(db.schema), tostring(lib.SCHEMA), tostring(dropped))
      end
      db.runs = nil
    end
    db.schema = lib.SCHEMA
    db.runs = db.runs or {}
    db.runs[#db.runs + 1] = record
    while #db.runs > P.ringMax do table.remove(db.runs, 1) end
    return db
  end

  --- Render a record as a list of plain strings. Returns a table (not a printed side effect) so the
  --- headless suite can assert on the exact lines without frames or a chat sink.
  function P.FormatReport(record)
    local lines = {}
    local function add(fmt, ...)
      lines[#lines + 1] = select("#", ...) > 0 and fmt:format(...) or fmt
    end

    local f = record.fps
    add("capture: %s  (%s, schema %d, v%s)", record.label ~= "" and record.label or "unlabelled",
        record.addon, record.schema, record.version)
    for _, line in ipairs(P.ContextLines(record.context)) do add(line) end

    addFpsLines(add, f)
    addBucketLines(add, P, record, f.active.seconds)
    addNestingNote(add, P, record)

    return lines
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
    P.armed = nil
    P.on = true              -- the brackets record only inside an experiment
    stopwatch("play")
    publishState()
    P.Announce("Experiment |cFFFFFF00%s|r |cff40ff40RECORDING|r \226\128\148 combat started",
        P.LABELS[P.recording] or P.recording)
  end

  local function closeWindow()
    local w = P.recording
    P.recording = nil
    P.on = false
    stopwatch("pause")
    if not w then return end
    completed[w] = true
    publishState()
    local a = fpsArms[w]
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
      local a = fpsArms[P.recording]
      a.seconds = a.seconds + elapsed
      a.frames  = a.frames + 1
    else
      closeWindow()
    end
  end

  --- Begin an experiment. Samples nothing until a window is armed with Measure().
  function P.Start(label)
    P.Reset()
    P.label = label
    P.run = true
    P.armed, P.recording = nil, nil
    P.on = false
    -- Lifecycle lines are never gated behind a host debug flag, unlike a host's own debug logging
    -- (that gate exists to keep the host quiet while idle). A perf run is explicit user action, so
    -- a user who started a run should not have to have debug logging enabled first to see it working.
    P.context = P.Context()
    P.Log("run started \226\128\148 %s", P.label or "unlabelled")
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

    fpsArms[arm].seconds, fpsArms[arm].frames = 0, 0
    completed[arm] = false          -- re-arming redoes the step, so it is no longer done
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
    P.run = false
    P.armed = nil
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

    P.run, P.armed, P.recording = false, nil, nil
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
    P.label = nil
    -- The context stamp goes with the run it described. Left standing, a `perf report` after a
    -- cancel prints empty buckets wearing the discarded run's character, realm and zone — a record
    -- that looks like a capture of somewhere nobody measured.
    P.context = nil
    P.Log("run CANCELLED \226\128\148 measurements discarded, nothing saved")
    publishState()
    return true
  end

  -- ── Suspend / resume ─────────────────────────────────────────────────────────────────────
  --
  -- The host owns what "inert" means; the lib owns only the state and the announcement. Two rules
  -- the host contract depends on, both learned the hard way and both documented in the README:
  --
  --   * Suspend MUST make the addon inert WITHOUT a reload. Reloading or disabling an addon shifts
  --     shared-frame ownership, which is the confound that makes the built-in Addon Profiler
  --     useless for this question.
  --   * Visibility MUST be enforced at the source — a `perf.suspended` check inside the host's own
  --     show-decision — rather than by imperatively hiding frames here. Otherwise a combat
  --     transition, a target swap or a settings change re-shows a bar behind suspend's back.

  function P.Suspend()
    if P.suspended then return false end
    P.suspended = true
    P.Log("addon SUSPENDED \226\128\148 inert")
    d.suspend()
    return true
  end

  function P.Resume()
    if not P.suspended then return false end
    P.suspended = false
    P.Log("addon RESUMED \226\128\148 events and frames restored")
    d.resume()
    return true
  end

  -- ── Command surface ──────────────────────────────────────────────────────────────────────
  --
  -- The lib MUST NOT register a slash command of its own — the Ka0s standard mandates schema-driven
  -- dispatch through each addon's own COMMANDS table, and third-party hosts do not use that pattern
  -- at all. What the lib supplies is behavior and help text; the host owns its slash surface and
  -- decides how `perf` is reached. OnCommand returns lines rather than printing them, which is also
  -- what lets a panel click and a typed command run the identical code path.

  --- Help text for the host to print. Returned rather than printed, so a host can fold it into its
  --- own help output however it likes.
  function P.Usage()
    local s = P.slash
    return {
      ("usage: |cFFFFFF00%s perf <start|measure|finish|cancel|report|dump|show|hide|toggle>|r"):format(s)
        .. " \226\128\148 or just click the panel",
      "  |cFFFFFF00start [label]|r  begin a run; zeroes the counters and records who/where you are.",
      "                 The label is appended to the timestamp so runs are tellable apart.",
      "  |cFFFFFF00measure a|r      arm Experiment A \226\128\148 addon ACTIVE. Recording starts the moment",
      "                 combat does and ends when combat ends. Nothing between is measured.",
      "  |cFFFFFF00measure b|r      arm Experiment B \226\128\148 same, but suspends the addon first, so the",
      "                 two experiments differ by the addon and nothing else.",
      ("  |cFFFFFF00finish|r         end the run, save it to %s and lift any suspend."):format(d.sv),
      "                 Prints nothing \226\128\148 use `report` when you want to read it. `/reload` to flush.",
      "  |cFFFFFF00cancel|r         abandon the run \226\128\148 discards it unsaved and restores the addon.",
      "                 Only available while a run is actually in flight.",
      "  |cFFFFFF00report|r         print the summary; opens the log window if it is hidden.",
      "  |cFFFFFF00dump|r           render the run as one line of JSON in the log, for pasting",
      "                 somewhere. Same data the summary is built from.",
      "  |cFFFFFF00show|r / |cFFFFFF00hide|r / |cFFFFFF00toggle|r   the step panel. Hiding it never touches the run.",
    }
  end

  -- Sub-verb handlers, one entry each. A dispatch table rather than an if/elseif ladder: the ladder
  -- form measured CCN 24 under `lizard`, the worst in the addon this was extracted from, purely
  -- from the shape of the dispatch. Each handler here is CCN 1-3 and reads on its own.
  --
  -- Handlers take (out, rest) and append chat lines to `out`. Returning lines rather than printing
  -- them is what lets the host own its output — and is why the lib needs no chat frame of its own.
  local SUBS = {}

  -- `rest` is the free text after the sub-verb: an optional capture label. Captures accumulate in a
  -- ring across sessions, so an auto-timestamp alone makes two runs from the same afternoon
  -- near-impossible to tell apart when reading the SavedVariables file later. A supplied label is
  -- appended to the timestamp, never replaces it.
  function SUBS.start(out, rest)
    local stamp = date and date("%Y-%m-%d %H:%M") or "capture"
    local label = (rest or ""):match("^%s*(.-)%s*$")
    P.Start(label ~= "" and (stamp .. " " .. label) or stamp)
    P.Announce("perf run |cff40ff40STARTED|r \226\128\148 %s", P.label or "unlabelled")
    for _, line in ipairs(P.ContextLines(P.context)) do out[#out + 1] = line end
    showLog()
    -- The clickable equivalent of the steps just printed. Chat scrolls away the moment combat
    -- starts; the panel does not.
    P.ShowPanel()
  end

  function SUBS.measure(out, rest)
    local token = (rest or ""):match("^(%S*)")
    local armName, err = P.Measure(token)
    if not armName then
      if err == "no experiment" then
        out[#out + 1] = ("start one first \226\128\148 `%s perf start`"):format(P.slash)
      else
        out[#out + 1] = ("unknown window '%s' \226\128\148 use `measure a` or `measure b`")
          :format(token ~= "" and token or "?")
      end
      return
    end
    out[#out + 1] = ("Experiment |cFFFFFF00%s|r |cffffff00ARMED|r (%s) \226\128\148 recording starts "
      .. "when combat does, and ends when combat does"):format(token:upper(),
      armName == "suspended" and "addon |cffff4040SUSPENDED|r" or "addon |cff40ff40active|r")
  end

  function SUBS.show()   P.ShowPanel()   end
  function SUBS.hide()   P.HidePanel()   end
  function SUBS.toggle() P.TogglePanel() end

  function SUBS.cancel(out)
    if not P.Cancel() then
      out[#out + 1] = "no perf run to cancel"
      return
    end
    out[#out + 1] = "perf run |cffcc5252CANCELLED|r \226\128\148 nothing saved"
  end

  function SUBS.finish(out)
    if not P.run then
      out[#out + 1] = ("no perf run is active \226\128\148 `%s perf start`"):format(P.slash)
      return
    end
    local record = P.Stop()
    -- Resume BEFORE saving or formatting. Experiment B leaves the host inert, and with no manual
    -- resume verb the only other way back is a /reload — so an error in Save or FormatReport must
    -- not be able to strand the addon dead for the rest of the session.
    if P.suspended then
      P.Resume()
      out[#out + 1] = "addon |cff40ff40RESUMED|r \226\128\148 restored"
    end
    P.Save(record)
    -- Deliberately does NOT print the summary. `finish` fires the moment a fight ends, when the log
    -- is buried under combat output and the numbers scroll past unread.
    P.Announce("perf run |cffff4040FINISHED|r \226\128\148 saved; `Report` or `Dump` in the panel "
      .. "to read it, `/reload` to flush it to SavedVariables")
  end

  function SUBS.report()
    showLog()
    for _, line in ipairs(P.FormatReport(P.BuildRecord(P.label))) do P.Log(line) end
    P.MarkReviewed("report")
  end

  -- Writes the JSON to the log, NOT a popup. The log is the window you already have open and can
  -- scroll; popping a modal over the game for something you may only want to glance at is the wrong
  -- default.
  function SUBS.dump()
    showLog()
    P.Log(lib.EncodeJSON(P.BuildRecord(P.label)))
    P.MarkReviewed("dump")
  end

  --- Phase summary plus the usage. Bare `<slash> perf` IS the entry point: the panel's first row
  --- starts a run, so this is how someone who remembers one command reaches all of them.
  function P.StatusLines()
    local phase = "|cffff4040stopped|r"
    if P.recording then
      phase = ("|cff40ff40SAMPLING window %s|r"):format(P.recording)
    elseif P.armed then
      phase = ("|cffffff00window %s armed|r \226\128\148 waiting for combat"):format(P.armed)
    elseif P.run then
      phase = "|cffffff00run active|r \226\128\148 no experiment armed"
    end
    local out = { ("perf %s, addon %s"):format(phase,
      P.suspended and "|cffff4040SUSPENDED|r" or "|cff40ff40active|r") }
    for _, line in ipairs(P.Usage()) do out[#out + 1] = line end
    return out
  end

  --- Run one perf sub-command. `args` is everything after the host's own `perf` verb. Returns the
  --- chat lines the host should print — never nil, so a caller can always ipairs() the result.
  function P.OnCommand(args)
    args = tostring(args or "")
    -- A panel row hands back its full command ("perf measure a"); a slash handler hands back only
    -- what followed its own verb. Accept both so the two paths cannot diverge.
    args = args:gsub("^%s*perf%s*", "")
    local sub = (args:match("^(%S*)") or ""):lower()
    local handler = SUBS[sub]
    if not handler then
      P.ShowPanel()
      return P.StatusLines()
    end
    local out = {}
    handler(out, args:match("^%S*%s+(.*)$"))
    return out
  end

  -- No-panel fallbacks: a host can call or index these unconditionally, whether or not PerfPanel.lua
  -- was loaded alongside this file. lib.__AttachPanel overwrites every one of them when it runs.
  P.ShowPanel     = function() end
  P.HidePanel     = function() end
  P.TogglePanel   = function() end
  P.RefreshPanel  = function() end
  P.IsPanelShown  = function() return false end
  P.STEPS             = {}
  P.PanelStateOf      = function() return "locked" end
  P.PanelIsActionable = function() return false end

  -- The panel is part of this module; a copy of the lib without PerfPanel.lua loaded still works,
  -- it just has no panel. Hosts reach it through P.ShowPanel and friends.
  --
  -- The click path PRINTS what OnCommand returns. A typed command reaches the user through the
  -- host's slash layer, which prints those lines; the panel has no slash layer behind it, so
  -- discarding them made a click quietly produce less output than typing the same thing — the
  -- "ARMED" acknowledgement above all, which is the line telling the user the window is live.
  if lib.__AttachPanel then
    lib.__AttachPanel(P, d, tr, function(cmd)
      local lines = P.OnCommand(cmd)
      for _, line in ipairs(lines) do hostPrint(line) end
      return lines
    end)
  end

  return P
end
