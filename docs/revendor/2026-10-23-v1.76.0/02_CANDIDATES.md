# Candidates (LootHistory, LibKa0s v1.75.2 -> v1.76.0)

The run's owner scope (Ka0sAddonsCommonTasks `docs/2026-10-23-SIM_PREVIEW_MODE_STRIPS/inputs/OWNER_SCOPE.md`,
sections A and C) already decided every adoption below, and the run's `plan-data/items.json`
assigns each its own item. So no interview ran, nothing is declined and no issue is filed. Each is
implemented in its own commit after this re-vendor, not inside it.

## Class A: delivered on the copy, nothing to adopt

- **A simulation plays on its own (SimTimeline 3, SimPanel 5).** `/lh sim start <scenario>`, the
  picker's START, the idle Start row and RESTART now play every step at the host's step delay
  (`settings.sim.stepDelay`), still held by the ledger gate. A typed `step` or a row click holds the
  run; Resume continues it. Run all is gone; the controls are Pause/Resume, Restart and Stop. Evidence:
  tag `docs/api/Sim/version-2.3.5-docs.md:20-55`; CHANGELOG v1.76.0, "SimTimeline minor 3 and SimPanel
  minor 5".
- **`Resume` keeps `paused` when refused** as `building` or `done` (same evidence).
- **Kit 41 unchanged.**

## Class B: adopted by owner decision, each in its own item

| Candidate | Evidence | Files it touches | Blast radius | Decision |
|---|---|---|---|---|
| `W.TestStrip(parent, { kind = "sim" })` and `strip.kind` (Widgets 14) | tag `docs/api/Widgets/version-14.1.4.3.2-docs.md:27-56`, :768, :784; CHANGELOG v1.76.0, "Widgets minor 14" | `core/WidgetsSetup.lua` (`NS.MakeTestStrip` gains `kind`), `modules/Browser.lua` (one strip per mode, the header badge only on a degraded install) | additive: a second strip beside the test strip; the badge narrows to the degraded fallback | adopt, **LH-10** (OWNER_SCOPE A, C) |
| Reword what names Run all; re-true the controls and typed-start suites | CHANGELOG v1.76.0, *What a consumer owes* | `settings/Schema.lua:417` tooltip, comments in `settings/Schema.lua`, `defaults/Profile.lua`, `modules/Sim.lua`; README; `docs/ARCHITECTURE.md`, `docs/schema.md`, `docs/settings-panel.md`, `docs/smoke-tests.md`; `tests/test_sim_panel.lua`, `tests/test_sim_slash.lua` | strings, docs and tests only | adopt, **LH-01** (OWNER_SCOPE A.1, C.1) |

## Not candidates here

- **`LibKa0s-Glow-1.0`:** still unconsumed; this addon draws no glow (settled at v1.75.0).
