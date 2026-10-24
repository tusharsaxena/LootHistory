# 01 — Current State

**Addon:** Ka0s Loot History (`LootHistory`), version `1.2.0` (`LootHistory.toc:5`, `core/Namespace.lua:5`).
**Repo HEAD:** `289b280e0191454a53ed80d94143a22172de0a53` — *Merge branch 'feat/2026-09-07-audit-review-remediation'*, on `master`, working tree clean.
**Audited against:** **Ka0s WoW Addon Standard v2.39.0 (2026-09-07)**, resolved from
`WowAddonStandards` master at commit `7e609f580943be51201f1bde190b2cd1f1433bd1`
(*Merge branch 'feat/2026-09-07-audit-review-remediation'*, 2026-09-08 21:11 +0530).

**How the standard was resolved.** `git clone --depth 1 https://github.com/tusharsaxena/WowAddonStandards`,
then `head -1 standards/STANDARDS.md` → `# Ka0s WoW Addon Standard (v2.39.0, 2026-09-07)`. `AUDIT.md`,
`standards/STANDARDS.md`, all **26** section files linked from the Sections list, and `standards/ADDONS.md`
were read from that checkout. A stale `curl`-fetched copy from a previous session was diffed against the
clone and found to differ in **twelve** section files (`anti-patterns`, `audit-review-history`,
`automated-tests`, `documentation`, `line-endings`, `lint`, `localization`, `open-evolutions`,
`options-ui`, `packaging`, `slash-commands`, `standalone-windows`); the stale copy was deleted and every
rule below is measured against the clone.

**Rule set used:** the **addon** rule set. The repo ships `LootHistory.toc`, so step 1's library-repo
switch (`library-stack-§7`'s applicability list) does not apply.

**Prefix:** `LH-`, reused. New findings this run start at **LH-55**; `LH-01…LH-54` are spent across the
five prior audit runs and four review bundles.

---

## Layout (`layout`)

The single modular layout, exactly: `core/ defaults/ locales/ modules/ settings/ media/ libs/ tests/ docs/`.
Folder load order in the TOC is `libs/ → locales/ → core/ → defaults/ → modules/ → settings/`
(`LootHistory.toc:15-78`).

`media/` holds only `logos/` and `screenshots/` — no `fonts/`, `icons/` or `textures/`, so nothing
duplicates the shared payload under `libs/LibKa0s/media/{fonts,icons,textures}` (`layout-§3`,
`library-stack-§8`).

**`layout-§1`'s 1500-line cap over every authored `.lua` the repository tracks** (v2.39.0 states the
scope explicitly, `tests/` included, vendored code carved out): **zero files over cap.** Four in the
1000–1500 on-notice band — `modules/Browser.lua` (1289), `modules/Analytics.lua` (1178),
`modules/BrowserTable.lua` (1173), `settings/Panel.lua` (1041). Largest test file
`tests/test_panel.lua` (998). On-notice is the compliant state.

## TOC (`toc-file`)

Thirteen metadata fields including `## X-License: MIT` (`:11`), `## X-Standard:` pointing at the
standards repo (`:12`) and `## X-Curse-Project-ID: 1607560` (`:13`) — published, so the id is real
rather than a placeholder. Single Retail TOC, no flavor fan-out.

`# Libraries` lists `libs\LibKa0s\LibKa0s.xml` **once**, after Ace3 (`:27`) — never individual module
`.lua` files (`toc-file-§4/§5`).

`# Core` carries position annotations at `:34-35` (EnvSetup, marked **conventional**), `:37-39`
(ItemSetup, load-bearing), `:41-42` (MediaSetup, load-bearing), `:49` (WidgetsSetup), `:52`
(PoolSetup), and `# Settings` at `:71-74` (OptionsSetup, load-bearing). Measured against
`toc-file-§5`'s **own denominator** — the positions that actually resolve something at file scope,
established by reading the seam files and `core/Constants.lua` — the denominator is **four**, and
**two of the four are unannotated**: `core\CoreSetup.lua` (`:48`) and `core\DebugLogSetup.lua`
(`:51`). See **LH-56** / **LH-57**.

