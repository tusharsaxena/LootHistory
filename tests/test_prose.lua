-- tests/test_prose.lua — the US-English prose gate (localization-§5).
--
-- WHAT IT PROVES. That no authored file this repository tracks carries a British spelling from
-- localization-§5's published `BRITISH` list, once the `ALLOWED` US words that contain one of those
-- substrings have been taken out as whole words. Source, locale files, the TOC, README.md and every
-- document under docs/ — the whole authored set, read from git.
--
-- WHY IT EXISTS, in this repo specifically. It did not, until 2026-09-22, and the collection-wide
-- sweep of that day found 100 lines across 34 files -- the most of any addon here. Thirteen sat in
-- docs/smoke-tests.md, seven in docs/performance.md, five in the lifecycle seam. Nothing in the
-- repository could see one of them: `luacheck` does not read English, and every other suite here
-- reads behavior. A sweep is a measurement of one afternoon; this is what makes it a property.
--
-- BOTH LISTS ARE COPIED WHOLE, AND NOTHING IS ADDED. localization-§5 is explicit that a gate MUST
-- carry every `BRITISH` entry and every `ALLOWED` entry and MUST NOT carry an entry the section does
-- not publish, because a private list is a coverage claim no reader outside this repo can check —
-- LibKa0s shipped six substrings for months and stayed green while `CANCELLED` went out in chat text
-- a player reads. If a sweep here finds a British form the published list misses, it is amended in
-- the standard first and arrives here on the next sync; it does not get added locally.
--
-- IT FAILS RATHER THAN PASSES WHEN IT CANNOT LOOK. No `io.popen`, no git, an unreadable tracked file
-- — every one of those is a failure, not a skip. A gate that goes quiet when it is blind reports
-- success, which is worse than not existing. Same bargain tests/_kit/test_eol.lua and
-- tests/test_layout_cap.lua strike.

local h = _G.LH_TEST
local test, fail = h.test, h.fail
local ROOT = _G.LH_TEST_ROOT or "."

-- ---------------------------------------------------------------------------
-- The published lists (localization-§5), copied whole
-- ---------------------------------------------------------------------------

-- localization-§5 · US English is the source dialect. Copy BOTH lists whole.
-- BRITISH: lowercase substrings, matched case-insensitively.
-- ALLOWED: correct US words that contain a BRITISH substring; removed as WHOLE WORDS first.

local BRITISH = {
    -- -our → -or
    "colour", "behaviour", "favour", "honour", "neighbour", "armour", "flavour",
    "labour", "rumour", "humour", "endeavour", "rigour", "vigour", "saviour",
    -- -re → -er
    "centre", "centring", "metre", "fibre", "calibre", "theatre", "manoeuvre",
    -- -ce → -se
    "defence", "licence", "offence", "pretence", "practis",
    -- -ise / -isation → -ize / -ization, and the -yse verbs
    "initialis", "normalis", "generalis", "specialis", "optimis", "customis",
    "serialis", "summaris", "utilis", "organis", "authoris", "prioritis",
    "alphabetis", "categoris", "sanitis", "visualis", "minimis", "maximis",
    "itemis", "randomis", "tokenis", "capitalis", "localis", "modularis",
    "standardis", "memois", "recognis", "analys", "paralys", "synthesis",
    "emphasis",
    -- a doubled consonant before a suffix, where US English keeps one
    "cancelled", "cancelling", "cancellable", "labelled", "labelling",
    "travelled", "travelling", "modelled", "modelling", "signalled",
    "signalling", "levelled", "levelling", "fuelled", "fuelling", "totalled",
    "totalling", "fulfil",
    -- -ogue → -og
    "catalogue", "dialogue", "analogue",
    -- no family, just British
    "grey", "artefact", "whilst", "amongst", "learnt", "ageing", "enquir",
    "acknowledgement", "judgement", "sceptic", "mould", "sulphur", "programme",
}

local ALLOWED = {
    "analysis", "analyses", "analyst", "analysts",
    "organism", "organisms", "organist",
    "specialist", "specialists", "generalist", "generalists",
    "optimism", "optimist", "optimists", "optimistic", "optimistically",
    "paralysis", "paralyses", "synthesis", "syntheses", "emphasis", "emphases",
    "fulfill", "fulfills", "fulfilled", "fulfilling", "fulfillment",
    "programmer", "programmers", "programmed",
}

