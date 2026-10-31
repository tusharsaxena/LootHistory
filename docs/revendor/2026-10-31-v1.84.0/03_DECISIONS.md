# Decisions

The multi-repo run pre-decided these (Ka0sAddonsCommonTasks `docs/2026-10-31-FINDINGS_REMEDIATION/M2_LIBRARY_RELEASE.md`). Nobody was interviewed, and no GitHub issue is filed for a decline, by that run's brief.

| Candidate | Decision | Source |
|---|---|---|
| `opts.afterSubgroup` | adopt, in the `XX-ADOPT` commit | M2 step 7 brief, LibKa0s#59 |
| `LibKa0s-Charts-1.0` | adopt, in the `XX-ADOPT` commit | M2 step 4, LibKa0s#66 |
| `opts.beforeGroup` | declined: this addon draws nothing before a group | brief: recorded here, not filed |
| `note` row | declined: no host-drawn text line to replace | brief: recorded here, not filed |
| `O.PositionBlock` | declined: no position rows | brief: recorded here, not filed |
| `O.PageBanner{ acts }` | declined: the banner has no second action | brief: recorded here, not filed |

## How the two adoptions landed

- **`opts.afterSubgroup`:** LibKa0s#59 calls this a host-drawn heading. This addon draws no heading by hand; what the seam replaces is `CAPTURE_CUT`, the second `O.RenderRows` slice that put the Capture picker under Loot. The picker moves from Capture's `afterGroup` to Loot's `afterSubgroup`.
- **`LibKa0s-Charts-1.0`:** `Analytics._newCharts` passes `owner`, `pool`, `tip`, `hideTip`, `barFill`, `fonts.divider` and `onReskin`. Ka0s Default's render stays the same outside the strips. `tests/analytics_golden.txt` moved, and outside the four strip pools the only change in its lines, with anchors and heights set aside, is the y cursor (each strip 28 shorter) and the mock's strip width.
- **Cards not adopted:** `ctx:card` takes the host's one `panel` seam, the skin's Panel, and these cards wear the skin's Card, in other tokens. Adopting would change them on screen, so they stay in `modules/Analytics.lua`. `Charts.fitFontSize` does replace the local helper.
- **Removed from this addon:** the factories and renderers, `_truncate`, `_tipText`, `_fitFontSize` and `_charStackSegments`, with their 22 cases. The library's suite covers each one.
- **New failure mode, handled:** without the major, `Analytics:Attach` draws one line and no charts.
