# Candidates (LootHistory, LibKa0s v1.71.0 -> v1.75.0)

The run's owner scope (`Ka0sAddonsCommonTasks/docs/2026-10-22-LIBKA0S_ISSUES_45_58/inputs/OWNER_SCOPE.md`,
section A) already decided every adoption below, and the run's `items.tsv` assigns each one its own
M3 item. So no interview ran, nothing is declined, and no issue is filed. Each candidate is
implemented in its own commit after this re-vendor, not inside it. Blockers (01_DELTA.md, a-i) are
not candidates and are not repeated here.

## Class A: delivered on the copy, nothing to adopt

- **Options 29: a structural refresh keeps the page's scroll offset.** Every page this addon
  refreshes (the Filters id lists, the AH Price tab) now stays where the player was.
- **Core 11, DebugLog 20, OptionsIdList 5, PerfPanel 7:** comment corrections only.
- **DebugLogDiagnostics 3:** the diagnostics report's `LibKa0s running:` line lists Glow, Sim,
  SimTimeline and SimPanel when they are loaded. This addon does not parse its own report.
- **Kit 39-41:** `__fireUnconditional` reach, `assertLatchHoldOrder` (optional), the icon gate in
  `test_vendor_sync.lua`, and the crashed-lizard bucket in the complexity suite.

## Class B and C: adopted by owner decision, each in its own item

| Candidate | Evidence | Files it touches | Blast radius | Decision |
|---|---|---|---|---|
| `W.SearchBox(parent, width, opts)` (Widgets 13) | tag `docs/api/Widgets/version-13.1.4.3.2-docs.md`, *What changed*; CHANGELOG v1.75.0 "Widgets minor 13: W.SearchBox (#52)" | `modules/BrowserFilterBar.lua`, `core/WidgetsSetup.lua` (an `NS.MakeSearchBox` seam) | replaces the hand-built filter-bar search box | adopt, **LH-03** (OWNER_SCOPE A #52) |
| `W.TestStrip(parent, opts)` (Widgets 13) | same document; CHANGELOG "Widgets minor 13: W.TestStrip (#48)" | `modules/Browser.lua` / the filter bar, `core/WidgetsSetup.lua` | additive (no strip exists today); passes the host's `info` art, already declared | adopt, **LH-04** (OWNER_SCOPE A #48) |
| `Item.BonusIDsFromLink(link)` (Item 3) | tag `docs/api/Item/version-3-docs.md`; CHANGELOG "Item minor 3" | `modules/Export.lua` (the Wowhead link builder; `splitColons` deleted) | replaces a hand-written walk | adopt, **LH-02** (OWNER_SCOPE A #51). The degradation stub already carries it from this re-vendor (blocker b). |
| `LibKa0s-Sim-1.0` (Sim 1, SimTimeline 1, SimPanel 1) | tag `docs/api/Sim/`; CHANGELOG "LibKa0s-Sim-1.0 (new major ...)" | new `core/SimSeam.lua`, `modules/Sim*.lua`, `core/Dispatch.lua`, Compat routing, store accessors | whole-module adoption, a new simulator; host contract H1-H10 | adopt, **LH-06..LH-14** (OWNER_SCOPE A #54) |

## Not candidates here

- **`LibKa0s-Glow-1.0`:** this addon draws no glow; its adopters are DropWatcher, QuickComms and
  KickCD (OWNER_SCOPE A #56). No consumer shape in LootHistory.
- **`W.StepPanel`:** withdrawn before release (LK-11 outcome B); the step-panel renderer is private
  to `SimPanel.lua`, reached only through the Sim adoption above.
- **`O.Drawer` (Options 29 / OptionsDrawer 1):** no settings page here groups rows under a header
  that opens and closes. The stub carries it as a no-op for parity only.
- **`Media.ICON_SETS`, `Media.IconAuthor` (Media 5):** the addon offers no icon chooser and draws
  no Game-icons mark, so neither has a use here.
- **`Perf.Note(..., false)` (Perf 15):** no bucket here runs both inside a parent and at top level.
