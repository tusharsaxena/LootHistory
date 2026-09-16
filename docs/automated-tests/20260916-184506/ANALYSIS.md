# Analysis — 20260916-184506

- **Addon:** LootHistory 1.3.0
- **Verdict:** green
- **Commit:** b267e3858e4cbefc6ecb3693f1e78e9f05f515ef (master), clean
- **Previous run:** [`20260916-094432`](../20260916-094432/)

## Headline

Both gating suites are clean — `luacheck` 0 warnings / 0 errors over 63 files and 786 of 786 cases
passing with no skips — so the run and the commit gate are green. The news is that both findings the
previous run recorded have been **closed**: the CCN-16 body in `settings/Slash.lua` is gone (max CCN
back to 15, warnings 1 → 0) and `tests/test_panel.lua` is back under `layout-§1`'s cap (over-cap files
1 → 0), so a release run taken today would clear the tag gate's zero-above-CCN-15 condition.
`perf` remains a standing `skip`: this addon ships no `tests/perf.lua`, so this bundle says nothing
at all about runtime cost.

## Suites

| Suite | Status | Result | Artifact | Moved since [`20260916-094432`](../20260916-094432/) |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 63 files | [`lint.txt`](lint.txt) | Same 0/0; scope widened 59 → 63 files. |
| tests | pass | 786 passed, 0 skipped, 0 failed, 786 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | +18 cases (768 → 786); still zero skips. |
| perf | skip | 0 scenarios — no `tests/perf.lua` | — (no artifact; nothing was measured) | Unchanged — a standing skip, not a new gap. |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | Max CCN 16 → **15**; warnings 1 → **0**; over-cap files 1 → **0**. |

Every status and count above comes from [`manifest.json`](manifest.json).

**Complexity in full** — all eight of `lizard`'s footer fields plus the two derived counts, from
`manifest.json`'s `suites.complexity` (the same footer is at the end of
[`complexity.txt`](complexity.txt)):

| Metric | Value |
|---|---|
| Total NLOC | 15349 |
| Functions | 2045 |
| Avg NLOC / function | 6.4 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 52.0 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 4 |
| Files over the 1500 cap | 0 |

Totals and averages tell different stories here and both are needed. The **totals** rose — 14889 →
15349 NLOC over 1980 → 2045 functions — which is the addon and its suite growing, not degrading. The
**averages** are flat or better: NLOC per function unchanged at 6.4, avg CCN down 2.2 → 2.1, avg
tokens per function 51.9 → 52.0, which is noise. So the code got bigger without getting denser, and
that is the only reading of these ten rows that is a complexity signal.

**`perf` — skipped, and that is a standing fact about the addon rather than a tooling gap.** The
runner's reason is `no tests/perf.lua — this addon ships no offline scenarios`, the first of
`automated-tests-§3`'s two sanctioned reasons (*nothing to run*), **not** a ratified
`performance-§12` no-combat-path exemption. Nothing in this bundle measures runtime cost, and
`performance-§9`'s zero-overhead evidence does not exist for LootHistory. This is a `skip`, not a
pass: at the release gate it is NOT EVALUATED. No suite was skipped for a missing tool — Lua 5.1.5,
`luacheck` 1.2.0 and `lizard` 1.24.0 were all present ([`manifest.json`](manifest.json), `host`).

## What moved

- **lint** — unchanged at 0 warnings / 0 errors, over 63 files rather than 59. The four extra files
  are new source and suite files, not a change of scope: `.luacheckrc` still excludes `libs/`,
  `docs/audits/`, `docs/reviews/`, `_dev/` and `tests/_kit/`, so those paths were not looked at at
  either run.
- **tests** — 768 → 786 passed, **+18 cases**, still 0 failed and 0 skipped, so passed and total
  agree and nothing here claims coverage that was not exercised.
  [`test-cases.md`](test-cases.md) is the inventory for this run.
- **perf** — no movement possible; skipped at both runs for the same reason.
- **complexity — the two open findings closed.**
  - `Sl@139-163@./settings/Slash.lua` warned at **CCN 16** last run and does not appear in this
    run's warnings block at all; [`complexity.txt`](complexity.txt) ends with *"No thresholds
    exceeded"*. Max CCN across the addon is back to 15 and the warning count is 0 — the peel the
    previous disposition proposed was taken.
  - `tests/test_panel.lua` was **1655 lines, over `layout-§1`'s 1500 cap**; it is no longer in the
    band table and `overCapFiles` is 0. The split the previous disposition named happened: the file
    now reports 665 NLOC over 52 functions beside a new `tests/test_panel_filters.lua` at 480 NLOC
    over 69 functions ([`complexity.txt`](complexity.txt)).
- **band files** — still 4, and the same 4. Three are flat on line count; `modules/Browser.lua` is
  the only one that moved, and it moved **down** (1307 at the previous run).
- **functions at the ceiling** — 7 bodies sit at exactly CCN 15, one decision below the tag gate,
  three of them in `modules/BrowserTable.lua` (up from two). None warns, so none blocks anything
  today.

## Complexity watch list

The generated tables live in [`../RESULTS.md`](../RESULTS.md) under `## Complexity watch list`; this
is the read of them.

**Functions `lizard` warned on:** None. The table reads `None.` for the first time since
[`20260916-094432`](../20260916-094432/) introduced a warned body, and that is the release gate's
condition satisfied.

**Files by `layout-§1` band:** four files in `1000–1500 (on notice)` — `modules/Analytics.lua`,
`modules/Browser.lua`, `modules/BrowserTable.lua` and `settings/Panel.lua` — and **none** over the
1500 cap. The band is the compliant state, not a breach. Nothing **newly** crossed this run; one
row left the record entirely (`tests/test_panel.lua`, fixed).

On shelf life: `automated-tests-§4` retires a disposition carried as *Accepted* across three
consecutive **release** runs. This record contains exactly one release run
([`20260910-234511`](../20260910-234511/), 1.2.0 → 1.3.0), so no row has reached that line yet.
`modules/Analytics.lua` is nonetheless the one to watch — it has read *"Peel next"* with nothing
tracking it for six consecutive runs, which is a decision that has stopped being one whether or not
the release clock has run out.

## Actions

1. File an owned issue for `modules/Analytics.lua`'s peel — split renderers from the
   formatting/segmenting helpers — or convert its watch-list row to *Accepted* and stop calling it
   next. Six runs of *"peel next"* with no owner is the row's own finding.
2. Watch the three CCN-15 bodies in `modules/BrowserTable.lua` (`@657-705`, `@969-986`,
   `@1080-1123`). They are dense guarding rather than tangled control flow, but any one of them
   gaining a single `and` would re-open the tag gate's blocker. No action today.
3. Decide whether LootHistory should ship `tests/perf.lua`. Until it does, every row in
   [`../RESULTS.md`](../RESULTS.md) is silent about runtime cost, and the silence is permanent
   rather than transient.
