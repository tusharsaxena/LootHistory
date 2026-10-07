# Timeline Ledger — Phase 9 (Autocomplete, smoother lines, Type & SubType grouping, test-mode tooltips) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal (owner feedback 2026-10-07):** (1) test mode: hovering History items shows no tooltip; (2) Timeline lines look jagged; (3) a "Type & SubType" group-by (LootHistory and BankLedger); (4) the item-name suggestion list moves directly under the Search box with the same gray border, as an autocomplete, on every tab (History, Insights, Timeline, Holdings) and in BankLedger.

**Repos and branches:**
- LibKa0s `/mnt/d/Profile/Users/Tushar/Documents/GIT/LibKa0s` — branch `feat/2026-10-06-line-chart` (continue; v1.69.0 is a LOCAL unpublished tag at its earlier head).
- LootHistory — branch `feat/2026-10-06-timeline-ledger`.
- BankLedger `/mnt/d/Profile/Users/Tushar/Documents/GIT/BankLedger` — NEW branch `feat/2026-10-07-autocomplete-typesubtype` created from its `feat/2026-10-06-revendor-libka0s-v1.69.0` head (so it carries both).
- The other nine consumers (AbsorbTracker, KickCD, ConsumableMaster, MultiMeters, PanelMaster, PrettyChat, WhatGroup, AuraMaster, PartyFrameEnhanced) — their existing `feat/2026-10-06-revendor-libka0s-v1.69.0` branches gain one more re-vendor commit to v1.70.0.

