-- testkit/prose_selftests.lua — the prose gate's fixture-driven self-tests, peeled out of
-- `test_prose.lua` at kit revision 29.
--
-- WHY A SEPARATE FILE. `test_prose.lua` stood at 1486 lines, fourteen under `layout-§1`'s cap, and
-- the self-tests at its foot were one of its two seams (the other, the narrowing machinery, is
-- `prose_coverage.lua`). They moved unchanged: the same cases, the same names, the same order.
--
-- THEY ARE STILL THE `test_prose` SUITE'S CASES. The file is not named `test_*`, so the suite
-- inventory does not read it as a suite of its own and a consumer wires nothing new: `test_prose.lua`
-- loads it by path from its own folder, at the point the cases used to stand, and every `test` call
-- below registers under the suite that is loading. A copy of the kit without it fails at load.
--
-- It is handed the kit, the narrowing machinery `prose_coverage.lua` returns, and the four scan
-- functions of `test_prose.lua`'s own that the cases drive, and it reads nothing else.

local Kit, C, scan = ...
local test = Kit.test

local SOURCE_EXEMPT, SOURCE_SKIPDIRS, SOURCE_SKIPFILES =
    C.SOURCE_EXEMPT, C.SOURCE_SKIPDIRS, C.SOURCE_SKIPFILES
local validateOptions, resolveExempt, allNarrowings = C.validateOptions, C.resolveExempt, C.allNarrowings
local tocLoads, pkgmetaIgnores, ignoreCovers = C.tocLoads, C.pkgmetaIgnores, C.ignoreCovers
local coverageOf, coverageSummary = C.coverageOf, C.coverageSummary
local narrowingsLoadedByToc, narrowingsNotIgnored = C.narrowingsLoadedByToc, C.narrowingsNotIgnored
local filterPaths, collect = scan.filterPaths, scan.collect
local exclusionSets, validateWaived = scan.exclusionSets, scan.validateWaived

-- ---------------------------------------------------------------------------
-- The self-tests
-- ---------------------------------------------------------------------------
--
-- They ship with the gate, beside it, and they are pure: they drive the functions the gate itself
-- runs over fixtures in memory, touching neither git nor the disk. Here rather than only in the
-- library repo's own suite for the reason the cap gate's are: a vendored gate whose logic is tested
-- only upstream can rot in place through a re-vendor.
--
-- The fixture bodies below quote British spellings on purpose, which is safe in both homes this
-- file has: in the kit it is `testkit/prose_selftests.lua`, exempt by name from the library repo's
-- own shipped-payload gate, and in a consumer it is under the `tests/_kit/` prefix this gate skips.

local FIXTURE = {
    ["GlobalStrings/GlobalStrings.lua"]     = 'ERR_DUEL_X = "Duel cancelled.";',
    ["GlobalStrings/GlobalStrings_018.lua"] = 'NPEV2_SELL_GREY_ITEMS = "grey items";',
    ["GlobalStringsNotes.md"]               = "The dump is regenerated, not coloured by hand.",
    ["core/Frame.lua"]                      = "-- centre the frame",
    ["media/logo.png"]                      = "",
}
local FIXTURE_PATHS = {
    "GlobalStrings/GlobalStrings.lua", "GlobalStrings/GlobalStrings_018.lua",
    "GlobalStringsNotes.md", "core/Frame.lua", "media/logo.png",
}
local NO_SKIP_FILES, NO_SKIP_DIRS = {}, {}

--- The gate's own three steps, run over the fixture: resolve, filter, collect.
local function scanFixture(exempt)
    local paths = filterPaths(FIXTURE_PATHS, NO_SKIP_FILES, NO_SKIP_DIRS,
        resolveExempt(exempt, FIXTURE_PATHS))
    return paths, collect(paths, function(path) return FIXTURE[path] end, {})
end

