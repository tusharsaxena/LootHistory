# 01 — Current state

**Addon:** Ka0s Loot History (`LootHistory`), `## Version: 1.4.0`, `## Interface: 120100`.
**Audited against:** Ka0s WoW Addon Standard **v2.76.1 (2026-10-07)**. `AUDIT.md`, `standards/STANDARDS.md`,
all 27 section files linked from its Sections list, and `standards/ADDONS.md` were fetched verbatim with
`curl -fsSL` from `raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master` (remote `master` =
`f47238929230c0059409e1b0a8d69cea99123bd9` per `git ls-remote`). The fetched `AUDIT.md` and the fetched section
files are byte-identical to the sibling `../WowAddonStandards` working tree (`diff -q`, `diff -rq`; the only
differences are four unlinked files and `_raw/` present locally).
**Tree audited:** `b9c1271a737393349ee660fafe635cfdd40ee3fa` on branch `feat/2026-10-07-review-audit-remediation`.
The tree was clean at the start of the run; during it `git status --short` began showing an untracked
`docs/reviews/2026-10-07/`, written concurrently by a separate review pass. It is not part of the audited tree and
nothing in this bundle counts it. Read-only: this folder is the only write.
**Run date:** 2026-10-07. Prefix **`LH-`** (reused). The highest ID issued before this run is `LH-77`
(`docs/audits/2026-09-23/`), so new rows start at **LH-78**.

**Tooling.** Every `luacheck`, `lua tests/run.lua` and complexity run went through
`~/.claude/dev-copilot/bin/ka0s-bounded`. Lua 5.1.5, Luacheck 1.2.0, lizard 1.24.0.

## Repository kind

**Addon.** `dev-copilot-profile` reported `profile=wow`, `kind=addon` (reason `toc:## Interface`). The repo has a
`.toc` and is row "Ka0s Loot History" of `ADDONS.md`'s in-scope addons table, with launcher menu entries
`Enabled · Locked · Test mode · Show window (the History browser)`. The detector and the table agree. The whole addon
rule set applies.

## Snapshot, section by section

### layout
- Modular skeleton: `core/` (18 files), `defaults/` (2), `locales/enUS.lua`, `modules/` (24), `settings/` (5),
  `media/logos/` + `media/screenshots/`, `libs/`, `tests/`, `docs/`. No `tools/`. The only tracked `.py`/`.sh` is the
  vendored `tests/_kit/run-automated-tests.sh` (not authored here, not a generator).
- Authored Lua census (`git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)'`, `tests/` included): **116 files,
  44,858 lines, 0 over the 1500 cap, 10 in the 1000–1500 band** (largest `modules/BrowserTable.lua` 1476,
  `modules/Browser.lua` 1416). No generated-data exemption is declared.
- Census heading `### Files over the 1500-line cap` sits under `## Documented deviations`
  (`docs/ARCHITECTURE.md:425`) and reads "Nothing is over the cap today" — true, but its "largest file … 1296 lines"
  figure is stale (LH-73). Gate wired by path: `tests/run.lua:119`.
- `media/` holds only the addon's logos and screenshots; no private copy of a library asset.
- Logo `media/logos/loothistory.logo.128.tga`: TGA type **2**, **128×128**, **32** bpp (header read with `od`).

### toc-file
- Field order matches `toc-file-§1`; `## IconTexture` names the addon's own 128 file; `X-Curse-Project-ID: 1607560`.
- `## SavedVariables: LootHistoryDB, LootHistoryPerfDB` — two globals, correct now that the perf harness is wired
  (the `performance-§12` exemption was retired 2026-10-06).
