Delta: LibKa0s v1.77.0 -> v1.78.0

Run by the 2026-10-25 skinning run, leg 1 (item `LH-RV`) on branch `feat/2026-10-25-skinning`,
following `/dev-copilot:wow-revendor-libka0s` from the installed dev-copilot 2.6.0. The run is
non-interactive: its own items decide the adoptions (Ka0sAddonsCommonTasks `docs/2026-10-25-SKINNING/`,
items LH-01 to LH-06), so nothing is interviewed and no issue is filed. v1.78.0 is a LOCAL annotated
tag on the LibKa0s run branch (`git -C ../LibKa0s rev-parse v1.78.0^{commit}` = `fb7b7a3`), unpushed
(`git -C ../LibKa0s ls-remote --tags origin v1.78.0` prints nothing); the payload was taken from it
with `git -C ../LibKa0s archive v1.78.0 LibKa0s testkit tools | tar -x -C <scratch>`. The tag was
never checked out.

## Step 0, pre-flight

LootHistory's newest single-tag bundle, `2026-10-24-v1.77.0`, states base v1.76.0 on line 1; the
provenance line before the v1.77.0 re-vendor named v1.76.0. **ok**, no correction owed.

## 3a. Claimed version and base

    grep -n '[Bb]undles' CLAUDE.md
    56:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.77.0 (MIT).

The payload matched the library at v1.77.0 (`git -C ../LibKa0s archive v1.77.0 LibKa0s testkit`
into a scratch folder, then `diff -rq` of both payloads: `tests/_kit` identical, `libs/LibKa0s`
differing only by the `Only in <tag>/media/icons` lines of the undeclared icons). **Base: v1.77.0.**

    git -C ../LibKa0s log --oneline v1.77.0..v1.78.0      # 25 commits, LK-00 .. LK-90
    git -C ../LibKa0s diff --stat v1.77.0 v1.78.0 -- LibKa0s testkit
    48 files changed, 7502 insertions(+), 776 deletions(-)

## 3b. Actual version

The vendored minors before the copy agreed with v1.77.0 (`grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR
...' libs/LibKa0s/*.lua`). No claim/fact disagreement.

## 3c. Per-file minor delta (the tag's `LibKa0s.xml` walked; unchanged files omitted)

| File | v1.77.0 | v1.78.0 |
|---|---|---|
| `Core.lua` | `LibKa0s-Core-1.0` 12 | 13 |
| `Media.lua` | `LibKa0s-Media-1.0` 5 | 6 |
| `Skin.lua` | (new) | `LibKa0s-Skin-1.0` 4 |
| `SkinDefs.lua` | (new) | `DEFS_MINOR` 4 |
| `SkinPaint.lua` | (new) | `PAINT_MINOR` 2 |
| `SkinPaintExtras.lua` | (new) | `EXTRAS_MINOR` 1 |
| `SkinPaintControls.lua` | (new) | `CONTROLS_MINOR` 1 |
| `SkinEUI.lua` | (new) | `EUI_MINOR` 1 |
| `SkinAce.lua` | (new) | `ACE_MINOR` 1 |
| `Widgets.lua` | `LibKa0s-Widgets-1.0` 15 | 16 |
| `WidgetsReorder.lua` | `REORDER_MINOR` 1 | 2 |
| `WidgetsDragHandle.lua` | `DRAG_MINOR` 5 | 6 |
| `WidgetsLineChart.lua` | `CHART_MINOR` 3 | 4 |
| `WidgetsAutocomplete.lua` | `AUTOCOMPLETE_MINOR` 3 | 4 |
| `WidgetsCopyWindow.lua` | (new) | `COPY_MINOR` 1 |
| `DebugLog.lua` | `LibKa0s-DebugLog-1.0` 21 | 22 |
| `DebugLogDiagnostics.lua` | `DIAG_MINOR` 3 | 4 |
| `DebugLogWindow.lua` | (new) | `WINDOW_MINOR` 1 |
| `Options.lua` | `LibKa0s-Options-1.0` 30 | 33 |
| `OptionsRegistry.lua` | `REGISTRY_MINOR` 2 | 3 |
| `OptionsWidgets.lua` | `WIDGETS_MINOR` 34 | 35 |
| `OptionsIds.lua` | `IDS_MINOR` 3 | 4 |
| `OptionsIdList.lua` | `IDLIST_MINOR` 5 | 6 |
| `OptionsTabs.lua` | `TABS_MINOR` 9 | 10 |
| `OptionsCombat.lua` | `COMBAT_MINOR` 2 | 3 |
| `OptionsCompose.lua` | `COMPOSE_MINOR` 11 | 12 |
| `OptionsScroll.lua` | `SCROLL_MINOR` 4 | 6 |
| `OptionsNav.lua` | `NAV_MINOR` 2 | 3 |
| `OptionsDrawer.lua` | `DRAWER_MINOR` 1 | 2 |
| `OptionsKeybinds.lua` | `KEYBINDS_MINOR` 4 | 5 |
| `OptionsAppearance.lua` | (new) | `APPEARANCE_MINOR` 1 |
| `PerfPanel.lua` | `PANEL_MINOR` 9 | 10 |
| `SimPanel.lua` | `SIM_PANEL_MINOR` 6 | 7 |

