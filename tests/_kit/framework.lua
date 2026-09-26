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
Kit.VERSION = 31

-- ── the resource guard (kit revision 23) ───────────────────────────────────────────────────────
--
-- A headless run can take the whole machine down with it, and in this collection one did: a stray
-- probe registered in a runner made a `lua tests/run.lua --list` child start another child, which
-- started another, each ~700 MB, until the kernel's OOM killer took the VM (and the editor session
-- driving it) with them. A per-process `ulimit -v` would NOT have stopped that -- every link in the
-- chain fitted under any sensible cap -- so the guard bounds the chain and the tree, not only the
-- process:
--
--   * DEPTH. Every guarded process re-launches itself once with `KA0S_KIT_DEPTH` one higher than
--     it found it. Nothing downstream has to cooperate: a suite that shells out to the runner
--     through a bare `io.popen` still produces a child that loads this file, reads the variable its
--     parent exported, and refuses past `KA0S_KIT_MAX_DEPTH` (default 4) with exit 3.
--   * TREE MEMORY. The outermost process (depth 1) runs inside a `systemd-run --user --scope` with
--     `MemoryMax` (`KA0S_KIT_TREE_MB`, default half of RAM) and `TasksMax` (`KA0S_KIT_TASKS`, 256),
--     so a runaway tree is killed as ONE unit by its own cgroup rather than by the kernel choosing
--     among everything on the machine. Skipped silently where systemd is absent.
--   * PROCESS MEMORY. `ulimit -v` (`KA0S_KIT_PROC_MB`, default 2048) on every process. Lua 5.1
--     answers an allocation over the limit with a catchable "not enough memory", so the case that
--     crossed it fails with a name instead of the process dying.
--   * WALL CLOCK. `timeout --foreground` (`KA0S_KIT_TIMEOUT_S`, default 900) on every process.
--     `--foreground` keeps Ctrl-C working; a grandchild is still bounded, by its own guard.
--
-- `KA0S_KIT_GUARD=off` disables all four -- for a debugger, never for a gate. `KA0S_KIT_CGROUP=off`
-- drops only the scope. A limit of 0 drops that limit.
--
-- The re-launch happens when this file LOADS, which is the first thing every runner does, so a
-- consumer adopts the guard by re-vendoring and changes nothing in its own code. It is idempotent
-- within a process (a suite that `dofile`s the kit again gets the kit, not a second run), and the
-- re-launched process knows it is the guarded one by a marker ARGUMENT, which unlike an environment
-- variable is not inherited by the children it goes on to start.

local GUARD_FLAG = "--kit-guarded"
local GUARD_LOADED = "ka0s.testkit.guard"

local function envNumber(name, default)
  local v = tonumber(os.getenv(name) or "")
  if v == nil then return default end
  return v
end

--- MemTotal and MemAvailable in MB, from /proc/meminfo; nil, nil where there is none.
local function meminfoMB()
  local f = io.open("/proc/meminfo", "r")
  if not f then return nil, nil end
  local text = f:read("*a") or ""
  f:close()
  local total = tonumber(text:match("MemTotal:%s+(%d+)"))
  local avail = tonumber(text:match("MemAvailable:%s+(%d+)"))
  return total and math.floor(total / 1024), avail and math.floor(avail / 1024)
end

--- The guard's limits, resolved from the environment.
local function guardSettings()
  local totalMB = meminfoMB()
  return {
    depth    = envNumber("KA0S_KIT_DEPTH", 0),
    maxDepth = envNumber("KA0S_KIT_MAX_DEPTH", 4),
    procMB   = envNumber("KA0S_KIT_PROC_MB", 2048),
    treeMB   = envNumber("KA0S_KIT_TREE_MB", totalMB and math.floor(totalMB / 2) or 8192),
    tasks    = envNumber("KA0S_KIT_TASKS", 256),
    seconds  = envNumber("KA0S_KIT_TIMEOUT_S", 900),
    cgroup   = os.getenv("KA0S_KIT_CGROUP") ~= "off",
  }
end

local function guardQuote(v)
  return "'" .. (tostring(v):gsub("'", "'\\''")) .. "'"
end

--- True when `cmd` exits 0 under `sh`, on 5.1 (a status number) and 5.2+ (a boolean) alike.
local function shellOk(cmd)
  local ok = os.execute(cmd)
  return ok == 0 or ok == true
end

