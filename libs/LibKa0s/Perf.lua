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
-- Depends on LibStub, LibKa0s-Core-1.0 and LibKa0s-Lifecycle-1.0, and on NO ADDON FRAMEWORK — that
-- last half is the part worth protecting. Neither sibling embeds anything either, so an addon that
-- is not on the Ace substrate can still adopt this probe; what the two dependencies cost is two
-- vendored sibling files, and re-vendoring is whole-folder, so neither is ever separately missing
-- in practice.

-- Refuse rather than degrade when Core is missing or too old. Failing here means the host's own
-- setup stub reports "perf is not installed" honestly, instead of the probe registering and then
-- nil-erroring mid-run in whichever addon the user happened to be using.
local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

-- The second floor, and it is a RE-VENDOR TRIGGER rather than a quiet addition: a vendored copy of
-- this file that arrives beside a payload with no Lifecycle.lua in it does not register at all, so
-- a host that re-vendored half the folder loses its perf probe outright instead of finding out
-- mid-run. Suspend and resume are now two holds on the host's latch rather than two direct calls
-- into the host, which is the whole reason the floor exists: without the latch there is nothing
-- for `Suspend` to take a hold on, and the arm would have to keep a `suspended` boolean of its own
-- — the second lifecycle mechanism the standard names as the anti-pattern.
local lifecycle = LibStub and LibStub("LibKa0s-Lifecycle-1.0", true)
local NEEDS_LIFECYCLE = 1
if not lifecycle or (lifecycle.MINOR or 0) < NEEDS_LIFECYCLE then return end   -- module absent

local MAJOR, MINOR = "LibKa0s-Perf-1.0", 14
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
-- are not localized pass nothing and get these.

