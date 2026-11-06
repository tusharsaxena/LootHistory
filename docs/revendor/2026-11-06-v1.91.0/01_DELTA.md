Delta: LibKa0s v1.90.0 -> v1.91.0

Item `FU-RV-LH` of Ka0sAddonsCommonTasks `docs/2026-11-06-FOLLOWUPS_V1_91/00_PLAN.md`.
Written before the copy. The payload is taken from the tag, never the working tree:

```sh
git -C ../LibKa0s archive v1.91.0 LibKa0s testkit tools | tar -x -C /tmp/claude-1000/fu-rv-lh.jWvH
git -C ../LibKa0s rev-parse 'v1.91.0^{commit}'   # 55bfbb47180ad0b8eb53c8c5277ea7176ab42c36
git -C ../LibKa0s ls-remote --tags origin v1.91.0  # (nothing: the tag is local, cut by FU-L3)
```

The tag is local and not yet pushed. This is a new tag for this addon (its provenance names v1.90.0),
so it is a new re-vendor with a new bundle, not a refresh.

## Step 0: pre-flight

**Skipped.** The installed skill's Step 0 roster regex (`\]\(\.\./\.\./[A-Za-z]+/\)`) expects markdown
links, but `../WowAddonStandards/standards/ADDONS.md` writes `` `../../<Folder>/` ``, so it matches no
addon; and its `tag_at` helper arrives with `"$1"` / `"$2:CLAUDE.md"` substituted by the command's
arguments. Both are fixed upstream by this run's `FU-DC1` (dev-copilot 2.7.1). The previous bundle
(`2026-11-06-v1.90.0`) states base v1.89.0, which 3a's history agrees with (`1a8ad3d V89-LH` rolled
the line to v1.89.0, `bba6e74 SF1-RV-LH` to v1.90.0). No base correction is owed.

## 3a: claimed version, and the base

```sh
grep -n '[Bb]undles' CLAUDE.md
# 58:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.90.0 (MIT).
c=$(git log -1 --format=%H -- libs/LibKa0s tests/_kit)   # 10b0042 SF2-RV-LH: Refresh LibKa0s v1.90.0
git show "$c:CLAUDE.md" | grep -oE 'Bundles \[LibKa0s\]\([^)]*\) v[0-9]+\.[0-9]+\.[0-9]+'
# Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.90.0
```

The line and the last payload commit agree: **base v1.90.0**.

```sh
git -C ../LibKa0s log --oneline v1.90.0..v1.91.0
# 55bfbb4 FU-L3, 1938837 FU-L3, 3f7be30 FU-L2 (test_toast), acc9640 FU-L2 (SkinPaintExtras),
# c1ed261 FU-L2 (Widgets), d72dc4a FU-L2 (Core), 55d3b0f FU-L1 (line chart), plus the v1.90.0 merge lines
git -C ../LibKa0s diff --stat v1.90.0 v1.91.0 | tail -1
# 62 files changed, 30753 insertions(+), 1835 deletions(-)
```

## 3b: actual version

`grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua` gives every file
at its v1.90.0 minor (Core 16, Widgets 25, WidgetsLineChart 6, SkinPaintExtras 18, ...). The claim and
the bytes agree.

## 3c: per-file minor delta (the tag's `LibKa0s.xml` loop)

Only these rows move; every other file is at the same minor on both sides.

| File | old | new |
|---|---|---|
| `Core.lua` (`LibKa0s-Core-1.0`) | 16 | 17 |
| `CorePixel.lua` (`PIXEL_MINOR`) | (new) | 1 |
| `SkinPaintExtras.lua` (`EXTRAS_MINOR`) | 18 | 19 |
| `SkinPaintHud.lua` (`HUD_MINOR`) | (new) | 1 |
| `SkinAceConfirm.lua` (`CONFIRM_MINOR`) | (new) | 1 |
| `Widgets.lua` (`LibKa0s-Widgets-1.0`) | 25 | 26 |
| `WidgetsDropdown.lua` (`DROPDOWN_MINOR`) | (new) | 1 |
| `WidgetsLineChart.lua` (`CHART_MINOR`) | 6 | 7 |

Four files are new, each a peel of the file listed above it. No consumer file is behind the others:
no cross-major skew.

## 3d: both diffs (before the copy)

```sh
diff -rq --strip-trailing-cr <tag>/LibKa0s libs/LibKa0s | grep -v 'media/icons'   # 9 lines
diff -rq --strip-trailing-cr <tag>/testkit tests/_kit                             # empty
```

Library: `Core.lua`, `LibKa0s.xml`, `SkinPaintExtras.lua`, `Widgets.lua` and `WidgetsLineChart.lua`
differ, and `CorePixel.lua`, `SkinAceConfirm.lua`, `SkinPaintHud.lua` and `WidgetsDropdown.lua` are only
in the tag. Kit: identical (revision 51 both sides). No `Only in libs/LibKa0s` line: nothing removed
upstream. The `Only in <tag>/LibKa0s/media/icons` lines are the undeclared icons.

## 3e: consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v /libs/ | grep -v /tests/`:
Bus, Charts, Compat, Core, DebugLog, Env, Item, Launcher, Lifecycle, Media, Options, Perf, Pool,
Schema, Sim, Skin, Slash, Widgets. The three majors that moved (Core, Widgets, Skin) are consumed here.

