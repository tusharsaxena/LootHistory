# Decisions (LootHistory)

- No adoption in this item: the release offers no candidate, and the candidate-adoption interview is
  out of scope for the sweep (`Ka0sAddonsCommonTasks/docs/2026-09-26-AUTOMATED_TESTS_SWEEP/`, item
  LH-ATS-RV).
- `tests/test_libka0s.lua`'s explicit `LIB_FILES` list gains the four new files in XML order
  (`OptionsRegistry.lua` after `Options.lua`, `OptionsIds.lua` and `OptionsIdList.lua` after
  `OptionsWidgets.lua`, `OptionsCombat.lua` after `OptionsTabs.lua`), so the count case against
  `LibKa0s.xml` stays green.
- The library-absent stub in `settings/OptionsSetup.lua` needs nothing: no new public member.
- `docs/test-cases.md` regenerated with `lua tests/run.lua --list`; it does not change (no case added
  or removed).
- Left for the sweep's doc sync (LH-ATS-SD): line citations into `Options.lua` and
  `OptionsWidgets.lua` in `docs/settings-panel.md`, `docs/common-tasks.md`, `settings/Panel.lua`
  comments, `tests/panel_support.lua` and `tests/test_panel_filters.lua`. Several point into code
  that now lives in `OptionsRegistry.lua`, `OptionsIds.lua` or `OptionsIdList.lua`, and some were
  already stale before this copy.
