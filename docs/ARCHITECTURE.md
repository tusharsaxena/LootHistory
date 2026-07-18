# ARCHITECTURE — Ka0s Loot History

Engineering reference for the addon: module map, data model, message bus, slash surface,
event wiring, taint posture, and standards compliance (the standalone window follows standalone-windows).
For scope see [`scope.md`](scope.md); for the working brief and the full doc index see [`agent-context.md`](agent-context.md). Topic docs sit alongside this file in `docs/`.

---

## Overview

**Ka0s Loot History** passively records every item the player loots above a configurable
quality threshold, attributes each drop to a **source** (kill / container / mail / trade /
AH / quest / vendor / craft / roll / M+ / other), stores it account-wide, and presents it in
a standalone browser window with a filter/sort/group table plus an Insights analytics view.

The addon splits into two internal halves:

- **Collector** (capture) — `CHAT_MSG_LOOT` is the authoritative "item received (self)"
  signal. Peripheral events stamp a short-lived source **context** that the collector consumes
  when the loot line arrives, then writes one record to an account-wide AceDB array.
- **Browser** (view) — a non-secure standalone frame rendering a virtualized pooled-row table
  (History) and a frame-based analytics view (Insights), driven off the same DB.

Modular Ace3 addon: AceAddon / AceDB / AceEvent / AceTimer / AceConsole / AceGUI, plus
LibSharedMedia-3.0, LibDataBroker-1.1 and LibDBIcon-1.0. All libraries are **vendored** in
`libs/` and committed (Ka0s Standard v2.0.0 — externals forbidden).

---

## Module map

Load order is fixed in `LootHistory.toc`: vendored `libs/` → `locales/` → `core/` (Compat first) →
`defaults/` → `modules/` (Attribution and Filters before Collector) → `settings/` (last).