--- The exit code `os.execute` reports, normalized: 5.1 hands back a wait status, 5.2+ a triple.
--- A child killed by signal N reports 128 + N, as a shell would.
local function exitCodeOf(a, how, n)
  if type(a) == "number" then
    if a % 256 == 0 then return a / 256 end
    return 128 + a % 128
  end
  if how == "signal" then return 128 + (n or 0) end
  return n or (a and 0 or 1)
end

--- The command line that re-launches this process under the guard, or nil when it cannot be built.
--- Every argument below index 1 (the interpreter and its own options) and the script are kept, the
--- marker goes right after the script, and the script's own arguments follow unchanged.
local function guardedCommand(a, s)
  local lowest = 0
  while a[lowest - 1] ~= nil do lowest = lowest - 1 end
  if lowest == 0 then return nil end
  local parts = {}
  for i = lowest, 0 do parts[#parts + 1] = guardQuote(a[i]) end
  parts[#parts + 1] = GUARD_FLAG
  for i = 1, #a do parts[#parts + 1] = guardQuote(a[i]) end

  local depth = s.depth + 1
  local prefix = ""
  if s.seconds > 0 and shellOk("command -v timeout >/dev/null 2>&1") then
    prefix = ("timeout --foreground -k 10 %d "):format(s.seconds)
  end
  if depth == 1 and s.cgroup and s.treeMB > 0
    and shellOk("systemd-run --user --scope --quiet --collect true >/dev/null 2>&1") then
    prefix = ("systemd-run --user --scope --quiet --collect -p MemoryMax=%dM -p MemorySwapMax=0 "
      .. "-p TasksMax=%d %s"):format(s.treeMB, s.tasks, prefix)
  end
  local ulimit = s.procMB > 0 and ("ulimit -v %d 2>/dev/null; "):format(s.procMB * 1024) or ""
  return ("%sKA0S_KIT_DEPTH=%d exec %s%s"):format(ulimit, depth, prefix, table.concat(parts, " "))
end

--- Explain an exit the guard itself caused, on stderr, so a killed run never reads as a test failure.
local function explainGuardExit(code, s)
  if code == 124 then
    io.stderr:write(("kit guard: the run went past its %d s wall-clock limit and was stopped "
      .. "(KA0S_KIT_TIMEOUT_S raises it)\n"):format(s.seconds))
  elseif code == 137 then
    io.stderr:write(("kit guard: the run was killed (SIGKILL) -- most likely by its memory limit, "
      .. "%d MB for the whole process tree (KA0S_KIT_TREE_MB). A suite that needs that much is "
      .. "usually holding instances it no longer uses\n"):format(s.treeMB))
  end
end

--- Re-launch this process under the guard and exit with its code, or return to run unguarded.
local function guardProcess()
  if package.loaded[GUARD_LOADED] then return end
  package.loaded[GUARD_LOADED] = true
  if os.getenv("KA0S_KIT_GUARD") == "off" then return end

  local a = rawget(_G, "arg")
  if type(a) ~= "table" or type(a[0]) ~= "string" then return end
  if a[1] == GUARD_FLAG then
    table.remove(a, 1)
    return
  end
  if not shellOk(":") then return end

  local s = guardSettings()
  if s.maxDepth > 0 and s.depth + 1 > s.maxDepth then
    io.stderr:write(("kit guard: refusing to start %s at process depth %d (limit %d, "
      .. "KA0S_KIT_MAX_DEPTH). A runner is re-launching itself in a chain -- look for a suite, or a "
      .. "stray file a runner loads, that starts `lua tests/run.lua` as it loads\n")
      :format(a[0], s.depth + 1, s.maxDepth))
    os.exit(3)
  end

  local cmd = guardedCommand(a, s)
  if not cmd then return end
  io.stdout:flush()
  local code = exitCodeOf(os.execute(cmd))
  explainGuardExit(code, s)
  os.exit(code)
end

guardProcess()

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

-- ── assertions and the surface-parity gate ─────────────────────────────────────────────────
--
-- In `asserts.lua` beside this file since kit revision 26, which took this file back under
-- `layout-§1`'s cap; loaded once, here, where the block used to stand, so every member is on the kit
-- table before `Kit.expose` copies it. The folder is found from this chunk's own name, the way
-- `mock_base.lua` finds `mock_record.lua`, with the vendored layout as the fallback for a loader
-- that rewrites chunk names. A missing file raises: a kit with no assertions cannot fail a case.

local function kitFolder()
  local info = debug and debug.getinfo and debug.getinfo(1, "S")
  local dir = info and tostring(info.source or ""):match("^@(.*[/\\])")
  local f = dir and io.open(dir .. "asserts.lua", "r")
  if f then f:close(); return dir end
  return "tests/_kit/"
end

local asserts = dofile(kitFolder() .. "asserts.lua")(Kit)
local fail = asserts.fail

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
  t.assertErrorMatches = Kit.assertErrorMatches
  t.assertLibraryConstant = Kit.assertLibraryConstant
  t.assertSuiteInventory = Kit.assertSuiteInventory
  t.assertSurfaceParity  = Kit.assertSurfaceParity
  t.publicMembers        = Kit.publicMembers
  t.setSurfaceSource     = Kit.setSurfaceSource

  -- The by-name form needs somewhere to look, and every harness in this collection that stubs a
  -- LIBRARY TABLE already has it: the mock it just built. Wired here rather than demanded of the
  -- runner so that adoption is the case alone, and only when nothing is registered yet — a repo
  -- that called setSurfaceSource itself (because its stubs mirror instances) keeps its own. The
  -- same LibStub is always recorded as `assertLibraryConstant`'s fallback, since such a repo's
  -- source answers an instance, and a lib-level constant is not on it.
  local mock = t.mocks or t.mock
  local ls = t.LibStub or (type(mock) == "table" and mock.LibStub) or nil
  if ls then asserts.setLibraryFallback(ls) end
  if ls and asserts.surfaceSource() == nil then Kit.setSurfaceSource(ls) end
  return t
end

-- ── suite loading ──────────────────────────────────────────────────────────────────────────

-- The path helpers the loader below keys on, and the suite inventory, are in `inventory.lua` beside
-- this file since kit revision 28, which took this file out of `layout-§1`'s 1000–1500 band; loaded
-- once, here, where the helpers used to stand, so `Kit.assertSuiteInventory` is on the kit table
-- before `Kit.expose` copies it and every caller below reads the same functions it did.
local inventory = dofile(kitFolder() .. "inventory.lua")(Kit, fail)
local fileExists, normDir, rootOf = inventory.fileExists, inventory.normDir, inventory.rootOf
local resolveDir, adviceDir = inventory.resolveDir, inventory.adviceDir
local suiteEntry = inventory.suiteEntry

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
--- The first absolute path on a developer's machine that `source` names, or nil.
---
--- A suite reads the repository through the runner's `root`, never through a host path. The one
--- file in this collection that did -- a scratch probe pointing into a sibling checkout -- is the one
--- that took a machine down, and a host path is the tell a probe leaves behind that a real suite
--- never has. Matched on shapes no WoW path can take: a WSL drive mount, a Linux or macOS home, a
--- Windows profile.
local HOST_PATHS = { "/mnt/%a/", "/home/[%w_%.%-]+/", "/Users/[%w_%.%-]+/", "%a:[\\/]Users[\\/]" }

local function hostPathIn(source)
  for _, pattern in ipairs(HOST_PATHS) do
    local at = source:find(pattern)
    if at then return (source:match("[^%s\"'`]*", at)) end
  end
  return nil
end

--- Resource limits the runner holds every case and every suite load to (kit revision 23), resolved
--- in Kit.run from `opts` and then the environment, which wins so an operator can raise one for a
--- single run without editing a runner.
local limits = { heapMB = 1024, leakMB = 256, caseSeconds = 120 }

local BOUNDED_EXEMPT = {}

--- Put the hook that was in place back, then hand pcall's results through untouched. Exempt from
--- the ceiling (as `pcallBounded` is): it runs after the body returned, and raising there would
--- fail a case that finished in time.
local function restoreHook(saved, ...)
  if saved[1] then debug.sethook(saved[1], saved[2], saved[3]) else debug.sethook() end
  return ...
end

--- Call `fn` with a CPU-time ceiling of `seconds`, returning pcall's results.
---
--- A count hook, checked every million VM instructions, raises once the ceiling is passed -- and
--- from then on fires on EVERY instruction, so a body that swallows the error with its own pcall
--- still cannot outrun it: the first instruction it runs outside that pcall raises again. (At a
--- million-instruction interval it could: nearly every firing lands inside the inner pcall.)
--- It bounds a runaway Lua loop inside one case, which the process-level timeout would otherwise
--- only catch by killing the whole run with no name attached. Not a wall clock: time spent blocked
--- in a child process is not counted, and the process-level timeout covers that.
local function pcallBounded(seconds, fn, ...)
  if not seconds or seconds <= 0 or not debug or not debug.sethook then return pcall(fn, ...) end
  local saved = { debug.gethook() }
  local deadline, expired = os.clock() + seconds, false
  local function hook()
    if not expired then
      if os.clock() <= deadline then return end
      expired = true
      debug.sethook(hook, "", 1)
    end
    local running = debug.getinfo(2, "f")
    if running and BOUNDED_EXEMPT[running.func] then return end
    error(("kit limit: went past its %d s CPU ceiling (KA0S_KIT_CASE_S) -- a loop that "
      .. "never ends, or a case doing far more work than a unit case should"):format(seconds), 2)
  end
  debug.sethook(hook, "", 1000000)
  return restoreHook(saved, pcall(fn, ...))
end
BOUNDED_EXEMPT[pcallBounded], BOUNDED_EXEMPT[restoreHook] = true, true

local function loadSuites(dir, suites)
  -- Normalized here rather than at the call site: `Kit.__loadSuites` is driven directly by the
  -- kit's own self-tests, and a normalizer only `Kit.run` applied would be one a self-test could
  -- not hold it to.
  dir = normDir(dir)
  for i, entry in ipairs(suites) do
    local name, pending, entryDir = suiteEntry(entry)
    local entryPath = resolveDir(entryDir, dir)
    local path = entryPath .. tostring(name) .. ".lua"
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
      local f = io.open(path, "r")
      local hostPath = f and hostPathIn(f:read("*a") or "")
      if f then f:close() end
      if hostPath then
        error(("suite %s names a path on this machine (%s) -- a suite reaches the repo through the "
          .. "runner's root, never through a host path. A scratch probe belongs in a scratch "
          .. "directory, not in tests/"):format(path, hostPath), 0)
      end
      local chunk, err = loadfile(path)
      if not chunk then error(err, 0) end
      -- A suite file REGISTERS cases and does nothing else, so its load gets the same CPU ceiling a
      -- case does: a file that does its work at load time fails here, by name.
      local ok, loadErr = pcallBounded(limits.caseSeconds, chunk, Kit)
      if not ok then error(loadErr, 0) end
    else
      -- The pair key again (kit revision 25): the commonest way to reach this branch is a bare
      -- entry for a suite that ships in the kit, and the fix is the `dir` rather than a new file.
      local kitDir, hint = dir .. "_kit/", ""
      if entryPath ~= kitDir and fileExists(kitDir .. tostring(name) .. ".lua") then
        -- The first `%s` is a DIAGNOSTIC -- where the file actually is, resolved. The `dir = %q` is
        -- ADVICE, and advice is printed in the spelling a suites list has to carry (`adviceDir`).
        local advice, note = adviceDir(kitDir, rootOf(dir))
        hint = (" — %s%s.lua DOES exist, so this entry wants { name = %q, dir = %q }%s")
          :format(kitDir, tostring(name), tostring(name), advice, note)
      end
      error(("suite inventory: %s is declared in the suites list (position %d) but is not on disk "
        .. "— delete the entry or write the file%s; to keep it listed while it is being written, "
        .. "declare it as { name = %q, pending = \"why\" } so it registers as a skip rather than "
        .. "as nothing"):format(path, i, hint, tostring(name)), 0)
    end
  end
  currentSuite = nil
end

-- ── `--list` ───────────────────────────────────────────────────────────────────────────────
--
-- Emits the whole body of docs/test-cases.md, CRLF-terminated, and exits 0 without running a
-- single case. CRLF is written HERE rather than left to a `| sed 's/$/\r/'` in the shell: the
-- repos pin `*.md text eol=crlf`, a plain redirect writes LF, and a regeneration command with a
-- pipeline in it is one someone eventually runs without the pipeline.

-- ── the command line ───────────────────────────────────────────────────────────────────────
--
-- Four flags, all parsed here so `--list` and the shard driver read the same argv the same way:
--
--   --list          render the inventory and exit, running nothing
--   --layout-cap-exempt PATH...  name the PATHs `Kit.layoutCap.exempt` covers and exit (revision 31)
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

--- `jobs` capped by memory: no more workers than three quarters of the available memory holds at
--- `perMB` each (kit revision 23). `--jobs auto` used to mean one worker per CPU whatever each one
--- weighed, and sixteen workers of a heavy suite is more than a laptop's memory. Unchanged when the
--- available figure is unknown.
local function memoryCappedJobs(jobs, availMB, perMB)
  if jobs <= 1 or not availMB or not perMB or perMB <= 0 then return jobs end
  return math.max(1, math.min(jobs, math.floor(availMB * 0.75 / perMB)))
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

  -- Cases the RUNNER registered rather than a suite file — today, a declined kit gate (kit revision
  -- 25). They are emitted first, because that is when they run, and they are emitted at all because
  -- the `## Totals` line counts the whole registry: a case in no group would make the table's rows
  -- and its own total disagree, which is a worse way to lose a decline than never printing it.
  local loose = {}
  for _, t in ipairs(tests) do
    if t.suite == nil then
      loose[#loose + 1] = t.skip and (t.name .. " (skipped: " .. t.skip .. ")") or t.name
    end
  end
  if #loose > 0 then
    out()
    out(string.format("### the runner (%d)", #loose))
    out()
    for _, name in ipairs(loose) do out("- " .. name) end
  end

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
  if #loose > 0 then out(string.format("| the runner | %d |", #loose)) end
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

  local ok, err = pcallBounded(limits.caseSeconds, t.fn)
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

--- The live heap in MB after a full collection, which is what a budget is judged against:
--- `collectgarbage("count")` alone includes garbage not yet swept.
local function liveHeapMB()
  collectgarbage("collect")
  return collectgarbage("count") / 1024
end

--- The failure message when the heap is over `budgetMB` above `baseMB`, or nil. Collects only when
--- the cheap reading is already over, so a run inside its budget never pays for a full collection.
local function overBudget(baseMB, budgetMB)
  if budgetMB <= 0 or collectgarbage("count") / 1024 - baseMB <= budgetMB then return nil end
  local live = liveHeapMB()
  if live - baseMB <= budgetMB then return nil end
  return live
end

--- The leak gate, checked when the run leaves a suite: the LIVE heap may not end up more than
--- `limits.leakMB` above where it started. A harness that builds an instance per case and never
--- lets one go grows by a constant per case, which no single case notices and a whole run turns into
--- gigabytes -- one consumer held 685 MB of instances it had finished with. Reported once, against
--- the suite the run was in when it crossed, which is where the retaining starts to show.
local function leakFailure(baseMB, suite)
  local live = overBudget(baseMB, limits.leakMB)
  if not live then return nil end
  return ("  FAIL  leak gate\n          after %s.lua the live heap is %.0f MB, %.0f MB above where the "
    .. "run started (budget %d MB, KA0S_KIT_LEAK_MB) -- something is still holding instances or "
    .. "fixtures the finished cases no longer use"):format(tostring(suite), live, live - baseMB,
      limits.leakMB)
end

--- The heap budget, checked after every case: an absolute ceiling on the live heap, so a runaway
--- allocation fails the case that made it, by name, long before the process limit is reached.
local function heapFailure(t)
  local live = overBudget(0, limits.heapMB)
  if not live then return nil end
  return ("  FAIL  heap budget\n          after \"%s\" the live heap is %.0f MB, over the %d MB "
    .. "budget (KA0S_KIT_HEAP_MB); the run stops here rather than let one process take the "
    .. "machine's memory"):format(t.name, live, limits.heapMB)
end

--- Run every case this process owns, and return the tally.
local function runOwned(mine, shardIndex)
  local tally = { passed = 0, failed = 0, skipped = 0 }
  local baseMB, suite, leakReported = liveHeapMB(), nil, false
  local function checkLeak()
    if leakReported or suite == nil then return end
    local failure = leakFailure(baseMB, suite)
    if failure then
      print(failure)
      tally.failed, leakReported = tally.failed + 1, true
    end
  end
  for _, t in ipairs(tests) do
    if ownedHere(t, mine, shardIndex) then
      if t.suite ~= suite then
        checkLeak()
        suite = t.suite
      end
      local status = runCase(t)
      tally[status] = tally[status] + 1
      local heap = heapFailure(t)
      if heap then
        print(heap)
        tally.failed = tally.failed + 1
        return tally
      end
    end
  end
  checkLeak()
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

-- ── `--layout-cap-exempt` (kit revision 31) ────────────────────────────────────────────────
--
-- layout-§1's second carve-out, generated non-shipping data, is a fact about the repository that
-- no path betrays, so it arrives as `Kit.layoutCap.exempt` in the consumer's `tests/run.lua`, and
-- `test_layout_cap.lua` reads it there. `run-automated-tests.sh` writes the same rule's band table
-- and has to leave out the same files; a second list, or a second matching rule typed into the
-- shell, is a copy that drifts. So the runner asks this file instead:
--
--   lua tests/run.lua --layout-cap-exempt PATH...
--
-- prints `layout-cap-exempt<TAB>PATH` for each PATH the exempt set covers and exits 0 without
-- loading a suite. The marker is there so nothing a runner prints while it sets up can be read as
-- an answer. The matching rule below is the one the cap gate calls, through `Kit.__layoutCapCovers`.

--- True when the exempt entry `entry` covers `path`: the path itself, or a folder containing it.
---
--- Globs are not expanded. An entry that would only match through one matches nothing, which errs
--- toward reporting a breach rather than toward excusing a file nobody meant to excuse.
local function layoutCapCovers(entry, path)
  if entry == path then return true end
  local folder = (entry:sub(-1) == "/") and entry or (entry .. "/")
  return path:sub(1, #folder) == folder
end

--- The string entries of `Kit.layoutCap.exempt`, read from an array, a map of path to true, or
--- both. A malformed table or entry is `test_layout_cap.lua`'s to fail by name; here it covers nothing.
local function layoutCapEntries()
  local o = Kit.layoutCap
  local entries = type(o) == "table" and o.exempt or nil
  local list = {}
  if type(entries) ~= "table" then return list end
  for key, value in pairs(entries) do
    local entry = (type(key) == "number") and value or (value and key)
    if type(entry) == "string" then list[#list + 1] = entry end
  end
  return list
end

--- Print, behind the marker, every argument after `--layout-cap-exempt` that an entry covers.
local function printLayoutCapExempt()
  local entries, after = layoutCapEntries(), false
  for _, path in ipairs(argv()) do
    if after then
      for _, entry in ipairs(entries) do
        if layoutCapCovers(entry, path) then print("layout-cap-exempt\t" .. path); break end
      end
    elseif path == "--layout-cap-exempt" then
      after = true
    end
  end
end

--- Load the suites, then either render the inventory or run everything.
--- opts = { dir = "tests/", suites = { ... }, suiteInventory = true, jobs = 1 }
--- `--layout-cap-exempt PATH...` answers the runner's carve-out question and exits first (above).
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
  if hasFlag("--layout-cap-exempt") then
    printLayoutCapExempt()
    os.exit(0)
  end

  local dir    = opts.dir or "tests/"
  local suites = opts.suites or {}

  local shardIndex, shardCount = shardArg()
  -- A shard NEVER spawns shards. Whatever default the runner carries, a child runs its slice
  -- serially -- otherwise `jobs = "auto"` in a consumer's run.lua forks a process tree.
  local jobs = shardIndex and 1 or jobsArg(opts.jobs)
  local _, availMB = meminfoMB()
  jobs = memoryCappedJobs(jobs, availMB, envNumber("KA0S_KIT_SHARD_MB", 512))

  limits.heapMB      = envNumber("KA0S_KIT_HEAP_MB", opts.heapBudgetMB or 1024)
  limits.leakMB      = envNumber("KA0S_KIT_LEAK_MB", opts.leakBudgetMB or 256)
  limits.caseSeconds = envNumber("KA0S_KIT_CASE_S", opts.caseSeconds or 120)

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

--- layout-§1's generated-data matching rule (kit revision 31). Internal like the rest of this block,
--- but not only for self-tests: `test_layout_cap.lua` calls it, so the gate and the runner's
--- `--layout-cap-exempt` answer can never match an exempt entry two different ways.
Kit.__layoutCapCovers = layoutCapCovers

--- The live registry, for the kit's own self-tests.
function Kit.__tests() return tests end

--- The resource-limit internals (kit revision 23), for the kit's own self-tests.
Kit.__hostPathIn       = hostPathIn
Kit.__pcallBounded     = pcallBounded
Kit.__memoryCappedJobs = memoryCappedJobs
Kit.__exitCodeOf       = exitCodeOf
Kit.__limits           = limits
Kit.__leakFailure      = leakFailure
Kit.__heapFailure      = heapFailure

--- The suite-inventory internals (kit revision 25), for the kit's own self-tests. The decline
--- reader above all: it is the one path in the inventory that can turn a failure into a skip, so
--- what it does and does not accept is pinned directly rather than inferred from a green run.
Kit.__loadSuites    = loadSuites
Kit.__normDir       = normDir
Kit.__resolveDir    = resolveDir
Kit.__adviceDir     = adviceDir
Kit.__deviationRows = inventory.deviationRows
Kit.__declineFor    = inventory.declineFor
Kit.__kitGateRule   = inventory.kitGateRule

return Kit
