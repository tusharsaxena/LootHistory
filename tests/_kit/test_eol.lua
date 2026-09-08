-- testkit/test_eol.lua — the working-tree line-ending gate, over every file git tracks.
--
-- This exists because the defect it catches is invisible to everything else. `run-automated-tests.sh`
-- writes every bundle file with a plain shell redirect, and a redirect is a kernel write into the
-- working tree — it never passes through git's clean/smudge filters. In a repo pinned
-- `* text=auto eol=crlf`, which is every client-bound repo in the collection, the bundle therefore
-- landed LF on disk while `.gitattributes` said CRLF, on every run, for nine revisions of the kit.
--
-- NOTHING REPORTED IT. The blob is LF in the index either way — that is where LF belongs — so
-- `git diff` is empty before the commit AND after it, and `git add --renormalize` does not help
-- because it rewrites the index and the index was never wrong. Only a byte-level audit ever saw it.
-- Kit revision 10 fixes the writer; this is the gate that keeps it fixed.
--
-- IT READS THE WHOLE TRACKED SET, and did not until revision 15. It used to ask git about
-- `docs/automated-tests/` alone, because the bundles are what the writer that caused the defect
-- writes. That scope is why it stayed green while seven files in LibKa0s sat LF on disk under a CRLF
-- pin — two of them, `DebugLog.lua` and `Pool.lua`, inside the SHIPPED payload, which is what made
-- `diff -r LibKa0s <Addon>/libs/LibKa0s` report thousands of phantom lines in nine repositories on
-- every re-vendor. A shell redirect is not the only way to write a file past git's filters: sed, an
-- editor on the other side of a WSL mount and any generator that opens a path for writing all do
-- it. The set to hold to the pin is therefore the set git tracks, and the narrower scope was a gate
-- reading as coverage it did not provide.
--
-- IT ASSERTS THE INVARIANT, NOT THE IMPLEMENTATION. It never looks at the runner's source. It asks
-- git what each path's terminator is declared to be and then reads the bytes, so it also catches a
-- file the runner does not write at all — most usefully `ANALYSIS.md`, which the
-- `/wow-addon:automated-tests` skill agent drops into the bundle directory after the runner has
-- exited and which is therefore outside the runner's own pass. A red here for that file is the gate
-- working, not the gate being wrong.
--
-- IT FAILS RATHER THAN PASSES WHEN IT CANNOT LOOK. No `io.popen`, no git, no answer from
-- `check-attr` — all of those are a failure. A gate that goes quiet when it is blind reports
-- success, which is worse than not existing. Same bargain tests/test_kitsync.lua and
-- tests/test_prose.lua strike.
--
-- IT SHIPS IN THE KIT, so every consumer inherits it instead of each writing its own. That is why
-- it takes the kit as its chunk argument rather than reading the exposed table: that table's global
-- name belongs to the consumer (`LK_TEST`, `AT_TEST`, `KICKCD_TEST`, …) and a vendored suite cannot
-- know which one it is standing in. Wire it as `{ name = "test_eol", dir = "tests/_kit/" }` in the
-- runner's suite list; `Kit.assertSuiteInventory` goes red until you do, so it cannot arrive with a
-- re-vendor and then quietly run nothing.

local Kit = ...
local test, fail = Kit.test, Kit.fail

