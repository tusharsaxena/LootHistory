# Summary (LootHistory)

LibKa0s v1.61.0 -> v1.62.0 from the local tag; `tests/_kit` kit revision 27 -> 31; CLAUDE.md
provenance rolled. Options 25 -> 26, OptionsWidgets 31 -> 32, OptionsTabs 5 -> 6, and four new
files at minor 1 (OptionsRegistry, OptionsIds, OptionsIdList, OptionsCombat). No blocker, no
candidate, nothing adopted, nothing declined.

Gate after the copy and the `LIB_FILES` update (all through `ka0s-bounded`):

- tests: 961 passed, 0 failed, 0 skipped, 961 total (961 before)
- luacheck: 0 warnings / 0 errors in 70 files
- lizard (`-x ./libs/* -x ./tests/_kit/*`, CCN 15): no warnings
- largest authored file: `docs/smoke-tests.md` at 1465 lines; nothing over 1500
