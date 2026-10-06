# Timeline Ledger — Phase 7 (Inter-holder moves become Gain + Loss) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Owner decision 2026-10-06 (after seeing duplicate "Transfer" rows for a Warband-bank → bags withdrawal of 1383g 99s and a Dawn Crystal): a move between two DIFFERENT holders is no longer a MOVE pair. The sender writes an OUT (Loss) row and the receiver an IN (Gain) row, each with a reason naming the action. Moves within ONE holder (bags ↔ own bank, equip/unequip, AH post escrow) stay single MOVE (Transfer) rows.

**Spec:** `docs/superpowers/specs/2026-10-06-timeline-ledger-design.md` §5.1 rule 2 (amend it: inter-holder = OUT + IN with action reasons), §4.1, §6, §7. Update the spec text in Task 3.

## Global Constraints

All Phase 1–6 Global Constraints bind. Source enum append-only (export contract). Schema migrations appended (`to = 13`), idempotent, `schemaVersion` default 0. CRLF restored after commits; gate via ka0s-bounded; regenerate docs/test-cases.md.

## Decisions (owner + controller rulings)

- New `SourceType` members (append-only, labels in `C.SourceLabel`, order in `C.SourceOrder`, included where the other ledger reasons are): `WARBAND_DEPOSIT` ("Warband deposit": character → §warband), `WARBAND_WITHDRAW` ("Warband withdraw": §warband → character), `ALT_MAIL` ("Alt mail"), `ALT_TRADE` ("Alt trade"), `CURRENCY_TRANSFER` ("Currency transfer"). Both rows of one move carry the SAME reason. The existing `TRANSFER` reason remains for single-holder MOVE rows and for currency consumed by a transfer beyond what arrived.
- Rows: sender `dir = "OUT"`, receiver `dir = "IN"`, each with its own `holder`; keep `from`/`to` on both rows (`"<holder>/<container>"`) for display/tooling; add `pairId` (shared small id, e.g. `ts .. ":" .. counter`) on both so a future view can relate them.
- History: the Character column shows the row's HOLDER (`NS.LedgerFormat.HolderLabel`, so `§warband` reads "Warband"), not the acting character; quantities signed as for any gain/loss. The Character filter matches the holder (Warband selectable).
- Insights: these rows count as gains/losses (owner accepted that account-wide totals still net out); they appear under their own reasons in the gains-vs-losses chart; no special exclusion.
- Rollup: in/out tallies follow the rows (OUT on sender, IN on receiver) — closes are unchanged (Holdings is the source of closes).

## Review Focus

1. Warband withdraw of gold and of an item produces exactly 2 rows (OUT on §warband, IN on character), same reason, same pairId; no MOVE row. Pinned in Task 1.
2. Bags → own bank deposit still produces exactly 1 MOVE row. Pinned in Task 1.
3. Migration converts only MOVE rows whose from/to holders differ, is idempotent, and rebuilds affected daily i/o so the Timeline strip matches the converted rows. Pinned in Task 2.
4. Character filter "Current" shows the character's half but not the Warband half; selecting Warband shows the Warband half. Pinned in Task 3.
5. Coalescing (60 s amend window) never merges an IN row with an OUT row or across holders. Pinned in Task 1.

### Task 0: Hidden/tracking currencies never produce rows (duplicate "Nebulous Voidcore")

**Evidence (owner report 2026-10-06 + read-only trace):** two Gain rows "Nebulous Voidcore" x1 one second apart — #137 currencyID 3513 (blank SubType, tooltip "None": a HIDDEN tracking currency) and #138 currencyID 3418 (SubType "Midnight", the real listed currency). Cause: the chat path (`modules/Collector.lua:217-272`, OnChatMsgCurrency/currencyLine) records ANY id the chat link resolves to (no listed-id check, ~line 227) and posts `claim("CURRENCY", 3513)` (~266) which no delta ever consumes; the real 3418 was newly discovered (not in baseline) so its delta went through the full list rescan, found no claim on `c:3418`, held CLAIM_WAIT 1.5 s and wrote an OTHER row. Holdings/diff paths are already list-only (Scanner.ScanCurrencies → Compat.ListCurrencies).

**Files:** `modules/Collector.lua`, `core/Compat.lua` (new `Compat.ListedCurrencyID(id, name)`; fix the CurrencyCategory miss memo ~lines 385, 408-412), `tests/test_collector.lua`, `tests/test_compat.lua`, `docs/data-flow.md` (currency section), `docs/smoke-tests.md` (CUR-1).

