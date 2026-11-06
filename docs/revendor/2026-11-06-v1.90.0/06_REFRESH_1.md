# Refresh 1 of the v1.90.0 re-vendor (SF2, 2026-11-06)

The tag `v1.90.0` was local and unpushed when this addon first vendored it (`SF1-RV-LH`). The library then
moved it to carry SF2-L1, the three remaining one-UI-unit lines: the shared menu's divider rule, the ReorderList row
boxes and the DragHandle strips, now one physical pixel wide. This is the skill's *A tag that moved before it was pushed*
case, so no new bundle folder is written and line 1 of `01_DELTA.md` is unchanged.

| | Commit |
|---|---|
| `git -C ../LibKa0s rev-parse v1.90.0^{commit}` before | `4485b8f589077b47e61f261405b3008bc4d81838` |
| after | `1ba5fa2556319c2aa4c37085385632bb7113eb1a` |

## Per-file minor delta between the two commits (3c's loop, run against each)

| File | Before | After |
|---|---|---|
| `Widgets.lua` | 24 | 25 |
| `WidgetsReorder.lua` | 5 | 6 |
| `WidgetsDragHandle.lua` | 12 | 13 |

Kit revision: 51 -> 51. No other file moved. Class A for this addon: nothing to adopt, and no host change.

## The copy

Both payloads were re-copied whole from a fresh `git -C ../LibKa0s archive v1.90.0 LibKa0s testkit tools`. Before the
prune both content diffs were empty. Prune: `prune-icons: .: 22 icon(s) declared; kept 23 file(s), removed 5817`. After the prune, the only remaining differences are the
`Only in <extract>/LibKa0s/media/icons` lines for icons this addon does not declare. The `LibKa0s icons:` line is unchanged.

## Blocker fixed in this commit (3g/3j class)

The suite pinned the first cut's minors, so the refresh was red (1978 passed, 3 failed). The `v1.90.0` case pinned
Widgets 24, and the `v1.85.0` case pinned WidgetsReorder 5 and WidgetsDragHandle 12 exactly (`tests/test_libka0s.lua`).
`tests/test_widgets.lua:165` asserted "written against Widgets minor 24". Following the file's own convention, the
older release case now reads `>=` with a "pinned there" note, and the newest one pins Widgets 25, WidgetsReorder 6
and WidgetsDragHandle 13. No code changed.

## Gate

- `ka0s-bounded luacheck .`: Total: 0 warnings / 0 errors in 162 files
- `ka0s-bounded lua tests/run.lua`: 1981 passed, 0 failed, 1 skipped, 1982 total
