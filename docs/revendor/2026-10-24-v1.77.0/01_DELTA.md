Delta: LibKa0s v1.76.0 -> v1.77.0

Run by the 2026-10-24 keybindings, settings layout and frame strata run (item `LH-RV`) on branch
`feat/2026-10-24-keybinds-layout-strata`, following `/dev-copilot:wow-revendor-libka0s` from the
installed dev-copilot 2.4.0. The run is non-interactive: its own items decide the adoptions
(Ka0sAddonsCommonTasks `docs/2026-10-24-KEYBINDS_LAYOUT_STRATA/`, items LH-KB and LH-ZS), so nothing
is interviewed and no issue is filed. v1.77.0 is a LOCAL annotated tag on the LibKa0s run branch
(`78240f7`), unpushed (`git -C ../LibKa0s ls-remote --tags origin v1.77.0` prints nothing); the
payload was taken from it with `git -C ../LibKa0s archive v1.77.0 LibKa0s testkit tools | tar -x -C <scratch>`.

## Step 0, pre-flight

LootHistory's newest single-tag bundle, `2026-10-23-v1.76.0`, states base v1.75.2 on line 1; the
provenance line before its re-vendor commit `b853d9c` named v1.75.2. **ok**, no correction owed.

## 3a. Claimed version and base

    grep -n '[Bb]undles' CLAUDE.md
    56:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.76.0 (MIT).

The last payload commit is `06d6a6c` ("LH-RV2: Re-vendor LibKa0s from the moved v1.76.0 tag"), whose
provenance line names v1.76.0. The payload matched the library at v1.76.0 (`diff -rq` of both
payloads against `git archive v1.76.0`: `tests/_kit` identical, `libs/LibKa0s` differing only by the
`Only in <tag>/media/icons` lines of the undeclared icons). **Base: v1.76.0.**

    git -C ../LibKa0s log --oneline v1.76.0..v1.77.0
    78240f7 LK-90: close v1.77.0 with its release record (20261024-074358)
    3c2bb20 LK-90: split three functions over CCN 15 that the release run found
    ea2cb09 LK-90: close v1.77.0: version block, pointers, consumers, band
    0a5807d LK-13: Sync the Keybindings tab with Options -> Keybindings
    9ab9d37 LK-12: Add the Keybindings tab, OptionsKeybinds minor 2
    0b10ad3 LK-11: address review — refuse BUTTON1/BUTTON2 on the client chord route
    88dfa8a LK-11: Add OptionsKeybinds.lua minor 1, the key binding model
    66b7bd4 LK-20: Add O.StrataTooltip, the one shared strata-row tooltip
    7de587b LK-04: Close the IdList suggestion list at the start of combat
    f452d69 LK-03: Clamp the dropdown menu and the autocomplete list to the screen
    dda3ff9 LK-02: Add DragHandle level offset, ApplyLevel and ignoreParentAlpha
    665bf63 LK-01: Make the tool windows toplevel and re-raise shown StaticPopups
    8173cdb LK-10: Kit revision 42: binding mock, layer recorder, Bindings.xml check
    0a1683a LK-00: Open v1.77.0 with an unreleased CHANGELOG section
    9df6df8 Merge branch 'feat/2026-10-23-sim-preview-mode-strips'

`git -C ../LibKa0s diff --stat v1.76.0 v1.77.0 -- LibKa0s testkit`: 18 files, 1672 insertions, 34
deletions. Payload: `Core.lua`, `DebugLog.lua`, `LibKa0s.xml`, `Options.lua`, `OptionsCombat.lua`,
`OptionsCompose.lua`, `OptionsIds.lua`, the new `OptionsKeybinds.lua`, `PerfPanel.lua`,
`SimPanel.lua`, `Widgets.lua`, `WidgetsAutocomplete.lua`, `WidgetsDragHandle.lua`. Kit:
`README.md`, `framework.lua`, and the new `bindings_xml.lua`, `mock_bindings.lua`, `mock_layers.lua`.

## 3b. Actual version

