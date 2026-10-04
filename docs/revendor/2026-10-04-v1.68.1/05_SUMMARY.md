# Summary (LootHistory)

LibKa0s v1.68.0 -> v1.68.1 from the pushed annotated tag (`9000cbd`, tag object `9fb7956`, via
`git archive`). The base comes from the CLAUDE.md provenance line and matches the payload bytes, so
there is no base correction and no span bundle is owed. No library file moved: all 32 LibStub
constants print the same old and new, no file was added or removed and no floor rose. The kit moves
from revision 35 to 36 (`framework.lua`, `run-automated-tests.sh`, `test_eol.lua`). No contract
blocker (3g).

In the same commit as both payloads:

- the CLAUDE.md provenance line rolls v1.68.0 -> v1.68.1;
- `docs/debug.md:14`'s "is the vendored set, from LibKa0s v1.68.0" stamp rolls to v1.68.1, as it
  did with the v1.68.0 re-vendor (DebugLog 19 / DebugLogDiagnostics 2 / DebugLogGates 1 are
  unchanged).

No prose here names the kit revision this repo *holds*, so nothing moves 35 -> 36 under
`docs/api/testkit/version-36-docs.md:59-60`. Every "kit revision 35" left in the live tree names the
revision the sighted complexity suite *arrived* in, and revision 36 adds nothing to that suite:
`docs/testing.md:121` and `:252`, `modules/Analytics.lua:283` and `tests/run.lua:119`. They stay.

- **Delivered free (class A):** kit revision 36's renamed `RESULTS.md` lead-in, on the next
  automated-test run.
- **Adoption candidates:** zero (rename-only release; no surface added). Interview skipped.
  `Perf` stays declined, settled (`performance-§12` exemption).
- **Adopted:** none. **Declined:** none, so no issue filed. **Unreached:** none.

Gate after the copy:

- tests (`ka0s-bounded lua tests/run.lua`): 1049 passed, 0 failed, 1 skipped, 1050 total,
  unchanged. Both vendor-sync cases are green on the rolled line ("libs/LibKa0s is the LibKa0s
  release CLAUDE.md says this addon bundles", "tests/_kit is the test kit that shipped with that
  release"). `lua tests/run.lua --list` matches `docs/test-cases.md`, so the inventory and the
  README badge stay.
- luacheck (`ka0s-bounded luacheck .`): 0 warnings / 0 errors in 80 files (`libs/` and
  `tests/_kit/` excluded by `.luacheckrc`; no host Lua changed).
- both payloads `diff -r` clean against the tag after the copy, with and without
  `--strip-trailing-cr`; `tests/_kit/run-automated-tests.sh` stays mode 100755.
