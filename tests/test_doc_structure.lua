-- tests/test_doc_structure.lua — the two documented shapes documentation-§1 and §3 fix in place.
--
-- WHAT IT PROVES. Three things a reader can check and nothing else in this repository does:
-- that docs/ARCHITECTURE.md still carries the ten sections `documentation-§3` names for the hub;
-- that every markdown link pointing INTO one of that file's headings lands on a heading that
-- exists; and that README.md carries the two player-facing history surfaces `documentation-§1`
-- allows — `## What's new in <X.Y.Z>` and `## Version History` — and no third.
--
-- WHY THE THIRD CASE EXISTS. This README grew a `## Unreleased` section holding two fixes that had
-- landed since the 1.2.0 tag. Nothing about it was dishonest, and that is the trap: a third history
-- surface is useful right up to the moment someone bumps the version, rolls the release notes into
-- `## What's new` and `## Version History` from the git log the way `wow-addon:bump-version` does,
-- and leaves the third one behind. Then the repository states two versions of what shipped and the
-- stale one is the one at the top of the page. §1 gives the history exactly two homes for that
-- reason, and §3 adds that `docs/` is not where a forbidden root doc goes to live — so the check
-- covers the whole tracked markdown set, not just README.md.
--
-- The section removed here lost nothing. Both bullets describe commits on this branch (the chart
-- pools recycling, and the RecordAdded repaint coalescing), and `## What's new` is defined by §1 as
-- "everything since the last `x.y.z`-release tag" — which is where the next bump reads them from.
--
-- WHAT IT DOES NOT DO, DELIBERATELY. It does not check that `## What's new` names the TOC's version,
-- and it does not check heading ORDER. The first is `wow-addon:bump-version`'s job and pinning it
-- here would redden the tree between the bump's own two edits; the second would go red on every
-- ordinary addition, which is a gate with a standing reason to be switched off.
--
-- IT FAILS RATHER THAN PASSES WHEN IT CANNOT LOOK. No `io.popen`, no git, no ARCHITECTURE.md and no
-- README.md are each a failure, not a skip — the same bargain tests/_kit/test_eol.lua strikes.

local T = _G.LH_TEST
local test, fail, assertTrue = T.test, T.fail, T.assertTrue
local assertEqual = T.assertEqual
local ROOT = T.root or "."

local ARCHITECTURE = "docs/ARCHITECTURE.md"
local README       = "README.md"

-- `documentation-§3`'s ten mandated hub sections, named rather than counted because a bare count
-- goes stale silently. Matched case-insensitively: the collection is split between `## Module map`
-- and `## Module Map`, and the section names a section, not a capitalization.
local MANDATED = {
  "Overview", "Module Map", "Settings Schema", "Message Bus", "Slash Commands",
  "Event Subscriptions", "Taint Notes", "Known Limitations",
  "Documentation map", "Documented deviations",
}

-- The history surfaces `documentation-§1` does NOT allow, as case-insensitive heading words. A
-- fourth spelling someone invents is caught by none of these, which is why the two ALLOWED forms
-- are asserted positively below rather than this list being the whole gate.
local FORBIDDEN_HISTORY = {
  "unreleased", "changelog", "change log", "release notes", "upcoming",
  "next release", "recent changes", "in development",
}

-- `documentation-§1`'s README section list, in its order. Item 4 (Description) and the badge row
-- are not headings, so the sequence starts at item 5. `## How <it> works` is domain-titled by the
-- section's own instruction, which is why it is a pattern and not a name. `required = false` marks
-- the SHOULD and MAY sections — omit one only when it would be empty, but when present the relative
-- order MUST hold.
local README_ORDER = {
  { pattern = "^What's new in ",       required = true,  name = "## What's new in <X.Y.Z>" },
  { pattern = "^Screenshots$",          required = false, name = "## Screenshots" },
  { pattern = "^Usage$",                required = true,  name = "## Usage" },
  { pattern = "^How .+ works?$",        required = true,  name = "## How <it> works" },
  { pattern = "^FAQ$",                  required = false, name = "## FAQ" },
  { pattern = "^Troubleshooting$",      required = false, name = "## Troubleshooting" },
  { pattern = "^Issues and feature requests$", required = true, name = "## Issues and feature requests" },
  { pattern = "^Version History$",      required = true,  name = "## Version History" },
  { pattern = "^Credits$",              required = false, name = "## Credits" },
}

--- A file's contents with line endings normalized, or a failure.
local function read(rel)
  local fh = io.open(ROOT .. "/" .. rel, "r")
  if not fh then fail("doc gate: " .. rel .. " could not be opened", 2) end
  local body = fh:read("*a") or ""
  fh:close()
  return (body:gsub("\r\n", "\n"))
