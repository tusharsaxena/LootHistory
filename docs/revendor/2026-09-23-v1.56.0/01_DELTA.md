Delta: LibKa0s v1.55.0 -> v1.56.0

# 01 — Delta

Run: 2026-09-24, plan item RV-LH of the 2026-09-23 review and standards-audit remediation (the
folder carries the plan's date). Steps 2–4 of the local `../wow-addon/commands/revendor-libka0s.md`
(as amended by WA-01) were taken by hand and non-interactively by an orchestrated session. Steps 5–8
(candidates, adoption) are not taken here: this addon's M3 items own them, so the bundle carries
`01_DELTA.md` and `05_SUMMARY.md` only. No filing, no push. Target: this repo, branch
`feat/2026-09-23-review-audit-remediation` @ `36072e5`.

Source: the sibling checkout `../LibKa0s`, **tag `v1.56.0` (tag object `4622018` -> commit
`514fc0a`)**, extracted with `git -C ../LibKa0s archive v1.56.0 LibKa0s testkit | tar -x -C <scratch>/`,
never the working tree. The tag is local to `../LibKa0s` and not yet pushed;
`tests/test_vendor_sync.lua` compares against the tag the provenance line names, so the local tag is
enough (it passes on this copy).

`git -C ../LibKa0s log --oneline v1.55.0..v1.56.0` lists 53 commits: the LK-01..LK-34 items of the
same plan, plus `2c6689e`, `51cc901`, the merge `46ccaa6` and the review record `ab6404d`.

## Base pre-flight

The newest single-tag bundle, `docs/revendor/2026-09-23-v1.55.0/`, names base v1.54.2 and new
v1.55.0 on line 1, and the provenance line before this run named v1.55.0. The chain is unbroken, no
tag went unrecorded, and no span bundle is owed.

## 3a — Claimed version, before this run

`grep -n '[Bb]undles' CLAUDE.md` -> `CLAUDE.md:51`: Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s)
**v1.55.0** (MIT). No provenance line in `README.md`.

## 3b — Actual version, before this run

`grep -hoE 'local (MAJOR, )?([A-Z_]*MINOR) *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua` gives
v1.55.0's block (the left column of 3c), and kit revision 25 (`grep -n 'Kit.VERSION'
tests/_kit/framework.lua`). The line and the bytes agreed before the copy.

## 3c — Per-file minor delta

File list read from the tag's `LibKa0s/LibKa0s.xml` (21 `<Script>` rows, unchanged from v1.55.0);
same grep on both sides.

| File | v1.55.0 | v1.56.0 |
|---|---|---|
| **`Core.lua`** | 7 | **8** |
| `Env.lua` | 1 | 1 |
| `Compat.lua` | 1 | 1 |
| **`Lifecycle.lua`** | 1 | **2** |
| **`Bus.lua`** | 1 | **2** |
| **`Schema.lua`** | 1 | **2** |
| `Pool.lua` | 3 | 3 |
| **`Item.lua`** | 1 | **2** |
| **`Media.lua`** | 3 | **4** |
| **`Widgets.lua`** | 9 | **10** |
| `WidgetsDragHandle.lua` | 2 | 2 |
| **`DebugLog.lua`** | 12 | **13** |
| **`Slash.lua`** | 14 | **15** |
| **`Launcher.lua`** | 1 | **2** |
| **`Options.lua`** | 23 | **24** |
| **`OptionsWidgets.lua`** | 30 | **31** |
| **`OptionsTabs.lua`** | 3 | **4** |
| `OptionsCompose.lua` | 7 | 7 |
| **`OptionsScroll.lua`** | 3 | **4** |
| **`Perf.lua`** | 12 | **13** |
| `PerfPanel.lua` | 5 | 5 |

No major changes, no file is added or removed, and the XML is byte-identical. Composite keys per the
v1.56.0 CHANGELOG: Options 24.31.4.7.4, Perf 13.5, Widgets 10.2.

## 3d — Both diffs

`diff -rq <scratch>/LibKa0s libs/LibKa0s` and `diff -rq --strip-trailing-cr` report the same set:
`Bus.lua`, `Core.lua`, `DebugLog.lua`, `Item.lua`, `Launcher.lua`, `Lifecycle.lua`, `Media.lua`,
`Options.lua`, `OptionsScroll.lua`, `OptionsTabs.lua`, `OptionsWidgets.lua`, `Perf.lua`,
`Schema.lua`, `Slash.lua`, `Widgets.lua` differ. No `Only in` line on either side. Content and bytes
agree, so nothing forked and there is no line-ending drift.

`diff -rq <scratch>/testkit tests/_kit` and the `--strip-trailing-cr` form agree: `Only in
<scratch>`: `asserts.lua`, `mock_events.lua`, `prose_lists.lua`; `README.md`, `framework.lua`,
`mock_base.lua`, `mock_record.lua`, `run-automated-tests.sh`, `test_eol.lua`, `test_layout_cap.lua`,
`test_prose.lua` differ. No `Only in tests/_kit` line: nothing to delete.

After the copy (`rm -rf` then `cp -r`, runner kept executable) both `diff -r` runs are empty.

## 3e — Consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v '/libs/' | grep -v '/tests/'`:

