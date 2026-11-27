# ARCHITECTURE — Ka0s Loot History

Engineering reference for the addon: module map, data model, message bus, slash surface,
event wiring, taint posture, and standards compliance (the standalone window follows standalone-windows).
For scope see [`scope.md`](scope.md); the full doc index is the last section of this file. Topic docs sit alongside this file in `docs/`.

---

## Overview

**Ka0s Loot History** passively records every item the player loots above a configurable
quality threshold, attributes each drop to a **source** (kill / container / M+ / bonus roll /
roll / quest / trade / mail / AH / vendor / deconstruct / craft / refund / other), stores it
account-wide, and presents it in a standalone browser window with a filter/sort/group table plus
an Insights analytics view.

It ships on Retail and WoW Forever from one codebase; what one client lacks (the warband bank,
Mythic+, and the sources WoW Forever has no content for) is absent there, never hidden, and the
features each client has in a shape of its own are in [§ Per-client features](#per-client-features-clients-4).

The addon splits into two internal halves:

- **Collector** (capture) — `CHAT_MSG_LOOT` is the authoritative "item received (self)"
  signal. Peripheral events stamp a short-lived source **context** that the collector consumes
  when the loot line arrives, then writes one record to an account-wide AceDB array.
- **Browser** (view) — a non-secure standalone frame rendering a virtualized pooled-row table
  (History) and a frame-based analytics view (Insights), driven off the same DB.

Modular Ace3 addon: AceAddon / AceDB / AceEvent / AceTimer / AceConsole / AceGUI, plus
LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0 and
**[LibKa0s](https://github.com/tusharsaxena/LibKa0s)** — the Ka0s-owned shared library behind the
chat printer, the art and monospace face, the debug console, the slash-command interface, the
settings canvas with its tab strip and Master-controls composer, the settings schema runtime, the
bus message catalog, the spell-name compat reader, the shared drag-to-reorder list,
the flat dropdowns, the Timeline's line chart and the skin engine (vendored at the tag the `CLAUDE.md` provenance line names). All libraries
are **vendored** in `libs/` and committed (Ka0s Standard v2.0.0 — externals forbidden); LibKa0s is
vendored **whole-folder**, because twenty of its twenty-one majors resolve `LibKa0s-Core-1.0` before
registering and a per-file copy is how cross-major skew gets manufactured.

---

## Module map

The authored files load in the fixed order `LootHistory.toc` sets: vendored `libs/` →
`locales/` → `core/` (Compat first) → `defaults/` → `modules/` → `settings/` (last). The
`core/*Setup.lua` files and three in `settings/` (`OptionsSetup.lua`, `Schema.lua`, `Slash.lua`) are
the LibKa0s seams. Capture lives in `modules/Collector.lua` and `modules/Attribution.lua`, every
capture registration and read-side hook in `core/Dispatch.lua`'s two row tables, the holdings ledger in `modules/Reconciler.lua` and its steps, who holds a thing and where in `modules/HoldingsTally.lua` (read by the item and currency tooltip block, `modules/HoldingsTip.lua`, and by the public API, `modules/HoldingsAPI.lua`, [§ Public API (v1)](#public-api-v1)), the window in `modules/Browser.lua` and
its tabs, and every setting in one `settings/Schema.lua` row. The in-game simulator is
`core/SimSeam.lua` (the answer seam, straight after Compat), `modules/SimWorld.lua`, `SimDrivers.lua`,
`SimScenario.lua`, `Sim.lua` (the session host) and `SimPanel.lua`, on `LibKa0s-Sim-1.0`
([§ The simulator](#the-simulator)). The skin this addon wears is `core/SkinSetup.lua`'s, the
`LibKa0s-Skin-1.0` seam: it registers the owner `"LootHistory"` at file load, publishes `NS.Skin` (the
owner's facade every surface paints through) and applies the profile's choice right after AceDB
exists and first on every profile event. A handful of TOC positions are
load-bearing, each carrying a `LOAD-BEARING` comment in the TOC (toc-file-§5; count them with
`grep -c LOAD-BEARING LootHistory.toc`); every other position is conventional, and the TOC says so.

The per-file role table, the directory tree, each load-bearing position with the field it binds,
and the AceAddon lifecycle hooks are in [module-map.md](module-map.md).

### Per-client features (clients-§4)

Ka0s Loot History serves Retail and WoW Forever from one codebase (the roster's `Retail · Forever`,
`## Interface: 120105, 16001`, no load-gating line). The table names each feature that serves one
client, or that both clients have in a shape of their own; every feature it does not name serves
both. The Client column takes the standard's tokens alone: `retail`, `forever` or `both`. A feature
both clients have in their own shape is two rows, one `retail` and one `forever`, its two lists
picked once by `NS.Compat.ClientKey()` (clients-§5), never a filtered Retail list. A `both` row is a
change the WoW Forever port made on both clients (ruling R8, or a fix the Forever client forced),
listed so the port's surface is in one place. `C.FEATURE_CLIENTS` (`core/Constants.lua`) declares the
Retail-only features, `C.FEATURE` holds each one's `Compat.ForClient` answer, read once, and
`C.SOURCE_CLIENTS` declares the Retail-only sources; an event row is declared with `clients = { ... }`
on the row itself. The client is asked only in `core/CompatClient.lua` (clients-§3), and
`tests/test_compat_routing.lua` fails any other file that reads a `WOW_PROJECT_*` constant. The
rulings (R1 to R8) and the lead's calls (D6, D15) are Ka0sAddonsCommonTasks
`docs/2026-11-22-LOOTHISTORY_BANKLEDGER_FOREVER_PORT/00_DESIGN.md`; what the Forever client does that
these rows work around is [forever-quirks.md](forever-quirks.md), and the probes that check their safe
defaults are [forever-probes.md](forever-probes.md). `tests/test_client_shape.lua` checks this table
names every declared feature and source, and each one's own suite checks it present where declared and
absent elsewhere, on each kit profile (clients-§6).

The deconstruct seeds are re-validated against each client's own DB2 on wago.tools (clients-§10):
`tools/seeds/seeds.py` checks `modules/Attribution.lua`'s `DECONSTRUCT_IDS`, `NAME_SEEDS_BY_CLIENT`
and the simulator's `D.SPELLS` against `SpellName` and `SkillLineAbility` (product `wow` for Retail,
`wowf` for WoW Forever, where Milling and Prospecting stay empty by decision). Every candidate and
flag is ruled as data (`tools/seeds/<flavor>_rulings.json`), and each run is a frozen bundle under
`docs/seed-research/`. The procedure is [`validate-seeds.md`](validate-seeds.md).

| Feature | Client | Gated in |
|---|---|---|
| The warband bank (`warbandBank`, R1): the Reconciler's `tabs` and `warbandMoney` parts and their two event rows (`ACCOUNT_MONEY`, `PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED`), the `AccountBanker` arming in `R.BANKER_ARMS`, the tab ids (`C.WARBAND_TAB_IDS`), the char <-> warband pairing and its two sources `WARBAND_DEPOSIT` / `WARBAND_WITHDRAW`, the Holdings tab's Warband split, the holdings tooltip's warband-bank icon, live count and wording (#34: the `tabs` container, the `account` part of `Compat.LiveItemCounts` and the tally's `tabs` overlay, the warband bank named in two of its settings' tooltips), the words "warband moves" in Track transfers' tooltip, test mode's tabs and warband gold, and the simulator's warband tabs, gold and bank steps | `retail` | `core/Constants.lua` (`C.FEATURE_CLIENTS`, `C.SOURCE_CLIENTS`, `C.WARBAND_TAB_IDS`), `modules/Reconciler.lua` (the parts, the event rows' `clients`, `R.READABLE_ON`), `modules/Holdings.lua` (`gateOf`), `modules/HoldingsTab.lua` (`ORDER`), `modules/HoldingsTip.lua` (`ORDER`), `modules/HoldingsTally.lua` (the live overlay), `core/CompatTooltip.lua` (`LiveItemCounts`), `settings/Schema.lua`, `modules/TestData.lua`, `modules/SimWorld.lua`, `modules/SimScenario.lua` |
| Mythic+ (`mythicPlus`, R2): the `MPLUS` source, the keystone context and its four event rows (`CHALLENGE_MODE_START`, `CHALLENGE_MODE_COMPLETED`, `CHALLENGE_MODE_RESET` and `ZONE_CHANGED_NEW_AREA`, which serves only the keystone), the Insights keystone breakdown (`Database:Stats`' `byKeystone`), the diagnostics `attribution: keystone` line and the simulator's `key` scenario | `retail` | `core/Constants.lua` (`C.FEATURE_CLIENTS`, `C.SOURCE_CLIENTS`), `modules/Attribution.lua` (the rows, `ResolveLootSource`), `core/Database.lua`, `modules/Diagnostics.lua`, `modules/SimScenario.lua` |
| Appearances (`appearances`): the two `TRANSMOG_COLLECTION_SOURCE_ADDED` / `_REMOVED` event rows (owner Appearance), the Record appearances switch row, test mode's appearance sample rows, the simulator's appearance driver, world seeds and loot-scenario step, and the Insights "Appearances Collected By Character" section's data (rep/appearance spec, D7; declared in M2.1, its rows land with M2.3 and M2.4) | `retail` | `core/Constants.lua` (`C.FEATURE_CLIENTS`), `modules/Appearance.lua` (the rows), `settings/Schema.lua` (row `clients`), `modules/BrowserTableTestData.lua`, `modules/SimWorld.lua`, `modules/SimDrivers.lua`, `modules/SimScenario.lua` |
| Reputation's faction kinds: renown, friendship, guild and paragon progress read where the client answers them; WoW Forever answers base standings only (API-gap detection inside one feature, clients-§3) | `both` | `core/Compat.lua` (`FactionSnapshot`), `modules/SimWorld.lua` (per-client faction seeds) |
| The sources WoW Forever has no content for (R2): `BONUS_ROLL`, `MILLING` and `PROSPECTING`, absent from `C.SourceOrder`, `C.SOURCE_IMPLEMENTED` and `C.SOURCE_OPTIONS` (so from the Source filter, the capture mute list and test mode's sample); on WoW Forever the bonus-roll line carries no source tag, and Milling and Prospecting stamp no `DECONSTRUCT` loss. `C.SourceType` and `C.SourceLabel` stay whole on both, because they are the export contract (a label may be worded per client, `C.SOURCE_LABEL_WORDS`, never to another key's label) | `retail` | `core/Constants.lua` (`C.SOURCE_CLIENTS`, `C.SOURCE_ABSENT`), `core/Util.lua` (the bonus-roll line), `core/Ledger.lua` (the `DECONSTRUCT` rule's stampers), `modules/BrowserTableTestData.lua` (the source weights) |
| The `DECONSTRUCT` reason (a deconstructed item's loss) reads "Deconstructed", stamped by Disenchant, Milling and Prospecting | `retail` | `core/Constants.lua` (`C.SourceLabel`), `core/Ledger.lua` (`DECONSTRUCT_SOURCE`) |
| The `DECONSTRUCT` reason reads "Disenchanted" (never the `DISENCHANT` gain source's "Disenchant", since Group by Source and the Source filter key on the label), stamped by Disenchant (`13262`) alone (owner ruling F1, K101-FU-01; the stored key is the same on both) | `forever` | `core/Constants.lua` (`C.SOURCE_LABEL_WORDS`), `core/Ledger.lua` (`DECONSTRUCT_SOURCE`) |
| The deconstruct seeds: Retail's Disenchant, Milling and Prospecting spell ids and name families, and the simulator's casts | `retail` | `modules/Attribution.lua` (`DECONSTRUCT_IDS`, `NAME_SEEDS_BY_CLIENT`), `modules/SimDrivers.lua` (`D.SPELLS`) |
| The deconstruct seeds: Disenchant (`13262`) alone; Milling and Prospecting empty by decision (D15) | `forever` | `modules/Attribution.lua`, `modules/SimDrivers.lua` |
| The account's words: the holder reads "Warband" and the bound states "Warbound" / "Warbound Until Equipped" | `retail` | `core/Constants.lua` (`C.ACCOUNT`), `modules/LedgerFormat.lua`, `modules/BrowserTable.lua`, `modules/BrowserTableTestData.lua`, `modules/BrowserWidgets.lua`, `modules/HoldingsTab.lua`, `modules/HoldingsTip.lua`, `modules/HoldingsAPI.lua`, `modules/Export.lua`, `modules/AnalyticsFormat.lua`, `core/Database.lua`, `settings/Schema.lua`, `settings/Slash.lua` |
| The account's words: "Account" and "Account Bound" / "Account Bound Until Equipped" (R2; the stored `§warband` holder and the `WARBAND` / `WARBAND_UE` states are the same keys on both) | `forever` | the same reads of `C.ACCOUNT` |
| Character keys: `Name-Realm` (`Util.PlayerKey`, `Util.QualifyName`, `Compat.TradeTargetKey`, `Compat.LatestCurrencyTransfer`), and the Character column's tooltip says "full Name-Realm" | `retail` | `core/CompatClient.lua` (`RegionalNames`, `UnitCharacterName`, `CharacterKey`), `core/Util.lua`, `core/Compat.lua`, `core/Constants.lua` (`C.CHARACTER_FORM`), `modules/BrowserTable.lua` |
| Character keys: the whole two-word name, first name and surname, with no realm (D6, forever-quirks-§4); the tooltip says "full name and surname" | `forever` | the same files |
| The container groups: the bags are `Backpack` and the five bag slots (`C.BAG_IDS` 0..5) | `retail` | `core/Constants.lua` (`C.BAG_IDS`, read from LibKa0s-Compat's `ContainerGroups()` through `core/CompatClient.lua`; the pattern rows are `NS.Compat.CONTAINER_PATTERNS_BY_CLIENT`) |
| The container groups: the bags also hold the Keyring (`-1`, R5); a bag socketed into the bank (`-2`) is ignored for now (R6) | `forever` | `core/Constants.lua` (`C.BAG_IDS`, read from LibKa0s-Compat's `ContainerGroups()` through `core/CompatClient.lua`; the pattern rows are `NS.Compat.CONTAINER_PATTERNS_BY_CLIENT`) |
| The Wowhead item base: `https://www.wowhead.com/item=` | `retail` | `core/Constants.lua` (`C.WOWHEAD_ITEM_BASE`), `modules/Export.lua` (`WowheadLink`) |
| The Wowhead item base: `https://www.wowhead.com/forever/item=` (R7) | `forever` | the same |
| The default skin: Ka0s Default (`NS.DEFAULT_SKIN = Skin:DefaultSkin()`, skinning-§2) | `retail` | `core/SkinSetup.lua`, `defaults/Profile.lua` (`appearance.skin`) |
| The default skin: WoW Forever (the same read) | `forever` | `core/SkinSetup.lua`, `defaults/Profile.lua` |
| Test mode's and the simulator's seeds: the shared sample characters, Retail's classes, zones, items, currencies and sim fixtures | `retail` | `core/SimSeam.lua` (`NS.SampleCharacters`, `NS.SampleCrowd`), `modules/BrowserTableTestData.lua`, `modules/TestData.lua`, `modules/SimWorld.lua` (`ITEM_SETS`, `FIXTURES`), `modules/SimScenario.lua` (`SCENARIO_ITEMS`) |
| Test mode's and the simulator's seeds: the "First Surname" sample characters, the nine classes, the Stormwind-area zones, 1.x items, Honor Points and Merchant's Favor, the Defias Thug kill in Stormwind City | `forever` | the same files |
| The `CharacterBanker` interaction (`67`) arms the character bank and the bank scope (R8) | `both` | `modules/Reconciler.lua` (`R.BANKER_ARMS`, by `Compat.BankerKind`), `modules/AttributionOut.lua` (`SCOPE_OF`) |
| The bank readiness guard (R8): no character-bank read while `C_Bank.CanViewBank(Enum.BankType.Character)` is false, or while a bank container that had slots on the last ready read answers 0 (on a first visit, while fewer containers answer slots than the purchased tab count) within `R.READY_WAIT` (5 s); `BAG_CONTAINER_UPDATE` and `BANK_TABS_CHANGED` cue the re-read, and the slot counts are kept in `meta.bankSlots` | `both` | `modules/Reconciler.lua` (`R:BankState`, the cue rows), `core/CompatClient.lua` (LibKa0s-Compat minor 6's `CanViewCharacterBank`, nil read as viewable, `NumPurchasedBankTabs` and `UnreadyBankContainers`, LibKa0s#101), `modules/Holdings.lua` (`NoteBankSlots`) |
| Money text: `C_CurrencyInfo.GetCoinTextureString`, then `GetMoneyString`, then `Ng Ns Nc` text (R8; WoW Forever has no bare `GetCoinTextureString`) | `both` | `core/Util.lua` (`FormatMoney`) |
| The roll-won line: the parser takes the global's `%s` capture, so WoW Forever's `\|HlootHistory:%d\|h` prefix is skipped; the simulator fills each `%d` and `%s` in the global's order | `both` | `core/Util.lua` (`ParseRollWon`), `modules/SimDrivers.lua` (`D.RollWonText`) |
| The probe verbs, `/lh debug probe start\|stop\|status\|clear` (R4): session-only facts into the capped `db.global.probe`, stamped with the client and build | `both` | `modules/Probe.lua`, `settings/Schema.lua` (the `debug` row), `core/CompatClient.lua` (`ClientBuild`) |

---

## Data model

One record per loot event, appended to the account-wide `db.global.history` dense array. The
history is the account's record and sits outside every profile; every setting is per profile
([profiles.md](profiles.md)). Every
acquisition is **one row** — records are keyed only by array position and never deduplicated by
item — so every column is first-class for sort and filter, and aggregation stays a view concern.
Records carry no metatables, which is what lets `Database:Export` serialize them directly.

The full field table, the `SourceType` / `Confidence` enums, currency rows, the derived
`Util.RecordValue`, the `schemaVersion` migration chain and the two read seams are in
**[schema.md](schema.md)**.

Beside the loot log sits the **timeline ledger's** account-wide state (schema v11): `db.global.holdings` (what each character and the virtual `"§warband"` holder owns now, by container, with the time each container was last read), the sparse `daily` rollup the Timeline reads (written by `modules/Rollup.lua`, with its own retention `rollupRetentionDays`), and the `ledgerSince` / `resetPrompt` bookkeeping. Row fields `dir` / `kind` / `holder` / `from` / `to` are reserved and written from Phase 2. Shapes and writers are in [schema.md](schema.md#the-ledger-stores); the scan engine is in [data-flow.md](data-flow.md#holdings-scan).

The capture paths reach all three stores through one accessor each (`Database`'s local `historyStore()`, `Holdings:Store()`, `Rollup:Store()`), which answers a simulation's session table from the host's `NS.SimStores` first and the saved store otherwise. Retention, purge, the storage summary, the bound repair, the migrations and the rollup's seed and prune stay on the saved stores. The table is in [data-flow.md](data-flow.md#capture-path-stores).

## Settings schema

`settings/Schema.lua` is the single source of truth: one row drives the AceDB default, the panel
widget and the slash get/set/list/reset behavior, and every write to a row's path goes through
`Schema:Set(path, value)` (validate → write to the active profile, `NS.db.profile` → `onChange`). Two stored rows
write `db.global` through their own `get`/`set` instead: `minimap.shown` (launcher-§3) and
`settings.retentionDays`, which stays account-wide because it governs the shared history (owner
decision D6; see [profiles.md](profiles.md)). The runtime behind the
seam is **`LibKa0s-Schema-1.0`** (`NS.SchemaRuntime`): every host name is a one-line delegate to it,
and a write-completing, log-silent stub in the same file stands in when the library is absent.
Thirty-eight rows ship today, on **one** schema-backed page: the General subcategory, whose eight tabs are
Master controls, Capture, Filters, AH price, Interface, History, Skin and Keybindings; Filters and
Keybindings hold no rows (Keybindings is the library's, options-ui-§20). The Skin tab (key
`Appearance`) holds eight: `settings.appearance.source` and `.skin`, the Scope's `.ignorePanel` and
`.ignoreFonts`, the Font and texture overrides `.font` and `.texture`, and the Font outline `.outline`
(LibKa0s v1.82.0: `all`, `hud` or `off`) are drawn by the library's own Skin tab (skinning-§3), and `.pickerSeen`, the first-run skin picker's memory, is drawn by nothing.
The `settings.auction.priority` cascade is written outside the helper and carries the
`architecture-§5` row under Documented deviations. The rest of the store is not a row: the named
non-setting state (window geometry and the per-tab `savedViews` in the profile; LibDBIcon's `minimap` table, the
loot log and its repair bookkeeping in `db.global`) and the id filter sets, a structural registry in
the profile whose one writer is `NS.Filters` and whose one load pass is the v8→v9 move
(`core/Database.lua`). Each one's storage key, owner and
every writer, with the row table, the reset scopes and the bulk-reset log line, are in
[schema.md](schema.md#state-outside-the-rows).

---

## Message bus

Closed `Ka0s_LootHistory_*` bus (AceEvent) of four messages, exactly one sender per message. No cross-module
table reach.

Each name is declared once, as `NS.MSG.<KEY>` in `core/Constants.lua`, and every `SendMessage` /
`RegisterMessage` names the constant, never the literal (`architecture-§4`). The table goes through
**`LibKa0s-Bus-1.0`**'s `Catalog`, which validates the names at load and answers a strict copy, so a
mistyped key raises at the call site. Only `Catalog` is adopted: the receivers below are untracked
on purpose, so the major's stand-down record (`New`) is not used. Without the library a one-member
stub hands back the plain table ([message-bus.md](message-bus.md#declared-once-as-nsmsg)).

**Every receiver registers on its own `NS.NewBusTarget()`**, never on the shared `NS.bus` as `self`:
CallbackHandler keys callbacks by `(message, target)`, so two consumers sharing a target clobber each other.

| Message (`NS.MSG` key) | Sender | Payload | Consumers |
|---|---|---|---|
| `Ka0s_LootHistory_RecordAdded` (`RECORD_ADDED`) | `Database:Add` | `(record, index)` | Browser (refresh History), Analytics (live recompute), Panel (live stats), Timeline (never counted: the rollup tallies from `Database:OnWrite`). Browser, Analytics and Timeline run their repaint through `NS.Coalesce(…, Constants.RECORD_ADDED_COALESCE)`, so a multi-drop kill costs **one** pass rather than one per row; `HistoryChanged` still repaints immediately. |
| `Ka0s_LootHistory_HistoryChanged` (`HISTORY_CHANGED`) | `Database` (`Delete`/`PruneOld`/`Purge`, the public `FireHistoryChanged` that `NS.Filters` calls on a blacklist/whitelist edit, and `RepairBoundStates` on a pass that actually fixed rows) | — | Browser, Analytics, Panel (History stats + the Filters tab) |
| `Ka0s_LootHistory_SettingsChanged` (`SETTINGS_CHANGED`) | `Schema` — seventeen `onChange` handlers, ten reasons (`enabled`, `quality`, `questfilter`, `ammofilter`, `currency`, `excludes`, `ledger` from Track holdings and losses and Record gold, `view` from Show transfers by default, `chrome` from the Master controls tab's `scale` / `alpha` / `locked`, and `tooltip` from the five Holdings in tooltips rows), and `S:AdoptProfile` with the eleventh, `profile`, once per profile switch, copy or reset | reason string | Collector (`RefreshUpvalues`), Browser (`OnSettingsChanged`), Reconciler (`ledger` / `profile`: re-registers or drops its capture events), HoldingsTally (`ledger` / `profile`: wipes its cache), HoldingsTip (`tooltip` / `ledger` / `profile`: re-reads its hot-path settings cache), HoldingsAPI (`ledger` / `profile`: fires `HoldingsChanged` with a nil holder when availability flips) |
| `Ka0s_LootHistory_HoldingsChanged` (`HOLDINGS_CHANGED`) | the Reconciler only: `Reconciler:Flush`, once per holder whose holdings moved, `Reconciler:ForgetHolder`, and `Reconciler:AnnounceHolders`, once per holder of a simulation's session store when the simulation stops | `holder` key (`PlayerKey()` or `"§warband"`) | HoldingsTab and Timeline (repaint while their pane is shown), HoldingsTally (wipes its cache), HoldingsAPI (relays it as `HoldingsChanged` through its own CallbackHandler registry, silent during a simulation; it never sends on the bus) |

A blacklist/whitelist edit re-caches the Collector by a direct call and broadcasts through
`Database:FireHistoryChanged()`; `windowScale`, `rowHeight`, `retentionDays` and `minimap.shown` are
off the bus. Both are reasoned in the linked doc.

---

## Slash commands

Registered by `settings/Slash.lua` for both `/lh` and `/loothistory`. Bare `/lh` **opens the
Settings panel on its landing page** by running the `config` verb (slash-commands-§3, Slash minor
11); `/lh help` prints the command index. Window display is explicit via `toggle`/`show`/`hide`.
Verbs dispatch from `NS.COMMANDS`; `/lh help` is generated from the same table.

**The slash surface is unchanged while the addon is disabled** (slash-commands-§2/§7): only the
feature verbs `show` / `hide` / `toggle` / `skin` / `lock` / `unlock` / `test` / `purge` / `holdings` / `sim` refuse, with the collection's one refusal
line, and the addon itself is genuinely inert. See [disabled-state.md](disabled-state.md).

| Verb | Action |
|---|---|
| *(none)* | Open the Settings panel on its landing page (same as `config`) |
| `show` / `hide` / `toggle` | Open / close / toggle the window |
| `config` | Open the Settings panel |
| `skin` | Open the first-run skin picker on demand, whatever `pickerSeen` says (`NS.RunSkinVerb`, the library's `O.SkinVerb`). A feature verb: refused with the one disabled line while the addon is off |
| `lock` / `unlock` | Lock / unlock the History window and the export modal (slash-commands-§8, AF-HDR-LH). **Aliases** of `/lh set settings.locked true` / `false`, the Master controls **Lock frame** row, through `Schema:Set`; the launcher's **Locked** entry and the History window's header lock mark run the same verbs. Feature verbs: refused while the addon is off |
| `enable` / `disable` | Turn recording on / off. **Aliases**, never a second switch: each is `/lh set settings.enabled <bool>` with the path filled in, so it writes the Master controls **Enable Loot History** row through `Schema:Set` and holds no state of its own (slash-commands-§2). Both keep answering while the addon is disabled, which is what stops the pair being one-way |
| `version` | Print the addon version (`[LH] v<version>`, read from TOC metadata) |
| `get <path>` | Print a setting value |
| `set <path> <value>` | Set a setting value |
| `list` | List all settings |
| `reset <path>` | Reset one setting to its default |
| `resetall` | Reset all settings to defaults: `options-ui-§12`'s global reset, the **profile reset** (`db:ResetProfile()`). The same act as the General page's **Defaults** button and the Master controls tab's **Reset all settings** (which confirms first): the active profile's settings, id lists, AH cascade, saved view and window geometry come back as shipped, and test mode ends. The loot history is account-wide and untouched (`/lh purge` clears it), and so is the minimap button (launcher-§3). Scope matrix in [`schema.md`](schema.md#reset-semantics) |
| `profile` / `profile <name>` | Bare: list the profiles, the current one marked. With a name: switch to that existing profile (exact case; surrounding quotes stripped, spaces kept). An unknown name is refused with the list and never created; a switch in combat is refused. The behavior is `LibKa0s-Slash-1.0`'s `CliProfile` (Slash minor 17) over `NS.db`, and it answers while the addon is disabled. See [profiles.md](profiles.md) |
| `holdings <query>` | Write the ten largest account-wide holdings whose name contains the query (gold as money, others as counts), from `db.global.holdings`, to the debug console as a **report** (`debug-logging-§15`, LibKa0s#79): through `NS.DebugLog:Report`, whatever the logging flag reads, revealing a hidden console, with one chat pointer line. No match answers `no holdings match '<query>'.` in chat and writes nothing. A feature verb: refused with the one disabled line while the addon is off. Reads only; never scans |
| `debug` / `debug on` / `debug off` / `debug diagnostics` / `debug events` / `debug probe start\|stop\|status\|clear` | Bare: toggle the debug console window. `on` / `off`: set the session-only logging flag (`NS.State.debug`, never persisted), independent of the window. `diagnostics` is tested first and runs the same report as the `diagnostics` verb. `events`: print the event names this client refused at registration (`NS.RejectedEvents`, `events-frames-taint-§1`), or `none`; it needs no console. `probe`: the WoW Forever port's probe verbs (ruling R4, `modules/Probe.lua`), recording client facts into the capped `db.global.probe` until stopped, its lines in chat and nothing in the console; a bare `probe` is `status`. See [forever-probes.md](forever-probes.md) |
| `diagnostics` | Append the diagnostics report to the debug console (`debug-logging-§14`), after whatever trace it already holds, with logging on or off and while the addon is disabled. The run turns session logging on first when it is off (standard v2.71.0), and the console's **Diagnostics** link runs the same call. No other name (`diag`, `dump`) runs it. See [debug.md](debug.md) |
| `perf` | The `LibKa0s-Perf-1.0` A/B capture: bare opens the step panel, `perf finish` prints the report (bucketed costs of the six in-combat handlers) and the JSON dump. A diagnostic, so it answers while the addon is disabled; a capture takes the `perf` hold on the latch. See [performance.md](performance.md). |
| `test` | Toggle a synthetic preview dataset for the table, Insights, Holdings and the Timeline (session-only; the same switch as the Master controls **Test mode** checkbox, and combat ends it). Its people are sample characters: the collection's five (`NS.SampleCharacters`, LibKa0s-Sim-1.0's `Sample`) and a pool of the same convention for the other classes ([browser.md](browser.md#test-mode-lh-test--synthetic-preview)) |
| `sim` | The in-game simulator, `LibKa0s-Sim-1.0`'s verb grammar (`NS.Sim:RunVerb`): bare prints status and usage and opens the panel; `start <scenario>` (every successful start shows the panel too, Sim 5, LibKa0s v1.113.0; FB2-LH-01), `run` / `step` / `pause` / `resume` / `restart`, `stop`, `status`, `panel`, and the host verb `loot [n]`. A feature verb: refused while the addon is disabled. No key binding; the launcher menu's **Sim mode** entry and the Master controls **Sim mode** checkbox run the same verb through `NS.ToggleSim` (R6-SIM), which reads Sim mode as the sim window shown or a sim running (R7-SIM): from off it is the bare verb, from on a stop while a sim runs, then the window closed. See [§ The simulator](#the-simulator) |
| `purge` | Delete ALL loot history (confirm dialog). Refused while a simulation runs |
| `help` | Print the generated command index |

### The Show window key binding

The root `Bindings.xml` (never a TOC line) declares one binding, `CLICK LootHistoryToggleWindow:LeftButton`, in the addon's own category `BINDING_HEADER_LOOTHISTORY` with no `header` and no default key (launcher-§6, anti-pattern #96): the player finds **Toggle history browser** in Options -> Keybindings -> Ka0s Loot History, a section of its own titled with the brand, and on the General page's **Keybindings** tab, which the library draws from `NS.BINDINGS` (`O.KeybindingsTab`, options-ui-§20). `NS.BINDINGS`, the one bindings table, is declared beside the button; `tests/test_keybinding.lua` checks it against `Bindings.xml` through `Kit.assertBindingsXml`. `core/LauncherSetup.lua` creates the plain, hidden, non-secure button of that permanent name **above** its degraded exit, so the key works without the library; its click is the launcher menu's **Show window** handler, the `/lh toggle` verb. A key cannot be grayed, so the click asks `NS.RefusalLine()` (`core/LifecycleSetup.lua`) first and prints its one line while the addon stands down: the disabled line, or *Not available during a performance capture.* under the perf hold alone, which the verb's gate does not see and `B:Show` refuses silently. See [disabled-state.md](disabled-state.md).

---

## Public API (v1)

Other addons read the holdings tally through one global, published by `modules/HoldingsAPI.lua` at
file load with `rawset` (public-api, #34). `_G.LootHistory` is `{ API = NS.API }` and nothing else
(architecture-§1). Reach it like this:

```lua
local api = LootHistory and LootHistory.API and LootHistory.API.v1
```

**Versioning.** `v1` is semver-stable. A field may be added to an answer. A field is never removed,
renamed or retyped, and a function never changes its arguments. A breaking change ships as `v2`
beside `v1`, and `v1` keeps answering. `api.Version()` answers `1` (`C.API_VERSION`) always, even while
the API is unavailable.

### Functions

Every function is dot-called (`api.ItemCount(id)`, not `api:ItemCount(id)`).

| Signature | Returns |
|---|---|
| `api.Version()` | `1`, always. |
| `api.IsAvailable()` | `true` while the addon is up, enabled and recording the ledger (see *Availability*). |
| `api.Holders()` | A new array of holder keys: characters ascending, then `"§warband"` last when present. `{}` while unavailable. |
| `api.HolderInfo(holder)` | `{ name, realm, class, isWarband, isCurrent, lastSeen, partial }`. `name` and `realm` split at the first `-` on Retail. On WoW Forever `name` is the whole key and `realm` is nil. For `"§warband"`, `name` is the account's word (`"Warband"`, Forever `"Account"`), `realm` is nil and `isWarband` is true. `class` is the class file (it can be nil). `lastSeen` is a timestamp. `partial` is true until the holder's bank (the warband's tabs) is first read. nil for an unknown holder, a non-string, or while unavailable. |
| `api.ItemCount(itemID)` | `total, perHolder`, where `perHolder = { [holder] = { [container] = n } }`. Only nonzero containers and holders appear. The container keys are `bags`, `equipped`, `bank`, `mail`, `auctions` and `tabs`. Every holder is included, the warband too. `itemID` is the base item id: every variant of it counts. `nil, {}` while unavailable or for a non-number. `0, {}` for an id nobody holds. |
| `api.CurrencyCount(currencyID)` | `total, { [holder] = n }`. The same rules. |
| `api.Money(holder)` | Copper for `holder`. With `holder` nil, the sum over every holder, the logged-in character included. nil for an unknown holder or while unavailable. |
| `api.Holdings(holder)` | A deep copy of the stored entry: `{ items = { [itemID] = { [container] = n } }, currency = { [id] = n }, money = copper, links = { [itemID] = link }, scanned = { [container] = ts }, meta = { genesis, partial, completeAt, lastSeen, classFile } }`. Stored values only, with no live overlay: a snapshot of the ledger. Internal fields (escrow, bank slot sizes) are left out. nil for an unknown holder or while unavailable. |
| `api.Scanned(holder)` | A copy of the holder's scan times, `{ bags = ts, bank = ts, …, money = ts, currency = ts }`, or nil. |
| `api.RegisterCallback(owner, "HoldingsChanged", fn)` | CallbackHandler semantics: `fn` is a function, or a method name on `owner`. A function is called as `fn(event, holder)`, a method as `owner[fn](owner, event, holder)`. |
| `api.UnregisterCallback(owner, "HoldingsChanged")` | CallbackHandler semantics. |

CallbackHandler ships vendored with this addon. On an install without it, `RegisterCallback` and
`UnregisterCallback` are still functions. They do nothing and return false, so `v1` has the same
eleven names either way.

### Copies only

Every table an answer returns is freshly built. None is, or holds, a table of
`db.global.holdings`, the tally's cache or its scratch rows. A consumer may keep, sort or write
into an answer, and the next call is unaffected. A consumer must not expect an answer to update
in place: query again after `HoldingsChanged`.

### Live versus stored

The API reads the saved ledger only. Test mode's sample and a `/lh sim` session's store never reach
it. On top of the ledger, the logged-in character's counts are read live:

- **Items.** The logged-in character's `bags`, `equipped` (worn gear and the bags in its bag slots)
  and `bank` come from the client's item counts. On Retail the warband's `tabs` do too. Everyone
  else's containers, and the logged-in character's `mail` and `auctions`, are stored.
- **The zero-suspect fallback.** Away from a banker, a live bank or tabs count of 0 over a stored
  count above 0 answers the stored count, because the client has not loaded that bank this session.
  At a banker the live count is authoritative. While a `/lh sim` session runs no bank is: the
  simulated bank step never makes the real client's count authoritative, and every live read above
  is the real client's, never the simulated world's.
- **Currencies.** The logged-in character's quantity is live. An account-wide currency's is live on
  `"§warband"`. Other holders are stored.
- **Money.** The logged-in character's purse is live. The warband's deposit is live where the client
  answers, otherwise stored. Other holders are stored.
- `api.Holdings(holder)` is the exception: it is stored values only.

### Availability

`api.IsAvailable()` is false, and every other answer is the empty one listed above, while:

- the addon is disabled (`/lh disable`, or the Master controls checkbox);
- a perf capture holds the addon down;
- **Track holdings and losses** (`settings.trackLedger`) is off.

`trackLedger` is a **per-profile** setting while the ledger is account-wide, so the answer follows the
logged-in character's profile. `_G.LootHistory` itself stays while the addon is down. Only its answers
go empty.

### `HoldingsChanged`

The payload is `(event, holder)`, with `event = "HoldingsChanged"`.

- After a ledger flush, it fires once per holder whose holdings changed. That covers "Forget this
  character" too.
- With `holder = nil`, it means everything may have changed. It fires when availability flips (a
  `trackLedger` change or a profile switch), when the addon stands down and when it stands up again.
  Re-query on it.
- The relay wipes the tally's cache before it fires, so a query made inside the callback already
  reads the new store.
- It never fires during `/lh sim`. A simulation's flushes concern its own session store, which the
  API never reads.
- The logged-in character's own bag moves fire after the ledger's debounced flush, never mid-combat.
  The live counts above are current on every call anyway.
- The relay re-fires the addon's own `HOLDINGS_CHANGED` message through its own CallbackHandler
  registry. It sends nothing on the addon's message bus.

### Holder keys and client notes

- Characters are `"Name-Realm"` on Retail and `"First Surname"` on WoW Forever. The account holder
  is `"§warband"` on both. The `§` marks a system key.
- WoW Forever has no warband bank: no `tabs` container appears there, the warband holder holds only
  account-wide currencies, and `HolderInfo` names it `"Account"`.

---

## The disabled state

**Disabled means the addon is not running** (`slash-commands-§7`). `core/LifecycleSetup.lua` is the
`LibKa0s-Lifecycle-1.0` seam: one latch, stood down while any named hold is taken, and every route to
the switch arrives at `NS.Lifecycle:Set("disabled", …)`. Standing down unregisters every event, bus
subscription and unit frame, cancels every deferral `NS.After` armed and hides the windows at the
source (`B:VisibilityAllows`). A hook that cannot be undone gates its own body instead, through one of three funnels: the `hooksecurefunc` capture hooks into `Attribution:Stamp`, the ledger's loss-side hooks into `AttributionOut`, and the holdings tooltip's post calls (`TooltipDataProcessor.AddTooltipPostCall` and the tooltips' `OnHide` / `OnTooltipCleared` `HookScript`s, #34) into `NS.HoldingsTip.OnTooltip`, whose first rung is `NS.IsStoodDown()`. `HoldingsTally`, `HoldingsTip` and `HoldingsAPI` each stand down directly after `Rollup:Disable` and up after `Timeline:Enable`, each dropping its own bus target; `_G.LootHistory` survives as setup and its answers go empty. The slash surface, the
settings panel, AceDB and the launcher registration survive as setup, and `tests/test_disabled.lua`
is the conformance suite. The working-state wipes are callable apart from the stand-down, for the
simulator's start and stop (LootHistory#37): `Reconciler:ResetState()`, `Attribution:ResetContexts()`
and `NS.CancelDeferral(h)`, which cancels one `NS.After` handle and leaves the login deferrals armed.
The 20-second login deferral sets `NS.State.loginSettled`. The full account is in
[disabled-state.md](disabled-state.md).

---

## Event subscriptions

**One event table and one hook table** (`core/Dispatch.lua`, LootHistory#37). Every capture event
below that is not the lifecycle's own `PLAYER_ENTERING_WORLD` or the window's `PLAYER_REGEN_*` pair
is a row of `NS.EVENT_ROWS` (`{ event, owner, target, fn, unit? }`), and every `hooksecurefunc`
row a row of `NS.HOOK_ROWS` (`{ name, owner, fn, tbl?, install? }`). The four capture modules append
their rows at file load, so row order is TOC order and equals the stand-up order: Attribution (nine
`bus` rows, five on WoW Forever, which has no keystone, the player-only `spell` row, five hooks), AttributionOut (six `out` rows, thirteen
hooks), Collector (three `bus` rows), Reconciler (sixteen `ledger` rows, fourteen on WoW Forever). Each module's Enable and
Disable call `NS.RegisterRows(owner, targetObj, targetKey)` / `NS.UnregisterRows(owner)` instead of a
hand-written list, and `row.registered` is true only while a registration is live; hooks go in once
per session through `NS.InstallHookRows(owner)` under the module's latch. Every live handler is
`NS.Deliver(row, event, ...)` (hooks: `NS.DeliverHook`), whose one hook point, `NS.RealEventFilter`,
is nil until the simulator sets it. `NS.DeliverAll(event, ...)` walks the registered rows (or
`hook:<name>` the installed hook rows) in order under `pcall`, which is how a simulated event reaches
exactly the handlers the client would call. `TRADE_ACCEPT_UPDATE` and the two
`PLAYER_INTERACTION_MANAGER_FRAME_*` events have two rows each, on two targets, and `BuyMerchantItem`
two hook rows (`StampVendor`, then `StampOut("BUY")`). `tests/test_dispatch.lua` pins the
(target, event) set against a pre-refactor snapshot.

**Every row below is torn out, not gated, while the addon is disabled** — see
[disabled-state.md](disabled-state.md). The `hooksecurefunc` rows are the one exception the
standard sanctions, because that API has no un-hook; they gate their bodies on the latch (`Attribution:Stamp` for the Phase 1 hooks, `StampOut` and the `On*` bodies of `modules/AttributionOut.lua` for the ledger's).

The Reconciler's rows register only while `settings.trackLedger` is on, one event at a time through `NS.RegisterRows` (and so `NS.SafeRegisterEvent`) on a private target (sixteen names, fourteen on WoW Forever; the combat edge is the same `PLAYER_REGEN_ENABLED` the visibility row uses, on a different target). In combat a handler sets a dirty bit and nothing else.

| Event / hook | Handler | Module |
|---|---|---|
| `PLAYER_ENTERING_WORLD` | `OnEnterWorld` (once-per-session prune + the deferred bound-state repair, both deferred through `NS.After` so a stand-down can cancel them) | `core/LootHistory.lua` |
| `CHAT_MSG_LOOT` | `OnChatMsgLoot` (authoritative capture) | `modules/Collector.lua` |
| `CHAT_MSG_CURRENCY` | `OnChatMsgCurrency` (currency capture: `recordCurrency` → per-source mute → currency blacklist, writing a `Type=Currency` row) | `modules/Collector.lua` |
| `LOOT_OPENED` | `OnLootOpened` (GUID decode → KILL/CONTAINER/MPLUS) | `modules/Attribution.lua` |
| `LOOT_CLOSED` | `OnLootClosed` (the window's lines get `LOOT_LINE_GRACE` more) | `modules/Attribution.lua` |
| `ENCOUNTER_START` / `ENCOUNTER_END` | encounter context | `modules/Attribution.lua` |
| `CHALLENGE_MODE_START` / `CHALLENGE_MODE_COMPLETED` | keystone context (`Compat.GetActiveKeystoneLevel`); Retail only (`C.FEATURE.mythicPlus`, ruling R2) | `modules/Attribution.lua` |
| `ZONE_CHANGED_NEW_AREA` | `OnZoneChanged` — clears the keystone context on leaving the party instance (`Compat.InPartyInstance`), re-arms it on re-entry to an active key; Retail only, since it serves only the keystone | `modules/Attribution.lua` |
| `CHALLENGE_MODE_RESET` | `OnChallengeModeReset` — clears the keystone context; Retail only | `modules/Attribution.lua` |
| `TRADE_ACCEPT_UPDATE` | trade context (on mutual accept) | `modules/Attribution.lua` |
| `QUEST_TURNED_IN` | `OnQuestTurnedIn` (questID detail; the reward stamp itself comes from the `GetQuestReward` hook below) | `modules/Attribution.lua` |
| `UNIT_SPELLCAST_SUCCEEDED` (player-only) | `OnSpellSucceeded` → DISENCHANT/MILLING/PROSPECTING by spell id first, then a locale-independent localized name-family fallback (the seed lists are per client: Disenchant alone on WoW Forever) | `modules/Attribution.lua` |
| `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` | `ApplyVisibility` — the two combat edges the `settings.visibility` dropdown is about; only ever **hides** a window the setting has stopped allowing, never opens one. `PLAYER_REGEN_DISABLED` also ends a running test mode (`BrowserTable:EndTestModeForCombat`: one chat line, the **Test mode** box unticks, the window is not opened) | `modules/Browser.lua` |
| `hooksecurefunc("BuyMerchantItem")` | `StampVendor` (vendor context) | `modules/Attribution.lua` |
| `hooksecurefunc("TakeInboxItem")` / `("AutoLootMailItem")` | `StampMail` → MAIL, or AH for Auction-House mail | `modules/Attribution.lua` |
| `hooksecurefunc(C_Container.UseContainerItem)` | `OnContainerItemUse` → CONTAINER (opening a lootable bag item) | `modules/Attribution.lua` |
| `hooksecurefunc("GetQuestReward")` | `StampQuestReward` → QUEST (stamps before the reward pushes) | `modules/Attribution.lua` |
| `hooksecurefunc("RepairAllItems")` | `StampOut("REPAIR")` for gold leaving | `modules/AttributionOut.lua` |
| `hooksecurefunc("BuyMerchantItem")` (second hook) / `("BuybackItem")` | `StampOut("BUY")` | `modules/AttributionOut.lua` |
| `hooksecurefunc("DeleteCursorItem")` | `StampOut("DESTROY")` for an item leaving | `modules/AttributionOut.lua` |
| `hooksecurefunc("SendMail")` / `("TakeInboxMoney")` | `OnSendMail` stamps `MAIL_SEND` and stages `pendingMail` (an own alt as recipient makes a `MOVE` into its mail); `OnTakeInboxMoney` stamps `AH_SOLD` for a sale's money | `modules/AttributionOut.lua` |
| `hooksecurefunc(C_AuctionHouse.PostItem)` / `PostCommodity` | `OnPost` records the quantity posted and stamps `AH_POST_FEE` | `modules/AttributionOut.lua` |
| `hooksecurefunc(C_AuctionHouse.PlaceBid)` / `ConfirmCommoditiesPurchase` | `OnAuctionBuy` stamps `AH_BUY` | `modules/AttributionOut.lua` |
| `hooksecurefunc(C_TradeSkillUI.CraftRecipe)` / `CraftSalvage` / `CraftEnchant` | `OnCraft` opens the `CRAFT_TTL` window that attributes reagent losses to `CRAFT_REAGENT` | `modules/AttributionOut.lua` |
| `GuildBankFrame` `OnShow` / `OnHide` (`HookScript`) | sets and clears the `guildBank` scope | `modules/AttributionOut.lua` |
| `CHAT_MSG_MONEY` | `OnChatMsgMoney`: the player's own looted money and party share (`YOU_LOOT_MONEY`, `LOOT_MONEY_SPLIT`, `YOU_LOOT_MONEY_GUILD`); writes the rich `GOLD` row and posts its claim. Gated by `trackLedger` and `recordGold` | `modules/Collector.lua` |
| `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` / `_HIDE` (second registration) | `OnInteraction` on a separate target: sets and clears `State.scopes` (merchant, trainer, taxi, mailbox, auction, bank, guild bank) for the reason picker | `modules/AttributionOut.lua` |
| `MAIL_SEND_SUCCESS` / `MAIL_FAILED` | `OnMailSent` confirms the staged send to an own alt (inside a 10 s window); `OnMailFailed` drops it | `modules/AttributionOut.lua` |
| `TRADE_ACCEPT_UPDATE` (second registration) | `OnTradeAccept`: on mutual accept stamps `TRADE_GIVE` for losses and names the partner | `modules/AttributionOut.lua` |
| `ADDON_LOADED` | `HookGuildBankFrame` when `Blizzard_GuildBankUI` loads (the frame is load-on-demand; `GUILDBANKFRAME_*` events never fire on 12.x) | `modules/AttributionOut.lua` |
| `BAG_UPDATE` | marks `bags`, `bank` or `tabs` dirty by bag id; no scan | `modules/Reconciler.lua` |
| `BAG_UPDATE_DELAYED` | arms the 0.35 s flush fuse (`NS.After`) | `modules/Reconciler.lua` |
| `PLAYER_EQUIPMENT_CHANGED` | marks `equipped`; arms the fuse | `modules/Reconciler.lua` |
| `PLAYER_MONEY` / `ACCOUNT_MONEY` | marks `money` / `warbandMoney`; arms the fuse | `modules/Reconciler.lua` |
| `CURRENCY_DISPLAY_UPDATE` | `OnCurrencyUpdate` folds the event's own change into a per-id accumulator (marks `currencyDelta`); a nil id marks `currency` for a full list rescan; arms the fuse | `modules/Reconciler.lua` |
| `CURRENCY_TRANSFER_LOG_UPDATE` | flags an account currency transfer so the next flush pairs it as a MOVE to the own alt; arms the fuse | `modules/Reconciler.lua` |
| `PLAYERBANKSLOTS_CHANGED` / `PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED` | marks `bank` / `tabs`; arms the fuse | `modules/Reconciler.lua` |
| `BAG_CONTAINER_UPDATE` / `BANK_TABS_CHANGED` | the bank's re-read cues (both clients, ruling R8): at an open bank, marks `bank` (and on Retail `tabs`); arms the fuse | `modules/Reconciler.lua` |
| `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` / `_HIDE` | `OnInteraction`, table-driven by `R.BANKER_ARMS` (keyed by `Compat.BankerKind`) and `R.READABLE_ON`: a Banker or CharacterBanker (both clients, ruling R8), or on Retail an AccountBanker, makes the bank readable (marks bank, and on Retail tabs and warband gold), the mailbox makes `mail` readable, the auction house arms `auctionHouse`; a final `Flush` on hide, then unreadable | `modules/Reconciler.lua` |
| `MAIL_INBOX_UPDATE` | marks `mail` while the mailbox is open; arms the fuse (the column is read by `modules/Escrow.lua`'s scan step) | `modules/Reconciler.lua` |
| `OWNED_AUCTIONS_UPDATED` | while the auction house is open, makes the owned-auctions list readable and marks `auctions`; arms the fuse | `modules/Reconciler.lua` |
| `PLAYER_REGEN_ENABLED` | runs a login reconcile deferred by combat, else replays a deferred flush | `modules/Reconciler.lua` |

All flavor-varying or deprecated calls behind these handlers are routed through
`core/Compat.lua` (the compat firewall) — no inline `WOW_PROJECT_ID` branching in feature code. So is
every read a simulated loot run has to answer — the loot window (`NumLootItems`, `LootSourceGUID`), the
where-am-I stamp (`Zone`, `PlayerMapID`, which `NS.Zone`/`NS.PlayerMapID` forward to), the instance,
group and combat reads, the class token, and every read-side hook (`HookSecure`/`HookSecureMember`) —
because `LibKa0s-Sim-1.0`'s answer seam wraps Compat members and nothing else
([compat-layer.md](compat-layer.md#the-simulator-relevant-reads); `tests/test_compat_routing.lua` pins it).

**Every event row above registers through one per-event helper** (events-frames-taint-§1; for the
capture rows, inside `NS.RegisterRows`):
`NS.SafeRegisterEvent` / `NS.SafeRegisterUnitEvent` / `NS.SafeRegisterEvents`, `LibKa0s-Core-1.0`'s
(Core minor 8) published by `core/CoreSetup.lua`, so a name the client refuses costs only itself. The
refused names land on the addon's own `NS.RejectedEvents`, which `/lh debug events` prints and the
diagnostics report carries;
[midnight-quirks.md](midnight-quirks.md#unknown-event-names--one-refusal-costs-one-edge) records the trade.

---

## The simulator

`/lh sim` (LootHistory#37, on `LibKa0s-Sim-1.0`, LibKa0s#53 and #54) runs the **real capture
engine** against an invented world, solo and outside an instance. The edges are invented: the
seam's providers answer the world reads, and the drivers fire the client's events and play its
hooked calls as `hook:<name>`. Everything between the edges is the live code, so a simulated row's
source or reason is the one `Attribution`, the `Collector`, the `Reconciler` and `Ledger.PickReason`
decided. The simulator never writes a row, a source or a reason itself. Six scenarios ship (`loot`,
`key`, `vendor`, `ah`, `bank`, `social`); the four that record through the ledger refuse while
`settings.trackLedger` is off. Nothing a simulation records is saved: the capture paths write
session stores, and the History, Insights, Holdings and Timeline tabs read them while it runs. The
library owns the seam, the session, the step machine, the verb grammar and the step panel, which
every successful start shows (the typed start and restart, the panel's Start row and picker, a host's
own `Sim:Start`; Sim 5, LibKa0s v1.113.0, held by `tests/test_sim_panel.lua`, FB2-LH-01); this
addon owns the world, the drivers, the scenarios, the store swap, the refusals and the marker, and
keeps its own fields on `NS.SimHost` and `NS.SimStores`, never on the library instance. The data
path is in [data-flow.md](data-flow.md#simulator); the design is
`docs/superpowers/specs/2026-10-22-in-game-simulator-design.md`.

The library's host contract, and where this addon meets each point:

| Point | What it asks | Where it is met |
|---|---|---|
| H1 | Every client read the simulator answers is an `NS.Compat` member, read at call time | `core/Compat.lua` (`NumLootItems`, `LootSourceGUID`, `Zone`, `PlayerMapID`, `InInstance`, `InGroup`, `PlayerInCombat`; read-side hooks through `HookSecure` / `HookSecureMember`); `tests/test_compat_routing.lua` |
| H2 | The seam is built straight after the Compat file, and nothing escapes its wrap | `core/SimSeam.lua`, the LOAD-BEARING TOC line after `core\Compat.lua`; `tests/test_sim_seam.lua` asserts `NS.SimSeam:Unwrapped()` is empty |
| H3 | One `deliver` that reaches the client's handlers, in the client's order, for any event name | `NS.DeliverAll` over `NS.EVENT_ROWS` / `NS.HOOK_ROWS` (`core/Dispatch.lua`, [§ Event subscriptions](#event-subscriptions)) |
| H4 | Session-only storage for every capture-path write, proven byte-identical | `NS.SimStores` and one accessor per store ([§ Data model](#data-model)); `tests/test_sim_store.lua` |
| H5 | The refusal covers stood-down, test mode and the world; test mode refuses while a simulation runs | `NS.SimHost.Refusal` (`modules/Sim.lua`) and `testModeRefusal` (`modules/BrowserTable.lua`) |
| H6 | The stand-down stops it first; host reasons stop it | `call("SimStop")` first in `STAND_DOWN_STEPS` (`core/LifecycleSetup.lua`); `NS.OnProfileEvent` (`profile`); the world watch (`group`, `instance`, `combat`); real interference (`world`) |
| H7 | One feature-verb row, `sim`, refused while disabled, no launcher entry | `settings/Schema.lua`'s `NS.COMMANDS` row, not in `LIVE_WHILE_DISABLED`; no key binding. The launcher's Sim mode entry and the Master controls Sim mode box (R6-SIM, LibKa0s compose minor 19) are the same verb through the one `NS.IsSimMode` / `NS.ToggleSim` pair; since R7-SIM the pair reads the sim window shown or a sim running, and `NS.WatchSimWindow` refreshes the box on the window's OnShow and OnHide |
| H8 | A preview-mode marker, a diagnostics section and a debug tag | The cyan simulation strip (one strip per mode; the `SIM` title badge only as the degraded fallback) and the footer (`modules/Browser.lua`, [browser.md](browser.md)); the `sim` diagnostics section (`modules/Diagnostics.lua`); the `Sim` tag ([debug.md](debug.md)) |
| H9 | An inert stub without the library, with surface parity | `NS.SimHost.NewSeamStub` / `NewSimStub` (`core/SimSeam.lua`); `tests/test_surface_parity.lua` |
| H10 | The panel's position | Session-only by the owner's ruling (OWNER_SCOPE C.11): held in the library instance's memory, never a window-state key and never a schema row, so a simulation writes nothing to SavedVariables |

**While a simulation runs**, a real event that interferes (the player's own loot, currency or
money line, a loot window, an encounter or key start, a quest turn-in, a trade, a sent mail, an
interaction frame, any real hook call) stops it with reason `world` and is then recorded live into
the saved stores, so no real loot is lost; other real events are absorbed, and the stop's drift scan
picks up what they changed. Joining a group, entering an instance or combat stops it too. The
destructive surfaces (purge, the ledger reset, Forget this character, a row's Delete and a retention
change that would prune) refuse with one line until it stops.

---

## Menus: two mechanisms, on purpose

Neither menu is a Blizzard `UIDropDownMenu`. The ten flat dropdowns are `LibKa0s-Widgets-1.0`'s,
sharing one process-wide popup that every non-click close path shuts with `NS.CloseMenu()`; the
History row's right-click action list stays hand-rolled because it needs per-row disable. See
[browser.md](browser.md#menus-two-mechanisms-on-purpose).

---

## Frame layering

Every strata this addon writes is read from the one layers table, `NS.Constants.LAYERS` in
`core/Constants.lua` (frame-layering-§5), whose header comment states the whole stack, the library's
and Blizzard's tiers included. The addon owns three tiers, by the standard's keys: `WINDOW` (HIGH:
the History window, toplevel and clamped, every pane inside it inherited), `MODAL` (DIALOG: the
Export modal, toplevel and clamped) and `POPUP` (FULLSCREEN_DIALOG: the row context menu, clamped,
dismissed by `GLOBAL_MOUSE_DOWN` with no click catcher, closed by the window's `OnHide` and the
disable ladder). It writes no frame level; the library's grip (+10) is the only explicit band in a
window. `tests/test_layers.lua` pins all of it through the kit's layer recorder.

## Tooltip placement

Every tooltip this addon places itself opens where the hovered element sits in its window, never at
the pointer (standalone-windows' *Tooltip placement*, adopted by AD-92-LH, LibKa0s#92). The one host
seam is `core/Compat.lua`: `Compat.OwnTooltip(owner)` owns `GameTooltip` at `ANCHOR_NONE`, and
`Compat.PlaceTooltip(owner, place)` places it, after it is filled and shown, through
`LibKa0s-Tooltip-1.0` read at call time. Every `Show*` helper there owns, fills, shows, then places
the same way, taking the caller's `place`:

| `place` | Element | Placer | Where it opens |
|---|---|---|---|
| nil / `"body"` | a **body** element: a History row, a column header (History and Holdings), a Holdings row, a Timeline strip column, legend entry and the plot's hover, an Insights gains-vs-losses bar | `PlaceBeside(tip, el, nil)`, the group being `GroupOf`: the History window | beside the window, right when it fits else left, its top level with the element's, 2 px off; an item tooltip's Shift-compare opens further out on the same side |
| `"chrome"` | a **chrome** element: the mode strip under the title bar, a filter-bar button (Export, Clear, Save, Reset), the Timeline's **Total only** toggle on the tab's header band | `PlaceAttached(tip, el)` | centered above the element, below it only with no room above |
| a function | an Insights chart mark (bar, segment, list row, legend chip, strip column) | the Charts host's `ctx:PlaceTip(tip, owner)` (Charts minor 2), handed to `showTip` as its fourth argument | beside the window group, level with the mark |

With unreadable geometry a body tooltip tries `PlaceAttached`, and when no placer places it (or a
degraded install has no Tooltip major) it is attached above the element (`BOTTOM` on its `TOP`, 2 px):
never the cursor, never a corner. The History window registers no companions; `GroupOf` answers the
window itself, its docked mode strip and footer being its children. A tooltip the library placed
is placed again when it grows after Show (an uncached item or currency whose data arrives late: the
Tooltip docs' step 4): a one-time `OnSizeChanged` hook on `GameTooltip` runs `Tip.Replace` while the
element it was placed for still owns the shown tooltip, so a late-growing tooltip near the screen's
bottom is re-clamped rather than running off it. The export modal's buttons carry no tooltip. `ShowCursorTooltip` (Insights'
cursor-pinned line) is retired, and the ledger bars' and Timeline's `ANCHOR_CURSOR`, the headers' and
filter-bar buttons' `ANCHOR_BOTTOM`, the legend's `ANCHOR_TOP` and the rows' `ANCHOR_RIGHT` are gone.
`tests/test_tooltip_place.lua` pins the seam on the kit's fake screen, each surface's suite pins its
hover through `tests/tip_spy.lua`, and a static guard fails any `ANCHOR_*` other than `ANCHOR_NONE`, or a
`GetCursorPosition`, in a shipped file outside the allowlist below.

**Left as they are** (the rule's *What it does not bind*), each in the guard's allowlist or outside
this addon's code:

- **The AH price tab's (i) marks** (`settings/PanelAuction.lua`, `ANCHOR_RIGHT`): they sit on a
  Blizzard Settings canvas page, which the rule does not bind.
- **The minimap button and the broker row** (`core/LauncherSetup.lua` fills one line): the launcher
  library places the minimap tooltip (`PlaceLauncher`, Launcher minor 11, launcher-§7), and a broker
  display places its own.
- **The filter bar's dropdown menus and the row context menu**: the library's dropdown entries are
  the library's to place, and the row menu's entries carry no tooltip.
- **The library's own windows** (the debug console, the copy window, the sim panel, the skin picker)
  and the title-bar marks (`W.HeaderButtons`, `AttachTitleTip`): placed by LibKa0s v1.105.0.
- **The holdings block appended to any item or currency tooltip** (#34, `modules/HoldingsTip.lua`): it places nothing. It adds lines to a tooltip someone else owns, through `Compat.AppendTooltipRows`, and never calls `SetOwner` or `PlaceTooltip` (`tests/test_holdings_tip.lua` pins it through `tests/tip_spy.lua`).
- **`AnalyticsCharts.lua`'s `ANCHOR_TOP`**: not a placement. It is the legacy anchor the Charts library
  still hands a host's `tip` for a strip column, read only to pick that column's line token.

---

## Skins

LootHistory is the collection's first skin adopter (skinning-§3; Ka0sAddonsCommonTasks
`docs/2026-10-25-SKINNING/`, leg 1). Every visual element paints through the `LibKa0s-Skin-1.0`
facade with this addon as its **owner**.

- **The seam.** `core/SkinSetup.lua` registers the owner `"LootHistory"` (the folder name) at file
  load with its read and write seams (`NS.SkinChoice`, `NS.WriteSkinChoice`, both through
  `NS.Schema`), publishes `NS.Skin` (the owner's facade) and the call-site helpers `NS.SkinColor`,
  `NS.SkinRGB`, `NS.SkinEscape`, `NS.SkinBar` (a bar of data in the skin's bar texture),
  `NS.QualityColor`, `NS.SkinPaintAce` / `NS.SkinPaintAceTree` / `NS.SkinOnRelease`. Its degraded arm answers every facade name from `NS.SKIN_FALLBACK`, a host copy
  of the Ka0s Default tokens this addon reads, which `tests/test_surface_parity.lua` holds to the
  library's values. The choice is two profile keys, `settings.appearance.source` and `.skin`, and the
  tab's Scope two more, `.ignorePanel` (**Ignore settings panel**: this addon's settings pages stay
  the client's; on in a new profile) and `.ignoreFonts` (**Ignore fonts**: every string keeps its own
  face and size), applied through `NS.ApplySkinIgnore` (`Skin:SetIgnore`, live both ways), and the
  tab's Font and texture two more, `.font` and `.texture` (an LSM key each, `""` for the skin's own),
  applied through `NS.ApplySkinOverride` (`Skin:SetOverride`, live), and its Font outline one more,
  `.outline` (`all`, `hud` or `off`; LibKa0s v1.82.0), applied through `NS.ApplySkinOutline`
  (`Skin:SetOutline`, live) ([schema.md](schema.md)). All seven are drawn by the library's Skin tab
  (key `Appearance`) on the General page, just before Keybindings
  ([settings-panel.md](settings-panel.md)). An eighth key, `.pickerSeen`, is the first-run skin
  picker's memory, and `/lh skin` (`NS.RunSkinVerb`, the library's `O.SkinVerb`) opens the picker
  again on demand.
- **The first-run skin picker.** `NS.MaybeShowSkinPicker` shows the library's picker
  (`O.SkinPicker`, LibKa0s OptionsSkinPicker 2: titled "Choose a skin", with the brand on its own
  line above the dropdown, `frame.ownerLabel`, and the Skin tab's Font, Texture, Font outline and
  Scope rows under it, LibKa0s v1.83.0) while the profile's `pickerSeen` is false: two
  seconds after login on an addon that stands up, and after every profile event. Never while the
  addon stands down; in combat it waits for `PLAYER_REGEN_ENABLED`. A pick only previews (the skin
  is worn, not saved), and so does a change on its rows; **Apply** and the gear save what moved
  through `NS.WriteSkinChoice`, and the close control and Escape put back the old skin and whatever
  the rows previewed. Apply, the close, the gear and Escape set the key, and
  so does another Ka0s addon's **Apply to all Ka0s addons** for this picker while it is queued
  (one picker is up at a time across Ka0s addons; a queued call answers `nil, "queued"`).
  `NS.HideSkinPicker` (the stand-down, and first on every profile event, so the put-back lands
  before the new profile's skin) takes it down without setting it. Its preview is test mode (`spec.preview`, LibKa0s
  OptionsSkinPicker 11, R6-PV): opened with the History window hidden and test mode off, the picker
  turns test mode on through `BrowserTable:SetTestMode` (the start opens the window); the eye toggles
  it; every close puts back the mode it opened with, and hides the window again when the preview
  opened it.
- **Repaint flow.** `NS.ApplySkinChoice` runs right after `NS:InitDB` and first on every profile
  event (`core/LootHistory.lua`), applying the stored Scope, overrides and Font outline with the stored skin, and
  from each Skin tab row with only its own half. It calls
  `Skin:SetChoice`, which resolves the skin, repaints every frame recorded for this owner (each
  primitive re-runs in repaint mode) and then fires `NS.Skin.OnLooksChanged`. Surfaces that cannot be
  repainted in place subscribe there: markup built once (sort arrows, AH ticks), pooled rows (both
  pool lists are walked), Insights' palette, the Timeline model, the AH price table. Nothing keys off
  `SETTINGS_CHANGED`. No reload, no OnUpdate, no events; `settings.alpha` stays whole-window opacity.
- **The EllesmereUI provider.** The library's (`SkinEUI.lua`). With source `eui` and its gate holding
  (EllesmereUI's `RegisterSkin` and `EllesmereUIBlizzardSkin` loaded, third-party skins on, this
  addon not switched off in its list), EllesmereUI's facade paints the vocabulary it has; otherwise
  the addon wears its Ka0s skin and the Skin tab names the failing condition. Ka0s to
  EllesmereUI applies live; EllesmereUI back to Ka0s asks for a reload. The read of `EllesmereUIDB`
  is the library's documented deviation, not this addon's.
- **Owners on every library surface.** Each LibKa0s factory is handed the owner in the form it reads:
  `opts.owner` for the dropdown (and the shared menu it opens), the search box, its autocomplete
  list, the mode strips, the History window's footer (`W.Footer`), the line chart and the AH drag
  list (`core/WidgetsSetup.lua`), and both windows' title-bar marks (`W.HeaderButtons` through
  `NS.MakeHeaderButtons`, AD-86-LH); the
  descriptor's `addonName` for the debug console and its copy window (`core/DebugLogSetup.lua`), the
  export copy window (`modules/Export.lua`), the perf panel (`core/PerfSetup.lua`) and every close
  mark (`NS.MakeCloseButton`); the Sim descriptor's `name` for the sim panel (`modules/Sim.lua`); the
  Options instance's `addonName` for the settings chrome. The console and both copy windows pass **no
  `applySkin`**, because a host hook owns the whole job and the library never paints over it.
  `tests/test_skin_tools.lua` pins each.
- **The Scope's settings-panel half (LibKa0s v1.81.0; D-01 to D-03 of the skin library
  follow-ups).** *Ignore settings panel* covers the settings panel and nothing else: every window
  (History, Export, the debug console, the copy windows, the perf and sim panels, the strips, the
  first-run picker) wears the skin whatever it says. On the panel, the AceGUI rows and the Options
  chrome are the library's; the AH drag list is panel-scoped by default (WidgetsReorder minor 3, so
  the seam passes no `panel`); and the AH price table's own paints go through `NS.SkinPanelColor`
  (Ka0s Default's value while the panel is ignored, `NS.SkinPanelIgnored()` being the public
  `Skin:GetIgnore` panel half) and its strings through `S.Text(fs, token, { panel = true })`, so one
  page never mixes stock and skinned. No dropdown, search box, strip, chart or autocomplete of this
  addon sits on the settings panel, so none passes `panel = true`. *Ignore fonts* reaches every string
  the library paints; this addon has no HUD.
- **The typed-value gate.** The kit's `test_skin_values` (revision 50, `Kit.skinValues` in
  `tests/run.lua`) fails on a typed color or a client texture path in every tracked file under
  `core/`, `modules/` and `settings/`, outside the kit's shared categories and a host's allow rows. It
  reads the kit's color calls and this addon's three paint helpers, `NS.SkinBar`, `setCell` and
  `NS.IconMarkup`. A row that matches nothing fails.
- **The switch test.** The kit's `test_skin_switch` (`Kit.skinSwitch`) flips each surface
  `tests/skin_surfaces.lua` declares to a probe skin and fails one that draws the same. A surface is
  one painted object, because the kit counts a change anywhere under what `build` answers. From kit
  revision 58 each setter family moves on its own, and the bars of data (a strip bar, a ranked source
  bar, a per-character segment, a ledger half, a Timeline flow column) say `expect = "texture"`, so a
  fill whose texture stopped following fails even while its tint moves; the two source-colored ones
  hold their color (`hold = "color"`, the per-source meaning table). The harness loads no
  LibSharedMedia, so while a fixture stands `tests/skin_surfaces.lua` installs a fake that answers each
  skin's statusbar key with a path of its own. Font keys are left out of it: resolving them took the run to
  259 MB above its start, past the kit's 256 MB leak budget (measured 2026-11-20, SD-SK-LH.1).

### Intentional exceptions

**Three allow rows, each a meaning color (cause MC).** The five rows the addon's own color gate carried
went when the kit's check replaced it, because a kit category takes each of them: the item quality's
client color (`qualityHex`), chat output (`NS.PREFIX` and the get/set echo) and the simulator's fixture
hyperlinks. The fifth, the ledger reset prompt's gold headings, is gone: they read `gtip.title` through
`NS.LedgerResetText()` (`settings/Slash.lua`), built again on every offer (the owner's U-7, SD-SK-LH.3). Test kit revision 58 (LibKa0s v1.108.0) reads colors kept in a table or a `return` as well,
and three of those no kit category takes: the degraded title badges' red and cyan (`TEST_MARK` and
`SIM_MARK` in `modules/Browser.lua`, drawn only with no `W.TestStrip`) and the common quality's white
that `qualityColor` (`modules/BrowserTable.lua`) answers for a quality the client has no color for.
The Insights per-source palette is named `SOURCE_CATEGORY_COLOR` in `modules/AnalyticsFormat.lua`, so
the kit's meaning-table category takes it as a named meaning table (skinning-§9).

Outside the gate's reach, also on purpose:

- **Alpha literals** over token components (`SetColorTexture(r, g, b, 0.95)` in the Insights bars,
  the ledger half and the Timeline strip) are the surface's opacity, the same under every skin.
- **`SOURCE_COLOR`** in `modules/AnalyticsFormat.lua`: a loot source's identity across skins; no token
  names it (LH-04).
- **The TEST MODE / SIM badge colors** in `modules/Browser.lua`: drawn only on a degraded
  install, where no skin exists and the badge stands in for the strip.
- **Fonts.** The skin's face reaches every text the addon shows. The facade's primitives draw their
  own (title bars, buttons, edit boxes, dropdowns, `S.Text`, the AceGUI controls), and the addon's own
  FontStrings built from `GameFont*` templates (table cells, Insights, the Timeline, Holdings, the AH
  table, the filter bar's hint) take the skin's face through `S.Font`, face only, their colors still
  the addon's. Sizes are relative to Ka0s Default's (LibKa0s SkinPaint minor 4), so each keeps its
  template's size scaled by the skin's, and the layouts measured against it hold. Every skin names
  a face of its own (Ka0s Default's is Prototype, LibKa0s SkinDefs minor 18; WoW Default's is the
  client's Friz Quadrata), so outside WoW Default the addon's strings no longer read in the
  `GameFont*` templates' Friz Quadrata; with **Ignore fonts** on,
  every string keeps its own face and size and the skin still colors it. Two strings stay on their own face: the row's
  direction glyph (the mono font, for its arrows) and the close button's mark. The browser's top tabs
  are the skin's `S.Tab`, so their labels read `tab.text` / `tab.onText` on the backing it draws
  ([browser.md](browser.md#tabs)).
- **The minimap button and the broker tooltip's frame** stay stock: LibDBIcon gives every addon's button
  one look, and the LDB tooltip's frame and backdrop are the client's. The lines follow the skin: the
  library paints its title, status and hint lines from `gtip.title`, `gtip.line`, `gtip.on` and
  `gtip.off` (`libs/LibKa0s/Launcher.lua`), and the host's one line, the record count
  (`core/LauncherSetup.lua`), takes `gtip.subtle` (the .7 gray it drew).
- **`GameTooltip`'s backdrop is never restyled.** Host tooltip lines take `gtip.*` tokens through
  `core/Compat.lua`'s Show* helpers; the frame is Blizzard's.
- **Stock Blizzard dialogs and pickers**: the reset and purge `StaticPopup`s and `ColorPickerFrame`.
- **Constants' semantic tables** need no entry: the tables LH-04 kept are values, not paint calls,
  and the meaning colors that moved became `sem.*` tokens.

---

## Taint notes

- The **browser is a plain non-secure `CreateFrame`** (per standalone-windows) — it touches no protected
  functions and needs no combat-lockdown gate. It can open/refresh in combat.
- The **Settings panel** uses the canonical Blizzard `Settings.RegisterCanvasLayoutCategory`
  canvas with a **lazy, combat-locked** AceGUI body — opening is refused in combat, and a page on
  screen in combat is covered and refuses writes until `PLAYER_REGEN_ENABLED` (the library's lock,
  options-ui-§2; the addon keeps no guard of its own on the settings surface).
- Attribution uses `hooksecurefunc` (post-hooks only) on `BuyMerchantItem` / `TakeInboxItem` /
  `AutoLootMailItem` — these observe, never replace, and carry no taint.
- The **holdings tooltip block** (#34) observes through `TooltipDataProcessor.AddTooltipPostCall` for the Item and Currency data types (each resolved by name, client-quirks-§5 Q18) and never replaces a Blizzard function. It reads only `data.id` and `data.hyperlink`, each through `Compat.IsSecret` first (Q17); a line's text is never read, compared or concatenated. Appending lines and calling `Show` on `GameTooltip` is what Blizzard's own post calls do, and the tooltip is not a protected frame, so it runs in combat. Comparison tooltips and forbidden tooltips are skipped.
- No secure templates, no protected action buttons, no `SetAttribute` — the addon is purely
  observational, so it cannot taint the loot/combat path.

---

## Standards compliance

[§ Documented deviations](#documented-deviations) is the register, and a deviation in it is
*ratified*: an audit records it as accepted rather than re-filing it. Audit bundles are frozen the
day they are written and this file is not, so where the two disagree the register is the current
answer. The pricing shims outside `core/Compat.lua` are the one standing non-row, listed there.

---

## Documentation map

Every `.md` under `docs/` appears in exactly one table below (`documentation-§3`). Frozen and
generated material is out of scope, named once per directory and never enumerated per run:
`docs/audits/`, `docs/reviews/`, `docs/automated-tests/<run>/`, `docs/perf-analysis/<run>/`,
`docs/revendor/<date>-v<tag>/` (the three earliest bundles, `2026-08-25`, `2026-09-03` and
`2026-09-12`, predate the `-v<tag>` suffix), `docs/seed-research/<date>-<flavor>/` and `docs/superpowers/`. The stores' own
`automated-tests/README.md`, `automated-tests/RESULTS.md` and `perf-analysis/README.md` are live
and registered below.

### Required (documentation-§3, Tier 1)

| Doc | Covers |
|---|---|
| `ARCHITECTURE.md` | This file — the hub: module map, data model, message bus, slash surface, event wiring, this map, and the documented-deviations register |
| `scope.md` | What the history records, and the loot it deliberately does not |
| `module-map.md` | Every non-vendored file, its responsibility, and load order |
| `schema.md` | `LootHistoryDB`’s two scopes (account-wide history, per-profile settings), the loot record, the settings rows, carve-outs, migrations |
| `settings-panel.md` | The panel tree, per-option behavior, and the write seam |
| `data-flow.md` | Loot event in → gate → attribute → record |
| `common-tasks.md` | Recipes for the changes made most often here |

### Conditional (documentation-§3, Tier 2)

| Doc | Status | Trigger |
|---|---|---|
| `slash-dispatch.md` | Present | The verbs in `NS.COMMANDS` |
| `midnight-quirks.md` | Present | Clients includes Retail (client-quirks-§1): carries the vendored client-quirks catalog, then the addon's own Retail bind-state and currency-API behavior it works around |
| `forever-quirks.md` | Present | Clients includes Forever (`Retail · Forever`, forever-quirks-§1): the vendored Forever catalog block, then the addon's own Forever workarounds (the bank model, the keyring, the socketed bank bag, the roll-won prefix, money text, two-word names) |
| `compat-layer.md` | Present | The shims `grep -cE '^\s*function\s+[A-Za-z_][A-Za-z0-9_]*\.' core/Compat.lua` counts, addon-specific shimming beyond LibKa0s |
| `message-bus.md` | Present | Shipped below the >10-message threshold, deliberately: the one-sender/one-target contract is what a receiver has to get right, and CallbackHandler's silent clobber is not something a three-row table in `ARCHITECTURE.md` can explain |
| `profiles.md` | Present | Every setting but the retention is per profile and a Profiles page ships (`settings/Profiles.lua`); the page says what a profile holds, what stays account-wide (the history and its retention, D6), the adopt path and the v9 and v10 moves |
| `debug.md` | Present | The diagnostics report (`/lh diagnostics`, `debug-logging-§14`) is a debug surface of the addon's own, and every Ka0s addon ships it |
| `perf-analysis/README.md` | Present | The in-game capture store: bundle naming, the three artifacts, schema pointer, how to capture with `/lh perf`, the capture index |

### Verification and record

| Doc | Covers |
|---|---|
| `testing.md` | How to run the harness and lint; the green commit gate |
| `smoke-tests.md` | The in-game smoke-test suite |
| `test-cases.md` | The generated case inventory (authoritative pass count) |
| `performance.md` | The harness: buckets and why, the zero-overhead evidence, how to capture |
| `automated-tests/README.md` | What the automated-test record is and how to produce it |
| `automated-tests/RESULTS.md` | One row per run; generated, never hand-edited |

### Addon-specific (documentation-§3, Tier 3)

| Doc | Covers |
|---|---|
| `browser.md` | The standalone History window: table, filter bar, menus, and the Insights tab |
| `combat-path-sweep.md` | The whole-repo event/timer inventory with per-fire work (kept as the event census; it no longer backs an exemption) |
| `disabled-state.md` | What *off* means here: the lifecycle latch and its holds, what stands down, what survives as setup, and the conformance suite |
| `forever-probes.md` | The WoW Forever port's probe sheet (ruling R4): what `/lh debug probe` records, the `/run` fallback per probe, and the safe default each one checks |
| `validate-seeds.md` | The seed-validation contract `/dev-copilot:validate-seeds` runs: the deconstruct seeds' flavors (`retail` on `wow`, `forever` on `wowf`), `tools/seeds/seeds.py`'s steps, the precedent a ruling follows and the gate |

## Documented deviations

The register (`documentation-§3`). **A deviation not in this table is not ratified** — the reasoning
may live at length in this repo's GitHub issues or in an audit bundle, and the **Why**
column cites that id, but an issue declining a rule with no row here is itself the deviation.
An audit reads this table, records these as accepted, and does not count them toward its MUST tally.

**Re-check trigger** is the condition that *ends* the deviation, written so a reader can tell whether
it has already fired. This table is **not a graveyard**: a row whose cited rule the standard has since
changed — so the behavior is now mandated or permitted outright — is retired, not kept for history.
Eleven such records are named below the table rather than carried in it.

| Rule | What differs | Why | Decided | Re-check trigger |
|---|---|---|---|---|
| `architecture-§5` | The **`settings.auction.priority`** ordered cascade, neither a schema row nor registry membership, is written to the active profile (`NS.db.profile.settings.auction.priority`) directly rather than through `NS.Schema:Set`. It is seeded empty on first read by `NS.AuctionPrice:GetPriority` (`modules/AuctionPrice.lua`) and written by `ReconcilePriority` / `MovePriorityWithin`; the global reset brings it back with the rest of the profile. | The cascade is an order over a **fixed** member set, the `NS.Constants.AUCTION_KEYS` tags, which the player only reorders. `architecture-§5` makes that a **value**, not a registry, and a value with no row is what its **MUST NOT** leaves a register row for. No schema row type expresses a drag-reordered list, so there is no row for `Set` to validate against. Reasoned in [`schema.md`](schema.md) *Standards note*. The id filter sets and the named non-setting state left this row on 2026-09-12; see below. | 2026-07-17 | `settings.auction.priority` gains a schema row, an ordered-list row type or a whole-value row, and every write to it goes whole through `Schema:Set`. That retires this row. |
| `options-ui-§1` | The inverted set pickers (`settings.excludedSources`, `settings.auction.capture`) are drawn by **this addon**, from `afterSubgroup` and `afterGroup` respectively, rather than by one of the library's widget makers. | The library's makers are checkbox / slider / dropdown / editbox / color picker; a wrapping `InlineGroup` of checkboxes whose stored value is the logical **inverse** of the tick is none of them, and `RenderGrid` takes no `parent` and would open a second overlapping scroll frame. The rows stay in the schema, so the CLI and every reset still see them. Closed issue [**LIBKA0S-14**](https://github.com/tusharsaxena/LootHistory/issues/20). | 2026-08-01 | `LibKa0s-Options-1.0` gains a multi-check / set maker with a `parent`, or a second host needs the same shape (one host, one shape is why it was not raised upstream). |
| `localization-§1` | This addon ships **English only**: the `NS.L` seam is exported and `locales/enUS.lua` ships, but only a handful of strings route through `NS.L` (the Profiles page name, the `profile` and `diagnostics` help descriptions, the library-absent line, and the History window's test-mode marks: the strip under the title bar, the strip's tooltip lines and the TEST MODE badge a degraded install shows in its place, and the Show window key binding's row label and its performance-capture refusal) — every other label, tooltip and message is a hardcoded English literal. | `localization-§3` names English-only as one of the routing SHOULD's **two terminal compliant states**, and names this row as what makes it terminal: without it the SHOULD is formally open and every audit re-files it, which is what has been happening. Both `localization` MUSTs are met unconditionally — the seam is exported with the key-returning fallback (`NS.L` in `locales/enUS.lua`) and `enUS.lua` ships carrying no dead keys. The argument was written in `locales/enUS.lua`, in the comment under the `NS.L` metatable, and calls itself "an accepted scope decision, not an oversight"; a comment is exactly what `documentation-§3` says does not ratify a decision, which is why `LH-48` in `docs/audits/2026-09-07/` filed it. This row is the ratification the comment was standing in for. | 2026-09-08 | **The first non-English locale file added to `locales/`.** That change routes the strings and retires this row. |
| `localization-§4` | **Deconstruct attribution falls back to matching a localized spell name.** `Attribution:DeconstructSource` resolves a player cast by spell id first (`DECONSTRUCT_ID`, `modules/Attribution.lua`); on a miss it compares the cast's **client-locale name** against tokens derived from seed spell ids (`NAME_SEEDS`; `seedToken` resolves each through `NS.Compat.GetSpellName`; the substring match is in `Attribution:DeconstructSource`), where §4 says a game entity is identified by id, never by a localized display string. The reasoning is in the comment above `DECONSTRUCT_ID`, which points at this row. | Modern retail splits Milling and Prospecting into generic, per-expansion and **per-herb / per-ore "Mass Mill" / "Mass Prospect"** spells, and that id set is **not enumerable**: it is too large and grows every patch, so an id-only table silently stops attributing each new variant. The compared names are **derived from ids on the same client** at match time, so no English literal is ever compared and the match is locale-correct by construction: "Milling" on enUS is "Mahlen" on deDE on both sides of the compare. Closed issue [#2](https://github.com/tusharsaxena/LootHistory/issues/2); audit finding `LH-74` in `docs/audits/2026-09-23/`. | 2026-09-24 | **Blizzard exposes a stable deconstruct token or category** on the cast (a spell category, a profession-action flag, anything id-shaped), **or the Mass Mill / Mass Prospect id set becomes enumerable** (a stable list or an API that returns it). Either one moves the fallback onto ids and retires the row. |

- Retired on 2026-11-25: the `testing-§15` row (*`tests/run.lua` passes `leakBudgetMB = 288`*, decided
  2026-11-25 in SF-LH-01's review fixes). Its re-check trigger fired when IS-LH-01 removed Item sources
  and `test_itemsources.lua` (Ka0sAddonsCommonTasks `docs/2026-11-25-ITEM_SEARCH/`): measured that day,
  a WoW Forever run ends about 255.5 MB above its start (276 MB live after `test_widgets.lua`, failing at
  a 255 MB budget and passing at 256), so the runner is back on the kit's 256 MB. The margin is under
  1 MB; the retention in the skin, Insights and panel suites is still there, and the next suite that
  adds a megabyte crosses it.
- Retired on 2026-11-21: the `layout-§1` row (*`modules/Browser.lua` stays in the 1000-1500 band*,
  decided 2026-10-31 at 1386 lines, `FX-LH-SIZE` of Ka0sAddonsCommonTasks `docs/2026-10-31-FINDINGS_REMEDIATION/`).
  Its 1400-line re-check fired at 1410 (`0a39972`, 2026-11-17), and the file reached 1477. The owner
  ruled fix (`FU-LH-BROWSER`): the view layer now reads the window state through `B` (`B:GetWindow`,
  `B:ActiveTab` and the new `B._tabSpec`, so the frame, the tab registry and the active tab keep their
  one writer in `modules/Browser.lua`), and the per-tab view layer moved verbatim on that seam to
  `modules/BrowserViews.lua`, taking `switching` and the parked `live` states with it. `Browser.lua` is
  988 lines and `BrowserViews.lua` 507, both below the band, so there is nothing left to record.
- Narrowed on 2026-09-12 ([#30](https://github.com/tusharsaxena/LootHistory/issues/30)): `settings.window` and `savedView` left the `architecture-§5`
  row as named non-setting state (standard v2.44.0), and LibDBIcon's `minimapPos`, never in it, is named beside them in [schema.md](schema.md#named-non-setting-state-owners-and-writers); the `B:SetupMinimap` seed over the minimap row's stored `minimap.hide` key was deleted.
- Narrowed on 2026-09-12: the id filter sets left the `architecture-§5` row, as a structural
  registry whose writer and load pass [schema.md](schema.md#the-id-filter-sets-a-structural-registry) names (history in `schema.md`, *Standards note*).
- Retired on 2026-10-06: the `performance-§12` row (*no perf harness is wired*, decided 2026-08-05,
  closed issue [**LIBKA0S-17**](https://github.com/tusharsaxena/LootHistory/issues/22) and the decline in
  [#29](https://github.com/tusharsaxena/LootHistory/issues/29)). Its re-check trigger fired: the timeline
  ledger put real work behind in-combat `BAG_UPDATE`, money and currency events, and the owner ratified
  wiring the harness (spec F2). `core/PerfSetup.lua` now brackets the in-combat handlers (six since #34's `tooltipBlock`), `/lh perf`
  is registered, and [performance.md](performance.md) is the harness page.
- Retired on 2026-10-02: the `library-stack-§8` row (*the History grip draws Blizzard's corner
  grabber, not the catalog's `resize` mark*, decided 2026-09-24, audit finding `LH-76`). Since
  [#33](https://github.com/tusharsaxena/LootHistory/issues/33) the grip is `Core.MakeResizable`'s, so
  the library draws that art on a working install and this addon names no mark there; the copy in
  `core/CoreSetup.lua`'s library-absent arm is the pre-library grip kept for a degraded install, a
  fallback rung like the multiplication-sign close ([common-tasks.md](common-tasks.md)).
- Retired on 2026-09-29: the `options-ui-§12` row (*three reset controls, three blast radii*,
  decided 2026-09-02). Profiles arrived (owner decision D5, settings only), so this addon now has
  both scopes, and §12 resolves itself for that case: the global reset is the profile reset and the
  account-wide history is not settings. `/lh resetall`, the Defaults button and Reset all settings
  are one act, `db:ResetProfile()` (`Sl:CliResetAll`), none of them touches the history, and
  `/lh purge` is the separately confirmed act for it ([profiles.md](profiles.md)).
- Retired on 2026-09-08: the `sessionOnly` row kind, which `options-ui-§15` and `options-ui-§12` now
  mandate (`LH-54` in `docs/audits/2026-09-07/`; the design is in [`settings-panel.md`](settings-panel.md)).
- Retired: [`LIBKA0S-02`](https://github.com/tusharsaxena/LootHistory/issues/19)'s declined window skin, since `Core.SKIN` is this addon's
  treatment as of Core minor 3 ([`LIBKA0S-18`](https://github.com/tusharsaxena/LootHistory/issues/25)).
- Retired: [`LIBKA0S-19`](https://github.com/tusharsaxena/LootHistory/issues/26)'s dropped `makeCloseButton`, since
  `standalone-windows` gives a library-drawn window's close control to the library.
- Never a row: the pricing shims outside `core/Compat.lua`, a gap in the standard rather than a
  deviation ([`compat-layer.md`](compat-layer.md#third-party-pricing-addons-stay-out-of-compat)).
- Never a row: the AH price table's pooled host, `ctx._priHost`, declined in closed issue [#21](https://github.com/tusharsaxena/LootHistory/issues/21).
  `options-ui` never names `SetRenderer`, so that declined a library adoption rather than a rule; the
  reasoning is in `settings/PanelAuction.lua`, the *THE HOST IS A RAW FRAME THIS ADDON OWNS FOR THE SESSION* comment (`LH-47` in `docs/audits/2026-09-07/`).

### Files over the 1500-line cap

The `layout-§1` census: one row per authored, tracked `.lua` file over 1500 lines, naming the
terminal state it sits in. Vendored code (`libs/`, `tests/_kit/`) is outside the cap. Gated by the
kit's `tests/_kit/test_layout_cap.lua`.

Nothing is over the cap today. The largest authored file is `tests/test_browsertable.lua` at 1494 lines,
then `tests/test_browser.lua` at 1348, `settings/Schema.lua` at 1337, `core/Database.lua` at 1336
and `tests/test_database.lua` at 1252 (`git ls-files '*.lua' | grep -v '^libs/' | grep -v '^tests/_kit/' | xargs wc -l`, 2026-11-27).
On 2026-11-27 (#34, M1.6) `core/Compat.lua` (1326 lines, past its 1200 re-check) shed the holdings
tooltip's reads verbatim to `core/CompatTooltip.lua` (277 lines), leaving 1105.
On 2026-11-27 the v1.118.0 re-vendor took `tests/test_libka0s.lua` to 1510 lines, and its per-tag release-pin
cases moved verbatim to `tests/test_libka0s_releases.lua` (796 lines), leaving 723.
On 2026-11-21 `modules/Browser.lua` (1477 lines) shed its per-tab view layer to `modules/BrowserViews.lua`
and is 988 lines (`FU-LH-BROWSER`). On 2026-10-31 `modules/BrowserTable.lua` shed its sample dataset to `modules/BrowserTableTestData.lua`,
`settings/Panel.lua` its AH price table to `settings/PanelAuction.lua`, and `tests/test_browser.lua`,
`tests/test_schema.lua` and `tests/test_slash.lua` their later sections to `tests/test_browser_filterbar.lua`,
`tests/test_schema_seam.lua` and `tests/test_slash_verbs.lua`; the
1000-1500 band is observed and dispositioned in the release watch list (`automated-tests-§4`), not here.

---

## Known limitations

- **WoW Forever is built from its interface files, not yet measured in game.** Every Forever row in
  [§ Per-client features](#per-client-features-clients-4) and [forever-quirks.md](forever-quirks.md) rests on the 1.60.1
  interface files and other addons' Forever code. Each has a safe default and a probe
  (`/lh debug probe`, [forever-probes.md](forever-probes.md)); an answer that contradicts its default
  becomes a follow-up item (ruling R3), and in-client smoke on both clients is the owner's.
- **Full source coverage.** Every `SourceType` member has a live capture path. Deconstruct abilities
  stamp their own `DISENCHANT`/`MILLING`/`PROSPECTING` source (player `UNIT_SPELLCAST_SUCCEEDED` by
  spell id); `AH` is stamped from Auction-House mail; `BONUS_ROLL`/`CRAFT`/`REFUND` are attributed
  straight from their self-identifying loot lines; `ROLL` is stamped from the "You won:" roll line
  just before the item's receive line (see [data-flow.md](data-flow.md)). `VENDOR`/`MAIL`/`TRADE`
  were confirmed recording in-client (smoke CAP-4 to CAP-6, review F-001, passed). NB: the `ROLL` path assumes the client
  emits `LOOT_ROLL_YOU_WON` ("You won:") rather than the compact "no-spam" roll variant — verify
  in-game (smoke CAP-9, review F-009).
- **No per-item source name.** The "From" column and its combat-log kill-name cache were removed:
  for the dominant real-world loot (containers, delves, pushed/quest items) no reliable name was
  resolvable, so the column was almost always blank. Records keep `source` and the machine-readable
  `sourceDetail` (npcID / encounter / keystone / questID); the human name is no longer captured or
  displayed.
- **Loot past a window's cover.** An open loot window names one line per slot however late it lands,
  and a closed one for `LOOT_LINE_GRACE` (5 s). A container opened from the bags has `CONTAINER_TTL`
  (4 s); anything later falls back to `OTHER` / `INFERRED`.
- **A currency under a collapsed Currency-tab header has no category.** `Compat.CurrencyCategory`
  rebuilds its cache once on a miss, but `C_CurrencyInfo.GetCurrencyListInfo` enumerates only the
  children of expanded headers, so such a row keeps `itemSubType = nil` and falls out of the subtype
  filter. The addon does not expand the list itself, since that would rewrite the player's Currency
  tab; see [midnight-quirks.md](midnight-quirks.md) *Currency category*.
- **Warband gold away from the bank is unverified** (spec §5.6, smoke LED-6). `Compat.GetWarbandMoney` wraps `C_Bank.FetchDepositedMoney`; whether the client answers it with no bank open is not yet recorded. When it answers `nil` the Warband's gold stays at its last read and ages on the Holdings tab instead of being shown as zero.
- **Escrow is holdings-only until resolved.** Items in the mail and owned-auction columns write no row while in flight (spec S6): a mail from another player, a posted auction and a pending sale surface as rows only when they resolve. The guild bank is outside the account by design (scope.md D3).
- **An AH sale is matched by item name.** The sale mail's subject (`AUCTION_SOLD_MAIL_SUBJECT`, `%s` = the bare item name) is compared with the exited item's stored name, so two same-name items with different ids can mis-attribute one resolution.
- **An unresolved exit is booked as sold after 30 days** (`Escrow.EXIT_TTL`). An auction that left the owned list and never came back by mail or named in a sale mail is written as `OUT AH_SOLD`.
- **Auction-exit reason labels can be wrong when several auctions of one item are out.** Exits are
  kept per item, not per auction: `commitExits` in `modules/Escrow.lua` (through `addExits`) adds
  each new exit to the item's one `escrow.exits` entry and overwrites its shared `ts`, so the 30-day `EXIT_TTL` clock
  restarts on every new exit. And one sale mail books **every** pending exit of that item as
  `OUT AH_SOLD`, so when some of those auctions in fact expired, their return mail lands later as a
  plain `IN MAIL` row instead of resolving the exit. Net counts stay correct; only the reason labels
  are wrong. The fix needs a per-auction `escrow.exits` schema and a migration, so it is not done.
- **The guild cut in `YOU_LOOT_MONEY_GUILD` lines.** The line's first amount may be pre- or post-guild-cut; whichever it is, the diff books the difference to the claim as a plain gold row. Smoke LED-P2-22 records which it is.
- **Own-alt trades are impossible today.** The client allows one online character per account, so the `TRANSFER` path for trades between your own characters is dormant; a trade to another player is `OUT TRADE_GIVE`.
- **Disabled at login: no scan until the next `PLAYER_ENTERING_WORLD`.** With `settings.enabled` off at login the Reconciler registers nothing and runs no `LoginScan`; enabling later schedules a resume scan (one second after `Enable`) only in a session that already logged in, so a session that started disabled reconciles at its next world entry.
- **Play elsewhere is `UNTRACKED`.** Changes made while the addon was not watching (disabled, not installed, or on another PC) are written as `UNTRACKED` rows: bags, gear, gold and currency at the next login or resume, the bank and warband tabs on the first read of the next banker visit ([data-flow.md](data-flow.md#login-and-resume-untracked)). Two PCs each running the addon keep separate SavedVariables, so each sees the other's play this way: holdings totals stay correct, but the reasons (loot, vendor, deposit) are lost. Cross-PC sync is out of scope.
- **Insights' Transfers card depends on the Direction filter.** Insights reads its own filter (per tab since P11), so under its default view (Gains + Losses) the Transfers card reads 0 until Transfers is ticked.
- **The Timeline starts at the upgrade.** A holder's line begins at its genesis, the first full scan after the ledger shipped, and there is no back-casting before it (ledger D5). Counts are per item id, not per variant (item level, bonus ids). A holder that has not logged in since the upgrade has no class, so it draws gray. Several Line-region facts can only be proved in the client (`Frame:CreateLine`, fractional thickness, the cursor-to-plot mapping, daylight-saving day labels); they are the TL-13 list in [smoke-tests.md](smoke-tests.md#timeline).
- **The simulator runs on the real clock.** `time()` and `GetTime()` are never seamed, so the
  Reconciler's 0.35 s debounce, its 1.5 s claim wait and its 6 s settle hold take real seconds, and
  a playing simulation waits on them through the ledger gate rather than skipping them.
- **Simulated items must be cached for full names.** The simulator's item, bind and price reads
  answer live from the client; an item the client has not cached yet records with the link's own
  name and color until it is.
- **The holdings tooltip is as fresh as each holder's last flush** (#34). An alt's stored counts date from its last ledger flush, and the block dims the oldest stored container a day or more old with its age. A bank never visited is not flagged in the tooltip; the Holdings tab shows that holder as partial.
- **The live bank and warband-bank counts depend on the client holding that bank's data.** The tooltip and the API read the logged-in character's bank, and on Retail the warband bank, live from `C_Item.GetItemCount` diffs. Away from a banker, a live 0 over a stored count above 0 reads the store (the zero-suspect rule), so the store wins until the next banker visit.
- **WoW Forever's tooltip post-call types and `GetItemCount` arity are assumed** from the interface files until smoke FOREVER-17 and FOREVER-18 pass ([forever-quirks.md](forever-quirks.md)).
- **`trackLedger` is per profile, the ledger account-wide.** A character on a profile with Track holdings and losses off sees no holdings block, and the public API answers empty for it.
- **No upgrade-scoring addon interop** (Pawn/Loot Appraiser). Auction-house price interop
  (Auctionator/TSM/OribosExchange) shipped in Rev-2 — see the AH-price cascade above and
  [schema.md](schema.md).

See the [GitHub issue tracker](https://github.com/tusharsaxena/LootHistory/issues) for the full backlog.

---

