# Timeline Ledger — Phase 4 (Polish from first in-game review) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the issues the owner found in the first in-game look at the branch: filter bar wrapping, Holdings tab density/banding/tooltips, a stray header, the Show-transfers default, and bank/warband drift attribution.

**Architecture:** Small, independent fixes on `feat/2026-10-06-timeline-ledger`. The filter bar moves out of `modules/Browser.lua` (1497/1500 lines) into `modules/BrowserFilterBar.lua` before it is changed. Holdings view changes stay in `modules/HoldingsTab.lua` (pure model + pooled view). The drift fix lives in `modules/Reconciler.lua`.

**Tech Stack:** Lua 5.1, WoW Retail 12.1.0, Ace3, vendored LibKa0s v1.69.0; gate `ka0s-bounded lua tests/run.lua` + `ka0s-bounded luacheck .`.

**Spec:** `docs/superpowers/specs/2026-10-06-timeline-ledger-design.md` (§5.6 drift, §7, §8.2, §11) plus the owner's feedback recorded in each task below.

## Global Constraints

- All Phase 1–3 Global Constraints still bind (Compat boundary, real Disable, SafeRegisterEvent on private targets, schema rows, append-only migrations with `schemaVersion` default 0, combat = dirty bits only, ≤ 1500 lines per file, CRLF line endings restored after every commit).
- Match the History table's look (`modules/BrowserTable.lua`) for any row styling: same skin colors, row height, stripe alpha, header font.
- Every test added runs headless; regenerate `docs/test-cases.md`.

## Review Focus

1. A narrow window at the new minimum width still shows every filter control on one line with no truncated label. Pinned in Task 1.
2. An expanded Holdings thing keeps all its holder rows on the parent's stripe color, and the next thing alternates. Pinned in Task 2.
3. Hovering a currency or gold row never errors (no item link). Pinned in Task 2.
4. A profile that explicitly stored `showTransfers = false` reads `true` after migration; a later explicit `false` is respected. Pinned in Task 3.
5. A bank whose contents changed while away writes `UNTRACKED` rows on the first read of the visit, and a deposit made during the same visit still writes a `MOVE`. Pinned in Task 4.

---

### Task 1: Filter bar on one line; Direction and Bound the same width; larger minimum window

**Owner feedback:** Some filter dropdowns wrap their label onto two lines (e.g. "Direction: 2 selected", "Quality: Common+"). Make every control fit on one row line; make the Direction and Bound dropdowns the same width; raise the window's minimum size so everything fits on one row.

**Files:**
- Create: `modules/BrowserFilterBar.lua` — move `B:BuildFilterBar` and its private helpers (the filter-bar section of `modules/Browser.lua`) here verbatim first, in its own commit, with no behavior change (TOC: directly after `modules\Browser.lua`). Update `docs/module-map.md`, `docs/ARCHITECTURE.md` module map and any doc/test that names the old location.
- Modify: `modules/BrowserFilterBar.lua` (layout), `modules/Browser.lua` (minimum size constants `B._minW` / `B._minH` and the resize bounds).
- Test: `tests/test_browser.lua` (append).

**Requirements:**
- Every filter dropdown label renders on a single line: compute each control's width from its widest possible label (measure with the FontString used, e.g. `GetUnboundedStringWidth`, against every option label plus prefix such as "Direction: 2 selected", "Quality: Common+", "Character: Current") plus arrow padding, or shorten multi-select summaries ("Direction: 2 sel." is NOT acceptable — prefer widening). Labels must also be set non-wrapping (`SetWordWrap(false)`, `SetMaxLines(1)`).
- Direction and Bound dropdowns share one width (the larger of the two computed widths).
- Window minimum width = the width the two filter rows need at those control widths plus margins; the existing resize grip and saved geometry clamp to the new minimum (an older saved smaller size is widened on load).
- Tests: (a) every filter-bar dropdown label FontString has word-wrap off; (b) Direction width == Bound width; (c) `B._minW` ≥ the sum of row-1 and row-2 control widths + gaps (assert against the built frames); (d) restoring a saved geometry narrower than the minimum yields the minimum.
- Commit messages: `refactor(browser): move the filter bar to modules/BrowserFilterBar.lua` then `fix(browser): one-line filter controls, equal Direction/Bound widths, larger minimum window`.

### Task 2: Holdings tab — metadata columns, banding, tooltips, header overlap

**Owner feedback:** The Holdings screen has a lot of empty space — add metadata like ilvl, quality, type, subtype, auction price. Add alternate row coloring like History; one color per thing, expanded holder rows share the parent's color. Show the item tooltip when hovering the item name. (Also: a green "Cou…"/"Count" label overlaps the Total header — find and fix.)

**Files:** Modify `modules/HoldingsTab.lua`; Test `tests/test_holdingstab.lua`. If `modules/HoldingsTab.lua` would exceed ~700 lines, split the view into `modules/HoldingsTabView.lua`.