## Libraries (`library-stack`)

Twelve vendored libs, all committed, no `externals:`. Ace3 stack plus LibStub, CallbackHandler-1.0,
LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0 and `LibKa0s`.

`library-stack-§3`'s reachability test, all three ways present: a direct `LibStub` call (nine seam
files), an **Ace3 mixin name string** AceAddon resolves on the addon's behalf —
`AceAddon:NewAddon(NS, addonName, "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")`
(`core/LootHistory.lua:4`) — and a vendored lib reaching another (CallbackHandler-1.0, named by no
addon file). Under v2.39.0's *mandatory when used* wording all twelve are correctly vendored.

**Shared subsystems are consumed, not hand-rolled.** There is no `modules/DebugLog.lua`, no widget-maker
file, no dispatcher and no test framework of the addon's own. What the addon owns is a descriptor plus a
degradation stub per module, in nine setup files:

| Module | Lookup | Descriptor / stub |
|---|---|---|
| `LibKa0s-Core-1.0` | `core/CoreSetup.lua:39` | stub at `:85-142`; `NS.MakeCloseButton` wrapper at `:167-168`, degraded twin at `:138` |
| `LibKa0s-DebugLog-1.0` | `core/DebugLogSetup.lua:25` | stub at `:32-73`; descriptor at `:78-138`, carrying `addonName = addonName` (`:88`, debug-logging-§13) |
| `LibKa0s-Options-1.0` | `settings/OptionsSetup.lua:47` | the documented **load-completing** stub at `:49-147` |
| `LibKa0s-Slash-1.0` | `settings/Slash.lua:136` | descriptor over `NS.COMMANDS` |
| `LibKa0s-Env-1.0` | `core/EnvSetup.lua:41` | guarded seam |
| `LibKa0s-Item-1.0` | `core/ItemSetup.lua:27` | `NS.Item = Item or { … }` (`:41`) |
| `LibKa0s-Media-1.0` | `core/MediaSetup.lua:57` | `NS.Icon` / `NS.MediaFont` / `NS.IconMarkup` answer nil-safely; `Media.RegisterLSM(addonName)` once (`:149`) fed the file's own first vararg (`:55`) |
| `LibKa0s-Pool-1.0` | `core/PoolSetup.lua:22` | `NS.Pool = Pool or { … }` (`:24`) |
| `LibKa0s-Widgets-1.0` | `core/WidgetsSetup.lua:85` | every seam guards on `W` |

**No perf harness is wired** — that is a **ratified `performance-§12` decline**, register row Decided
2026-08-05, issue #22. Confirmed against the tree today: zero `SetScript("OnUpdate"` sites, no
`C_Timer.NewTicker`, thirteen event registrations and five one-shot timers.

**Provenance and vendoring.** `CLAUDE.md:51` — `Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.27.0 (MIT)`.
`README.md` carries no such line and no bundled-library inventory of any kind. Both `diff -r` checks
against the sibling repo at tag `v1.27.0` are **empty** (see `03_EVIDENCE.md`).

## Settings panel (`options-ui`)

One canvas sub-page, **General**, registered at `settings/Panel.lua:1023-1029` through
`O.RegisterOptionsPage` and driven by `O.SetRenderer(ctx, renderGeneral)` (`:1027`). The landing page is
the host's own `buildMain` (options-ui-§5) and is exempt from the strip; there is no Profiles sub-page,
because the addon is account-wide by design.

**Tab strip:** six tabs, `Master controls` first under that exact literal (`settings/Panel.lua:889`),
then `Capture`, `AH Price`, `Interface`, `History`, `Filters` (`:887-894`). The Master controls block is
**composed** through the library — `O.MasterControls{…}` at `settings/Schema.lua:68-101` — and spliced at
the head of `S.Schema` so the strip's order is the array's order (`:310-315`).

