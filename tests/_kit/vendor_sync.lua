-- testkit/vendor_sync.lua — the consumer-side vendored-payload gate, once, for every repo that
-- vendors LibKa0s. Moved here out of prettychat, where it was written and where it earned its keep,
-- by way of AbsorbTracker, where the header below was written.
--
-- WHAT IT CHECKS: that `libs/LibKa0s/` and `tests/_kit/` in the consuming repo are exactly what the
-- LibKa0s repo published at the tag THAT REPO'S CLAUDE.md says it bundles -- and, since kit
-- revision 16, that the vendored `tests/_kit/run-automated-tests.sh` is recorded 100755 in that
-- repo's git index (`automated-tests-§2`), which no byte comparison can see.
--
-- WHY THE TAG AND NOT THE WORKING TREE: LibKa0s can be mid-release — several
-- commits and a pile of uncommitted work ahead of anything it has tagged.
-- Diffing against its working tree would redden this suite for upstream progress
-- this addon has not adopted and should not adopt, and the natural "fix" for that
-- red is to re-vendor uncommitted work, shipping bytes that exist at no ref
-- anybody can check out.
--
-- WHY IT EXISTS AT ALL: LibKa0s gave `testkit/` a revision (`Kit.VERSION`) and it
-- was vendored into six consumers straight off `master`, while that revision was
-- in no release. Every one of those repos then carried a provenance line naming a
-- tag its `tests/_kit/` no longer matched, and not one of them noticed,
-- because prettychat was the only repo with this file. It refused the vendor,
-- correctly, and LibKa0s v1.4.0 was cut to make the revision vendorable.
--
-- THE PROVENANCE LINE IS AN INPUT, NOT A CONSTANT. It is read out of CLAUDE.md
-- rather than hardcoded: a provenance line and a vendored payload that disagree
-- is precisely the drift this file exists to catch, so the claim has to be the
-- thing under test. Bump the line and the bytes in the same commit.
--
-- WHY CLAUDE.md AND NOT README.md: the line answers "which LibKa0s does this build
-- carry?", which is a maintainer's question, not a player's — README.md is the
-- addon's user-facing page and carries no bundled-library inventory at all as of
-- kit revision 9. `provenanceFile` is an opt for the repo that keeps it elsewhere,
-- but the default moved, and a repo that never moved its line reads as carrying no
-- provenance line at all rather than silently falling back to the old location.
--
-- ONE NORMALIZATION, AND ONLY ONE: `git show` hands back the stored blob, which
-- is LF, while the working tree is CRLF because `.gitattributes` pins
-- `* text=auto eol=crlf`. CR is stripped from the working-tree side so the file
-- is compared to the blob it round-trips to. Nothing else is normalized — a real
-- fork in content still fails.
--
-- ^ that paragraph is carried in verbatim from AbsorbTracker/tests/test_vendor_sync.lua, and it is
-- the behavior IN USE here. State the consequence plainly, because it is the one thing a reader
-- must not have to infer: a vendored copy differing from the blob ONLY in line endings PASSES, and
-- a vendored copy differing by a single content byte FAILS. That is the intended split. Line
-- endings are decided per checkout by `.gitattributes` — the same commit legitimately materialises
-- as CRLF here and LF in a repo that does not pin them — so treating them as a content fork would
-- redden every consumer for a fact about their checkout rather than about their bytes. The
-- normalization-free equivalent is `git hash-object <working-tree file>` against the sibling's blob
-- sha, which makes git do the round-trip instead; it is the better shape if this is ever rewritten
-- rather than moved, and it draws the same line in the same place.
--
-- TWO PROPERTIES OF LIVING HERE, both deliberate:
--   * the gate is INSIDE the payload it checks. A consumer that locally patches `tests/_kit/`
--     breaks this file's own byte-identity assertion, which is exactly the right outcome — the fix
--     for a kit problem is upstream and re-vendor, never a local edit.
--   * LibKa0s cannot run it. There is no sibling to compare against from inside the library repo,
--     which is why this is a factory the CONSUMER calls rather than a suite that auto-registers,
--     and why `tests/test_kitsync.lua` stays the library-side equivalent.
--
-- THE ONE CARVE-OUT FROM WHOLE-FOLDER: `media/icons/` (kit revision 40, `library-stack-§7` from
-- standard v2.85.0). LibKa0s v1.74.0 took the icon folder to 5,836 TGAs, about 18 MB (28 MB on disk), and twelve
-- consumers copying all of it to draw a handful of glyphs is a cost nobody chose. So a consumer
-- DECLARES which icons it ships, in one line directly under its provenance line:
--
--   LibKa0s icons: all (icon picker).            -- the whole catalog; only for a player-facing chooser
--   LibKa0s icons: none.                         -- no icon files, no icon license files
--   LibKa0s icons: settings, close, ph:sword.    -- exactly these, by their lib.ICONS names
--
-- and this gate then holds `libs/LibKa0s/media/icons/` to EXACTLY that: every declared icon
-- present and byte-identical to the tag, every undeclared one absent, each set's attribution
-- files (the non-TGA files beside its icons) present when any of its icons ships and absent when
-- none does. Everything else under `libs/LibKa0s/` is compared whole, as before. The catalog a name
-- is checked against is the TAG's file list, never this repo's copy: a copy already pruned of a
-- name must not be able to vouch for it. No line at all is read as `all`, so a consumer that has
-- not declared yet is gated exactly as it was before this revision.
--
-- USAGE, from a consuming `tests/test_vendor_sync.lua`:
--
--   local VendorSync = dofile("tests/_kit/vendor_sync.lua")
--   VendorSync.register(_G.AT_TEST, {})
--
-- The consumer keeps ownership of its case names, so `docs/test-cases.md` counts do not move when a
-- repo swaps its hand-copied gate for this one.