--- Every path git tracks, sorted, and the `text` and `eol` attributes git declares for each.
---
--- `git ls-files` rather than a directory walk, for two reasons. Lua 5.1 has no directory API and
--- nothing in this collection depends on LuaFileSystem, so a recursive walk would be several
--- shell-outs deep; and the tracked set is the right set anyway — an untracked scratch file someone
--- left in a bundle folder has no declared terminator to violate.
---
--- ONE shell-out for the whole repository rather than one per path. `git check-attr --stdin` reads
--- the list `git ls-files` writes and answers both attributes for every path in a single pass. Asked
--- per path, `check-attr` measured about 17ms here — some nine seconds added to every run, in ten
--- repositories, which is how a gate acquires a flag to switch it off and then stops being run at
--- all. `-z` on both sides because a path may contain anything but NUL, and the line-oriented forms
--- quote such a path instead of printing it.
local function trackedAttrs()
  if not io.popen then
    fail("eol gate: io.popen is unavailable, so this gate cannot run and must not be reported as "
      .. "passing", 2)
  end
  local p = io.popen('git ls-files -z | git check-attr text eol --stdin -z 2>/dev/null')
  if not p then
    fail("eol gate: io.popen returned no handle, so this gate cannot run and must not be reported "
      .. "as passing", 2)
  end
  local data = p:read("*a") or ""
  p:close()

  -- `<path>NUL<attribute>NUL<value>NUL`, repeated. Split by hand rather than with a pattern: `%z`
  -- is Lua 5.1's spelling for the zero byte and an error in 5.4, and these suites run under both.
  local fields, pos = {}, 1
  while true do
    local at = data:find("\0", pos, true)
    if not at then break end
    fields[#fields + 1] = data:sub(pos, at - 1)
    pos = at + 1
  end

  local order, attrs = {}, {}
  for i = 1, #fields - 2, 3 do
    local path, name, value = fields[i], fields[i + 1], fields[i + 2]
    local a = attrs[path]
    if not a then
      a = {}
      attrs[path] = a
      order[#order + 1] = path
    end
    a[name] = value
  end

  if #order == 0 then
    fail("eol gate: `git ls-files -z | git check-attr text eol --stdin -z` returned nothing — "
      .. "either git is not available here or this is not a repository; this gate cannot run, and "
      .. "must not be reported as passing", 2)
  end
  table.sort(order)
  return order, attrs
end

--- Read a whole file as bytes, or nil if it cannot be opened. Binary mode is load-bearing: text
--- mode on Windows would translate away the exact bytes this gate is here to inspect.
local function readBytes(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

--- Count the line terminators in `data` and how many of them are CRLF rather than bare LF.
local function terminators(data)
  local total, crlf = 0, 0
  for i = 1, #data do
    if data:byte(i) == 10 then
      total = total + 1
      if i > 1 and data:byte(i - 1) == 13 then crlf = crlf + 1 end
    end
  end
  return total, crlf
end

test("eol: every tracked file carries the terminator .gitattributes declares for it", function()
  local order, attrs = trackedAttrs()
  local hits = {}
  for _, path in ipairs(order) do
    local want, text = attrs[path].eol, attrs[path].text
    if not want then
      fail("eol gate: git answered no `eol` attribute for " .. path .. "; this gate cannot run, and "
        .. "must not be reported as passing", 2)
    end
    -- `unspecified` is not a violation — it is the repo declaring nothing, and there is then
    -- nothing to hold the bytes to. Neither is `text: unset`: the pin here is global, so a path
    -- marked `binary` still answers `eol: crlf` while git converts nothing for it, and holding a
    -- .tga to a terminator count would be a red about an image. PanelMaster's extension-less
    -- `tools/artwork/bin/realesrgan-ncnn-vulkan` is the live case for that carve-out. The NUL guard
    -- below is the backstop, for a binary nobody remembered to mark.
    if (want == "crlf" or want == "lf") and text ~= "unset" then
      local data = readBytes(path)
      if data == nil then
        fail("eol gate: cannot read " .. path .. ", which git tracks", 2)
      end
      if data:find("\000", 1, true) == nil then
        local total, crlf = terminators(data)
        local wrong = (want == "crlf") and (total - crlf) or crlf
        if wrong > 0 then
          hits[#hits + 1] = string.format("%s - declared %s, but %d of %d terminators are %s",
            path, want, wrong, total, (want == "crlf") and "bare LF" or "CRLF")
        end
      end
    end
  end
  if #hits > 0 then
    -- Name every file rather than the first: these arrive a whole directory at a time, and fixing
    -- them one red run at a time is the slowest possible way to find that out.
    fail("eol: " .. #hits .. " tracked file(s) disagree with `git check-attr eol`. A write that "
      .. "bypasses git's filters - a shell redirect, sed, an editor across a WSL mount - leaves the "
      .. "index right and the disk wrong, so `git diff` will never show you this and "
      .. "`git add --renormalize` will not fix it. Repair each with "
      .. "`rm <path> && git checkout -- <path>`, then count the bytes: `tr -dc '\\r' < <path> | "
      .. "wc -c` must equal `tr -dc '\\n' < <path> | wc -c`:\n          "
      .. table.concat(hits, "\n          "), 2)
  end
end)
