# 01 — Delta: LibKa0s v1.32.0 → v1.33.0

Run: 2026-09-12, the steps of `/wow-addon:revendor-libka0s` taken non-interactively by the
orchestrating session. No filing and no push. Target: this repo, branch `chore/2026-09-12-libka0s-1.33.0` @ `ee2c8ec`.

Source: the sibling checkout `../LibKa0s`, **tag `v1.33.0` (tag object `7d5e061` → commit `06ee368`)**,
extracted with `git -C ../LibKa0s archive v1.33.0 LibKa0s testkit | tar -x -C <scratch>/`, never the
working tree. The tag is local to `../LibKa0s` and not yet pushed. `tests/test_vendor_sync.lua`
compares against the tag the provenance line names, so the local tag is enough.

```
git -C ../LibKa0s log --oneline v1.32.0..v1.33.0
  06ee368 v1.33.0: release test record 20260912-214123
  25d59a9 v1.33.0: preload LSM fonts on first panel show; count docstrings; kit 18
  2bd4c56 docs(releasing): v1.32.0 is merged in all ten consumers
  0741fe6 Merge branch 'feat/2026-09-12-v1.32.0': LibKa0s v1.32.0 (bulk bracket)
  7a019a6 Merge branch 'feat/2026-09-12-v1.31.0': LibKa0s v1.31.0
  bf8ed91 v1.32.0 docs: Slash 8's bulkEnd row no longer calls count "rows actually written"
  6233e3e v1.32.0 docs: the reviewer's findings on the bulk bracket (post-tag, docs only)
```

## 3a — Claimed version, before this run

`CLAUDE.md:51`: Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) **v1.32.0** (MIT).

## 3b — Actual version, before this run

Core 7, DebugLog 12, Env 1, Item 1, Media 3, Options 16, OptionsScroll 3, OptionsWidgets 15,
OptionsCompose 4, Perf 11, PerfPanel 5, Pool 3, Slash 8, Widgets 9; kit revision 17. That is
v1.32.0's version block, so the line and the bytes agreed before the copy.

## 3c — Per-file minor delta

| File | v1.32.0 | v1.33.0 |
|---|---|---|
| Core | 7 | 7 |
| Env | 1 | 1 |
| Pool | 3 | 3 |
| Item | 1 | 1 |
| Media | 3 | 3 |
| Widgets | 9 | 9 |
| DebugLog | 12 | 12 |
| **Slash** | **8** | **9** |
| **Options** | **16** | **17** |
| OptionsWidgets | 15 | 15 |
| OptionsCompose | 4 | 4 |
| OptionsScroll | 3 | 3 |
| Perf | 11 | 11 |
| PerfPanel | 5 | 5 |
| **kit revision** | **17** | **18** |

No cross-major skew. Both moved files arrive in the same whole-folder copy.

## 3d — Both diffs

Payloads synced whole from the extracted tag (`rsync -a --delete`), so a file deleted upstream would
be deleted here. None was: the file lists match the tag's.

```
git status --short            # libs/LibKa0s/Options.lua, libs/LibKa0s/Slash.lua,
                              # tests/_kit/README.md, tests/_kit/framework.lua, tests/_kit/mock_base.lua
diff -r --strip-trailing-cr ../LibKa0s/LibKa0s libs/LibKa0s   # content: empty
diff -r                     ../LibKa0s/LibKa0s libs/LibKa0s   # bytes:   empty
diff -r <scratch>/testkit tests/_kit                          # bytes:   empty
```

`tests/_kit/run-automated-tests.sh` keeps mode 100755.

## 3e — Consumption map

`LibKa0s-Options-1.0` is looked up at `settings/OptionsSetup.lua:47` and `LibKa0s-Slash-1.0` at `settings/Slash.lua:168`.
Both moved majors are consumed here. Unchanged from v1.32.0.

## 3f — Kit revision, and the pairing rule

`Kit.VERSION` moves 17 → 18 in the same commit as the v1.33.0 library payload, which is the pairing
the tag ships.

## What moved (from the v1.33.0 changelog block)

- **`Options.lua` minor 17: every LSM font loaded on the first panel show.** One off-screen frame
  per session holds one FontString per distinct LSM font path, so an `LSM30_Font` dropdown no longer
  opens on blank rows. It runs from `SetRenderer`'s OnShow (after the combat refusal) and from an
  OnShow hook `O.CreatePanel` installs for a page with no renderer. It needs the descriptor's
  `getLSM`; with none it returns before building anything.
- **`Options.lua` minor 17 and `Slash.lua` minor 9: docstrings.** Five docstrings stop calling the
  bulk bracket's `count` the rows "actually written". No behavior moves.
- **Kit revision 18.** The AceDB fake's `CopyProfile` fires `OnProfileCopied` with the **source**
  profile's key as the third argument, as AceDB-3.0 does. Through revision 17 it passed the active
  profile to every callback.

No member or descriptor field is added, removed or renamed.

## Baseline, before the copy

`lua tests/run.lua`: 738 passed, 0 failed, 0 skipped, 738 total. `luacheck .`: 0 warnings / 0 errors
in 59 files.
