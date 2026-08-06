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
Kit.VERSION = 8

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

--- Assert that a degraded-path stub carries the whole surface of the live module.
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
  label = label or "surface"
  if type(live) ~= "table" then fail(label .. ": the live surface is not a table", 1) end
  if type(degraded) ~= "table" then fail(label .. ": the degraded surface is not a table", 1) end

  local skip = {}
  for k, v in pairs(ignore or {}) do
    if v == true then skip[k] = true else skip[v] = true end
  end

  local keys = {}
  for k in pairs(live) do
    if not skip[k] then keys[#keys + 1] = k end
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
  return t
end

-- ── suite loading ──────────────────────────────────────────────────────────────────────────

local function fileExists(path)
  local f = io.open(path, "r")
  if f then f:close(); return true end
  return false
end

--- A suites entry is either a plain basename or `{ name = "test_foo", pending = "why" }`.
local function suiteEntry(entry)
  if type(entry) == "table" then return entry.name, entry.pending end
  return entry, nil
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
    local name, pending = suiteEntry(entry)
    local path = dir .. tostring(name) .. ".lua"
    currentSuite = name
    if pending then
      if fileExists(path) then
        error(("suite inventory: %s is declared `pending = %q` (position %d in the suites list) but "
          .. "the file exists — drop the `pending` field so its cases actually run")
          :format(path, tostring(pending), i), 0)
      end
      Kit.test(tostring(name) .. ".lua: suite not written yet", nil, tostring(pending))
    elseif fileExists(path) then
      dofile(path)
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
function Kit.assertSuiteInventory(dir, suites)
  dir = dir or "tests/"
  local declared, order, pending = {}, {}, {}
  for i, entry in ipairs(suites or {}) do
    local name, why = suiteEntry(entry)
    declared[tostring(name)] = i
    order[#order + 1] = tostring(name)
    -- A `pending` entry is declared-and-deliberately-absent. Demanding it be on disk would make the
    -- write-in-progress affordance unreachable, which is the whole point of keeping it. The other
    -- direction still binds: if the file DOES appear, `loadSuites` raises rather than skipping it.
    if why then pending[tostring(name)] = true end
  end

  local onDisk, listed = suiteFilesOn(dir)
  if listed == 0 then
    fail("suite inventory: could not list " .. dir .. " — no `ls -A` and no `dir /b`; this gate "
      .. "cannot run, and must not be reported as passing", 2)
  end
  local present = {}
  for _, name in ipairs(onDisk) do present[name] = true end

  local problems = {}
  for i, name in ipairs(order) do
    if not present[name] and not pending[name] then
      problems[#problems + 1] = ("%s%s.lua is declared in the suites list (position %d) but is not "
        .. "on disk — delete the entry or write the file"):format(dir, name, i)
    end
  end
  for _, name in ipairs(onDisk) do
    if not declared[name] then
      problems[#problems + 1] = ("%s%s.lua exists but is not declared in the suites list — add %q "
        .. "to the runner; it is running zero cases today"):format(dir, name, name)
    end
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

local function wantsList()
  for _, a in ipairs(arg or {}) do
    if a == "--list" then return true end
  end
  return false
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
function Kit.run(opts)
  local dir    = opts.dir or "tests/"
  local suites = opts.suites or {}

  if opts.dir and opts.suiteInventory ~= false then
    Kit.assertSuiteInventory(dir, suites)
  end

  loadSuites(dir, suites)

  if wantsList() then
    renderInventory(suites)
    os.exit(0)
  end

  local passed, failed, skipped = 0, 0, 0
  for _, t in ipairs(tests) do
    if t.skip then
      skipped = skipped + 1
      print("  SKIP  " .. t.name .. " — " .. t.skip)
    else
      local ok, err = pcall(t.fn)
      local reason = (not ok) and skipReasonOf(err) or nil
      if reason then
        skipped = skipped + 1
        print("  SKIP  " .. t.name .. " — " .. reason)
      elseif ok then
        passed = passed + 1
        print("  PASS  " .. t.name)
      else
        failed = failed + 1
        print("  FAIL  " .. t.name .. "\n          " .. tostring(err))
      end
    end
  end
  -- Skips are their own column and are NOT added to `passed`; the exit code is still `failed == 0`.
  print(string.format("\n%d passed, %d failed, %d skipped, %d total",
    passed, failed, skipped, passed + failed + skipped))
  os.exit(failed == 0 and 0 or 1)
end

--- The live registry, for the kit's own self-tests.
function Kit.__tests() return tests end

return Kit
