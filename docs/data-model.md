# Data model

One record per loot event, the dense-array history it lives in, the `SourceType` / `Confidence` enums, the `schemaVersion` migration seam, and the two read seams (`ActiveHistory`, `Export`).

## The loot record

Every acquisition is **one row** — records are keyed only by array position, never deduplicated by item. Timestamps and every column are therefore first-class for sort/filter; aggregation (group-by, Insights) is a *view* concern, never a storage concern. Records are plain tables with **no metatables**, so they serialize cleanly for `Database:Export`.

Assembled by `Collector:BuildRecord` (`modules/Collector.lua:43`):

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
| `source` | `SourceType` enum key (see below) — how the item arrived, resolved by the attribution engine. See [attribution.md](./attribution.md). |
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

All history lives at `LootHistoryDB.global.history` — an account-wide dense array (see [saved-variables.md](./saved-variables.md)). `Database:Add` (`core/Database.lua:287`) appends one record and fires `Ka0s_LootHistory_RecordAdded`; that is the only write path during normal play.

### Rebuild-and-swap on delete

Deletion never leaves holes — every predicate/bulk path **rebuilds a fresh array and swaps it in**:

- `Database:Delete(pred)` (`core/Database.lua:718`) — keep everything where `pred(r)` is false.
- `Database:PruneOld()` (`core/Database.lua:778`) — retention cleanup; drops records older than `settings.retentionDays` (`0` == keep Always), gated once per session.
- `Database:RepairBoundStates()` (`core/Database.lua:258`) — the deferred warbound-state split; upgrades under-classified rows in place and fires `HistoryChanged` when it changes any.
- `Database:Purge()` (`core/Database.lua:734`) — replace with `{}`.

Each of these assigns a new table to `NS.db.global.history` and fires `Ka0s_LootHistory_HistoryChanged`, avoiding both O(n²) shifting and array holes. Because records carry no metatables, the swap is a plain value move.

## Enums

### SourceType

`Constants.SourceType` (`core/Constants.lua:8`) — the stored `source` values. **String keys are the export contract: do not rename them.** Extending the enum is forward-compatible.

```
KILL · CONTAINER · MAIL · TRADE · AH · QUEST · VENDOR · CRAFT · ROLL
BONUS_ROLL · MPLUS · REFUND · OTHER · DISENCHANT · MILLING · PROSPECTING
```

Companion tables in the same file: `SourceOrder` (display order for grouping/analytics, `core/Constants.lua:17`) and `SourceLabel` (short UI labels, `core/Constants.lua:24`).

`SOURCE_IMPLEMENTED` (`core/Constants.lua:37`) marks the sources with a **live capture path**; it gates the per-source mute UI. Every source now qualifies, so all appear in the option list — the enum stays whole because it is the export contract. See [attribution.md](./attribution.md).

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

> Not part of the record, but related: `Constants.ITEMCLASS_QUEST = 12` (`core/Constants.lua:44`) is the locale-independent `Enum.ItemClass.Questitem` id the collector's optional quest-item gate keys on — never the localized `itemType` string.

## schemaVersion & the migration seam

`schemaVersion` is a version stamp on the persisted DB, seeded in `defaults/Global.lua:10` and carried to the current shape **8** by the migrations below. It lives alongside `history`/`settings`/`minimap` under `global`.

`NS:RunMigrations` (`core/Database.lua:125`) is the single, idempotent upgrade seam. `InitDB` (`core/Database.lua:4`) calls it immediately after `AceDB:New` and **before any history read**. The steps are **not** written into the runner's body: they live in the module-level `MIGRATIONS` array (`core/Database.lua:19`), one entry per step, and the runner does nothing but walk it. **Adding a migration is one appended entry there** — the runner is never edited.

```lua
-- core/Database.lua — MIGRATIONS, walked in array order by NS:RunMigrations()
-- { to = 2, apply = function(g) <strip r.viaWhitelist from each record>            return n end },
-- { to = 3, apply = function(g) <rename each record's sellPrice -> vendorPrice>    return n end },
-- { to = 4, apply = function(g) <backfill currency-record quality from C_CurrencyInfo> return n end },
-- { to = 5, apply = function(g) <backfill currency-record bound from C_CurrencyInfo>   return n end },
-- { to = 6, apply = function(g) <re-scan retired ACCOUNT rows -> WARBAND / WARBAND_UE>  return n end },
-- { to = 7, apply = function()  <hand the warbound split to the deferred repair>   return 0 end },
-- { to = 8, apply = function(g) <rewrite a savedView mapID filter as zone names>   return n end },
```

Array order **is** run order, so a step always sees every earlier step's output and entries are appended, never reordered. The runner owns the version arithmetic that each step used to carry itself: it runs a step when `g.schemaVersion < m.to` (which is what makes the chain skip-forward and idempotent), writes `g.schemaVersion = m.to` **after** `apply` returns — so an error mid-chain can never advance the stamp past unapplied work — and emits the `[Migrate]` line from the row count `apply` returns.

