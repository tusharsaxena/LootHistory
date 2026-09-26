# LibKa0s testkit

The shared headless test harness for the Ka0s addon collection: the test registry and assertions,
the source loader, the universal half of the WoW-API mock and its opt-in id lookups, the
consolidated automated-test runner, the consumer-side vendoring gate, and three suites of its
own.

**The full surface — every function, every mock seam, every fidelity rule — is documented in the
LibKa0s repo under `docs/api/testkit/`, one document per kit revision:**
<https://github.com/tusharsaxena/LibKa0s/tree/master/docs/api/testkit>. This file covers what the kit
*is* and how to vendor it; that directory is the reference, and is the source of truth.

The link is absolute on purpose. This file is byte-identical in twelve places — here, this repo's
`tests/_kit/`, and each of the ten consumers' — so a relative path that resolved from one would be
broken in the other eleven.

## The files

| File | What it is |
|---|---|
| `framework.lua` | The entry point: the resource guard, the registry, `Kit.skip`, `Kit.expose`, the suite loader, the runner and the `--list` renderer |
| `inventory.lua` | The suite inventory (`Kit.assertSuiteInventory`, the gate-rule table, the `## Documented deviations` reader and the decline matcher) and the path helpers it keys on. `framework.lua` loads it from its own folder; nothing else does (kit revision 28) |
| `asserts.lua` | The assertions (`assertEqual` to `assertError`, `assertErrorMatches` and `assertLibraryConstant`) and the surface-parity gate (`setSurfaceSource`, `publicMembers`, `assertSurfaceParity`). `framework.lua` loads it from its own folder; nothing else does (kit revision 26) |
| `loader.lua` | Headless source loading into the mocked environment |
| `mock_base.lua` | The universal half of the WoW-API mock, and the Ace fakes |
| `mock_record.lua` | The recording surveys; `mock_base.lua` loads it from its own folder |
| `mock_events.lua` | `EventRegistry`, `C_EventUtils.IsEventValid`, and the raw frame registration's `__badEvents` raise; `mock_base.lua` loads it from its own folder (kit revision 26) |
| `mock_ids.lua` | Opt-in id lookups, installed on a finished mock |
| `vendor_sync.lua` | The consumer-side vendoring gate |
| `run-automated-tests.sh` | The consolidated automated-test runner |
| `test_eol.lua` | The line-ending gates, a kit suite |
| `test_prose.lua` | The US-English prose gate, a kit suite |
| `prose_lists.lua` | The published lists `test_prose.lua` reads: both spelling lists, the folder exclusions and the store-root files read back out of them. `test_prose.lua` loads it from its own folder; nothing else does (kit revision 26) |
| `prose_coverage.lua` | The prose gate's narrowing machinery: the validators for the three lists a repository narrows the gate by, the one resolved coverage set, the TOC and `.pkgmeta` readers, the two refusals and the disclosure line. `test_prose.lua` loads it from its own folder; nothing else does (kit revision 29) |
| `prose_selftests.lua` | The prose gate's fixture-driven self-tests. Not a suite of its own: `test_prose.lua` loads it from its own folder and its cases register under `test_prose`, so a consumer wires nothing new (kit revision 29) |
| `test_layout_cap.lua` | The 1500-line cap gate, a kit suite |
| `test_diagnostics_contract.lua` | The diagnostics dump's dispatcher contract (`debug-logging-§14`), a kit suite run against the consumer's own dispatcher (kit revision 27) |
| `README.md` | This file |

They vendor as one folder. A copy that leaves out `asserts.lua`, `inventory.lua`, `mock_record.lua`,
`mock_events.lua`, `prose_lists.lua`, `prose_coverage.lua` or `prose_selftests.lua` fails at load
rather than passing over nothing.

## `run-automated-tests.sh`

The collection's consolidated automated-test runner, and the only executable in the kit. It runs the
four out-of-game suites and records every result as one frozen bundle under
`docs/automated-tests/<YYYYMMDD-HHMMSS>/`, then regenerates `docs/automated-tests/RESULTS.md` whole:
the lead-in, the new row above every preserved older one, the complexity watch list and a standing
section per suite (see `automated-tests` in the standard). **Exactly one cell in that file is
authored** — the watch list's `Disposition`, which the runner carries forward while its entry is
unchanged and leaves blank when the entry is new (`automated-tests-§4`, *the one boundary*). A
generated sentence that is wrong is fixed in LibKa0s and arrives on the next re-vendor; edited here
it is reverted silently by that re-vendor.

```sh
tests/_kit/run-automated-tests.sh                            # all four, writes a bundle
tests/_kit/run-automated-tests.sh --suite lint --suite tests # a subset
tests/_kit/run-automated-tests.sh --no-bundle                # print only, write nothing
```

It lives here rather than in each addon for the same reason the rest of the kit does: it must be
byte-identical everywhere, and the vendoring gate below already enforces exactly that. Two things
about it are load-bearing:

- **`lint` and `tests` gate; `perf` and `complexity` do not.** They are measured, recorded and
  diffed, never used to fail the run. `performance-§9`/`§10` are explicit that a wall-clock or
  complexity threshold which fails a run teaches everyone to reach for `--no-verify`, after which
  the gate protects nothing and the habit remains.
- **A missing tool is a skip, not a failure**, and a skip is recorded as one — so a green run that
  actually measured nothing cannot read as a green run that measured everything.
- **From kit revision 25 every row names the commit it measured and whether the tree was clean.**
  Both cells are read from git and nobody types them, a dirty row is kept and **marked** rather
  than dropped, and the table is widened **once** — every row written before the runner emitted
  these cells carries `unknown` in both, never `clean` and never a sha reconstructed from
  archaeology (`automated-tests-§4`). The full sha, the branch and a boolean `dirty` are in each
  bundle's `manifest.json`, as they already were.
- **From kit revision 26 a missing `tests/perf.lua` is read against the deviation register.**
  `automated-tests-§3` sanctions two perf skip reasons. Before recording reason (1), *nothing to
  run*, the runner reads the `## Documented deviations` table in `docs/ARCHITECTURE.md` and then the
  root `CLAUDE.md`. A row whose Rule cell is exactly `performance-§12` records reason (2), the
  ratified no-combat-path exemption, naming the file it came from, and `RESULTS.md`'s Perf section
  points at `docs/performance.md`. A register the runner cannot read exits 2 before any suite runs.
  `KA0S_PERF_EXEMPT=1` records reason (2) only in a repo that has no register.
