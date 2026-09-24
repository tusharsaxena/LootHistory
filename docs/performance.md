# Performance

**Ka0s Loot History brackets nothing.** It holds the `performance-§12` no-combat-path exemption,
ratified in [ARCHITECTURE.md § Documented deviations](ARCHITECTURE.md#documented-deviations) and
reasoned at length in closed issue [**LIBKA0S-17**](https://github.com/tusharsaxena/LootHistory/issues/22).
There is no `core/PerfSetup.lua`, no `LootHistoryPerfDB`, no `/lh perf` verb, no `tests/perf.lua`
and no `docs/perf-analysis/` store. `perf` stays a reserved verb and `libs/LibKa0s/` stays whole.

## Which criteria apply: (a) and (c)

- **(a) — no combat path.** No `OnUpdate` handler, no repeating ticker, and no event handler doing
  more than occasional work in combat. `CHAT_MSG_LOOT` fires mid-fight, but `Collector:ShouldRecord`
  drops nearly every line before the tooltip build and the price cascade run.
- **(c) — `suspend` would suppress the data the addon exists to record.** Window B must be inert,
  which here means not recording the loot that drops during that fight.
- **(b) is not claimed.** Whether two arms would separate on the kept-line path is an empirical
  question this addon has no harness to answer.

## Where the sweep lives

[combat-path-sweep.md](combat-path-sweep.md) holds the committed whole-repo `RegisterEvent` /
`SetScript("OnUpdate"` / `C_Timer` sweep: the commands, all fifteen event registrations and all
five one-shot timers with their per-fire work, the one allocation left unmeasured on purpose, and
the lifecycle seam a re-armed harness would reuse. Re-run the sweep before trusting this page.

The vendored runner reads the register row and records perf skip reason (2) in
[`automated-tests/`](automated-tests/RESULTS.md); the release notes name the exemption too.

## What re-arms the wiring

**The first `OnUpdate` handler, repeating ticker, or in-combat event handler doing real work
re-arms the full wiring MUST** (performance-§1 and everything under it). That is the register row's
re-check trigger.
