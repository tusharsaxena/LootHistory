# 01 — Delta: LibKa0s v1.30.0 → v1.31.0

Every read below was taken on branch `fix/2026-09-12-triage` (at `27f8190`, which carries #30)
**before anything was copied**. The payload was extracted from the tag, not from the sibling's
working tree:

```sh
git -C ../LibKa0s archive v1.31.0 LibKa0s testkit | tar -x -C <scratch>/lh-b2/
git -C ../LibKa0s rev-parse v1.31.0^{commit}     # 30db4edeabfffe2ec64b9d638d6d8018b2c5d890
git -C ../LibKa0s tag --sort=-v:refname | head -1 # v1.31.0
```

The folder is `2026-09-12-v1.31.0` because `docs/revendor/2026-09-12/` already holds the frozen
v1.29.0 → v1.30.0 bundle taken the same day.

## 3a. Claimed version

```sh
grep -n '[Bb]undles' CLAUDE.md README.md
```

`CLAUDE.md:51`: `Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.30.0 (MIT) — …`.
`README.md` carries no provenance line.

## 3b. Actual version (per-file minors in `libs/LibKa0s/`)

```sh
grep -hoE 'local (MAJOR, )?(MINOR|WIDGETS_MINOR|SCROLL_MINOR|PANEL_MINOR) *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua
grep -n 'COMPOSE_MINOR =' libs/LibKa0s/OptionsCompose.lua
```

The line and the bytes agree: every minor is the one v1.30.0 shipped.

## 3c. Per-file minor delta

The file list is the tag's `LibKa0s/LibKa0s.xml`
(`grep -o 'file="[^"]*"' <scratch>/lh-b2/LibKa0s/LibKa0s.xml`), fourteen files.

| File | Constant | Addon (v1.30.0) | Tag v1.31.0 |
|---|---|---|---|
| `Core.lua` | `MINOR` | 7 | 7 |
| `Env.lua` | `MINOR` | 1 | 1 |
| `Pool.lua` | `MINOR` | 3 | 3 |
| `Item.lua` | `MINOR` | 1 | 1 |
| `Media.lua` | `MINOR` | 3 | 3 |
| `Widgets.lua` | `MINOR` | 9 | 9 |
| `DebugLog.lua` | `MINOR` | 12 | 12 |
| `Slash.lua` | `MINOR` | 7 | 7 |
| `Options.lua` | `MINOR` | 15 | 15 |
| `OptionsWidgets.lua` | `WIDGETS_MINOR` | 14 | **15** |
| `OptionsCompose.lua` | `COMPOSE_MINOR` | 3 | **4** |
| `OptionsScroll.lua` | `SCROLL_MINOR` | 3 | 3 |
| `Perf.lua` | `MINOR` | 10 | 10 |
| `PerfPanel.lua` | `PANEL_MINOR` | 5 | 5 |

Two files move, both forward. **No cross-major skew.**

## 3d. Both diffs

```sh
diff -rq --strip-trailing-cr <scratch>/lh-b2/LibKa0s libs/LibKa0s   # OptionsCompose.lua, OptionsWidgets.lua
diff -rq                     <scratch>/lh-b2/LibKa0s libs/LibKa0s   # the same two
diff -rq --strip-trailing-cr <scratch>/lh-b2/testkit tests/_kit     # README.md, framework.lua, mock_base.lua
diff -rq                     <scratch>/lh-b2/testkit tests/_kit     # the same three
```

- `libs/LibKa0s/`: content dirty in exactly the two files whose minors moved. That is the release,
  not a local fork: `git -C ../LibKa0s diff --stat v1.30.0 v1.31.0 -- LibKa0s testkit` names
  `LibKa0s/OptionsCompose.lua`, `LibKa0s/OptionsWidgets.lua`, `testkit/README.md`,
  `testkit/framework.lua` and `testkit/mock_base.lua`, and nothing else.
- `tests/_kit/`: content dirty in `README.md`, `framework.lua` and `mock_base.lua`, the kit moving
  from revision 16 to 17.
- Bytes and content name the same files, so there is no line-ending drift to renormalise.
- No `Only in <Addon>/…` line on either side, so nothing upstream removed survives here.

## 3e. Consumption map

```sh
grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v '/libs/' | grep -v '/tests/'
```

| Major | Lookup site |
|---|---|
| Core | `core/CoreSetup.lua:39` |
| Env | `core/EnvSetup.lua:41` |
| Pool | `core/PoolSetup.lua:22` |
| Item | `core/ItemSetup.lua:27` |
| Media | `core/MediaSetup.lua:57` |
| Widgets | `core/WidgetsSetup.lua:85` |
| DebugLog | `core/DebugLogSetup.lua:25` |
| Options | `settings/OptionsSetup.lua:47` |
| Slash | `settings/Slash.lua:136` |
| Perf | none: the `performance-§12` no-combat-path exemption, a register row in `docs/ARCHITECTURE.md`. Settled. |

The two moved files are Options' secondaries, which this addon consumes through
`settings/OptionsSetup.lua`. No composer (`O.BorderGroup`, `O.BarGroup`, …) is called anywhere in
`core/`, `modules/` or `settings/`; the only mentions are the degradation stub's no-op entries
(`settings/OptionsSetup.lua:113-114`).

## 3f. Kit revision and the pairing rule

```sh
grep -n 'Kit.VERSION =' <scratch>/lh-b2/testkit/framework.lua tests/_kit/framework.lua
```

Tag: `Kit.VERSION = 17`. Addon: `Kit.VERSION = 16`.

Pairing rule: a consumer on LibKa0s v1.9.0 or newer MUST take kit revision 11 or later in the same
commit. Both payloads are copied whole from one tag in one commit, so the rule holds by
construction, and it is why the two payloads move together.

The runner's recorded mode is unchanged at the tag (`git -C ../LibKa0s ls-tree v1.31.0
testkit/run-automated-tests.sh` → `100755`).

## Baseline, before the copy

```sh
lua tests/run.lua   # 722 passed, 0 failed, 0 skipped, 722 total
luacheck .          # 0 warnings / 0 errors in 59 files
```
