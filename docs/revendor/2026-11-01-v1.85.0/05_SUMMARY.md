# Summary

- **Tag:** v1.84.0 -> v1.85.0, base from the provenance line. Kit 47 -> 49. Per-file minors in `01_DELTA.md`. No span bundle, no base correction, no refresh.
- **For free:** see class A in `02_CANDIDATES.md`.
- **Blockers:** facade and Options stub members, and the minor pins; resolved in the re-vendor commit, with `tests/test_mediasetup.lua`'s drawn-marks list.
- **Icons:** adds `chevron-up, move, reset, volume-high`; all Open Iconic, whose credit stays. No provenance split. No dead stub mirrors.
- **Adopted:** by the plan's FS-LH-FIX commit. **Declined:** nothing.
- **Look changes for this host (releasing.md, Step 5):** `SimPanel.lua`, `SimPanelRender.lua` and `Widgets.lua` moved, in the look only. `/lh sim`'s Steps title band is 30 high, an owned tooltip title takes `gtip.title`, and an owned strip's icon takes `icon.tint`. Scenarios and test-mode data are unchanged; re-look at the next release.
- **Gate at the copy:** 1842 passed, 0 failed, 1 skipped; luacheck 0/0.
