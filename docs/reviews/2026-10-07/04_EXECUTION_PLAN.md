# LootHistory — execution plan (2026-10-07 review)

Branch: `feat/2026-10-07-review-audit-remediation`. The green gate after every task is `lua tests/run.lua` plus `luacheck .` at 0/0, and the inventory and badge move in the same commit as any count change.

## Milestones

### M1 — Small fixes (C-04, C-05, C-08, C-09)
**Done when:** each change has a commit, the suite is green, and `docs/test-cases.md` and the badge reflect the new cases (+2: C-04, C-05).

| Task | Role | Implements | Files | Parallel? |
|---|---|---|---|---|
| T1 | lua-fixer | C-04 / F-004 | `core/Util.lua`, `tests/test_util.lua` | yes |
| T2 | lua-fixer | C-05 / F-005 | `modules/Reconciler.lua`, `tests/test_perf.lua` | yes, but **must precede T5** (same file) |
| T3 | lua-fixer | C-08 / F-008 | `modules/TimelineModel.lua` | yes |
| T4 | doc-fixer | C-09 / F-009 (+ C-06's known-limitation line, F-006) | `docs/testing.md`, `docs/data-flow.md` | yes |

T1 and T2 each add a case, so their `docs/test-cases.md` / README edits conflict. **Serialize the inventory regeneration**: land T1, then T2, each regenerating `docs/test-cases.md` with `lua tests/run.lua --list`.

### M2 — The release gate (C-01)
**Done when:** a sighted complexity run in scratch (`ka0s-bounded bash tests/_kit/run-automated-tests.sh --suite complexity --no-bundle`) reports **0 warnings**, and the suite is green.

| Task | Role | Implements | Files |
|---|---|---|---|
| T5 | lua-refactorer | C-01 | `modules/Reconciler.lua` (after T2) |
| T6 | lua-refactorer | C-01 | `core/LifecycleSetup.lua` |
| T7 | lua-refactorer | C-01 (characterization first for `convertHolderMoves` if not already pinned) | `core/Database.lua`, `tests/test_database.lua` |
| T8 | lua-refactorer | C-01 | `core/Ledger.lua`, `core/Compat.lua` |
| T9 | lua-refactorer | C-01 | `modules/Escrow.lua`, `modules/Collector.lua`, `modules/Holdings.lua`, `modules/AnalyticsLedger.lua`, `modules/TestData.lua` |
| T10 | lua-refactorer | C-01 | `modules/Browser.lua`, `modules/BrowserTable.lua` |

T5–T9 touch disjoint files and can run in parallel. T10 must precede M3.

### M3 — Peel (C-02)
**Done when:** `modules/BrowserTable.lua` and `modules/Browser.lua` are each below 1300 lines, the TOC lists the new files, `docs/module-map.md` and `docs/ARCHITECTURE.md` are updated, and the suite is green.

| Task | Role | Implements | Files |
|---|---|---|---|
| T11 | lua-refactorer | C-02 / F-002 | `modules/Browser.lua` → `modules/BrowserWidgets.lua`, `LootHistory.toc`, docs |
| T12 | lua-refactorer | C-02 / F-002 | `modules/BrowserTable.lua` → `modules/BrowserTableGroup.lua`, `LootHistory.toc`, docs |

T11 and T12 both edit `LootHistory.toc` and `docs/module-map.md`, so **serialize** them.

### M4 — Owner sign-off (C-03 plus the smoke list)
**Done when:** the owner has recorded LED-P2-01..24 and the `03_SMOKE_TESTS.md` sign-off table. The `AttributionOut.lua:64-65` comment is updated after LED-P2-06 passes.

## Checkpoints

1. After M1, the coordinator checks the green gate and that the inventory and badge agree.
2. After M2, the coordinator re-runs the sighted complexity suite in scratch (0 warnings) before any file moves.
3. After M3, the owner runs the in-client C-01 and C-02 smokes.
4. Before release, M4 must be complete. `/dev-copilot:bump-version` then regenerates `docs/automated-tests/` (expected: 0 CCN warnings, `perf` running).

## Commit strategy

Make one commit per task, with the subject prefixed by the consolidated plan's item id. Suggested messages:

- `fix(util): Coalesce recovers from a window the stand-down canceled (F-004)`
- `fix(perf): combat-exit flush runs outside the ledgerEvent bracket (F-005)`
- `refactor(timeline): RowDelta uses Ledger.LocationHolder (F-008)`
- `docs: testing.md suite count; escrow exit known limitation (F-009, F-006)`
- `refactor(<file>): <function> under CCN 15 (F-001)`, one per file group
- `refactor(browser): peel the widget kit into BrowserWidgets.lua (F-002)`
- `refactor(browsertable): peel grouping into BrowserTableGroup.lua (F-002)`
