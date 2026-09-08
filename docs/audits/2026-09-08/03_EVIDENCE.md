# 03 — Evidence

Every `file:line` below was re-read at the moment this file was written, and the cited text is quoted
beside it. Every count was produced by the command shown, run from the repo root, with its scope
stated. No number is carried forward from an earlier bundle.

---

## 0. Resolving the standard

```
$ git clone --depth 1 https://github.com/tusharsaxena/WowAddonStandards was
$ head -1 was/standards/STANDARDS.md
# Ka0s WoW Addon Standard (v2.39.0, 2026-09-07)
$ git -C was log -1 --format='%H %ad %s'
7e609f580943be51201f1bde190b2cd1f1433bd1 Tue Sep 8 21:11:16 2026 +0530 Merge branch 'feat/2026-09-07-audit-review-remediation'
```

A `curl`-fetched copy left in the session scratchpad by an earlier run was diffed file-by-file against
the clone. **Twelve section files differed** — `anti-patterns`, `audit-review-history`,
`automated-tests`, `documentation`, `line-endings`, `lint`, `localization`, `open-evolutions`,
`options-ui`, `packaging`, `slash-commands`, `standalone-windows` — i.e. the stale copy was
pre-amendment. It was deleted; the clone is what every rule below is measured against.

---

## 1. Lint

**Scope:** the whole tree as `.luacheckrc` defines it — `exclude_files = { "libs/", "docs/audits/",
"docs/reviews/", "_dev/", "tests/_kit/" }`, so `libs/`, the frozen audit and review bundles, `_dev/`
and the vendored kit are **out**; **`core/`, `defaults/`, `locales/`, `modules/`, `settings/` and the
whole of `tests/` except `_kit/` are in.**

```
$ luacheck .
...
Total: 0 warnings / 0 errors in 59 files
$ luacheck . | grep -c '^Checking'
59
```

`.luacheckrc:12` — `exclude_files = { "libs/", "docs/audits/", "docs/reviews/", "_dev/", "tests/_kit/" }`
— matches v2.39.0's amended `lint` template exactly: narrowed to `tests/_kit/`, nothing wider.

`.luacheckrc:73` — `files["tests/"] = {` — the harness global is scoped here, not in top-level
`read_globals`.

`.luacheckrc:14` — `-- NO TOP-LEVEL \`ignore\`, and none is coming back (lint-§1, \`M4-11\`). This file carried`
— no blanket ignore. The thirteen surviving suppressions are per-file `212/self` stanzas
(`.luacheckrc:114-134`), each with a written reason at `:103-110`.

Under the ratified `performance-§12` decline, `lint` forbids `debugprofilestop` in `read_globals` and
`LootHistoryPerfDB` in `globals`:

```
$ grep -c 'debugprofilestop\|PerfDB' .luacheckrc
0
```

## 2. Headless suite

```
$ lua tests/run.lua | tail -1
719 passed, 0 failed, 0 skipped, 719 total
```

Three vendored gates ran green inside it, quoted from the run:

```
  PASS  libs/LibKa0s is the LibKa0s release CLAUDE.md says this addon bundles
  PASS  tests/_kit is the test kit that shipped with that release
  PASS  eol: every tracked file carries the terminator .gitattributes declares for it
```

`docs/test-cases.md` holds **719** rows (`grep -c '^- ' docs/test-cases.md` → `719`) and
`README.md:7` reads `![Tests](https://img.shields.io/badge/Tests-719%2F719_passing-green)` — badge,
inventory and run agree (`testing-§5`).

## 3. Vendored Ka0s-owned library — `diff -r`, both halves

Provenance line read first, because it is the ref the diffs use:

`CLAUDE.md:51` — `Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.27.0 (MIT) — the Ka0s-owned shared`

```
$ grep -n 'Bundles \[LibKa0s\]' CLAUDE.md
51:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.27.0 (MIT) — the Ka0s-owned shared
$ grep -n 'Bundles \[LibKa0s\]' README.md          # expect none
$ grep -nE '^## (Libraries|Bundled libraries|Libraries and credits|Credits and libraries|Credits and bundled libraries)' README.md   # expect none
$ grep -n 'WoW_Addon_Standard' README.md
6:![Standard](https://img.shields.io/badge/Ka0s-WoW_Addon_Standard-yellow)
```

