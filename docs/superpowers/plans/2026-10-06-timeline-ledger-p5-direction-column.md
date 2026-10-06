# Timeline Ledger — Phase 5 (Direction column like BankLedger) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Make History's Direction a distinct, labelled column — an arrow glyph plus colored text ("Gain" / "Loss" / "Transfer") — the way BankLedger's ledger table draws Deposit/Withdraw.

**Spec:** `docs/superpowers/specs/2026-10-06-timeline-ledger-design.md` §7 (Direction column), owner feedback 2026-10-06 (screenshot: BankLedger Direction column, "▼ Deposit" green / "▲ Withdraw" red, header "Direction").

## Global Constraints

All Phase 1–4 Global Constraints bind (≤ 1500 lines per file, CRLF restored after commits, green gate through ka0s-bounded, regenerate docs/test-cases.md). The mono-font glyph use is the already-ratified exception (memory: mono font ratified; BankLedger documents the same pattern) — no new deviation.

## Review Focus

1. Pooled rows reused across gain/loss/transfer/legacy rows never show a stale glyph or color. Pinned in Task 1.
2. Group headers (Group: Direction) still read "Direction: Gain (N)" etc. Pinned in Task 1.

### Task 1: Direction column with glyph + colored label; smoke-doc formatting fix

**Files:** `modules/BrowserTable.lua` (the `dir` column spec ~line 180, the cell painter ~line 1167, BuildRow), `core/Constants.lua` (`C.DirLabel` / `C.DirGlyph` already exist — reuse; add nothing unless a label is missing), `tests/test_browsertable.lua`, `docs/browser.md`, `docs/smoke-tests.md`.

**Reference implementation (read it, don't copy blindly):** `/mnt/d/Profile/Users/Tushar/Documents/GIT/BankLedger/modules/LedgerTable.lua` — the `direction` column spec (~line 52: `label = "Direction", width = 82, align = "LEFT"`), `paintDirectionCell(fs, entry, glyphFS)` (~line 396-410) and how BuildRow creates the separate glyph FontString in the mono face.

**Requirements:**
- Header label "Direction"; column width sized to fit glyph + the longest label ("Transfer") at the row font (~85-95 px); left-aligned.
- Cell = a separate glyph FontString in the mono face (`C.FONT_MONO`) showing `C.DirGlyph[dir]` (▲ gain, ▼ loss, the transfer glyph), followed by the label text `C.DirLabel[dir]` in the regular row font; BOTH glyph and label colored with `NS.LedgerFormat.Color(dir)` (gain green, loss red, transfer gray). Legacy rows (no `dir`) read as Gain via `NS.Util.RowDir`.
- The painter sets glyph text, color AND shown-state every time (pooled rows); non-direction columns never show the glyph FontString.
- Sorting/grouping by Direction unchanged (DIR_RANK); the tooltip/desc for the column stays.
- If the History table's total column width grows, verify the minimum window width from Phase 4 still holds (adjust the floor computation if it is derived from table columns).
- Fix the Phase 4 residual: in `docs/smoke-tests.md` LED-10, put a blank line before the `Result:` line (and fix the stray heading rendering the reviewer noted) so it renders as its own paragraph. Add a smoke row LED-11: History Direction column shows "▲ Gain" green, "▼ Loss" red, transfer gray with label, across scrolling (pooled rows) and Group: Direction.
- Tests: column spec label/width; painter on IN/OUT/MOVE/legacy rows sets glyph text, label text and color; re-painting a pooled row from MOVE to IN leaves no stale glyph/color; a non-direction cell hides the glyph FontString.
- Commit: `feat(history): Direction column with glyph and colored label (BankLedger style)`.

### Task 2: Qty column fits gold amounts; Gold tooltip like BankLedger

**Owner feedback (screenshot):** History's Qty column truncates gold amounts ("9661…", "-1561…", "+1521…"). Widen it so the full signed gold value shows. Add a tooltip for Gold rows like BankLedger's: title "Gold" (gold color), a line "Amount" with the money string (coins) right-aligned, and a gray hint line when the row has a context menu (e.g. "Right-click for options").

**Files:** `modules/BrowserTable.lua` (qty column width / value formatting, row OnEnter for gold rows), `core/Compat.lua` if a new tooltip method is needed, `tests/test_browsertable.lua`, `docs/browser.md`, `docs/smoke-tests.md`.

**Reference:** BankLedger's gold row tooltip — grep `/mnt/d/Profile/Users/Tushar/Documents/GIT/BankLedger/modules/` for the gold tooltip (`Amount`, `GetCoinTextureString`, `GameTooltip:AddDoubleLine`).

**Requirements:**
- Qty column width fits the widest realistic signed gold string at the row font (e.g. "+9,999,999g 99s 99c" rendered via the same money formatter the cell uses — prefer a compact coin-texture string so the column stays reasonable; measure, don't guess). Item/currency quantities unchanged. Re-check the Phase 4 minimum-window floor if it depends on table width.
- Gold rows: hovering the Item cell shows the BankLedger-style tooltip (title "Gold" in gold color; `AddDoubleLine("Amount", <signed coin string>)`; the right-click hint only if this table offers a row context menu). Item and currency rows keep their existing tooltips. Presence-gated GameTooltip use via Compat (existing tooltip shims).
- Tests: qty width ≥ measured width of the widest sample (with a nonzero mock measurer if needed); gold row OnEnter calls the title/AddDoubleLine path and never SetHyperlink; item row still calls SetHyperlink; OnLeave hides.
- Smoke row LED-12: gold amounts fully visible; gold tooltip matches BankLedger's.
- Commit: `feat(history): wider Qty for gold amounts; BankLedger-style Gold tooltip`.

### Task 3: Stray faint green "Cou…" text drawn over other tabs

**Owner evidence (two screenshots):** a faint green text reading like "Cou…" / "Coun… <Tr…" is visible over the Holdings header (near Total) AND over History rows (under the Item column on a Gain row and near the Source column) — at DIFFERENT positions on different tabs. That rules out the P4 hypothesis (Character dropdown label wrap). Strong lead: a FontString created by the Timeline tab or the LibKa0s LineChart / legend / in-out strip / axis labels is parented or anchored to the browser window (or UIParent) instead of the Timeline pane, so it stays visible after the Timeline tab has been shown. Green = the gain color; "Cou…" likely "Count", "<Tr…" likely a legend/axis label such as "Transfers".

**Files:** `modules/Timeline.lua`, `core/WidgetsSetup.lua` (`NS.MakeLineChart` seam), `libs/LibKa0s/WidgetsLineChart.lua` is vendored — if the bug is in the library, DO NOT edit the vendored copy: report BLOCKED with the exact library line so the controller can fix it upstream in LibKa0s and re-vendor; `tests/test_timeline.lua` (or the Timeline suite), `docs/smoke-tests.md`.

**Requirements:**
- Find the leaking region(s) headless: build the window, select Timeline, then select History and Holdings, and assert that every FontString/Texture/Line created while Timeline was built is hidden when the Timeline pane is hidden (walk the mock's created regions; `IsVisible()` must be false for all of them when the pane is hidden). Fix the parenting/anchoring so they belong to the Timeline pane (or hide on pane OnHide).
- Also check Insights' strip/legend labels the same way (same class of bug).
- Update smoke LED-9 to describe the confirmed cause and the check (visit Timeline, then History/Holdings: no stray text).
- Commit: `fix(timeline): chart labels belong to the Timeline pane (stray text over other tabs)`.
