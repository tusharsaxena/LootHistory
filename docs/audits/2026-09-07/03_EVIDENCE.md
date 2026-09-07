# 03 — Evidence

Every `file:line` below was re-read at the moment this file was written and the cited text is quoted
beside it. Every count is the output of a recorded command whose **scope** is stated. Nothing here is
carried forward from an earlier bundle.

Machine: WSL2 / Ubuntu. Repo at `/mnt/d/Profile/Users/Tushar/Documents/GIT/LootHistory`, head
`6d3c2de`. Sibling library repo present at `/mnt/d/Profile/Users/Tushar/Documents/GIT/LibKa0s`.

---

## 1. Mechanical checks

### 1.1 Lint

```
$ luacheck .
Total: 0 warnings / 0 errors in 28 files
```

Scope: the whole repo minus `.luacheckrc:4`'s `exclude_files = { "libs/", "docs/audits/",
"docs/reviews/", "_dev/", "tests/" }`. So the 28 are the shipped source under `core/ defaults/
locales/ modules/ settings/`; the vendored library and the entire test tree are **not** linted.

### 1.2 Headless suite

```
$ lua tests/run.lua
699 passed, 0 failed, 0 skipped, 699 total
```

`0 skipped` is a measured figure: the two vendored-payload gate cases found the sibling checkout and
actually compared. It matches `docs/test-cases.md`'s footer table row `| **Total** | **699** |` and
the README badge `Tests-699%2F699_passing` (`README.md:7`).

### 1.3 Complexity — the standard's invocation, verbatim

```
$ lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .
No thresholds exceeded (cyclomatic_complexity > 15 or length > 1000 …)
Total nloc  Avg.NLOC  AvgCCN  Avg.token  Fun Cnt  Warning cnt
    13222       6.4     2.2       52.6      1761            0
```

Compared against the latest committed bundle, `docs/automated-tests/20260825-103428/complexity.txt`,
whose footer reads `12116 / 6.4 / 2.2 / 52.6 / 1639 / 0`, and whose `manifest.json` records
`"run": "20260825-103428"`, `"addonVersion": "1.2.0"`, `"release": null`, `"maxCcn": 15`,
`"bandFiles": 3`, `"overCapFiles": 0`.

**Drift since that run:** no function crossed a `lizard` threshold — warnings stay at **0** and the
maximum stays at **15**. NLOC rose 12116 → 13222 (+1106) and functions 1639 → 1761 (+122), which is
growth rather than densification: the averages are identical to the digit. The band membership
**did** change:

```
$ wc -l modules/Browser.lua modules/Analytics.lua modules/BrowserTable.lua settings/Panel.lua
1281 modules/Browser.lua
1178 modules/Analytics.lua
1173 modules/BrowserTable.lua
1004 settings/Panel.lua
```

`settings/Panel.lua` at **1004 LOC** has newly entered `layout-§1`'s 1000–1500 on-notice band, and
the bundle's band table lists only three files. Nothing is over the 1500 cap. The bundle's stamp
dates it **13 days** stale, and the working tree has moved 55 test cases and 1106 NLOC since. This
is **LH-49**.

Six functions sit exactly on CCN 15 without crossing, unchanged in membership from the recorded run —
`Compat.ScanBound` (`core/Compat.lua:219`), `Attribution:OnLootOpened`, `BrowserTable:BindRow`,
`BrowserTable:GroupRecords`, `BrowserTable:UpdateHeaderArrows`, and the block `lizard` attributes to
`E@39-159` in `modules/Export.lua`. All six are dense **defaulting/guarding**, not tangled control
flow: `lizard` scores every `and`/`or` short-circuit as a decision, so a run of
`t.k = rec.k or D.k` lines reads high with no branching behind it.

### 1.4 Vendored Ka0s-owned library — both diffs, against the tag the repo names

The tag comes from the provenance line, not from the sibling's `HEAD`:

```
$ grep -n 'Bundles \[LibKa0s\]' CLAUDE.md
51:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.25.0 (MIT) — the Ka0s-owned shared

