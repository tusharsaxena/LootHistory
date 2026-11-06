Delta: LibKa0s v1.85.0 -> v1.89.0

Item `V89-LH` of Ka0sAddonsCommonTasks `docs/2026-11-06-REVENDOR_LIBKA0S_V1_89/00_PLAN.md`. Written before
the copy. The payload is taken from the tag, never the working tree:

```sh
git -C ../LibKa0s archive v1.89.0 LibKa0s testkit tools | tar -x -C /tmp/claude-1000/v89-lh/new
git -C ../LibKa0s rev-parse 'v1.89.0^{commit}'   # df00e5f09fc71b59001b9e83afb22f868573b3d2
```

## Step 0: pre-flight

From the run's `inputs/step0-preflight.txt` (the roster regex fixed as the plan records):

```
LootHistory  2026-11-01-v1.85.0  base v1.84.0  vendored-before v1.84.0@6fe5d26  ok
```

No base correction is owed.

## 3a: claimed version, and the base

```sh
grep -n '[Bb]undles' CLAUDE.md
# 58:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.85.0 (MIT).
c=$(git log -1 --format=%H -- libs/LibKa0s tests/_kit)   # 4dede61 R6-RV2: Re-vendor LibKa0s v1.85.0 (round 6 sim checkbox re-cut)
git show "$c:CLAUDE.md" | grep -oE 'Bundles \[LibKa0s\]\([^)]*\) v[0-9]+\.[0-9]+\.[0-9]+'
# Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.85.0
git log --format='%h %s' "$c..HEAD" -- CLAUDE.md           # (no rolls since)
```

The line and the last payload commit agree: **base v1.85.0**. The payload today is the library's at
v1.85.0 (`diff -rq` against `git archive v1.85.0 LibKa0s testkit`: library differs only by the
undeclared `media/icons` files, kit identical).

```sh
git -C ../LibKa0s log --oneline v1.85.0..v1.89.0    # 23 commits, df00e5f .. 06eae81
git -C ../LibKa0s diff --stat v1.85.0 v1.89.0 | tail -1
# 83 files changed, 125301 insertions(+), 321 deletions(-)
```

## 3b: actual version

`grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua` gives every file at
its v1.85.0 minor (Toast 3, Widgets 22, DebugLogDiagnostics 6, no IconBrowser). The claim and the bytes
agree.

## 3c: per-file minor delta (the tag's `LibKa0s.xml` loop)

Only these rows move; every other file of the 67 is at the same minor on both sides.

| File | old | new |
|---|---|---|
| `Toast.lua` (`LibKa0s-Toast-1.0`) | 3 | 4 |
| `Widgets.lua` (`LibKa0s-Widgets-1.0`) | 22 | 23 |
| `DebugLogDiagnostics.lua` (`DIAG_MINOR`) | 6 | 7 |
| `IconBrowserSources.lua` (`LibKa0s-IconBrowser-1.0`) | (new) | 1 |
| `IconBrowserWindow.lua` (`WINDOW_MINOR`) | (new) | 1 |
| `IconBrowser.lua` (`BROWSER_MINOR`) | (new) | 1 |

No consumer file is ahead of or behind the others: no cross-major skew.

## 3d: both diffs (before the copy)

```sh
diff -rq --strip-trailing-cr <tag>/LibKa0s libs/LibKa0s | grep -v 'media/icons'   # 7 lines
diff -rq                     <tag>/LibKa0s libs/LibKa0s | grep -v 'media/icons'   # the same 7
diff -rq --strip-trailing-cr <tag>/testkit tests/_kit                             # 3 lines
```

Library: `DebugLogDiagnostics.lua`, `LibKa0s.xml`, `Toast.lua`, `Widgets.lua` differ; `IconBrowser.lua`,
`IconBrowserSources.lua`, `IconBrowserWindow.lua` only in the tag. Kit: `README.md`, `framework.lua`,
`mock_ace.lua` differ. Content and bytes agree, so there is no line-ending drift. No `Only in libs/LibKa0s`
line: nothing removed upstream. The `Only in <tag>/LibKa0s/media/icons` lines are the undeclared icons.

## 3e: consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v /libs/ | grep -v /tests/`:
Bus, Charts, Compat, Core, DebugLog, Env, Item, Launcher, Lifecycle, Media, Options, Perf, Pool, Schema,
Sim, Skin, Slash, Widgets. **Not looked up:** Glow, Toast, IconBrowser (new). No new lookup site.

