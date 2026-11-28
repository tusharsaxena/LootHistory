# Performance

Ka0s Loot History is wired into **`LibKa0s-Perf-1.0`** (performance-§1). The probe, the guided
A/B run, the record schema and the step panel are the library's; `core/PerfSetup.lua` supplies
what only this addon knows: which handlers to measure, and the latch that makes it inert.

The addon held the `performance-§12` no-combat-path exemption until the timeline ledger (spec §13
F2). Holdings diffing put work behind `BAG_UPDATE`, money and currency events, which can fire in
combat. That was the exemption's re-check trigger, and the row is retired (see
[ARCHITECTURE.md § Documented deviations](ARCHITECTURE.md#documented-deviations)).

## The buckets

Twelve, in report order. Each is a handler that runs **in combat**:

| Bucket | Handler | What it covers |
|---|---|---|
| `lootLine` | `Collector:OnChatMsgLoot` | Every loot line in the group: parse, gate, and on a kept line the item extras, the price cascade and the record write |
| `currencyLine` | `Collector:OnChatMsgCurrency` | Currency lines: parse, blacklist, one record write |
| `moneyLine` | `Collector:OnChatMsgMoney` | Looted money and party share: one gold row and its claim |
| `spellCast` | `Attribution:OnSpellSucceeded` | Every player cast: one memoized deconstruct lookup |
| `ledgerEvent` | `Reconciler:OnEvent` | Every capture event (`BAG_UPDATE` storms, money, currency, equipment): a dirty bit and a debounce, nothing else |
| `tooltipBlock` | `HoldingsTip.OnTooltip` | Every item and currency tooltip build (#34), about five a second while one is hovered, in combat too: the guard ladder, then either a replay of the memoized lines (no tally compose, no icon markup) or a rebuild from the tally, and the append. The bracket closes on every call, including one the ladder refuses |
| `repEvent` | `Reputation:OnStandingChanged` | Every `FACTION_STANDING_CHANGED`, which fires on kills in combat: one `Compat.FactionSnapshot` (four to six C API reads, answered as values), the pure delta and at most one `Database:Add` or `Amend`. Nothing is allocated when the standing did not move (`repUnchanged` below) |
| `appearanceEvent` | `Appearance:OnSourceAdded` / `OnSourceRemoved` | Retail only. Every appearance source collected or removed, which bursts on an ensemble: the duplicate guard, three or four client reads behind `Compat.AppearanceSource` and, on a gain, `Compat.IsNewLook`, the context `Peek` and one `Database:Add` |
| `gainSend` | `GainFeed:Send` | Every gain sent to the toast feeds (#38): the bus fan-out with every receiver's work inside it, so each feed's filter, payload copy and `Push`. Nothing is sent, and nothing bracketed, while no enabled feed takes the kind: each observer's tap is one field test |
| `toastPaint` | the toast feeds' `content` closure around `ToastContent.Content` (`modules/ToastFeed.lua`) | A toast row's content: the first line, counts, cap, price and upgrade lines. The Feed calls it when a row presents, merges, repaints or settles, never per frame; the lazy price gather and item-extras read sit inside, once per payload |
| `xpEvent` | `Progress:OnXP` | Every experience event while a feed takes experience (kills and quests, so in combat): one `Compat.PlayerXP`, the pure delta, at most one send |
| `skillScan` | Progress's coalesced scan | The profession read after `SKILL_LINES_CHANGED` or `CHAT_MSG_SKILL`, 0.5 s after the burst: `GetProfessionInfo` per profession on Retail; on WoW Forever the walk waits for combat to end |
| `farmGain` | `Farm:OnGain` (#39), the farm session's GAIN receiver | One table bump and one packed log line per gain, only while a session is open (nothing is registered otherwise); prices are deferred off the combat path. Declares `within = "gainSend"` and passes it |
| `farmWindow` | `Farm:OnLootWindow` (#39), Attribution's loot-window notification | Counts the window's corpses (one `GetLootSourceInfo` walk per slot into a reused table), nodes, fish or containers; top level. With no session Attribution pays one nil test |

Nesting is declared and observed (performance-§3). **`toastPaint` declares `within = "gainSend"`**: a push presents or merges its row inside the send, and the content closure passes the parent it actually ran in, `"gainSend"` while `GainFeed.sending` is set (only inside the bracket) and `false` (top level) on a repaint, settle or refresh, so the record says *observed inside gainSend and at top level*. **`gainSend` declares no `within`, because it has no one parent**: every observer sends from inside its own bracket and passes that bucket's key through `GainFeed:SendChat` / `SendEvent` (`lootLine`, `currencyLine`, `moneyLine`, `repEvent`, `appearanceEvent`, `xpEvent`, `skillScan`), and the holdings diff's tap passes `false` (the flush is not a bucket). Each record therefore carries the observed parents (`observedWithin`, `observedMixed`, `observedSecond`), and the report's nesting note says which totals overlap: never sum `gainSend` into a capture bucket, nor `toastPaint` or `farmGain` (#39, which also declares `within = "gainSend"`) into `gainSend`. The Feed's own clock (enter, hold, fade, the pulse, the countdown bar, smooth moves) is the library's: one unparented frame, armed only while a row needs a tick (`Stats().awake`), and it is not bracketed here; `tests/test_toast_feed.lua` pins an idle and a cleared feed asleep.

**`Reconciler:Flush` is not a bucket.** The reconcile (scan, plan, hold or commit) defers to
`PLAYER_REGEN_ENABLED` in combat (`Compat.InCombatLockdown()` at the top of `R:Flush`), so in a
capture it would read 0.000. A bucket that reads 0.000 in every capture is a lie in every report
(performance-§3). It is measured offline instead: `tests/perf.lua` scenario 3 pins one container
scan per dirty group, never one per slot.

## The brackets

Shape A everywhere, one exit:

```lua
function Collector:OnChatMsgLoot(_, msg)
  local t0 = Perf.on and debugprofilestop()
  lootLine(self, msg)
  if t0 then Perf.Note("lootLine", debugprofilestop() - t0) end
end
```

The body is a file-local function, so the bracket measures every early return too. `Perf` is a
load-time upvalue (`local Perf = NS.Perf`), which is why `core/PerfSetup.lua` loads directly
after `core/LifecycleSetup.lua` and above every module. Dormant, a bracket costs one upvalue read,
one field read and one test.

`debugprofilestop()` is called directly in the brackets rather than through `core/Compat.lua`. It
is a profiling clock that exists on every client, and a Compat hop would add a call to the very
path being measured.

## The zero-overhead evidence

`tests/perf.lua` scenario 1 sends a **dropped** loot line (below the quality gate, the common case
in a raid) through the bracketed `OnChatMsgLoot` with capture off, and through the unbracketed body
(`NS.Collector._lootLine`). It checks that the bracketed path allocates no more bytes per call
than the bare body. Scenario 2 pins an in-combat `BAG_UPDATE` storm at zero bytes and zero scans. Scenario 6 sends a `FACTION_STANDING_CHANGED` whose standing did not move through the bracketed
`Reputation:OnStandingChanged`, which must allocate nothing either.

| Scenario | Bytes/iter ceiling | Scans/iter | Measured 2026-10-31 |
|---|---|---|---|
| `lootDroppedBracketed` (1) | 0 | 0 | 0.0 |
| `lootDroppedBare` (1) | 0 | 0 | 0.0 |
| `combatBagUpdate` (2) | 0 | 0 | 0.0 |
| `reconcileCleanBags` (3) | 124000 | 1 | 118120.0 |
| `repUnchanged` (6) | 0 | 0 | 0.0 (2026-11-28) |

Four scenarios are **recorded, not gated** (`RECORDED_ONLY`): the holdings tally cold and warm and the tooltip block's replay (4, 5, #34), and `toastMerge200` (7, #38), the same item gain pushed 200 times into the Main feed with merging on. Every push after the first merges into one live row and repaints it, and the repaint builds the row's strings, so it carries no byte ceiling; the merge's own zero allocation is pinned by `tests/test_toast_model.lua`.

The ceilings are pinned numbers in `tests/perf.lua`, with the reason beside them. Scenario 3 is the
one that does real work: an unchanged pass over 216 occupied slots, behind the debounce and never
in combat.

The runner is **outside the green gate**: `lua tests/run.lua` does not run it. It asserts only
deterministic quantities (bytes with the GC stopped, call counts), never time. Run it with
`lua tests/perf.lua [--out <path>] [--label <text>]`; the vendored automated-test runner records it
as the `perf` suite ([testing.md](testing.md)), reading the scenario table it prints and keeping the
`--out` record as the run's `perf.json`.

## Suspend

`P.Suspend` takes the latch's `perf` hold, and `P.Resume` releases it. This is the same latch the
`disabled` hold uses (`core/LifecycleSetup.lua`, [disabled-state.md](disabled-state.md)), so window
B runs exactly the stand-down `/lh disable` runs. Releasing `perf` never stands up an addon the
player disabled during the run.

Window B no longer loses ledger data. The Reconciler is down while the hold is taken, and anything
that changed in the meantime is read back on resume (`Reconciler:Enable` -> `LoginScan`) as
`UNTRACKED` drift. Loot lines during window B are still not recorded, by design: an inert addon
records nothing.

## How to capture

1. `/lh perf` opens the step panel (the verb works while the addon is disabled).
2. Follow the panel: Experiment A (active), Experiment B (suspended), then finish.
3. Copy the report and the JSON dump out of the client.
4. Run `/dev-copilot:wow-perf-analysis` with both. It writes a frozen bundle under
   [`perf-analysis/`](perf-analysis/README.md).

The capture ring lives in its own SavedVariables global, `LootHistoryPerfDB` (performance-§5),
declared in the TOC beside `LootHistoryDB` and kept outside the AceDB tree.

With no LibKa0s, `NS.Perf` is a stub: brackets are no-ops and `/lh perf` answers
`perf capture unavailable.`.

## The event census

[combat-path-sweep.md](combat-path-sweep.md) keeps the whole-repo registration and timer inventory
with per-fire work. It no longer backs an exemption; it is how you check that a new handler that
can run in combat has a bucket.

## Accepted costs

**A Timeline pane resize renders the chart twice.** The pane's `OnSizeChanged` runs `TL:Layout`,
which calls `chart:Render` explicitly (`modules/Timeline.lua`), and the chart, anchored to the pane,
also renders from its own `OnSizeChanged` (LibKa0s `WidgetsLineChart.lua`). The second pass is
bounded: the regions are pooled, so it costs one extra LTTB thinning and repaint, and only on a
resize, never in combat. It is accepted rather than designed out, and no library seam is wanted for
it (review finding LK-R-04). `tests/test_timeline.lua` pins the count at 2, so a change to it shows
up as a failing case and this paragraph moves with it.
