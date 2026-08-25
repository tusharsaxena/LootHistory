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

**(a) — no combat path.** The addon owns **no `OnUpdate` handler, no repeating ticker, and no event
handler doing more than occasional work while the player is in combat.** The whole-repo sweep below
is the evidence; the claim without it is an assertion.

**(c) — `suspend` would suppress the data the addon exists to record.** The capture protocol opens
its windows on the player's combat state (performance-§7) and `suspend` (performance-§6) must make
the host inert for the whole of window B. For this addon that means **not recording the loot that
drops during that fight** — running one experiment would silently cost the user real history. A
diagnostic that damages the thing it measures is worse than no diagnostic. (Criterion (b) also
happens to hold — the one line of per-event work is too small and too rare for two arms to differ —
but (c) is the load-bearing half and is the one named here.)

## The sweep — `RegisterEvent` / `SetScript("OnUpdate"` / `C_Timer`

Whole-repo, excluding `libs/`, `tests/_kit/` and `tests/`. Regenerate with:

```sh
grep -rn "RegisterEvent\|RegisterUnitEvent" core modules settings defaults locales
grep -rn 'SetScript("OnUpdate"' core modules settings defaults locales
grep -rn "C_Timer\|NewTicker" core modules settings defaults locales
```

**`OnUpdate` handlers: none. Repeating tickers: none.** Both greps return zero rows.

**Game events: eleven, all of them occasional.**

| Event | Registered at | Work done per fire |
|---|---|---|
| `PLAYER_ENTERING_WORLD` | `core/LootHistory.lua:37` | Once per session — latches `cleanupDone`, then returns. Schedules the two one-shot timers below. |
| `CHAT_MSG_LOOT` | `modules/Collector.lua:213` | One chat line: parse, threshold-check, and on a keeper one table insert. Fires a few times per fight, not a few times per frame. |
| `CHAT_MSG_CURRENCY` | `modules/Collector.lua:214` | Same shape, currency lines. |
| `LOOT_OPENED` | `modules/Attribution.lua:332` | Stamps the single-slot loot context (one table write). Not combat-gated, but a loot window is not a hot path. |
| `ENCOUNTER_START` / `ENCOUNTER_END` | `modules/Attribution.lua:333-334` | Two field writes, twice per encounter. |
| `CHALLENGE_MODE_START` / `CHALLENGE_MODE_COMPLETED` | `modules/Attribution.lua:335-336` | Two field writes, twice per key. |
| `TRADE_ACCEPT_UPDATE` | `modules/Attribution.lua:337` | Out of combat by construction. |
| `QUEST_TURNED_IN` | `modules/Attribution.lua:338` | One context stamp. |
| `UNIT_SPELLCAST_SUCCEEDED` | `modules/Attribution.lua:343` | **Unit-filtered to `player`** through its own `RegisterUnitEvent` frame, precisely so the raid-wide firehose a bare registration would deliver never arrives. One spell-id lookup against the deconstruct table. |

**`C_Timer` calls: four, every one of them one-shot. No `C_Timer.NewTicker` anywhere.**

| Call | Where | What it is |
|---|---|---|
| `C_Timer.After(5, …)` | `core/LootHistory.lua:54` | Login-deferred retention prune + the first warbound repair pass. Once per session. |
| `C_Timer.After(20, …)` | `core/LootHistory.lua:58` | The second warbound repair pass, once the item cache is warm. Once per session. |
| `C_Timer.After(0.4, cb)` | `core/Compat.lua:202` | Item-cache retry after a `RequestLoadItemDataByID`, fired from the filter panel. |
| `C_Timer.After(delay, fn)` | `settings/OptionsSetup.lua:98` | The library's color-picker drag throttle, handed in through the descriptor. No schema row is a color today, so nothing reaches it. |

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
per `RECORD_ADDED_COALESCE` window, wired at `modules/Browser.lua` and `modules/Analytics.lua`.
`HistoryChanged` stays immediate, because a delete or a prune is one deliberate action. Issue #27.

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

## The complexity half

Cost-of-change is measured even though runtime cost is not: `lizard` runs in every automated-test
bundle, and the watch list lives in
[`automated-tests/RESULTS.md`](automated-tests/RESULTS.md). See
[`testing.md`](testing.md) for the four suites and which checkpoint each one gates.