- **An empty watch-list table prints its header row and separator, then `None.`** under a blank
  line (`automated-tests-§4` and the playbook's Step 3). Revision 25 printed `None.` in place of the
  header, and revisions 26 to 29 printed the header alone; from kit revision 30 it is both. The
  blank line keeps GitHub-flavored Markdown from reading `None.` as a row of the table, and the
  runner's own reader of the previous watch list skips it.
- **The band table leaves out generated non-shipping data** (kit revision 31), `layout-§1`'s second
  carve-out. Which files are generated is a fact about the repository that no path betrays, so the
  runner does not guess: it asks the repo's own `tests/run.lua` with
  `lua tests/run.lua --layout-cap-exempt PATH...`, which `Kit.run` answers from the
  `Kit.layoutCap.exempt` set the cap gate reads, with the one matching rule both call
  (`Kit.__layoutCapCovers`), before loading any suite. A file it leaves out is named in a line under
  the table, and `manifest.json`'s `bandFiles` and `overCapFiles` no longer count it. With no
  `tests/run.lua`, or no set, every file is listed as before.
- **The bundle is written to whatever `.gitattributes` declares for it**, read per path with
  `git check-attr text eol` at the end of the run — not assumed. Everything the runner writes goes
  down a plain shell redirect, which bypasses git's filters entirely, so before kit revision 10 every
  run in a CRLF-pinned repo left a fresh crop of LF stragglers that `git status` never mentions and
  `git add --renormalize` never fixes. A repo that declares nothing is left exactly as it is, and so
  is any path whose `text` is `unset`: `binary` unsets `text` but says nothing about `eol`, so a
  marked asset still answers `eol: crlf` from the pin and asking `eol` alone would rewrite a file git
  itself never converts (`line-endings-§7`).

**It is LF, and it must stay LF.** Every other file in this collection is CRLF, pinned by
`.gitattributes`. A `#!/usr/bin/env bash` line followed by CRLF makes the kernel look for an
interpreter literally named `bash\r`, so a CRLF-pinned repo that ships a `.sh` **MUST** carve it out
with `*.sh text eol=lf` — here and in every consumer. Without that line the vendored copy is broken
on every checkout, not in one contributor's.

## `vendor_sync.lua`

The consumer-side vendored-payload gate: it asserts that a repo's `libs/LibKa0s/` and `tests/_kit/`
are exactly what LibKa0s published at the tag that repo's `CLAUDE.md` says it bundles. It used to be
~150 lines copy-pasted into six repos with a one-line delta, which is six chances to fix any one
problem six different ways.

```lua
-- tests/test_vendor_sync.lua
local VendorSync = dofile("tests/_kit/vendor_sync.lua")
VendorSync.register(_G.AT_TEST, {})
```

A factory rather than auto-registration, so the consumer keeps its own test global and its own case
names — the names are what `docs/test-cases.md` counts, and swapping a hand-copied gate for this one
must not move a repo's numbers.

Two things about it living here are deliberate: the gate is **inside the payload it checks**, so a
locally patched `tests/_kit/` breaks the gate's own byte-identity assertion; and **LibKa0s cannot run
it** — there is no sibling to compare against from inside the library repo, which is why
`tests/test_kitsync.lua` is the library-side equivalent.

When the sibling checkout is absent the cases report **SKIP** with the reason, never PASS. Its
comparison contract, including the one line-ending normalization and why it exists, is stated in the
file's own header. Read that header before changing anything about how the bytes are compared.

**It also checks the runner's recorded mode** (kit revision 16, `automated-tests-§2`). Besides one
case per payload, `register` adds `the automated-test runner is recorded executable (100755)`,
which reads `tests/_kit/run-automated-tests.sh`'s mode out of the consuming repo's git index. The
bit lives there and nowhere a byte comparison or `ls -l` can see it: `cp` does not carry it, and on
DrvFs with `core.fileMode=false` everything looks executable. The case needs no sibling, so a
missing LibKa0s checkout does not skip it. It skips, with the reason, only where the index cannot be
read at all: no `io.popen`, no git, or not a work tree. `opts.runner` and `opts.runnerCase` override
the path and the case name.

## `test_eol.lua`

The first of the kit's three own suites. Its first case holds every file `git ls-files` reports to the
terminator `.gitattributes` declares for it, reading the bytes rather than trusting git's own
classification. From revision 26 it also names every **lone CR** (a CR no LF follows) as
`path:line`, over the same files: git's `text=auto` stores such a file as binary, so neither git nor
a count of CRLF pairs sees it. It is here rather than in each repo's `tests/` for the reason the rest of the
kit is here: eleven repositories need exactly the same gate and none of them should be asked to
re-type it. `line-endings-§7` MUSTs the check be mechanical and supplies a command; a command is
something someone runs, a suite is something the run runs.

Wire it in the consuming runner's suite list, which is the one line adoption costs:

```lua
Kit.run{ dir = "tests/", suites = { "test_schema", ..., { name = "test_eol", dir = "tests/_kit/" } } }
```

`Kit.assertSuiteInventory` scans `tests/_kit/` for suites as well as `tests/`, so a re-vendor that
lands this file in a repo that has not declared it goes **red** naming the entry to add. That is
deliberate: a gate that arrives silently and runs nothing is the failure this kit already refuses
everywhere else.

It reads the bytes for every path git calls text and skips every path whose `text` is `unset` —
`binary` unsets `text` and says nothing about `eol`, so a marked asset still answers `eol: crlf`
from a global pin and holding a .tga to a terminator count would be a red about an image. That is
the same rule the runner applies when it writes a bundle, and the two must not disagree. Everything
else it declines to check, it declines loudly: no `io.popen`, no git, no answer from `check-attr`
and it fails rather than passing.

The repair when it goes red is `rm <path> && git checkout -- <path>`, per path it names.
**`git add --renormalize .` fixes nothing here** — it rewrites the index, and the index was never
wrong; that is precisely why nothing else in a repository ever reports this.

**From kit revision 25 it carries a second case: the `.gitattributes` body itself.**
`line-endings-§5` publishes two canonical bodies — 84 lines client-bound, 85 non-client — and
§7 asks that a repo be **diffed** against the right one rather than read against it. The case picks
which by §2's mechanical discriminator (a `.toc`, a client-bound `libs/`, or the tracked payload
folder a Ka0s-owned library ships under `library-stack-§7`), never by a roster of repository
names, then holds the file line for line through the body's final line and its terminator. Below
the body, and only there, a `§5` appendix may carry the binary marks no extension reaches; it is
graded against §5's own five rules rather than waved through. Both bodies are copied into the suite
verbatim, which is why they sit in long-bracket strings: a transcript that gets re-spelled stops
being one.

## `test_prose.lua`

