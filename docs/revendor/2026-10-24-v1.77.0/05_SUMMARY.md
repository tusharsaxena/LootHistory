# Summary (LootHistory)

LibKa0s v1.76.0 -> v1.77.0 from the local annotated tag (`78240f7`, via `git archive`), base read
from the CLAUDE.md provenance line and confirmed against the payload. Minors: Core 11 -> 12,
DebugLog 20 -> 21, PerfPanel 8 -> 9, SimPanel 5 -> 6, Widgets 14 -> 15, WidgetsDragHandle 4 -> 5,
WidgetsAutocomplete 2 -> 3, Options 29 -> 30, OptionsIds 2 -> 3, OptionsCombat 1 -> 2,
OptionsCompose 7 -> 8, and the new OptionsKeybinds 3; every other file unchanged; test kit 41 -> 42.
Both payloads matched the tag under `diff -r` (content and bytes) before the prune.

**Span bundle:** none owed. **Base correction:** none owed.

**Delivered for free (class A):** the debug console, perf panel and sim step panel are toplevel and
re-raise a shown confirmation; the filter dropdown menus and the Search suggestion list are clamped
to the screen; the Filters tab's IdList suggestion list closes at combat start.

**Contract blockers:** one. Every Options degradation stub owes `KeybindingsTab`, `KeybindRows`,
`KEYBINDS_UNCHANGED` and `StrataTooltip` (CHANGELOG v1.77.0, *What a consumer owes*), and
`Kit.assertSurfaceParity` went red at the copy. Resolved in the re-vendor commit:
`settings/OptionsSetup.lua`'s stub carries the four members.

**Icon declaration and prune.** `LibKa0s icons:` line kept unchanged (16 names). The tag's
`tools/prune-icons.lua` kept 17 files (16 `.tga` + the Open Iconic license) and removed 5,823, the
same set as at v1.76.0, so no icon file changes in git. No provenance split, no README credit
change, no dead stub mirror.

**Other ripple in the commit:** `tests/test_libka0s.lua` adds `OptionsKeybinds.lua` to the explicit
load list, relaxes the v1.71.0 - v1.76.0 pins on the files that moved to floors and adds a v1.77.0
case pinning the release; `tests/test_widgets.lua` moves its Widgets pin to 15; `docs/test-cases.md`
regenerated (Total 1703); the README test badge moves to 1703/1703.

**Adopted in this commit:** none. **Adoptions owed, each its own item:** the Keybindings tab and the
kit's binding checks (LH-KB), the strata changes (LH-ZS). **Deferred (run 2026-10-24):**
`O.StrataTooltip`, DragHandle's level fields, `Core.RaiseStaticPopups` for a host window.
**Declined:** none, so no issue filed. **Unreached:** none.

**Gates.** `luacheck .` (bounded): 0 warnings / 0 errors in 138 files. `lua tests/run.lua`
(bounded): 1703 passed, 0 failed, 1 skipped. In-client smoke for the adoptions is the owner's,
under LH-KB and LH-ZS.

## Re-vendor after the tag moved (M3)

LK-95 moved the local annotated tag v1.77.0 to carry the settings-layout surfaces of the run's item
020. Old: the commit `78240f7b2d69df27b74fc9280cbfbf7b95dd4f1f` the first copy took. New: tag object
`b2b8ee25c5f9fa26db146254bf786b366dec986b`, peeling to commit
`afae2f75cb7ff61c57156d9a3d8a6b2b9f4c5e10` (`git -C ../LibKa0s rev-parse v1.77.0^{}`). Both payloads
were copied whole again from `git archive v1.77.0 LibKa0s testkit` (plus `tools` for the prune).

**Per-file minors that moved:** OptionsCompose 8 -> 11 (minor 9: Master controls `notes`,
`resetPositionTooltip`, `lockIsPreview`, the *Master opacity* label and the frameless packing;
minor 10: `tooltips` on the group composers; minor 11: `O.ResetAllTooltip`). Every other file,
and the test kit (revision 42), is byte-identical to the first copy; `LibKa0s/OptionsCompose.lua`
is the only file the diff named. Before the prune both payloads matched the tag under `diff -r`.

**Prune.** `LibKa0s icons:` line unchanged (16 names); the tag's `tools/prune-icons.lua` kept 17
files and removed 5,823, the same set, so no icon file changes in git. Provenance line stays
v1.77.0 (it records no sha or kit revision).

**Contract blockers:** two, both fixed in the commit. `Kit.assertSurfaceParity` went red on
`ResetAllTooltip`: `settings/OptionsSetup.lua`'s stub carries it as the library's suggested inert
member (answers the tail alone). The composed alpha row now reads *Master opacity* (stored path
`settings.alpha` unchanged): `tests/test_panel.lua` and `tests/test_schema.lua` pin the new label,
`docs/settings-panel.md` and smoke PANEL-5 / PANEL-7 name it (procedure wording only; their
2026-10-10 results stand). `tests/test_libka0s.lua`'s v1.77.0 case pins OptionsCompose 11 and
`O.ResetAllTooltip`. This addon is not frameless and omits no `locked` row, so the frameless
packing changes nothing here.

**Adopted:** none. `notes`, `resetPositionTooltip`, `lockIsPreview`, group `tooltips` and
`O.ResetAllTooltip` are LH-LY's to adopt. **Standards half:** no drift (WS-95 closed rulings inside
v2.88.0, which this addon already cites).

**Gates.** `luacheck .` (bounded): 0 warnings / 0 errors in 140 files. `lua tests/run.lua`
(bounded): 1718 passed, 0 failed, 1 skipped; `docs/test-cases.md` regenerates unchanged.
