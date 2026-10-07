# LootHistory — final summary (2026-10-07 review; written assuming `03_SMOKE_TESTS.md` passed)

## Headline

This cycle brought LootHistory back inside its release gate after the timeline-ledger merge. It reduced 26 functions back to CCN 15 or below, and it split the two History-window files before either reached the 1500-line cap. It fixed a settings readout that could stop updating for the rest of a session after a disable, and kept the combat-exit flush out of the perf bucket meant for cheap in-combat work. It also recorded the ledger's in-client checks and corrected a stale doc count. There is no player-visible behavior change beyond the readout fix.

## Counts

Critical fixed: 0, High fixed: 0, Medium fixed: 3 (F-001, F-002, F-003), Low fixed: 4 (F-004, F-005, F-008, F-009).
Deliberately not code-fixed: **F-006**, which is documented as a known limitation because a correct fix needs an `escrow.exits` schema change and a migration for a labeling-only edge case. **F-007** is accepted because the growth is bounded and only a few kilobytes.

## Changes by theme

### Release gate (C-01)
- **What changed:** 26 functions in 13 files were split into named helpers or ordered file-scope lists. No behavior change.
- **Why:** `automated-tests-§3` gates the tag on zero functions above CCN 15.
- **IDs:** F-001 / C-01.
- **Files:** `core/LifecycleSetup.lua`, `core/Database.lua`, `core/Ledger.lua`, `core/Compat.lua`, `modules/Reconciler.lua`, `modules/Escrow.lua`, `modules/Collector.lua`, `modules/Holdings.lua`, `modules/AnalyticsLedger.lua`, `modules/TestData.lua`, `modules/Browser.lua`, `modules/BrowserTable.lua`, plus characterization cases in `tests/`.

### File peel (C-02)
- **What changed:** the widget kit moved to `modules/BrowserWidgets.lua`, and History grouping moved to `modules/BrowserTableGroup.lua`.
- **Why:** both files were past the re-check triggers their own dispositions set, and one was 24 lines under the cap.
- **IDs:** F-002 / C-02.
- **Files:** `modules/Browser.lua`, `modules/BrowserWidgets.lua` (new), `modules/BrowserTable.lua`, `modules/BrowserTableGroup.lua` (new), `LootHistory.toc`, `docs/module-map.md`, `docs/ARCHITECTURE.md`.

### Lifecycle and measurement edges (C-04, C-05)
- **What changed:** the coalescer treats a window the stand-down canceled as not pending. The combat-exit flush runs outside the `ledgerEvent` bracket.
- **Why:** the settings page's storage readout could freeze for the session, and the perf bucket's declared scope was false.
- **IDs:** F-004 / C-04, F-005 / C-05.
- **Files:** `core/Util.lua`, `modules/Reconciler.lua`, `tests/test_util.lua`, `tests/test_perf.lua`.

### Hygiene (C-03, C-06, C-08, C-09)
- **What changed:** the owner's LED-P2 results were recorded and the `AttributionOut` comment was updated. The escrow limitation was documented. There is now one location parser, and the suite count in `docs/testing.md` is correct.
- **IDs:** F-003, F-006, F-008, F-009.
- **Files:** `docs/smoke-tests.md`, `modules/AttributionOut.lua`, `docs/data-flow.md`, `modules/TimelineModel.lua`, `docs/testing.md`.

## API / behavior changes

- No new or renamed slash verbs, settings or SavedVariables keys. Two new source files appear in the TOC.

## Saved-variable / migration notes

- None. No schema bump (`NS.SCHEMA_VERSION` stays 14).

## Deprecated-API migrations

- None.

## Performance impact

- C-05 changes attribution only. The before/after evidence is the C-05 `/lh perf` capture recorded as a `docs/perf-analysis/<stamp>/` bundle. Until that capture exists, no figure is claimed.

## Test and complexity movement

- Tests: 1476 passed / 1 skipped / 1477 before. After: +2 cases (C-04, C-05) plus any C-01 characterization cases. `docs/test-cases.md` and the README badge moved in the same commits.
- The next release's `RESULTS.md` regeneration should confirm 0 CCN warnings (from 26 today), and `BrowserTable.lua` and `Browser.lua` out of the band they entered.

## Known follow-ups

- F-006: per-exit timestamps for auction escrow, if the labeling error is ever reported.
- F-007: accepted. Revisit only if a session-memory capture shows it.

## Verification evidence

- `03_SMOKE_TESTS.md` sign-off table (owner), the sighted complexity run at M2's checkpoint, and the commit range on `feat/2026-10-07-review-audit-remediation`.

## Suggested PR description

```
LootHistory: review remediation (2026-10-07)

- F-001: 26 functions back under CCN 15 (release gate, automated-tests-§3)
- F-002: peel Browser widget kit and BrowserTable grouping before the 1500-line cap
- F-003: Phase 2 ledger smokes recorded by the owner
- F-004: Coalesce recovers from a window canceled at stand-down (settings readout froze)
- F-005: combat-exit flush runs outside the ledgerEvent perf bracket
- F-008/F-009: one location parser; testing.md suite count
- F-006 documented as a known limitation; F-007 accepted
```
