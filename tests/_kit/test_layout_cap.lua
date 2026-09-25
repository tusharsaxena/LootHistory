-- testkit/test_layout_cap.lua — the 1500-line cap gate (layout-§1), over every authored `.lua` file
-- the repository tracks.
--
-- WHAT IT PROVES. That the tree and the census agree, in each of the three directions they can
-- disagree in: no authored file over layout-§1's 1500-line cap is missing from the census; no
-- census row names a path that is gone or no longer over the cap; and every over-cap row says
-- which of the section's three terminal states it sits in — peeled, an open issue naming the seam
-- a peel would follow, or a ratified deviation row carrying a re-check trigger. The fourth state,
-- a breach that nothing anywhere remarks on, is what layout-§1 refuses and what this file exists to
-- make impossible: "the count sitting in a bundle manifest that no document reads".
--
-- IT SHIPS IN THE KIT because the hand-written alternative has been measured. Five repositories
-- wrote their own — 232, 221, 209, 380 and 206 lines, no two byte-identical — and seven addons
-- wrote none at all, so the cap's only enforcement there was an auditor with a line count. The
-- five drifted where it costs most. One looks for a heading named ``Files by the `layout-§1` band``
-- where the other four look for `Files over the 1500-line cap`, so one rule is keyed to two names;
-- that same copy gates the 1000-1500 band the release watch list already generates, and the other
-- four do not; two of them fail a census with no rows in it, which layout-§1 now sanctions as a
-- result, while a third lets the heading go missing altogether, which it does not; and one reads
-- its census from the root `CLAUDE.md`, which the same MUST sanctions, at a heading level the
-- register above it does not. A rule enforced by five copies is
-- five chances to carry a subset, and this one has been carrying five different subsets.
--
-- THE SCOPE IS THE TRACKED SET MINUS BOTH OF LAYOUT-1'S CARVE-OUTS, and it is the part earlier
-- drafts got wrong twice, in both directions.
--
--   * Carve-out one is VENDORED CODE. `libs/` and `tests/_kit/` are its two INSTANCES, not two
--     carve-outs: both arrive by whole-folder copy from upstream (library-stack-§3, testing-§1) and
--     are audited in the repository that writes them, so neither the cap nor the band binds a file
--     this repo MUST NOT edit. That pair is compiled in, because it is the same pair everywhere
--     the kit is vendored. A library repo's own `testkit/` is NOT in it: the kit is authored there,
--     and a file a repo writes is a file it can peel.
--
--   * Carve-out two is GENERATED NON-SHIPPING DATA, on its three conditions — generated rather
--     than authored, loaded by nothing, excluded from what a player downloads. A gate cannot infer
--     any of the three. They are facts about the repository, not properties a path betrays, so the
--     exempt set ARRIVES THROUGH THE OPTS TABLE, the way the vendored-payload gate takes its
--     consumer facts (testing-§11). Nothing about a particular repository is compiled in here.
--
-- Scoped to the vendored folders alone — the careless reading, and the one both earlier drafts
-- took — this gate fails the single repository in the collection that had already done everything
-- the rule asked. It tracks 27 generated `GlobalStrings/*.lua` files, one of them 23,842 lines and
-- every one of them exempt by rule, and with no exempt set to hand the gate that dump is either an
-- unremarked authored breach or, once the repo writes the row it already carries, a row whose
-- disposition the gate refuses — red either way, for a file layout-§1 never bound. Measured, not
-- hypothetical, and it is why the second carve-out is an input rather than a pattern.
--
-- WHAT IT DELIBERATELY DOES NOT DO.
--
--   * It does not judge whether an exemption is LEGITIMATE, and it never will. That judgment rests
--     on the same three repository facts it cannot read, and it belongs to the auditor. What the
--     gate can see is whether the two RECORDS agree about which paths were exempted, so that is
--     all it asserts: a row marked `exempt` names a path the opts-borne exempt set contains, and
--     an exempt path the census mentions is marked rather than carrying a terminal state — the
--     three terminal states are for breaches, and a file the carve-out exempts was never in
--     breach. A repository that puts a hand-written file in that set has fooled the gate and will
--     be caught by a reader, which is the correct division of labor for a fact no path betrays.
--
--   * It does not gate the 1000-1500 on-notice band. The band is the GENERATED observation, and
--     automated-tests-§4's watch list emits a row for it on every run; the census is the AUTHORED
--     disposition and covers the over-cap band alone. One copy of this gate asserted the band too,
--     which made a file moving between bands a migration between two documents rather than one
--     line moving in one of them. Retiring that is the point of shipping one gate.
--
--   * It does not assert the line figures printed in the census. They are dated measurements, and
--     pinning them would redden the suite on every ordinary edit to a large file — a gate with a
--     standing reason to be switched off stops being run. Membership is the invariant; the numbers
--     are prose.
--
-- IT FAILS RATHER THAN SKIPS WHEN IT CANNOT LOOK. No `io.popen`, no git, no hub document, no
-- census heading, a tracked file that cannot be opened — every one of those is a failure. A gate
-- that goes quiet on a repository it never read reports green on it, which is the same bargain the
-- EOL and kit-sync gates already strike (testing-§11, line-endings-§7).
--
-- THERE IS EXACTLY ONE CLEAN SKIP, and it is not that bargain being softened: a repository that
-- tracks no authored `.lua` at all — a documentation-and-tooling repo (documentation-§8) — owes no
-- census and wires no gate, so a census it does not have is not a hole. The discrimination is
-- explicit rather than implied by an empty answer: git is asked for the WHOLE tracked set, and an
-- empty answer to THAT is a broken gate and fails, while a non-empty tracked set holding no
-- authored `.lua` is the documentation repo and skips, saying so.
--
-- WIRING, in the consumer's `tests/run.lua`, before `Kit.run`:
--
--   local Kit = dofile("tests/_kit/framework.lua")
--   Kit.layoutCap = {
--     hub    = "docs/ARCHITECTURE.md",              -- the default; a library repo passes "CLAUDE.md"
--     exempt = { "GlobalStrings/" },                -- layout-§1's generated-data carve-out, per repo
--   }
--   Kit.run{ dir = "tests/", suites = { …, { name = "test_layout_cap", dir = "tests/_kit/" } } }
--
-- Declared by the pair (basename, kit directory) like every other kit suite (testing-§9), so
-- `Kit.assertSuiteInventory` goes red until it is wired and it cannot arrive with a re-vendor and
-- then quietly run nothing. Both opts are optional: a repo with no generated data and its census
-- in the standard place passes none of them. It takes the kit as its chunk argument rather than
-- reading the exposed table, for the reason `test_eol.lua` does — that table's global name belongs
-- to the consumer (`LK_TEST`, `AT_TEST`, `KICKCD_TEST`, …) and a vendored suite cannot know which
-- one it is standing in — and `Kit.layoutCap` is reachable for exactly the same reason: the kit
-- table is the one object both sides already hold.
--
-- THE SELF-TESTS SHIP WITH IT, below the gate, and they are pure: they drive the census parser and
-- the comparison over fixtures in memory, touching neither git nor the disk. They are here rather
-- than in the library repo's own suite because a vendored gate whose logic is tested only upstream
-- is a gate that can rot in place through a re-vendor, and because each of the three assertions
-- should be shown to go red when it is broken, in every repository that relies on it.

