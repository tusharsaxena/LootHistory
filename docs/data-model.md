# Data model

One record per loot event, the dense-array history it lives in, the `SourceType` / `Confidence` enums, the `schemaVersion` migration seam, and the two read seams (`ActiveHistory`, `Export`).

## The loot record

Every acquisition is **one row** — records are keyed only by array position, never deduplicated by item. Timestamps and every column are therefore first-class for sort/filter; aggregation (group-by, Insights) is a *view* concern, never a storage concern. Records are plain tables with **no metatables**, so they serialize cleanly for the deferred v2 export.

Assembled by `Collector:BuildRecord` (`modules/Collector.lua:41`):

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
| `bound` | Bind state: `nil` \| `"BOE"` \| `"BOP"` \| `"ACCOUNT"` \| `"WARBAND"`. |
| `vendorPrice` | Vendor sell price in **copper, per unit** (captured at loot time — not market price). Renamed from `sellPrice` by the v2→v3 migration (see below). Half of the "value" comparison — see `Util.RecordValue` below. |
| `auctionPrice` | **Nested map** `provider → key → copper` (e.g. `{ tsm = { dbmarket = 41200 }, oribos = { market = 40800 } }`), captured at loot time by `NS.AuctionPrice:GatherAll` (`modules/AuctionPrice.lua`) — every configured capture key from every installed pricing addon (Auctionator / TSM / OribosExchange), not just one. **`nil`** when nothing was captured (no pricing addon installed, item unpriced, the capture set is empty, or every provider errored). A single price for display/comparison is chosen at *read time* by `NS.AuctionPrice:Pick(map)`, which walks the user's configured priority list and returns the first key present (`price, tag`); it is never re-priced after capture — the map is a point-in-time snapshot, not a live market feed. There is no `priceSource` record field: `Pick`'s `tag` return *is* the provenance, computed on read, not stored. |
| `itemType` / `itemSubType` | Localized item class / subclass strings (e.g. `Armor` / `Cloth`); back the type breakdown and the type filter. |
| `quantity` | Stack size for this loot event (the `%d` from `CHAT_MSG_LOOT`; `1` for the singular line). |
| `source` | `SourceType` enum key (see below) — how the item arrived, resolved by the attribution engine. See [attribution.md](./attribution.md). |
| `sourceDetail` | Optional, source-specific context table (`npcID` / `encounterID` / `difficulty` / `keystoneLevel` / `questID`). Stored for the export and the M+ keystone breakdown; **not displayed** in the Source column. |
| `zone` | Human-readable zone label at loot time. |
| `mapID` | Stable numeric map id — the grouping key (`zone` is the label but localizes/renames). |
| `subzone` | Optional finer sub-area string. |
| `confidence` | `Confidence` enum key — `CERTAIN` when a live source stamp was adopted, `INFERRED` on the `OTHER` fallback. |

The denormalized item fields (`itemID`, `itemName`, `quality`, `itemLevel`, `bound`, `vendorPrice`, `auctionPrice`, `itemType`, `itemSubType`) exist so the [browser](./browser.md) table can filter/sort/group thousands of rows without touching item links or the item cache; `itemLink` remains the source of truth for the tooltip.

### Derived value — `Util.RecordValue`, never stored

There is **no `value` field on the record.** Every "worth" figure — the Insights Value breakdown,
the browser's Value column, the CSV/AI export — computes it on read via `Util.RecordValue(record)`
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

All history lives at `LootHistoryDB.global.history` — an account-wide dense array (see [saved-variables.md](./saved-variables.md)). `Database:Add` (`core/Database.lua:69`) appends one record and fires `Ka0s_LootHistory_RecordAdded`; that is the only write path during normal play.

### Rebuild-and-swap on delete

Deletion never leaves holes. `Database:DeleteAt` (`core/Database.lua:326`) uses `table.remove` (which compacts), while every predicate/bulk path **rebuilds a fresh array and swaps it in**:

- `Database:Delete(pred)` (`core/Database.lua:340`) — keep everything where `pred(r)` is false.
- `Database:PruneOld()` (`core/Database.lua:400`) — retention cleanup; drops records older than `settings.retentionDays` (`0` == keep Always), gated once per session.
- `Database:Purge()` (`core/Database.lua:356`) — replace with `{}`.

