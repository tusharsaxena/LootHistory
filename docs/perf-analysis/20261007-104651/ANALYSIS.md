# Analysis — 20261007-104651

- **Addon:** Ka0s Loot History 1.4.0 (record schema 2, client interface 120100)
- **Captured:** 2026-10-07 10:46 local, label `2026-10-07 10:46`
- **Who / where:** Sacrìlege-Frostmourne, level 90 Protection Paladin · Murder Row (no subZone) · party (5) / party
- **Delta:** +0.57 ms/frame, unresolved (the arms were different pulls and the delta is about 2,700 times the addon's own accounted cost)
- **Previous capture:** none — this is the first

## Headline

This is the first in-game capture of the addon since the timeline ledger gave it a combat path. The
addon's own Lua cost **0.666 ms over the 48.6 s active arm, which is 0.014 ms per second of combat**
and 0.0002 ms per frame, with a longest single call of 0.053 ms ([`dump.json`](dump.json)). The
frame-time delta of +0.57 ms/frame is not attributable to the addon. Nothing here needs acting on,
but the run exercised almost none of the ledger's combat path, so it is a thin baseline (see Actions).

## The arms

Both figures come from [`dump.json`](dump.json)'s `fps` block; the rounded forms are in
[`report.md`](report.md).

| Arm | Seconds | Frames | Avg fps | ms/frame |
|---|---|---|---|---|
| active (addon running) | 48.5990 | 3161 | 65.0425 | 15.3746 |
| suspended (addon inert) | 52.7060 | 3560 | 67.5445 | 14.8051 |
| **delta** | | | | **+0.5695** |

The delta is nominally just past the roughly 0.5 ms/frame line, but it does not resolve the addon.
Both arms are shorter than the 60–80 s the ±0.3 ms/frame floor assumes, the arms differ by 4.1 s
(48.6 s against 52.7 s), and they were separate pulls, so the fight itself differed between them. The
addon's bucketed Lua is 0.0002 ms/frame (0.6659 ms over 3161 active frames), so the delta is about
2,700 times the cost the buckets measured directly. A difference that size cannot be the addon's own
Lua; it is pull-to-pull variance in a five-player dungeon. The buckets are the answer, not the delta.

## The buckets — what the addon actually cost

Every figure from [`dump.json`](dump.json)'s `buckets`; `ms/s` is `totalMs` over the **active** arm's
seconds, as [`report.md`](report.md) computes it. Buckets nest — **do not sum the column**.

| Bucket | Calls | Total ms | ms/s | Max ms | Parent |
|---|---|---|---|---|---|
| `spellCast` | 68 | 0.6636 | 0.014 | 0.0533 | none declared |
| `ledgerEvent` | 1 | 0.0023 | 0.000 | 0.0023 | none declared |

Neither bucket declares a parent, so they do not overlap and can be added up. The addon's accounted
cost is **0.6659 ms, or 0.014 ms per second of combat**.

- `spellCast` is 99.7% of it. It ran 68 times at an average of 0.0098 ms and a maximum of 0.0533 ms,
  which is 1.4 casts per second of combat.
- `ledgerEvent` ran once, at 0.0023 ms.

Three declared buckets are **absent**, so they never fired: `lootLine`, `currencyLine` and
`moneyLine`. No loot, currency or money line arrived during the active arm. That is a result about
what the run exercised, not about those handlers' cost.

## What the capture did not hold constant

From [`report.md`](report.md)'s context block:

- **Different pulls.** The two arms were separate combats in Murder Row, 48.6 s and 52.7 s long.
  Combat gating equalizes neither the encounter nor the environment.
- **No run log.** The paste kept for this bundle holds the report and the dump only; the lifecycle
  lines (`armed`, `RECORDING`, `SUSPENDED`, `RESUMED`) were not supplied. This record therefore cannot
  confirm that arm B was combat-gated, that it really ran suspended, or that no `/reload` landed
  between the arms.
- **Order.** Arm A (addon active) ran first and arm B (suspended) second, so any warm-up or
  fatigue effect lands on the same side of every comparison.
- **Out-of-combat work is outside the A/B by design.** The ledger reconciles on `PLAYER_REGEN_ENABLED`
  (see [`../../performance.md`](../../performance.md)), so a flush after the pull is not in either arm.

Validation: `dump.json`'s `addon` is `LootHistory`, `version` is 1.4.0 (matches the TOC), `schema` is 2
(matches `lib.SCHEMA` in `libs/LibKa0s/Perf.lua`), both arms have frames > 0, and the report's rounded
figures reconcile with the dump's four-decimal ones. The bundle stamp is the label's minute with the
seconds as supplied by the capture owner; `dump.timestamp` renders as 10:50:32 local, the end of the
run.

## What moved

First capture — nothing to diff against; every figure above is a baseline reading.

## Actions

1. **Coverage gap, new here.** `ledgerEvent` fired once, so no in-combat bag, money or currency
   traffic was exercised, and `lootLine`, `currencyLine` and `moneyLine` never fired. Take a follow-up
   capture that uses potions and loots mid-pull (`core/PerfSetup.lua` buckets, no code change).
2. **Order, new here.** Run the follow-up with arm B (suspended) before arm A, to see whether the
   +0.57 ms/frame sign follows the order rather than the addon.
3. **Run log, new here.** Keep the lifecycle lines in the next paste so the arms' conditions can be
   confirmed.
