# Performance

Ka0s Loot History is wired into **`LibKa0s-Perf-1.0`** (performance-§1). The probe, the guided
A/B run, the record schema and the step panel are the library's; `core/PerfSetup.lua` supplies
what only this addon knows: which handlers to measure, and the latch that makes it inert.

The addon held the `performance-§12` no-combat-path exemption until the timeline ledger (spec §13
F2). Holdings diffing put work behind `BAG_UPDATE`, money and currency events, which can fire in
combat. That was the exemption's re-check trigger, and the row is retired (see
[ARCHITECTURE.md § Documented deviations](ARCHITECTURE.md#documented-deviations)).

## The buckets

Five, in report order. Each is a handler that runs **in combat**:

| Bucket | Handler | What it covers |
|---|---|---|
| `lootLine` | `Collector:OnChatMsgLoot` | Every loot line in the group: parse, gate, and on a kept line the item extras, the price cascade and the record write |
| `currencyLine` | `Collector:OnChatMsgCurrency` | Currency lines: parse, blacklist, one record write |
| `moneyLine` | `Collector:OnChatMsgMoney` | Looted money and party share: one gold row and its claim |
| `spellCast` | `Attribution:OnSpellSucceeded` | Every player cast: one memoized deconstruct lookup |
| `ledgerEvent` | `Reconciler:OnEvent` | Every capture event (`BAG_UPDATE` storms, money, currency, equipment): a dirty bit and a debounce, nothing else |

None declares `within`: none runs inside another.

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
than the bare body. Scenario 2 pins an in-combat `BAG_UPDATE` storm at zero bytes and zero scans.

The runner is **outside the green gate**: `lua tests/run.lua` does not run it. It asserts only
deterministic quantities (bytes with the GC stopped, call counts), never time. Run it with
`lua tests/perf.lua`; the vendored automated-test runner records it as the `perf` suite
([testing.md](testing.md)).

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
