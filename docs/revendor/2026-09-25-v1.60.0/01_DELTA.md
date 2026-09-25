Delta: LibKa0s v1.58.0 -> v1.60.0 (span: v1.59.0 v1.60.0)

# 01 — Delta

Run: 2026-09-26, plan item DR-LH-01 of the 2026-09-25 diagnostics rollout
(`Ka0sAddonsCommonTasks/docs/2026-09-25-DIAGNOSTICS_COMMAND/`). The folder carries the plan's date,
as `2026-09-23-v1.58.0/` did. `/wow-addon:revendor-libka0s --tag v1.60.0` was run by an orchestrated
session, with its interview answered from the plan (see `02_CANDIDATES.md`). No filing, no push.
Target: this repo, branch `feat/2026-09-25-diagnostics-rollout`, cut from `master` @ `bd46eac`.

Source: the sibling checkout `../LibKa0s`, **tag `v1.60.0` (tag object `ac59511` -> commit
`bed0eb1`)**, extracted with `git -C ../LibKa0s archive v1.60.0 LibKa0s testkit | tar -x -C
<scratch>/`, never the working tree. The old side is the same extraction at `v1.58.0`.

`git -C ../LibKa0s log --oneline v1.58.0..v1.60.0` lists 17 commits: v1.59.0 (`e8faa5d`, `53c141a`,
merged as `c01db86`) and v1.60.0 (`58e3794` DR-LK-01 through `bed0eb1` DR-LK-06).

## Base pre-flight

The newest bundle, `docs/revendor/2026-09-23-v1.58.0/`, names new v1.58.0, and the provenance line
before this run named v1.58.0. v1.59.0 was never vendored here (it went to AuraMaster only, per its
changelog block), so this bundle spans it: its one change, WidgetsDragHandle minor 3, is recorded
below.

## 3a — Claimed version, before this run

`grep -n '[Bb]undles' CLAUDE.md` -> `CLAUDE.md:56`: Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s)
**v1.58.0** (MIT). No provenance line in `README.md`.

## 3b — Actual version, before this run

`grep -oE 'local (MAJOR, )?[A-Z_]*MINOR *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua` gives v1.58.0's
block (the left column of 3c), and `grep -n 'Kit.VERSION' tests/_kit/framework.lua` gives kit
revision **26**. `diff -rq --strip-trailing-cr` and `diff -rq` of the v1.58.0 extraction against
`libs/LibKa0s/` and `tests/_kit/` are both empty. The line and the bytes agreed before the copy.

## 3c — Per-file minor delta

File list read from the tag's `LibKa0s/LibKa0s.xml`: **22** `<Script>` rows, one more than v1.58.0
(`DebugLogDiagnostics.lua`, after `DebugLog.lua`). Same grep on both sides.

| File | v1.58.0 | v1.60.0 |
|---|---|---|
| `Core.lua` | 8 | 8 |
| `Env.lua` | 1 | 1 |
| `Compat.lua` | 1 | 1 |
| `Lifecycle.lua` | 2 | 2 |
| `Bus.lua` | 2 | 2 |
| `Schema.lua` | 2 | 2 |
| `Pool.lua` | 3 | 3 |
| `Item.lua` | 2 | 2 |
| `Media.lua` | 4 | 4 |
| `Widgets.lua` | 10 | 10 |
| **`WidgetsDragHandle.lua`** (`DRAG_MINOR`) | 2 | **3** (v1.59.0) |
| **`DebugLog.lua`** | 13 | **14** |
| **`DebugLogDiagnostics.lua`** (`DIAG_MINOR`) | absent | **1** (new file) |
| **`Slash.lua`** | 15 | **16** |
| `Launcher.lua` | 4 | 4 |
| `Options.lua` | 24 | 24 |
| `OptionsWidgets.lua` (`WIDGETS_MINOR`) | 31 | 31 |
| `OptionsTabs.lua` (`TABS_MINOR`) | 4 | 4 |
| `OptionsCompose.lua` (`COMPOSE_MINOR`) | 7 | 7 |
| `OptionsScroll.lua` (`SCROLL_MINOR`) | 4 | 4 |
| `Perf.lua` | 13 | 13 |
| `PerfPanel.lua` (`PANEL_MINOR`) | 5 | 5 |

No cross-major skew before the copy: every file was at v1.58.0's minor.

## 3d — Both diffs, before the copy

`diff -rq --strip-trailing-cr <scratch>/new/LibKa0s libs/LibKa0s` and the same for `testkit` vs
`tests/_kit`:

- differ: `DebugLog.lua`, `LibKa0s.xml`, `Slash.lua`, `WidgetsDragHandle.lua`
- only in the tag: `DebugLogDiagnostics.lua`
- kit differ: `README.md`, `framework.lua`; only in the tag: `test_diagnostics_contract.lua`
- **no `Only in libs/LibKa0s` or `Only in tests/_kit` line**: nothing removed upstream, so the copy
  deletes nothing.

