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
