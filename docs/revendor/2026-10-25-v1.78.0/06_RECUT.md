# Re-cut: v1.78.0 at 7ec0e0a (LootHistory)

Run by the 2026-10-25 skinning run, leg 1 (item `LH-RV2`) on branch `feat/2026-10-25-skinning`.
The local annotated tag v1.78.0 moved twice after `LH-RV` vendored it at `fb7b7a3`: to `a3790f4`
(LK-A1) and to `7ec0e0a` (LK-A2). It is still local and unpushed, and the version did not change, so
the CLAUDE.md provenance line stays `v1.78.0` and the LibKa0s icons: line is unchanged. The payload
came from `git -C ../LibKa0s archive v1.78.0 LibKa0s testkit | tar -x -C <scratch>`. The tag was
never checked out.

**What moved.** Under `diff -r` against the vendored copy, outside the pruned `media/icons/`, only two
files differ, and `tests/_kit/` is byte-identical (kit revision stays 43):

- `Media.lua`, Media 6 -> 7 (LK-A1): `RegisterLSM` no longer offers a key LibSharedMedia already
  holds. LSM-3.0 checks the file before the key, so a host whose own folder lacks a newer key's art
  used to report "Attempt to register an invalid font" through `geterrorhandler()`. No new media key
  and no new icon.
- `SkinDefs.lua`, SkinDefs 4 -> 5 (LK-A2): nine Semantic tokens, the bind states (`sem.boundNone`,
  `sem.boundBoE`, `sem.boundBoP`, `sem.boundWarband`, `sem.boundWarbandUE`), Insights' split
  (`sem.boundBoPAlt`, `sem.boundBoEAlt`, `sem.boundNoneAlt`) and `sem.danger`. Ka0s Default keeps the
  addon's current pixels. LH-03 and LH-04 adopt them, each in its own item.

**Contract blockers:** none. No member was added to a surface a degradation stub mirrors, and
`test_surface_parity` stays green.

**Ripple:** `tests/test_libka0s.lua`, where the v1.78.0 case now pins Media 7 and SkinDefs 5 and its
header names the two re-cuts, and the v1.75.0 case's Media floor note reads 7. The test count does
not change, so the README badge and `docs/test-cases.md` stay as they are.

**Gates.** `luacheck .` (bounded): 0 warnings / 0 errors in 143 files. `lua tests/run.lua`
(bounded): 1748 passed, 0 failed, 1 skipped (`test_vendor_sync` green against the re-cut tag). No
authored `.lua` file above 1500 lines (the largest is `tests/test_browser.lua` at 1459).
