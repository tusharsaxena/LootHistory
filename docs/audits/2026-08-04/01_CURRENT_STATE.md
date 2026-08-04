# 01 — Current State

**Addon:** Ka0s Loot History (`LootHistory`), version **1.2.0**
**Audit date:** 2026-08-04
**Audited against:** **Ka0s WoW Addon Standard v2.17.1 (2026-08-03)**
**Repo HEAD at audit time:** `17d1d55` — *"docs+i18n: adopt standard v2.17.1 — US English spelling throughout"*
**Working tree:** clean apart from the untracked `docs/reviews/2026-08-03/` bundle.

## Provenance of the standard text

The standard was resolved **from the raw GitHub URLs** and **cross-checked byte-for-byte against the
local canonical checkout** at `/mnt/d/Profile/Users/Tushar/Documents/GIT/WowAddonStandards`:

- `AUDIT.md` was fetched fresh this run via
  `curl -fsSL --max-time 15 https://raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master/AUDIT.md`
  and `diff` against `WowAddonStandards/AUDIT.md` was **empty**.
- `standards/STANDARDS.md` and **all 24 section files** named in its Sections map were compared
  against `WowAddonStandards/standards/STANDARDS.md` and `WowAddonStandards/standards/standards/*.md`;
  every `diff` was **empty**.
- Three section files (`anti-patterns.md`, `performance.md`, `testing.md`) were **re-fetched fresh
  from the raw URL** as a spot probe and were byte-identical to both the cached copies and the
  checkout.
- The checkout was verified read-only first: `git status --porcelain` empty, `git log -1` =
  `2141229 v2.17.1 — finish the v2.17.0 rollout…`.

No rule in this bundle was reconstructed from memory. **No section was left unassessed.**

The 24 sections read in full: `layout`, `toc-file`, `library-stack`, `architecture`,
`savedvariables`, `options-ui`, `standalone-windows`, `preview-mode`, `slash-commands`,
`localization`, `events-frames-taint`, `public-api`, `compat`, `debug-logging`, `packaging`, `lint`,
`testing`, `performance`, `documentation`, `audit-review-history`, `versioning-git`,
`naming-cheatsheet`, `anti-patterns`, `open-evolutions`.

---

## Snapshot, section by section

### layout

Modular layout is present and correct: `core/`, `defaults/`, `locales/`, `settings/`, `modules/`,
`media/`, `libs/`, `tests/`, `docs/`. No loose source at the repo root. Folder casing is lowercase,
Lua files are PascalCase (`core/Database.lua`, `modules/BrowserTable.lua`).

`defaults/` holds **only** `defaults/Global.lua` (`defaults/Global.lua:1-44`) — the addon is
account-wide by design (`CLAUDE.md:64`, `docs/saved-variables.md`), so there is no profile tree;
`layout-§1` sanctions `Global.lua` for that case.

File sizes: largest are `modules/Browser.lua` (1314), `modules/Analytics.lua` (1180),
`modules/BrowserTable.lua` (1040). All within the 1500 LOC cap; three sit in the 1000–1500
"on notice" band. No file exceeds the cap.

`media/` uses typed subfolders only: `media/logos/` (runtime `.tga` + source `.jpg`, plus a
third-party `wowhead-logo.png`) and `media/fonts/` (JetBrains Mono + `OFL.txt`) and
`media/screenshots/`. Nothing loose in `media/`.

### toc-file

`LootHistory.toc:1-13` carries the metadata block in the mandated field order (Interface, Title,
Notes, Author, Version, IconTexture, SavedVariables, OptionalDeps, DefaultState, Category-enUS,
X-License, X-Standard, X-Curse-Project-ID), with no blank lines inside it. Single Interface line
`120007`. `X-License: MIT`, `X-Standard:` present, `X-Curse-Project-ID: 1607560` present.
`X-Wago-ID` / `X-WoWI-ID` correctly omitted (the addon is not listed there).

The `#`-sectioned file listing (`LootHistory.toc:15-60`) is in the toc-file-§5 order
**Libraries → Locales → Core → Defaults → Modules → Settings**. Libraries are listed directly, one
entry per library, ending in the single aggregate `libs\LibKa0s\LibKa0s.xml` after Ace3
(`LootHistory.toc:27`). No addon-authored `embeds.xml`.

**SavedVariables declares only `LootHistoryDB`** (`LootHistory.toc:7`) — see deviations.

