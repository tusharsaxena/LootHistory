# Module map

Where each responsibility lives in the source tree, plus the TOC load order and the AceAddon lifecycle hooks. `LootHistory.toc` is the source of truth for load order — match this map to it before editing. 18 source files across `core/`, `defaults/`, `locales/`, `settings/`, `modules/`; the internal-only terms **Collector** (capture) and **Browser** (view) are used throughout.

## Directory tree

```
Ka0s Loot History (AceAddon: NS promoted in place)
├── core/
│   ├── Compat.lua      — LOADS FIRST. Every deprecated/flavor-varying API shim behind
│                          a C_*/global presence check: GUID decode, item info/extras,
│                          bound-scan, map id, keystone, mail-header/AH detection, loot
│                          global-strings, spell name. Retail-only; degrades to nil/false.
│   ├── Constants.lua    — NS.Constants (alias NS.C): SourceType enum (the export
│                          contract — stable string keys), SourceOrder/SourceLabel,
│                          SOURCE_IMPLEMENTED gate, quality/retention/source option
│                          tables, ITEMCLASS_QUEST, CONTEXT_TTL, FONT_MONO path.
│   ├── Namespace.lua    — bootstrap metadata: NS.name, NS.version ("1.1.0"), NS.PREFIX.
│   ├── State.lua        — NS.State: runtime-only mutable state (lootContext, encounter,
│                          keystone, cleanupDone, debug, testRecords). Never persisted.
│   ├── Util.lua         — pure helpers: PlayerKey, SplitPath, date/money/byte formatters,
│                          RangeFrom (shared date-range→epoch), CHAT_MSG_LOOT self-parse.
│   ├── LootHistory.lua  — AceAddon:NewAddon(NS,…); NS.addon / NS.bus / NS.NewBusTarget;
│                          OnInitialize / OnEnable / OnEnterWorld lifecycle.
│   └── Database.lua      — AceDB init + migration seam; ActiveHistory / Add / QueryList /
│                          Query / Export / Stats / DeleteAt / Delete / Purge / PruneOld /
│                          StorageStats. Fires RecordAdded / HistoryChanged.
├── defaults/
│   └── Global.lua       — NS.defaults.global: schemaVersion, history[], settings{},
│                          minimap{}. Account-wide (.global, not .profile).
├── locales/
│   └── enUS.lua         — NS.L with a key-returning metatable fallback. v1 ships
│                          English-only; no string routes through NS.L yet (seam kept).
├── settings/
│   ├── Schema.lua       — one row per setting; S:Set single write seam; boot validation;
│                          NS.COMMANDS slash dispatch table.
│   ├── Slash.lua        — AceConsole /lh + /loothistory binding; help from NS.COMMANDS;
│                          schema-driven get/set/list/reset CLI; purge/reset confirm popups.
│   └── Panel.lua        — Settings.RegisterCanvasLayoutCategory landing page + General
│                          subcategory; lazy AceGUI two-column schema render; History stats.
└── modules/
    ├── Attribution.lua  — source-resolution engine: stamps a short-lived loot context
                           from peripheral events/hooks, consumes it on CHAT_MSG_LOOT.
                           Loads BEFORE Collector.
    ├── Collector.lua     — CHAT_MSG_LOOT handler: self-filter → quality/source/quest gate
                           → build record → Database:Add. Hot-path upvalues.
    ├── Browser.lua       — standalone-windows window shell: frame, skin, tabs, filter bar,
                           saved view, minimap (LDB + LibDBIcon). Bus subscriber.
    ├── BrowserTable.lua  — virtualized pooled-row History table: filter→group→sort→slice
                           →bind; column model; row menu; /lh test synthetic dataset.
    ├── Analytics.lua     — Insights tab: stat cards + breakdown charts + top lists off a
                           single Database:Stats pass; pooled widgets, re-laid-out on resize.
    └── DebugLog.lua      — session-only debug console window; defines the NS.Debug sink.
```

