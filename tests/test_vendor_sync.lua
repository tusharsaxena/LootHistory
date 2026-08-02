-- tests/test_vendor_sync.lua — the vendored-payload gate. Ported from prettychat,
-- which is where it was written and where it earned its keep.
--
-- WHAT IT CHECKS: that `libs/LibKa0s/` and `tests/_kit/` in this repo are exactly
-- what the LibKa0s repo published at the tag THIS README says it bundles.
--
-- WHY THE TAG AND NOT THE WORKING TREE: LibKa0s can be mid-release — several
-- commits and a pile of uncommitted work ahead of anything it has tagged.
-- Diffing against its working tree would redden this suite for upstream progress
-- this addon has not adopted and should not adopt, and the natural "fix" for that
-- red is to re-vendor uncommitted work, shipping bytes that exist at no ref
-- anybody can check out.
--
-- WHY IT EXISTS AT ALL: LibKa0s gave `testkit/` a revision (`Kit.VERSION`) and it
-- was vendored into six consumers — this one among them — straight off `master`,
-- while that revision was in no release. Every one of those repos then carried a
-- README provenance line naming a tag its `tests/_kit/` no longer matched, and
-- not one of them noticed, because prettychat was the only repo with this file.
-- It refused the vendor, correctly, and LibKa0s v1.4.0 was cut to make the
-- revision vendorable. This is that check, in this repo, so the next time it is
-- caught here too.
--
-- THE PROVENANCE LINE IS AN INPUT, NOT A CONSTANT. It is read out of README.md
-- rather than hardcoded: a provenance line and a vendored payload that disagree
-- is precisely the drift this file exists to catch, so the claim has to be the
-- thing under test. Bump the line and the bytes in the same commit.
--
-- ONE NORMALIZATION, AND ONLY ONE: `git show` hands back the stored blob, which
-- is LF, while the working tree is CRLF because `.gitattributes` pins
-- `* text=auto eol=crlf`. CR is stripped from the working-tree side so the file
-- is compared to the blob it round-trips to. Nothing else is normalized — a real
-- fork in content still fails.

local T    = _G.LH_TEST
local test = T.test
local ROOT = "."

local SIBLING = ROOT .. "/../LibKa0s"

--- Read a whole file as bytes, or nil if it cannot be opened.
local function readBytes(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local body = fh:read("*a")
    fh:close()
    return body
end

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

--- The version this README claims to bundle. Both casings are accepted: the line
--- is a template in `docs/releasing.md` but not every repo writes it as its own
--- sentence — LootHistory carries it mid-sentence inside a "Bundled libraries"
--- paragraph, and a pattern anchored to a capital B silently matches nothing
--- there, which is a gate that passes by not looking.
local function bundledVersion()
    local readme = readBytes(ROOT .. "/README.md") or ""
    return readme:match("[Bb]undles %[LibKa0s%]%b() (v[%d%.]+)")
end

--- The tag to compare against, or nil when the sibling checkout is absent.
---
--- A missing sibling is the ONE case where this pair may go quiet, and it is said
--- in the case name rather than hidden. Where the folder IS there, a missing tag,
--- a missing file, an extra file or a content difference all FAIL.
local function siblingTag()
    if not gitShow("HEAD:LibKa0s/Core.lua") then return nil end
    local version = bundledVersion()
    T.assertTrue(version ~= nil,
        "README.md carries a `Bundles [LibKa0s](...) vX.Y.Z (MIT).` provenance line")
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

test("libs/LibKa0s is the LibKa0s release the README says this addon bundles", function()
    local tag = siblingTag()
    if not tag then return end
    assertVendorSync(tag, "LibKa0s", ROOT .. "/libs/LibKa0s", "the library repo")
end)

test("tests/_kit is the test kit that shipped with that release", function()
    local tag = siblingTag()
    if not tag then return end
    -- README.md included: the file that actually diverged in this collection WAS
    -- a README, so a check restricted to *.lua would have caught nothing.
    assertVendorSync(tag, "testkit", ROOT .. "/tests/_kit", "the library repo")
end)