$ grep -n 'Bundles \[LibKa0s\]' README.md
(no output)
```

```
$ git -C ../LibKa0s archive v1.25.0 | tar -x -C /tmp/lk
$ diff -r /tmp/lk/LibKa0s   ./libs/LibKa0s      # exit 0, no output
$ diff -r /tmp/lk/testkit   ./tests/_kit        # exit 0, no output
```

**Both empty.** No anti-pattern #45 drift, no #48 partial vendoring — the whole ship folder is
present, and the harness is under `tests/_kit/`, never `libs/`. The TOC lists the aggregate once:

```
LootHistory.toc:27:libs\LibKa0s\LibKa0s.xml
```

### 1.5 The three README/`CLAUDE.md` greps

```
$ grep -nE '^## (Libraries|Bundled libraries|Libraries and credits|Credits and libraries|Credits and bundled libraries)' README.md
(no output)

$ grep -n 'WoW_Addon_Standard' README.md
6:![Standard](https://img.shields.io/badge/Ka0s-WoW_Addon_Standard-yellow)
```

The badge is the **bare** `![Standard](…)` form, not wrapped in a link. No library roll-call in the
intro prose either — `README.md:12-14` is player-facing description only.

### 1.6 Close-button wrapper

```
$ grep -rn 'MakeCloseButton(' --include='*.lua' . | grep -v '/libs/' | grep -v '/tests/'
core/CoreSetup.lua:168:  return lib.MakeCloseButton(parent, onClick, addonName)
modules/Browser.lua:88:function B:MakeCloseButton(parent, onClick)
modules/Browser.lua:90:  return NS.MakeCloseButton(parent, onClick)
modules/Export.lua:465:    NS.Browser:MakeCloseButton(tbar, function() frame:Hide() end)
```

`core/CoreSetup.lua:168` is the **one** wrapper and it supplies `addonName`. `modules/Browser.lua:90`
is a call to it; `modules/Browser.lua:994` (`local close = B:MakeCloseButton(titleBar, function()
B:Hide() end)`) and `modules/Export.lua:465` are calls to that. No direct `lib.MakeCloseButton`, no
`Core.MakeCloseButton`, no `NS.DebugLog.MakeCloseButton`. **Compliant.**

### 1.7 Line endings

```
$ test -f .gitattributes && echo present
present
$ grep -n '^\* text=auto eol=\(crlf\|lf\)$' .gitattributes
26:* text=auto eol=crlf
$ grep -n '^\*\.sh text eol=lf$' .gitattributes
34:*.sh text eol=lf
$ grep -c ' binary$' .gitattributes
20
```

(a) present, (b) the pin matches the repo's kind — it ships a `.toc`, so client-bound and CRLF,
(c) the mandatory `*.sh` carve-out is there, (d) 20 binary lines. The body is the canonical
client-bound file, not a `*.sh`-only near-miss: `.gitattributes:15-25` carries the full
CLIENT-BOUND rationale block above the pin.

(e), the one that fails — run exactly as `AUDIT.md` writes it:

```
$ git ls-files -z | xargs -0 -I{} sh -c '
    set -- $(git check-attr text eol -- "{}" | sed "s/.*: //")
    [ "$1" = unset ] && exit
    cr=$(tr -dc "\r" < "{}" | wc -c); lf=$(tr -dc "\n" < "{}" | wc -c)
    case "$2" in crlf) [ "$lf" -gt 0 ] && [ "$cr" -ne "$lf" ] && echo "{}";;
                 lf)   [ "$cr" -gt 0 ] && echo "{}";; esac' 2>/dev/null | wc -l
9
```

**Nine tracked files disagree with the declared pin** — **LH-46**. Scope: every path
`git ls-files` reports, binaries skipped by the `text=unset` guard; **two** of the nine sit inside
the frozen `docs/revendor/2026-08-25/` bundle, which is never edited, and the remaining seven are
live source and config. The files are deliberately not enumerated: `git add --renormalize .` fixes
all nine in one action. This number is **far lower** than a pre-v2.28.1 bundle would have reported
for this repo, because the old command counted every binary and every JSON as a stray; earlier frozen
bundles are not edited to reconcile.

### 1.8 Packaging

```
$ for e in .luacheckrc .gitignore .gitattributes .claude .superpowers docs tests _dev; do
    grep -q "^  - $e\b" .pkgmeta || echo "NOT IGNORED — $e"; done
NOT IGNORED — .gitattributes
NOT IGNORED — .claude
NOT IGNORED — .superpowers

$ for e in .[!.]*; do [ -e "$e" ] || continue;
    grep -q "^  - $e\b" .pkgmeta || echo "UNACCOUNTED — $e"; done
