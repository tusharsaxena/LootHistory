# Decisions (LootHistory, v1.68.0)

No interview was held. The owner delegated every decision in the 2026-10-02 tooltip-place sweep
(Ka0sAddonsCommonTasks `docs/2026-10-02-LIBKA0S_TOOLTIP_PLACE/00_PLAN.md`: "The other seven:
re-vendor only (no strip)"), so the executor decided and records the reasoning here.

- **B1, `tooltipPlace` / `place`: declined, not applicable.** The hook exists for a host whose drag
  strip cannot own its own tooltip. Loot History builds no `DragHandle`
  (`grep -rn 'DragHandle' --include='*.lua' core modules settings`: no call), so there is no strip
  and no tooltip for it to place. This is not a gap, so no GitHub issue is filed, per the plan's rule
  that a declined candidate is filed only when the reason is a real gap. If Loot History ever grows a
  drag strip, the hook is there to take at that time.
