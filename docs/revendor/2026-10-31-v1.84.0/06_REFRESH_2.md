# Refresh 2: the second v1.84.0 re-cut

Tag `v1.84.0` moved again before it was pushed: `git -C ../LibKa0s ls-remote --tags origin v1.84.0` prints nothing. So this is a refresh under the re-vendor command, and it adds this file instead of a new folder. The other files here stay as written, and line 1 of `01_DELTA.md` stands.

- **Old commit:** `7a8bc0f133ed118d2c79c7c5288b97964e24fae5`
- **New commit:** `b5229b876e803768322fb4d8c66be69f01c8e4a1`
- **Why:** the owner's ruling of 2026-11-01, `lib.__PatchLSM30Border` goes entirely, with no stub.

## Per-file minors between the two commits

| File | Old | New |
|---|---|---|
| `Options.lua` | 36 | 37 |
| `OptionsDrawer.lua` | 3 | 4 |
| `OptionsMedia.lua` | 2 | 3 |

Every other file keeps its minor. The test kit is byte-identical at both commits, revision 47.

## This addon

- **Blockers:** none. Authored code and tests never called `__PatchLSM30Border`, so there was no call or test to remove, and no stub or guard was added.
- **Icons:** `CLAUDE.md` is unchanged. The prune kept 19 files and removed 5821.
- **Consumer pins:** `tests/test_libka0s.lua`, the v1.84.0 case takes Options 37 and OptionsMedia 3 and now pins OptionsDrawer 4. The v1.82.0 OptionsDrawer pin relaxes to `>=`.
- **Gate:** `lua tests/run.lua` 1841 passed, 0 failed, 1 skipped; `ka0s-bounded luacheck .` 0 warnings, 0 errors in 159 files.
