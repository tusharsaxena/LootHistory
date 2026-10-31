Delta: LibKa0s v1.83.0 -> v1.84.0

Run in the multi-repo pass `docs/2026-10-31-FINDINGS_REMEDIATION/M2_LIBRARY_RELEASE.md` (Ka0sAddonsCommonTasks), step 7. Tag `v1.84.0` is local, at `e917ccd`.

## 3a. Claimed version

`grep -n '[Bb]undles' CLAUDE.md` gives line 58, v1.83.0. The last payload commit, `git log -1 --format=%H -- libs/LibKa0s tests/_kit`, is `1952c06` and its line names v1.83.0, so the two agree. Base v1.83.0.

## 3b. Actual version

The payload matches `git archive v1.83.0 LibKa0s testkit` under `diff -rq` apart from the pruned icons. Line and bytes agree.

## 3c. Per-file minors (only files that moved; `git show v1.84.0:LibKa0s/LibKa0s.xml` loop)

```
Schema.lua old: local MAJOR, MINOR = "LibKa0s-Schema-1.0", 2 new: local MAJOR, MINOR = "LibKa0s-Schema-1.0", 3
Charts.lua old:  new: local MAJOR, MINOR = "LibKa0s-Charts-1.0", 1
ChartsRender.lua old:  new: local RENDER_MINOR = 1
Skin.lua old: local MAJOR, MINOR = "LibKa0s-Skin-1.0", 10 new: local MAJOR, MINOR = "LibKa0s-Skin-1.0", 11
SkinOwnerTokens.lua old:  new: local TOKENS_MINOR = 1
SkinDefs.lua old: local DEFS_MINOR = 18 new: local DEFS_MINOR = 19
SkinDefsOthers.lua old:  new: local OTHERS_MINOR = 1
WidgetsDragHandle.lua old: local DRAG_MINOR = 8 new: local DRAG_MINOR = 10
DebugLogDiagnostics.lua old: local DIAG_MINOR = 5 new: local DIAG_MINOR = 6
Slash.lua old: local MAJOR, MINOR = "LibKa0s-Slash-1.0", 20 new: local MAJOR, MINOR = "LibKa0s-Slash-1.0", 21
Options.lua old: local MAJOR, MINOR = "LibKa0s-Options-1.0", 34 new: local MAJOR, MINOR = "LibKa0s-Options-1.0", 35
OptionsWidgets.lua old: local WIDGETS_MINOR = 38 new: local WIDGETS_MINOR = 40
OptionsFlow.lua old:  new: local FLOW_MINOR = 2
OptionsIds.lua old: local IDS_MINOR = 5 new: local IDS_MINOR = 6
OptionsIdSuggest.lua old:  new: local SUGGEST_MINOR = 1
OptionsTabs.lua old: local TABS_MINOR = 11 new: local TABS_MINOR = 13
OptionsTabbed.lua old:  new: local TABBED_MINOR = 2
OptionsCompose.lua old: local COMPOSE_MINOR = 14 new: local COMPOSE_MINOR = 15
OptionsSkinPicker.lua old: local PICKER_MINOR = 4 new: local PICKER_MINOR = 5
OptionsSkinPickerRows.lua old:  new: local ROWS_MINOR = 1
SimPanel.lua old: local SIM_PANEL_MINOR = 8 new: local SIM_PANEL_MINOR = 9
SimPanelRender.lua old:  new: local RENDER_MINOR = 1
```

No consumer skew: every file above is behind only because the tag is new. Kit revision 46 -> 47.

## 3e. Consumption map

No lookup of `LibKa0s-Charts-1.0` before this run. Adoption adds one, in `modules/AnalyticsCharts.lua`.

## 3f. Pairing

Both payloads move together in one commit, so the rule that a library re-vendor takes its kit is met by construction.

## 3g. Contract delta

Read `docs/api/Options` 34.4.38... -> 35.4.40..., the v1.84.0 CHANGELOG block and `docs/api/Widgets/version-17.3.10.5.5.2-docs.md`. In the Options document, the removed lines are only the version rows; all the rest is added. The peels are pure moves and the rest are additive.

**Blockers:** none. This addon has no `__Attach*` site and no `DragHandle` host. Pins the copy moves, which are not contract changes: the typed load list in `tests/test_libka0s.lua`, `O.PositionBlock` on the `settings/OptionsSetup.lua` stub.

## 3h. Unrecorded tags

v1.84.0 is the only new tag; v1.79.0 to v1.83.0 are in `docs/revendor/2026-10-31-v1.79.0-v1.83.0/`. No span bundle.

## 3i. Icon declaration

`CLAUDE.md:59` is kept unchanged. Hand lists have drifted before, and the owner's smoke is the backstop: a pruned icon draws blank and no suite sees it.

## 3j. Whole-folder icon tests

`tests/test_libka0s.lua:601` and `tests/test_mediasetup.lua:136` open declared names only. No blocker.
