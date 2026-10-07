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

Fifty-two authored files load in the fixed order `LootHistory.toc` sets: vendored `libs/` →
`locales/` → `core/` (Compat first) → `defaults/` → `modules/` → `settings/` (last). Ten
`core/*Setup.lua` files and three in `settings/` (`OptionsSetup.lua`, `Schema.lua`, `Slash.lua`) are
the LibKa0s seams. Capture lives in `modules/Collector.lua` and `modules/Attribution.lua`, the
holdings ledger in `modules/Reconciler.lua` and its steps, the window in `modules/Browser.lua` and
its tabs, and every setting in one `settings/Schema.lua` row. A handful of TOC positions are
load-bearing, each carrying a `LOAD-BEARING` comment in the TOC (toc-file-§5; count them with
`grep -c LOAD-BEARING LootHistory.toc`); every other position is conventional, and the TOC says so.

The per-file role table, the directory tree, each load-bearing position with the field it binds,
and the AceAddon lifecycle hooks are in [module-map.md](module-map.md).

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
generated material is out of scope, named once per directory and never enumerated per run:
`docs/audits/`, `docs/reviews/`, `docs/automated-tests/<run>/`, `docs/perf-analysis/<run>/`,
`docs/revendor/<date>-v<tag>/` (the three earliest bundles, `2026-08-25`, `2026-09-03` and
`2026-09-12`, predate the `-v<tag>` suffix) and `docs/superpowers/`. The stores' own
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
then `tests/test_browsertable.lua` at 1392 and `modules/BrowserTable.lua` at 1302 (`git ls-files '*.lua' |
grep -v '^libs/' | grep -v '^tests/_kit/' | xargs wc -l`, 2026-10-07, after `modules/BrowserTable.lua`
shed its display-list layer to `modules/BrowserTableGroup.lua` and `modules/Browser.lua`, now 1231,
its dropdown-option kit to `modules/BrowserWidgets.lua`, and after `LH-14` added characterization cases to
`tests/test_browsertable.lua` and split the last five functions above CCN 15); the
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
- **No upgrade-scoring addon interop** (Pawn/Loot Appraiser). Auction-house price interop
  (Auctionator/TSM/OribosExchange) shipped in Rev-2 — see the AH-price cascade above and
  [schema.md](schema.md).

See the [GitHub issue tracker](https://github.com/tusharsaxena/LootHistory/issues) for the full backlog.

---

