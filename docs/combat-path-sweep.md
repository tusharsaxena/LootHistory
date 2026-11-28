# The combat-path sweep

> **Retained as the event census. It no longer backs the `performance-§12` exemption (retired
> 2026-10-06, timeline ledger F2).** The addon is now wired into LibKa0s-Perf; the buckets are on
> [performance.md](performance.md). The tables below were written for the exemption and are kept
> as the inventory of what runs per fire. The timeline-ledger registrations are in
> [their own section](#timeline-ledger-registrations-phases-1-and-2). A new handler that can run in
> combat needs a bucket in `core/PerfSetup.lua`.

This page was the committed evidence behind the exemption. The criteria it rested on are in
closed issue [LIBKA0S-17](https://github.com/tusharsaxena/LootHistory/issues/22), and the retirement
is noted under [ARCHITECTURE.md § Documented deviations](ARCHITECTURE.md#documented-deviations).
**Re-run the sweep before trusting this page.**

## Why `CHAT_MSG_LOOT` stays inside criterion (a)

**(a) — no combat path.** The addon owns **no `OnUpdate` handler and no repeating ticker**, and no
event handler doing more than occasional work while the player is in combat. The second half of that
is affirmed here explicitly rather than left to be read off a table, because it is the one place
criterion (a) could plausibly fail: `CHAT_MSG_LOOT` fires mid-fight, and on a line it keeps it does
a `C_TooltipInfo` tooltip build (`Compat.ScanBound`) and a `pcall` into every installed pricing
addon. It does not fail, and the reason is in the code rather than in the adjective —
`Collector:ShouldRecord` (called from `lootLine`, `modules/Collector.lua`) runs **before** any of that work, and `lootLine`
returns on its refusal, so every line the filters drop, which on the shipped rare-and-above default is nearly all
chat loot traffic, costs a pattern match and a threshold comparison. What reaches the tooltip build
is a few kept items per boss kill, not a few per frame. The whole-repo sweep below is the rest of
the evidence; the claim without it is an assertion.

## The sweep — `RegisterEvent` / `SetScript("OnUpdate"` / `C_Timer`

Whole-repo, excluding `libs/`, `tests/_kit/` and `tests/`. Regenerate with:

```sh
grep -rn "RegisterEvent\|RegisterUnitEvent" core modules settings defaults locales
grep -rn 'SetScript("OnUpdate"' core modules settings defaults locales
grep -rn "C_Timer\|NewTicker" core modules settings defaults locales
```

**`OnUpdate` handlers: none. Repeating tickers: none.** The second grep returns zero lines, and
`NewTicker` appears nowhere in the third's output.

**Game events: fifteen registrations, fifteen rows.** The first grep returns **twenty-three** lines,
and since the dispatch table (`core/Dispatch.lua`, LootHistory#37) most capture registrations are
no longer a grep hit of their own: every capture event is a row of `NS.EVENT_ROWS`, declared at file
load in its module, and registered by `NS.RegisterRows` in `core/Dispatch.lua` (one call for the unit row
and one for every other row). The table therefore cites each row's declaration. Of the twenty-three
lines, those two calls and two comment lines are `core/Dispatch.lua`'s; twelve are Core's per-event
helper bodies in `core/CoreSetup.lua` (the degraded stub's `NS.SafeRegisterEvent` family and the live wrappers
of the same names; see [ARCHITECTURE.md § Event subscriptions](ARCHITECTURE.md#event-subscriptions));
`core/LifecycleSetup.lua`'s `registerEnterWorldStep` holds the guard and the call; `modules/Attribution.lua`
carries the pattern names inside a comment; and the last three (two in `modules/Browser.lua`'s `B:Enable` and
one in `settings/Slash.lua`'s `NS.OfferLedgerReset`) are registrations this table and the
[timeline-ledger table](#timeline-ledger-registrations-phases-1-and-2) below cover.

| Event | Registered at | Work done per fire |
|---|---|---|
| `PLAYER_ENTERING_WORLD` | `core/LifecycleSetup.lua`, `registerEnterWorldStep` | Handled by `addon:OnEnterWorld` (`core/LootHistory.lua`). Once per session — latches `NS.State.cleanupDone`, then returns. Schedules the four one-shot timers below. |
| `CHAT_MSG_LOOT` | `modules/Collector.lua` (row) | **The only in-combat handler that does real work, and it does it only past the filters.** Every line: parse, then `ShouldRecord` against threshold, source, class, blacklist and whitelist — a dropped line returns from `lootLine` having allocated nothing: the gate config it hands `ShouldRecord` is one module-level `gateCfg` table, refreshed with the settings and given only the line's `itemID` per call, not a table built per line (`LootHistory-R-16`). A **kept** line then runs `NS.Compat.GetItemExtras`, which is `C_Item.GetItemInfoInstant` + `C_Item.GetItemInfo` and then `Compat.ScanBound` — a real `C_TooltipInfo.GetHyperlink` build walked line by line — followed by `NS.AuctionPrice:GatherAll`, one `pcall`ed fetch per installed provider across the Auctionator / TSM / Oribos cascade (all seven default capture keys are on). That is meaningfully more than a table insert, which is why it is written out here. It is bounded by the gate above it and by loot itself: a few kept items per kill. |
| `CHAT_MSG_CURRENCY` | `modules/Collector.lua` (row) | Currency lines, and **not** the same shape as the row above: no tooltip build and no price cascade. Link parse, the listed-id check (`Compat.ListedCurrencyID`: one `GetCurrencyListSize` read, plus at most one list walk for an id seen for the first time since the list last changed), blacklist check, three `Compat.Currency*` lookups, one record insert. |
| `LOOT_OPENED` | `modules/Attribution.lua` (row) | Stamps the single-slot loot context (one table write). Not combat-gated, but a loot window is not a hot path. |
| `LOOT_CLOSED` | `modules/Attribution.lua` (row) | Shortens the loot window's cover (one field write). Not combat-gated, for the same reason. |
| `ENCOUNTER_START` | `modules/Attribution.lua` (row) | Two field writes, once per encounter. |
| `ENCOUNTER_END` | `modules/Attribution.lua` (row) | One field write (the grace expiry on a kill) or one clear (a wipe), once per encounter. |
| `CHALLENGE_MODE_START` | `modules/Attribution.lua` (row; this row, `CHALLENGE_MODE_COMPLETED`, `ZONE_CHANGED_NEW_AREA` and `CHALLENGE_MODE_RESET` register on Retail only, `C.FEATURE.mythicPlus`) | Two field writes, once per key. |
| `CHALLENGE_MODE_COMPLETED` | `modules/Attribution.lua` (row) | One keystone-level read and at most one field write, once per key. The context is kept for the reward chest. |
| `TRADE_ACCEPT_UPDATE` | `modules/Attribution.lua` (row) | Out of combat by construction. |
| `QUEST_TURNED_IN` | `modules/Attribution.lua` (row) | One context stamp. |
| `ZONE_CHANGED_NEW_AREA` | `modules/Attribution.lua` (row) | One API call per zone change (`IsInInstance`, through `Compat.InPartyInstance`), then either clears the keystone context or, on re-entry to an active key, one `GetActiveKeystoneInfo` read and one small table. Zone changes are rare and never a combat loop. |
| `CHALLENGE_MODE_RESET` | `modules/Attribution.lua` (row) | One field write, once per reset key. |
| `UNIT_SPELLCAST_SUCCEEDED` | `modules/Attribution.lua` (row) | **Unit-filtered to `player`** through its own `RegisterUnitEvent` frame, precisely so the raid-wide firehose a bare registration would deliver never arrives. One spell-id lookup against the deconstruct table. |
| `PLAYER_REGEN_DISABLED` | `modules/Browser.lua`, `B:Enable` | **On the combat edge, once a fight, never inside one.** `B:ApplyVisibility`: if the window is not shown it returns immediately; otherwise one `settings.visibility` read, no combat-state read at all (the handler passes the edge in), and at most one `Hide`. It only ever hides — a window the setting starts allowing again is still the player's to open. |
| `PLAYER_REGEN_ENABLED` | `modules/Browser.lua`, `B:Enable` | The other edge of the same handler, same cost. |

**`C_Timer` calls: nine in the table below (as measured on 2026-11-06; the ledger's debounce and claim timers are in the timeline-ledger section), every one of them one-shot. No `C_Timer.NewTicker` anywhere.** Grep the
three patterns and most of what comes back is prose and guards; the call sites are the table below.
`core/ItemSetup.lua`'s `LoadItem` fallback and `settings/OptionsSetup.lua`'s `scheduleTimer` carry the guard and the call on one
line, which is why counting call sites by eye off the grep undercounts.

**Three of the original five now go through `NS.After`, and that is the change v1.41.0 made here; the timeline ledger's two login timers were added on it.**
`C_Timer.After` cannot be canceled, and `slash-commands-§7` asks for every timer **canceled**
rather than left armed to wake up and find a flag. `core/LifecycleSetup.lua`'s `NS.After` takes a
`C_Timer.NewTimer` handle where the client has one, tracks it in a live set, and `NS.CancelDeferrals`
drops the lot on the way down. The retention prune is why: it is a SavedVariables write on a
five-second fuse lit by `PLAYER_ENTERING_WORLD`, and before this a player who switched the addon off
inside those five seconds got the write anyway, from a game event, while it was disabled.

| Call | Where | What it is |
|---|---|---|
| `NS.After(5, …)` | `core/LootHistory.lua`, `addon:OnEnterWorld` | Login-deferred retention prune + the first warbound repair pass. Once per session, and **cancelable**. |
| `NS.After(20, …)` | `core/LootHistory.lua`, `addon:OnEnterWorld` | The second warbound repair pass, once the item cache is warm, which also sets `NS.State.loginSettled` (the simulator's login refusal). Once per session, and cancelable. |
| `NS.After(3, …)` | `core/LootHistory.lua`, `addon:OnEnterWorld` | The holdings genesis / login scan (`Reconciler:LoginScan`) when the ledger is on. Once per session, and cancelable. |
| `NS.After(5, …)` | `core/LootHistory.lua`, `addon:OnEnterWorld` | The one-time ledger reset recommendation (`NS.OfferLedgerReset`). Once per session, and cancelable. |
| `NS.After(2, …)` | `core/LootHistory.lua`, `addon:OnEnterWorld` | The first-run skin picker / one-time skin notice (`NS.MaybeShowSkinPicker`, which asks `NS.MaybeShowSkinNotice` first). Once per session, and cancelable. |
| `C_Timer.After(0.4, cb)` | `core/ItemSetup.lua`, `LoadItem` | `NS.Item.LoadItem`'s item-cache retry, in the degraded-install fallback; the live path is the same call in the library (`lib.LoadItem` in `libs/LibKa0s/Item.lua`) — **one-shot, and only when the caller passes a callback.** Two callers: `core/Database.lua`'s `examineRow`, the warbound repair pass, passes none, so it requests the item and arms **no timer at all**; the Filters tab's LibKa0s `IdList` passes one per **batch**, not per id (LibKa0s v1.35.0): every uncached id one render asks for shares a single check, which repaints the list once if any name has landed and re-asks the rest, up to five asks per id — an options panel the player opened by hand. |
| `NS.After(delay, …)` | `core/Util.lua`, `Util.Coalesce` | `Util.Coalesce`'s window, `RECORD_ADDED_COALESCE` = 0.2 s. **Not a ticker and it cannot become one:** each closure holds a `pending` flag that swallows every trigger until the timer fires, so a burst of *n* `RecordAdded` messages arms exactly one. Three independent closures exist — `modules/Browser.lua`, `modules/Analytics.lua` and `settings/Panel.lua`, one per subscribing surface — so the ceiling is three pending timers at once. Through `NS.After` since v1.41.0: a repaint already in flight when the player switches the addon off is canceled rather than waking to find nothing to paint, which is the shape `slash-commands-§7` singles out as the most expensive one. |
| `C_Timer.After(delay, fn)` | `settings/OptionsSetup.lua`, `scheduleTimer` | The library's 50 ms slider and color-picker drag throttles, handed in through the descriptor. The return value is unused: the library keeps its own armed flag (OptionsWidgets minor 31: the `armed` local behind `makeSlider`'s live-commit throttle and the color picker's `throttledCommit`, both in `libs/LibKa0s/OptionsWidgets.lua`). No schema row is a color today; the sliders reach it. |
| `C_Timer.After(NOTICE_RETRY, …)` | `core/SkinSetup.lua`, `NS.MaybeShowSkinNotice` | The one-time skin notice's combat retry, `NOTICE_RETRY` = 5 s. **Not a combat path** (owner ruling, 2026-11-06): a one-shot that re-arms one at a time (`noticeWaiting`) and only while the account's notice is pending and the library answered `"combat"`; each tick is one library call (`O.SkinNotice`) that shows and records nothing in combat. |

The `LoadItem` and `scheduleTimer` rows stay on raw `C_Timer.After` on purpose: neither is a deferral of the addon's own. One is the item-cache retry inside a **degraded-install fallback** for a library function, and the other is a throttle the **library** arms from a settings widget the player is dragging. Routing either through `NS.CancelDeferrals` would mean a stand-down reaching into somebody else's work. The skin notice's retry is the addon's own and stays raw for a different reason: it is self-limiting (one armed at a time, gone once the notice is claimed or recorded), and the owner ruled on 2026-11-06 that it is not a combat path, so it does not reopen `performance-§12`.

The message bus (`RegisterMessage`, `modules/Analytics.lua`, `modules/Browser.lua`,
`settings/Panel.lua`) fires from this addon's own writes, which are the events above. It used to be
excluded from the sweep on that reasoning plus "and only when a window is open" — and that
exclusion was wrong, in a way worth recording rather than quietly deleting.

`Database:Add` fires `Ka0s_LootHistory_RecordAdded` once per **looted item**. With the browser open
that reached a full `BrowserTable:Refresh`, seven filter-dropdown builders each scanning the whole
dataset, a `Database:StorageStats` pass with a per-record byte estimate, and — on the Insights tab —
a full `Analytics:Refresh`. Roughly **nine O(history) passes per loot line**, uncoalesced, on a
plain non-secure frame that `docs/ARCHITECTURE.md` says can be open during combat. "Only when a
window is open" described exactly the case that mattered and read as though it dismissed it.

The 2026-08-03 review recorded F-004 as fixed — "the record-added repaint is coalesced" — and it
was not true of the tree. It is now: `NS.Coalesce` (`core/Util.lua`) collapses a burst into one run
per `RECORD_ADDED_COALESCE` window, wired in `modules/Browser.lua`'s `B:Enable`,
`modules/Analytics.lua`'s `Analytics:Enable` and — for the History tab's storage readout, which walks the whole
history to estimate bytes — `settings/Panel.lua`'s `renderHistory`. `HistoryChanged` stays immediate, because a
delete or a prune is one deliberate action. Issue #27.

The bus is therefore **in** the sweep's scope from now on, and the entry above is what it found.

## Timeline-ledger registrations (phases 1 and 2)

Added by the timeline ledger, after the sweep above was taken. All but the last register one by one
through `NS.RegisterRows` (and so `NS.SafeRegisterEvent`) from their `NS.EVENT_ROWS` rows, on the
shared bus or a private bus target, and all go down with the latch.

| Event | Registered at | Work done per fire |
|---|---|---|
| `CHAT_MSG_MONEY` | `modules/Collector.lua` (row) | Fires in combat on looted money. Parse, then one gold row and one claim (an accumulator add on the Reconciler). Bucket `moneyLine`. |
| `BAG_UPDATE` | `modules/Reconciler.lua` (the sixteen `ledger` rows, fourteen on WoW Forever) | **The storm.** One dirty bit per fire, routed to `bags`, `bank` or `tabs` by container id. No scan, no allocation (`tests/perf.lua` scenario 2). Bucket `ledgerEvent`. |
| `BAG_UPDATE_DELAYED` | same | Arms the 0.35 s debounce (one `NS.After`, swallowed while one is pending). |
| `PLAYER_EQUIPMENT_CHANGED`, `PLAYER_MONEY`, `ACCOUNT_MONEY`, `PLAYERBANKSLOTS_CHANGED`, `PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED` | same | One dirty bit and the debounce. |
| `CURRENCY_DISPLAY_UPDATE` | same | One accumulator add per currency id (the signed change and its gain/loss source), one dirty bit, the debounce. |
| `CURRENCY_TRANSFER_LOG_UPDATE` | same | One flag, one dirty bit, the debounce. |
| `MAIL_INBOX_UPDATE`, `OWNED_AUCTIONS_UPDATED` | same | Only while the mailbox / auction house is open: one dirty bit and the debounce. |
| `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` / `_HIDE` | same, and `modules/AttributionOut.lua` (rows) | Not a combat path (an NPC frame). Reconciler: readability flags, and on hide one final flush. AttributionOut: one scope stamp. |
| `PLAYER_REGEN_ENABLED` | `modules/Reconciler.lua` | **Where the deferred work runs.** `R:Flush` returns at once in combat and sets `deferred`; this edge runs the one reconcile (or the deferred login scan). Outside the `ledgerEvent` bucket: `R:OnEvent` dispatches it before the bracket opens (`tests/test_perf.lua`). |
| `MAIL_SEND_SUCCESS`, `MAIL_FAILED` | `modules/AttributionOut.lua` (rows) | Out of combat by construction. A stamp, or one field clear. |
| `TRADE_ACCEPT_UPDATE` | `modules/AttributionOut.lua` (row) | Out of combat by construction. One stamp on a completed trade. |
| `ADDON_LOADED` | `modules/AttributionOut.lua` (row) | Hooks the guild bank frame once when `Blizzard_GuildBankUI` loads; otherwise one string compare. |
| `PLAYER_REGEN_ENABLED` | `settings/Slash.lua` (`NS.OfferLedgerReset`) | Only when the reset offer comes due in combat: a one-shot on a private target that drops itself and re-offers once out of combat. |

## Reputation and appearance registrations

Added by the reputation and appearance capture (`docs/superpowers/specs/2026-11-27-rep-appearance-capture-design.md`),
after the sweeps above. Each is an `NS.EVENT_ROWS` row on the shared bus, registered by
`NS.RegisterRows` only while its capture switch is on, and each goes down with the latch.

| Event | Registered at | Work done per fire |
|---|---|---|
| `FACTION_STANDING_CHANGED` | `modules/Reputation.lua` (row; both clients) | **Fires in combat**, on every kill that moves a standing. One `Compat.FactionSnapshot` (four to six C API reads, answered as values, never a table), the pure `Reputation.Delta` against the in-memory baseline entry (updated in place), and at most one `Database:Add` or `Amend`. Nothing is allocated when the standing did not move: `tests/perf.lua` scenario 6, `repUnchanged`, pins it at zero bytes. Bucket `repEvent`. |
| `TRANSMOG_COLLECTION_SOURCE_ADDED` / `_REMOVED` | `modules/Appearance.lua` (rows; Retail only, `C.FEATURE.appearances`) | Bursts on an ensemble or a Trading Post set, one fire per source. The duplicate guard (two table reads), three or four client reads behind `Compat.AppearanceSource` and, on a gain, `Compat.IsNewLook`, the context `Peek`, and one `Database:Add`. Bucket `appearanceEvent`. |

Two one-shot timers come with the reputation seed, both through `NS.After`, so `NS.CancelDeferrals`
drops them on a stand-down and `Reputation:ResetState` cancels them by handle:

| Call | Where | What it is |
|---|---|---|
| `NS.After(2, …)` | `modules/Reputation.lua`, `Reputation:EnableCapture` | The first seed of the baseline (`Reputation:Seed`, one `Compat.ListFactions` walk), once each time the capture comes up. Cancelable. |
| `NS.After(C.REP_SEED_RETRY, …)` | `modules/Reputation.lua`, `Reputation:Seed` | Only when a seed comes due in combat: the walk expands the Reputation panel's headers, which is UI state, so it re-arms once per 5 s until combat ends, one at a time (the earlier handle is canceled first). **Not a ticker.** Cancelable. |

## Toast feed registrations (#38)

Added by the loot toasts (`docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md`), after the
sweeps above. The event rows are `NS.EVENT_ROWS` rows registered through `NS.RegisterRows` only while
a toast feed wants them, and every one goes down with the latch.

| Event or path | Registered at | Work done per fire |
|---|---|---|
| The GAIN tap in each observer (the three chat lines, the reputation and appearance handlers, the holdings diff) | not a registration: a field test inside a handler already listed | **One upvalue read, one field read and one test** while no enabled feed takes the kind (`if GainFeed.on and GainFeed.wants.K`). With a feed on: `Begin` clears the one reused scratch table (no allocation), the fields are filled and `Send` (bucket `gainSend`) broadcasts it. A gated chat gain with the ledger on posts one feed claim, the only allocation on the path. |
| `Ka0s_LootHistory_Gain` | `modules/ToastFeed.lua` (`Toasts.__gain`, a bus message, not an event) | Inside `gainSend`. Per feed: the filter (`M.Accepts`, table reads), the appearance absorb check, then a payload copy and `Push`. **A merge allocates nothing**: the reducer hands the spare payload back (`tests/test_toast_model.lua`). A new toast takes one payload table from the spare list or makes one; Feed-1.0 has no close callback, so that table is collected rather than pooled. The highlight sound plays at most once per feed per `C.TOAST_SOUND_GAP`. |
| The toast's `content` call | `modules/ToastFeed.lua` (the Feed calls it) | Bucket `toastPaint`. On present, merge, repaint and the settle re-read, never per frame. The price gather and the item-extras read run once per payload and are cached on it. |
| `PLAYER_XP_UPDATE`, `PLAYER_LEVEL_UP` | `modules/Progress.lua` (rows, owner `ProgressXP`) | **Fires in combat** on every kill that grants experience. Bucket `xpEvent`: one `Compat.PlayerXP` (the experience, level and cap reads, answered as values), the pure `XPDelta` over reused tables, at most one send. |
| `SKILL_LINES_CHANGED`, `CHAT_MSG_SKILL` | `modules/Progress.lua` (rows, owner `ProgressSkill`) | Arms one 0.5 s coalescer (`NS.Coalesce`, through `NS.After`). The scan (bucket `skillScan`) fills reused tables; on WoW Forever it waits for combat to end. |
| `PLAYER_REGEN_ENABLED` | `modules/Progress.lua` (row, owner `ProgressRegen`) | Out of combat by construction: the XP reseed after a secret read, the owed Forever scan. |
| `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` | `modules/ToastFeed.lua` (rows on `Toasts.__rows`) | Once per combat edge, three feeds: lock, click-through and hold on the way in; click-through off and release on the way out. |
| The Feed's clock | `LibKa0s-Feed-1.0` (an unparented frame, the library's) | Armed only while a row needs a tick (enter, hold, fade, pulse, countdown bar, smooth moves) and disarmed when every row rests; `Stats().awake` is false on an idle feed and after `Clear()` (`tests/test_toast_feed.lua`). Not a host bracket: its cost is the library's. |

## Hooks and post calls

No `RegisterEvent` grep finds these, because they are not events. Each runs on a client action, and
the ones that can run in combat are bracketed.

| Hook | Installed at | Work done per fire |
|---|---|---|
| `TooltipDataProcessor.AddTooltipPostCall` for the Item and Currency data types | `modules/HoldingsTip.lua`, `HT:InstallHooks` (from `HT:Enable`, once per session per type, through `Compat.HookTooltipType`) | **Runs in combat**, on every item or currency tooltip build: about five a second while one is hovered. Bucket `tooltipBlock`. The guard ladder returns at its first failing rung (stood down, settings off, not writable, a comparison tooltip, no id, already drawn on this show, modifier not held). Past it, every call reads the live counts the memo is keyed on: for an item `Compat.LiveItemCounts` (two `C_Item.GetItemCount` calls, three on Retail, plus, only when something is carried and the item can be worn, one `GetInventoryItemID` per equipment slot and bag slot: ids only, no link built) and the Reconciler's two readable flags, for a currency one `Compat.CurrencyQuantity`. An unchanged refresh then replays the memoized lines: no tally compose, no icon markup, no string building. A rebuild hands those live counts to the tally (no second read), reads its cached entry and builds the lines once. `tests/test_holdings_tip.lua` pins a replay at zero bytes on the real live read; `tests/perf.lua` records `tooltipBlockReplay`. |
| `GameTooltip:HookScript("OnHide")` and `HookScript("OnTooltipCleared")`, per tooltip | `modules/HoldingsTip.lua`, `watch`, the first time the block draws on that tooltip | One weak-table write that clears the never-twice mark. No gate, because it draws and writes nothing. |
| `hooksecurefunc` capture and loss-side hooks | `core/Dispatch.lua`'s `NS.HOOK_ROWS`, `modules/AttributionOut.lua` | Out of combat by construction (vendor, mail, auction house, crafting, the guild bank): one stamp each. |

The reconcile itself (`Reconciler:Flush`: scan, plan, hold or commit) never runs in combat, so it is
not a perf bucket. `tests/perf.lua` scenario 3 bounds it at one container scan per dirty group.

## The allocation that is not measured, and stays that way

The other half of the Insights widget-pool story in [browser.md](browser.md#widget-pools-are-recycled-and-that-is-tested),
written down because a silent skip reads exactly like an oversight.

`wantedByProvider` (`modules/AuctionPrice.lua`) regroups the capture set into
`{ provider = { key = true } }` on every call, and `GatherAll` calls it — once per **kept**
loot line, the `CHAT_MSG_LOOT` row above. It allocates one `out` table plus one sub-map per
provider named in the set: on the shipped default (`C.AUCTION_CAPTURE_DEFAULT` in `core/Constants.lua`, seven keys across
Auctionator, TSM and Oribos) that is exactly **four small tables per kept line**, from a set that
changes only when the player edits the Price sources table in settings. The obvious repair is to
memoize it and refresh on a settings change.

It is not being taken, and the reason is the exemption itself rather than an argument about size.
**There is no `tests/perf.lua` here in which to add a scenario, and by the register's own terms
there is not going to be one** — so the number that would decide this cannot be produced, and
"four tables is cheap" would be the same unmeasured assertion the exemption exists to refuse. What is
already on that line makes the guess a bad bet in any case: `NS.Compat.GetItemExtras`
(called from `lootLine`, `modules/Collector.lua`) walks a `C_TooltipInfo` build line by line, and `GatherAll` then makes
one `pcall`ed call into every installed pricing addon. A memo would also buy real state — an
invalidation path, and a cached table handed out to three third-party fetchers — against a saving
nobody in this repo can size.

So it is left alone deliberately. `LOOTHISTORY-R-10`, 2026-09-08; the collection plan gates it on
"a scenario that measures it, added first — otherwise skip", and that gate cannot open here.

**What re-opens it:** the exemption ending — the trigger on [performance.md](performance.md#what-re-arms-the-wiring) — which brings a harness with
it, or `wantedByProvider` acquiring a caller that runs more often than once per kept loot line.

## What re-arming would reuse

**The teardown machinery exists anyway, and it is the DISABLE path's.** `slash-commands-§7` builds
the stand-down on the same seam performance-§6's suspend would have used, and this addon has that
seam: `core/LifecycleSetup.lua`'s `NS.StandDown` / `NS.StandUp`, behind one `LibKa0s-Lifecycle-1.0`
latch. The latch takes named **holds**, and `NS.HOLD_PERF` is published and honored although nothing
here takes it — so if this exemption is ever re-examined, arming the harness is a registration
rather than a second teardown path written beside the first. A parallel lifecycle mechanism is the
anti-pattern (`anti-patterns #85`), and declining the harness is not a license to grow one.
`tests/test_disabled.lua` drives both holds through the latch, so the invariant that matters —
releasing one hold must not resurrect an addon the other is still holding down — is under test here
today. See [disabled-state.md](disabled-state.md). `libs/LibKa0s/` is
still vendored **whole** — `Perf.lua`, `PerfSampler.lua`, `PerfCommands.lua` and `PerfPanel.lua` included — because the folder is copied
whole or not at all (library-stack-§7, anti-pattern #48), and `perf` stays a reserved verb
(slash-commands-§2): it is simply never registered, so it can never come to mean anything else here.
