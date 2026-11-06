# Candidates: LibKa0s v1.90.0 -> v1.91.0 (LootHistory)

Sources: `git -C ../LibKa0s log --oneline v1.90.0..v1.91.0`, the tag's `CHANGELOG.md` block v1.91.0,
and the `docs/api/` documents of every major that moved (Core 17.1, Widgets 26.1.6.13.7.8.5,
Skin 17.1.27.8.19.19.1.1.17.4.9). Pin and file-list blockers (01_DELTA.md) are not candidates.

## A. Delivered on the copy (no host change)

- **The line chart's lines in physical pixels** (`CHANGELOG.md` v1.91.0, *The line chart's lines in
  physical pixels (FU-L1)*; `docs/api/Widgets/version-26.1.6.13.7.8.5-docs.md:25-33`): the Timeline
  tab's chart (`modules/Timeline.lua:252`, through `NS.MakeLineChart`) draws its x axis, y grid rules,
  the `ledgerSince` marker and the hover crosshair one physical pixel at any UI scale, re-sized on a UI
  scale change with no render. The series take this addon's own thicknesses (`C.TIMELINE.TOTAL_W` 2.5,
  `LINE_W` 2, `core/Constants.lua:360-361`), now read as physical pixels (see 01_DELTA.md, 3g).
- **The band-file peels** (`CHANGELOG.md` v1.91.0, *The band files peeled (FU-L2)*): Core's pixel
  edges, Widgets' dropdown and shared menu, and SkinPaintExtras' HUD looks and AceConfig confirmation
  box move to their own files under the same member names. Pure moves; nothing for a host to call.

## B. Host change required

None. v1.91.0 adds no member, option, row type or descriptor field.

## C. Whole-module adoption

None: no new major in this range.
