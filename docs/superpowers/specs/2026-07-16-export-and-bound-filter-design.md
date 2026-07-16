# Export button + Bound filter — design

**Date:** 2026-07-16
**Status:** approved (design), pending spec review

## Summary

Two changes to the History browser's filter bar:

1. **Remove the player-scope toggle** ("Current player / All players"), which is redundant with the
   Character multi-select filter, and put an **Export** button in its place. Export opens a small modal
   offering CSV export now and an AI-report export later.
2. **Add a Bound multi-select filter** to the filter bar, inserted after Date and before Quality, whose
   options are the five binding states from the Bound column's header-tooltip legend.

Target client WoW 12.0.7, Ace3, English-only, account-wide storage — unchanged.

## Motivation

- The player toggle only ever set the `char` filter to "current player" or "all players"; the Character
  dropdown already expresses any character subset, so the toggle is redundant UI.
- Users want their data out of the addon: into a spreadsheet (CSV) and, later, into an AI prompt that
  produces a formatted report.
- Binding state is shown per-row (the coloured lock) and is a natural thing to filter on, but there is
  no filter for it today.

## 1. Filter bar changes (`modules/Browser.lua`)

### Remove the player toggle

- Delete `PLAYER_OPTIONS`, the `dd.player` dropdown creation, and its `onSelect`.
- The **current-player session default is preserved.** It lives in `ApplyView(view, "current")` /
  `SetCharSet` — not in the toggle widget. The window still opens scoped to the current character; the
  Character dropdown widens it.
