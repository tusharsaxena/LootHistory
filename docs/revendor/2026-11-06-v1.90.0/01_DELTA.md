Delta: LibKa0s v1.89.0 -> v1.90.0

Item `SF1-RV-LH` of Ka0sAddonsCommonTasks `docs/2026-11-06-REVENDOR_LIBKA0S_V1_89/SF1_SMOKE_FEEDBACK.md`.
Written before the copy. The payload is taken from the tag, never the working tree:

```sh
git -C ../LibKa0s archive v1.90.0 LibKa0s testkit tools | tar -x -C /tmp/claude-1000/rv-lh-v190
git -C ../LibKa0s rev-parse 'v1.90.0^{commit}'   # 4485b8f589077b47e61f261405b3008bc4d81838
git -C ../LibKa0s ls-remote --tags origin v1.90.0  # (nothing: the tag is local, cut by SF1-L3)
```

The tag is local and not yet pushed. This is a new tag for this addon (its provenance names v1.89.0),
so it is a new re-vendor with a new bundle, not a refresh.

## Step 0: pre-flight (this addon)

```
LootHistory  2026-11-06-v1.89.0  base v1.85.0  vendored-before v1.85.0@1a8ad3d  ok
```

No base correction is owed.

## 3a: claimed version, and the base

```sh
grep -n '[Bb]undles' CLAUDE.md
# 58:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.89.0 (MIT).
c=$(git log -1 --format=%H -- libs/LibKa0s tests/_kit)   # 1a8ad3d V89-LH: Re-vendor LibKa0s v1.89.0
git show "$c:CLAUDE.md" | grep -oE 'Bundles \[LibKa0s\]\([^)]*\) v[0-9]+\.[0-9]+\.[0-9]+'
# Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.89.0
```

The line and the last payload commit agree: **base v1.89.0**.

```sh
git -C ../LibKa0s log --oneline v1.89.0..v1.90.0   # 4 commits past the v1.89.0 merge line:
# 7d42f4e SF1-L1, b9f7651 SF1-L2, 4ac9f3c SF1-L3, 4485b8f SF1-L3 (plus the harvest merge e809ca3)
git -C ../LibKa0s diff --stat v1.89.0 v1.90.0 | tail -1
# 37 files changed, 35494 insertions(+), 94 deletions(-)
```

## 3b: actual version

`grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua` gives every file at
its v1.89.0 minor (Core 15, Widgets 23, Skin 16, ...). The claim and the bytes agree.

## 3c: per-file minor delta (the tag's `LibKa0s.xml` loop)

Only these rows move; every other file is at the same minor on both sides. No file is new.

| File | old | new |
|---|---|---|
| `Core.lua` (`LibKa0s-Core-1.0`) | 15 | 16 |
| `Widgets.lua` (`LibKa0s-Widgets-1.0`) | 23 | 24 |
| `WidgetsAutocomplete.lua` (`AUTOCOMPLETE_MINOR`) | 7 | 8 |
| `Skin.lua` (`LibKa0s-Skin-1.0`) | 16 | 17 |
| `SkinPaint.lua` (`PAINT_MINOR`) | 18 | 19 |
| `SkinPaintExtras.lua` (`EXTRAS_MINOR`) | 17 | 18 |
| `OptionsAppearance.lua` (`APPEARANCE_MINOR`) | 6 | 7 |

No consumer file is behind the others: no cross-major skew.

## 3d: both diffs (before the copy)

```sh
diff -rq --strip-trailing-cr <tag>/LibKa0s libs/LibKa0s | grep -v 'media/icons'   # 7 lines
diff -rq                     <tag>/LibKa0s libs/LibKa0s | grep -v 'media/icons'   # the same 7
diff -rq                     <tag>/testkit tests/_kit                             # empty
```

Library: the seven files above differ. Kit: identical (revision 51 both sides). Content and bytes agree,
so there is no line-ending drift. No `Only in libs/LibKa0s` line: nothing removed upstream. The
`Only in <tag>/LibKa0s/media/icons` lines are the undeclared icons.

## 3e: consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v /libs/ | grep -v /tests/`:
Bus, Charts, Compat, Core, DebugLog, Env, IconBrowser, Item, Launcher, Lifecycle, Media, Options, Perf,
Pool, Schema, Sim, Skin, Slash, Widgets. All four majors that moved (Core, Widgets, Skin, Options) are
consumed here.

