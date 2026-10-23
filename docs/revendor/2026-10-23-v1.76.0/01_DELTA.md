Delta: LibKa0s v1.75.2 -> v1.76.0

Run by the 2026-10-23 sim auto-run, QC preview selector, mode strips and MM/KCD simulators run
(item `LH-RV`) on branch `feat/2026-10-23-sim-preview-mode-strips`, following
`/dev-copilot:wow-revendor-libka0s` from the installed dev-copilot 2.4.0. The run is
non-interactive: the run's own items decide every adoption (Ka0sAddonsCommonTasks
`docs/2026-10-23-SIM_PREVIEW_MODE_STRIPS/`), so nothing is interviewed and no issue is filed.
v1.76.0 is a LOCAL annotated tag on the LibKa0s run branch (`9949368`), unpushed; the payload was
taken from it with `git -C ../LibKa0s archive v1.76.0 LibKa0s testkit tools | tar -x -C <scratch>`.

## Step 0, pre-flight

LootHistory's newest single-tag bundle, `2026-10-22-v1.75.0`, states base v1.71.0 on line 1; the
provenance line before its re-vendor commit `bd1b558` named v1.71.0. **ok**, no correction owed.

## 3a. Claimed version and base

    grep -n '[Bb]undles' CLAUDE.md
    56:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.75.2 (MIT).

The last payload commit is `7df4a87` ("Re-vendor LibKa0s v1.75.2 (SimPanel minor 4)"), whose
provenance line names v1.75.2. The payload matched the library at v1.75.2 (`diff -rq` of both
payloads against `git archive v1.75.2`: `tests/_kit` identical, `libs/LibKa0s` differing only by
the `Only in <tag>/media/icons` lines of the undeclared icons). **Base: v1.75.2.**

    git -C ../LibKa0s log --oneline v1.75.2..v1.76.0
    9949368 LK-90: address review — name tests/test_sim_panel.lua in the CLAUDE.md 1000-1500 band
    82d76f6 LK-90: close v1.76.0 with its release record (20261023-150627)
    f9ce82a LK-90 (1/2): release v1.76.0: version block, pointers, consumers
    37e6b69 LK-25: add the preview and simulation re-look to the release checklist
    d5fa6e9 LK-10: give W.TestStrip a simulation flavor (Widgets minor 14)
    d728cc4 LK-01: play a simulation on its own and drop Run all (Sim 2.3.5)
    05cb400 LK-00: open v1.76.0 with an unreleased CHANGELOG block
    99fb662 Merge branch 'fix/2026-10-23-sim-picker-step-delay' (LibKa0s v1.75.2: SimPanel minor 4)

`git -C ../LibKa0s diff --stat v1.75.2 v1.76.0`: 30 files; the payload files are
`LibKa0s/SimPanel.lua`, `LibKa0s/SimTimeline.lua` and `LibKa0s/Widgets.lua`. No `testkit/` file
moved.

## 3b. Actual version

The vendored minors before the copy agreed with v1.75.2 (`grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR
...' libs/LibKa0s/*.lua`): Widgets 13, SimTimeline 2, SimPanel 4. No claim/fact disagreement.

## 3c. Per-file minor delta (the tag's `LibKa0s.xml` walked; unchanged files omitted)

| File | v1.75.2 | v1.76.0 |
|---|---|---|
| `Widgets.lua` | `LibKa0s-Widgets-1.0` 13 | 14 |
| `SimTimeline.lua` | `TIMELINE_MINOR` 2 | 3 |
| `SimPanel.lua` | `SIM_PANEL_MINOR` 4 | 5 |

Every other file is at its v1.75.2 minor; `Sim.lua` stays 2. No file is new or removed. No
cross-major skew.

## 3d. Both diffs

After `cp -r` of both payloads and before the prune, `diff -r --strip-trailing-cr` and `diff -r`
of `<scratch>/LibKa0s` against `libs/LibKa0s`, and of `<scratch>/testkit` against `tests/_kit`, were
all empty. After the prune the only differences are `Only in <scratch>/LibKa0s/media/icons…` lines
for the icons not declared (210 lines under `diff -rq`, directories collapsed).

## 3e. Consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v /libs/ | grep -v /tests/`:
Env (`core/EnvSetup.lua:46`, `core/Compat.lua:68`), DebugLog (`core/DebugLogSetup.lua:25`), Bus
(`core/Constants.lua:328`), Launcher (`core/LauncherSetup.lua:42`), Lifecycle
(`core/LifecycleSetup.lua:47`, `modules/Diagnostics.lua:129`), Core (`core/CoreSetup.lua:44`), Item
(`core/ItemSetup.lua:26`), Compat (`core/Compat.lua:169`), Pool (`core/PoolSetup.lua:22`), Sim
(`core/SimSeam.lua:52`, `modules/Sim.lua:358`), Perf (`core/PerfSetup.lua:23`), Widgets
(`core/WidgetsSetup.lua:106`), Media (`core/MediaSetup.lua:57`), Slash (`settings/Slash.lua:208`),
Options (`settings/OptionsSetup.lua:47`), Schema (`settings/Schema.lua:763`). Unconsumed: Glow, as
at v1.75.0. Both majors that moved (Sim, Widgets) are consumed.

