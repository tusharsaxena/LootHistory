-- testkit/inventory.lua — the suite inventory and the path helpers it keys on, peeled out of
-- framework.lua.
--
-- WHY A SEPARATE FILE (kit revision 28). `framework.lua` had been back in `layout-§1`'s 1000–1500
-- band since kit revision 26 peeled `asserts.lua` out of it, and its band entry, carried as
-- *Accepted* across six release runs, had outlived `automated-tests-§4`'s three-release shelf life.
-- Revision 26 named this as the next seam, and it is a real one: the inventory's state (the declines
-- already reported) is read by nothing else, and it reaches the rest of the kit only through
-- `Kit.test`, which a recorded decline registers as a declared skip, and `fail`. The path helpers
-- come with it because the inventory keys every declaration on them; `framework.lua`'s own suite
-- loader, `--list` renderer and shard partitioner read five of them, and get them back from here.
-- Moving it changes no behavior. `framework.lua` loads this chunk ONCE, where the path helpers used
-- to stand and before `loadSuites`, so `Kit.assertSuiteInventory` is on the kit table exactly when
-- it was before.
--
-- SHAPE. The file returns `function(Kit, fail)`, as `asserts.lua` does: it installs
-- `Kit.assertSuiteInventory` on the kit table it is handed and returns the helpers `framework.lua`
-- still calls, and the internals it exposes to the kit's own self-tests. It is not a module a suite
-- loads on its own: `framework.lua` is the entry point, and this file vendors beside it in the same
-- folder.

return function(Kit, fail)

  -- Kit gates the repository has declined, by the RESOLVED path of the declined suite, so a second
  -- call to `Kit.assertSuiteInventory` reports it once rather than twice (kit revision 25). Resolved
  -- and not root-relative, which this file otherwise prefers: the key has to tell two REPOSITORIES
  -- apart inside one process, and `tests/_kit/test_prose` is the same string in all of them -- the
  -- kit's own inventory fixtures, a fresh temporary tree per case, are where that is provable. The
  -- case NAME below is root-relative all the same, and for the opposite reason.
  local declinesReported = {}

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

  --- What `framework.lua` needs back: the path helpers its suite loader, `--list` renderer and
  --- shard partitioner call, and the decline reader and gate table it exposes to the kit's own
  --- self-tests (`Kit.__deviationRows`, `Kit.__declineFor`, `Kit.__kitGateRule`).
  return {
    fileExists    = fileExists,
    normDir       = normDir,
    rootOf        = rootOf,
    resolveDir    = resolveDir,
    adviceDir     = adviceDir,
    suiteEntry    = suiteEntry,
    deviationRows = deviationRows,
    declineFor    = declineFor,
    kitGateRule   = KIT_GATE_RULE,
  }

end
