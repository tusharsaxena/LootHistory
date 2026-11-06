# Summary

- **Tag:** v1.89.0 -> v1.90.0 (local tag, `4485b8f`), base from the provenance line (`CLAUDE.md:58`),
  agreeing with the last payload commit `1a8ad3d`. Kit unchanged at 51. Minors moved: Core 15 -> 16,
  Widgets 23 -> 24, WidgetsAutocomplete 7 -> 8, Skin 16 -> 17, SkinPaint 18 -> 19,
  SkinPaintExtras 17 -> 18, OptionsAppearance 6 -> 7. Table in `01_DELTA.md`. No span bundle, no base
  correction, no refresh file.
- **For free (class A):** every edge of the library's dropdowns, search box, menus and autocomplete
  list is one physical pixel at any UI scale and position (SF1-L1); a skin copy from this addon leaves
  a `keepScope` owner's Scope alone (SF1-L2).
- **Contract blockers:** none. **Pin blockers**, fixed in the re-vendor commit:
  `tests/test_libka0s.lua`'s v1.85.0 exact pins on Core, Skin, SkinPaint, SkinPaintExtras,
  WidgetsAutocomplete and OptionsAppearance, and its v1.89.0 pin on Widgets, relax to floors, and a new
  v1.90.0 case pins the new minors and kit 51; `tests/test_widgets.lua`'s adoption pin moves to
  Widgets 24.
- **Icons:** `LibKa0s icons:` line kept unchanged (22 names). The prune kept 23 files (the 22 declared
  plus the license text) and removed 5817, all of them undeclared files the whole-folder copy brought
  back; the shipped set is the same as at v1.89.0. No provenance split, no README credit change, no
  dead stub mirror, no README provenance line.
- **Adopted:** nothing. **Declined:** nothing filed; `keepScope` not applicable (`03_DECISIONS.md`).
- **Look changes for this host:** the library controls' edges are pinned to one physical pixel. This
  addon was the reference look in the owner's smoke, so no visible change is expected; the owner's
  in-client smoke is the check.
- **Gate after the copy and the prune:** luacheck 0 warnings / 0 errors in 162 files; tests 1981
  passed, 0 failed, 1 skipped (the kit's diagnostics opt-out case, which does not apply to this addon).
  Largest own file 1395 lines (cap 1500); no shipped function changed, so no CCN moves.
