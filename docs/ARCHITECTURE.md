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
bus message catalog, the spell-name compat reader, the shared drag-to-reorder list,
the flat dropdowns and the Timeline's line chart (vendored at v1.69.0, see `CLAUDE.md`). All libraries
are **vendored** in `libs/` and committed (Ka0s Standard v2.0.0 — externals forbidden); LibKa0s is
vendored **whole-folder**, because fourteen of its fifteen majors resolve `LibKa0s-Core-1.0` before
registering and a per-file copy is how cross-major skew gets manufactured.

---

## Module map

Load order is fixed in `LootHistory.toc`: vendored `libs/` → `locales/` → `core/` (Compat first) →
`defaults/` → `modules/` → `settings/` (last). **Nine**
LibKa0s seams sit inside `core/` and **three** in `settings/`. These TOC positions are
load-bearing, each carrying a `LOAD-BEARING` comment in the TOC (toc-file-§5; count them with
`grep -c LOAD-BEARING LootHistory.toc`):

- `core/ItemSetup.lua` and `core/MediaSetup.lua` sit **above `core/Constants.lua`**, which calls
  `NS.Item.QualityLabel` and reads `NS.MediaFont` (for `FONT_MONO`) at file load.
- `core/CoreSetup.lua` sits **below `core/Namespace.lua`** (`lib:New{ prefix = NS.PREFIX }` at load)
  and **above every file-scope `NS.Print` capture** (`modules/Browser.lua:5`, `settings/Schema.lua:5`,
  `settings/Slash.lua:4`); `core/DebugLogSetup.lua` sits **below `core/Constants.lua`** (`FONT_MONO`).
- `defaults/Global.lua`, `defaults/Profile.lua` and `settings/OptionsSetup.lua` sit **above
  `settings/Schema.lua`**, which takes `NS.defaults.profile` as a file-scope local
  (`settings/Schema.lua:21`) and composes its Master controls tab through
  `NS.Options.MasterControls` at file load (options-ui-§15).
- `settings/Slash.lua` sits **below `settings/Schema.lua`**: the dispatcher is built at load with
  `commands = NS.COMMANDS`, which Schema assigns; above it, `:New` raises and `/lh` never registers.
- `settings/Panel.lua` sits **below `settings/Schema.lua`**: it reads `NS.Schema.MASTER_GROUP` and
  `NS.Schema.MasterAfterGroup` at file load.