-- The published block is 91 substrings and 30 allowances. The counts are a tripwire, not a proof —
-- a copy that drops one entry and invents another passes them — but the failure mode they catch is
-- the one that actually happens, which is a list arriving truncated or half-pasted. The proof is a
-- diff of the block above against localization-§5, and `/wow-addon:revendor-standards` is when it
-- gets run.
local PUBLISHED_BRITISH, PUBLISHED_ALLOWED = 91, 30

-- ---------------------------------------------------------------------------
-- What is scanned, and what is not
-- ---------------------------------------------------------------------------

-- Named directory by directory and file by file, as localization-§5 requires, so the exclusion list
-- cannot quietly grow by widening a pattern. Four categories and nothing else:
--
--   * vendored code this repo MUST NOT edit — `libs/` and `tests/_kit/`. A kit or library problem is
--     a finding to fix in LibKa0s and re-vendor; tests/test_vendor_sync.lua holds that line.
--   * frozen dated bundles, which are the record of what a tool said on the day rather than authored
--     prose, and are not rewritten. There is no CHANGELOG.md here to add — documentation-§1 permits
--     one only in a Ka0s-owned library repo.
--   * `locales/enGB.lua`, which is what a British locale file is for. This repo ships enUS only; the
--     carve-out is written down here rather than discovered by whoever adds the file.
--   * this file, which quotes every forbidden spelling in order to forbid it.
--
-- docs/superpowers/ is deliberately NOT excluded. Its plans and specs are dated, but they are
-- authored prose that people still read, not a tool's frozen output, and they are clean today.
local SKIPPED_DIRS = {
    "libs/",
    "tests/_kit/",
    "docs/audits/",
    "docs/automated-tests/",
    "docs/perf-analysis/",
    "docs/reviews/",
    "docs/revendor/",
}

--- A spelling that is NOT this repository's English to correct, per FILE and per WORD.
---
--- Per word rather than per file, because the whole-file form would hide every other British
--- spelling in a file this repo edits often -- and `core/LifecycleSetup.lua` is one of them.
---
--- `cancelled` is AceTimer's field name, not our prose. `NS.After` records the flag on its own
--- handle as `h.cancelled` because that is what `tests/_kit/mock_record.lua`'s live-timer survey
--- reads off a handle (`:103`, `:106`, `:123`) and what AceTimer-3.0 calls the same field. A US
--- respelling here would not be a correction: the survey would stop seeing a canceled deferral as
--- canceled, and the stand-down suite's timer assertion would go quietly unfalsifiable, which is
--- exactly what slash-commands-§7 says a conformance suite must not be.
local WAIVED = {
    ["core/LifecycleSetup.lua"] = { cancelled = true },
}

local SKIPPED_FILES = {
    ["locales/enGB.lua"] = true,
    ["tests/test_prose.lua"] = true,
}

--- True when `path` is authored text this section has an opinion about.
---
--- Extension rather than directory, because the authored set is not one tree: locale values sit in
--- `locales/`, comments in `core/`, prose in `docs/` and the TOC's own notes at the root. `.luacheckrc`
--- is named on its own — it is authored Lua with authored comments wearing a different extension, and
--- an extension rule alone would miss it.
local function isAuthoredText(path)
    return path:find("%.lua$") or path:find("%.md$") or path:find("%.toc$") or path == ".luacheckrc"
end

