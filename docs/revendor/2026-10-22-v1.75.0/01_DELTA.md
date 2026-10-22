Delta: LibKa0s v1.71.0 -> v1.75.0

Run by the 2026-10-22 LibKa0s issues #45-#58 run (item `LH-RV`) on branch
`feat/2026-10-22-libka0s-issues-45-58`, following `/dev-copilot:wow-revendor-libka0s` from the
installed dev-copilot 2.4.0. The run is non-interactive: the owner already decided every adoption
(the run's `inputs/OWNER_SCOPE.md`, section A), so no interview ran and no decline issue was filed.

## Source

```sh
git -C ../LibKa0s rev-parse 'v1.75.0^{commit}'          # 265a89eba3db44f2d85e61287d1691cca6b1effd
git -C ../LibKa0s ls-remote --tags origin v1.75.0        # (empty: a LOCAL annotated tag, not pushed)
git -C ../LibKa0s archive v1.75.0 LibKa0s testkit tools | tar -x -C <scratch>
```

The payload comes from the tag through `git archive`, never from the working tree. `tools/` is
extracted only for `tools/prune-icons.lua`; it is not copied into the addon.

## Base (3a, 3b)

```sh
grep -n '[Bb]undles' CLAUDE.md
# 56:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.71.0 (MIT) — the Ka0s-owned shared
c=$(git log -1 --format=%H -- libs/LibKa0s tests/_kit)      # e74eb26
git show "$c:CLAUDE.md" | grep -oE 'Bundles \[LibKa0s\]\([^)]*\) v[0-9]+\.[0-9]+\.[0-9]+'   # v1.71.0
git log --format='%h %s' "$c..HEAD" -- CLAUDE.md           # b57541e SD-FIN-02 (line unchanged)
git -C ../LibKa0s archive v1.71.0 LibKa0s testkit | tar -x -C <scratch>/claimed
diff -rq --strip-trailing-cr <scratch>/claimed/LibKa0s libs/LibKa0s && \
  diff -rq --strip-trailing-cr <scratch>/claimed/testkit tests/_kit && echo payload-matches
# payload-matches
```

The base is v1.71.0. v1.72.0, v1.73.0 and v1.74.0 were never vendored here, so this one range covers
them and no span bundle is owed. Step 0's pre-flight for this addon: the newest bundle
(`2026-10-07-v1.71.0`) states base v1.70.0, and the provenance before its re-vendor commit `e74eb26`
was v1.70.0, so it is correct. Step 3h's listing (vendored tags minus recorded tags) is empty.

```sh
git -C ../LibKa0s log --oneline v1.71.0..v1.75.0 | wc -l     # 56
git -C ../LibKa0s diff --stat v1.71.0 v1.75.0 | tail -1      # 5863 files changed (5,722 of them icons)
```

## Per-file minor delta (3c)

From the tag's `LibKa0s/LibKa0s.xml`, each file's `[A-Z_]*MINOR` constant, old (this repo before the
copy) against new (the tag). Unchanged files are omitted.

| File | Old | New | Release |
|---|---|---|---|
| `Core.lua` | 10 | 11 | v1.75.0, comment-only (#57) |
| `Item.lua` | 2 | 3 | v1.75.0, `Item.BonusIDsFromLink` (#51) |
| `Glow.lua` | (new) | 1 | v1.75.0, new major `LibKa0s-Glow-1.0` (#56) |
| `Media.lua` | 4 | 5 | v1.74.0, three icon sets, `ICON_SETS`, `IconAuthor` |
| `MediaIcons.lua` | (new) | 1 | v1.74.0, generated catalog (Media key 5.1) |
| `Widgets.lua` | 12 | 13 | v1.75.0, `W.SearchBox` (#52), `W.TestStrip` (#48) |
| `DebugLog.lua` | 19 | 20 | v1.75.0, comment-only (#57) |
| `DebugLogDiagnostics.lua` | 2 | 3 | v1.75.0, header names Glow and Sim |
| `Options.lua` | 28 | 29 | v1.73.0, the drawer's attach, scroll kept on refresh |
| `OptionsIdList.lua` | 4 | 5 | v1.75.0, comment-only (#57) |
| `OptionsTabs.lua` | 8 | 9 | v1.75.0, `O.__releaseChrome` removed (#45) |
| `OptionsDrawer.lua` | (new) | 1 | v1.73.0, `O.Drawer` |
| `Perf.lua` | 14 | 15 | v1.72.0, `Perf.Note` takes `false` |
| `PerfPanel.lua` | 6 | 7 | v1.75.0, comment-only (#53) |
| `Sim.lua` | (new) | 1 | v1.75.0, new major `LibKa0s-Sim-1.0` (#54) |
| `SimTimeline.lua` | (new) | 1 | v1.75.0 |
| `SimPanel.lua` | (new) | 1 | v1.75.0 (holds the step-panel renderer privately, LK-11 outcome B) |

No file was behind the tag after the copy (no cross-major skew). No `WidgetsStepPanel.lua` ships:
`W.StepPanel` was withdrawn before release (LK-11 outcome B, the run's `exceptions.tsv` row LK-10).
No `NEEDS_*` floor rises. The library is seventeen majors across forty files.

## Both diffs (3d)

Before the copy, `diff -rq --strip-trailing-cr <scratch>/LibKa0s libs/LibKa0s` listed 131 lines: 18
changed or new Lua/XML files above and 113 `Only in <scratch>/LibKa0s/media/icons...` lines (the
111 new flat Open Iconic marks and the `phosphor/` and `game-icons/` folders). The kit differed in
`README.md`, `framework.lua`, `inventory.lua`, `mock_base.lua`, `mock_record.lua`,
`run-automated-tests.sh` and `vendor_sync.lua`, and lacked `latch.lua`. No `Only in libs/LibKa0s` or
`Only in tests/_kit` line, so nothing was deleted by hand.

After `cp -r` of both folders and BEFORE the prune, all four diffs were empty:

```sh
diff -r --strip-trailing-cr <scratch>/LibKa0s libs/LibKa0s   # (empty)
diff -rq                    <scratch>/LibKa0s libs/LibKa0s   # (empty)
diff -r --strip-trailing-cr <scratch>/testkit tests/_kit     # (empty)
diff -rq                    <scratch>/testkit tests/_kit     # (empty)
```

After the prune the only difference is `Only in <scratch>/LibKa0s/media/icons...` for the icons
this addon does not declare, which is the declaration working (3d's fourth reading).

## Consumption map (3e)

```sh
grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v '^libs/' | grep -v '^tests/'
```

`core/ItemSetup.lua:26` Item, `core/MediaSetup.lua:57` Media, `core/CoreSetup.lua:44` Core,
`core/EnvSetup.lua:42` Env, `core/DebugLogSetup.lua:25` DebugLog, `core/LifecycleSetup.lua:47`
Lifecycle, `core/LauncherSetup.lua:42` Launcher, `core/Compat.lua:102` Compat, `core/Constants.lua:328`
Bus, `core/PoolSetup.lua:22` Pool, `core/WidgetsSetup.lua:95` Widgets, `core/PerfSetup.lua:23` Perf,
`modules/Diagnostics.lua:129` Lifecycle, `settings/OptionsSetup.lua:47` Options,
`settings/Slash.lua:201` Slash, `settings/Schema.lua:750` Schema.

Fifteen majors consumed. Not consumed: `LibKa0s-Glow-1.0` and `LibKa0s-Sim-1.0`, both new here. Of
the moved files, this addon reaches Core, Item, Media, Widgets, DebugLog/DebugLogDiagnostics,
Options (OptionsIdList, OptionsTabs, OptionsDrawer) and Perf/PerfPanel.

## Kit revision and the pairing rule (3f)

```sh
grep -n 'Kit.VERSION' <scratch>/testkit/framework.lua tests/_kit/framework.lua
# <scratch>/testkit/framework.lua:20:Kit.VERSION = 41
# tests/_kit/framework.lua:20:Kit.VERSION = 38
```

Kit 38 -> 41 (39: `__fireUnconditional` reaches method-name and function handlers, and
`assertLatchHoldOrder`; 40: the icon-declaration gate; 41: crashed-lizard bucket, two `__` kit
members unexported). Both payloads move in one commit, as the pairing rule has required since kit 11.

## Contract delta (3g)

Majors read: the moved minors intersected with the consumption map. `grep -rn '__Attach[A-Za-z]*'
core modules settings` is empty: this addon hands the library no member through an attach seam, so
no host-supplied callback's call site can have moved.

- **Options 29: a structural refresh of a page on screen keeps its scroll offset.** `grep -rn
  'SetScroll\|ScrollToTop\|SetVerticalScroll' settings` is empty; this addon never scrolled a page
  back to the top by hand. Nothing to change.
- **Kit 39: `M.__fireUnconditional` now reaches method-name handlers after unregister.** `grep -rn
  Unconditional tests --include='*.lua' | grep -v _kit` is empty, so no stand-down case changes
  meaning. `tests/test_disabled.lua` stayed green.
- **Core 11, DebugLog 20, OptionsIdList 5, PerfPanel 7: comment-only.** They correct the claim that a
  missing icon falls back to text: a host that passes its folder name gets a blank control when the
  icon is not declared. This is why `close`, `copy`, `clear` and `info` are on the declaration.
- **Perf 15: `Perf.Note`'s parent may be `false`.** Additive. `core/PerfSetup.lua`'s stub `Note` is a
  no-op and takes any argument.

### Blockers, fixed in the re-vendor commit

| # | Blocker | Where it went red | Fix |
|---|---|---|---|
| a | Options 29 / OptionsDrawer 1 add `O.Drawer`; OptionsTabs 9 removes `O.__releaseChrome` | `tests/test_surface_parity.lua` Options case (`Drawer is missing`) | `settings/OptionsSetup.lua` stub gains `Drawer = noop`; the dead `__releaseChrome = noop` mirror and its name in the `__` grep comment are removed (LibKa0s#45, the KickCD M4-09 precedent). The other `__` mirrors stay. |
| b | Item 3 adds `Item.BonusIDsFromLink` | `tests/test_surface_parity.lua` Item case (`BonusIDsFromLink is missing`) | `core/ItemSetup.lua` stub gains a local pure `BonusIDsFromLink` with the library's exact walk. New case in `tests/test_itemsetup.lua` compares the degraded and live answers over a 3-bonus link, a 0-bonus link, a bare itemString with a declared count of 0, a non-numeric field inside the span, a link with modifiers after the bonuses, a currency string and a non-string; red first (`stub carries no BonusIDsFromLink`), then green. Call-site adoption is LH-02. |
| c | Kit 40's icon subset: the whole-catalog walk opens a file per `Media.ICONS` name (now 5,836) | `tests/test_mediasetup.lua` "every name the library ships has a file in the vendored copy" | Rewritten as "the icon declaration is exactly the drawn set, and each has its file": reads the declaration through `tests/_kit/vendor_sync.lua`'s `iconDeclaration`, asserts `mode == "list"`, set equality with `DRAWN` (both directions), and a `.tga` per declared name. `DRAWN`'s comment now names `clear` as library-drawn too. |
| d | The prune would remove `info` silently if undeclared | `tests/test_libka0s.lua` "the vendored info art the help mark points at is on disk" (would pass on disk while the declaration drifted) | Renamed "... is declared and on disk": asserts the declaration names `info` before the file check. |
| e | Release pins move | `tests/test_libka0s.lua` "v1.71.0: ..." (`expected 4, got 5`) | `OptionsIdList` and `KIT_VERSION` relax to `>=` with "pinned there" notes; new case "v1.75.0: the vendored minors and the kit revision match the release" pins Core 11, Item 3, Glow 1, Media 5, MediaIcons 1, Widgets 13 (no `WidgetsStepPanel`), DebugLog 20, DebugLogDiagnostics 3, Options 29, OptionsIdList 5, OptionsTabs 9, OptionsDrawer 1 (and `O.Drawer` on the live instance), Perf 15, PerfPanel 7, Sim 1, SimTimeline 1 and SimPanel 1 (both paired on the shell's minor), kit 41. Read off the tag's CHANGELOG v1.72.0-v1.75.0 blocks. |
| f | Kit 39 `__fireUnconditional` | none | Nothing to fix (see above). |
| g | Stale mentions | `docs/debug.md:13-14` | DebugLog 20 / DebugLogDiagnostics 3 / v1.75.0 and the `version-20.3.1` document. `docs/testing.md` carries no present-tense kit-38 claim; its `test_mediasetup.lua` row and vendor-gate block now describe the declaration. `docs/ARCHITECTURE.md:33` recounts sixteen of seventeen majors resolving Core. |
| h | Six new payload files | `tests/test_libka0s.lua` "every file of LibKa0s.xml is vendored and loads" (`expected 34, got 40`) | `LIB_FILES` gains `Glow.lua`, `MediaIcons.lua`, `OptionsDrawer.lua`, `Sim.lua`, `SimTimeline.lua` and `SimPanel.lua` in XML order. Not named in the item spec. |
| i | Widgets 13 | `tests/test_widgets.lua` "the seam builds a real library dropdown" (`written against Widgets minor 12`) | The pin moves to 13 with a paragraph: the dropdown's skin literals are hoisted into a file-local `SKIN` with the same values; `Dropdown`, `CloseMenu`, `CopyWindow` and `ReorderList` keep every member and opts field. Not named in the item spec. |

## The icon declaration (3i, 3j)

**(b) Provenance split.** `CLAUDE.md:56` ran on into prose (`... v1.71.0 (MIT) — the Ka0s-owned
shared ...`), so kit 40's `VendorSync.iconDeclaration` had nowhere to find the line. The sentence is
split: the provenance line ends at `(MIT).`, the declaration follows, and the prose resumes as its own
paragraph with one added sentence on what reads the line and what an omission costs.

**(c, e) The line, decided by the run's item spec and recorded here, not re-asked:**

```
LibKa0s icons: ban, chat, chevron-down, chevron-right, circle-check, clear, close, confirm, copy, graph, info, lock, segment, sort-down, sort-up, spreadsheet.
```

| Name | Evidence |
|---|---|
| ban | `modules/BrowserTable.lua:1231,1239` (menu data); `settings/Panel.lua:591` (TICK_OFF) |
| chat | `modules/BrowserTable.lua:1222` |
| chevron-down | `core/WidgetsSetup.lua:108` (dropdown); `modules/BrowserTable.lua:1169`; `modules/HoldingsTab.lua:429` |
| chevron-right | `modules/BrowserTable.lua:1168`; `modules/HoldingsTab.lua:428` |
| circle-check | `settings/Panel.lua:589` |
| clear | `modules/BrowserTable.lua:1246`; `modules/HoldingsTab.lua:284`; library-drawn by the DebugLog console |
| close | library-drawn: `Core.MakeCloseButton` via `core/CoreSetup.lua:276-277` (`modules/Browser.lua`, `modules/Export.lua`, the DebugLog console, PerfPanel) |
| confirm | `core/WidgetsSetup.lua:109` (multi-select tick) |
| copy | library-drawn by the DebugLog console |
| graph | `modules/BrowserTable.lua:1226`; `modules/HoldingsTab.lua:277` |
| info | `settings/Panel.lua:844`; library-drawn by the Options id list's help mark (`settings/Panel.lua:337` passes no `helpIcon`) |
| lock | `modules/BrowserTable.lua:86,111,113,120` |
| segment | `core/WidgetsSetup.lua:159` (reorder handle) |
| sort-down, sort-up | `modules/BrowserTable.lua:326-327`; `modules/HoldingsTab.lua:304-305` |
| spreadsheet | `modules/Export.lua:543` (makeButton's trailing icon) |

Every name is a flat Open Iconic entry; no `ph:` or `gi:` name is drawn. The filter-bar buttons pass
no icon. Hand lists have drifted before (KickCD `tests/test_mediasetup.lua:28`, WhatGroup
`tests/test_mediasetup.lua:19`); `tests/test_mediasetup.lua` now holds `DRAWN` equal to the
declaration, and the owner's in-client smoke (SM-LH-1..6) is the backstop, because a pruned icon
still resolves to a path and draws blank.

**3j.** `grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v '/_kit/'`
found the whole-catalog walk (blocker c) and the `info` file check (blocker d). No second declaration
parser is written; both cases use the kit's.

## Prune

```sh
lua <scratch>/tools/prune-icons.lua .
# prune-icons: .: 16 icon(s) declared; kept 17 file(s), removed 5823
```

Removed: 208 flat Open Iconic marks, the whole `phosphor/` folder (1,434 marks and
`LICENSE-phosphor.txt`) and the whole `game-icons/` folder (4,178 marks, `LICENSE-game-icons.txt` and
`AUTHORS.txt`). Kept: the 16 declared `.tga` files and `LICENSE-open-iconic.txt`.
