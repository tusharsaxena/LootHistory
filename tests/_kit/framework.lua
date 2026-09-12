-- testkit/framework.lua — the test registry, the assertions, the runner and the `--list` renderer.
--
-- COLLECT-THEN-RUN, deliberately. Some runners in the collection execute each case body at
-- registration time and short-circuit it in list mode, which makes `--list` a second code path
-- through the same file — so the inventory can disagree with the run. Here `test()` only records,
-- and nothing executes until run(). `--list` is then a pure filter over the registry and cannot
-- drift from what actually runs.

local Kit = {}

--- The kit revision. A plain integer, bumped on every released change to ANY file in `testkit/`,
--- because the files vendor as one folder and are never adopted separately.
---
--- This is NOT a LibStub minor and does NOT make the kit a library: nothing registers it, no load
--- order depends on it, and two copies never negotiate — the vendoring gate is byte-identity, not
--- version comparison (`tests/test_kitsync.lua`). What it buys is the one question byte-identity
--- cannot answer on its own: *which* kit is a given consumer holding? Before this, "AbsorbTracker's
--- kit is stale" was only reachable by diffing against this repo at the right commit. Now the
--- consumer can say so itself, and its API document has a name.
Kit.VERSION = 16

local tests = {}
local currentSuite  -- basename (no extension) of the suite file currently being dofile'd

