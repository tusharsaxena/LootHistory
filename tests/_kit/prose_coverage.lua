-- testkit/prose_coverage.lua — the prose gate's narrowing machinery, peeled out of
-- `test_prose.lua` at kit revision 29 (issue #39).
--
-- WHAT IT HOLDS. Everything that reads a repository's DECLARED NARROWINGS of the gate, from all three
-- lists (`Kit.prose.exempt` in the runner, `skipDirs` and `skipFiles` in `tests/prose_waivers.lua`):
-- the validators, the one resolved coverage set, the TOC and `.pkgmeta` readers, the two refusals
-- that read that set and the disclosure line. Every function here is pure, apart from `fail`: text
-- and path lists in, findings out. `test_prose.lua`'s header is the account of why each piece exists.
--
-- WHY A SEPARATE FILE. `test_prose.lua` stood at 1486 lines, fourteen under `layout-§1`'s cap, and
-- this machinery was the seam issue #39 named. It moved unchanged: the same functions, in the same
-- order, with the same messages. What stayed in `test_prose.lua` is the path scan, the
-- British-spelling matcher, the waiver file's reader and the cases.
--
-- `test_prose.lua` loads it by path from its own folder, the way it loads `prose_lists.lua`, and
-- hands it the three things it reads from there: the kit's `fail`, and the `SCAN_BACK` and
-- `KIT_DIRS` sets `dirCovers` asks. Nothing else loads it. A copy of the kit without it fails at load.

local fail, SCAN_BACK, KIT_DIRS = ...

-- ---------------------------------------------------------------------------
-- The consumer facts: localization-§5's generated-data carve-out
-- ---------------------------------------------------------------------------

--- The opts table the runner sets on the kit, or an empty one.
---
--- A missing table is not a failure: an absent `exempt` means a repository with no generated data,
--- which is ten of the eleven. It rides on the kit table for the reason the suite takes the kit as
--- its chunk argument at all — the exposed table's global name belongs to the consumer (`LK_TEST`,
--- `AT_TEST`, …) and a vendored suite cannot know which one it is standing in.
---
--- The validator is split out from the reader BECAUSE OF A DEFECT THIS FILE SHIPPED: the self-test
--- for the absent case saved `Kit.prose`, set a bad value, RESTORED IT, and only then read it back,
--- so the assertion landed on the LIVE RUNNER's carve-out -- permanently green where none is
--- declared, permanently red in the one repository it exists for. In a pure function the self-tests
--- drive it over fixtures and no case here touches `Kit.prose`.
local function validateOptions(o)
    if o == nil then return {} end
    if type(o) ~= "table" then
        fail("prose gate: Kit.prose is the consumer-facts table -- { exempt = { ... } } -- and this "
            .. "runner set it to a " .. type(o), 3)
    end
    return o
end