> **Note on a standard-internal contradiction carried over from the 2026-07-18 run (LH-13).**
> `toc-file-§5`'s section order (Locales before Core, Settings last) and `layout-§1`'s load order
> (`core → defaults → locales → settings → modules`) still disagree. The addon now follows
> **`toc-file-§5`**, which is the more specific TOC rule, so LH-13 is recorded **closed against
> `toc-file-§5`**; the upstream contradiction itself remains open and is not this addon's to fix.

### library-stack

All libraries are vendored under `libs/` and committed: LibStub, CallbackHandler-1.0, AceAddon-3.0,
AceDB-3.0, AceEvent-3.0, AceTimer-3.0, AceConsole-3.0, AceGUI-3.0, LibSharedMedia-3.0,
LibDataBroker-1.1, LibDBIcon-1.0, **LibKa0s**. No `externals:` in `.pkgmeta`. No Ace fork. No suite
dependency; `## OptionalDeps:` only, never `## Dependencies:`.

`libs/LibKa0s/` is the **whole ship folder** and is **byte-identical** to
`../LibKa0s/LibKa0s` (`diff -r` empty — see `03_EVIDENCE.md`). `tests/_kit/` is byte-identical to
`../LibKa0s/testkit` (`diff -r` empty) and correctly lives under `tests/`, never `libs/`.

Four of the five majors are wired, each in its own setup file with a degradation stub:

| Major | Setup file | Instance |
|---|---|---|
| `LibKa0s-Core-1.0` | `core/CoreSetup.lua:32` | `NS.IsConcatSafe` / `NS.SafeToString` / `NS.Print` / `NS.Format` |
| `LibKa0s-DebugLog-1.0` | `core/DebugLogSetup.lua:25,76` | `NS.DebugLog`, sink bound bare at `:135` |
| `LibKa0s-Slash-1.0` | `settings/Slash.lua:103,170` | `Dispatcher`, re-exported onto `NS.Slash` |
| `LibKa0s-Options-1.0` | `settings/OptionsSetup.lua:35,66` | `NS.Options` (the instance *is* the member) |
| `LibKa0s-Perf-1.0` | **— not wired —** | **— absent —** |

Every lookup uses the silent form `LibStub(major, true)`; the addon's own suite pins this
(`tests/test_libka0s.lua`, case *"every seam file resolves its major with the silent flag"*).

### architecture

`local addonName, NS = ...` is the first line of every source file. No `_G[addonName]` table.
AceAddon registration passes `NS` as the first argument (`core/LootHistory.lua:4`) and **reclaims the
printer from AceConsole's embed** immediately after (`core/LootHistory.lua:13`) — architecture-§2's
second sanctioned fix, with `NS.Util.print` as the pristine copy.

Modules publish idempotently (`NS.Browser = NS.Browser or {}` etc.). The closed bus uses
`Ka0s_LootHistory_*` messages, and **every receiver owns a private AceEvent target** from
`NS.NewBusTarget()` (`core/LootHistory.lua:20-26`; consumers at `modules/Collector.lua:217`,
`modules/Analytics.lua:657`, `modules/Browser.lua:1308`, `settings/Panel.lua:123,318`). Messages are
documented in `docs/ARCHITECTURE.md` under `## Message bus`.

Schema-as-single-source is present: `settings/Schema.lua:23-113` is the row table,
`S:Set` (`settings/Schema.lua:160`) is the single write seam that both the panel descriptor
(`settings/OptionsSetup.lua:78`) and the slash descriptor (`settings/Slash.lua:188`) route through.
Boot validation walks every row (`settings/Schema.lua:189-198`).

### savedvariables

AceDB is initialized at `core/Database.lua:5` against `LootHistoryDB` with `NS.defaults`.
`schemaVersion` lives in the global namespace (`defaults/Global.lua:10`) and a real migration runner
ships with **eight** migrations plus a deferred bound-state repair (`core/Database.lua:13-120`).
Storage is account-wide under `db.global` (a recorded design decision, `CLAUDE.md:64`).

Defaults are declared in `defaults/Global.lua`; **schema rows restate several of the same literals**
rather than referencing them — see deviations.

There is **no second `<Addon>PerfDB` global** — see deviations.

### options-ui

