# Perf analysis

The store for **in-game** performance captures of Ka0s Loot History (performance-§8). An
interpretation without its record is an assertion, so every capture this repo cites lands here as
a frozen bundle. What the harness measures and why is on [performance.md](../performance.md).

## Bundle naming

`docs/perf-analysis/<YYYYMMDD-HHMMSS>/`, in local time, taken from the record's own timestamp
rather than from when the bundle was written.

## The three artifacts

| File | What it is |
|---|---|
| `report.md` | The text report the client printed after `/lh perf finish` |
| `dump.json` | The JSON dump, byte for byte as copied out of the client |
| `ANALYSIS.md` | The write-up, per the standards repo's `PERF_ANALYSIS.md` playbook |

Bundles are never edited and never pruned.

## Record schema

The record is LibKa0s-Perf's, not this addon's: `lib.SCHEMA` in `libs/LibKa0s/Perf.lua`, documented
in the library's `docs/api/`. The buckets are declared in `core/PerfSetup.lua`.

## How to capture

1. `/lh perf` opens the step panel.
2. Run Experiment A, then Experiment B, then finish.
3. Copy the report and the dump.
4. Run `/dev-copilot:wow-perf-analysis` with both; it writes the bundle here.

Offline runs (`lua tests/perf.lua`) are not captures. They are recorded with the automated-test
battery in [`automated-tests/`](../automated-tests/RESULTS.md).

## Captures

| Stamp | Addon version | Label | What it measured | Bundle |
|---|---|---|---|---|
| 20261007-104651 | 1.4.0 | `2026-10-07 10:46` | Protection Paladin, five-player party in Murder Row; 48.6 s / 52.7 s arms; 0.014 ms of addon Lua per second of combat, 99.7% `spellCast`; frame-time delta +0.57 ms/frame, unresolved (pull-to-pull variance); `ledgerEvent` fired once, so in-combat ledger traffic was not exercised | [20261007-104651](20261007-104651/ANALYSIS.md) |
