# Candidates: LibKa0s v1.85.0 -> v1.89.0 (LootHistory)

Sources: `git -C ../LibKa0s log --oneline v1.85.0..v1.89.0`, the tag's `CHANGELOG.md` blocks v1.86.0 to
v1.89.0, and the `docs/api/` documents of every major that moved (Widgets, DebugLog, Toast, IconBrowser,
testkit). Blockers (01_DELTA.md) are not candidates.

## A. Delivered on the copy (no host change)

- **Kit revision 51** (`CHANGELOG.md` v1.89.0, *The kit's unregister guard*; `docs/api/testkit/version-51-docs.md`):
  the mock CallbackHandler clears an entry only where one exists, so an unregister during a dispatch no
  longer raises `invalid key to 'next'`. This suite gets the flake fix for free.
- **DebugLogDiagnostics 7** (`CHANGELOG.md` v1.86.0, *The icon browser's sources*, last bullet): the
  `/lh debug` diagnostics report's `LibKa0s running:` line names `IconBrowser`. No member moves.
- **Widgets 23 for a dropdown host** (`docs/api/Widgets/version-23.5.12.6.7.5-docs.md`, *What changed at
  this version*): `W.CloseMenu` now closes every cascade level; this addon's ten filter-bar dropdowns and
  `W.TestStrip`'s right-click menu are flat and draw what minor 22 drew.

## B. Host change required

- **Widgets 23 `submenu` / `radio` / `selected` / `opts.check` on `W.ContextMenu`** (same document, the
  row-field table). Not applicable: this addon has no `W.ContextMenu` use site
  (`grep -rn 'ContextMenu' core modules settings` finds none; its menus are `W.Dropdown`s, which ignore
  the three fields). Plan row *Cascading-menu fields: addons with no W.ContextMenu use site*.
- **Toast 4 stack** (`CHANGELOG.md` v1.88.0, *The stack*). Not applicable: Toast is not looked up here
  (01_DELTA.md 3e) and the addon raises no toast (`tests/test_libka0s.lua`'s `LIB_FILES` comment on
  `Toast.lua`).

## C. Whole-module adoption

- **`LibKa0s-IconBrowser-1.0`** (new at v1.86.0; `docs/api/IconBrowser/version-1.1.1-docs.md`). The
  browser serves an addon whose player picks an icon. LootHistory has no icon chooser: every mark it
  draws is a fixed name in its `LibKa0s icons:` declaration. Blast radius would be additive, but there is
  nothing for it to serve. Plan row *IconBrowser: every addon without an icon chooser*, settled.

No other new surface in the range. No genuine candidate outside the plan's decisions table.
