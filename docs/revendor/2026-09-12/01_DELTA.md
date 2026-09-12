# 01 — Delta: LibKa0s v1.29.0 → v1.30.0

Every read below was taken on branch `chore/libka0s-1.30.0-arch5` (off `master` at `1881d1c`)
**before anything was copied**. The payload was extracted from the tag, not from the sibling's
working tree:

```sh
git -C ../LibKa0s archive v1.30.0 LibKa0s testkit | tar -x -C <scratch>/lh-v1.30.0/
git -C ../LibKa0s rev-parse v1.30.0^{commit}     # e369e0fc99e22063200893d15c68237072222ed3
git -C ../LibKa0s tag --sort=-v:refname | head -1 # v1.30.0
```

The tag sits on the library's `fix/kit-27-30` branch and is not merged to its `master`. That does
not matter here: `tests/test_vendor_sync.lua` resolves the **tag** the provenance line names.

## 3a. Claimed version

```sh
grep -n '[Bb]undles' CLAUDE.md
```

`CLAUDE.md:51` — `Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.29.0 (MIT) — …`

## 3b. Actual version (per-file minors in `libs/LibKa0s/`)

```sh
grep -hoE 'local (MAJOR, )?(MINOR|WIDGETS_MINOR|SCROLL_MINOR|PANEL_MINOR|COMPOSE_MINOR) *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua
```

The line and the bytes agree: every minor is the one v1.29.0 shipped.

## 3c. Per-file minor delta

The file list is the tag's `LibKa0s/LibKa0s.xml`
(`git -C ../LibKa0s show v1.30.0:LibKa0s/LibKa0s.xml | grep -oE 'file="[^"]+"'`), fourteen files.
Sorted minor lists hash identically on both sides (`… | sort | md5sum` →
`8e57c3d4bea777d21a05f1a39d2e929d` for the addon copy and for the tag).

| File | Constant | Addon (v1.29.0) | Tag v1.30.0 |
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
| `OptionsWidgets.lua` | `WIDGETS_MINOR` | 14 | 14 |
| `OptionsCompose.lua` | `COMPOSE_MINOR` | 3 | 3 |
| `OptionsScroll.lua` | `SCROLL_MINOR` | 3 | 3 |
| `Perf.lua` | `MINOR` | 10 | 10 |
| `PerfPanel.lua` | `PANEL_MINOR` | 5 | 5 |

No file moved. **No cross-major skew.**

## 3d. Both diffs

```sh
diff -r --strip-trailing-cr <scratch>/LibKa0s libs/LibKa0s   # empty
diff -rq                    <scratch>/LibKa0s libs/LibKa0s   # empty
diff -r --strip-trailing-cr <scratch>/testkit tests/_kit     # four files differ
diff -rq                    <scratch>/testkit tests/_kit     # the same four
```

- `libs/LibKa0s/`: content and bytes both clean. Nothing to copy that is not already here.
- `tests/_kit/`: **content dirty** in `README.md`, `framework.lua`, `mock_base.lua` and
  `vendor_sync.lua`. That is the kit moving from revision 15 to 16, not a local fork
  (`git -C ../LibKa0s diff --stat v1.29.0 v1.30.0 -- LibKa0s testkit` names the same four files and
  nothing under `LibKa0s/`).
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

No major moved in this release, so the map changes nothing about what can be adopted.

## 3f. Kit revision and the pairing rule

```sh
grep -n 'Kit.VERSION' <scratch>/testkit/framework.lua tests/_kit/framework.lua
```

Tag: `Kit.VERSION = 16`. Addon: `Kit.VERSION = 15`. The whole release is the kit revision.

Pairing rule: a consumer on LibKa0s v1.9.0 or newer MUST take kit revision 11 or later in the same
commit. Both payloads are copied whole from one tag in one commit, so the rule holds by
construction. It is why the two payloads move together even when, as here, only one of them
changed.

The runner's recorded mode, which kit 16's new vendor-sync case asserts, is already right:
`git ls-files -s -- tests/_kit/run-automated-tests.sh` → `100755`.