lib.STRINGS = {
  PANEL_TITLE_SUFFIX = " \226\128\148 Perf Run",
  STEP_START    = "Start perf run",
  STEP_MEASURE_A = "Measure A (with the addon)",
  STEP_MEASURE_B = "Measure B (without the addon)",
  STEP_FINISH   = "Finish perf run",
  STEP_REPORT   = "Report",
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

-- Emit every declared ancestor a recorded bucket names, with zero counts where it never fired
-- (issue #12). Buckets are created lazily, on the first Note, so a parent that recorded no calls
-- was absent from the record while its child's `within` named it, and a reader of dump.json had
-- no descriptor to fall back on. Only ANCESTORS are added: a declared bucket with no fired
-- descendant stays absent, so a record does not grow by every idle bucket a host declares. An
-- added parent claims no observation. The depth guard is addBucketLines' own, against a malformed
-- descriptor whose `within` chain loops.
local function fillAncestors(out, withinMap)
  local named = {}
  for _, b in pairs(out) do
    if b.within then named[#named + 1] = b.within end
  end
  for _, parent in ipairs(named) do
    local depth = 0
    while parent and not out[parent] and depth < 8 do
      out[parent] = { calls = 0, totalMs = 0, maxMs = 0, within = withinMap[parent] }
      parent, depth = withinMap[parent], depth + 1
    end
  end
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

-- Per-bucket budgets (issue #1): REPORT-ONLY, by decision. An in-game capture is noisy, and the
-- deterministic offline counters already gate releases, so a budget states a ceiling and the
-- report says whether the capture stayed inside it. Nothing refuses, raises or exits on OVER.
--
-- The record's own budget first, so a capture read back off the ring is judged against the
-- ceiling it was built with; the live descriptor's for a budgeted bucket the record never got.
-- `secs` is the active seconds, as for the bucket table. Returns nil when no bucket declares a
-- budget, which is what keeps an un-adopted host's report and finish ack exactly as they were.
local function axis(parts, label, observed, ceiling)
  if not ceiling then return false end
  local over = observed > ceiling
  parts[#parts + 1] = ("%s %.3f / %.3f %s"):format(label, observed, ceiling, over and "OVER" or "ok")
  return over
end

local function budgetRows(P, record, secs)
  local rows, over = {}, 0
  for _, key in ipairs(P.BUCKET_ORDER) do
    local b = record.buckets[key]
    local budget = b and b.budget or P.BUCKET_BUDGET[key]
    if budget then
      local row = { key = key, parts = {} }
      if not b or b.calls == 0 then
        row.status = "not exercised"
      else
        local rate = secs > 0 and (b.totalMs / secs) or 0
        local hot = axis(row.parts, "ms/s", rate, budget.msPerSec)
        hot = axis(row.parts, "max ms", b.maxMs, budget.maxMs) or hot
        row.status = hot and "OVER" or "ok"
        if hot then over = over + 1 end
      end
      rows[#rows + 1] = row
    end
  end
  if #rows == 0 then return nil end
  return rows, over
end

local function addBudgetLines(add, P, record, secs)
  local rows = budgetRows(P, record, secs)
  if not rows then return end
  add("")
  add("budget (report-only): observed / ceiling")
  for _, row in ipairs(rows) do
    if row.status == "not exercised" then
      add("  %-14s not exercised", row.key)
    else
      add("  %-14s %-4s  %s", row.key, row.status, table.concat(row.parts, ", "))
    end
  end
end

--- How many budgeted buckets a record went over, or nil when no bucket declares a budget. For the
--- finish acknowledgment in PerfCommands.lua, which says one line about it and gates on nothing.
function lib.__budgetOver(P, record)
  local _, over = budgetRows(P, record, record.fps.active.seconds)
  return over
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

-- P.Context's client reads, at file level so the function is a loop over them (it measured CCN 19
-- sighted, WowAddonStandards#6). Each asks one global, existence-checked, so the headless harness
-- (and any client that renames one) degrades to the field's default rather than erroring.

--- The player's specialization name, or nil. Namespaced rung first, deprecated global second, nil
--- where neither is there — the shape `Env.lua`'s C_AddOns shim models, applied here because the
--- spec reader moved the same way. The global still answers on today's client, which is exactly why
--- this was easy to miss: the day it stops, every saved record names the spec "?" and a record is
--- read weeks later, when there is nothing left to go and look at. `GetSpecializationInfo` keeps its
--- own guard on the global rather than being paired with a namespaced rung, because the reader that
--- moved is the INDEX one and this shim claims no more than it has checked.
local function specName()
    local specIndex = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
        or GetSpecialization
    if not (specIndex and GetSpecializationInfo) then return nil end
    local index = specIndex()
    if not index then return nil end
    local _, name = GetSpecializationInfo(index)
    return name
end

--- { field, reader } in the order P.Context always read them. A reader answering nil (or false)
--- leaves the field at its default.
local CONTEXT_READS = {
    { "character", function() return UnitName and UnitName("player") end },
    { "realm",     function() return GetRealmName and GetRealmName() end },
    { "class",     function() return UnitClass and (UnitClass("player")) end },
    { "level",     function() return UnitLevel and UnitLevel("player") end },
    { "spec",      specName },
    { "zone",      function() return GetZoneText and GetZoneText() end },
    { "subZone",   function() return GetSubZoneText and GetSubZoneText() end },
}

-- The descriptor's optional host sinks, resolved once so the hot-ish paths do not re-branch on
-- presence. At file level rather than inside lib:New, so the four presence tests are this
-- function's branches and not the closure's: a sighted lizard run counted every `and`/`or` in
-- them against lib:New (issue #7).
local function noop() end
local function printLine(line) print(line) end

local function resolveHooks(d)
  local function hook(f, default)
    if type(f) == "function" then return f end
    return default
  end
  return hook(d.log, printLine), hook(d.print, printLine), hook(d.showLog, noop),
    hook(d.onChange, noop)
end

-- What a probe with no PerfCommands.lua or no PerfSampler.lua beside it answers (issue #7). Both
-- files are part of this major and a whole-folder re-vendor always carries them, so this arises only
-- from a hand-trimmed copy; one line naming the file says what to fix, where a nil member would
-- raise in the host's slash layer or the panel's click path. OnCommand keeps its contract: a table,
-- never nil. Without the capture the commands have nothing to drive, so they answer its line.
local COMMANDS_MISSING = "perf commands are not installed \226\128\148 PerfCommands.lua is missing "
  .. "from this copy of LibKa0s; re-vendor the whole folder"
local SAMPLER_MISSING = "perf capture is not installed \226\128\148 PerfSampler.lua is missing "
  .. "from this copy of LibKa0s; re-vendor the whole folder"

local function installCommandStub(P, line)
  local function missing() return { line } end
  P.Usage, P.StatusLines, P.OnCommand = missing, missing, missing
end

-- The capture's members, inert. The brackets are no-ops (P.on is never set without the windows,
-- so they were never going to record); Start says why in the log and runs nothing; Stop still
-- hands back a record, an empty one, because a host driving the API directly reads it.
local function installSamplerStub(P)
  local function no() return false end
  P.Open, P.Close, P.__sampler = noop, noop, noop
  P.Start   = function() P.Log(SAMPLER_MISSING) end
  P.Measure = function() return nil, "no experiment" end
  P.Stop    = function() return P.BuildRecord(P.label) end
  P.Cancel, P.Suspend, P.Resume = no, no, no
end

-- The two secondary files lib:New installs from, or their stubs. Returns what P.Reset calls to
-- close every open bracket. At file level so lib:New carries none of these branches.
local function installPeers(P, ctx)
  if not lib.__installSampler then
    installSamplerStub(P)
    installCommandStub(P, SAMPLER_MISSING)
    return noop
  end
  local resetOpenDepth = lib.__installSampler(P, ctx)
  if lib.__installCommands then
    lib.__installCommands(P, ctx)
  else
    installCommandStub(P, COMMANDS_MISSING)
  end
  return resetOpenDepth
end

-- The descriptor's `buckets`, validated per entry rather than trusted: an entry with no `key` used
-- to raise a raw "table index is nil" from inside the loop, which tells a host nothing about which
-- of its buckets is wrong. A `budget` is refused the same way, naming the entry and the field
-- (issue #1). The levels blame lib:New's caller, the descriptor's author. The budget is copied, so
-- a host that edits its descriptor table later does not move a ceiling under a live instance.
local function ceiling(i, budget, field)
  local v = budget[field]
  if v ~= nil and (type(v) ~= "number" or v ~= v or v <= 0) then   -- v ~= v: NaN
    error(("LibKa0s-Perf: descriptor.buckets[%d].budget.%s must be a positive number")
      :format(i, field), 5)
  end
  return v
end

local function readBudget(i, budget)
  if budget == nil then return nil end
  if type(budget) ~= "table" then
    error(("LibKa0s-Perf: descriptor.buckets[%d].budget must be a table"):format(i), 4)
  end
  local out = { msPerSec = ceiling(i, budget, "msPerSec"), maxMs = ceiling(i, budget, "maxMs") }
  if not (out.msPerSec or out.maxMs) then
    error(("LibKa0s-Perf: descriptor.buckets[%d].budget must name msPerSec or maxMs"):format(i), 4)
  end
  return out
end

local function readBuckets(d)
  local order, within, budgets = {}, {}, {}
  for i, b in ipairs(d.buckets or {}) do
    if type(b) ~= "table" or type(b.key) ~= "string" then
      error(("LibKa0s-Perf: descriptor.buckets[%d].key must be a string"):format(i), 3)
    end
    order[#order + 1] = b.key
    if b.within then within[b.key] = b.within end
    budgets[b.key] = readBudget(i, b.budget)
  end
  return order, within, budgets
end

-- The declared budget onto each emitted bucket, a copy per record so editing a saved record cannot
-- move the host's ceiling. Additive within schema 2: an unbudgeted bucket carries no `budget` key.
local function attachBudgets(out, budgets)
  for key, b in pairs(out) do
    local g = budgets[key]
    if g then b.budget = { msPerSec = g.msPerSec, maxMs = g.maxMs } end
  end
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
  -- The host's stand-down latch, and the only route this module now has to making the addon inert.
  -- Required rather than optional: an instance with no latch has no way to suspend, and a perf run
  -- whose Experiment B measured a fully live addon produces a delta of roughly zero and reads as
  -- "this addon costs nothing" — a wrong answer that looks exactly like a good one.
  --
  -- `suspend` and `resume` are NO LONGER REQUIRED and are no longer called. A host that has adopted
  -- the latch passes the very same two functions to LibKa0s-Lifecycle-1.0 as `standDown` and
  -- `standUp`, where the DISABLED arm reaches them too; leaving them on this descriptor as well is
  -- harmless and is what an un-migrated host will do, but nothing here reads them. Keeping the
  -- `required` calls would have forced every host to carry two live copies of its own teardown, and
  -- two copies is how the perf arm and the disable arm drift apart.
  required(d, "lifecycle", "table")

  local P = {}

  -- Optional host sinks, resolved once so the hot-ish paths do not re-branch on presence.
  local hostLog, hostPrint, showLog, onChange = resolveHooks(d)
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

  -- Report order, the declared nesting and the declared budgets (readBuckets). Membership controls
  -- only PRESENTATION — Note() accepts any key, so a bracket nobody declared still records, it just
  -- does not print.
  P.BUCKET_ORDER, P.BUCKET_WITHIN, P.BUCKET_BUDGET = readBuckets(d)

  -- Capture running? Read directly by every bracket call site, so it must stay a plain boolean RAW
  -- field — no accessor. The instance does carry a metatable (below), but it exists only for
  -- `suspended`; a raw key never reaches it.
  --
  -- `armed`, `recording` and `label` start as `false` and are never written nil, for the same
  -- reason: the sampler reads `armed` and `recording` on every frame of a run, and a nil write
  -- removes the raw key so each later read falls through to the __index closure (Perf minor 13).
  -- Every reader tests truthiness or compares against a string, so `false` reads as "none".
  P.on        = false
  P.run       = false     -- between Start() and Stop()
  P.armed     = false     -- window armed, waiting for combat
  P.recording = false     -- window currently recording
  P.label     = false     -- the run's capture label

  -- The latch, and the one hold this module is allowed to take on it. The key is read off the
  -- Lifecycle major rather than spelled here, so the arm that takes the hold and the arm that
  -- releases it cannot come to disagree about what it is called.
  local lc   = d.lifecycle
  local HOLD = lifecycle.HOLD_PERF

  -- `P.suspended` IS THE LATCH, READ THROUGH. This module used to keep its own boolean beside the
  -- host's inert state, and that second copy is precisely what let a `resume` at the end of a perf
  -- run resurrect an addon the player had disabled halfway through it: two booleans, one edge, and
  -- whichever wrote last won. There is now exactly one answer to "is this addon inert", it lives in
  -- the latch, and this field is a VIEW of it rather than a copy — every existing host and every
  -- existing case that reads `P.suspended` keeps reading the same field name and now gets the truth.
  --
  -- __newindex guards the one key. A write to `P.suspended` would rawset a shadowing field that
  -- wins over __index forever after, which is the silent half of the bug this removes; every other
  -- key writes through untouched, and __newindex only ever fires for a key the table does not
  -- already carry, so nothing on the bracket path pays for it.
  setmetatable(P, {
    __index = function(_, k)
      if k == "suspended" then return lc:IsHeld(HOLD) end
      return nil
    end,
    __newindex = function(t, k, v)
      if k == "suspended" then
        error("LibKa0s-Perf: P.suspended is the latch's answer and cannot be assigned — "
          .. "take or release the '" .. HOLD .. "' hold instead", 2)
      end
      rawset(t, k, v)
    end,
  })

  local buckets   = {}
  local completed = { active = false, suspended = false }
  local reviewed  = { report = false }
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

  -- The open depth of the Shape B brackets lives in PerfSampler.lua with P.Open and P.Close since
  -- Perf minor 14 (issue #7); P.Reset zeroes it through this, which the installer hands back. Until
  -- then, and for good in a payload without that file, there is nothing to close.
  local resetOpenDepth = noop

  function P.Reset()
    buckets   = {}
    -- The DEPTH is what resets, and `slots` is deliberately kept: it is the free list, so emptying
    -- it here would make the first brackets of every run allocate again, which is the cost this
    -- shape exists to pay once. Nothing reads a slot above `openDepth`, so leaving them is not a
    -- leak of state between runs — the next Open at that depth overwrites both fields.
    resetOpenDepth()
    completed = { active = false, suspended = false }
    reviewed  = { report = false }
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
        report = review("report"),
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
      for _, read in ipairs(CONTEXT_READS) do
          local value = read[2]()
          if value then ctx[read[1]] = value end
      end
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
    fillAncestors(out, P.BUCKET_WITHIN)
    attachBudgets(out, P.BUCKET_BUDGET)

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
    -- A retention prune, and debug-logging-§8 makes a prune one of the flows the log MUST tell.
    -- One summary line per prune, never one per record (debug-logging-§9).
    local over = #db.runs - P.ringMax
    if over > 0 then
      for _ = 1, over do table.remove(db.runs, 1) end
      P.Log("perf ring at its cap of %s \226\128\148 dropped %s oldest record(s)",
        tostring(P.ringMax), tostring(over))
    end
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
    add("capture: %s  (%s, schema %d, v%s)", record.label ~= "" and record.label or "unlabeled",
        record.addon, record.schema, record.version)
    for _, line in ipairs(P.ContextLines(record.context)) do add(line) end

    addFpsLines(add, f)
    addBucketLines(add, P, record, f.active.seconds)
    addNestingNote(add, P, record)
    addBudgetLines(add, P, record, f.active.seconds)

    return lines
  end

  -- ── The capture, and the command surface ────────────────────────────────────────────────
  --
  -- In LibKa0s/PerfSampler.lua since Perf minor 14 (issue #7): the Shape B brackets, the
  -- measurement windows, the FPS sampler, P.Start through P.Cancel, and P.Suspend / P.Resume. In
  -- LibKa0s/PerfCommands.lua: P.Usage, the sub-verb handlers, P.StatusLines and P.OnCommand. A
  -- payload without either file still answers every command, with one line naming it, so a host's
  -- slash layer and the panel's click path never meet a nil (installPeers).
  resetOpenDepth = installPeers(P, {
    d = d, showLog = showLog, publishState = publishState, hold = HOLD,
    arms = function() return fpsArms end,
    completed = function() return completed end,
  })
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
  -- "ARMED" acknowledgment above all, which is the line telling the user the window is live.
  if lib.__AttachPanel then
    lib.__AttachPanel(P, d, tr, function(cmd)
      local lines = P.OnCommand(cmd)
      for _, line in ipairs(lines) do hostPrint(line) end
      return lines
    end)
  end

  return P
end
