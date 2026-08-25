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
settings canvas and the flat dropdowns. All libraries
are **vendored** in `libs/` and committed (Ka0s Standard v2.0.0 — externals forbidden); LibKa0s is
vendored **whole-folder**, because nine of its ten majors resolve `LibKa0s-Core-1.0` before
registering and a per-file copy is how cross-major skew gets manufactured.

---

## Module map

Load order is fixed in `LootHistory.toc`: vendored `libs/` → `locales/` → `core/` (Compat first) →
`defaults/` → `modules/` (Attribution and Filters before Collector) → `settings/` (last). Two
LibKa0s seams sit inside `core/`, and their positions are load-bearing rather than tidy — see
`core/CoreSetup.lua` below and [module-map.md](module-map.md) for the four constraints that pin them.

| File | Role |
|---|---|
| `core/Compat.lua` | **Loads first.** The compat firewall: every deprecated/varying-API shim gated by direct `C_*`/global presence (no `WOW_PROJECT_ID` game-flavor branching — Retail-only) — GUID decode + `UNIT_KINDS`, item/map/zone info, active keystone level, quality-from-link fallback. |
| `core/MediaSetup.lua` | The **`LibKa0s-Media-1.0`** seam: `NS.Icon` / `NS.MediaFont` / `NS.IconMarkup`, and `Media.RegisterLSM(addonName)` at **file load**. **Its TOC position is load-bearing** — it must sit above `core/Constants.lua`, which resolves `FONT_MONO` from `NS.MediaFont` at load. Paths are extensionless and point into the vendored payload (`libs/LibKa0s/media/`); `nil` is a real answer twice (no library, no such name), and every call site keeps its Blizzard rung underneath. This addon ships no font and no icons of its own. |
| `core/Constants.lua` | `SourceType` enum, `SourceOrder`/`SourceLabel`, `SOURCE_IMPLEMENTED` (coverage gate), `Confidence`, `CONTEXT_TTL`, `ITEMCLASS_QUEST` (Quest item-class id for the capture filter), `CURRENCY_TYPE` (the `"Currency"` type label for currency rows), `AUCTION_KEYS` (the AH-price key catalog), `FONT_MONO_NAME` / `FONT_MONO` (resolved from `NS.MediaFont` at load — see `core/MediaSetup.lua`), quality/retention/source option tables. |
| `core/Namespace.lua` | Bootstrap: sets `NS.name`, `NS.version`, `NS.PREFIX`. (`NS.L` is published by `locales/enUS.lua`; module tables self-publish idempotently.) |
| `core/State.lua` | Runtime state: `lootContext`, encounter/keystone context, session flags, session-only `debug`, and the session-only `testRecords` (the `/lh test` synthetic dataset). |
| `core/Util.lua` | Pure helpers: date-range (`RangeFrom`) + time/money/byte formatting, self-loot string parsing, `PlayerKey`, dotted-path split. |
| `core/CoreSetup.lua` | The **`LibKa0s-Core-1.0`** seam. Publishes the shared **secret-safe chat printer** — `NS.Print` / `NS.Format` / `NS.Util.print` (+ `IsConcatSafe` / `SafeToString`), the single seam every module prints through (events-frames-taint-§8), reclaimed from AceConsole's `:Print` in `core/LootHistory.lua` — which is why this file publishes to **both** keys. It also publishes **`NS.LIBKA0S_MISSING`**: one cause clause, appended to by every other LibKa0s seam in the addon, set outside the `if not lib` branch because they read it on both paths. A cross-file contract, not an implementation detail. Also publishes **`NS.ApplySkin`** and **`NS.MakeCloseButton`** — the latter wrapped once so `lib.MakeCloseButton`'s **third** argument, this addon's folder name, is passed from every close control it builds; a two-argument passthrough would run, return a button, stay green in every suite, and draw a multiplication sign forever (anti-patterns #64). |
| `core/WidgetsSetup.lua` | The **`LibKa0s-Widgets-1.0`** seam: **`NS.MakeDropdown(parent, width)`**, **`NS.HasWidgets()`**, **`NS.CloseMenu()`** and **`NS.CopyWindow(descriptor)`** — the export copy window, a lazily-built handle rather than a frame, so a session that never exports creates nothing. One factory for all ten flat dropdowns this addon draws — the filter bar's nine and the export modal's Data Set picker — and it is where the widget's art is resolved: a vendored library cannot know which addon folder it sits in, so `chevron` and `check` are looked up through `NS.Icon` **here** and passed in as parameters, once, rather than at each call site. It passes **no `glyphFont`** and that is a decision: the field is a *precondition* for any option carrying `opt.glyph`, no option this addon builds carries one (the multi-select tick is markup the library splices itself, the Character rows' class icons are markup folded into a label), and a proportional face passed for a glyph nothing draws renders a box. It replaced 208 lines of `modules/Browser.lua` — the collection's third copy of one widget. `nil` is a real answer both ways: `NS.MakeDropdown` returns nil with no library and both surfaces refuse to draw rather than build a control that opens no menu, and `NS.CloseMenu` becomes a no-op. **`NS.HasWidgets()`** is the same question asked with nothing built — a surface whose only control is a dropdown would otherwise have to create its window to learn the answer, and `modules/Export.lua`'s window carries a global name, so a build-and-discard probe stranded one `LootHistoryExportWindow` per open. |
| `core/DebugLogSetup.lua` | The **`LibKa0s-DebugLog-1.0`** seam: `NS.DebugLog` and the global `NS.Debug` sink. Replaced the 359-line `modules/DebugLog.lua`. The window chrome is deliberately split: `applySkin` **is** passed, as a closure resolving `NS.Browser` at frame-build time (hoisting it into a load-time local silently loses the skin — `modules/Browser.lua` loads long after `core/`), while **`makeCloseButton` is still deliberately not passed**. The descriptor does carry **`addonName = addonName` beside `name = addonName`**: `name` seeds the frame globals, `addonName` is what the library builds a texture path from, and that one line turns the console's title strip into three icon controls (`close`, `copy`, `clear`) on both the console and its copy window. The window *edge* is shared across every Ka0s window; the *close control* on a library-drawn window is the library's — and since Core minor 6 the library's is this collection's `close` mark, so the two now match without either side overriding the other (standalone-windows; closed issue [LIBKA0S-19](https://github.com/tusharsaxena/LootHistory/issues/26), asserted in `tests/test_debuglog.lua`). |
| `core/LootHistory.lua` | `AceAddon:NewAddon`; `OnInitialize`/`OnEnable`; `PLAYER_ENTERING_WORLD` → once-per-session retention prune. Owns `NS.bus`/`NS.addon` and the `NS.NewBusTarget()` bus-receiver factory. |
| `core/Database.lua` | AceDB `InitDB` + `RunMigrations` (schema-migration seam) + `RepairBoundStates` (the deferred warbound-state split a migration can't do, armed by `ArmBoundRepair`), `Add`/`Query`/`ActiveHistory`/`Delete`/`PruneOld`/`Purge`/`Stats`/`Export`/`FireHistoryChanged`, retention. `ActiveHistory` is the read seam that swaps in the test dataset over the raw account-wide history — filtering is point-in-time (decided at capture), so reads never hide or resurrect a stored row (see Data model). |
| `defaults/Global.lua` | `NS.defaults.global`: `schemaVersion`, `history`, `blacklist`, `whitelist`, `currencyBlacklist`, `settings` (incl. `recordCurrency` and the `auction` cascade), `minimap`. |
| `locales/enUS.lua` | Canonical strings; `NS.L` metatable fallback. |
| `settings/Schema.lua` | One row per setting — single source for AceDB defaults, panel widgets, slash get/set/list/reset. `Schema:Set` write seam. `NS.COMMANDS`. |
| `settings/Slash.lua` | The **`LibKa0s-Slash-1.0`** seam. AceConsole `/lh` + `/loothistory`; the dispatcher, help header/rows, landing rows, schema CLI and type-aware parser are the library's, reading the host's positional `NS.COMMANDS`. Host-owned: the purge / reset-everything / filter-list-clear confirm dialogs, `ResetEverything` (the panel's **Reset Everything** button, which is a superset of the `/lh resetall` verb), the `CliResetAll` wrapper that also clears the id-lists, and `FormatSchemaValue` — the descriptor's `format` hook for `type = "table"`, the one row type the library has none for. |
| `settings/OptionsSetup.lua` | The **`LibKa0s-Options-1.0`** seam: the canvas shell, breadcrumb header, lazy Defaults button, page registry, scroll + always-shown-scrollbar patch, widget makers, two-column flow engine, `SetRenderer` and the two refresh tiers. Where every declined surface is recorded. Must load before `settings/Panel.lua`. |
| `settings/Panel.lua` | The page builders on top of that seam: the landing page, General, Filters and AH Price, plus the live DB stats block and the two widgets the library has no maker for (the inverted set picker and the pooled AH price table). |
| `modules/AuctionPrice.lua` | `NS.AuctionPrice:GatherAll(itemLink, itemID)` reads an AH price for a just-looted item from every installed third-party pricing addon (Auctionator / TSM / OribosExchange), capturing **every configured key** into a nested `provider → key → copper` map (`settings.auction.capture`), not just one; every provider call is `pcall`-wrapped so a broken/absent addon degrades to `nil` and the gather continues. `NS.AuctionPrice:Pick(map)` is the read-time seam that selects one price from that map via the user-configurable `settings.auction.priority` cascade (first present key wins), returning `price, tag`. Third-party integration boundary — presence-gated here, **deliberately outside** `core/Compat.lua` (Blizzard-API-only); see Standards compliance below. |
| `modules/Attribution.lua` | Source-resolution engine: stamps `State.lootContext` from peripheral events; `Consume` returns source/detail/confidence or `OTHER`/`INFERRED`. Loads before Filters/Collector. |
| `modules/Filters.lua` | `NS.Filters`: the blacklist/whitelist item-id lists — `Add`/`Remove` (copy-on-write, mutually exclusive), `Blacklist`/`Whitelist` (the live id sets), `SortedIDs`, `ParseItemID` — **plus the currency blacklist** (`AddCurrencyBlacklist`/`RemoveCurrencyBlacklist`, `CurrencyBlacklist`, `ParseCurrencyID`; blacklist-only, keyed by `currencyID`). On change: a direct `Collector:RefreshUpvalues()` re-cache + `Database:FireHistoryChanged()`. Data-only; loads before Collector; no `Enable`. |
| `modules/Collector.lua` | `CHAT_MSG_LOOT` handler: self-filter, then the point-in-time gate (blacklist veto → normal quality/source/quest gate → whitelist rescue, recording a plain row with no marker of how it got in), `Consume`, an `AuctionPrice:GatherAll` call to stamp the record's `auctionPrice` map, `BuildRecord`, `Database:Add`. Also the **`CHAT_MSG_CURRENCY` handler** (`OnChatMsgCurrency`): a slimmer gate (`recordCurrency` master toggle → per-source mute → currency blacklist; no quality/quest/itemID checks) that writes a `Type=Currency` row. Caches hot-path upvalues (incl. the id lists, `recordCurrency`, `currencyBlacklist`). |
| `modules/Browser.lua` | Window shell: frame/skin, tabs, the **shared singleton filter bar + footer** (multi-select Bound/Quality/Type/SubType/Source/Zone/Character, date, search) that drives BOTH the History table and the Insights charts (`CurrentFilter`), group-by, the **tab-aware `Export` button** (`OpenExport`), LDB launcher + LibDBIcon minimap button. Its nine dropdowns are **`LibKa0s-Widgets-1.0`**'s, through `core/WidgetsSetup.lua` — this file used to *be* the widget. The window is `HIGH` strata, deliberately below the shared popup's `FULLSCREEN_DIALOG`, so an open menu draws above it. Since LibKa0s v1.13.0 the popup intercepts nothing — it listens on `GLOBAL_MOUSE_DOWN` — so a click outside an open menu closes the menu **and** lands here on the same press. |
| `modules/BrowserTable.lua` | Virtualized pooled-row table: filter → group → sort → slice → bind pipeline; columns, sort, grouping, row interactions (link / blacklist / delete). `OrderedFilteredRecords` exposes the on-screen order for export. |
| `modules/Export.lua` | Export modal (`NS.Export:Open`) at `DIALOG` strata, config-driven per invoking tab (`{ title, providers, csv }`): Data Set dropdown (All Data / Current View, a **`LibKa0s-Widgets-1.0`** dropdown through `core/WidgetsSetup.lua`); on an install with no library the modal **refuses to open**, decided by `NS.HasWidgets()` *before* the frame is created, so the refusal costs nothing and memoises nothing; `CSV` serializes loot rows (History) and `InsightsCSV` a sectioned analytics dump (Insights); `WowheadLink` builder; the copy window is **`LibKa0s-Widgets-1.0`**'s `CopyWindow`, described (not built) here through `core/WidgetsSetup.lua`'s `NS.CopyWindow`. Called directly by the Browser; no bus message. |
| `modules/Analytics.lua` | Insights tab, split by two dividers into a **LOOT** block (items-only stat/highlight cards + breakdowns: source, value, quality, item type, bound type, per-character companions, hour/weekday + per-day strips, top zones/items/value) and a **CURRENCY** block (Currency Collected, Currency by Type × Source, Currency by Character × Type, currency-per-day) shown only when the range has currency events — all from one `Database:Stats` pass, **scoped by the shared filter bar** (`Browser:CurrentFilter`, no range selector of its own). Pooled bar/strip/list renderers. |

---

## Data model

One record per loot event, appended to the account-wide `db.global.history` dense array. Every
acquisition is **one row** — records are keyed only by array position and never deduplicated by
item — so every column is first-class for sort and filter, and aggregation stays a view concern.
Records carry no metatables, which is what lets `Database:Export` serialize them directly.

The full field table, the `SourceType` / `Confidence` enums, currency rows, the derived
`Util.RecordValue`, the `schemaVersion` migration chain and the two read seams are in
**[schema.md](schema.md)**.

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
| `settings.recordCurrency` | Data Collection | CheckBox | `true` | Record looted currency as `Type=Currency` rows; obeys the per-source mute list, ignores the quality filter. Fires `SettingsChanged` (`"currency"`). |
| `settings.excludedSources` | Data Collection | MultiCheck | `{}` | Stored as *muted* sources; panel renders inverted ("Record data from"). Fires `SettingsChanged`. |
| `settings.auction.enabled` | AH Price | CheckBox | `true` | Master switch; `false` short-circuits the capture path (`GatherAll` gathers nothing), so new drops store no auction map — already-stored records are unaffected. |
| `settings.auction.capture` | AH Price | MultiCheck (`skipRender`) | `Constants.AUCTION_CAPTURE_DEFAULT` | The single collect-**and**-rank flag per `"provider:key"` source: a ticked source is gathered at loot time *and* participates in the priority cascade. Schema-backed for the default/slash CLI, but rendered by the AH Price sub-page's unified price table (`settings/Panel.lua` `buildAuctionTable`) as the per-row Enabled checkbox. |

`settings.auction.priority` (ordered `"provider:key"` cascade) is a carve-out, not a Schema row — see
the "AH Price" subcategory's unified price table (`buildAuctionTable`: a frame-light, reused-slot table
with per-row tick / addon / price-module / reorder-arrows / enable-checkbox / status columns) and
[`schema.md`](schema.md). (The former per-tag `priorityDisabled` carve-out was
removed — collection and priority are now the single `capture` flag.)

`settings.window` (persisted position/size), `savedView` (the saved table view), `minimap`
(LibDBIcon state), and the `blacklist`/`whitelist` item-id lists (managed by `NS.Filters`, surfaced
in the settings **Filters** subcategory) are storage/data state written straight to `NS.db.global`,
**not** Schema rows and not routed through `Schema:Set` — an accepted carve-out (see Standards
compliance, and [`schema.md`](schema.md)). Debug is session-only (`NS.State.debug`)
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
| `Ka0s_LootHistory_HistoryChanged` | `Database` (`Delete`/`PruneOld`/`Purge`, the public `FireHistoryChanged` that `NS.Filters` calls on a blacklist/whitelist edit, and `RepairBoundStates` on a pass that actually fixed rows) | — | Browser, Analytics, Panel (History stats + Filters page) |
| `Ka0s_LootHistory_SettingsChanged` | `Schema` `onChange` (enabled / quality / questfilter / currency / excludes) | reason string | Collector (`RefreshUpvalues`), Browser (`OnSettingsChanged`) |

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
| `PLAYER_ENTERING_WORLD` | `OnEnterWorld` (once-per-session prune + the deferred bound-state repair) | `core/LootHistory.lua` |
| `CHAT_MSG_LOOT` | `OnChatMsgLoot` (authoritative capture) | `modules/Collector.lua` |
| `CHAT_MSG_CURRENCY` | `OnChatMsgCurrency` (currency capture: `recordCurrency` → per-source mute → currency blacklist, writing a `Type=Currency` row) | `modules/Collector.lua` |
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

## Menus: two mechanisms, on purpose

This addon draws **two** kinds of menu and neither is a Blizzard `UIDropDownMenu` — both avoid that
API's protected-call taint surface, and neither is going to replace the other.

**The flat dropdown is `LibKa0s-Widgets-1.0`'s**, reached through `core/WidgetsSetup.lua`'s
`NS.MakeDropdown`. Ten instances: the filter bar's Group-by, Date, Bound, Quality, Type, SubType,
Source, Zone and Character, plus the export modal's Data Set picker. Its popup is a **process-wide
singleton** shared with every other Ka0s addon that has adopted the major — one menu open at a time
across the whole client, parented to `UIParent` at `FULLSCREEN_DIALOG`, outliving any window that
dropped it. Two consequences this addon has to honor: every frame that owns a dropdown sits *below*
that strata (the History window is `HIGH`, the export modal is `DIALOG`) so the menu draws above
whatever dropped it, and every **non-click close path** calls `NS.CloseMenu()` — the window's
`OnHide` (which is also the Escape / `UISpecialFrames` route), `Browser:Hide` (the slash-command
close) and the export modal's `OnHide`. A frame's own `Hide()` cannot reach a popup it does not own.

The popup does **not** intercept the click that dismisses it. Since LibKa0s v1.13.0 (Widgets minor 5)
it registers `GLOBAL_MOUSE_DOWN` while shown and hides on a press that is neither over itself nor
over the dropdown that dropped it, so one press both closes the menu and reaches whatever is under
the cursor (`libs/LibKa0s/Widgets.lua`). Through minor 4 it was a full-screen `Button` at
`FULLSCREEN` whose lack of `RegisterForClicks` took `LeftButtonUp` and nothing else — and this addon
is where that was found, because a right-click on a history row with a filter menu open simply did
nothing.

**`BrowserTable:ShowRowMenu` stays hand-rolled**, and coexists. It is a right-click **action list**,
not a labelled selector: it shows no current value and picking an item performs an action (link to
chat, blacklist, delete) rather than changing a setting. It also needs **per-row disable** —
"Link to chat" is dead without an `itemLink`, "Blacklist item" without an `itemID` — and per-row
disable is a *documented, deliberate absence* from the major: `opt.isActive` reports a state, it
does not gate a click. Converting it would mean either losing the disable or growing the library a
feature no consumer has asked for. It keeps its own small popup and its own catcher.

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

**Read [§ Documented deviations](#documented-deviations) first.** It is the register, and a
deviation that is in it is *ratified* — an audit records it as accepted rather than re-filing it.
The `performance` section's `LibKa0s-Perf-1.0` adoption chain (`LH-20`…`LH-26` in the 2026-08-04 and
2026-08-05 bundles) is the case in point: it is not open work, it is the `performance-§12`
no-combat-path exemption, claimed with a committed sweep in [`performance.md`](performance.md) and
recorded as one register row. Audit bundles are frozen the day they are written; this file is not,
so where the two disagree the register is the current answer.

The carve-outs below are separate: each was raised, resolved, and is **not** an open deviation.
One was raised and **ratified (2026-07-17)**:
the `blacklist` / `whitelist` item-id lists (issue #14) are persistent state managed outside
`Schema:Set` — a fourth carve-out alongside `settings.window`, `savedView`, and
`settings.windowScale`'s geometry sibling. The later `currencyBlacklist` (a currencyID-keyed,
blacklist-only sibling) and the `settings.auction.priority` ordered cascade join the same class —
a dynamic id-set or an ordered list has no fixed schema widget to express — all managed by
`NS.Filters` / `NS.AuctionPrice` writing `NS.db.global` directly. A dynamic, unbounded id-set has no schema widget to
express, so `NS.Filters` mutates `NS.db.global` directly, exactly as the pre-existing carve-outs do;
it is accepted as the same class, and the standard's own definition was left unchanged. Recorded in
[`schema.md`](schema.md) under the "Standards note".

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

A third was raised and **flagged (2026-07-17)**, and is still open for the next standards-audit: the
schema gained a **`sessionOnly` row kind** (`get`/`set` accessors, never written to `db.global`) so the
"Debug console" window-visibility toggle can live in the settings panel while honoring "debug is
session-only, never persisted". It extends schema-as-single-source rather than breaking it — the toggle
is a real schema row — but it is a row that deliberately never reaches the DB. See
[`settings-panel.md`](settings-panel.md).

Two surface-specific notes:

1. **The standalone browser window follows standalone-windows** (Standalone windows / data browsers): a non-secure
   `CreateFrame`, so it needs no combat-lockdown gate — ESC via `UISpecialFrames`, persisted
   position/size/scale, one `SKIN`/`ApplySkin` seam. This addon is standalone-windows's reference implementation.
   The Settings panel separately follows the options-ui-§2 combat-gated canvas.
2. **Bare `/lh` prints help** (standard slash-commands-§4); window display is explicit (`/lh toggle`,
   `/lh show|hide`).

Vendored libraries follow Ka0s Standard v2.0.0 (vendoring is the suite-wide rule).

---

## Documentation map

Every `.md` under `docs/` appears in exactly one table below (`documentation-§3`). Frozen and
generated directories are named once each and never enumerated per run: `docs/audits/`, `docs/reviews/`, `docs/automated-tests/`, `docs/superpowers/`.

### Required (documentation-§3, Tier 1)

| Doc | Covers |
|---|---|
| `ARCHITECTURE.md` | This file — the hub: module map, data model, message bus, slash surface, event wiring, this map, and the documented-deviations register |
| `scope.md` | What the history records, and the loot it deliberately does not |
| `module-map.md` | Every non-vendored file, its responsibility, and load order |
| `schema.md` | `LootHistoryDB`’s account-wide shape, the loot record, carve-outs, migrations |
| `settings-panel.md` | The panel tree, per-option behavior, and the write seam |
| `data-flow.md` | Loot event in → gate → attribute → record |
| `common-tasks.md` | Recipes for the changes made most often here |

### Conditional (documentation-§3, Tier 2)

| Doc | Status | Trigger |
|---|---|---|
| `slash-dispatch.md` | Present | 14 verbs in `NS.COMMANDS` |
| `midnight-quirks.md` | Present | Bind-state and currency-API behavior the addon works around |
| `compat-layer.md` | Present | `core/Compat.lua` is 416 lines of addon-specific shimming beyond LibKa0s |
| `message-bus.md` | Present | Shipped below the >10-message threshold, deliberately: the one-sender/one-target contract is what a receiver has to get right, and CallbackHandler's silent clobber is not something a three-row table in `ARCHITECTURE.md` can explain |
| `profiles.md` | Not applicable | No profile control ships in the options UI — the addon is account-wide by design and never touches `db.profile` |
| `debug.md` | Not applicable | The console is `LibKa0s-DebugLog-1.0`’s, with no debug surface of the addon’s own |
| `perf-analysis/README.md` | Not applicable | No performance harness is wired — see `performance.md` and `ARCHITECTURE.md` → `## Documented deviations` |

### Verification and record

| Doc | Covers |
|---|---|
| `testing.md` | How to run the harness and lint; the green commit gate |
| `smoke-tests.md` | The in-game smoke-test suite |
| `test-cases.md` | The generated case inventory (authoritative pass count) |
| `performance.md` | The addon performance page |
| `automated-tests/README.md` | What the automated-test record is and how to produce it |
| `automated-tests/RESULTS.md` | One row per run; generated, never hand-edited |

### Addon-specific (documentation-§3, Tier 3)

| Doc | Covers |
|---|---|
| `browser.md` | The standalone History window: table, filter bar, and the Insights tab |

## Documented deviations

The register (`documentation-§3`). **A deviation not in this table is not ratified** — the reasoning
may live at length in this repo's GitHub issues or in an audit bundle, and the **Why**
column cites that id, but an issue declining a rule with no row here is itself the deviation.
An audit reads this table, records these as accepted, and does not count them toward its MUST tally.

**Re-check trigger** is the condition that *ends* the deviation, written so a reader can tell whether
it has already fired. This table is **not a graveyard**: a row whose cited rule the standard has since
changed — so the behavior is now mandated or permitted outright — is retired, not kept for history.
Three such records were retired rather than carried in here, and are named below the table.

| Rule | What differs | Why | Decided | Re-check trigger |
|---|---|---|---|---|
| `architecture-§5` | Five pieces of persistent state are written to `NS.db.global` directly rather than through `NS.Schema:Set`: `settings.window` geometry, `savedView`, the `blacklist` / `whitelist` item-id sets, `currencyBlacklist`, and the `settings.auction.priority` ordered cascade. | A dynamic, unbounded id-set and an ordered cascade have no fixed schema widget to express, so there is no row for `Set` to validate against. Owned by `NS.Filters` / `NS.AuctionPrice`; reasoned in [`schema.md`](schema.md) *Standards note* and in **Standards compliance** above. | 2026-07-17 | `options-ui` gains a set/list widget maker, or any of these five acquires a fixed schema row — at which point it moves back under the single write seam. |
| `architecture-§5` | The schema carries a **`sessionOnly` row kind** (`get`/`set` accessors, never written to `db.global`), used by the "Debug console" window-visibility toggle. | It extends schema-as-single-source rather than breaking it — the toggle is a real schema row driving the panel, the CLI and reset — but it is a row that deliberately never reaches the DB, because `debug-logging` makes the debug flag session-only. See [`settings-panel.md`](settings-panel.md). | 2026-07-17 | The standard names a session-only row kind (then this is compliant, not a deviation), or the toggle becomes persistent. |
| `performance-§12` | **No perf harness is wired.** No `core/PerfSetup.lua`, no `LootHistoryPerfDB`, no `/lh perf` verb, no suspend/resume contract, no `tests/perf.lua`, no `docs/perf-analysis/` store. `libs/LibKa0s/` is still vendored whole and `perf` is still a reserved verb. | Criterion **(a)** — no `OnUpdate`, no repeating ticker, no in-combat handler doing more than occasional work — proven by the committed whole-repo `RegisterEvent` / `SetScript("OnUpdate"` / `C_Timer` sweep in [`performance.md`](performance.md), which names the per-event work for all eleven events and all four one-shot timers. Plus criterion **(c)**: `suspend` must make the host inert for the whole of window B, which for this addon means not recording the loot that drops during that fight — one experiment would cost the user real history. Closed issue [**LIBKA0S-17**](https://github.com/tusharsaxena/LootHistory/issues/22). | 2026-08-05 | **The first `OnUpdate` handler, repeating ticker, or in-combat event handler doing real work re-arms the full wiring MUST.** |
| `options-ui-§1` | The inverted set pickers (`settings.excludedSources`, `settings.auction.capture`) are drawn by **this addon**, from `afterGroup`, rather than by one of the library's widget makers. | The library's makers are checkbox / slider / dropdown / editbox / color picker; a wrapping `InlineGroup` of checkboxes whose stored value is the logical **inverse** of the tick is none of them, and `RenderGrid` takes no `parent` and would open a second overlapping scroll frame. The rows stay in the schema, so the CLI and every reset still see them. Closed issue [**LIBKA0S-14**](https://github.com/tusharsaxena/LootHistory/issues/20). | 2026-08-01 | `LibKa0s-Options-1.0` gains a multi-check / set maker with a `parent`, or a second host needs the same shape (one host, one shape is why it was not raised upstream). |

**Retired, deliberately not rows.** [`LIBKA0S-02`](https://github.com/tusharsaxena/LootHistory/issues/19)'s declined window skin — `Core.SKIN` **is** this
addon's treatment as of Core minor 3, so there is nothing left to deviate from ([`LIBKA0S-18`](https://github.com/tusharsaxena/LootHistory/issues/25)).
[`LIBKA0S-19`](https://github.com/tusharsaxena/LootHistory/issues/26)'s dropped `makeCloseButton` — `standalone-windows` now draws the split explicitly (the
edge is shared, the close control on a library-drawn window is the library's), so passing nothing is
the compliant path. And the third-party pricing shims living in `modules/AuctionPrice.lua` rather
than `core/Compat.lua`: the standard defines no boundary for **non-Blizzard** addon interop, so that
is a recorded gap in the standard, not a deviation from it — the paragraph in **Standards
compliance** above is its home.

---

## Known limitations

- **Full source coverage.** Every `SourceType` member has a live capture path. Deconstruct abilities
  stamp their own `DISENCHANT`/`MILLING`/`PROSPECTING` source (player `UNIT_SPELLCAST_SUCCEEDED` by
  spell id); `AH` is stamped from Auction-House mail; `BONUS_ROLL`/`CRAFT`/`REFUND` are attributed
  straight from their self-identifying loot lines; `ROLL` is stamped from the "You won:" roll line
  just before the item's receive line (see [data-flow.md](data-flow.md)). `VENDOR`/`MAIL`/`TRADE`
  were confirmed recording in-client (smoke §F-001, passed). NB: the `ROLL` path assumes the client
  emits `LOOT_ROLL_YOU_WON` ("You won:") rather than the compact "no-spam" roll variant — verify
  in-game (smoke §F-009).
- **No per-item source name.** The "From" column and its combat-log kill-name cache were removed:
  for the dominant real-world loot (containers, delves, pushed/quest items) no reliable name was
  resolvable, so the column was almost always blank. Records keep `source` and the machine-readable
  `sourceDetail` (npcID / encounter / keystone / questID); the human name is no longer captured or
  displayed.
- **Slow manual click-looting.** The source context uses a fixed `CONTEXT_TTL` (1.5s). Looting
  items more than ~1.5s apart from one open window can let later items fall back to
  `OTHER`/`INFERRED`. The single-slot context with a fixed TTL is a settled design decision, not an
  open backlog item — see [scope.md](scope.md) *Resolved design decisions*.
- **No upgrade-scoring addon interop** (Pawn/Loot Appraiser). Auction-house price interop
  (Auctionator/TSM/OribosExchange) shipped in Rev-2 — see the AH-price cascade above and
  [schema.md](schema.md).

See the [GitHub issue tracker](https://github.com/tusharsaxena/LootHistory/issues) for the full backlog.

---

