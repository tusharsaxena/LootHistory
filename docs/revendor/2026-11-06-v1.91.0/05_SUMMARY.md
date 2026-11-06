# Summary

- **Tag:** v1.90.0 -> v1.91.0 (local tag, `55bfbb4`), base from the provenance line (`CLAUDE.md:58`),
  agreeing with the last payload commit `10b0042`. Kit unchanged at 51. Minors moved: Core 16 -> 17,
  Widgets 25 -> 26, WidgetsLineChart 6 -> 7, SkinPaintExtras 18 -> 19; new files CorePixel 1,
  WidgetsDropdown 1, SkinPaintHud 1, SkinAceConfirm 1. Table in `01_DELTA.md`. Step 0 skipped (its
  roster regex matches nothing in the current ADDONS.md; fixed upstream by FU-DC1). No span bundle, no
  base correction, no refresh file.
- **For free (class A):** the Timeline chart's axis, grid rules, `ledgerSince` marker and hover
  crosshair are one physical pixel at any UI scale (FU-L1); the four peels are pure moves (FU-L2).
- **Look change for this host:** the Timeline's series thicknesses (`C.TIMELINE.TOTAL_W` 2.5,
  `LINE_W` 2) are now read as physical pixels where they were UI units, so at a UI scale where a unit
  is more than a pixel the lines draw slightly thinner. The plan rules this semantics; the owner's
  in-client smoke of the Timeline tab is the check. `[upstream]`: the Widgets 26.1.6.13.7.8.5 API
  document (line 33) says LootHistory passes no `thickness`; it does.
- **Contract blockers:** none. **File-list and pin blockers**, fixed in the re-vendor commit:
  `tests/test_libka0s.lua`'s `LIB_FILES` gains `CorePixel.lua`, `SkinPaintHud.lua`,
  `SkinAceConfirm.lua` and `WidgetsDropdown.lua` in the tag's XML order; its v1.85.0 pin on
  WidgetsLineChart and v1.90.0 pins on Core, Widgets and SkinPaintExtras relax to floors with a
  "pinned there" note, and a new v1.91.0 case pins the new minors and kit 51 exactly;
  `tests/test_widgets.lua`'s adoption pin moves to Widgets 26 and its comment names
  `WidgetsDropdown.lua` as the menu's home. No stub mirrors a moved member (the peels keep every name).
- **Icons:** `LibKa0s icons:` line kept unchanged (22 names). The prune kept 23 files (the 22 declared
  plus the license text) and removed 5817, all undeclared files the whole-folder copy brought back;
  the shipped set is the same as at v1.90.0. No provenance split, no README credit change, no dead
  stub mirror, no README provenance line.
- **Adopted:** nothing. **Declined:** nothing filed (`03_DECISIONS.md`). **Unreached:** none.
- **Gate after the copy and the prune:** luacheck 0 warnings / 0 errors in 162 files; tests 1982
  passed, 0 failed, 1 skipped (the kit's diagnostics opt-out case, which does not apply to this addon).
  Largest own Lua file 1395 lines (cap 1500); no shipped function changed, so no CCN moves.