| File | Role |
|---|---|
| `core/Compat.lua` | **Loads first.** The compat firewall: every deprecated/varying-API shim gated by direct `C_*`/global presence (no `WOW_PROJECT_ID` game-flavor branching — Retail-only) — GUID decode + `UNIT_KINDS`, item/map/zone info, active keystone level, quality-from-link fallback. |
| `core/Constants.lua` | `SourceType` enum, `SourceOrder`/`SourceLabel`, `SOURCE_IMPLEMENTED` (coverage gate), `Confidence`, `CONTEXT_TTL`, `ITEMCLASS_QUEST` (Quest item-class id for the capture filter), quality/retention/source option tables. |
| `core/Namespace.lua` | Bootstrap: sets `NS.name`, `NS.version`, `NS.PREFIX`. (`NS.L` is published by `locales/enUS.lua`; module tables self-publish idempotently.) |
| `core/State.lua` | Runtime state: `lootContext`, encounter/keystone context, session flags, session-only `debug`, and the session-only `testRecords` (the `/lh test` synthetic dataset). |
| `core/Util.lua` | Pure helpers: date-range (`RangeFrom`) + time/money/byte formatting, self-loot string parsing, `PlayerKey`, dotted-path split. Also the shared **secret-safe chat printer** — `NS.Print` (+ `IsConcatSafe`/`SafeToString`), the single seam every module prints through (events-frames-taint-§8), reclaimed from AceConsole's `:Print` in `core/LootHistory.lua`. |
| `core/LootHistory.lua` | `AceAddon:NewAddon`; `OnInitialize`/`OnEnable`; `PLAYER_ENTERING_WORLD` → once-per-session retention prune. Owns `NS.bus`/`NS.addon` and the `NS.NewBusTarget()` bus-receiver factory. |
| `core/Database.lua` | AceDB `InitDB` + `RunMigrations` (schema-migration seam), `Add`/`Query`/`ActiveHistory`/`DeleteAt`/`Delete`/`PruneOld`/`Purge`/`Stats`/`Export`/`FireHistoryChanged`, retention. `ActiveHistory` is the read seam that swaps in the test dataset over the raw account-wide history — filtering is point-in-time (decided at capture), so reads never hide or resurrect a stored row (see Data model). |
| `defaults/Global.lua` | `NS.defaults.global`: `schemaVersion`, `history`, `blacklist`, `whitelist`, `settings`, `minimap`. |
| `locales/enUS.lua` | Canonical strings; `NS.L` metatable fallback. |
| `settings/Schema.lua` | One row per setting — single source for AceDB defaults, panel widgets, slash get/set/list/reset. `Schema:Set` write seam. `NS.COMMANDS`. |
| `settings/Slash.lua` | AceConsole `/lh` + `/loothistory`; verb dispatch from `NS.COMMANDS`; generated help; purge / reset-all / filter-list-clear confirm dialogs. |
| `settings/Panel.lua` | `Settings.RegisterCanvasLayoutCategory` landing page + lazy AceGUI body (combat-gated), driven by Schema, with live DB stats. |
| `modules/AuctionPrice.lua` | `NS.AuctionPrice:Lookup(itemLink, itemID)`: reads an AH price for a just-looted item from installed third-party pricing addons, in a user-configurable, first-hit-wins cascade (Auctionator → TSM → OribosExchange by default, `settings.auction.*`). Every provider call is `pcall`-wrapped so a broken/absent addon degrades to `nil` and the cascade continues. Returns `price, tag` (both `nil` when no enabled provider has a price). Third-party integration boundary — presence-gated here, **deliberately outside** `core/Compat.lua` (Blizzard-API-only); see Standards compliance below. |
| `modules/Attribution.lua` | Source-resolution engine: stamps `State.lootContext` from peripheral events; `Consume` returns source/detail/confidence or `OTHER`/`INFERRED`. Loads before Filters/Collector. |
| `modules/Filters.lua` | `NS.Filters`: the blacklist/whitelist item-id lists — `Add`/`Remove` (copy-on-write, mutually exclusive), `IsBlacklisted`/`IsWhitelisted`, `SortedIDs`, `ParseItemID`. On change: a direct `Collector:RefreshUpvalues()` re-cache + `Database:FireHistoryChanged()`. Data-only; loads before Collector; no `Enable`. |
| `modules/Collector.lua` | `CHAT_MSG_LOOT` handler: self-filter, then the point-in-time gate (blacklist veto → normal quality/source/quest gate → whitelist rescue, recording a plain row with no marker of how it got in), `Consume`, an `AuctionPrice:Lookup` call to stamp `auctionPrice`/`priceSource`, `BuildRecord`, `Database:Add`. Caches hot-path upvalues (incl. the id lists). |
| `modules/Browser.lua` | Window shell: frame/skin, tabs, the **shared singleton filter bar + footer** (multi-select Bound/Quality/Type/SubType/Source/Zone/Character, date, search) that drives BOTH the History table and the Insights charts (`CurrentFilter`), group-by, the **tab-aware `Export` button** (`OpenExport`), LDB launcher + LibDBIcon minimap button. |
| `modules/BrowserTable.lua` | Virtualized pooled-row table: filter → group → sort → slice → bind pipeline; columns, sort, grouping, row interactions (link / blacklist / delete). `OrderedFilteredRecords` exposes the on-screen order for export. |
| `modules/Export.lua` | Export modal (`NS.Export:Open`), config-driven per invoking tab (`{ title, providers, csv, ai }`): Data Set dropdown (All Data / Current View); `CSV` serializes loot rows (History) and `InsightsCSV` a sectioned analytics dump (Insights); `WowheadLink` builder; own copy window. **Export to AI** (`AIPrompt`) bundles BOTH CSVs for the selected Data Set into a prompt that points at `docs/ai-export-guideline.md` (pure pointer — no network from the addon), which in turn instructs the AI to fetch and fill the ready-made `docs/ai-export-template.html` (a data-driven report whose engine renders KPIs, charts and the history browser from the loot rows); plus a "?" help popup. Called directly by the Browser; no bus message. |
| `modules/Analytics.lua` | Insights tab: stat/highlight cards + breakdowns (source, value, quality, item type, bound type, character, hour/weekday, M+ keystone, confidence) + top zones/items/value from `Database:Stats`, **scoped by the shared filter bar** (`Browser:CurrentFilter`, no range selector of its own). Pooled bar/strip/list renderers. |
| `modules/DebugLog.lua` | Session-only debug console window (Copy/Clear); mirrors `NS.Debug` output. Visibility drives `NS.State.debug`. |

---

## Data model

One record per loot event, stored densely in `LootHistoryDB.global.history` (deletion and
retention rebuild-and-swap — no holes). `itemLink` is canonical; the denormalized item fields
back fast table ops.