| Major | Lookup site | Minor moved? |
|---|---|---|
| Core | `core/CoreSetup.lua:39` | 7 -> 8 |
| Env | `core/EnvSetup.lua:41` | no |
| Compat | `core/Compat.lua:94` | no |
| Lifecycle | `core/LifecycleSetup.lua:47` | 1 -> 2 |
| Bus | `core/Constants.lua:201` | 1 -> 2 |
| Pool | `core/PoolSetup.lua:22` | no |
| Item | `core/ItemSetup.lua:26` | 1 -> 2 |
| Media | `core/MediaSetup.lua:57` | 3 -> 4 |
| Widgets | `core/WidgetsSetup.lua:85` | 9 -> 10 |
| DebugLog | `core/DebugLogSetup.lua:25` | 12 -> 13 |
| Launcher | `core/LauncherSetup.lua:40` | 1 -> 2 |
| Options | `settings/OptionsSetup.lua:47` | 23 -> 24 (and its three sub-files) |
| Slash | `settings/Slash.lua:209` | 14 -> 15 |
| Schema | `settings/Schema.lua:587` | 1 -> 2 |

Perf is still not looked up (ratified `performance-§12` row in `docs/ARCHITECTURE.md`), so its move
to 13 reaches this addon only as bytes.

## 3f — Kit revision, and the pairing rule

`grep -n 'Kit.VERSION' <scratch>/testkit/framework.lua tests/_kit/framework.lua` -> **25 -> 26**.
Both payloads are copied whole in one commit, so the pairing rule holds by construction.

## 3g — Contract delta

`git -C ../LibKa0s diff --stat v1.55.0 v1.56.0 -- docs/api` adds a new live document and member
manifest for every major whose minor moved (Bus 2, Core 8, DebugLog 13, Item 2, Launcher 2,
Lifecycle 2, Media 4, Options 24.31.4.7.4, Perf 13.5, Schema 2, Slash 15, Widgets 10.2) plus
`testkit/version-26-docs.md`; the superseded documents change only header metadata. The CHANGELOG
calls the release additive: no `NEEDS_*` floor rises and no major changes.

### Blockers — reds on the copy, left for this addon's M3 items

The remediation plan item says this commit makes no other edit, so the two reds below are recorded
and not fixed here (a departure from the playbook's "fix the host in Step 4's commit", which the
plan overrides). Run on the copy: 856 passed, 2 failed, 858 total; `luacheck .` 0 / 0 in 65 files.

1. **Schema instance stub lacks `SetMany`.** `tests/test_surface_parity.lua:210` fails:
   `schema instance vs host stub: the degraded stub diverges from the live surface in 1 place(s) —
   SetMany is missing (live: function)`. Schema minor 2 adds the member
   (`../LibKa0s/docs/api/Schema/version-2-docs.md:25`); the v1.56.0 CHANGELOG's "What a consumer
   owes" names LootHistory among the hosts whose instance stub (`settings/Schema.lua:496`,
   `stubLib:New`) must gain it.
2. **Widgets adoption pin.** `tests/test_widgets.lua:106` fails: `this adoption is written against
   Widgets minor 9 (expected 9, got 10)`. Minor 10 moves `ReorderList`'s drag poll onto the ghost
   (`../LibKa0s/docs/api/Widgets/version-10.2-docs.md:26-47`); this addon's cascade is dragged
   through that widget (`settings/Panel.lua`), so the pin is re-read against 10.2 and re-stamped, not
   loosened.

### Not blockers

- The Core seam parity case pins `NS` members, not the library's lib-level surface, so Core minor
  8's `SafeRegisterEvent` family is not owed by a stub here; it stays green.
- The Slash `DisabledLine` pin with `Kit.assertLibraryConstant`
  (`../LibKa0s/docs/api/Slash/version-15-docs.md:598-613`) is asked for, not enforced; the suite is
  green without it.
- Kit revision 26's behavioral flips (frames start shown, the raising AceDB fake, recorded
  `EventRegistry` callbacks, lone-CR counting, store-root prose, `§` in kit case names, perf skip
  reason (2)) redden nothing here beyond the two above. The `§` case names mean
  `docs/test-cases.md` is stale until it is regenerated, which a later item owns.
- `grep -rn '__Attach[A-Za-z]*' . --include='*.lua' --exclude-dir=libs --exclude-dir=_kit` finds no
  host-supplied `__Attach*` member, so `RenderTabbedSchema`'s move to `OptionsTabs.lua` does not
  touch this addon.
