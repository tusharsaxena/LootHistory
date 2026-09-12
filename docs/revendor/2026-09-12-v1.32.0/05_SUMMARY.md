# 05 — Summary: LibKa0s v1.31.0 → v1.32.0

## What moved

`CLAUDE.md` now names v1.32.0 (tag `e18dd12`, local and unpushed). Two library files moved; the kit
and everything else is byte-identical to v1.31.0.

| File | Constant | Before | After |
|---|---|---|---|
| `Slash.lua` | `MINOR` | 7 | 8 |
| `Options.lua` | `MINOR` | 15 | 16 |

No cross-major skew, no file removed upstream, no line-ending drift, and no instance member added.

## Adopted

- **B1: the Slash bracket around `CliResetAll`.** The Defaults button, the footer Defaults and
  `/lh resetall` each log exactly one line, `[Set] reset all: N rows`, with no per-row `[Set]`. N is
  the seam's tally of rows whose stored value changed, so a press on settings already at their
  defaults logs `[Set] reset all: 0 rows`. Validation, the write and each row's `onChange` still run
  for all 16 rows.

## Declined, or not needed

- **B2: the Options bracket.** Not reached. No path calls the library's `RestoreDefaults` or
  `RestoreAllDefaults`.
- **B3: a `[Set]` line for Reset all settings.** `Sl:ResetEverything` writes no row through the seam,
  so it keeps its one `[Data] reset-all removed N rows` line and logs no `[Set]`.
- **B4: stub no-ops.** None needed.
- **No GitHub issue was filed**, because the brief said to skip filing.

## What each act logs now (debug on)

| Act | Lines |
|---|---|
| Defaults (header or footer), two rows off default | `[Set] reset all: 2 rows` |
| Defaults, everything already at default | `[Set] reset all: 0 rows` |
| `/lh resetall` | `[Set] reset all: N rows` |
| `/lh reset <path>` | `[Set] <path> = <value>` |
| Reset all settings (confirm) | `[Data] reset-all removed N rows` |

## Commits on `fix/2026-09-12-triage` from this run

| Commit | What |
|---|---|
| `14f2977` | Carry LibKa0s v1.32.0: both payloads, the provenance line, and `01_DELTA.md` |
| the next commit | The Slash bracket, the seam's changed-row tally, the tests, the docs and this bundle |

## Gates

| Point | `lua tests/run.lua` | `luacheck .` | `lizard -C 15` |
|---|---|---|---|
| Baseline, before the copy | 727 / 727 | 0 / 0 | 0 warnings |
| After the copy (`14f2977`) | 727 / 727, including the vendor-sync cases against v1.32.0 | 0 / 0 | 0 warnings |
| Tests first, before the seam | 729 / 734 (5 red) | — | — |
| After the adoption | 734 / 734 | 0 / 0 | 0 warnings |

Nothing was pushed.
