# Candidates, LibKa0s v1.83.0 -> v1.84.0

Sources: `git log v1.83.0..v1.84.0`, the v1.84.0 CHANGELOG block, `docs/api/Options` and `docs/api/Charts/version-1.1-docs.md`.

## Class A, delivered by the copy

- The eight peels, which are pure moves.
- WidgetsDragHandle minors 9 and 10. This addon has no `DragHandle` host, so nothing reaches it.
- Schema 3 and Slash 21 skip a `note` row. This addon has no note row yet.

## Class B

| Candidate | Evidence | Blast radius |
|---|---|---|
| `opts.afterSubgroup` on `O.RenderRows` | CHANGELOG v1.84.0, OptionsFlow minor 2; LibKa0s#59 names this addon | Replaces the two-slice render in `settings/Panel.lua` |
| `opts.beforeGroup` | OptionsFlow minor 2; asked for by DpsRace | Additive, no use here |
| `note` row | OptionsFlow minor 2; asked for by PGFE | Additive, no use found |
| `O.PositionBlock` | OptionsCompose minor 15; asked for by QuickComms | Additive, no position rows here |
| `O.PageBanner{ acts }` | OptionsTabs minor 13; asked for by KickCD | Additive, no use here |

## Class C

| Candidate | Evidence | Blast radius |
|---|---|---|
| `LibKa0s-Charts-1.0` | `docs/api/Charts/version-1.1-docs.md`, *Adopting it*; LibKa0s#66 | Replaces code this addon owns: the renderers in `modules/AnalyticsCharts.lua` |
