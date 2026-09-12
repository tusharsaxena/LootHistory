# 01 — Delta: LibKa0s v1.31.0 → v1.32.0

Every read below was taken on branch `fix/2026-09-12-triage` (at `a206709`) **before anything was
copied**. The payload was extracted from the tag, not from the sibling's working tree:

```sh
git -C ../LibKa0s archive v1.32.0 LibKa0s testkit | tar -x -C <scratch>/lh-v132/
git -C ../LibKa0s rev-parse v1.32.0^{commit}     # e18dd12b98bc745afbe4d81c44ecbf5061848341
git -C ../LibKa0s tag --sort=-v:refname | head -1 # v1.32.0
```

`v1.32.0` is a local tag in `../LibKa0s` and has not been pushed. The folder is
`2026-09-12-v1.32.0` because `docs/revendor/2026-09-12/` and `2026-09-12-v1.31.0/` already hold the
two earlier re-vendors taken the same day.

## 3a. Claimed version

`CLAUDE.md:51`: `Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.31.0 (MIT) — …`.
`README.md` carries no provenance line.

## 3b. Actual version (per-file minors in `libs/LibKa0s/`)

```sh
grep -hoE 'local (MAJOR, )?(MINOR|WIDGETS_MINOR|SCROLL_MINOR|PANEL_MINOR) *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua
grep -n 'COMPOSE_MINOR =' libs/LibKa0s/OptionsCompose.lua
```

The line and the bytes agree: every minor is the one the re-cut v1.31.0 (`e7e1962`) shipped.

## 3c. Per-file minor delta

| File | Constant | Addon (v1.31.0) | Tag v1.32.0 |
|---|---|---|---|
| `Core.lua` | `MINOR` | 7 | 7 |
| `Env.lua` | `MINOR` | 1 | 1 |
| `Pool.lua` | `MINOR` | 3 | 3 |
| `Item.lua` | `MINOR` | 1 | 1 |
| `Media.lua` | `MINOR` | 3 | 3 |
| `Widgets.lua` | `MINOR` | 9 | 9 |
| `DebugLog.lua` | `MINOR` | 12 | 12 |
| `Slash.lua` | `MINOR` | 7 | **8** |
| `Options.lua` | `MINOR` | 15 | **16** |
| `OptionsWidgets.lua` | `WIDGETS_MINOR` | 15 | 15 |
| `OptionsCompose.lua` | `COMPOSE_MINOR` | 4 | 4 |
| `OptionsScroll.lua` | `SCROLL_MINOR` | 3 | 3 |
| `Perf.lua` | `MINOR` | 11 | 11 |
| `PerfPanel.lua` | `PANEL_MINOR` | 5 | 5 |

Two files move, both forward. **No cross-major skew.**

## 3d. Both diffs

```sh
git -C ../LibKa0s diff --stat v1.31.0 v1.32.0 -- LibKa0s testkit
#   LibKa0s/Options.lua | 120 ++++++++++----
#   LibKa0s/Slash.lua   |  54 +++++-
diff -rq --strip-trailing-cr <scratch>/lh-v132/LibKa0s libs/LibKa0s   # Options.lua, Slash.lua
diff -rq                     <scratch>/lh-v132/LibKa0s libs/LibKa0s   # the same two
diff -rq --strip-trailing-cr <scratch>/lh-v132/testkit tests/_kit     # empty
diff -rq                     <scratch>/lh-v132/testkit tests/_kit     # empty
```

- `libs/LibKa0s/`: content dirty in exactly the two files whose minors moved, which is the release.
- `tests/_kit/`: byte-identical. The kit stays at revision 17 (`Kit.VERSION = 17` on both sides).
- Bytes and content name the same files, so there is no line-ending drift. After the copy both moved
  files count CR == LF (1114 / 1114 and 652 / 652).
- No `Only in …` line on either side.

## 3e. Consumption map

| Major | Lookup site | Moves at v1.32.0 |
|---|---|---|
| Core | `core/CoreSetup.lua:39` | no |
| Env | `core/EnvSetup.lua:41` | no |
| Pool | `core/PoolSetup.lua:22` | no |
| Item | `core/ItemSetup.lua:27` | no |
| Media | `core/MediaSetup.lua:57` | no |
| Widgets | `core/WidgetsSetup.lua:85` | no |
| DebugLog | `core/DebugLogSetup.lua:25` | no |
| Options | `settings/OptionsSetup.lua:47` | **yes**, minor 16 |
| Slash | `settings/Slash.lua:148` | **yes**, minor 8 |
| Perf | none (the `performance-§12` register row) | no |

Both moved majors are consumed. What they add is two optional descriptor fields, `bulkBegin` and
`bulkEnd`. **No instance member is added, removed or renamed** (CHANGELOG v1.32.0: "Nothing is
removed or renamed, no member is added"), so neither degradation stub needs a new no-op, and
`tests/test_surface_parity.lua` confirms it on the copy.

## 3f. Kit revision and the pairing rule

Tag: `Kit.VERSION = 17`. Addon: `Kit.VERSION = 17`. Both payloads are copied whole from one tag in
one commit, so the pairing rule holds by construction. The runner's recorded mode stays `100755`
(`git -C ../LibKa0s ls-tree v1.32.0 testkit/run-automated-tests.sh`; `git ls-files -s
tests/_kit/run-automated-tests.sh`).

## Baseline, before the copy

```sh
lua tests/run.lua   # 727 passed, 0 failed, 0 skipped, 727 total
luacheck .          # 0 warnings / 0 errors in 59 files
```
