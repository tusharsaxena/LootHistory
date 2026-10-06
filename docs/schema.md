# Schema

The persisted shape: the single saved variable and its two scopes (the account-wide `db.global` and the per-profile `db.profile`), one record per loot event, the dense-array history it lives in, the `SourceType` / `Confidence` enums, the `Schema:Set` write seam, the rows it writes and its storage-only carve-outs, the `schemaVersion` migration seam, retention, and the two read seams (`ActiveHistory`, `Export`).

## The saved variable

Single saved-variable: `LootHistoryDB`, an AceDB-3.0 store. `NS:InitDB` calls `AceDB:New("LootHistoryDB", NS.defaults, true)` (`core/Database.lua:7`), and the store has **two scopes**, split by what a value *is* (docs/profiles.md):

- **`db.global`, account-wide: what the account RECORDED.** The loot history, the deferred warbound repair's bookkeeping, the `schemaVersion` stamp, `retentionDays` (the one setting that governs the recorded data, owner decision D6: a profile switch, copy or reset never changes what the prune deletes), and LibDBIcon's `minimap` table, which launcher-§3 pins to the global store so a profile switch never moves or hides the button.
- **`db.profile`, per profile: what the player CONFIGURED.** Every other schema row under `settings`, the three id filter lists, the window geometry and the saved table view. The `true` third argument makes every character start on the shared `Default` profile; the Profiles page (settings/Profiles.lua) moves a character to another one.

Why the history is account-wide: loot is collected across every character on the account and attributed with a `char` column on each record, so the browser and Insights tab can show one alt's drops, all alts, or any subset. A per-profile history would fragment that record and force a schema + query rewrite; the account-wide decision is load-bearing, and a profile switch, copy or reset never touches it.

