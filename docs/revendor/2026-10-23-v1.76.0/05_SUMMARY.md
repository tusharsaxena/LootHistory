# Summary (LootHistory)

LibKa0s v1.75.2 -> v1.76.0 from the local annotated tag (`9949368`, via `git archive`), base read
from the CLAUDE.md provenance line and confirmed against the payload. Minors: Widgets 13 -> 14,
SimTimeline 2 -> 3, SimPanel 4 -> 5; Sim 2 and every other file unchanged; test kit 41 unchanged.
Both payloads matched the tag under `diff -r` (content and bytes) before the prune.

**Span bundle.** v1.75.1 and v1.75.2 were vendored (`d04e849`, `7df4a87`) without a bundle, so
`docs/revendor/2026-10-23-v1.75.1-v1.75.2/` records them (two tags). No base correction owed.

**Delivered for free (class A):** a typed or clicked start plays the simulation on its own at the
step delay, the ledger gate still holding each step; a manual step or row click holds the run;
Resume keeps `paused` when refused; Run all is gone and the controls are Pause/Resume, Restart and
Stop.

**Contract blockers:** none. The Sim verb change moved two suites, re-trued minimally here
(`tests/test_sim_panel.lua`'s controls case clicks the first control, Resume, instead of
`controls.run`; `tests/test_sim_slash.lua`'s `loot [n]` case waits for the started run to finish
before counting). LH-01 owns the full re-true and the Run all wording.

**Icon declaration and prune.** `LibKa0s icons:` line kept unchanged (16 names). The tag's
`tools/prune-icons.lua` kept 17 files (16 `.tga` + the Open Iconic license) and removed 5,823 (the
undeclared Open Iconic marks, all of `phosphor/` and all of `game-icons/`), the same set as at
v1.75.2, so no icon file changes in git. No provenance split, no README credit change, no dead
stub mirror (`__releaseChrome` was removed at v1.75.0).

**Other ripple in the commit:** `tests/test_libka0s.lua` relaxes the v1.75.0, v1.75.1 and v1.75.2
pins on Widgets, SimTimeline and SimPanel to floors and adds a v1.76.0 case pinning the release;
`tests/test_widgets.lua` moves its Widgets pin to 14; `docs/test-cases.md` regenerated (Total
1697); the README test badge moves to 1697/1697.

**Adopted in this commit:** none. **Adoptions owed, each its own item:** the sim strip flavor
(LH-10), the Run all rewording and suite re-true (LH-01). **Declined:** none, so no issue filed.
**Unreached:** none.

**Gates.** `luacheck .` (bounded): 0 warnings / 0 errors in 138 files. `lua tests/run.lua`
(bounded): 1697 passed, 0 failed, 1 skipped. In-client smoke for the adoptions is the owner's,
under LH-01 and LH-10.

## Amendment: the tag moved for LK-91 (item LH-RV2)

The LOCAL annotated tag v1.76.0 moved `9949368` -> `7e81ff7` to carry LK-91 (a long step-panel
label ran under the command column: BankLedger's `/bl sim` "Deposit 1 x Flask ..." step). Both
payloads were replaced whole again from `git -C ../LibKa0s archive v1.76.0 LibKa0s testkit` and
pruned with the tag's `tools/prune-icons.lua` (16 declared, 17 kept, 5,823 removed, the same set,
so no icon change). Files that changed: `libs/LibKa0s/PerfPanel.lua` (PerfPanel 7 -> 8) and
`libs/LibKa0s/SimPanel.lua` (same minor 5; the library bumped it already in the unpublished
v1.76.0). Each now anchors the row label LEFT at the label column and RIGHT 8 px short of the
command, word wrap off, so a long label truncates with an ellipsis. `tests/_kit/` and every other
file are unchanged; kit revision 41. The provenance line already read v1.76.0 and is kept.
`diff -r` against the tag copy shows only the pruned icons.

Ripple: `tests/test_libka0s.lua` relaxes the v1.75.0 PerfPanel pin to a floor (`>= 7`) and pins
PerfPanel 8 in the v1.76.0 case. No case added or renamed, so `docs/test-cases.md` and the README
badge are unchanged. Nothing to adopt: the fix is delivered for free to `/lh sim`'s step panel.

Gates: `luacheck .` 0 warnings / 0 errors in 138 files; `lua tests/run.lua` 1702 passed, 0 failed,
1 skipped (`test_vendor_sync` against the moved tag).