The vendored minors before the copy agreed with v1.76.0 (`grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR
...' libs/LibKa0s/*.lua`). No claim/fact disagreement.

## 3c. Per-file minor delta (the tag's `LibKa0s.xml` walked; unchanged files omitted)

| File | v1.76.0 | v1.77.0 |
|---|---|---|
| `Core.lua` | `LibKa0s-Core-1.0` 11 | 12 |
| `Widgets.lua` | `LibKa0s-Widgets-1.0` 14 | 15 |
| `WidgetsDragHandle.lua` | `DRAG_MINOR` 4 | 5 |
| `WidgetsAutocomplete.lua` | `AUTOCOMPLETE_MINOR` 2 | 3 |
| `DebugLog.lua` | `LibKa0s-DebugLog-1.0` 20 | 21 |
| `Options.lua` | `LibKa0s-Options-1.0` 29 | 30 |
| `OptionsIds.lua` | `IDS_MINOR` 2 | 3 |
| `OptionsCombat.lua` | `COMBAT_MINOR` 1 | 2 |
| `OptionsCompose.lua` | `COMPOSE_MINOR` 7 | 8 |
| `OptionsKeybinds.lua` | (new) | `KEYBINDS_MINOR` 3 |
| `PerfPanel.lua` | `PANEL_MINOR` 8 | 9 |
| `SimPanel.lua` | `SIM_PANEL_MINOR` 5 | 6 |

Every other file is at its v1.76.0 minor. One file is new (`OptionsKeybinds.lua`, the twelfth
Options file); none is removed. No cross-major skew.

## 3d. Both diffs

After `cp -r` of both payloads and before the prune, `diff -r --strip-trailing-cr` and `diff -r` of
`<scratch>/LibKa0s` against `libs/LibKa0s`, and of `<scratch>/testkit` against `tests/_kit`, were all
empty. After the prune the only differences are `Only in <scratch>/LibKa0s/media/icons…` lines for
the icons not declared.

## 3e. Consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua'` outside `libs/` and
`tests/`: Env (`core/EnvSetup.lua:46`, `core/Compat.lua:68`), DebugLog (`core/DebugLogSetup.lua:25`),
Bus (`core/Constants.lua:328`), Launcher (`core/LauncherSetup.lua:42`), Lifecycle
(`core/LifecycleSetup.lua:47`, `modules/Diagnostics.lua:129`), Core (`core/CoreSetup.lua:44`), Item
(`core/ItemSetup.lua:26`), Compat (`core/Compat.lua:169`), Pool (`core/PoolSetup.lua:22`), Sim
(`core/SimSeam.lua:52`, `modules/Sim.lua:358`), Perf (`core/PerfSetup.lua:23`), Widgets
(`core/WidgetsSetup.lua:108`), Media (`core/MediaSetup.lua:57`), Slash (`settings/Slash.lua:208`),
Options (`settings/OptionsSetup.lua:47`), Schema (`settings/Schema.lua:763`). Unconsumed: Glow, as at
v1.75.0. Every major that moved (Core, DebugLog, Options, Perf, Sim, Widgets) is consumed.

## 3f. Kit revision

`grep -n 'Kit.VERSION'`: 42 in the tag's `testkit/framework.lua`, 41 in `tests/_kit/framework.lua`
before the copy. Both payloads move together (the pairing rule: a consumer on LibKa0s v1.9.0 or newer
takes kit revision 11 or newer in the same commit; satisfied by the whole copy).

## 3g. Contract delta, and Blockers

Read at the tag: `docs/api/Options/version-30.2.34.3.5.9.2.8.4.2.1.3-docs.md`,
`docs/api/Core/version-12-docs.md`, `docs/api/Widgets/version-15.1.5.3.3-docs.md`,
`docs/api/Sim/version-2.3.6-docs.md`, `docs/api/Perf/version-15.1.1.9-docs.md`,
`docs/api/DebugLog/version-21.3.1-docs.md`, `docs/api/testkit/version-42-docs.md`, and the
CHANGELOG v1.77.0 block's *What a consumer owes*.
`grep -rn '__Attach[A-Za-z]*' . --include='*.lua' --exclude-dir=libs --exclude-dir=_kit`: no hits, so
no host-supplied member of an attach seam is in play.

