# 03 — Decisions

This run was non-interactive. The orchestrator's brief for wave B2 (2026-09-12) set the rules in
advance, following the owner's decision 3: take from kit 17 every local override it makes
redundant, if the suite stays green after characterizing first, and decline everything else, with
the reason recorded here. No GitHub issue was filed for a decline, because the brief said to skip
filing.

| # | Candidate | Decision | Reason |
|---|---|---|---|
| B1 | Delete the local `NewAddon` wrapper in `tests/wow_mock.lua` | **adopt** | Kit 17 embeds the mixin list itself. The characterization case passed before and after, and it goes red when `AceEvent-3.0` is dropped from the production list. Commit `a2b70ed`. |
| — | `spec.bind` on the composers (`OptionsCompose` 4, `OptionsWidgets` 15) | **decline (not applicable)** | Class A. This addon composes only path-keyed Master controls rows and edits no registry records through a composer. PanelMaster is the consumer this is for (#48). |
| — | Port suites onto `M.__fireEvent` | **decline (nothing to port)** | No suite fires a handler through `t.__events[event](event, ...)` on the addon object. `tests/test_browser.lua` fires `B.__ev.__events[event](event)` on the Browser's own target, which kit 17 records the same way. That still works, and changing it is churn with no fidelity gain. |
| — | Drive `/lh` through `AceConsole:__slash` | **decline** | `tests/test_slash.lua` drives `Sl:OnSlash`, which is what the registered handler calls. Adding the AceConsole hop tests the kit, not the addon. |
| — | Every other local extension in `tests/wow_mock.lua` | **not a v1.31.0 surface** | See the table in `02_CANDIDATES.md`. The geometry flip is revision 18 at the earliest, and the kit declined `SetTitle`. |

No candidate was left unreached.
