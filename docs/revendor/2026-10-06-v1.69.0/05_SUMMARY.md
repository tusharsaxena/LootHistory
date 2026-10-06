# Summary (LootHistory)

LibKa0s v1.68.1 -> v1.69.0 from the local annotated tag (`5949f4c`, tag object `aeea542`, via
`git archive`). One file added (`WidgetsLineChart.lua`, minor 1; Widgets key 12.1.4.1), no minor
moved, no floor rose. Kit revision 36 -> 37 (`mock_lines.lua`). Both payloads match the tag under
`diff -r`.

In the same commit: CLAUDE.md provenance line and the `docs/debug.md:14` stamp roll to v1.69.0;
`tests/test_libka0s.lua` gains the file in `LIB_FILES` and a v1.69.0 case.

Adopted: none yet (`lib.LineChart` is adopted by Task B2). Declined: none.

Gate: tests 1233 passed, 0 failed, 1 skipped (1234 total); luacheck 0 warnings / 0 errors in 104
files.
