# LibKa0s v1.61.0 -> v1.62.0: the delta (LootHistory)

Copied from the tag `v1.62.0` (`5dc9f5d`, local tag), never from a working tree:
`git -C ../LibKa0s archive v1.62.0 LibKa0s testkit | tar -x -C <scratch>`.

## Claimed and actual version

- `grep -n '[Bb]undles' CLAUDE.md`: the provenance line claimed v1.61.0.
- The bytes agreed: `Options.lua` minor 25, `OptionsWidgets.lua` `WIDGETS_MINOR = 31`,
  `OptionsTabs.lua` `TABS_MINOR = 5`, which are v1.61.0's minors. No line/bytes disagreement.

## libs/LibKa0s (`diff -rq --strip-trailing-cr`, before the copy)

```
Files <tag>/LibKa0s/LibKa0s.xml and libs/LibKa0s/LibKa0s.xml differ
Files <tag>/LibKa0s/Options.lua and libs/LibKa0s/Options.lua differ
Only in <tag>/LibKa0s: OptionsCombat.lua
Only in <tag>/LibKa0s: OptionsIdList.lua
Only in <tag>/LibKa0s: OptionsIds.lua
Only in <tag>/LibKa0s: OptionsRegistry.lua
Files <tag>/LibKa0s/OptionsTabs.lua and libs/LibKa0s/OptionsTabs.lua differ
Files <tag>/LibKa0s/OptionsWidgets.lua and libs/LibKa0s/OptionsWidgets.lua differ
```

The byte diff (`diff -rq`, no strip) named the same eight entries: no line-ending-only drift.
No `Only in libs/LibKa0s` line, so nothing is deleted.

| File | Constant | v1.61.0 | v1.62.0 |
|---|---|---|---|
| `Options.lua` | `MINOR` | 25 | 26 |
| `OptionsRegistry.lua` | `REGISTRY_MINOR` | - | 1 (new: the page registry and the combat park, out of `Options.lua`) |
| `OptionsWidgets.lua` | `WIDGETS_MINOR` | 31 | 32 |
| `OptionsIds.lua` | `IDS_MINOR` | - | 1 (new: `O.ResolveId`, `O.UnnamedCandidates`, `O.ID_NAME_HINT`, `O.IdInput`, out of `OptionsWidgets.lua`) |
| `OptionsIdList.lua` | `IDLIST_MINOR` | - | 1 (new: `O.IdList`, out of `OptionsWidgets.lua`) |
| `OptionsTabs.lua` | `TABS_MINOR` | 5 | 6 |
| `OptionsCombat.lua` | `COMBAT_MINOR` | - | 1 (new: the combat lock's page chrome, out of `OptionsTabs.lua`) |

The Options major key moves from `25.31.5.7.4.1` to `26.1.32.1.1.6.1.7.4.1`. Every other file is
unchanged. No `NEEDS_*` floor rises, no major is added, and no member, descriptor field or row
field changes (v1.62.0 CHANGELOG).

## tests/_kit

`Kit.VERSION` 27 -> 31 (`grep -n 'Kit.VERSION' testkit/framework.lua tests/_kit/framework.lua`).

```
Files <tag>/testkit/README.md and tests/_kit/README.md differ
Files <tag>/testkit/framework.lua and tests/_kit/framework.lua differ
Only in <tag>/testkit: inventory.lua
Only in <tag>/testkit: prose_coverage.lua
Only in <tag>/testkit: prose_selftests.lua
Files <tag>/testkit/run-automated-tests.sh and tests/_kit/run-automated-tests.sh differ
Files <tag>/testkit/test_layout_cap.lua and tests/_kit/test_layout_cap.lua differ
Files <tag>/testkit/test_prose.lua and tests/_kit/test_prose.lua differ
```

- Revision 28: the suite inventory peels out of `framework.lua` into `inventory.lua`.
- Revision 29: `test_prose.lua` splits into `prose_coverage.lua` and `prose_selftests.lua`; its cases
  still register under `test_prose`.
- Revision 30 (ATS-20): an empty watch-list table in `RESULTS.md` prints its header, then `None.`.
- Revision 31 (ATS-21): the band table leaves out the files `Kit.layoutCap.exempt` names. This repo
  declares no exempt set, so its band table is unchanged.

Both payloads move together in one commit (the kit-revision pairing rule).

## Consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v /libs/ | grep -v /tests/`:
Bus, Compat, Core, DebugLog, Env, Item, Launcher, Lifecycle, Media, Options, Perf, Pool, Schema,
Slash, Widgets. Only `LibKa0s-Options-1.0` moved a minor, and this addon consumes it.

## Blockers (contract delta)

None. `grep -rn '__Attach[A-Za-z]*' . --include='*.lua' --exclude-dir=libs --exclude-dir=_kit`
finds no host call site: every `__Attach*` is library-internal. The release moves code between files
and states that no member, descriptor field or row field changes, and the headless suite (which
drives the settings page, the filter bar's id lists and the combat lock) is green on the new bytes.
