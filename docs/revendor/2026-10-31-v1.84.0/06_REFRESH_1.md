# Refresh 1: the v1.84.0 re-cut

Tag `v1.84.0` moved before it was pushed: `git -C ../LibKa0s ls-remote --tags origin v1.84.0` prints nothing. So this is a refresh under the re-vendor command, and it adds this file instead of a new folder. The other files here stay as written, and line 1 of `01_DELTA.md` stands.

- **Old commit:** `e917ccd833768b8fe68e9542d3fbf6b38cab6659`
- **New commit:** `7a8bc0f133ed118d2c79c7c5288b97964e24fae5`
- **Why:** the owner's ruling of 2026-11-01, `Ka0sMedia_*` is the only media picker (LibKa0s#73).

## Per-file minors between the two commits

| File | Old | New |
|---|---|---|
| `SkinAce.lua` | 5 | 6 |
| `Options.lua` | 35 | 36 |
| `OptionsWidgets.lua` | 40 | 41 |
| `OptionsCompose.lua` | 15 | 16 |
| `OptionsScroll.lua` | 9 | 10 |
| `OptionsMedia.lua` | 1 | 2 |

Every other file keeps its minor. The test kit is byte-identical at both commits, revision 47.

## This addon

- **Blockers:** none. Authored code names no `LSM30_*` type, `AceGUIWidgetLSMlists` or `__PatchLSM30Border`, and this repo vendors no AceGUI-3.0-SharedMediaWidgets. LibSharedMedia-3.0 stays, because the pickers read it.
- **Free:** the Skin tab's Font and Texture rows were already `Ka0sMedia_*` pickers, through `lib.__newMediaRow`. This addon draws no border row.
- **Icons:** `CLAUDE.md` is unchanged. The prune kept 19 files and removed 5821.
- **Consumer pins:** `tests/test_libka0s.lua`, the v1.84.0 case takes the new minors and the earlier cases relax to `>=`.
- **Gate:** `lua tests/run.lua` 1841 passed, 0 failed, 1 skipped; `ka0s-bounded luacheck .` 0 warnings, 0 errors in 159 files.