The second, and it is here for the reason the first one is: eleven repositories need
the same gate and none of them should be asked to re-type it. `localization-§5` makes US English
the source dialect, publishes the `BRITISH` and `ALLOWED` lists a gate MUST carry **whole**, and
requires the rule to be enforced mechanically — `luacheck` does not read English, and a repo's own
suites read behavior.

By the time this shipped, seven repositories had written the gate by hand and the copies had
already diverged in the part that costs most to get wrong: three called the file `test_prose.lua`,
three `test_spelling.lua`, and two folded it into `test_docs.lua`, so nothing could tell at a
glance which repositories had a gate at all. Four more had none. A rule enforced by eleven
hand-written copies is eleven chances to carry a subset.

Wire it the same way, and it is the same one line:

```lua
Kit.run{ dir = "tests/", suites = { "test_schema", ..., { name = "test_prose", dir = "tests/_kit/" } } }
```

**A repo that already has its own copy wires one or the other, never both.** Two gates over one
rule is two lists to keep whole, which is the divergence this file exists to end.

### What it reads

Every tracked `.lua`, `.md` and `.toc` file and `.luacheckrc`, minus `localization-§5`'s named
exclusions, which live in `prose_lists.lua` beside the gate: vendored code (`libs/`, `tests/_kit/`),
the frozen stores (`docs/audits/`, `docs/automated-tests/`, `docs/perf-analysis/`, `docs/reviews/`,
`docs/revendor/`, and from revision 26 `docs/superpowers/` and `docs/investigations/`),
`locales/enGB.lua` and the gate's own files. **From revision 26 three store-root files are read back
out of those folders**, named file by file in `SCAN_BACK`: `docs/automated-tests/README.md`,
`docs/automated-tests/RESULTS.md` and `docs/perf-analysis/README.md`. A store's dated bundles are
frozen, but these three are rewritten in place (`documentation-§3`), so they are authored text. A
repository's own `skipDirs` entry that only restates one of the kit's folders does not undo the
scan-back; one that is wider does, and so does `skipFiles`, both disclosed as below.

### `Kit.prose` — the generated-data carve-out

`localization-§5`'s third exclusion is a generated dump of the client's own strings, and it rests on
three facts about a repository that no path betrays: a script writes the file and a person does not
edit it, nothing loads it, and `.pkgmeta` keeps it out of the packaged zip. A gate can infer none of
the three, so the set arrives the way the cap gate's does — on the kit table, before `Kit.run`,
which is where an auditor already reads `Kit.layoutCap.exempt` naming the same folder for the same
three reasons:

```lua
Kit.prose = { exempt = { "GlobalStrings/" } }   -- generated, loaded by nothing, not packaged
Kit.run{ dir = "tests/", suites = { ..., { name = "test_prose", dir = "tests/_kit/" } } }
```

Absent is the normal case and means a repository with no generated data, which is ten of the eleven.
An entry is a tracked path or a folder ending in `/`; globs are not expanded, and a folder is
compared as `entry .. "/"`, so a sibling whose name merely starts with it is not swept in. An exempt
path is dropped **before it is opened** rather than filtered after the fact. An entry that matches
nothing is stale rather than silent and is not a failure, exactly as the cap gate treats one;
`Kit.prose` set to something other than a table **is** a failure, because a runner that made that
mistake would otherwise read as a repository with no generated data at all.

**A generated file that ships is not exempt.** Inside the payload a player downloads, the third
condition fails and the spellings reach a screen, which is the one thing the rule exists to prevent.
Nor is this a whole-file waiver by the back door: an authored file somebody would rather not fix
belongs in `tests/prose_waivers.lua`'s `waived` table, per file **and** per word, with the reason
written beside it.

**Two of the three conditions are GATED, and the third is the auditor's.** A path betrays nothing,
but the repository root the gate already runs in answers two of the three out loud, so it reads
them:

- **LOADED BY NOTHING.** Every tracked `.toc` is parsed and a declared narrowing covering any file a
  TOC loads reddens the run. Backslashes are read as the separators they are, `##` directives, `#`
  comments and blank lines are dropped, and each file line resolves against its own TOC's folder so
  a vendored library's TOC names its own files. The gate reads each TOC's own lines and follows
  nothing further -- no `.xml` include, no `dofile` -- so the rest of this condition stays with the
  third, as the auditor's.
- **EXCLUDED FROM WHAT A PLAYER DOWNLOADS.** The root `.pkgmeta`'s `ignore:` block is read and a
  narrowing no ignore line covers reddens the run. Only that block: a column-zero sibling key
  closes it, while indented comments and blank lines do not. An ignore entry covers a path exactly,
  by folder, or by the packager's `*`, matched on the whole path and on the basename.
- **GENERATED RATHER THAN AUTHORED** is not gated and cannot be: nothing in the repository root
  records whether a script or a person wrote the lines. A repository that names a hand-written file
  in the exempt set has fooled the gate and will be caught by a reader, which is the same division
  of labor `Kit.layoutCap.exempt` strikes.

**Where the repository has no `.toc`, the first check degrades out loud rather than disappearing**:
it skips with the reason printed, because a repo that packages no addon the client loads has no TOC
for LOADED BY NOTHING to be read off. Same for `.pkgmeta` where nothing is packaged. **A `.toc`
with no `.pkgmeta` is refused**, because the packager then ships the working tree whole.

**BOTH REFUSALS REACH BOTH CHANNELS.** A repository narrows this gate in two places -- `Kit.prose.exempt`
here, and `skipDirs` / `skipFiles` in the waiver file below -- and they land in the same exclusion
sets and take files out of the same scan. Gating one of them is gating neither, so every entry in
all three lists is a **declared narrowing** and the two refusals run over the lot, in the same words.
Each list is refused on **its own** matching rule, because a refusal must cover exactly what that
list suppresses: the carve-out matches a path or a folder, `skipDirs` is the plain prefix the scan
compares, `skipFiles` is one exact path. `localization-§5`'s own published exclusions -- `libs/`,
`tests/_kit/`, `locales/enGB.lua`, the frozen dated bundles -- are neither refused nor disclosed;
they are the baseline, and `libs/` is on every TOC in the collection on purpose.

**Both refusals read ONE resolved coverage set.** Every entry is resolved through its own rule
against the tracked authored set once, and the refusals, the disclosure and its counts all read
that one resolution. They used to resolve it apiece -- packaging asked `.pkgmeta` about the entry
**as written**, the TOC refusal asked about the paths the entry actually suppresses -- and for an
unanchored `skipDirs` prefix those are different questions. Under a `.pkgmeta` that ignores the
`tools` folder, `skipDirs = { "tools" }` hid the shipped root file `tools-notes.md` beside it with
both refusals green. So **the packaging refusal asks about the entry as written AND about every
path it covers**: the first arm keeps a stale entry honest, the second closes what it left open.
An entry that covers **no** tracked path is refused for its **spelling** instead -- git writes
forward slashes, with no leading `./` and no trailing `/`, and is case-sensitive -- because the
packaging message would contradict the same run's disclosure, which says it suppressed nothing.

