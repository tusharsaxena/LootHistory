Delta: LibKa0s v1.109.0 -> v1.110.0

Payload taken from the local tag, never the sibling tree: `git -C ../LibKa0s archive v1.110.0 LibKa0s testkit tools` (tag commit `e97bf187`; `git -C ../LibKa0s ls-remote --tags origin v1.110.0` prints nothing, so the tag is not on origin yet). Run under Ka0sAddonsCommonTasks `docs/2026-11-22-LIBKA0S_101_CONTAINER_READER/`, item K101-LH-01: copy, provenance, declaration and prune only, with no adoption interview and no issue filing (the run's adoption is its own manifest row, K101-LH-02).

## Step 0 pre-flight
Newest single-tag bundle `2026-11-20-v1.108.0`, line 1 `Delta: LibKa0s v1.107.0 -> v1.108.0`; the provenance line before the commit that vendored v1.108.0 (`06ba07a`) named v1.107.0. ok, no correction owed.

## 3a Base
- `grep -n '[Bb]undles' CLAUDE.md` at HEAD (`60ddc12`): `CLAUDE.md:59: Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.109.0 (MIT).`
- `git log -1 --format=%h -- libs/LibKa0s tests/_kit` is `c48777f` ("FU-RV-LH: Re-copy Compat.lua (minor 5) and Sim.lua (minor 4) from the re-cut v1.109.0"), whose CLAUDE.md names v1.109.0. They agree.
- `diff -rq` of a v1.109.0 extract against `libs/LibKa0s` (outside the pruned `media/`) and `tests/_kit` printed nothing (payload-matches).
- `git -C ../LibKa0s log --oneline v1.109.0..v1.110.0`: 6 commits (K101-LK-01, K101-LK-02, K101-LK-REV, K101-LK-REL x2, and the v1.109.0 merge). `git -C ../LibKa0s diff --stat v1.109.0 v1.110.0 -- LibKa0s testkit`: 4 files changed (`LibKa0s/Compat.lua`, `testkit/README.md`, `testkit/framework.lua`, `testkit/mock_client.lua`), 302 insertions, 8 deletions.

## 3b/3c Per-file minors that moved
The constants HEAD carried matched v1.109.0's. Against the tag's `LibKa0s.xml` (3c's loop, only the rows that moved):
```
Compat.lua  old: local MAJOR, MINOR = "LibKa0s-Compat-1.0", 5  new: local MAJOR, MINOR = "LibKa0s-Compat-1.0", 6
```
No file added, no `NEEDS_*` floor raised, no cross-major skew.

## 3d Diffs
After the copy and before the prune, `diff -r --strip-trailing-cr` and `diff -r` of the extract against `libs/LibKa0s` and `tests/_kit` printed nothing. After the prune the only differences are `Only in <extract>/LibKa0s/media/...` lines for undeclared icons and sounds.

## 3e Consumption map
`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua'` outside `libs/` and `tests/`: Compat is looked up at `core/Compat.lua:172` (`GetSpellName` only) and `core/CompatClient.lua:26` (the client helpers). The other majors are as the v1.108.0 bundle lists them; none moved here.

## 3f Kit
`Kit.VERSION` 59 -> 60 (`tests/_kit/framework.lua:20`): the Forever profile gains the 27-member `Enum.BagIndex` and `C_Bank.CanViewBank`. Both payloads move together in one commit, as the pairing rule has required since v1.9.0.

## 3g Contract delta
`diff` of `docs/api/Compat/version-5-docs.md` against `version-6-docs.md` (both at v1.110.0): rows 18-23 are new members (`ContainerGroups`, `CanViewCharacterBank`, `NumPurchasedBankTabs`, `BankerKind`, `UnreadyBankContainers`, `CONTAINER_PATTERNS_BY_CLIENT`); no existing row changed its sentence, and no existing surface gained a MUST. The document's *What a host owes* (version-6-docs.md, "What changed at this version"): nothing until it adopts; a suite pinning `Compat` at 5 re-pins at 6; a host calling `Kit.assertSurfaceParity(NS.Compat, "LibKa0s-Compat-1.0", ignore)` fails parity on the six new members until it wires them or lists them in `ignore`.

This addon hands Compat no host member (no `__Attach*` site touches Compat). Its own `Compat.CanViewCharacterBank` (`core/Compat.lua:857`) and `Compat.NumPurchasedCharacterBankTabs` are host shims, not wired from the library, so the copy changes none of their answers.

**Blockers, fixed in the re-vendor commit:**
- `tests/test_libka0s.lua`: the v1.105.0 case's exact `Compat, 5` pin and the v1.109.0 case's `KIT_VERSION, 59` pin become floors, and a v1.110.0 case pins Compat 6 and kit revision 60.
- `tests/test_surface_parity.lua`: the by-name Compat parity case lists the six new members in `ignore`, with a comment naming K101-LH-02, which wires them and removes them from the list.

## 3i Icon declaration
`grep -n 'LibKa0s icons:' CLAUDE.md`: `CLAUDE.md:60`, the next non-blank line under the provenance line. Kept as it was. Prune: `lua <extract>/tools/prune-icons.lua .` reported 23 icons declared and removed the rest of the catalog and the 362 sound files again (no `LibKa0s sounds:` line); `git status` shows no change under `libs/LibKa0s/media/`. Credits unchanged: Open Iconic is still the only set shipped. No provenance split.

## 3j Whole-folder icon tests
`grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v /_kit/`: 4 hits, unchanged since v1.105.0, all declared-name assertions. None.

## 3h Span
v1.109.0 was vendored (`5a6fe46`, `c48777f`) with no bundle. Recorded in the span bundle `2026-11-22-v1.109.0-v1.109.0`, written in this run.

## Dead stub mirrors
`grep -rn '__releaseChrome' . --include='*.lua' --exclude-dir=libs --exclude-dir=_kit`: two history comments in `tests/`, no mirror. None.
