# Re-cut 2: v1.78.0 at 65a23cb (LootHistory)

Run by the 2026-10-25 skinning run, leg 1 (item `LH-RV3`) on branch `feat/2026-10-25-skinning`.
After `LH-RV2` vendored the tag at `7ec0e0a`, the local annotated tag v1.78.0 moved once more, to
`65a23cb` (LK-A3). It is still local and unpushed, and the version did not change, so the CLAUDE.md
provenance line stays `v1.78.0` and the `LibKa0s icons:` line is unchanged. The payload came from
`git -C ../LibKa0s archive v1.78.0 LibKa0s testkit | tar -x -C <scratch>`, copied whole over
`libs/LibKa0s/` and `tests/_kit/`, then pruned with the tag's own `tools/prune-icons.lua` (16 icons
declared, 17 files kept, 5,823 removed, the same set as before). The tag was never checked out.

**What moved.** Under `diff -r` against the vendored copy, outside the pruned `media/icons/`, only
one file differs, and `tests/_kit/` is byte-identical (kit revision stays 43):

- `SkinDefs.lua`, SkinDefs 5 -> 6 (LK-A3): eleven tokens for the rest of LootHistory's constants,
  each where no older token held the exact value: `text.value`, `text.bodyAlt`, `text.subtle`,
  `text.highlight`, `gtip.value`, `gtip.subtle`, `icon.dim`, `sem.goodAlt`, `sem.badAlt`,
  `sem.warbandAlt` and `sem.unknown`. Ka0s Default keeps the addon's current pixels; the dark skins
  inherit them, Azeroth sets the window ones in ink, and no skin darkens a gtip one. LH-04 and the
  later skinning items adopt them, each in its own item.

**Contract blockers:** none. No member was added to a surface a degradation stub mirrors, and
`test_surface_parity` stays green.

**Ripple:** `tests/test_libka0s.lua`, where the v1.78.0 case now pins SkinDefs 6 (red first against
the SkinDefs 5 copy, together with `test_vendor_sync`), its header names the third re-cut, and the
`LIB_FILES` load-list comment reads SkinDefs 6. The test count does not change, so the README badge
and `docs/test-cases.md` stay as they are.

**Gates.** `luacheck .` (bounded): 0 warnings / 0 errors in 144 files. `lua tests/run.lua`
(bounded): 1755 passed, 0 failed, 1 skipped (`test_vendor_sync` green against the re-cut tag). No
authored `.lua` file above 1500 lines (the largest is `tests/test_browser.lua` at 1459).
