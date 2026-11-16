Delta: LibKa0s v1.93.0 -> v1.105.0

Payload taken from the tag, never the sibling tree: `git -C ../LibKa0s archive v1.105.0 LibKa0s testkit tools`. Run under Ka0sAddonsCommonTasks `docs/2026-11-16-LIBKA0S_ISSUES_75_PLUS/`, item RV-LH, copy-and-bundle half only: no adoption interview and no GitHub issue filing (the run's design section 5).

## The tag was re-cut during this item
The copy was first taken from the first cut of the local tag `v1.105.0` (commit `79b1d9c4`). Against that payload LootHistory's kit leak gate failed: the live heap ended about 6 MB over the kit's default budget (`KA0S_KIT_LEAK_MB`), because kit revision 57's frame hold (#75) added two closures to every mock frame and this suite builds a great many frames. The leak budget was not raised and no test was touched. The fix is the library's: LibKa0s `LK-FIX-1` (`8209c104`, "Kit 57's frame hold adds no closure per frame") moves the hold into the frame stub's own methods, and the local tag `v1.105.0` was re-cut there. Only `testkit/mock_base.lua` and `testkit/mock_events.lua` differ between the two tag commits; both were re-copied into `tests/_kit/`, and the kit revision stays 57. Everything below is measured against the re-cut tag (`git -C ../LibKa0s rev-parse v1.105.0^{commit}` = `8209c10484eed242541a66af5d97537ad5d7fa0e`).

## Step 0 pre-flight
Newest single-tag bundle `2026-11-07-v1.93.0`, line 1 `Delta: LibKa0s v1.92.0 -> v1.93.0`. The commit that rolled the provenance line to v1.93.0 is `b6e2ad6`, whose parent named v1.92.0. ok, no correction owed.

## 3a Base
- `git show HEAD:CLAUDE.md | grep -n '[Bb]undles'`: `58:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.93.0 (MIT).`
- Last payload commit, `git log -1 --format=%h -- libs/LibKa0s tests/_kit`, is `b5a1a32` (WFP-RV2-LH, "Re-copy LibKa0s v1.93.0 after the final-review fixes"); its CLAUDE.md names v1.93.0, and no CLAUDE.md commit since rolled the line. They agree.
- The payload at HEAD equalled the library at v1.93.0: `diff -rq` of HEAD's `libs/LibKa0s` (outside the pruned `media/icons` and `media/sounds`) and `tests/_kit` against a v1.93.0 extract printed nothing (payload-matches).
- Library range: `git -C ../LibKa0s log --oneline v1.93.0..v1.105.0` is 118 commits (LK-FIX-1 included), across the tags v1.94.0 to v1.105.0, none of which this addon vendored. `git -C ../LibKa0s diff --stat v1.93.0 v1.105.0 -- LibKa0s testkit`: 420 files changed, 10328 insertions, 725 deletions.

## 3b/3c Per-file minors that moved (old = HEAD, new = v1.105.0)
The constants HEAD carried matched v1.93.0's, so the line and the bytes agreed. From the tag's `LibKa0s.xml` (82 files):
```
Core.lua  old: 17  new: 18
Tooltip.lua  old: none  new: 1
Compat.lua  old: 3  new: 4
Role.lua  old: none  new: 1
Callout.lua  old: none  new: 4
CalloutSettings.lua  old: none  new: 5
WaypointArrow.lua  old: none  new: 2
WaypointArrowSettings.lua  old: none  new: 2
Charts.lua  old: 1  new: 2
Media.lua  old: 12  new: 13
Skin.lua  old: 17  new: 18
SkinDefs.lua  old: 27  new: 28
SkinDefsOthers.lua  old: 8  new: 10
Widgets.lua  old: 26  new: 27
WidgetsDropdown.lua  old: 1  new: 2
WidgetsReorder.lua  old: 6  new: 7
WidgetsDragHandle.lua  old: 13  new: 14
WidgetsDragHandleTip.lua  old: none  new: 1
WidgetsCopyWindow.lua  old: 5  new: 6
WidgetsHeader.lua  old: none  new: 1
WidgetsBar.lua  old: none  new: 1
DebugLog.lua  old: 22  new: 23
DebugLogDiagnostics.lua  old: 7  new: 11
DebugLogWindow.lua  old: 4  new: 5
Launcher.lua  old: 9  new: 11
OptionsWidgets.lua  old: 45  new: 46
OptionsNav.lua  old: 6  new: 7
OptionsSkinPicker.lua  old: 11  new: 12
OptionsSkinPickerQueue.lua  old: none  new: 1
IconBrowserWindow.lua  old: 1  new: 2
IconBrowser.lua  old: 1  new: 2
PerfPanel.lua  old: 13  new: 14
Sim.lua  old: 2  new: 3
SimPanel.lua  old: 10  new: 11
SimPanelRender.lua  old: 3  new: 4
```
The other 47 files kept their minor. `none` is a file new in the range: Role (v1.95.0), Callout and CalloutSettings (v1.96.0), WaypointArrow and WaypointArrowSettings (v1.99.0), and this release's five, Tooltip, WidgetsDragHandleTip, WidgetsHeader, WidgetsBar and OptionsSkinPickerQueue. No cross-major skew: the copy is whole.

## 3d Diffs
Against a fresh extract of the re-cut tag, `diff -rq <extract>/testkit tests/_kit` printed nothing, and `diff -rq <extract>/LibKa0s libs/LibKa0s` printed only `Only in <extract>/LibKa0s/media/icons...` lines (icons not declared) and `Only in <extract>/LibKa0s/media/sounds: callout` (no sounds declared): 205 lines in all, none outside those two folders. Content and bytes are both clean (the working tree is CRLF on both sides under `eol=crlf`; the index is LF). No `Only in libs/LibKa0s` line appeared: nothing was removed upstream in the range. New untracked payload files: the ten Lua files above, `media/fonts/BebasNeue-*`, `media/fonts/RussoOne-*`, `media/waypoint/` and `tests/_kit/mock_screen.lua`.

## 3e Consumption map
`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' core modules settings --include='*.lua'`
```
core/Compat.lua:68:LibStub("LibKa0s-Env-1.0", true)
core/Compat.lua:169:LibStub("LibKa0s-Compat-1.0", true)
core/Constants.lua:327:LibStub("LibKa0s-Bus-1.0", true)
core/CoreSetup.lua:44:LibStub("LibKa0s-Core-1.0", true)
core/DebugLogSetup.lua:25:LibStub("LibKa0s-DebugLog-1.0", true)
core/EnvSetup.lua:46:LibStub("LibKa0s-Env-1.0", true)
core/ItemSetup.lua:26:LibStub("LibKa0s-Item-1.0", true)
core/LauncherSetup.lua:42:LibStub("LibKa0s-Launcher-1.0", true)
core/LifecycleSetup.lua:47:LibStub("LibKa0s-Lifecycle-1.0", true)
core/MediaSetup.lua:57:LibStub("LibKa0s-Media-1.0", true)
core/PerfSetup.lua:23:LibStub("LibKa0s-Perf-1.0", true)
core/PoolSetup.lua:22:LibStub("LibKa0s-Pool-1.0", true)
core/SimSeam.lua:52:LibStub("LibKa0s-Sim-1.0", true)
core/SkinSetup.lua:97:LibStub("LibKa0s-Skin-1.0", true)
core/WidgetsSetup.lua:115:LibStub("LibKa0s-Widgets-1.0", true)
modules/AnalyticsCharts.lua:12:LibStub("LibKa0s-Charts-1.0", true)
modules/Diagnostics.lua:129:LibStub("LibKa0s-Lifecycle-1.0", true)
modules/Sim.lua:358:LibStub("LibKa0s-Sim-1.0", true)
settings/OptionsSetup.lua:47:LibStub("LibKa0s-Options-1.0", true)
settings/Schema.lua:860:LibStub("LibKa0s-Schema-1.0", true)
settings/Slash.lua:208:LibStub("LibKa0s-Slash-1.0", true)
```
Majors in the payload with no lookup in this addon: LibKa0s-Callout-1.0 LibKa0s-Glow-1.0 LibKa0s-IconBrowser-1.0 LibKa0s-Role-1.0 LibKa0s-Toast-1.0 LibKa0s-Tooltip-1.0 LibKa0s-WaypointArrow-1.0. Tooltip is the #92 candidate (02_CANDIDATES.md); the rest have no use here today.

## 3f Kit revision
```
old: HEAD tests/_kit/framework.lua:20:Kit.VERSION = 53
new: testkit/framework.lua:20:Kit.VERSION = 57
```
Kit revision 57 pairs with v1.105.0, and both payloads are copied whole in one commit. Revision 57's frame hold (#75: a frame with a raw event registration is held until it unregisters) is what tripped this suite's leak gate on the first cut; on the re-cut tag (LK-FIX-1, above) the gate passes at the default budget. The new `tests/_kit/mock_screen.lua` (the opt-in fake screen and tooltip recorder) is loaded by no suite here yet; it is the harness a #92 adoption would test against. This addon's CLAUDE.md carries no kit-revision sentence, so there is nothing to roll beyond the provenance line.

## 3g Contract delta and Blockers
Host-supplied members, `grep -rn '__Attach[A-Za-z]*' . --include='*.lua' --exclude-dir=libs --exclude-dir=Libs --exclude-dir=_kit`:
```
none
```
Changes under surfaces this addon consumes whose shape did not move, each fixed in the re-vendor commit:
- **DebugLog instance gains `Report` and `Serialize`** (DebugLog minor 23, DebugLogDiagnostics minor 11, LibKa0s#79). `Kit.assertSurfaceParity` reads the instance by name, so the library-absent stub in `core/DebugLogSetup.lua` gains both: `Report` streams the body to chat with no pointer and answers the lines written, `Serialize` answers one line.
- **Options instance gains `SideTabs`** (OptionsNav minor 7, from v1.100.0). The stub in `settings/OptionsSetup.lua` gains a no-op.
- **Compat gains four region-unique identity helpers** (Compat minor 4, v1.94.0: `RegionalNames`, `UnitCharacterName`, `CharacterKey`, `RealmKey`). This addon ships for Retail only and calls none of them, so `tests/test_surface_parity.lua` lists them among the Compat members it deliberately does not wire.
- **Ka0s Default's `list.stripe` and `list.hover` moved** (SkinDefs minor 28, LibKa0s#84: stripe white .03 to .08, hover gold .10 to .16). `core/SkinSetup.lua`'s library-absent fallback copies Ka0s Default's values, so it re-copies the two, and the "today's values" tables in `tests/test_skin_table.lua` and `tests/test_skin_insights.lua` re-pin them with the reason.
- **The console's counter moved to the footer** (DebugLogWindow minor 5, LibKa0s#90): the count is the console's footer line in `text.muted`, and `log.count` stays skin data the console no longer reads. `tests/test_skin_tools.lua`'s skin-switch case reads the counter against `text.muted`; the `ts`, `tag` and `text` colours are still checked against their `log.*` tokens.
- **The console's title marks are Widgets `HeaderButtons`** (DebugLogWindow minor 5, WidgetsHeader minor 1, LibKa0s#86), which measure each built mark rather than adding a constant. Under the mock an icon mark reports its 12 px art, so `tests/test_debuglog.lua` re-pins the Clear-to-Copy gap at 18 (12 + 6; 24 in the client). The 48 px word-fallback case it guards against is unchanged.
- **Widgets minor 27** (`W.Footer`, `W.FOOTER`, strip docking, v1.103.0) and **WidgetsDropdown minor 2** (an entry's tooltip opens beside its menu, LibKa0s#92). No Dropdown, ContextMenu or CloseMenu member, option or row field moved, so `tests/test_widgets.lua`'s adoption pin moves to Widgets 27 with the reason written beside it.
- **`tests/test_libka0s.lua`**: `LIB_FILES` gains the ten new files in the tag's XML order; the earlier releases' 29 exact minor pins and the kit pin become floors, and a new case `v1.105.0: the vendored minors and the kit revision match the release` pins every moved minor exactly and the kit at 57.

**Blockers: none.** No fix needed a decision.

## 3h Unrecorded vendored tags
The re-vendor-bundle walk (provenance tags at every payload commit and every CLAUDE.md roll since the store's horizon, 2026-08-25, against the tags named by the bundles in `docs/revendor/`):
```
(empty)
```
No span bundle is owed: v1.93.0, the tag the provenance line moved from, is recorded by `2026-11-07-v1.93.0`.

## 3i Icon declaration
- `grep -n 'LibKa0s icons:' CLAUDE.md`: `59:LibKa0s icons: ban, chat, chevron-down, chevron-right, chevron-up, circle-check, clear, close, confirm, copy, eye, graph, info, lock, move, reset, segment, settings, sort-down, sort-up, spreadsheet, volume-high.`
- Kept as written, the next non-blank line under the provenance line. This release adds `settings` to the library-drawn set (the settings mark on the library's title bars), and the line already carries it. No `LibKa0s sounds:` line: sounds `none`.
- The tag's `tools/prune-icons.lua` kept 23 icon files (22 declared plus `LICENSE-open-iconic.txt`) and removed 202 Open Iconic, 1435 Phosphor and 4180 Game-icons files; the sounds prune removed all 362 sound files (eight voice packs). A second run, `lua <extract>/tools/prune-icons.lua .`, reported `22 icon(s) declared; kept 23 file(s), removed 0` and `sounds none ...; kept 0 file(s), removed 0`.

## 3j Tests that assume the whole icon folder
`grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v '/_kit/'`
```
tests/test_mediasetup.lua:106:  for _, name in ipairs(Media.ICONS) do known[name] = true end
tests/test_mediasetup.lua:139:    local fh = io.open("libs/LibKa0s/media/icons/" .. name .. ".tga", "rb")
tests/test_libka0s.lua:649:  local f = io.open("libs/LibKa0s/media/icons/info.tga", "rb")
tests/test_libka0s.lua:650:  assertTrue(f ~= nil, "libs/LibKa0s/media/icons/info.tga is missing: the folder was not copied whole")
```
All already narrowed to declared names (`info` is declared); nothing to fix.

## Dead stub mirrors
`grep -rn '__releaseChrome' . --include='*.lua' --exclude-dir=libs --exclude-dir=_kit` finds only history comments (tests/test_libka0s.lua:732, tests/test_surface_parity.lua:47). Nothing to remove.
