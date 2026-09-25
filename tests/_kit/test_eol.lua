-- testkit/test_eol.lua — the two line-ending gates (line-endings-§7): the working tree against
-- the terminator git declares for it, and `.gitattributes` itself against the body
-- line-endings-§5 fixes.
--
-- TWO CASES, ONE FILE. One file already owns this question, and two gates over one rule is two
-- lists to keep whole (testing-§9) — the same argument that put the prose gate in the kit instead
-- of in eleven repositories. Neither case covers the other, which is why both are here: a tree can
-- agree perfectly with a pin that is the wrong pin, and a byte-perfect `.gitattributes` says
-- nothing about a file a shell redirect wrote past git's filters.
--
-- ===========================================================================================
-- CASE ONE — the working tree against the declared pin, over every file git tracks.
-- ===========================================================================================
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
-- IT COUNTS LONE CRs TOO, from revision 26. A CR that no LF follows is invisible to a count of LFs
-- and the CRs before them, and git's `text=auto` stores such a file unnormalized as binary, so both
-- the old count and every renormalization walked past it (`AuraMaster-A-18`). It is counted over the
-- same set as the terminator check and named at its line.
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

--
-- ===========================================================================================
-- CASE TWO — `.gitattributes` itself against line-endings-§5's canonical body. Revision 25.
-- ===========================================================================================
--
-- IT EXISTS BECAUSE THE BODY WAS LEFT TO THE EYE, and the measurement says what that produced. On
-- 2026-09-22, twelve of the fourteen repositories in this collection were missing
-- `*.py text eol=lf` — a line-endings-§3 MUST since standard v2.61.0 — and thirteen of the fourteen
-- diverged from §5's canonical body. Every one of the thirteen diverged in the SAME place, on the
-- same six lines: the shell-scripts comment §3 widened to eight when it took in the shebang rule.
-- Thirteen repositories did not each make a judgment about their `.gitattributes`. One edit failed
-- to travel, and between the audit that shipped it and the next one nothing in any repository
-- mentioned it again. That is the same shape case one was written against, one file up.
--
-- IT IS NOT COSMETIC IN TWO OF THE TWELVE. Measured on 2026-09-23: FIVE tracked
-- `#!/usr/bin/env python3` files sit CRLF on disk across two of them — four generators under one
-- repository's `tools/`, and a fifth outside `tools/` in another — because with no `*.py` carve-out
-- above them the CRLF pin applies. That is `python3\r` on every checkout, for everyone, with an
-- error naming a string nobody greps for: the exact failure §3 was extended to prevent, sitting in
-- the tree since the release that extended it, under a green suite. The other ten are missing the
-- line without a file behind it yet, which is the same defect one commit before it costs anything.
--
-- BOTH BODIES ARE COPIED WHOLE OUT OF §5 AND NOTHING IS RE-AUTHORED HERE, for the reason
-- test_prose.lua copies its two word lists whole: §5 stays the one place the body is written down,
-- so changing a comment there is one kit revision and one re-vendor rather than fourteen hand edits
-- that diverge the way the last one did. The pin line, the shebang carve-outs and the binary marks
-- the (b) and (c) checks look for are READ OUT OF those bodies rather than typed again beside them.
-- A second list here is the same defect one scope smaller.
--
-- IT CARRIES NO ROSTER OF REPOSITORIES. Which body applies is decided by §2's mechanical
-- discriminator and nothing else — a tracked `.toc`, a tracked client-bound `libs/`, or the payload
-- folder a Ka0s-owned library repo ships (library-stack-§7) — because a list of repo names inside
-- the gate is one more copy to update the day a repo is added. The third arm is not decoration:
-- LibKa0s has neither a `.toc` nor a `libs/`, so without it the library that SHIPS this gate is the
-- one repository the gate misfiles, into the wrong group, about its own payload.
--
-- IT COMPARES LINES, NOT BYTES, AND THE DIFFERENCE IS EXACTLY ONE TERMINATOR. §5 prints the body
-- LF; on disk in a CRLF-pinned repo the same body is CRLF, so a literal byte compare would fail
-- every client-bound repo for being correct. The terminator is case one's question, asked over the
-- whole tracked set with `.gitattributes` in it, so nothing is given up by stripping a trailing CR
-- here: between the two cases the bytes are covered once each and neither answer rests on the other.
--
-- IT FAILS RATHER THAN PASSES WHEN IT CANNOT LOOK, on the same bargain case one strikes: no git, no
-- tracked set, no readable `.gitattributes` is a failure and not a skip.
--
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
--- Memoized: both cases ask git the same question and one shell-out answers it. A failure is never
--- cached, because it raises before the assignment below.
local cachedOrder, cachedAttrs
local function trackedAttrs()
  if cachedOrder then return cachedOrder, cachedAttrs end
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
  cachedOrder, cachedAttrs = order, attrs
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