## 3f: kit revision

```sh
grep -n 'Kit.VERSION' <tag>/testkit/framework.lua tests/_kit/framework.lua
# <tag>: Kit.VERSION = 51     tests/_kit: Kit.VERSION = 51
```

Kit unchanged at 51. Both payloads still move together in this commit (the pairing rule, satisfied by
the whole-folder copy).

## 3g: contract delta

Majors moved and consumed: Core, Widgets, Skin.

- **Core 16 -> 17, CorePixel 1** (`docs/api/Core/version-17.1-docs.md`): a pure move of the pixel
  edges section (`__PixelSize`, `__OnPixelScale`, `__WatchPixels`, `__PixelBackdrop`,
  `__RefreshPixelBackdrops`); "No public member is added, removed or renamed". This addon calls none.
- **Widgets 25 -> 26, WidgetsDropdown 1** (`docs/api/Widgets/version-26.1.6.13.7.8.5-docs.md`, CHANGELOG
  v1.91.0 *The band files peeled*): `lib.Dropdown`, `lib.ContextMenu`, `lib.CloseMenu` move to the new
  file under the same names. No member moves; this addon's `W.Dropdown` / `W.CloseMenu` sites are
  unchanged.
- **WidgetsLineChart 6 -> 7** (`docs/api/Widgets/version-26.1.6.13.7.8.5-docs.md:25-33`): the axis,
  grid, markers and crosshair are one physical pixel, and "A host's `series[i].thickness` is read as
  physical pixels too". **This addon passes a thickness**: `core/Constants.lua:360-361`
  (`TOTAL_W = 2.5`, `LINE_W = 2`), carried by `modules/TimelineModel.lua:287,337` and handed to
  `chart:SetData` by `TM.ChartData` (`modules/TimelineModel.lua:477`). Under v1.91.0 the Timeline's
  Total line is 2.5 physical pixels and each holder line 2, where they were 2.5 and 2 UI units. No
  signature, option or shape moves, so nothing errors. **Not a blocker:** the plan rules the semantics
  ("A host-passed series thickness is read as physical pixels too", `00_PLAN.md` section 1, naming
  LootHistory as a LineChart consumer) and pre-decides "nothing to adopt". The owner's in-client smoke
  of the Timeline is the check. **`[upstream]` finding:** the API document's line 33 says "LootHistory
  and LibKa0sSkinTester pass no `thickness`"; LootHistory does, as above.
- **SkinPaintExtras 18 -> 19, SkinPaintHud 1, SkinAceConfirm 1**
  (`docs/api/Skin/version-17.1.27.8.19.19.1.1.17.4.9-docs.md:21`): "no member of the major or of a
  facade and no behavior changes ... a host's Skin facade owes nothing".
- `grep -rn '__Attach[A-Za-z]*' . --include='*.lua' --exclude-dir=libs --exclude-dir=_kit`: no site.

No contract blocker.

## Blockers (fixed in the re-vendor commit)

The addon's own file list and pins, not contracts:

- `tests/test_libka0s.lua`'s `LIB_FILES` list is compared by count against `LibKa0s.xml`; it gains
  `CorePixel.lua`, `SkinPaintHud.lua`, `SkinAceConfirm.lua` and `WidgetsDropdown.lua` in the tag's XML
  order (after `Core.lua`, after `SkinPaintExtras.lua` (both), after `Widgets.lua`).
- `tests/test_libka0s.lua`'s v1.85.0 case pins `WidgetsLineChart == 6` and its v1.90.0 case pins
  `Core == 16`, `Widgets == 25`, `SkinPaintExtras == 18`. These relax to floors with a "pinned there"
  note, and a new v1.91.0 case pins the new minors exactly.
- `tests/test_widgets.lua`'s adoption pin (`lib.MODULES.Widgets == 25`) moves to 26, with the minor's
  note beside the earlier ones, and its comment naming `Widgets.lua` as the menu's home names
  `WidgetsDropdown.lua`.

## 3h: tags vendored and never recorded

The skill's listing (horizon `2026-08-25`, both payload paths plus the `CLAUDE.md` rolls, `tag_at`
rewritten with a named variable) prints nothing: 67 tags vendored, 67 recorded. **No span bundle.**

## 3i: the icon declaration

```sh
grep -n 'LibKa0s icons:' CLAUDE.md
# 59:LibKa0s icons: ban, chat, chevron-down, chevron-right, chevron-up, circle-check, clear, close, confirm, copy, eye, graph, info, lock, move, reset, segment, settings, sort-down, sort-up, spreadsheet, volume-high.
```

The next non-blank line after the provenance line (58). **Kept as is** (decided: the run keeps every
addon's icons line). v1.91.0 adds no library-drawn icon name. The gate and the owner's in-client smoke
are the backstop; hand lists have drifted before (KickCD `tests/test_mediasetup.lua:28`, WhatGroup
`tests/test_mediasetup.lua:19`), and a pruned icon resolves to a path and draws blank.

## 3j: tests that assume the whole icon folder

```sh
grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v '/_kit/'
```

`tests/test_libka0s.lua:620` opens `info.tga` (declared); `tests/test_mediasetup.lua:106` reads the
catalog's names, and `:139` opens declared names only. None assumes the whole folder. No blocker.

## Dead stub mirrors

No `__` member was removed in this range (the peels move members under the same names). Nothing to
remove.
