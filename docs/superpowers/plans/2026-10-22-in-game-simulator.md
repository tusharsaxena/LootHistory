# In-game simulator (`/lh sim`) — implementation plan, as executed

**Spec:** [2026-10-22-in-game-simulator-design.md](../specs/2026-10-22-in-game-simulator-design.md)
**Issues:** LootHistory#37, LibKa0s#53, LibKa0s#54
**Branch:** `feat/2026-10-22-libka0s-issues-45-58` (the 2026-10-22 LibKa0s issues #45-#58 run)
**Run bundle:** Ka0sAddonsCommonTasks `docs/2026-10-22-LIBKA0S_ISSUES_45_58/` (items LH-06 to LH-14)

This plan records the work as it was executed. Each task landed as commits whose subject starts with
its item id; the commit bodies carry the full detail and each deviation. Like the spec, this file is
not edited after the run.

## Global constraints

- Host contract first, simulator second: the refactors (LH-06 to LH-09) are behavior-preserving and
  each lands with characterization tests before any Sim file.
- `core/Compat.lua` is the only route to a client read the simulator answers.
- No library code touches a SavedVariables store; the store swap is host code.
- Every file stays under the 1500-line cap; every new function at or below CCN 15.
- Green gate per commit: `lua tests/run.lua` (0 failed) and `luacheck .` (0/0), `docs/test-cases.md`
  regenerated (CRLF) when counts move, the README Tests badge with it.
- In-client smoke checks are the owner's and are never marked passed by an agent.

## Tasks

| Item | Task | Commits | Deviations recorded |
|---|---|---|---|
| LH-RV, RV2, RV3 | Re-vendor LibKa0s v1.75.0, then refresh twice as the local tag moved (Sim minor 2, SimTimeline minor 2, SimPanel minor 2) | `LH-RV: …`, `LH-RV2: …`, `LH-RV3: …` | None of substance |
| LH-06 | H1: route the simulator-relevant reads and read-side hooks through Compat (`NumLootItems`, `LootSourceGUID`, `Zone`, `PlayerMapID`, `InInstance`, `InGroup`, `PlayerInCombat`; hooks via `HookSecure`); `tests/test_compat_routing.lua` | b012b88 | Hook targets rawset on `_G` in the attribution suite's stubs; the capture check is scoped to file-scope locals; a Browser line cite moved |
| LH-07 | H3: one event table and one hook table, `core/Dispatch.lua` (`NS.EVENT_ROWS`, `NS.HOOK_ROWS`, `RegisterRows`, `Deliver`, `DeliverAll`); `tests/test_dispatch.lua` | 8870a9b, ecdd306 | `modules/Collector.lua` moved in the TOC so row order is stand-up order; hook rows spell the member field `tbl` plus `install`; `R:OnEvent` keeps its adapter; the spell row carries `unit` |
| LH-08 | `R:ResetState()`, `Attribution:ResetContexts()`, `NS.CancelDeferral(h)`, `NS.State.loginSettled` | f6ad14f, 93e2cf3 | None of substance |
| LH-09 | H4: session-aware store accessors (`NS.SimStores`, `historyStore()`, `Holdings:Store()`, `Rollup:Store()`, the coalescing read) | df0e98e, 1f99420 | `Rollup:SeedOnce` / `Prune` read the saved stores explicitly |
| LH-10 | H2, H5, H6: `core/SimSeam.lua` (seam, pure and guarded sets, stubs), then `modules/Sim.lua` (refusals, start, real-event split, world watch, stop steps, `NS.SimBlocks`, `SimStop` first in the stand-down) | d826356, 04d8030, 3ff63a7 | `HOLDINGS_CHANGED` on stop goes through `R:AnnounceHolders`; the purge confirm, the panel button and the first ledger-reset confirm are guarded too |
| LH-11 | The seeded world and its 23 providers (`modules/SimWorld.lua`), the event and hook drivers (`modules/SimDrivers.lua`) | c98eb56, f1e35a5 | Bonus count in itemString field 13; Midnight fixture ids; hook-first order for drivers whose post-hook reads the pre-call slot |
| LH-12 | The six scenarios and the ledger gate (`modules/SimScenario.lua`); `tests/test_sim_e2e.lua`, `tests/test_sim_store.lua` | c72dadb, 082b70f | The gate does not close on a flush deferred by simulated combat; key's keystone rides the MPLUS rows; ah posts three and checks the mailbox first; vendor destroys before repair; social's alt currency is not credited |
| LH-13 | H7, H8, H9: the panel descriptor (`modules/SimPanel.lua`), the `SIMULATION` marker, the `sim` verb with the `loot [n]` host verb, the diagnostics `sim` section, the parity case | 15e89e7, 4025740 | Marker cases in `tests/test_sim_panel.lua` (the browser suite is near the cap); the verb count pinned in `tests/test_profiles.lua` |
| LH-14 | Docs and the owed SIM smoke theme: this spec and plan, `docs/ARCHITECTURE.md` (module map, message bus, the simulator section with H1-H10, known limitations), `docs/data-flow.md` (`## Simulator`), `docs/slash-dispatch.md`, `docs/compat-layer.md`, `docs/disabled-state.md`, `docs/debug.md`, `docs/browser.md`, `docs/smoke-tests.md` (SIM-1 to SIM-7), the README | `LH-14: …` | See the commit body |

## Review focus (as executed)

1. The (target, event) registration set is unchanged by the dispatch table (`tests/test_dispatch.lua`
   against a pre-refactor snapshot).
2. `NS.SimSeam:Unwrapped()` is empty after the whole addon loads, and every Compat member is
   classified (`tests/test_sim_seam.lua`).
3. Every scenario writes exactly its pinned rows, by step and by run, with no duplicate, and ends
   settled (`tests/test_sim_e2e.lua`).
4. The saved `history`, `holdings` and `daily` serialize byte-identically before start and after
   stop for every scenario (`tests/test_sim_store.lua`).
5. Every refusal, every automatic stop and every destructive-surface refusal prints its one line
   (`tests/test_sim_session.lua`).

## Owed

The in-client checks SIM-1 to SIM-7 (`docs/smoke-tests.md`, the item's SM-LH-20 to SM-LH-26), listed
under Pending sign-off until the owner records a pass.