UNACCOUNTED — .git
UNACCOUNTED — .gitattributes
UNACCOUNTED — .pkgmeta
UNACCOUNTED — .pytest_cache
UNACCOUNTED — .superpowers
```

`.git` needs no row. `.claude/` does not exist here, so its absence from the list is only a template
gap. The real list is **LH-45**: `.gitattributes` and `.pkgmeta` are **tracked** and therefore ship
into the packaged AddOn today; `.superpowers/` (3.6 MB, self-ignored, `git ls-files .superpowers` →
`0`) and `.pytest_cache/` are untracked and so do not ship from a clone, but both owe a row or a
comment because the enumeration is what goes stale.

`.pkgmeta:1` is `package-as: LootHistory`, there is no `externals:` block, and `.pkgmeta:3-4`
records the vendoring choice — both compliant.

### 1.9 The retired-notation sweep

```
$ grep -rnE '§[0-9]+\.[0-9]+' core defaults locales modules settings LootHistory.toc \
    README.md CLAUDE.md DEPENDENCIES.md docs/*.md \
    docs/automated-tests/README.md docs/automated-tests/RESULTS.md .luacheckrc .pkgmeta
(no output; exit 1)
$ grep -rnE '§[0-9]+\.[0-9]+' tests/*.lua
(no output; exit 1)
```

Scope stated explicitly: **all** live source directories, the TOC, all three root docs, **all sixteen
live `docs/*.md` pages**, the two generated `docs/automated-tests/` pages, both config files and the
addon's own test suites. **Excluded** and deliberately not counted: `libs/` (not this repo's to fix),
`tests/_kit/` (vendored), the frozen `docs/audits/`, `docs/reviews/`, `docs/revendor/` and
`docs/automated-tests/<run>/` bundles, `docs/superpowers/specs/**` (those design docs' own internal
section numbers, never standard citations) and `.superpowers/`. **Zero hits — LH-19 is closed.**

### 1.10 The register and the issue store

`docs/ARCHITECTURE.md:377` is `## Documented deviations`, and the table below it uses the mandated
`| Rule | What differs | Why | Decided | Re-check trigger |` shape.

```
$ gh issue list --state all --limit 200 --json number,title,state,labels
```

27 issues. Every one carries a `state:` label (`state:done` ×13, `state:will-not-do` ×5,
`state:triaged` ×4 open, plus `enhancement`) and a `severity:` label. No `[status]` title prefix
survives (anti-pattern #62 clear). No `docs/pending/` directory exists.

**The inverse check** — a decline recorded only as an issue:

```
$ gh issue view 21 --json body --jq .body
### Why this will not be done
`SetRenderer` is **declined on the AH Price page alone** …
### Provenance
Migrated from `docs/pending/LEDGER.md` row `LIBKA0S-15` … decided 2026-08-01. This issue is
**closed by design**: it records a settled refusal …
```

Issue #21 is `state:will-not-do` and there is **no matching register row**: the five rows cite
`architecture-§5` ×2, `performance-§12`, `options-ui-§12` and `options-ui-§1`, and
`docs/ARCHITECTURE.md:276-323`'s `## Standards compliance` prose does not cover it either. That is
**LH-47**. Issue #18 (`Add a serialized v2 export format`) is a feature decline, not a rule decline,
and owes no row.

**A row whose cited rule has since changed** — `docs/ARCHITECTURE.md:392`:

> `| architecture-§5 | The schema carries a **sessionOnly row kind** … | … | 2026-07-17 | The
> standard names a session-only row kind (then this is compliant, not a deviation), or the toggle
> becomes persistent. |`

The standard now names it, twice:

- `options-ui.md:320` (in **§15**, *The Master controls tab*): *"**Debug console belongs here**, as a
  session-only row (debug-logging), not as a bespoke checkbox bolted onto some other section."*
- `options-ui.md:240` (in **§12**, *Global reset*): *"What the walk **MUST** keep is exactly what a
  profile reset cannot reach: **session-only rows**, whose storage is their own `set()` rather than
  the db (preview mode, a debug console toggle, a test mode)."*

The trigger has fired. That is **LH-54**.

---

## 2. Documentation shape — measured, not read

### 2.1 Tier 1 — all six present under exactly the canonical names

`docs/scope.md`, `docs/module-map.md`, `docs/schema.md`, `docs/settings-panel.md`,
`docs/data-flow.md`, `docs/common-tasks.md`. **No MUST failure.**

### 2.2 Tier 2 — each of the seven answered, and every trigger evaluated against the code

| Doc | Trigger evaluated against the code | State |
|---|---|---|
| `slash-dispatch.md` | `settings/Schema.lua:431-461` declares **14** verbs — ≥ 8 | Present |
| `midnight-quirks.md` | `core/Compat.lua` carries bind-state and currency workarounds | Present |
| `compat-layer.md` | `core/Compat.lua` is 416 lines of addon-specific shimming | Present |
| `message-bus.md` | 3 distinct messages — **below** the >10 trigger; shipped anyway, with the reason in the map row | Present (over-delivery, not a finding) |
| `profiles.md` | no profile control in the options UI; nothing reads `db.profile` | *Not applicable* row, and the code agrees |
| `debug.md` | no debug surface beyond `LibKa0s-DebugLog-1.0` (`core/DebugLogSetup.lua:76`) | *Not applicable* row, and the code agrees |
| `perf-analysis/README.md` | harness not wired (no `core/PerfSetup.lua`), ratified `performance-§12` exemption | *Not applicable* row — **required** to be absent under the exemption |

No row asserts something false. **No MUST failure.**

### 2.3 `## Documentation map` — both directions

`docs/ARCHITECTURE.md:331`. Sixteen `.md` files exist directly under `docs/`; the map's four tables
name exactly those sixteen, once each, and every named file exists. Frozen/generated directories are
named once each at `:333-334` (`docs/audits/`, `docs/reviews/`, `docs/automated-tests/`,
`docs/revendor/`, `docs/superpowers/`) and never enumerated per run. No orphan, no dangling row.

### 2.4 Non-canonical filenames and retired docs

No `data-model.md`, `saved-variables.md`, `pipeline.md`, `capture-pipeline.md`,
`override-pipeline.md`, `settings-system.md`, `wow-quirks.md`, `slash-commands.md` or
`debug-console.md`. No `file-index.md`, no `conventions.md`, no `docs/complexity.md`, no
`docs/perf-runs/`, no `docs/pending/LEDGER.md`, no `TODO.md`. `docs/browser.md` is genuine Tier 3
(the standalone History window) and is registered in the map. **Nothing to file.**

### 2.5 Hub shape

`wc -l docs/ARCHITECTURE.md` → **434**. Thirteen `##` sections; the longest mandated one is
*Settings schema* (`:93-151`, 58 lines), and *Module map* (`:37-82`, 45), *Message bus* (`:151-182`,
31) and *Slash commands* (`:182-206`, 24) are all well under the ~60-line spill line, each leaving a
summary plus one link to its topic doc. The file is marginally over the ~400-line SHOULD with every
section already spilled — the shape `AUDIT.md` says to report and not to file.

---

## 3. Settings-panel content — nine checks, from the schema

**(a) Every page draws a tab strip.** One non-exempt page, `General`. Its distinct `group` values in
declaration order come from `settings/Schema.lua:313-315` splicing `MASTER_ROWS` ahead of `ROWS`:
**Master controls → Capture → AH Price → Interface → History** (`GENERAL_TABS`, rendered at
`settings/Panel.lua:903` through `O.TabStrip`). The landing page (`P.BuildMain`,
`settings/Panel.lua:933`) is the host's own `buildMain` and is mandated in that shape; there is no
AceConfig Profiles sub-page. `renderGeneral` has no untabbed fallback and no early return that skips
the strip — the stale-pointer branch at `:895-898` heals to `GENERAL_TABS[1]` rather than bailing.
**Compliant.**

**(b) First tab is exactly `Master controls`, with the canonical rows.** `settings/Schema.lua:68`
is `local MASTER_ROWS, MASTER_AFTER_GROUP = O.MasterControls{`, so the block is **composed** by the
library, not hand-written, and `settings/Schema.lua:310-315` splices it at the head with the comment
*"its group has to be the page's FIRST — the strip's order IS this array's order"*.
`S.MASTER_GROUP = O.MASTER_GROUP or "Master controls"` (`settings/Schema.lua:168`). The defaults
handed in (`:73-83`) are `enabled`, `visibility`, `scale`, `alpha`, `locked`, `debugConsole`, plus
`onResetPosition` (`:87`) and `onResetAll` (`:94`) — every canonical row the addon has state for.
The frame-only rows are owed, and the sweep proves it rather than assuming it:

```
$ grep -rn 'SetMovable(true)' --include='*.lua' core modules settings
modules/Browser.lua:944:  frame:SetMovable(true)
modules/Export.lua:439:  frame:EnableMouse(true); frame:SetMovable(true); frame:SetClampedToScreen(true)
```

**The migration question.** `General visibility` is the four-value dropdown, and the stored key is
**new**, not a changed type — `defaults/Global.lua:23-27`:

> *"General visibility is a DROPDOWN, not a boolean, because a boolean can only ever answer two of
> the four. This addon never shipped a `show only in combat` checkbox, so the key is NEW rather than
> migrated: an install from before this release simply has no `visibility` and AceDB merges "always"
> in."*

So no `schemaVersion` bump and no migration step are owed. `defaults/Global.lua:10` holds
`schemaVersion = 1` and `core/Database.lua:125`'s `function NS:RunMigrations()` is the live runner.
**Compliant — nothing filed.**

**(c) / (d) Color rows.**

```
$ grep -rn 'ColorPicker\|widget *= *"Color\|classColorSource' settings/ modules/ core/
(no output)
$ grep -rn 'disabledIf' settings/
(no output)
```

The addon declares no color row, so `options-ui-§17` does not apply. **Not a deviation.**

**(e) Ordering is a drag.**

```
$ grep -rn 'ScrollUp-Up\|ScrollDown-Up' --include='*.lua' settings/ | grep -v '/libs/'
(no output)
```

The AH cascade uses the shared widget: `settings/Panel.lua:574` `local list = NS.MakeReorderList{`,
wired through `core/WidgetsSetup.lua:145`. `settings/Panel.lua:450-455` records the adoption and the
split — *"The host draws NO row background and NO row border. The library owns both now, and a host
copy beside them is double chrome."* No `MoveUp`/`MoveDown` handler, no numeric position field.
**Compliant.**

**(f) Font / border / bar groups.**

```
$ grep -rn 'LSM30_' --include='*.lua' settings/ core/ modules/
(no output)
```

The addon ships none of the three shared-media groups, so there is nothing to compose and nothing to
order. Subgroup headings are used where a tab mixes control types — `settings/Schema.lua:228`
(`subgroup = "Pricing"`), `:240` (`"Price sources"`), `:267`/`:280` (`"Window"`), `:287`
(`"Minimap"`) — and `settings/Panel.lua:922-925` renders active tabs with `noHeadings = true` while
leaving `subgroup` intact. No hand-rolled colored `Label` standing in for a `Heading`.

**(g) One chrome block, not boxed twice.** `settings/Panel.lua:875-877`:

> *"No banner (options-ui-§14): this addon is account-wide — every path resolves against db.global
> and there is no profile, no per-window state and nothing for a banner to be a picker FOR. It draws
> no page-header block either: nothing on this page applies to every tab."*

Verified against the schema: no page-wide control is declared inside a `group`. The page's only
page-wide acts are the host's Defaults button (`settings/Panel.lua:986`, `defaultsButton = true`) and
the composed Master-controls button pair, both of which the library places. No `InlineGroup` or
backdropped `SimpleGroup` wraps a chrome band, because there is no band. **Compliant.**

**(h) A wrapped strip's geometry.** `LootHistory` has one page of five tabs, so no page wraps today.
The pitch is the library's, read through the vendored `libs/LibKa0s/Options*.lua` which
§1.4's `diff -r` proves byte-identical to v1.25.0 — that measurement is audited in the library's own
repo, not here. Nothing addon-side to file.

**(i) A secondary strip, and no third level.** `settings/Panel.lua:399` draws the Filters tab's three
id-lists through `O.SubTabStrip(ctx, host.frame, {...})` into a layout-suppressed `SimpleGroup` added
as an ordinary scroll child (`:392-395`), i.e. inside the scroll, not pinned into chrome. The
selection is per primary tab and session-only: `settings/Panel.lua:380` `ctx.activeSubTab =
ctx.activeSubTab or {}`, keyed by `FILTERS_TAB` (`:356`), never written to `db.global` — no
`activeSubTab` appears anywhere in `defaults/Global.lua` or in the schema array. Stale pointers heal
at `:386`. No strip is nested inside a secondary tab and no `subgroup` fakes one. **Compliant.**

---

## 4. Degradation stubs — every member the addon reaches

**Options.** Members reached across `settings/`:

```
$ grep -rhno 'O\.[A-Za-z_]*' --include='*.lua' settings/ | sed 's/.*O\.//' | sort -u
AddSpacer BUTTON_PAIR_REL ClearScroll CreateOptionsPanel CreatePanel EnsureScroll MASTER_GROUP
MasterControls OpenOptionsPanel RefreshPanel RefreshScalars RegisterOptionsPage RenderField
RenderRows RenderTabbedSchema SECTION_HEADING_H Section SetRenderer SubTabStrip TabStrip
```

All twenty are answered by the stub at `settings/OptionsSetup.lua:49-130`. The stub is deliberately
**load-completing rather than member-answering**, and says so at `:50-53` — that is the one
documented exception and is **not** flagged. `MasterControls = function() return {}, noop end`
(`:109`) returns **two** values, matching the live composer's arity.

**DebugLog.** Members reached: `Debug`, `Hide`, `IsShown`, `SetEnabled`, `Show`, `Toggle`. The stub
(`core/DebugLogSetup.lua:32-71`) answers all six plus the buffer surface, and closes with
`NS.Debug = function() end` (`:72`) then `return` (`:73`) — so the live-path republish at `:144`
(`NS.Debug = NS.DebugLog.Debug`) is unreachable on the degraded path and `NS.Debug` is never nil.
The descriptor carries `addonName = addonName` (`:88`) as `debug-logging-§13` requires, with the
`name`/`addonName` split explained at `:82-86`. **No gap.**

---

## 5. Shared media

```
$ find media -type f
media/logos/loothistory.logo.{256.jpg,jpg,png,tga}
media/screenshots/loothistory-screenshot-0{1..9}.png
```

No private `fonts/`, `icons/` or `textures/` beside `libs/LibKa0s/media/` — what remains is exactly
the logo and the screenshots (anti-pattern #63 clear). The seam is fed the addon's own first vararg:
`core/MediaSetup.lua:1` `local addonName, NS = ...` with one `RegisterLSM` call, loaded at
`LootHistory.toc:43` above `core/Constants.lua`, whose `FONT_MONO` resolves at file load.

**One-off marks.** Every art site in `modules/` routes through `NS.Icon` / `NS.IconMarkup` with a
Blizzard path as the **degraded fallback** (`modules/BrowserTable.lua:80, 105, 107, 114, 259-260,
1043-1044, 1154`; `core/WidgetsSetup.lua:98-99, 149`). Two exceptions, graded differently:

- `modules/Browser.lua:1052-1053` uses `Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up/-Highlight`,
  and `:1048-1051` records **why**: *"This briefly drew the catalog's `resize` mark instead … one
  addon's window corner looking unlike every other window corner in the collection is drift."*
  A SHOULD with the reason written down is a decision. **Not filed.**
- `settings/Panel.lua:459-461`:
  ```
  459: local READY     = "Interface\\RaidFrame\\ReadyCheck-Ready"      -- green tick: collecting
  460: local NOTREADY  = "Interface\\RaidFrame\\ReadyCheck-NotReady"   -- red mark: off / not installed
  461: local INFO_ICON = "Interface\\FriendsFrame\\InformationIcon"
  ```
  No `NS.Icon` and no reason. `libs/LibKa0s/Media.lua:92`'s `ICONS` catalog carries
  `circle-check`, `cancel` and `info`. This is **LH-53**.

The perf-panel decoration hook does not exist here (no harness), so there is nothing to simplify.

---

## 6. The watch list as a decision record

`docs/automated-tests/RESULTS.md` — dispositions counted by hand off the two tables:

- Warned-function table: one row, `— | — | — | **None.** No function exceeds CCN 15.` Confirmed by
  today's `lizard` run (§1.3) and by `"warnings": 0` in the latest manifest. Nothing accepted.
- Band table: three rows. `modules/Browser.lua` — *"Accepted, own disposition — `LH-37`"*;
  `modules/BrowserTable.lua` — *"Accepted."*; `modules/Analytics.lua` — *"Peel next"*.

Two `Accepted`, which is not "every entry accepted", and the list reads in one pass. §4's shelf life
counts **release** runs:

```
$ git log --oneline -- docs/automated-tests/RESULTS.md | wc -l
```
— seven recorded runs, **`"release": null` in every manifest**, so the three-release clock has not
started and neither `Accepted` row has aged out. The row that has is the third:
`RESULTS.md:100-105` and `:143` both say `modules/Analytics.lua` has read *"peel next"* since
`20260804-233322` with nothing moving and **nothing tracking it**. That is **LH-52** — filed on the
substance, with the letter's non-applicability stated rather than glossed.

**Complexity refactors since the last audit** were checked for the forbidden shapes and none was
found: `settings/Panel.lua:470`'s `ACOL` and `settings/Panel.lua:358-368`'s `FILTER_TABS` are
**module-level** tables, not per-call allocations (#43 clear); the helpers carry descriptive names
(`rowsOfGroup`, `buildFiltersTab`, `refreshAuctionTable`, `makeFilterSection` — #52 clear); the
refactored paths are covered by `tests/test_panel.lua` (41 cases) and `tests/test_schema.lua` (47);
and no `t.k = stored.k or D.k` was introduced over a field whose stored `false` is a user choice —
`settings/Schema.lua:363-375`'s `S:Set` writes through `deepcopy` and `S:Get` (`:380`) reads the
stored path rather than defaulting with `or` (#54 clear).

---

## 7. Compliance claims that are not deviations, each sourced

- **Layout / TOC.** `layout-§1` modular tree; `toc-file-§5` load-bearing positions annotated with
  what resolves — `LootHistory.toc:37-39`, `:41-42`, `:71-74` — and conventional positions marked as
  conventional at `:34-35`. `X-Curse-Project-ID: 1607560` (`:13`) is a real published id, not a
  placeholder.
- **Namespace.** `local addonName, NS = ...` opens every source file; no `_G[addonName]`; the only
  two declared globals are justified at `.luacheckrc:43-44`.
- **Events / taint.** 13 `RegisterEvent` sites; **zero** `SetScript("OnUpdate")`; seven one-shot
  `C_Timer.After`; both movable frames non-secure and on `UISpecialFrames`
  (`modules/Browser.lua:1086`, `modules/Export.lua:500`); one `InCombatLockdown` read at
  `modules/Browser.lua:1134`.
- **SavedVariables.** One global (`LootHistory.toc:7`); `schemaVersion = 1`
  (`defaults/Global.lua:10`); runner at `core/Database.lua:125` stamping only applied steps.
- **`architecture-§5` single write seam.** `settings/Schema.lua:363` `function S:Set(path, value)`,
  validate → `deepcopy` → `WritePath` → `onChange`, with `sessionOnly` short-circuited; boot
  validation at `:401` `function S:Register()` is live, and `:391-400` records why its formerly dead
  `row.default == nil` conjunct was removed.
- **`localization-§3` MUSTs.** `NS.L` exported at `locales/enUS.lua:5`
  (`NS.L = setmetatable(NS.L or {}, { __index = function(_, k) return k end })`); `enUS.lua` ships and
  carries **no** dead keys. Only the routing SHOULD's terminal state is unrecorded — **LH-48**, whose
  evidence is `locales/enUS.lua:7-9` (*"v1.0.0 ships English-only … an accepted scope decision, not an
  oversight"*) with no corresponding register row in `docs/ARCHITECTURE.md:377-396`.
- **`preview-mode`.** `/lh test` exists (`settings/Schema.lua:450`) and toggles a synthetic dataset;
  the addon draws no persistent positionable display, so the section is N/A either way.
- **`public-api`.** Nothing is exposed; no `_G[addonName]` publish. N/A.
- **`documentation-§1` README.** Badges at `README.md:3-7` in canonical order with the bare standard
  badge at `:6`; logo at `:9`; `## What's new in 1.2.0` (`:42`) immediately above `## Screenshots`
  (`:49`) and agreeing with the top `## Version History` row (`:196`); `## Issues and feature
  requests` (`:188`); no `## Credits`; no angle-bracket placeholder; no `%20`. The two extra headings
  at `:36` and `:141` are **LH-51**.
- **`documentation-§2` CLAUDE.md.** 65 lines, all six items in order: title `:1`, adherence `:3-4`,
  `## Standards compliance (read first)` `:6-26` closing with *"When in doubt, treat conformance as a
  hard requirement and ask."*, the docs pointer list `:28-47`, provenance `:51`, green gate `:62-65`.