**The narrowing also says what it suppressed, in one line covering both channels.** A third case
passes with every declared path, the list each came from, the file count, and **the paths
themselves, grouped under the entry that suppressed each**:

```
PASS  prose: the exclusions this repository declared suppressed 3 of 148 tracked authored file(s),
      by: docs/spell-research/ [skipDirs in tests/prose_waivers.lua] (3):
      docs/spell-research/2026-09-20/ANALYSIS.md, docs/spell-research/2026-09-20/DIFF.md,
      docs/spell-research/2026-09-20/SOURCES.md
```

A count with no path under it is what let a `.pkgmeta`-blessed entry over a shipped file read as
ratified rather than as suspicious. The list is **bounded and says so**: once the disclosure would
name more than twelve paths, every entry falls back to its count and three examples --
`GlobalStrings/ [Kit.prose.exempt in tests/run.lua] (28): ..., and 25 more (list bounded)` -- so
nobody reads a truncated list as a complete one.

So a narrowing is never invisible in a green run, whichever list supplied it. Its body re-measures
the live lists and compares them against the reading taken at load, so a suite or a waiver file that
changes between the two is caught rather than obeyed. The three cases register wherever a repository
declared a narrowing of **either** kind; keyed on the carve-out alone, a repository that narrows the
gate only through the waiver file got no disclosure and no refusal at all.

### `tests/prose_waivers.lua`, and why the seam exists

Some British spellings in a Ka0s tree are not the repository's English to correct, and the kit
cannot know which. AceTimer's flag field carries the British double-L spelling of *canceled* — a handle records it under that name
because that is what `mock_record.lua`'s live-timer survey reads off it, and correcting the
spelling stops the survey seeing a canceled timer as canceled, leaving a stand-down assertion
quietly unfalsifiable. Blizzard spells its `LFG_LIST_APPLICATION_STATUS_UPDATED` status the same
way, and an addon matches it verbatim off the event. `localization-§5` already says to match
game data on the token the game uses; this is that rule meeting this gate. A generated dump of
the client's own strings is **not** one of these and does not belong here — that is
`Kit.prose.exempt`, above.

So a consumer MAY ship an optional `tests/prose_waivers.lua`. Absent is the normal case and means
no waivers:

```lua
return {
  skipDirs  = { "docs/spell-research/" },           -- named, never patterned
  skipFiles = { ["docs/vendor-notes.md"] = true },
  waived    = { ["core/LifecycleSetup.lua"] = { ["cancel" .. "led"] = true } },
}
```

`skipDirs` and `skipFiles` extend `localization-§5`'s own **named exclusion** list and nothing
wider — a frozen dated store under a name only that repo knows, a document whose subject is this
rule. They are not a home for generated data.

**They face the same two refusals `Kit.prose.exempt` does.** An entry here that a TOC loads is
refused, and one `.pkgmeta` does not ignore is refused, for the identical reason: whatever a reader
means by the entry, a file inside the packaged payload carries its spellings to a player's screen.
They appear in the same disclosure line too. One consequence, stated rather than discovered: a
**British locale file cannot be excluded by `skipFiles`**, because a locale file is TOC-loaded and
shipped, so both refusals reject it. `locales/enGB.lua` is excluded by name in the kit's own copy of
`localization-§5`'s list, which is where a differently-named one belongs too — that list is
published by the standard, and a repository needing another name on it amends the standard rather
than its own waiver file.

`waived` is the **only** list here the two refusals do not police, because a waiver that has to name
the word cannot hide a spelling it did not name. It is therefore the way out a refusal points at.
Its **shape** is checked all the same: keys are the tracked paths being waived, values are tables of
string-keyed words, and either array form -- `waived = { "core/Foo.lua" }`, or a file's words written
as `{ "cancel" .. "led" }` -- is a **failure** rather than the silence it used to be, because the
scan looks both up by key and would have waived nothing at all.

The shape is per FILE and per WORD, never per file alone: a whole-file waiver hides every other
British spelling in a file the repo edits often, which is how a gate acquires a blind spot the size
of a module. A waiver file that exists but does not return a table is a **failure**, not an empty
one — the alternative silently widens the gate.

## `test_layout_cap.lua`

The third, new in kit revision 25, and the one that arrived with five hand-written predecessors
already in the collection — 232, 221, 209, 380 and 206 lines, no two byte-identical. `layout-§1`
caps every authored `.lua` file a repo tracks at 1500 lines and requires the disposition of each
breach be written where a reader and a gate can both find it: a `Files over the 1500-line cap`
heading **under** `## Documented deviations`, in `docs/ARCHITECTURE.md` or, for a Ka0s-owned
library repo, the root `CLAUDE.md`. This suite is what reads that census.

It takes `git ls-files` as its tree, drops vendored code (`libs/` and `tests/_kit/`), counts the
bytes on disk, and asserts three things and their converses: no over-cap file is missing from the
census, no census row outlives the breach it records, and every over-cap row names one of
`layout-§1`'s three terminal states — the issue naming the seam, the ratified deviation row, or the
scheduled peel. It does **not** judge whether an exemption is legitimate; that rests on three
repository facts no path betrays, and it stays with the auditor.

Two facts about a consumer cannot be inferred, so they arrive on the kit table before `Kit.run`:

```lua
Kit.layoutCap = {
  hub    = "docs/ARCHITECTURE.md",   -- the default; a library repo passes "CLAUDE.md"
  exempt = { "GlobalStrings/" },     -- layout-§1's generated-data carve-out, paths or folders
}
Kit.run{ dir = "tests/", suites = { ..., { name = "test_layout_cap", dir = "tests/_kit/" } } }
```

From kit revision 31 the same `exempt` set also keeps those files out of `run-automated-tests.sh`'s
band table, so it is declared once and read by both.

**A repo that wrote its own retires it by re-vendoring.** Leaving both is a basename collision the
inventory reports, and the bare declaration wires the local file over the kit's. A repo that tracks
no authored `.lua` wires nothing and the suite skips, with the reason said out loud.

## `test_diagnostics_contract.lua`

The fourth, new in kit revision 27. `debug-logging-§14` makes a diagnostics dump a MUST: exactly
`/<slash> diagnostics` and `/<slash> debug diagnostics` write one report into the debug console,
both work while the addon is disabled, the report appends and never clears, it lands with logging
off, both markers carry the brand, and no other name (`diag`, `dx`, or a name the addon retired)
runs it. LibKa0s builds the report; this suite checks the addon's half, through the addon's own
dispatcher, and the addon's own suite adds its domain sections.

