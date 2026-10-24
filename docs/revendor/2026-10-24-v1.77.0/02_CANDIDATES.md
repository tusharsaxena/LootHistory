# Candidates (LootHistory, LibKa0s v1.76.0 -> v1.77.0)

The run's owner scope (Ka0sAddonsCommonTasks `docs/2026-10-24-KEYBINDS_LAYOUT_STRATA/inputs/OWNER_SCOPE.md`)
and its `plan-data/items.json` decide the adoptions: the Keybindings tab is LH-KB (item 015) and the
strata changes are LH-ZS (item 030, the ids in `plan-data/accepted.json`). The item spec for LH-RV
says not to interview and to record every other candidate as deferred (run 2026-10-24), with
nothing filed. So no interview ran, nothing is declined and no issue is filed. Adoptions land in
their own items, after this re-vendor.

## Class A: delivered on the copy, nothing to adopt

- **Toplevel tool windows (Core 12, DebugLog 21, PerfPanel 9, SimPanel 6).** The debug console
  (`/lh debug`), the perf panel and the `/lh sim` step panel are DIALOG, clamped and now toplevel, so
  a click raises each among its DIALOG peers, and each re-raises a shown StaticPopup on show (a
  *Reset all settings* confirmation is not buried). Evidence: tag `docs/api/Core/version-12-docs.md:24`;
  CHANGELOG v1.77.0, "Core minor 12, DebugLog minor 21, PerfPanel minor 9 and SimPanel minor 6".
  Reaches LOO-S05 of the strata review.
- **Clamped popups (Widgets 15, WidgetsAutocomplete 3).** The filter bar's dropdown menus
  (`NS.MakeDropdown`) and the Search box's suggestion list (`NS.MakeAutocomplete`,
  `modules/BrowserFilterBar.lua:445`) stay on screen when the History window sits at a screen edge.
  Evidence: tag `docs/api/Widgets/version-15.1.5.3.3-docs.md:14`; CHANGELOG, "Widgets minor 15 and
  WidgetsAutocomplete minor 3".
- **The IdList suggestion list closes at combat start (OptionsIds 3, OptionsCombat 2)**, on the
  Filters tab's id lists. CHANGELOG, "OptionsIds minor 3 and OptionsCombat minor 2".
- **Kit 42**, paired with the payload.

## Class B: host change required

| Candidate | Evidence | Files it would touch | Blast radius | Decision |
|---|---|---|---|---|
| `O.KeybindingsTab` / `O.KeybindRows` / `O.KEYBINDS_UNCHANGED` (OptionsKeybinds 2-3), the General > Keybindings tab | tag `docs/api/Options/version-30.2.34.3.5.9.2.8.4.2.1.3-docs.md:60-72`, :1539-1541; CHANGELOG, "OptionsKeybinds minor 2" | `Bindings.xml`, `core/LauncherSetup.lua` (`NS.BINDINGS`), `settings/Schema.lua` / the General page tabs, locales, tests, docs | additive: a new tab | adopt, **LH-KB** (OWNER_SCOPE 015) |
| Kit `Kit.assertBindingsXml`, `Kit.keybindThroughTab`, `mock_bindings.lua` | tag `docs/api/testkit/version-42-docs.md` | `tests/` | additive: new suites | adopt, **LH-KB** |
| Kit `mock_layers.lua` (frame-layer recorder) | tag `docs/api/testkit/version-42-docs.md` | `tests/` | additive | with **LH-ZS** if its strata changes want it (item 030) |
| `O.StrataTooltip(values, strings)` (OptionsCompose 8) | Options doc :86-92; CHANGELOG, "OptionsCompose minor 8" | none today: this addon offers no player strata row | additive | deferred (run 2026-10-24); not in the run's planned consumers for this addon |
| DragHandle `spec.level`, `spec.ignoreParentAlpha`, `handle:ApplyLevel()` (WidgetsDragHandle 5) | Widgets doc :45-49; CHANGELOG, "WidgetsDragHandle minor 5" | none today: this addon builds no DragHandle | additive | deferred (run 2026-10-24) |
| `Core.RaiseStaticPopups()` for a host window (Core 12) | Core doc :24 | `modules/Browser.lua`, `modules/Export.lua` if a host window wanted it | additive | deferred (run 2026-10-24); the strata ids accepted for this addon (LOO-Z01..Z06, Z08) do not call it |

## Not candidates here

- **`LibKa0s-Glow-1.0`:** still unconsumed; this addon draws no glow (settled at v1.75.0).
- **The Options stub's four members** are a blocker (01_DELTA 3g), fixed in the re-vendor commit, not
  a candidate.