The panel is the library's. `settings/OptionsSetup.lua:66-114` builds the `LibKa0s-Options-1.0`
instance from a descriptor carrying `parentTitle`, a **named** `mainPanelName`
(`LootHistorySettingsPanel`), the `get`/`set`/`applyDefault` write seam, `rowsForPage`, `allRows`,
`scheduleTimer`, `onAceGUI` and `buildMain`. The stub (`settings/OptionsSetup.lua:37-64`) is the
documented **load-completing** kind, publishing `LSMValues` and no-opping the rest — correct per
options-ui-§1 and deliberately **not** flagged.

Category registration is **eager**, from `OnInitialize` (`core/LootHistory.lua:34` →
`settings/Panel.lua:698-785`), never deferred to `/lh config`. Three subcategories (General, Filters,
AH Price), all with `defaultsButton = true` and a parked `defaultsOnClick`
(`settings/Panel.lua:712-765`); the Defaults widget is built lazily via `O.EnsureDefaultsButton` in
the panel's `OnShow` (`settings/Panel.lua:769`). Bodies render lazily through `O.SetRenderer` or a
guarded first-`OnShow`. Combat gating lives inside the library's `OpenOptionsPanel`
(`settings/Panel.lua:787-792`); the host adds no second un-gated open path. Scalar refresh is in
place via `O.RefreshScalars` (`settings/Panel.lua:684-686`).

The AH Price page keeps its **own** `OnShow` rather than `O.SetRenderer`, with a measured
justification recorded in comments (`settings/OptionsSetup.lua:20-27`, `settings/Panel.lua:738-747`):
its eleven pooled raw row slots would be orphaned by the renderer contract's `ClearScroll`.

The host also carries its own structural-rebuild bookkeeping (`ctx.rebuilders` / `ctx.dirty`,
`settings/Panel.lua:136-140`) alongside the library's — see deviations.

### standalone-windows

The History browser is a plain non-secure `CreateFrame("Frame")`, movable/resizable, registered in
`UISpecialFrames` (`modules/Browser.lua:1203-1204`), with position/size persisted to
`db.global.settings.window` (`modules/Browser.lua:115-121`) and a `settings.windowScale` setting
(`settings/Schema.lua:52-58`). It uses a tab strip with lazy per-tab build, and pooled rows for the
history table (`modules/BrowserTable.lua:581,720-726,877-898`).

`B.SKIN` (`modules/Browser.lua:20-33`) carries **exactly** the normative Ka0s window-edge values —
background `0.06,0.06,0.08,0.92`, black 1px outer edge, `0.24,0.24,0.27,0.85` inner highlight, gold
`1.0,0.82,0.0` title, matching divider — and `B:ApplySkin` (`modules/Browser.lua:66-86`) draws the
two-line edge including the once-built inner child frame. The host's own 24×24 class-colored close
glyph (`modules/Browser.lua:90-104`) is used on **its own** windows only; `core/DebugLogSetup.lua`
deliberately passes **no** `makeCloseButton`, so the library's windows keep Core's glyph
(`core/DebugLogSetup.lua:125-130`). That split is exactly what standalone-windows-§2 requires.

The `applySkin` hook **is** passed (`core/DebugLogSetup.lua:121-123`) so the console tracks the
host's re-skin seam — a sanctioned use. What is missing is delegation to `Core.ApplySkin` rather than
restating the values; see deviations.

### preview-mode

**N/A** — this is a data browser with no positionable on-screen display. The addon nevertheless
ships `/lh test`, a synthetic preview dataset (`settings/Schema.lua:233-236`,
`NS.State.testRecords`), which exceeds the section's expectation.

### slash-commands

`NS.COMMANDS` (`settings/Schema.lua:213-245`) is the host's ordered table of **positional triples**,
passed into the dispatcher descriptor (`settings/Slash.lua:173`). Registration is through
AceConsole (`settings/Slash.lua:238-241`) for `/lh` and `/loothistory`; no `SLASH_*` globals.

Reserved verbs present: `help`, `get`, `set`, `list`, `reset`, `resetall`, `config`, `version`,
`debug`. **`perf` is absent** — see deviations. `reset` takes a schema path. The `version` verb reads
TOC metadata with the in-code constant as fallback (`settings/Slash.lua:180-183`).