- In `modules/`: `modules/Escrow.lua` sits **below `modules/Reconciler.lua`** (it appends to the
  Reconciler's `SCAN_STEPS` / `PLAN_STEPS` / `COMMIT_STEPS` at load); `modules/Analytics.lua` and
  `modules/AnalyticsCharts.lua` sit **below `modules/AnalyticsFormat.lua`** (they bind `Analytics.K`
  and its helpers at load); `modules/BrowserWidgets.lua` sits **directly above `modules/Browser.lua`**
  (Browser binds its `B._dataset` and `B._options` builders at load);
  `modules/BrowserFilterBar.lua` sits **below `modules/Browser.lua`** (it
  binds `B._applyFilter` and its siblings at load); `modules/BrowserTableGroup.lua` sits **directly
  below `modules/BrowserTable.lua`** (it binds `BrowserTable._columnByKey` and
  `BrowserTable._groupColumn` at load); `modules/HoldingsTab.lua` and
  `modules/Timeline.lua` sit **below `modules/Browser.lua`** (each calls `NS.Browser:RegisterTab` at
  load), and `modules/Timeline.lua` also **below `modules/TimelineModel.lua`** (`TM.TOTAL`).

Every other position is **conventional**, and the TOC says so: `locales/`, the plain Core run, the
Env, Lifecycle, Widgets, Pool and Launcher seams and every unannotated `modules/` file resolve
nothing of a sibling at load. The rows below and
[module-map.md](module-map.md) carry each one.

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
| `core/Ledger.lua` | `NS.Ledger`, the timeline ledger's pure primitives: `ThingKey` / `ParseThingKey` (`i:<id>`, `c:<id>`, `g`), `Diff` (signed per-key change between two count maps) and `DirSign`, plus the daily-rollup cell math (`DayKey`, `RowThingKey`, `RollupClose` / `RollupFlow`, `PruneDaily`, `ForgetHolderDaily`). No WoW API and no SavedVariables, so what the Reconciler decides is pinned headless. Conventional TOC position, after `core/Util.lua`. |
| `core/CoreSetup.lua` | The **`LibKa0s-Core-1.0`** seam. Publishes the shared **secret-safe chat printer** — `NS.Print` / `NS.Format` / `NS.Util.print` (+ `IsConcatSafe` / `SafeToString`), the single seam every module prints through (events-frames-taint-§8), reclaimed from AceConsole's `:Print` in `core/LootHistory.lua` — which is why this file publishes to **both** keys. It also publishes **`NS.LIBKA0S_MISSING`**: one cause clause, appended to by every other LibKa0s seam in the addon, set outside the `if not lib` branch because they read it on both paths. A cross-file contract, not an implementation detail. Also publishes **`NS.ApplySkin`** and **`NS.MakeCloseButton`** — the latter wrapped once so `lib.MakeCloseButton`'s **third** argument, this addon's folder name, is passed from every close control it builds; a two-argument passthrough would run, return a button, stay green in every suite, and draw a multiplication sign forever (anti-patterns #64). And **`NS.MakeResizable`**, the History window's corner grip: `Core.MakeResizable` by reference (Core minor 10's `canResize` gates it on Lock frame, `onResizeStop` saves once per release), or the pre-library grip on a degraded install (#33). |
| `core/LifecycleSetup.lua` | The **`LibKa0s-Lifecycle-1.0`** seam (`slash-commands-§7`): **`NS.Lifecycle`**, the one latch every reason to be inert holds (`NS.HOLD_DISABLED`, `NS.HOLD_PERF`), plus **`NS.StandDown`** / **`NS.StandUp`** (every registration this addon owns torn out and rebuilt), **`NS.After`** / **`NS.CancelDeferrals`** (cancelable deferrals), **`NS.IsStoodDown`**, **`NS.AddonIsOff`** (the stored switch the slash gate and the launcher ask), **`NS.OnEnabledChanged`** and **`NS.BindLifecycle`** (AceDB's three profile callbacks onto `NS.OnProfileEvent`). TOC position is **conventional**: nothing resolves at load, and the latch is first touched from `addon:OnEnable`. Without the library it degrades to a hold set and two edges written out locally. See [disabled-state.md](disabled-state.md). |
| `core/PerfSetup.lua` | The addon's half of **`LibKa0s-Perf-1.0`** (performance-§1): the five in-combat buckets (`lootLine`, `currencyLine`, `moneyLine`, `spellCast`, `ledgerEvent`), the `perf` hold on the latch and the `/lh perf` handler. TOC position directly after `core/LifecycleSetup.lua` is load-bearing. See [performance.md](performance.md). |
| `core/WidgetsSetup.lua` | The **`LibKa0s-Widgets-1.0`** seam: **`NS.MakeDropdown(parent, width)`**, **`NS.HasWidgets()`**, **`NS.CloseMenu()`** and **`NS.CopyWindow(descriptor)`** and **`NS.MakeLineChart(parent, opts)`** (the Timeline's chart; nil without the library) with **`NS.LineChartChrome()`** (its published paddings, read by the in/out strip while the chart is cleared) and **`NS.MakeAutocomplete(editBox, opts)`** (the Search box's suggestion list on every tab, P9; nil without the library) — the export copy window, a lazily-built handle rather than a frame, so a session that never exports creates nothing. One factory for all ten flat dropdowns this addon draws — the filter bar's nine and the export modal's Data Set picker — and it is where the widget's art is resolved: a vendored library cannot know which addon folder it sits in, so `chevron` and `check` are looked up through `NS.Icon` **here** and passed in as parameters, once, rather than at each call site. It passes **no `glyphFont`** and that is a decision: the field is a *precondition* for any option carrying `opt.glyph`, no option this addon builds carries one (the multi-select tick is markup the library splices itself, the Character rows' class icons are markup folded into a label), and a proportional face passed for a glyph nothing draws renders a box. It replaced 208 lines of `modules/Browser.lua` — the collection's third copy of one widget. `nil` is a real answer both ways: `NS.MakeDropdown` returns nil with no library and both surfaces refuse to draw rather than build a control that opens no menu, and `NS.CloseMenu` becomes a no-op. **`NS.HasWidgets()`** is the same question asked with nothing built — a surface whose only control is a dropdown would otherwise have to create its window to learn the answer, and `modules/Export.lua`'s window carries a global name, so a build-and-discard probe stranded one `LootHistoryExportWindow` per open. |
| `core/DebugLogSetup.lua` | The **`LibKa0s-DebugLog-1.0`** seam: `NS.DebugLog` and the global `NS.Debug` sink. Replaced the 359-line `modules/DebugLog.lua`. The window chrome is deliberately split: `applySkin` **is** passed, as a closure resolving `NS.Browser` at frame-build time (hoisting it into a load-time local silently loses the skin — `modules/Browser.lua` loads long after `core/`), while **`makeCloseButton` is still deliberately not passed**. The descriptor does carry **`addonName = addonName` beside `name = addonName`**: `name` seeds the frame globals, `addonName` is what the library builds a texture path from, and that one line turns the console's title strip into three icon controls (`close`, `copy`, `clear`) on both the console and its copy window. The window *edge* is shared across every Ka0s window; the *close control* on a library-drawn window is the library's — and since Core minor 6 the library's is this collection's `close` mark, so the two now match without either side overriding the other (standalone-windows; closed issue [LIBKA0S-19](https://github.com/tusharsaxena/LootHistory/issues/26), asserted in `tests/test_debuglog.lua`). |
| `core/PoolSetup.lua` | The **`LibKa0s-Pool-1.0`** seam: `NS.Pool` with `New`, `Acquire(pool, factory)`, `ReleaseAll(pool, before)` and `Counts(pool)`. TOC position is **conventional**: nothing resolves at load, and every `NS.Pool.New` call is inside a function (`modules/Analytics.lua:213`). It ended this addon's one genuinely wrong copy of a shared idea: the old chart pool hid its active widgets and dropped them, so the free list stayed empty and every `LayoutCharts` pass allocated a fresh frame per chart element — and frames are never destroyed in WoW. The `before` hook is not garnish: a host releasing a pool of panels releases each panel's own row pool first. Since LibKa0s v1.17.0 (Pool minor 3) `ReleaseAll` parks the active set **backward** — `Acquire` pops the free list from the end, so releasing the last rank first hands every widget back to the rank it already held instead of alternating that mapping on every render. `core/PoolSetup.lua`'s degraded fallback releases backward too: the copy that calls itself “the same pool, locally” is the one place the published contract must not quietly differ. |
| `core/LauncherSetup.lua` | The **`LibKa0s-Launcher-1.0`** seam: **`NS.Launcher`**, the minimap button and the broker plugin as **one** LibDataBroker object registered twice (launcher-§1). It replaced `B:SetupMinimap` / `B:RefreshMinimap` / `B:SetMinimapHidden` in `modules/Browser.lua`. The descriptor's `name` is the addon's **folder** name on both registrations — LibDBIcon keys the button by it — its `icon` is `media/logos/loothistory.logo.128.tga`, the same file the TOC's `## IconTexture` names (launcher-§4), and `minimap` is a **function** answering `db.global.minimap` rather than the table, because AceDB replaces any table captured at file load. **The two buttons are the library's** (Launcher minor 4, LibKa0s v1.58.0; launcher-§2, standard v2.67.0): **left-click opens the settings panel** (`openSettings`, `NS.Panel:Open`) in either state, and **right-click opens the options menu** — the client's context menu, titled with the label, with four checkboxes because this addon has all four states (ADDONS.md's row): **Enabled** (`isEnabled` = `not NS.AddonIsOff()`; `setEnabled(on)` runs the `/lh enable` or `/lh disable` handler), **Locked** (`isLocked` = `B:IsLocked`, the *Lock frame* row's `settings.locked`; `toggleLock` writes that row's path through `Schema:Set`, because this addon has no lock verb), **Test mode** (`isTestMode` = `BrowserTable.testMode`; `toggleTestMode` runs the `/lh test` handler) and **Show window** (`isWindowShown` = the History window's `IsShown`; `toggleWindow` runs the `/lh toggle` handler). The verb handlers are reached through a local `runVerb`, which looks the verb up in `NS.COMMANDS` at call time and calls its `entry[3]`, so every entry is the verb itself — feature-verb gate and chat line included — never a copy. While disabled the library grays the last three with "enable the addon first" and calls none of them. The retired `onClick`, `leftClickLabel` and `disabledLine` are no longer passed. The **status tooltip is the library's** too (Launcher minor 3, LibKa0s v1.57.0; launcher-§1): it draws on every hover, disabled included — `Ka0s Loot History  v<version>` (`NS.Version()`, the TOC's), `Enabled: Yes|No`, `Locked: Yes|No`, `Test mode: On|Off`, the addon's one line (`onTooltipShow`: the record count), then the fixed hints `Left-click: Open settings` and `Right-click: Options menu`. Every field is a function, asked on every show and every menu open. `Register()` runs from `addon:OnInitialize`, after `NS:InitDB`. **No degradation stub** — unlike every other seam here, nothing in the addon calls into this module except `OnInitialize` and the `minimap.shown` row's `set`, and both already guard on `NS.Launcher`; a stub answering `IsShown`/`SetShown` would be a second copy of state that lives in `db.global.minimap`. No profile event and no reset replaces `db.global.minimap` (launcher-§3), so the button keeps the table it was handed at `Register` and nothing in this addon names LibDBIcon directly. |
| `core/LootHistory.lua` | `AceAddon:NewAddon`; `OnInitialize`/`OnEnable`; `PLAYER_ENTERING_WORLD` → once-per-session retention prune. Owns `NS.bus`/`NS.addon`, the `NS.NewBusTarget()` bus-receiver factory, and **`NS.OnProfileEvent`**, the one adopt path AceDB's three profile callbacks reach (the latch, one log line, then every setting's effect re-applied, and never a prune: the retention is account-wide; see [profiles.md](profiles.md)). |
| `core/Database.lua` | AceDB `InitDB` + `RunMigrations` (schema-migration seam, whose v8→v9 step moved every setting from `db.global` into the `Default` profile and whose v9→v10 step lifted `retentionDays` back to `db.global`, owner decision D6) + `RepairBoundStates` (the deferred warbound-state split a migration can't do, armed by `ArmBoundRepair`), `Add`/`Query`/`ActiveHistory`/`Delete`/`PruneOld`/`Purge`/`Stats`/`Export`/`FireHistoryChanged`, retention. `ActiveHistory` is the read seam that swaps in the test dataset over the raw account-wide history — filtering is point-in-time (decided at capture), so reads never hide or resurrect a stored row (see Data model). |
| `defaults/Global.lua` | `NS.defaults.global`, the account-wide half: `schemaVersion`, `history`, `retentionDays` (the one setting that governs recorded data, D6), `minimap`. |
| `defaults/Profile.lua` | `NS.defaults.profile`, every setting: `settings` (incl. `recordCurrency`, the window geometry and the `auction` cascade), `blacklist`, `whitelist`, `currencyBlacklist`. |
| `locales/enUS.lua` | Canonical strings; `NS.L` metatable fallback. |
| `settings/Schema.lua` | One row per setting — single source for AceDB defaults, panel widgets, slash get/set/list/reset. The **`LibKa0s-Schema-1.0`** seam: descriptor, degradation stub, and the host's `Schema:Set` / `:Get` / ... names delegating to `NS.SchemaRuntime`. `NS.COMMANDS`. |
| `settings/Slash.lua` | The **`LibKa0s-Slash-1.0`** seam. AceConsole `/lh` + `/loothistory`; the dispatcher, help header/rows, landing rows, schema CLI and type-aware parser are the library's, reading the host's positional `NS.COMMANDS`. Host-owned: the purge / global-reset / filter-list-clear confirm dialogs, `CliResetAll` (options-ui-§12's global reset, the profile reset behind `/lh resetall`, the General page's Defaults button and the Master controls tab's **Reset all settings**), and `FormatSchemaValue` — the descriptor's `format` hook for `type = "table"`, the one row type the library has none for. |
| `settings/OptionsSetup.lua` | The **`LibKa0s-Options-1.0`** seam: the canvas shell, breadcrumb header, lazy Defaults button, page registry, scroll + always-shown-scrollbar patch, widget makers, two-column flow engine, `SetRenderer`, the two refresh tiers, the page chrome (`TabStrip` / `SubTabStrip`) and the schema composers (`MasterControls`). Where every declined surface is recorded. **Its TOC position is load-bearing** — `settings/Schema.lua` calls `NS.Options.MasterControls` at file load, and `settings/Panel.lua` takes `NS.Options` as a file-scope upvalue, so it must load above both. |
| `settings/Panel.lua` | The page builders on top of that seam: the landing page, the **General** subcategory and the registration of the Profiles page after it. General's six-tab strip is drawn by hand because two of its tabs (Filters, AH Price) hold no schema rows to partition. Plus the live DB stats block and the two surfaces the library has no maker for — the inverted set picker and the pooled AH price table, the latter now reordered through the shared `ReorderList`. |
| `settings/Profiles.lua` | The **Profiles** subcategory (options-ui-§3): AceDBOptions' own profile manager drawn by AceConfigDialog into a canvas, no Defaults button, registered last by `P:Register`. The addon's one AceConfig use; opts out when AceDBOptions or AceConfig is missing. See [profiles.md](profiles.md). |
| `modules/AuctionPrice.lua` | `NS.AuctionPrice:GatherAll(itemLink, itemID)` reads an AH price for a just-looted item from every installed third-party pricing addon (Auctionator / TSM / OribosExchange), capturing **every configured key** into a nested `provider → key → copper` map (`settings.auction.capture`), not just one; every provider call is `pcall`-wrapped so a broken/absent addon degrades to `nil` and the gather continues. `NS.AuctionPrice:Pick(map)` is the read-time seam that selects one price from that map via the user-configurable `settings.auction.priority` cascade (first present key wins), returning `price, tag`. Third-party integration boundary — presence-gated here, **deliberately outside** `core/Compat.lua` (Blizzard-API-only); see [compat-layer.md](compat-layer.md#third-party-pricing-addons-stay-out-of-compat). |
| `modules/Attribution.lua` | Source-resolution engine: stamps `State.lootContext` from peripheral events; `Consume` returns source/detail/confidence or `OTHER`/`INFERRED`. Loads before Filters/Collector. |
| `modules/AttributionOut.lua` | The **loss side** of attribution: `StampOut` writes `State.outContext`, `OnInteraction` keeps `State.scopes`, `ReasonContext` feeds `Ledger.PickReason`. Installs the latch-gated outbound post-hooks once per session and registers its events on a private target (`__outEv`). `EnableOut` / `DisableOut`, the latter called from `NS.StandDown`. |
| `modules/Filters.lua` | `NS.Filters`: the blacklist/whitelist item-id lists — `Add`/`Remove` (copy-on-write, mutually exclusive), `Blacklist`/`Whitelist` (the live id sets), `SortedIDs` — **plus the currency blacklist** (`AddCurrencyBlacklist`/`RemoveCurrencyBlacklist`, `CurrencyBlacklist`; blacklist-only, keyed by `currencyID`). Parsing and labeling an entry is the Filters tab's LibKa0s IdList's job, not this module's. On change: a direct `Collector:RefreshUpvalues()` re-cache + `Database:FireHistoryChanged()`. Data-only; loads before Collector; no `Enable`. |
| `modules/Scanner.lua` | `NS.Scanner`: stateless, side-effect-free reads — `ScanContainers(ids)`, `ScanEquipped`, `ScanCurrencies`, `ReadMoney`, `ReadWarbandMoney` — returning count maps, every WoW call through `NS.Compat`. Container ids come from `Enum.BagIndex` member names, never numbers. |
| `modules/Holdings.lua` | `NS.Holdings`: the `db.global.holdings` store (one entry per holder, the Warband under `"§warband"`) and its read API — `Get`, `ApplyContainer` / `ApplyCurrency` / `ApplyMoney`, `CreditCurrency` / `CreditEscrow`, `MarkGenesis`, `Total`, `Search`, `Holders`, `Describe`, `ForgetHolder`, and the read seams `ActiveStore` / `View`, which answer test mode's sample (`NS.State.testHoldings`) while it is on, as `Database:ActiveHistory` does for rows. Written only by the Reconciler; every write that changes a total reports its close to `NS.Rollup`, and `meta.completeAt` records when a holder's bank was first read. Item type and currency-name reads go through `Compat.GetItemTypeInfo` / `Compat.CurrencyName`. |
| `modules/Rollup.lua` | `NS.Rollup`, the Timeline's daily rollup writer (see [data-flow.md](data-flow.md#daily-rollup)): `NoteClose` (called from `NS.Holdings`' write methods), `OnWrite` (the `NS.Database:OnWrite` hook that tallies gained and lost), `SeedOnce`, `Prune`, `ForgetHolder`, `Keys`, and `ActiveStore`, the day table the Timeline reads (test mode's `NS.State.testDaily` while it is on). `Enable` / `Disable` add and remove the write hook only, so it holds no event and no bus target. Loads right after Holdings. |
| `modules/Reconciler.lua` | `NS.Reconciler`: keeps holdings current as a scan, plan, hold-or-commit pipeline that writes the ledger rows (see [data-flow.md](data-flow.md#the-ledger-holdings-diff--claims)). Fourteen events (below) only **mark parts dirty**; `Flush` scans each dirty, readable part into Holdings and sends `HOLDINGS_CHANGED` once per changed holder. Never scans in combat (`deferred`, replayed on `PLAYER_REGEN_ENABLED`). Two private bus targets: `_settings` for the `trackLedger` switch, `__ev` for the capture events. `Enable` / `DisableCapture` / `Disable`; the last is called from `NS.StandDown`. |
| `modules/Escrow.lua` | Mail and auction-house escrow, as steps appended to the Reconciler's scan, plan and commit lists: inbox and owned-auction columns, own-alt sends, posts, exits (returned, sold or aged out), mail money. Registers no events, so it has no `Disable`, by ruling. |
| `modules/Collector.lua` | `CHAT_MSG_LOOT` handler: self-filter, then the point-in-time gate (blacklist veto → normal quality/source/quest gate → whitelist rescue, recording a plain row with no marker of how it got in), `Consume`, an `AuctionPrice:GatherAll` call to stamp the record's `auctionPrice` map, `BuildRecord`, `Database:Add`. Also the **`CHAT_MSG_CURRENCY` handler** (`OnChatMsgCurrency`): a slimmer gate (`recordCurrency` master toggle → per-source mute → currency blacklist; no quality/quest/itemID checks) that writes a `Type=Currency` row. Caches hot-path upvalues (incl. the id lists, `recordCurrency`, `currencyBlacklist`). |
| `modules/LedgerFormat.lua` | Pure display helpers for ledger rows: `Glyph` / `Color` per direction, `SignedQty`, `QtyText`, signed counts and money. No frames, no events. Loads above Browser. |
| `modules/Browser.lua` | Window shell: frame/skin, tabs, the **shared singleton filter bar + footer** (multi-select Direction/Bound/Quality/Type/SubType/Source/Zone/Character, date, search) that drives BOTH the History table and the Insights charts (`CurrentFilter`), group-by, the **tab-aware `Export` button** (`OpenExport`). The LDB launcher and LibDBIcon minimap button are no longer here — see `core/LauncherSetup.lua`. Its ten dropdowns are **`LibKa0s-Widgets-1.0`**'s, through `core/WidgetsSetup.lua` — this file used to *be* the widget. The window is `HIGH` strata, deliberately below the shared popup's `FULLSCREEN_DIALOG`, so an open menu draws above it. Since LibKa0s v1.13.0 the popup intercepts nothing — it listens on `GLOBAL_MOUSE_DOWN` — so a click outside an open menu closes the menu **and** lands here on the same press. |
| `modules/BrowserWidgets.lua` | The filter bar's dropdown-option kit, split out of `modules/Browser.lua`: `dataset`, `withAll`, the Bound labels and the seven option builders (`B._options`: source, char, type, subtype, zone, quality, bound). Reads no browser state and builds no frame. Extends `NS.Browser`; Browser binds the builders at load, so it loads directly above `modules/Browser.lua`. |
| `modules/BrowserFilterBar.lua` | The shared filter bar, split out of `modules/Browser.lua`: `B:BuildFilterBar` (both rows of dropdowns, the search box, Save/Reset/Clear and Export), the static option sets and the bar button. Extends `NS.Browser`, binds its `B._` helpers at load, so it loads directly after `modules/Browser.lua`. |
| `modules/BrowserTable.lua` | Virtualized pooled-row table: the slice → bind half of the pipeline; columns, header arrows, row interactions (link / blacklist / delete), test mode. |
| `modules/BrowserTableGroup.lua` | The table's display-list layer, split out of `modules/BrowserTable.lua`: filter → sort → group (`SortRecords`, `SetSort`, `SetGroupBy`, `ToggleCollapse`, `GroupRecords`, `BuildDisplayList`). `OrderedFilteredRecords` exposes the on-screen order for export. Extends `NS.BrowserTable`, binds its `BrowserTable._columnByKey` / `_groupColumn` seam at load, so it loads directly after `modules/BrowserTable.lua`. |
| `modules/Export.lua` | Export modal (`NS.Export:Open`) at `DIALOG` strata, config-driven per invoking tab (`{ title, providers, csv }`): Data Set dropdown (All Data / Current View, a **`LibKa0s-Widgets-1.0`** dropdown through `core/WidgetsSetup.lua`); on an install with no library the modal **refuses to open**, decided by `NS.HasWidgets()` *before* the frame is created, so the refusal costs nothing and memoizes nothing; `CSV` serializes loot rows (History) and `InsightsCSV` a sectioned analytics dump (Insights); `WowheadLink` builder; the copy window is **`LibKa0s-Widgets-1.0`**'s `CopyWindow`, described (not built) here through `core/WidgetsSetup.lua`'s `NS.CopyWindow`. Called directly by the Browser; no bus message. |
| `modules/Analytics.lua` | Insights tab, split by two dividers into a **LOOT** block (items-only stat/highlight cards + breakdowns: source, value, quality, item type, bound type, per-character companions, hour/weekday + per-day strips, top zones/items/value) and a **CURRENCY** block (Currency Collected, Currency by Type × Source, Currency by Character × Type, currency-per-day) shown only when the range has currency events — all from one `Database:Stats` pass, **scoped by Insights' own filter** on the shared bar (`Browser:CurrentFilter("Insights")`, per tab since P11, no range selector of its own). Owns the cards, refresh, layout, `BuildCharts`, the bus subscription and `LayoutCharts`; the pure half is `modules/AnalyticsFormat.lua` and the drawing half `modules/AnalyticsCharts.lua` (split three ways for `layout-§1`, issue #32). |
| `modules/AnalyticsFormat.lua` | The Insights tab's pure half, loaded **before** `modules/Analytics.lua`: the layout constants (published as `Analytics.K`), the color tables and palettes (`Analytics._fmt`), and the formatting and segmenting helpers (`_truncate`, `_charStackSegments`, `_buildCharStackRows`, `_money`, `_tipText`, `_dayKeyList`, `_shortDay`, `_sortedByCount` and the color lookups). Builds no frame; both other Insights files bind what they need to file-scope locals at load. |
| `modules/AnalyticsCharts.lua` | The Insights tab's drawing half, loaded **after** `modules/Analytics.lua`: pooled bar/strip/list renderers — the widget factories, the section chrome (published on `Analytics._charts`, which `BuildCharts` resolves at call time) and the `render*` methods `LayoutCharts` calls. |
| `modules/AnalyticsLedger.lua` | The Insights tab's ledger half, loaded after `modules/AnalyticsCharts.lua`: the Gains and losses divider, the pre-`ledgerSince` caveat and the three back-to-back charts (reason, character, kind). Chrome lives in `inst.ledgerUI`, outside the pools. Registers nothing; no `Disable`, by ruling. |
| `modules/HoldingsTab.lua` | The **Holdings** tab, registered through `B:RegisterTab` (`order = 40`). `HT.BuildModel` is pure; the view is a pooled expandable list (thing, then holders with the container split and scan age). Listens to `HOLDINGS_CHANGED` on its own target; `Disable` is called from `NS.StandDown`. See [browser.md](browser.md#holdings-tab). |
| `modules/TimelineModel.lua` | The Timeline's pure model: day walk over `db.global.daily`, carry-forward, holder ranking and the `timelineMaxLines` cap, Total, in/out flows, the intraday rebuild with its daily fallback, hover lines and chart data. No frames, no events. Loads before `modules/Timeline.lua`. |
| `modules/Timeline.lua` | The **Timeline** tab, registered through `B:RegisterTab` (`order = 30`; honors Search, Date and Character only): thing picker over the shared Search, `NS.MakeLineChart`, in/out strip, legend, hover. Listens to `HOLDINGS_CHANGED` and `RECORD_ADDED` on a private target behind one coalesced repaint; `Disable` is called from `NS.StandDown`. See [browser.md](browser.md#timeline-tab). |
| `modules/TestData.lua` | `NS.TestData`, test mode's ledger half: `Publish(records)` (called by `BrowserTable:SetTestMode`) builds the session-only Holdings and Timeline sample from the History sample's universe — `NS.State.testHoldings` (four sample characters and the Warband, thirty items, three currencies, gold) and `NS.State.testDaily` (120 days, each series walked back from today's holdings with the sample rows' flows folded in) — deterministically, under a fixed seed; `Publish(nil)` clears both. `Describe(key)` names a sample thing for `NS.Holdings`. No events, no `Disable`. |
| `modules/Diagnostics.lua` | The diagnostics report's **sections** (`debug-logging-§14`): `/lh diagnostics` and `/lh debug diagnostics` both call `NS.DebugLog:RunDiagnostics()`, and **`LibKa0s-DebugLog-1.0`**'s helper writes the markers, its half of the identity header, a pcall per section, the cap and the append around the ordered list `NS.Diagnostics.Sections()` answers. Reads stored state and module fields only, never an item, tooltip or keystone API; see [module-map.md](module-map.md) for the section list. |

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

## Settings schema

`settings/Schema.lua` is the single source of truth: one row drives the AceDB default, the panel
widget and the slash get/set/list/reset behavior, and every write to a row's path goes through
`Schema:Set(path, value)` (validate → write to the active profile, `NS.db.profile` → `onChange`). Two stored rows
write `db.global` through their own `get`/`set` instead: `minimap.shown` (launcher-§3) and
`settings.retentionDays`, which stays account-wide because it governs the shared history (owner
decision D6; see [profiles.md](profiles.md)). The runtime behind the
seam is **`LibKa0s-Schema-1.0`** (`NS.SchemaRuntime`): every host name is a one-line delegate to it,
and a write-completing, log-silent stub in the same file stands in when the library is absent.
Twenty-two rows ship today, on **one** schema-backed page: the General subcategory, whose six tabs are
Master controls, Capture, AH Price, Interface, History and Filters, the last holding no rows.
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
| `Ka0s_LootHistory_SettingsChanged` (`SETTINGS_CHANGED`) | `Schema` — eight `onChange` handlers, six reasons (enabled / quality / questfilter / currency / excludes, plus `chrome` from the Master controls tab's `scale` / `alpha` / `locked`), and `S:AdoptProfile` with the seventh, `profile`, once per profile switch, copy or reset | reason string | Collector (`RefreshUpvalues`), Browser (`OnSettingsChanged`) |
| `Ka0s_LootHistory_HoldingsChanged` (`HOLDINGS_CHANGED`) | the Reconciler only: `Reconciler:Flush`, once per holder whose holdings moved, and `Reconciler:ForgetHolder` | `holder` key (`PlayerKey()` or `"§warband"`) | HoldingsTab and Timeline (repaint while their pane is shown) |

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
feature verbs `show` / `hide` / `toggle` / `test` / `purge` / `holdings` refuse, with the collection's one refusal
line, and the addon itself is genuinely inert. See [disabled-state.md](disabled-state.md).

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
| `resetall` | Reset all settings to defaults: `options-ui-§12`'s global reset, the **profile reset** (`db:ResetProfile()`). The same act as the General page's **Defaults** button and the Master controls tab's **Reset all settings** (which confirms first): the active profile's settings, id lists, AH cascade, saved view and window geometry come back as shipped, and test mode ends. The loot history is account-wide and untouched (`/lh purge` clears it), and so is the minimap button (launcher-§3). Scope matrix in [`schema.md`](schema.md#reset-semantics) |
| `profile` / `profile <name>` | Bare: list the profiles, the current one marked. With a name: switch to that existing profile (exact case; surrounding quotes stripped, spaces kept). An unknown name is refused with the list and never created; a switch in combat is refused. The behavior is `LibKa0s-Slash-1.0`'s `CliProfile` (Slash minor 17) over `NS.db`, and it answers while the addon is disabled. See [profiles.md](profiles.md) |
| `holdings <query>` | Print the ten largest account-wide holdings whose name contains the query (gold as money, others as counts), from `db.global.holdings`. A feature verb: refused with the one disabled line while the addon is off. Reads only; never scans |
| `debug` / `debug on` / `debug off` / `debug diagnostics` / `debug events` | Bare: toggle the debug console window. `on` / `off`: set the session-only logging flag (`NS.State.debug`, never persisted), independent of the window. `diagnostics` is tested first and runs the same report as the `diagnostics` verb. `events`: print the event names this client refused at registration (`NS.RejectedEvents`, `events-frames-taint-§1`), or `none`; it needs no console |
| `diagnostics` | Append the diagnostics report to the debug console (`debug-logging-§14`), after whatever trace it already holds, with logging on or off and while the addon is disabled. The run turns session logging on first when it is off (standard v2.71.0), and the console's **Diagnostics** link runs the same call. No other name (`diag`, `dump`) runs it. See [debug.md](debug.md) |
| `perf` | The `LibKa0s-Perf-1.0` A/B capture: bare opens the step panel, `perf finish` prints the report (bucketed costs of the five in-combat handlers) and the JSON dump. A diagnostic, so it answers while the addon is disabled; a capture takes the `perf` hold on the latch. See [performance.md](performance.md). |
| `test` | Toggle a synthetic preview dataset for the table, Insights, Holdings and the Timeline (session-only; the same switch as the Master controls **Test mode** checkbox, and combat ends it) |
| `purge` | Delete ALL loot history (confirm dialog) |
| `help` | Print the generated command index |

---

## The disabled state

**Disabled means the addon is not running** (`slash-commands-§7`). `core/LifecycleSetup.lua` is the
`LibKa0s-Lifecycle-1.0` seam: one latch, stood down while any named hold is taken, and every route to
the switch arrives at `NS.Lifecycle:Set("disabled", …)`. Standing down unregisters every event, bus
subscription and unit frame, cancels every deferral `NS.After` armed and hides the windows at the
source (`B:VisibilityAllows`); `hooksecurefunc` is the one sanctioned gate. The slash surface, the
settings panel, AceDB and the launcher registration survive as setup, and `tests/test_disabled.lua`
is the conformance suite. The full account is in [disabled-state.md](disabled-state.md).

---

## Event subscriptions

**Every row below is torn out, not gated, while the addon is disabled** — see
[disabled-state.md](disabled-state.md). The `hooksecurefunc` rows are the one exception the
standard sanctions, because that API has no un-hook; they gate their bodies on the latch (`Attribution:Stamp` for the Phase 1 hooks, `StampOut` and the `On*` bodies of `modules/AttributionOut.lua` for the ledger's).

The Reconciler's rows register only while `settings.trackLedger` is on, one event at a time through `NS.SafeRegisterEvent` on a private target (fourteen names; the combat edge is the same `PLAYER_REGEN_ENABLED` the visibility row uses, on a different target). In combat a handler sets a dirty bit and nothing else.

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
| `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` / `_HIDE` | `OnInteraction`, table-driven by `R.READABLE_ON`: a Banker or AccountBanker makes the bank readable (marks bank, tabs and warband gold), the mailbox makes `mail` readable, the auction house arms `auctionHouse`; a final `Flush` on hide, then unreadable | `modules/Reconciler.lua` |
| `MAIL_INBOX_UPDATE` | marks `mail` while the mailbox is open; arms the fuse (the column is read by `modules/Escrow.lua`'s scan step) | `modules/Reconciler.lua` |
| `OWNED_AUCTIONS_UPDATED` | while the auction house is open, makes the owned-auctions list readable and marks `auctions`; arms the fuse | `modules/Reconciler.lua` |
| `PLAYER_REGEN_ENABLED` | runs a login reconcile deferred by combat, else replays a deferred flush | `modules/Reconciler.lua` |

All flavor-varying or deprecated calls behind these handlers are routed through
`core/Compat.lua` (the compat firewall) — no inline `WOW_PROJECT_ID` branching in feature code.

**Every event row above registers through one per-event helper** (events-frames-taint-§1):
`NS.SafeRegisterEvent` / `NS.SafeRegisterUnitEvent` / `NS.SafeRegisterEvents`, `LibKa0s-Core-1.0`'s
(Core minor 8) published by `core/CoreSetup.lua`, so a name the client refuses costs only itself. The
refused names land on the addon's own `NS.RejectedEvents`, which `/lh debug events` prints and the
diagnostics report carries;
[midnight-quirks.md](midnight-quirks.md#unknown-event-names--one-refusal-costs-one-edge) records the trade.

---

## Menus: two mechanisms, on purpose

Neither menu is a Blizzard `UIDropDownMenu`. The ten flat dropdowns are `LibKa0s-Widgets-1.0`'s,
sharing one process-wide popup that every non-click close path shuts with `NS.CloseMenu()`; the
History row's right-click action list stays hand-rolled because it needs per-row disable. See
[browser.md](browser.md#menus-two-mechanisms-on-purpose).

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
answer. The pricing shims outside `core/Compat.lua` are the one standing non-row, listed there.

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
| `schema.md` | `LootHistoryDB`’s two scopes (account-wide history, per-profile settings), the loot record, the settings rows, carve-outs, migrations |
| `settings-panel.md` | The panel tree, per-option behavior, and the write seam |
| `data-flow.md` | Loot event in → gate → attribute → record |
| `common-tasks.md` | Recipes for the changes made most often here |

### Conditional (documentation-§3, Tier 2)

| Doc | Status | Trigger |
|---|---|---|
| `slash-dispatch.md` | Present | 20 verbs in `NS.COMMANDS` |
| `midnight-quirks.md` | Present | Bind-state and currency-API behavior the addon works around |
| `compat-layer.md` | Present | 47 shims (`grep -cE '^\s*function\s+[A-Za-z_][A-Za-z0-9_]*\.' core/Compat.lua`) of addon-specific shimming beyond LibKa0s |
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

## Documented deviations

The register (`documentation-§3`). **A deviation not in this table is not ratified** — the reasoning
may live at length in this repo's GitHub issues or in an audit bundle, and the **Why**
column cites that id, but an issue declining a rule with no row here is itself the deviation.
An audit reads this table, records these as accepted, and does not count them toward its MUST tally.

**Re-check trigger** is the condition that *ends* the deviation, written so a reader can tell whether
it has already fired. This table is **not a graveyard**: a row whose cited rule the standard has since
changed — so the behavior is now mandated or permitted outright — is retired, not kept for history.
Ten such records are named below the table rather than carried in it.

| Rule | What differs | Why | Decided | Re-check trigger |
|---|---|---|---|---|
| `architecture-§5` | The **`settings.auction.priority`** ordered cascade, neither a schema row nor registry membership, is written to the active profile (`NS.db.profile.settings.auction.priority`) directly rather than through `NS.Schema:Set`. It is seeded empty on first read by `NS.AuctionPrice:GetPriority` (`modules/AuctionPrice.lua:143`) and written by `ReconcilePriority` / `MovePriorityWithin` (`:139-195`); the global reset brings it back with the rest of the profile. | The cascade is an order over a **fixed** member set, the `NS.Constants.AUCTION_KEYS` tags, which the player only reorders. `architecture-§5` makes that a **value**, not a registry, and a value with no row is what its **MUST NOT** leaves a register row for. No schema row type expresses a drag-reordered list, so there is no row for `Set` to validate against. Reasoned in [`schema.md`](schema.md) *Standards note*. The id filter sets and the named non-setting state left this row on 2026-09-12; see below. | 2026-07-17 | `settings.auction.priority` gains a schema row, an ordered-list row type or a whole-value row, and every write to it goes whole through `Schema:Set`. That retires this row. |
| `options-ui-§1` | The inverted set pickers (`settings.excludedSources`, `settings.auction.capture`) are drawn by **this addon**, from `afterGroup`, rather than by one of the library's widget makers. | The library's makers are checkbox / slider / dropdown / editbox / color picker; a wrapping `InlineGroup` of checkboxes whose stored value is the logical **inverse** of the tick is none of them, and `RenderGrid` takes no `parent` and would open a second overlapping scroll frame. The rows stay in the schema, so the CLI and every reset still see them. Closed issue [**LIBKA0S-14**](https://github.com/tusharsaxena/LootHistory/issues/20). | 2026-08-01 | `LibKa0s-Options-1.0` gains a multi-check / set maker with a `parent`, or a second host needs the same shape (one host, one shape is why it was not raised upstream). |
| `localization-§1` | This addon ships **English only**: the `NS.L` seam is exported and `locales/enUS.lua` ships, but only a handful of strings route through `NS.L` (the Profiles page name, the `profile` and `diagnostics` help descriptions and the library-absent line) — every other label, tooltip and message is a hardcoded English literal. | `localization-§3` names English-only as one of the routing SHOULD's **two terminal compliant states**, and names this row as what makes it terminal: without it the SHOULD is formally open and every audit re-files it, which is what has been happening. Both `localization` MUSTs are met unconditionally — the seam is exported with the key-returning fallback (`locales/enUS.lua:5`) and `enUS.lua` ships carrying no dead keys. The argument was written at `locales/enUS.lua:7-11` and calls itself "an accepted scope decision, not an oversight"; a comment is exactly what `documentation-§3` says does not ratify a decision, which is why `LH-48` in `docs/audits/2026-09-07/` filed it. This row is the ratification the comment was standing in for. | 2026-09-08 | **The first non-English locale file added to `locales/`.** That change routes the strings and retires this row. |
| `localization-§4` | **Deconstruct attribution falls back to matching a localized spell name.** `Attribution:DeconstructSource` resolves a player cast by spell id first (`DECONSTRUCT_ID`, `modules/Attribution.lua:32-43`); on a miss it compares the cast's **client-locale name** against tokens derived from seed spell ids (`NAME_SEEDS`, `:53-59`; `seedToken` resolves each through `NS.Compat.GetSpellName` at `:64`; the substring match is `:94`), where §4 says a game entity is identified by id, never by a localized display string. The reasoning is at `:20-31`, which points at this row. | Modern retail splits Milling and Prospecting into generic, per-expansion and **per-herb / per-ore "Mass Mill" / "Mass Prospect"** spells, and that id set is **not enumerable**: it is too large and grows every patch, so an id-only table silently stops attributing each new variant. The compared names are **derived from ids on the same client** at match time, so no English literal is ever compared and the match is locale-correct by construction: "Milling" on enUS is "Mahlen" on deDE on both sides of the compare. Closed issue [#2](https://github.com/tusharsaxena/LootHistory/issues/2); audit finding `LH-74` in `docs/audits/2026-09-23/`. | 2026-09-24 | **Blizzard exposes a stable deconstruct token or category** on the cast (a spell category, a profession-action flag, anything id-shaped), **or the Mass Mill / Mass Prospect id set becomes enumerable** (a stable list or an API that returns it). Either one moves the fallback onto ids and retires the row. |

- Narrowed on 2026-09-12 ([#30](https://github.com/tusharsaxena/LootHistory/issues/30)): `settings.window` and `savedView` left the `architecture-§5`
  row as named non-setting state (standard v2.44.0), and LibDBIcon's `minimapPos`, never in it, is named beside them in [schema.md](schema.md#named-non-setting-state-owners-and-writers); the `B:SetupMinimap` seed over the minimap row's stored `minimap.hide` key was deleted.
- Narrowed on 2026-09-12: the id filter sets left the `architecture-§5` row, as a structural
  registry whose writer and load pass [schema.md](schema.md#the-id-filter-sets-a-structural-registry) names (history in `schema.md`, *Standards note*).
- Retired on 2026-10-06: the `performance-§12` row (*no perf harness is wired*, decided 2026-08-05,
  closed issue [**LIBKA0S-17**](https://github.com/tusharsaxena/LootHistory/issues/22) and the decline in
  [#29](https://github.com/tusharsaxena/LootHistory/issues/29)). Its re-check trigger fired: the timeline
  ledger put real work behind in-combat `BAG_UPDATE`, money and currency events, and the owner ratified
  wiring the harness (spec F2). `core/PerfSetup.lua` now brackets the five in-combat handlers, `/lh perf`
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
- Never a row: the AH Price table's pooled host, `ctx._priHost`, declined in closed issue [#21](https://github.com/tusharsaxena/LootHistory/issues/21).
  `options-ui` never names `SetRenderer`, so that declined a library adoption rather than a rule; the
  reasoning is at `settings/Panel.lua:772-778` (`LH-47` in `docs/audits/2026-09-07/`).

### Files over the 1500-line cap

The `layout-§1` census: one row per authored, tracked `.lua` file over 1500 lines, naming the
terminal state it sits in. Vendored code (`libs/`, `tests/_kit/`) is outside the cap. Gated by the
kit's `tests/_kit/test_layout_cap.lua`.

Nothing is over the cap today. The largest authored file is `tests/test_browser.lua` at 1459 lines,
then `modules/BrowserTable.lua` and `tests/test_browsertable.lua` at 1272 (`git ls-files '*.lua' |
grep -v '^libs/' | grep -v '^tests/_kit/' | xargs wc -l`, 2026-10-07, after `modules/BrowserTable.lua`
shed its display-list layer to `modules/BrowserTableGroup.lua` and `modules/Browser.lua`, now 1231,
its dropdown-option kit to `modules/BrowserWidgets.lua`); the
1000-1500 band is observed and dispositioned in the release watch list (`automated-tests-§4`), not here.

---

## Known limitations

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
- **Slow manual click-looting.** The source context uses a fixed `CONTEXT_TTL` (1.5s). Looting
  items more than ~1.5s apart from one open window can let later items fall back to
  `OTHER`/`INFERRED`. The single-slot context with a fixed TTL is a settled design decision, not an
  open backlog item — see [scope.md](scope.md) *Resolved design decisions*.
- **A currency under a collapsed Currency-tab header has no category.** `Compat.CurrencyCategory`
  rebuilds its cache once on a miss, but `C_CurrencyInfo.GetCurrencyListInfo` enumerates only the
  children of expanded headers, so such a row keeps `itemSubType = nil` and falls out of the subtype
  filter. The addon does not expand the list itself, since that would rewrite the player's Currency
  tab; see [midnight-quirks.md](midnight-quirks.md) *Currency category*.
- **Warband gold away from the bank is unverified** (spec §5.6, smoke LED-6). `Compat.GetWarbandMoney` wraps `C_Bank.FetchDepositedMoney`; whether the client answers it with no bank open is not yet recorded. When it answers `nil` the Warband's gold stays at its last read and ages on the Holdings tab instead of being shown as zero.
- **Escrow is holdings-only until resolved.** Items in the mail and owned-auction columns write no row while in flight (spec S6): a mail from another player, a posted auction and a pending sale surface as rows only when they resolve. The guild bank is outside the account by design (scope.md D3).
- **An AH sale is matched by item name.** The sale mail's subject (`AUCTION_SOLD_MAIL_SUBJECT`, `%s` = the bare item name) is compared with the exited item's stored name, so two same-name items with different ids can mis-attribute one resolution.
- **An unresolved exit is booked as sold after 30 days** (`Escrow.EXIT_TTL`). An auction that left the owned list and never came back by mail or named in a sale mail is written as `OUT AH_SOLD`.
- **The guild cut in `YOU_LOOT_MONEY_GUILD` lines.** The line's first amount may be pre- or post-guild-cut; whichever it is, the diff books the difference to the claim as a plain gold row. Smoke LED-P2-22 records which it is.
- **Own-alt trades are impossible today.** The client allows one online character per account, so the `TRANSFER` path for trades between your own characters is dormant; a trade to another player is `OUT TRADE_GIVE`.
- **Disabled at login: no scan until the next `PLAYER_ENTERING_WORLD`.** With `settings.enabled` off at login the Reconciler registers nothing and runs no `LoginScan`; enabling later schedules a resume scan (one second after `Enable`) only in a session that already logged in, so a session that started disabled reconciles at its next world entry.
- **Play elsewhere is `UNTRACKED`.** Changes made while the addon was not watching (disabled, not installed, or on another PC) are written as `UNTRACKED` rows: bags, gear, gold and currency at the next login or resume, the bank and warband tabs on the first read of the next banker visit ([data-flow.md](data-flow.md#login-and-resume-untracked)). Two PCs each running the addon keep separate SavedVariables, so each sees the other's play this way: holdings totals stay correct, but the reasons (loot, vendor, deposit) are lost. Cross-PC sync is out of scope.
- **Insights' Transfers card depends on the Direction filter.** Insights reads its own filter (per tab since P11), so under its default view (Gains + Losses) the Transfers card reads 0 until Transfers is ticked.
- **The Timeline starts at the upgrade.** A holder's line begins at its genesis, the first full scan after the ledger shipped, and there is no back-casting before it (ledger D5). Counts are per item id, not per variant (item level, bonus ids). A holder that has not logged in since the upgrade has no class, so it draws gray. Several Line-region facts can only be proved in the client (`Frame:CreateLine`, fractional thickness, the cursor-to-plot mapping, daylight-saving day labels); they are the TL-13 list in [smoke-tests.md](smoke-tests.md#timeline).
- **No upgrade-scoring addon interop** (Pawn/Loot Appraiser). Auction-house price interop
  (Auctionator/TSM/OribosExchange) shipped in Rev-2 — see the AH-price cascade above and
  [schema.md](schema.md).

See the [GitHub issue tracker](https://github.com/tusharsaxena/LootHistory/issues) for the full backlog.

---

