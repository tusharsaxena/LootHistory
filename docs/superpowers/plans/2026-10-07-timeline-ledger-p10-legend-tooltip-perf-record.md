# Timeline Ledger — Phase 10 (Timeline legend tooltip and spacing) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal (owner feedback 2026-10-07, screenshots of the legend tooltip "Priest-Ravencrest / Click to hide/show" and the legend row "Total · Warband · Mage-Ravencrest · …"):** (1) legend tooltip title in the holder's color (class color for characters; Warband its series color; Total stays gold); (2) add the holder's CURRENT holding of the charted thing; (3) Total shows the account's current holding too; (4) legend spacing: Warband → first character gap equals the character → character gap; the Total → next gap stays as today.

**Spec:** §8.1 (amend legend behavior in the same task).

## Global Constraints
All earlier Global Constraints bind (Compat boundary incl. tooltip shims, ≤ 1500 lines, CRLF restore, gate via ka0s-bounded, regenerate docs/test-cases.md). Code on the branch is ground truth (Phase 8 legend buttons, Phase 9 changes in modules/Timeline.lua).

## Review Focus
1. Holding numbers come from the active Holdings store (test-mode sample when on) for the charted thing; a holder with no holding shows 0. Pinned in Task 1.
2. Gold holdings render as coin strings, items/currencies as counts. Pinned in Task 1.
3. Legend layout: gap(Warband, first char) == gap(char, char); gap(Total, next) unchanged; works with and without a Warband series and when legend wraps. Pinned in Task 1.

### Task 1: Legend tooltip (holder color + current holding) and legend spacing
**Files:** `modules/Timeline.lua` (legend buttons' OnEnter and layout), `modules/TimelineModel.lua` if a pure helper is cleaner (holding per holder for a thingKey via `NS.Holdings:Total(thingKey, set)` / active store), Compat tooltip shims (reuse `ShowLinesTooltip`), tests (Timeline suites), `docs/browser.md`, `docs/smoke-tests.md` (TL-17), spec §8.1.
**Requirements:**
- Tooltip lines: title = holder label colored (character → `RAID_CLASS_COLORS` via the holder's stored classFile / NS class-color helper; Warband → its series color; Total → the current gold title color, unchanged); line "Holding" with the current holding (gold → coin string with the same formatter as History's gold Qty; currency/item → count with thousands separators); gray hint "Click to hide/show".
- Total's holding = sum over the holders currently charted? NO — the account total for the thing (all holders, Character filter respected the same way the Total line is computed); say "Holding (all shown characters)" if the Total line itself is filter-restricted. Match whatever the Total line represents.
- Legend layout: entries laid out left-to-right with one uniform gap between non-Total entries (Warband included); the Total entry keeps its current gap to the next entry. Remove any special extra spacing the Warband entry gets today.
- Tests: tooltip title color per holder kind; holding value and formatting for gold/currency/item; test-mode store used; zero holding; layout gaps measured from button anchors/widths with a nonzero mock measurer, with and without Warband.
- Commit: `feat(timeline): legend tooltip shows holder color and current holding; even legend spacing`.

### Task 2: Record the 2026-10-07 in-game perf capture

**Files:** create `docs/perf-analysis/20261007-104651/` with `report.md` and `dump.json` copied byte-for-byte from /tmp/claude-1000/-mnt-d-Profile-Users-Tushar-Documents-GIT-LootHistory/79f7a2ae-8245-4de7-b298-392826c863a6/scratchpad/perf-20261007-104651/ (the owner's capture), and `ANALYSIS.md` written per the WowAddonStandards PERF_ANALYSIS.md playbook (fetch it; follow its section structure). Update `docs/perf-analysis/README.md` "## Captures" (replace "None yet." with a row linking the bundle) and any index/doc-map row the doc gates require (`tests/test_doc_structure.lua`).
**Findings to state (controller analysis, verify the arithmetic):** attributed cost 0.666 ms over 48.6 s combat (≈0.014 ms/s, ≈0.0002 ms/frame, max call 0.053 ms) vs an FPS delta of +0.57 ms/frame (≈2,800× the attributed cost) → the delta is pull-to-pull variance (different pulls, 48.6 s vs 52.7 s, 5-player Murder Row), not addon cost. Coverage gap: ledgerEvent fired once — no in-combat bag/money/currency traffic was exercised; out-of-combat work is outside the A/B by design. Recommended follow-up capture: potions + looting mid-pull, and B-before-A order.
**Commit:** `docs(perf): record the 2026-10-07 in-game capture (no measurable combat cost)`.