local VendorSync = {}

local DEFAULT_ROOT     = "."
local DEFAULT_SIBLING  = "/../LibKa0s"
local DEFAULT_PROBE    = "HEAD:LibKa0s/Core.lua"
local DEFAULT_FILE     = "CLAUDE.md"
local DEFAULT_PATTERN  = "[Bb]undles %[LibKa0s%]%b() (v[%d%.]+)"
local DEFAULT_RUNNER   = "tests/_kit/run-automated-tests.sh"
local DEFAULT_RUNNER_CASE = "the automated-test runner is recorded executable (100755)"

--- The two payloads every consumer vendors, with the case names the shipped gates already use.
--- `local_` rather than `local` because `local` is a keyword.
local DEFAULT_PAIRS = {
  { case    = "libs/LibKa0s is the LibKa0s release CLAUDE.md says this addon bundles",
    tag     = "LibKa0s",
    local_  = "libs/LibKa0s",
    label   = "the library repo",
    -- The one subfolder held to the `LibKa0s icons:` declaration rather than copied whole.
    icons   = "media/icons" },
  -- Markdown included in the compared file set: the file that actually diverged in
  -- this collection WAS a README, so a check restricted to *.lua would have caught
  -- nothing.
  { case    = "tests/_kit is the test kit that shipped with that release",
    tag     = "testkit",
    local_  = "tests/_kit",
    label   = "the library repo" },
}

