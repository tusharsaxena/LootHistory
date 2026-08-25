# 01 — Delta: LootHistory vs LibKa0s v1.15.0

Run date: 2026-08-25. Library checkout: `../LibKa0s` (working tree clean; `master` is two
documentation-only commits ahead of the newest tag, so `v1.15.0` is the current payload).

Resolved tag — `git -C ../LibKa0s tag --sort=-v:refname | head -1` → **v1.15.0**.
Payload extracted from the tag, not the working tree:
`git -C ../LibKa0s archive v1.15.0 LibKa0s testkit | tar -x -C <scratch>/`.

## 3a. Claimed version

```sh
grep -in 'bundles' LootHistory/CLAUDE.md
```

> Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.15.0 (MIT) — the Ka0s-owned shared

## 3b. Actual version — the vendored minors

```sh
grep -hoE 'local +(MAJOR, )?[A-Z_]*MINOR *= *("[^"]+", *)?[0-9]+' LootHistory/libs/LibKa0s/*.lua
```

The claim and the bytes agree. The file list below is read from the tag's
`LibKa0s/LibKa0s.xml`, not from a table in the spec.

| File | Constant | Vendored | v1.15.0 | Delta |
|---|---|---|---|---|
| `Core.lua` | `MINOR` | 6 | 6 | — |
| `Env.lua` | `MINOR` | 1 | 1 | — |
| `Pool.lua` | `MINOR` | 1 | 1 | — |
| `Item.lua` | `MINOR` | 1 | 1 | — |
| `Media.lua` | `MINOR` | 3 | 3 | — |
| `Widgets.lua` | `MINOR` | 6 | 6 | — |
| `DebugLog.lua` | `MINOR` | 11 | 11 | — |
| `Slash.lua` | `MINOR` | 7 | 7 | — |
| `Options.lua` | `MINOR` | 8 | 8 | — |
| `OptionsWidgets.lua` | `WIDGETS_MINOR` | 7 | 7 | — |
| `OptionsScroll.lua` | `SCROLL_MINOR` | 3 | 3 | — |
| `Perf.lua` | `MINOR` | 7 | 7 | — |
| `PerfPanel.lua` | `PANEL_MINOR` | 4 | 4 | — |

## 3c. Cross-major skew

**None.** Every shipped file is at the tag's minor. There is no file on which this
consumer is behind, so there is no capability the payload advertises and this copy
does not carry.

## 3d. Both diffs, both directions

```sh
diff -r --strip-trailing-cr <scratch>/LibKa0s LootHistory/libs/LibKa0s   # 0 lines
diff -r                     <scratch>/LibKa0s LootHistory/libs/LibKa0s   # 0 lines
diff -r --strip-trailing-cr <scratch>/testkit LootHistory/tests/_kit     # 0 lines
diff -r                     <scratch>/testkit LootHistory/tests/_kit     # 0 lines
```

Content clean **and** bytes clean, on both payloads. Nothing has forked, no line-ending
drift, and no `Only in` line — so no file removed upstream survives here.

## 3e. Consumption map

```sh
grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' LootHistory --include='*.lua' | grep -v '/libs/' | grep -v '/tests/'
```

- `LootHistory/core/CoreSetup.lua:39` — Core
- `LootHistory/core/DebugLogSetup.lua:25` — DebugLog
- `LootHistory/core/EnvSetup.lua:41` — Env
- `LootHistory/core/ItemSetup.lua:27` — Item
- `LootHistory/core/MediaSetup.lua:57` — Media
- `LootHistory/core/PoolSetup.lua:22` — Pool
- `LootHistory/core/WidgetsSetup.lua:79` — Widgets
- `LootHistory/settings/OptionsSetup.lua:37` — Options
- `LootHistory/settings/Slash.lua:104` — Slash

Majors present in the payload with **no lookup anywhere in this addon**: `Perf`.

## 3f. Kit revision and the pairing rule

```sh
grep -n 'Kit.VERSION' <scratch>/testkit/framework.lua LootHistory/tests/_kit/framework.lua
```

Both read `Kit.VERSION = 12`. The pairing rule — a consumer on v1.9.0 or newer must
carry kit revision 11 or later in the same commit, because `vendor_sync.lua` before
revision 11 listed one directory level and line-ending-normalised everything, which
misreads `media` as a file and mangles any binary containing `0D 0A` — is satisfied.

## Verdict

**The delta is empty.** Same tag, both payloads byte-identical, kit revision paired.
No copy was made, the provenance line was not touched, and nothing was committed.

Confirmed independently by the addon's own gate: `tests/test_vendor_sync.lua` passes
both of its assertions inside a full green run.

| Gate | Command | Result |
|---|---|---|
| Lint | `luacheck .` | 0 warnings / 0 errors in 28 files |
| Tests | `lua tests/run.lua` | 644 passed, 0 failed, 0 skipped |

Neither was run as a post-copy gate — there was no copy. They are recorded because a
green vendor-sync assertion is the addon's own witness to the empty delta above.