The chat tag is the mandated cyan `|cff00ffff[LH]|r`, a single shared constant
(`core/Namespace.lua:10`). Every file takes `local print = NS.Print` at file scope
(`modules/Browser.lua:5`, `settings/Schema.lua:5`, `settings/Slash.lua:4`, `settings/Panel.lua:4`) —
**no call site invokes the global `print()`**. The printer is the library's, built at
`core/CoreSetup.lua:97` and handed to both descriptors as a late-bound forwarder
(`core/DebugLogSetup.lua:92`, `settings/Slash.lua:176`, `settings/OptionsSetup.lua:72`).

The one host-side formatter is `Sl.FormatSchemaValue` (`settings/Slash.lua:113-127`), which handles
the two `type = "table"` set-valued rows the library has no type for and hands **everything else**
straight back to `lib.FormatValue` — the supported `format` descriptor hook, not a re-implementation.

### localization

`locales/enUS.lua:5` exports `NS.L` with the key-returning metatable. Only `enUS` ships (English-only
is a recorded scope decision, `locales/enUS.lua:7-11`). Game data is matched on stable
identifiers and **localized GlobalString constants**, never English literals: `AUCTION_HOUSE` and the
`AH_SUBJECT_GLOBALS` list (`core/Compat.lua:95-109`), the `LOOT_ITEM_*` / `CURRENCY_GAINED*` /
`ITEM_*BOUND*` globals (`.luacheckrc:21-39`), `classFile` tokens, `creatureID` from `UnitGUID`
(`core/Compat.lua:124-146`).

A whole-repo sweep for British spellings across `*.lua` / `*.md` / `*.toc` (excluding `libs/`,
`tests/_kit/`, and frozen audit/review history) returned **zero hits**. US English is clean.

### events-frames-taint

AceEvent throughout; no per-module event frames. No secure-frame writes, no protected-API calls, no
Blizzard frame replacement, no chat-frame manipulation — so §2–§5 are largely N/A. Frame pooling is
used for the high-churn history table. The secret-safe stringifier and printer are the library's,
published at `core/CoreSetup.lua:91-92` and reclaimed after the AceConsole embed
(`core/LootHistory.lua:13`).

### public-api

**N/A** — the addon exposes no public surface; there is no `NS.API` and no `_G[addonName]`.

### compat

`core/Compat.lua` (481 lines) is the sole owner of every varying/deprecated API — 29 exported
shims, from `Compat.GetPlayerMapID` to `Compat.GetAddOnMetadata`. A whole-repo grep for direct
deprecated calls outside `Compat` found **one** hit, and it is a call *into* `Compat`
(`settings/Slash.lua:181`). No `WOW_PROJECT_ID` branching anywhere.

### debug-logging

The console is the library's. `core/DebugLogSetup.lua:76-131` builds the instance from a descriptor
carrying `name`, `title`, `font` (`NS.Constants.FONT_MONO`), `slash`, `isEnabled`/`setEnabled` over
the host's session-only `NS.State.debug` (`core/State.lua:15`), a late-bound `print`, `safeToString`,
`initSummary` and `onVisibilityChanged`. The sink is bound **bare** at `core/DebugLogSetup.lua:135`.
The stub (`core/DebugLogSetup.lua:32-73`) answers 17 members and still flips the flag and prints the
ack. The monospace font ships under `media/fonts/` with its `OFL.txt` and is registered with LSM at
`core/LootHistory.lua:30`.

Coverage is genuine: **39** `NS.Debug` call sites across seven files, tagged and coalesced —
migrations (`core/Database.lua:26-117`), prune and purge (`:612,664`), capture and the
**not-recorded** decisions (`modules/Collector.lua:117,170,184`), attribution
(`modules/Attribution.lua:121-214`), and one-summary-line-per-pass for the table and analytics
renders (`modules/BrowserTable.lua:872`, `modules/Analytics.lua:485`). Settings changes are logged
once at the write seam (`settings/Schema.lua:170-172`).

### packaging

`.pkgmeta:1-12` — `package-as: LootHistory`, no `externals:`, ignores `.luacheckrc`, `.gitignore`,
`docs`, `tests`, `_dev`, `*.bak`. No `enable-toc-creation`. The prior run's LH-16 (`tools/` shipping)
is **closed** — the directory no longer exists.

### lint