Every other file is at its v1.77.0 minor. Ten files are new (the seven of the new major
`LibKa0s-Skin-1.0`, and the peels `WidgetsCopyWindow.lua`, `DebugLogWindow.lua` and the new
thirteenth Options file `OptionsAppearance.lua`); none is removed. 51 files in the XML, 18 majors.
No cross-major skew.

`media/` gains five OFL faces and their licenses in `media/fonts/` (Barlow Regular and SemiBold,
Cinzel SemiBold, Atkinson Hyperlegible Regular and Bold) and the two Glass textures in
`media/textures/` (`glass-border.tga`, `glass-fill.tga`). The prune touches only `media/icons/`, so
all seven files ship.

## 3d. Both diffs

After `cp -r` of both payloads and before the prune, `diff -r --strip-trailing-cr` and `diff -rq` of
`<scratch>/LibKa0s` against `libs/LibKa0s`, and of `<scratch>/testkit` against `tests/_kit`, were all
empty, with no `Only in libs/LibKa0s` line (nothing removed upstream). After the prune the only
differences are `Only in <scratch>/LibKa0s/media/icons…` lines for the icons not declared.

## 3e. Consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua'` outside `libs/` and
`tests/`: Env (`core/EnvSetup.lua:46`, `core/Compat.lua:68`), DebugLog (`core/DebugLogSetup.lua:25`),
Bus (`core/Constants.lua:328`), Launcher (`core/LauncherSetup.lua:42`), Lifecycle
(`core/LifecycleSetup.lua:47`, `modules/Diagnostics.lua:129`), Core (`core/CoreSetup.lua:44`), Item
(`core/ItemSetup.lua:26`), Compat (`core/Compat.lua:169`), Pool (`core/PoolSetup.lua:22`), Sim
(`core/SimSeam.lua:52`, `modules/Sim.lua:358`), Perf (`core/PerfSetup.lua:23`), Widgets
(`core/WidgetsSetup.lua:108`), Media (`core/MediaSetup.lua:57`), Slash (`settings/Slash.lua:208`),
Options (`settings/OptionsSetup.lua:47`), Schema (`settings/Schema.lua:780`). Unconsumed: Glow (as
at v1.75.0) and the new **Skin**, which this run adopts in LH-01 (`core/SkinSetup.lua`). Every other
major that moved (Core, Media, Widgets, DebugLog, Options, Perf, Sim) is consumed.

## 3f. Kit revision

`grep -n 'Kit.VERSION'`: 43 in the tag's `testkit/framework.lua`, 42 in `tests/_kit/framework.lua`
before the copy. Kit 43 adds the opt-in paint recorder `mock_paint.lua` (and one comment line in
`mock_base.lua`). Both payloads move together (the pairing rule: a consumer on LibKa0s v1.9.0 or
newer takes kit revision 11 or newer in the same commit; satisfied by the whole copy).