test("prose self-test: the carve-out suppresses the named generated folder, and only it", function()
    local _, before = scanFixture(nil)
    Kit.assertEqual(#before, 4, "with no carve-out every authored fixture file is read and reported")

    local paths, after = scanFixture{ "GlobalStrings/" }
    Kit.assertEqual(#after, 2, "the two generated files go quiet and the other two do not")
    Kit.assertEqual(table.concat(after, " | "),
        "GlobalStringsNotes.md:1 - colour | core/Frame.lua:1 - centre",
        "and the two that remain are named with their line and their word")

    for _, path in ipairs(paths) do
        Kit.assertFalse(path:sub(1, #"GlobalStrings/") == "GlobalStrings/",
            "an exempt file is dropped before it is read, not filtered after: " .. path)
    end
end)

test("prose self-test: a path the carve-out does not name is not covered by one that looks like it",
function()
    -- `GlobalStringsNotes.md` is the whole point of the folder form comparing against
    -- `entry .. "/"`. A plain prefix match would swallow it, and the file a repository actually
    -- writes by hand would be the one that stopped being checked.
    for _, entry in ipairs{ "GlobalStrings/", "GlobalStrings" } do
        local set = resolveExempt({ entry }, FIXTURE_PATHS)
        Kit.assertTrue(set["GlobalStrings/GlobalStrings.lua"], "the dump is covered by " .. entry)
        Kit.assertTrue(set["GlobalStrings/GlobalStrings_018.lua"], "and every chunk beside it")
        Kit.assertFalse(set["GlobalStringsNotes.md"] == true,
            "and NOT the sibling that merely starts with it, written as `" .. entry .. "`")
        Kit.assertFalse(set["core/Frame.lua"] == true, "nor anything else in the tree")
    end

    local _, hits = scanFixture{ "GlobalStrings/GlobalStrings.lua" }
    Kit.assertEqual(#hits, 3, "naming one file exempts that file and leaves its chunks scanned")
    Kit.assertTrue(hits[1]:find("GlobalStrings_018", 1, true) ~= nil,
        "the unnamed chunk still reddens on the same spelling: " .. hits[1])

    local exact = resolveExempt({ ["core/Frame.lua"] = true }, FIXTURE_PATHS)
    Kit.assertTrue(exact["core/Frame.lua"], "the map form names one path")
    Kit.assertFalse(exact["GlobalStringsNotes.md"] == true, "and only that one")
end)

test("prose self-test: a carve-out that is not a set of path strings is a failure, not a silence",
function()
    Kit.assertError(function() resolveExempt("GlobalStrings/", FIXTURE_PATHS) end,
        "a bare string is the shape a runner reaches for first, and it would exempt nothing")
    Kit.assertError(function() resolveExempt({ 17 }, FIXTURE_PATHS) end,
        "an entry that is not a string cannot name a tracked path")

    -- Stale is not silent, and is deliberately NOT a failure: the file an entry named is gone, so
    -- there is nothing left for it to hide. Same call `Kit.layoutCap.exempt` makes.
    local stale = resolveExempt({ "Retired/" }, FIXTURE_PATHS)
    Kit.assertNil(next(stale), "an entry matching nothing resolves to an empty set and passes")

    -- And the table it arrives in: `Kit.prose = "GlobalStrings/"` is a mistake that would
    -- otherwise read as a repository with no generated data at all. DRIVEN OVER FIXTURE TABLES,
    -- AND `Kit.prose` IS NEVER TOUCHED -- the first draft of these three lines saved the live
    -- table, set a bad value, RESTORED IT and only then read it back, so the last assertion landed
    -- on the consumer's own carve-out and shipped permanently red there.
    Kit.assertError(function() validateOptions("GlobalStrings/") end,
        "Kit.prose set to something other than a table is a failure")
    Kit.assertNil(next(validateOptions(nil).exempt or {}),
        "and an absent Kit.prose is the normal case: no carve-out, no complaint")
    Kit.assertEqual(validateOptions{ exempt = { "GlobalStrings/" } }.exempt[1], "GlobalStrings/",
        "while a declared one is handed back whole")
end)

-- The two conditions the repository root answers, driven over the bodies the two repositories that
-- settled this question actually ship. They are fixtures, not reads: this library repo has no
-- `.toc`, no `.pkgmeta` and no carve-out, so a case reading its own surroundings would prove
-- nothing anywhere -- the mistake the gate shipped once already, in the case above.

local PRETTYCHAT_TOC = table.concat({
    "## Interface: 120100", "## Title: Fixture", "## SavedVariables: PrettyChatDB", "",
    "# Libraries (must load first)", "libs\\LibStub\\LibStub.lua", "libs\\LibKa0s\\LibKa0s.xml",
    "", "# Locales", "locales\\enUS.lua", "core\\EnvSetup.lua",
}, "\n")

local PRETTYCHAT_PKGMETA = table.concat({
    "package-as: PrettyChat", "", "enable-nolib-creation: no", "",
    "ignore:",
    "  - .luacheckrc",
    "  - docs        # holds docs/audits/ and docs/reviews/ too - all dev-only",
    "  - tests", '  - "*.bak"', "",
    "  # Generated reference data - the WHOLE folder, source dump, 26 chunks and all.",
    "  - GlobalStrings", "", "  - media/logos/*.png", "",
    "move-folders:", "  PrettyChat/nothing: nothing",
}, "\n")

local WHATGROUP_TOC = table.concat({
    "## Interface: 120100", "core\\Util.lua", "core\\Compat.lua",
    "# The LibKa0s-Env seam. After Compat, and before the two files that read the TOC.",
    "core\\EnvSetup.lua", "core\\Database.lua", "core\\WhatGroup.lua",
}, "\n")

local WHATGROUP_PKGMETA = table.concat({
    "package-as: WhatGroup", "", "ignore:", "  - .luacheckrc",
    "  - docs        # includes docs/audits and docs/reviews", "  - tests", "  - CLAUDE.md",
}, "\n")

test("prose self-test: a TOC's file lines are read as paths, and its directives and comments are not",
function()
    local loaded = tocLoads("PrettyChat.toc", PRETTYCHAT_TOC)
    Kit.assertEqual(#loaded, 4, "four file lines, and neither the three directives, the two "
        .. "comments nor the two blank lines")

    Kit.assertEqual(loaded[1].path, "libs/LibStub/LibStub.lua",
        "the client's backslashes are read as the separators they are")
    Kit.assertEqual(loaded[1].line, 6, "and the line is the one a reader will open the TOC to")
    Kit.assertEqual(loaded[1].toc, "PrettyChat.toc", "named with the TOC it came from")
    Kit.assertEqual(loaded[4].path, "core/EnvSetup.lua", "and the last file line is read too")

    -- A vendored library's TOC names ITS files: resolved against the repository root instead, a
    -- line reading `core\\Foo.lua` in libs/Bar/Bar.toc would claim this repository's core/Foo.lua
    -- is loaded and refuse an exemption over it.
    local nested = tocLoads("libs/Bar/Bar.toc", "core\\Foo.lua")
    Kit.assertEqual(nested[1].path, "libs/Bar/core/Foo.lua",
        "a nested TOC's lines resolve against the folder the TOC sits in")
end)

test("prose self-test: a .pkgmeta's ignore block is read, and the keys around it are not", function()
    local ignores = pkgmetaIgnores(PRETTYCHAT_PKGMETA)
    Kit.assertEqual(table.concat(ignores, ", "),
        ".luacheckrc, docs, tests, *.bak, GlobalStrings, media/logos/*.png",
        "every entry, with its trailing comment and its quotes taken off, and in file order")

    -- An indented comment and a blank line are ordinary inside these blocks and neither closes it.
    -- A key at column zero does, or `move-folders:` below would be read as two more ignores.
    for _, entry in ipairs(ignores) do
        Kit.assertFalse(entry:find("move%-folders") ~= nil,
            "a sibling key at column zero closes the block: " .. entry)
        Kit.assertFalse(entry:find("nothing", 1, true) ~= nil,
            "and nothing nested under that key is read as an ignore: " .. entry)
    end

    Kit.assertEqual(#pkgmetaIgnores("package-as: X\n"), 0,
        "a .pkgmeta with no ignore block yields no entries rather than failing")
end)

test("prose self-test: an ignore entry covers a path exactly, by folder, and by wildcard", function()
    Kit.assertTrue(ignoreCovers("GlobalStrings", "GlobalStrings/"),
        "the folder form a runner writes is covered by the bare name .pkgmeta writes")
    Kit.assertTrue(ignoreCovers("GlobalStrings", "GlobalStrings/GlobalStrings_018.lua"),
        "and so is a file inside it")
    Kit.assertFalse(ignoreCovers("GlobalStrings", "GlobalStringsNotes.md"),
        "and NOT the sibling that merely starts with the same letters")
    Kit.assertTrue(ignoreCovers("docs", "docs/data-flow.md"), "a folder covers what is under it")
    Kit.assertFalse(ignoreCovers("docs", "docsite/index.md"), "and nothing beside it")

    Kit.assertTrue(ignoreCovers("*.bak", "core/Frame.lua.bak"),
        "`*.bak` is written to mean a backup anywhere, so it is matched on the basename too")
    Kit.assertTrue(ignoreCovers("media/logos/*.png", "media/logos/logo.png"),
        "and a folder-scoped wildcard on the whole path")
    Kit.assertFalse(ignoreCovers("media/logos/*.png", "media/logos/logo.tga"),
        "which still refuses the extension it does not name")
end)

--- What the two fixture repositories track, as `filterPaths` would leave it: the universe every
--- narrowing below is resolved against, exactly as the gate resolves one against the live tree.
local FIXTURE_TRACKED = {
    "GlobalStrings/GlobalStrings.lua", "GlobalStringsNotes.md", "core/Compat.lua",
    "core/EnvSetup.lua", "core/Util.lua", "core/WhatGroup.lua", "docs/data-flow.md",
    "docs/spell-research/2026/notes.md", "locales/enUS.lua", "tests/run.lua",
}

--- The two refusals' input, built exactly as the gate builds it: a fixture carve-out and a fixture
--- waiver table, resolved against a fixture tracked set. Neither `Kit.prose` nor a file on disk is
--- touched by any case below.
local function coverOf(exempt, rules, paths)
    return coverageOf(allNarrowings(rules, exempt), paths or FIXTURE_TRACKED)
end

test("prose self-test: the carve-out admits a generated dump and refuses a file the TOC loads",
function()
    -- PrettyChat's, the case the carve-out exists for: generated chunks, no TOC line near them,
    -- and `- GlobalStrings` in the packaging manifest.
    local legit = coverOf({ "GlobalStrings/" })
    Kit.assertEqual(#narrowingsLoadedByToc(legit, tocLoads("PrettyChat.toc", PRETTYCHAT_TOC)), 0,
        "nothing in the TOC loads the dump")
    Kit.assertEqual(#narrowingsNotIgnored(legit, pkgmetaIgnores(PRETTYCHAT_PKGMETA)), 0,
        "and .pkgmeta keeps it out of the zip, so both gated conditions pass")

    -- WhatGroup's, the whole-file waiver wearing the carve-out's name, wired exactly as it was
    -- when it took that repository's gate green over five real hits, two of them in a TOC-loaded
    -- file. If either refusal is ever reverted, THIS case goes red.
    local abuse = coverOf({ "core/WhatGroup.lua", "docs/data-flow.md", "tests/" })
    local byToc = narrowingsLoadedByToc(abuse, tocLoads("WhatGroup.toc", WHATGROUP_TOC))
    Kit.assertEqual(#byToc, 1, "one of the three is loaded by the TOC")
    Kit.assertTrue(byToc[1]:find("core/WhatGroup.lua", 1, true) == 1,
        "and it is the shipped source file: " .. byToc[1])
    Kit.assertTrue(byToc[1]:find("[" .. SOURCE_EXEMPT .. "]", 1, true) ~= nil,
        "named with the list it was written in: " .. byToc[1])
    Kit.assertTrue(byToc[1]:find("line 7 of WhatGroup.toc", 1, true) ~= nil,
        "and with the TOC line that loads it: " .. byToc[1])

    local byPkg = narrowingsNotIgnored(abuse, pkgmetaIgnores(WHATGROUP_PKGMETA))
    Kit.assertEqual(table.concat(byPkg, ", "), "core/WhatGroup.lua [" .. SOURCE_EXEMPT .. "]",
        "and the same file is the one .pkgmeta does not keep out of the zip, while docs/ and "
        .. "tests/ are ignored and clear this condition")

    -- The third condition is untouched by both: `docs/data-flow.md` is authored prose, not in the
    -- TOC and ignored by .pkgmeta, so it passes every check a gate can make and is refused by a
    -- reader or not at all -- the cap gate's boundary too.
    Kit.assertEqual(#narrowingsLoadedByToc(coverOf({ "docs/data-flow.md" }),
        tocLoads("WhatGroup.toc", WHATGROUP_TOC)), 0, "the gate has no opinion about it")
    Kit.assertEqual(#narrowingsNotIgnored(coverOf({ "docs/data-flow.md" }),
        pkgmetaIgnores(WHATGROUP_PKGMETA)), 0, "under either gated condition")
end)

test("prose self-test: a waiver-file exclusion meets the same two refusals as the carve-out",
function()
    -- The older, wider channel, wired to hide exactly what the carve-out was stopped from hiding:
    -- WhatGroup's shipped, TOC-loaded source file, written in the other list.
    local viaFile = coverOf(nil, { skipFiles = { ["core/WhatGroup.lua"] = true } })
    local byToc = narrowingsLoadedByToc(viaFile, tocLoads("WhatGroup.toc", WHATGROUP_TOC))
    Kit.assertEqual(#byToc, 1, "skipFiles is read against the TOC too, and this file is on it")
    Kit.assertTrue(byToc[1]:find("[" .. SOURCE_SKIPFILES .. "]", 1, true) ~= nil,
        "named with the list it was written in, so the reader opens the right file: " .. byToc[1])
    Kit.assertTrue(byToc[1]:find("line 7 of WhatGroup.toc", 1, true) ~= nil,
        "and with the TOC line that loads it, exactly as the carve-out's refusal reads: "
        .. byToc[1])
    Kit.assertEqual(table.concat(narrowingsNotIgnored(viaFile,
        pkgmetaIgnores(WHATGROUP_PKGMETA)), ", "),
        "core/WhatGroup.lua [" .. SOURCE_SKIPFILES .. "]",
        "and .pkgmeta does not keep it out of the zip either")

    -- The same over skipDirs, which reaches the file through the folder above it.
    local viaDir = coverOf(nil, { skipDirs = { "core/" } })
    Kit.assertEqual(#narrowingsLoadedByToc(viaDir, tocLoads("WhatGroup.toc", WHATGROUP_TOC)), 1,
        "a skipDirs entry is refused on the first TOC line it covers")
    Kit.assertEqual(table.concat(narrowingsNotIgnored(viaDir,
        pkgmetaIgnores(WHATGROUP_PKGMETA)), ", "), "core/ [" .. SOURCE_SKIPDIRS .. "]",
        "and .pkgmeta ignores docs, tests and CLAUDE.md, not the source folder")

    -- And the legitimate shape still passes: AuraMaster's frozen dated store, which is what
    -- `skipDirs` is for. Generated on the day, no TOC line near it, and `- docs` in the manifest.
    local frozen = coverOf(nil, { skipDirs = { "docs/spell-research/" } })
    Kit.assertEqual(#narrowingsLoadedByToc(frozen, tocLoads("WhatGroup.toc", WHATGROUP_TOC)), 0,
        "a dated bundle under docs/ is loaded by no TOC line")
    Kit.assertEqual(#narrowingsNotIgnored(frozen, pkgmetaIgnores(WHATGROUP_PKGMETA)), 0,
        "and `- docs` keeps the whole tree out of the zip, so it clears both conditions")
end)

test("prose self-test: each list is refused on the matching rule its own scan uses", function()
    local loaded = { { path = "core/Frame.lua", line = 3, toc = "Fixture.toc" } }

    -- skipFiles is an EXACT key in the scan, so it is refused on an exact path and nothing wider.
    local only = { "core/Frame.lua" }
    Kit.assertEqual(#narrowingsLoadedByToc(
        coverOf(nil, { skipFiles = { ["core/"] = true } }, only), loaded), 0,
        "a skipFiles entry naming a folder suppresses nothing, so there is nothing to refuse")
    Kit.assertEqual(#narrowingsLoadedByToc(
        coverOf(nil, { skipFiles = { ["core/Frame.lua"] = true } }, only), loaded), 1,
        "and on the exact path it does suppress, it is refused")

    -- skipDirs is the PLAIN PREFIX `filterPaths` compares, which is wider than the carve-out's
    -- folder form -- deliberately, because the scan is wider there too.
    Kit.assertEqual(#narrowingsLoadedByToc(coverOf(nil, { skipDirs = { "core/Fra" } }, only),
        loaded), 1, "a skipDirs prefix the scan would suppress by is refused by that same prefix")
    Kit.assertEqual(#narrowingsLoadedByToc(coverOf({ "core/Fra" }, nil, only), loaded), 0,
        "while the carve-out's folder form neither reaches that file nor suppresses it")
end)

test("prose self-test: the scan and the refusals read the added exclusions through one reader",
function()
    local rules = { skipDirs = { "docs/frozen/" },
                    skipFiles = { ["docs/vendor-notes.md"] = true } }
    local skipFiles, skipDirs = exclusionSets(rules)
    Kit.assertTrue(skipFiles["docs/vendor-notes.md"], "the scan drops the named file")
    Kit.assertEqual(skipDirs[#skipDirs], "docs/frozen/", "and everything under the named folder")
    Kit.assertTrue(skipFiles["locales/enGB.lua"],
        "localization-§5's own exclusions are still there underneath")

    Kit.assertEqual(coverageSummary(coverOf({ "GlobalStrings/" }, rules, {
            "GlobalStrings/GlobalStrings.lua", "README.md",
            "docs/frozen/2026/a.md", "docs/vendor-notes.md" })),
        "GlobalStrings/ [" .. SOURCE_EXEMPT .. "] (1): GlobalStrings/GlobalStrings.lua; "
        .. "docs/frozen/ [" .. SOURCE_SKIPDIRS .. "] (1): docs/frozen/2026/a.md; "
        .. "docs/vendor-notes.md [" .. SOURCE_SKIPFILES .. "] (1): docs/vendor-notes.md",
        "and one disclosure names all three, sorted, each with the list it came from and with the "
        .. "paths it suppressed under it")

    -- The array form of skipFiles used to suppress NOTHING: `pairs` copied it across key and all,
    -- leaving a numeric key no path lookup could hit. Both forms go through the one reader now.
    local files = exclusionSets{ skipFiles = { "docs/vendor-notes.md" } }
    Kit.assertTrue(files["docs/vendor-notes.md"], "the array form names a file too")

    Kit.assertError(function() exclusionSets{ skipDirs = "docs/frozen/" } end,
        "a bare string would exclude nothing, so it is a failure rather than a silence")
    Kit.assertError(function() exclusionSets{ skipFiles = { 17 } } end,
        "and an entry that is not a string cannot name a tracked path, in this list either")

    -- localization-§5's published exclusions are the BASELINE, not a narrowing this repository
    -- chose: they are not disclosed and not refused, and `libs/` is on every TOC in the collection.
    Kit.assertNil(next(allNarrowings({}, nil)),
        "a repository that added nothing declares no narrowing at all")
end)

test("prose self-test: a narrowing is refused by what it suppresses, not by how it is written",
function()
    -- The hole the one coverage set closes, reproduced. `.pkgmeta` ignores the `tools` FOLDER and
    -- `skipDirs` is an UNANCHORED prefix, so the entry hides the shipped root file beside it while
    -- the entry as written stands blessed. Measured in a throwaway consumer before the fix: 15
    -- passed, 0 failed, both refusals green, and `tools-notes.md` -- two British spellings, inside
    -- the zip -- read by nothing.
    local tracked = { "README.md", "tools-notes.md", "tools/build.lua" }
    local ignores = pkgmetaIgnores("ignore:\n  - docs\n  - tools\n")
    local spill = coverOf(nil, { skipDirs = { "tools" } }, tracked)
    Kit.assertEqual(table.concat(spill[1].paths, ", "), "tools-notes.md, tools/build.lua",
        "the prefix covers the shipped root file as well as the ignored folder")
    local bad = narrowingsNotIgnored(spill, ignores)
    Kit.assertEqual(#bad, 1, "so the entry is refused although .pkgmeta ignores it as written")
    Kit.assertTrue(bad[1]:find("tools-notes.md", 1, true) ~= nil,
        "named by the shipped path it hides, which is the file a reader opens: " .. bad[1])
    Kit.assertEqual(#narrowingsNotIgnored(coverOf(nil, { skipDirs = { "tools/" } }, tracked),
        ignores), 0, "while the anchored spelling covers the ignored folder alone, and passes")

    -- And a narrowing that suppresses nothing is refused for its SPELLING. Sent to `.pkgmeta` it
    -- contradicted the same run's disclosure, which said truthfully that it suppressed nothing.
    local wrong, unmatched = narrowingsNotIgnored(
        coverOf(nil, { skipDirs = { "Tools/" } }, tracked), ignores)
    Kit.assertEqual(table.concat(unmatched, ", "), "Tools/ [" .. SOURCE_SKIPDIRS .. "]",
        "git is case-sensitive, so this entry matches nothing and says THAT")
    Kit.assertEqual(#wrong, 0, "rather than reading as a file the packager ships")
    local stale, none = narrowingsNotIgnored(
        coverOf(nil, { skipDirs = { "tools/gone/" } }, tracked), ignores)
    Kit.assertEqual(#stale + #none, 0,
        "while a stale entry .pkgmeta does cover stays stale rather than silent, and passes")
end)

test("prose self-test: the disclosure names what each entry suppressed, and says when it is bounded",
function()
    local small = coverOf(nil, { skipDirs = { "docs/frozen/" } },
        { "README.md", "docs/frozen/a.md", "docs/frozen/b.md" })
    Kit.assertEqual(coverageSummary(small),
        "docs/frozen/ [" .. SOURCE_SKIPDIRS .. "] (2): docs/frozen/a.md, docs/frozen/b.md",
        "under the bound every suppressed path is named, beneath the entry that suppressed it")

    -- 225 of 228 is the shape that makes naming them all unaffordable, and a truncated list a
    -- reader takes for a complete one is worse than the count on its own.
    local many = { "README.md" }
    for i = 1, 225 do many[#many + 1] = string.format("docs/frozen/%03d.md", i) end
    local line = coverageSummary(coverOf(nil, { skipDirs = { "docs/frozen/" } }, many))
    Kit.assertTrue(line:find("(225)", 1, true) ~= nil, "the count is the whole truth: " .. line)
    Kit.assertTrue(line:find("and 222 more (list bounded)", 1, true) ~= nil,
        "and the list that is not says out loud that it was cut short: " .. line)
    Kit.assertTrue(coverageSummary(coverOf(nil, { skipDirs = { "docs/gone/" } },
        { "README.md" })):find("(0): nothing", 1, true) ~= nil,
        "an entry that suppressed nothing says so rather than reading as coverage")
end)

test("prose self-test: a malformed waived is a failure, not a silence", function()
    -- The third key in the same table, and the silence `skipFiles` had just been cured of: the scan
    -- looks a waiver up by PATH and its words up by WORD, so either array form waives nothing at
    -- all. `waived` is still outside the two refusals -- per file AND per word, it cannot hide a
    -- spelling it did not name -- and this is the shape check that leaves it honest.
    Kit.assertError(function() validateWaived("core/Frame.lua") end,
        "a bare string is not a waiver table")
    Kit.assertError(function() validateWaived{ "core/Frame.lua" } end,
        "the array form waives nothing, which is the silence just removed from skipFiles")
    Kit.assertError(function() validateWaived{ ["core/Frame.lua"] = true } end,
        "per file AND per word: a file mapped to `true` is the whole-file waiver 5 forbids")
    Kit.assertError(function() validateWaived{ ["core/Frame.lua"] = { "centre" } } end,
        "and a word list written as an array waives nothing either")
    Kit.assertNil(next(validateWaived(nil)), "absent is the normal case and waives nothing")
    Kit.assertTrue(validateWaived{ ["core/Frame.lua"] = { centre = true } }["core/Frame.lua"].centre,
        "while the shape the docstring shows is handed back whole")
end)