**Controller rulings:** the autocomplete is promoted to LibKa0s (two consumers → `library-stack-§7` promotion bar met; no deviation). LibKa0s v1.70.0 is tagged LOCALLY only (publish waits for the owner's merge go-ahead), and every consumer re-vendors to it (owner ruling S3). Smoothing = fewer/longer segments + 2 px line, never altering values.

## Global Constraints

All earlier Global Constraints bind in every repo: the Ka0s WoW Addon Standard (any NEW deviation: STOP, report BLOCKED), each repo's CLAUDE.md, Compat boundary, real Disable, ≤ 1500 lines per file, green gate through `/home/tushar/.claude/dev-copilot/bin/ka0s-bounded` (`lua tests/run.lua` 0 failed, `luacheck .` 0/0), regenerate `docs/test-cases.md`, CRLF restored after every commit (`rm <path> && git checkout -- <path>` per touched file), never push/merge/publish, consumers re-vendor ONLY from the tag (`git -C LibKa0s archive <tag>`), provenance line bumped in the same commit.

## Review Focus

1. Autocomplete keyboard: Up/Down move, Enter picks, Esc closes and keeps typed text; clicking elsewhere closes; it never steals focus from the EditBox. Pinned in A1.
2. Autocomplete list width/position track the search box when the window resizes (FB-1 scaling). Pinned in B2.
3. Downsampling with a larger point spacing still keeps the series' min and max points. Pinned in A2.
4. "Type & SubType" headers with a missing subtype read "Type: Armor" (no trailing separator); currencies read "Currency · <category>". Pinned in B4/C3.
5. Test-mode rows with and without a real item id both show a tooltip; live rows unchanged. Pinned in B5.

## Part A — LibKa0s

### Task A1: `lib.Autocomplete` widget
Files: a new paired Widgets file (follow LibKa0s's paired-file/minor/version-key conventions exactly, as `WidgetsLineChart.lua` did at v1.69.0), API doc for the new version, tests, kit mock additions if an EditBox method is missing. API: `lib.Autocomplete(editBox, opts)` → handle; `opts.provider(text) -> { {text=, value=, color={r,g,b}|nil, icon=fileID|nil}, ... }` (called on text change, debounced ≥ 0.15 s, min 1 char), `opts.onPick(item)`, `opts.maxRows` (default 8), `opts.rowHeight`. The list anchors TOPLEFT/TOPRIGHT to the edit box's BOTTOMLEFT/BOTTOMRIGHT (same width, follows resizes), uses the edit box's skin border color (gray) and background, pooled rows, highlight on hover/selection, quality color per row, keyboard nav (Up/Down/Enter/Esc/Tab), closes on pick, on Esc, on EditBox focus loss (after click handling), and on `handle:Close()`; `handle:Refresh()`, `handle:SetEnabled(bool)`, `handle:Release()`. Never errors on an empty provider result (hides). Commit: `TL-LK-07: Autocomplete widget`.

### Task A2: LineChart per-chart point spacing
Files: `LibKa0s/WidgetsLineChart.lua` (+ its API doc and tests). Add `opts.pxPerPoint` (per chart, default stays `LC.PX_PER_POINT` = 2) used by `Math.Budget`; keep `series.thickness` (already per series). Test that a larger spacing reduces points and that LTTB keeps the global min and max of a series. Commit: `TL-LK-08: LineChart pxPerPoint option`.

### Task A3: Release v1.70.0 (LOCAL tag) + consumer census
Follow LibKa0s `docs/releasing.md` as the v1.69.0 release did (CHANGELOG, release record, API index, version keys, consumer census naming LootHistory and BankLedger as Autocomplete consumers), with the RELEASE RULE: `git tag -a v1.70.0` locally on the branch head; no push, no GitHub release, no master merge — list those as pending owner go-ahead. Commit(s) as releasing.md prescribes.

## Part B — LootHistory

### Task B1: Re-vendor LibKa0s v1.70.0
From the tag; provenance line in CLAUDE.md to v1.70.0; frozen revendor bundle if this repo keeps one (docs/revendor/, as B1 of Phase 3 did). Commit: `chore: re-vendor LibKa0s v1.70.0 (Autocomplete, LineChart pxPerPoint)`.

### Task B2: Search autocomplete on every tab
Files: `modules/BrowserFilterBar.lua` (attach `NS.MakeAutocomplete` seam — add it in `core/WidgetsSetup.lua` like `NS.MakeLineChart`), `modules/Timeline.lua` (remove the local picker list `makeSuggestRow`/`RenderSuggestions`; Timeline's provider charts the pick), providers per tab: History/Insights → distinct item and currency names in the current dataset (respecting test mode), picking sets the search text exactly and applies; Holdings → names from Holdings search; Timeline → things (Gold first when matching), picking charts it and keeps the search box text as the thing name. The provider is chosen by the active tab (registry: add an optional `suggest(text)`/`pick(item)` to the tab spec). Quality colors per row. Tests for each tab's provider and pick behavior, and that the Timeline's old list is gone. Smoke: AC-1 (all four tabs).

### Task B3: Smoother Timeline lines
`modules/Timeline.lua`: create the chart with `pxPerPoint = 6` and series thickness 2 (Total 2.5). Tests: the options reach the chart; point count for a 120-day series at a given width shrinks accordingly. Smoke: TL-16 (no stair-stepping on near-flat lines).

### Task B4: Group by "Type & SubType"
History (`modules/BrowserTable.lua` GROUP_OF/group options, labels) and Holdings (`modules/HoldingsTab.lua` grouping, Phase 6) gain a `typesub` grouping: key = itemType .. "\001" .. (itemSubType or ""), header "Type: <Type> · <SubType>" (no separator when subtype missing), ordered by type then subtype alphabetical. Saved view accepts it. Tests for headers, ordering, missing subtype, currency rows. Docs browser.md.

### Task B5: Test-mode tooltips in History
`modules/BrowserTable.lua` BuildTestData (or `modules/TestData.lua`): give sample rows real Midnight item IDs/links where the sample universe names real items (otherwise none). OnEnter: a row with a link → SetHyperlink (unchanged); a test row without a link → a text tooltip via Compat (name in quality color, "Type · SubType", gray "Test-mode sample"). Tests: both cases; live rows unchanged. Smoke: extend TM-1.

### Task B6: Docs and smokes (LootHistory)
browser.md, smoke-tests.md (AC-1, TL-16, the TM-1 tooltip line, HIST group "Type & SubType" row), module-map/ARCHITECTURE seam rows, test-cases.md.

## Part C — BankLedger (branch `feat/2026-10-07-autocomplete-typesubtype`)

### Task C1: Create the branch and re-vendor v1.70.0
`git -C BankLedger checkout -b feat/2026-10-07-autocomplete-typesubtype` from `feat/2026-10-06-revendor-libka0s-v1.69.0`; re-vendor from the v1.70.0 tag; provenance line. Commit: `chore: re-vendor LibKa0s v1.70.0`.

### Task C2: Search autocomplete in BankLedger
Attach the library Autocomplete to BankLedger's search box (`modules/Browser.lua` filter bar) through a host seam in its WidgetsSetup equivalent; provider = distinct item names (plus "Gold") in the ledger respecting its active filters/test mode; pick sets the search text and applies. Tests + its docs/smoke rows.

### Task C3: Group by "Type & SubType" in BankLedger
Add a `typesub` group option beside BankLedger's existing type/subtype groupings (`modules/Browser.lua` ~line 344 options, `modules/LedgerTable.lua` grouping/prefix), header "Type: <Type> · <SubType>"; saved view accepts it. Tests + docs.

## Part D — Other consumers

### Task D1: Re-vendor v1.70.0 into the nine other consumers
On each repo's existing `feat/2026-10-06-revendor-libka0s-v1.69.0` branch: re-vendor both payloads from the v1.70.0 tag (whole-folder), provenance to v1.70.0, gate green, one commit `chore: re-vendor LibKa0s v1.70.0`. (Parallel, one agent per repo.)