end

--- Every heading in a file, as { level, text } in document order.
local function headings(rel)
  local out = {}
  for line in (read(rel) .. "\n"):gmatch("([^\n]*)\n") do
    local hashes, text = line:match("^(#+)%s+(.-)%s*$")
    if hashes then out[#out + 1] = { level = #hashes, text = text } end
  end
  return out
end

--- `## <Name>` as a case-insensitive whole-line pattern.
local function heading(name)
  return "^##%s+" .. name:gsub("%a", function(c)
    return "[" .. c:upper() .. c:lower() .. "]"
  end):gsub(" ", "%%s+") .. "%s*$"
end

--- GitHub's heading-fragment slug: lowercased, formatting and punctuation dropped, spaces hyphened.
local function slug(text)
  local s = text:lower():gsub("`", "")
  s = s:gsub("[^%w%s%-]", "")
  s = s:gsub("%s+", "-")
  return s
end

--- Every markdown path git tracks, minus the vendored and frozen trees.
---
--- `git ls-files` rather than a directory walk: Lua 5.1 has no directory API, and the tracked set is
--- the right set anyway. `libs/` and `tests/_kit/` are vendored whole and byte-pinned by
--- tests/test_vendor_sync.lua; the dated bundles under `docs/audits/`, `docs/reviews/`,
--- `docs/automated-tests/`, `docs/revendor/`, `docs/perf-analysis/` and `docs/superpowers/` are
--- frozen records of the tree as it stood on their stamp, so a heading this repository no longer
--- carries is history inside one of them rather than a defect.
local function trackedMarkdown()
  if not io.popen then
    fail("doc gate: io.popen is unavailable, so this gate cannot run and must not be reported as "
      .. "passing", 2)
  end
  local p = io.popen("git ls-files '*.md' 2>/dev/null")
  if not p then
    fail("doc gate: io.popen returned no handle, so this gate cannot run and must not be reported "
      .. "as passing", 2)
  end
  local out = {}
  for path in p:lines() do
    local frozen = path:match("^libs/") or path:match("^tests/_kit/")
      or path:match("^docs/audits/") or path:match("^docs/reviews/")
      or path:match("^docs/automated%-tests/") or path:match("^docs/revendor/")
      or path:match("^docs/perf%-analysis/") or path:match("^docs/superpowers/")
    if not frozen then out[#out + 1] = path end
  end
  p:close()
  if #out == 0 then
    fail("doc gate: git tracks no markdown outside the vendored and frozen trees, which cannot be "
      .. "true here — treating a blind gate as a failure", 2)
  end
  return out
end

test("docs/ARCHITECTURE.md carries the ten sections documentation-§3 names", function()
  local body, missing = read(ARCHITECTURE), {}
  for _, name in ipairs(MANDATED) do
    local pattern, found = heading(name), false
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
      if line:match(pattern) then found = true break end
    end
    if not found then missing[#missing + 1] = "## " .. name end
  end
  assertTrue(#missing == 0, ARCHITECTURE .. " is missing " .. table.concat(missing, ", ")
    .. " — §3 names all ten rather than counting them, because a count goes stale in silence")
end)

test("every anchor pointing into docs/ARCHITECTURE.md resolves to a heading", function()
  local slugs = {}
  for _, h in ipairs(headings(ARCHITECTURE)) do slugs[slug(h.text)] = true end
  local dead = {}
  for _, path in ipairs(trackedMarkdown()) do
    local body = read(path)
    for frag in body:gmatch("%]%([^%)%s]-ARCHITECTURE%.md#([^%)%s]+)%)") do
      if not slugs[frag] then dead[#dead + 1] = path .. " -> #" .. frag end
    end
    if path == ARCHITECTURE then
      for frag in body:gmatch("%]%(#([^%)%s]+)%)") do
        if not slugs[frag] then dead[#dead + 1] = path .. " -> #" .. frag end
      end
    end
  end
  assertTrue(#dead == 0, "anchors into " .. ARCHITECTURE .. " that land on no heading: "
    .. table.concat(dead, ", "))
end)

test("the player-facing history has the two homes documentation-§1 allows, and no third", function()
  local whatsNew, versionHistory = 0, 0
  for _, h in ipairs(headings(README)) do
    if h.level == 2 then
      if h.text:match("^What's new in ") then whatsNew = whatsNew + 1 end
      if h.text:lower() == "version history" then versionHistory = versionHistory + 1 end
    end
  end
  assertTrue(whatsNew == 1, README .. " must carry exactly one `## What's new in <X.Y.Z>`; found "
    .. whatsNew)
  assertTrue(versionHistory == 1, README .. " must carry exactly one `## Version History`; found "
    .. versionHistory)

  -- And nowhere in the tracked markdown — §3's "docs/ is not where a forbidden root doc goes to
  -- live" is the same rule one directory down.
  local extra = {}
  for _, path in ipairs(trackedMarkdown()) do
    for _, h in ipairs(headings(path)) do
      local text = h.text:lower():gsub("[^%a%s]", ""):gsub("^%s+", ""):gsub("%s+$", "")
      for _, word in ipairs(FORBIDDEN_HISTORY) do
        if text == word then extra[#extra + 1] = path .. " -> ## " .. h.text end
      end
    end
    if path:match("CHANGELOG%.md$") then extra[#extra + 1] = path end
  end
  assertTrue(#extra == 0, "a third player-facing history surface, which documentation-§1 gives "
    .. "exactly two homes: " .. table.concat(extra, ", "))
end)

test("README.md's top-level sections are the ones documentation-§1 names, in its order", function()
  local cursor, out, seen = 1, {}, {}
  for _, h in ipairs(headings(README)) do
    if h.level == 2 then
      local at
      for i = cursor, #README_ORDER do
        if h.text:match(README_ORDER[i].pattern) then at = i break end
      end
      if at then
        cursor, seen[at] = at, true
      else
        -- Either a section §1 does not name, or one of its sections out of order. Both read the
        -- same from here and both are the finding: `## Auction-house pricing` sat between Usage
        -- and How attribution works, which is neither a listed section nor a listed position.
        out[#out + 1] = "## " .. h.text
      end
    end
  end
  assertTrue(#out == 0, README .. " carries a top-level section §1 does not name, or names in a "
    .. "different position: " .. table.concat(out, ", ") .. ". Detail that wants a home of its own "
    .. "folds into the listed section it belongs to, or moves under docs/")

  local absent = {}
  for i, entry in ipairs(README_ORDER) do
    if entry.required and not seen[i] then absent[#absent + 1] = entry.name end
  end
  assertTrue(#absent == 0, README .. " is missing " .. table.concat(absent, ", "))
end)

-- ── The deviation register's own citations resolve ─────────────────────────────

-- `audit-review-history`'s third MUST: an id a register row cites in **Why** has to resolve -- a
-- deviation id into `docs/audits/`, a finding id into `docs/reviews/`, an issue number onto this
-- repo. An id that resolves to nothing is worse than no citation at all, because it reads as
-- evidence and leads to none, and it survives every re-read by a maintainer who knows the shape of
-- an id and never goes looking for what it names.
--
-- The check is deliberately NOT "the string appears somewhere under `docs/audits/`". A bundle that
-- REPORTS a dead citation quotes the dead id while doing so, so a substring search goes green on
-- the very defect it was written for -- `testing-§12`'s failure mode, sitting inside the gate for
-- it. What counts is the id being ASSIGNED: standing at the head of a markdown table cell, a
-- heading or a bullet, which is where every bundle in this repo puts a row's own id, and where
-- prose that merely mentions one never puts it.
--
-- Scope is the **deviation** id -- this repo's own audit-bundle prefix, which is what
-- `documentation-§3` puts in a row's Why cell and what a bundle under `docs/audits/` assigns.

local DEVIATION_ID = { "%f[%w]LH%-[%u%-]*%d+", "%f[%w]LOOTHISTORY%-[%u%-]*%d+" }

--- Every `.md` under a dated bundle directory.
local function bundleFiles()
  if not io.popen then
    fail("register gate: io.popen is unavailable, so this gate cannot run and must not be reported "
      .. "as a pass")
  end
  local p = io.popen("ls -1 " .. ROOT .. "/docs/audits/*/*.md 2>/dev/null")
  if not p then fail("register gate: io.popen returned no handle") end
  local out, prefix = {}, ROOT .. "/"
  for line in p:lines() do
    if line ~= "" then
      out[#out + 1] = (line:sub(1, #prefix) == prefix) and line:sub(#prefix + 1) or line
    end
  end
  p:close()
  return out
end

--- Does `id` head a table cell, a heading or a bullet anywhere in `files`?
local function isAssigned(id, files)
  local function heads(s)
    return s:sub(1, #id) == id and not s:sub(#id + 1, #id + 1):match("[%w%-]")
  end
  for _, path in ipairs(files) do
    for line in (read(path) .. "\n"):gmatch("([^\n]*)\n") do
      local trimmed = line:gsub("^%s+", "")
      local lead = trimmed:match("^#+%s*(.*)$") or trimmed:match("^[%-%*]%s+(.*)$")
      if lead and heads((lead:gsub("^[%s%*`%[]+", ""))) then return true end
      if trimmed:sub(1, 1) == "|" then
        for field in (trimmed .. "|"):gmatch("([^|]*)|") do
          if heads((field:gsub("^[%s%*`%[]+", ""))) then return true end
        end
      end
    end
  end
  return false
end

test("every deviation id the register cites is assigned by a bundle in docs/audits/", function()
  -- The sentinel is what lets the register be the file's LAST `##` section without the slice
  -- silently coming back nil and the case passing on an empty string.
  local body = read(ARCHITECTURE) .. "\n## \n"
  local section = body:match("\n## Documented deviations\r?\n(.-)\r?\n## ")
  assertTrue(section ~= nil,
    "docs/ARCHITECTURE.md has no `## Documented deviations` section to read")

  local files = bundleFiles()
  if #files == 0 then fail("register gate: no bundle files under docs/audits/ to resolve against") end

  local seen, cited, offenders = {}, 0, {}
  for _, pattern in ipairs(DEVIATION_ID) do
    for pos, id in section:gmatch("()(" .. pattern .. ")") do
      -- A hyphen in front means this is the tail of a longer id (a work-item `M1-LK-11`), not a
      -- citation of a bundle row.
      if section:sub(pos - 1, pos - 1) ~= "-" and not id:find("%-R%-") and not seen[id] then
        seen[id] = true
        cited = cited + 1
        if not isAssigned(id, files) then offenders[#offenders + 1] = id end
      end
    end
  end

  assertTrue(cited > 0,
    "the register cites no deviation id at all -- either the rows changed or DEVIATION_ID did")
  assertEqual(#offenders, 0,
    "cited by a register row and assigned by no bundle under docs/audits/: "
      .. table.concat(offenders, ", "))
end)

-- ── The smoke suite's non-English-client section ───────────────────────────────

-- WHAT IT PROVES, AND WHAT IT DOES NOT. That docs/smoke-tests.md still carries a section addressed
-- to a non-English client, that the section names the locale to run it on, and that it says what a
-- failure looks like rather than only what a pass does. It proves nothing whatever about that
-- section having been RUN -- a checklist is a checklist, and this repository has no client.
--
-- WHY THIS REPOSITORY IN PARTICULAR. core/Compat.lua defines four English wordings as the fallback
-- for when the client leaves the ITEM_ACCOUNTBOUND* globals nil, and the same file calls the
-- tooltip "the ONLY witness" for items whose bind type lies. Every headless case for that path
-- asserts against enUS mock globals -- tests/test_compat.lua passes the literal strings
-- "Auction House" and "Auction won: %s" in, and checks that they come back out. So the suite is
-- green on that path whether it is right or wrong: the test and the bug agree with each other, and
-- section 18 is the only thing in this repository that looks at it from the other side.
--
-- The failure vocabulary is matched loosely on purpose: this file's sections say "Fail" where
-- others say "the finding", and pinning one spelling would redden the tree for a rewording.
local LOCALE_HEADING = "[Nn]on%-English client"
local FAILURE_WORDS = { "Fail", "failure", "Failure", "the finding" }

test("docs/smoke-tests.md carries a non-English-client section", function()
  local body = read("docs/smoke-tests.md")

  local capture, level, section = false, nil, {}
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    local hashes = line:match("^(#+)%s")
    if hashes and capture and #hashes <= level then break end
    if hashes and not capture and line:match(LOCALE_HEADING) then
      capture, level = true, #hashes
    end
    if capture then section[#section + 1] = line end
  end
  assertTrue(capture, "docs/smoke-tests.md has no heading naming a non-English client. The step is "
    .. "unconditional (M5-08): where an addon reads nothing localized the section still ships and "
    .. "says what it checked and why it came back empty")

  local text = table.concat(section, "\n")
  assertTrue(text:find("deDE", 1, true) or text:find("frFR", 1, true),
    "the non-English-client section names no client to run it on -- deDE and frFR are the two the "
    .. "collection's other locale steps use")

  local named = false
  for _, word in ipairs(FAILURE_WORDS) do
    if text:find(word, 1, true) then named = true break end
  end
  assertTrue(named, "the non-English-client section says what passing looks like and never what "
    .. "failing looks like. A step whose only outcome is 'it works' is unfalsifiable in a client "
    .. "the operator booted specially")

  assertTrue(#section >= 10, "the non-English-client section is " .. #section .. " lines -- a "
    .. "heading with a sentence under it records the gap as coverage, which is the failure M5-08 "
    .. "was filed for")
end)