--- Read a whole file as bytes, or nil if it cannot be opened.
local function readBytes(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local body = fh:read("*a")
    fh:close()
    return body
end

--- The FILE paths present locally under `dir`, sorted, relative to it and recursing into
--- subdirectories — the same shape `shippedNames` answers, because the two are compared as sets.
---
--- Lua 5.1 has no directory API and this repo does not depend on LuaFileSystem, so the listing
--- shells out: `find` for every shell this suite is actually run under, `dir /b /s` for cmd.exe,
--- whose output is absolute and is trimmed back here. Files only, in both — `ls-tree -r` lists no
--- directories, so listing them on this side would report a difference that is not one.
local function localNames(dir)
    local names = {}
    local function add(name)
        name = name:gsub("[\r\n]+$", ""):gsub("^%./", ""):gsub("\\", "/")
        if name ~= "" and name ~= "." and name ~= ".." then names[#names + 1] = name end
    end
    local function collect(cmd, strip)
        if not io.popen then return end
        local pipe = io.popen(cmd)
        if not pipe then return end
        for line in pipe:lines() do
            add(strip and (line:gsub(strip, "")) or line)
        end
        pipe:close()
    end
    collect(('cd "%s" 2>/dev/null && find . -type f 2>/dev/null'):format(dir))
    -- The cmd.exe fallback only where Lua says it is on Windows. Elsewhere an EMPTY or absent
    -- directory, which a `LibKa0s icons: none.` copy legitimately has (kit revision 40), would
    -- run coreutils' own `dir` and leave a file named NUL in the working directory.
    if #names == 0 and package.config:sub(1, 1) == "\\" then
        local win = dir:gsub("/", "\\")
        collect(('dir /b /s /a-d "%s" 2>NUL'):format(win),
                "^" .. win:gsub("%p", "%%%0") .. "\\")
    end
    table.sort(names)
    return names
end

--- Whether a path must be compared BYTE FOR BYTE, with no line-ending normalization.
---
--- The comparison below strips CR from the working-tree side, because a text file is CRLF on disk
--- and LF in the blob. Doing that to a binary is corruption: a TGA or a TTF whose bytes happen to
--- contain the pair 0D 0A would be reported as diverged from the very blob it round-trips to, and
--- the failure would name a line-ending problem in a file that has no lines. None of the 49 TGAs
--- LibKa0s v1.9.0 ships contains that pair today — which is exactly why this is written down,
--- because the gate would have passed and the next icon added could have broken it for a reason
--- nobody would look for here. The list matches `.gitattributes`' binary pins.
local BINARY_EXT = {
    tga = true, png = true, jpg = true, jpeg = true, gif = true, bmp = true, ico = true,
    blp = true, ttf = true, otf = true, mp3 = true, ogg = true, wav = true, zip = true,
}

local function isBinary(path)
    local ext = path:match("%.([%a%d]+)$")
    return ext ~= nil and BINARY_EXT[ext:lower()] == true
end

-- ── the icon declaration (kit revision 40) ────────────────────────────────────────────────────
--
-- Pure functions, published on the module so `tools/prune-icons.lua` parses the line and builds
-- the catalog with exactly the code this gate does. A pruning tool and a gate that disagreed about
-- what a line means would let the tool produce a copy the gate then refuses.

--- How the line is found: the marker at the START of a line (an optional `- ` or `* ` list marker
--- before it), then the declaration body. Anchored so prose that MENTIONS the line, such as
--- "see the `LibKa0s icons:` line above", is not read as a second declaration.
local DEFAULT_ICONS_PATTERN = "^[%s%-%*]*LibKa0s icons:%s*(.-)%s*$"

--- The icon sets, by the subfolder of `media/icons/` each lives in, mapped to the `lib.ICONS`
--- prefix its names carry (Media's `ICON_SETS`). Open Iconic is the flat folder, unprefixed.
local ICON_SET_PREFIX = { [""] = "", phosphor = "ph:", ["game-icons"] = "gi:" }

--- How many names a failure message lists before it says how many more there are.
local LIST_CAP = 10

--- `names`, sorted, the first LIST_CAP of them joined, and a count of the rest.
local function cappedList(names)
    table.sort(names)
    local shown = {}
    for i = 1, math.min(#names, LIST_CAP) do shown[i] = names[i] end
    local text = table.concat(shown, ", ")
    if #names > LIST_CAP then text = text .. (", ... and %d more"):format(#names - LIST_CAP) end
    return text
end
VendorSync.cappedList = cappedList

--- Parse a declaration's body (everything after `LibKa0s icons:`) into
---   { mode = "all", reason = "icon picker" } | { mode = "none", names = {} }
---   | { mode = "list", names = { "close", "ph:sword", ... } }   -- sorted, duplicates dropped
--- or nil and the reason it is malformed. Names are not checked against a catalog here; see
--- `VendorSync.requiredIcons`.
function VendorSync.parseIconLine(body)
    local s = tostring(body or ""):match("^%s*(.-)%s*$")
    if s:sub(-1) ~= "." then
        return nil, "the `LibKa0s icons:` line must end with a period"
    end
    s = s:sub(1, -2):match("^(.-)%s*$")
    if s == "" then
        return nil, "the `LibKa0s icons:` line names nothing: write `all (<the player-facing "
            .. "chooser>).`, `none.` or a comma-separated list of lib.ICONS names"
    end
    if s == "all" or s:match("^all[%s%(]") then
        local reason = s:match("^all%s*%((.-)%)$")
        reason = reason and reason:match("^%s*(.-)%s*$")
        if not reason or reason == "" then
            return nil, "`all` must be followed by a parenthesized reason naming the player-facing "
                .. "chooser, e.g. `LibKa0s icons: all (icon picker).` -- `all` is only for an addon "
                .. "whose UI lets the player choose among the catalog"
        end
        return { mode = "all", reason = reason }
    end
    if s == "none" then return { mode = "none", names = {} } end
    local names, seen = {}, {}
    for item in (s .. ","):gmatch("([^,]*),") do
        local name = item:match("^%s*(.-)%s*$")
        if name == "" then
            return nil, "the `LibKa0s icons:` list has an empty entry (two commas, or a trailing one)"
        end
        if not (name:match("^[%w_%-]+$") or name:match("^%a+:[%w_%-]+$")) then
            return nil, ("`%s` is not a lib.ICONS name (Open Iconic unprefixed, `ph:` Phosphor, "
                .. "`gi:` Game-icons; comma-separated)"):format(name)
        end
        if not seen[name] then seen[name] = true; names[#names + 1] = name end
    end
    table.sort(names)
    return { mode = "list", names = names }
end

--- Find and parse the declaration in a provenance document's text.
---
--- Returns `decl` (see parseIconLine), or `nil, nil` when the document carries no
--- `LibKa0s icons:` line at all -- the transition state, read by every caller as `all` -- or
--- `nil, reason` when the line is malformed, declared twice, or not directly under the provenance
--- line (blank lines between the two are allowed; any other line is not).
---
--- opts: `provenancePattern` (the gate's), `iconsPattern` (DEFAULT_ICONS_PATTERN).
--- The first non-blank line after line `at`, or nil.
local function nextNonBlank(lines, at)
    if not at then return nil end
    for i = at + 1, #lines do
        if lines[i]:match("%S") then return i end
    end
    return nil
end

function VendorSync.iconDeclaration(doc, opts)
    opts = opts or {}
    local provenance = opts.provenancePattern or DEFAULT_PATTERN
    local marker = opts.iconsPattern or DEFAULT_ICONS_PATTERN
    local found, provAt, lines = {}, nil, {}
    for line in (tostring(doc or "") .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", "")
        lines[#lines + 1] = line
        if line:match(marker) then found[#found + 1] = #lines end
        if not provAt and line:match(provenance) then provAt = #lines end
    end
    if #found == 0 then return nil, nil end
    if #found > 1 then
        return nil, ("the `LibKa0s icons:` line appears %d times (lines %s); declare once")
            :format(#found, table.concat(found, ", "))
    end
    local at = found[1]
    if nextNonBlank(lines, provAt) ~= at then
        return nil, ("the `LibKa0s icons:` line (line %d) must sit directly under the "
            .. "`Bundles [LibKa0s](...) vX.Y.Z (MIT).` provenance line"):format(at)
    end
    return VendorSync.parseIconLine(lines[at]:match(marker))
end

--- The catalog an icons folder answers, from its file paths RELATIVE to that folder:
---   names       = { [lib.ICONS name] = "phosphor/sword.tga", ... }
---   attribution = { [prefix] = { "phosphor/LICENSE-phosphor.txt", ... } }  -- non-TGA files in a set's folder
---   other       = { ... }  -- anything in no known set's folder; always ships, never pruned
--- `<n>.tga` flat is `<n>`, `phosphor/<n>.tga` is `ph:<n>`, `game-icons/<n>.tga` is `gi:<n>`.
function VendorSync.iconCatalog(paths)
    local cat = { names = {}, attribution = {}, other = {} }
    for _, path in ipairs(paths) do
        local dir, file = path:match("^(.-)/?([^/]+)$")
        local prefix = ICON_SET_PREFIX[dir or ""]
        if prefix == nil then
            cat.other[#cat.other + 1] = path
        elseif file:match("%.tga$") then
            cat.names[prefix .. file:sub(1, -5)] = path
        else
            local list = cat.attribution[prefix] or {}
            list[#list + 1] = path
            cat.attribution[prefix] = list
        end
    end
    return cat
end

--- The paths under the icons folder a declaration requires, as a sorted array, and the declared
--- names the catalog does not carry (sorted; empty when every name resolved). `all` answers every
--- path the catalog was built from, so pass the same `paths` iconCatalog read.
function VendorSync.requiredIcons(decl, cat, paths)
    local want, unknown = {}, {}
    if decl.mode == "all" then
        for _, p in ipairs(paths) do want[#want + 1] = p end
        table.sort(want)
        return want, unknown
    end
    local set, prefixes = {}, {}
    for _, p in ipairs(cat.other) do set[p] = true end
    for _, name in ipairs(decl.names or {}) do
        local path = cat.names[name]
        if path then
            set[path] = true
            prefixes[name:match("^(%a+:)") or ""] = true
        else
            unknown[#unknown + 1] = name
        end
    end
    for prefix in pairs(prefixes) do
        for _, p in ipairs(cat.attribution[prefix] or {}) do set[p] = true end
    end
    for p in pairs(set) do want[#want + 1] = p end
    table.sort(want)
    table.sort(unknown)
    return want, unknown
end

--- Split `names` (paths relative to the payload) into those under `dir/` -- returned RELATIVE to
--- it -- and the rest, both in their input order.
local function splitUnder(names, dir)
    local inside, outside = {}, {}
    local lead = dir .. "/"
    for _, name in ipairs(names) do
        if name:sub(1, #lead) == lead then inside[#inside + 1] = name:sub(#lead + 1)
        else outside[#outside + 1] = name end
    end
    return inside, outside
end
VendorSync.splitUnder = splitUnder
VendorSync.localNames = localNames

--- `register`'s opts with their defaults filled in, in the order `register` names them. A function
--- of its own because every default is a branch, and `register` is long enough already.
local function resolveOpts(opts)
    local root = opts.root or DEFAULT_ROOT
    return root,
        opts.sibling or (root .. DEFAULT_SIBLING),
        opts.probe or DEFAULT_PROBE,
        opts.provenanceFile or DEFAULT_FILE,
        opts.provenancePattern or opts.readmePattern or DEFAULT_PATTERN,
        opts.runner or DEFAULT_RUNNER,
        opts.runnerCase or DEFAULT_RUNNER_CASE,
        opts.iconsPattern or DEFAULT_ICONS_PATTERN
end

--- Register the gate's cases on the consumer's test table.
---
--- opts = {
---   root          = ".",                       -- the consuming repo root, as the suite sees it
---   sibling       = "./../LibKa0s",            -- the library checkout to read tags out of
---   probe         = "HEAD:LibKa0s/Core.lua",   -- the ref that answers "is the sibling there?"
---   provenanceFile    = "CLAUDE.md",           -- which doc carries the provenance line
---   provenancePattern = "[Bb]undles ...",      -- how the provenance line is spelled
---   pairs         = { { case = …, tag = …, local_ = …, label = …, icons = … }, … },
---   runner        = "tests/_kit/run-automated-tests.sh",  -- the runner, relative to root
---   runnerCase    = "the automated-test runner is recorded executable (100755)",
---   iconsPattern  = "^[%s%-%*]*LibKa0s icons:%s*(.-)%s*$", -- the icon declaration line, anchored (rev 40)
--- }
---
--- A pair's `icons` names the subfolder of its payload held to the `LibKa0s icons:` declaration
--- rather than compared whole; the default library pair carries `icons = "media/icons"` (kit
--- revision 40). A pair without the field is compared whole, as every pair was before.
---
--- Besides one case per pair, it registers ONE more, named by `runnerCase`: the runner's recorded
--- mode in the consuming repo's git index (kit revision 16). That case needs no sibling checkout.
---
--- `readmePattern` is still accepted as a name for `provenancePattern`; it named the
--- file the line used to live in, and the line moved at kit revision 9.
function VendorSync.register(T, opts)
    opts = opts or {}
    if type(T) ~= "table" or type(T.test) ~= "function" then
        error("vendor_sync: register(T, opts) needs the test table, e.g. _G.AT_TEST", 0)
    end
    if type(T.skip) ~= "function" then
        error("vendor_sync: T.skip is missing — this module needs kit revision 8 or newer; "
            .. "re-vendor tests/_kit/ from a LibKa0s tag that ships testkit/vendor_sync.lua", 0)
    end

    local ROOT, SIBLING, PROBE, FILE, PATTERN, RUNNER, RUNNER_CASE, ICONS_PATTERN = resolveOpts(opts)

    --- Run a command in the sibling library repo and return stdout, or nil if it
    --- produced nothing. `nil` means "could not answer" — never "matched".
    local function gitOut(args)
        if not io.popen then return nil end
        local pipe = io.popen(('git -C "%s" %s 2>/dev/null'):format(SIBLING, args), "r")
        if not pipe then return nil end
        local body = pipe:read("*a")
        pipe:close()
        if body == "" then return nil end
        return body
    end

    local function gitShow(ref) return gitOut(('show "%s"'):format(ref)) end

    --- Read MANY blobs in ONE `git` process, as `{ [ref] = contents }`.
    ---
    --- `git show` per file is one process spawn per file, and a payload is not a few files: LibKa0s
    --- v1.9.0 ships 49 icons and a font, so a consumer's gate was spawning ~66 gits and spending
    --- 7.5 seconds doing it. Once the loader's chunk cache landed, this ONE case was the single
    --- longest thing in that repo's whole suite -- and, because a shard can only be as fast as its
    --- slowest case, it was also the ceiling on everything `--jobs` could buy.
    ---
    --- `git cat-file --batch` answers all of them from one process. It reads its request list on
    --- stdin, which Lua 5.1's unidirectional `io.popen` cannot write to, so the list goes through a
    --- temp file and is redirected in. Each reply is `<oid> <type> <size>` and a newline, then
    --- EXACTLY `<size>` bytes, then one more newline. The payload is therefore sliced by LENGTH,
    --- never by pattern, and a blob carrying newlines, NUL bytes or CRLF round-trips unharmed --
    --- which is the whole reason this is safe for the TGAs and the TTF as well as for the Lua.
    ---
    --- A ref git cannot resolve answers `<ref> missing` with no payload, and maps to no entry.
    --- Every caller already treats an absent entry as "could not answer", never as "matched".
    ---
    --- One behavior difference from `gitShow`, and it is a fix: that function mapped an empty
    --- result to `nil`, so a legitimately EMPTY vendored file read as "the tag does not carry
    --- this". Here an empty blob is an empty string, and compares equal to an empty local file.
    local function gitShowMany(refs)
        local out = {}
        if not io.popen or #refs == 0 then return out end

        local listPath = os.tmpname()
        local list = io.open(listPath, "wb")
        if not list then return out end
        for _, ref in ipairs(refs) do list:write(ref, "\n") end
        list:close()

        local pipe = io.popen(('git -C "%s" cat-file --batch <"%s" 2>/dev/null')
            :format(SIBLING, listPath), "r")
        local body = pipe and pipe:read("*a") or ""
        if pipe then pipe:close() end
        os.remove(listPath)

        -- Replies come back in request order, so the walk pairs them off positionally.
        local pos, i = 1, 1
        while pos <= #body and i <= #refs do
            local nl = body:find("\n", pos, true)
            if not nl then break end
            local size = tonumber(body:sub(pos, nl - 1):match("%s(%d+)$") or "")
            if size then
                out[refs[i]] = body:sub(nl + 1, nl + size)
                pos = nl + 1 + size + 1     -- the payload, then the newline that closes it
            else
                pos = nl + 1                -- `<ref> missing` -- nothing follows
            end
            i = i + 1
        end
        return out
    end

    --- The paths the tag carries under `<subdir>/`, sorted, RELATIVE to that subdir and
    --- INCLUDING anything inside a subdirectory of it.
    ---
    --- `-r`, and that is not a tidy-up. Without it this listed one level and handed back
    --- DIRECTORY names, which the comparison below then tried to read as files -- so the first
    --- payload to ship a subdirectory (LibKa0s v1.9.0's `LibKa0s/media/`) turned a working gate
    --- into a failing one pointing at nothing wrong. Recursing means a file three levels down is
    --- compared like any other, which is what "byte-for-byte what the tag published" was always
    --- supposed to mean.
    local function shippedNames(tag, subdir)
        local body = gitOut(('ls-tree -r --name-only "%s:%s"'):format(tag, subdir))
        local names = {}
        for line in (body or ""):gmatch("[^\r\n]+") do
            if line ~= "" then names[#names + 1] = line end
        end
        table.sort(names)
        return names
    end

    --- The version this repo's provenance doc claims to bundle. Both casings are
    --- accepted: the line is a template in `docs/releasing.md` but not every repo
    --- writes it as its own sentence — some carry it mid-sentence, and a pattern
    --- anchored to a capital B silently matches nothing there, which is a gate that
    --- passes by not looking.
    local function bundledVersion()
        local doc = readBytes(ROOT .. "/" .. FILE) or ""
        return doc:match(PATTERN)
    end

    --- The tag to compare against. A missing sibling checkout is the ONE case where
    --- this pair may go quiet, and it now reports a SKIP carrying its reason rather
    --- than returning early — a bare `return` here registered as PASS, so six repos
    --- were reporting "checked, fine" for a comparison that never ran. Where the
    --- folder IS there, a missing tag, a missing file, an extra file or a content
    --- difference all FAIL.
    local function siblingTag()
        if not gitShow(PROBE) then
            T.skip(SIBLING .. " checkout absent — the vendored payload was NOT compared")
        end
        local version = bundledVersion()
        T.assertTrue(version ~= nil,
            FILE .. " carries a `Bundles [LibKa0s](...) vX.Y.Z (MIT).` provenance line")
        return version
    end

    --- The icon declaration this repo's provenance doc carries, or nil when it carries none (the
    --- transition state: the folder is compared whole). A malformed line FAILS here, naming why.
    local function iconDecl()
        local decl, err = VendorSync.iconDeclaration(readBytes(ROOT .. "/" .. FILE) or "",
            { provenancePattern = PATTERN, iconsPattern = ICONS_PATTERN })
        T.assertTrue(err == nil, ("%s: %s"):format(FILE, tostring(err)))
        return decl
    end

    --- The paths in `have` that `want` does not hold, sorted.
    local function minus(have, want)
        local inWant, out = {}, {}
        for _, p in ipairs(want) do inWant[p] = true end
        for _, p in ipairs(have) do
            if not inWant[p] then out[#out + 1] = p end
        end
        table.sort(out)
        return out
    end

    local compareBlobs   -- defined below; both comparison shapes end in it

    --- The declared shape (kit revision 40): everything outside `iconsDir` whole, and under it
    --- exactly what the declaration requires. Only the required blobs are read, so `none` or a
    --- short list costs one `ls-tree` and a few dozen blobs, not 5,836.
    local function assertDeclared(tag, subdir, localDir, label, shipped, mine, iconsDir, decl)
        local tagIcons, tagRest = splitUnder(shipped, iconsDir)
        local myIcons, myRest = splitUnder(mine, iconsDir)
        T.assertEqual(table.concat(myRest, ", "), table.concat(tagRest, ", "),
            ("%s holds the same files as %s at %s outside %s/"):format(localDir, label, tag, iconsDir))
        local want, unknown = VendorSync.requiredIcons(decl, VendorSync.iconCatalog(tagIcons), tagIcons)
        T.assertTrue(#unknown == 0,
            ("%s declares %d icon name(s) %s at %s does not carry in lib.ICONS: %s")
                :format(FILE, #unknown, label, tag, cappedList(unknown)))
        local extra, missing = minus(myIcons, want), minus(want, myIcons)
        T.assertTrue(#extra == 0,
            ("%d undeclared file(s) ship under %s/%s/ -- the `LibKa0s icons:` line does not require "
                .. "them: %s. Remove them with `lua tools/prune-icons.lua <this repo>` from the "
                .. "LibKa0s checkout, or declare the icons you draw")
                :format(#extra, localDir, iconsDir, cappedList(extra)))
        T.assertTrue(#missing == 0,
            ("%d declared file(s) are missing from %s/%s/: %s. Re-copy the folder from %s, then "
                .. "prune")
                :format(#missing, localDir, iconsDir, cappedList(missing), tag))
        local compare = {}
        for _, name in ipairs(tagRest) do compare[#compare + 1] = name end
        for _, p in ipairs(want) do compare[#compare + 1] = iconsDir .. "/" .. p end
        compareBlobs(tag, subdir, localDir, label, compare)
    end

    local function assertVendorSync(tag, subdir, localDir, label, iconsDir)
        local shipped = shippedNames(tag, subdir)
        local mine    = localNames(localDir)
        T.assertTrue(#shipped > 0, ("%s %s carries %s/"):format(label, tag, subdir))
        local decl = iconsDir and iconDecl()
        if decl and decl.mode ~= "all" then
            return assertDeclared(tag, subdir, localDir, label, shipped, mine, iconsDir, decl)
        end
        -- The file SET first: a file added on one side and not the other is invisible
        -- to a byte comparison that only walks the names it already knows about.
        T.assertEqual(table.concat(mine, ", "), table.concat(shipped, ", "),
            ("%s holds the same files as %s at %s"):format(localDir, label, tag))
        compareBlobs(tag, subdir, localDir, label, shipped)
    end

    --- Every name in `shipped` (relative to `subdir`), byte for byte against the tag.
    compareBlobs = function(tag, subdir, localDir, label, shipped)
        -- Every blob in one `git` call, not one call per file. See gitShowMany.
        local refs = {}
        for i, name in ipairs(shipped) do
            refs[i] = ("%s:%s/%s"):format(tag, subdir, name)
        end
        local blobs = gitShowMany(refs)
        for i, name in ipairs(shipped) do
            local blob = blobs[refs[i]]
            local here = readBytes(localDir .. "/" .. name)
            T.assertTrue(blob ~= nil, ("%s %s carries %s"):format(label, tag, name))
            T.assertTrue(here ~= nil, ("the vendored copy carries %s"):format(name))
            -- CR stripped from the working-tree side only, and only for text; see isBinary.
            local ours = here or ""
            if not isBinary(name) then ours = ours:gsub("\r\n", "\n") end
            T.assertEqual(ours, blob,
                ("%s matches %s at %s — re-vendor from the tag, do not edit %s")
                    :format(name, label, tag, localDir))
        end
    end

    for _, pair in ipairs(opts.pairs or DEFAULT_PAIRS) do
        T.test(pair.case, function()
            local tag = siblingTag()
            assertVendorSync(tag, pair.tag, ROOT .. "/" .. pair.local_,
                pair.label or "the library repo", pair.icons)
        end)
    end

    --- Run git in the CONSUMING repo, not the sibling, and return stdout, or nil if it produced
    --- nothing. The same contract as gitOut: nil means "could not answer", never "matched".
    local function rootGit(args)
        if not io.popen then return nil end
        local pipe = io.popen(('git -C "%s" %s 2>/dev/null'):format(ROOT, args), "r")
        if not pipe then return nil end
        local body = pipe:read("*a")
        pipe:close()
        if body == "" then return nil end
        return body
    end

    -- The runner's recorded MODE (automated-tests-§2), which the byte comparison above cannot see
    -- and never will: the executable bit is not in the file's bytes and `cp` does not carry it. It
    -- lives in the git INDEX and nowhere else that matters -- the collection runs on DrvFs, which
    -- reports rwxrwxrwx for every file, with `core.fileMode=false`, so neither `ls -l` nor git's own
    -- status will ever mention a runner that arrived 100644. So this reads the index.
    --
    -- Registered on its own rather than as a third pair: it needs no sibling and no tag, so a
    -- missing LibKa0s checkout must not skip it. It skips only where the index cannot be read at
    -- all -- no io.popen, no git, not a work tree -- and says so, never passing silently.
    T.test(RUNNER_CASE, function()
        if not io.popen then
            T.skip("io.popen is unavailable, so the git index cannot be read -- " .. RUNNER
                .. "'s mode was NOT checked")
        end
        local inside = (rootGit("rev-parse --is-inside-work-tree") or ""):match("^%s*(%S*)")
        if inside ~= "true" then
            T.skip("git answered no work tree at " .. ROOT .. " (git missing, or not a checkout) -- "
                .. RUNNER .. "'s mode was NOT checked")
        end
        local line = rootGit(('ls-files -s -- "%s"'):format(RUNNER))
        T.assertTrue(line ~= nil, RUNNER .. " is not tracked in the git index at " .. ROOT)
        T.assertEqual((line:match("^(%d+)%s")), "100755",
            ("%s is recorded executable in the git index (`git ls-files -s`: %s) -- fix with "
                .. "`git update-index --chmod=+x %s`; `ls -l` is no evidence on DrvFs")
                :format(RUNNER, (line:gsub("%s+$", "")), RUNNER))
    end)
end

return VendorSync