**Requirements:**
- Columns (left to right): Name · iLvl · Quality · Type · SubType · AH price (unit) · Total · Value. Widths proportional to the pane, Name flexible; columns hide right-to-left (Value last to hide... keep Name, Total, Value always) when the pane is too narrow. Header labels use the History header style. Values: iLvl from the stored link (`C_Item.GetDetailedItemLevelInfo` through a Compat shim; blank for non-equippable/currency/gold); Quality as the quality label in quality color; Type/SubType from `Compat.GetItemTypeInfo` (currency: "Currency"/category; gold: "Gold"/blank); AH price = the picked AH unit price (`NS.AuctionPrice:Pick` over `GatherAll`, same as History's AH column; blank when none); Value unchanged.
- BuildModel carries the new fields (pure, testable): `ilvl`, `qualityLabel`, `itemType`, `itemSubType`, `ahUnit`.
- Sorting: clicking a header sorts by that column (name/ilvl/quality/type/subtype/ah/total/value), toggling direction like History.
- Banding: each thing line gets stripe index `k` (alternating per THING, not per line); its expanded holder lines reuse the parent's stripe color. Use the same stripe colors/alpha as `modules/BrowserTable.lua`.
- Tooltip: `OnEnter` on a thing row's name shows `GameTooltip` anchored to the row: items → `SetHyperlink(link or "item:"..id)`; currencies → `SetCurrencyByID(id)`; gold → a plain "Gold" title with the total formatted; `OnLeave` hides it. All through Compat shims (presence-gated).
- Fix the overlapping green "Cou…" header text above Total (identify the leaking FontString — likely a column header or legend from another pane/template — and remove/anchor it correctly).
- Tests: model fields for an item/currency/gold; stripe index alternates per thing and holder lines inherit it; tooltip handler calls the right GameTooltip method for each kind (mock records calls) and never errors on gold; header sort toggles order; no stray header FontString (assert the header row's FontStrings are exactly the column labels).

### Task 3: Show transfers on by default (new and migrated profiles)

**Owner feedback:** Make "Show transfers by default" true as the initial setting, for new profiles and migrated existing profiles.

**Files:** `defaults/Profile.lua` (`settings.showTransfers = true`), `core/Database.lua` (append migration `to = 12`), `settings/Schema.lua` row text if it mentions "off", `docs/schema.md`, `docs/profiles.md` if it lists defaults, tests (`tests/test_database.lua`, `tests/test_profiles.lua`, any test pinning the old default or `SCHEMA_VERSION == 11`).

**Requirements:**
- Default becomes `true`.
- Migration v11 → v12 walks every stored profile in `db.sv.profiles` (raw, as the v9/v10 steps do) and removes an explicit `settings.showTransfers = false` so the new default applies; returns the count changed. Idempotent. A user who sets it false AFTER v12 keeps false.
- History's default Direction filter includes Transfers when the setting is on (verify the existing Browser logic reads the setting and the docs say so).
- Tests: fresh profile reads true; a stored `false` becomes true after v12; a post-migration explicit false stays false; step list now ends `11->12`; `NS.SCHEMA_VERSION == 12`.

### Task 4: Bank and warband-tab drift on the first read of a visit is UNTRACKED

**Owner question:** "What happens when a transaction happens while the addon is disabled or on another PC? How is that captured?" Bags/gear/gold/currency drift is already written as `UNTRACKED` at login/resume. Bank and warband tabs are only readable at a banker, so drift there currently lands on the next visit as ordinary gain/loss rows with a guessed reason.

**Files:** `modules/Reconciler.lua`, `tests/test_reconciler.lua` (or the P2 suite that covers bank pairing), `docs/data-flow.md` (Login and resume section), `docs/ARCHITECTURE.md` Known limitations (cross-PC note).

**Requirements:**
- When a Banker/AccountBanker interaction opens, the FIRST flush that reads `bank`/`tabs` for that visit is a drift pass for those parts only: their differences against the stored snapshot are written with reason `UNTRACKED` (no holds, no pairing, no claims), while any other dirty parts flushed in the same pass keep normal classification. Implementation hint: flush the open-time read separately (`bank`, `tabs`, `warbandMoney` with `forceReason = UNTRACKED`) before normal capture resumes for the visit; a holder whose bank was never read before (no `scanned.bank` / `scanned.tabs`) gets a silent first read (genesis for that container: no rows, clears `meta.partial`).
- Subsequent flushes during the same visit are normal (deposits/withdrawals → MOVE).
- Document in `docs/data-flow.md` and add to Known limitations: two PCs each with the addon keep separate SavedVariables, so each sees the other's play as `UNTRACKED` (totals stay correct, reasons are lost); cross-PC sync is out of scope.
- Tests: bank changed while closed → first open writes UNTRACKED rows for exactly the difference; a deposit after that in the same visit writes a MOVE pair, not UNTRACKED; never-read bank → silent first read, `partial` cleared, no rows; warband tabs behave the same on `§warband`.