The consumer's facts arrive on the kit table before `Kit.run`:

```lua
Kit.diagnostics = {
  brand       = "Ka0s Aura Master",               -- the DebugLog descriptor's brandName
  dispatch    = function(line) ... end,            -- run "/<slash> <line>" through the addon
  console     = function() return NS.DebugLog end, -- the live DebugLog instance
  setDebug    = function(on) ... end,              -- write the debug flag directly
  setDisabled = function(off) ... end,             -- stand the addon down (true) or up (false)
  retired     = { "dump" },                        -- optional: the addon's own retired names
  reset       = function() ... end,                -- optional: run before every case
}
Kit.run{ dir = "tests/", suites = { ..., { name = "test_diagnostics_contract",
  dir = "tests/_kit/" } } }
```

Until an addon has its report, `Kit.diagnostics` stays unset and the suite registers one declared
skip that names the rule, so the re-vendor that brings this file in stays green. The skip shows in
every run and in `docs/test-cases.md`.

## It is not a library

`testkit/` is **not** a LibStub major and **must never ship**.

- It has no `MAJOR`/`MINOR`, registers nothing with LibStub, and is never loaded by the client. The
  per-file-minor rule in `library-stack` does not apply to it, and a standards audit **MUST NOT**
  flag the missing version registry.
- It does carry a plain revision integer, `Kit.VERSION` at the top of `framework.lua`, exposed to
  suites as `KIT_VERSION`. That is **not** a LibStub minor and does not make this a library:
  nothing registers it, no load order depends on it, and two copies never negotiate — the vendoring
  gate below is byte-identity, not version comparison. It answers the one question byte-identity
  cannot answer alone: *which* kit is a given consumer holding. One number covers every file in the
  folder, because they vendor as one folder and are never adopted separately.
- It is vendored to `<Addon>/tests/_kit/`, not to `libs/`. `libs/` is the ship payload inside
  `#@no-lib-strip@`; anything there gets zipped. Under `tests/` the **existing** `- tests` entry in
  every addon's `.pkgmeta` already excludes it, so adopting the kit needs no packaging change and
  leaves no new ignore rule for the next scaffold to forget.
- It lives beside the shipping `LibKa0s/` folder rather than inside it, because `docs/releasing.md`
  defines that folder as "the payload and nothing else".

## Vendoring

Same discipline as the library itself:

```sh
cp -r testkit/. <Addon>/tests/_kit/
chmod +x <Addon>/tests/_kit/run-automated-tests.sh   # cp does not always carry the bit
diff -r testkit <Addon>/tests/_kit             # must be empty
cd <Addon> && lua tests/run.lua && luacheck .
```

The consumer's `.gitattributes` needs `*.sh text eol=lf` before the first re-vendor, or the runner
arrives CRLF and cannot execute.

Run the first two from the library repo's root, the same cwd `docs/releasing.md` assumes — the two
files give the same commands and must not disagree about where you are standing.

Never edit `tests/_kit/` in a consumer. A kit problem is a finding to fix here and re-vendor; a
local patch is a fork nobody knows about, and the next re-vendor silently reverts it.

LibKa0s is a consumer on the same terms as every addon: it reaches its own kit through
`tests/_kit/` rather than into `testkit/` directly, so `diff -r testkit tests/_kit` is the same gate
here as it is downstream, and a kit change that would break a consumer breaks this repo first.

## What a consuming `tests/run.lua` looks like

The runner keeps only what is genuinely per-addon: the load list, the lifecycle kick, and the suite
list.

```lua
local Kit    = dofile("tests/_kit/framework.lua")
local Loader = dofile("tests/_kit/loader.lua")
local mocks  = dofile("tests/wow_mock.lua")()   -- the addon's own extender

Loader.addonName = "AbsorbTracker"
local NS = {}
-- Libs first, and every file of LibKa0s.xml spelled out in XML order: the TOC pulls them through
-- the XML, so Loader.tocFiles cannot see them.
Loader.loadAll({ "libs/LibKa0s/Core.lua", ... , "libs/LibKa0s/PerfPanel.lua" }, NS, mocks)
Loader.loadAll(Loader.tocFiles("AbsorbTracker.toc"), NS, mocks)

NS:InitDB()
NS.CreateOptionsPanel()

_G.AT_TEST = Kit.expose{ NS = NS, mocks = mocks }

Kit.run{
  dir = "tests/",
  suites = { "test_schema", ..., { name = "test_eol", dir = "tests/_kit/" } },
}
```

A suites entry is a basename under `dir`, or a table: `{ name = ..., pending = "why" }` for a suite
being written (it registers as a declared skip instead of as nothing), and `{ name = ..., dir = ... }`
for a suite that ships in the kit rather than in `tests/`.

From kit revision 25 the inventory keys a declaration by the **pair** (directory, basename), so a
bare name and a `dir = "tests/_kit/"` entry of the same name are two declarations naming two
files. Directory spellings are reduced to one form first — a leading `./` stripped, `//` and
`/./` collapsed, exactly one trailing slash — because a runner that composes its `dir` out of a
resolved root reaches the gate spelling the same directory differently from the suites list beside
it. The folding is lexical: `..` and backslashes are left alone.

**A declaration and the runner's own `dir` are then read AGAINST EACH OTHER**, because folding the
spellings one hand produces is not the same as folding the spellings two hands produce. A runner
that hands `Kit.run` an absolute `dir` and then declares one kit suite relative and the next
absolute is writing both of them correctly, and both appear in real suites lists in this collection.
A relative entry under an absolute runner takes the runner's own root; an absolute entry under a
relative runner is cut back at the runner's own directory, the one anchor the two share, at its last
occurrence so a checkout that itself lives under a `tests/` cuts in the right place. An absolute
entry that never passes through that directory is left alone rather than given an invented
relationship. Without this, a correctly wired suite is reported as both missing and undeclared the
moment the runner is invoked by path from another working directory, and the run aborts before a
case executes.

**A remedy is advice about a SOURCE LINE, so it is printed the way that line has to read.** Under an
absolute runner the gate prints the repo-relative directory plus the instruction to build it from
the same root expression the runner already passes to `Kit.run` -- never the resolved path, which
belongs to one checkout and would break every other one if it were pasted in. The resolved path is
still printed, as a diagnostic saying where the file is. For the same reason the declined-gate
case's NAME is root-relative: that name is written into the generated `docs/test-cases.md`, and a
committed file must not depend on the working directory the generator ran from.

