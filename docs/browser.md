# The browser window

The standalone loot browser is a single non-secure window with two views — **History** (the table) and **Insights** (analytics). `modules/Browser.lua` owns the window shell; `modules/BrowserTable.lua` owns the History table; `modules/Analytics.lua` owns the Insights tab. All three read the same dataset through `Database:ActiveHistory` (see [data-model.md](data-model.md)), so `/lh test` swaps synthetic data under both views at once.

## The standalone window (standalone-windows)

`EnsureFrame` (`Browser.lua:965`) builds one plain `CreateFrame("Frame", "LootHistoryWindow", UIParent, "BackdropTemplate")` — the Ka0s Standard standalone-windows pattern for standalone data browsers, of which this addon is the reference implementation. It is **non-secure by design**: no `SecureFrameTemplate`, no `InCombatLockdown` gate, so the window opens and repaints freely in combat. (The *settings* panel is separately options-ui-§2 combat-gated; the browser is not.)

The frame is `HIGH` strata, mouse-enabled (no click-through to the world), movable, resizable, and `SetClampedToScreen(true)` (`Browser.lua:981-985`). Four standalone-windows obligations are wired in `EnsureFrame`:

- **ESC to close** — `LootHistoryWindow` is appended to `UISpecialFrames` (`Browser.lua:1108`), so Escape hides it via the stock path. Because that path calls `frame:Hide()` directly (not `B:Hide()`), an `OnHide` hook closes any open dropdown menu (`Browser.lua:1097`).
- **Persisted position / size** — `SaveWindow` / `RestoreWindow` (`Browser.lua:86-106`) write `settings.window = { point, x, y, w, h }` to `NS.db.global` on drag-stop and resize-stop, and restore it on open. Restore floors width/height at the frame minimums (`B._minW`/`B._minH`). This geometry is an architecture-§5 carve-out: it is written straight to `NS.db.global`, **not** through `Schema:Set` (see [settings-panel.md](settings-panel.md)).
- **Persisted scale** — applied from `settings.windowScale` on build (`Browser.lua:1104`) and live-updated by `OnSettingsChanged` when the scale setting changes (`Browser.lua:1142`).
- **One re-skin seam** — the flat "ElvUI-like" look lives in a single `SKIN` table (`Browser.lua:20`, exposed as `B.SKIN`) applied by `B:ApplySkin(f)` (`Browser.lua:37`). Everything — window, dropdowns, menus, buttons — is drawn from the stock `WHITE8X8` texture with no ElvUI dependency. `ApplySkin` is deliberately separate from construction so a future settings panel can re-skin live; the class-coloured `×` close glyph (`MakeCloseButton`, `Browser.lua:61`) is shared with the debug window.

The default height (`SKIN.defaultH = 700`) opens tall enough to show the full Insights view; the minimum height is `SKIN.minH = 460`. The **minimum width is mostly derived, not hard-coded** — `BrowserTable:MinFrameWidth` (`BrowserTable.lua:669`) sums every fixed column width + gaps + the Item column's minimum + scrollbar gutter + margins, so columns can never overflow horizontally. The row-1 Search box's right edge is pinned to the row-2 Character dropdown's right edge (so the two stay aligned at any width), and `EnsureFrame` floors the width at 1160 (`math.max(minW, 1160)`, `Browser.lua:977`) so the right-aligned Save/Reset/Clear cluster always clears that Search box. The result is used as both the opening width and the resize floor.

## Window shell

### Tabs

`TABS = { "History", "Insights" }` (`Browser.lua:109`). Each tab is a content pane created up front but built lazily: `BuildPane` calls `B:BuildTable(pane)` (attaches the History table) or `NS.Analytics:Attach(pane)` (attaches the charts) only the first time a tab is shown — the panes now hold **only** their view, because the filter bar and footer are shared window chrome (see below). `B:SelectTab` (`Browser.lua:127`) toggles pane visibility, recolours the tab labels (gold active / grey idle), moves the underline, and refreshes the newly shown view against the shared filter — History re-runs `BrowserTable:Refresh` + `RefreshFilterOptions`, Insights re-runs `Analytics:Refresh`, and both then repaint the shared footer. `lastTab` is remembered within a session. `B:Show` eager-builds the History pane so the table (and thus `matchCount`) exists even when the window opens straight onto Insights.

