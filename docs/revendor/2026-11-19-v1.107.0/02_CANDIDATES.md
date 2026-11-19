# 02 Candidates, LibKa0s v1.106.0 -> v1.107.0

Sources: `git -C ../LibKa0s log --oneline v1.106.0..v1.107.0`; LibKa0s CHANGELOG.md's v1.107.0 block; the Widgets `docs/api/` document for WidgetsDragHandle 15 and WidgetsDragHandleTip 2.

**Class A, delivered on the copy alone:** nothing visible here. The strip changes reach only a `W.DragHandle`, and this addon builds none.

**Class B, host change required:** none. The strip's `spec.settings`, `spec.onClose` and the retired `spec.tooltipPlace` apply only to a strip host.

**Class C, whole-module adoption:** none new in this range.