--- Count the line terminators in `data`, how many of them are CRLF rather than bare LF, and the
--- line of every lone CR: a byte 13 that no byte 10 follows.
---
--- THE LONE CR IS COUNTED BECAUSE THE PAIR COUNT CANNOT SEE IT. Counting LFs and asking which have a
--- CR before them reads `a\r\r\n` as one clean CRLF, and git cannot see it either: `text=auto`
--- classifies a file with a lone CR as binary and stores it unnormalized, so the index is `-text`
--- and every normalization pass walks past it. Until revision 26 that was this gate's blind spot and
--- line-endings-§7's known limit (the 2026-09-23 audit's `AuraMaster-A-18`). A line number here is
--- the count of LFs before the CR, plus one: the line the CR sits on.
local function terminators(data)
  local total, crlf, lone = 0, 0, {}
  for i = 1, #data do
    local b = data:byte(i)
    if b == 10 then
      total = total + 1
      if i > 1 and data:byte(i - 1) == 13 then crlf = crlf + 1 end
    elseif b == 13 and data:byte(i + 1) ~= 10 then
      lone[#lone + 1] = total + 1
    end
  end
  return total, crlf, lone
end

--- One tracked path's case-one verdict: a terminator hit (or nil) and a lone-CR hit per lone CR,
--- the latter appended to `loneHits` as `path:line`. A path with a NUL byte is a binary nobody
--- marked and is skipped whole, for both counts.
local function scanPath(path, want, loneHits)
  local data = readBytes(path)
  if data == nil then
    fail("eol gate: cannot read " .. path .. ", which git tracks", 3)
  end
  if data:find("\000", 1, true) ~= nil then return nil end
  local total, crlf, lone = terminators(data)
  for _, line in ipairs(lone) do loneHits[#loneHits + 1] = path .. ":" .. line end
  local wrong = (want == "crlf") and (total - crlf) or crlf
  if wrong == 0 then return nil end
  return string.format("%s - declared %s, but %d of %d terminators are %s",
    path, want, wrong, total, (want == "crlf") and "bare LF" or "CRLF")
end

test("eol: every tracked file carries the terminator .gitattributes declares for it", function()
  local order, attrs = trackedAttrs()
  local hits, loneHits = {}, {}
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
    --
    -- The lone-CR count runs over exactly this set and is NOT keyed on the index's `-text`: a file
    -- with a lone CR is `-text` in the index because `text=auto` calls it binary, but so is every
    -- real binary that detection caught unmarked, and keying on it would redden the realesrgan
    -- binary above for being a binary. The NUL guard is what tells the two apart.
    if (want == "crlf" or want == "lf") and text ~= "unset" then
      hits[#hits + 1] = scanPath(path, want, loneHits)
    end
  end
  if #loneHits > 0 then
    -- Every lone CR, at its line: there is no bulk repair for these the way there is for a file
    -- written past git's filters, because checking the file out again restores the same bytes.
    fail("eol: " .. #loneHits .. " lone CR(s) - a CR no LF follows - in tracked text. No terminator "
      .. "is a bare CR in this collection, and git's `text=auto` classifies a file carrying one as "
      .. "binary, so the index stores it unnormalized, `git add --renormalize` skips it and "
      .. "`git checkout` restores it exactly as it is. Delete each CR at the line named (usually "
      .. "the `\\r` of a doubled `\\r\\r\\n`), save, and stage the file:\n          "
      .. table.concat(loneHits, "\n          "), 2)
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

-- ---------------------------------------------------------------------------------------------
-- line-endings-§5's two canonical bodies, copied whole
-- ---------------------------------------------------------------------------------------------
--
-- Copied, never re-authored. §5 is the one place the body is written down and this is a transcript
-- of it: 84 lines client-bound, 85 non-client. The counts matter because they are where the diff
-- stops and the appendix begins — the standard itself carried 81/82 here until v2.63.0, and a body
-- short by three lines reports three phantom differences on a file that is correct, in every
-- repository, forever. Recount them against §5's fenced blocks when either body changes.

--- The client-bound body — the eleven addon repos and LibKa0s, whose payload lands in each of their
--- `libs/` trees. Differs from the non-client body in one decision: the pin, the paragraph above it
--- declaring which kind of repo this is, and that decision's two word-level consequences.
local CANONICAL_CLIENT = [==[
# =============================================================================
# Ka0s WoW Addon Standard — line-ending policy (line-endings-§2)
#
# Every repo in the Ka0s collection carries an explicit .gitattributes. There
# are exactly two variants of this file and they differ in one decision only:
# the pin below. Everything after it is byte-identical across the collection,
# so diffing a client-bound repo against a non-client one shows one decision,
# not two documents.
#
# Having no .gitattributes — or one that lists only exceptions to a rule that
# was never stated — is itself the defect. It leaves what lands on disk at the
# mercy of each contributor's `core.autocrlf` / `core.eol`.
# =============================================================================

# THIS REPO IS CLIENT-BOUND. It ships Lua into the WoW client, either directly
# as an addon or vendored into an addon's libs/ folder. The client expects
# CRLF in addon source, so the working tree is pinned CRLF on every platform.
#
# `text=auto` lets git classify text vs binary by content at add time. Text is
# always stored LF in the repository, so diffs and blame stay clean; `eol=crlf`
# pins what lands on disk at checkout and converts back on add. Because
# .gitattributes overrides per-user config, a Linux contributor on
# `core.autocrlf=input` and a Windows contributor on `true` end up with
# identical bytes, and LF stragglers written by tools that bypass git's filters
# (sed, WSL editors, generators) are corrected the moment they are staged.
* text=auto eol=crlf

# A file with a shebang is LF, ALWAYS — even in a CRLF-pinned repo, where
# everything else is CRLF. `#!/usr/bin/env bash` followed by CRLF makes the
# kernel look for an interpreter literally named "bash\r", and every `case`/`in`
# line becomes a syntax error; `#!/usr/bin/env python3` fails identically, and
# the error names "python3\r". The files this protects are the vendored
# tests/_kit/run-automated-tests.sh (automated-tests-§2) and any generator
# under tools/ (layout-§1). Without these carve-outs each is broken on every
# checkout rather than in one contributor's working tree.
*.sh text eol=lf
*.py text eol=lf

# Binaries — never line-end converted, never diffed as text. `text=auto` would
# usually detect these, but detection is content-based and a truncated or
# odd-header asset can fool it; marking them is cheap and removes the class of
# bug entirely. The list is the union of every binary type present anywhere in
# the collection plus the WoW media types an addon may add at any time.
#
# Images and textures
*.png binary
*.jpg binary
*.jpeg binary
*.gif binary
*.bmp binary
*.ico binary
*.tga binary
*.blp binary
# Fonts
*.ttf binary
*.otf binary
# Audio
*.mp3 binary
*.ogg binary
*.wav binary
# Archives and opaque data (model weights, tool payloads)
*.zip binary
*.tar binary
*.gz binary
*.7z binary
*.pdf binary
*.bin binary
*.param binary

# Renormalizing after this file is added or changed. The attributes only take
# effect for content as it passes through git, so an existing checkout must be
# rewritten once, in this order:
#
#   git add .gitattributes
#   git add --renormalize .
#   git status                 # review, then commit
#
# `--renormalize` rewrites the INDEX; it does not rewrite files already on
# disk. To fix a straggler in the WORKING TREE, delete it and check it out
# again (`rm <path> && git checkout -- <path>`), then count the bytes:
#   tr -dc '\r' < <path> | wc -c     # must equal…
#   tr -dc '\n' < <path> | wc -c     # …this, in a CRLF repo.
# Not `file <path>`: it reports nothing about line terminators for JSON or
# for any binary, so it passes files it never examined (line-endings-§7).
]==]

--- The non-client body — a repo that ships nothing into the WoW client, whose consumers are git,
--- GitHub and shell tooling, all of which are LF-native.
local CANONICAL_NONCLIENT = [==[
# =============================================================================
# Ka0s WoW Addon Standard — line-ending policy (line-endings-§2)
#
# Every repo in the Ka0s collection carries an explicit .gitattributes. There
# are exactly two variants of this file and they differ in one decision only:
# the pin below. Everything after it is byte-identical across the collection,
# so diffing a client-bound repo against a non-client one shows one decision,
# not two documents.
#
# Having no .gitattributes — or one that lists only exceptions to a rule that
# was never stated — is itself the defect. It leaves what lands on disk at the
# mercy of each contributor's `core.autocrlf` / `core.eol`.
# =============================================================================

# THIS REPO IS NOT CLIENT-BOUND. It ships nothing into the WoW client; its
# consumers are git, GitHub and tooling. CRLF exists in this collection for
# exactly one reason — the client — and that reason does not apply here, so the
# working tree is pinned LF on every platform.
#
# `text=auto` lets git classify text vs binary by content at add time. Text is
# always stored LF in the repository, so diffs and blame stay clean; `eol=lf`
# pins what lands on disk at checkout and converts back on add. Because
# .gitattributes overrides per-user config, a Linux contributor on
# `core.autocrlf=input` and a Windows contributor on `true` end up with
# identical bytes, and CRLF stragglers written by tools that bypass git's
# filters (Windows editors, generators) are corrected the moment they are
# staged.
* text=auto eol=lf

# A file with a shebang is LF, ALWAYS — even in a CRLF-pinned repo, where
# everything else is CRLF. `#!/usr/bin/env bash` followed by CRLF makes the
# kernel look for an interpreter literally named "bash\r", and every `case`/`in`
# line becomes a syntax error; `#!/usr/bin/env python3` fails identically, and
# the error names "python3\r". The files this protects are the vendored
# tests/_kit/run-automated-tests.sh (automated-tests-§2) and any generator
# under tools/ (layout-§1). Without these carve-outs each is broken on every
# checkout rather than in one contributor's working tree.
*.sh text eol=lf
*.py text eol=lf

# Binaries — never line-end converted, never diffed as text. `text=auto` would
# usually detect these, but detection is content-based and a truncated or
# odd-header asset can fool it; marking them is cheap and removes the class of
# bug entirely. The list is the union of every binary type present anywhere in
# the collection plus the WoW media types an addon may add at any time.
#
# Images and textures
*.png binary
*.jpg binary
*.jpeg binary
*.gif binary
*.bmp binary
*.ico binary
*.tga binary
*.blp binary
# Fonts
*.ttf binary
*.otf binary
# Audio
*.mp3 binary
*.ogg binary
*.wav binary
# Archives and opaque data (model weights, tool payloads)
*.zip binary
*.tar binary
*.gz binary
*.7z binary
*.pdf binary
*.bin binary
*.param binary

# Renormalizing after this file is added or changed. The attributes only take
# effect for content as it passes through git, so an existing checkout must be
# rewritten once, in this order:
#
#   git add .gitattributes
#   git add --renormalize .
#   git status                 # review, then commit
#
# `--renormalize` rewrites the INDEX; it does not rewrite files already on
# disk. To fix a straggler in the WORKING TREE, delete it and check it out
# again (`rm <path> && git checkout -- <path>`), then count the bytes:
#   tr -dc '\r' < <path> | wc -c     # must be 0 in an LF repo.
# Not `file <path>`: it reports nothing about line terminators for JSON or
# for any binary, so it passes files it never examined (line-endings-§7).
]==]

local ATTRS = ".gitattributes"
-- The appendix delimiter line-endings-§5 fixes, section sign and all. It is not a citation but
-- the exact text the file must carry. Revisions before 26 assembled it from bytes, when the kit
-- kept its string literals ASCII; the kit prints to a terminal and never reaches a player, so it
-- is typed as the document prints it, like every section citation in a message below.
local APPENDIX = "# --- line-endings-§5 appendix ---"

--- Split into lines on LF, dropping one trailing CR from each, and say whether the last line was
--- left unterminated. The CR is dropped because §5 prints the body LF while a CRLF-pinned repo
--- holds the same body CRLF on disk; the terminator itself is case one's question. The
--- unterminated flag is not pedantry: a file whose final line has no newline is a byte different
--- from the canonical body, and it is the one such difference a line-wise compare cannot see.
local function splitLines(text)
  local out, pos, unterminated = {}, 1, false
  while pos <= #text do
    local at = text:find("\n", pos, true)
    if at then
      out[#out + 1] = (text:sub(pos, at - 1):gsub("\r$", ""))
      pos = at + 1
    else
      out[#out + 1] = (text:sub(pos):gsub("\r$", ""))
      unterminated = true
      pos = #text + 1
    end
  end
  return out, unterminated
end

local BODY_CLIENT = splitLines(CANONICAL_CLIENT)
local BODY_NONCLIENT = splitLines(CANONICAL_NONCLIENT)

--- The pin line (§2), the shebang carve-outs (§3) and the binary marks (§4) that a body declares,
--- read out of the body rather than typed again beside it. Typed again, they are a second list with
--- its own drift — which is the defect one scope smaller, and `*.py` is the proof it happens: §3
--- gained that line in standard v2.61.0 and twelve of fourteen repositories never received it.
local function marksOf(body)
  local pin, carveOuts, binaries = nil, {}, {}
  for _, line in ipairs(body) do
    if line:match("^%* text=auto eol=%a+$") then
      pin = line
    elseif line:match("^%*%.%w+ text eol=lf$") then
      carveOuts[#carveOuts + 1] = line
    elseif line:match("^%*%.%w+ binary$") then
      binaries[#binaries + 1] = line
    end
  end
  return pin, carveOuts, binaries
end

--- The first two arms' evidence: the first tracked `.toc` (one at the root preferred over a nested
--- one) and the first tracked path under a top-level `libs/`, each nil when there is none.
local function clientEvidence(paths)
  local rootToc, anyToc, libs = nil, nil, nil
  for _, p in ipairs(paths) do
    if not rootToc and p:match("^[^/]+%.toc$") then rootToc = p end
    if not anyToc and p:match("%.toc$") then anyToc = p end
    if not libs and p:match("^libs/") then libs = p end
  end
  return rootToc or anyToc, libs
end

--- The third arm: the first top-level folder carrying `<folder>/<folder>.xml` with Lua anywhere
--- beneath it, returned as the folder and that XML's path, or nil when no folder has that shape.
local function libraryPayload(paths)
  local luaUnder = {}
  for _, p in ipairs(paths) do
    local top = p:match("^([^/]+)/")
    if top and p:match("%.lua$") then luaUnder[top] = true end
  end
  for _, p in ipairs(paths) do
    local dir = p:match("^([^/]+)/[^/]+%.xml$")
    if dir and p == dir .. "/" .. dir .. ".xml" and luaUnder[dir] then return dir, p end
  end
  return nil
end

--- Which body this repo must carry, by §2's mechanical discriminator and nothing else.
---
--- THREE ARMS, IN ORDER, AND NO ROSTER. A `.toc` says the repo ships an addon; a tracked `libs/`
--- says it ships a vendored payload into one; and a top-level folder carrying the aggregate XML
--- named after itself, with Lua beside it, is the ship payload of a Ka0s-owned library repo
--- (library-stack-§7). The third arm is matched on SHAPE rather than on the repo's name, because
--- the name a checkout sits under is the one fact about a repository a gate cannot read: this
--- folder is `LibKa0s/LibKa0s.xml` whatever the directory above it is called.
---
--- Without that third arm the library that ships this gate has no `.toc` and no `libs/`, so it
--- would be graded against the non-client body and told to pin LF the payload every addon vendors
--- CRLF. A gate whose first act is to misfile its own repo is not one anybody keeps.
---
--- Returns the body, the pin kind, and the evidence in words, which every failure below quotes so a
--- reader checks the classification before checking the diff.
local function repoKind(paths)
  local toc, libs = clientEvidence(paths)
  if toc then
    return BODY_CLIENT, "crlf", "it ships an addon to the client (" .. toc .. ")"
  end
  if libs then
    return BODY_CLIENT, "crlf", "it ships a client-bound libs/ tree (" .. libs .. ")"
  end
  local dir, xml = libraryPayload(paths)
  if dir then
    return BODY_CLIENT, "crlf",
      "it is a Ka0s-owned library repo whose ship payload is " .. dir .. "/ (" .. xml .. ")"
  end
  return BODY_NONCLIENT, "lf",
    "it ships nothing into the WoW client: no .toc, no tracked libs/, no library payload folder"
end

test("eol: .gitattributes is line-endings-§5's canonical body for this repo kind", function()
  local paths = trackedAttrs()
  local body, kind, why = repoKind(paths)
  local pin, carveOuts, binaries = marksOf(body)

  -- (a) PRESENT AT THE ROOT, AND TRACKED. Untracked is not the lesser failure it looks like:
  -- attributes reach a contributor's checkout only through the repository, so a .gitattributes
  -- nobody else receives is the absent file §1 calls the defect, wearing the right name.
  local tracked = false
  for _, p in ipairs(paths) do
    if p == ATTRS then tracked = true break end
  end
  if not tracked then
    fail("eol: git tracks no " .. ATTRS .. " at the repo root. line-endings-§1 makes the file a "
      .. "MUST for every repo in this collection, and is explicit that its absence is the defect "
      .. "rather than a neutral default: with no attributes, what lands on disk is decided by "
      .. "whichever `core.autocrlf` / `core.eol` each contributor's git happens to carry, so two "
      .. "people produce byte-different checkouts of the same commit and neither is doing anything "
      .. "wrong. Copy line-endings-§5's canonical body for this repo kind (" .. kind .. ", because " .. why
      .. "), then renormalize per line-endings-§6", 2)
  end
  local data = readBytes(ATTRS)
  if data == nil then
    fail("eol gate: cannot read " .. ATTRS .. ", which git tracks; this gate cannot run, and must "
      .. "not be reported as passing", 2)
  end
  local actual, unterminated = splitLines(data)

  -- (b) EXACTLY ONE PIN, AND THE ONE §2 GIVES THIS REPO KIND. Two pins is not a stricter policy but
  -- an unreadable one: git takes the last match, so the file says one thing to a reader and another
  -- to the tool.
  local pins = {}
  for i, line in ipairs(actual) do
    if line:match("^%*%s") and line:find("text=auto", 1, true) then
      pins[#pins + 1] = string.format("line %d: %s", i, line)
    end
  end
  if #pins ~= 1 then
    fail("eol: " .. ATTRS .. " carries " .. #pins .. " `* text=auto` pin(s); line-endings-§2 "
      .. "allows exactly one, and git resolves a duplicate by taking the last match, so the file "
      .. "reads as one policy and behaves as another:\n          "
      .. ((#pins > 0) and table.concat(pins, "\n          ") or "(none)"), 2)
  end
  if pins[1]:gsub("^line %d+: ", "") ~= pin then
    fail("eol: " .. ATTRS .. " pins `" .. pins[1]:gsub("^line %d+: ", "") .. "`, but "
      .. "line-endings-§2 gives this repo `" .. pin .. "` because " .. why .. ". CRLF exists in "
      .. "this collection for exactly one reason - the client - and where the client is not "
      .. "involved the reason does not apply. Changing a pin is line-endings-§6's two steps, index "
      .. "then working tree, not an edit to this line alone", 2)
  end

  -- (c) §3's SHEBANG CARVE-OUTS AND §4's BINARY MARKS, each read out of the canonical body above.
  local present = {}
  for _, line in ipairs(actual) do present[line] = true end
  local missing = {}
  for _, line in ipairs(carveOuts) do
    if not present[line] then missing[#missing + 1] = line .. "   (line-endings-§3)" end
  end
  for _, line in ipairs(binaries) do
    if not present[line] then missing[#missing + 1] = line .. "   (line-endings-§4)" end
  end
  if #missing > 0 then
    fail("eol: " .. ATTRS .. " is missing " .. #missing .. " line(s) line-endings-§3 and line-endings-§4 "
      .. "require. A missing shebang carve-out is a file broken on EVERY checkout rather than in "
      .. "one contributor's tree - `#!/usr/bin/env bash` followed by CRLF sends the kernel looking "
      .. "for an interpreter named \"bash\\r\", and `python3` fails identically with an error "
      .. "naming \"python3\\r\", which is a string nobody greps for. A missing binary mark is an "
      .. "asset git may line-end convert, because `text=auto` detects by content and an ASCII-bodied "
      .. "format fools it. Add each line where line-endings-§5's body puts it:\n          "
      .. table.concat(missing, "\n          "), 2)
  end

  -- (d) THE BODY, LINE FOR LINE, THROUGH ITS FINAL LINE.
  if #actual < #body then
    fail("eol: " .. ATTRS .. " is " .. #actual .. " lines; line-endings-§5's canonical body for "
      .. "this repo kind (" .. kind .. ", because " .. why .. ") is " .. #body .. ". The body is "
      .. "fixed so that a repo can be DIFFED against the standard rather than read against it, "
      .. "which is what stopped eight hand-written 22-to-68-line variants being eight things to "
      .. "keep in sync. Replace the file with line-endings-§5's body, and put any binary mark no extension can "
      .. "reach in a line-endings-§5 appendix below it", 2)
  end
  local diffs = {}
  for i = 1, #body do
    if actual[i] ~= body[i] then
      diffs[#diffs + 1] = string.format(
        "line %d\n            canonical: %s\n            on disk:   %s", i, body[i], actual[i])
    end
  end
  if #diffs > 0 then
    -- Every differing line, not the first: this is the diff. They arrive as a block - one comment
    -- the standard rewrote upstream - and reporting them one red run at a time is the slowest
    -- possible way to find that out.
    fail("eol: " .. ATTRS .. " differs from line-endings-§5's canonical body on " .. #diffs
      .. " line(s), for a repo that takes the " .. kind .. " body because " .. why .. ". The body "
      .. "is copied whole from line-endings-§5 and edited nowhere else: a change belongs upstream in the "
      .. "standard, and arrives here on the next kit revision and re-vendor. Thirteen of fourteen "
      .. "repositories diverged on the same six lines once already, because one edit failed to "
      .. "travel and nothing in any repository mentioned it again:\n          "
      .. table.concat(diffs, "\n          "), 2)
  end
  if #actual == #body and unterminated then
    fail("eol: " .. ATTRS .. " matches line-endings-§5's canonical body but its final line has no "
      .. "terminator, so the file is one byte short of the body it is required to be. Append a "
      .. "newline", 2)
  end

  -- THE §5 APPENDIX, WHICH IS THE ONE THING PERMITTED BELOW THE BODY. It exists for a real bind:
  -- §4 MUSTs that every binary be marked and keys its union list by extension, so a vendored binary
  -- with NO extension - PanelMaster's `tools/artwork/bin/realesrgan-ncnn-vulkan` is the live one -
  -- sits between two MUSTs and can satisfy exactly one. The appendix lets it satisfy both, at the
  -- price of a shape strict enough that an auditor can tell an appendix from an edited body without
  -- reading either.
  local problems, commented, delimiterAt = {}, false, nil
  for i = #body + 1, #actual do
    local line, at = actual[i], i
    -- A blank line is a separator, above the delimiter and between entries. It is the one thing
    -- below the body that is neither an assertion nor a violation, so it is taken out first.
    if not line:match("^%s*$") then
      if not delimiterAt then
        if line ~= APPENDIX then
          fail("eol: " .. ATTRS .. " carries " .. (#actual - #body) .. " line(s) below "
            .. "line-endings-§5's canonical body, and the first non-blank one is not the appendix "
            .. "delimiter. line-endings-§5 permits exactly one thing there, beginning with the line `" .. APPENDIX
            .. "` and holding only `binary` marks keyed by path - that delimiter is what lets a "
            .. "reader tell an appendix from an edited body without reading either. Found at line "
            .. at .. ": " .. line, 2)
        end
        delimiterAt = at
      elseif line == APPENDIX then
        problems[#problems + 1] = string.format(
          "line %d: a second `%s` - the appendix runs to the end of the file and nothing follows it",
          at, APPENDIX)
      elseif line:match("^#") then
        commented = true
      else
        local path, mark = line:match("^(%S+)%s+(%S+)$")
        if mark ~= "binary" then
          problems[#problems + 1] = string.format(
            "line %d: %s - an appendix holds `binary` marks and nothing else; line-endings-§2 forbids a per-path "
            .. "pin or a `-text` exemption and this is not a reopening of that", at, line)
        elseif path:find("[%*%?%[%]]") then
          problems[#problems + 1] = string.format(
            "line %d: %s - names a glob. Each entry names a SINGLE path, because a glob swallows "
            .. "the text file somebody adds under it next year, and a binary-marked text file is "
            .. "neither diffed nor converted: line-endings-§4's failure, self-inflicted by the fix for it",
            at, line)
        elseif not commented then
          problems[#problems + 1] = string.format(
            "line %d: %s - carries no comment above it saying what the file is and why no extension "
            .. "reaches it. The next reader's first question is whether it could have been an "
            .. "extension, and anything that could belongs in line-endings-§4's union list upstream, where all "
            .. "fourteen repos get it", at, line)
        end
        commented = false
      end
    end
  end
  if #problems > 0 then
    fail("eol: the line-endings-§5 appendix in " .. ATTRS .. " does not conform to line-endings-§5, on "
      .. #problems .. " line(s):\n          " .. table.concat(problems, "\n          "), 2)
  end
end)