--- Register a case.
---
--- `skipReason`, when given, registers the case as a DECLARED skip: `fn` is never called, the run
--- reports it as SKIP, and `--list` discloses the reason. That is the only kind of skip `--list` can
--- see, because `--list` never executes a case body (see the header) — a skip decided inside a body
--- is reported by the run, not by the inventory.
function Kit.test(name, fn, skipReason)
  tests[#tests + 1] = { name = name, fn = fn, suite = currentSuite, skip = skipReason }
end

-- ── skip ───────────────────────────────────────────────────────────────────────────────────
--
-- A third status, and the reason it exists: a case that CANNOT LOOK — no sibling checkout, no
-- git, a fixture the platform cannot produce — used to be written as a bare `return`, which
-- registers as PASS. Six repos in this collection did exactly that, so six green gates were
-- reporting "checked and fine" for a check that never ran.
--
-- Implemented as a sentinel error so it works from inside a case body, at any depth, without
-- restructuring the case into a predicate plus a body. Two properties are NON-NEGOTIABLE and are
-- asserted by the consumers that depend on them:
--
--   * a skip is NEVER folded into `passed` — the README [tests] badge and docs/test-cases.md
--     count passes, and a skip counted as one is the original lie in a new place;
--   * a skip NEVER changes the exit code — the same script is the commit gate, and the release
--     gate reads `suites.tests.failed` from the run manifest. A skip is "not evaluated", which the
--     release flow judges for itself; it is not a failure to be re-litigated here.

local SKIP = {}

--- Abandon the current case with a reason, reported as SKIP rather than as PASS or FAIL.
--- Never returns.
function Kit.skip(reason)
  error(setmetatable({ reason = tostring(reason or "no reason given") }, SKIP), 0)
end

--- The reason, if `err` is a skip sentinel; nil for any other error value.
local function skipReasonOf(err)
  if type(err) == "table" and getmetatable(err) == SKIP then return err.reason end
  return nil
end

-- ── assertions ─────────────────────────────────────────────────────────────────────────────
--
-- `level + 1` on every failure so the reported line is the CALLER's, not this file's.

local function fail(msg, level) error(msg, (level or 1) + 1) end
Kit.fail = fail

local function fmt(v)
  if type(v) == "table" then return "<table>" end
  return tostring(v)
end

function Kit.assertEqual(got, want, msg)
  if got ~= want then
    fail((msg or "assertEqual") ..
      string.format(" (expected %s, got %s)", fmt(want), fmt(got)), 1)
  end
end

function Kit.assertTrue(c, msg) if not c then fail(msg or "assertTrue failed", 1) end end
function Kit.assertFalse(c, msg) if c then fail(msg or "assertFalse failed", 1) end end

function Kit.assertNil(v, msg)
  if v ~= nil then fail((msg or "assertNil") .. " (got " .. fmt(v) .. ")", 1) end
end

--- Float comparison with an explicit tolerance. Never compare computed geometry with `==`.
function Kit.assertNear(got, want, tolerance, msg)
  tolerance = tolerance or 1e-6
  if type(got) ~= "number" or math.abs(got - want) > tolerance then
    fail((msg or "assertNear") ..
      string.format(" (expected %s +/- %s, got %s)", fmt(want), fmt(tolerance), fmt(got)), 1)
  end
end

--- Assert that calling fn raises. Returns the error message so a caller can assert on its text —
--- an assertion that something raised, without checking WHAT, passes just as happily on a typo in
--- the test itself.
function Kit.assertError(fn, msg)
  local ok, err = pcall(fn)
  if ok then fail(msg or "assertError: expected an error, got none", 1) end
  return tostring(err)
end

-- ── the surface source ─────────────────────────────────────────────────────────────────────
--
-- `Kit.assertSurfaceParity(stub, "LibKa0s-Options-1.0")` names a live surface instead of building
-- one, which is what turns a parity case into three lines a repo will actually write. The kit
-- cannot resolve that name on its own: it has no LibStub, no mock and no addon namespace, and
-- `_G.LibStub` is not it either — the loader hands each chunk a mocked environment rather than
-- writing into `_G` (`loader.lua`), so a kit that reached for the global would resolve nothing
-- headlessly and say the stub was fine.
--
-- So the harness supplies the source, once, and it takes either shape a harness naturally has:
--
--   * a CALLABLE — `Kit.setSurfaceSource(mocks.LibStub)`. Called as `src(name, true)`, which is
--     LibStub's own silent-lookup signature. This answers the LIBRARY TABLE for a major.
--   * a TABLE — `Kit.setSurfaceSource{ ["LibKa0s-Options-1.0"] = NS.Helpers }`. A map of name to
--     live surface, for the far commoner case where the stub mirrors an INSTANCE rather than the
--     library table. Every `settings/OptionsSetup.lua` degradation arm in this collection stubs
--     `NS.Helpers`, which is what `lib:New(descriptor)` returned — a surface the kit could never
--     have built for itself, because it needs the host's descriptor.
--
-- `Kit.expose` wires the callable shape automatically when the exposed table carries a mock with a
-- LibStub on it, so a repo whose stubs mirror library tables registers nothing. Anything else is
-- one explicit line in the runner, and the assertion FAILS rather than passes when the name does
-- not resolve — see the bargain in `assertSuiteInventory`.

local surfaceSource

--- Register where `Kit.assertSurfaceParity(stub, name)` looks a live surface up, and return the
--- source that was registered before — so a case that swaps it can put the old one back.
---
--- `src` is a callable, a table, or nil to unregister.
function Kit.setSurfaceSource(src)
  local previous = surfaceSource
  surfaceSource = src
  return previous
end

--- Is `v` reachable as a function call — a plain function, or a table with a `__call`?
local function callable(v)
  if type(v) == "function" then return true end
  local mt = type(v) == "table" and getmetatable(v)
  return (mt and mt.__call) ~= nil
end

--- The live surface registered under `name`, or nil plus why not.
local function resolveSurface(name)
  if surfaceSource == nil then
    return nil, ("no surface source is registered, so %q cannot be resolved and this gate cannot "
      .. "run — call Kit.setSurfaceSource(mocks.LibStub) or "
      .. "Kit.setSurfaceSource{ [%q] = <the live surface> } in the runner"):format(name, name)
  end
  local live
  if callable(surfaceSource) then
    local ok, got = pcall(surfaceSource, name, true)
    if not ok then
      return nil, ("the surface source raised on %q: %s"):format(name, tostring(got))
    end
    live = got
  else
    live = surfaceSource[name]
  end
  if type(live) ~= "table" then
    return nil, ("the surface source answers %s for %q, not a table — either the name is wrong or "
      .. "the live surface never loaded"):format(type(live), name)
  end
  return live
end

-- ── the public surface of a live module ────────────────────────────────────────────────────

--- LibStub bookkeeping. Present on every registered major, carried by no degradation stub in this
--- collection, and rightly so: `MAJOR` and `MINOR` are how the LIBRARY answers "which copy am I",
--- and a stub that answered them would be claiming to be the library it is standing in for.
local BOOKKEEPING = { MAJOR = true, MINOR = true, MODULES = true }

--- The public members of a live surface, sorted, as `{ { name = ..., kind = <type> }, ... }`.
---
--- Two exclusions, and they are the difference between a gate that gets adopted and one that does
--- not. `BOOKKEEPING` above, and every `__`-prefixed key: those are the module's own internals —
--- `__AttachWidgets`, `__widgetsMinor`, `__panelProbeMinor` — reached by a sibling file inside the
--- same major and by nothing else. Reported raw, the Options major alone would hand a stub author
--- ten divergences that are all correct omissions, and a gate whose first run is ten false
--- positives is a gate that gets an `ignore` list the size of its own output.
function Kit.publicMembers(t)
  local members = {}
  if type(t) ~= "table" then return members end
  for k, v in pairs(t) do
    if type(k) == "string" and not BOOKKEEPING[k] and k:sub(1, 2) ~= "__" then
      members[#members + 1] = { name = k, kind = type(v) }
    end
  end
  table.sort(members, function(a, b) return a.name < b.name end)
  return members
end

--- Assert that a degraded-path stub carries the whole surface of the live module.
---
--- Two calling forms:
---
---   assertSurfaceParity(live, degraded, label, ignore)   -- two tables, compared key for key
---   assertSurfaceParity(stub, majorName, ignore)         -- the live half is looked up by name
---
--- The second is selected by a STRING in the second position, and is the one a degradation case
--- should use: it names the surface instead of rebuilding it, and it compares only the PUBLIC
--- members (`Kit.publicMembers`), which is what a stub is actually obliged to carry. The first form
--- compares every key of `live` and is unchanged — a repo comparing two namespaces it built itself
--- decides for itself what belongs in them.
---
--- `live` is the real thing; `degraded` is what the addon falls back to when the library is not
--- there. Three of this collection's surviving High findings are one omitted stub member: a stub
--- returns without assigning `FormatKV`, so the command raises on exactly the degraded path the
--- stub exists to survive.
---
--- Two divergences are reported:
---   * a key present in `live` and ABSENT from `degraded`;
---   * a key that is a FUNCTION live and something else degraded — `false`, a table, a string.
---     `Helpers.RefreshAllPanels = UI and UI.RefreshAllPanels` is the shape: when `UI` is nil the
---     assignment yields nil and the key is simply absent (caught by the first rule); when `UI` is
---     present but the member is not, or the guard yields `false`, the key IS there and the call
---     site raises anyway. A check that only asks "is the key set?" waves that through.
---
--- EVERY divergence goes into ONE message, not the first. A stub written from a stale surface is
--- typically wrong in several places, and one-at-a-time is one test run per missing member.
---
--- `ignore` encodes "this member is live-only, on purpose" as data — either as a set
--- (`{ Foo = true }`) or as an array (`{ "Foo" }`). An intentional omission and a bug are otherwise
--- indistinguishable, and the usual resolution for that is to delete the case.
function Kit.assertSurfaceParity(live, degraded, label, ignore)
  -- Form two: `(stub, majorName, ignore)`. A string in the second position is unambiguous — the
  -- first form's second argument is the degraded table, and its third is the label.
  local byName = type(degraded) == "string"
  local publicOnly
  if byName then
    local name = degraded
    local resolved, why = resolveSurface(name)
    if not resolved then fail(name .. ": " .. why, 1) end
    degraded, ignore, label, live = live, label, name, resolved
    publicOnly = true
  end

  label = label or "surface"
  if type(live) ~= "table" then fail(label .. ": the live surface is not a table", 1) end
  if type(degraded) ~= "table" then fail(label .. ": the degraded surface is not a table", 1) end

  local skip = {}
  for k, v in pairs(ignore or {}) do
    if v == true then skip[k] = true else skip[v] = true end
  end

  local keys = {}
  if publicOnly then
    for _, member in ipairs(Kit.publicMembers(live)) do
      if not skip[member.name] then keys[#keys + 1] = member.name end
    end
  else
    for k in pairs(live) do
      if not skip[k] then keys[#keys + 1] = k end
    end
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

  local problems = {}
  for _, k in ipairs(keys) do
    local lv, dv = live[k], degraded[k]
    if dv == nil then
      problems[#problems + 1] = ("%s is missing (live: %s)"):format(tostring(k), type(lv))
    elseif type(lv) == "function" and type(dv) ~= "function" then
      problems[#problems + 1] =
        ("%s is a function live but %s degraded"):format(tostring(k), type(dv))
    end
  end

  if #problems > 0 then
    fail(("%s: the degraded stub diverges from the live surface in %d place(s) — %s")
      :format(label, #problems, table.concat(problems, "; ")), 1)
  end
end

--- Merge the registry and assertions into the host's `_G.<X>_TEST` table and return it, so a repo
--- keeps its existing global name and key set and no suite file has to change.
function Kit.expose(t)
  t = t or {}
  t.KIT_VERSION = Kit.VERSION
  t.test        = Kit.test
  t.fail        = Kit.fail
  t.skip        = Kit.skip
  t.assertEqual = Kit.assertEqual
  t.assertTrue  = Kit.assertTrue
  t.assertFalse = Kit.assertFalse
  t.assertNil   = Kit.assertNil
  t.assertNear  = Kit.assertNear
  t.assertError = Kit.assertError
  t.assertSuiteInventory = Kit.assertSuiteInventory
  t.assertSurfaceParity  = Kit.assertSurfaceParity
  t.publicMembers        = Kit.publicMembers
  t.setSurfaceSource     = Kit.setSurfaceSource

  -- The by-name form needs somewhere to look, and every harness in this collection that stubs a
  -- LIBRARY TABLE already has it: the mock it just built. Wired here rather than demanded of the
  -- runner so that adoption is the case alone, and only when nothing is registered yet — a repo
  -- that called setSurfaceSource itself (because its stubs mirror instances) keeps its own.
  if surfaceSource == nil then
    local mock = t.mocks or t.mock
    local ls = t.LibStub or (type(mock) == "table" and mock.LibStub) or nil
    if ls then Kit.setSurfaceSource(ls) end
  end
  return t
end

-- ── suite loading ──────────────────────────────────────────────────────────────────────────

local function fileExists(path)
  local f = io.open(path, "r")
  if f then f:close(); return true end
  return false
end

--- A suites entry is either a plain basename or a table:
---
---   `{ name = "test_foo", pending = "why" }`   — declared, deliberately not on disk yet
---   `{ name = "test_eol", dir = "tests/_kit/" }` — a suite that arrives with the vendored kit
---
--- `dir` overrides the runner's own suite directory for that entry alone. It exists because the kit
--- now ships suites of its own: a gate every consumer needs and no consumer should be asked to
--- re-type is vendored with `framework.lua`, and it lives where the rest of the kit lives rather
--- than being copied into each repo's `tests/`.
local function suiteEntry(entry)
  if type(entry) == "table" then return entry.name, entry.pending, entry.dir end
  return entry, nil, nil
end

--- List the plain entries of a directory, sorted. Lua 5.1 has no directory API and nothing in this
--- collection depends on LuaFileSystem, so the listing shells out: `ls -A` covers every shell the
--- suites are actually run under (Linux, WSL, macOS, Git Bash), `dir /b` is the cmd.exe fallback.
--- An empty result means "could not look" and every caller must treat it as a failure, never as an
--- empty directory — a gate that goes quiet when it cannot look is worse than no gate.
local function listDir(dir)
  local names = {}
  local function collect(cmd)
    if not io.popen then return end
    local p = io.popen(cmd)
    if not p then return end
    for line in p:lines() do
      local name = line:gsub("[\r\n]+$", "")
      if name ~= "" and name ~= "." and name ~= ".." then names[#names + 1] = name end
    end
    p:close()
  end
  collect(('ls -A "%s" 2>/dev/null'):format(dir))
  if #names == 0 then collect(('dir /b "%s" 2>NUL'):format((dir:gsub("/", "\\")))) end
  table.sort(names)
  return names
end

--- Load every suite, stamping each registered case with the file it came from.
---
--- A declared suite whose file is NOT on disk is a hard error. It used to be skipped, and the
--- comment here used to call that deliberate — "so a suite can be listed while it is being written
--- without taking the whole run down with it". The convenience is real; the silence is not worth
--- it. A renamed or deleted suite vanished from the run with no signal at all, and the run stayed
--- green while covering less than it did yesterday.
---
--- The write-in-progress affordance survives, made explicit: `{ name = "test_foo", pending = "why" }`
--- registers a declared skip instead of registering nothing. Declaring `pending` on a suite whose
--- file DOES exist is also an error — that is the same silence wearing the affordance's clothes.
local function loadSuites(dir, suites)
  for i, entry in ipairs(suites) do
    local name, pending, entryDir = suiteEntry(entry)
    local path = (entryDir or dir) .. tostring(name) .. ".lua"
    currentSuite = name
    if pending then
      if fileExists(path) then
        error(("suite inventory: %s is declared `pending = %q` (position %d in the suites list) but "
          .. "the file exists — drop the `pending` field so its cases actually run")
          :format(path, tostring(pending), i), 0)
      end
      Kit.test(tostring(name) .. ".lua: suite not written yet", nil, tostring(pending))
    elseif fileExists(path) then
      -- `loadfile` and call, rather than `dofile`, so the chunk receives the kit as `...`. A suite
      -- that ships IN the kit cannot read the exposed table the way a repo's own suites do: that
      -- table's global name is the consumer's (`LK_TEST`, `AT_TEST`, `KICKCD_TEST`, …) and the kit
      -- is never told what it is. A suite that ignores the argument — every existing one — is
      -- unaffected, and a syntax error still raises with the same message `dofile` gave.
      local chunk, err = loadfile(path)
      if not chunk then error(err, 0) end
      chunk(Kit)
    else
      error(("suite inventory: %s is declared in the suites list (position %d) but is not on disk "
        .. "— delete the entry or write the file; to keep it listed while it is being written, "
        .. "declare it as { name = %q, pending = \"why\" } so it registers as a skip rather than "
        .. "as nothing"):format(path, i, tostring(name)), 0)
    end
  end
  currentSuite = nil
end

--- The `test_*.lua` basenames on disk under `dir`, and the raw listing they came from.
local function suiteFilesOn(dir)
  local listing = listDir(dir)
  local names = {}
  for _, f in ipairs(listing) do
    local name = f:match("^(test_.+)%.lua$")
    if name then names[#names + 1] = name end
  end
  return names, #listing
end

-- The suites list, folded into the four lookups the gate reads: declaration order, the index each
-- name was declared at, the names that are deliberately absent, and the ones that live outside the
-- runner's own directory.
local function suiteDeclarations(suites)
  local declared, order, pending, dirs = {}, {}, {}, {}
  for i, entry in ipairs(suites or {}) do
    local name, why, entryDir = suiteEntry(entry)
    name = tostring(name)
    declared[name] = i
    order[#order + 1] = name
    -- A `pending` entry is declared-and-deliberately-absent. Demanding it be on disk would make the
    -- write-in-progress affordance unreachable, which is the whole point of keeping it. The other
    -- direction still binds: if the file DOES appear, `loadSuites` raises rather than skipping it.
    if why then pending[name] = true end
    if entryDir then dirs[name] = entryDir end
  end
  return declared, order, pending, dirs
end

-- A directory that cannot be listed is not an empty directory. Both callers below would otherwise
-- read "no suite files here" as "nothing has drifted" and report a gate that never ran as green.
local function suiteNamesOrFail(dir)
  local names, listed = suiteFilesOn(dir)
  if listed == 0 then
    fail("suite inventory: could not list " .. dir .. " — no `ls -A` and no `dir /b`; this gate "
      .. "cannot run, and must not be reported as passing", 3)
  end
  return names
end

-- Direction one: declared but not on disk.
local function collectMissing(problems, dir, order, dirs, pending, present)
  for i, name in ipairs(order) do
    -- An entry carrying its own `dir` is not expected in the runner's suite directory and is asked
    -- about where it actually lives.
    local at = dirs[name]
    local found
    if at then found = fileExists(at .. name .. ".lua") else found = present[name] end
    if not found and not pending[name] then
      problems[#problems + 1] = ("%s%s.lua is declared in the suites list (position %d) but is not "
        .. "on disk — delete the entry or write the file"):format(at or dir, name, i)
    end
  end
end

-- Direction two: on disk but not declared. `describe` differs between the runner's own directory
-- and the vendored kit because the fix differs — one is an entry, the other is an entry naming a
-- directory the runner does not own.
local function collectUndeclared(problems, dir, onDisk, declared, describe)
  for _, name in ipairs(onDisk) do
    if not declared[name] then
      problems[#problems + 1] = describe(dir, name)
    end
  end
end

local function undeclaredHere(dir, name)
  return ("%s%s.lua exists but is not declared in the suites list — add %q to the runner; it is "
    .. "running zero cases today"):format(dir, name, name)
end

local function undeclaredInKit(dir, name)
  return ("%s%s.lua arrived with the vendored kit but is not declared in the suites list — add "
    .. "{ name = %q, dir = %q } to the runner; it is running zero cases today"):format(dir, name, name, dir)
end

--- Both directions of the suite list, asserted.
---
--- `testing-§9` names the suite list as a list that MUST be pinned, and both of its silent failure
--- modes were live in this collection: a declared suite whose file is gone was skipped, and a suite
--- file nobody added to the list never ran at all. `loadSuites` closes the first; this closes the
--- second, and re-closes the first for the repos that call this directly from a case.
---
--- The two messages are worded differently on purpose, because the two fixes are different: one is
--- "delete the entry or write the file", the other is "add it to the runner". Every divergence in
--- both directions is reported in one message — a list that has drifted has usually drifted more
--- than once, and one-at-a-time is one test run per missing file.
---
--- THE VENDORED KIT IS SCANNED TOO, and it is the same second direction. A suite that ships in the
--- kit arrives in a consumer with a re-vendor rather than with a commit someone wrote, so the way it
--- fails is the way it always fails: the copy lands, nobody adds it to the suite list, and the run
--- is green over a gate that never executed. `tests/_kit/` is scanned whenever `framework.lua` is
--- found there — the collection's one vendoring destination, and the guard means a repo that
--- vendors somewhere else is simply not asked about it.
function Kit.assertSuiteInventory(dir, suites)
  dir = dir or "tests/"
  local declared, order, pending, dirs = suiteDeclarations(suites)

  local onDisk = suiteNamesOrFail(dir)
  local present = {}
  for _, name in ipairs(onDisk) do present[name] = true end

  local problems = {}
  collectMissing(problems, dir, order, dirs, pending, present)
  collectUndeclared(problems, dir, onDisk, declared, undeclaredHere)

  local kitDir = dir .. "_kit/"
  if fileExists(kitDir .. "framework.lua") then
    collectUndeclared(problems, kitDir, suiteNamesOrFail(kitDir), declared, undeclaredInKit)
  end

  if #problems > 0 then
    fail("suite inventory (" .. dir .. "):\n          - " .. table.concat(problems,
      "\n          - "), 2)
  end
end

-- ── `--list` ───────────────────────────────────────────────────────────────────────────────
--
-- Emits the whole body of docs/test-cases.md, CRLF-terminated, and exits 0 without running a
-- single case. CRLF is written HERE rather than left to a `| sed 's/$/\r/'` in the shell: the
-- repos pin `*.md text eol=crlf`, a plain redirect writes LF, and a regeneration command with a
-- pipeline in it is one someone eventually runs without the pipeline.

-- ── the command line ───────────────────────────────────────────────────────────────────────
--
-- Three flags, all parsed here so `--list` and the shard driver read the same argv the same way:
--
--   --list          render the inventory and exit, running nothing
--   --jobs N|auto   fan the suites out across N worker processes (`-j` is the short form)
--   --shard I/N     run only slice I of N. Set by the driver on each child; not for hand use.

local function argv() return arg or {} end

local function hasFlag(name)
  for _, a in ipairs(argv()) do
    if a == name then return true end
  end
  return false
end

--- The value of `--name V` or `--name=V`, or nil when the flag is absent.
local function flagValue(name)
  local a = argv()
  local pattern = "^" .. name:gsub("%-", "%%-") .. "=(.+)$"
  for i, v in ipairs(a) do
    if v == name then return a[i + 1] end
    local inline = tostring(v):match(pattern)
    if inline then return inline end
  end
  return nil
end

local function wantsList() return hasFlag("--list") end

--- `I, N` from `--shard I/N`, or nil when this process is not a shard.
--- A malformed value RAISES rather than defaulting: silently running everything when the caller
--- asked for a slice is how a parallel gate reports four passes for one run's worth of work.
local function shardArg()
  local v = flagValue("--shard")
  if not v then return nil end
  local i, n = tostring(v):match("^(%d+)/(%d+)$")
  i, n = tonumber(i), tonumber(n)
  if not i or not n or n < 1 or i < 1 or i > n then
    error(("--shard expects I/N with 1 <= I <= N, e.g. `--shard 2/4`; got %q"):format(tostring(v)), 0)
  end
  return i, n
end

--- The machine-readable line a shard emits INSTEAD of the human summary. The driver strips it from
-- the output it relays and adds the counts up; a shard that dies without printing one is reported
-- as a failure rather than contributing a silent zero.
local SHARD_MARKER = "__KIT_SHARD"

--- How many CPUs the host admits to, for `--jobs auto`. 1 when it will not say.
local function cpuCount()
  if not io.popen then return 1 end
  local p = io.popen("nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null")
  if not p then return 1 end
  local n = tonumber((p:read("*a") or ""):match("%d+"))
  p:close()
  return n or 1
end

--- The requested worker count: the flag if given, else the runner's own default, else 1.
local function jobsArg(default)
  local v = flagValue("--jobs") or flagValue("-j") or default
  if v == nil or v == 1 or v == "1" then return 1 end
  if v == "auto" then return math.max(1, cpuCount()) end
  local n = tonumber(v)
  if not n then
    error(("--jobs expects a number or `auto`; got %q"):format(tostring(v)), 0)
  end
  return math.max(1, math.floor(n))
end

--- The CONTIGUOUS slice `[first, last]` of `total` items belonging to shard `i` of `n`.
---
--- Contiguous, not round-robin, and that is the point: the driver relays shard 1's output, then
--- shard 2's, and so on, so a parallel run prints its cases in exactly the order a serial run
--- prints them. A gate whose output reshuffles every time it runs is a gate nobody diffs.
local function shardRange(total, i, n)
  local base, extra = math.floor(total / n), total % n
  local first = (i - 1) * base + math.min(i - 1, extra) + 1
  local count = base + ((i <= extra) and 1 or 0)
  return first, first + count - 1
end

local function out(line) io.write((line or ""), "\r\n") end

local function countIn(suite)
  local n = 0
  for _, t in ipairs(tests) do
    if t.suite == suite then n = n + 1 end
  end
  return n
end

local function renderInventory(suites)
  out("# Test Cases")
  out()
  out("The full inventory of every headless test case in this repo, grouped by the suite file it")
  out("lives in. The `## Totals` table below is the **authoritative pass count** — the README test")
  out("badge and any count quoted in the docs must agree with it.")
  out()
  out("**Generated — do not hand-edit.** Regenerate with `lua tests/run.lua --list > docs/test-cases.md`.")

  -- Declared-suite order, not first-seen and not sorted: the suite list is load-order-sensitive and
  -- the inventory should read the way the run reads.
  for _, entry in ipairs(suites) do
    local suite = suiteEntry(entry)
    local names = {}
    for _, t in ipairs(tests) do
      if t.suite == suite then
        -- A declared skip is disclosed in the inventory, so a reader of docs/test-cases.md sees
        -- that the case exists AND that it is not currently being evaluated.
        names[#names + 1] = t.skip and (t.name .. " (skipped: " .. t.skip .. ")") or t.name
      end
    end
    if #names > 0 then
      out()
      out(string.format("### %s.lua (%d)", suite, #names))
      out()
      for _, name in ipairs(names) do out("- " .. name) end
    end
  end

  out()
  out("## Totals")
  out()
  out("| Suite | Cases |")
  out("|-------|------:|")
  for _, entry in ipairs(suites) do
    local suite = suiteEntry(entry)
    local n = countIn(suite)
    if n > 0 then out(string.format("| %s.lua | %d |", suite, n)) end
  end
  out(string.format("| **Total** | **%d** |", #tests))
end

-- ── run ────────────────────────────────────────────────────────────────────────────────────

--- Load the suites, then either render the inventory or run everything.
--- opts = { dir = "tests/", suites = { ... }, suiteInventory = true }
--- Exits the process: 0 on success, 1 on any failure, so the green gate is a plain shell check.
---
--- `Kit.assertSuiteInventory` runs first whenever `opts.dir` is given EXPLICITLY — a runner that
--- discovers its own suites and passes no `dir` sits outside the assertion's premise and is left
--- alone. `suiteInventory = false` is the documented opt-out for a repo mid-migration; it is not a
--- setting to leave switched off.
--- Shell-quote one argument for `sh -c`.
local function shq(v)
  return "'" .. tostring(v):gsub("'", "'\\''") .. "'"
end

--- True when `os.execute` reached a POSIX shell (0 on 5.1, `true` on 5.2+).
local function posixShell()
  local ok = os.execute(":")
  return ok == 0 or ok == true
end

--- The count line a shard prints instead of the human summary, as a capture pattern.
local SHARD_PATTERN = "^" .. SHARD_MARKER .. " passed=(%d+) failed=(%d+) skipped=(%d+)$"

--- Launch `jobs` children, wait for all of them, and hand back the temp paths they wrote.
---
--- Every child is a plain re-invocation of the SAME runner with `--shard I/N` -- there is no worker
--- script and no second code path to keep in step. They are backgrounded from one `sh` and joined
--- with `wait`, because Lua 5.1 has no threads and `io.popen` blocks on read; each writes to its own
--- file so no two shards interleave mid-line.
local function spawnShards(interpreter, script, jobs)
  local outs, rcs, parts = {}, {}, {}
  for i = 1, jobs do
    outs[i], rcs[i] = os.tmpname(), os.tmpname()
    parts[i] = ("{ %s %s --shard %d/%d >%s 2>&1; echo $? >%s; } &")
      :format(shq(interpreter), shq(script), i, jobs, shq(outs[i]), shq(rcs[i]))
  end
  parts[#parts + 1] = "wait"
  os.execute(table.concat(parts, " "))
  return outs, rcs
end

--- Relay one shard's output verbatim and return `counts, exitCode`.
--- `counts` is nil when the shard never printed its count line, which means it did not finish.
local function drainShard(outPath, rcPath)
  local counts
  local outFile = io.open(outPath, "r")
  if outFile then
    for line in outFile:lines() do
      local passed, failed, skipped = line:match(SHARD_PATTERN)
      if passed then
        counts = {
          passed = tonumber(passed), failed = tonumber(failed), skipped = tonumber(skipped),
        }
      else
        print(line)
      end
    end
    outFile:close()
  end

  local rcFile = io.open(rcPath, "r")
  local code = rcFile and tonumber((rcFile:read("*a") or ""):match("%-?%d+"))
  if rcFile then rcFile:close() end

  os.remove(outPath)
  os.remove(rcPath)
  return counts, code
end

--- Add one shard's counts into the running tally.
local function addCounts(tally, counts)
  tally.passed  = tally.passed  + counts.passed
  tally.failed  = tally.failed  + counts.failed
  tally.skipped = tally.skipped + counts.skipped
end

--- Run this same script as `jobs` shard processes, relay their output in shard order, and return
--- the exit code the run should carry. Returns `nil, reason` when the platform cannot fan out, so
--- the caller can fall back to a serial run rather than reporting a failure that is really a
--- missing shell.
function Kit.runParallel(jobs)
  local interpreter, script = argv()[-1], argv()[0]
  if not interpreter then return nil, "the interpreter path is unknown (arg[-1] is unset)" end
  if not script then return nil, "this script's path is unknown (arg[0] is unset)" end
  if not posixShell() then return nil, "no POSIX shell to background workers from" end

  local outs, rcs = spawnShards(interpreter, script, jobs)
  local tally = { passed = 0, failed = 0, skipped = 0 }

  for i = 1, jobs do
    local counts, code = drainShard(outs[i], rcs[i])
    if counts then
      addCounts(tally, counts)
    else
      -- A shard that never printed its marker did not finish. Its cases are simply not in the
      -- totals, so the totals cannot be trusted and the run MUST go red -- this is the parallel
      -- runner's version of the silence `assertSuiteInventory` exists to prevent.
      tally.failed = tally.failed + 1
      print(("  FAIL  parallel runner\n          shard %d/%d produced no result line (exit %s) — "
        .. "it died before finishing, and its cases are missing from the totals below")
        :format(i, jobs, tostring(code)))
    end
  end

  print(string.format("\n%d passed, %d failed, %d skipped, %d total (%d shards)",
    tally.passed, tally.failed, tally.skipped,
    tally.passed + tally.failed + tally.skipped, jobs))
  return tally.failed == 0 and 0 or 1
end

--- Fan the suites out across processes and EXIT with the driver's code, when that is what was
--- asked for and is possible. Returns normally in every other case, so the caller falls through to
--- the serial path: `--jobs` not asked for, only one suite to split, `--list` (which must stay one
--- pure pass over one registry), or a platform with no shell to background workers from.
local function maybeFanOut(jobs, suites)
  if jobs <= 1 or wantsList() or #suites <= 1 then return end

  local code, why = Kit.runParallel(math.min(jobs, #suites))
  if code then os.exit(code) end
  print("  NOTE  --jobs asked for workers but this platform cannot fan out ("
    .. tostring(why) .. "); running serially")
end

--- The set of suite names this process owns, or nil for "all of them".
local function ownedSuites(suites, shardIndex, shardCount)
  if not shardIndex then return nil end
  local mine = {}
  local first, last = shardRange(#suites, shardIndex, shardCount)
  for i = first, last do
    mine[tostring((suiteEntry(suites[i])))] = true
  end
  return mine
end

--- Whether this process runs case `t`.
---
--- A case with no suite was registered outside a suite file; shard 1 owns it, so it runs exactly
--- once across the whole fan-out rather than once per shard or not at all.
local function ownedHere(t, mine, shardIndex)
  if not mine then return true end
  if t.suite == nil then return shardIndex == 1 end
  return mine[t.suite] == true
end

--- Run one case, print its line, and return "passed", "failed" or "skipped".
local function runCase(t)
  if t.skip then
    print("  SKIP  " .. t.name .. " — " .. t.skip)
    return "skipped"
  end

  local ok, err = pcall(t.fn)
  local reason = (not ok) and skipReasonOf(err) or nil
  if reason then
    print("  SKIP  " .. t.name .. " — " .. reason)
    return "skipped"
  end
  if ok then
    print("  PASS  " .. t.name)
    return "passed"
  end

  print("  FAIL  " .. t.name .. "\n          " .. tostring(err))
  return "failed"
end

--- Run every case this process owns, and return the tally.
local function runOwned(mine, shardIndex)
  local tally = { passed = 0, failed = 0, skipped = 0 }
  for _, t in ipairs(tests) do
    if ownedHere(t, mine, shardIndex) then
      local status = runCase(t)
      tally[status] = tally[status] + 1
    end
  end
  return tally
end

--- The closing line. A shard prints the machine-readable marker the driver adds up; a plain run
--- prints the human summary. Skips are their own column and are NEVER folded into `passed`.
local function reportTotals(tally, shardIndex)
  if shardIndex then
    print(("%s passed=%d failed=%d skipped=%d")
      :format(SHARD_MARKER, tally.passed, tally.failed, tally.skipped))
  else
    print(string.format("\n%d passed, %d failed, %d skipped, %d total",
      tally.passed, tally.failed, tally.skipped,
      tally.passed + tally.failed + tally.skipped))
  end
end

--- Load the suites, then either render the inventory or run everything.
--- opts = { dir = "tests/", suites = { ... }, suiteInventory = true, jobs = 1 }
--- Exits the process: 0 on success, 1 on any failure, so the green gate is a plain shell check.
---
--- A suites entry is a basename, `{ name = ..., pending = "why" }`, or `{ name = ..., dir = ... }`
--- for a suite that ships in the vendored kit rather than in `opts.dir` — see `suiteEntry`.
---
--- `Kit.assertSuiteInventory` runs first whenever `opts.dir` is given EXPLICITLY -- a runner that
--- discovers its own suites and passes no `dir` sits outside the assertion's premise and is left
--- alone. `suiteInventory = false` is the documented opt-out for a repo mid-migration; it is not a
--- setting to leave switched off.
---
--- `opts.jobs` is the runner's own default worker count (`1`, a number, or `"auto"`); `--jobs` on
--- the command line overrides it either way. Parallelism is OPT-IN per repo because splitting the
--- suites across processes also splits the process-wide state they share -- the `shared` instance,
--- the SavedVariables globals -- so a suite that quietly depended on another suite having run first
--- fails only once it is switched on. That dependency was always a bug; `--jobs` is what makes it
--- visible, and it should be switched on deliberately, with the run verified green.
function Kit.run(opts)
  local dir    = opts.dir or "tests/"
  local suites = opts.suites or {}

  local shardIndex, shardCount = shardArg()
  -- A shard NEVER spawns shards. Whatever default the runner carries, a child runs its slice
  -- serially -- otherwise `jobs = "auto"` in a consumer's run.lua forks a process tree.
  local jobs = shardIndex and 1 or jobsArg(opts.jobs)

  if opts.dir and opts.suiteInventory ~= false then
    Kit.assertSuiteInventory(dir, suites)
  end

  -- The parallel driver, before any suite is loaded so the parent does no registration work.
  -- Never in `--list` mode: the inventory must stay one pure pass over one registry.
  maybeFanOut(jobs, suites)

  loadSuites(dir, suites)

  if wantsList() then
    renderInventory(suites)
    os.exit(0)
  end

  local tally = runOwned(ownedSuites(suites, shardIndex, shardCount), shardIndex)
  reportTotals(tally, shardIndex)
  os.exit(tally.failed == 0 and 0 or 1)
end


--- The shard partitioner, for the kit's own self-tests. An off-by-one here silently drops or
--- double-runs whole suites while the totals still look plausible, so it is pinned directly.
Kit.__shardRange = shardRange

--- The live registry, for the kit's own self-tests.
function Kit.__tests() return tests end

return Kit
