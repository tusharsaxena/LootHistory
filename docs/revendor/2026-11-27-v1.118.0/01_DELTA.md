Delta: LibKa0s v1.114.0 -> v1.118.0

Payload taken from the local tag: `git -C ../LibKa0s archive v1.118.0 LibKa0s testkit tools`. Run as M0.2 of
`docs/superpowers/plans/2026-11-27-tooltip-toasts-farm.md` (the owner asked for the re-vendor ahead of #34,
#38 and #39, and asked to be interviewed only when absolutely necessary).

## Step 0 pre-flight
Newest single-tag bundle `2026-11-25-v1.114.0`, line 1 `Delta: LibKa0s v1.113.0 -> v1.114.0`, which agrees
with the provenance before the commit that vendored v1.114.0. ok, no correction owed.

## 3a Base
- `grep -n '[Bb]undles' CLAUDE.md`: `CLAUDE.md:60: Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.114.0 (MIT).`
- `git log -1 --format=%H -- libs/LibKa0s tests/_kit`, its CLAUDE.md: v1.114.0. They agree.
- `diff -rq --strip-trailing-cr` of a v1.114.0 extract against `libs/LibKa0s` and `tests/_kit`: only the
  pruned `media/` subsets differ (payload-matches).
- `git -C ../LibKa0s diff --stat v1.114.0 v1.118.0 -- LibKa0s testkit`: 7 files, 877 insertions, 77 deletions
  (`ForeverDB.lua`, `Media.lua`, `media/icons/CREDITS.txt`, `media/icons/dash.tga`, `testkit/README.md`,
  `testkit/framework.lua`, `testkit/mock_foreverdb.lua`).

## 3b/3c Per-file minors that moved
```
ForeverDB.lua  old:1  new:4
Media.lua      old:13 new:14
```
No new file in `LibKa0s.xml`, no `NEEDS_*` floor rose, no cross-major skew.

## 3d Diffs
After the copy, before the prune, `diff -r --strip-trailing-cr` of the extract against both payloads printed
nothing. After the prune only `Only in <extract>/LibKa0s/media/...` lines for undeclared icons and sounds.

## 3e Consumption map
Unchanged from the v1.114.0 bundle. `LibKa0s-ForeverDB-1.0` has no lookup site (Loot History dropped its
ForeverDB features in v1.115.0's Item Search run); it ships as part of the whole-folder payload.

## 3f Kit
`Kit.VERSION` 62 -> 65 (`tests/_kit/framework.lua:20`): the extended `mock_foreverdb.lua`. Both payloads move
in one commit.

## 3g Contract delta
- `Media` 13 -> 14 adds the `dash` icon to the catalog. No member changed shape.
- `ForeverDB` 1 -> 4 is additive and not consumed here.

**Blockers, fixed in the re-vendor commit** (tests only):
- `tests/test_libka0s.lua`: the v1.105.0 case's exact `Media, 13` pin and the v1.114.0 case's exact
  `ForeverDB, 1` and `KIT_VERSION, 62` pins became floors; a new v1.118.0 case pins ForeverDB 4, Media 14 and
  kit 65.
- That took the suite to 1510 lines, past layout-§1's cap. Its per-tag release cases (v1.71.0 onward) moved
  verbatim to `tests/test_libka0s_releases.lua`, registered right after it in `tests/run.lua`.

## 3h Span
No vendored tag is unrecorded: v1.115.0 to v1.117.0 were never vendored here.

## 3i Icon declaration
`CLAUDE.md:61`, kept as it was. `lua <extract>/tools/prune-icons.lua .` kept the 23 declared icons and removed
the rest of the catalog and the 362 sound files (no `LibKa0s sounds:` line). The tag's
`media/icons/CREDITS.txt` now ships (the prune keeps it). Credits unchanged: Open Iconic is the only set
shipped. No provenance split.

## 3j Whole-folder icon tests
Same read sites as v1.114.0; no blocker.