- Header order Libraries → Locales → Core → Defaults → Modules → Settings; `libs\LibKa0s\LibKa0s.xml` listed once.
- **Load-bearing positions, established by reading the seams and the module files rather than the comments.** Every
  `core/` and `defaults/` position and `settings\OptionsSetup.lua` / `settings\Slash.lua` are annotated (the
  2026-09-23 rows LH-56/57/63 are closed). **Four positions are load-bearing and unannotated:** `modules\Escrow.lua`
  (file-load `R.SCAN_STEPS[...]` on `NS.Reconciler`), `modules\AnalyticsCharts.lua` (file-load
  `Analytics._charts = …` with no `NS.Analytics or {}` guard), `modules\Timeline.lua` (file-load `TM.TOTAL` on
  `NS.TimelineModel`) and `settings\Panel.lua` (file-load `NS.Schema.MASTER_GROUP`). LH-78…LH-81. The `# Modules`
  block carries no conventional marker and its header "(Attribution before Collector)" names an order with no reason
  (LH-58).

### library-stack
- Vendored: LibStub, CallbackHandler, AceAddon/AceEvent/AceTimer/AceConsole/AceDB/AceGUI/AceConfig/AceDBOptions,
  LibSharedMedia, LibDataBroker, LibDBIcon, LibKa0s (whole folder). No `externals:`.
- **Provenance:** root `CLAUDE.md:56` — `Bundles [LibKa0s](…) v1.70.0 (MIT)`; none in `README.md`. v1.70.0 is ≥ every
  floor this run checks (Lifecycle v1.42.0, launcher v1.58.0, diagnostics v1.64.0, library lines v1.65.0, Options
  `addonName` v1.67.0, sighted kit v1.66.0/revision 35).
- **`diff -r` against the v1.70.0 tag** (`git archive v1.70.0 LibKa0s testkit`, commit `162a7fd`): payload **empty**,
  kit **empty**. No #45, no #48. Kit `Kit.VERSION = 37`.
- Majors wired, one seam each: Core, Env, Compat (`core/Compat.lua`), Lifecycle, Perf (**new**, `core/PerfSetup.lua`),
  Bus (`core/Constants.lua`), Pool, Item, Media, Widgets, DebugLog, Launcher (no stub, written decision), Options,
  Schema, Slash. No hand-rolled console, widget kit, dispatcher or harness.

### architecture
- Bootstrap, AceAddon registration and printer reclaim unchanged. Bus: five `Ka0s_LootHistory_*` messages, PascalCase,
  no literal at a call site (the grep returns nothing). Receivers own private targets.
- **File-load cross-module coupling** in three modules and one settings file (LH-82): `modules/Escrow.lua:26`,
  `:160-161` append to `NS.Reconciler`'s step tables at load; `modules/AnalyticsCharts.lua:2` reads `NS.Analytics`
  without the idempotent guard and writes into it at `:226`; `modules/Timeline.lua:26` reads `TM.TOTAL` at load.
- **Write paths (architecture-§5).** The ledger stores (`holdings`, `daily`, `ledgerSince`, `resetPrompt*`,
  `rollupSeeded`) are named in `docs/schema.md` *The ledger stores*; the `holdings` writer list says
  "`Reconciler:Flush` only" but two other writers exist (LH-86).

### settings / options-ui
- One `General` page drawn through the library's `O.TabStrip` with tabs Master controls, Capture, AH Price,
  Interface, History, Filters (`settings/Panel.lua:986-993`); plus the AceDBOptions `Profiles` sub-page and the landing
  page. First tab is `Master controls`. No color rows, no shared-media rows, no arrow-reorder art, no host
  `OpenToCategory`/`HideUIPanel`. Options descriptor passes `addonName` (`settings/OptionsSetup.lua:178`, v2.75.0 MUST).

### slash-commands
- `NS.COMMANDS` (`settings/Schema.lua:1043`): 20 verbs. `enable`/`disable` alias `CliSet("settings.enabled …")`.
  `diagnostics` row plus `debug diagnostics` tested first (`:1095`). `LIVE_WHILE_DISABLED` is the library's thirteen
  plus `profile`; feature verbs refuse with the library's `DisabledLine()`.