## 3f. Kit revision

`grep -n 'Kit.VERSION'`: 41 in the tag's `testkit/framework.lua` and 41 in `tests/_kit/framework.lua`.
Unchanged. Both payloads still move together (the pairing rule: a consumer on LibKa0s v1.9.0 or
newer takes kit revision 11 or newer in the same commit; satisfied by the whole copy).

## 3g. Contract delta, and Blockers

Read: `docs/api/Sim/version-2.2.4-docs.md` -> `version-2.3.5-docs.md` and
`docs/api/Widgets/version-13.1.4.3.2-docs.md` -> `version-14.1.4.3.2-docs.md` at the tag.
`grep -rn '__Attach[A-Za-z]*' . --include='*.lua' --exclude-dir=libs --exclude-dir=_kit`: no hits,
so no host-supplied member of an attach seam is in play.

- **Sim 2.3.5 (`version-2.3.5-docs.md:22-55`, *What changed at this version*):** no member is added
  or removed, but the verb layer changes what it does with unchanged signatures. A typed `start` /
  `restart` (and the panel's `START`, Start row and `RESTART`) now arm the run so the simulation
  plays on its own; a manual `step` or a row click holds the run paused; `Resume` keeps `paused` when
  refused; the controls are Pause/Resume, Restart and Stop and `RUN_ALL` leaves `Sim.STRINGS`.
  The members `sim:Start{}` and `sim:Restart()` arm nothing. LootHistory's host members
  (`Host.Prepare`, `stepDelay`, the ledger gate in `modules/Sim.lua`) are called exactly as before;
  the gate still holds each step of an armed run. No locale or module here overrides `RUN_ALL`
  (`grep -rn RUN_ALL locales modules`: nothing). **Not a code blocker.** Two suites were written
  against the old verb behaviour and are re-trued minimally in the re-vendor commit:
  - `tests/test_sim_panel.lua`, "the controls run, pause, resume, restart and stop": `controls.run`
    no longer exists; the case now asserts it is nil and clicks the first control (Resume, which
    sends `run`). LH-01 replaces the case whole.
  - `tests/test_sim_slash.lua`, "`loot [n]` plays n self-loot lines": a typed start now plays the
    scenario's own steps, so the case waits for that run to finish before counting the `loot` verb's
    rows.
  Strings and docs that name Run all (the step-delay tooltip at `settings/Schema.lua:417`, comments,
  README, `docs/schema.md`, `docs/settings-panel.md`, `docs/ARCHITECTURE.md`, `docs/smoke-tests.md`)
  are the CHANGELOG's "What a consumer owes" rewording and belong to LH-01.
- **Widgets 14 (`version-14.1.4.3.2-docs.md:27-56`, :768, :784):** additive. `opts.kind` and
  `strip.kind` are new; an existing `W.TestStrip` call (this addon's `NS.MakeTestStrip`,
  `core/WidgetsSetup.lua:290-293`) still draws the amber strip. Not a blocker. The Widgets pin in
  `tests/test_widgets.lua` moves from 13 to 14 with a note.

**Blockers:** none.

## 3h. Tags vendored and never recorded

The audit's walk (payload commits plus `CLAUDE.md` rolls since the store's horizon) against the
recorded bundles printed `v1.75.1` and `v1.75.2`: `d04e849` and `7df4a87` re-vendored them without a
bundle (the v1.75.0 bundle's `06_REFRESH.md` and `07_REFRESH.md` cover the moved v1.75.0 tag only).
One consolidated span bundle is written beside this one: `docs/revendor/2026-10-23-v1.75.1-v1.75.2/`.

## 3i. The icon declaration (decided, kept)

`grep -n 'LibKa0s icons:' CLAUDE.md` -> `57:LibKa0s icons: ban, chat, chevron-down, chevron-right,
circle-check, clear, close, confirm, copy, graph, info, lock, segment, sort-down, sort-up,
spreadsheet.`, the next non-blank line after the provenance line. Kept unchanged: v1.76.0 adds no
library-drawn name (the tag's CHANGELOG, *What a consumer owes*: a host that passes `kind = "sim"`
still declares `info` if it passes the `info` mark, which this one does and already declares). Hand
lists have drifted before (KickCD `tests/test_mediasetup.lua:28`, WhatGroup
`tests/test_mediasetup.lua:19`); the owner's in-client smoke is the backstop, since a pruned icon
still resolves to a path and draws blank.

## 3j. Tests that assume the whole icon folder

`grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v /_kit/`:
`tests/test_libka0s.lua:567-568` (the declared `info` file) and `tests/test_mediasetup.lua:100,133`
(the declaration check from v1.75.0). Both read declared names only. No blocker.
