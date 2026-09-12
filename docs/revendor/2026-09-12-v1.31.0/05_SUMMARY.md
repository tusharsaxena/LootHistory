# 05 — Summary: LibKa0s v1.30.0 → v1.31.0

## What moved

`CLAUDE.md` now names v1.31.0 (tag `30db4ed`). Two library files and the kit moved; everything else
is byte-identical to v1.30.0.

| File | Constant | Before | After |
|---|---|---|---|
| `OptionsCompose.lua` | `COMPOSE_MINOR` | 3 | 4 |
| `OptionsWidgets.lua` | `WIDGETS_MINOR` | 14 | 15 |
| `testkit/framework.lua` | `Kit.VERSION` | 16 | 17 |

The other eleven files (Core 7, Env 1, Pool 3, Item 1, Media 3, Widgets 9, DebugLog 12, Slash 7,
Options 15, OptionsScroll 3, Perf 10, PerfPanel 5) are unchanged. No cross-major skew, no file
removed upstream, no line-ending drift.

## Delivered on the copy alone (class A)

- The composers' `spec.bind` arm and the path-less `get` / `set` rows. Every row this addon renders
  has a path, so both are inert here.
- Kit 17's AceTimer, `M.__fireTimers()` cancellation and count, AceConsole's recorded commands,
  AceEvent's CallbackHandler message rules, `M.__fireEvent`, `M.__badEvents`, and AceGUI's
  `WidgetVersions` / `RegisterLayout`. None required a test port.

## Adopted

- **B1: the local `NewAddon` wrapper deleted** (`tests/wow_mock.lua`). Kit 17 embeds the mixin list
  itself. It was characterized first, and the case goes red when AceEvent is dropped from the
  production list. Commit `a2b70ed`.

## Declined, not applicable, or unreached

- Declined, with the reasons in `03_DECISIONS.md`: the bind arm (no record-backed composer here),
  porting to `M.__fireEvent` (nothing to port), and driving `/lh` through `AceConsole:__slash`.
- **No GitHub issue was filed**, because the orchestrator's brief for this run said to skip filing.
- Every other local extension in `tests/wow_mock.lua` is outside what v1.31.0 delivers. The
  geometry flip is revision 18 at the earliest, and the kit declined `SetTitle`.
- Nothing was left unreached.

## Commits on `fix/2026-09-12-triage` from this run

| Commit | What |
|---|---|
| `438b38d` | Carry LibKa0s v1.31.0: both payloads, the provenance line, and `01_DELTA.md` |
| `a2b70ed` | Kit 17 embeds the addon's mixins; the local `NewAddon` wrapper is deleted |
| `a6dc8d9` | A per-row delete of the loot history logs one `[Data]` line (not part of the re-vendor) |
| `3647c53` | The loot history log and its repair bookkeeping are named as recorded data (not part of the re-vendor) |

The last two are the brief's §8 and §9 items. They share this branch and appear here so the
commit list is complete.

## Gates

| Point | `lua tests/run.lua` | `luacheck .` |
|---|---|---|
| Baseline, before the copy | 722 / 722 | 0 / 0 |
| After the copy (`438b38d`) | 722 / 722, including the vendor-sync cases against v1.31.0 | 0 / 0 |
| After B1 (`a2b70ed`) | 723 / 723 | 0 / 0 |
| After the §8 trace (`a6dc8d9`) | 724 / 724 | 0 / 0 |

`luacheck` excludes `libs/` and `tests/_kit/` (`.luacheckrc`). The files that carry the seam, like
`tests/wow_mock.lua`, `tests/test_harness.lua` and `core/Database.lua`, are inside the checked set.
Nothing was pushed.
