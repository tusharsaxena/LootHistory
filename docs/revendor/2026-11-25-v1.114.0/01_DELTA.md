Delta: LibKa0s v1.113.0 -> v1.114.0

Payload taken from the local tag, never the sibling tree: `git -C ../LibKa0s archive v1.114.0 LibKa0s testkit tools` (tag commit `2eaa8fc9`; `git -C ../LibKa0s ls-remote --tags origin v1.114.0` prints nothing, so the tag is not on origin yet). Run under Ka0sAddonsCommonTasks `docs/2026-11-25-SEEDS_AND_FOREVERDB/`, item SF-LH-02 (its `03_SPEC.md` §9): copy, provenance, declaration and prune, with no adoption interview and no issue filing. The run pre-decides the one adoption, `LibKa0s-ForeverDB-1.0`, in the same item.

## Step 0 pre-flight
Newest single-tag bundle `2026-11-22-v1.110.0`, line 1 `Delta: LibKa0s v1.109.0 -> v1.110.0`; the provenance line before the commit that vendored v1.110.0 (`88403f5`) named v1.109.0. ok, no correction owed.

## 3a Base
- `grep -n '[Bb]undles' CLAUDE.md` at HEAD (`1c15fd7`): `CLAUDE.md:60: Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.113.0 (MIT).`
- `git log -1 --format=%h -- libs/LibKa0s tests/_kit` is `69ad523` ("FB2-LH-02: ... (the re-cut LibKa0s v1.113.0)"), whose CLAUDE.md names v1.113.0. They agree.
- `diff -rq` of a v1.113.0 extract (commit `557d7da5`) against `libs/LibKa0s` (outside the pruned `media/`) and `tests/_kit` printed nothing (payload-matches).
- `git -C ../LibKa0s log --oneline v1.113.0..v1.114.0`: 8 commits (SF-LK-01 x2, SF-LK-02 x2, SF-LK-REL x3, and the v1.112.0/v1.113.0 merge). `git -C ../LibKa0s diff --stat v1.113.0 v1.114.0 -- LibKa0s testkit`: 7 files changed (`LibKa0s/DebugLogDiagnostics.lua`, `LibKa0s/ForeverDB.lua` new, `LibKa0s/LibKa0s.xml`, `testkit/README.md`, `testkit/client_globals_forever.lua`, `testkit/framework.lua`, `testkit/mock_foreverdb.lua` new), 785 insertions, 48 deletions.

## 3b/3c Per-file minors that moved
The constants HEAD carried matched v1.113.0's. Against the tag's `LibKa0s.xml` (3c's loop, only the rows that moved):
```
ForeverDB.lua  old:   new: local MAJOR, MINOR = "LibKa0s-ForeverDB-1.0", 1
DebugLogDiagnostics.lua  old: local DIAG_MINOR = 11  new: local DIAG_MINOR = 12
```
`ForeverDB.lua` is new in this range, loaded after `Item.lua`. No `NEEDS_*` floor rose, and there is no cross-major skew.

## 3d Diffs
After the copy and before the prune, `diff -r --strip-trailing-cr` and `diff -r` of the extract against `libs/LibKa0s` and `tests/_kit` printed nothing. After the prune the only differences are `Only in <extract>/LibKa0s/media/...` lines for undeclared icons and sounds.

## 3e Consumption map
`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua'` outside `libs/` and `tests/`: the majors are as the v1.110.0 bundle lists them. `LibKa0s-ForeverDB-1.0` has no lookup site before this item; SF-LH-02 adds one (`core/ForeverDBSetup.lua`).

## 3f Kit
`Kit.VERSION` 60 -> 62 (`tests/_kit/framework.lua:20`). Revision 61 adds the opt-in `mock_foreverdb.lua`; revision 62 regenerates the Forever name set (`client_globals_forever.lua`, Ketho `forever` at `e230342`, 10545 -> 10559 names). Both payloads move together in one commit, as the pairing rule has required since v1.9.0.

## 3g Contract delta
- `DebugLog`: `docs/api/DebugLog/version-23.11.1.5-docs.md` against `version-23.12.1.5-docs.md`: the report's `LibKa0s running:` line names ForeverDB, and the identity section gains one `ForeverDB:` line read through `Status()`, which never loads the data addon. No member changed and no MUST was added. This addon's `modules/Diagnostics.lua` passes the library no member whose call site moved.
- `ForeverDB`: a new major, so there is nothing to diff.

**Blockers, fixed in the re-vendor commit** (`tests/test_libka0s.lua` only):
- `LIB_FILES` gains `libs/LibKa0s/ForeverDB.lua` after `Item.lua`, in XML order; without it the count case fails (86 against 87).
- The v1.105.0 case's exact `DebugLogDiagnostics, 11` pin and the exact `KIT_VERSION, 60` pins of the v1.110.0, v1.112.0 and v1.113.0 cases become floors. A new v1.114.0 case pins ForeverDB 1, DebugLogDiagnostics 12 and kit revision 62.

## 3h Span
v1.112.0 and v1.113.0 were vendored with no bundle: span bundle `2026-11-25-v1.112.0-v1.113.0`.

## 3i Icon declaration
`grep -n 'LibKa0s icons:' CLAUDE.md`: `CLAUDE.md:61`, the next non-blank line under the provenance line. Kept as it was; ForeverDB draws no icon. Prune: `lua <extract>/tools/prune-icons.lua .` reported 23 icons declared and removed the rest of the catalog and the 362 sound files again (no `LibKa0s sounds:` line); `git status` shows no change under `libs/LibKa0s/media/`. Credits unchanged: Open Iconic is still the only set shipped. No provenance split.

## 3j Whole-folder icon tests
`grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v '/_kit/'`: `tests/test_mediasetup.lua:110,143` and `tests/test_libka0s.lua:657` read declared names only, as before. No blocker.