local Kit = ...
local test, fail, skip = Kit.test, Kit.fail, Kit.skip

local CAP              = 1500
local DEFAULT_HUB      = "docs/ARCHITECTURE.md"
local REGISTER_HEADING = "Documented deviations"
local CENSUS_HEADING   = "Files over the 1500-line cap"

--- The two instances of layout-§1's first carve-out. Compiled in, because they are the same two in
--- every repository the kit is vendored into.
local VENDORED_PREFIXES = { "libs/", "tests/_kit/" }

-- ---------------------------------------------------------------------------
-- The consumer facts
-- ---------------------------------------------------------------------------

--- The opts table the runner sets on the kit, or an empty one.
---
--- A missing table is not a failure: `hub` has a default that is right for eleven of the twelve
--- repos, and an absent `exempt` means a repository with no generated data, which is most of them.
--- A repository that HAS generated data and forgets the opt does not go silently unchecked — its
--- dump surfaces as an unremarked breach in the first case below, which names this table.
local function options()
  local o = Kit.layoutCap
  if o == nil then return {} end
  if type(o) ~= "table" then
    fail("layout cap gate: Kit.layoutCap is the consumer-facts table — { hub = \"...\", exempt = "
      .. "{ ... } } — and this runner set it to a " .. type(o), 2)
  end
  return o
end

-- ---------------------------------------------------------------------------
-- The tree
-- ---------------------------------------------------------------------------