See [data-model.md](data-model.md) for the record shape, [message-bus.md](message-bus.md) for the closed bus, [slash-dispatch.md](slash-dispatch.md) for the command table, [settings-panel.md](settings-panel.md) for the canvas panel, [compat-layer.md](compat-layer.md) for the API firewall, [attribution.md](attribution.md) for source resolution, and [browser.md](browser.md) for the window.

## TOC load order

`LootHistory.toc` orders files by dependency, not alphabetically. Libraries first, then `core/` (Compat first), defaults, locales, settings, modules (Attribution before Collector).

1. `libs/` — vendored LibStub, CallbackHandler-1.0, AceAddon-3.0, AceEvent-3.0, AceTimer-3.0, AceConsole-3.0, AceDB-3.0, AceGUI-3.0, LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0. Committed in-tree (Ka0s Standard v1.1 — vendoring is mandatory; `.pkgmeta` externals are forbidden). Don't edit.
2. `core/Compat.lua` — **loads first** of `core/`. Hangs `NS.Compat` (the private namespace `NS` is the second file vararg, not a global) and populates every deprecated/varying API shim: `GetPlayerMapID`, `GetActiveKeystoneLevel`, `HookUseContainerItem` / `ContainerItemHasLoot`, `HookGetQuestReward` / `CurrentQuestID`, `IsSpellTargeting`, `GetSpellName`, `GetMailHeader` / `IsAuctionHouseMail`, `GetZone`, `DecodeGUID` (+ `UNIT_KINDS`), `QualityFromLink` / `QualityLabel`, `GetItemInfo`, `ScanBound`, `GetItemExtras`, `GetAddOnMetadata`. Each is gated by a direct `C_*`/global presence check (`Compat.lua:5-7`) — no `WOW_PROJECT_ID` branching — so anything later can rely on `NS.Compat` existing.
3. `core/Constants.lua` — exposes `NS.Constants` (alias `NS.C`) with the `SourceType` enum (stable string keys = the export contract; `Constants.lua:8-13`), `SourceOrder` / `SourceLabel`, the `SOURCE_IMPLEMENTED` mute-UI gate (`Constants.lua:33-37` — `CRAFT`/`ROLL` are enum'd but unstamped, so hidden), `ITEMCLASS_QUEST` (locale-independent quest-item class, `Constants.lua:44`), `CONTEXT_TTL` (1.5 s), the quality/retention/source option tables, and `FONT_MONO`. Publishes `NS.SourceType` / `NS.Confidence` aliases.
4. `core/Namespace.lua` — sets `NS.name`, `NS.version` (`"1.1.0"`, `Namespace.lua:5`), and `NS.PREFIX` (the cyan `|cff00ffff[LH]|r` chat tag, slash-commands-§4). Modules still self-publish idempotently; nothing else wired here.
5. `core/State.lua` — `NS.State`, the runtime-only mutable state: `lootContext` (the single-slot attribution stamp), `encounter` / `keystone` (instance context), and the session flags `cleanupDone`, `debug`, `testRecords`. Reset every load — never persisted to SavedVariables (`State.lua:13-17`).
6. `core/Util.lua` — pure helpers: `PlayerKey` (`Name-Realm`), `SplitPath`, `FormatClock` / `FormatDate` / `FormatMoney` / `FormatBytes`, `RangeFrom` (date-range key → `from` epoch, shared by the Browser date filter and the Insights range selector so they can't drift), and `BuildLootPatterns` / `ParseSelfLoot` (compile the localized loot global-strings once and parse a `CHAT_MSG_LOOT` line into link + quantity). Also the shared **secret-safe chat printer** — `NS.Print` (`= NS.Util.print`) plus `IsConcatSafe` / `SafeToString`: every module does `local print = NS.Print` and emits `print("msg")`, so the cyan `NS.PREFIX` tag is prepended once and each arg is secret-stringified (events-frames-taint-§8). `NS.Print` is reclaimed from AceConsole's `:Print` mixin in `core/LootHistory.lua`.
7. `core/LootHistory.lua` — the AceAddon bootstrap. `AceAddon:NewAddon(NS, addonName, "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")` promotes `NS` in place (no `_G.LootHistory` rebind — the namespace stays private) and sets `NS.addon` / `NS.bus`. Defines `NS.NewBusTarget()` — the fresh-AceEvent-target factory every message consumer must use so two consumers can't clobber each other on the shared bus (`LootHistory.lua:15-26`; see [message-bus.md](message-bus.md)). Defines the three lifecycle hooks (below).
8. `core/Database.lua` — defines `NS:InitDB` (`AceDB-3.0:New("LootHistoryDB", NS.defaults, true)` — account-wide) and `NS:RunMigrations` (reads/writes `db.global.schemaVersion`; a no-op seam today, `Database.lua:13-18`), then `NS.Database` with the read/write path: `History` / `ActiveHistory` (the test-mode-aware read seam behind Query/Stats), `Count`, `Add` (fires `RecordAdded`), `QueryList` / `Query`, `Export` (the v2 export contract), `Stats` (the single O(n) pass all Insights widgets consume), `DeleteAt` / `Delete` / `Purge` / `PruneOld` (all fire `HistoryChanged`), and `StorageStats`. Does not create the DB at file-load.
9. `defaults/Global.lua` — `NS.defaults.global`: `schemaVersion = 1`, `history = {}`, the `settings` table (enabled, qualityThreshold, excludeQuestItems, excludedSources, retentionDays, windowScale, window), and `minimap = { hide = false }`. History and settings both live under `.global` (account-wide); debug is deliberately NOT here (session-only). See [data-model.md](data-model.md).
10. `locales/enUS.lua` — `NS.L` with a metatable that returns the key itself, so English strings work untranslated and missing keys never error. The addon ships English-only: no user-facing string routes through `NS.L` yet (an accepted scope decision, `enUS.lua:7-11`); the seam is kept for a future localization pass.
11. `settings/Schema.lua` — `NS.Schema` (alias `S`): one row per setting (`S.Schema`, `Schema.lua:10-64`) driving AceDB defaults, panel widgets, and the slash CLI. `S:Set(path, value)` is the single user-setting write seam — validate → deep-copy → write to `NS.db.global` → `onChange` (`Schema.lua:109-117`); the deep-copy stops a reset from aliasing the DB to a shared default table. Also owns `NS.COMMANDS`, the slash dispatch/help table (`Schema.lua:142-174`). `debug` is intentionally not a Schema row.
12. `settings/Slash.lua` — `NS.Slash`. Registers `/lh` and `/loothistory` via AceConsole (`Slash.lua:36-39`), dispatches the verb against `NS.COMMANDS`, and generates the help index from it (bare `/lh` prints help — Ka0s slash-commands-§4). Provides the schema-driven `CliGet` / `CliSet` / `CliList` (via the pure `BuildListLines`, with the shared `FormatSchemaValue` / `FormatKV` helpers) / `CliReset` / `CliResetAll` / `CliVersion`, the `ResetEverything` full wipe, and registers the purge / reset-all `StaticPopupDialogs` confirm dialogs at file-load (`Slash.lua:7-27`). See [slash-dispatch.md](slash-dispatch.md).
13. `settings/Panel.lua` — `NS.Panel`. Registers the parent `Settings.RegisterCanvasLayoutCategory` (a logo + tagline + slash-command landing page) plus a `General` `RegisterCanvasLayoutSubcategory` holding the real settings. Renders `NS.Schema.Schema` into a lazy two-column AceGUI grid (checkbox/dropdown/slider/multi-check makers), a live History stats + Purge section, and the always-shown-scrollbar patch (`Panel.lua:109-172`, Ka0s options-ui-§10). Writes route through `NS.Schema:Set`; `P:Open` is combat-gated. See [settings-panel.md](settings-panel.md).
14. `modules/Attribution.lua` — **loads before Collector.** The source-resolution engine (`NS.Attribution`). `Stamp` writes the single-slot `State.lootContext` (fresh for `CONTEXT_TTL`, not cleared on consume — one loot window emits many lines); `Consume` reads it or falls back to `OTHER`/`INFERRED` (`Attribution.lua:71-97`). `ResolveLootSource` maps a loot-slot GUID + instance state → source + detail (Creature→KILL, GameObject→MPLUS/CONTAINER, Item→CONTAINER). `Attribution:Enable` (called from `OnEnable`, never at file-load) registers the peripheral stampers: LOOT_OPENED, ENCOUNTER/CHALLENGE_MODE, TRADE_ACCEPT_UPDATE, QUEST_TURNED_IN, a player-only `RegisterUnitEvent` frame for deconstruct spell-success, and `hooksecurefunc` hooks for vendor buy / mail take / container use / quest reward. See [attribution.md](attribution.md).
15. `modules/Collector.lua` — `NS.Collector`, the acquisition path. `ShouldRecord` is the pure quality/excluded-source/quest-item gate (keyed on the locale-independent `ITEMCLASS_QUEST`, `Collector.lua:17-22`); `BuildRecord` assembles the record. `OnChatMsgLoot` parses the self-loot line, consumes the attribution context, gates, gathers item/zone extras, and calls `Database:Add`. `Collector:Enable` registers `CHAT_MSG_LOOT` and — on its own `NS.NewBusTarget()` — `Ka0s_LootHistory_SettingsChanged`, refreshing the hot-path upvalues (`enabled`/`qualityThreshold`/`excludedSources`/`excludeQuestItems`) rather than reading the DB per loot (`Collector.lua:97-113`, Ka0s events-frames-taint-§7).
16. `modules/Browser.lua` — `NS.Browser`, the standalone window (Ka0s standalone-windows reference implementation). Owns the non-secure `LootHistoryWindow` frame (HIGH strata, movable/resizable, ESC via `UISpecialFrames`), the flat `SKIN` + `ApplySkin` re-skin seam, window position/scale persistence to `NS.db.global.settings.window` (an architecture-§5 carve-out from `Schema:Set`, `Browser.lua:76-105`), the History/Insights tab strip (lazy pane build), the custom flat-skin filter bar + multi-select dropdowns, the saved-view / player-scope logic, and the LibDataBroker launcher + LibDBIcon minimap button. `Browser:Enable` subscribes to `SettingsChanged` / `HistoryChanged` / `RecordAdded` on its own bus target and calls `SetupMinimap`. See [browser.md](browser.md).
17. `modules/BrowserTable.lua` — `NS.BrowserTable`, the virtualized pooled-row History table. Defines the `COLUMNS` model (Character always last; `BrowserTable.lua:118-171`), the filter→sort→group→slice→bind pipeline over `Database:QueryList(CurrentRecords, filter)`, a `FauxScrollFrame` + row pool (never one frame per record, Ka0s standalone-windows), collapsible group headers, the class-icon / bound-lock markup, the right-click row menu (link / delete), and the deterministic-PRNG synthetic dataset for `/lh test` (`ToggleTestMode` publishes `NS.State.testRecords`, `BrowserTable.lua:387-400`, so both the table and Insights render off the same fake data).
18. `modules/Analytics.lua` — `NS.Analytics`, the Insights tab. Attaches to the Browser's Insights pane, builds stat/highlight cards + a stack of breakdown sections (source, vendor value, quality, quality mix, item type, bound type, per-character, per-day + value-per-day strips, hour-of-day, weekday, M+ keystone, confidence) + top zones/items/value lists, all off a single `Database:Stats(filter)` pass scoped by a date-range selector. Widgets are pooled and re-laid-out on resize; `BuildCharts` subscribes to `RecordAdded` / `HistoryChanged` on its own bus target for live refresh (`Analytics.lua:438-449`).
19. `modules/DebugLog.lua` — **loads last** of `modules/`. `NS.DebugLog`, the session-only debug console (`LootHistoryDebugWindow`, DIALOG strata, styled by `Browser:ApplySkin`) with a `ScrollingMessageFrame` log in JetBrains Mono, Copy/Clear buttons, and a header `Debug: ON/OFF` toggle. Defines the global sink `NS.Debug(tag, fmt, …)` (`DebugLog.lua:248-262`) — zero-allocation no-op when `NS.State.debug` is off, otherwise appends a tagged `<ts> | [<tag>] <content>` line. `D:SetEnabled` is the single state seam shared by `/lh debug on|off` and the header toggle. It loads after the other modules only reference `NS.Debug` at runtime inside `NS.State.debug` guards, so the late definition never matters.

## AceAddon lifecycle

1. **TOC file-load** as listed above. After load: `NS.Compat` / `NS.Constants` / `NS.State` / `NS.Util` are populated; `core/LootHistory.lua` has run `AceAddon-3.0:NewAddon` to promote `NS` in place (setting `NS.addon` / `NS.bus` and defining `NS.NewBusTarget`); `NS.defaults` is set; `NS.L` exists; `NS.Schema` (with `NS.COMMANDS`), `NS.Slash` (with its confirm dialogs registered) and `NS.Panel` exist; each module has published `NS.X = NS.X or {}` and defined its methods but **not** enabled — no module touches a WoW event/hook/frame API at file-load (so the headless test harness can load every file).
2. **`addon:OnInitialize`** (Ace lifecycle, fires on `ADDON_LOADED`; `LootHistory.lua:28-35`): registers the JetBrains Mono font with LibSharedMedia; `NS:InitDB` builds the AceDB instance and runs `NS:RunMigrations` (no-op at `schemaVersion = 1`; the seam future schema changes hook into); `NS.Schema:Register` runs boot validation (every schema path must resolve against the defaults); `NS.Slash:Register` binds `/lh` + `/loothistory`; `NS.Panel:Register` registers the Blizzard canvas categories (deferred content — panels render lazily on first `OnShow`).
3. **`addon:OnEnable`** (`LootHistory.lua:37-42`): registers `PLAYER_ENTERING_WORLD` → `OnEnterWorld`, then enables the modules in order — `Attribution:Enable` (peripheral event registrations + read-side hooks), `Collector:Enable` (`CHAT_MSG_LOOT` + the `SettingsChanged` upvalue-refresh subscription), and `Browser:Enable` (bus subscriptions + `SetupMinimap`). `BrowserTable` and `Analytics` have **no** `Enable` — they attach lazily when the Browser first builds their pane (`Analytics` subscribes to the bus in `BuildCharts`); `DebugLog` likewise builds its frame lazily. `Panel` and `Slash` do their work in `OnInitialize`, not here.
4. **`addon:OnEnterWorld`** (`LootHistory.lua:45-53`): guarded to run once per session (`NS.State.cleanupDone`). Schedules `Database:PruneOld` via `C_Timer.After(5, …)` so retention cleanup lands 5 s after the login/zone spike rather than during it. `PruneOld` drops records older than `settings.retentionDays` (0 = keep Always) by rebuild-and-swap and fires `HistoryChanged`.

## External dependencies

All vendored under `libs/` and pulled in by `LootHistory.toc` (Ka0s Standard v1.1 — vendoring is the suite-wide rule; do not switch to `.pkgmeta` externals): LibStub, CallbackHandler-1.0, AceAddon-3.0, AceEvent-3.0, AceTimer-3.0, AceConsole-3.0, AceDB-3.0, AceGUI-3.0, LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0. LibSerialize / LibDeflate are deferred to the v2 export and not shipped yet. The `## OptionalDeps` line lists the same set so a shared standalone copy is used when present. `LootHistory.toc`'s `## Interface: 120007` targets Midnight (12.0.7).
