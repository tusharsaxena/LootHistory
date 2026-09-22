-- testkit/test_prose.lua — the US-English prose gate (localization-5), over every file git tracks.
--
-- WHAT IT PROVES. That no authored file this repository tracks carries a British spelling from
-- localization-5's published `BRITISH` list, once the `ALLOWED` US words that contain one of those
-- substrings have been taken out as whole words. Source, locale files, the TOC, `README.md` and
-- every document under `docs/` — the whole authored set, read from git.
--
-- IT SHIPS IN THE KIT, so a consumer inherits it instead of writing its own. That is the whole
-- reason it is here. Seven repositories in this collection had written this gate by hand before it
-- was, and by the time the eighth was being written the copies had already diverged in the part
-- that matters least and costs most to get wrong: three spelled the file `test_prose.lua`, three
-- `test_spelling.lua`, and two folded it into `test_docs.lua`, so nothing could tell at a glance
-- which repositories had a gate at all. Four more had none, and the drift in them was found only by
-- a sweep somebody remembered to run. A rule enforced by eleven hand-written copies is eleven
-- chances to carry a subset.
--
-- It takes the kit as its chunk argument rather than reading the exposed table, for the reason
-- `test_eol.lua` does: that table's global name belongs to the consumer (`LK_TEST`, `AT_TEST`,
-- `KICKCD_TEST`, …) and a vendored suite cannot know which one it is standing in. Wire it as
-- `{ name = "test_prose", dir = "tests/_kit/" }` in the runner's suite list;
-- `Kit.assertSuiteInventory` goes red until you do, so it cannot arrive with a re-vendor and then
-- quietly run nothing.
--
-- A REPOSITORY THAT ALREADY HAS ITS OWN COPY WIRES ONE OR THE OTHER, NEVER BOTH. Two gates over one
-- rule is two lists to keep whole, which is the divergence this file exists to end.
--
-- BOTH LISTS ARE COPIED WHOLE, AND NOTHING IS ADDED. localization-5 is explicit that a gate MUST
-- carry every `BRITISH` entry and every `ALLOWED` entry and MUST NOT carry an entry the section does
-- not publish, because a private list is a coverage claim no reader outside the repo can check. If a
-- sweep finds a British form the published list misses, it is amended in the standard first and
-- arrives here on the next sync; it does not get added locally.
--
-- IT FAILS RATHER THAN PASSES WHEN IT CANNOT LOOK. No `io.popen`, no git, an unreadable tracked file
-- — every one of those is a failure, not a skip. A gate that goes quiet when it is blind reports
-- success, which is worse than not existing. Same bargain `test_eol.lua` strikes.

local Kit = ...
local test, fail = Kit.test, Kit.fail

-- ---------------------------------------------------------------------------
-- The published lists (localization-5), copied whole
-- ---------------------------------------------------------------------------

-- localization-5 · US English is the source dialect. Copy BOTH lists whole.
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
-- the one that actually happens, which is a list arriving truncated or half-pasted.
local PUBLISHED_BRITISH, PUBLISHED_ALLOWED = 91, 30

-- ---------------------------------------------------------------------------
-- What is scanned, and what is not
-- ---------------------------------------------------------------------------

-- The exclusions localization-5 names, and only those. Every one is a directory or a file rather
-- than a pattern, so the list cannot quietly grow by widening a regex:
--
--   * vendored code the consumer MUST NOT edit — `libs/` and `tests/_kit/`. A defect in either is
--     fixed upstream and re-vendored, never patched in place.
--   * frozen dated bundles, which are the record of what a tool said on the day rather than
--     authored prose, and released changelog entries, which are the same thing in a file.
--   * `locales/enGB.lua`, which is what a British locale file is for.
--   * the gate itself, which quotes every forbidden spelling in order to forbid it.
local SKIPPED_DIRS = {
    "libs/", "Libs/", "tests/_kit/",
    "docs/audits/", "docs/automated-tests/", "docs/perf-analysis/",
    "docs/reviews/", "docs/revendor/",
}

