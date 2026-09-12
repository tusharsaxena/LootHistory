# 01 — Delta: LibKa0s v1.33.0 → v1.34.0

Run: 2026-09-13, the steps of `/wow-addon:revendor-libka0s` taken non-interactively by the
orchestrating session. No filing and no push. Target: this repo, branch `chore/2026-09-12-libka0s-1.33.0` @ `af81ba6`.

Source: the sibling checkout `../LibKa0s`, **tag `v1.34.0` (tag object `9165044` → commit `33bae81`)**,
extracted with `git -C ../LibKa0s archive v1.34.0 LibKa0s testkit | tar -x -C <scratch>/`, never the
working tree. The tag is local to `../LibKa0s` and not yet pushed. `tests/test_vendor_sync.lua`
compares against the tag the provenance line names, so the local tag is enough.

```
git -C ../LibKa0s log --oneline v1.33.0..v1.34.0
  33bae81 v1.34.0: release test record 20260913-002423
  b9d64c7 v1.34.0: string rows keep every word; Reset-all tooltip follows the reset; kit 19
```

## 3a — Claimed version, before this run

`CLAUDE.md:51`: Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) **v1.33.0** (MIT).

## 3b — Actual version, before this run

Core 7, DebugLog 12, Env 1, Item 1, Media 3, Options 17, OptionsScroll 3, OptionsWidgets 15,
OptionsCompose 4, Perf 11, PerfPanel 5, Pool 3, Slash 9, Widgets 9; kit revision 18. That is
v1.33.0's version block, so the line and the bytes agreed before the copy.

## 3c — Per-file minor delta

| File | v1.33.0 | v1.34.0 |
|---|---|---|
| Core | 7 | 7 |
| Env | 1 | 1 |
| Pool | 3 | 3 |
| Item | 1 | 1 |
| Media | 3 | 3 |
| Widgets | 9 | 9 |
| DebugLog | 12 | 12 |
| **Slash** | **9** | **10** |
| **Options** | **17** | **18** |
| OptionsWidgets | 15 | 15 |
| **OptionsCompose** | **4** | **5** |
| OptionsScroll | 3 | 3 |
| Perf | 11 | 11 |
| PerfPanel | 5 | 5 |
| **kit revision** | **18** | **19** |

No cross-major skew. The three moved files arrive in the same whole-folder copy, which matters for
the pair `Options.lua` 18 / `OptionsCompose.lua` 5: `lib:New` now hands its descriptor to
`lib.__AttachCompose(O, d)`, and a composer paired with an older shell reads the missing descriptor
as "no `resetProfile`".

## 3d — Both diffs

Payloads synced whole from the extracted tag (`rsync -a --delete`), so a file deleted upstream would
be deleted here. None was: the file lists match the tag's.

```
git status --short            # libs/LibKa0s/Options.lua, libs/LibKa0s/OptionsCompose.lua,
                              # libs/LibKa0s/Slash.lua, tests/_kit/README.md,
                              # tests/_kit/framework.lua, tests/_kit/mock_base.lua
diff -r --strip-trailing-cr ../LibKa0s/LibKa0s libs/LibKa0s   # content: empty
diff -r                     ../LibKa0s/LibKa0s libs/LibKa0s   # bytes:   empty
diff -r <scratch>/testkit tests/_kit                          # bytes:   empty
```

`tests/_kit/run-automated-tests.sh` keeps mode 100755.

## 3e — Consumption map

`LibKa0s-Options-1.0` (which carries `OptionsCompose.lua`) is looked up at `settings/OptionsSetup.lua:47` and `LibKa0s-Slash-1.0` at `settings/Slash.lua:168`.
Every moved file is consumed here. Unchanged from v1.33.0.

## 3f — Kit revision, and the pairing rule

`Kit.VERSION` moves 18 → 19 in the same commit as the v1.34.0 library payload, which is the pairing
the tag ships. Revision 19 is **not** the geometry flip: that stays its own revision, now "20 at the
earliest" (`tests/_kit/mock_base.lua`'s comment and the library's `docs/api/testkit/version-19-docs.md`).

## What moved (from the v1.34.0 changelog block)

- **`Slash.lua` minor 10: a `string` row takes the whole value.** `lib.ParseValue` gives a `string`
  row everything typed after the path, trimmed at both ends, with internal spacing kept verbatim.
  Through minor 9 it took the first whitespace token. With a `values` list the WHOLE string must
  match an entry, so a valid entry followed by more words (`always junk`) is now refused where
  minor 9 stored the entry. An empty or blank value is still refused with `expected a value`.
  `bool`, `number` and `color` rows parse exactly as before.
- **`Options.lua` minor 18 and `OptionsCompose.lua` minor 5: the *Reset all settings* tooltip.** It
  now follows the descriptor. No `resetProfile`: *"Restore every setting in this addon to its
  default."*, byte for byte the minor-4 text. `resetProfile`: *"Reset the current profile to its
  defaults. Your other profiles are not affected."* `resetProfile` plus the new optional
  `profilesPage = true`: the same, naming *Profiles → Reset Profile*. `profilesPage` is the one new
  descriptor field and changes nothing but that tooltip.
- **Kit revision 19.** The AceDB fake's `ResetProfile` fires `OnProfileReset` with the database
  alone, no key, as AceDB-3.0 does. `OnProfileChanged` and `OnProfileCopied` keep their keys.

No member is added, removed or renamed.

## Baseline, before the copy

`lua tests/run.lua`: 738 passed, 0 failed, 0 skipped, 738 total. `luacheck .`: 0 warnings / 0 errors
in 59 files.
