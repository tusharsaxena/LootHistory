# Summary (LootHistory)

LibKa0s v1.77.0 -> v1.78.0 from the local annotated tag (`fb7b7a3`, via `git archive`), base read
from the CLAUDE.md provenance line and confirmed against the payload. Minors: Core 12 -> 13, Media
5 -> 6, Widgets 15 -> 16 (WidgetsReorder 1 -> 2, WidgetsDragHandle 5 -> 6, WidgetsLineChart 3 -> 4,
WidgetsAutocomplete 3 -> 4, new WidgetsCopyWindow 1), DebugLog 21 -> 22 (DebugLogDiagnostics 3 -> 4,
new DebugLogWindow 1), Options 30 -> 33 (OptionsRegistry 2 -> 3, OptionsWidgets 34 -> 35,
OptionsIds 3 -> 4, OptionsIdList 5 -> 6, OptionsTabs 9 -> 10, OptionsCombat 2 -> 3, OptionsCompose
11 -> 12, OptionsScroll 4 -> 6, OptionsNav 2 -> 3, OptionsDrawer 1 -> 2, OptionsKeybinds 4 -> 5, new
OptionsAppearance 1), PerfPanel 9 -> 10, SimPanel 6 -> 7, and the new major `LibKa0s-Skin-1.0`
(Skin 4, SkinDefs 4, SkinPaint 2, SkinPaintExtras 1, SkinPaintControls 1, SkinEUI 1, SkinAce 1);
every other file unchanged; test kit 42 -> 43. Both payloads matched the tag under `diff -r`
(content and bytes) before the prune.

**Span bundle:** none owed. **Base correction:** none owed.

**Delivered for free (class A):** nothing visible changes while no skin owner is registered; the
library's controls, tool windows and settings chrome paint as at v1.77.0. Media 6 registers the
five OFL skin faces and the Glass border and background with LibSharedMedia.

**Contract blockers (adoption blockers):** one. Every Options degradation stub owes
`AppearanceTab` and `AppearanceRows` (CHANGELOG v1.78.0, *What a consumer owes*; Options doc
:64-66, :1738-1739), and `Kit.assertSurfaceParity` went red at the copy. Resolved in the re-vendor
commit: `settings/OptionsSetup.lua`'s stub carries both new members (`AppearanceTab` answering
`{ key = "Appearance", label = "Appearance", render = noop }`, `AppearanceRows` answering nil).

**Icon declaration and prune.** The plan-review grep over the tag's Skin, Appearance, Options and
Widgets files (01_DELTA 3i, widened to Core, DebugLog, PerfPanel and SimPanel) found no new
library-drawn name: still `close`, `clear`, `copy`, `info`, all declared. `LibKa0s icons:` line kept
unchanged (16 names). The tag's `tools/prune-icons.lua` kept 17 files (16 `.tga` + the Open Iconic
license) and removed 5,823, the same set as at v1.77.0, so no icon file changes in git. No
provenance split, no dead stub mirror.

**README credits.** The three new OFL faces are credited beside JetBrains Mono: Barlow (the Barlow
Project Authors), Cinzel (the Cinzel Project Authors, its SemiBold cut from the variable font) and
Atkinson Hyperlegible (the Braille Institute of America), each SIL OFL 1.1, their licenses shipped
beside them in `libs/LibKa0s/media/fonts/`. The Glass textures are LibKa0s's own generated art and
carry no third-party credit. No icon-set credit moves.

**Other ripple in the commit:** `tests/test_libka0s.lua` adds the ten new files to `LIB_FILES` in
XML order, relaxes the v1.71.0, v1.75.0 and v1.77.0 pins on the files that moved to floors and adds
a v1.78.0 case pinning the release; `tests/test_widgets.lua` moves its Widgets pin to 16;
`docs/test-cases.md` regenerated (Total 1729); the README test badge moves to 1729/1729.

**Adopted in this commit:** none. **Adopted in this run, each its own item:** the Skin major and the
Appearance tab (LH-01), window chrome (LH-02), the History table (LH-03), Insights, Timeline and
Holdings (LH-04), host AceGUI widgets (LH-06), tool surfaces and docs (LH-05). **Declined:** none,
so no issue filed. **Unreached:** none.

**Gates.** `luacheck .` (bounded): 0 warnings / 0 errors in 140 files. `lua tests/run.lua`
(bounded): 1729 passed, 0 failed, 1 skipped (`test_vendor_sync` green against v1.78.0). No authored
`.lua` file above 1500 lines (largest `tests/test_browser.lua`, 1459). In-client smoke for the
adoptions is the owner's, under LH-01 to LH-06.
