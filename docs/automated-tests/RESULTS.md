# Automated test results

<!-- The newest run is prepended by tests/_kit/run-automated-tests.sh. -->
<!-- This file is OVERWRITTEN IN PLACE — the git history of this one path is the trend line. -->

One row per run. The frozen evidence for each is in the dated folder beside this file;
the analysis of a given run is its `ANALYSIS.md`.

| Run | Version | Lint w/e | Tests | Perf | CCN warn | Max CCN | Verdict |
|---|---|---|---|---|---|---|---|
| [`20260804-114855`](20260804-114855/) | 1.2.0 | 0/0 | 563/563 | skip | 9 | 58 | **green** |

## Complexity watch list

Current state as of [`20260804-114855`](20260804-114855/) — not that run's diff.
Every function `lizard` warned on and every file in `layout-§1`'s 1000–1500 on-notice band,
each with a one-line disposition.

| `Database:QueryList` | 58 | `core/Database.lua` | **Accepted.** A filter-predicate chain, one branch per field, on the browser's per-keystroke path. |
| `NS:RunMigrations` | 56 | `core/Database.lua` | **Accepted, by design.** The CCN *is* the migration count; it can only rise. |
| `Database:RepairBoundStates` | 23 | `core/Database.lua` | **Accepted for now.** The repair "has been wrong more than once"; leave it one readable pass. |

Six further entries in `modules/Browser.lua` / `BrowserTable.lua` accepted with reasons recorded at 2026-08-04. `Database:Stats` (was 75, the worst in the repo) is **gone** — peeled this session into eleven named helpers, max CCN 13.

**Files in the 1000–1500 band:** `modules/Browser.lua` (1314) — already tracked as LH-31; `modules/Analytics.lua` (1180) — **peel next, now unblocked** by the `Database:Stats` work; `modules/BrowserTable.lua` (1040) — accepted.