### Running it faster

Two things about the runner are worth knowing before a suite gets large.

**The loader caches compiled chunks** (kit revision 12 and later). A suite that builds a fresh,
isolated instance per case re-loads the whole source tree every time, which is the correct shape —
isolation comes from re-*running* the chunks under a new mock. What it does not need to do is re-read
and re-parse the bytes, and before revision 12 it did: one consumer's 1,246 cases drove 60,112
`loadfile` calls, 91% of the run's CPU. The cache is automatic, changes nothing about isolation
(it holds a function, not a result), and took that suite from 2m10s to 11.9s. A suite that rewrites a
source file mid-run and needs the new bytes calls `Loader.uncache(path)`.

**The suites can be split across processes** with `--jobs`:

```sh
lua tests/run.lua              # serial — the default
lua tests/run.lua -j auto      # one worker per CPU
lua tests/run.lua --jobs 4     # four workers
```

Each worker is a re-invocation of the same `tests/run.lua` with `--shard I/N`, so there is no second
code path. Shards take contiguous slices and their output is relayed in order, which makes a parallel
run's transcript byte-identical to a serial one; a shard that dies without reporting fails the run
rather than quietly shrinking the totals; and `--list` never shards.

This half is **opt-in per repo** — `Kit.run`'s default is `jobs = 1`. Splitting the suites also
splits the process-wide state they share (the `shared` instance, the SavedVariables globals), so a
suite that quietly depended on an earlier suite having run first passes serially and fails sharded.
That was always a bug; `--jobs` is what makes it visible. Switch it on with
`Kit.run{ ..., jobs = "auto" }` once the sharded run is confirmed green.

### Resource bounds (kit revision 23)

A run cannot take the machine with it. When `framework.lua` loads it re-launches the process once
under a re-launch **depth** limit, a **process-tree** memory cap (a `systemd-run --user --scope`
where systemd exists), a per-process `ulimit -v` and a wall-clock `timeout`; inside the run, every
case is held to a **heap budget**, a **CPU ceiling** and a cumulative **leak gate**, and a suite that
names a host path is refused. All of it arrives by re-vendoring, and every limit is an environment
variable (`KA0S_KIT_*`) or a `Kit.run` option. The table of names and defaults, and the incidents
behind each bound, are in `docs/api/testkit/version-23-docs.md` in the LibKa0s repo.

Because the bounds hold per run, **several repos' suites can run at once** — nothing here asks for
one-at-a-time. `--jobs auto` also caps its worker count by available memory.


`Kit.expose` merges `test` and the assertions into the table you pass, so each repo keeps its own
global name (`AT_TEST`, `LK_TEST`, `KICKCD_TEST`, …) and its own extra keys, and **no existing suite
file has to change** when a repo adopts the kit.

## What an addon's `tests/wow_mock.lua` looks like

A thin extender over the base. Plain per-key overwrite — the base builder returns a fresh table per
call, so there is no merge machinery to reason about.

```lua
local base = dofile("tests/_kit/mock_base.lua")

return function()
  local M = base()
  M.__absorbs = {}
  M.UnitGetTotalAbsorbs = function(unit) return M.__absorbs[unit] or 0 end
  M.C_ClassColor = { GetClassColor = function() return { r = 1, g = 1, b = 1 } end }
  return M
end
```

Use `M.__stubFrame()` to build extra frame-shaped objects and `M.__libs` to register additional
library fakes (AceDBOptions, LibSharedMedia) without reaching through LibStub's closure.

## What the mock records, and how to assert on it (`mock_record.lua`)

**Revision 22** adds the five surveys a suite needs to ask whether an addon has actually stood down,
and a sixth file to carry them. Every one of them answers over the LIVE state, and every one of them
LOSES entries when the addon gives something up — which is the half that matters:

| Member | Answers |
|---|---|
| `M.__registrations()` | `{ target, kind, event, unit }` for every live registration. `kind` is `event`, `message`, `bucket`, `frame` (a raw `frame:RegisterEvent`), `unit` (one row **per unit token**) or, from revision 26, `callback` — an `EventRegistry` callback, shaped `{ kind, event, owner }` with **no `target`**. |
| `M.__timers()` | every armed AceTimer handle, un-canceled `C_Timer` ticker and frame carrying an `OnUpdate`. `M.__timers` **indexed** is still the pending queue it always was. |
| `M.__shownFrames()` | every frame this build made that is shown, in creation order. From revision 26 a new frame starts **shown**, as `CreateFrame` returns one in the client, so a frame production builds and never hides is on this list. |
| `M.__svWrites()` | `{ path, value }` for every write that reached a watched SavedVariables tree since `M.__resetSvWrites()`. `M.__watchSv("<Global>")` adds a root the AceDB fake did not create. |
| `M.__printed()` | every line that reached the chat frame, plus `M.__resetPrinted()` and `M.__recordPrint(line)` for a printer that ends somewhere else. |
| `M.__aceguiLive(type)` | from revision 26, how many widgets of that type the AceGUI fake has handed out and not taken back; with no type, `{ [type] = count }` for every type with one out. The fake never reuses a widget, so this count is the only way to see a render that Creates and never Releases. Assert on the difference across a render: the shared mock carries earlier suites' widgets. |

Driving them: **`M.__fire(event, ...)` dispatches to the live registration set only** — what the
client would do — and **`M.__fireUnconditional(target, event, ...)` fires at a target whose
registration has been removed**, which is what proves a survivor would have been caught. A suite
that omits the second is asserting on its own silence: an empty registry dispatches nothing whether
the addon stood down or the harness lost the ability to dispatch at all.

The same revision models **`AceBucket-3.0`** (`RegisterBucketEvent`, `RegisterBucketMessage`,
`UnregisterBucket`, `UnregisterAllBuckets`), because a bucket is a registration a stand-down has to
remove and the kit had no model of one. A bucket coalesces onto the kit's one timer queue and does
not call back if it was unregistered before its tick.

`mock_base.lua` installs this file itself — it is **not** opt-in the way `mock_ids.lua` is, because
a survey a consumer forgets to switch on does not fail a stand-down suite, it passes it over an
empty table. The kit vendors as one folder, and a copy missing `mock_record.lua` **raises** on the
first `base()` rather than degrading. See `docs/api/testkit/version-22-docs.md`.