```lua
{
  ts, char, classFile,                       -- when / who (classFile = locale-independent token)
  itemID, itemLink, itemName, quality,       -- item identity
  itemLevel, bound, sellPrice,               -- itemLevel: equippable only; bound: BOE|BOP|ACCOUNT|WARBAND
  auctionPrice, priceSource,                  -- AH snapshot (copper, per unit) + provenance; both nil if unpriced
  itemType, itemSubType, quantity,           -- item classification + stack size
  source, sourceDetail,                      -- source ∈ Constants.SourceType
  zone, mapID, subzone,                       -- where
  confidence,                                 -- CERTAIN | INFERRED
}
```

- **Storage is account-wide** (`.global`, with a `char` column) — not per-character profiles.
  Switching that is a schema + query rewrite; see [`agent-context.md`](agent-context.md) "Do not change without reason".
- `schemaVersion` is a version stamp on the DB; the current shipped shape is **2**.
  `NS:RunMigrations` (`core/Database.lua`) runs once at init from `InitDB` (after AceDB is ready,
  before any history read) — the idempotent seam future schema changes hook into. The **v1→v2**
  migration ships here: it strips the retired per-record `viaWhitelist` field (point-in-time
  filtering no longer hides stored rows) without deleting any records.
- `Database:Export(filter)` returns metatable-free plain copies — the forward-compatible v2
  export contract (do not change its field shape).
- **`auctionPrice`/`priceSource` are optional record fields, added with no `schemaVersion` bump
  and no migration.** `auctionPrice` (copper, per unit) is an AH price snapshot taken at loot time
  by `modules/AuctionPrice.lua`'s cascade (Auctionator → TSM → OribosExchange, user-configurable,
  first-hit-wins); `priceSource` is its provenance tag. Both are `nil` when no enabled provider had
  a price — including every record written before this feature, which simply falls back to
  vendor. There is **no stored `value` field**: every "worth" figure (Insights, the browser Value
  column, CSV/AI export) is derived on read via `Util.RecordValue(record)` — `auctionPrice` if
  present, else `sellPrice`, else `nil` — never persisted. See [data-model.md](data-model.md).
- **Test-mode read seam.** All read paths (`Query`, and therefore `Stats`, plus the Browser's
  `CurrentRecords`) resolve their dataset through `Database:ActiveHistory()`, which returns
  `State.testRecords` when `/lh test` is active and the raw account-wide history otherwise. This is
  why toggling test mode drives both the History table and the Insights tab off the same synthetic
  data. Write paths (`Add`, prune) always target the real history — they never see the override.
- **Blacklist/whitelist filtering is point-in-time (decided at capture).** The gate in
  `modules/Collector.lua` runs on every `CHAT_MSG_LOOT`: a **blacklisted** id is an absolute veto
  and the item is never written; a **whitelisted** id that would otherwise fail the normal gate is
  rescued and written as a plain row, indistinguishable from any other. There is no per-record hide
  flag and no derived read-time filter — `Database:ActiveHistory()`/`Query` always return the raw,
  already-stored history. Editing either list only changes what happens to *future* loots; it never
  hides, restores, or otherwise touches rows already in `.global.history` (deleting a row still
  requires `Database:Delete`). The lists live in `.global.{blacklist,whitelist}`, owned by
  `NS.Filters`.

**Source types** (`Constants.SourceType`, stable stored keys): `KILL`, `CONTAINER`, `MAIL`,
`TRADE`, `AH`, `QUEST`, `VENDOR`, `CRAFT`, `ROLL`, `MPLUS`, `OTHER`, plus the deconstruct sources
`DISENCHANT`, `MILLING`, `PROSPECTING`. The enum is extended additively (renaming keys is forbidden
— the export contract — but adding is forward-compatible), and only sources with a live stamper are
exposed in the UI:
`Constants.SOURCE_IMPLEMENTED` gates the "Record data from" mute list, and the Browser's
data-driven filter dropdowns (Bound/Quality/Source/Type/SubType/Zone/Character, all multi-select)
self-scope from live data — each offers only the values the history actually contains (so Heirloom,
Poor, Warbound, etc. appear only when present). `ROLL`/`CRAFT` have no stamper yet (see Known
limitations).

---

## Settings schema