The badge is the **bare** `![Standard](…)` form, not wrapped in a link (`documentation-§1` #2). No
bundled-library inventory heading and none in the intro prose. The provenance line is in `CLAUDE.md`
and **not** in `README.md`, so `tests/_kit/vendor_sync.lua` finds it where it looks (anti-pattern #59,
anti-pattern #58 both clear).

Sibling repo found at `/mnt/d/Profile/Users/Tushar/Documents/GIT/LibKa0s`. Diffed against the **tag the
provenance line names**, not `HEAD`:

```
$ git -C ../LibKa0s archive v1.27.0 | tar -x -C /tmp/libk
$ diff -r /tmp/libk/LibKa0s ./libs/LibKa0s && echo "SHIP DIFF EMPTY"
SHIP DIFF EMPTY
$ diff -r /tmp/libk/testkit ./tests/_kit && echo "TESTKIT DIFF EMPTY"
TESTKIT DIFF EMPTY
```

Both **MUST**-empty diffs are empty over the whole folder — every module, not only the wired ones — so
neither anti-pattern #45 (drift) nor #48 (partial vendoring) applies. The harness sits under `tests/_kit/`
and not `libs/`, so it does not ship.

`LootHistory.toc:27` — `libs\LibKa0s\LibKa0s.xml` — the single aggregate, listed once, after Ace3.
No individual `LibKa0s` `.lua` file appears in the TOC.

## 4. Line endings

**Scope:** every tracked file — `git ls-files` — with binaries skipped by asking git for `text` as
well as `eol`, and files with no `\n` skipped.

```
$ test -f .gitattributes && echo present
present
$ grep -n '^\* text=auto eol=\(crlf\|lf\)$' .gitattributes
26:* text=auto eol=crlf
$ grep -n '^\*\.sh text eol=lf$' .gitattributes
34:*.sh text eol=lf
$ grep -c ' binary$' .gitattributes
23
```

The repo ships a `.toc`, so it is client-bound and `eol=crlf` is the correct pin (`line-endings-§2`).

**§5, the body diff** — 81-line client-bound canonical body extracted from
`standards/standards/line-endings.md`:

```
$ diff <(head -n 81 .gitattributes | tr -d '\r') /tmp/canon-client.txt && echo "BODY IDENTICAL"
BODY IDENTICAL
$ wc -l < .gitattributes
81
$ tail -n +82 .gitattributes | tr -d '\r' | grep -m1 .
(no output; exit 1)
```

Byte-for-byte canonical, no `line-endings-§5 appendix` and none owed — the repo vendors no
extension-less binary.

**§7 property (e), the working tree against the pin:**

```
$ git ls-files -z | xargs -0 -I{} sh -c '
    set -- $(git check-attr text eol -- "{}" | sed "s/.*: //")
    [ "$1" = unset ] && exit
    cr=$(tr -dc "\r" < "{}" | wc -c); lf=$(tr -dc "\n" < "{}" | wc -c)
    case "$2" in crlf) [ "$lf" -gt 0 ] && [ "$cr" -ne "$lf" ] && echo "{}";;
                 lf)   [ "$cr" -gt 0 ] && echo "{}";; esac' 2>/dev/null | wc -l
0
```

**Zero.** The 2026-09-07 bundle measured nine with the same command; that bundle is frozen and is not
edited, so the two numbers are reconciled here instead: `M4-10` ran `git add --renormalize .` plus a
re-checkout and closed all nine. The gate `line-endings-§7` MUSTs — `tests/_kit/test_eol.lua`,
test-kit revision 15 — is present, reports green in §2's run, and agrees with this measurement, so
there is no gate finding either.

## 5. Packaging

**Scope:** every root dot-entry the shell can see, `.git` excluded (the packager never sees it).

```
$ for e in .luacheckrc .pkgmeta .gitignore .gitattributes .claude .superpowers docs tests _dev; do
    grep -q "^  - $e\b" .pkgmeta || echo "NOT IGNORED — $e"; done
NOT IGNORED — .claude
$ for e in .[!.]*; do [ -e "$e" ] || continue; [ "$e" = ".git" ] && continue;
    grep -q "^  - $e\b" .pkgmeta || echo "UNACCOUNTED — $e"; done
(no output)
$ ls -a | grep '^\.'
.git .gitattributes .gitignore .luacheckrc .pkgmeta .pytest_cache .superpowers
```

The strong-form check (`packaging-§29`) prints nothing. The weak-form list names `.claude`, which does
not exist here; the reason is written in the file —

`.pkgmeta:16` — `  # stale, not about a package growing. .claude is deliberately absent from this`

— and continues to `:18`. That is **LH-61**, filed Info.

`.pkgmeta:9` — `  - .gitattributes   # the repo's line-ending policy: governs the checkout, not the package`
`.pkgmeta:10` — `  - .pkgmeta         # packager configuration: consumed before the zip is built, of no use inside it`

Both are the lines `LH-45` asked for; the self-reference at `:10` is the one v2.39.0 added to the
template itself.

## 6. Complexity — measured, and its drift recorded

**Invocation taken verbatim from the standard** (`automated-tests-§1`, `AUDIT.md` step 6); no extra
flag, no narrowed path, no re-tuned threshold. **Scope:** the whole repo minus `./libs/*` and
`./tests/_kit/*` — so `core/`, `defaults/`, `locales/`, `modules/`, `settings/` and `tests/` are all in.

```
$ lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .
...
No thresholds exceeded (cyclomatic_complexity > 15 or length > 1000 or nloc > 1000000 or parameter_count > 100)
Total nloc   Avg.NLOC  AvgCCN  Avg.token   Fun Cnt  Warning cnt   Fun Rt   nloc Rt
     13879       6.5     2.2       52.6     1809            0      0.00    0.00
```

`lizard` version 1.24.0 (the same one the record's `host.lizard` names). **Zero warned functions.**

**Drift against the latest bundle**, `docs/automated-tests/20260908-181338/` (stamped
`2026-09-08T18:13:38+05:30`, sha `1ef54e1`, `"release": null`):

| | Record (`20260908-181338`) | Measured now (HEAD `289b280`) | Drift |
|---|---|---|---|
| Total NLOC | 13670 | **13879** | +209 |
| Functions | 1803 | **1809** | +6 |
| Warned functions | 0 | **0** | — |
| Suite cases | 714 | **719** | +5 |
| Lint files | 58 | **59** | +1 |
| Files in the 1000–1500 band | 4 | **4** | — |
| Files over the 1500 cap | 0 | **0** | — |

**No function crossed a `lizard` threshold and no file entered or left `layout-§1`'s band since that
run.** The whole drift is one commit: `5600e08` (`M4c-06`), which landed ~3 hours after the bundle and
added `tests/test_lintconfig.lua` (278 lines, 5 cases). The record's stamp dates it at three hours
old. **The checkpoint is release, not commit, and no bundle in the record is a release run** — all
eight carry `"release": null` — so this is a note about the release process, not a finding, and it is
deliberately **not** re-filed as `LH-49`.

`docs/automated-tests/README.md` and `docs/automated-tests/RESULTS.md` both exist; the vendored runner
is present and executable (`git ls-files -s tests/_kit/run-automated-tests.sh` → mode `100755`); there
is no retired `docs/complexity.md`.

## 7. The watch list, read as a decision record — LH-52

Four Band rows, three reading **Accepted** and one reading **Peel next**. Not "every entry accepted",
and short enough to read in one pass, so the backlog-in-disguise test passes on shape. The one that
fails is the disposition itself:

`docs/automated-tests/RESULTS.md:81` — `| 1000–1500 (on notice) | \`modules/Analytics.lua\` | 1178 | **Peel next — unblocked since [\`20260804-233322\`](20260804-233322/), and`
… continuing in the same cell: *"still not started after five runs … Nothing tracks it, and that is the
gap this cell has now reported five times running: a disposition that names itself next and never moves
is a decision that has stopped being one. No peel lands this cycle (`03_SPEC.md` § C22), so the
remaining honest move is an owned issue, and `M5-07` is where this plan files what it decided not to do."*

`git log` on the file shows the disposition surviving each regeneration:

```
$ git log --oneline --date=short --format='%h %ad %s' -- docs/automated-tests/RESULTS.md | head -4
830b425 2026-09-08 M5-01: the record is regenerated, and three files called flat had all moved
a571a78 2026-08-25 docs: the fast test gate, and two smoke steps that still expected the bug
91db662 2026-08-07 automated-tests: record run 20260807-114650 — green
7050394 2026-08-07 Re-vendor LibKa0s v1.8.2 — testkit revision 10
```

**§4's shelf life counts release runs and there are none**, so the letter of the rule has not started:

```
$ grep -h '"release"' docs/automated-tests/*/manifest.json | sort | uniq -c
      8   "release": null,
```

The issue the row promises does not exist:

```
$ gh issue list --state all --limit 200 --json number,title,createdAt,state,labels ...
#29 2026-09-08T11:56:47Z [CLOSED] Withdraw the ratified performance-§12 exemption: declined — the citations rotted, the argument did not — state:will-not-do severity:low
#28 2026-09-08T11:56:36Z [CLOSED] LOOTHISTORY-R-16: /lh help advertises config on a library-less load, where it silently declines — state:done severity:low
#27 2026-08-25T07:11:22Z [CLOSED] RecordAdded fans out ~9 full-history passes per looted item, in combat, uncoalesced — state:done severity:high
```

`M5-07` filed 25 issues across nine repositories on 2026-09-08; the only two that landed here are #28
and #29, and neither is the Analytics peel. Three issues are open — #9, #11, #16, #17 — all
`state:triaged` feature work, none of them this.

**On the nature of the CCN here:** `modules/Analytics.lua` carries no warned function at all (max CCN
across the repo is 15, warn threshold 16), so this row is about **size**, not density. The two
functions that do sit at exactly 15 are in `modules/BrowserTable.lua` (`@605-653`, `@1028-1071`), and
per `performance-§10` that is dense **defaulting and guarding** — `lizard` counts every `and`/`or`
short-circuit as a decision — rather than tangled control flow.

## 8. British spellings — LH-55

**Scope:** every tracked `.lua`, `.md` and `.toc` **except** `libs/`, `tests/_kit/`, `docs/audits/`,
`docs/reviews/`, `docs/revendor/`, `docs/superpowers/` and `docs/automated-tests/<run>/` — i.e. the
four exclusions `localization-§5` names, each by directory rather than by pattern. **81 files swept.**
The gate script carries the `BRITISH` and `ALLOWED` lists **whole**, copied from
`standards/standards/localization.md:192-227`, with `ALLOWED` removed as whole words **before** the
substring scan, as §5 requires.

```
$ git ls-files '*.lua' '*.md' '*.toc' | grep -v '^libs/' | grep -v '^tests/_kit/' \
    | grep -v '^docs/audits/' | grep -v '^docs/reviews/' | grep -v '^docs/revendor/' \
    | grep -v '^docs/superpowers/' | grep -vE '^docs/automated-tests/[0-9]' | wc -l
81
$ lua brit.lua scan.txt | tail -1
TOTAL HITS: 62
```

62 hits over **27** files, by substring:

| Substring | Hits | | Substring | Hits |
|---|---|---|---|---|
| `centre` | 17 | | `cancelled` | 5 |
| `colour` | 13 | | `labelled` | 4 |
| `behaviour` | 7 | | `licence` | 3 |
| `memois` | 5 | | `travelled` | 2 |
| `honour` | 5 | | `normalis` | 1 |

Six sample citations, each re-read and quoted:

- `core/ItemSetup.lua:10` — `-- colour fallback, was this addon's alone.`
- `modules/AuctionPrice.lua:58` — `-- Rebuilt per kept loot line rather than memoised, deliberately: LOOTHISTORY-R-10, dispositioned in`
- `docs/ARCHITECTURE.md:114` — `… \`always\` / \`inCombat\` / \`outOfCombat\` / \`never\`. Honoured by \`Browser:VisibilityAllows\` …`
- `docs/smoke-tests.md:874` — `  **chevron**, gray, vertically centred.`
- `DEPENDENCIES.md:110` — `  (\`libs/LibKa0s/media/\`), whose provenance and licences are that library's to carry.`
- `tests/test_panel.lua:831` — `test("Panel: the reorder controller is cancelled at the TOP of the page render", function()`

**Nothing here is a shipped player-facing string.** Stripping comments before the scan leaves exactly
four hits, and all four are test names or assertion messages:

```
$ for f in $(non-md files in scope); do awk '{ line=$0; sub(/--.*/,"",line); ... }' "$f"; done
tests/test_itemsetup.lua:96:       assertEqual(quality, 4, "the colour fallback still answers for an uncached item")
tests/test_panel.lua:610:   assertEqual(moved, 0, "a page reset must not recentre the window as a side effect")
tests/test_panel.lua:831: test("Panel: the reorder controller is cancelled at the TOP of the page render", function()
tests/test_panel.lua:840:   assertTrue(list.dead == true, "the previous render's controller must have been cancelled")
```

That is why the grade is **Low**: no `NS.L` key, no chat line and no label is affected, so nothing a
player reads changes spelling. `docs/test-cases.md:723` — `- Panel: the reorder controller is cancelled at the TOP of the page render` —
is the generated mirror of `tests/test_panel.lua:831` and regenerates with it.

**How much of this is new.** Of the ten substrings hit, eight (`centre`, `colour`, `behaviour`,
`cancelled`, `labelled`, `travelled`, `licence`, `normalis`) also appear in `localization-§5`'s
pre-v2.39.0 prose Use/Never table, covering **52** of the 62 hits; `memois` and `honour` — the
remaining **10** hits — are reachable only from the newly published list. What changed materially is
that §5 now publishes a list a script can run, which is why a sweep exists at all where three prior
audits read the table and filed nothing.

## 9. TOC load-bearing positions — LH-56, LH-57, LH-58

The denominator was established by **reading the seam files and `core/Constants.lua`**, not by counting
TOC lines. Sweep for file-scope resolutions:

```
$ for f in core/*.lua defaults/*.lua modules/*.lua settings/*.lua; do
    awk '/^local [A-Za-z_, ]+ *= *NS\./ {print FILENAME":"NR": "$0}' "$f"; done
```

plus the two table-constructor cases the sweep cannot see (`lib:New({…})` at file scope). Four
load-bearing positions in the `# Core` and `# Settings` blocks; **two annotated, two not.**

**Annotated (compliant):**

- `LootHistory.toc:37-39` → `core\ItemSetup.lua`. Names what resolves: `NS.Item`'s `QualityLabel`,
  called by `core/Constants.lua` at file load.
- `LootHistory.toc:41-42` → `core\MediaSetup.lua`. `core/Constants.lua:64` —
  `C.FONT_MONO = NS.MediaFont and NS.MediaFont(C.FONT_MONO_NAME) or _G.STANDARD_TEXT_FONT` — is the
  resolution named.
- `LootHistory.toc:71-74` → `settings\OptionsSetup.lua`, and `settings/Schema.lua:68` —
  `local MASTER_ROWS, MASTER_AFTER_GROUP = O.MasterControls{` — is the file-load call it protects.
  Also stated in-file at `settings/OptionsSetup.lua:40`.

**Unannotated (LH-56):** `LootHistory.toc:48` — `core\CoreSetup.lua` — a bare path, nothing at the line.
The resolution it protects is `core/CoreSetup.lua:180` — `local printer = lib:New({ prefix = NS.PREFIX })`
— reading `core/Namespace.lua:10` — `NS.PREFIX = "|cff00ffff[LH]|r"`. TOC `:45` is `core\Namespace.lua`,
so the sequence is dependency-correct. The constraint is written **inside** the file at
`core/CoreSetup.lua:29` — `--   AFTER  core/Namespace.lua   — NS.PREFIX is the tag, passed verbatim as a plain string.`
— which is not where §5 requires it.

**Unannotated (LH-57):** `LootHistory.toc:51` — `core\DebugLogSetup.lua` — a bare path. The resolution
is `core/DebugLogSetup.lua:90` — `  font  = NS.Constants.FONT_MONO,` — inside the `lib:New({…})`
constructor evaluated at file load, reading `core/Constants.lua:64`. TOC `:44` is `core\Constants.lua`.
Written in-file at `core/DebugLogSetup.lua:17` —
`--   AFTER  core/Constants.lua  — \`font\` is read at :New time (NS.Constants.FONT_MONO).`

**The SHOULD (LH-58):** `LootHistory.toc:34-35` is the model for a conventional annotation —
`# The LibKa0s-Env seam. After Compat, whose map, zone and TOC-metadata shims it took over;` … *"nothing
here resolves at load, so the position is conventional rather than load-bearing."* Four groups carry no
such statement: `LootHistory.toc:15` (`# Libraries (vendored in libs/ — load first)`), `:29`
(`# Locales`), `:57` (`# Defaults`), `:70` (`# Settings`).

`layout-§1`'s within-`core/` sequence itself is **not** filed: dependency-correct order with its
load-bearing positions declared is compliant whatever the sequence.

## 10. Shared subsystems — descriptors, stubs and the close-button grep

Compliance is cited at the **descriptor and the stub**, never at the library's source.

- `core/DebugLogSetup.lua:25` — `local lib = LibStub and LibStub("LibKa0s-DebugLog-1.0", true)`
- `core/DebugLogSetup.lua:88` — `  addonName = addonName,` — the field `debug-logging-§13` MUSTs, so
  the console's own copy/clear/close draw this collection's marks.
- `settings/OptionsSetup.lua:47` — `local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)`
- `core/MediaSetup.lua:55` — `local addonName, NS = ...` and `:149` —
  `if Media then Media.RegisterLSM(addonName) end` — one `RegisterLSM` call, fed the file's **own** first
  vararg rather than a frame prefix or a hand-typed constant.

**Stub coverage, measured per setup file.** The members the addon reaches on the DebugLog instance:

```
$ grep -rhno 'DebugLog[.:][A-Za-z_]*' --include='*.lua' core modules settings defaults locales \
    | sed 's/.*DebugLog[.:]//' | sort -u
Debug  Hide  IsShown  SetEnabled  Show  Toggle
```

All six are answered on the library-absent path: `Show`, `Hide`, `IsShown`, `Toggle` and `SetEnabled`
in the stub table at `core/DebugLogSetup.lua:32-71`, and `Debug` separately at `:72`
(`  NS.Debug = function() end`) — `NS.DebugLog.Debug` is only ever read on the library path, at `:144`.
Nothing is missing.

The **Options** stub (`settings/OptionsSetup.lua:55-145`) is the documented exception: load-completing
rather than member-answering, publishing real-enough load-time members and no-opping the rest, with the
reasoning written at `:50-53` and `:74-80`. Flagging it would be a false positive and it is not filed.
The `Core`, `Item`, `Pool`, `Env`, `Widgets` and `Media` seams each guard on their own library handle
and answer nil-safely on every published member.

**The close-button grep, run as written:**

```
$ grep -rn 'MakeCloseButton(' --include='*.lua' . | grep -v '/libs/' | grep -v '/tests/'
core/CoreSetup.lua:168:  return lib.MakeCloseButton(parent, onClick, addonName)
modules/Browser.lua:88:function B:MakeCloseButton(parent, onClick)
modules/Browser.lua:90:  return NS.MakeCloseButton(parent, onClick)
modules/Browser.lua:994:  local close = B:MakeCloseButton(titleBar, function() B:Hide() end)
modules/Export.lua:465:    NS.Browser:MakeCloseButton(tbar, function() frame:Hide() end)
```

Every line is one of the four sanctioned shapes: the **one** wrapper definition
(`core/CoreSetup.lua:167` — `NS.MakeCloseButton = function(parent, onClick)` — and `:168`, which supplies
the third argument), its degraded twin (`core/CoreSetup.lua:138` —
`  NS.MakeCloseButton = fallbackCloseButton`), the module delegator, and two calls to it. **No direct
`lib.MakeCloseButton(...)` outside the seam, no `Core.MakeCloseButton(...)`, and no
`NS.DebugLog.MakeCloseButton(...)` in a perf-panel decoration hook** — the last is impossible here, since
the perf panel is not wired. `standalone-windows`'s reasoned-decline route is not in play: the addon
**uses** the wrapper, so the four conditions do not need evaluating. Anti-pattern #65 clear.

**Shared media, both halves:**

```
$ find media -type d
media  media/logos  media/screenshots
$ ls libs/LibKa0s/media/
fonts  icons  textures
```

No private copy of anything the payload ships (anti-pattern #63 clear). One-off marks:
`settings/Panel.lua:510` — `local TICK_ON  = NS.IconMarkup("circle-check", READY, 16,` — and `:512` —
`local TICK_OFF = NS.IconMarkup("ban", NOTREADY, 16,` — and `:745` —
`      itex:SetTexture((NS.Icon and NS.Icon("info")) or INFO_ICON)`. All three go through the catalog
with the Blizzard path demoted to the fallback rung, which is `LH-53` closed. The remaining
`Interface\` paths in addon source are `WHITE8X8` (a solid chip the catalog has no entry for), the
class-icon sheet, the LDB minimap icon, the addon's own logo, and `modules/Browser.lua:1052-1053`'s
size grabber — a **recorded** decision, and compliant.

## 11. Settings panel content — the nine `options-ui` checks

- **(a) tab strip.** `settings/Panel.lua:887-894` declares six tabs; `:889` — `  { key = "Master controls" },`.
  `renderGeneral` draws the strip unconditionally through `O.TabStrip` (`:940`) with no count-based
  fallback and no early return. The landing page (`P.BuildMain`, `:970`) and the absent Profiles page are
  the two exempt surfaces.
- **(b) first tab, and the migration.** The literal matches `libs/LibKa0s/OptionsCompose.lua:50`'s
  `MASTER_GROUP = "Master controls"`, and the rows are the library's composer's, not a hand-written copy:
  `settings/Schema.lua:68` — `local MASTER_ROWS, MASTER_AFTER_GROUP = O.MasterControls{`. The frame-only
  rows are all present because the `SetMovable` sweep finds two movable frames (stated at
  `settings/Schema.lua:60-62`). **The migration question is answered in the negative and proven:**
  `defaults/Global.lua:26` — `-- General visibility is a DROPDOWN, not a boolean, because a boolean can only ever answer two`
  — continuing *"This addon never shipped a `show only in combat` checkbox, so the key is NEW rather than
  migrated."* Confirmed: `grep -rn 'showOnlyInCombat\|onlyInCombat' core modules settings defaults tests`
  returns nothing, so no `schemaVersion` bump and no migration step are owed.
- **(c)/(d) color rows.** `grep -n 'widget *= *"color"\|type *= *"color"\|classColorSource\|disabledIf' settings/*.lua`
  returns nothing — no color rows exist, so neither rule has a subject.
- **(e) ordering.** `grep -rn 'ScrollUp-Up\|ScrollDown-Up' --include='*.lua' settings/` returns nothing.
  The AH cascade is dragged through the shared `ReorderList`, and `settings/Panel.lua:468-469` records
  that the host draws no row background and no border, so there is no double chrome.
- **(f) media groups.** `grep -rn 'LSM30_Font\|LSM30_Border\|LSM30_Statusbar' core modules settings`
  returns nothing — no hand-written font/border/bar group and no broadcast meta row.
- **(g) chrome.** One block, no banner, no page-header, reasoned at `settings/Panel.lua:912-914`. No
  page-wide control is declared inside a `group`; the Defaults button is the library's page-wide one
  (`:1023`, `defaultsButton = true`) and `P:RestoreDefaults` (`:993`) covers the whole page. No `InlineGroup` or backdropped
  `SimpleGroup` wraps a chrome band (anti-pattern #72 clear).
- **(h) wrapped strip.** `libs/LibKa0s/OptionsWidgets.lua:441-455` measures the pitch from
  `TAB_ATLAS[false][1]` — the **unselected** art — and caches it on success only (`:451-453`, `measuredArtH = h` at `:452`). The suite
  case is real, not green-against-nothing: `tests/test_panel.lua:938-940` asserts the harness answers a
  **different** height for the selected art before anything else, `:945-949` forces a real wrap by
  narrowing the chrome to 200px, and `:979` pins the pitch to the unselected height. It names the
  mutation it dies under at `:933-936`.
- **(i) secondary strip.** `settings/Panel.lua:409` — `  local _, height = O.SubTabStrip(ctx, host.frame, {`
  — drawn as ordinary scroll content on a layout-suppressed `SimpleGroup` (`:399-406`), selection kept
  per primary tab in `ctx.activeSubTab[FILTERS_TAB]` (`:390-396`) and never persisted (`:382-384`). No
  third level: no strip inside a secondary tab, and `subgroup` is used only for real headings.

## 12. Documentation shape — measured against `documentation-§3`'s list

**Tier 1, all six present:** `docs/{scope,module-map,schema,settings-panel,data-flow,common-tasks}.md`.

**Tier 2, all seven answered**, triggers evaluated against the code:

| Doc | Trigger, measured | Answer |
|---|---|---|
| `slash-dispatch.md` | 14 verbs in `NS.COMMANDS` (`settings/Schema.lua:430-462`); threshold 8 | Present |
| `midnight-quirks.md` | bind-state / currency-API workarounds | Present |
| `compat-layer.md` | **24** shims (`grep -c '^function Compat\.' core/Compat.lua` → 24); v2.39.0's new threshold is 3 | Present |
| `message-bus.md` | 3 distinct messages, below the >10 threshold | Present anyway, with the reason in the map |
| `profiles.md` | no `db.profile` write; the sole `GetCurrentProfile` hit is a read for the init summary (`core/Database.lua:176`) | *Not applicable* — true |
| `debug.md` | the console is `LibKa0s-DebugLog-1.0`'s; no debug surface of the addon's own | *Not applicable* — true |
| `perf-analysis/README.md` | no harness wired, under the ratified `performance-§12` decline | *Not applicable* — true |

No *Not applicable* row asserts something false.

**`## Documentation map`** — `docs/ARCHITECTURE.md:331` — four tables in order, the fourth at `:360`
(`### Verification and record`) carrying exactly the six mandated rows and **not** `perf-analysis/README.md`,
which registers under `### Conditional` as v2.39.0 requires. Every `.md` under `docs/` appears exactly
once; frozen directories are named once each at `:333-334`; no row points at a missing file.
`ARCHITECTURE.md`'s own row is present and is filed neither way (a MAY).

**No non-canonical Tier 1/2 filename and no retired doc:**

```
$ for f in docs/complexity.md docs/file-index.md docs/conventions.md docs/pending/LEDGER.md; do ...
absent  docs/complexity.md
absent  docs/file-index.md
absent  docs/conventions.md
absent  docs/pending/LEDGER.md
absent  docs/perf-runs/
absent  docs/pending/
```

**Retired `§N.M` notation sweep.** **Scope:** every tracked `.md`, `.lua` and `.toc` **excluding** `libs/`
and the five frozen/generated directories (`docs/audits/`, `docs/reviews/`, `docs/revendor/`,
`docs/superpowers/`, `docs/automated-tests/<run>/`) — **87 files**, and the live `docs/` pages **are**
in it:

```
$ git ls-files '*.md' '*.lua' '*.toc' | grep -v '^libs/' | grep -v '^docs/audits/' \
    | grep -v '^docs/reviews/' | grep -v '^docs/revendor/' | grep -v '^docs/superpowers/' \
    | grep -vE '^docs/automated-tests/[0-9]' | xargs grep -noE '§[0-9]+\.[0-9]+' | wc -l
0
```

Zero. (The frozen bundles still hold the old notation, which is correct — they are the record.)

**Hub shape.** `wc -l docs/ARCHITECTURE.md` → **458**. Section spans, from
`grep -n '^## ' docs/ARCHITECTURE.md`: Overview 28, Module map 45, Data model 11, Settings schema 58,
Message bus 31, Slash commands 24, Event subscriptions 23, Menus 34, Taint notes 13, Standards
compliance 55, Documentation map 46, Documented deviations 55, Known limitations 27. **Every one is
inside the ~60 MUST**, so nothing is being used as storage; the file is over the ~400 SHOULD.
That is **LH-60**, Info.

## 13. The register, read before anything was filed

`docs/ARCHITECTURE.md:377` — `## Documented deviations` — five rows plus two retirement paragraphs.

Triggers, each evaluated against the tree:

- `architecture-§5` / `options-ui-§1` — both wait on a library widget maker.
  `libs/LibKa0s/OptionsWidgets.lua:1820` — `  function O.RenderGrid(ctx, items)` — still takes no
  `parent`, and no multi-check/set/list maker is published at v1.27.0. **Not fired.**
- `performance-§12` — `grep -rn 'SetScript("OnUpdate"' core modules settings` → nothing;
  `C_Timer.NewTicker` → nothing; 13 `RegisterEvent` sites and 5 one-shot `C_Timer.After` call sites (7
  grep hits, two of them presence guards at `core/LootHistory.lua:55` and `core/Util.lua:240`). These
  agree with `docs/performance.md:53` — `**Game events: thirteen registrations, thirteen rows.** …` — and
  `:73` — `**\`C_Timer\` calls: five, every one of them one-shot. No \`C_Timer.NewTicker\` anywhere.**`
  These two counts were `LOOTHISTORY-R-05`/`R-06` and are now correct. **Not fired.**
- `options-ui-§12` — awaits a maintainer ruling. **Not fired.**
- `localization-§1` — `ls locales/` → `enUS.lua` only. **Not fired.**

Evidence ids resolved: #14, #20, #21, #22, #25, #26 all exist in this repo's issue store (listed in §7's
`gh` output and the fuller listing behind it). `LH-47`, `LH-48`, `LH-54` resolve to
`docs/audits/2026-09-07/02_DEVIATIONS.md`.

The two retirement paragraphs, both re-read:

- `docs/ARCHITECTURE.md:398` — `\`sessionOnly\` row kind as an \`architecture-§5\` deviation, with the trigger *"the standard names a` …
  and `:400` — `\`options-ui-§15\` makes the debug console *"a session-only row (debug-logging)"* a mandated row on` —
  the retirement `LH-54` asked for, citing the rules that closed it.
- `docs/ARCHITECTURE.md:419` — `row because a row cites a \`filename-§N\` and there is none to cite: \`options-ui\` never names` —
  issue #21's decline recorded in the register, with the question `LH-47` posed answered against the code
  (`settings/Panel.lua:1027` — `    O.SetRenderer(ctx, renderGeneral)`).

**Inverse check — a decline with no register home.** Six `state:will-not-do` issues exist: #18, #19,
#20, #21, #22, #29. #20 and #22 carry rows; #19 is retired in the paragraph at
`docs/ARCHITECTURE.md:410`; #21 is recorded at `:419-427`; #29 declines *withdrawing* the
`performance-§12` exemption, which already has its row; #18 declines a **feature** (a serialized v2
export format), not a rule, so it owes no row. **No unrecorded ratified decline.**

## 14. Refactor shapes since the last audit

`git log --since=2026-09-07` shows 21 commits. Checked against `performance-§11` and the named
anti-patterns:

- **#52** (a body dumped into one unrecognisable helper) — none; the two refactors that moved code
  (`M4-22`, `M4c-06`) named what they did in the commit and in the file.
- **#43** (a dispatch or defaults table built inside a function) — none found.
- **#54** (`t.k = stored.k or D.k` over fields whose stored `false`/`""`/empty set is a user choice) —
  `grep -rn '= *\(rec\|stored\|g\|s\)\.[A-Za-z_]* *or *[A-Z]\?[A-Za-z_]*\.' core modules settings`
  returns nothing.
- **testing-§13** (an untested function refactored with no characterization test) — `M4c-06` added
  `tests/test_lintconfig.lua` (278 lines) and `M4-17` added the TOC-version pin, so both refactors
  landed with new pinning cases rather than without.
- **#76 / `library-stack-§9`** (an AceGUI re-registration living in an addon's `core/`) — no
  `core/LSMPatch.lua`, and `grep -rn 'RegisterWidgetType\|AceGUIWidgetLSMlists' core modules settings`
  returns nothing. The addon has nothing to move.