### Filter bar — a browser-wide singleton (issue #13)

The filter bar and footer are **shared window chrome, not per-tab**: one filter drives the History table **and** the Insights charts, so you always know which slice of your loot you're looking at across both views. `EnsureFrame` anchors a `filterHost` frame below the tab strip and above the panes, then calls `B:BuildFilterBar(filterHost)` once; the footer is created directly on the frame. Layout top-to-bottom is: title bar · tab strip · **filter bar** · panes · **footer**.

`B:BuildFilterBar` lays out a **two-row** bar, ordered to mirror the table's columns:

- **Row 1** — Group-by dropdown · item-name search box · right-aligned `Save` · `Reset` · `Clear` buttons.
- **Row 2** — the column filters left→right in table order: Date · Bound · Quality · Type · SubType · Source · Zone · Character, plus a right-aligned tab-aware `Export` button.

Group-by, sort, and Save/Reset/Clear are table-view concerns; they're part of the shared bar but only affect the History table (harmless on Insights). Every filter change funnels through `ApplyFilter`, which pushes to `BrowserTable:SetFilter` (keeping `matchCount` + the footer current for both tabs) and, when Insights is the visible tab, re-runs `Analytics:Refresh`. `B:CurrentFilter()` hands Analytics a plain copy of `B.activeFilter` (the exact field shape `Database:QueryList` consumes), so the charts and the table filter by identical criteria.

All dropdowns are a custom flat-skin control (`MakeDropdown`, `Browser.lua:273`) rather than Blizzard's `UIDropDownMenu` — this keeps the look consistent and avoids the protected-call taint surface. One shared popup menu (`EnsureMenu`, `Browser.lua:190`) is reused by every dropdown, with a full-screen catcher that closes it on an outside click.

**Bound, Quality, Type, SubType, Source, Zone and Character are multi-select** (`dd:SetMulti(true)`). Clicking values toggles them into the dropdown's `_selected` set and keeps the menu open; the collapsed button summarises as the "All" label (empty set), the single option's label (one pick), or `"<Prefix>: N selected"` (`UpdateMultiLabel`, `Browser.lua:330`). Selected multi-select items get an inline check-glyph markup (`CHECK_MARKUP`, `Browser.lua:19`), and options can carry their own colour (quality colour) or an inline icon (the Character dropdown shows each looter's class icon + class colour via `BrowserTable:ClassIconMarkup`). The **Bound** dropdown (`boundOptions`) is data-driven like the others but kept in a fixed logical order (`BOUND_ORDER`: `Not Bound` / `Bind on Equip` / `Bind on Pickup` / `Account Bound` / `Warbound`, matching the Bound column's tooltip legend) — only states present in the data are offered, so e.g. `Warbound` appears once some loot is warbound. `Not Bound` uses a `NONE` sentinel that `Database:QueryList` maps to `r.bound == nil`.

Each multi-select's `onMultiSelect` copies its set into the matching `B.activeFilter` field via `setToFilter` (`Browser.lua:553`) — a fresh copy, never aliased to the live dropdown, so a later toggle can't mutate the filter behind the table's back — then calls `ApplyFilter`, which pushes `B.activeFilter` to `BrowserTable:SetFilter` and updates the footer. The set-vs-scalar shape is what `Database:QueryList` consumes (`Database.lua:136`; a set means membership, a scalar means equality).

The **date dropdown** is single-select (Today / Last 7 days / Last 30 days / All); it writes `activeFilter.from` from `NS.Util.RangeFrom(v)` (`Browser.lua:830`). The **search box** writes `activeFilter.text` on every keystroke (case-insensitive substring on item name). Every **value filter — bound / quality / source / type / subtype / zone / character** — is data-driven: `RefreshFilterOptions` rebuilds each from the current dataset (distinct values, prefixed with an "All" sentinel), so the menu offers exactly the values the history contains and nothing it doesn't. Quality (`qualityOptions`) is sorted in quality order and tinted per quality — so Heirloom / Poor / Artifact appear whenever present (matching the Insights "Quality distribution"); Bound (`boundOptions`) keeps a fixed logical order. The only static dropdowns are the two that are *controls*, not data enumerations: **Group by** (the grouping modes) and **Date** (the range presets) — those always offer every option regardless of the data.