**Revision 26** adds `mock_events.lua`, installed the same way. `M.EventRegistry` is a recording
fake of Blizzard's CallbackRegistry — `RegisterCallback(event, func, owner)`,
`UnregisterCallback(event, owner)`, `TriggerEvent(event, ...)`, one callback per (event, owner),
invoked as `func(owner, ...)` — and every live callback is a `callback` row in `M.__registrations()`,
so a stand-down suite sees one left behind. A raw `frame:RegisterEvent` or `RegisterUnitEvent` on a
name in `M.__badEvents` now raises `Attempt to register unknown event "<NAME>"`, as the AceEvent path
already did, and records nothing. `M.C_EventUtils.IsEventValid(name)` answers `false` for such a
name; set `M.C_EventUtils = nil` to model an older client. See `docs/api/testkit/version-26-docs.md`.

## Id lookups for an id list (`mock_ids.lua`)

**Revision 20** adds the answers LibKa0s-Options-1.0's `ResolveId`, `IdInput` and `IdList` read:
`C_Spell.GetSpellInfo` by id or name, `C_Item.GetItemInfoInstant`, `C_Item.GetItemNameByID` and
`C_Item.GetItemQualityByID`, and `C_CurrencyInfo.GetCurrencyInfo`, over records a suite seeds. They
are **opt-in**, in a file of their own, installed on a finished mock after the harness's own
namespaces:

```lua
local M = base()
dofile("tests/_kit/mock_ids.lua")(M)
M.addIdRecord("spell", 21562, "Power Word: Fortitude", 135987)
M.addIdRecord("item", 2589, "Linen Cloth", 132889, true, 1) -- uncached: icon yes, name and quality not yet
```

The base installs none of them, because three consumers reach their Compat fallbacks by clearing
`C_Spell` or `C_Item`. The installer fills only the keys still missing, so a harness's own item
fixture keeps answering. A name lookup ignores case and answers the lowest matching id.
`M.clearIdRecords()` empties every kind between cases. The same revision gives the AceGUI fake
`GetText()`, `SetType(t)` (recorded as `checkType`) and `DisableButton(v)` (recorded as
`buttonDisabled`). See `docs/api/testkit/version-20-docs.md`.

What `IdInput`'s suggestions read is a **second** opt-in, called after the install:
`M.installIdSuggestions()`. It fills, only where missing, the bag walk (`C_Container`), the
spellbook's enumeration (`C_SpellBook`), the two quality-tier lookups (`C_TradeSkillUI`) and
`C_Spell.GetSpellSubtext`. A suite seeds them with `M.setBagItems(bag, ids)`, `M.setSpellBook(ids)`,
`M.setCraftedQuality(id, tier)`, `M.setReagentQuality(id, tier)` and `M.setSpellSubtext(id, text)`,
and `M.clearIdRecords()` empties those seeds along with the records. It also gives the AceGUI fake's EditBox an `editbox` input frame, where a test fires
`OnArrowPressed`, `OnEscapePressed` and `OnEditFocusLost`. None of this is in the plain install:
ConsumableMaster walks its bags through `_G.C_Container`, which a namespace on the mock would
shadow, and PanelMaster's harness adds its own `editbox` only when there is none.

## Asking a frame how tall it is

`GetHeight()` and `GetWidth()` answer **0 for every frame nobody armed**, which is what roughly 308
test files across the collection are written against. Arm the one frame a case cares about with
`f:__setGeom(w, h)`, and it answers:

```lua
local tex = M.__stubFrame():__setGeom()      -- arm it, size to follow
tex:SetAtlas("Options_Tab_Middle", true)     -- production dresses it
tex:GetHeight()                              -- M.__atlasSizes["Options_Tab_Middle"][2]
```

`SetAtlas` records `f.__atlas` whether or not a size was asked for, so a case that only wants to know
which art a widget dressed itself in needs no arming at all. `useAtlasSize` — the same argument that
makes a real texture take the art's dimensions — records the size `M.__atlasSizes` publishes for that
atlas; an atlas the table does not publish leaves the geometry as it found it, because the client
draws nothing for an unknown atlas rather than collapsing the texture to zero.

**The arming belongs to the test and never to the code under test.** Production calls `SetAtlas`
itself — `OptionsWidgets.lua` measures its tab pitch on a probe texture no test holds a handle to —
so a `SetAtlas` that armed geometry on its own would switch that measurement on in every suite in the
collection at once. That was tried; three of LibKa0s's own widget cases went red inside a minute.

`M.__atlasSizes` is a **fixture, not a measurement**. Nothing in it was read off a client. The two
tab families answer different heights on purpose — a table answering one number for every atlas could
not fail a selection-invariance assertion — so read the figure a case expects out of the table rather
than restating it, and add an atlas your addon needs in your own `tests/wow_mock.lua`.

## Asserting a degradation stub against the real surface

A degradation stub is a second implementation of somebody else's surface, so it drifts the moment
that surface grows a member the host starts calling — and it drifts silently, because the live path
stays green and only the degraded path raises, in exactly the install the stub exists for.
`Kit.assertSurfaceParity` reports **every** divergence in one message, in either of two forms:

```lua
T.assertSurfaceParity(live, degraded, "Slash stub", { HelpHeader = true })  -- two tables
T.assertSurfaceParity(degraded, "LibKa0s-Slash-1.0", { HelpHeader = true }) -- by name
```

The by-name form is selected by a **string** in the second position. It compares only the surface's
**public** members — `Kit.publicMembers`: every string key that is neither LibStub bookkeeping
(`MAJOR`, `MINOR`, `MODULES`) nor `__`-prefixed — because a stub owes none of those, and reported raw
they are half a dozen correct omissions read out as failures on the case's first run.

The kit cannot resolve a name on its own. It has no LibStub, no mock and no addon namespace, and the
loader hands each chunk a mocked environment rather than writing into `_G`, so a kit reaching for
`_G.LibStub` would resolve nothing and report every stub as fine. The harness registers the source,
once:

```lua
Kit.setSurfaceSource(mocks.LibStub)                          -- callable: src(name, true)
Kit.setSurfaceSource{ ["LibKa0s-Options-1.0"] = NS.Helpers } -- table: name -> live surface
```

`Kit.expose` wires the callable shape for you when the exposed table carries `mocks` or `mock` with a
`LibStub` on it, and only when nothing is registered yet. Use the table shape when the stub mirrors
an **instance** rather than a library table — every `settings/OptionsSetup.lua` arm in this
collection stubs `NS.Helpers`, which is what `lib:New(descriptor)` returned and what the kit could
never build for itself.

An unresolvable name, a source that raises, a name answering something other than a table, or no
source at all is a **failure** naming the fix — never a quiet pass.

## The Ace fakes, and the shims they replace

Ace3 is faked here rather than loaded, and each fake models what a suite has needed to observe,
checked against the real Ace3 source. **Build on them rather than replacing them**: wrap a fake in
`M.__libs` and call the kit's through, and layer only what is genuinely your addon's. A harness that
replaces a fake wholesale never receives a kit revision again. The fakes never read their receiver, so
a wrapper that calls through with its own table as `self` is served.