## 3f: kit revision

```sh
grep -n 'Kit.VERSION' <tag>/testkit/framework.lua tests/_kit/framework.lua
# <tag>: Kit.VERSION = 51     tests/_kit: Kit.VERSION = 51
```

Kit unchanged at 51. Both payloads still move together in this commit (the pairing rule, satisfied by
the whole-folder copy).

## 3g: contract delta

Majors moved and consumed: Core, Widgets, Skin, Options.

- **Core 15 -> 16** (`docs/api/Core/version-16-docs.md:23-35`): four internal `__` members
  (`__PixelSize`, `__WatchPixels`, `__OnPixelScale`, `__PixelBackdrop`); "No public member is added,
  removed or renamed" and "A host calls none of them". This addon calls none.
- **Widgets 23 -> 24, WidgetsAutocomplete 7 -> 8** (`docs/api/Widgets/version-24.5.12.6.8.5-docs.md:19-27`):
  "No member, option or row field is added, removed or renamed"; `GetBackdrop()` answers the table as
  given; "What a host owes: nothing". This addon's `W.Dropdown`, `W.SearchBox` and `W.Autocomplete`
  sites take the pixel-exact edge on the copy.
- **Skin 16 -> 17, SkinPaint 18 -> 19, SkinPaintExtras 17 -> 18**
  (`docs/api/Skin/version-17.1.27.8.19.18.17.4.9-docs.md:19-36`): `RegisterOwner`'s optional
  `keepScope`; one that does not name it keeps the previous behavior. This addon's
  `core/SkinSetup.lua:792` registration is unchanged and correct.
- **OptionsAppearance 6 -> 7** (CHANGELOG v1.90.0, *A copy leaves a host's Scope alone*):
  `lib.__copySkinTo` skips the Scope only for a `keepScope` target. No host member.
- `grep -rn '__Attach[A-Za-z]*' . --include='*.lua' --exclude-dir=libs --exclude-dir=_kit`: no site.

No contract blocker.

## Blockers (fixed in the re-vendor commit)

The addon's own pins, not contracts:

- `tests/test_libka0s.lua`'s v1.85.0 case pins `Core == 15`, `Skin == 16`, `SkinPaint == 18`,
  `SkinPaintExtras == 17`, `WidgetsAutocomplete == 7`, `OptionsAppearance == 6`; its v1.89.0 case pins
  `Widgets == 23`. These relax to floors, and a v1.90.0 case pins the new minors.
- `tests/test_widgets.lua`'s adoption pin (`lib.MODULES.Widgets == 23`) moves to 24, with the minor's
  note beside the earlier ones.

## 3h: tags vendored and never recorded

The skill's listing (horizon `2026-08-25`, both payload paths plus the `CLAUDE.md` rolls) prints
nothing. **No span bundle.**

## 3i: the icon declaration

```sh
grep -n 'LibKa0s icons:' CLAUDE.md
# 59:LibKa0s icons: ban, chat, chevron-down, chevron-right, chevron-up, circle-check, clear, close, confirm, copy, eye, graph, info, lock, move, reset, segment, settings, sort-down, sort-up, spreadsheet, volume-high.
```

The next non-blank line after the provenance line (58). **Kept as is** (decided: the run keeps every
addon's icons line). v1.90.0 adds no library-drawn icon name. The gate (`tests/test_mediasetup.lua`'s
drawn-vs-declared cases) and the owner's in-client smoke are the backstop; hand lists have drifted
before (KickCD `tests/test_mediasetup.lua:28`, WhatGroup `tests/test_mediasetup.lua:19`), and a pruned
icon resolves to a path and draws blank.

## 3j: tests that assume the whole icon folder

```sh
grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v '/_kit/'
```

`tests/test_libka0s.lua:620` opens `info.tga` (declared); `tests/test_mediasetup.lua:106` reads the
catalog's names, and `:139` opens declared names only. None assumes the whole folder. No blocker.

## Dead stub mirrors

No `__` member was removed in this range. `grep -rn '__releaseChrome'` finds only history comments.
Nothing to remove.