`settings/Schema.lua` is the single source of truth — one row drives the AceDB default, the
panel widget, and the slash get/set/list/reset behavior. Every mutation flows through
`Schema:Set(path, value)` (validate → write to `NS.db.global` → `onChange`).

| Path | Group | Widget | Default | Notes |
|---|---|---|---|---|
| `settings.enabled` | Master Controls | CheckBox | `true` | Master capture switch. Fires `SettingsChanged`. |
| `minimap.hide` | Master Controls | CheckBox | `false` | Hides the LibDBIcon button (applied live). |
| `state.debugConsole` | Master Controls | CheckBox | `false` | **Session-only** (`sessionOnly`): shows/hides the debug console; never persisted (`get`/`set` proxy `NS.DebugLog`). |
| `settings.windowScale` | Master Controls | Slider (0.6–1.6) | `1.0` | Browser window scale (applied live). |
| `settings.qualityThreshold` | Data Collection | Dropdown | `1` (Common+) | Minimum quality to record. Fires `SettingsChanged`. |
| `settings.excludeQuestItems` | Data Collection | CheckBox | `true` | Drop Quest-class items at capture (gates on `Constants.ITEMCLASS_QUEST`, locale-independent). Fires `SettingsChanged`. |
| `settings.retentionDays` | Data Collection | Dropdown | `30` | `0` = keep Always. Prunes on change. |
| `settings.excludedSources` | Data Collection | MultiCheck | `{}` | Stored as *muted* sources; panel renders inverted ("Record data from"). Fires `SettingsChanged`. |
| `settings.auction.enabled` | Auction House Price | CheckBox | `true` | Master switch for the AH-price cascade (`modules/AuctionPrice.lua`); `false` short-circuits `Lookup` to `nil, nil`. |
| `settings.auction.tsmSource` | Auction House Price | Dropdown | `"dbmarket"` | Which TSM price key the cascade requests when it reaches TSM. |
| `settings.auction.auctionator` / `.tsm` / `.oribos` | Auction House Price | CheckBox | `true` | Per-provider on/off. |
| `settings.auction.priorityAuctionator` / `.priorityTSM` / `.priorityOribos` | Auction House Price | Dropdown | `1` / `2` / `3` | Cascade order (1 = probed first); ties broken by canonical order. |

`settings.window` (persisted position/size), `savedView` (the saved table view), `minimap`
(LibDBIcon state), and the `blacklist`/`whitelist` item-id lists (managed by `NS.Filters`, surfaced
in the settings **Filters** subcategory) are storage/data state written straight to `NS.db.global`,
**not** Schema rows and not routed through `Schema:Set` — an accepted carve-out (see Standards
compliance, and [`saved-variables.md`](saved-variables.md)). Debug is session-only (`NS.State.debug`)
and never persisted.

---

## Message bus

Closed `Ka0s_LootHistory_*` bus (AceEvent), exactly one sender per message. No cross-module
table reach.

> **Receivers must register on a private bus target** (`NS.NewBusTarget()`), never on the shared
> `NS.bus`/`NS.addon` as `self`. CallbackHandler keys callbacks by `(message, target)`, so two
> consumers of the same message that share a target silently clobber each other — only the last
> registrant receives it. `SettingsChanged`, `RecordAdded`, and `HistoryChanged` each have multiple
> consumers, so every consumer (Collector, Browser, Analytics, Panel) owns its own target.

| Message | Sender | Payload | Consumers |
|---|---|---|---|
| `Ka0s_LootHistory_RecordAdded` | `Database:Add` | `(record, index)` | Browser (refresh History), Analytics (live recompute), Panel (live stats) |
| `Ka0s_LootHistory_HistoryChanged` | `Database` (`DeleteAt`/`Delete`/`PruneOld`/`Purge`, and the public `FireHistoryChanged` that `NS.Filters` calls on a blacklist/whitelist edit) | — | Browser, Analytics, Panel (History stats + Filters page) |
| `Ka0s_LootHistory_SettingsChanged` | `Schema` `onChange` (enabled / quality / questfilter / excludes) | reason string | Collector (`RefreshUpvalues`), Browser (`OnSettingsChanged`) |

> A blacklist/whitelist edit stays within the one-sender rule: it re-caches the Collector via a
> **direct** `Collector:RefreshUpvalues()` call (not a `SettingsChanged` message) and broadcasts
> `HistoryChanged` through `Database:FireHistoryChanged()` (so `Database` remains that message's sole
> sender). The Panel's Filters page subscribes to `HistoryChanged` on its own second bus target.