Content diffs and byte diffs name the same files, so there is no line-ending-only drift.

## 3e — Consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v '/libs/' | grep -v '/tests/'`:

| Major | Lookup site |
|---|---|
| Core | `core/CoreSetup.lua:39` |
| Env | `core/EnvSetup.lua:42` |
| Compat | `core/Compat.lua:102` |
| Lifecycle | `core/LifecycleSetup.lua:47` |
| Bus | `core/Constants.lua:207` |
| Schema | `settings/Schema.lua:662` |
| Pool | `core/PoolSetup.lua:22` |
| Item | `core/ItemSetup.lua:26` |
| Media | `core/MediaSetup.lua:57` |
| Widgets | `core/WidgetsSetup.lua:85` |
| DebugLog | `core/DebugLogSetup.lua:25` |
| Slash | `settings/Slash.lua:233` |
| Launcher | `core/LauncherSetup.lua:42` |
| Options | `settings/OptionsSetup.lua:47` |

Perf has no lookup: settled (performance-§12, the documented deviation in `docs/ARCHITECTURE.md`),
and v1.60.0 does not move Perf. Nothing in the addon calls `DragHandle`
(`grep -rn DragHandle core modules settings` is empty), so WidgetsDragHandle minor 3 reaches no
host code.

## 3f — Kit revision and the pairing rule

`grep -n 'Kit.VERSION'`: tag `testkit/framework.lua:20` -> **27**; `tests/_kit/framework.lua:20` ->
**26**. The kit moves this time, so both payloads are copied whole in the same commit (the pairing
rule: a consumer on v1.9.0 or newer takes the kit that shipped with it, revision 11 or later).
Revision 27 adds `test_diagnostics_contract.lua`, which the suite inventory requires in
`tests/run.lua`'s suite list.

## 3g — Contract delta, and the blockers

Majors that moved **and** are consumed: **DebugLog** (13 -> 14.1) and **Slash** (15 -> 16).
Widgets moved only in `WidgetsDragHandle.lua`, whose surface this addon does not call.
`grep -rn '__Attach[A-Za-z]*' . --include='*.lua' --exclude-dir=libs --exclude-dir=_kit` is empty:
this addon hands the library no `__Attach*` members.

Read: `docs/api/DebugLog/version-13-docs.md` (Superseded) against `version-14.1-docs.md`, and
`docs/api/Slash/version-15-docs.md` against `version-16-docs.md`, both at the tag, plus the
v1.60.0 `CHANGELOG.md` block *What a consumer owes on re-vendoring v1.60.0*.

**Blockers**, each fixed in the vendor commit beside the payload and the line:

1. **DebugLog stub parity.** Minor 14 installs three instance members, `RunDiagnostics`,
   `BuildDiagnostics` and `DebugVerb` (`version-14.1-docs.md`; CHANGELOG v1.60.0 *Surface-parity
   churn*). `tests/test_surface_parity.lua` pins the stub in `core/DebugLogSetup.lua` against the
   live instance by name, so it goes red on the copy. Fix: the stub gains all three.
   `RunDiagnostics` prints `"%s is unavailable: the LibKa0s library did not load."` with
   `%s = "/lh diagnostics"` through `NS.Print`, writes nothing, and returns 0 (STD-14);
   `BuildDiagnostics` returns an empty report; `DebugVerb` answers `false` so the host keeps its
   own fallback.
2. **The live set.** Slash 16's `lib.LIVE_VERBS` gains `diagnostics` after `perf`
   (`version-16-docs.md`: "A host that passes a literal array does not, and adds `diagnostics`").
   This addon restates the set literally in `settings/Schema.lua` (`LIVE_WHILE_DISABLED`, the gate
   the library-less dispatcher also uses), and `tests/test_disabled.lua` pins that copy equal to
   `lib.LIVE_VERBS`. Fix: `diagnostics = true` joins the host table; the two test copies
   (`tests/test_disabled.lua`, `tests/test_slash.lua`) gain `"diagnostics"` in the library's order.
3. **The kit's new suite.** `tests/run.lua`'s suite list gains
   `{ name = "test_diagnostics_contract", dir = "tests/_kit/" }`; the inventory gate fails the run
   otherwise. With `Kit.diagnostics` unset it registers one declared skip until DR-LH-03.

**Not a blocker: the buffer.** `lib.MAX_BUFFER` 1500 -> 3000 and `lib.BUFFER_SLACK` 64 -> 128.
`grep -n 'MAX_BUFFER\|BUFFER_SLACK' tests/*.lua` is empty and no host test writes a literal 1500
into the console, so no suite moves. Three smoke-test lines quote the counter as `N / 1500 lines`
(`docs/smoke-tests.md:706,716,963`); those are the plan's DR-LH-05 doc sites, not this commit's.

**Not a blocker: `DebugLog.lua`'s `append` split.** Internal; `Add` keeps its gate and signature.
