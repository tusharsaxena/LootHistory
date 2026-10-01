Delta: LibKa0s v1.65.0 -> v1.66.0

# The delta (LootHistory)

Copied from the tag `v1.66.0` (`e4c5ef7`, local annotated tag), never from a working tree or a
branch tip: `git -C ../LibKa0s archive v1.66.0 LibKa0s testkit | tar -x -C <scratch>`. Part of the
2026-10-01 GitHub issue pass (Ka0sAddonsCommonTasks `docs/2026-10-01-GITHUB_ISSUE_PASS/`, item
GI-LH-RV).

## Claimed and actual version

- `grep -n '[Bb]undles' CLAUDE.md`: the provenance line claimed v1.65.0.
- `git log -1 --format=%H -- libs/LibKa0s tests/_kit` is `fbc50fb` (DG-LH-01), whose CLAUDE.md
  names v1.65.0. The payload before the copy equals `git archive v1.65.0` byte for byte
  (`diff -rq` against both folders: `payload-matches`).
- Pre-flight: the newest single-tag bundle, `2026-09-29-v1.63.0`, states base v1.62.0, and the
  provenance line before its re-vendor (`e08c0dc`) named v1.62.0. No correction owed.
- Unrecorded vendored tags: v1.64.0 (`7ab6153`, `c13afda`) and v1.65.0 (`fbc50fb`) have no bundle.
  They are recorded in the span bundle `2026-10-01-v1.64.0-v1.65.0/`, written with this one.

## libs/LibKa0s (`diff -rq`, before the copy)

Changed: `DebugLog.lua`, `LibKa0s.xml`, `OptionsTabs.lua`, `OptionsWidgets.lua`, `Perf.lua`,
`Slash.lua`, `Widgets.lua`. Only in the tag: `PerfCommands.lua`, `PerfSampler.lua`,
`SlashParse.lua`, `WidgetsReorder.lua`. No `Only in libs/LibKa0s` line, so nothing is deleted.
`git -C ../LibKa0s diff --stat v1.65.0 v1.66.0 -- LibKa0s testkit`: 20 files changed, 2693
insertions(+), 1651 deletions(-).

Per-file loop over the tag's `LibKa0s.xml` (only the files whose constant moved):

| File | Constant | v1.65.0 | v1.66.0 |
|---|---|---|---|
| `Widgets.lua` | `MINOR` | 11 | 12 |
| `WidgetsReorder.lua` | `REORDER_MINOR` | (new) | 1 |
| `DebugLog.lua` | `MINOR` | 18 | 19 |
| `Slash.lua` | `MINOR` | 18 | 19 |
| `SlashParse.lua` | `PARSE_MINOR` | (new) | 1 |
| `OptionsWidgets.lua` | `WIDGETS_MINOR` | 33 | 34 |
| `OptionsTabs.lua` | `TABS_MINOR` | 7 | 8 |
| `Perf.lua` | `MINOR` | 13 | 14 |
| `PerfSampler.lua` | `SAMPLER_MINOR` | (new) | 1 |
| `PerfCommands.lua` | `COMMANDS_MINOR` | (new) | 1 |

No `NEEDS_*` floor rises and no major is added (v1.66.0 CHANGELOG). The payload goes from 28 to 32
files. The TOC loads the library through `libs\LibKa0s\LibKa0s.xml`, and `tests/run.lua` derives its
library load list from the same XML (`Loader.xmlFiles`), so neither needed a line for the four new
files. `tests/test_libka0s.lua`'s explicit `LIB_FILES` count list did, and gained them in XML order.

## tests/_kit

`Kit.VERSION` 34 -> 35 (`grep -n 'Kit.VERSION' testkit/framework.lua tests/_kit/framework.lua`).
Changed: `README.md`, `asserts.lua`, `framework.lua`, `inventory.lua`, `mock_base.lua`,
`run-automated-tests.sh`, `test_eol.lua`. New: `lizard_sighted.lua`, `test_lizard_sighted.lua`
(wired in `tests/run.lua` as `{ name = "test_lizard_sighted", dir = "tests/_kit/" }`; the inventory
gate fails the run until it is). Both payloads are copied whole in one commit (the kit-revision
pairing rule).

## After the copy

`diff -r` (bytes, no strip) of the tag's `LibKa0s/` against `libs/LibKa0s/` and of `testkit/`
against `tests/_kit/`: both empty.

## Consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' --include='*.lua' . | grep -v /libs/ | grep -v /tests/`:
Compat, Bus, Core, DebugLog, Env, Item, Launcher, Lifecycle, Media, Pool, Widgets, Options, Schema,
Slash. Perf is not looked up: this addon declines it (performance-§12 no-combat-path exemption,
`docs/combat-path-sweep.md`), a settled decline.

## Contract delta (3g)

Majors that moved a minor and that this addon consumes: Widgets, DebugLog, Slash, Options.

- **Widgets 11 -> 12**: `ReorderList` moved unchanged to `WidgetsReorder.lua`
  (`docs/api/Widgets/version-12.1.3-docs.md`, "What a host must change: nothing"). The host calls
  `W.ReorderList` from `core/WidgetsSetup.lua:150`, which the new file still publishes.
- **DebugLog 18 -> 19**: `lib:New`'s refusals and defaults moved to file-level helpers; no member,
  field, default or string moves (`version-19.2.1-docs.md`).
- **Slash 18 -> 19**: `ParseValue`/`FormatValue` take an optional resolver and a host `d.parse`
  receives it as a third argument. This addon's Slash descriptor supplies no `parse` and its `L`
  carries none of the `ERR_*` / `NONE` keys (`grep -n 'parse *=' settings/Slash.lua`: none), so it
  prints what it printed.
- **Options (OptionsWidgets 34, OptionsTabs 8)**: `RenderGrid`'s `parent`/`opts.gap` and the three
  `RenderTabbedSchema` opts are all off by default. This addon calls neither (`grep -rn
  'RenderGrid\|RenderTabbedSchema' core modules settings`: none); its `skipRender` "Price sources"
  row keeps its bucket, which the CHANGELOG names explicitly.

**Blockers: none.**

## Consumer tests that moved with the library

- `tests/test_libka0s.lua` "every file of LibKa0s.xml is vendored and loads": 28 -> 32 files; the
  four new files added to `LIB_FILES` in XML order.
- `tests/test_widgets.lua` "the seam builds a real library dropdown": re-pinned to Widgets minor
  12, with the reason (`ReorderList` moved, nothing else).

Neither is a library defect; both are this addon's pins of the version it was written against.
