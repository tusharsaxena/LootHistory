# Closed message bus

All inter-module communication uses `AceEvent`-style messages with a fixed name set. The bus is `NS.bus` — the AceEvent-embedded addon object created in [`core/LootHistory.lua`](../core/LootHistory.lua). New entries belong here, in the module headers, and in the [module map](module-map.md). **Don't invent new messages without a reason** — the closed list is what keeps cross-module coupling auditable.

## The six messages

| Message | Sender | Payload | Listeners |
|---|---|---|---|
| `Ka0s_LootHistory_RecordAdded` | `Database:Add` **and** `Database:Amend` ([`core/Database.lua`](../core/Database.lua)) | `(record, index)` | Browser (refresh History), Analytics (live recompute), Panel (live stats), Timeline (coalesced repaint; never counted: the rollup's tallies come from the `Database:OnWrite` hook, because this message is re-sent on every amend) — Browser, Analytics and Timeline repaint through `NS.Coalesce(…, Constants.RECORD_ADDED_COALESCE)`, one pass per 0.2s burst |
| `Ka0s_LootHistory_HistoryChanged` | `Database` — `Delete` / `PruneOld` / `Purge` and the public `FireHistoryChanged` (called by `NS.Filters` on a blacklist/whitelist edit, to refresh the Filters settings tab's list UI) via `fireHistoryChanged`, plus `RepairBoundStates` sending directly on a productive pass ([`core/Database.lua`](../core/Database.lua)) | — | Browser, Analytics, Panel (History stats + the Filters tab) |
| `Ka0s_LootHistory_SettingsChanged` | `Schema` — a row's `onChange`, or `S:AdoptProfile` on a profile event ([`settings/Schema.lua`](../settings/Schema.lua)) | `reason` string | Collector (`RefreshUpvalues`), Browser (`OnSettingsChanged`), Reconciler (re-registers or drops its capture events on the `"ledger"` and `"profile"` reasons), HoldingsTally (wipes its cache on `"ledger"` and `"profile"`), HoldingsTip (re-reads its hot-path settings cache on `"tooltip"`, `"ledger"` and `"profile"`), HoldingsAPI (fires `HoldingsChanged` with a nil holder when `"ledger"` or `"profile"` flips its availability), Reputation and Appearance (re-read their upvalues; re-sync their rows on `"reputation"` / `"appearance"` and `"profile"`), GainFeed and Toasts (#38, on `"toasts"`, `"profile"` and `"enabled"`: GainFeed recomputes what the feeds want; Toasts drops its config snapshot and refreshes each feed) |
| `Ka0s_LootHistory_Gain` | `GainFeed:Send` only ([`modules/GainFeed.lua`](../modules/GainFeed.lua), #38). Collector, Reputation, Appearance, Progress and the Reconciler's diff fill its payload and hand it over; none of them sends | `gain`, the one reused scratch table | Toasts (`OnGain`, on `Toasts.__gain`), Farm (`OnGain`, on `Farm.__ev`, only while a farm session is open; #39) |
| `Ka0s_LootHistory_FarmChanged` | `Farm:Changed` only ([`modules/Farm.lua`](../modules/Farm.lua), #39): every session edge (start, pause, resume, finish, a store swap) and each tally (a gain, a cost, an activity count, a price fill) | `reason`: `start` \| `pause` \| `resume` \| `finish` \| `gain` \| `cost` \| `store` \| `rename` \| `delete` | `NS.FarmPanel` (`modules/FarmPanel.lua`, on its own bus target from `FP:Enable`, coalesced 0.25 s; only while the panel shows); `NS.FarmDetails` (`modules/FarmDetails.lua`, its own bus target from `FD:Enable`, coalesced 0.25 s: the Details window on every reason while it shows the open session, else and the summary on `finish`, `rename`, `delete` and `store` only); the Farm tab (M4.4) will subscribe the same way |
| `Ka0s_LootHistory_HoldingsChanged` | the Reconciler only (`modules/Reconciler.lua`): `Reconciler:Flush`, once per holder whose holdings moved in a flush, `Reconciler:ForgetHolder`, once for a forgotten character, and `Reconciler:AnnounceHolders`, once per holder of a simulation's session store when the simulation stops (`modules/Sim.lua`) | `holder` key (`NS.Util.PlayerKey()` or `"§warband"`) | HoldingsTab (repaints while its pane is on screen), Timeline (the same coalesced repaint as above, only while its pane is visible), HoldingsTally (wipes its per-thing cache), HoldingsAPI (relays it to other addons as `HoldingsChanged`, except during a simulation) |

Exactly one sender is allowed per message — the table is sender-authoritative. `Gain` keeps its one sender the same way `HistoryChanged` does: the observers call `GainFeed:Begin` and `GainFeed:Send` (or the `SendChat` / `SendEvent` helpers over it), just as `NS.Filters` calls `Database:FireHistoryChanged`, and `tests/test_gain_feed.lua` scans `modules/` for any other `SendMessage(NS.MSG.GAIN`. `HoldingsChanged` keeps its one sender, the Reconciler, even for "Forget this character": `Holdings:ForgetHolder` and `Rollup:ForgetHolder` do the dropping, and `Reconciler:ForgetHolder` announces it.

**The daily rollup is not a bus receiver.** `modules/Rollup.lua` takes its closes from `NS.Holdings`' write methods and its gained/lost tallies from `NS.Database:OnWrite`, a synchronous hook, so it holds no message registration and no event, and the disabled-state survey has nothing of it to find (see [data-flow.md](data-flow.md#daily-rollup)).

## Declared once, as `NS.MSG`

Each name is declared **once**, in [`core/Constants.lua`](../core/Constants.lua) (this addon has no `core/Bus.lua`), and every `SendMessage` / `RegisterMessage` in the addon names the constant — `NS.MSG.RECORD_ADDED`, `NS.MSG.HISTORY_CHANGED`, `NS.MSG.SETTINGS_CHANGED`, `NS.MSG.HOLDINGS_CHANGED`, `NS.MSG.GAIN`, `NS.MSG.FARM_CHANGED` — never the literal (`architecture-§4`). The table is passed through **`LibKa0s-Bus-1.0`'s `Catalog`**, which checks the names at load and answers a strict copy: reading an undeclared key raises, so a mistyped constant fails at the call site for a sender as well as a receiver. Only `Catalog` is used. The receivers stay untracked on `NS.NewBusTarget()` (below), so the major's stand-down record (`New`) is not adopted. With the library absent, `core/Constants.lua` falls back to a stub `Catalog` that returns the plain table: the names are the same and only the strictness is lost. `tests/test_constants.lua` pins each wire string by driving its real sender, and it scans every TOC file for a stray literal.

## `Ka0s_LootHistory_RecordAdded` payload

Fired once per persisted loot event, immediately after the record is appended to the account-wide array in [`Database:Add`](../core/Database.lua), **and again by `Database:Amend`** when the Reconciler grows a same-key row inside the 60 s coalescing window (timeline-ledger spec §5.5). An amend resends the same `(record, index)` with the record's quantity already raised. **Receivers repaint, never count** (spec S2): a handler that incremented a total per message would count a coalesced row once per amend. Browser, Analytics and the Panel are all coalesced repaints, so this holds; anything that must account for each quantity change registers `Database:OnWrite` instead, which sees every `Add` and `Amend` once with its delta. The payload is `(record, index)`: the full record table (see [schema.md](schema.md)) and its 1-based position in `NS.db.global.history`. Consumers treat it as an incremental "one row added" signal — the Browser refreshes the History table, Analytics recomputes live, and the Settings panel updates its live storage stats. None of the current subscribers actually read the `index`; it is carried for cheap append-in-place refreshes without a full re-query.

Note the write path fires against the *real* history only. Browser test mode swaps a synthetic dataset in at the read seam (`Database:ActiveHistory`, `core/Database.lua`), but `Add`/prune never see that override, so `RecordAdded` is never emitted for test data.

## `Ka0s_LootHistory_HistoryChanged` payload

The bulk-mutation counterpart to `RecordAdded`: no payload, meaning "the history array changed structurally — re-query from scratch." Every emission is `Database`'s, so it stays the single sending module — four of the five through the private `fireHistoryChanged` helper, and the deferred bound repair directly, because it is defined above that helper in `core/Database.lua`:

- `Database:Delete(pred)` — predicate delete.
- `Database:Purge()` — the `/lh purge` wipe.
- `Database:PruneOld()` — retention rebuild-and-swap, sent only when it removed at least one row (a prune with nothing to drop fires nothing, so the login prune over a fresh history causes no repaint) (also invoked when the player accepts the `retentionDays` row's prune confirm, so a retention change surfaces as `HistoryChanged`, not `SettingsChanged`). Never from a profile event: the retention is account-wide (owner decision D6), so the adopt path has nothing to prune.
- `Database:RepairBoundStates()` — the deferred warbound-state split, which fires **only when a pass actually fixed rows** (`fixed > 0`). It sends directly rather than through `fireHistoryChanged`, because the repair is defined above that helper; the window can already be open when a pass lands and renders the Bound column off those rows, so it repaints rather than leaving stale locks until the next open.
- `Database:FireHistoryChanged()` — the public wrapper `NS.Filters` calls after a **blacklist/whitelist** edit. Filtering is point-in-time, so a list edit never changes what a query returns for already-stored rows; the message exists so the Settings ▸ General ▸ Filters tab's live id list re-renders. Emitting through this wrapper keeps `Database` the one sender (the Filters module never sends on the bus itself).

Because deletion and retention rebuild-and-swap (no holes; see [schema.md](schema.md)), indices are not stable across a `HistoryChanged`, which is why the payload is empty — subscribers must re-read, not patch by index.

> The blacklist/whitelist edit also re-caches the Collector's list upvalues via a **direct** `NS.Collector:RefreshUpvalues()` call (not a `SettingsChanged` message) — the lists aren't schema settings and the Collector is their only capture-side consumer, so no second `SettingsChanged` sender is introduced.

## `Ka0s_LootHistory_HoldingsChanged` payload

Fired by `Reconciler:Flush` after a scan changed a holder's stored holdings: one send **per changed holder**, never one per scanned part, so a vendor sale that touches bags, gold and a currency in the same debounce window announces its holder once. The payload is the `holder` key — the character's `NS.Util.PlayerKey()`, or the literal `"§warband"` for the virtual Warband holder. A flush that changed nothing sends nothing, and a flush that cannot run (in combat, or a bank part with no banker open) defers rather than sending.

Four receivers, each on its own private target:

- **HoldingsTab** (`HT.__ev`, `modules/HoldingsTab.lua`) repaints only while its pane is shown and otherwise lets the next tab selection refresh it.
- **Timeline** (`TL.__ev`, `modules/Timeline.lua`) runs the same coalesced repaint as for `RecordAdded`, only while its pane is visible.
- **HoldingsTally** (`T.__ev`, `modules/HoldingsTally.lua`, #34) wipes its per-thing cache, whatever the holder, so the next tooltip or API read rebuilds from the store.
- **HoldingsAPI** (`A.__ev`, `modules/HoldingsAPI.lua`, #34) re-fires the holder as `HoldingsChanged` through its own CallbackHandler registry, for other addons (`LootHistory.API.v1`, [ARCHITECTURE.md](ARCHITECTURE.md#public-api-v1)). That registry is not the bus, so the API is one more receiver and never a second sender. It relays nothing while a simulation is active, because a simulation's flushes concern its session store, which the API never reads.

The payload is a hint, not a patch: a receiver re-reads `NS.Holdings`.

## `Ka0s_LootHistory_Gain` payload

Fired once per gain the addon observes (#38 D6), **before** the capture filters and the minimum quality: an item, money or currency loot line whether or not it wrote a row, a reputation change, an appearance collected (Retail), experience and a profession skill-up, and a gain the holdings diff found with no chat line. Toasts, which are not records, are one receiver; the farm session (#39, `modules/Farm.lua`) is the second, registered only while a session is open, and it enters `wants` through `GainFeed:SetFarm(C.FARM.GAIN_KINDS)`.

The payload is **one scratch table**, reused for every send: `GainFeed:Begin(kind)` sets every field in `GainFeed.FIELDS` to nil (a loop, no allocation), then `kind`, `dir = "IN"` and `sim` (`NS.Sim:IsActive()`). It is valid only during the synchronous send, so a receiver copies what it keeps (`ToastModel.NewPayload`). The fields:

- `kind`: `ITEM`, `GOLD`, `CURRENCY`, `REPUTATION`, `APPEARANCE`, `XP` or `SKILL` (`C.GainKind`; the first five equal the `C.Kind` strings, and `XP` and `SKILL` are never record kinds). `dir` is `"OUT"` only for a reputation loss.
- `id` (item, currency, faction, appearance source or skill line; none for money or experience), `qty` (always positive: the count, copper, the reputation amount, the experience or the ranks risen), `link`, `name`, `quality`, `icon`, `classID`.
- `source`, `sourceDetail`, `confidence`, as attribution answered them; `origin` is `"chat"`, `"diff"` or `"event"`.
- `recorded` (the capture path wrote a History row for it), `record` (that row), `gated` (the drop reason when it did not: `quality`, `blacklist`, `recordCurrency-off`, ...).
- Per kind: `label`, `rank`, `standing`, `threshold`, `repType`, `accountWide` (reputation); `itemID`, `newLook` (appearance); `level`, `levelUp`, `cur`, `max` (experience); `old`, `new`, `max` (skill-up).

**The observers never send.** Each tap is `if GainFeed.on and GainFeed.wants.K then ... end` over a load-time upvalue of `NS.GainFeed`, so while no enabled feed takes a kind its tap costs one field test (events-frames-taint-§7). A chat gain that wrote no row posts a **feed claim** through `GainFeed:SendChat` while the ledger is on, and the holdings diff's `GainFeed:FromDiff` consumes it, so the same gain does not reach the feeds twice ([data-flow.md](data-flow.md#the-gain-feeds-taps-38)).

## `Ka0s_LootHistory_SettingsChanged` payload

Sent from nineteen schema-row `onChange` handlers in [`settings/Schema.lua`](../settings/Schema.lua) (eighteen on WoW Forever, where the registry drops the Record appearances row), carrying twelve distinct `reason` strings between them:

- `"enabled"` (`settings.enabled`, through `S.OnEnabledWritten`);
- `"quality"` (`settings.qualityThreshold`), `"questfilter"` (`settings.excludeQuestItems`), `"ammofilter"` (`settings.excludeAmmo`), `"currency"` (`settings.recordCurrency`), `"reputation"` (`settings.recordReputation`), `"appearance"` (`settings.recordAppearances`, Retail only) and `"excludes"` (`settings.excludedSources`);
- `"ledger"` (`settings.trackLedger` and `settings.recordGold`);
- `"view"` (`settings.showTransfers`);
- `"chrome"` (`settings.scale`, `settings.alpha` and `settings.locked`, so the Browser re-applies the addon-wide chrome to both of its frames);
- `"tooltip"` (the five `settings.tooltip.*` rows, #34).

Every row on the **Toasts** page (`settings/SchemaToasts.lua`, #38) sends a thirteenth, `"toasts"`, whichever feed or setting it is.

A fourteenth, `"profile"`, comes from the same module but not from a row: `S:AdoptProfile`, which the profile adopt path (`NS.OnProfileEvent`, `core/LootHistory.lua`) runs once per profile switch, copy or reset, because every setting may have changed at once. Keeping it in `settings/Schema.lua` keeps the message at one sending module. The reason lets a subscriber branch; the Collector and the Browser re-read everything on any reason, the Reputation and Appearance owners re-read their upvalues on any reason and toggle their rows only on theirs, and the other six consumers act only on theirs:

- **Collector** (`modules/Collector.lua`) calls `RefreshUpvalues()`, re-caching `qualityThreshold` / `excludeQuestItems` / `recordCurrency` / `excludedSources` (and the id lists) off the settings table so the `CHAT_MSG_LOOT` and `CHAT_MSG_CURRENCY` hot paths never touch the DB.
- **Browser** (`modules/Browser.lua`) calls `OnSettingsChanged()` to reflect the change in the open window. On a profile event the adopt path has already called `B:AdoptProfile` directly, for what the window reads from the profile outside the chrome (geometry, saved view, row height).
- **Reconciler** (`modules/Reconciler.lua`, its `_settings` target) re-registers or drops its capture events on `"ledger"` and `"profile"`.
- **Reputation** and **Appearance** (`modules/Reputation.lua`, `modules/Appearance.lua`, each on its own `_settings` target) re-read `trackLedger` and `excludedSources` on every reason, and on their own reason (`"reputation"` / `"appearance"`) or `"profile"` register or unregister their capture rows to match the switch. The reputation and appearance capture adds **no new message**: its rows reach the browser through the existing `RecordAdded`.
- **HoldingsTally** (`modules/HoldingsTally.lua`) wipes its cache on `"ledger"` and `"profile"`.
- **HoldingsTip** (`modules/HoldingsTip.lua`) re-reads the five tooltip rows and `trackLedger` into its hot-path cache on `"tooltip"`, `"ledger"` and `"profile"`, which also invalidates every replay memo.
- **HoldingsAPI** (`modules/HoldingsAPI.lua`) re-checks its availability on `"ledger"` and `"profile"` and, when it flipped, fires `HoldingsChanged` with a nil holder.
- **GainFeed** (`modules/GainFeed.lua`, #38, its `__ev` target) runs `Recompute` on `"toasts"`, `"profile"` and `"enabled"`: which kinds an enabled feed takes, then each observer's `SyncCapture` (Reputation, Appearance and Progress register or drop their rows) and `ToastBlizz.Apply`.
- **Toasts** (`modules/ToastFeed.lua`, #38, its `__ev` target) runs `RefreshConfig` on the same three: the config snapshot is dropped, each feed's `Refresh()` re-reads its layout, motion and style getters, and the combat rows follow the enabled set.

### What does NOT broadcast

Two schema rows deliberately skip the bus and drive their side effect directly in `onChange`:

- `settings.windowScale` → `NS.Browser:SetScale(v)`.
- `settings.rowHeight` → `NS.BrowserTable:Bind()`.

`minimap.shown` is off the bus too, and for a stronger reason: it has no `onChange` at all. It is the one **stored** row that carries its own `set` (`settings/Schema.lua`), because the row says SHOWN while its one stored key, LibDBIcon's `minimap.hide`, says HIDDEN (no `shown` key is ever stored), and that `set` both records the inversion and calls `NS.Launcher:SetShown` (launcher-§3).

None of the three emits `SettingsChanged`, because nothing else needs to react — they are one-consumer, view-only knobs. (Likewise `retentionDays` fires `HistoryChanged` via `PruneOld`, not `SettingsChanged`.) Keeping these off the bus means flipping the minimap button or the window scale never cascades into a Collector upvalue refresh or a table rebuild.

## The private-bus-target invariant

**Every consumer must register on its OWN `NS.NewBusTarget()` — never on the shared `NS.bus` / `NS.addon` as `self`.** This is the single hardest rule on the bus and it is load-bearing.

`NS.NewBusTarget()` (`core/LootHistory.lua`) returns a fresh, AceEvent-embedded table. `NS.bus:SendMessage(...)` still fans out to every embedded target, so a private target receives broadcasts exactly like the shared object would — but it owns its own callback slots.

The reason: **CallbackHandler keys registered callbacks by `(message, target)`.** If two modules both did `NS.bus:RegisterMessage("Ka0s_LootHistory_HistoryChanged", handler)`, they would share the single target `NS.bus`, so the second registration would overwrite the first under the same `(message, target)` key — and only the last registrant would ever be called. The bug is silent: no error, the message still fires, but one module's handler simply never runs.

Because multiple consumers subscribe to the same messages — `HistoryChanged` has four listeners (Browser, Analytics, the Panel's History-stats section, and the Panel's Filters tab) and `RecordAdded` three — sharing `NS.bus` as the target would clobber all but the last. Each consumer therefore stores its own target and registers on it (the Panel uses two: `P.__ev` for the History stats and `P.__evFilters` for the Filters tab's live list rebuild):

- Collector — `self.__ev = NS.NewBusTarget()` (`modules/Collector.lua`, `Collector:Enable`).
- Browser — `B.__ev = NS.NewBusTarget()` (`modules/Browser.lua`, `B:Enable`).
- Analytics — `self.__ev = NS.NewBusTarget()` (`modules/Analytics.lua`, `Analytics:Enable`).
- Reconciler — **two** targets: `self._settings` hears `SettingsChanged("ledger" | "profile")` for as long as the addon is up, so ticking `trackLedger` back on can re-register; `self.__ev` carries the capture events and exists only while the setting is on (`modules/Reconciler.lua`).

The capture **game events** are not on this list: they are rows of `NS.EVENT_ROWS` (`core/Dispatch.lua`), registered through `NS.RegisterRows` on the bus (Attribution, Collector, Reputation, Appearance, Progress), on `Attribution.__outEv` (AttributionOut), on the Reconciler's `__ev` and on `Toasts.__rows`; see [ARCHITECTURE.md](ARCHITECTURE.md#event-subscriptions). Messages never go through the row table.
- HoldingsTab — `self.__ev = NS.NewBusTarget()`, for `HoldingsChanged` (`modules/HoldingsTab.lua`).
- Timeline — `self.__ev = NS.NewBusTarget()`, for `HoldingsChanged` and `RecordAdded` (`modules/Timeline.lua`).
- HoldingsTally, HoldingsTip and HoldingsAPI — one `self.__ev = NS.NewBusTarget()` each, in their `Enable` (`modules/HoldingsTally.lua`, `modules/HoldingsTip.lua`, `modules/HoldingsAPI.lua`, #34).
- GainFeed — `self.__ev = NS.NewBusTarget()`, for `SettingsChanged` (`modules/GainFeed.lua`, `GainFeed:Enable`, #38).
- Toasts — **two** message targets: `self.__gain` for `Gain` and `self.__ev` for `SettingsChanged` (`modules/ToastFeed.lua`, `Toasts:Enable`, #38). A third, `self.__rows`, carries only its two combat event rows, kept off the AceAddon target because Progress holds `PLAYER_REGEN_ENABLED` there.
- Panel — `local ev = NS.NewBusTarget()`, **twice**: the History tab's storage readout (`settings/Panel.lua`, `renderHistory`) and the Filters tab's id-lists (`settings/Panel.lua`, `buildFiltersTab`), each on its own target.

Only the *senders* use `NS.bus` directly (`NS.bus:SendMessage(...)`); every *receiver* goes through its private target.

## Adding or removing a message

Adding a message means updating:

1. The single source emitter (one sender per message — the table above is sender-authoritative).
2. Every consumer that reacts to it — each on its **own** `NS.NewBusTarget()`, never the shared bus.
3. The table above (sender, payload, listeners).
4. The relevant module header comment.
5. The closed-bus rule in [common-tasks.md](common-tasks.md) if the new message carries cross-module rules.
