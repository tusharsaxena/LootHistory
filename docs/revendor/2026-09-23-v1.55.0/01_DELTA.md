# 01 — Delta: LibKa0s v1.54.2 → v1.55.0

Run: 2026-09-23, Steps 2–4 of `/wow-addon:revendor-libka0s` taken non-interactively by an
orchestrated session (suite phase 5). Steps 5–8 (candidates, adoption) are a later pass, so this
bundle carries `01_DELTA.md` only. No filing and no push. Target: this repo, branch
`suite/2026-09-22-standards-sweep` @ `8eb2638` (the prep commit, green on kit revision 24).

Source: the sibling checkout `../LibKa0s`, **tag `v1.55.0` (tag object `bb161b7` → commit
`6f9c5e0`)**, resolved with `git -C ../LibKa0s tag --sort=-v:refname | head -1` and extracted with
`git -C ../LibKa0s archive v1.55.0 LibKa0s testkit | tar -x -C <scratch>/`, never the working tree.
The tag is local to `../LibKa0s` and not yet pushed; `tests/test_vendor_sync.lua` compares against
the tag the provenance line names, so the local tag is enough.

```
git -C ../LibKa0s log --oneline v1.54.2..v1.55.0
  6f9c5e0 Record the v1.55.0 release run
  ae48f3f Make the v1.55.0 record true after the complexity split
  244c752 Bring collectKitHoles and repoKind under the CCN 15 ceiling
  be91249 Split Schema's Set and Validate under the CCN 15 gate
  18ca82a Release v1.55.0
  c051bef Re-vendor the standards reference, and make the v1.55.0 docs true
  06b4051 Add three majors: Compat, Bus, and the Schema runtime's portable half
  2a5e06f Test-kit revision 25: the four gates standard v2.63.0 already cites
```

## 3a — Claimed version, before this run

`grep -n '[Bb]undles' CLAUDE.md` → `CLAUDE.md:51`: Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s)
**v1.54.2** (MIT). No provenance line in `README.md` (same grep, no hit).

## 3b — Actual version, before this run

`grep -hoE 'local (MAJOR, )?([A-Z_]*MINOR) *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua`:
Core 7, DebugLog 12, Env 1, Item 1, Launcher 1, Lifecycle 1, Media 3, Options 23, OptionsCompose 7,
OptionsScroll 3, OptionsTabs 3, OptionsWidgets 30, Perf 12, PerfPanel 5, Pool 3, Slash 14,
Widgets 9, WidgetsDragHandle 2; kit revision 24 (`grep -n 'Kit.VERSION' tests/_kit/framework.lua`).
That is v1.54.2's block, so the line and the bytes agreed before the copy.

## 3c — Per-file minor delta

File list read from the tag's `LibKa0s/LibKa0s.xml` (21 `<Script>` rows); same grep on both sides.

| File | v1.54.2 | v1.55.0 |
|---|---|---|
| `Core.lua` | 7 | 7 |
| `Env.lua` | 1 | 1 |
| **`Compat.lua`** | absent | **1** (new major `LibKa0s-Compat-1.0`) |
| `Lifecycle.lua` | 1 | 1 |
| **`Bus.lua`** | absent | **1** (new major `LibKa0s-Bus-1.0`) |
| **`Schema.lua`** | absent | **1** (new major `LibKa0s-Schema-1.0`) |
| `Pool.lua` | 3 | 3 |
| `Item.lua` | 1 | 1 |
| `Media.lua` | 3 | 3 |
| `Widgets.lua` | 9 | 9 |
| `WidgetsDragHandle.lua` | 2 | 2 |
| `DebugLog.lua` | 12 | 12 |
| `Slash.lua` | 14 | 14 |
| `Launcher.lua` | 1 | 1 |
| `Options.lua` | 23 | 23 |
| `OptionsWidgets.lua` | 30 | 30 |
| `OptionsTabs.lua` | 3 | 3 |
| `OptionsCompose.lua` | 7 | 7 |
| `OptionsScroll.lua` | 3 | 3 |
| `Perf.lua` | 12 | 12 |
| `PerfPanel.lua` | 5 | 5 |

No existing file's minor moves. No cross-major skew. The XML gains three rows, in load order:
`Compat.lua` after `Env.lua`; `Bus.lua` and `Schema.lua` after `Lifecycle.lua`.

## 3d — Both diffs

`diff -rq --strip-trailing-cr <scratch>/LibKa0s libs/LibKa0s` and the byte form (no flag) report
the same set: `Only in <scratch>`: `Bus.lua`, `Compat.lua`, `Schema.lua`; `LibKa0s.xml` differs.
Content and bytes agree, so nothing has forked and there is no line-ending drift. No
`Only in libs/LibKa0s` line: nothing to delete.

