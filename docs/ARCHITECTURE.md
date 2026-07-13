# ARCHITECTURE — Ka0s Loot History

Engineering reference for the addon: module map, data model, message bus, slash surface,
event wiring, taint posture, and standards compliance (the standalone window follows §6A).
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

Tier-2 Ace3 addon: AceAddon / AceDB / AceEvent / AceTimer / AceConsole / AceGUI, plus
LibSharedMedia-3.0, LibDataBroker-1.1 and LibDBIcon-1.0. All libraries are **vendored** in
`libs/` and committed (Ka0s Standard v1.1 — externals forbidden).

---

## Module map

Load order is fixed in `LootHistory.toc`: vendored `libs/` → `core/` (Compat first) →
`defaults/` → `locales/` → `settings/` → `modules/` (Attribution before Collector).

| File | Role |
|---|---|
| `core/Compat.lua` | **Loads first.** The compat firewall: every deprecated/varying-API shim gated by direct `C_*`/global presence (no `WOW_PROJECT_ID` game-flavor branching — Retail-only) — GUID decode + `UNIT_KINDS`, item/map/zone info, active keystone level, quality-from-link fallback. |
| `core/Constants.lua` | `SourceType` enum, `SourceOrder`/`SourceLabel`, `SOURCE_IMPLEMENTED` (coverage gate), `Confidence`, `CONTEXT_TTL`, `ITEMCLASS_QUEST` (Quest item-class id for the capture filter), quality/retention/source option tables. |
| `core/Namespace.lua` | Bootstrap shared upvalues (`NS.L`, `NS.C` aliases). |
| `core/State.lua` | Runtime state: `lootContext`, encounter/keystone context, session flags, session-only `debug`, and the session-only `testRecords` (the `/lh test` synthetic dataset). |
| `core/Util.lua` | Pure helpers: date-range (`RangeFrom`) + time/money/byte formatting, self-loot string parsing, `PlayerKey`, dotted-path split. |
| `core/LootHistory.lua` | `AceAddon:NewAddon`; `OnInitialize`/`OnEnable`; `PLAYER_ENTERING_WORLD` → once-per-session retention prune. Owns `NS.bus`/`NS.addon` and the `NS.NewBusTarget()` bus-receiver factory. |
| `core/Database.lua` | AceDB `InitDB` + `RunMigrations` (schema-migration seam), `Add`/`Query`/`ActiveHistory`/`DeleteAt`/`Delete`/`PruneOld`/`Purge`/`Stats`/`Export`, retention. `ActiveHistory` is the read seam that swaps in the test dataset (see Data model). |
| `defaults/Global.lua` | `NS.defaults.global`: `schemaVersion`, `history`, `settings`, `minimap`. |
| `locales/enUS.lua` | Canonical strings; `NS.L` metatable fallback. |
| `settings/Schema.lua` | One row per setting — single source for AceDB defaults, panel widgets, slash get/set/list/reset. `Schema:Set` write seam. `NS.COMMANDS`. |
| `settings/Slash.lua` | AceConsole `/lh` + `/loothistory`; verb dispatch from `NS.COMMANDS`; generated help; purge/reset-all confirm dialogs. |
| `settings/Panel.lua` | `Settings.RegisterCanvasLayoutCategory` landing page + lazy AceGUI body (combat-gated), driven by Schema, with live DB stats. |
| `modules/Attribution.lua` | Source-resolution engine: stamps `State.lootContext` from peripheral events; `Consume` returns source/detail/confidence or `OTHER`/`INFERRED`. Loads before Collector. |
| `modules/Collector.lua` | `CHAT_MSG_LOOT` handler: self-filter, quality gate, quest-item gate (by item class), `Consume`, source-exclude check, `BuildRecord`, `Database:Add`. Caches hot-path upvalues. |
| `modules/Browser.lua` | Window shell: frame/skin, tabs, multi-select filter bar (Quality/Type/Source/Zone/Character + player-scope, date, search), group-by, footer, LDB launcher + LibDBIcon minimap button. |
| `modules/BrowserTable.lua` | Virtualized pooled-row table: filter → group → sort → slice → bind pipeline; columns, sort, grouping, row interactions. |
| `modules/Analytics.lua` | Insights tab: date-range scoped stat/highlight cards + breakdowns (source, vendor value, quality, item type, bound type, character, hour/weekday, M+ keystone, confidence) + top zones/items/value from `Database:Stats`. Pooled bar/strip/list renderers. |
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
  itemType, itemSubType, quantity,           -- item classification + stack size
  source, sourceDetail,                      -- source ∈ Constants.SourceType
  zone, mapID, subzone,                       -- where
  confidence,                                 -- CERTAIN | INFERRED
}
```

- **Storage is account-wide** (`.global`, with a `char` column) — not per-character profiles.
  Switching that is a schema + query rewrite; see [`agent-context.md`](agent-context.md) "Do not change without reason".
- `schemaVersion` is a version stamp on the DB; 1.0.0 ships the initial shape (**1**).
  `NS:RunMigrations` (`core/Database.lua`) runs once at init from `InitDB` (after AceDB is ready,
  before any history read) and normalizes `schemaVersion` — the idempotent seam future schema
  changes hook into. No schema change has shipped yet, so its body is a no-op beyond stamping **1**.
- `Database:Export(filter)` returns metatable-free plain copies — the forward-compatible v2
  export contract (do not change its field shape).
- **Test-mode read seam.** All read paths (`Query`, and therefore `Stats`, plus the Browser's
  `CurrentRecords`) resolve their dataset through `Database:ActiveHistory()`, which returns
  `State.testRecords` when `/lh test` is active and the live `.global.history` otherwise. This is
  why toggling test mode drives both the History table and the Insights tab off the same synthetic
  data. Write paths (`Add`, prune) always target the real history — they never see the override.

**Source types** (`Constants.SourceType`, stable stored keys): `KILL`, `CONTAINER`, `MAIL`,
`TRADE`, `AH`, `QUEST`, `VENDOR`, `CRAFT`, `ROLL`, `MPLUS`, `OTHER`, plus the deconstruct sources
`DISENCHANT`, `MILLING`, `PROSPECTING`. The enum is extended additively (renaming keys is forbidden
— the export contract — but adding is forward-compatible), and only sources with a live stamper are
exposed in the UI:
`Constants.SOURCE_IMPLEMENTED` gates the "Record data from" mute list, and the Browser's
data-driven filter dropdowns (Source/Type/Zone/Character, all multi-select) self-scope from live
data. `ROLL`/`CRAFT` have no stamper yet (see Known limitations).

---

## Settings schema

`settings/Schema.lua` is the single source of truth — one row drives the AceDB default, the
panel widget, and the slash get/set/list/reset behavior. Every mutation flows through
`Schema:Set(path, value)` (validate → write to `NS.db.global` → `onChange`).

| Path | Group | Widget | Default | Notes |
|---|---|---|---|---|
| `settings.enabled` | Master Controls | CheckBox | `true` | Master capture switch. Fires `SettingsChanged`. |
| `minimap.hide` | Master Controls | CheckBox | `false` | Hides the LibDBIcon button (applied live). |
| `settings.windowScale` | Master Controls | Slider (0.6–1.6) | `1.0` | Browser window scale (applied live). |
| `settings.qualityThreshold` | Data Collection | Dropdown | `1` (Common+) | Minimum quality to record. Fires `SettingsChanged`. |
| `settings.excludeQuestItems` | Data Collection | CheckBox | `true` | Drop Quest-class items at capture (gates on `Constants.ITEMCLASS_QUEST`, locale-independent). Fires `SettingsChanged`. |
| `settings.retentionDays` | Data Collection | Dropdown | `30` | `0` = keep Always. Prunes on change. |
| `settings.excludedSources` | Data Collection | MultiCheck | `{}` | Stored as *muted* sources; panel renders inverted ("Record data from"). Fires `SettingsChanged`. |

`settings.window` (persisted position/size) and `minimap` (LibDBIcon state) are storage-only,
not user-facing rows. Debug is session-only (`NS.State.debug`) and never persisted.

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
| `Ka0s_LootHistory_HistoryChanged` | `Database` (`DeleteAt`/`Delete`/`PruneOld`/`Purge`) | — | Browser, Analytics, Panel |
| `Ka0s_LootHistory_SettingsChanged` | `Schema` `onChange` (enabled / quality / questfilter / excludes) | reason string | Collector (`RefreshUpvalues`), Browser (`OnSettingsChanged`) |

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
| `UNIT_SPELLCAST_SUCCEEDED` (player-only) | `OnSpellSucceeded` → DISENCHANT/MILLING/PROSPECTING by spell-name family (+ id fallback) | `modules/Attribution.lua` |
| `hooksecurefunc("BuyMerchantItem")` | `StampVendor` (vendor context) | `modules/Attribution.lua` |
| `hooksecurefunc("TakeInboxItem")` / `("AutoLootMailItem")` | `StampMail` → MAIL, or AH for Auction-House mail | `modules/Attribution.lua` |
| `hooksecurefunc(C_Container.UseContainerItem)` | `OnContainerItemUse` → CONTAINER (opening a lootable bag item) | `modules/Attribution.lua` |
| `hooksecurefunc("GetQuestReward")` | `StampQuestReward` → QUEST (stamps before the reward pushes) | `modules/Attribution.lua` |

All flavor-varying or deprecated calls behind these handlers are routed through
`core/Compat.lua` (the compat firewall) — no inline `WOW_PROJECT_ID` branching in feature code.

---

## Taint notes

- The **browser is a plain non-secure `CreateFrame`** (per §6A) — it touches no protected
  functions and needs no combat-lockdown gate. It can open/refresh in combat.
- The **Settings panel** uses the canonical Blizzard `Settings.RegisterCanvasLayoutCategory`
  canvas with a **lazy, combat-gated** AceGUI body — it defers building/opening during combat.
- Attribution uses `hooksecurefunc` (post-hooks only) on `BuyMerchantItem` / `TakeInboxItem` /
  `AutoLootMailItem` — these observe, never replace, and carry no taint.
- No secure templates, no protected action buttons, no `SetAttribute` — the addon is purely
  observational, so it cannot taint the loot/combat path.

---

## Standards compliance

No deviations from the Ka0s standard (also recorded in [`scope.md`](scope.md) and [`agent-context.md`](agent-context.md)).
Two surface-specific notes:

1. **The standalone browser window follows §6A** (Standalone windows / data browsers): a non-secure
   `CreateFrame`, so it needs no combat-lockdown gate — ESC via `UISpecialFrames`, persisted
   position/size/scale, one `SKIN`/`ApplySkin` seam. This addon is §6A's reference implementation.
   The Settings panel separately follows the §6 combat-gated canvas.
2. **Bare `/lh` prints help** (standard §7.4); window display is explicit (`/lh toggle`,
   `/lh show|hide`).

Vendored libraries follow Ka0s Standard v1.1 (vendoring is the suite-wide rule).

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
- **No value/upgrade addon interop yet** (Auctionator/TSM/Pawn/Loot Appraiser) — planned
  post-1.0.0.
- **AI export is a seam only** in v1.0.0 — `Database:Export()` exists; the companion export
  feature ships in v2.

See the [GitHub issue tracker](https://github.com/tusharsaxena/LootHistory/issues) for the full post-1.0.0 backlog.