The **v1→v2** migration strips the retired per-record `viaWhitelist` field from every stored row — point-in-time filtering simply no longer hides stored rows, so the old soft-delete annotation is dead weight. The **v2→v3** migration (Rev-2 AH-price integration) renames the per-record `sellPrice` field to `vendorPrice` on every stored row — non-destructive, the value is preserved, only the key changes (making room for the derived `value` model's vendor/auction naming). The **v3→v4** migration (currency quality) backfills `quality` on every stored currency row (`currencyID` set, `quality` still nil) from `C_CurrencyInfo`, so currency looted before this change gets the same Name-color + Quality-column treatment as currency looted after it; a currency the client can't resolve at init stays nil. The **v4→v5** migration (currency bound) likewise backfills `bound` on every stored currency row (`currencyID` set, `bound` still nil) — `"WARBAND"` for a Warband-transferable currency, else `"BOP"` — so currency looted before the change gets the Bound-glyph too; unresolved ids stay nil. The **v5→v6** migration retires the `"ACCOUNT"` bind state: Retail has had no account-bound wording distinct from Warbound since 11.0, so every stored `ACCOUNT` row is a mislabeled warbound drop of one kind or the other (see [midnight-quirks.md](midnight-quirks.md)). Which kind isn't recoverable from the record, so it parks them all on `"WARBAND"` and rewrites a `savedView` Bound filter naming the retired token (else the restored view would match nothing). The **v6→v7** migration then hands the split to a deferred repair, whose arming is versioned by its own `boundRepairRevision` rather than by the schema stamp — that job has been wrong more than once, and each fix has to re-run it on DBs that already ran and cleared a broken pass ([saved-variables.md](saved-variables.md)). **Neither does the work inline, and that is the point:** migrations run from `InitDB` at `ADDON_LOADED`, when the item cache is cold — `C_Item.GetItemInfo` answers nothing and the tooltip carries no bind line — so a one-shot pass reads "no rows to fix" and then bumps the stamp, burning the only chance. Instead they set `boundRepairPending`, and `Database:RepairBoundStates` (deferred: twice per session after login, plus every window open) does the split off both bind signals, keeping the flag until every candidate row is **settled** (item cached *and* a real tooltip, not the `RETRIEVING_ITEM_INFO` placeholder) or the fruitless-pass cap is hit. The **v7→v8** migration follows the Zone filter's move from `mapID` to the zone **name** (see the `mapID` row above): it rewrites a `savedView`'s stored `mapID` set into the names those ids were recorded under, since the restored view would otherwise filter on a field nothing reads. Ids no longer present in the history resolve to nothing and the filter drops. None of the seven migrations deletes any records.

All are safe no-ops when the DB isn't ready yet, and idempotent once a DB is already at v8.

## Read seams

### ActiveHistory — the test-mode swap

Every read-path query resolves against `Database:ActiveHistory` (`core/Database.lua:278`), **not** `history` directly:

```lua
function Database:ActiveHistory()
  return (NS.State and NS.State.testRecords) or NS.db.global.history
end
```

`NS.State.testRecords` (`core/State.lua:16`) is a session-only synthetic dataset published by `/lh test` (`BrowserTable:ToggleTestMode`). When set, `Query`, `Stats`, `Export`, and thus the History table **and** the Insights tab all render off the same fake data. Write paths (`Add`, the delete/prune family) always target the real `history` and never see the override.

**Blacklist/whitelist filtering is point-in-time (decided at capture), not a read-time filter.**
`modules/Collector.lua`'s gate runs on every `CHAT_MSG_LOOT`: a **blacklisted** id is an absolute
veto and the item is never written; a **whitelisted** id that would otherwise fail the normal gate
is rescued and written as a plain row. `ActiveHistory` (and therefore `Query`/`Stats`/`Export`)
always return the raw, already-stored history — there is no per-record hide flag and nothing is
ever filtered out at read time. Editing either list only changes what happens to *future* loots;
it never hides, restores, or otherwise touches rows already in `db.global.history` (removing a row
still requires `Database:Delete`). The blacklist/whitelist lists are owned by `NS.Filters`
(`modules/Filters.lua`). See [saved-variables.md](saved-variables.md).

`global.currencyBlacklist` (`{ [currencyID]=true }`) is a third carve-out set, alongside `blacklist`/
`whitelist`, but keyed by **currencyID** rather than itemID — a separate namespace, since the two ids
can collide. It is **blacklist-only** (there is no currency whitelist) and, like the item lists, is
strictly point-in-time: a blacklisted currency id is dropped at capture and never written to
`history`; existing currency rows are never hidden or removed.

`Database:Query(filter)` (`core/Database.lua:426`) runs the generic `QueryList` (`core/Database.lua:401`) — an AND-combined filter over quality / source / char / itemType / zone (scalar equality or set membership; `zone` matches the record's zone **name**, with nameless rows under the empty string), a `from`/`to` timestamp range, and a case-insensitive `itemName` substring. `Database:Stats(filter)` (`core/Database.lua:651`) aggregates the filtered result in one O(n) pass for Insights.

### Export — the v2 contract

`Database:Export(filter)` (`core/Database.lua:433`) returns a plain, **metatable-free** copy of the (optionally filtered) history — the forward-compatible v2 export contract. It rebuilds each record field-by-field so the emitted shape is explicit and stable across internal refactors (the retired `sourceName` field, for example, is intentionally absent). The exported fields are exactly the record fields listed above:

```
ts · char · classFile · itemID · itemLink · itemName · quality · itemLevel · bound ·
vendorPrice · auctionPrice · itemType · itemSubType · quantity · source · sourceDetail ·
zone · mapID · subzone · confidence
```

The CSV/Insights export (`modules/Export.lua`) serializes on top of this seam. See [module-map.md](./module-map.md) for where the pieces live.
