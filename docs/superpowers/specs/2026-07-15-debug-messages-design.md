# Design — Better debug messages + standard MUST-DOs

**Date:** 2026-07-15
**Repos touched:** `LootHistory` (addon), `WowAddonStandards` (the standard)
**Status:** Approved design; implementation plan to follow.

## Goal

Make the debug console more useful: (1) trace the addon's main functional flows, (2) log
every settings change, (3) kill per-item/per-slot spam by coalescing, (4) keep the already-
standardized line format, and (5) codify coverage + anti-spam + settings-logging as **MUST**
rules in the Ka0s WoW Addon Standard, with this addon as the reference implementation.

## Motivation

The user wants all of: less noise, traceable flows, visible settings changes, and the rules
made a hard MUST in the standard.

## What is already in place (no change)

- Line format `<HH:MM:SS> | [<Tag>] <content>` — implemented via `NS.Debug(tag, fmt, …)` →
  `DebugLog.FormatColored` / `FormatPlain`, and **already MUST** in `debug-logging.md §3`.
- The single sink `NS.Debug`, its zero-alloc gate (`NS.State.debug`), secret-safe
  stringification (`NS.SafeToString`), and the session-only on/off flag.
- Every one of the ~18 existing call sites already routes through this seam, so "always this
  format" is structurally guaranteed — **no call site bypasses `NS.Debug`.**
- Verbosity stays a **flat on/off flag** — no log levels/tiers. Noise is fixed purely by
  coalescing.

## Decisions

- **Verbosity model:** flat on/off (`NS.State.debug`). No levels. (Rejected: INFO/VERBOSE
  tiers — more power but new session state + per-call-site level tagging, not wanted.)
- **Settings logging:** one canonical line at the single write seam (`Schema:Set`); no
  downstream re-echo.
- **Window geometry:** the documented `Schema:Set` carve-out is **not** logged — per-drag
  position writes would be noise.

## LootHistory code changes

### A. Coalesce existing spam (ConsumableMaster `eab4d50` pattern)

- `modules/Attribution.lua` — `[Open] LOOT_OPENED slot=… guid=… -> …` currently emits **one
  line per loot slot** (the per-slot loop). Collapse to **one summary line per open**:
  `LOOT_OPENED N slots -> <source> (<detail>)`. Detail/string-building stays behind the debug
  gate (zero-alloc when off). The existing "no source GUID" summary line is folded into this
  single summary.

### B. New flow coverage — all gated, exactly one line each

| Tag | File / site | Example line | Notes |
|-----|-------------|--------------|-------|
| `Init` | `core/LootHistory.lua` `OnEnable` | `DB ready schemaVersion=1 records=1423 modules=6` | Once on boot. |
| `Migrate` | `core/Database.lua` `RunMigrations` | `v1 -> v2, 1423 rows touched` | **Only when a migration actually runs.** |
| `Prune` | `core/LootHistory.lua` PEW prune | `retention 30d: removed 12 rows` | Once per session. |
| `Data` | `core/Database.lua` `Purge` / `DeleteAt` | `purge-all removed 1423 rows` / `deleted row @<ts>` | User-initiated mutations only. |
| `UI` | `modules/Browser.lua` show/hide/tab | `window shown` / `tab -> Insights` | One line per user action, never per frame. |
| `Table` | `modules/BrowserTable.lua` end of render | `rendered 84/1423 rows (filters=Quality,Source; group=Zone; sort=ts↓)` | **One coalesced summary per render pass.** |
| `Insights` | `modules/Analytics.lua` recompute | `computed range=30d, 1423 records` | One line per recompute. |

**Core anti-spam guarantee:** `Table` and `Insights` fire on every filter keystroke, so each
render/recompute pass emits **strictly one summary line — never per-row.**

### C. Settings — single seam, no echo

- `settings/Schema.lua` `Schema:Set` keeps its `[Set] <path> = <value>` line as the **one**
  canonical settings-change trace.
- **Remove** the redundant `[Cfg] changed(reason) → enabled=… q=… quest=…` echo in
  `modules/Collector.lua`'s `SettingsChanged` handler (it fires immediately after `[Set]`).
- A module reacting to `SettingsChanged` logs **only** if it does something a reader cannot
  infer from `[Set]` (e.g. Collector genuinely enabling/disabling capture).

### Tag inventory after this change

- Kept: `Loot`, `Drop`, `Attr`, `Open`, `Mail`, `Cast`, `Set`, `Debug`.
- Added: `Init`, `Migrate`, `Prune`, `Data`, `UI`, `Table`, `Insights`.
- Removed: `Cfg` (folded into `Set`).
- `Open` = the game loot window (attribution engine); `UI` = the addon's own browser window.
  Kept distinct on purpose.

## Standard changes — `WowAddonStandards/standards/standards/debug-logging.md`

Three new **normative** subsections (format §3 already covers "always this format"):

1. **Coverage (MUST).** Every addon MUST trace its main functional flows: lifecycle
   (load/init, schema migration, retention/prune), its core capture/compute flow, all data
   mutations, view open/recompute, **and every settings change.**
2. **Coalescing / anti-spam (MUST NOT).** MUST NOT emit per-item / per-slot / per-frame lines
   on a repeating path; collapse to **one summary line per pass** carrying the
   scanned/affected detail. String-building MUST stay behind the debug gate (zero-alloc when
   off). Described generically — the standard names no addon.
3. **Settings changes (MUST).** Log every settings mutation **once, at the single write seam**
   (the schema `Set`) as `[Set] <path> = <value>`; downstream change handlers MUST NOT
   re-echo the same change.

Bump the standard's version/date (new normative MUST content).

## Deviations flagged (per CLAUDE.md deviation rule + hard rules)

- **No auto-commit.** CLAUDE.md hard rule ("Never auto-stage / commit / push") overrides the
  brainstorming skill's "commit the design doc" step. This spec and all edits are left
  **working-tree only**; the user controls git.
- **Two repos.** Spec lives in `LootHistory/docs/superpowers/specs/`; the normative edits land
  in the `WowAddonStandards` repo. Both working-tree only.
- **Standard change, not addon deviation.** The user has explicitly chosen to *add* these
  MUST-DOs to the standard (the deviation rule's "change the standard's own definition" path),
  so this is a sanctioned standards evolution rather than a silent conform/deviate.

## Out of scope (YAGNI)

- Log levels / verbosity tiers.
- Logging window geometry drags.
- Persisting the debug flag (stays session-only per `debug-logging.md §5`).
- Any change to the console window, Copy/Clear, fonts, or the format itself.

## Verification

- `lua tests/run.lua` (headless) and `luacheck .` (0 errors) before any commit.
- Unit-test the coalescing helpers as pure formatters where practical.
- In-game smoke: toggle debug on, exercise each flow (boot, loot, open a loot window with
  many slots, change a setting, purge, open browser, filter the table, open Insights) and
  confirm each emits exactly one correctly-tagged line with no per-row/per-slot spam.