**Character scope.** The Character filter is a multi-select dropdown (empty = all players). `B:SetCharSet` (`Browser.lua:654`) is the single seam that writes the char filter and mirrors the selection into the dropdown. The window **opens scoped to the current player** — a session-only default applied by `ApplyView(view, "current")`, deliberately *not* part of a saved view — and the dropdown widens it to any character subset.

**Saved views.** A "view" = group-by + sort + the column filters (bound / quality / type / subtype / source / zone) + date + search (but **not** character scope). `B:CaptureView` (`Browser.lua:663`) snapshots it; `SaveView` writes it to `NS.db.global.savedView`, `ResetView` clears it back to `STOCK_VIEW` (`Browser.lua:737`), and `ClearFilters` re-applies the saved-or-stock view. `B:ApplyView` (`Browser.lua:687`) is the single seam that paints every filter field, the table's group/sort, and the resolved filter, then resets scope. Like `settings.window`, `savedView` is an architecture-§5 carve-out persisted straight to `NS.db.global`. `asSet` (`Browser.lua:562`) tolerates the legacy scalar form so pre-multi-select saved views still load.

**Export (tab-aware, issue #15).** The right-aligned `Export` button routes through `B:OpenExport`, which picks the modal for the active tab. The modal **header names the source tab** — `"Export " .. lastTab` → "Export History" / "Export Insights", and any future tab flows through the same string. Both modes share the same skinned modal (`NS.Export:Open`, `modules/Export.lua`) — a **Data Set** dropdown (**All Data** vs **Current View**), an **Export to CSV** button, and a greyed **Export to AI** placeholder (`Export:AIPrompt` stub) — driven by a per-open `config = { title, providers, csv }`:

- **History tab** — exports loot **rows**. Providers: All Data (`Database:Export({})`) and Current View (`BrowserTable:OrderedFilteredRecords`, the filtered records in current sort/group order). Serializer: `Export:CSV`. That CSV leads with `ts` followed by human `date` (DD-MMM-YYYY) and `time` (HH:MM); renamed raw columns sit beside a readable sibling — human `quality` label before `qualityRaw`, formatted `sellPrice` ("Ng Ns Nc") before `sellPriceRaw` (copper) — `bound` is the friendly label, and a `wowheadLink` (built from the item's bonus IDs) is last. `itemLink`, `sourceDetail`, `mapID`, `subzone` and `confidence` are intentionally omitted.
- **Insights tab** — exports the **analytics summary**. Providers compute a `Database:Stats` result over All Data (`Stats({})`) or Current View (`Stats(B:CurrentFilter())`, honouring the shared filter). Serializer: `Export:InsightsCSV` — a sectioned `Section,Label,Count,Value` CSV mirroring the Insights view (summary cards, then each breakdown: by source/quality/type/bound/character/weekday/hour/keystone/confidence, the top zones/items lists, and per-day activity). The AI report is still a placeholder.

Export is called directly by the Browser and registers no bus message; its copy window (Ctrl+C to copy) is deliberately separate from the debug copy window so their layouts can diverge.

### Footer

The footer is **shared window chrome** (issue #13), created on the frame by `EnsureFrame` and shown on both tabs. `B:UpdateFooter` prints `"Showing X of Y"` at the bottom-left, where X is `BrowserTable.matchCount` (records that passed the filter, captured before grouping) and Y is `#dataset()` — the current dataset, so both numbers track test mode and reflect the same shared filter regardless of tab.

`B:UpdateDbSize` (`Browser.lua:605`) prints the estimated stored size — `"Database ≈ <size>"` — right-aligned at the footer's bottom-right, from `Database:StorageStats().bytes` (the same estimate the settings panel shows) through `Util.FormatBytes`. It reflects the **real** persisted history (not the test dataset) and is recomputed only where storage can change or the view (re)opens — `SelectTab("History")`, `OnHistoryChanged`, and `OnDatasetChanged` — **never** on a filter keystroke (filtering can't change what's stored), so the per-keystroke path stays allocation-light.

### LDB launcher + minimap button

`B:SetupMinimap` (`Browser.lua:1153`) registers a LibDataBroker-1.1 `"launcher"` data object (`INV_Misc_Bag_08` icon) with LibDBIcon-1.0. Left-click toggles the window, right-click opens the settings panel, and the tooltip shows the live `Database:Count()`. Visibility lives in `db.global.minimap` (the same table the "Hide minimap button" setting writes, owned by LibDBIcon), so registration alone honours the persisted hide state across `/reload`; `B:SetMinimapHidden` (`Browser.lua:1186`) toggles it live. Both libs are resolved lazily and the whole thing no-ops gracefully if either is missing.

The Browser subscribes to the bus on its **own** `NS.NewBusTarget()` (`B.__ev`, `Browser.lua:1212`) — never the shared bus-as-self — so its `SettingsChanged` / `HistoryChanged` / `RecordAdded` handlers don't clobber the Collector's or Analytics' handlers for the same messages (see [message-bus.md](message-bus.md)). `OnHistoryChanged` only does work when the window is open on the History tab.

## History tab — the virtualized table

`BrowserTable` is a **virtualized, object-pooled** table over `Database:Query`. The pipeline is **filter → group → sort → slice → bind** (`BrowserTable.lua:6`). Only the visible slice of rows ever exists as frames — there is never one frame per record.

### Column model

`BrowserTable.COLUMNS` (`BrowserTable.lua:118`) is a flat, ordered array; each entry carries a `key`, `label`, fixed `width` (or `flex = true` for the Item column, which absorbs the slack), `align`, a `desc` (header tooltip), a `valueFn(r)` (pure cell text) and a `sortFn(r)` (sort key). The columns are: Date, Time, iLvl, Bound (icon), Item (flex), Qty, Quality, Type, SubType, Source, Zone, Vendor, Character. **Character is intentionally last and Vendor second-last** — the order note (`BrowserTable.lua:116`) says any new column (AH price, Pawn) must be inserted before Character. `CellText` (`BrowserTable.lua:181`) exposes the same `valueFn` path the UI binds through, so cell text is unit-tested.

The **Bound column** renders no text — it draws a tinted padlock (`BOUND_STYLE`, `BrowserTable.lua:15`): grey = unbound, off-white = BoE, green = BoP, orange = account-bound, blue = warbound. The lock atlas is resolved once against a fallback list (`LOCK_ATLASES`, `BrowserTable.lua:27`) so it never renders blank on clients missing a given atlas; the header lock's tooltip shows the full legend (`AddBoundLegend`, `BrowserTable.lua:80`). The **Character column** and **Item/Quality columns** are colourised — class colour and item-quality colour respectively (`BindRow`, `BrowserTable.lua:892`).

### Filter → group → sort → slice → bind

`BuildDisplayList` (`BrowserTable.lua:544`) runs the pipeline: `Database:QueryList(CurrentRecords(), filter)` filters, `matchCount` is captured, then `SortRecords` and `GroupRecords` produce the flat display list. `CurrentRecords` (`BrowserTable.lua:537`) is just `Database:ActiveHistory()`, so the table shows synthetic data in test mode and live history otherwise.

- **Sort** — `SortRecords` (`BrowserTable.lua:424`) does a **stable** sort into a *new* array (records are never mutated); because Lua 5.1's `table.sort` isn't stable it decorates each record with its original index and tiebreaks on it, preserving chronological order among equal keys. `SetSort` (`BrowserTable.lua:447`) handles header clicks: re-clicking the active column flips direction, a new numeric column starts descending and a text column ascending (`NUMERIC_SORT`, `BrowserTable.lua:197`). Arrows are inline texture markup (`ARROW_ASC`/`ARROW_DESC`) because the default font has no ▲/▼ glyphs.
- **Group** — `GroupRecords` (`BrowserTable.lua:485`) partitions the sorted records under collapsible `{ kind="header" }` entries when `groupBy ≠ "none"`. The seven modes are None / Day / Quality / Type / Source / Zone / Character (`GROUP_OPTIONS`, `Browser.lua:376`, ordered to mirror the columns). `groupOf` (`BrowserTable.lua:215`) namespaces each group key by its mode (`groupBy .. "\001" .. raw`) so a zone named "Kill" can't collide with the Kill source in the collapsed-state map. Groups sort by the grouping column's natural order (direction `groupAsc`), and the row sort still holds within each group. **Clicking the grouped column's header flips the group order** rather than the row sort (`SetSort`, `BrowserTable.lua:451`); `UpdateHeaderArrows` shows the group-order arrow on the grouped column and the sort arrow on the sort column. Collapsing a group (`ToggleCollapse`, `BrowserTable.lua:474`) emits only its header.
- **Slice + bind** — `Bind` (`BrowserTable.lua:859`) drives a `FauxScrollFrameTemplate`: it computes `numVisible` from the viewport height, calls `FauxScrollFrame_Update`, reads the scroll offset, releases all rows, then acquires and binds only `list[offset+1 .. offset+numVisible]`. Empty state shows either "No records match your filters." or "No loot recorded yet. Go kill something." depending on whether a filter is active.

### Object pooling

`AcquireRow` (`BrowserTable.lua:573`) pops a free row from `rowPool` or builds a new pooled `Button` (one FontString per column + a stripe, highlight, bound-lock texture and group-header FontString). `ReleaseAllRows` (`BrowserTable.lua:701`) hides every active row and returns it to the free list before each bind — so the frame count is bounded by the viewport, never by history size (Standard standalone-windows). Column geometry is recomputed by `LayoutRowCells` (`BrowserTable.lua:678`) and `BuildHeaderCells` (`BrowserTable.lua:809`) — the flex Item column takes `total − fixed`, and `Bind` re-lays the header on every pass so header and rows stay aligned across resizes.

### Row actions

Each pooled row wires three interactions (`AcquireRow`, `BrowserTable.lua:621-653`):

- **Hover** → the full in-game item tooltip via `GameTooltip:SetHyperlink(record.itemLink)`; INFERRED rows get a "Source inferred (uncertain)." note, plus a hint line advertising the click actions.
- **Shift-left-click** → `ChatEdit_InsertLink(link)` links the item to chat.
- **Right-click** → `ShowRowMenu` (`BrowserTable.lua`), a tiny flat-skin popup (gold border so it reads against the 3D world) with **Link to chat**, **Blacklist item**, and **Delete**. **Blacklist item** (issue #14) calls `NS.Filters:AddBlacklist(record.itemID)` — point-in-time, so the clicked row (and every other stored row of that id) stays in the browser; only *future* loots of the id are dropped. Use **Delete** to remove existing rows. There is deliberately no whitelist action here (whitelisting is about items that were *not* recorded, so there's no row to act on). **Delete** calls `NS.Database:Delete(pred)` (which fires `HistoryChanged`) and repaints immediately.

A group header's left-click toggles its collapse instead.

## Insights tab — Analytics

`Analytics:Attach` (`Analytics.lua`) builds a `UIPanelScrollFrameTemplate` filling the pane, a row of stat/highlight cards, and a stack of breakdown sections. Everything is **driven off a single `Database:Stats(filter)` pass** (`Analytics:Refresh`) — one O(n) aggregation whose result struct feeds every card, bar, strip and list.

### Scope — the shared filter (issue #13)

Insights has **no range selector of its own**. `Analytics:Refresh` scopes every stat by the browser's shared filter — `Database:Stats(NS.Browser:CurrentFilter())` — so the Insights view and the History table always reflect the exact same criteria (the shared Date dropdown, plus every column filter). An empty filter aggregates the whole visible history. Analytics live-refreshes while it's the visible tab (its own `RecordAdded`/`HistoryChanged` bus subscription) and whenever the shared filter changes on the Insights tab (`ApplyFilter`).

### Stat & highlight cards

`CARD_DEFS` (`Analytics.lua:212`) — 4 columns per row, `wide` cards spanning 2: records, distinct items, characters, vendor value, active days, epic+ drops, best drop (ilvl), richest drop, date range (wide), busiest day (wide). `UpdateCards` (`Analytics.lua:290`) reads them straight from `stats.totals`; string cards (value, richest, span, busy) use a smaller font. "Vendor value" throughout is `sellPrice × quantity` captured at loot time — **not** market price.

### Breakdown sections

`LayoutCharts` (`Analytics.lua:548`) binds and positions each section top-down off `self.stats`, returning the running y-cursor (empty sections are skipped entirely). The sections, in order:

| Section | Source field | Renderer |
|---|---|---|
| Loot by source | `bySource` (share of records) | horizontal bars, per-source colour |
| Vendor value by source | `valueBySource` | horizontal bars |
| Quality distribution | `byQuality` (quality order) | horizontal bars, quality colour |
| Quality mix | `byQuality` | one segmented stacked bar |
| Loot by item type | `byType` | horizontal bars |
| Loot by bound type | `byBound` (`BOUND_ORDER`) | horizontal bars |
| Loot by character | `byChar` | class-coloured horizontal bars |
| Loot over time (per day) | `byDay` | vertical strip |
| Vendor value over time (per day) | `valueByDay` | vertical strip |
| Loot by hour of day | `byHour` (24 buckets) | vertical strip |
| Loot by weekday | `byWeekday` (Sun–Sat) | horizontal bars |
| Mythic+ loot by keystone level | `byKeystone` | horizontal bars (only when keyed loot exists) |
| Attribution confidence | `byConfidence` | horizontal bars |
| Top zones / Top items by count / Top items by value | `topZones` / `topItems` / `topItemsByValue` | ranked list panels |

Three pooled renderers back all of these:

- **`renderBarSection`** (`Analytics.lua:412`) — a header + one horizontal bar per row (fixed label + track/fill + value). It normalises so the largest bar fills the track and the rest scale relative to it.
- **`renderStrip`** (`Analytics.lua:440`) — a per-bucket vertical strip with an axis line and rotated x-axis labels (thinned out when bars get narrow); each bar's hover shows the bucket's info line. The per-day strips share a `firstTs..lastTs` day-key list (gaps included) from `dayKeyList`, capped to the most recent `MAX_DAY_BARS = 60`.
- **`renderListPanel`** (`Analytics.lua:489`) — a ranked list panel capped at 10 rows; item rows are quality-coloured with a gold star before epic+ items (`starMarkup`, resolved against a fallback atlas list). The two item lists share the same entry tables from `stats.byItem` — two orderings, count-desc and value-desc.

Every renderer draws from a per-section pool in `self.pool` (`Analytics.lua:384`); `LayoutCharts` releases all pools up front, then re-acquires only the widgets it needs, so no chart holds a widget per data point. `Analytics:Layout` (`Analytics.lua:310`) sets the scroll child height from the final y-cursor. If the range has no records, `HideAllCharts` runs and an empty-state label shows.

Analytics subscribes to `RecordAdded` / `HistoryChanged` on its own `NS.NewBusTarget()` (`Analytics.lua:403`) and live-refreshes only while the Insights tab is visible.

## `/lh test` — synthetic preview

`BrowserTable:ToggleTestMode` (`BrowserTable.lua:406`) publishes a synthetic dataset to `NS.State.testRecords` and opens the window. Because `Database:ActiveHistory` (`Database.lua:105`) returns `NS.State.testRecords` when present, the fake data flows through the *same* read paths (`Query` / `Stats` / `CurrentRecords`) — so it drives **both** the History table and the Insights charts at once, while write paths (Add / prune) always target the real history and never see the override. `OnDatasetChanged` (`Browser.lua:627`) rebuilds the filter dropdowns from the new dataset, resets to the stock view + all players in test mode (test characters differ from the current one), and toggles the red "TEST MODE" badge beside the title.

`BuildTestData` (`BrowserTable.lua:344`) generates a deliberately **non-uniform** spread — weighted-random sources / qualities / classes / zones / types / timestamps, a handful of "hot" items over a long tail, keystone and evening-hour peaks — so the charts read like real play. It uses a deterministic Park–Miller LCG with a fixed seed (`testRng`, `BrowserTable.lua:324`), **not** `math.random`, so the dataset is byte-identical every run and the headless tests stay stable. A coverage seed pass first guarantees every source / quality / class / binding appears and the range spans more than 14 days regardless of the dice.

Test mode is session-only: it resets on `/reload` and is never persisted (Standard debug-logging-§5, same rule as the debug flag).

---

See also: [module-map.md](module-map.md) · [data-model.md](data-model.md) · [settings-panel.md](settings-panel.md) · [message-bus.md](message-bus.md)
