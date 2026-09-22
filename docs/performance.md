# Performance

**This addon brackets nothing, and that is a recorded, conditional decision** — the
`performance-§12` no-combat-path exemption, ratified in
[ARCHITECTURE.md § Documented deviations](ARCHITECTURE.md#documented-deviations) and reasoned at
length in closed issue [**LIBKA0S-17**](https://github.com/tusharsaxena/LootHistory/issues/22).
The `LibKa0s-Perf-1.0` adoption chain the 2026-08-04 and 2026-08-05 audits filed (`LH-20`…`LH-26`)
is this exemption, claimed, and not open work.

There is therefore no `core/PerfSetup.lua`, no `LootHistoryPerfDB`, no `/lh perf` verb, no
`tests/perf.lua` and no `docs/perf-analysis/` store.

**The teardown machinery exists anyway, and it is the DISABLE path's.** `slash-commands-§7` builds
the stand-down on the same seam performance-§6's suspend would have used, and this addon has that
seam: `core/LifecycleSetup.lua`'s `NS.StandDown` / `NS.StandUp`, behind one `LibKa0s-Lifecycle-1.0`
latch. The latch takes named **holds**, and `NS.HOLD_PERF` is published and honored although nothing
here takes it — so if this exemption is ever re-examined, arming the harness is a registration
rather than a second teardown path written beside the first. A parallel lifecycle mechanism is the
anti-pattern (`anti-patterns #85`), and declining the harness is not a license to grow one.
`tests/test_disabled.lua` drives both holds through the latch, so the invariant that matters —
releasing one hold must not resurrect an addon the other is still holding down — is under test here
today. See [ARCHITECTURE.md → *The disabled state*](ARCHITECTURE.md#the-disabled-state). `libs/LibKa0s/` is
still vendored **whole** — `Perf.lua` and `PerfPanel.lua` included — because the folder is copied
whole or not at all (library-stack-§7, anti-pattern #48), and `perf` stays a reserved verb
(slash-commands-§2): it is simply never registered, so it can never come to mean anything else here.

## Why: criterion (a), and criterion (c)

**(a) — no combat path.** The addon owns **no `OnUpdate` handler and no repeating ticker**, and no
event handler doing more than occasional work while the player is in combat. The second half of that
is affirmed here explicitly rather than left to be read off a table, because it is the one place
criterion (a) could plausibly fail: `CHAT_MSG_LOOT` fires mid-fight, and on a line it keeps it does
a `C_TooltipInfo` tooltip build (`Compat.ScanBound`) and a `pcall` into every installed pricing
addon. It does not fail, and the reason is in the code rather than in the adjective —
`Collector:ShouldRecord` (`modules/Collector.lua:116`) runs **before** any of that work and returns
at `:125`, so every line the filters drop, which on the shipped rare-and-above default is nearly all
chat loot traffic, costs a pattern match and a threshold comparison. What reaches the tooltip build
is a few kept items per boss kill, not a few per frame. The whole-repo sweep below is the rest of
the evidence; the claim without it is an assertion.

**(c) — `suspend` would suppress the data the addon exists to record.** The capture protocol opens
its windows on the player's combat state (performance-§7) and `suspend` (performance-§6) must make
the host inert for the whole of window B. For this addon that means **not recording the loot that
drops during that fight** — running one experiment would silently cost the user real history. A
diagnostic that damages the thing it measures is worse than no diagnostic.

**Criterion (b) is deliberately not claimed.** It used to be, in a parenthesis calling the
per-event work "one line" — which the `CHAT_MSG_LOOT` row below shows it is not. Whether two arms
of a measurement would separate on that path is an empirical question, and the addon has no harness
with which to answer it; asserting it anyway is exactly the unmeasured claim this page exists to
prevent. (a) and (c) carry the exemption without it.

## The sweep — `RegisterEvent` / `SetScript("OnUpdate"` / `C_Timer`

Whole-repo, excluding `libs/`, `tests/_kit/` and `tests/`. Regenerate with:

```sh
grep -rn "RegisterEvent\|RegisterUnitEvent" core modules settings defaults locales
grep -rn 'SetScript("OnUpdate"' core modules settings defaults locales
grep -rn "C_Timer\|NewTicker" core modules settings defaults locales
```

**`OnUpdate` handlers: none. Repeating tickers: none.** The second grep returns zero lines, and
`NewTicker` appears nowhere in the third's output.

**Game events: thirteen registrations, thirteen rows.** The first grep returns **sixteen** lines;
three of them are not registrations: `core/LifecycleSetup.lua:111` is the guard above the call, and `modules/Attribution.lua:361-362` are the pattern names inside a comment. The rows are
in the order the grep prints them, so the two can be held side by side.

| Event | Registered at | Work done per fire |
|---|---|---|
| `PLAYER_ENTERING_WORLD` | `core/LifecycleSetup.lua:112` | Handled by `addon:OnEnterWorld` (`core/LootHistory.lua:73`). Once per session — latches `NS.State.cleanupDone`, then returns. Schedules the two one-shot timers below. |
| `CHAT_MSG_LOOT` | `modules/Collector.lua:218` | **The only in-combat handler that does real work, and it does it only past the filters.** Every line: parse, then `ShouldRecord` (`:116`) against threshold, source, class, blacklist and whitelist — a dropped line returns at `:125` having allocated nothing. A **kept** line then runs `NS.Compat.GetItemExtras` (`:128`), which is `C_Item.GetItemInfoInstant` + `C_Item.GetItemInfo` and then `Compat.ScanBound` — a real `C_TooltipInfo.GetHyperlink` build walked line by line — followed by `NS.AuctionPrice:GatherAll` (`:129`), one `pcall`ed fetch per installed provider across the Auctionator / TSM / Oribos cascade (all seven default capture keys are on). That is meaningfully more than a table insert, which is why it is written out here. It is bounded by the gate above it and by loot itself: a few kept items per kill. |
| `CHAT_MSG_CURRENCY` | `modules/Collector.lua:219` | Currency lines, and **not** the same shape as the row above: no tooltip build and no price cascade. Link parse, blacklist check, three `Compat.Currency*` lookups, one record insert. |
| `LOOT_OPENED` | `modules/Attribution.lua:349` | Stamps the single-slot loot context (one table write). Not combat-gated, but a loot window is not a hot path. |
| `ENCOUNTER_START` | `modules/Attribution.lua:350` | Two field writes, once per encounter. |
| `ENCOUNTER_END` | `modules/Attribution.lua:351` | Clears them, once per encounter. |
| `CHALLENGE_MODE_START` | `modules/Attribution.lua:352` | Two field writes, once per key. |
| `CHALLENGE_MODE_COMPLETED` | `modules/Attribution.lua:353` | Clears them, once per key. |
| `TRADE_ACCEPT_UPDATE` | `modules/Attribution.lua:354` | Out of combat by construction. |
| `QUEST_TURNED_IN` | `modules/Attribution.lua:355` | One context stamp. |
| `UNIT_SPELLCAST_SUCCEEDED` | `modules/Attribution.lua:369` | **Unit-filtered to `player`** through its own `RegisterUnitEvent` frame, precisely so the raid-wide firehose a bare registration would deliver never arrives. One spell-id lookup against the deconstruct table. |
| `PLAYER_REGEN_DISABLED` | `modules/Browser.lua:1246` | **On the combat edge, once a fight, never inside one.** `B:ApplyVisibility` (`:1142`): if the window is not shown it returns immediately; otherwise one `settings.visibility` read, at most one `InCombatLockdown()` call, and at most one `Hide`. It only ever hides — a window the setting starts allowing again is still the player's to open. |
| `PLAYER_REGEN_ENABLED` | `modules/Browser.lua:1252` | The other edge of the same handler, same cost. |

**`C_Timer` calls: five, every one of them one-shot. No `C_Timer.NewTicker` anywhere.** Grep the
three patterns and most of what comes back is prose and guards; the call sites are the table below.
`core/ItemSetup.lua:70` and `settings/OptionsSetup.lua:206` carry the guard and the call on one
line, which is why counting call sites by eye off the grep undercounts.

**Three of the five now go through `NS.After`, and that is the change v1.41.0 made here.**
`C_Timer.After` cannot be canceled, and `slash-commands-§7` asks for every timer **canceled**
rather than left armed to wake up and find a flag. `core/LifecycleSetup.lua`'s `NS.After` takes a
`C_Timer.NewTimer` handle where the client has one, tracks it in a live set, and `NS.CancelDeferrals`
drops the lot on the way down. The retention prune is why: it is a SavedVariables write on a
five-second fuse lit by `PLAYER_ENTERING_WORLD`, and before this a player who switched the addon off
inside those five seconds got the write anyway, from a game event, while it was disabled.

| Call | Where | What it is |
|---|---|---|
| `NS.After(5, …)` | `core/LootHistory.lua:81` | Login-deferred retention prune + the first warbound repair pass. Once per session, and **cancelable**. |
| `NS.After(20, …)` | `core/LootHistory.lua:85` | The second warbound repair pass, once the item cache is warm. Once per session, and cancelable. |
| `C_Timer.After(0.4, cb)` | `core/ItemSetup.lua:70` | `NS.Item.LoadItem`'s item-cache retry, in the degraded-install fallback; the live path is the same line in the library (`libs/LibKa0s/Item.lua:124`) — **one-shot, and only when the caller passes a callback.** Two callers: `core/Database.lua:214`, the warbound repair pass, passes none, so it requests the item and arms **no timer at all**; the Filters tab's LibKa0s `IdList` passes one per **batch**, not per id (LibKa0s v1.35.0): every uncached id one render asks for shares a single check, which repaints the list once if any name has landed and re-asks the rest, up to five asks per id — an options panel the player opened by hand. |
| `NS.After(delay, …)` | `core/Util.lua:256` | `Util.Coalesce`'s window, `RECORD_ADDED_COALESCE` = 0.2 s. **Not a ticker and it cannot become one:** each closure holds a `pending` flag that swallows every trigger until the timer fires, so a burst of *n* `RecordAdded` messages arms exactly one. Three independent closures exist — `modules/Browser.lua`, `modules/Analytics.lua` and `settings/Panel.lua`, one per subscribing surface — so the ceiling is three pending timers at once. Through `NS.After` since v1.41.0: a repaint already in flight when the player switches the addon off is canceled rather than waking to find nothing to paint, which is the shape `slash-commands-§7` singles out as the most expensive one. |
| `C_Timer.After(delay, fn)` | `settings/OptionsSetup.lua:206` | The library's color-picker drag throttle, handed in through the descriptor. No schema row is a color today, so nothing reaches it. |

The last two rows stay on raw `C_Timer.After` on purpose: neither is a deferral of the addon's own. One is the item-cache retry inside a **degraded-install fallback** for a library function, and the other is a throttle the **library** arms from a settings widget the player is dragging. Routing either through `NS.CancelDeferrals` would mean a stand-down reaching into somebody else's work.

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
per `RECORD_ADDED_COALESCE` window, wired at `modules/Browser.lua:1241`,
`modules/Analytics.lua:667` and — for the History tab's storage readout, which walks the whole
history to estimate bytes — `settings/Panel.lua:170`. `HistoryChanged` stays immediate, because a
delete or a prune is one deliberate action. Issue #27.

The bus is therefore **in** the sweep's scope from now on, and the entry above is what it found.

## What ends the exemption

**The first `OnUpdate` handler, repeating ticker, or in-combat event handler doing real work
re-arms the full wiring MUST** (performance-§1 and everything under it). That is the re-check
trigger recorded in the register, and it is stated in those words because the change that ends the
exemption is exactly the change nobody will re-read this page during.

Until then, the release notes carry `perf: skip` naming this exemption (automated-tests-§3) — the
skip is said out loud rather than left to read as measured, because a suite that did not run is
never a pass.

## The one allocation that is measured: the Insights widget pools

`modules/Analytics.lua` draws every bar, stacked bar, swatch, strip segment and list row out of a
pool, and `Analytics:LayoutCharts` releases all 35 of them at the top of every layout pass. That
only costs nothing if released widgets come back. Until 2026-08-24 `releaseAll` hid each active
object and dropped it, so `pool.free` was empty on every `acquire` and `factory()` ran each time —
a fresh frame per chart element on every re-render, and frames are never destroyed in WoW, so a
session's worth of filter changes and tab switches accumulated hidden frames for good.

The fix is one loop, but the guarantee is the test: `tests/test_analytics.lua` counts `factory`
calls across two layout passes and requires the second to build nothing. Reading `pool.free` would
pass against a pool nobody reuses, and reading the source would pass against a `LayoutCharts` that
released some other way — so a second case pins that the render path releases through the single
shared helper. Both go through `Analytics._acquire` / `Analytics._releaseAll`, published for the
headless suite.

## The allocation that is not measured, and stays that way

The other half of that story, written down because a silent skip reads exactly like an oversight.

`wantedByProvider` (`modules/AuctionPrice.lua:61`) regroups the capture set into
`{ provider = { key = true } }` on every call, and `GatherAll` calls it at `:76` — once per **kept**
loot line, the `CHAT_MSG_LOOT` row above. It allocates one `out` table plus one sub-map per
provider named in the set: on the shipped default (`core/Constants.lua:148-152`, seven keys across
Auctionator, TSM and Oribos) that is exactly **four small tables per kept line**, from a set that
changes only when the player edits the Price sources table in settings. The obvious repair is to
memoize it and refresh on a settings change.

It is not being taken, and the reason is the exemption above rather than an argument about size.
**There is no `tests/perf.lua` here in which to add a scenario, and by the register's own terms
there is not going to be one** — so the number that would decide this cannot be produced, and
"four tables is cheap" would be the same unmeasured assertion this page exists to refuse. What is
already on that line makes the guess a bad bet in any case: `NS.Compat.GetItemExtras`
(`modules/Collector.lua:128`) walks a `C_TooltipInfo` build line by line, and `GatherAll` then makes
one `pcall`ed call into every installed pricing addon. A memo would also buy real state — an
invalidation path, and a cached table handed out to three third-party fetchers — against a saving
nobody in this repo can size.

So it is left alone deliberately. `LOOTHISTORY-R-10`, 2026-09-08; the collection plan gates it on
"a scenario that measures it, added first — otherwise skip", and that gate cannot open here.

**What re-opens it:** the exemption ending — the trigger written above — which brings a harness with
it, or `wantedByProvider` acquiring a caller that runs more often than once per kept loot line.

## The complexity half

Cost-of-change is measured even though runtime cost is not: `lizard` runs in every automated-test
bundle, and the watch list lives in
[`automated-tests/RESULTS.md`](automated-tests/RESULTS.md). See
[`testing.md`](testing.md) for the four suites and which checkpoint each one gates.
