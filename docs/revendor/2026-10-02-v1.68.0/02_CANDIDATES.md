# Candidates (LootHistory, v1.67.0 -> v1.68.0)

Sources: `git -C ../LibKa0s log --oneline v1.67.0..v1.68.0` (DA-LK-01 carries the only payload
change), the v1.68.0 CHANGELOG block (WidgetsDragHandle minor 3 -> 4) and
`docs/api/Widgets/version-12.1.4-docs.md` against `version-12.1.3-docs.md`.

## Class A: delivered on the re-vendor alone

- None that this addon sees. Minor 4's hookless path is minor 3's calls in minor 3's order
  (`version-12.1.4-docs.md:44`), and this addon builds no drag handle.

## Class B: host change required

| # | Surface | Evidence | Files it would touch | Recommendation | Blast radius |
|---|---|---|---|---|---|
| B1 | `DragHandle` spec `tooltipPlace(tip, frame)` and the tooltip descriptor's `place` (Since 4) | `version-12.1.4-docs.md:18-48`, `:692`, `:725-746`, `:756`; CHANGELOG v1.68.0 | none: `grep -rn 'DragHandle' --include='*.lua' core modules settings` finds no call | **Decline, not applicable.** The hook places the tooltip of a drag strip, and Loot History has no drag strip, so there is nothing to attach it to | would be additive; nothing to add it to |

## Class C: whole-module adoption

- None new. Perf stays a settled decline (performance-§12 no-combat-path exemption,
  `docs/combat-path-sweep.md`); v1.68.0 does not touch Perf, so the premise has not moved.
