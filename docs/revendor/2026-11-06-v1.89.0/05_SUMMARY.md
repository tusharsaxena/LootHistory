# Summary

- **Tag:** v1.85.0 -> v1.89.0, base from the provenance line (`CLAUDE.md:58`), agreeing with the last
  payload commit `4dede61`. Kit 50 -> 51. Minors moved: Toast 3 -> 4, Widgets 22 -> 23,
  DebugLogDiagnostics 6 -> 7, and the new major IconBrowser (IconBrowserSources 1, IconBrowserWindow 1,
  IconBrowser 1). Table in `01_DELTA.md`. No span bundle, no base correction, no refresh.
- **For free (class A):** kit 51's unregister guard, the diagnostics report naming IconBrowser, and
  `W.CloseMenu` closing every cascade level, with this addon's dropdowns and strip menu unchanged.
- **Contract blockers:** none. **Pin blockers**, fixed in the re-vendor commit: `tests/test_libka0s.lua`'s
  `LIB_FILES` gains the three IconBrowser files (XML order), its v1.85.0 exact pins on DebugLogDiagnostics,
  Toast, Widgets and the kit relax to floors, and a new v1.89.0 case pins the new minors;
  `tests/test_widgets.lua`'s adoption pin moves to Widgets 23.
- **Icons:** `LibKa0s icons:` line kept unchanged (22 names). The prune kept 23 files (the 22 declared
  plus the license text) and removed 5817, all of them undeclared files the whole-folder copy had
  brought back; the shipped set is the same as at v1.85.0. No provenance split, no README credit change,
  no dead stub mirror, no README provenance line.
- **Adopted:** nothing (the plan names no adoption for this addon). **Declined:** nothing filed;
  IconBrowser settled, the menu and Toast fields not applicable (`03_DECISIONS.md`).
- **Look changes for this host:** none expected. `Widgets.lua` moved, but this addon's menus are flat.
- **Gate after the copy and the prune:** luacheck 0 warnings / 0 errors in 162 files; tests 1980 passed,
  0 failed, 1 skipped (the kit's diagnostics opt-out case, which does not apply to this addon). The first run
  after the copy was 1979 passed, 1 failed: the Widgets adoption pin, fixed above.
- **Left for sync-docs:** `docs/ARCHITECTURE.md` and `docs/testing.md` still name kit revision 50, and the
  generated `docs/test-cases.md` does not yet list the new v1.89.0 case.
