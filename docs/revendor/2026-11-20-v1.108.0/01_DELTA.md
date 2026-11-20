Delta: LibKa0s v1.107.0 -> v1.108.0

Payload taken from the local tag, never the sibling tree: `git -C ../LibKa0s archive v1.108.0 LibKa0s testkit tools` (tag commit `56c20b76`; `git -C ../LibKa0s ls-remote --tags origin v1.108.0` prints nothing, so the tag is not on origin yet). Run under Ka0sAddonsCommonTasks `docs/2026-11-20-LIBKA0S_94_97_99_100/`, item SD-RV-LH: copy, provenance, declaration and prune only, with no adoption interview and no issue filing (the run's adoption items are its own manifest rows, SD-SK-LH for this addon).

## Step 0 pre-flight
Newest single-tag bundle `2026-11-19-v1.107.0`, line 1 `Delta: LibKa0s v1.106.0 -> v1.107.0`; the provenance line before the commit that vendored v1.107.0 (`40720fd`) named v1.106.0. ok, no correction owed.

## 3a Base
- `grep -n '[Bb]undles' CLAUDE.md` at HEAD (`97cec5e`): `Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.107.0 (MIT).`
- `git log -1 --format=%h -- libs/LibKa0s tests/_kit` is `b9ea65e` ("Re-vendor the re-cut LibKa0s v1.107.0"), whose CLAUDE.md names v1.107.0. They agree.
- `diff -rq` of a v1.107.0 extract against `libs/LibKa0s` (outside the pruned `media/`) and `tests/_kit` printed nothing (payload-matches).
- `git -C ../LibKa0s log --oneline v1.107.0..v1.108.0`: 15 commits (SD-LK-94, SD-LK-99, SD-LK-100, SD-LK-97 Batches A to D with their review fixes, SD-LK-GUARD Batch G and its two review fixes, SD-LK-REL x2, and the v1.107.0 merge). `git -C ../LibKa0s diff --stat v1.107.0 v1.108.0 -- LibKa0s testkit`: 23 files changed, 1363 insertions, 306 deletions.

## 3b/3c Per-file minors that moved
The constants HEAD carried matched v1.107.0's. Against the tag's `LibKa0s.xml` (3c's loop, only the rows that moved):
```
Core.lua                   old: MINOR = 18            new: MINOR = 19
Callout.lua                old: MINOR = 4             new: MINOR = 5
CalloutSettings.lua        old: SETTINGS_MINOR = 5    new: SETTINGS_MINOR = 6
WaypointArrow.lua          old: MINOR = 2             new: MINOR = 3
WaypointArrowSettings.lua  old: SETTINGS_MINOR = 2    new: SETTINGS_MINOR = 3
Charts.lua                 old: MINOR = 2             new: MINOR = 3
ChartsRender.lua           old: RENDER_MINOR = 1      new: RENDER_MINOR = 2
SkinPaint.lua              old: PAINT_MINOR = 19      new: PAINT_MINOR = 20
SkinPaintHud.lua           old: HUD_MINOR = 1         new: HUD_MINOR = 2
SkinPaintControls.lua      old: CONTROLS_MINOR = 18   new: CONTROLS_MINOR = 19
Widgets.lua                old: MINOR = 29            new: MINOR = 30
WidgetsDropdown.lua        old: DROPDOWN_MINOR = 2    new: DROPDOWN_MINOR = 3
WidgetsDragHandle.lua      old: DRAG_MINOR = 15       new: DRAG_MINOR = 16
WidgetsDragHandleTip.lua   old: DRAGTIP_MINOR = 2     new: DRAGTIP_MINOR = 3
WidgetsLineChart.lua       old: CHART_MINOR = 7       new: CHART_MINOR = 8
WidgetsBar.lua             old: BAR_MINOR = 1         new: BAR_MINOR = 2
OptionsCompose.lua         old: COMPOSE_MINOR = 19    new: COMPOSE_MINOR = 20
```
No file added, no `NEEDS_*` floor raised, no cross-major skew.

## 3d Diffs
After the copy and before the prune, `diff -r --strip-trailing-cr` and `diff -r` of the extract against `libs/LibKa0s` and `tests/_kit` printed nothing. After the prune the only differences are `Only in <extract>/LibKa0s/media/...` lines for undeclared icons and sounds.

## 3e Consumption map
`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' core modules settings --include='*.lua'`: Bus, Charts, Compat, Core, DebugLog, Env, Item, Launcher, Lifecycle, Media, Options, Perf, Pool, Schema, Sim, Skin, Slash, Tooltip, Widgets. Neither Callout nor WaypointArrow is looked up. This addon builds no `W.Bar`, no `W.DragHandle` and no `W.ContextMenu` submenu, and calls none of `O.FontGroup`, `O.BorderGroup`, `O.BarGroup`, `O.ColorPair` or `S.ApplyBarFill` (`grep -rnE 'FontGroup|BorderGroup|BarGroup|ColorPair|ApplyBarFill|ContextMenu|W\.Bar\b|DragHandle' --include='*.lua'` outside `libs/` and `tests/_kit/` finds only the degraded facade's `ApplyBarFill` and `BarStyle` names in `core/SkinSetup.lua`).

## 3f Kit
`Kit.VERSION` 57 -> 58 (`tests/_kit/framework.lua:20`). Both payloads move together in one commit, as the pairing rule has required since v1.9.0.

## 3g Contract delta
The consumer-visible default changes (CHANGELOG v1.108.0, *What a consumer owes*), read against what this addon hands over:
- **OptionsCompose 20 (composers emit FromSkin companions by default).** This addon calls no composer; its Appearance rows are `OptionsAppearance`'s (`__AttachAppearance`, minor unchanged), whose font and texture overrides already default to `""`, the skin's own. Nothing owed.
- **WidgetsBar 2, SkinPaintHud 2, `S.ApplyBarFill` (borders, gloss, a texture for a bare StatusBar).** No `W.Bar` and no StatusBar here. Nothing owed.
- **Charts 3 / ChartsRender 2 (a bar of data only through `barFill`; an owner's default `barFill` wears the skin's gloss, U-4).** `modules/AnalyticsCharts.lua:36` passes its own `barFill` (`NS.SkinBar`, bar texture and tint) with an owner, so its bars keep drawing as before. Only the library's default `barFill` adds the gloss; a host `barFill` does not. That is not a blocker (nothing breaks); taking U-4's gloss on this addon's own data bars is SD-SK-LH's.
- **WidgetsDropdown 3 (submenu arrow tint, no secret label measured).** This addon opens no submenu and passes plain labels. Nothing owed.
- **Widgets 30 (`Footer` lays only shown marks; `W.OwnerWarnings`).** The History footer passes no marks (`modules/Browser.lua`, `NS.MakeFooter(frame, { grip = true })`) and every hosted widget passes `owner` (`core/WidgetsSetup.lua`). Nothing owed; registering an owner-warning sink is optional and not taken here.
- **Callout 5, WaypointArrow 3.** Not built here. Nothing owed.
- **Kit revision 58.** `test_skin_values` reads colors kept in tables and `return`s: it reported the Insights per-source palette, the two degraded title badges and the unknown-quality white. `test_skin_switch` compares each setter family on its own; this addon's declared surfaces all passed it unchanged.

**Blockers, fixed in the re-vendor commit:** the exact minor pins in `tests/test_libka0s.lua` (each moved file's older pin becomes a floor and a v1.108.0 case pins the new minors), the Widgets minor pin in `tests/test_widgets.lua`, and the three revision-58 typed-value hits (the palette's local renamed `SOURCE_CATEGORY_COLOR` so the kit's meaning-table category takes it; three `Kit.skinValues.rows` with cause MC in `tests/run.lua`).

## 3i Icon declaration
`LibKa0s icons:` kept as it was. Prune: `lua <extract>/tools/prune-icons.lua .` kept the same 23 icon files the addon shipped and removed the rest of the catalog and the 362 sound files again (no `LibKa0s sounds:` line); `git status` shows no change under `libs/LibKa0s/media/`. Credits unchanged: Open Iconic is still the only set shipped. No provenance split.

## 3j Whole-folder icon tests
`grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v /_kit/`: 4 hits, unchanged since v1.105.0, all declared-name assertions. None.

## 3h Span
Every tag vendored since the store's horizon has a bundle (v1.107.0 in `2026-11-19-v1.107.0`, v1.106.0 in the span `2026-11-19-v1.106.0-v1.106.0`). Nothing to write.
