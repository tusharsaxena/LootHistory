-- testkit/vendor_sync.lua — the consumer-side vendored-payload gate, once, for every repo that
-- vendors LibKa0s. Moved here out of prettychat, where it was written and where it earned its keep,
-- by way of AbsorbTracker, where the header below was written.
--
-- WHAT IT CHECKS: that `libs/LibKa0s/` and `tests/_kit/` in the consuming repo are exactly what the
-- LibKa0s repo published at the tag THAT REPO'S CLAUDE.md says it bundles.
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

--- The two payloads every consumer vendors, with the case names the shipped gates already use.
--- `local_` rather than `local` because `local` is a keyword.
local DEFAULT_PAIRS = {
  { case    = "libs/LibKa0s is the LibKa0s release CLAUDE.md says this addon bundles",
    tag     = "LibKa0s",
    local_  = "libs/LibKa0s",
    label   = "the library repo" },
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

--- The basenames present locally, sorted. Lua 5.1 has no directory API and this
--- repo does not depend on LuaFileSystem, so the listing shells out — `ls -A`
--- for every shell this suite is actually run under, `dir /b` for cmd.exe.
local function localNames(dir)
    local names = {}
    local function collect(cmd)
        if not io.popen then return end
        local pipe = io.popen(cmd)
        if not pipe then return end
        for line in pipe:lines() do
            local name = line:gsub("[\r\n]+$", "")
            if name ~= "" and name ~= "." and name ~= ".." then names[#names + 1] = name end
        end
        pipe:close()
    end
    collect(('ls -A "%s" 2>/dev/null'):format(dir))
    if #names == 0 then collect(('dir /b "%s" 2>NUL'):format((dir:gsub("/", "\\")))) end
    table.sort(names)
    return names
end

--- Register the gate's cases on the consumer's test table.
---
--- opts = {
---   root          = ".",                       -- the consuming repo root, as the suite sees it
---   sibling       = "./../LibKa0s",            -- the library checkout to read tags out of
---   probe         = "HEAD:LibKa0s/Core.lua",   -- the ref that answers "is the sibling there?"
---   provenanceFile    = "CLAUDE.md",           -- which doc carries the provenance line
---   provenancePattern = "[Bb]undles ...",      -- how the provenance line is spelled
---   pairs         = { { case = …, tag = …, local_ = …, label = … }, … },
--- }
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

    local ROOT    = opts.root or DEFAULT_ROOT
    local SIBLING = opts.sibling or (ROOT .. DEFAULT_SIBLING)
    local PROBE   = opts.probe or DEFAULT_PROBE
    local FILE    = opts.provenanceFile or DEFAULT_FILE
    local PATTERN = opts.provenancePattern or opts.readmePattern or DEFAULT_PATTERN

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

    --- The basenames the tag carries under `<subdir>/`, sorted.
    local function shippedNames(tag, subdir)
        local body = gitOut(('ls-tree --name-only "%s:%s"'):format(tag, subdir))
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

    local function assertVendorSync(tag, subdir, localDir, label)
        local shipped = shippedNames(tag, subdir)
        local mine    = localNames(localDir)
        T.assertTrue(#shipped > 0, ("%s %s carries %s/"):format(label, tag, subdir))
        -- The file SET first: a file added on one side and not the other is invisible
        -- to a byte comparison that only walks the names it already knows about.
        T.assertEqual(table.concat(mine, ", "), table.concat(shipped, ", "),
            ("%s holds the same files as %s at %s"):format(localDir, label, tag))
        for _, name in ipairs(shipped) do
            local blob = gitShow(("%s:%s/%s"):format(tag, subdir, name))
            local here = readBytes(localDir .. "/" .. name)
            T.assertTrue(blob ~= nil, ("%s %s carries %s"):format(label, tag, name))
            T.assertTrue(here ~= nil, ("the vendored copy carries %s"):format(name))
            -- CR stripped from the working-tree side only; see the header.
            T.assertEqual((here or ""):gsub("\r\n", "\n"), blob,
                ("%s matches %s at %s — re-vendor from the tag, do not edit %s")
                    :format(name, label, tag, localDir))
        end
    end

    for _, pair in ipairs(opts.pairs or DEFAULT_PAIRS) do
        T.test(pair.case, function()
            local tag = siblingTag()
            assertVendorSync(tag, pair.tag, ROOT .. "/" .. pair.local_,
                pair.label or "the library repo")
        end)
    end
end

return VendorSync