Until schema v9 **every** setting lived in `db.global` too, and the profile was unused. The v8→v9 migration moved them, and the v9→v10 migration lifted `retentionDays` back out to `db.global.retentionDays` (see [schemaVersion & the migration seam](#schemaversion--the-migration-seam)).

### `db.global` shape

Defaults are declared in `defaults/Global.lua`; AceDB merges them under `db.global` on first access.

```lua
db.global = {
  schemaVersion = 11,          -- DB schema stamp; declared 0, carried to 11 by NS:RunMigrations at init
  history = {},                -- dense array of loot records (one per loot event)
  retentionDays = 30,          -- "Keep history for" (row settings.retentionDays); 0 == keep Always. Account-wide (D6)
  minimap = { hide = false },  -- LibDBIcon visibility state (global by launcher-§3)
  boundRepairPending = <true|nil>,  -- migration job: rows still to be split (see below)
  boundRepairAttempts = <n|nil>,    -- fruitless passes so far; both clear when the job completes
  boundRepairRevision = <n|nil>,    -- which build of that job has run; a bump re-arms it
  holdings = {},               -- timeline ledger: what each holder owns now (see The ledger stores)
  daily = {},                  -- timeline ledger: sparse daily rollup (store created v11, written by modules/Rollup.lua)
  rollupRetentionDays = 0,     -- "Keep Timeline days for" (row settings.rollupRetentionDays); 0 == keep Always. Account-wide
  rollupSeeded = <ts|nil>,     -- when the one-time rollup seed ran (undeclared bookkeeping, see The ledger stores)
  ledgerSince = <ts|nil>,      -- when ledger capture began (v11 step; the reset popup rewrites it)
  resetPrompt = <nil|"reset"|"kept">,  -- the one-time reset recommendation's recorded answer
}
```

### `db.profile` shape

Defaults are declared in `defaults/Profile.lua`; AceDB merges them into the active profile on first access, and into every profile a session switches to.

```lua
db.profile = {
  blacklist = {},              -- { [itemID]=true } — dropped at capture; existing rows untouched (registry: NS.Filters)
  whitelist = {},              -- { [itemID]=true } — always record, bypassing the gates (registry: NS.Filters)
  currencyBlacklist = {},      -- { [currencyID]=true } — currency dropped at capture (blacklist-only; registry: NS.Filters)
  settings = {
    enabled          = true,   -- master switch (Master controls tab)
    visibility       = "always",  -- always | inCombat | outOfCombat | never (Master controls tab)
    scale            = 1.0,    -- ADDON-WIDE scale; multiplies windowScale below
    alpha            = 1.0,    -- ADDON-WIDE opacity
    locked           = false,  -- stop the History window and the export modal being dragged
    qualityThreshold = 1,      -- record Common (white) and above
    excludeQuestItems = true,  -- drop Quest-class items at capture (opt-out)
    recordCurrency   = true,   -- record looted currency as Type=Currency rows (source-muted; ignores quality)
    excludedSources  = {},     -- set of MUTED SourceType keys
                               -- (no retentionDays: it is account-wide, db.global.retentionDays)
    windowScale      = 1.0,    -- the History window's OWN scale; multiplied by settings.scale
    rowHeight        = 18,     -- History-table row height, in pixels
    window           = {},     -- persisted position/size (named non-setting state, see below)
    auction = {
      enabled = true,          -- master AH-pricing switch (Schema row)
      capture = {},            -- set of enabled "provider:key" tags — collect AND rank (Schema row, MultiCheck)
      priority = {},           -- ordered "provider:key" cascade selection list (the one carve-out, see below)
    },
  },
  savedView = <table|nil>,     -- saved table view (named non-setting state, see below); absent until saved
}
```

- `history` is a **dense array** — `Database:Delete`/`PruneOld` rebuild-and-swap rather than leaving holes (`core/Database.lua:863`, `:946`). Each record's field shape is documented below.
- `settings.excludedSources` is stored as the set of **muted** sources; the panel renders it inverted ("Record data from"), so a checked box means "record this source" (`settings/Schema.lua:305`).
- `savedView` exists once the user clicks **Save** in the browser filter bar, or once the Timeline remembers a pick (see below); until then reads fall back to the stock view.

- `settings.visibility`, `settings.scale`, `settings.alpha` and `settings.locked` are the **Master controls** tab's addon-wide rows (options-ui-§15). They **need no migration of their own**: none of them replaces an older stored value — this addon never shipped a *show only in combat* boolean — so a store written before them simply has no key and AceDB merges the shipped default in. `settings.scale` **multiplies** `settings.windowScale` rather than replacing it: one is addon-wide, the other is the History window's own, and options-ui-§15 forbids conflating them.

Debug is **session-only** (`NS.State.debug`) and is deliberately **never persisted** — it resets to off on every reload (no `debug` key in either defaults file; the console-visibility row `state.debugConsole` is on the Master controls tab).

## The loot record

Every acquisition is **one row** — records are keyed only by array position, never deduplicated by item. Timestamps and every column are therefore first-class for sort/filter; aggregation (group-by, Insights) is a *view* concern, never a storage concern. Records are plain tables with **no metatables**, so they serialize cleanly for `Database:Export`.

Assembled by `Collector:BuildRecord` (`modules/Collector.lua:60`):

```lua
-- a single entry in LootHistoryDB.global.history[]
{
  ts           = 1752230400,        -- local epoch seconds (server-local time())
  char         = "Ka0z-Ravencrest", -- "Name-Realm" of the looter (Util.PlayerKey)
  classFile    = "MAGE",            -- locale-independent class token (for row coloring)
  itemID       = 211296,
  itemLink     = "|cffa335ee|Hitem:211296::...|h[Item Name]|h|r",
  itemName     = "Item Name",
  quality      = 4,
  itemLevel    = 639,
  bound        = "BOP",
  vendorPrice  = 25000,             -- vendor sell price, copper per unit (renamed from sellPrice in v3)
  auctionPrice = {                  -- nested map provider -> key -> copper (nil if nothing captured)
    tsm = { dbmarket = 41200, dbminbuyout = 39500 },
    oribos = { market = 40800 },
  },
  itemType     = "Armor",
  itemSubType  = "Cloth",
  quantity     = 1,
  source       = "KILL",
  sourceDetail = { npcID = 214506, encounterID = 2902, difficulty = 16 },
  zone         = "Nerub-ar Palace",
  mapID        = 2657,
  subzone      = "The Hive",
  confidence   = "CERTAIN",
}
```

### Field semantics

| Field | Meaning |
|---|---|
| `ts` | Loot time, local epoch seconds via `time()`. The primary sort/range key. |
| `char` | Looter's `"Name-Realm"` (`Util.PlayerKey`) — the account-wide `char` column that stands in for per-character profiles. |
| `classFile` | Locale-independent class token (`"MAGE"`, `"WARRIOR"`, …) from `UnitClass`. Used only for coloring the character in the UI — never the localized class name. |
| `itemID` | Numeric item id. Denormalized from the link for fast filter/sort/group without parsing links or hitting an uncached `GetItemInfo`. |
| `itemLink` | **Canonical.** Reconstructs the *exact* tooltip (upgrade track, bonus IDs, crafted stats) via `SetHyperlink`; never re-derivable from `itemID` alone. |
| `itemName` | Denormalized name — backs text search and display without a cache lookup. |
| `quality` | Numeric `Enum.ItemQuality` (0 Poor … 5 Legendary; Heirloom/Artifact also occur and show up in the filters and Insights). Denormalized for fast filter/sort and the quality breakdown. |
| `itemLevel` | Effective item level for equippable items; `nil` otherwise. |
| `bound` | Bind state: `nil` \| `"BOE"` \| `"BOP"` \| `"WARBAND"` \| `"WARBAND_UE"` (warbound until equipped). |
| `vendorPrice` | Vendor sell price in **copper, per unit** (captured at loot time — not market price). Renamed from `sellPrice` by the v2→v3 migration (see below). Half of the "value" comparison — see `Util.RecordValue` below. |
| `auctionPrice` | **Nested map** `provider → key → copper` (e.g. `{ tsm = { dbmarket = 41200 }, oribos = { market = 40800 } }`), captured at loot time by `NS.AuctionPrice:GatherAll` (`modules/AuctionPrice.lua`) — every configured capture key from every installed pricing addon (Auctionator / TSM / OribosExchange), not just one. **`nil`** when nothing was captured (no pricing addon installed, item unpriced, the capture set is empty, or every provider errored). A single price for display/comparison is chosen at *read time* by `NS.AuctionPrice:Pick(map)`, which walks the user's configured priority list and returns the first key present (`price, tag`); it is never re-priced after capture — the map is a point-in-time snapshot, not a live market feed. There is no `priceSource` record field: `Pick`'s `tag` return *is* the provenance, computed on read, not stored. |
| `itemType` / `itemSubType` | Localized item class / subclass strings (e.g. `Armor` / `Cloth`); back the type breakdown and the type filter. |
| `quantity` | Stack size for this loot event (the `%d` from `CHAT_MSG_LOOT`; `1` for the singular line). |
| `source` | `SourceType` enum key (see below) — how the item arrived, resolved by the attribution engine. See [data-flow.md](./data-flow.md). |
| `sourceDetail` | Optional, source-specific context table (`npcID` / `encounterID` / `difficulty` / `keystoneLevel` / `questID`). Stored for the export and the M+ keystone breakdown; **not displayed** in the Source column. |
| `zone` | Human-readable zone label at loot time. |
| `mapID` | Stable numeric map id at loot time. Recorded and exported, but **not** a grouping or filtering key: one named zone spans many UiMapIDs (each dungeon floor and sub-map has its own), so grouping by it splits a zone. `zone` is the key everything user-facing uses. |
| `subzone` | Optional finer sub-area string. |
| `confidence` | `Confidence` enum key — `CERTAIN` when a live source stamp was adopted, `INFERRED` on the `OTHER` fallback. |

The denormalized item fields (`itemID`, `itemName`, `quality`, `itemLevel`, `bound`, `vendorPrice`, `auctionPrice`, `itemType`, `itemSubType`) exist so the [browser](./browser.md) table can filter/sort/group thousands of rows without touching item links or the item cache; `itemLink` remains the source of truth for the tooltip.

### Derived value — `Util.RecordValue`, never stored

There is **no `value` field on the record.** Every "worth" figure — the Insights Value breakdown,
the browser's Value column, the CSV export — computes it on read via `Util.RecordValue(record)`
(`core/Util.lua`):

```lua
function Util.RecordValue(record)
  if record == nil then return nil end
  local a = record.auctionPrice and NS.AuctionPrice:Pick(record.auctionPrice) or nil
  local v = record.vendorPrice
  if a and v then return math.max(a, v) end
  return a or v
end
```

`AuctionPrice:Pick` resolves the nested `auctionPrice` map down to a single copper figure via the
user's configured priority list (first present key wins). The map only ever holds *collected* keys
(collection and priority-participation are one flag now — `settings.auction.capture`), so `Pick`
simply returns the highest-ranked source that has a price; `RecordValue` then takes the **higher of**
that picked auction price and `vendorPrice` — a valuable item never reads as worth less than what a
vendor would pay for it. `nil` only when both `vendorPrice` and every captured auction price are
`nil`. Aggregate worth is always `RecordValue(r) * quantity`, never `RecordValue(r)` alone.

Filtering is point-in-time: a row rescued by the whitelist (it failed the normal collection gate but its item id was whitelisted) is written as a plain record, indistinguishable from any other — there is no per-record marker for how it got in, and no field is stripped from `Database:Export`.

## Storage: a dense array

All history lives at `LootHistoryDB.global.history` — an account-wide dense array (see [schema.md](./schema.md)). `Database:Add` (`core/Database.lua:411`) appends one record and fires `Ka0s_LootHistory_RecordAdded`; that is the only write path during normal play.

### Rebuild-and-swap on delete

Deletion never leaves holes — every predicate/bulk path **rebuilds a fresh array and swaps it in**:

- `Database:Delete(pred)` (`core/Database.lua:863`) — keep everything where `pred(r)` is false.
- `Database:PruneOld()` (`core/Database.lua:950`) — retention cleanup; drops records older than the account-wide `retentionDays` (`0` == keep Always), gated once per session.
- `Database:RepairBoundStates()` (`core/Database.lua:382`) — the deferred warbound-state split; upgrades under-classified rows in place and fires `HistoryChanged` when it changes any.
- `Database:Purge()` (`core/Database.lua:882`) — replace with `{}`.

Each of these assigns a new table to `NS.db.global.history` and fires `Ka0s_LootHistory_HistoryChanged`, avoiding both O(n²) shifting and array holes. Because records carry no metatables, the swap is a plain value move.

## Enums

### SourceType

`Constants.SourceType` (`core/Constants.lua:8`) — the stored `source` values. **String keys are the export contract: do not rename them.** Extending the enum is forward-compatible.

```
KILL · CONTAINER · MAIL · TRADE · AH · QUEST · VENDOR · CRAFT · ROLL
BONUS_ROLL · MPLUS · REFUND · OTHER · DISENCHANT · MILLING · PROSPECTING
```

Companion tables in the same file: `SourceOrder` (display order for grouping/analytics, `core/Constants.lua:17`) and `SourceLabel` (short UI labels, `core/Constants.lua:24`).

`SOURCE_IMPLEMENTED` (`core/Constants.lua:37`) marks the sources with a **live capture path**; it gates the per-source mute UI. Every source now qualifies, so all appear in the option list — the enum stays whole because it is the export contract. See [data-flow.md](./data-flow.md).

### Currency records

A currency loot is stored as a history record with `currencyID` (the structural signal),
`itemType = "Currency"`, `itemSubType = <live currency category>`, `itemName` (currency name),
`quantity`, `quality` — the currency's **own** `C_CurrencyInfo` quality tier — and `bound`, both
captured at loot time. `quality` drives the History table's Name-cell color and fills the Quality
column for currency rows the same way it does for items, and hovering a currency row shows the in-game
currency tooltip (`GameTooltip:SetCurrencyByID`). `bound` is `"WARBAND"` for a Warband-transferable
currency (`C_CurrencyInfo.isAccountTransferable`) and `"BOP"` otherwise, driving the Bound-column lock
glyph. The remaining item-only fields (`itemID`, `itemLink`, `itemLevel`, prices) remain nil.
`itemID == nil && currencyID ~= nil` distinguishes a
currency row. Currency is excluded from every **LOOT** chart — the item-attribute charts
(quality/ilvl/bound/type/top-items) *and* the Loot-by-source / value / per-character charts — so
per-character totals tally across the section; it drives its own **CURRENCY** sections instead (under a
dedicated divider below the **LOOT** divider — see [browser.md](./browser.md)). Currency still counts
in the time/activity strips (`byDay`/`byHour`/`byWeekday`/`byZone`) and the headline `records`/`characters`
KPIs. `Database:Stats` computes these off the same filtered pass as
the item stats: `byCurrency` (qty per currency name), `currencySourceMatrix` (currency name →
source → qty), `currencyCharMatrix` (character → currency name → qty — feeds the **Currency by
Character × Type** stacked chart), `currencyBySource` (source → total qty summed across every
currency — its in-dashboard chart was removed but the aggregate is still computed),
`currencyByChar`, `currencyByDay`, and `currencyTotals`
(`distinct`, `events`, `biggestHaul`).

`Database:Stats` also computes five per-character × category matrices (`char → category → magnitude`)
that back the "… by Character" stacked companion charts, **all items-only**: `charBySource`,
`charValueBySource`, `charByQuality`, `charByType`, `charByBound`. `byChar` registers every character
(for the class-color lookup and the `characters` KPI) but its `count`/`value` are items-only, so a
currency-only character is registered with `count = 0` and is skipped by "Loot by character".
(`byKeystone`/`byConfidence` feed the Export only — their dashboard charts and per-character companions
were removed.)

### Confidence

`Constants.Confidence` (`core/Constants.lua:44`): `CERTAIN` \| `INFERRED`. Surfaces attribution uncertainty in the UI and lets the export flag inferred rows.

> Not part of the record, but related: `Constants.ITEMCLASS_QUEST = 12` (`core/Constants.lua:48`) is the locale-independent `Enum.ItemClass.Questitem` id the collector's optional quest-item gate keys on — never the localized `itemType` string.

## The `Schema:Set` write seam

Every user *setting* mutation flows through one seam: `Schema:Set(path, value)` in `settings/Schema.lua:735` — validate → deep-copy → write to the active profile (`NS.db.profile`), or through the row's own `set` for the three stored rows that live in `db.global` (`minimap.shown`, `settings.retentionDays`, `settings.rollupRetentionDays`) → fire the row's `onChange`. Since LibKa0s v1.55.0 the seam is **`LibKa0s-Schema-1.0`**'s: `settings/Schema.lua` builds one runtime instance (`NS.SchemaRuntime`) over this addon's rows and keeps every host name (`Schema:Set`, `:Get`, `:FindRow`, `:Default`, `:ApplyDefault`, `.BulkBegin`, `.BulkEnd`, `:Register`) as a one-line delegate, so no call site moved. The descriptor supplies where a stored row lives (`resolveRoot`, `NS.db.profile`, asked at call time so a profile switch retargets the next read and write), the debug sink, the minimap and retention rows' sweep exemption and this addon's refusal words (`unknown path: <path>`, `invalid value`). With the library absent, a write-completing, log-silent stub in the same file keeps every read and write working. `settings/Schema.lua` holds one row per setting and is the single source of truth for the AceDB default, the panel widget, and the slash get/set/list/reset behavior (see [settings-panel.md](settings-panel.md) and [slash-dispatch.md](slash-dispatch.md)). Paths resolve against the active profile; the three stored rows outside it own their storage through their own `get`/`set`: `minimap.shown` over the global LibDBIcon table (`db.global.minimap.hide`), `settings.retentionDays` over `db.global.retentionDays` and `settings.rollupRetentionDays` over `db.global.rollupRetentionDays`. The resolved library is `NS.SchemaLib`, and the boot check `Schema:Register` is its `Validate`: row shape (`group`, `type`, no duplicate path) plus path resolution against `defaults/Profile.lua`.

The deep-copy (the library's, on every stored write) matters for the two table-valued settings (`excludedSources`, and any reset that passes a schema `default` table): without it, a write would alias the DB to a shared default table and let an in-place mutation poison the default for the rest of the session.

**`writeThrough`: the one path stored without a row.** The descriptor also lists `writeThrough = { "settings.enabled" }` (`LibKa0s-Schema-1.0` minor 2; `options-ui-§1` route (a)). It is data only: no row, label, default or validate. On a full load the Master controls composer declares `settings.enabled`, and **a path with a row always takes the row**, so the checkbox and `/lh enable`/`disable` are validated and reach the row's `onChange` (the latch, then `SettingsChanged`) as before. On a load with the library absent, the Options stub's `MasterControls` composer is hollow and emits no row, and without the list the seam would answer that write `unknown path`. With it, the degradation stub (`hostSchemaStub`, the same file) stores a listed row-less path the way the library does: the root resolved (`nowhere to store` before `InitDB`), the value copied in, **no validate and no `onChange`**, `true`. A caller that needs the reaction runs it itself after the write: the library-less Slash stub's `CliSet` (the degraded `/lh enable` / `disable`) calls `NS.Schema.OnEnabledWritten()`, the same function the row's `onChange` calls on a full load. Every other row-less path is still refused. The stub also carries minor 2's `SetMany` (all or nothing: every entry, a written-through one included, is prepared before anything is stored, and the first refusal answers `false, err, nil, index`) and forwards the instance id from `Get` to a row's `get` and from `ApplyDefault` to `Set`; no row in this addon reads the id. `tests/test_schema_stub.lua` pins each on a real degraded load.

### The rows

A row's `page` is the canvas subcategory it is edited on, its `group` is the tab within that page (options-ui-§13), its optional `subgroup` is a subsection heading inside a tab (options-ui-§7), and its `path` is where the value is stored: four independent facts. Every row today is on the General page, and the sixth tab, Filters, holds none. How the page draws them is in [settings-panel.md](settings-panel.md).

| Path | Page ▸ Tab | Widget | Default | Notes |
|---|---|---|---|---|
| `settings.enabled` | General ▸ Master controls | CheckBox | `true` | The addon-wide switch. Its `onChange` calls `S.OnEnabledWritten`, which calls `NS.OnEnabledChanged`, which takes or releases the `disabled` hold on the one `LibKa0s-Lifecycle-1.0` latch — so writing this path is what actually stands the addon down or back up (slash-commands-§7). Fires `SettingsChanged` second, after a stand-up has rebuilt the subscriptions. |
| `settings.visibility` | General ▸ Master controls | Dropdown | `"always"` | `always` / `inCombat` / `outOfCombat` / `never`. Honored by `Browser:VisibilityAllows` — `B:Show` refuses, and the two combat transitions hide a window the setting has stopped allowing. Never opens the window by itself. |
| `settings.scale` | General ▸ Master controls | Slider (0.5–2, step 0.05) | `1.0` | **Addon-wide.** `Browser:ApplyChrome` multiplies it by `settings.windowScale` for the History window; the export modal takes it alone. |
| `settings.alpha` | General ▸ Master controls | Slider (0–1, step 0.05) | `1.0` | **Addon-wide** opacity, same two frames. |
| `settings.locked` | General ▸ Master controls | CheckBox | `false` | Gates both `OnDragStart` handlers (History window title bar, export modal title bar) rather than un-setting `SetMovable`. |
| `state.debugConsole` | General ▸ Master controls | CheckBox | `false` | **Session-only** (`sessionOnly`): shows/hides the debug console; never persisted (`get`/`set` proxy `NS.DebugLog`). Moved here from Interface. |
| `minimap.shown` | General ▸ Master controls | CheckBox | `true` *(the row's sense)* | The LibDBIcon button's visibility, composed from `minimapPath` (launcher-§3, standard v2.65.0). **The CLI path is `minimap.shown`, in the row's own sense; the one stored key is `minimap.hide`**, LibDBIcon's own, and no `shown` key is ever stored (anti-pattern #81), so its `get`/`set` invert at `Schema:Set` — one of the two **stored** rows with accessors of its own, beside `settings.retentionDays` — and the `set` calls `NS.Launcher:SetShown`, which moves the button immediately rather than at the next reload. `defaults/Global.lua` ships `hide = false`, which is the same fact in the other sense. The path carries no `settings.` prefix because LibDBIcon's table lives in the global store, outside the block's. It replaced the Interface tab's **Hide minimap button**. **Exempt from every bulk reset** (launcher-§3, standard v2.54.0): `NS.Schema.RESET_EXEMPT` names it once, as a map from the row path to the stored path (its entry is `["minimap.shown"] = "minimap.hide"`): `Schema:ApplyDefault` skips the row path while a bulk bracket is open, and *Reset all settings* is a profile reset that cannot reach the global table at all. Because the row owns its storage (its own `get` and `set`), `Schema:Register`'s defaults check skips it rather than looking for a `shown` default. A single `/lh reset minimap.shown` still resets it — that is the player naming the row. |
| `state.testMode` | General ▸ Master controls | CheckBox | `false` | **Session-only**: the History window's test mode, composed from `testModePath`, pairing beside **Minimap button**. `get` reads `BrowserTable.testMode`; `set` switches through `BrowserTable:SetTestMode` only when the value differs. Never persisted. The same switch as `/lh test`; combat, Reset all settings and `/lh resetall` end it. |
| `settings.qualityThreshold` | General ▸ Capture | Dropdown | `1` (Common+) | Minimum quality to record. Fires `SettingsChanged`. |
| `settings.recordCurrency` | General ▸ Capture | CheckBox | `true` | Record looted currency as `Type=Currency` rows; obeys the per-source mute list, ignores the quality filter. Fires `SettingsChanged` (`"currency"`). |
| `settings.trackLedger` | General ▸ Capture | CheckBox | `true` | "Track holdings and losses": keeps `db.global.holdings` current (and, from Phase 2, writes gain/loss/transfer rows). Off = loot gains only, as before. Fires `SettingsChanged` (`"ledger"`), which the Reconciler hears to register or drop its capture events. |
| `settings.excludeQuestItems` | General ▸ Capture | CheckBox | `true` | Drop Quest-class items at capture (gates on `Constants.ITEMCLASS_QUEST`, locale-independent). Fires `SettingsChanged`. |
| `settings.excludedSources` | General ▸ Capture | MultiCheck | `{}` | Stored as *muted* sources; panel renders inverted ("Record data from"), host-drawn from `afterGroup`. Fires `SettingsChanged`. |
| `settings.auction.enabled` | General ▸ AH Price ▸ *Pricing* | CheckBox | `true` | Master switch; `false` short-circuits the capture path (`GatherAll` gathers nothing), so new drops store no auction map — already-stored records are unaffected. |
| `settings.auction.capture` | General ▸ AH Price ▸ *Price sources* | MultiCheck (`skipRender`) | `Constants.AUCTION_CAPTURE_DEFAULT` | The single collect-**and**-rank flag per `"provider:key"` source. Schema-backed for the default/slash CLI, rendered as the price table's per-row Enabled checkbox. It also **declares the "Price sources" heading** — `startSubgroup` runs before the `skipRender` check. |
| `settings.windowScale` | General ▸ Interface | Slider (0.6–1.6, step 0.05) | `1.0` | The History window's OWN scale, multiplied by `settings.scale` (applied live). |
| `settings.rowHeight` | General ▸ Interface | Slider (14–28, step 1) | `18` | History-table row height in pixels; was `local ROW_H = 18` in `modules/BrowserTable.lua`. Clamped on read (`BrowserTable.RowHeight`) because the value comes from SavedVariables. Re-binds the table on change. |
| `settings.timelineMaxLines` | General ▸ Interface | Slider (2–16, step 1) | `8` | How many holders the Timeline draws as their own line besides the Total. The richest holders of the charted thing win the slots, after the Character filter has narrowed the field. Per profile. |
| `settings.retentionDays` | General ▸ History | Dropdown | `30` | **Account-wide, not per profile** (owner decision D6): its own `get`/`set` read and write `db.global.retentionDays`, declared in `defaults/Global.lua`, so a profile switch, copy or reset never changes it, and its tooltip says so. `NS.Schema.RESET_EXEMPT` maps it to that key, so no bulk reset reaches it and the profile reset's count leaves it out; a single `/lh reset settings.retentionDays` still resets it, through the same confirm. `0` = keep Always. A change that would delete records asks first (`KA0S_LOOTHISTORY_PRUNE`); **No** restores the previous value. The tab's other two controls — the storage readout and **Purge history…** — are bespoke and have no path. |
| `settings.rollupRetentionDays` | General ▸ History | Dropdown | `0` | **Account-wide, not per profile**, for the reason `settings.retentionDays` is: its own `get`/`set` read and write `db.global.rollupRetentionDays` (declared in `defaults/Global.lua`), and `NS.Schema.RESET_EXEMPT` maps it to that key, so no bulk reset reaches it and the profile reset's count leaves it out. `0` = keep Always (the default); the options are `C.ROLLUP_RETENTION_OPTIONS`, with longer floors than the history's because a day is a few bytes. **No confirm:** changing it deletes nothing on the spot; the prune runs once per session from the login deferral, so a shorter window takes effect at the next login, and the tooltip says so. |

### State outside the rows

Several pieces of persisted state, in both scopes, are not schema rows, so nothing writes them through `Schema:Set`, and only one of them is a carve-out. `architecture-§5` sorts the rest into **named non-setting state**, which no control chooses and no row addresses, and a **structural registry**. Neither needs a register row once its owner and writers are named, and [*Named non-setting state*](#named-non-setting-state-owners-and-writers) and [*The id filter sets*](#the-id-filter-sets-a-structural-registry) below name them (for the window, so does the NOTE above `SaveWindow`, `modules/Browser.lua:92`):

- **`settings.window`** (profile) — named non-setting state: the browser window geometry `{ point, x, y, w, h }` relative to UIParent, which only a drag or a resize determines. Saved by `SaveWindow` on move/resize (`modules/Browser.lua:97`), restored by `RestoreWindow` on show (`modules/Browser.lua:106`). This is the standalone-windows window position/size persistence.
- **`savedView`** (profile) — named non-setting state: the saved table view, captured whole when the player clicks the filter bar's **Save**: group-by, sort keys, and the multi-select column filters (bound / quality / type / subtype / source / zone) plus the date range and search text. Captured by `B:CaptureView`, written by `B:SaveView`, cleared to `nil` by `B:ResetView`. Character scope is **not** part of the view — it is a session-only "current player" default. When `savedView` is absent, `savedViewOrStock` returns the hard-coded `STOCK_VIEW` baseline (`modules/Browser.lua:251`). **It may now be materialized without a Save:** picking a thing on the Timeline (or **Show in Timeline** from a row) calls `B:SetViewField("timelineThing", key)`, which, when no view is stored yet, first writes a *copy of the stock view* and then sets the field, so the remembered pick survives `/reload` and a later Reset or Save sees nothing but the same stock values. `savedView.timelineThing` is the thing key (`"g"`, `"c:<id>"`, `"i:<id>"`), default `"g"`; `B:CaptureView` carries it through a Save.
- **`history`** (global) — named non-setting state, **recorded data**: the loot log, owned by `NS.Database` (`core/Database.lua`). The player deletes rows of it or clears it but never authors a row. Beside it sits the deferred warbound repair's bookkeeping, **`boundRepairPending`**, **`boundRepairAttempts`** and **`boundRepairRevision`**: recorded data with the same owner, which the load pass arms (see [schemaVersion & the migration seam](#schemaversion--the-migration-seam)). [*Recorded data*](#recorded-data-history-and-the-repair-bookkeeping) below lists every writer.
- **`blacklist` / `whitelist` / `currencyBlacklist`** (profile) — the id filter lists (issue #14; the currency list added with currency capture). They are a **structural registry** (`architecture-§5`): the player adds and removes members and no row names one, so they are written by their one registry writer, `NS.Filters` (`modules/Filters.lua`), rather than through `Schema:Set`. That is compliant and needs no register row; the storage keys, the writer and the load pass (the v8→v9 move, once) are named in [*The id filter sets*](#the-id-filter-sets-a-structural-registry) below. The writer's callers are the Filters tab (`settings/Panel.lua:226-310`), the History right-click menu (`modules/BrowserTable.lua:1192`, `:1173`), and the Clear-all confirms (`settings/Slash.lua:53-87`). The global reset (`Sl:CliResetAll`, `settings/Slash.lua:435`, reached by `/lh resetall`, the General page's **Defaults** button and **Reset all settings**) also empties the sets, because it resets the whole profile, and `architecture-§5` does not count wholesale replacement as a registry write. Copy-on-write mutation, then a direct `Collector:RefreshUpvalues()` re-cache + `Database:FireHistoryChanged()` (the browser re-queries). All are strictly **point-in-time**: they decide what happens at capture, not what happens to rows already stored. Blacklisted item ids are dropped at capture (`CHAT_MSG_LOOT`) and never written to `history`; existing rows are never hidden or removed. Whitelisted ids are always recorded, bypassing the quality/source/quest gates, as plain rows with no special flag. `currencyBlacklist` is keyed by **currencyID** (a separate namespace, since item and currency ids can collide) and is **blacklist-only** (no currency whitelist): a blacklisted currency is dropped at capture (`CHAT_MSG_CURRENCY`). Changing any list fires `Database:FireHistoryChanged()` and calls `Collector:RefreshUpvalues()` so the browser/Insights re-query and future captures see the new lists — it never hides or reveals existing rows. An item id lives on at most one of the item lists. See [settings-panel.md](settings-panel.md).
- **`settings.auction.priority`** (profile) — **the one carve-out**, with a register row under [ARCHITECTURE.md → *Documented deviations*](ARCHITECTURE.md#documented-deviations): the ordered `"provider:key"` AH-price cascade selection list (`AuctionPrice:Pick` walks it front-to-back; first present key wins). An ordered list has no fixed Schema widget (CheckBox/Dropdown/Slider/MultiCheck) to express reordering, so it is read/written directly via `AuctionPrice:GetPriority` / `ReconcilePriority` / `MovePriorityWithin` (`modules/AuctionPrice.lua`) and **dragged** on the AH Price tab through the shared `ReorderList` widget (options-ui-§18). `MovePriorityWithin(subset, from, to)` is a **splice to index** — one write, however far the row traveled — and re-lays the dragged subset into its own slots in the stored array, so reordering the sources you collect never moves the ones you do not. It replaced the pairwise `SwapPriorityTags` the old ▲▼ arrows drove, which is gone. Its sibling `settings.auction.capture` (now the single collect-**and**-rank flag per source) **is** a normal Schema row (`MultiCheck`, `settings/Schema.lua`) — only the ordering half is a carve-out. (There is no longer a separate `priorityDisabled` set: collection and priority-participation are one flag — an unticked source is neither collected nor ranked.)

`minimap` (global) is not on that list because LibDBIcon owns it: `NS.Launcher:Register()` (`core/LauncherSetup.lua`) hands the table to LibDBIcon and the library keeps the button's state in it, storing `minimapPos` when the button is dragged. Only its `hide` leaf is a schema row. Setup does not seed the table when it is missing (#30): replacing the whole table would be a write over the `minimap.shown` row's stored `hide` key, and the AceDB default (`defaults/Global.lua:27`) already supplies it. The table is **global** (launcher-§3), so no profile event and no reset replaces it: the button keeps the table it was handed at `Register`, its visibility and its dragged position survive *Reset all settings* and the page's **Defaults** button, and a profile switch neither moves nor hides it.

> **Standards note (accepted carve-out).** `settings.auction.priority` bypasses the schema-as-single-source rule (`architecture-§5`: every write to a schema-row path goes through `Schema:Set`, and any other persistent state written outside it needs a register row). It carries one, in [ARCHITECTURE.md → *Documented deviations*](ARCHITECTURE.md#documented-deviations). **`window` and `savedView` are no longer in this class.** Standard v2.44.0 calls geometry only a drag determines, and a view captured whole by a *Save* act, **named non-setting state**. Neither needs a row once its owner and writers are named, and LibDBIcon's `minimapPos` falls under the same rule's library clause. [*Named non-setting state*](#named-non-setting-state-owners-and-writers) names all three, so `window` and `savedView` left the register on 2026-09-12 (#30); `minimapPos` was never in it. **The id sets are no longer in this class either.** They were ratified as a carve-out on 2026-07-17. Standard v2.43.0 then called a player-built id set a **structural registry**, compliant when it has one named writer. `NS.Filters` is that writer and the load pass is none (AceDB defaults only), so the sets left the register on 2026-09-12. `settings.auction.priority` follows the older precedent (Rev-2 R5, 2026-07-19): an ordered list is not one of the four schema widget types, so it is managed directly by `modules/AuctionPrice.lua` + the AH Price panel. (The former `settings.auction.priorityDisabled` per-tag carve-out was removed when collection and priority-participation were unified into the single `settings.auction.capture` flag — see the AH Price table in [settings-panel.md](settings-panel.md).) Standard v2.43.0 made the id-set pattern first-class, as a registry with one named writer. The ordered-list pattern still has no schema row type, and that is the register row's re-check trigger.

Note `settings.windowScale` **is** a Schema row (a General ▸ Interface ▸ *Window* slider, beside `settings.rowHeight`) even though `settings.window` is not — the scale is a user-facing setting, the geometry is runtime state. The geometry is still reachable from the panel, through the Master controls tab's **Reset position** button (`Browser:ResetWindow`), which is an act rather than a setting.

### Named non-setting state: owners and writers

Three more pieces are **named non-setting state** (`architecture-§5`): no control chooses their
values and no row addresses them, so they are written outside the helper with no register row. Each
has one owner, `NS.Browser` (`modules/Browser.lua`), and every writer is listed with the act that
reaches it.

- **`NS.db.profile.settings.window`**, the window geometry `{ point, x, y, w, h }`. The local
  `SaveWindow` (`:97`) writes it when a title-bar drag stops (`:975`) and when a resize ends
  (`:1063`, the `onResizeStop` the browser hands `Core.MakeResizable`, which runs once per release
  of a sizing the grip started and never after a press Lock frame refused). `B:ResetWindow` (`:680`) writes `{}`, reached from the Master controls
  **Reset position** button (`onResetPosition`, `settings/Schema.lua:120`). A profile reset brings
  it back with the rest of the profile, and every profile event re-reads it (`B:AdoptProfile`,
  `:695`).
- **`NS.db.profile.savedView`**, the remembered view. `B:SaveView` (`:663`) stores the whole
  `B:CaptureView()` when the player clicks the filter bar's **Save** (`:770`). `B:ResetView`
  (`:671`) clears it to `nil` (and with it the remembered Timeline thing), reached from the filter bar's **Reset** (`:767`). A profile reset
  clears it with the rest of the profile. The load pass reshaped it while it still lived in global
  (migrations `to = 6` and `to = 8` in `core/Database.lua`) and then moved it into the profile
  (`to = 9`).
- **`NS.db.global.minimap`**, apart from its `hide` row. `NS.Launcher:Register()`
  (`core/LauncherSetup.lua`) hands the table to LibDBIcon and writes nothing to it, since the AceDB
  default (`defaults/Global.lua:27`) supplies it. The one writer is the library: dragging the minimap
  button stores `minimapPos` (`libs/LibDBIcon-1.0/LibDBIcon-1.0.lua:194`). The addon never calls the
  library's `Lock`, `Unlock` or compartment functions, its only other writes into the table. The
  scope is **global** and launcher-§3 fixes it there: a profile switch must not move a player's
  buttons, and no reset reaches it either.

### The id filter sets: a structural registry

The id filter sets are a structural registry (`architecture-§5`): the player adds and removes ids,
the defaults ship the sets empty, and no schema row or whole-value path names them, so they need no
register row while only the writer and load pass named here touch them. Their storage keys are
`NS.db.profile.blacklist` and `.whitelist` (`{ [itemID] = true }`) and `.currencyBlacklist`
(`{ [currencyID] = true }`), declared empty in `defaults/Profile.lua:16-18`, so every profile has its
own three. Their one writer is `NS.Filters` (`modules/Filters.lua`), whose per-id and clear verbs
are called by the Filters tab, the History right-click menu and the Clear-all confirms, none of
which writes the sets itself. Their load pass is the v8→v9 step (`moveSettingsToProfile`,
`core/Database.lua:47`), which moved each stored set out of `db.global` into the `Default` profile
once; nothing else in `MIGRATIONS` touches them, and a profile created later is seeded by the AceDB
defaults.

### Recorded data: `history` and the repair bookkeeping

[*State outside the rows*](#state-outside-the-rows) names both as recorded data;
this is the writer list. The player deletes rows of the log or clears it, but never authors a row.
Its one owner, `NS.Database` (`core/Database.lua`), holds every writer. `Add` (`core/Database.lua:411`)
appends each kept loot or currency line (`modules/Collector.lua:175`, `:240`). `PruneOld`
(`core/Database.lua:950`) drops rows past the account-wide `retentionDays` once per session after
`PLAYER_ENTERING_WORLD` (`core/LootHistory.lua:130`) and when the player accepts the prune confirm
that row's `onChange` raises (`S:OnRetentionChanged`, `settings/Schema.lua:814`). `Purge` (`core/Database.lua:882`) empties it from the purge confirm
(`settings/Slash.lua:13`) that `/lh purge` and **Purge history…** open, or directly with no
`StaticPopup_Show` (`settings/Schema.lua:1054`, `settings/Panel.lua:113`). `Delete`
(`core/Database.lua:863`) drops the row the History right-click **Delete** names
(`modules/BrowserTable.lua:1207`). `RepairBoundStates` (`core/Database.lua:382`) rewrites a row's
`bound` (`core/Database.lua:339`) from two deferrals after login (`core/LootHistory.lua:138`, `:142`)
and each window open (`modules/Browser.lua:1081`). No settings reset and no profile event reaches
it: the history is account-wide and outside every profile. Purge and delete each log one `[Data]`
line, the prune one `[Prune]` (`debug-logging-§8`).

The repair bookkeeping is the deferred warbound repair's job state (see
[schemaVersion & the migration seam](#schemaversion--the-migration-seam)). **`boundRepairRevision`** is
written only by the load pass: `NS:ArmBoundRepair` (`core/Database.lua:270`), which only
`NS:RunMigrations` calls, stamps it when it arms the job, setting **`boundRepairPending`** and clearing
**`boundRepairAttempts`** (`core/Database.lua:275`). After that the repair's `finishPass`
(`core/Database.lua:365`) advances `boundRepairAttempts` and clears both once nothing is pending or
the fruitless-pass cap is reached. The defaults declare none of the three.

### The ledger stores

The timeline ledger (spec `docs/superpowers/specs/2026-10-06-timeline-ledger-design.md` §4) adds four pieces of account-wide state beside `history`. All four are `db.global`, outside every profile, and no settings reset reaches them. `core/Ledger.lua` holds the pure primitives (thing keys, `Diff`); `NS.Holdings` (`modules/Holdings.lua`) owns `holdings`.

```lua
db.global.holdings = {            -- one writer: NS.Reconciler, through the NS.Holdings Apply* calls
  ["Ka0z-Ravencrest"] = {         -- NS.Util.PlayerKey(); the Warband is the literal key "§warband"
    meta    = { genesis = <ts>, lastSeen = <ts>, partial = <bool>, completeAt = <ts|nil>, classFile = "MAGE" },
    scanned = { bags = <ts>, equipped = <ts>, bank = <ts>, money = <ts>, currency = <ts> },
    items   = { [itemID] = { bags = 12, bank = 40 } },   -- count per container (bags / equipped / bank / mail / auctions / tabs)
    currency = { [currencyID] = quantity },
    links   = { [itemID] = "|cff...|Hitem:...|h[Name]|h|r" },  -- the last link seen, for display
    money   = <copper>,           -- gold
    escrow  = { mailOwn = {}, mailMoney = 0, exits = {} },  -- created on first use (see below)
  },
  ["§warband"] = { ... },         -- tabs (warband bank), warband gold, account-wide currency
}
db.global.daily      = {}         -- ["YYYY-MM-DD"][holder][thingKey] = { c, i, o } (close, gained, lost): created empty at v11, written since Phase 3
db.global.rollupRetentionDays = 0  -- 0 = keep every day; declared in defaults/Global.lua (reset-exempt, account-wide)
db.global.rollupSeeded = <ts|nil>  -- stamped once when the first seed ran; deliberately undeclared
db.global.ledgerSince = <ts>      -- when capture began; a Reset from the popup restamps it
db.global.resetPrompt = nil | "reset" | "kept"   -- the answer to the one-time popup
db.global.resetPromptPending = nil | true      -- armed by the v11 step when history existed; the popup's Keep/Reset and a purge clear it
```

- **Keys.** Container ids are derived from `Enum.BagIndex` member names, never hardcoded numbers. A thing key is `"i:<itemID>"`, `"c:<currencyID>"` or `"g"` (gold) (`Ledger.ThingKey` / `ParseThingKey`). `§` marks a system holder: code that means "characters" skips keys that start with it.
- **`scanned` is the staleness clock.** A container never read has no timestamp, and the Holdings tab shows it as "never". `meta.partial` is true until the holder's bank (or, for the Warband, its tabs) has been read once, so a first-login character is not presented as owning an empty bank.
- **Row fields written since Phase 2.** A ledger row carries `dir` (`IN` / `OUT` / `MOVE`), `kind` (`ITEM` / `CURRENCY` / `GOLD`), `holder` (whose holdings it belongs to: a `PlayerKey` or `"§warband"`), `from` / `to` (the two ends of a `MOVE`, each `holder/container`, for example `Ka0z-Ravencrest/bags` to `Ka0z-Ravencrest/bank`, or `Alt-Realm/mail`, `Alt-Realm/currency`, `Ka0z-Ravencrest/auctions`) and `claimed` (true when a chat line wrote the row and the diff then confirmed it). `quantity` stays **unsigned**; the sign is `Ledger.DirSign[dir]` (`Ledger.Signed`), and a `MOVE` signs as zero. Every reader goes through `Util.RowDir` / `RowKind` / `RowHolder`, which default an unmarked row to a gain by `char`, so no pre-ledger row was rewritten.
- **The GOLD row shape.** `kind = "GOLD"`, `itemName = "Gold"`, `itemType = Constants.GOLD_TYPE` (`"Gold"`), `quantity` in **copper**, no `itemID`, `itemLink`, `quality` or price fields. A looted-gold row also carries `source` / `sourceDetail` / `zone` from the loot context (and `claimed = true` once the diff confirms it); a diff-written one has `source` = the reason (`SELL`, `REPAIR`, `MAIL_SEND`, ...).
- **A ledger row's `source` is its reason.** Item and currency diff rows reuse the `source` column for the reason (`SourceType`, appended 2026-10-06 with the 18 ledger members in `C.LEDGER_REASON`), with `confidence` `INFERRED` for `OTHER` / `UNTRACKED` and `CERTAIN` otherwise. A `MOVE` row's reason is `TRANSFER` (or the pair's own, for example a mail money move).
- **Escrow.** `holdings[h].escrow` is created on first use by `Holdings:Escrow(h)`. `mailOwn[itemID]` counts how much of that holder's inbox it (or another own character) sent, so taking it is a `MOVE` and not a gain; `mailMoney` is own-origin copper waiting in the inbox; `exits[itemID] = { n, ts }` is what left the owned-auction list and has not yet resolved (returned by mail, sold, or aged out after 30 days). Written only by `modules/Escrow.lua`'s commit step; see [data-flow.md](data-flow.md#the-ledger-holdings-diff--claims).
- **Settings the ledger reads.** `settings.trackLedger` (the capture switch), `settings.recordGold` (default on: gold gains and losses become rows; holdings count gold either way) and `settings.showTransfers` (default off; on adds `MOVE` to History's default Direction filter). `settings.qualityThreshold` is relabeled **Minimum quality (detailed records)** (F5, 2026-10-06): it gates the detailed chat-written rows and History's default view floor, not what the ledger counts; see [scope.md](scope.md). All three new rows ship in `defaults/Profile.lua` and `settings/Schema.lua`.
- **`ledgerSince`, `resetPrompt` and `resetPromptPending` are deliberately not declared in `defaults/Global.lua`.** AceDB strips a stored value equal to its default and backfills a declared default onto old accounts; an undeclared `nil` means "never decided" on an account that was upgraded and "not applicable" on a new one.
- **The reset popup** (`KA0S_LOOTHISTORY_LEDGER_RESET`, `settings/Slash.lua`) is offered once, about five seconds after login, when `resetPromptPending` is set (the v11 step arms it on an upgrade that carried history, and it is persisted so it outlives the load that migrated), the history is non-empty and `resetPrompt` is `nil`. **Keep** stores `"kept"`. Esc stores nothing, so the next login asks again. **Export first** opens the export window and re-asks when it closes (a stand-down drops that re-ask). **Reset** confirms, calls `Database:Purge`, stores `"reset"` and restamps `ledgerSince`; holdings are untouched. A combat login holds the offer for `PLAYER_REGEN_ENABLED`, and `NS.StandDown` drops a held offer (`NS.DropLedgerResetOffer`).
- **Writers.** `holdings`: `Reconciler:Flush` only. `ledgerSince`: the v11 step and the popup's Reset. `resetPrompt`: the popup only. `resetPromptPending`: the v11 step sets it; the popup's Keep / Reset and `Database:Purge` clear it. `daily`: the v11 step creates it; `modules/Rollup.lua` writes it (closes from `NS.Holdings`' write methods, gained/lost tallies from the `Database:OnWrite` hook) and prunes it, and `Rollup:ForgetHolder` (through `Reconciler:ForgetHolder`) drops one holder's cells. `rollupSeeded`: `Rollup:SeedOnce` only.
- **The daily rollup is sparse twice over.** `daily["YYYY-MM-DD"][holder][thingKey]` exists only for a day, holder and thing that *changed*, and inside a cell a field exists only when it is known or non-zero: `c` is the holder's total of the thing at the end of that day (as far as the addon has seen), `i` the quantity gained that day, `o` the quantity lost. A day with no cell carries the last `c` forward (the Timeline does that at read time, `TimelineModel`), so a balance that never moves costs one cell, not one per day. `MOVE` rows tally nothing: a transfer changes two holders' closes and no one's gained or lost. The day key is the local calendar day (`Ledger.DayKey`, `date("%Y-%m-%d")`), zero-padded so string order is time order.
- **`meta.completeAt`** is stamped once, by `Holdings`, the first time a holder's gate container is read (the bank for a character, the tabs for the Warband), at the moment `meta.partial` flips to false. The Timeline draws a holder's line dashed from its genesis to that moment and solid after; a holder that completed before the field existed has none and draws solid.
- **`rollupRetentionDays`** (global, `0` = Always) is read only by `Rollup:Prune`, from the login deferral. A shorter window drops every day before the cutoff and folds each thing's last close onto the cutoff day first, so a line still starts at its last known value. `settings.rollupRetentionDays` is reset-exempt for the reason `retentionDays` is, and sits in `S.RESET_EXEMPT` as the third entry.
- **`rollupSeeded` is deliberately not declared** in `defaults/Global.lua`, for the reason `ledgerSince` is not: AceDB strips a value equal to its default. It is the timestamp of `Rollup:SeedOnce`, which writes today's close for everything held, once per account, so a thing that never changes again still has a cell to draw from.
### Reset semantics

The reset surfaces write these tables. Since profiles arrived, the global reset is ONE act behind three controls, and its blast radius is the active profile (`options-ui-§12`):

| Reset | Trigger | Schema settings | id lists | `savedView` | `settings.window` | `history` | `retentionDays` | `minimap` |
|-------|---------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Global (profile) reset** | `/lh resetall` · the General page's **Defaults** · **Reset all settings** → confirm (all `Sl:CliResetAll`) | ✓ | ✓ | ✓ | ✓ | — | — | — |
| **Profiles → Reset Profile** | AceDBOptions' own button on the Profiles page | ✓ | ✓ | ✓ | ✓ | — | — | — |
| **Position only** | **Reset position** (Master controls) | — | — | — | ✓ (`Browser:ResetWindow`) | — | — | — |
| **Single** | `/lh reset <path>` (`Sl:CliReset`) | one row | — | — | — | — | if named | if named |
| **Purge** | `/lh purge` · **Purge history…** → confirm | — | — | — | — | ✓ | — | — |

**The global reset is `db:ResetProfile()`, never a walk of the schema** (`options-ui-§12`). `Sl:CliResetAll` (`settings/Slash.lua:435`) calls the library's `O.RestoreAllDefaults`, over an Options descriptor that supplies `resetProfile` (`settings/OptionsSetup.lua`): the session-only rows (the debug console and test mode, whose storage is their own `set()`) are restored row by row, then `S.ResetProfile` (`settings/Schema.lua:759`) runs `db:ResetProfile()` inside the Schema runtime's `ResetCounted`, and every panel re-renders. AceDB empties the active profile in place and merges `defaults/Profile.lua` back, so every setting, the three id lists, the AH cascade, the saved view and the window geometry come back as a fresh profile has them, and `OnProfileReset` reaches the adopt path (`NS.OnProfileEvent`, `core/LootHistory.lua:95`), which re-applies them all. No other profile and not the profile list is touched. The veto the row walk honors is named once, `S.VetoedFromResetAll` (`settings/Schema.lua:748`): every stored row (the profile reset takes it) and anything on the Profiles page.

**The history is not settings.** `db.global` holds the recorded loot and is outside every profile, so no reset reaches it, and neither does the retention that prunes it (`global.retentionDays`, owner decision D6), so a reset can never change what the next prune deletes: clearing it is `/lh purge`, a separate act with its own confirm (`KA0S_LOOTHISTORY_PURGE`). That is `options-ui-§12`'s rule for an addon with **both** scopes, and it is why the Reset all settings confirm uses the first canonical wording (*"Reset this profile to the addon's defaults? … your other profiles are not affected."*). Before profiles, the same button emptied `db.global` wholesale, history and all, and `/lh resetall` walked the schema rows and the id lists instead; the two acts differed, and that difference was a ratified deviation. It is gone.

**One line** (`debug-logging-§10`). The profile event logs `[Set] reset profile '<name>' to defaults (N rows)`, N the stored rows that were off their default just before the reset (the Minimap button and the two retention rows are not counted: both are stored in `db.global`, and `S.RESET_EXEMPT` names them). A reset driven straight at the db (AceDBOptions' Reset Profile) was counted by nothing, so its line carries no count. The reset's own bulk bracket adds no second line: the adopt path's `ConsumeResetCount` marks it as a profile reset. A reset that raised before it reached the handler is logged by the bracket instead, as `[Set] reset all: N rows (stopped by an error)`. The single reset logs `[Set] <path> = <value>`.

- The Filters **tab** carries per-list **Clear all** buttons (confirm-gated, `KA0S_LOOTHISTORY_CLEAR_BLACKLIST`/`_WHITELIST`/`_CURRENCY`) so a list can be emptied without a full reset. `Filters:ClearList` / `Filters:ClearAll` do a single copy-on-write replace + one `_notify` (`ClearAll` empties all three lists).
- **One "Defaults" button, and it is page-wide.** Filters and AH Price stopped being sub-pages in R6, so their two header buttons are gone; the General page's is the only one left and options-ui-§13 forbids narrowing its blast radius to the visible tab. It is the global reset above, so it covers the schema rows, the three id-lists **and** the auction cascade. It no longer recenters the window on its own: **Reset position** is its own button on the Master controls tab, and the geometry comes back with the profile.
- **Test mode ends** on the global reset: it is a session-only row, and the row walk restores it to `false` (`options-ui-§15`).

## schemaVersion & the migration seam

`schemaVersion` is a version stamp on the persisted DB, declared `0` in `defaults/Global.lua:18` and carried to the current shape **11** (`NS.SCHEMA_VERSION`, the ladder's highest `to`) by the migrations below. It lives alongside `history` and `minimap` under `global`: one stamp for the account, because every step is account-wide.

**The `0` floor** (savedvariables-§1, standard v2.65.0). The declared default is the pre-migration floor, never the current version, and it never moves. AceDB's `removeDefaults` strips a stored value equal to its default at logout, and its defaults merge backfills a declared default onto an account that stored no stamp; `0` has neither problem, since any stamp the runner advanced differs from it and persists, and an unstamped account reads `0` and walks every step. The runner, not the defaults, owns the stamp. Every step is idempotent against an empty history, so a brand-new install walking the whole ladder changes nothing but the stamp.

**No step is profile-scoped** (savedvariables-§1). Every step runs once, against `db.global`, before anything has read a profile: v6 and v8 reshaped `savedView` while it still lived in global, v9 is the step that moved it and every setting into the profile, and v10 lifted `retentionDays` back out of the raw profiles into global. A profile created, copied or switched to later is born in today's shape, so the profile events' adopt path (`NS.OnProfileEvent`, `core/LootHistory.lua:95`) has no step to run; it is where one would go if a future step ever needs a per-profile stamp.

`NS:InitDB` (`core/Database.lua:7`) creates the AceDB store, then immediately calls `NS:RunMigrations` to normalize the persisted schema **before any history read, and before anything reads `db.profile`** — the v9 step writes the raw `Default` profile, and AceDB merges the defaults into it on that first read.

`NS:RunMigrations` (`core/Database.lua:244`) is the single, idempotent upgrade seam. `InitDB` (`core/Database.lua:7`) calls it immediately after `AceDB:New` and **before any history read**. The steps are **not** written into the runner's body: they live in the module-level `MIGRATIONS` array (`core/Database.lua:123`), one entry per step, and the runner does nothing but walk it. **Adding a migration is one appended entry there** — the runner is never edited.

```lua
-- core/Database.lua — MIGRATIONS, walked in array order by NS:RunMigrations()
-- { to = 2, apply = function(g) <strip r.viaWhitelist from each record>            return n end },
-- { to = 3, apply = function(g) <rename each record's sellPrice -> vendorPrice>    return n end },
-- { to = 4, apply = function(g) <backfill currency-record quality from C_CurrencyInfo> return n end },
-- { to = 5, apply = function(g) <backfill currency-record bound from C_CurrencyInfo>   return n end },
-- { to = 6, apply = function(g) <re-scan retired ACCOUNT rows -> WARBAND / WARBAND_UE>  return n end },
-- { to = 7, apply = function()  <hand the warbound split to the deferred repair>   return 0 end },
-- { to = 8, apply = function(g) <rewrite a savedView mapID filter as zone names>   return n end },
-- { to = 9, apply = function(g) <move every setting into the Default profile>      return n end },
-- { to = 10, apply = function(g) <lift retentionDays out of every profile into global> return n end },
-- { to = 11, apply = function(g) <create holdings{} and daily{}, stamp ledgerSince; rewrites no row> return 0 end },
```

Array order **is** run order, so a step always sees every earlier step's output and entries are appended, never reordered. The runner owns the version arithmetic that each step used to carry itself: it runs a step when `g.schemaVersion < m.to` (which is what makes the chain skip-forward and idempotent), writes `g.schemaVersion = m.to` **after** `apply` returns — so an error mid-chain can never advance the stamp past unapplied work — and emits the `[Migrate]` line from the row count `apply` returns.

The **v1→v2** migration strips the retired per-record `viaWhitelist` field from every stored row — point-in-time filtering simply no longer hides stored rows, so the old soft-delete annotation is dead weight. The **v2→v3** migration (Rev-2 AH-price integration) renames the per-record `sellPrice` field to `vendorPrice` on every stored row — non-destructive, the value is preserved, only the key changes (making room for the derived `value` model's vendor/auction naming). The **v3→v4** migration (currency quality) backfills `quality` on every stored currency row (`currencyID` set, `quality` still nil) from `C_CurrencyInfo`, so currency looted before this change gets the same Name-color + Quality-column treatment as currency looted after it; a currency the client can't resolve at init stays nil. The **v4→v5** migration (currency bound) likewise backfills `bound` on every stored currency row (`currencyID` set, `bound` still nil) — `"WARBAND"` for a Warband-transferable currency, else `"BOP"` — so currency looted before the change gets the Bound-glyph too; unresolved ids stay nil. The **v5→v6** migration retires the `"ACCOUNT"` bind state: Retail has had no account-bound wording distinct from Warbound since 11.0, so every stored `ACCOUNT` row is a mislabeled warbound drop of one kind or the other (see [midnight-quirks.md](midnight-quirks.md)). Which kind isn't recoverable from the record, so it parks them all on `"WARBAND"` and rewrites a `savedView` Bound filter naming the retired token (else the restored view would match nothing). The **v6→v7** migration then hands the split to a deferred repair, whose arming is versioned by its own `boundRepairRevision` rather than by the schema stamp — that job has been wrong more than once, and each fix has to re-run it on DBs that already ran and cleared a broken pass ([schema.md](schema.md)). **Neither does the work inline, and that is the point:** migrations run from `InitDB` at `ADDON_LOADED`, when the item cache is cold — `C_Item.GetItemInfo` answers nothing and the tooltip carries no bind line — so a one-shot pass reads "no rows to fix" and then bumps the stamp, burning the only chance. Instead they set `boundRepairPending`, and `Database:RepairBoundStates` (deferred: twice per session after login, plus every window open) does the split off both bind signals, keeping the flag until every candidate row is **settled** (item cached *and* a real tooltip, not the `RETRIEVING_ITEM_INFO` placeholder) or the fruitless-pass cap is hit. The **v7→v8** migration follows the Zone filter's move from `mapID` to the zone **name** (see the `mapID` row above): it rewrites a `savedView`'s stored `mapID` set into the names those ids were recorded under, since the restored view would otherwise filter on a field nothing reads. Ids no longer present in the history resolve to nothing and the filter drops. The **v8→v9** migration (profiles; `moveSettingsToProfile`, `core/Database.lua:47`) moves what the player configured out of the account-wide store: the `settings` block, the three id lists and `savedView` are copied from `db.global` into the raw `Default` profile (`db.sv.profiles.Default`, created if absent) and then cleared from global. `Default` is the profile every character was already on, because `InitDB` has always passed `true`. A stored table is laid over one the profile already holds, key by key, so a value the account stored wins and a key it never stored (AceDB's logout strip removed it for equaling the default) keeps the default. The history, its repair bookkeeping and LibDBIcon's `minimap` table stay where they are. A second run finds nothing left in global and moves nothing. The **v9→v10** migration (`moveRetentionToGlobal`, owner decision D6) takes `retentionDays` back out: the setting that decides what the prune deletes from the shared history belongs to the account, not to a profile. It reads both stored shapes — a `retentionDays` still under `global.settings` (left there when the v9 step had no raw file to move it through) and one in any raw profile under `db.sv.profiles` (where v9 put it, and wherever a character wrote it while it was per profile) — clears every one, and stores the value that deletes the least as `global.retentionDays`: `0` (keep Always) beats any day count, otherwise the longer window wins, so the move can never shorten what is kept. With nothing stored anywhere the account keeps its own value, and a second run lifts nothing. None of the nine migrations deletes any records.

All are safe no-ops when the DB isn't ready yet, and idempotent once a DB is already at v11. `tests/test_profiles.lua` pins the v9 and v10 steps: the values land, global is cleared, recorded data is untouched, an unstored key keeps its default, the retention lands in global from either shape keeping the longest window, and a re-run is a no-op.

**Arming the deferred repair is versioned separately**, by `boundRepairRevision` against a `BOUND_REPAIR_REVISION` constant (`NS:ArmBoundRepair`, run on every init) — not by `schemaVersion`. The repair has been wrong more than once, and each fix must re-run it on DBs that already ran and *cleared* a broken pass; tying that to the schema stamp meant a migration per bug. Bumping the constant re-arms on the next login and is a no-op otherwise. `Database:RepairBoundStates` runs it deferred — twice per session from `OnEnterWorld`, and again on every window open, where the item cache is warmest and the wrong lock is about to be looked at. Each candidate row (parked `"WARBAND"` **or** `"BOE"` — BoE because a capture that trusted the lying bind type filed these one state too loose — with an id or a link) is re-read through `Compat.ItemBindState` and merged with `BestBound`, so a row only ever moves toward the more specific warbound state; a genuine BoE reads back BoE and stays. A row counts as resolved only once its **item data is cached and its tooltip is real** — an uncached item returns a legible `RETRIEVING_ITEM_INFO` tooltip, which must not count (the bind type answering BoE is not evidence it isn't warbound — that mistake made an earlier revision of this job clear itself in one pass); unsettled rows are requested and left for the next pass, as is anything past the 200-row per-pass budget; `boundRepairPending`/`boundRepairAttempts` clear once none are pending, or after 10 *fruitless* passes (a pass that fixed something resets the budget, since it proves the client is answering). The `defaults/Global.lua` value stays `0` for brand-new DBs; every DB is carried to `10` by these migrations on its first load after upgrade.

## Retention prune

`Database:PruneOld` (`core/Database.lua:950`) enforces the account-wide `db.global.retentionDays` (the row `settings.retentionDays`) over the account-wide history: it drops every record older than `now - retentionDays × 86400`, rebuild-and-swap, and fires `Ka0s_LootHistory_HistoryChanged` — only when it removed at least one row; a prune that removes nothing leaves the store untouched and fires nothing. `retentionDays == 0` means "keep Always" and returns early. It runs once per session after login, and after a retention change — but a change never prunes on its own say-so.

The row's `onChange` is `S:OnRetentionChanged` (`settings/Schema.lua:814`). It asks `Database:CountOlderThan(days)` (`core/Database.lua:933`, an allocation-free count, `0` for Always) how many records the new value would drop:

- **None** — the value becomes the confirmed retention and nothing else happens.
- **Some, in-game** — it raises `KA0S_LOOTHISTORY_PRUNE` (`settings/Slash.lua:23`), naming the new retention and the count. **Yes** first stores the value the popup named if the store has moved since it opened, then runs `PruneOld`, so the prune and the dropdown both land on the retention the player agreed to. **No** writes the last *confirmed* retention back through `Schema:Set` and prints `retention kept at <label>; no records were deleted.` — so the stored value, which the login prune reads, never holds a retention the player refused, and the next login deletes nothing either (`S:ConfirmRetention`, `settings/Schema.lua:838`). A second change while the popup is open re-shows it for the newer value; Blizzard cancels the open one with reason `"override"` first, and `OnCancel` ignores that reason rather than treating it as **No**.
- **Some, with no `StaticPopup_Show`** (headless) — it prunes at once.

The confirmed retention is seeded from the store by `S:SyncRetention` in `addon:OnInitialize`. `/lh set settings.retentionDays <n>` goes through the same seam and so raises the same confirm.

**A profile event never prunes** (owner decision D6). The retention is account-wide, stored at `db.global.retentionDays` outside every profile, so a profile the addon adopts (a switch, a copy, a reset) brings no retention of its own and the adopt path (`NS.OnProfileEvent`, `S:AdoptProfile`) has nothing to count, confirm or prune. `/lh resetall` and AceDBOptions' Reset Profile reset the profile and cannot reach it either; `S.RESET_EXEMPT` keeps it out of every bulk sweep. A per-profile retention would let a switch to a profile that keeps a week delete everything older at the next login, for every profile. `tests/test_profiles.lua` pins it: a switch, a copy, a reset and `/lh resetall` over records a 7-day retention would drop call no prune, no count and no confirm, and leave every record.

## Read seams

### ActiveHistory — the test-mode swap

Every read-path query resolves against `Database:ActiveHistory` (`core/Database.lua:402`), **not** `history` directly:

```lua
function Database:ActiveHistory()
  return (NS.State and NS.State.testRecords) or NS.db.global.history
end
```

`NS.State.testRecords` (`core/State.lua:16`) is a session-only synthetic dataset published by test mode (`BrowserTable:SetTestMode`, behind the Master controls `Test mode` checkbox and `/lh test`). When set, `Query`, `Stats`, `Export`, and thus the History table **and** the Insights tab all render off the same fake data. Write paths (`Add`, the delete/prune family) always target the real `history` and never see the override.

**Blacklist/whitelist filtering is point-in-time (decided at capture), not a read-time filter.**
`modules/Collector.lua`'s gate runs on every `CHAT_MSG_LOOT`: a **blacklisted** id is an absolute
veto and the item is never written; a **whitelisted** id that would otherwise fail the normal gate
is rescued and written as a plain row. `ActiveHistory` (and therefore `Query`/`Stats`/`Export`)
always return the raw, already-stored history — there is no per-record hide flag and nothing is
ever filtered out at read time. Editing either list only changes what happens to *future* loots;
it never hides, restores, or otherwise touches rows already in `db.global.history` (removing a row
still requires `Database:Delete`). The blacklist/whitelist lists are owned by `NS.Filters`
(`modules/Filters.lua`). See [schema.md](schema.md).

`profile.currencyBlacklist` (`{ [currencyID]=true }`) is a third id set in the same `NS.Filters` registry, alongside `blacklist`/
`whitelist`, but keyed by **currencyID** rather than itemID — a separate namespace, since the two ids
can collide. It is **blacklist-only** (there is no currency whitelist) and, like the item lists, is
strictly point-in-time: a blacklisted currency id is dropped at capture and never written to
`history`; existing currency rows are never hidden or removed.

`Database:Query(filter)` (`core/Database.lua:551`) runs the generic `QueryList` (`core/Database.lua:526`) — an AND-combined filter over quality / source / char / itemType / zone (scalar equality or set membership; `zone` matches the record's zone **name**, with nameless rows under the empty string), a `from`/`to` timestamp range, and a case-insensitive `itemName` substring. `Database:Stats(filter)` (`core/Database.lua:796`) aggregates the filtered result in one O(n) pass for Insights.

### Export — the v2 contract

`Database:Export(filter)` (`core/Database.lua:627`) returns a plain, **metatable-free** copy of the (optionally filtered) history — the forward-compatible v2 export contract. The nested `auctionPrice` and `sourceDetail` tables are deep-copied (`NS.Util.DeepCopy`), so a consumer that mutates an export never rewrites the live SavedVariables row; the copy is paid once per export. It rebuilds each record field-by-field so the emitted shape is explicit and stable across internal refactors (the retired `sourceName` field, for example, is intentionally absent). The exported fields are exactly the record fields listed above:

```
ts · char · classFile · itemID · currencyID · itemLink · itemName · quality · itemLevel · bound ·
vendorPrice · auctionPrice · itemType · itemSubType · quantity · source · sourceDetail ·
zone · mapID · subzone · confidence · dir · kind · holder · from · to · claimed
```

`dir`, `kind` and `holder` are emitted through the `NS.Util.RowDir` / `RowKind` / `RowHolder`
accessors, so a pre-ledger row exports `IN`, its derived kind and its `char`; `from`, `to` and
`claimed` are copied as stored (nil on a legacy row).

**History CSV column list (F4, decided 2026-10-06).** `modules/Export.lua`'s `COLUMNS` order is: `ts, date, time, char, classFile, itemID, currencyID, itemName, quality, qualityRaw, itemLevel, bound, vendorPrice, vendorPriceRaw, auctionPrice, auctionPriceRaw, value, valueRaw, auctionSource, itemType, itemSubType, quantity, source, zone`, then one `auc_<provider>_<key>` per `AUCTION_KEYS` entry, then `wowheadLink`, then the **five appended ledger columns** `dir, kind, holder, from, to`. They are appended, never inserted, so every earlier column keeps its index in a user's spreadsheet, and a legacy row exports `IN`, its derived kind, its `char`, and empty `from` / `to`. The CSV does not carry `claimed`. The Insights CSV gains `Ledger` and `Losses by ...` sections when the range holds losses.

### Database write seam and `Stats().ledger`

`Database:OnWrite(fn)` registers `fn(record, delta, isNew)`, called **synchronously** for every row `Add` writes (`delta` = its quantity, `isNew` true) and every `Amend` (`delta` = the added quantity, `isNew` false). It is synchronous on purpose: a bus message would let a receiver see the row after a later amend, and Phase 3's daily rollup must add each delta exactly once. `RemoveWriteHook(fn)` unregisters. `Database:Amend(index, addQty)` grows `history[index].quantity` in place and sends `RECORD_ADDED` again with the same `(record, index)`; it is how the 60 s coalescing in [data-flow.md](data-flow.md#coalescing) works.

`Database:Stats(filter).ledger` is one table filled by `accumulateLedger` for **every** row in the range (the legacy breakdowns still count only item and currency gains, so a gains-only history produces the numbers it always did): `gainedCount`, `lostCount`, `movedCount`, `gainedValue`, `lostValue`, `netCount`, `netValue` (value is copper: gold rows count their copper, items their `RecordValue x quantity`, currency 0), `reasonIn` / `reasonOut` (row counts per reason), `valueReasonIn` / `valueReasonOut`, `charIn` / `charOut` (value per character), `kindIn` / `kindOut` (row counts per kind), `goldIn`, `goldOut` (copper), and `preLedgerRows` (rows older than `ledgerSince`, for the Insights caveat).

The CSV/Insights export (`modules/Export.lua`) serializes on top of this seam. See [module-map.md](./module-map.md) for where the pieces live.