- **The disabled state (slash-commands-§7) — measured compliant.** Registration census: every registration routes
  through `NS.SafeRegister*` or a module's private target; `NS.StandDown` (`core/LifecycleSetup.lua:116-139`) disables
  Collector, Reconciler, Attribution (+`DisableOut`), Browser, Analytics, HoldingsTab, Timeline and Rollup, drops the
  ledger-reset offer target and cancels every `NS.After` deferral. Hooks are `hooksecurefunc`/`HookScript` funnels gated
  on the latch. The latch is `LibKa0s-Lifecycle-1.0` with two holds (`disabled`, `perf`); `core/PerfSetup.lua` hands it
  to Perf. `tests/test_disabled.lua` is wired (`tests/run.lua:87`) and carries `-- red under:` comments.

### launcher
- One object via `LibKa0s-Launcher-1.0` (`core/LauncherSetup.lua`), `label = NS.BRAND` ("Ka0s Loot History"),
  `isEnabled/setEnabled`, `isLocked/toggleLock`, `isTestMode/toggleTestMode`, `isWindowShown/toggleWindow` — matching
  `ADDONS.md`'s column; `onTooltipShow` adds only a record count; `debug` and `debugAtEnable` passed. Compliant.

### debug-logging
- DebugLog descriptor passes `addonName`; gates `DebugOnce`/`DebugChanged`/`DebugForget`/`DebugAtEnable` bound and
  stubbed (`core/DebugLogSetup.lua:79-94`). Slash, Options, Launcher, Lifecycle descriptors each pass `debug`.
  No host `SetEnabled` around `RunDiagnostics`; no `diag`/`dump` alias. README `## Reporting a bug` verbatim, bullets.

### events-frames-taint
- `events-frames-taint-§1`: the Core `SafeRegister*` family plus `NS.RejectedEvents`, surfaced by `/lh debug events`
  (`settings/Schema.lua:1096-1098`). LH-64 closed. The player spell frame is the sanctioned unit-event carve-out.
- `events-frames-taint-§2`: the Browser's visibility now takes the edge from the handler
  (`modules/Browser.lua:1387-1394`) — LH-65 closed.

### performance
- **Harness wired** (2026-10-06): `core/PerfSetup.lua` builds `NS.Perf` with five buckets and a stub covering every
  member the addon calls (`on`, `Note`, `OnCommand`); `perf` verb registered; `tests/perf.lua` carries a zero-overhead
  scenario; `.luacheckrc` carries `debugprofilestop` and `LootHistoryPerfDB`. One in-game capture,
  `docs/perf-analysis/20261007-104651/` with `report.md`, one-line `dump.json` and `ANALYSIS.md`, indexed in
  `docs/perf-analysis/README.md`. No surface-parity case for the Perf stub (LH-68).

### tests / lint / automated-tests
- `lua tests/run.lua`: **1476 passed, 0 failed, 1 skipped, 1477 total.** `luacheck .`: **0/0 in 116 files**;
  `exclude_files` narrows to `tests/_kit/` plus `libs/` and frozen bundles; no top-level `ignore`.
- `docs/test-cases.md` regenerated to scratch with `--list`: identical to the committed file. README badge
  `Tests-1476%2F1476` excludes the skip, per `testing-§5`.
- Kit 37: `test_lizard_sighted`, `test_layout_cap`, `test_eol`, `test_vendor_sync`, `test_diagnostics_contract` wired.
- **Complexity (sighted runner, `--no-bundle`):** 4431 functions, avg CCN 2.5, **max 24, 26 functions above CCN 15**,
  parity clean (0 blind files). Newest bundle `20260927-030334` measured `8e60c1f`, **171 commits behind HEAD**, was
  recorded on a pre-35 kit (no `blindFiles` in its manifest) and reads 0 warnings / max 15 / 2519 functions (LH-87).

### packaging
- `.pkgmeta` ignores every named dev entry; check (b) prints only `.git`; check (c) prints nothing. Compliant.

### line-endings (`.gitattributes`)
- Present; pin `* text=auto eol=crlf` (`.gitattributes:26`); `*.sh`/`*.py text eol=lf` (`:36-37`); 20 `binary` lines.
  First 84 lines **byte-identical** to `line-endings-§5`'s client-bound body; no tail. Working-tree check (e):
  **0 of 675** tracked files disagree with the pin. `tests/_kit/test_eol.lua` wired. Compliant.

