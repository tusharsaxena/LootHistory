Delta: LibKa0s v1.68.1 -> v1.69.0

Run by the timeline-ledger Phase 3 plan (Task B1) on branch `feat/2026-10-06-timeline-ledger`. The
adoption of the one new surface is already ratified by spec F3, so no interview ran.

## Source

```sh
git -C ../LibKa0s rev-parse --short 'v1.69.0^{commit}'   # 5949f4c (annotated tag object aeea542)
git -C ../LibKa0s archive v1.69.0 LibKa0s testkit | tar -x -C <scratch>
```

v1.69.0 is a LOCAL tag only (not pushed, no GitHub release), so there is no release or compare URL.
The payload is taken from the tag through `git archive`, never from the working tree.

## Base

CLAUDE.md provenance line named v1.68.1 (`CLAUDE.md:56`), matching the prior re-vendor bundle
`docs/revendor/2026-10-04-v1.68.1/`.

## Per-file minor delta

One file added: `libs/LibKa0s/WidgetsLineChart.lua`, minor 1 (`lib.MODULES.WidgetsLineChart`),
loaded after `WidgetsDragHandle.lua` in `LibKa0s.xml`. Widgets key 12.1.4 -> 12.1.4.1. No existing
LibStub minor moves and no `NEEDS_*` floor rises.

## Both diffs, after the copy

```sh
diff -r <scratch>/LibKa0s libs/LibKa0s   # (empty)
diff -r <scratch>/testkit tests/_kit     # (empty)
```

Before the copy: libs differed in `LibKa0s.xml` plus the added `WidgetsLineChart.lua`; the kit
differed in `README.md`, `framework.lua`, `mock_base.lua` plus the added `mock_lines.lua`.
(`--strip-trailing-cr` shows the same set: no line-ending drift.)

## Kit revision

`Kit.VERSION` 36 -> 37. `mock_lines.lua` makes `CreateLine` on every tracked frame answer a
distinct, recording Line object. Both payloads move together in one commit (the pairing rule).

## Contract delta

Surfaces added: `lib.LINE_CHART`, `lib.ChartMath`, `lib.LineChart` (CHART_MINOR 1). No existing
surface changes signature or contract. Blockers: none.