Of the majors that moved, the addon consumes **Widgets** (`core/WidgetsSetup.lua:115`) and **DebugLog**
(`core/DebugLogSetup.lua:25`). Toast and IconBrowser are loaded by the XML and wired by nothing here.

## 3f: kit revision

```sh
grep -n 'Kit.VERSION' <tag>/testkit/framework.lua tests/_kit/framework.lua
# <tag>: Kit.VERSION = 51     tests/_kit: Kit.VERSION = 50
```

Kit 50 -> 51 (the CallbackHandler unregister guard). Both payloads move in this one commit (the kit
pairing rule, satisfied by the whole-folder copy).

## 3g: contract delta

Majors moved and consumed: Widgets and DebugLog.

- **Widgets 22 -> 23** (`docs/api/Widgets/version-22.5.12.6.7.5-docs.md` -> `version-23.5.12.6.7.5-docs.md`,
  *What changed at this version: cascading menus*): additive `submenu`, `radio`, `selected` rows and
  `opts.check` on `W.ContextMenu`; "Every single-level menu, a dropdown's and a host's, is unchanged",
  and "a dropdown ignores all three". The `CloseMenu` row gains "and every level of a cascade". This
  addon calls `W.Dropdown`, `W.CloseMenu`, `W.TestStrip` (which opens a flat `W.ContextMenu` itself),
  `W.SearchBox`, `W.Autocomplete`, `W.CopyWindow`, `W.LineChart`, `W.ReorderList`; it calls
  `W.ContextMenu` nowhere. No moved call site or tightened MUST reaches it.
- **DebugLogDiagnostics 6 -> 7**: the report's `LibKa0s running:` line names `IconBrowser`. No member moves.
- `grep -rn '__Attach[A-Za-z]*' . --include='*.lua' --exclude-dir=libs --exclude-dir=_kit`: no site.

No contract blocker.

## Blockers (fixed in the re-vendor commit)

The addon's own pins, not contracts:

- `tests/test_libka0s.lua`'s `LIB_FILES` must match the XML's file count ("every file of LibKa0s.xml is
  vendored and loads"); it gains `IconBrowserSources.lua`, `IconBrowserWindow.lua`, `IconBrowser.lua`,
  in XML order after `OptionsMedia.lua`.
- `tests/test_libka0s.lua`'s v1.85.0 exact pins (`DebugLogDiagnostics == 6`, `Toast == 3`,
  `Widgets == 22`, `KIT_VERSION == 50`) relax to floors, and a v1.89.0 case pins the new minors.
- `tests/test_widgets.lua`'s adoption pin (`lib.MODULES.Widgets == 22`, "this adoption is written against
  Widgets minor 22") moves to 23, with the minor's note beside the earlier ones. Found by the first gate
  after the copy (1979 passed, 1 failed), as the earlier minors were.
- No Toast instance stub in this addon (it raises no toast), so Toast 4's `SetStack`, `Visible`,
  `FrameFor` owe nothing here.

## 3h: tags vendored and never recorded

The skill's listing (horizon `2026-08-25`, both payload paths plus the `CLAUDE.md` rolls) prints
nothing. **No span bundle.**

## 3i: the icon declaration

```sh
grep -n 'LibKa0s icons:' CLAUDE.md
# 59:LibKa0s icons: ban, chat, chevron-down, chevron-right, chevron-up, circle-check, clear, close, confirm, copy, eye, graph, info, lock, move, reset, segment, settings, sort-down, sort-up, spreadsheet, volume-high.
```

The next non-blank line after the provenance line (58); the provenance line ends its sentence. **Kept
as is.** v1.86.0..v1.89.0 add library-drawn names only for surfaces this addon does not wire (the icon
browser's `search` and `close`; a cascading menu's arrow and tick, which need a `W.ContextMenu` host
with `submenu` or `radio`). The gate (`tests/test_mediasetup.lua`'s drawn-vs-declared cases) and the
owner's in-client smoke are the backstop: a pruned icon resolves to a path and draws blank.

## 3j: tests that assume the whole icon folder

```sh
grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v '/_kit/'
```

`tests/test_libka0s.lua:614` opens `info.tga` (declared); `tests/test_mediasetup.lua:106` reads the
catalog's names, and `:139` opens declared names only. None assumes the whole folder. No blocker.

## Dead stub mirrors

No `__` member was removed in this range. `grep -rn '__releaseChrome'` finds only history comments
(`tests/test_libka0s.lua`, `tests/test_surface_parity.lua`). Nothing to remove.