> `windowScale` and `minimap.hide` changes are **not** broadcast on the bus — their `onChange`
> calls `Browser:SetScale` / `Browser:SetMinimapHidden` directly. Only `enabled`, quality,
> quest-item filter and excludes (which affect capture) fan out via `SettingsChanged`.

---

## Slash commands

Registered by `settings/Slash.lua` for both `/lh` and `/loothistory`. Bare `/lh` **prints the
help index** (standard-compliant); window display is explicit via `toggle`/`show`/`hide`. Verbs
dispatch from `NS.COMMANDS`; `/lh help` is generated from the same table.

| Verb | Action |
|---|---|
| *(none)* | Print the help / command index |
| `show` / `hide` / `toggle` | Open / close / toggle the window |
| `config` | Open the Settings panel |
| `version` | Print the addon version (`[LH] v<version>`, read from TOC metadata) |
| `get <path>` | Print a setting value |
| `set <path> <value>` | Set a setting value |
| `list` | List all settings |
| `reset <path>` | Reset one setting to its default |
| `resetall` | Reset all settings to defaults |
| `debug` | Toggle the debug console (session-only) |
| `test` | Toggle a synthetic preview dataset for the table and Insights (session-only) |
| `purge` | Delete ALL loot history (confirm dialog) |
| `help` | Print the generated command index |

---

## Event subscriptions

| Event / hook | Handler | Module |
|---|---|---|
| `PLAYER_ENTERING_WORLD` | `OnEnterWorld` (once-per-session prune) | `core/LootHistory.lua` |
| `CHAT_MSG_LOOT` | `OnChatMsgLoot` (authoritative capture) | `modules/Collector.lua` |
| `LOOT_OPENED` | `OnLootOpened` (GUID decode → KILL/CONTAINER/MPLUS) | `modules/Attribution.lua` |
| `ENCOUNTER_START` / `ENCOUNTER_END` | encounter context | `modules/Attribution.lua` |
| `CHALLENGE_MODE_START` / `CHALLENGE_MODE_COMPLETED` | keystone context (`Compat.GetActiveKeystoneLevel`) | `modules/Attribution.lua` |
| `TRADE_ACCEPT_UPDATE` | trade context (on mutual accept) | `modules/Attribution.lua` |
| `QUEST_TURNED_IN` | `OnQuestTurnedIn` (questID detail; the reward stamp itself comes from the `GetQuestReward` hook below) | `modules/Attribution.lua` |
| `UNIT_SPELLCAST_SUCCEEDED` (player-only) | `OnSpellSucceeded` → DISENCHANT/MILLING/PROSPECTING by spell id first, then a locale-independent localized name-family fallback | `modules/Attribution.lua` |
| `hooksecurefunc("BuyMerchantItem")` | `StampVendor` (vendor context) | `modules/Attribution.lua` |
| `hooksecurefunc("TakeInboxItem")` / `("AutoLootMailItem")` | `StampMail` → MAIL, or AH for Auction-House mail | `modules/Attribution.lua` |
| `hooksecurefunc(C_Container.UseContainerItem)` | `OnContainerItemUse` → CONTAINER (opening a lootable bag item) | `modules/Attribution.lua` |
| `hooksecurefunc("GetQuestReward")` | `StampQuestReward` → QUEST (stamps before the reward pushes) | `modules/Attribution.lua` |

All flavor-varying or deprecated calls behind these handlers are routed through
`core/Compat.lua` (the compat firewall) — no inline `WOW_PROJECT_ID` branching in feature code.

---

## Taint notes

- The **browser is a plain non-secure `CreateFrame`** (per standalone-windows) — it touches no protected
  functions and needs no combat-lockdown gate. It can open/refresh in combat.
- The **Settings panel** uses the canonical Blizzard `Settings.RegisterCanvasLayoutCategory`
  canvas with a **lazy, combat-gated** AceGUI body — it defers building/opening during combat.
- Attribution uses `hooksecurefunc` (post-hooks only) on `BuyMerchantItem` / `TakeInboxItem` /
  `AutoLootMailItem` — these observe, never replace, and carry no taint.
- No secure templates, no protected action buttons, no `SetAttribute` — the addon is purely
  observational, so it cannot taint the loot/combat path.

