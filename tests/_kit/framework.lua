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
Kit.VERSION = 27

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
-- Kit gates the repository has declined, by the RESOLVED path of the declined suite, so a second
-- call to `Kit.assertSuiteInventory` reports it once rather than twice (kit revision 25). Resolved
-- and not root-relative, which this file otherwise prefers: the key has to tell two REPOSITORIES
-- apart inside one process, and `tests/_kit/test_prose` is the same string in all of them -- the
-- kit's own inventory fixtures, a fresh temporary tree per case, are where that is provable. The
-- case NAME below is root-relative all the same, and for the opposite reason.
local declinesReported = {}

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

local function assertsFolder()
  local info = debug and debug.getinfo and debug.getinfo(1, "S")
  local dir = info and tostring(info.source or ""):match("^@(.*[/\\])")
  local f = dir and io.open(dir .. "asserts.lua", "r")
  if f then f:close(); return dir end
  return "tests/_kit/"
end

local asserts = dofile(assertsFolder() .. "asserts.lua")(Kit)
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

local function fileExists(path)
  local f = io.open(path, "r")
  if f then f:close(); return true end
  return false
end

--- A directory path in the ONE spelling this gate compares and keys on (kit revision 25).
---
--- Two runners in this collection resolve their own root out of `arg[0]` and fall back to `"."`,
--- so the same directory reaches the kit twice in two spellings: `./tests/_kit/` from the runner's
--- `dir`, and `tests/_kit/` from the declaration, which is the literal form `testing-§9` prescribes.
--- Raw string inequality reads those as two different directories, and the pair key, as it was
--- first written, reported a COLLISION against a repo that had done exactly what the rule asks --
--- with a remedy that said to delete a vendored file. It failed from `Kit.run`, so the whole suite
--- aborted and no case ran, and `--list` aborted with it, so the repo could not even regenerate
--- `docs/test-cases.md`. Caught before the revision shipped; two consumers were already in it.
---
--- LEXICAL, NOT RESOLVED, and that is a choice rather than a shortcut. Lua 5.1 has no `stat`,
--- nothing in this collection depends on LuaFileSystem, and the shell-outs that could answer file
--- identity (`realpath`, `cd && pwd`) cost a process per comparison, are absent on the cmd.exe
--- fallback this file already carries a listing path for, and resolve symlinks that the runner's
--- own `dir` does not -- a kit that followed a symlink to decide two declarations were the same
--- suite would be inventing an answer the runner never uses. Every spelling this collection
--- actually produces differs by a `./` prefix, a doubled slash or a missing trailing slash, and all
--- three are decidable without touching the disk.
---
--- `..` is deliberately left in place: collapsing `a/../b` lexically is wrong the moment `a` is a
--- symlink. Both sides of every comparison get the same treatment, so identical spellings still
--- match; two spellings that differ across a `..` are simply not claimed to be recognized. A
--- backslash is left alone for the same reason -- it is a legal character in a POSIX filename, and
--- no runner here writes one.
---
--- The working directory comes back as `./` rather than as the empty string, because `dir` is used
--- BOTH as a prefix to concatenate and as an argument to `ls -A`: `""` would serve the first and
--- hand the second an empty argument, which the listing would report as "cannot look" and fail the
--- run. An empty input is left empty -- that is "no directory given", not "here".
local function normDir(dir)
  local raw = tostring(dir or "")
  if raw == "" then return "" end
  local s = raw:gsub("//+", "/")
  local n
  repeat s, n = s:gsub("^%./", "") until n == 0
  repeat s, n = s:gsub("/%./", "/") until n == 0
  if s == "" or s == "." then return "./" end
  if s:sub(-1) ~= "/" then s = s .. "/" end
  return s
end

--- Is `dir` -- already through `normDir` -- rooted, rather than read from the process's working
--- directory? POSIX `/...`, and the `C:/...` a cmd.exe run can produce. Lexical, like the rest.
local function isAbsoluteDir(dir)
  return dir:sub(1, 1) == "/" or dir:find("^%a:[/\\]") ~= nil
end

--- The repository root as a path prefix, derived from the runner's suite directory: `tests/` gives
--- the empty string, `sub/tests/` gives `sub/`. The kit never takes a root from the environment.
local function rootOf(dir)
  return dir:match("^(.-)[^/]+/+$") or ""
end