**Requirements:**
- `Compat.ListedCurrencyID(id, name)` returns the id to record, or nil: (a) `id` if it is in the token list (category cache) OR in the current character's / §warband's holdings `currency` baseline (covers currencies under collapsed headers); (b) else, if exactly ONE listed id has the same name, that listed id (remap 3513 → 3418); (c) else nil.
- In the chat currency path, after resolving the id: use the remapped id for the row AND the claim; on nil, drop the line with `traceCurrencyLineDrop("unlisted")` and post no claim. A genuinely new listed currency whose list entry is not yet present at chat time then gets its first gain from the diff path (accepted; documented).
- Fix the CurrencyCategory one-shot miss memo: clear it when `GetCurrencyListSize()` changes or on a nil-id CURRENCY_DISPLAY_UPDATE, so an id that later becomes listed resolves its SubType.
- No migration of already-stored hidden rows (cold client at migration time cannot test listing); document that the owner can delete them via the row menu.
- Tests: hidden id with a listed same-name twin → exactly one row under the twin id, claimed by the delta (no OTHER diff row); hidden id with no twin → no row, no claim, no holding; new listed id with list updated before the chat line → one claimed chat row; new id with list not yet updated → no chat row, one diff row after the rescan; id that misses then gets listed → SubType resolves; id under a collapsed header present in the baseline → kept.
- Commit: `fix(currency): hidden tracking currencies never record; remap same-name twins`.

### Task 1: Capture — inter-holder moves write OUT + IN with action reasons

**Files:** `core/Constants.lua` (new reasons), `core/Ledger.lua` (PairHolders / classification output shape), `modules/Reconciler.lua` (row writer for pairs), `modules/Escrow.lua` (alt mail), the trade and currency-transfer paths (grep `TRANSFER`, `PairHolders`, `MOVE` in modules/), `modules/LedgerFormat.lua` if labels/colors are keyed by reason; tests in the suites that pin pairs today (grep tests for `MOVE` and `PairHolders`), `tests/test_constants.lua`/`tests/test_util.lua` enum-count pins.

**Requirements:** as in Decisions. Reason selection: character→§warband = WARBAND_DEPOSIT, §warband→character = WARBAND_WITHDRAW (items, gold); own-alt mail credit = ALT_MAIL (sender OUT when sent, receiver IN when taken — keep Escrow's in-flight mail column semantics; the sender's OUT replaces today's MOVE half); own-alt trade = ALT_TRADE; account currency transfer between own characters = CURRENCY_TRANSFER. Update every test that asserted a MOVE pair for these flows to the new OUT+IN shape; add tests for Review Focus 1, 2, 5. Commit: `feat(ledger): moves between holders are a loss and a gain with action reasons`.

### Task 2: Migration v13 — convert stored inter-holder MOVE pairs; rebuild affected daily i/o

**Files:** `core/Database.lua` (append `to = 13`), `modules/Rollup.lua` / `core/Ledger.lua` (a pure helper to recompute a day's i/o for given holders/things from rows, if none exists), tests `tests/test_database.lua` (+ the rollup suite), `tests/test_profiles.lua` if it pins the version.

**Requirements:** For each stored row with `dir == "MOVE"` whose `from` holder ≠ `to` holder (parse `"<holder>/<container>"`): set `dir` = "OUT" if `holder` is the from-holder else "IN"; set `source` by the Decisions mapping (from/to = character↔`§warband` → WARBAND_DEPOSIT/WITHDRAW; character↔character: if the row's original reason/escrow marks mail → ALT_MAIL, trade → ALT_TRADE, kind CURRENCY → CURRENCY_TRANSFER; anything ambiguous → ALT_TRADE for items/gold, CURRENCY_TRANSFER for currency — document); add `pairId` only if absent (pair rows sharing ts+thing+qty with opposite holders get the same id; else a unique id). Then, for every (day, holder, thing) touched, recompute the rollup cell's `i`/`o` from the rows for that day (closes untouched). Idempotent (second run changes 0); returns rows changed. Update the step list/target assertions to 13. Commit: `feat(db): v13 converts inter-holder transfer pairs to loss + gain`.

### Task 3: Display, filters, Insights, docs

**Files:** `modules/BrowserTable.lua` (Character column = holder label; Character filter matches holder), `modules/BrowserFilterBar.lua` (Character list includes Warband if not already), Insights reason lists/colors (`modules/AnalyticsFormat.lua` palette for the 5 new reasons, legends), `modules/Export.lua` (no shape change beyond values), docs: the spec §5.1/§4.1/§6/§7 amendment (dated 2026-10-06, owner decision), `docs/data-flow.md`, `docs/schema.md` (enum + v13), `docs/browser.md`, `docs/smoke-tests.md` (TR-1: Warband withdraw gold+item → one Loss row on Warband, one Gain row on the character, reason Warband withdraw; TR-2: bags→bank deposit → one Transfer row; TR-3: mail an item to an alt and take it → Alt mail Loss/Gain), tests for Review Focus 4 and Insights counting the new reasons. Commit: `feat(history): holder column, warband filter, insights reasons for holder moves`.

Also in Task 3: update the test-mode sample generators from Phase 6 (sample history rows and sample rollup) so they emit the new OUT+IN shape with these reasons instead of inter-holder MOVE pairs.