**`options-ui-§15`'s migration question, asked and answered.** `settings.visibility` is a four-value
dropdown whose default is `"always"` (`defaults/Global.lua:30`). The addon **never shipped a
*show only in combat* boolean at that path** — stated at `defaults/Global.lua:26-29` — so the key is new
rather than migrated and AceDB merges the default in. No `schemaVersion` bump and no migration step are
owed. Verified: `grep -rn 'showOnlyInCombat\|onlyInCombat'` over `core modules settings defaults tests`
returns nothing.

**The other seven §13–§18 checks:** no color rows at all, so §17's companion rule and §17's `disabledIf`
ban have no subject; no `ScrollUp-Up`/`ScrollDown-Up` art anywhere under `settings/` — the AH cascade is
dragged through the shared `ReorderList` (`settings/Panel.lua:459-468`); no `LSM30_Font`/`LSM30_Border`/
`LSM30_Statusbar` control anywhere, so §16 has no subject; one chrome block, no banner and no
page-header, reasoned at `settings/Panel.lua:911-913`; the wrapped-strip pitch is read from the
**unselected** atlas and cached once (`libs/LibKa0s/OptionsWidgets.lua:441-455`) and is pinned by a
suite case that first asserts the harness distinguishes the two atlas heights
(`tests/test_panel.lua:920-993`); and the secondary strip is ordinary page content whose selection is
kept per primary tab in session state (`settings/Panel.lua:386-420`), with no third level.

## Slash (`slash-commands`)

`NS.COMMANDS` is a 14-verb positional table at `settings/Schema.lua:431-462`, owned by the host and
handed to `LibKa0s-Slash-1.0`. The `[LH]` cyan prefix is `NS.PREFIX` at `core/Namespace.lua:10`, and
four consumer files take `local print = NS.Print` at file scope with the `events-frames-taint-§8`
reason on the line.

## Debug (`debug-logging`)

Entirely `LibKa0s-DebugLog-1.0`'s. `NS.Debug` is republished from the library instance
(`core/DebugLogSetup.lua:144`) and reached from ~40 call sites. The stub answers **all six** members
the addon reaches on the instance (`Show`, `Hide`, `IsShown`, `Toggle`, `SetEnabled`, and `Debug` via
the separate `NS.Debug = function() end` at `:141`).

## Tests (`testing`, `automated-tests`)

`lua tests/run.lua` → **719 passed, 0 failed, 0 skipped, 719 total**. `luacheck .` → **0 warnings /
0 errors in 59 files**. `docs/test-cases.md` holds 719 rows and the README badge reads `719%2F719`
(`README.md:7`) — badge, inventory and run agree.

`.luacheckrc` matches v2.39.0's amended template: `exclude_files = { "libs/", "docs/audits/",
"docs/reviews/", "_dev/", "tests/_kit/" }` (`:12`) — the test tree **is** in scope — the harness global
sits in a `files["tests/"]` stanza (`:73-85`) and never in top-level `read_globals`, there is **no**
top-level `ignore` (`:14-26` records its removal and the 110 findings that produced), and the thirteen
surviving suppressions are per-file `212/self` stanzas with a written reason (`:87-134`). Under the
ratified `performance-§12` decline the file correctly carries **neither** `debugprofilestop` in
`read_globals` **nor** `LootHistoryPerfDB` in `globals`.

Eight run bundles under `docs/automated-tests/`, newest `20260908-181338` (cut today 18:13:38 at sha
`1ef54e1`, verdict green, `"release": null` — **no run in the record is a release run**).
`docs/automated-tests/{README.md,RESULTS.md}` both present; the vendored runner
`tests/_kit/run-automated-tests.sh` is present and executable (mode `100755` in the index). No retired
`docs/complexity.md`.

## `.gitattributes` (`line-endings`)

Present at the root, **81 lines, byte-for-byte identical to `line-endings-§5`'s client-bound canonical
body**, with nothing after it — no `§5 appendix`, and none owed. Pin recorded verbatim:
`* text=auto eol=crlf` (`:26`); `*.sh text eol=lf` (`:34`); 23 ` binary` marks.
`tests/_kit/test_eol.lua` (test-kit revision 15) is present and green, and property (e) measures
**0 tracked files** disagreeing with the pin.

## Packaging (`.pkgmeta`)

`package-as: LootHistory`, no `externals:`, no `enable-toc-creation`. The strong-form check —
every root dot-entry present in the repo named or justified — passes with **zero unaccounted entries**.
`.claude` is named in `packaging`'s weak-form template and is deliberately absent here, with the reason
written at `.pkgmeta:11-18`; see **LH-61**.

## Root docs (`documentation-§1/§2/§7`)

`README.md` (196 lines) follows the canonical order exactly: H1, the five-badge row with the **bare**
`![Standard](…)` (`:6`), logo, description, `## What's new in 1.2.0` (`:36`) immediately above
`## Screenshots` (`:43`), `## Usage` (`:63`), `## How attribution works` (`:135`), `## FAQ` (`:151`),
`## Troubleshooting` (`:168`), `## Issues and feature requests` (`:184`), `## Version History` (`:188`).
No `## Credits`, no library inventory heading, no library roll-call in the intro, no root `CHANGELOG.md`.
The three cheap step-3 greps all come back clean.