- **Options 30 / OptionsKeybinds 2 / OptionsCompose 8: every Options degradation stub gains
  `KeybindingsTab`, `KeybindRows`, `KEYBINDS_UNCHANGED` and `StrataTooltip`** (CHANGELOG v1.77.0,
  *What a consumer owes*; Options doc :60-72 and :1539-1541). `Kit.assertSurfaceParity` went red at
  the copy (`tests/test_surface_parity.lua`, "parity: the Options stub carries the whole live
  surface": 4 places). **A blocker, fixed in the re-vendor commit:** `settings/OptionsSetup.lua`'s
  stub carries the four members (an inert tab entry, a `KeybindRows` answering nil as the live one
  does when it cannot draw, the live sentence as a string, and a `StrataTooltip` answering `""`).
- **Core 12, DebugLog 21, PerfPanel 9, SimPanel 6:** the debug console, perf panel and sim panel are
  toplevel and re-raise a shown StaticPopup on show; `Core.RaiseStaticPopups()` is added. Owes
  nothing (CHANGELOG, "Core minor 12 ..."). Not a blocker.
- **Widgets 15 / WidgetsAutocomplete 3:** the dropdown menu and the autocomplete list are clamped to
  the screen; no member moves. **WidgetsDragHandle 5:** `spec.level`, `spec.ignoreParentAlpha`,
  `handle:ApplyLevel()`, all opt-in (Widgets doc :14, :45-49). Not blockers. The Widgets pin in
  `tests/test_widgets.lua` moves from 14 to 15 with a note.
- **OptionsIds 3 / OptionsCombat 2:** the IdList suggestion list closes at combat start; `__`
  members only, owes nothing.
- **Kit 42:** `bindings_xml.lua` (`Kit.assertBindingsXml`, `Kit.keybindThroughTab`),
  `mock_bindings.lua`, `mock_layers.lua`, all opt-in. No existing suite here asserts a
  Bindings.xml shape, so nothing went red on it and nothing is marked pending; the v2.88.0 shape is
  LH-KB's.

Other suites the copy turned red, re-trued minimally in the re-vendor commit (no behaviour change):
`tests/test_libka0s.lua` ("every file of LibKa0s.xml is vendored and loads": the explicit load list
gains `OptionsKeybinds.lua`; the v1.71.0, v1.75.0, v1.75.1, v1.75.2 and v1.76.0 pins on the files
that moved relax to floors, and a v1.77.0 case pins the release) and `tests/test_widgets.lua` (the
Widgets 15 pin).

**Blockers:** one, the Options stub's four members, resolved in the re-vendor commit.

## 3h. Tags vendored and never recorded

The audit's walk (payload commits plus `CLAUDE.md` rolls since the store's horizon) against the
recorded bundles printed nothing. No span bundle.

## 3i. The icon declaration (decided, kept)

`grep -n 'LibKa0s icons:' CLAUDE.md` -> `57:LibKa0s icons: ban, chat, chevron-down, chevron-right,
circle-check, clear, close, confirm, copy, graph, info, lock, segment, sort-down, sort-up,
spreadsheet.`, the next non-blank line after the provenance line. Kept unchanged: v1.77.0 adds no
library-drawn name (the tag's `docs/releasing.md`, *Library-drawn icons are the host's to declare*,
is still `close`, `clear`, `copy`, `info`; `OptionsKeybinds.lua` and `O.StrataTooltip` call no
`Icon(`). Hand lists have drifted before (KickCD `tests/test_mediasetup.lua:28`, WhatGroup
`tests/test_mediasetup.lua:19`); the owner's in-client smoke is the backstop, since a pruned icon
still resolves to a path and draws blank.

## 3j. Tests that assume the whole icon folder

`grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v /_kit/`:
`tests/test_libka0s.lua:570-571` (the declared `info` file) and `tests/test_mediasetup.lua:100,133`
(the declaration check). Both read declared names only. No blocker.