`diff -rq --strip-trailing-cr <scratch>/testkit tests/_kit` and the byte form agree: `Only in
<scratch>`: `test_layout_cap.lua`; `README.md`, `framework.lua`, `run-automated-tests.sh`,
`test_eol.lua`, `test_prose.lua` differ. No `Only in tests/_kit` line.

## 3e — Consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v '/libs/' | grep -v '/tests/'`:

| Major | Lookup site |
|---|---|
| Core | `core/CoreSetup.lua:39` |
| Env | `core/EnvSetup.lua:41` |
| Lifecycle | `core/LifecycleSetup.lua:47` |
| Pool | `core/PoolSetup.lua:22` |
| Item | `core/ItemSetup.lua:26` |
| Media | `core/MediaSetup.lua:57` |
| Widgets | `core/WidgetsSetup.lua:85` |
| DebugLog | `core/DebugLogSetup.lua:25` |
| Launcher | `core/LauncherSetup.lua:40` |
| Slash | `settings/Slash.lua:209` |
| Options | `settings/OptionsSetup.lua:47` |

Perf is not looked up (ratified: `performance-§12` row in `docs/ARCHITECTURE.md`). The three new
majors — Compat, Bus, Schema — have no lookup anywhere: unadopted, for Step 5.

## 3f — Kit revision, and the pairing rule

`grep -n 'Kit.VERSION' <scratch>/testkit/framework.lua tests/_kit/framework.lua` → **24 → 25**.
Both payloads are copied whole in one commit, so the v1.9.0+ / kit ≥ 11 pairing rule holds by
construction; it is the reason the two payloads move together.

## 3g — Contract delta

**No library blocker.** The intersection of "a minor moved" (3c) and "this addon looks it up" (3e)
is empty: no existing file's minor moved. `git -C ../LibKa0s diff --stat v1.54.2 v1.55.0 -- docs/api`
touches only the three new majors' folders, `docs/api/README.md`, `docs/api/testkit/version-25-docs.md`,
and `docs/api/Widgets/version-9.1-docs.md` / `version-9.2-docs.md`, whose diff is header metadata
(Status / Superseded-by rows moved to the right document) and a "Moving to version 9.2" note for
a version this addon already carries. `grep -rn '__Attach[A-Za-z]*' . --include='*.lua'
--exclude-dir=libs --exclude-dir=_kit` finds no host-supplied `__Attach*` member.

### Blockers — kit contract, fixed in the vendor commit (or before it)

Revision 25 changes what the runner's suite list must say. These are not candidates: the suite
aborts from `Kit.run` until they are fixed.

1. **Shadow: a bare `"test_prose"`.** Revision 25 keys `Kit.assertSuiteInventory` by the pair
   (basename, directory). `tests/run.lua` declared a bare `"test_prose"` beside a local
   `tests/test_prose.lua`, so through revision 24 the local copy ran and was accepted as covering
   the kit's, which loaded nothing — LibKa0s v1.55.0's CHANGELOG names this repo among the six in
   that state. Fixed in the prep commit `8eb2638`: the local copy is deleted (`localization-§5`:
   one gate or the other, never both), the kit's is declared `{ name = "test_prose", dir =
   "tests/_kit/" }`. `8eb2638` also moved the local copy's single waiver (`core/LifecycleSetup.lua:66`,
   `:79`) to `tests/prose_waivers.lua` on the grounds that `h.cancelled` was AceTimer's field name.
   That reason was false: `h` is `NS.After`'s own wrapper table, which never enters the mock's timer
   queue, and the kit's live-timer survey (`tests/_kit/mock_record.lua:103`, `:106`, `:123`) never
   reads it. A follow-up commit respelled the field `h.canceled` and deleted `tests/prose_waivers.lua`,
   so the spelling is fixed rather than waived and the gate stays green.
2. **Undeclared kit suite `test_layout_cap`.** Arrives with the copy; declared `{ name =
   "test_layout_cap", dir = "tests/_kit/" }` in the vendor commit. Its census (`layout-§1`,
   `### Files over the 1500-line cap` under `## Documented deviations` in `docs/ARCHITECTURE.md`)
   landed in `8eb2638`: nothing is over the cap.
3. **Hand-typed lib load list.** `tests/test_libka0s.lua:20` (`LIB_FILES`) re-types the XML and
   its vendor-fidelity case asserts the count equals the XML's. It gains `Compat.lua` after
   `Env.lua`, and `Bus.lua`, `Schema.lua` after `Lifecycle.lua`, in the vendor commit. No
   `NO_LIBKA0S`-style skip list exists in this harness (`grep -rn NO_LIBKA0S tests/` is empty); the
   runner itself derives its load list from the XML (`tests/run.lua:21`).