--- Split a NUL-delimited blob into an array.
---
--- `git ls-files -z` because a path may contain anything but NUL, and the line-oriented form quotes
--- such a path instead of printing it — a quoted path would not match a file on disk, and this gate
--- would then report a breach that is really a parse failure. Split by hand rather than with a
--- pattern: `%z` is Lua 5.1's spelling for the zero byte and an error in 5.4, and these suites run
--- under both.
local function splitNul(blob)
  local out, start = {}, 1
  while true do
    local at = blob:find("\0", start, true)
    if not at then break end
    if at > start then out[#out + 1] = blob:sub(start, at - 1) end
    start = at + 1
  end
  return out
end

--- Every path git tracks, in git's order.
---
--- The WHOLE tracked set rather than `-- '*.lua'`, and that is the discrimination the one clean
--- skip rests on: an empty answer here means git could not be reached or this is not a repository,
--- which is a failure, while a tracked set that simply holds no `.lua` is a documentation repo,
--- which is not. Asked only for Lua, those two answers are the same empty list.
local function trackedFiles()
  if not io.popen then
    fail("layout cap gate: io.popen is unavailable, so the tracked set cannot be read; this gate "
      .. "cannot run and must not be reported as passing", 2)
  end
  local pipe = io.popen("git ls-files -z")
  if not pipe then
    fail("layout cap gate: io.popen returned no handle for `git ls-files`, so this gate cannot run "
      .. "and must not be reported as passing", 2)
  end
  local blob = pipe:read("*a") or ""
  pipe:close()

  local paths = splitNul(blob)
  if #paths == 0 then
    fail("layout cap gate: `git ls-files -z` returned nothing — either git is unavailable here or "
      .. "this is not a repository. A repository that tracks no authored Lua still tracks its own "
      .. "documents, so this is the gate being blind rather than a repo with nothing to check, and "
      .. "it must not be reported as passing", 2)
  end
  return paths
end

--- True when `path` is vendored, and so not authored here.
local function isVendored(path)
  for _, prefix in ipairs(VENDORED_PREFIXES) do
    if path:sub(1, #prefix) == prefix then return true end
  end
  return false
end

--- A whole file as bytes, or nil when it cannot be opened.
---
--- Binary mode so the count below is of the bytes on disk: the working tree is pinned CRLF in every
--- client-bound repo (line-endings-§2), text mode on Windows would translate that away, and a gate
--- that counts a different file from the one `wc -l` counts is a gate whose numbers nobody trusts.
local function readBytes(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local body = fh:read("*a") or ""
  fh:close()
  return body
end

--- Lines in `body`, counted as `wc -l` counts them, plus a final unterminated line if there is one.
--- Counted on LF alone: under a CRLF pin every terminator is `\r\n`, and counting the `\n` of each
--- pair gives the same figure either way.
local function countLines(body)
  if body == "" then return 0 end
  local n = 0
  for _ in body:gmatch("\n") do n = n + 1 end
  if body:sub(-1) ~= "\n" then n = n + 1 end
  return n
end

-- ---------------------------------------------------------------------------
-- The exempt set
-- ---------------------------------------------------------------------------

--- True when the opts entry `entry` covers `path`: the path itself, or a folder containing it.
---
--- Globs are not expanded. An entry that would only match through one matches nothing, which errs
--- toward reporting a breach rather than toward excusing a file nobody meant to excuse — and the
--- red that follows names the path, so the typo is one line from being read.
local function exemptEntryCovers(entry, path)
  if entry == path then return true end
  local folder = (entry:sub(-1) == "/") and entry or (entry .. "/")
  return path:sub(1, #folder) == folder
end

--- The opts-borne exempt set, resolved against the tree into a set of concrete paths.
---
--- Takes an array of paths and folders, a map of path to true, or both — a runner writes whichever
--- reads better beside the reason it is passing them.
---
--- An entry matching nothing is NOT a failure. It is stale, not silent: the file it named is gone,
--- so there is nothing it could be hiding, and the moment it covers the wrong file the case below
--- says so by name. The rule's own second assertion is about a DISPOSITION outliving its breach,
--- and an exemption is not a disposition.
local function resolveExempt(entries, tree)
  local set = {}
  if entries == nil then return set end
  if type(entries) ~= "table" then
    fail("layout cap gate: Kit.layoutCap.exempt is the set of paths layout-§1's generated-data "
      .. "carve-out removes, as an array or a map; this runner set it to a " .. type(entries), 2)
  end
  for key, value in pairs(entries) do
    local entry = (type(key) == "number") and value or (value and key)
    if entry ~= nil then
      if type(entry) ~= "string" then
        fail("layout cap gate: every entry in Kit.layoutCap.exempt is a tracked path or a folder "
          .. "ending in `/`; this one is a " .. type(entry), 2)
      end
      for path in pairs(tree) do
        if exemptEntryCovers(entry, path) then set[path] = true end
      end
    end
  end
  return set
end

-- ---------------------------------------------------------------------------
-- The census
-- ---------------------------------------------------------------------------

--- `text` as an array of lines, with CR dropped so a CRLF hub parses as an LF one.
local function linesOf(text)
  local out = {}
  for line in ((text:gsub("\r\n", "\n")) .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = line end
  return out
end

--- Every ATX heading in `lines`, as { level, title, line }.
local function headingsOf(lines)
  local out = {}
  for i, line in ipairs(lines) do
    local hashes, title = line:match("^(#+)%s+(.-)%s*$")
    if hashes then
      out[#out + 1] = { level = #hashes, title = (title:gsub("%s*#+$", "")), line = i }
    end
  end
  return out
end

--- Where the census heading sits, or nil and why it cannot be read from there.
---
--- The parent is FIXED and is the same parent in both hosts: the census sits under
--- `## Documented deviations`, and its level follows that register's own nesting, so a `##`
--- register takes a `###` census beneath it. Locating it by its parent rather than by its name
--- alone is what makes a heading a doc-shape gate can find twice — and it is why a census that is
--- a SIBLING of the register, which is where one of the five hand-written copies reads its own,
--- is reported here with the move it owes rather than accepted quietly.
local function locateCensus(headings)
  local register
  for i, h in ipairs(headings) do
    if h.title == REGISTER_HEADING then register = i break end
  end
  if not register then
    return nil, "carries no `## " .. REGISTER_HEADING .. "` register, which is the census's fixed "
      .. "parent in both hosts (documentation-§3)"
  end

  local level = headings[register].level
  local stop = #headings + 1
  for i = register + 1, #headings do
    if headings[i].level <= level then stop = i break end
  end

  for i = register + 1, stop - 1 do
    if headings[i].title == CENSUS_HEADING then
      if headings[i].level ~= level + 1 then
        return nil, ("carries `" .. CENSUS_HEADING .. "` at heading level %d under a level %d "
          .. "register; the census's level follows the register's own nesting, so it belongs at "
          .. "level %d"):format(headings[i].level, level, level + 1)
      end
      return headings[i]
    end
  end

  for _, h in ipairs(headings) do
    if h.title == CENSUS_HEADING then
      return nil, ("carries `" .. CENSUS_HEADING .. "` at line %d, outside the `## "
        .. REGISTER_HEADING .. "` register at line %d. The parent is fixed: a reader asking "
        .. "whether a breach was ratified is already reading the register that holds the answer, "
        .. "so the census goes one level beneath it"):format(h.line, headings[register].line)
    end
  end
  for _, h in ipairs(headings) do
    if h.title:lower():find("cap", 1, true) or h.title:lower():find("layout", 1, true) then
      return nil, ("carries no `" .. CENSUS_HEADING .. "` heading under its register; the closest "
        .. "heading it does carry is `%s` at line %d. The name does not vary — a rule keyed to two "
        .. "spellings is a rule one repo answers and the next does not"):format(h.title, h.line)
    end
  end
  return nil, "carries no `" .. CENSUS_HEADING .. "` heading under its `## " .. REGISTER_HEADING
    .. "` register. Every repo that tracks an authored `.lua` owes the heading, and a repo with "
    .. "nothing over the cap writes the result under it rather than leaving it out"
end

--- The census section of a hub document: its rows in file order, and the prose beside them.
---
--- A row is a table line whose first cell is a single backticked path. The table's own heading row
--- and its `|---|` separator carry no backticks and fall out on their own, and reading stops at the
--- next heading at or above the census's level, so a later section growing a table cannot leak in.
---
--- `rest` is every cell after the path, kept whole rather than picked apart by column: the census
--- is specified by what it must SAY, not by how many columns it says it in, and a three-column and
--- a four-column census are both compliant.
local function parseCensus(text)
  local lines = linesOf(text)
  local heading, why = locateCensus(headingsOf(lines))
  if not heading then return nil, why end

  local rows, prose = {}, {}
  for i = heading.line + 1, #lines do
    local line = lines[i]
    local hashes = line:match("^(#+)%s")
    if hashes and #hashes <= heading.level then break end
    local path, rest = line:match("^|%s*`([^`]+)`%s*|(.*)$")
    if path then
      rows[#rows + 1] = { path = path, rest = (rest:gsub("%s*|%s*$", "")) }
    elseif line:match("^%s*$") or line:match("^%s*|") then -- blank, or the table's own header
      local _ = nil
    else
      prose[#prose + 1] = line
    end
  end
  return { rows = rows, prose = table.concat(prose, "\n") }
end

--- What is wrong with the SHAPE of a census section, or nil.
---
--- An empty census is a RESULT: a repo that tracks Lua and has nothing over the cap keeps the
--- heading and writes so under it, the way performance-§10 already treats an empty watch list.
--- A heading with nothing at all beneath it is the state that cannot be told apart from a census
--- nobody wrote, and it is the one this refuses — along with its mirror, a census that declares
--- the empty result and then lists rows under it, which two of the hand-written copies grew only
--- after the day their last breach was peeled out from under a table that still said otherwise.
local function censusShape(section)
  if #section.rows == 0 and section.prose == "" then
    return "`" .. CENSUS_HEADING .. "` heading stands with nothing under it. An empty census is a "
      .. "RESULT and an absent one is indistinguishable from a census nobody wrote, so write the "
      .. "result — \"Nothing is over the cap today\" — under the heading rather than leaving a "
      .. "reader to guess which of the two they are looking at"
  end
  if #section.rows > 0 and section.prose:lower():find("nothing is over the", 1, true) then
    return "cap census says nothing is over the cap and then lists " .. #section.rows
      .. " row(s) under it. Those are contradictory claims about the same fact — drop whichever "
      .. "one is stale"
  end
  return nil
end

--- True when a row's cells mark it as claiming layout-§1's generated-data carve-out.
local function marksExempt(rest)
  return rest:lower():find("%f[%a]exempt") ~= nil
end

--- True when a row's cells name one of layout-§1's three terminal states: an issue number to open,
--- a ratified deviation row to read, or a peel that is scheduled. A cell naming none of them is a
--- note, and a note is what this section exists to stop being enough.
local function namesTerminalState(rest)
  local lower = rest:lower()
  return rest:find("#%d") ~= nil
    or lower:find("deviation", 1, true) ~= nil
    or lower:find("register row", 1, true) ~= nil
    or lower:find("peel", 1, true) ~= nil
end

-- ---------------------------------------------------------------------------
-- The comparison
-- ---------------------------------------------------------------------------

--- The census against the tree, in every direction the two can disagree.
---
--- Pure, and separated from every byte of IO above on purpose: it is what the self-tests at the
--- foot of this file drive, so each of the three assertions can be shown to go red when it breaks
--- without a repository being bent into the shape that breaks it.
---
--- `tree` is { path = lineCount } over the authored set, `rows` the census in file order, `exempt`
--- the resolved exempt set. Returns four sorted arrays, one per case below.
local function audit(tree, rows, exempt)
  local listed = {}
  for _, row in ipairs(rows) do listed[row.path] = true end

  local missing = {}
  for path, count in pairs(tree) do
    if count > CAP and not exempt[path] and not listed[path] then
      missing[#missing + 1] = path .. " (" .. count .. " lines)"
    end
  end

  local spent, unstated, disagreeing = {}, {}, {}
  for _, row in ipairs(rows) do
    local count = tree[row.path]
    if count == nil then
      spent[#spent + 1] = row.path .. " (no authored file is tracked at that path)"
    elseif count <= CAP then
      spent[#spent + 1] = row.path .. " (" .. count .. " lines, under the cap)"
    else
      -- Graded only while the row is a live breach: a row the case above already condemns should
      -- be one red to fix, not three.
      local marked, isExempt = marksExempt(row.rest), exempt[row.path] == true
      if marked and not isExempt then
        disagreeing[#disagreeing + 1] = row.path
          .. " — marked `exempt` in the census, and absent from the exempt set this gate was handed"
      elseif isExempt and not marked then
        disagreeing[#disagreeing + 1] = row.path
          .. " — in the exempt set this gate was handed, and its census row does not mark it exempt"
      elseif not marked and not namesTerminalState(row.rest) then
        unstated[#unstated + 1] = row.path
      end
    end
  end

  table.sort(missing) table.sort(spent) table.sort(unstated) table.sort(disagreeing)
  return missing, spent, unstated, disagreeing
end

-- ---------------------------------------------------------------------------
-- Reading this repository, once
-- ---------------------------------------------------------------------------

local cached

--- The tree, the exempt set and the census, read once and shared by every case below.
---
--- Read inside the cases rather than at load: a suite file registers cases and does nothing else,
--- and a gate that shells out while the runner is still building its registry fails outside any
--- case's name. Nothing is cached until every read has succeeded, so a repository this gate cannot
--- look at fails in each case rather than once.
local function state()
  if cached then return cached end

  local tree, count = {}, 0
  for _, path in ipairs(trackedFiles()) do
    if path:sub(-4) == ".lua" and not isVendored(path) then
      local body = readBytes(path)
      if body == nil then
        fail("layout cap gate: git tracks " .. path .. " and it cannot be opened, so the cap "
          .. "cannot be measured over it; this gate must not be reported as passing", 2)
      end
      tree[path] = countLines(body)
      count = count + 1
    end
  end
  if count == 0 then
    cached = { count = 0 }
    return cached
  end

  local o = options()
  local hub = o.hub or DEFAULT_HUB
  local text = readBytes(hub)
  if text == nil then
    fail("layout cap gate: " .. hub .. " could not be opened, and it is where this repository's cap "
      .. "census lives. Pass `Kit.layoutCap.hub` if the engineer-context hub is elsewhere — a "
      .. "Ka0s-owned library repo keeps its census in the root CLAUDE.md — but a hub this gate "
      .. "cannot read is a gate that cannot look, and it fails rather than skipping", 2)
  end
  local section, why = parseCensus(text)
  if not section then
    fail("layout cap gate: " .. hub .. " " .. why, 2)
  end

  cached = { count = count, tree = tree, hub = hub, section = section,
             exempt = resolveExempt(o.exempt, tree) }
  return cached
end

--- The state, or the one clean skip.
local function repository()
  local s = state()
  if s.count == 0 then
    skip("this repository tracks no authored .lua file, so layout-§1 leaves it no census to write "
      .. "and no cap to gate; the obligation arrives with its first authored .lua outside a frozen "
      .. "bundle")
  end
  return s
end

-- ---------------------------------------------------------------------------
-- The three assertions
-- ---------------------------------------------------------------------------

test("layoutcap: every authored file over the 1500-line cap is named in the census", function()
  local s = repository()
  local missing = audit(s.tree, s.section.rows, s.exempt)
  if #missing > 0 then
    fail("over layout-§1's " .. CAP .. "-line cap and remarked on nowhere: "
      .. table.concat(missing, ", ") .. ". Peel it, open an issue naming the seam a peel would "
      .. "follow, or ratify a deviation row with a re-check trigger — then write the row into "
      .. s.hub .. "'s `" .. CENSUS_HEADING .. "` census. If the file is generated non-shipping "
      .. "data, it owes no row at all: name it in `Kit.layoutCap.exempt` in the runner, where the "
      .. "three conditions a path cannot betray are asserted by the auditor instead", 2)
  end
end)

test("layoutcap: no census row outlives the breach it records", function()
  local s = repository()
  local _, spent = audit(s.tree, s.section.rows, s.exempt)
  if #spent > 0 then
    fail(s.hub .. "'s cap census carries rows for files that are no longer over the cap: "
      .. table.concat(spent, ", ") .. ". Delete the row, and close the issue or retire the "
      .. "deviation row that backed it — a disposition must not outlive its breach, or the census "
      .. "becomes a list of decisions about files nobody has", 2)
  end
end)

test("layoutcap: every over-cap census row carries one of layout-§1's three terminal states",
  function()
    local s = repository()
    local _, _, unstated = audit(s.tree, s.section.rows, s.exempt)
    if #unstated > 0 then
      fail(s.hub .. "'s cap census names these files and does not say which terminal state they "
        .. "sit in: " .. table.concat(unstated, ", ") .. ". A row acknowledges the line count; "
        .. "layout-§1 asks which of the three it is — the issue that names the seam, the deviation "
        .. "row that ratified it, or the peel that is scheduled", 2)
    end
  end)

test("layoutcap: the census and the exempt set agree about which paths were exempted", function()
  local s = repository()
  local _, _, _, disagreeing = audit(s.tree, s.section.rows, s.exempt)
  if #disagreeing > 0 then
    fail("the cap census in " .. s.hub .. " and the exempt set in `Kit.layoutCap.exempt` disagree: "
      .. table.concat(disagreeing, "; ") .. ". Whether an exemption is LEGITIMATE is the auditor's "
      .. "call against layout-§1's three conditions and never this gate's; that the two records name "
      .. "the same paths is the part a gate can see, so it is the part it holds you to", 2)
  end
end)

test("layoutcap: an empty census is written as a result rather than left standing empty", function()
  local s = repository()
  local why = censusShape(s.section)
  if why then fail(s.hub .. "'s " .. why, 2) end
end)

-- ---------------------------------------------------------------------------
-- The self-tests
-- ---------------------------------------------------------------------------
--
-- Each of the three assertions, shown going red when it is broken, plus the parser that finds the
-- census in the first place. All of it over fixtures in memory: no git, no disk, and no repository
-- bent into a shape to prove a point about it.

local HUB = table.concat({
  "# Architecture",
  "",
  "## Documented deviations",
  "",
  "| Rule | What differs | Why | Decided | Re-check trigger |",
  "|---|---|---|---|---|",
  "| `layout-§2` | a folder of generated data | no home for it | 2026-01-01 | the folder moving |",
  "",
  "### Files over the 1500-line cap",
  "",
  "One row per over-cap authored file.",
  "",
  "| Path | Lines | Terminal state |",
  "|---|---|---|",
  "| `modules/Big.lua` | 1702 | Issue #12 names the seam a peel would follow |",
  "| `Dump/Strings.lua` | 23842 | Exempt — generated, loaded by nothing, not shipped |",
  "",
  "## Something else",
  "",
  "| `modules/NotTheCensus.lua` | 9999 | a table in a later section |",
}, "\n")

test("layoutcap self-test: the parser reads the census nested under the register, and stops there",
  function()
    local section = parseCensus(HUB)
    Kit.assertEqual(#section.rows, 2, "two rows under the census heading")
    Kit.assertEqual(section.rows[1].path, "modules/Big.lua", "first row's path")
    Kit.assertEqual(section.rows[2].path, "Dump/Strings.lua", "second row's path")
    Kit.assertTrue(section.prose:find("One row per", 1, true) ~= nil, "the prose beside the rows")
    Kit.assertTrue(marksExempt(section.rows[2].rest), "the second row marks itself exempt")
    Kit.assertFalse(marksExempt(section.rows[1].rest), "the first row does not")
    Kit.assertTrue(namesTerminalState(section.rows[1].rest), "the first row names an issue")
  end)

test("layoutcap self-test: a census outside its register, or at the wrong level, is not read",
  function()
    local sibling = HUB:gsub("### Files over", "## Files over")
    local at, why = parseCensus(sibling)
    Kit.assertNil(at, "a sibling of the register is not the census")
    Kit.assertTrue(why:find("outside the", 1, true) ~= nil, "and the reason says where it is: " .. why)

    local deeper = HUB:gsub("### Files over", "#### Files over")
    local _, level = parseCensus(deeper)
    Kit.assertTrue(level:find("level 4", 1, true) ~= nil, "a level too deep says so: " .. level)

    local renamed = HUB:gsub("### Files over the 1500%-line cap",
      "### Files by the `layout-§1` band")
    local _, gone = parseCensus(renamed)
    Kit.assertTrue(gone:find("closest heading", 1, true) ~= nil, "a renamed census: " .. gone)

    local noRegister = HUB:gsub("## Documented deviations", "## Notes")
    local _, orphan = parseCensus(noRegister)
    Kit.assertTrue(orphan:find("no `## Documented", 1, true) ~= nil, "no register: " .. orphan)
  end)

test("layoutcap self-test: an over-cap file missing from the census is reported, and an exempt "
  .. "one is not", function()
    local rows = parseCensus(HUB).rows
    local tree = { ["modules/Big.lua"] = 1702, ["Dump/Strings.lua"] = 23842,
                   ["modules/New.lua"] = 1600, ["modules/Small.lua"] = 40 }
    local exempt = { ["Dump/Strings.lua"] = true }

    local missing = audit(tree, rows, exempt)
    Kit.assertEqual(#missing, 1, "exactly the unremarked breach")
    Kit.assertEqual(missing[1], "modules/New.lua (1600 lines)", "named with its measurement")

    -- The carve-out as an input, and the whole reason it is one: drop the exempt set and the
    -- generated dump becomes a breach the repository cannot answer.
    local narrowed = audit(tree, {}, {})
    Kit.assertEqual(#narrowed, 3, "scoped without the exempt set, the dump is reported too")
  end)

test("layoutcap self-test: a census row that outlives its breach is reported", function()
  local rows = parseCensus(HUB).rows
  local _, spent = audit({ ["modules/Big.lua"] = 900, ["Dump/Strings.lua"] = 23842 }, rows,
    { ["Dump/Strings.lua"] = true })
  Kit.assertEqual(#spent, 1, "the peeled file's row")
  Kit.assertTrue(spent[1]:find("under the cap", 1, true) ~= nil, "says why: " .. spent[1])

  local _, gone = audit({ ["Dump/Strings.lua"] = 23842 }, rows, { ["Dump/Strings.lua"] = true })
  Kit.assertEqual(#gone, 1, "the deleted file's row")
  Kit.assertTrue(gone[1]:find("no authored file", 1, true) ~= nil, "says why: " .. gone[1])
end)

test("layoutcap self-test: an over-cap row that names no terminal state is reported", function()
  local tree = { ["modules/Big.lua"] = 1702 }
  local vague = { { path = "modules/Big.lua", rest = " 1702 | it is large " } }
  local _, _, unstated = audit(tree, vague, {})
  Kit.assertEqual(#unstated, 1, "a row that only acknowledges the line count")
  Kit.assertEqual(unstated[1], "modules/Big.lua", "named")

  for _, cell in ipairs{ " see #12 ", " the deviation row above ", " peel scheduled for 1.4.0 " } do
    local _, _, none = audit(tree, { { path = "modules/Big.lua", rest = cell } }, {})
    Kit.assertEqual(#none, 0, "each of the three terminal states is followable: " .. cell)
  end
end)

test("layoutcap self-test: the census and the exempt set are held to naming the same paths",
  function()
    local tree = { ["Dump/Strings.lua"] = 23842 }
    local marked = { { path = "Dump/Strings.lua", rest = " 23842 | Exempt — generated " } }

    local _, _, _, unbacked = audit(tree, marked, {})
    Kit.assertEqual(#unbacked, 1, "a row marked exempt that the opts table does not exempt")
    Kit.assertTrue(unbacked[1]:find("absent from the exempt set", 1, true) ~= nil, unbacked[1])

    local stated = { { path = "Dump/Strings.lua", rest = " 23842 | Issue #40 names the seam " } }
    local _, _, _, mismarked = audit(tree, stated, { ["Dump/Strings.lua"] = true })
    Kit.assertEqual(#mismarked, 1, "an exempt path whose row claims a terminal state instead")
    Kit.assertTrue(mismarked[1]:find("does not mark it exempt", 1, true) ~= nil, mismarked[1])

    local _, _, unstated, agreed = audit(tree, marked, { ["Dump/Strings.lua"] = true })
    Kit.assertEqual(#agreed, 0, "the two records agreeing is the whole of what the gate can see")
    Kit.assertEqual(#unstated, 0, "and an exempt row is never graded against the terminal states")
  end)

test("layoutcap self-test: a census that states nothing is told apart from one that states none",
  function()
    Kit.assertNil(censusShape(parseCensus(HUB)), "rows and prose beside them are a census")

    local empty = { rows = {}, prose = "" }
    local silent = censusShape(empty)
    Kit.assertTrue(silent ~= nil and silent:find("stands with nothing", 1, true) ~= nil,
      "a heading with nothing under it: " .. tostring(silent))

    local result = { rows = {}, prose = "Nothing is over the cap today." }
    Kit.assertNil(censusShape(result), "the same heading with the result written under it")

    local both = { rows = { { path = "modules/Big.lua", rest = " 1702 | #12 " } },
                   prose = "Nothing is over the cap today." }
    local stale = censusShape(both)
    Kit.assertTrue(stale ~= nil and stale:find("contradictory", 1, true) ~= nil,
      "the result and rows under it at once: " .. tostring(stale))
  end)

test("layoutcap self-test: the exempt set takes folders as well as paths", function()
  local tree = { ["Dump/One.lua"] = 2000, ["Dump/Two.lua"] = 2000, ["Dumpling.lua"] = 2000 }
  local folder = resolveExempt({ "Dump/" }, tree)
  Kit.assertTrue(folder["Dump/One.lua"] and folder["Dump/Two.lua"], "both files under the folder")
  Kit.assertFalse(folder["Dumpling.lua"] == true, "and nothing a prefix match would have swept in")

  local exact = resolveExempt({ ["Dump/One.lua"] = true }, tree)
  Kit.assertTrue(exact["Dump/One.lua"], "the map form names one path")
  Kit.assertFalse(exact["Dump/Two.lua"] == true, "and only that one")
end)