--- `dir` with the repository-root prefix `root` cut off it, when it carries one.
local function relToRoot(dir, root)
  if root ~= "" and dir:sub(1, #root) == root then return dir:sub(#root + 1) end
  return dir
end

--- A declaration's `dir` and the runner's `dir`, RESOLVED AGAINST EACH OTHER and normalized.
---
--- `normDir` folds the spellings ONE hand produces; this folds the spellings TWO hands produce.
--- KickCD and MultiMeters each take `root` from `arg[0]` with a `"."` fallback, hand `Kit.run`
--- `root .. "/tests/"`, then declare one kit suite as `root .. "/tests/_kit/"` and the next as a
--- bare `"tests/_kit/"`. From the repo root the fallback folds both to `tests/_kit/`, which is why
--- this went unnoticed. Invoked BY PATH from anywhere else -- a wrapper script, an editor's runner,
--- a CI step -- `root` is absolute, the relative entry keys differently from the very directory it
--- names, and the inventory reports one correctly wired suite as BOTH "declared but not on disk"
--- AND "arrived with the kit but is not declared", aborting before a single case runs.
---
--- So neither side is keyed until it has been read against the other. A relative entry under an
--- absolute runner takes the runner's root -- the root it was written against. The mirror has none
--- to take, a relative runner's root being the empty string, so an absolute entry is cut back at
--- the runner's own directory, the one anchor both sides share, at the LAST occurrence so a
--- checkout that itself lives under a `tests/` cuts in the right place. An absolute entry that
--- never passes through that directory is left alone: inventing a relationship between two paths
--- that share no anchor is worse than reporting none.
local function resolveDir(entryDir, runnerDir)
  local e = normDir(entryDir)
  if e == "" then return runnerDir end
  if isAbsoluteDir(e) == isAbsoluteDir(runnerDir) then return e end
  if isAbsoluteDir(runnerDir) then return rootOf(runnerDir) .. e end
  local cut, from = nil, 1
  while true do
    local found = e:find("/" .. runnerDir, from, true)
    if not found then break end
    cut, from = found, found + 1
  end
  return cut and e:sub(cut + 1) or e
end

--- The `dir` a remedy tells an engineer to WRITE, and the note that goes with it -- which is not
--- always the `dir` the gate RESOLVED, and printing the resolved one was a defect.
---
--- Every remedy below hands over a `{ name = ..., dir = ... }` to paste into a suites list, and
--- each used to interpolate the resolved directory: under a runner rooted at `arg[0]`, invoking it
--- from any other working directory printed `dir = "/home/someone/GIT/KickCD/tests/_kit/"`, and an
--- engineer who follows a remedy literally -- which is what a remedy is for -- has then hard-coded
--- one machine's checkout into a file every other checkout runs, breaking the plain
--- `lua tests/run.lua` the advice was meant to restore.
---
--- A remedy is advice about a SOURCE LINE, so it is printed the way that line has to read. A
--- relative runner has already resolved to the spelling its own declarations use. An absolute one
--- cannot: the kit is handed the VALUE of the runner's root and never the NAME of the expression
--- behind it, so it prints the repo-relative directory plus the instruction to build it from that
--- same expression -- the one thing it knows is right, because `Kit.run` was handed it.
local function adviceDir(kitDir, root)
  if not isAbsoluteDir(kitDir) then return kitDir, "" end
  local rel = relToRoot(kitDir, root)
  return rel, (" (spell that `dir` with the same root expression this runner already passes to "
    .. "`Kit.run`, as in `dir = root .. \"/%s\"`, and never the resolved path named above -- that "
    .. "one is this checkout's alone)"):format(rel)
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
---
--- `dir` is NOT optional decoration on a kit suite. A declaration is the pair (basename,
--- directory), and the bare form names the runner's own directory — so `"test_prose"` wires
--- `tests/test_prose.lua` and says nothing about `tests/_kit/test_prose.lua`, which the inventory
--- then reports as a collision or a decline rather than accepting as covered (kit revision 25,
--- `testing-§9`).
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

-- ── the suite inventory ────────────────────────────────────────────────────────────────────
--
-- A DECLARATION IS THE PAIR (BASENAME, DIRECTORY) (kit revision 25). Until this revision the
-- declaration set was keyed by bare basename and that same set was handed to the kit-directory
-- pass, so a bare `"test_prose"` — an entry that wires the repo's OWN `tests/test_prose.lua` —
-- also answered for `tests/_kit/test_prose.lua`. The kit's copy was never loaded, and nothing said
-- so: the runner's suite list, `docs/test-cases.md` and the pass count all reported the rule as
-- gated. Six repositories were in that state, this one among them. The inventory reads two
-- directories, so its key has to carry which one (`testing-§9`).

--- The rule each suite the kit ships is the gate for. A decline is keyed to it.
---
--- Written down here rather than read out of the suite file's header, because a header is prose and
--- a gate that parses prose to decide whether another gate may be switched off has a typo-sized
--- hole in it. A kit suite with no row here is still declinable — the register row is then matched
--- on the suite's name alone — but it loses the half of the match that says the row is about THIS
--- rule, so a new kit gate adds its row in the revision that ships it.
-- Spelled `<file>-§N`, the way documentation-§6 spells every citation and every kit string now
-- does (kit revision 26): these values are printed into a failure message a consumer cannot
-- respell. Revisions before 26 dropped the section sign here, because LibKa0s's ASCII gate read
-- the kit's string literals; that gate now reads only the shipped library, since the kit prints
-- to a terminal and `tests/` never ships. `normRule` below reduces both spellings to one key, so
-- a register cell that drops the sign still matches.
local KIT_GATE_RULE = {
  test_prose      = "localization-§5",
  test_eol        = "line-endings-§7",
  test_layout_cap = "layout-§1",
  test_diagnostics_contract = "debug-logging-§14",
}

--- Where a repository keeps its `## Documented deviations` register (`documentation-§3`): an addon
--- in `docs/ARCHITECTURE.md`, a library repo — which has no `docs/` trio to put one in — in its
--- root `CLAUDE.md`. Both are read, in that order.
local REGISTER_HOSTS = { "docs/ARCHITECTURE.md", "CLAUDE.md" }

--- The table rows under `## Documented deviations` in `path`; nil when there is no such file.
---
--- Only the rows DIRECTLY under the heading, ending at the next heading of any level: `layout-§1`
--- nests the over-cap census inside this register, and a census row is not a deviation row. A
--- register a repo has subdivided is read as far as its first subdivision and no further, which is
--- the reading that cannot turn a table about something else into a waiver.
local function deviationRows(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local rows, inside = {}, false
  for line in f:lines() do
    local text = line:match("^#+%s(.*)$")
    if text then
      inside = text:lower():find("documented deviations", 1, true) ~= nil
    elseif inside and line:find("^%s*|") then
      rows[#rows + 1] = line
    end
  end
  f:close()
  return rows
end

--- A markdown table row's cells, trimmed, without the outer pipes.
local function rowCells(row)
  local body = row:match("^%s*|(.-)|%s*$")
  if not body then return {} end
  local out = {}
  for cell in (body .. "|"):gmatch("(.-)|") do
    out[#out + 1] = (cell:gsub("^%s*(.-)%s*$", "%1"))
  end
  return out
end

--- A rule reference reduced to the form both spellings share. This collection writes
--- `localization-§5`, some older file headers and register cells drop the section sign, and a
--- register cell wraps whichever it used in backticks.
local function normRule(s)
  -- `string.char(194, 167)` is the section sign's two UTF-8 bytes, stripped wherever they fall.
  return (tostring(s):lower():gsub("[`%s]", ""):gsub(string.char(194, 167), ""))
end

--- `s` on one line, cut to `n` bytes without leaving half a UTF-8 sequence behind.
local function clip(s, n)
  s = tostring(s or ""):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
  if #s <= n then return s end
  return (s:sub(1, n):gsub("[\128-\191]+$", ""):gsub("[\194-\244]$", "")) .. " ..."
end

--- The `## Documented deviations` row that declines the kit gate whose path, relative to the
--- repository root and without its extension, is `gate` — with the register it sits in. Nil is the
--- ordinary answer and means there is no decline to honor.
---
--- BOTH halves are required, and both are narrow: the Rule cell names the rule the gate serves, AND
--- the row names the KIT'S OWN path. Neither half can be relaxed, and this library is the proof of
--- both. Its register carries two `localization-§5` rows about third-party API identifiers, so the
--- rule alone would have waved the prose gate through without ever mentioning it — and both of
--- those rows go on to mention `tests/test_prose.lua`, the repo's own gate, in passing, so a match
--- on the bare basename would have done the same. A row that declines the kit's copy says which
--- copy it is declining; a row that merely mentions a suite has not decided anything.
local function declineFor(root, gate, rule)
  for _, host in ipairs(REGISTER_HOSTS) do
    local path = root .. host
    for _, row in ipairs(deviationRows(path) or {}) do
      local cells = rowCells(row)
      local keyed = (not rule) or normRule(cells[1] or ""):find(normRule(rule), 1, true) ~= nil
      if keyed and row:find(gate, 1, true) then return path, cells end
    end
  end
  return nil
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

-- The suites list, folded into what the gate reads: one record per declaration in declaration
-- order, the position each PAIR was declared at, and the declarations grouped by bare basename —
-- which is no longer a key, only the question "does anything else claim this name?".
local function suiteDeclarations(dir, suites)
  local entries, at, byName = {}, {}, {}
  -- EVERY directory that becomes a key or a comparand goes through `resolveDir` first, on both
  -- sides and at the one place each side enters the gate. A declaration's `dir` and the runner's
  -- `dir` are written by different hands -- one by hand in a suites list, one composed from a
  -- resolved root -- and the pair key is only a key if both hands spell it the same way. Folding
  -- each side on its own is not enough: `normDir` leaves an absolute path absolute and a relative
  -- one relative, so a mixed list keyed two ways until `resolveDir` read them against each other.
  dir = normDir(dir)
  for i, entry in ipairs(suites or {}) do
    local name, why, entryDir = suiteEntry(entry)
    name = tostring(name)
    -- A `pending` entry is declared-and-deliberately-absent. Demanding it be on disk would make the
    -- write-in-progress affordance unreachable, which is the whole point of keeping it. The other
    -- direction still binds: if the file DOES appear, `loadSuites` raises rather than skipping it.
    local rec = { name = name, dir = resolveDir(entryDir, dir), index = i,
      pending = why and true or nil }
    entries[#entries + 1] = rec
    at[rec.dir .. name] = i
    byName[name] = byName[name] or {}
    byName[name][#byName[name] + 1] = rec
  end
  return entries, at, byName
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

-- Direction one: declared but not on disk. Asked about where the declaration says the file lives,
-- which for an entry carrying its own `dir` is not the runner's suite directory.
local function collectMissing(problems, entries, kitDir, root)
  for _, rec in ipairs(entries) do
    local path = rec.dir .. rec.name .. ".lua"
    if not rec.pending and not fileExists(path) then
      local hint = ""
      if rec.dir ~= kitDir and fileExists(kitDir .. rec.name .. ".lua") then
        local advice, note = adviceDir(kitDir, root)
        hint = (" — %s%s.lua DOES exist, so this entry wants { name = %q, dir = %q }%s")
          :format(kitDir, rec.name, rec.name, advice, note)
      end
      problems[#problems + 1] = ("%s is declared in the suites list (position %d) but is not on "
        .. "disk — delete the entry or write the file%s"):format(path, rec.index, hint)
    end
  end
end

-- Direction two, in the runner's own directory: on disk but not declared against THIS directory.
local function collectUndeclared(problems, dir, onDisk, at)
  for _, name in ipairs(onDisk) do
    if not at[dir .. name] then
      problems[#problems + 1] = ("%s%s.lua exists but is not declared in the suites list — add %q "
        .. "to the runner; it is running zero cases today"):format(dir, name, name)
    end
  end
end

--- The last declaration of `name` against a directory other than the kit's whose file exists:
--- the repo's own copy a collision reports as running in the kit's place, or nil.
local function kitShadow(recs, kitDir, name)
  local shadow = nil
  for _, rec in ipairs(recs or {}) do
    if rec.dir ~= kitDir and fileExists(rec.dir .. name .. ".lua") then shadow = rec end
  end
  return shadow
end

--- The declared skip a recorded decline becomes: keyed per repo, named and reasoned per gate.
local function declineRecord(kitPath, gate, register, cells, shadowPath)
  return {
    -- NAMED by the root-relative gate rather than by `kitPath`, because the name is read
    -- back by `--list` into `docs/test-cases.md`: a committed generated file must not say
    -- one thing when the runner is invoked from the repo root and another when a wrapper
    -- invokes it by path. Keyed by `kitPath`, which is the half that must stay per-repo.
    key  = kitPath,
    name = ("suite inventory: %s.lua is declined, and the decline is recorded"):format(gate),
    reason = ("%s carries a `## Documented deviations` row keyed %s: %s%s"):format(
      register, cells[1] ~= "" and cells[1] or "(no rule cell)", clip(cells[2], 200),
      shadowPath and (" — %s runs in its place"):format(shadowPath) or ""),
  }
end

-- Direction two, over the vendored kit, and the half the pair key changes (kit revision 25).
--
-- A kit suite no declaration names is a gate running zero cases, and it arrives in three shapes.
-- A COLLISION — the repo declares that basename against its own directory and has a file there —
-- is reported with BOTH paths and which one is running, because the repo has made a choice and the
-- report is what makes it visible now rather than at the next audit. A DECLINE — the same thing
-- with a `## Documented deviations` row behind it — is reported once as a skip carrying the row's
-- reason, and that carve-out is what keeps `localization-§5`'s permission exercisable: a repo that
-- carries its own prose gate wires the kit's copy or its own, never both. Anything else is a plain
-- hole. The first and the third are failures; only the recorded one is a skip; none of the three
-- is a silent pass.
local function collectKitHoles(problems, declines, kitDir, onDisk, at, byName, root)
  for _, name in ipairs(onDisk) do
    if not at[kitDir .. name] then
      local kitPath, shadow = kitDir .. name .. ".lua", kitShadow(byName[name], kitDir, name)
      local shadowPath = shadow and (shadow.dir .. name .. ".lua") or nil
      local rule = KIT_GATE_RULE[name]
      -- The kit's path as the REGISTER would write it: relative to the repository root, which is
      -- what a row names and what the runner's absolute-or-relative `dir` is not. It doubles as
      -- the decline's identity below: the one spelling of this gate that does not move with the
      -- working directory the runner happened to be invoked from.
      local gate = relToRoot(kitDir, root) .. name
      local advice, note = adviceDir(kitDir, root)
      local register, cells = declineFor(root, gate, rule)
      rule = rule or "the rule this gate serves"
      if register then
        declines[#declines + 1] = declineRecord(kitPath, gate, register, cells, shadowPath)
      elseif shadow then
        problems[#problems + 1] = ("%s ships in the vendored kit, and the suites list declares a "
          .. "bare %q (position %d) instead — that entry wires %s, %s is what runs, and the kit's "
          .. "copy is loading zero cases. Wire one or the other, never both: change the entry to "
          .. "{ name = %q, dir = %q }%s and delete %s, or record the decline as a "
          .. "`## Documented deviations` row keyed %s that names %s.lua")
          :format(kitPath, name, shadow.index, shadowPath, shadowPath, name, advice, note,
            shadowPath, rule, gate)
      else
        problems[#problems + 1] = ("%s arrived with the vendored kit but is not declared in the "
          .. "suites list — add { name = %q, dir = %q }%s to the runner, or record the decline as "
          .. "a `## Documented deviations` row keyed %s that names %s.lua; it is running zero cases "
          .. "today"):format(kitPath, name, advice, note, rule, gate)
      end
    end
  end
end

--- Both directions of the suite list, asserted.
---
--- `testing-§9` names the suite list as a list that MUST be pinned, and both of its silent failure
--- modes were live in this collection: a declared suite whose file is gone was skipped, and a suite
--- file nobody added to the list never ran at all. `loadSuites` closes the first; this closes the
--- second, and re-closes the first for the repos that call this directly from a case.
---
--- The messages are worded differently on purpose, because the fixes are different: one is "delete
--- the entry or write the file", another "add it to the runner", a third "wire one or the other,
--- never both". Every divergence in both directions is reported in one message — a list that has
--- drifted has usually drifted more than once, and one-at-a-time is one test run per missing file.
---
--- THE VENDORED KIT IS SCANNED TOO. A suite that ships in the kit arrives in a consumer with a
--- re-vendor rather than with a commit someone wrote, so the way it fails is the way it always
--- fails: the copy lands, nobody adds it to the suite list, and the run is green over a gate that
--- never executed. `tests/_kit/` is scanned whenever `framework.lua` is found there — the
--- collection's one vendoring destination, and the guard means a repo that vendors somewhere else
--- is simply not asked about it.
function Kit.assertSuiteInventory(dir, suites)
  -- The runner's own `dir` normalized once, here, so `kitDir`, the `at[...]` keys, every
  -- `rec.dir` comparison below and the root the register is read against all derive from the same
  -- spelling (kit revision 25).
  dir = normDir(dir or "tests/")
  local kitDir, root = dir .. "_kit/", rootOf(dir)
  local entries, at, byName = suiteDeclarations(dir, suites)

  local problems, declines = {}, {}
  collectMissing(problems, entries, kitDir, root)
  collectUndeclared(problems, dir, suiteNamesOrFail(dir), at)

  if fileExists(kitDir .. "framework.lua") then
    collectKitHoles(problems, declines, kitDir, suiteNamesOrFail(kitDir), at, byName, root)
  end

  -- Registered as DECLARED skips, before the failure check and once per suite however many times
  -- this is called: a decline belongs in `docs/test-cases.md` and in the run's own output, which is
  -- the whole difference between a gate somebody decided not to wire and a gate nobody knows about.
  for _, d in ipairs(declines) do
    if not declinesReported[d.key] then
      declinesReported[d.key] = true
      Kit.test(d.name, nil, d.reason)
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
Kit.__deviationRows = deviationRows
Kit.__declineFor    = declineFor
Kit.__kitGateRule   = KIT_GATE_RULE

return Kit