--- True when the opts entry `entry` covers `path`: the path itself, or a folder containing it.
---
--- Globs are not expanded: an entry that would only match through one matches nothing, which errs
--- toward reporting a spelling rather than excusing a file nobody meant to excuse. The folder form
--- compares against `entry .. "/"`, so a sibling whose name merely STARTS with it —
--- `GlobalStringsNotes.md` beside `GlobalStrings/` — is not swept in by a prefix match.
local function exemptEntryCovers(entry, path)
    if entry == path then return true end
    local folder = (entry:sub(-1) == "/") and entry or (entry .. "/")
    return path:sub(1, #folder) == folder
end

--- The opts-borne exempt set, resolved against the tracked paths into a set of concrete paths.
---
--- Takes an array of paths and folders, a map of path to true, or both — a runner writes whichever
--- reads better beside the reason it is passing them, exactly as `Kit.layoutCap.exempt` does. An
--- entry matching nothing resolves to an empty set here; what becomes of it is the refusals' call.
-- The three lists a repository can narrow this gate by, spelled the way a message must name them.
-- A reader told only WHICH path was refused still has to guess which file to open, and two of the
-- three live in a different file from the third.
local SOURCE_EXEMPT    = "Kit.prose.exempt in tests/run.lua"
local SOURCE_SKIPDIRS  = "skipDirs in tests/prose_waivers.lua"
local SOURCE_SKIPFILES = "skipFiles in tests/prose_waivers.lua"
local SOURCE_WAIVED    = "waived in tests/prose_waivers.lua"

--- One list's entries as the repository wrote them, validated, in a stable order.
---
--- Shared by all three lists, so a malformed `skipDirs` is refused in the same words a malformed
--- `Kit.prose.exempt` is, and the scan and the refusals can never read one differently from the
--- other. `source` names the list in the message; it is the only thing that varies. Sorted, because
--- a set whose printed order depends on `pairs` is a line that changes when nothing did.
---
--- Array or map, either way. The map form's `false` value declares nothing and is dropped, which is
--- what it already meant to the scan.
local function declaredEntries(entries, source)
    source = source or SOURCE_EXEMPT
    local list = {}
    if entries == nil then return list end
    if type(entries) ~= "table" then
        fail("prose gate: " .. source .. " is a set of paths that narrow this gate, written as an "
            .. "array or as a map; this repository set it to a " .. type(entries), 3)
    end
    for key, value in pairs(entries) do
        local entry = (type(key) == "number") and value or (value and key)
        if entry ~= nil then
            if type(entry) ~= "string" then
                fail("prose gate: every entry in " .. source .. " is a tracked path or a folder "
                    .. "ending in `/`; this one is a " .. type(entry), 3)
            end
            list[#list + 1] = entry
        end
    end
    table.sort(list)
    return list
end

local function resolveExempt(entries, paths)
    local set = {}
    for _, entry in ipairs(declaredEntries(entries, SOURCE_EXEMPT)) do
        for _, path in ipairs(paths) do
            if exemptEntryCovers(entry, path) then set[path] = true end
        end
    end
    return set
end

-- ---------------------------------------------------------------------------
-- A declared narrowing, whichever of the three lists it was written in
-- ---------------------------------------------------------------------------

--- One entry a repository narrowed this gate by: the text it wrote, the list it wrote it in, and
--- the predicate saying which tracked paths that entry takes out of the scan.
---
--- `covers` is the CHANNEL'S OWN matching rule rather than a shared approximation, because the
--- refusals must refuse exactly what the scan suppresses: `exemptEntryCovers` for the carve-out,
--- `dirCovers`, the prefix-with-scan-back `filterPaths` asks for `skipDirs`, one exact key for
--- `skipFiles`.
local function narrowing(entry, source, covers)
    return { entry = entry, source = source, covers = covers }
end

--- The runner's carve-out, as narrowings.
local function exemptNarrowings(entries)
    local out = {}
    for _, entry in ipairs(declaredEntries(entries, SOURCE_EXEMPT)) do
        out[#out + 1] = narrowing(entry, SOURCE_EXEMPT,
            function(path) return exemptEntryCovers(entry, path) end)
    end
    return out
end

--- Whether a `skipDirs` entry, kit or repository, takes `path` out of the scan: the unanchored
--- prefix, except that a `SCAN_BACK` file is kept against a kit folder, and against a repository
--- entry that only restates one. `filterPaths` and the refusals both ask this, so a restated kit
--- folder cannot be disclosed or refused as covering the store-root file the scan reads.
local function dirCovers(dir, path)
    return path:sub(1, #dir) == dir and not (SCAN_BACK[path] and KIT_DIRS[dir])
end

--- The waiver file's two exclusion lists, as narrowings.
---
--- THE OLDER AND WIDER CHANNEL, and the one that went two revisions with no check on it at all: it
--- reaches the same exclusion sets, so it faces the same refusals and the same disclosure.
local function waiverNarrowings(rules)
    local out = {}
    for _, dir in ipairs(declaredEntries(rules.skipDirs, SOURCE_SKIPDIRS)) do
        out[#out + 1] = narrowing(dir, SOURCE_SKIPDIRS,
            function(path) return dirCovers(dir, path) end)
    end
    for _, file in ipairs(declaredEntries(rules.skipFiles, SOURCE_SKIPFILES)) do
        out[#out + 1] = narrowing(file, SOURCE_SKIPFILES,
            function(path) return path == file end)
    end
    return out
end

--- Every narrowing this repository declared, from all three lists, in one stable order.
local function allNarrowings(rules, exemptEntries)
    local out = exemptNarrowings(exemptEntries)
    for _, n in ipairs(waiverNarrowings(rules or {})) do out[#out + 1] = n end
    table.sort(out, function(a, b)
        if a.entry ~= b.entry then return a.entry < b.entry end
        return a.source < b.source
    end)
    return out
end

-- ---------------------------------------------------------------------------
-- The two carve-out conditions the repository root answers out loud
-- ---------------------------------------------------------------------------
--
-- Pure, every one of them: text in, findings out. They are driven by the self-tests in
-- `prose_selftests.lua` over the two real repositories' own `.toc` and `.pkgmeta` bodies held as fixtures, so the logic is
-- proved in every repository that vendors this kit rather than only in the one that happens to declare a
-- carve-out. This library repo declares none and has no `.toc` at all, so nothing else would.

--- A path as a TOC or a `.pkgmeta` spells it, rewritten the way git spells it: forward slashes, no
--- leading `./`, no trailing `/`. A TOC uses the client's backslashes; the two must be comparable.
local function normalizePath(path)
    path = path:gsub("\\", "/"):gsub("^%./", "")
    while path:sub(-1) == "/" do path = path:sub(1, -2) end
    return path
end

--- Every path a TOC body loads, as `{ path =, line =, toc = }`, resolved against the TOC's folder.
---
--- A TOC is line-oriented: `##` is a directive, `#` a comment, a blank line is nothing, and every
--- other line is a file the client loads. Paths are relative to the folder the TOC sits in, so a
--- vendored library's TOC names ITS files and not this repository's — which is why the folder is
--- prefixed rather than the line taken as a repository path.
local function tocLoads(tocPath, body)
    local dir = tocPath:match("^(.*/)") or ""
    local out, n = {}, 0
    for line in (body:gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local entry = line:match("^%s*(.-)%s*$")
        if entry ~= "" and entry:sub(1, 1) ~= "#" then
            out[#out + 1] = { path = dir .. normalizePath(entry), line = n, toc = tocPath }
        end
    end
    return out
end

--- The `ignore:` block of a `.pkgmeta` body, as an array of entries.
---
--- `.pkgmeta` is YAML the BigWigs packager reads and `ignore:` is a block sequence of paths
--- relative to the repository root. ONLY that key is read: a sibling key at column zero closes the
--- block, so `externals:` or `move-folders:` below can never be mistaken for ignores, while an
--- indented comment or a blank line leaves it open -- both ordinary in this collection's files.
local function pkgmetaIgnores(body)
    local out, inside = {}, false
    for line in (body:gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do
        local stripped = line:gsub("%s+$", "")
        if stripped:match("^ignore:%s*$") then
            inside = true
        elseif inside then
            local item = stripped:match("^%s+%-%s*(.+)$")
            if item then
                item = item:gsub("%s+#.*$", "")
                item = item:match('^"(.*)"$') or item:match("^'(.*)'$") or item
                out[#out + 1] = normalizePath(item)
            elseif stripped:match("^%S") then
                inside = false
            end
        end
    end
    return out
end

--- True when the `.pkgmeta` ignore entry `entry` keeps `path` out of the packaged zip.
---
--- Exact, a folder containing it, or the packager's `*` wildcard — matched against the whole path
--- and against the basename alone, because `- "*.bak"` means a backup anywhere and
--- `- media/logos/*.png` means one folder, and both spellings are in this collection today. A
--- non-match REFUSES, so the wildcard is read generously: too narrowly is a legitimate carve-out
--- a consumer cannot get past.
local function ignoreCovers(entry, path)
    entry, path = normalizePath(entry), normalizePath(path)
    if entry == "" then return false end
    if entry == path then return true end
    if path:sub(1, #entry + 1) == entry .. "/" then return true end
    if entry:find("*", 1, true) then
        local pattern = "^" .. entry:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".-") .. "$"
        if path:find(pattern) then return true end
        if (path:match("([^/]+)$") or path):find(pattern) then return true end
    end
    return false
end

-- ── one resolved coverage set, and the two refusals that read it ──────────────

--- Every narrowing with the tracked paths it actually suppresses, resolved through its OWN
--- `covers` rule, in the order `allNarrowings` sorted them and with each path list sorted.
---
--- ONE RESOLUTION FOR BOTH REFUSALS AND THE DISCLOSURE, WHICH IS THE POINT OF THIS FUNCTION. They
--- computed coverage apiece -- the TOC refusal asked `covers` about the paths a TOC loads, the
--- packaging refusal asked `.pkgmeta` about the ENTRY AS WRITTEN -- and for an unanchored
--- `skipDirs` prefix those are different questions: coverage spilled past the boundary the refusal
--- checked, and a shipped root file sat behind an ignored folder of nearly the same name with both
--- refusals green. Two computations of one fact is how they disagreed; one is how they cannot.
--- `paths` is what this gate would read had the repository declared nothing -- tracked, authored,
--- minus localization-§5's published exclusions -- so a coverage list is exactly what the entry
--- takes out of THIS scan.
local function coverageOf(narrowings, paths)
    local out = {}
    for _, n in ipairs(narrowings) do
        local covered = {}
        for _, path in ipairs(paths) do
            if n.covers(path) then covered[#covered + 1] = path end
        end
        table.sort(covered)
        out[#out + 1] = { entry = n.entry, source = n.source, paths = covered }
    end
    return out
end

--- `entry [source]`: what every refusal and the disclosure name a narrowing by. The list it came
--- from travels with it -- a line naming a path alone leaves the reader hunting two files for it.
local function coverageLabel(c) return c.entry .. " [" .. c.source .. "]" end

--- At most `max` of `paths`, with the remainder COUNTED rather than dropped quietly, and the line
--- saying it was bounded so nobody reads a truncated list as a complete one.
local function boundedPaths(paths, max)
    local shown = {}
    for i = 1, math.min(max, #paths) do shown[i] = paths[i] end
    local text = table.concat(shown, ", ")
    if #paths > #shown then
        text = text .. ", and " .. (#paths - #shown) .. " more (list bounded)"
    end
    return text
end

--- The disclosure's `by:` clause: each entry, the list it came from, how many tracked authored
--- files it suppressed, and WHICH ones.
---
--- Naming them is the half that was missing: a count with nothing under it is what made a
--- `.pkgmeta`-blessed entry over a shipped file read as ratified. Past `COVERAGE_LIST_MAX` paths
--- every entry falls back to its count and `COVERAGE_EXAMPLES` of them, saying the list is bounded.
local COVERAGE_LIST_MAX = 12
local COVERAGE_EXAMPLES = 3

local function coverageSummary(coverage)
    local named = 0
    for _, c in ipairs(coverage) do named = named + #c.paths end
    local max = (named > COVERAGE_LIST_MAX) and COVERAGE_EXAMPLES or named
    local out = {}
    for _, c in ipairs(coverage) do
        out[#out + 1] = coverageLabel(c) .. " (" .. #c.paths .. ")"
            .. ((#c.paths == 0) and ": nothing" or (": " .. boundedPaths(c.paths, max)))
    end
    return table.concat(out, "; ")
end

--- The narrowings some TOC loads a file through, named with the list they came from and with the
--- TOC line that loads it, sorted.
---
--- Read off the resolved coverage rather than off `covers` a second time, so this refusal and the
--- packaging one below can never again refuse two different things. A path a TOC names but this
--- scan would never read -- an `.xml` include, an untracked file -- is suppressed by nothing.
local function narrowingsLoadedByToc(coverage, loaded)
    local bad = {}
    for _, c in ipairs(coverage) do
        local covered = {}
        for _, path in ipairs(c.paths) do covered[path] = true end
        for _, hit in ipairs(loaded) do
            if covered[hit.path] then
                bad[#bad + 1] = coverageLabel(c) .. " (loads " .. hit.path .. ", line "
                    .. hit.line .. " of " .. hit.toc .. ")"
                break
            end
        end
    end
    table.sort(bad)
    return bad
end

--- True when some `.pkgmeta` ignore entry keeps `path` out of the packaged zip.
local function ignoredByPkgmeta(ignores, path)
    for _, ignore in ipairs(ignores) do
        if ignoreCovers(ignore, path) then return true end
    end
    return false
end

--- Two findings out of the ONE coverage set: the narrowings `.pkgmeta` does not keep out of the
--- zip, and the narrowings that suppress nothing at all.
---
--- ASKED OF THE ENTRY AS WRITTEN AND OF EVERY PATH IT COVERS, because those are not one question.
--- The entry arm is deliberate strictness -- an entry covering nothing today still has to be one
--- the packager would drop if it covered something tomorrow -- and the coverage arm closes what
--- that arm left open: coverage spills past the boundary it checks, past a `.pkgmeta` that blessed
--- the entry and shipped the file.
---
--- AN ENTRY COVERING NOTHING IS REPORTED SEPARATELY, and only where the entry arm already refused
--- it: the problem there is the entry's SPELLING, and the same run's disclosure says it suppressed
--- nothing, so sending the reader to `.pkgmeta` prints two lines that contradict each other. It
--- stays red; a stale entry `.pkgmeta` DOES cover stays stale rather than silent and not a failure,
--- as `Kit.layoutCap.exempt` treats one.
local function narrowingsNotIgnored(coverage, ignores)
    local bad, unmatched = {}, {}
    for _, c in ipairs(coverage) do
        if not ignoredByPkgmeta(ignores, c.entry) then
            local into = (#c.paths == 0) and unmatched or bad
            into[#into + 1] = coverageLabel(c)
        else
            local shipped = {}
            for _, path in ipairs(c.paths) do
                if not ignoredByPkgmeta(ignores, path) then shipped[#shipped + 1] = path end
            end
            if #shipped > 0 then
                bad[#bad + 1] = coverageLabel(c) .. " (.pkgmeta ignores the entry, but it "
                    .. "suppresses " .. #shipped .. " packaged file(s) it does not name: "
                    .. boundedPaths(shipped, COVERAGE_EXAMPLES) .. ")"
            end
        end
    end
    table.sort(bad)
    table.sort(unmatched)
    return bad, unmatched
end

return {
    validateOptions       = validateOptions,
    SOURCE_EXEMPT         = SOURCE_EXEMPT,
    SOURCE_SKIPDIRS       = SOURCE_SKIPDIRS,
    SOURCE_SKIPFILES      = SOURCE_SKIPFILES,
    SOURCE_WAIVED         = SOURCE_WAIVED,
    resolveExempt         = resolveExempt,
    dirCovers             = dirCovers,
    waiverNarrowings      = waiverNarrowings,
    allNarrowings         = allNarrowings,
    tocLoads              = tocLoads,
    pkgmetaIgnores        = pkgmetaIgnores,
    ignoreCovers          = ignoreCovers,
    coverageOf            = coverageOf,
    coverageSummary       = coverageSummary,
    narrowingsLoadedByToc = narrowingsLoadedByToc,
    narrowingsNotIgnored  = narrowingsNotIgnored,
}
