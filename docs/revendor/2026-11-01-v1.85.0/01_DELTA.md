Delta: LibKa0s v1.84.0 -> v1.85.0

Part of Ka0sAddonsCommonTasks `docs/2026-11-01-FULL_SKINNING/` (FS-LH-RV). The tag is local, cut by that run's `FS-REL`, at `09a835c`.

## Base (3a, 3b)

`grep -n '[Bb]undles' CLAUDE.md` names v1.84.0. `git log -1 --format=%H -- libs/LibKa0s tests/_kit` gives a commit whose line names v1.84.0 as well, and `diff -rq --strip-trailing-cr` of both payloads against `git archive v1.84.0` shows only the undeclared icons: the bytes are v1.84.0.

Newest single-tag bundle `2026-10-31-v1.84.0` states base v1.83.0, which is the addon's history. No correction owed.

## Per-file minors (3c), moved files only

`for f in LibKa0s.xml files: grep the [A-Z_]*MINOR constant, old against tag`

| File | old | new |
|---|---|---|
| Glow.lua | 1 | 2 |
| Toast.lua | 1 | 2 |
| Skin.lua | 11 | 14 |
| SkinDefs.lua | 19 | 24 |
| SkinDefsOthers.lua | 1 | 6 |
| SkinPaint.lua | 13 | 16 |
| SkinPaintExtras.lua | 7 | 15 |
| SkinPaintControls.lua | 11 | 14 |
| SkinEUI.lua | 2 | 3 |
| SkinAce.lua | 6 | 9 |
| Widgets.lua | 17 | 20 |
| WidgetsReorder.lua | 3 | 5 |
| WidgetsDragHandle.lua | 10 | 12 |
| WidgetsLineChart.lua | 5 | 6 |
| WidgetsAutocomplete.lua | 5 | 6 |
| WidgetsCopyWindow.lua | 2 | 4 |
| DebugLogWindow.lua | 2 | 3 |
| Launcher.lua | 5 | 6 |
| OptionsWidgets.lua | 41 | 44 |
| OptionsIds.lua | 6 | 7 |
| OptionsIdList.lua | 7 | 8 |
| OptionsTabs.lua | 13 | 15 |
| OptionsCompose.lua | 16 | 17 |
| OptionsScroll.lua | 10 | 13 |
| OptionsNav.lua | 4 | 5 |
| OptionsDrawer.lua | 4 | 5 |
| OptionsKeybinds.lua | 6 | 7 |
| OptionsAppearance.lua | 5 | 6 |
| OptionsSkinPicker.lua | 5 | 7 |
| OptionsMedia.lua | 3 | 4 |
| PerfPanel.lua | 11 | 12 |
| SimPanel.lua | 9 | 10 |
| SimPanelRender.lua | 1 | 2 |

No file is behind the old tag: no cross-major skew.

## Kit (3f)

`grep -n 'Kit.VERSION'`: revision 47 -> 49. The two payloads move together.

## Consumption (3e)

Lookups outside `libs/` and `tests/`: Bus, Charts, Compat, Core, DebugLog, Env, Item, Launcher, Lifecycle, Media, Options, Perf, Pool, Schema, Sim, Skin, Slash, Widgets. Unchanged.

## Blockers (3g, 3j)

- **Facades.** `CHANGELOG.md` v1.85.0, "What a consumer owes": the degraded Skin facade (`core/SkinSetup.lua`) gains `Mark`, `MarkText`, `HudTextColor`, `HudLabelColor`, `BarFillColor`, `HudShadow`, `BarGloss` and `HudFont`, and its `FontFlags` and `HudFontSize` become real functions, which `HudFont` calls; the Options stub (`settings/OptionsSetup.lua`) gains `LabelFont`. Fixed in the re-vendor commit.
- **Icons.** `docs/releasing.md` Step 8 for v1.85.0: `chevron-down, chevron-up, close, confirm, info, move, reset, volume-high`, or kit revision 49's vendor gate goes red. Decided by the plan, not re-asked. Hand lists have drifted before; the owner's smoke is the backstop. `tests/test_mediasetup.lua`'s `DRAWN` list moves with the line.
- **Minor pins.** `tests/test_libka0s.lua` and `tests/test_widgets.lua` pinned minors this tag moves; the old pins relax and a v1.85.0 case pins the new ones.
- `tests/test_libka0s.lua:614` opens `info.tga`, which stays declared. No `__Attach*` site in this addon, and `__releaseChrome` has no mirror here.
- **`Skin.FollowOnce`** is not reached: this addon has no HUD and no D-cause row.

## Unrecorded tags (3h)

v1.79.0 to v1.83.0 are recorded by the span bundle `2026-10-31-v1.79.0-v1.83.0`; nothing unrecorded.
