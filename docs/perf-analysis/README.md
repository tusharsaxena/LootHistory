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

None yet.