--- Split a NUL-delimited blob. `git ls-files -z` because a path may contain anything but NUL, and the
--- line-oriented form quotes such a path instead of printing it — a quoted path would not open, and
--- this gate would then report a read failure that is really a parse failure.
local function splitNul(blob)
    local out, start = {}, 1
    while true do
        local i = blob:find("\0", start, true)
        if not i then break end
        if i > start then out[#out + 1] = blob:sub(start, i - 1) end
        start = i + 1
    end
    return out
end

--- Every authored path git tracks, minus the four named exclusions, in git's order.
local function scannedPaths()
    if not io.popen then
        fail("prose gate: io.popen is unavailable, so the tracked set cannot be read and this gate "
            .. "must not be reported as passing", 2)
    end
    local pipe = io.popen("git -C '" .. ROOT .. "' ls-files -z")
    if not pipe then
        fail("prose gate: io.popen returned no handle for `git ls-files`, so this gate cannot run "
            .. "and must not be reported as passing", 2)
    end
    local blob = pipe:read("*a") or ""
    pipe:close()

    local paths = {}
    for _, path in ipairs(splitNul(blob)) do
        if isAuthoredText(path) and not SKIPPED_FILES[path] then
            local skip = false
            for _, dir in ipairs(SKIPPED_DIRS) do
                if path:sub(1, #dir) == dir then skip = true break end
            end
            if not skip then paths[#paths + 1] = path end
        end
    end
    if #paths == 0 then
        fail("prose gate: `git ls-files` reported no authored files, which cannot be true here — "
            .. "either git is unavailable or this is not a repository; this gate cannot run, and "
            .. "must not be reported as passing", 2)
    end
    return paths
end

--- The British substrings present in one line, after `ALLOWED` has been taken out as whole words.
---
--- Whole words, and before the scan, exactly as localization-§5 requires. Delimit on non-letters,
--- drop a token that IS an allowance, and run the substrings over what is left. Matching `ALLOWED` as
--- a substring instead would swallow *analysed* inside the allowance for *analyses* and hide the
--- defect this gate exists to find.
local ALLOWED_SET = {}
for _, word in ipairs(ALLOWED) do ALLOWED_SET[word] = true end

local function britishIn(line)
    local lowered = line:lower()
    local kept = lowered:gsub("%a+", function(token)
        if ALLOWED_SET[token] then return "" end
        return token
    end)

    local found
    for _, entry in ipairs(BRITISH) do
        if kept:find(entry, 1, true) then
            found = found or {}
            found[#found + 1] = entry
        end
    end
    return found
end

-- ---------------------------------------------------------------------------
-- The gate
-- ---------------------------------------------------------------------------

test("prose: no authored file carries a British spelling from localization-§5's published list",
function()
    local hits = {}
    for _, path in ipairs(scannedPaths()) do
        local fh = io.open(ROOT .. "/" .. path, "r")
        if not fh then
            fail("prose gate: git tracks " .. path .. " but it cannot be opened", 2)
        end
        local body = fh:read("*a") or ""
        fh:close()

        local n = 0
        for line in (body:gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do
            n = n + 1
            local found = britishIn(line)
            if found and WAIVED[path] then
                local kept = {}
                for _, entry in ipairs(found) do
                    if not WAIVED[path][entry] then kept[#kept + 1] = entry end
                end
                found = #kept > 0 and kept or nil
            end
            if found then
                hits[#hits + 1] = string.format("%s:%d - %s", path, n, table.concat(found, ", "))
            end
        end
    end

    if #hits > 0 then
        -- Name every one of them rather than the first. These arrive a whole commit at a time — one
        -- rename ripples through a case name, its inventory line and three comments — and clearing
        -- them a red run at a time is the slowest possible way to learn how many there were.
        fail(#hits .. " line(s) of authored text carry a British spelling (localization-§5). US "
            .. "English is the source dialect: WoW's own API is US-spelled, so a British-spelled "
            .. "identifier sits one letter from the Blizzard symbol beside it and a `grep -r color` "
            .. "silently misses half its call sites. Correct each, and if the spelling is a locale "
            .. "KEY move every locales/*.lua file and every call site in the same change:\n          "
            .. table.concat(hits, "\n          "), 2)
    end
end)

test("prose: the gate carries localization-§5's two lists whole, and nothing of its own", function()
    if #BRITISH ~= PUBLISHED_BRITISH or #ALLOWED ~= PUBLISHED_ALLOWED then
        fail(string.format("the copied lists are %d BRITISH and %d ALLOWED entries; "
            .. "localization-§5 publishes %d and %d. A gate carrying a subset is the second "
            .. "anti-pattern stacked on the first (#46, testing-§12): it reads as coverage and "
            .. "provides none. Re-copy both blocks whole",
            #BRITISH, #ALLOWED, PUBLISHED_BRITISH, PUBLISHED_ALLOWED), 2)
    end

    -- The section's prose says an allowance is a correct US word that CONTAINS a British substring,
    -- and two of the published thirty do not: `syntheses` and `emphases` are the plurals of
    -- `synthesis` and `emphasis`, and neither plural contains its own entry. So that containment rule
    -- is described here rather than asserted. A gate that reddens on the list it is required to copy
    -- whole gets deleted rather than obeyed, and the divergence is the standard's to settle, not this
    -- repository's to paper over with a local edit.

    -- Lowercase, because the scan lowercases the line and compares literally. An upper-case entry
    -- would never match anything and would sit in the list looking like coverage.
    local shouty = {}
    for _, entry in ipairs(BRITISH) do
        if entry ~= entry:lower() then shouty[#shouty + 1] = entry end
    end
    if #shouty > 0 then
        fail("BRITISH entries that are not lowercase, and therefore match nothing: "
            .. table.concat(shouty, ", "), 2)
    end
end)