---

## Standards compliance

No open deviations from the Ka0s standard. One carve-out was raised and **ratified (2026-07-17)**:
the `blacklist` / `whitelist` item-id lists (issue #14) are persistent state managed outside
`Schema:Set` — a fourth carve-out alongside `settings.window`, `savedView`, and
`settings.windowScale`'s geometry sibling. A dynamic, unbounded id-set has no schema widget to
express, so `NS.Filters` mutates `NS.db.global` directly, exactly as the pre-existing carve-outs do;
it is accepted as the same class, and the standard's own definition was left unchanged. Recorded in
[`saved-variables.md`](saved-variables.md) under the "Standards note".

A second carve-out was raised and **ratified (2026-07-18)** for the AH-price integration: the
third-party pricing-addon shims (`Auctionator` / `TSM_API` / `OEMarketInfo` presence + call
wrapping) live in `modules/AuctionPrice.lua`, **deliberately outside** `core/Compat.lua`.
`core/Compat.lua` is defined as the *Blizzard*-API compat firewall (deprecated/varying `C_*`/global
shims); a cascade over **other addons'** APIs is a different kind of boundary — optional,
config-driven, multi-provider, and irrelevant to every non-pricing module — so folding it into
Compat would blur that file's one job. The Ka0s Standard does not currently define a boundary for
third-party (non-Blizzard) addon interop, so this is recorded as a resolved gap rather than a
deviation: `AuctionPrice` is the addon's third-party-integration boundary, presence-gated exactly
like Compat's own shims (each provider call is `pcall`-wrapped so a broken/absent addon degrades to
`nil` and the cascade continues), but it is its own module because its subject is not a Blizzard
API. The standard's own definition was left unchanged.

Two surface-specific notes:

1. **The standalone browser window follows standalone-windows** (Standalone windows / data browsers): a non-secure
   `CreateFrame`, so it needs no combat-lockdown gate — ESC via `UISpecialFrames`, persisted
   position/size/scale, one `SKIN`/`ApplySkin` seam. This addon is standalone-windows's reference implementation.
   The Settings panel separately follows the options-ui-§2 combat-gated canvas.
2. **Bare `/lh` prints help** (standard slash-commands-§4); window display is explicit (`/lh toggle`,
   `/lh show|hide`).

Vendored libraries follow Ka0s Standard v2.0.0 (vendoring is the suite-wide rule).

---

## Known limitations

- **Partial source coverage.** `ROLL` and `CRAFT` are defined in the `SourceType` enum but have no
  stamper yet (`CRAFT` is reserved for broad recipe crafting, whose cast time can exceed the context
  TTL — see TODO), so they are hidden from the mute list via `SOURCE_IMPLEMENTED`. Deconstruct
  abilities stamp their own `DISENCHANT`/`MILLING`/`PROSPECTING` source (player `UNIT_SPELLCAST_SUCCEEDED`
  by spell id), and `AH` is stamped from Auction-House mail. `VENDOR`/`MAIL`/`TRADE` were confirmed
  recording in-client (smoke §F-001, passed). BAG_UPDATE-diff capture for the `ROLL` gap is backlog.
- **No per-item source name.** The "From" column and its combat-log kill-name cache were removed:
  for the dominant real-world loot (containers, delves, pushed/quest items) no reliable name was
  resolvable, so the column was almost always blank. Records keep `source` and the machine-readable
  `sourceDetail` (npcID / encounter / keystone / questID); the human name is no longer captured or
  displayed.
- **Slow manual click-looting.** The source context uses a fixed `CONTEXT_TTL` (1.5s). Looting
  items more than ~1.5s apart from one open window can let later items fall back to
  `OTHER`/`INFERRED`. Revisiting the single-slot TTL is a backlog item.
- **No value/upgrade addon interop yet** (Auctionator/TSM/Pawn/Loot Appraiser) — planned.
- **AI export depends on the AI tool's web access** — the prompt is a *pure pointer* to
  `docs/ai-export-guideline.md` (raw on `master`), which itself points at `docs/ai-export-template.html`;
  a paste target with browsing disabled can fetch neither, so it produces a generic report instead of
  the themed one. The help popup states web access is required.

See the [GitHub issue tracker](https://github.com/tusharsaxena/LootHistory/issues) for the full backlog.
