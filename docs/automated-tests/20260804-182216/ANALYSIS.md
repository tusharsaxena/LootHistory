# Analysis — 20260804-182216

- **Addon:** LootHistory 1.2.0
- **Verdict:** green
- **Commit:** 75ed7c01630e (master), dirty
- **Started:** 2026-08-04T18:22:16+05:30
- **Previous run:** none — this is the first recorded run

## Headline

The first automated-test record for this addon, produced while adopting `automated-tests`
(standard v2.19.0). Both gating suites are clean: `luacheck` reports 0 warnings / 0 errors across
23 files and the headless harness passes 563 of 563 cases. The offline perf runner is absent (see below). Every figure below is a **baseline** —
there is no previous run to diff against, so nothing here is a regression and nothing is an
improvement.

## Suites

| Suite | Status | Result | Artifact | Moved since previous run |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 23 files | [`lint.txt`](lint.txt) | — first run |
| tests | pass | 563 passed, 0 failed, 563 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | — first run |
| perf | skip | — | — (not run) | — first run |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | — first run |

### Complexity in full

Every field of `lizard`'s footer, plus the two derived file counts. The **averages** are what make
this run comparable to the next one across a change in size: a total that rises because the addon
grew is a different fact from an average that rises because it got denser, and only the second is a
complexity signal.

| Metric | Value |
|---|---|
| Total NLOC | 11196 |
| Functions | 1457 |
| Avg NLOC / function | 6.7 |
| Avg CCN | 2.3 |
| Max CCN | 58 |
| Avg tokens / function | 55.4 |
| Warnings (CCN > 15) | 9 |
| Warning rate — `Fun Rt` / `nloc Rt` | 0.01 / 0.04 |
| Files in the 1000–1500 band | 3 |
| Files over the 1500 cap | 0 |

`tests/perf.lua` is absent — this addon ships no offline scenarios, so nothing was measured there. That is a **skip, not a pass**: it is recorded as one in `manifest.json`, and it means this run says nothing about the addon's runtime cost.

## What moved

**First run — nothing to diff against; every figure above is a baseline reading.** The next run is
the first one that can say something moved, and this record is what it will be read against.

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|
| `Database:QueryList` | 58 | `core/Database.lua` | **Accepted.** A filter-predicate chain — one branch per filter field, each independent and short, on the path the browser calls on every filter change. |
| `NS:RunMigrations` | 56 | `core/Database.lua` | **Accepted, by design.** A strictly ordered ladder of schema steps; the CCN *is* the migration count and can only rise. Do not read growth here as decay. |
| `Database:RepairBoundStates` | 23 | `core/Database.lua` | **Accepted for now.** The warband/BoE repair; its comment records that it "has been wrong more than once", which argues for one readable pass. |
| `B:CaptureView` | 23 | `modules/Browser.lua` | **Accepted.** One guard per captured field; read and pinned together with its inverse `B:ApplyView`. |
| `menu:Populate` | 20 | `modules/Browser.lua` | **Accepted.** Dropdown row construction, one branch per widget decision, run on menu open. |
| `dd:UpdateMultiLabel` | 19 | `modules/Browser.lua` | **Accepted.** The collapsed-button label rule; every branch is a documented display case, all pinned in `tests/test_browser.lua`. |
| `groupOf` | 19 | `modules/BrowserTable.lua` | **Accepted.** One branch per group-by mode, with the namespaced key that stops collapse state colliding between modes. |
| `B:ApplyView` | 17 | `modules/Browser.lua` | **Accepted.** The restore half of `CaptureView`, plus the deliberate carve-out that player scope is not part of a saved view. |
| `make` | 16 | `modules/BrowserTable.lua` | **Accepted — test mode only.** The fixed-seed synthetic record builder; never runs for a player. |

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Browser.lua` | 1314 | **Already tracked as `LH-31`.** The window shell, filter bar and dropdown widget kit; if it needs peeling the seam is the widget kit into a sibling file. |
| 1000–1500 (on notice) | `modules/Analytics.lua` | 1180 | **Peel next — now unblocked.** It was gated on the `Database:Stats` work, which has landed. Split renderers from the formatting/segmenting helpers. |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1040 | **Accepted.** Just over the line, and already three clean layers. Watch it; do nothing yet. |

## Actions

None arising from this run. The dispositions above are carried forward from the complexity reports
written against the same measurements earlier today; each was recorded with its evidence at the
time, and none is new here.
