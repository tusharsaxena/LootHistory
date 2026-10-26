# Re-cut 3: v1.78.0 at 585d40e (LootHistory)

Run by the 2026-10-25 skinning run (item `LH-RV4`) on branch `feat/2026-10-25-skinning`. After
`LH-RV3` vendored the tag at `65a23cb`, the local annotated tag v1.78.0 moved again, to `585d40e`
(LK-A4). It is still local and unpushed, and the version did not change. So the CLAUDE.md provenance
line stays `v1.78.0`, and the `LibKa0s icons:` line is unchanged.

The payload came from `git -C ../LibKa0s archive v1.78.0 LibKa0s testkit tools | tar -x -C <scratch>`.
It was copied whole over `libs/LibKa0s/` and `tests/_kit/`, then pruned with the tag's own
`tools/prune-icons.lua`: 16 icons declared, 17 files kept, 5,823 removed, the same set as before.
The tag was never checked out.

**What moved.** Outside the pruned `media/icons/`, only one file differs, and `tests/_kit/` is
byte-identical (kit revision stays 43):

- `SkinPaint.lua`, SkinPaint 2 -> 3 (LK-A4). The owner's smoke test crashed the client with a
  `STACK_OVERFLOW` when moving this addon from WoW Forever to WoW Midnight. The History search box's
  repaint handed the box back the anonymous font object that the client's EditBox answers
  `GetFontObject` with. Now a prior font object is recorded only when it is a named font that is not
  the target itself; any other target gets its face and shadow back by path.

**Contract blockers:** none. No member was added to a surface that a degradation stub mirrors, and
`test_surface_parity` stays green.

**Ripple:** `tests/test_libka0s.lua`. Its v1.78.0 case now pins SkinPaint 3; it was red first
against the SkinPaint 2 copy. Its header names the fourth re-cut, and the `LIB_FILES` load-list
comment reads SkinPaint 3. The test count does not change, so the README badge and
`docs/test-cases.md` stay as they are.

**Gates.** Both ran through the bounded runner:

- `luacheck .`: 0 warnings / 0 errors in 148 files.
- `lua tests/run.lua`: 1782 passed, 0 failed, 1 skipped, counted together with `LH-FX1`'s test-clock
  fix, which landed in its own commit.