## 3g. Contract delta, and Blockers

Read at the tag: the CHANGELOG v1.78.0 block (*What a consumer owes*),
`docs/api/Options/version-33.3.35.4.6.10.3.12.6.3.2.5.1-docs.md` (:64-66, :1738-1739, :2234),
`docs/api/Skin/version-4.4.2.1.1.1.1-docs.md`, `docs/api/Core/version-13-docs.md`,
`docs/api/Widgets/version-16.2.6.4.4.1-docs.md`, `docs/api/DebugLog/version-22.4.1.1-docs.md`,
`docs/api/Perf/version-15.1.1.10-docs.md`, `docs/api/Sim/version-2.3.7-docs.md`,
`docs/api/Media/version-6.1-docs.md` and `docs/api/testkit/version-43-docs.md`.
`grep -rn '__Attach[A-Za-z]*' . --include='*.lua' --exclude-dir=libs --exclude-dir=_kit`: no hits,
so no host-supplied member of an attach seam is in play.

- **Options 33 / OptionsAppearance 1: every Options degradation stub gains `AppearanceTab` and
  `AppearanceRows`** (CHANGELOG v1.78.0, *What a consumer owes*; `skinning-§3`), adopted or not.
  `Kit.assertSurfaceParity` went red at the copy (`tests/test_surface_parity.lua`, "parity: the
  Options stub carries the whole live surface": "AppearanceRows is missing (live: function);
  AppearanceTab is missing (live: function)"). **A blocker, fixed in the re-vendor commit:**
  `settings/OptionsSetup.lua`'s stub carries `AppearanceTab` (answering the inert entry
  `{ key = "Appearance", label = "Appearance", render = noop }`) and `AppearanceRows` (answering
  nil, as the live one does when it cannot draw). The lib-level `APPEARANCE_STRINGS` table is on
  the module, not the instance, and the parity gate does not ask for it.
- **Core 13, Widgets 16 (+ Reorder 2, DragHandle 6, LineChart 4, Autocomplete 4, CopyWindow 1),
  DebugLog 22 (+ Diagnostics 4, Window 1), PerfPanel 10, SimPanel 7, Options 31-33 and its files:**
  every control, window and settings page takes a skin owner, resolved at call time through
  `Skin:IsOwner`. No member is added, removed or renamed; an unregistered name, no name and a client
  without the Skin major paint as v1.77.0 did, call for call (the library's
  `tests/test_widgets_skin.lua`, `tests/test_options_skin.lua`, `tests/test_tool_windows_skin.lua`).
  Owes nothing until the addon registers an owner. Not blockers.
- **OptionsCompose 12 / OptionsWidgets 35:** `fromSkin` on `FontGroup`, `BorderGroup`, `BarGroup`
  and the row field `skinValue()` are opt-in; without `fromSkin` the rows are minor 11's. Not a
  blocker.
- **Media 6:** additive, every name and path of 5.1 resolves the same; `RegisterLSM` now also
  registers the five faces and the Glass border and background. In leg 1 LootHistory is the first
  consumer running v1.78.0, so those LSM keys resolve into this addon's folder until leg 2 ships the
  files everywhere (CHANGELOG, "In leg 1 the new keys resolve into LootHistory's folder"). Not a
  blocker; credited in the README (below).
- **Kit 43:** `mock_paint.lua` is opt-in; nothing here installs it yet. Not a blocker.

Other suites the copy turned red, re-trued minimally in the re-vendor commit (no behaviour change):
`tests/test_libka0s.lua` ("every file of LibKa0s.xml is vendored and loads": `LIB_FILES` gains the
ten new files in XML order, each under a "New in v1.78.0" comment; the exact v1.71.0, v1.75.0 and
v1.77.0 pins on the files that moved relax to floors with a "N since v1.78.0, pinned there" note;
a new "v1.78.0: the vendored minors and the kit revision match the release" case pins every moved
minor, the seven `LibKa0s-Skin-1.0` MODULES, OptionsAppearance 1, the two attached Appearance
members and `T.KIT_VERSION == 43`), and `tests/test_widgets.lua` (the Widgets pin moves from 15 to
16 with a note).

