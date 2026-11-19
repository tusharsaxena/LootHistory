Delta: LibKa0s v1.106.0 -> v1.107.0

Payload taken from the local tag, never the sibling tree: `git -C ../LibKa0s archive v1.107.0 LibKa0s testkit tools` (tag commit `427e108d`, not on origin yet). Run under Ka0sAddonsCommonTasks `docs/2026-11-19-ADOPTION_FEEDBACK/`, item AF-RV-LH: copy, provenance, declaration and prune only, with no adoption interview (the run's adoption items are its own manifest rows).

## Step 0 pre-flight
Newest single-tag bundle `2026-11-16-v1.105.0`, line 1 `Delta: LibKa0s v1.93.0 -> v1.105.0`; the provenance line before the commit that vendored v1.105.0 named v1.93.0. ok, no correction owed.

## 3a Base
- `grep -n '[Bb]undles' CLAUDE.md` at HEAD: `Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.106.0 (MIT).`
- `git log -1 --format=%h -- libs/LibKa0s tests/_kit` is `7438c64` ("Re-vendor LibKa0s v1.106.0"), whose CLAUDE.md names v1.106.0. They agree.
- `diff -rq` of a v1.106.0 extract against `libs/LibKa0s` (outside the pruned `media/`) and `tests/_kit` printed nothing (payload-matches).
- `git -C ../LibKa0s log --oneline v1.106.0..v1.107.0`: 6 commits (AF-LK-01, AF-LK-02, AF-DR-LK, AF-LK-03 x3). `git -C ../LibKa0s diff --stat v1.106.0 v1.107.0 -- LibKa0s testkit`: 2 files changed, 195 insertions, 197 deletions.

## 3b/3c Per-file minors that moved
The constants HEAD carried matched v1.106.0's. Against the tag's `LibKa0s.xml`:
```
WidgetsDragHandle.lua     old: DRAG_MINOR = 14     new: DRAG_MINOR = 15
WidgetsDragHandleTip.lua  old: DRAGTIP_MINOR = 1   new: DRAGTIP_MINOR = 2
```
No other file moved; no cross-major skew.

## 3d Diffs
After the copy and before the prune, `diff -r` (content and bytes) of the extract against `libs/LibKa0s` and `tests/_kit` printed nothing. After the prune the only differences are `Only in <extract>/LibKa0s/media/...` lines for undeclared icons and sounds.

## 3e Consumption map
This addon looks up Bus, Charts, Compat, Core, DebugLog, Env, Item, Launcher, Lifecycle, Media, Options, Perf, Pool, Schema, Sim, Skin, Slash, Tooltip and Widgets. It builds no `W.DragHandle` (`grep -rn DragHandle --include='*.lua'` outside `libs/` and `tests/_kit/` finds none), and no library surface it drives builds one (Callout is the payload's only DragHandle caller, and this addon does not look Callout up).

## 3f Kit
`Kit.VERSION = 57` at both ends; the kit is byte-identical between the two tags.

## 3g Contract delta
The two moved files change the drag strip: marks [?][settings][close] with the settings mark on unless `spec.settings == false`, the close still only with `spec.onClose`, the window header's tints, a 14 px mark pitch, and the strip tooltip always above (`spec.tooltipPlace` ignored). This addon passes no DragHandle spec and no `tooltipPlace`, so nothing it hands over moved. **Blockers: none.** The one test change is the exact-pin case (`tests/test_libka0s.lua`: the v1.105.0 case's two DragHandle pins become floors, and a v1.107.0 case pins minors 15 and 2).

## 3i Icon declaration
`LibKa0s icons:` kept as it was (it already declares `settings`, which strip consumers now owe; this addon has no strip). Prune: `lua <extract>/tools/prune-icons.lua .` kept the same 23 icon files the addon shipped and removed the rest of the catalog and the 362 sound files again (no `LibKa0s sounds:` line). Credits unchanged: Open Iconic is still the only set shipped. No provenance split.

## 3j Whole-folder icon tests
`grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v /_kit/`: unchanged since v1.105.0, all declared-name assertions. None.

## 3h Span
v1.106.0 was vendored (`7438c64`) with no bundle; recorded in the span bundle `docs/revendor/2026-11-19-v1.106.0-v1.106.0/` written in this run.
