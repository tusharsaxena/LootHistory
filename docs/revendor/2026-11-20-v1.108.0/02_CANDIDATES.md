# 02 Candidates, LibKa0s v1.107.0 -> v1.108.0

Sources: `git -C ../LibKa0s log --oneline v1.107.0..v1.108.0`; LibKa0s CHANGELOG.md's v1.108.0 block, read in full; the Charts 3.2, Skin 18.1.28.10.20.19.2.1.19.4.9, Widgets 30.3.7.16.3.8.8.6.1.2 and testkit 58 documents under `docs/api/`.

**Class A, delivered on the copy alone:** the footer's shown-marks layout (nothing visible here: the History footer has no marks); the shared menu's secret-label guard and submenu arrow tint (no submenu here); kit revision 58's stricter `test_skin_switch` and `test_skin_values` checks.

**Class B, host change required:**
- The skin's gloss on a Charts owner's bar of data (U-4, Charts minor 3) reaches only the library's default `barFill`. This addon passes its own (`modules/AnalyticsCharts.lua:36`), so its Insights bars, ledger halves and Timeline flow columns take the gloss only through `NS.SkinBar`. Run item SD-SK-LH.
- `expect = "texture"` on a declared skin-switch surface (testkit 58). Run item SD-SK-LH (SD-SK-LH.1).
- `W.OwnerWarnings(owner, sink)` (Widgets 30): an optional debug report of owner-less widgets. Every widget here already passes `owner`; noted, not taken in this run.

**Class C, whole-module adoption:** none new in this range.