**Blockers:** one, the Options stub's two Appearance members, resolved in the re-vendor commit.
They are also listed as adoption blockers in `05_SUMMARY.md`.

## 3h. Tags vendored and never recorded

The audit's walk (payload commits plus `CLAUDE.md` rolls since the store's horizon) against the
recorded bundles: every vendored tag has a bundle (v1.77.0 included, `2026-10-24-v1.77.0`). No span
bundle.

## 3i. The icon declaration (decided, kept)

`grep -n 'LibKa0s icons:' CLAUDE.md` -> `57:LibKa0s icons: ban, chat, chevron-down, chevron-right,
circle-check, clear, close, confirm, copy, graph, info, lock, segment, sort-down, sort-up,
spreadsheet.`, the next non-blank line after the provenance line.

The item's plan-review resolution (d) asked for this grep before the prune:

    git -C ../LibKa0s grep -nE 'Icon\(|ICONS\[|IconMarkup\(' v1.78.0 -- LibKa0s/Skin*.lua \
      LibKa0s/OptionsAppearance.lua LibKa0s/Options*.lua LibKa0s/Widgets*.lua
    v1.78.0:LibKa0s/OptionsIdList.lua:236:  -- ... `KCM.Icon("info")` ... (a comment)
    v1.78.0:LibKa0s/OptionsIdList.lua:515:    local art = media and media.Icon and media.Icon(host, ID_HELP_ICON)
    v1.78.0:LibKa0s/OptionsIdList.lua:520:  local function idHelpIcon(spec)
    v1.78.0:LibKa0s/OptionsIdList.lua:585:    local path = idHelpIcon(spec)
    v1.78.0:LibKa0s/OptionsIdList.lua:696:  local function entryRemoveIcon(ctx, spec, entry, line)
    v1.78.0:LibKa0s/OptionsIdList.lua:871:    if iconStyle then entryRemoveIcon(ctx, spec, entry, line) end
    v1.78.0:LibKa0s/SkinPaintControls.lua:491:--- S.SquareIcon(frame, opts): ... (a comment)
    v1.78.0:LibKa0s/Widgets.lua:603:local function tintSearchIcon(icon, owner)
    v1.78.0:LibKa0s/Widgets.lua:675:      tintSearchIcon(box.icon, opts.owner)

Widened to `Core.lua`, `DebugLog*.lua`, `PerfPanel.lua` and `SimPanel.lua`: `Core.lua:277`
(`Icon(addonName, "close")`) and `DebugLogWindow.lua:173` (`Icon(addonName, icon)`, called at :221-222
with `"clear"` and `"copy"`, the calls that peeled out of `DebugLog.lua`). The only `Media.Icon`
names the library draws are still `close`, `clear`, `copy` and `info` (the tag's
`docs/releasing.md` :339-358, *Library-drawn icons are the host's to declare*), all four already
declared. `OptionsAppearance.lua`'s gate marks are the client's ready-check textures
(`Interface\RaidFrame\ReadyCheck-Ready` / `-NotReady`, :85-86), and no Skin primitive draws a
Media icon (CHANGELOG, "No primitive draws a `LibKa0s-Media-1.0` icon"). **No name added; the line is
kept unchanged (16 names).** Hand lists have drifted before (KickCD `tests/test_mediasetup.lua:28`,
WhatGroup `tests/test_mediasetup.lua:19`); the owner's in-client smoke is the backstop, since a
pruned icon still resolves to a path and draws blank.

## 3j. Tests that assume the whole icon folder

`grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v /_kit/`:
`tests/test_libka0s.lua:588-589` (the declared `info` file) and `tests/test_mediasetup.lua:100,133`
(the declaration check). Both read declared names only. No blocker.
