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
settings canvas with its tab strip and Master-controls composer, the settings schema runtime, the
bus message catalog, the spell-name compat reader, the shared drag-to-reorder list
and the flat dropdowns. All libraries
are **vendored** in `libs/` and committed (Ka0s Standard v2.0.0 — externals forbidden); LibKa0s is
vendored **whole-folder**, because fourteen of its fifteen majors resolve `LibKa0s-Core-1.0` before
registering and a per-file copy is how cross-major skew gets manufactured.

---

## Module map

Load order is fixed in `LootHistory.toc`: vendored `libs/` → `locales/` → `core/` (Compat first) →
`defaults/` → `modules/` (Attribution and Filters before Collector) → `settings/` (last). **Nine**
LibKa0s seams sit inside `core/`, and **four** of their positions are load-bearing rather than tidy:
`core/ItemSetup.lua` and `core/MediaSetup.lua` must sit above `core/Constants.lua` (which calls
`NS.Item.QualityLabel` and reads `NS.MediaFont` at file load), `core/WidgetsSetup.lua` below
`core/MediaSetup.lua` (the dropdown art resolves through `NS.Icon`), and `core/PoolSetup.lua` above
every module that pools a widget. **Two more** sit in `settings/` — `settings/OptionsSetup.lua` and
`settings/Slash.lua` — and the Options one's position is load-bearing too: `settings/Schema.lua` composes its Master controls tab at file
load through `NS.Options.MasterControls` (options-ui-§15), so the Options seam has to be above it. The rows below and [module-map.md](module-map.md) carry each one.