**Revision 26** makes the AceDB fake's profile verbs fail where AceDB-3.0 fails. `CopyProfile(name,
silent)` raises `Cannot have the same source and destination profiles ("<name>").` when `name` is the
active profile, and `Cannot copy profile "<name>" as it does not exist.` for a missing source unless
`silent`; `DeleteProfile(name, silent)` raises `Cannot delete the active profile ("<name>") in an
AceDBObject.` on the active profile, and `Cannot delete profile "<name>" as it does not exist.` on a
missing one unless `silent`. The messages are AceDB-3.0's own, byte for byte (`AceDB-3.0.lua:531-537`
and `:581-587`), raised at level 2. `CopyProfile` now resets the active profile before copying, as
AceDB does, so a key the source lacks reads its default. `SetProfile` strips the **outgoing** profile
of every value equal to its default (`:460-463`) — the scalar and plain-table arms of
`removeDefaults`, not the `"*"`/`"**"` wildcards. Through revision 25 every bad name returned
silently, so a consumer's copy or delete command passed its suite on a name that raises in the client.

**Revision 19** fixes one more. The AceDB fake's `ResetProfile` fires `OnProfileReset` with the
database alone, as AceDB-3.0 does (`self.callbacks:Fire("OnProfileReset", self)`); through revision
18 it passed the active profile as a third argument, so a reset handler that read one passed under
the kit and got `nil` in the client. A handler that needs the profile asks `db:GetCurrentProfile()`.

**Revision 18** fixes one argument. The AceDB fake's `CopyProfile` fires `OnProfileCopied` with the
**source** profile's key as its third argument, as AceDB-3.0 does; through revision 17 it passed the
active profile, so a copy of `"Raid"` into `"Default"` reached a handler as a copy of `"Default"`.
`OnProfileChanged` still carries the profile switched to. (`OnProfileReset` then kept the active
profile; revision 19 drops it.)

**Revision 17** added the surfaces six consumer harnesses had hand-rolled:

- **`NewAddon([object,] name, lib, ...)` honors its mixin list** — it embeds exactly the named
  libraries through `LibStub`, names the object, registers it for `GetAddon` and stamps AceAddon's
  object model. `NewModule` builds modules. The lifecycle is driven the way the client drives it:
  `AceAddon.frame:__fire("OnEvent", "PLAYER_LOGIN")` initializes everything queued, then enables each
  addon and then its modules, in order; `AceAddon:EnableAddon(addon)` is the enable cascade alone.
  `NewAddon(target)` — exactly one argument, a table — keeps revision 16's behavior.
- **AceEvent is two CallbackHandler registries.** Messages take string methods, the optional `arg`
  and `UnregisterAllMessages`; `M.__msgRegistry` is the message registry. `M.__fireEvent(event, ...)`
  fires a game event at every registrant and answers how many ran. An event name in `M.__badEvents`
  raises on its first registration, as retail does.
- **AceTimer is real**, on the kit's queue: `M.__fireTimers()` skips a canceled timer and answers how
  many ran. A canceled handle carries AceTimer's own field name, and a `C_Timer.NewTimer` handle
  answers Blizzard's own method; the testkit document names both.
- **AceConsole** records chat commands in `AceConsole.commands`; `AceConsole:__slash(command, input)`
  runs one.
- **AceGUI** publishes `WidgetVersions` and a layout registry.

Four pieces arrived at kit revision 16, each replacing a shim a consumer had written for itself.
Delete the local copy when you re-vendor:

- **`AceGUI:Release(w)`** follows the real one's order and records what it took back:
  `w.__released = true`, and `AceGUI.__released` in order. It fires `"OnRelease"` before it wipes
  the widget's callbacks and `userdata`. `Release(nil)` and a second release of the same widget both
  raise, as they do in the client. `w:Release()` is the same call.
- **An `AceEvent:Embed(t)` target** records game events with `RegisterEvent`, `UnregisterEvent` and
  `UnregisterAllEvents` on `t.__events`. These are the same functions the `NewAddon` target carries,
  so a module's own event target and the addon object behave identically. `RegisterEvent` raises
  where CallbackHandler does, including a missing method. Fire a recorded function as
  CallbackHandler does, `t.__events[event](event, ...)`, and a recorded method name as
  `t[method](t, event, ...)`.
- **`NewAddon`** stamps AceConsole's `Printf` beside its `Print`, so an addon that forgets to take
  its own `NS.Printf` back after `NewAddon` fails the way it does in the client.
- **`vendor_sync.lua`** checks the runner's recorded mode, as described above.

## Fidelity rules

These are why this is one file rather than one per repository. Each exists because a friendlier mock already hid
a real bug.

1. **A stub that silently succeeds is worse than no stub.** If production code branches on a return
   value, the mock must return something a branch can distinguish.
2. **Getters used in arithmetic or concatenation must return real numbers and strings.** The
   always-shown-scrollbar patch multiplies `GetHeight()` and concatenates `GetName()`; both raise on
   a table, which is what the metatable's blanket "return the frame" would hand them.
3. **Anything a test needs to observe must be recorded, not no-opped.** Event registration, script
   handlers, widget creation order. A no-op `RegisterUnitEvent` lets a widened or dropped per-unit
   event filter pass the entire suite.
4. **Anything a test needs to drive must be fireable.** `__fire` on frames and on AceGUI widgets is
   what makes a lazy first-`OnShow` render and an `OnValueChanged` write path reachable at all.
5. **Model the awkward real behavior, not the convenient one.** AceDB's `copyDefaults` merges in
   place; AceConsole's `Embed` clobbers a same-named custom `Print` and `Printf`. All are reproduced,
   because each has already caused a real bug.

## Known divergence, deliberately kept

`CreateTexture` and `CreateFontString` answer from the frame stub's metatable and therefore return
**the frame itself**, not a distinct object. WhatGroup's and KickCD's own mocks make them distinct
and treat that as a correctness requirement — and they are right.

It is kept because changing it is not a harness change. AbsorbTracker's `tests/perf.lua` memoizes
frame proxies specifically *because* `bar.valueText` and `bar.statusBar` are the same table, so
distinct objects move its `api/iter` figure — which is the parity gate for library extractions — and
`tests/test_display.lua` counts `Show`/`Hide` calls that currently land on one shared object.
LibKa0s's own `PerfPanel.lua` carries a `__label`/`__state` workaround for the same reason.

Fixing it is a deliberate change with its own test updates and a fresh parity baseline. It is
tracked, not forgotten.
