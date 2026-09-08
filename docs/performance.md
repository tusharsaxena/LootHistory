# Performance

**This addon brackets nothing, and that is a recorded, conditional decision** — the
`performance-§12` no-combat-path exemption, ratified in
[ARCHITECTURE.md § Documented deviations](ARCHITECTURE.md#documented-deviations) and reasoned at
length in closed issue [**LIBKA0S-17**](https://github.com/tusharsaxena/LootHistory/issues/22).

There is therefore no `core/PerfSetup.lua`, no `LootHistoryPerfDB`, no `/lh perf` verb, no
suspend/resume contract, no `tests/perf.lua` and no `docs/perf-analysis/` store. `libs/LibKa0s/` is
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
`Collector:ShouldRecord` (`modules/Collector.lua:111`) runs **before** any of that work and returns
at `:120`, so every line the filters drop, which on the shipped rare-and-above default is nearly all
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

**Game events: thirteen registrations, thirteen rows.** The first grep returns **fifteen** lines;
two of them, `modules/Attribution.lua:347-348`, are the pattern names inside a comment. The rows are
in the order the grep prints them, so the two can be held side by side.

| Event | Registered at | Work done per fire |
|---|---|---|
| `PLAYER_ENTERING_WORLD` | `core/LootHistory.lua:40` | Once per session — latches `NS.State.cleanupDone`, then returns. Schedules the two one-shot timers below. |
| `CHAT_MSG_LOOT` | `modules/Collector.lua:213` | **The only in-combat handler that does real work, and it does it only past the filters.** Every line: parse, then `ShouldRecord` (`:111`) against threshold, source, class, blacklist and whitelist — a dropped line returns at `:120` having allocated nothing. A **kept** line then runs `NS.Compat.GetItemExtras` (`:123`), which is `C_Item.GetItemInfoInstant` + `C_Item.GetItemInfo` and then `Compat.ScanBound` — a real `C_TooltipInfo.GetHyperlink` build walked line by line — followed by `NS.AuctionPrice:GatherAll` (`:124`), one `pcall`ed fetch per installed provider across the Auctionator / TSM / Oribos cascade (all seven default capture keys are on). That is meaningfully more than a table insert, which is why it is written out here. It is bounded by the gate above it and by loot itself: a few kept items per kill. |
| `CHAT_MSG_CURRENCY` | `modules/Collector.lua:214` | Currency lines, and **not** the same shape as the row above: no tooltip build and no price cascade. Link parse, blacklist check, three `Compat.Currency*` lookups, one record insert. |
| `LOOT_OPENED` | `modules/Attribution.lua:339` | Stamps the single-slot loot context (one table write). Not combat-gated, but a loot window is not a hot path. |
| `ENCOUNTER_START` | `modules/Attribution.lua:340` | Two field writes, once per encounter. |
| `ENCOUNTER_END` | `modules/Attribution.lua:341` | Clears them, once per encounter. |
| `CHALLENGE_MODE_START` | `modules/Attribution.lua:342` | Two field writes, once per key. |
| `CHALLENGE_MODE_COMPLETED` | `modules/Attribution.lua:343` | Clears them, once per key. |
| `TRADE_ACCEPT_UPDATE` | `modules/Attribution.lua:344` | Out of combat by construction. |
| `QUEST_TURNED_IN` | `modules/Attribution.lua:345` | One context stamp. |
| `UNIT_SPELLCAST_SUCCEEDED` | `modules/Attribution.lua:350` | **Unit-filtered to `player`** through its own `RegisterUnitEvent` frame, precisely so the raid-wide firehose a bare registration would deliver never arrives. One spell-id lookup against the deconstruct table. |
| `PLAYER_REGEN_DISABLED` | `modules/Browser.lua:1281` | **On the combat edge, once a fight, never inside one.** `B:ApplyVisibility` (`:1141`): if the window is not shown it returns immediately; otherwise one `settings.visibility` read, at most one `InCombatLockdown()` call, and at most one `Hide`. It only ever hides — a window the setting starts allowing again is still the player's to open. |
| `PLAYER_REGEN_ENABLED` | `modules/Browser.lua:1282` | The other edge of the same handler, same cost. |

**`C_Timer` calls: five, every one of them one-shot. No `C_Timer.NewTicker` anywhere.** The third
grep returns **eight** lines: one is the pattern name in a comment (`core/Util.lua:238`), two are
presence guards that call nothing (`core/LootHistory.lua:55`, `core/Util.lua:240`), and five are
call sites. Two of the five — `core/ItemSetup.lua:71` and `settings/OptionsSetup.lua:181` — carry
the guard and its call on one line, which is why counting call sites by eye off this grep
undercounts.

| Call | Where | What it is |
|---|---|---|
| `C_Timer.After(5, …)` | `core/LootHistory.lua:56` | Login-deferred retention prune + the first warbound repair pass. Once per session. |
| `C_Timer.After(20, …)` | `core/LootHistory.lua:60` | The second warbound repair pass, once the item cache is warm. Once per session. |
| `C_Timer.After(0.4, cb)` | `core/ItemSetup.lua:71` | `NS.Item.LoadItem`'s item-cache retry — **one-shot, and only when the caller passes a callback.** Two callers: `core/Database.lua:214`, the warbound repair pass, passes none, so it requests the item and arms **no timer at all**; `settings/Panel.lua:202` passes one, to relabel a filter-list row once the client has cached the name — an options panel the player opened by hand. |
| `C_Timer.After(delay, …)` | `core/Util.lua:242` | `Util.Coalesce`'s window, `RECORD_ADDED_COALESCE` = 0.2 s. **Not a ticker and it cannot become one:** each closure holds a `pending` flag that swallows every trigger until the timer fires, so a burst of *n* `RecordAdded` messages arms exactly one. Three independent closures exist — `modules/Browser.lua:1278`, `modules/Analytics.lua:656`, `settings/Panel.lua:171` — so the ceiling is three pending timers at once, one per surface, and only while that surface is subscribed. |
| `C_Timer.After(delay, fn)` | `settings/OptionsSetup.lua:181` | The library's color-picker drag throttle, handed in through the descriptor. No schema row is a color today, so nothing reaches it. |

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
per `RECORD_ADDED_COALESCE` window, wired at `modules/Browser.lua:1278`,
`modules/Analytics.lua:656` and — for the History tab's storage readout, which walks the whole
history to estimate bytes — `settings/Panel.lua:171`. `HistoryChanged` stays immediate, because a
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
memoise it and refresh on a settings change.

It is not being taken, and the reason is the exemption above rather than an argument about size.
**There is no `tests/perf.lua` here in which to add a scenario, and by the register's own terms
there is not going to be one** — so the number that would decide this cannot be produced, and
"four tables is cheap" would be the same unmeasured assertion this page exists to refuse. What is
already on that line makes the guess a bad bet in any case: `NS.Compat.GetItemExtras`
(`modules/Collector.lua:123`) walks a `C_TooltipInfo` build line by line, and `GatherAll` then makes
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