`.luacheckrc` present, `std = "lua51"`, `exclude_files` now includes `docs/audits/` and
`docs/reviews/` (prior run's LH-17 **closed**). `globals` carries `LootHistoryDB` and
`StaticPopupDialogs`, each commented. **`luacheck .` runs clean: 0 warnings / 0 errors in 23 files.**
`debugprofilestop` is absent from `read_globals` and `LootHistoryPerfDB` from `globals` — a
consequence of the un-adopted perf harness; see deviations.

### testing

The kit is vendored at `tests/_kit/` (byte-identical to source) and `tests/wow_mock.lua` is a thin
extender over `mock_base.lua`. `tests/run.lua:30` derives the addon's own file list from the TOC via
`Loader.tocFiles`, and spells the eight `LibKa0s.xml` files out explicitly in XML order
(`tests/run.lua:17-26`). `Kit.expose` publishes `NS`, `mocks` and `Loader`.

**`lua tests/run.lua` → 563 passed, 0 failed, 563 total.** `docs/test-cases.md` is generated and its
grand total (563) matches the README `[tests]` badge (563/563). The degraded path is tested by
**actually loading the addon with LibKa0s absent** (`tests/test_libka0s.lua:48-62`), not by
hand-stubbing. `tests/test_vendor_sync.lua` carries a byte-identity gate over both vendored copies.

What is missing: the **derivation-pinning cases** testing-§9 mandates, and `tests/perf.lua` — see
deviations. The versioning suite (testing-§10) is **N/A**: this addon publishes no LibStub major.
Falsification comments (testing-§12) are absent from all suites; the section states an audit
**MUST NOT** record that as a deviation, so it is recorded here as **unverified**.

### performance

**Not adopted at all.** There is no `core/PerfSetup.lua`, no `NS.Perf`, no bucket declaration, no
bracket, no `perf` verb, no `LootHistoryPerfDB`, no suspend/resume, no `tests/perf.lua`, no
`docs/performance.md`, no `docs/perf-runs/`. The decision is **recorded** as a `wont-do` in
`docs/pending/LEDGER.md:70` (LIBKA0S-17), on the grounds that the addon owns no hot path (eleven
events, no `OnUpdate`, three one-shot timers) and that `suspend` would drop the very loot it exists
to record. The reasoning is sound and the record is exactly what the standard's deviation process
asks for — but the section is a **MUST for the wiring** regardless of coverage, so the audit records
it as a deviation cluster with that context attached.

### documentation

Root ships exactly `README.md`, `CLAUDE.md`, `LICENSE`. The README follows the canonical order —
H1, the five canonical badges in order (`README.md:3-7`, standard badge in the `_` form, `[wow]`
`Midnight_12.0.7` matching Interface `120007`, `[tests]` 563/563 matching the inventory), logo,
description, `## What's new in 1.2.0` (`:32`) immediately above `## Screenshots` (`:39`) and matching
the top Version History row (`:172`), `## Usage` with both mandated subsections, `## How attribution
works`, `## FAQ`, `## Troubleshooting`, `## Issues and feature requests`, `## Version History`. No
angle-bracket placeholders; the only `<…>` is a deliberate `<br>` in a table cell.

`CLAUDE.md` is a pointer stub with the required `## Standards compliance (read first)` section
(`CLAUDE.md:11`) — the prior run's LH-15 is **closed** — the adherence line, the docs pointer list
and the green-gate line. It explicitly states `docs/agent-context.md` must not exist
(`CLAUDE.md:24-39`), and **no such file is present** (anti-pattern #49 clear).

`docs/` carries the canonical trio (`ARCHITECTURE.md`, `testing.md`, `smoke-tests.md`) plus
`test-cases.md` and thirteen topic-detail docs. `docs/performance.md`, `docs/perf-runs/README.md` and
`docs/complexity.md` are absent. No `TODO.md`.

### audit-review-history

`docs/audits/2026-07-12/`, `docs/audits/2026-07-18/` and `docs/reviews/2026-07-11/`,
`docs/reviews/2026-08-03/` are retained and untouched. This run writes a new dated folder.

### versioning-git

Semver `1.2.0` in the TOC (`:5`) and in code (`core/Namespace.lua:5`), matching the README badge row
and the top Version History row. `schemaVersion` is at 8 with a migration per step. Trunk-based; the
current branch is `master` with no stray topic branches.

### naming-cheatsheet / anti-patterns

Naming conforms throughout. Of the 49 anti-patterns, the addon is clear of all but the ones implied
by the deviations below; specifically **#45 and #48 are clear** (both vendor diffs empty), **#47 is
clear** (no hand-rolled console, toolkit, dispatcher or harness; no local patch under `libs/`), and
**#49 is clear**.