- Prune the now-dead `dd.player` branch inside `SetCharSet` (the block that set the toggle's label). The
  `scope` parameter and all current-player-default logic stay exactly as they are.

### Add the Export button

- A `makeBarButton` labelled **Export**, placed in the vacated row-2 right slot (`TOPRIGHT`, ~164px wide),
  with a tooltip ("Export your loot history to CSV or an AI report.").
- `onClick` → `NS.Export:Open(providers)` where `providers` is:
  ```lua
  {
    allData     = function() return NS.Database:Export({}) end,
    currentView = function() return NS.BrowserTable:OrderedFilteredRecords() end,
  }
  ```

### Add the Bound filter

- Insert a **multi-select** dropdown (same machinery as Quality/Type/Source/Zone/Character) after Date,
  before Quality. New row-2 order:
  **Date · Bound · Quality · Type · Source · Zone · Character.**
- Options (labels verbatim from `BOUND_LEGEND`):

  | value      | label            | matches `r.bound` |
  |------------|------------------|-------------------|
  | `NONE`     | Not Bound        | `nil`             |
  | `BOE`      | Bind on Equip    | `"BOE"`           |
  | `BOP`      | Bind on Pickup   | `"BOP"`           |
  | `ACCOUNT`  | Account Bound    | `"ACCOUNT"`       |
  | `WARBAND`  | Warbound         | `"WARBAND"`       |

  The `all` sentinel row is `Bound: All`.
- `onMultiSelect` → `B.activeFilter.bound = setToFilter(set)` then `ApplyFilter()`.
- Wire `bound` into the saved-view lifecycle: add to `STOCK_VIEW` (`bound = {}`), capture in
  `CaptureView` (`bound = setToFilter(dd.bound._selected) or {}`), and apply in `ApplyView`
  (`dd.bound:SetSelected(asSet(view.bound))` + `self.activeFilter.bound = setToFilter(asSet(view.bound))`).

### Row-2 layout

Adding Bound (~96px including its gap) to the left cluster would collide with the Export button at the
current minimum frame width. The plan tightens dropdown widths (and, only if necessary, nudges the
minimum frame width up) so all seven row-2 controls plus the Export button fit without horizontal
overflow. This is a layout-tuning detail, resolved during implementation.

## 2. Bound filter in the query (`core/Database.lua`)

Extend `QueryList` with a `bound` clause, consistent with the other set-valued filters:

```lua
local boundSet = type(filter.bound) == "table" and filter.bound or nil
...
if ok and boundSet then
  if not boundSet[r.bound or "NONE"] then ok = false end
end
```

The `NONE` sentinel is how "Not Bound" (`r.bound == nil`) is selected. No scalar form is needed — the
Browser always passes a set — but a stray non-table `filter.bound` is simply ignored (same defensive
posture as `quality`).

## 3. New module `modules/Export.lua` (`NS.Export`)

A new module, published as `NS.Export = NS.Export or {}`, added to the TOC after `Browser.lua`/
`BrowserTable.lua`. It owns the export modal, CSV serialization, the Wowhead-link builder, and (stubbed)
the AI prompt. Keeping this out of `Browser.lua` (already ~1050 lines) preserves single-purpose files.

### `Export:Open(providers)`

Builds (once) and shows the export modal. `providers` holds the two dataset accessors described above.

**Modal UI** — a skinned frame reusing `NS.Browser:ApplySkin` and `NS.Browser:MakeCloseButton`:

- **Data Set** dropdown: `All Data` (default) / `Current View`. Reuses the Browser dropdown look. Since
  `MakeDropdown` is currently file-local to Browser, the plan promotes a minimal dropdown factory to a
  shared entry point (e.g. `NS.Browser:MakeDropdown` / `NS.Browser:MakeBarButton`) that both modules call,
  OR Export builds a small purpose-made 2-option control. Chosen during implementation; either keeps the
  flat skin consistent.
- **Export to CSV** button → `Export:CSV(selectedRecords)` → shows the result in Export's own copy window.
- **Export to AI** button → placeholder: disabled (greyed) with a "Coming soon" tooltip, backed by a
  `Export:AIPrompt(records)` stub to be built later.

### Export's own copy window

Export builds and owns **its own** copy window (a read-only multiline `EditBox`, Ctrl+C to copy, Esc to
close), modelled on the debug copy window but **not shared with it** — so its layout can evolve
independently. `DebugLog.lua` is not touched. Frame name `LootHistoryExportCopyWindow`, registered in
`UISpecialFrames`.

### `Export:CSV(records)`

- One header row + one row per record.
- **Columns: all 19 export-contract fields plus two derived columns — `date` and `wowheadLink` (21
  total).** Field order follows `Database:Export`'s field list, with `date` and `wowheadLink` appended
  last.
- `ts` is emitted as the raw epoch integer. The derived **`date`** column is the human-readable
  `DD-MMM-YYYY` form (e.g. `16-Jul-2026`) via the existing `NS.Util.FormatDate(ts)` (already `%d-%b-%Y`;
  its code comment is stale and reads "MM/DD/YY").
- **`bound`** is emitted as its **friendly label** — `Not Bound` (for `nil`), `Bind on Equip`,
  `Bind on Pickup`, `Account Bound`, `Warbound` — matching the Bound column's tooltip legend. Export
  defines its own token→label map (the legend table is file-local to `BrowserTable`).
- `nil` numeric/string fields are emitted as empty.
- **Quoting (RFC 4180):** a field is wrapped in double quotes if it contains a comma, double quote, CR, or
  LF; embedded `"` is doubled. `itemLink` (contains `|`, brackets) is emitted raw inside quotes.
- Line terminator `\r\n` (spreadsheet-friendly); the copy window shows it as-is.

### `Export:WowheadLink(record)`

- Parse `record.itemLink`'s itemString: `link:match("|Hitem:([%-?%d:]+)|h")` (or `item:` fallback), split
  on `:`. Field layout: `itemID, enchant, gem1..gem4, suffix, unique, linkLevel, specID, modifiersMask,
  itemContext, numBonusIDs, bonusID1..N, ...`.
- Build `https://www.wowhead.com/item=<itemID>?bonus=<b1:b2:…>`; omit `?bonus=` when there are no bonus
  IDs. Bonus IDs are the modifiers Wowhead uses to reconstruct the exact item (ilvl, tertiaries, sockets).
- Fallbacks: no parseable itemString but `record.itemID` present → `https://www.wowhead.com/item=<itemID>`;
  neither → empty string.
- Inert text only — no network request is ever made.

## 4. `BrowserTable:OrderedFilteredRecords()` (`modules/BrowserTable.lua`)

New method returning the currently-filtered records **in current sort/group order** — exactly what the
table shows. Implementation: walk `BuildDisplayList()` and collect `entry.record` for every `kind == "row"`
entry (dropping `kind == "header"`). This makes "Current View" faithful to the on-screen ordering.

## 5. Tests (`tests/`)

- **Database bound filter** (`tests/test_database.lua`): a set including `NONE` matches unbound records;
  each token matches its records; a mixed set unions correctly; empty/absent filter returns all.
- **Export CSV** (new `tests/test_export.lua`): header column set/order (incl. `date` + `wowheadLink`); a
  record round-trips to the expected row; quoting escapes commas/quotes/newlines; `nil` fields become
  empty; `bound=nil` → `Not Bound` and each token → its friendly label; `date` column = `FormatDate(ts)`.
- **Export Wowhead link** (same file): itemString with bonus IDs → `?bonus=` list; itemString without
  bonuses → bare `item=<id>`; missing/garbage link with `itemID` → bare `item=<id>`; nothing → `""`.
- Register the new test file in `tests/run.lua`.
- **CLAUDE hard rule:** regenerate `docs/test-cases.md` (`lua tests/run.lua --list > docs/test-cases.md`)
  and bump the README `tests` badge count in the same change.

## 6. Docs

- `docs/browser.md`: document the Export button/modal and the Bound filter; remove the player-toggle
  description.
- `docs/ARCHITECTURE.md`: add the `Export` module to the module map.
- `LootHistory.toc`: add `modules\Export.lua` after the existing browser modules.

## Standards compliance

Nothing here reads as a deviation from the Ka0s WoW Addon Standard:

- New module + modal is the standard unit of work; `NS.Export` follows the module-publishing pattern.
- The Wowhead link is inert text (no network call, no protected API).
- Export is invoked directly by Browser — no new inter-module bus message, so the closed-bus rule is
  untouched.
- All user-facing strings stay inline English, matching the existing convention.

If any deviation surfaces during implementation it will be flagged to the user per the deviation rule.

## Out of scope (YAGNI)

- The AI export itself (prompt construction + report generation) — this change only lands the disabled
  placeholder button and a stub.
- User-configurable CSV column selection.
- Any export-to-file / clipboard-API path (the copy window is the transport).
- Persisting the last-used Data Set choice.