### Root docs
- README: H1, five badges in order (standard badge bare), description, Screenshots, Usage, How attribution works, FAQ,
  Troubleshooting (with the reporting row), Reporting a bug, Issues and feature requests, Version History, Credits
  (external credit only). No logo, no library inventory, no numbered list. Usage closes on two sentences (LH-71); the
  1.4.0 history row carries a contributor-facing, un-prefixed line (LH-83).
- `CLAUDE.md`: stub, sections in mandated order (LH-72 closed), provenance line present.
- `DEPENDENCIES.md`: present; its verification block quotes raw `lizard` (LH-84).

### docs/ (documentation-§3 tier model)
- Tier 1: all six present under canonical names. Tier 2: `slash-dispatch.md` (20 verbs), `midnight-quirks.md`,
  `compat-layer.md` (57 shims by the standard's grep), `message-bus.md`, `profiles.md` (Profiles page ships),
  `debug.md`, `perf-analysis/README.md` (harness wired) — all present. Verification-and-record table holds exactly the six.
  Tier 3: `browser.md`, `combat-path-sweep.md`, `disabled-state.md`. All 23 live `.md` files appear in exactly one table.
- Frozen stores named out of scope: audits, reviews, automated-tests, revendor, superpowers — **not**
  `docs/perf-analysis/<run>/`, whose two `.md` files are neither registered nor named (LH-85).
- No `file-index.md`, `conventions.md`, `complexity.md`, `perf-runs/`, `pending/`, `agent-context.md`, `TODO.md`.
- Hub `docs/ARCHITECTURE.md`: **478 lines**; `## Module map` runs **77** lines with ten links; `## Event subscriptions`
  runs 62 (LH-60).
- Re-vendor store: 23 bundles, all with `01_DELTA.md` and `05_SUMMARY.md`; **52 tags vendored since the 2026-08-25
  horizon, 52 recorded, 0 unrecorded** (LH-62 closed).

### Register and issue store
- `## Documented deviations` read first: four rows (`architecture-§5` auction priority, `options-ui-§1` inverted set
  pickers, `localization-§1` English only, `localization-§4` deconstruct names). Every trigger evaluated, none fired;
  every evidence id resolves; no cited rule has changed. Ten retirement notes below the table.
- `gh issue list --state all`: 34 issues, every one carries a `state:` label; #34 (open, `state:untriaged`) has no
  `severity:` label — the ordinary stray, not a finding. No `[status]` prefix. Every `state:will-not-do` issue is a
  register row, a retirement note or a declined feature (#18).

## Against the prior run (`docs/audits/2026-09-23/`)

| Prior ID | Status |
|---|---|
| LH-52 | **Closed** — #32 done; `modules/Analytics.lua` peeled to 674 lines across four files. |
| LH-56, LH-57, LH-63 | **Closed** — the three TOC lines are annotated (`LootHistory.toc:56`, `:72`, `:127`). |
| LH-58 | **Carried, narrowed** to the `# Modules` group; re-parented under LH-78. |
| LH-60 | **Carried** — Settings schema now spilled (22 lines); Module map is the oversize section; hub 554 → 478. |
| LH-62 | **Closed** — 0 unrecorded tags. |
| LH-64, LH-65, LH-66, LH-67, LH-72 | **Closed.** |
| LH-68 | **Carried, narrowed** — Env, Item, Media, Pool, Lifecycle now covered; Perf (newly adopted) is not. |
| LH-69, LH-70 | **Closed by change of state** — the `performance-§12` exemption was retired and the harness wired. |
| LH-71 | **Carried, narrowed** — six sentences down to two. |
| LH-73 | **Carried** with a new set of drifted figures. |
| LH-74 | **Closed → recorded deviation** (register row 2026-09-24). |
| LH-75 | **Closed** — defaults `schemaVersion = 0`, `NS.SCHEMA_VERSION` from the runner (the rule itself changed). |
| LH-76 | **Closed** — the grip is `Core.MakeResizable`'s (#33); the register row was retired. |
| LH-77 | **Carried** (Info). |
