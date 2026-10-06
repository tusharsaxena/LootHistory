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
