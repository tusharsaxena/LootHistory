# Timeline Ledger — Phase 6 (Test-mode data, Holdings group-by, scaling filter bar) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Owner feedback 2026-10-06: (1) test mode (`/lh test`) shows sample data on the Timeline and Holdings tabs too; (2) the Holdings view honors Group-by; (3) the filter bar fills the window width with equal left/right margins at the minimum width and scales proportionally when the window is wider.

**Spec:** `docs/superpowers/specs/2026-10-06-timeline-ledger-design.md` §8.0–§8.2 plus the owner feedback in each task.

## Global Constraints

All Phase 1–5 Global Constraints bind (Compat boundary, real Disable, ≤ 1500 lines per file, CRLF restored after commits, green gate through ka0s-bounded, regenerate docs/test-cases.md, docs updated with behavior). Test mode is session-only and MUST NOT write SavedVariables (same contract as the existing `NS.State.testRecords`, modules/BrowserTable.lua:~657 and core/Database.lua:~450).

## Review Focus

1. Turning test mode off restores the real holdings/rollup views with nothing written to `db.global.holdings` or `db.global.daily`. Pinned in Task 1.
2. Holdings group-by with expanded things: holder rows stay under their thing, banding stays per thing within each group. Pinned in Task 2.
3. Window resized wider/narrower repeatedly: right margin always equals left margin (±1 px rounding, remainder given to the flexible control), no control below its one-line base width. Pinned in Task 3.

### Task 1: Test-mode sample data for the Holdings and Timeline tabs

**Files:** `modules/BrowserTable.lua` (where `/lh test` toggles `NS.State.testRecords` via `BuildTestData`), `modules/Holdings.lua` (read path), `modules/Rollup.lua` / `modules/TimelineModel.lua` (read path), possibly a new `modules/TestData.lua` if the generators would push any file near the cap; tests (`tests/test_holdings.lua`, `tests/test_holdingstab.lua`, the Timeline/TimelineModel suites, `tests/test_slash.lua`); `docs/` (where test mode is documented: grep "test mode").

**Requirements:**
- When test mode is on, publish session-only `NS.State.testHoldings` (same shape as `db.global.holdings`) and `NS.State.testDaily` (same shape as `db.global.daily`), built deterministically from the same sample universe as `BuildTestData` (the same characters, items, currencies; plus `§warband` and gold): at least 4 characters + Warband, ~40 items across qualities/types with links where the existing sample has them, 3 currencies, gold; daily series covering ~120 days with plausible ups/downs (deterministic, no `math.random` without a fixed seed), consistent with the test history rows' gains/losses where practical.
- Every holdings/rollup READ path resolves against the test stores while test mode is on (one accessor each, e.g. `Holdings:Store()` and the rollup's day-table accessor, mirroring `Database:History()` at core/Database.lua:~450). WRITE paths (Reconciler, Rollup writer) never touch the test stores and never run against them.
- Toggling off clears both and repaints the Holdings and Timeline tabs (same signal path History uses on toggle).
- Tests: on → Holdings tab model non-empty with ≥ 4 holders + Warband, Timeline model for Gold and for one item yields ≥ 2 lines with ≥ 100 points; off → views read the real (empty in the fixture) stores; `db.global.holdings` / `db.global.daily` untouched across on/off (deep-compare before/after); generation is deterministic (two builds equal).
- Smoke row (TM-1): `/lh test` → Holdings and Timeline show sample data; `/lh test` again → real data back.
- Commit: `feat(testmode): sample holdings and timeline data in test mode`.

### Task 2: Group-by in the Holdings view

**Files:** `modules/HoldingsTab.lua` (pure BuildModel + view; split the view into `modules/HoldingsTabView.lua` if it would pass ~700 lines), `modules/BrowserFilterBar.lua` (Group dropdown enabled on Holdings; per-tab filter graying), tests `tests/test_holdingstab.lua`, docs `docs/browser.md`.

**Requirements:**
- The shared Group dropdown is enabled on the Holdings tab. Supported groupings on Holdings: None, Quality, Type, SubType, Character (holder). Group options that do not apply to Holdings (Day, Source, Zone, Direction, …) are hidden or disabled while Holdings is active, and if the active group is unsupported on Holdings the view falls back to None without overwriting the History/Insights group choice (keep a per-tab group value, or map unsupported → None at read time; document which).
- Group headers look and behave like History's (collapsible "<Prefix>: <Value> (N)" header rows, same font/colors; collapse state remembered per tab within the session). N = number of things in the group.
- Character grouping: a thing appears under each holder that holds it; its Total in that group is that holder's count (the expand still lists that holder's container breakdown). Other groupings keep the all-holders total.
- Sorting applies within groups; groups ordered like History (quality by rank desc; type/subtype alphabetical; holders alphabetical, Warband last).
- Banding: stripe alternates per thing within the whole list (reset per group is acceptable — pick one and document); holder rows keep the parent's stripe (Phase 4 rule).
- Tests: grouping by Quality/Type/SubType/Character produces correct headers and counts; Character grouping totals per holder; collapse hides members; unsupported group → None; History's group value unaffected.
- Commit: `feat(holdings): group-by (quality, type, subtype, character)`.

### Task 3: Filter bar fills the window and scales proportionally

**Owner feedback (screenshot):** at the current width the filter controls stop ~120 px short of the right border while the left gap is ~6 px. Make the dropdowns match the window width at the minimum size, and when the window is wider, scale them so the left and right gaps stay consistent; choose the scaling ratio.

**Files:** `modules/BrowserFilterBar.lua`, `modules/Browser.lua` (resize hook / min width), tests `tests/test_browser.lua` (or a filter-bar suite), docs `docs/browser.md`, `docs/smoke-tests.md`.

**Scaling rule (controller ruling — implement exactly):**
- Fixed: left margin M (the current left inset) = right margin; inter-control gap G.
- Each row-2 control i has a base width b_i = its measured one-line width (Phase 4 `filterWidths`). Available width A = innerWidth − 2M − (n−1)G. Ratio r = A / Σb_i, floored at 1 (never narrower than base). Width w_i = floor(b_i · r); the rounding remainder goes to the last control (Export) so the row ends exactly at innerWidth − M.
- The minimum window width is the width at which r = 1 (row 2 exactly fits), so at minimum width the gaps are equal.
- Row 1 aligns to row 2's grid: Group width = Date width, Direction width = Bound width (both columns share x positions); the Save/Reset/Clear cluster spans exactly Export's x-range (three buttons equal width, gaps G); the search box takes the remaining width between Direction and the cluster.
- Re-layout on window size change (OnSizeChanged of the browser frame), cheap: positions/widths only, no rebuilds; dropdown menus already open are closed or re-anchored.
- Tests (pure layout function + built frames with a nonzero mock measurer): at min width r == 1 and right gap == left gap; at min+300 px all widths scale by the same r (within rounding) and right gap == left gap; row-1 Group/Direction x and width equal Date/Bound; cluster spans Export exactly; never below base widths when the window is narrower than min (clamped by min size anyway).
- Smoke row (FB-1): drag the window wider/narrower; both rows always end at the same right margin as the left.
- Commit: `feat(browser): filter bar fills the window and scales proportionally`.