Each of these assigns a new table to `NS.db.global.history` and fires `Ka0s_LootHistory_HistoryChanged`, avoiding both O(n²) shifting and array holes. Because records carry no metatables, the swap is a plain value move.

## Enums

### SourceType

`Constants.SourceType` (`core/Constants.lua:8`) — the stored `source` values. **String keys are the export contract: do not rename them.** Extending the enum is forward-compatible.

```
KILL · CONTAINER · MAIL · TRADE · AH · QUEST · VENDOR · CRAFT · ROLL
BONUS_ROLL · MPLUS · REFUND · OTHER · DISENCHANT · MILLING · PROSPECTING
```

Companion tables in the same file: `SourceOrder` (display order for grouping/analytics, `core/Constants.lua:16`) and `SourceLabel` (short UI labels, `core/Constants.lua:23`).

`SOURCE_IMPLEMENTED` (`core/Constants.lua:37`) marks the sources with a **live capture path**; it gates the per-source mute UI. Every source now qualifies, so all appear in the option list — the enum stays whole because it is the export contract. See [attribution.md](./attribution.md).

### Confidence

`Constants.Confidence` (`core/Constants.lua:40`): `CERTAIN` \| `INFERRED`. Surfaces attribution uncertainty in the UI and lets the export flag inferred rows.

> Not part of the record, but related: `Constants.ITEMCLASS_QUEST = 12` (`core/Constants.lua:44`) is the locale-independent `Enum.ItemClass.Questitem` id the collector's optional quest-item gate keys on — never the localized `itemType` string.

## schemaVersion & the migration seam

`schemaVersion` is a version stamp on the persisted DB, seeded in `defaults/Global.lua:9` and carried to the current shape **3** by the migrations below. It lives alongside `history`/`settings`/`minimap` under `global`.

`NS:RunMigrations` (`core/Database.lua:13`) is the single, idempotent upgrade seam. `InitDB` (`core/Database.lua:4`) calls it immediately after `AceDB:New` and **before any history read**. Two migrations ship in its body:

```lua
-- core/Database.lua — NS:RunMigrations()
-- if g.schemaVersion < 2 then <strip r.viaWhitelist from each record> ; g.schemaVersion = 2 end
-- if g.schemaVersion < 3 then <rename each record's sellPrice -> vendorPrice> ; g.schemaVersion = 3 end
```

The **v1→v2** migration strips the retired per-record `viaWhitelist` field from every stored row — point-in-time filtering simply no longer hides stored rows, so the old soft-delete annotation is dead weight. The **v2→v3** migration (Rev-2 AH-price integration) renames the per-record `sellPrice` field to `vendorPrice` on every stored row — non-destructive, the value is preserved, only the key changes (making room for the derived `value` model's vendor/auction naming). Neither migration deletes any records.

Both are safe no-ops when the DB isn't ready yet, and idempotent once a DB is already at v3.

## Read seams

### ActiveHistory — the test-mode swap

Every read-path query resolves against `Database:ActiveHistory` (`core/Database.lua:60`), **not** `history` directly:

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

`Database:Query(filter)` (`core/Database.lua:151`) runs the generic `QueryList` (`core/Database.lua:85`) — an AND-combined filter over quality / source / char / itemType / mapID (scalar equality or set membership), a `from`/`to` timestamp range, and a case-insensitive `itemName` substring. `Database:Stats(filter)` (`core/Database.lua:177`) aggregates the filtered result in one O(n) pass for Insights.

### Export — the v2 contract

`Database:Export(filter)` (`core/Database.lua:158`) returns a plain, **metatable-free** copy of the (optionally filtered) history — the forward-compatible v2 export contract. It rebuilds each record field-by-field so the emitted shape is explicit and stable across internal refactors (the retired `sourceName` field, for example, is intentionally absent). The exported fields are exactly the record fields listed above:

```
ts · char · classFile · itemID · itemLink · itemName · quality · itemLevel · bound ·
vendorPrice · auctionPrice · itemType · itemSubType · quantity · source · sourceDetail ·
zone · mapID · subzone · confidence
```

v1 ships this seam but no serializer/UI; the v2 AI export builds on top of it. See [module-map.md](./module-map.md) for where the pieces live.
