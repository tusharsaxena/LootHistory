# Timeline Ledger — Phase 8 (Timeline line toggles) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Owner feedback 2026-10-07 (screenshot of the Timeline tab in test mode): add a "Total only" toggle, and make each legend entry at the bottom (Total, Priest-Ravencrest, …) clickable to toggle that line.

**Spec:** `docs/superpowers/specs/2026-10-06-timeline-ledger-design.md` §8.1 (amend with this behavior in the same task).

## Global Constraints

All Phase 1–7 Global Constraints bind (Compat boundary, ≤ 1500 lines, CRLF restored after commits, gate via ka0s-bounded, regenerate docs/test-cases.md). The vendored LibKa0s LineChart is not edited here; if the widget lacks a needed seam (e.g. per-series visibility or legend click callbacks), implement it in the host (`modules/Timeline.lua`) by passing only the visible series to the chart, or report BLOCKED naming the exact library change.

## Review Focus

1. Hiding every line (including Total) shows an empty-state message, never an error or a zero-range axis. Pinned in Task 1.
2. Y-axis rescales to visible lines only; the in/out strip stays the Total's. Pinned in Task 1.
3. Hidden state survives changing the charted thing and the date range; "Total only" persists in the saved view across reloads (profile `savedView`), per-holder hidden set is session-only. Pinned in Task 1.

### Task 1: "Total only" toggle and clickable legend

**Files:** `modules/Timeline.lua` (header toggle, legend buttons, visible-series selection), `modules/TimelineModel.lua` (pure: filter series by a hidden set, y-range over visible series), `modules/Browser.lua`/view-field code only if the saved view needs a new key (`timelineTotalOnly`), tests (Timeline/TimelineModel suites), docs `docs/browser.md`, `docs/smoke-tests.md` (TL-14), spec §8.1 amendment.

**Requirements:**
- Header: a "Total only" toggle (checkbox-style button in the house skin) next to the thing title. On → hide every holder line, keep Total. Off → restore the holder set that was visible before it was turned on. Persist as `savedView.timelineTotalOnly` (default off) through the existing view-field mechanism.
- Legend: each entry (Total + each holder) is a clickable button over its label. Click toggles that series' visibility. Hidden entries render dimmed (gray text, ~0.4 alpha) and keep their position; visible ones keep their line color. Tooltip: "Click to hide/show".
- Coupling: "Total only" reads as ON exactly when Total is visible and every holder is hidden; legend clicks update it; turning it on/off updates the legend.
- Hidden holder set is session-only, keyed by holder key; survives switching the charted thing and date range; holders that are not in the current chart are ignored.
- Chart draws only visible series; y-range/ticks computed over visible series; in/out strip unchanged (Total). All series hidden → chart area shows "All lines hidden — click a legend entry to show it." with no axes error.
- Hover crosshair/tooltip lists only visible series.
- Tests: pure filter + y-range over visible series; toggle on/off restores the previous set; legend click toggles and updates the toggle state; all-hidden empty state; persistence of timelineTotalOnly via the saved view; hover lists visible only; legend button count == series count and pooled buttons are reused across rebuilds.
- Commit: `feat(timeline): Total-only toggle and click-to-toggle legend`.

### Task 2: Tooltips on the Timeline gain/loss (in/out) strip bars

**Owner feedback 2026-10-07 (screenshot of the green/red daily bars under the Timeline chart):** add tooltips on the gain/loss bars.

**Files:** `modules/Timeline.lua` (strip bar frames — make each day's bar pair mouse-enabled, or one invisible hover hit-region per day covering the gain and loss bars), `modules/TimelineModel.lua` (the per-day flow values already feed the strip; expose what the tooltip needs if not already), Compat tooltip shims (`Compat.ShowTextTooltip` / `ShowAmountTooltip` from P4/P5 — reuse), tests (Timeline suite), docs `docs/smoke-tests.md` (TL-15), `docs/browser.md`.

**Requirements:**
- Hovering anywhere over a day's strip column (gain bar, loss bar, or the gap between them) shows a tooltip anchored to the cursor/bar: title = the day ("14 Aug 2026", same date format as the X axis/hover), then lines "Gained" (+N, green) / "Lost" (−N, red) / "Net" (signed, colored by sign). Gold values as coin strings (same formatter as History's gold Qty); currencies/items as counts. Lines with 0 are shown as 0 only if the other side is non-zero; days with no flow have no hit region (no tooltip).
- Values = the strip's own data (the Total across the visible holders? NO — the strip is defined as the Total; keep it the Total regardless of legend toggles from Task 1, and say "Total" in the tooltip title line: "14 Aug 2026 · Total").
- Hit regions are pooled with the bars (no per-redraw frame churn); OnLeave hides the tooltip; the chart's crosshair hover and the strip tooltip don't fight (strip area only).
- Tests: a day with in and out → tooltip lines Gained/Lost/Net with correct signs/colors; gold formatting path; no-flow day has no region; pooled regions reused across redraws (counts stable); OnLeave hides.
- Commit: `feat(timeline): tooltips on the daily gain/loss strip`.

### Task 3: Test mode pre-selects a Timeline item

**Owner feedback 2026-10-07:** in test mode the Timeline tab looks empty on load; pre-select an item (e.g. Everlight Crystal).

**Files:** `modules/Timeline.lua` (thing resolution on refresh), `modules/TestData.lua` (expose the default sample thing key), tests (Timeline suite), `docs/smoke-tests.md` (extend TM-1).

**Requirements:**
- While test mode is on, if the Timeline's current thing is unset OR not present in the sample stores, chart a default sample thing: "Everlight Crystal" if the sample contains it, else the sample item with the most rollup points (deterministic tie-break by thingKey). Expose it as `NS.TestData.DefaultTimelineThing()`.
- Session-only: never writes `savedView.timelineThing`; turning test mode off returns the Timeline to the user's own saved/real selection (or its empty prompt).
- A thing the user picks while in test mode is respected for the rest of the test session (not reset on every refresh).
- Tests: test mode on with no thing → title is the default sample thing and lines are drawn; saved view unchanged; user pick in test mode persists across refreshes; off → previous selection restored.
- Commit: `feat(testmode): Timeline opens on a sample item in test mode`.

### Task 4: Title Case for the holder-move reason labels

**Files:** `core/Constants.lua` (`C.SourceLabel` for WARBAND_DEPOSIT, WARBAND_WITHDRAW, ALT_MAIL, ALT_TRADE, CURRENCY_TRANSFER → "Warband Deposit", "Warband Withdraw", "Alt Mail", "Alt Trade", "Currency Transfer"), any test/golden/doc that pins the old strings (grep), `docs/smoke-tests.md` TR rows.

**Requirements:** display labels only; enum KEYS unchanged (export contract). Tests that pin labels updated; goldens regenerated only for these strings (`LH_WRITE_GOLDEN=1` per docs/testing.md if a golden pins them, and say so in the report). Commit: `fix(labels): Title Case for holder-move reasons`.
