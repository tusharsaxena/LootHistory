# Summary (LootHistory)

LibKa0s v1.65.0 -> v1.66.0 from the local tag `v1.66.0`; `tests/_kit` 34 -> 35; CLAUDE.md
provenance rolled in the same commit (GI-LH-RV). Widgets 11 -> 12, DebugLog 18 -> 19, Slash 18 -> 19,
OptionsWidgets 33 -> 34, OptionsTabs 7 -> 8, Perf 13 -> 14; new WidgetsReorder 1, SlashParse 1,
PerfSampler 1, PerfCommands 1. No blocker. No base correction. Span bundle
`2026-10-01-v1.64.0-v1.65.0/` written beside this one for the two unrecorded tags.

- Delivered on the re-vendor alone (class A): the sighted complexity suite (kit 35), wired as
  `test_lizard_sighted`; the four peels and DebugLog 19, which ask nothing of this addon.
- Adopted: none (the issue pass defers adoption to GI-LK-13).
- Declined: none. Unreached: B1 to B3 (`02_CANDIDATES.md`).
- Consumer pins moved: `tests/test_libka0s.lua` (28 -> 32 library files) and `tests/test_widgets.lua`
  (Widgets minor 12).
- New in-client check: PANEL-20, the AH Price reorder drag (`ReorderList` now loads from
  `WidgetsReorder.lua`).

Gate after the copy (all through `ka0s-bounded`):

- tests: 1019 passed, 0 failed, 1 skipped, 1020 total (1011 / 0 / 1, 1012 before; +8 are
  `test_lizard_sighted`'s cases)
- luacheck: 0 warnings / 0 errors in 74 files
- vendor parity: `diff -r` of both payloads against the tag, empty
- complexity, sighted (`bash tests/_kit/run-automated-tests.sh --suite complexity --no-bundle`):
  maxCcn 86, warnings 5, blindFiles 0. Above CCN 15: `Analytics.LayoutCharts` 86
  (`modules/Analytics.lua`), `E.InsightsCSV` 41 (`modules/Export.lua`), `refreshAuctionTable` 36
  (`settings/Panel.lua`), `Collector.OnChatMsgLoot` 20 (`modules/Collector.lua`), `browser` 18
  (`modules/Diagnostics.lua`). GI-LH-01 and GI-LH-02 bring them under 15.
