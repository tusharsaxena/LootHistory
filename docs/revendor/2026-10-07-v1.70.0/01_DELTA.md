Delta: LibKa0s v1.69.0 -> v1.70.0

Run by the timeline-ledger Phase 9 plan (Task B1) on branch `feat/2026-10-06-timeline-ledger`. Adoption
of the new surfaces is ratified by the Phase 9 plan, so no interview ran.

## Source

```sh
git -C ../LibKa0s rev-parse --short 'v1.70.0^{commit}'   # 162a7fd
git -C ../LibKa0s archive v1.70.0 LibKa0s testkit | tar -x -C <scratch>
```

v1.70.0 is a LOCAL tag only (not pushed, no GitHub release), so there is no release or compare URL.
The payload is taken from the tag through `git archive`, never from the working tree.

## Base

CLAUDE.md provenance line named v1.69.0 (`CLAUDE.md:56`), matching `docs/revendor/2026-10-06-v1.69.0/`.

## Per-file minor delta

- Added: `libs/LibKa0s/WidgetsAutocomplete.lua`, minor 1 (`lib.MODULES.WidgetsAutocomplete`), loaded
  after `WidgetsLineChart.lua` in `LibKa0s.xml`.
- Changed: `WidgetsLineChart.lua` minor 1 -> 2 (Widgets key 12.1.4.1 -> 12.1.4.2.1).
- No other LibStub minor moves and no `NEEDS_*` floor rises.

## Both diffs, after the copy

```sh
diff -r <scratch>/LibKa0s libs/LibKa0s   # (empty)
diff -r <scratch>/testkit tests/_kit     # (empty)
```

Before the copy: libs differed in `LibKa0s.xml` and `WidgetsLineChart.lua` plus the added
`WidgetsAutocomplete.lua`; the kit did not differ.

## Kit revision

`Kit.VERSION` stays 37; `tests/_kit` is byte-identical to v1.69.0's.

## Contract delta

Surfaces added: `lib.Autocomplete(editBox, opts)`; `opts.pxPerPoint` on `lib.LineChart` and an optional
second argument on `ChartMath.Budget` (default `LINE_CHART.PX_PER_POINT` = 2, so existing charts draw
as before). No existing surface changes signature or contract. Blockers: none.