| File | Role |
|---|---|
| `core/Compat.lua` | **Loads first.** The compat firewall: every deprecated/varying-API shim gated by direct `C_*`/global presence (no `WOW_PROJECT_ID` game-flavor branching — Retail-only) — GUID decode + `UNIT_KINDS`, item/map/zone info, active keystone level, quality-from-link fallback. `Compat.GetSpellName` is **`LibKa0s-Compat-1.0`**'s member, wired as a field, with the reader stub (`nil`) when the library is absent. |
| `core/EnvSetup.lua` | The **`LibKa0s-Env-1.0`** seam: `NS.Meta(field)`, `NS.Version()`, `NS.PlayerMapID()` and `NS.Zone()` — the TOC read behind `/lh version` and the where-am-I stamp on every stored row. Took over `core/Compat.lua`'s map, zone and TOC-metadata shims. It is handed `addonName` (the addon **folder**, the first vararg — not `## Title`) because a vendored library cannot know which folder it sits in. **TOC position is conventional, not load-bearing**: nothing resolves here beyond the LibStub lookup. `NS.Zone` answers two strings and **never nil** — `""` buckets with nil on purpose in `Database:Stats`, the Zone filter and group-by-zone. |
| `core/ItemSetup.lua` | The **`LibKa0s-Item-1.0`** seam: `NS.Item` with `ItemIDFromLink`, `QualityFromLink`, `QualityLabel` and `LoadItem`. **Its TOC position is load-bearing** — `core/Constants.lua` calls `QualityLabel` at **file load** to build the quality threshold labels, so it must sit above Constants. The **resolver did not move**: `Compat.GetItemInfo` still guesses name and quality for an uncached id (this addon would rather store an approximate row than lose the drop). A degraded install gets the same four primitives locally — the quality they write is **stored**, not just drawn. |
| `core/MediaSetup.lua` | The **`LibKa0s-Media-1.0`** seam: `NS.Icon` / `NS.MediaFont` / `NS.IconMarkup`, and `Media.RegisterLSM(addonName)` at **file load**. **Its TOC position is load-bearing** — it must sit above `core/Constants.lua`, which resolves `FONT_MONO` from `NS.MediaFont` at load. Paths are extensionless and point into the vendored payload (`libs/LibKa0s/media/`); `nil` is a real answer twice (no library, no such name), and every call site keeps its Blizzard rung underneath. This addon ships no font and no icons of its own. |
| `core/Constants.lua` | `SourceType` enum, `SourceOrder`/`SourceLabel`, `SOURCE_IMPLEMENTED` (coverage gate), `Confidence`, `CONTEXT_TTL`, `ITEMCLASS_QUEST` (Quest item-class id for the capture filter), `CURRENCY_TYPE` (the `"Currency"` type label for currency rows), `AUCTION_KEYS` (the AH-price key catalog), `RECORD_ADDED_COALESCE` (`0.2`s — the `RecordAdded` repaint window), `FONT_MONO_NAME` / `FONT_MONO` (resolved from `NS.MediaFont` at load — see `core/MediaSetup.lua`), quality/retention/source option tables. |
| `core/Namespace.lua` | Bootstrap: sets `NS.name`, `NS.version`, `NS.PREFIX`. (`NS.L` is published by `locales/enUS.lua`; module tables self-publish idempotently.) |
| `core/State.lua` | Runtime state: `lootContext`, encounter/keystone context, session flags, session-only `debug`, and the session-only `testRecords` (the `/lh test` synthetic dataset). |
| `core/Util.lua` | Pure helpers: date-range (`RangeFrom`) + time/money/byte formatting, self-loot string parsing, `PlayerKey`, dotted-path split, and **`Util.Coalesce(fn, delay)`** (also published as `NS.Coalesce`) — the burst coalescer behind the `RecordAdded` repaint. It clears its pending flag **before** running the body, so a raise inside `fn` cannot wedge the trigger and leave a surface that never repaints again; with no `C_Timer` it runs straight through. |
| `core/CoreSetup.lua` | The **`LibKa0s-Core-1.0`** seam. Publishes the shared **secret-safe chat printer** — `NS.Print` / `NS.Format` / `NS.Util.print` (+ `IsConcatSafe` / `SafeToString`), the single seam every module prints through (events-frames-taint-§8), reclaimed from AceConsole's `:Print` in `core/LootHistory.lua` — which is why this file publishes to **both** keys. It also publishes **`NS.LIBKA0S_MISSING`**: one cause clause, appended to by every other LibKa0s seam in the addon, set outside the `if not lib` branch because they read it on both paths. A cross-file contract, not an implementation detail. Also publishes **`NS.ApplySkin`** and **`NS.MakeCloseButton`** — the latter wrapped once so `lib.MakeCloseButton`'s **third** argument, this addon's folder name, is passed from every close control it builds; a two-argument passthrough would run, return a button, stay green in every suite, and draw a multiplication sign forever (anti-patterns #64). |
| `core/WidgetsSetup.lua` | The **`LibKa0s-Widgets-1.0`** seam: **`NS.MakeDropdown(parent, width)`**, **`NS.HasWidgets()`**, **`NS.CloseMenu()`** and **`NS.CopyWindow(descriptor)`** — the export copy window, a lazily-built handle rather than a frame, so a session that never exports creates nothing. One factory for all ten flat dropdowns this addon draws — the filter bar's nine and the export modal's Data Set picker — and it is where the widget's art is resolved: a vendored library cannot know which addon folder it sits in, so `chevron` and `check` are looked up through `NS.Icon` **here** and passed in as parameters, once, rather than at each call site. It passes **no `glyphFont`** and that is a decision: the field is a *precondition* for any option carrying `opt.glyph`, no option this addon builds carries one (the multi-select tick is markup the library splices itself, the Character rows' class icons are markup folded into a label), and a proportional face passed for a glyph nothing draws renders a box. It replaced 208 lines of `modules/Browser.lua` — the collection's third copy of one widget. `nil` is a real answer both ways: `NS.MakeDropdown` returns nil with no library and both surfaces refuse to draw rather than build a control that opens no menu, and `NS.CloseMenu` becomes a no-op. **`NS.HasWidgets()`** is the same question asked with nothing built — a surface whose only control is a dropdown would otherwise have to create its window to learn the answer, and `modules/Export.lua`'s window carries a global name, so a build-and-discard probe stranded one `LootHistoryExportWindow` per open. |
| `core/DebugLogSetup.lua` | The **`LibKa0s-DebugLog-1.0`** seam: `NS.DebugLog` and the global `NS.Debug` sink. Replaced the 359-line `modules/DebugLog.lua`. The window chrome is deliberately split: `applySkin` **is** passed, as a closure resolving `NS.Browser` at frame-build time (hoisting it into a load-time local silently loses the skin — `modules/Browser.lua` loads long after `core/`), while **`makeCloseButton` is still deliberately not passed**. The descriptor does carry **`addonName = addonName` beside `name = addonName`**: `name` seeds the frame globals, `addonName` is what the library builds a texture path from, and that one line turns the console's title strip into three icon controls (`close`, `copy`, `clear`) on both the console and its copy window. The window *edge* is shared across every Ka0s window; the *close control* on a library-drawn window is the library's — and since Core minor 6 the library's is this collection's `close` mark, so the two now match without either side overriding the other (standalone-windows; closed issue [LIBKA0S-19](https://github.com/tusharsaxena/LootHistory/issues/26), asserted in `tests/test_debuglog.lua`). |
| `core/PoolSetup.lua` | The **`LibKa0s-Pool-1.0`** seam: `NS.Pool` with `New`, `Acquire(pool, factory)`, `ReleaseAll(pool, before)` and `Counts(pool)`. Loads **before every module that pools a widget** (Analytics, BrowserTable). It ended this addon's one genuinely wrong copy of a shared idea: the old chart pool hid its active widgets and dropped them, so the free list stayed empty and every `LayoutCharts` pass allocated a fresh frame per chart element — and frames are never destroyed in WoW. The `before` hook is not garnish: a host releasing a pool of panels releases each panel's own row pool first. Since LibKa0s v1.17.0 (Pool minor 3) `ReleaseAll` parks the active set **backward** — `Acquire` pops the free list from the end, so releasing the last rank first hands every widget back to the rank it already held instead of alternating that mapping on every render. `core/PoolSetup.lua`'s degraded fallback releases backward too: the copy that calls itself “the same pool, locally” is the one place the published contract must not quietly differ. |
| `core/LauncherSetup.lua` | The **`LibKa0s-Launcher-1.0`** seam: **`NS.Launcher`**, the minimap button and the broker plugin as **one** LibDataBroker object registered twice (launcher-§1), plus **`NS.RefreshLauncher()`**. It replaced `B:SetupMinimap` / `B:RefreshMinimap` / `B:SetMinimapHidden` in `modules/Browser.lua`. The descriptor's `name` is the addon's **folder** name on both registrations — LibDBIcon keys the button by it — its `icon` is `media/logos/loothistory.logo.128.tga`, the same file the TOC's `## IconTexture` names (launcher-§4), and `minimap` is a **function** answering `db.global.minimap` rather than the table, because AceDB replaces any table captured at file load. **Rung (a)** (launcher-§2): left-click is `NS.Browser:Toggle`, the addon's own switch, and right-click always opens the settings panel. `Register()` runs from `addon:OnInitialize`, after `NS:InitDB`. **No degradation stub** — unlike every other seam here, nothing in the addon calls into this module except `OnInitialize` and the `minimap.hide` row's `set`, and both already guard on `NS.Launcher`; a stub answering `IsShown`/`SetShown` would be a second copy of state that lives in `db.global.minimap`. `NS.RefreshLauncher()` re-points LibDBIcon at the store's new table after *Reset all settings*, which is the one call in this addon that still names LibDBIcon: the library publishes no re-point seam of its own. |
| `core/LootHistory.lua` | `AceAddon:NewAddon`; `OnInitialize`/`OnEnable`; `PLAYER_ENTERING_WORLD` → once-per-session retention prune. Owns `NS.bus`/`NS.addon` and the `NS.NewBusTarget()` bus-receiver factory. |
| `core/Database.lua` | AceDB `InitDB` + `RunMigrations` (schema-migration seam) + `RepairBoundStates` (the deferred warbound-state split a migration can't do, armed by `ArmBoundRepair`), `Add`/`Query`/`ActiveHistory`/`Delete`/`PruneOld`/`Purge`/`Stats`/`Export`/`FireHistoryChanged`, retention. `ActiveHistory` is the read seam that swaps in the test dataset over the raw account-wide history — filtering is point-in-time (decided at capture), so reads never hide or resurrect a stored row (see Data model). |
| `defaults/Global.lua` | `NS.defaults.global`: `schemaVersion`, `history`, `blacklist`, `whitelist`, `currencyBlacklist`, `settings` (incl. `recordCurrency` and the `auction` cascade), `minimap`. |
| `locales/enUS.lua` | Canonical strings; `NS.L` metatable fallback. |
| `settings/Schema.lua` | One row per setting — single source for AceDB defaults, panel widgets, slash get/set/list/reset. The **`LibKa0s-Schema-1.0`** seam: descriptor, degradation stub, and the host's `Schema:Set` / `:Get` / ... names delegating to `NS.SchemaRuntime`. `NS.COMMANDS`. |
| `settings/Slash.lua` | The **`LibKa0s-Slash-1.0`** seam. AceConsole `/lh` + `/loothistory`; the dispatcher, help header/rows, landing rows, schema CLI and type-aware parser are the library's, reading the host's positional `NS.COMMANDS`. Host-owned: the purge / global-reset / filter-list-clear confirm dialogs, `ResetEverything` (the Master controls tab's **Reset all settings** button — options-ui-§12's global reset, and a superset of the `/lh resetall` verb), the `CliResetAll` wrapper that also clears the id-lists, and `FormatSchemaValue` — the descriptor's `format` hook for `type = "table"`, the one row type the library has none for. |
| `settings/OptionsSetup.lua` | The **`LibKa0s-Options-1.0`** seam: the canvas shell, breadcrumb header, lazy Defaults button, page registry, scroll + always-shown-scrollbar patch, widget makers, two-column flow engine, `SetRenderer`, the two refresh tiers, the page chrome (`TabStrip` / `SubTabStrip`) and the schema composers (`MasterControls`). Where every declined surface is recorded. **Its TOC position is load-bearing** — `settings/Schema.lua` calls `NS.Options.MasterControls` at file load, and `settings/Panel.lua` takes `NS.Options` as a file-scope upvalue, so it must load above both. |
| `settings/Panel.lua` | The page builders on top of that seam: the landing page and the one **General** subcategory, whose six-tab strip is drawn by hand because two of its tabs (Filters, AH Price) hold no schema rows to partition. Plus the live DB stats block and the two surfaces the library has no maker for — the inverted set picker and the pooled AH price table, the latter now reordered through the shared `ReorderList`. |
| `modules/AuctionPrice.lua` | `NS.AuctionPrice:GatherAll(itemLink, itemID)` reads an AH price for a just-looted item from every installed third-party pricing addon (Auctionator / TSM / OribosExchange), capturing **every configured key** into a nested `provider → key → copper` map (`settings.auction.capture`), not just one; every provider call is `pcall`-wrapped so a broken/absent addon degrades to `nil` and the gather continues. `NS.AuctionPrice:Pick(map)` is the read-time seam that selects one price from that map via the user-configurable `settings.auction.priority` cascade (first present key wins), returning `price, tag`. Third-party integration boundary — presence-gated here, **deliberately outside** `core/Compat.lua` (Blizzard-API-only); see [compat-layer.md](compat-layer.md#third-party-pricing-addons-stay-out-of-compat). |
| `modules/Attribution.lua` | Source-resolution engine: stamps `State.lootContext` from peripheral events; `Consume` returns source/detail/confidence or `OTHER`/`INFERRED`. Loads before Filters/Collector. |
| `modules/Filters.lua` | `NS.Filters`: the blacklist/whitelist item-id lists — `Add`/`Remove` (copy-on-write, mutually exclusive), `Blacklist`/`Whitelist` (the live id sets), `SortedIDs` — **plus the currency blacklist** (`AddCurrencyBlacklist`/`RemoveCurrencyBlacklist`, `CurrencyBlacklist`; blacklist-only, keyed by `currencyID`). Parsing and labeling an entry is the Filters tab's LibKa0s IdList's job, not this module's. On change: a direct `Collector:RefreshUpvalues()` re-cache + `Database:FireHistoryChanged()`. Data-only; loads before Collector; no `Enable`. |
| `modules/Collector.lua` | `CHAT_MSG_LOOT` handler: self-filter, then the point-in-time gate (blacklist veto → normal quality/source/quest gate → whitelist rescue, recording a plain row with no marker of how it got in), `Consume`, an `AuctionPrice:GatherAll` call to stamp the record's `auctionPrice` map, `BuildRecord`, `Database:Add`. Also the **`CHAT_MSG_CURRENCY` handler** (`OnChatMsgCurrency`): a slimmer gate (`recordCurrency` master toggle → per-source mute → currency blacklist; no quality/quest/itemID checks) that writes a `Type=Currency` row. Caches hot-path upvalues (incl. the id lists, `recordCurrency`, `currencyBlacklist`). |
| `modules/Browser.lua` | Window shell: frame/skin, tabs, the **shared singleton filter bar + footer** (multi-select Bound/Quality/Type/SubType/Source/Zone/Character, date, search) that drives BOTH the History table and the Insights charts (`CurrentFilter`), group-by, the **tab-aware `Export` button** (`OpenExport`), LDB launcher + LibDBIcon minimap button. Its nine dropdowns are **`LibKa0s-Widgets-1.0`**'s, through `core/WidgetsSetup.lua` — this file used to *be* the widget. The window is `HIGH` strata, deliberately below the shared popup's `FULLSCREEN_DIALOG`, so an open menu draws above it. Since LibKa0s v1.13.0 the popup intercepts nothing — it listens on `GLOBAL_MOUSE_DOWN` — so a click outside an open menu closes the menu **and** lands here on the same press. |
| `modules/BrowserTable.lua` | Virtualized pooled-row table: filter → group → sort → slice → bind pipeline; columns, sort, grouping, row interactions (link / blacklist / delete). `OrderedFilteredRecords` exposes the on-screen order for export. |
| `modules/Export.lua` | Export modal (`NS.Export:Open`) at `DIALOG` strata, config-driven per invoking tab (`{ title, providers, csv }`): Data Set dropdown (All Data / Current View, a **`LibKa0s-Widgets-1.0`** dropdown through `core/WidgetsSetup.lua`); on an install with no library the modal **refuses to open**, decided by `NS.HasWidgets()` *before* the frame is created, so the refusal costs nothing and memoizes nothing; `CSV` serializes loot rows (History) and `InsightsCSV` a sectioned analytics dump (Insights); `WowheadLink` builder; the copy window is **`LibKa0s-Widgets-1.0`**'s `CopyWindow`, described (not built) here through `core/WidgetsSetup.lua`'s `NS.CopyWindow`. Called directly by the Browser; no bus message. |
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

`settings/Schema.lua` is the single source of truth: one row drives the AceDB default, the panel
widget and the slash get/set/list/reset behavior, and every write to a row's path goes through
`Schema:Set(path, value)` (validate → write to `NS.db.global` → `onChange`).
The runtime behind the seam is **`LibKa0s-Schema-1.0`**: the file builds one instance over its rows
(`NS.SchemaRuntime`; the resolved library is `NS.SchemaLib`), and every host name is a one-line
delegate to it, so no caller moved. Its descriptor names the store (`NS.db.global`), the debug sink,
the sweep-exempt minimap row and this addon's refusal words. The boot check `Schema:Register` is the
library's `Validate`: row shape (`group`, `type`, no duplicate path) plus path resolution against
`defaults/Global.lua`. With the library absent, a write-completing, log-silent stub in the same file
keeps reads, writes, reactions and the sweep veto working ([schema.md](schema.md#the-schemaset-write-seam)).
A bulk reset logs one `[Set] reset all: N rows` line, never one per row (`debug-logging-§10`): the
Defaults button and `/lh resetall` reach the library's bracketed `CliResetAll`, N is the seam's own
tally of rows whose stored value changed, and a raise part-way appends ` (stopped by an error)`.
Reset all settings logs one `[Set] reset account-wide settings to defaults (N rows)`
([slash-dispatch.md](slash-dispatch.md), [schema.md](schema.md#reset-semantics)).
Seventeen rows ship today, on **one** schema-backed page: the General subcategory, whose six tabs are
Master controls, Capture, AH Price, Interface, History and Filters, the last holding no rows.
The `settings.auction.priority` cascade is written outside the helper and carries the
`architecture-§5` row under Documented deviations. The row table, the storage-only state, the reset
scopes and the history of each carve-out are in [schema.md](schema.md).

Three more pieces are **named non-setting state** (`architecture-§5`): no control chooses their
values and no row addresses them, so they are written outside the helper with no register row. Each
has one owner, `NS.Browser` (`modules/Browser.lua`), and every writer is listed with the act that
reaches it.

- **`NS.db.global.settings.window`**, the window geometry `{ point, x, y, w, h }`. The local
  `SaveWindow` (`:97`) writes it when a title-bar drag stops (`:964`) and when the resize grip is
  released (`:1052`). `B:ResetWindow` (`:681`) writes `{}`, reached from the Master controls
  **Reset position** button (`onResetPosition`, `settings/Schema.lua:109`) and from **Reset all
  settings** (`Sl:ResetEverything`, `settings/Slash.lua:180`).
- **`NS.db.global.savedView`**, the remembered view. `B:SaveView` (`:663`) stores the whole
  `B:CaptureView()` when the player clicks the filter bar's **Save** (`:754`). `B:ResetView`
  (`:672`) clears it to `nil`, reached from the filter bar's **Reset** (`:751`) and from
  `Sl:ResetEverything` (`settings/Slash.lua:180`). The load pass reshapes it (migrations `to = 6`
  and `to = 8` in `core/Database.lua`).
- **`NS.db.global.minimap`**, apart from its `hide` row. `NS.Launcher:Register()`
  (`core/LauncherSetup.lua`) hands the table to LibDBIcon and writes nothing to it, since the AceDB
  default (`defaults/Global.lua:63`) supplies it. The one writer is the library: dragging the minimap
  button stores `minimapPos` (`libs/LibDBIcon-1.0/LibDBIcon-1.0.lua:194`). The addon never calls the
  library's `Lock`, `Unlock` or compartment functions, its only other writes into the table. The
  scope is **global** and launcher-§3 fixes it there: a profile switch must not move a player's
  buttons. This addon has no profile at all, so what that rule buys here is only the first half —
  and `Sl:ResetEverything`, which is this addon's translation of options-ui-§12 for a profile-less
  addon, does empty the table (see *Known limitations*).

The loot log **`NS.db.global.history`** is named non-setting state too, **recorded data**: the
player deletes rows of the log or clears it, but never authors a row. Its one owner, `NS.Database`
(`core/Database.lua`), holds every writer, and [schema.md → *Recorded data*](schema.md#recorded-data-history-and-the-repair-bookkeeping)
lists them with the act that reaches each. The warbound repair's bookkeeping beside it is recorded
data of the same owner, and one key of it only the load pass writes: **`boundRepairRevision`**
(`core/Database.lua:155`), stamped by `NS:ArmBoundRepair`, which only `NS:RunMigrations` calls.
That call also arms **`boundRepairPending`** and **`boundRepairAttempts`**, which the deferred
repair then advances and clears.

The id filter sets are a structural registry (`architecture-§5`): the player adds and removes ids,
the defaults ship the sets empty, and no schema row or whole-value path names them, so they need no
register row while only the writer and load pass named here touch them. Their storage keys are
`NS.db.global.blacklist` and `.whitelist` (`{ [itemID] = true }`) and `.currencyBlacklist`
(`{ [currencyID] = true }`), declared empty in `defaults/Global.lua:20-22`. Their one writer is
`NS.Filters` (`modules/Filters.lua`), whose per-id and reset verbs are called by the Filters tab,
the History right-click menu, the Clear-all confirms and `Sl:CliResetAll`, none of which writes the
sets itself. They have no load pass: the AceDB defaults seed them and no `MIGRATIONS` step in
`core/Database.lua` touches them.

---

## Message bus

Closed `Ka0s_LootHistory_*` bus (AceEvent), exactly one sender per message. No cross-module
table reach.

Each name is declared once, as `NS.MSG.<KEY>` in `core/Constants.lua`, and every `SendMessage` /
`RegisterMessage` names the constant, never the literal (`architecture-§4`). The table goes through
**`LibKa0s-Bus-1.0`**'s `Catalog`, which validates the names at load and answers a strict copy, so a
mistyped key raises at the call site. Only `Catalog` is adopted: the receivers below are untracked
on purpose, so the major's stand-down record (`New`) is not used. Without the library a one-member
stub hands back the plain table ([message-bus.md](message-bus.md#declared-once-as-nsmsg)).

> **Receivers must register on a private bus target** (`NS.NewBusTarget()`), never on the shared
> `NS.bus`/`NS.addon` as `self`. CallbackHandler keys callbacks by `(message, target)`, so two
> consumers of the same message that share a target silently clobber each other — only the last
> registrant receives it. `SettingsChanged`, `RecordAdded`, and `HistoryChanged` each have multiple
> consumers, so every consumer (Collector, Browser, Analytics, Panel) owns its own target.

| Message (`NS.MSG` key) | Sender | Payload | Consumers |
|---|---|---|---|
| `Ka0s_LootHistory_RecordAdded` (`RECORD_ADDED`) | `Database:Add` | `(record, index)` | Browser (refresh History), Analytics (live recompute), Panel (live stats). Browser and Analytics run their repaint through `NS.Coalesce(…, Constants.RECORD_ADDED_COALESCE)`, so a multi-drop kill costs **one** pass rather than one per row; `HistoryChanged` still repaints immediately. |
| `Ka0s_LootHistory_HistoryChanged` (`HISTORY_CHANGED`) | `Database` (`Delete`/`PruneOld`/`Purge`, the public `FireHistoryChanged` that `NS.Filters` calls on a blacklist/whitelist edit, and `RepairBoundStates` on a pass that actually fixed rows) | — | Browser, Analytics, Panel (History stats + the Filters tab) |
| `Ka0s_LootHistory_SettingsChanged` (`SETTINGS_CHANGED`) | `Schema` `onChange` — eight handlers, six reasons (enabled / quality / questfilter / currency / excludes, plus `chrome` from the Master controls tab's `scale` / `alpha` / `locked`) | reason string | Collector (`RefreshUpvalues`), Browser (`OnSettingsChanged`) |

> A blacklist/whitelist edit stays within the one-sender rule: it re-caches the Collector via a
> **direct** `Collector:RefreshUpvalues()` call (not a `SettingsChanged` message) and broadcasts
> `HistoryChanged` through `Database:FireHistoryChanged()` (so `Database` remains that message's sole
> sender). The Panel's Filters TAB subscribes to `HistoryChanged` on its own second bus target.

> `windowScale`, `rowHeight`, `retentionDays` and `minimap.hide` changes are **not** broadcast on
> the bus — their `onChange` reaches `Browser:SetScale` / `BrowserTable:Bind` /
> `Database:PruneOld` directly, and `minimap.hide` has no `onChange` at all: it is the one stored
> row whose own `set` does the work, because the row says SHOWN and LibDBIcon's key says HIDDEN and
> that inversion has to happen inside the write seam (launcher-§3). What does fan out via
> `SettingsChanged` is the five capture settings (`enabled`, quality, currency, quest-item filter,
> excludes) plus the Master controls tab's three chrome settings (`scale`, `alpha`, `locked`),
> which share the one `"chrome"` reason.

---

## Slash commands

Registered by `settings/Slash.lua` for both `/lh` and `/loothistory`. Bare `/lh` **opens the
Settings panel on its landing page** by running the `config` verb (slash-commands-§4, Slash minor
11); `/lh help` prints the command index. Window display is explicit via `toggle`/`show`/`hide`.
Verbs dispatch from `NS.COMMANDS`; `/lh help` is generated from the same table.

**The slash surface is UNCHANGED while the addon is disabled** (slash-commands-§2/§7, standard
v2.57.0, LibKa0s v1.41.0 / Slash minor 13). Every reserved verb answers: `config` and the bare `/lh`
open the panel, `version` prints, `debug` runs, and the whole schema CLI — `get`, `set`, `list`,
`reset`, `resetall` — reads and repairs settings, which is precisely when a player most needs it.
The standard narrowed this to `enable` and `help` at v2.56.0 and **reversed it** at v2.57.0; the
case that settled the reversal was the smallest one, `/lh` on a disabled addon returning a refusal
instead of the one surface it can be switched back on from by hand. This addon passes **no**
`liveVerbs` to the dispatcher, so it takes the library's set rather than a copy that could drift.

**A disabled addon refuses a feature verb** (slash-commands-§2's SHOULD, which survived the
reversal and is the only refusal in the disabled state). While `settings.enabled` is `false`,
`show` / `hide` / `toggle` / `test` / `purge` answer one tagged line naming `/lh enable` and do
nothing else. The gate is **one gate**, wrapped round each feature handler as `NS.COMMANDS` is built
(`settings/Schema.lua`), so every route into a verb passes it — the library's dispatcher, the
positional walk the library-less install falls back to, and a direct call on the triple — and a verb
declared tomorrow is gated by default. The live set is named once, as data (`LIVE_WHILE_DISABLED`),
and is `lib.LIVE_VERBS` restated: `help`, `config`, `version`, `enable`, `disable`, `debug`, `perf`
and the schema CLI. **The refusal line is the collection's, not this addon's** — one shape, built by
`LibKa0s-Slash-1.0` from `NS.BRAND` and the slash and reached through `NS.Slash.DisabledLine()` from
both call sites (the verb gate and the launcher's left click). It is no longer an `NS.L` string:
`locales/enUS.lua` carried `SLASH_DISABLED_VERB` until v1.41.0, and slash-commands-§7 makes the
wording the collection's rather than the addon's.

**And the addon itself is genuinely INERT — see [§ The disabled state](#the-disabled-state).**

| Verb | Action |
|---|---|
| *(none)* | Open the Settings panel on its landing page (same as `config`) |
| `show` / `hide` / `toggle` | Open / close / toggle the window |
| `config` | Open the Settings panel |
| `enable` / `disable` | Turn recording on / off. **Aliases**, never a second switch: each is `/lh set settings.enabled <bool>` with the path filled in, so it writes the Master controls **Enable Loot History** row through `Schema:Set` and holds no state of its own (slash-commands-§2). Both keep answering while the addon is disabled, which is what stops the pair being one-way |
| `version` | Print the addon version (`[LH] v<version>`, read from TOC metadata) |
| `get <path>` | Print a setting value |
| `set <path> <value>` | Set a setting value |
| `list` | List all settings |
| `reset <path>` | Reset one setting to its default |
| `resetall` | Reset all settings to defaults (non-destructive: history is untouched). `minimap.hide` is **exempt** — launcher-§3 makes the minimap button's visibility survive every reset. The **destructive** form is the Master controls tab's **Reset all settings** button, which empties the whole account-wide store — `options-ui-§12`'s shape for an addon with no profile. The two are deliberately different acts today: a **ratified** divergence from that rule's opening sentence, carried as a row in [§ Documented deviations](#documented-deviations); scope matrix in [`schema.md`](schema.md#reset-semantics) |
| `debug` | Toggle the debug console (session-only) |
| `test` | Toggle a synthetic preview dataset for the table and Insights (session-only; the same switch as the Master controls **Test mode** checkbox, and combat ends it) |
| `purge` | Delete ALL loot history (confirm dialog) |
| `help` | Print the generated command index |

---

## The disabled state

**Disabled means the addon is not running** (`slash-commands-§7`, standard v2.57.0). Not hidden, not
quiet, not skipping a repaint — not running. A player who unticks **Enable Loot History** has asked
for the same outcome they would get by unticking the addon in Blizzard's own AddOns list, minus the
`/reload`.

**This addon shipped a draw gate until v1.41.0, and it is worth naming.** `settings.enabled` was one
hot-path upvalue `modules/Collector.lua` read at the top of `OnChatMsgLoot`, and nothing else
changed: `CHAT_MSG_LOOT` stayed registered, so the client went on walking the registration list on
every loot line in the raid, building the argument frame and entering Lua for an addon the player
had switched off. The addon had not stopped watching — it had stopped reacting — and the dispatch it
went on paying is precisely what a player switching it off is trying to stop paying
(`anti-patterns #85`). The upvalue is gone; the registrations go instead.

### One latch, named holds

`core/LifecycleSetup.lua` is the `LibKa0s-Lifecycle-1.0` seam: ONE latch, stood down while at least
one **hold** is taken and stood up only when the last is released. `NS.Lifecycle:Set("disabled", …)`
is the one branch, and the checkbox, the `enable` / `disable` verbs, `/lh set settings.enabled` and
AceDB's profile callbacks all arrive at it through `NS.OnEnabledChanged`. There is deliberately no
bare stand-up: releasing one hold must not resurrect an addon another is still holding down.

**This addon takes one hold today.** It declines `LibKa0s-Perf` (`performance-§12`, a ratified row in
[§ Documented deviations](#documented-deviations)), so nothing here takes `perf`. The key is
published (`NS.HOLD_PERF`) and the latch honors it, because the invariant is the library's rather
than this addon's — `tests/test_disabled.lua` drives both holds through it, so arming the harness
later is a registration and not a rewrite.

### What stands down

| Goes down | Where |
|---|---|
| The AceAddon target's own registrations — `PLAYER_ENTERING_WORLD`, the Collector's two chat events, Attribution's nine | `NS.addon:UnregisterAllEvents()` in `NS.StandDown` |
| The three private bus targets — `SettingsChanged`, `HistoryChanged`, `RecordAdded`, `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED` | `Collector:Disable` / `Browser:Disable` / `Analytics:Disable` |
| Attribution's per-unit spell frame (`UNIT_SPELLCAST_SUCCEEDED`, `player`) | `Attribution:Disable` |
| Every deferral the addon armed — the retention prune, the bound-state repair, both coalesced repaints | `NS.CancelDeferrals`, over the handles `NS.After` tracks |
| The History window, the export modal and the debug console | `NS.StandDown`, and kept down by the first rung of `B:VisibilityAllows` |

**Hidden AT THE SOURCE, not imperatively.** The first rung of `B:VisibilityAllows` answers `false`
while the latch is down, so every route into the window — the verb, the minimap click, the tab
restore, the visibility dropdown — asks one question. An imperative hide alone would come back on
the next combat transition or settings change, and the addon would be visibly running while it
claimed to be off.

**The one sanctioned gate is `hooksecurefunc`**, which has no un-hook. Five hooks reach
`Attribution:Stamp` — `BuyMerchantItem`, `TakeInboxItem`, `AutoLootMailItem`, `UseContainerItem` and
`GetQuestReward` — and that one funnel gates its body and returns. It is not license to gate
anything that has a real unregister.

**`NS.After` replaced bare `C_Timer.After` for the addon's own deferrals**, and that is load-bearing
rather than tidy: the retention prune is a SavedVariables write on a five-second fuse lit by
`PLAYER_ENTERING_WORLD`, and `C_Timer.After` cannot be put out. A player who switched the addon off
inside those five seconds got the write anyway, from a game event, while it was disabled.

### What survives, because it is SETUP

The chat command and the dispatcher; `NS.COMMANDS`; the settings-category registration and the panel
body, including the panel's own bus subscriptions; the AceDB handle, `Schema:Set` and AceDB's
`OnProfileChanged` / `OnProfileCopied` / `OnProfileReset` callbacks; and the launcher's registration
— the minimap button stays on the minimap and the broker row stays in the display, because
`minimap.hide` is a per-installation display preference and says nothing about whether the addon is
running. Without those, `/lh enable` would not exist and the switch would only go one way.

**The launcher's CLICK changes** (`launcher-§2`). This addon is rung (a), so the left click drives a
primary window and is a feature: while disabled it prints the one refusal line, does nothing else
and writes no SavedVariables. The rung-(c) carve-out does not reach it — that one is for a left
click that opens the settings panel and nothing else. **Right-click is unchanged in either state**,
because the owner's ruling narrows the *slash* surface and a mouse click is not a slash command.

### The conformance suite

`tests/test_disabled.lua` is `slash-commands-§7`'s mandated suite, in the green gate like any other.
Every negative case asserts on the **registration set** through the kit's recording mock, never on a
handler's return value — an early return is exactly what a draw gate does, so a suite written
against one certifies the thing it exists to catch. It was confirmed red against the draw gate by
putting it back: steps 3, 4, 6 and 10 all redden, and the Collector's early return does not save it.

---

## Event subscriptions

**Every row below is torn out, not gated, while the addon is disabled** — see
[§ The disabled state](#the-disabled-state). The `hooksecurefunc` rows are the one exception the
standard sanctions, because that API has no un-hook; they gate their bodies at `Attribution:Stamp`.

| Event / hook | Handler | Module |
|---|---|---|
| `PLAYER_ENTERING_WORLD` | `OnEnterWorld` (once-per-session prune + the deferred bound-state repair, both deferred through `NS.After` so a stand-down can cancel them) | `core/LootHistory.lua` |
| `CHAT_MSG_LOOT` | `OnChatMsgLoot` (authoritative capture) | `modules/Collector.lua` |
| `CHAT_MSG_CURRENCY` | `OnChatMsgCurrency` (currency capture: `recordCurrency` → per-source mute → currency blacklist, writing a `Type=Currency` row) | `modules/Collector.lua` |
| `LOOT_OPENED` | `OnLootOpened` (GUID decode → KILL/CONTAINER/MPLUS) | `modules/Attribution.lua` |
| `ENCOUNTER_START` / `ENCOUNTER_END` | encounter context | `modules/Attribution.lua` |
| `CHALLENGE_MODE_START` / `CHALLENGE_MODE_COMPLETED` | keystone context (`Compat.GetActiveKeystoneLevel`) | `modules/Attribution.lua` |
| `ZONE_CHANGED_NEW_AREA` | `OnZoneChanged` — clears the keystone context on leaving the party instance (`Compat.InPartyInstance`), re-arms it on re-entry to an active key | `modules/Attribution.lua` |
| `CHALLENGE_MODE_RESET` | `OnChallengeModeReset` — clears the keystone context | `modules/Attribution.lua` |
| `TRADE_ACCEPT_UPDATE` | trade context (on mutual accept) | `modules/Attribution.lua` |
| `QUEST_TURNED_IN` | `OnQuestTurnedIn` (questID detail; the reward stamp itself comes from the `GetQuestReward` hook below) | `modules/Attribution.lua` |
| `UNIT_SPELLCAST_SUCCEEDED` (player-only) | `OnSpellSucceeded` → DISENCHANT/MILLING/PROSPECTING by spell id first, then a locale-independent localized name-family fallback | `modules/Attribution.lua` |
| `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` | `ApplyVisibility` — the two combat edges the `settings.visibility` dropdown is about; only ever **hides** a window the setting has stopped allowing, never opens one. `PLAYER_REGEN_DISABLED` also ends a running test mode (`BrowserTable:EndTestModeForCombat`: one chat line, the **Test mode** box unticks, the window is not opened) | `modules/Browser.lua` |
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
not a labeled selector: it shows no current value and picking an item performs an action (link to
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
  canvas with a **lazy, combat-locked** AceGUI body — opening is refused in combat, and a page on
  screen in combat is covered and refuses writes until `PLAYER_REGEN_ENABLED` (the library's lock,
  options-ui-§2; the addon keeps no guard of its own on the settings surface).
- Attribution uses `hooksecurefunc` (post-hooks only) on `BuyMerchantItem` / `TakeInboxItem` /
  `AutoLootMailItem` — these observe, never replace, and carry no taint.
- No secure templates, no protected action buttons, no `SetAttribute` — the addon is purely
  observational, so it cannot taint the loot/combat path.

---

## Standards compliance

[§ Documented deviations](#documented-deviations) is the register, and a deviation in it is
*ratified*: an audit records it as accepted rather than re-filing it. Audit bundles are frozen the
day they are written and this file is not, so where the two disagree the register is the current
answer. The third-party pricing shims live in `modules/AuctionPrice.lua` rather than
`core/Compat.lua`. That departs from no rule, because the standard defines no boundary for
non-Blizzard addon interop, and [compat-layer.md](compat-layer.md#third-party-pricing-addons-stay-out-of-compat)
records the reasoning.

---

## Documentation map

Every `.md` under `docs/` appears in exactly one table below (`documentation-§3`). Frozen and
generated directories are named once each and never enumerated per run: `docs/audits/`, `docs/reviews/`, `docs/automated-tests/`, `docs/revendor/`, `docs/superpowers/`.

### Required (documentation-§3, Tier 1)

| Doc | Covers |
|---|---|
| `ARCHITECTURE.md` | This file — the hub: module map, data model, message bus, slash surface, event wiring, this map, and the documented-deviations register |
| `scope.md` | What the history records, and the loot it deliberately does not |
| `module-map.md` | Every non-vendored file, its responsibility, and load order |
| `schema.md` | `LootHistoryDB`’s account-wide shape, the loot record, the settings rows, carve-outs, migrations |
| `settings-panel.md` | The panel tree, per-option behavior, and the write seam |
| `data-flow.md` | Loot event in → gate → attribute → record |
| `common-tasks.md` | Recipes for the changes made most often here |

### Conditional (documentation-§3, Tier 2)

| Doc | Status | Trigger |
|---|---|---|
| `slash-dispatch.md` | Present | 16 verbs in `NS.COMMANDS` |
| `midnight-quirks.md` | Present | Bind-state and currency-API behavior the addon works around |
| `compat-layer.md` | Present | `core/Compat.lua` is 419 lines of addon-specific shimming beyond LibKa0s |
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
Seven such records are named below the table rather than carried in it.

| Rule | What differs | Why | Decided | Re-check trigger |
|---|---|---|---|---|
| `architecture-§5` | The **`settings.auction.priority`** ordered cascade, neither a schema row nor registry membership, is written to `NS.db.global` directly rather than through `NS.Schema:Set`. It is seeded empty on first read by `NS.AuctionPrice:GetPriority` (`modules/AuctionPrice.lua:116`), written by `ReconcilePriority` / `MovePriorityWithin` (`:124-180`), and refilled in place by `P:RestoreDefaults` (`settings/Panel.lua:1062-1066`). | The cascade is an order over a **fixed** member set, the `NS.Constants.AUCTION_KEYS` tags, which the player only reorders. `architecture-§5` makes that a **value**, not a registry, and a value with no row is what its **MUST NOT** leaves a register row for. No schema row type expresses a drag-reordered list, so there is no row for `Set` to validate against. Reasoned in [`schema.md`](schema.md) *Standards note*. The id filter sets and the named non-setting state left this row on 2026-09-12; see below. | 2026-07-17 | `settings.auction.priority` gains a schema row, an ordered-list row type or a whole-value row, and every write to it goes whole through `Schema:Set`. That retires this row. |
| `performance-§12` | **No perf harness is wired.** No `core/PerfSetup.lua`, no `LootHistoryPerfDB`, no `/lh perf` verb, no suspend/resume contract, no `tests/perf.lua`, no `docs/perf-analysis/` store. `libs/LibKa0s/` is still vendored whole and `perf` is still a reserved verb. | Criterion **(a)** — no `OnUpdate`, no repeating ticker, no in-combat handler doing more than occasional work — proven by the committed whole-repo `RegisterEvent` / `SetScript("OnUpdate"` / `C_Timer` sweep in [`performance.md`](performance.md), which names the per-event work for all fifteen registrations and all five one-shot timers, and states explicitly why `CHAT_MSG_LOOT` — the one handler that fires in combat and does real work on a kept line — stays inside (a): `Collector:ShouldRecord` gates the tooltip build and the price cascade, so a dropped line costs a match and a comparison. Criterion **(b)** is no longer claimed alongside them: it rested on calling that handler's work "one line", which it is not, and this addon has no harness with which to measure the difference. Plus criterion **(c)**: `suspend` must make the host inert for the whole of window B, which for this addon means not recording the loot that drops during that fight — one experiment would cost the user real history. Closed issue [**LIBKA0S-17**](https://github.com/tusharsaxena/LootHistory/issues/22). | 2026-08-05 | **The first `OnUpdate` handler, repeating ticker, or in-combat event handler doing real work re-arms the full wiring MUST.** |
| `options-ui-§12` | **Three reset controls, three blast radii**, where §12's opening sentence puts the **Reset all settings** control, the header **Defaults** button and `/lh resetall` behind **one** implementation. **Reset all settings** (Master controls) confirms and runs `Sl:ResetEverything` (`settings/Slash.lua:180`), which empties `db.global` wholesale — settings, the three id-lists, `savedView`, window geometry **and the recorded loot history**. The **Defaults** button (`P:RestoreDefaults`, `settings/Panel.lua:1059`) and the `resetall` verb (`Sl:CliResetAll`, `settings/Schema.lua:769`) reach the schema rows, the three id-lists and the auction cascade only, and never touch `history`. | §12's translation for an addon with **no profile section** is *empty the account-wide store wholesale*, and its own closing paragraph carves out an account-wide **record** as "a separate, separately-confirmed act — never folded into *reset settings*". This addon has both in **one** table: `db.global` holds the settings and the loot ledger, so the translation and the carve-out point opposite ways and the rule does not resolve itself. `/lh purge` is the separately-confirmed act for the ledger half. Re-pointing `resetall` — documented as non-destructive in README, `slash-dispatch.md` and `smoke-tests.md`, and the answer README gives to "reset my settings but keep the history" — at a history-destroying act is **data loss for anyone with the macro**, so it is a maintainer's call and not a refactor: raised at the v2 settings adoption and recorded rather than reconciled. Scope matrix in [`schema.md`](schema.md#reset-semantics). | 2026-09-02 | **The maintainer rules on one of the two reconciliations**, and either one ends this row: (a) all three route to `ResetEverything`, the slash verb confirm-gated like the button, with README / [`slash-dispatch.md`](slash-dispatch.md) rewritten and the behavior break called out in the release notes; or (b) `options-ui-§12` grows the profile-less split this addon needs — a settings reset that spares an account-wide **record**, beside that record's own separately-confirmed purge. |
| `options-ui-§1` | The inverted set pickers (`settings.excludedSources`, `settings.auction.capture`) are drawn by **this addon**, from `afterGroup`, rather than by one of the library's widget makers. | The library's makers are checkbox / slider / dropdown / editbox / color picker; a wrapping `InlineGroup` of checkboxes whose stored value is the logical **inverse** of the tick is none of them, and `RenderGrid` takes no `parent` and would open a second overlapping scroll frame. The rows stay in the schema, so the CLI and every reset still see them. Closed issue [**LIBKA0S-14**](https://github.com/tusharsaxena/LootHistory/issues/20). | 2026-08-01 | `LibKa0s-Options-1.0` gains a multi-check / set maker with a `parent`, or a second host needs the same shape (one host, one shape is why it was not raised upstream). |
| `localization-§1` | This addon ships **English only**: the `NS.L` seam is exported and `locales/enUS.lua` ships, but no user-facing string routes through `NS.L` — every label, tooltip and message is a hardcoded English literal. | `localization-§3` names English-only as one of the routing SHOULD's **two terminal compliant states**, and names this row as what makes it terminal: without it the SHOULD is formally open and every audit re-files it, which is what has been happening. Both `localization` MUSTs are met unconditionally — the seam is exported with the key-returning fallback (`locales/enUS.lua:5`) and `enUS.lua` ships carrying no dead keys. The argument was written at `locales/enUS.lua:7-11` and calls itself "an accepted scope decision, not an oversight"; a comment is exactly what `documentation-§3` says does not ratify a decision, which is why `LH-48` in `docs/audits/2026-09-07/` filed it. This row is the ratification the comment was standing in for. | 2026-09-08 | **The first non-English locale file added to `locales/`.** That change routes the strings and retires this row. |

- Narrowed on 2026-09-12 ([#30](https://github.com/tusharsaxena/LootHistory/issues/30)): `settings.window` and `savedView` left the `architecture-§5`
  row as named non-setting state (standard v2.44.0), and LibDBIcon's `minimapPos`, never in it, is named beside them in [Settings schema](#settings-schema); the `B:SetupMinimap` seed over the `minimap.hide` row was deleted.
- Narrowed on 2026-09-12: the id filter sets left the `architecture-§5` row, as a structural
  registry whose writer and load pass [Settings schema](#settings-schema) names (history in `schema.md`, *Standards note*).
- Retired on 2026-09-08: the `sessionOnly` row kind, which `options-ui-§15` and `options-ui-§12` now
  mandate (`LH-54` in `docs/audits/2026-09-07/`; the design is in [`settings-panel.md`](settings-panel.md)).
- Retired: [`LIBKA0S-02`](https://github.com/tusharsaxena/LootHistory/issues/19)'s declined window skin, since `Core.SKIN` is this addon's
  treatment as of Core minor 3 ([`LIBKA0S-18`](https://github.com/tusharsaxena/LootHistory/issues/25)).
- Retired: [`LIBKA0S-19`](https://github.com/tusharsaxena/LootHistory/issues/26)'s dropped `makeCloseButton`, since
  `standalone-windows` gives a library-drawn window's close control to the library.
- Never a row: the pricing shims outside `core/Compat.lua`, a gap in the standard rather than a
  deviation ([`compat-layer.md`](compat-layer.md#third-party-pricing-addons-stay-out-of-compat)).
- Never a row: the AH Price table's pooled host, `ctx._priHost`, declined in closed issue [#21](https://github.com/tusharsaxena/LootHistory/issues/21).
  `options-ui` never names `SetRenderer`, so that declined a library adoption rather than a rule; the
  reasoning is at `settings/Panel.lua:740-746` (`LH-47` in `docs/audits/2026-09-07/`).

### Files over the 1500-line cap

The `layout-§1` census: one row per authored, tracked `.lua` file over 1500 lines, naming the
terminal state it sits in. Vendored code (`libs/`, `tests/_kit/`) is outside the cap. Gated by the
kit's `tests/_kit/test_layout_cap.lua`.

Nothing is over the cap today. The largest authored file is `modules/Browser.lua` at 1271 lines
(`git ls-files '*.lua' | grep -v '^libs/' | grep -v '^tests/_kit/' | xargs wc -l`, 2026-09-23); the
1000-1500 band is observed and dispositioned in the release watch list (`automated-tests-§4`), not here.

---

## Known limitations

- **A reset still discards the minimap button's dragged position.** Standard v2.54.0 restated
  launcher-§3 as a **property** — a player's minimap-button choice survives both *Reset all settings*
  and a page-scoped **Defaults** button — and this addon now exempts `minimap.hide` from both
  (`NS.Schema.RESET_EXEMPT`, `Schema:ApplyDefault`, and the carry-across in `wipeGlobal`). What is
  **not** carried across is LibDBIcon's `minimapPos`, which lives in the same table: *Reset all
  settings* still empties `db.global` wholesale, so a button the player dragged returns to the
  library's default angle, and `NS.RefreshLauncher` then hands LibDBIcon the store's new table. §3
  names the position only in its **reasoning** for the exemption and MUSTs only the `hide` row, so
  this is inside the rule as written; whether the position is meant to be carried too is a question
  for the standard rather than something to answer locally.
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