local SKIPPED_FILES = {
    ["locales/enGB.lua"] = true,
    ["tests/test_prose.lua"] = true,
    ["tests/test_spelling.lua"] = true,
    -- The waiver file is the fourth exclusion too, and for the same reason the gate is: it
    -- exists to name forbidden spellings, and every reason written beside a waiver is prose
    -- ABOUT one. A gate that scans it reddens on the file whose whole job is to record what
    -- it must not correct, and the only way out would be to write those reasons without
    -- naming the word -- which is the one place naming it is the point.
    ["tests/prose_waivers.lua"] = true,
}

-- ---------------------------------------------------------------------------
-- What the consumer adds: its own exclusions and its waivers
-- ---------------------------------------------------------------------------

--- The optional `tests/prose_waivers.lua`, which a consumer writes and this file reads.
---
--- WHY THIS SEAM EXISTS AT ALL, rather than the kit carrying the exceptions. Some British spellings
--- in a Ka0s tree are not the repository's English to correct, and the kit cannot know which:
---
---   * AceTimer's flag field carries the British double-L spelling of *canceled*, and a handle
---     records the flag under that name because it is what `tests/_kit/mock_record.lua`'s
---     live-timer survey reads off it. Correct the spelling and the survey stops seeing a canceled
---     timer as canceled, so a stand-down suite's timer assertion goes quietly unfalsifiable —
---     precisely what slash-commands-7 forbids.
---   * Blizzard spells its `LFG_LIST_APPLICATION_STATUS_UPDATED` status the same way, and an addon
---     matches it verbatim off the event. Correct the spelling and the lookup never matches.
---   * British spellings of *color* and *gray* appear inside Blizzard's own generated
---     `GlobalStrings` dump, which is the game's English arriving whole from the client.
---
--- localization-5 already says to match game data on the token the game uses. This is that rule
--- meeting this gate.
---
--- THE SHAPE IS PER FILE AND PER WORD, never per file alone. A whole-file waiver hides every other
--- British spelling in a file the repo edits often, which is how a gate acquires a blind spot the
--- size of a module. Returning:
---
---     return {
---       skipDirs = { "GlobalStrings/" },              -- optional, named not patterned
---       skipFiles = { ["docs/vendor-notes.md"] = true },
---       waived = {
---         ["core/LifecycleSetup.lua"] = { ["cancel" .. "led"] = true },
---       },
---     }
---
--- ABSENT IS THE NORMAL CASE and means no waivers. A repo with nothing to waive ships no file.
local function consumerRules()
    local chunk = loadfile("tests/prose_waivers.lua")
    if not chunk then return {} end
    local ok, rules = pcall(chunk)
    if not ok or type(rules) ~= "table" then
        fail("prose gate: tests/prose_waivers.lua exists but did not return a table (" ..
            tostring(rules) .. "). A waiver file that cannot be read must not be treated as "
            .. "an empty one, because that silently widens the gate", 2)
    end
    return rules
end

--- True when `path` is authored text this section has an opinion about.
---
--- Extension rather than directory, because the authored set is not one tree: locale values sit in
--- `locales/`, comments in `core/`, prose in `docs/` and the TOC's own notes at the root.
--- `.luacheckrc` is named on its own — it is authored Lua with authored comments wearing a different
--- extension, and an extension rule alone would miss it.
local function isAuthoredText(path)
    return path:find("%.lua$") or path:find("%.md$") or path:find("%.toc$") or path == ".luacheckrc"
end

--- Split a NUL-delimited blob. `git ls-files -z` because a path may contain anything but NUL, and
--- the line-oriented form quotes such a path instead of printing it — a quoted path would not open,
--- and this gate would then report a read failure that is really a parse failure.
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