`CLAUDE.md` is a 65-line stub carrying all six mandated items in order, including the provenance line.
`DEPENDENCIES.md` is 148 lines over four numbered sections plus a *Keeping this file honest* close.

## `docs/` (`documentation-§3`)

**Tier 1 — all six present** under exactly the canonical names: `scope.md`, `module-map.md`, `schema.md`,
`settings-panel.md`, `data-flow.md`, `common-tasks.md`.

**Tier 2 — all seven accounted for**, each trigger evaluated against the code:
`slash-dispatch.md` (14 verbs, threshold 8), `midnight-quirks.md`, `compat-layer.md` (**24** shims in
`core/Compat.lua` against v2.39.0's new *three or more* trigger), `message-bus.md` (3 messages, below
the >10 threshold, shipped anyway with the reason in the register), and three honest *Not applicable*
rows — `profiles.md` (no `db.profile` write anywhere; the one hit, `core/Database.lua:176`, is a
read of `GetCurrentProfile` for the init summary), `debug.md` (the console is the library's),
`perf-analysis/README.md` (no harness, under the ratified decline).

**`## Documentation map`** at `docs/ARCHITECTURE.md:331` covers every `.md` under `docs/` in exactly one
of **four** tables in order — Required, Conditional, **`### Verification and record`** (`:360`, six rows,
exactly the mandated set), Addon-specific — with frozen directories named once each and no dangling row.
`ARCHITECTURE.md`'s own row is present; per `AUDIT.md` that is a MAY and is filed neither way.

**No non-canonical Tier 1/2 filename** (`data-model.md`, `saved-variables.md`, `pipeline.md`,
`settings-system.md`, `wow-quirks.md`, `slash-commands.md`, `debug-console.md` — none present).
**No retired doc**: no `file-index.md`, no `conventions.md`, no `complexity.md`, no `docs/perf-runs/`,
no `docs/pending/` and no `LEDGER.md`.

**Hub shape:** no mandated section exceeds ~60 lines — the largest are *Settings schema* (58),
*Standards compliance* (55) and *Documented deviations* (55) — so every section has spilled. The whole
file is **458 lines** against the ~400 SHOULD; reported as shape, not arithmetic. See **LH-60**.

## The deviation register, read first

`docs/ARCHITECTURE.md` → `## Documented deviations` (`:377`) carries **five** ratified rows plus two
retirement paragraphs. Every row's re-check trigger was evaluated against the tree in front of me and
every evidence id resolved (`audit-review-history`'s third MUST, new in v2.39.0) — details in
`02_DEVIATIONS.md`'s *Recorded deviations* table and `03_EVIDENCE.md`. **No trigger has fired.**

The issue store carries 29 issues, every one with a `state:` and a `severity:` label, and **no
surviving `[status]` title prefix**. Four titles (#23–#26) are a bare `LIBKA0S-NN:` with nothing after
the colon — a cosmetic migration artefact, not a `state:` duplicate, and not filed.