--- Every authored path git tracks, minus the named exclusions, in git's order.
local function scannedPaths(rules)
    if not io.popen then
        fail("prose gate: io.popen is unavailable, so the tracked set cannot be read and this gate "
            .. "must not be reported as passing", 2)
    end
    local pipe = io.popen("git ls-files -z")
    if not pipe then
        fail("prose gate: io.popen returned no handle for `git ls-files`, so this gate cannot run "
            .. "and must not be reported as passing", 2)
    end
    local blob = pipe:read("*a") or ""
    pipe:close()

    local skipFiles = {}
    for k, v in pairs(SKIPPED_FILES) do skipFiles[k] = v end
    for k, v in pairs(rules.skipFiles or {}) do skipFiles[k] = v end

    local skipDirs = {}
    for _, d in ipairs(SKIPPED_DIRS) do skipDirs[#skipDirs + 1] = d end
    for _, d in ipairs(rules.skipDirs or {}) do skipDirs[#skipDirs + 1] = d end

    local paths = {}
    for _, path in ipairs(splitNul(blob)) do
        if isAuthoredText(path) and not skipFiles[path] then
            local skip = false
            for _, dir in ipairs(skipDirs) do
                if path:sub(1, #dir) == dir then skip = true break end
            end
            if not skip then paths[#paths + 1] = path end
        end
    end
    if #paths == 0 then
        fail("prose gate: `git ls-files` reported no authored files, which cannot be true — either "
            .. "git is unavailable or this is not a repository; this gate cannot run, and must not "
            .. "be reported as passing", 2)
    end
    return paths
end

--- The British substrings present in one line, after `ALLOWED` has been taken out as whole words.
---
--- Whole words, and before the scan, exactly as localization-5 requires. Delimit on non-letters,
--- drop a token that IS an allowance, and run the substrings over what is left. Matching `ALLOWED`
--- as a substring instead would swallow *analysed* inside the allowance for *analyses* and hide the
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

test("prose: no authored file carries a British spelling from localization-5's published list",
function()
    local rules = consumerRules()
    local waived = rules.waived or {}
    local hits = {}

    for _, path in ipairs(scannedPaths(rules)) do
        local fh = io.open(path, "r")
        if not fh then
            fail("prose gate: git tracks " .. path .. " but it cannot be opened", 2)
        end
        local body = fh:read("*a") or ""
        fh:close()

        local pass = waived[path]
        local n = 0
        for line in (body:gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do
            n = n + 1
            local found = britishIn(line)
            -- Per WORD, so every other British spelling in a waived file still reddens.
            if found and pass then
                local kept = {}
                for _, entry in ipairs(found) do
                    if not pass[entry] then kept[#kept + 1] = entry end
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
        fail(#hits .. " line(s) of authored text carry a British spelling (localization-5). US "
            .. "English is the source dialect: WoW's own API is US-spelled, so a British-spelled "
            .. "identifier sits one letter from the Blizzard symbol beside it and a `grep -r color` "
            .. "silently misses half its call sites. Correct each, and if the spelling is a locale "
            .. "KEY move every locales/*.lua file and every call site in the same change. If it is "
            .. "game data or a library's field name, waive it per file and per word in "
            .. "tests/prose_waivers.lua with the reason:\n          "
            .. table.concat(hits, "\n          "), 2)
    end
end)

test("prose: the gate carries localization-5's two lists whole, and nothing of its own", function()
    if #BRITISH ~= PUBLISHED_BRITISH or #ALLOWED ~= PUBLISHED_ALLOWED then
        fail(string.format("the copied lists are %d BRITISH and %d ALLOWED entries; "
            .. "localization-5 publishes %d and %d. A gate carrying a subset is the second "
            .. "anti-pattern stacked on the first (#46, testing-12): it reads as coverage and "
            .. "provides none. Re-copy both blocks whole",
            #BRITISH, #ALLOWED, PUBLISHED_BRITISH, PUBLISHED_ALLOWED), 2)
    end

    -- The section's prose says an allowance is a correct US word that CONTAINS a British substring,
    -- and two of the published thirty do not: `syntheses` and `emphases` are the plurals of
    -- `synthesis` and `emphasis`, and neither plural contains its own entry. So that containment
    -- rule is described here rather than asserted. A gate that reddens on the list it is required to
    -- copy whole gets deleted rather than obeyed, and the divergence is the standard's to settle.

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
