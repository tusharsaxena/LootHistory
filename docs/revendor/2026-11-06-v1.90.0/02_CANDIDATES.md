# Candidates: LibKa0s v1.89.0 -> v1.90.0 (LootHistory)

Sources: `git -C ../LibKa0s log --oneline v1.89.0..v1.90.0`, the tag's `CHANGELOG.md` block v1.90.0,
and the `docs/api/` documents of every major that moved (Core 16, Widgets 24.5.12.6.8.5,
Skin 17.1.27.8.19.18.17.4.9, Options 37.4.44.2.7.2.9.15.2.4.19.13.5.5.7.7.11.1.1.4). Pin blockers
(01_DELTA.md) are not candidates.

## A. Delivered on the copy (no host change)

- **One physical pixel on the library's controls** (`CHANGELOG.md` v1.90.0, *One physical pixel
  (SF1-L1)*; `docs/api/Widgets/version-24.5.12.6.8.5-docs.md:19-27`, "What a host owes: nothing"):
  this addon's `W.Dropdown` filter-bar dropdowns, its `W.SearchBox`, the shared menu and the
  `W.Autocomplete` list draw a one-physical-pixel edge at any UI scale and sub-pixel position.
  LootHistory's edges already measured 1 px in the owner's smoke (feedback item 4: it is the
  reference); the change makes that hold at every position instead of by luck.
- **Skin's pixel watch moved into Core** (SkinPaint 19, SkinPaintExtras 18): `P.px` and the pixel
  watch call Core's; no host surface.
- **`lib.__copySkinTo` honours `keepScope`** (OptionsAppearance 7): a *Copy to all* or *Apply to all*
  started from LootHistory now leaves Ka0s Skin Tester's Scope alone once the tester opts in
  (`SF1-ST`). No host change here.

## B. Host change required

- **`RegisterOwner(owner, { keepScope = true })`** (`docs/api/Skin/version-17.1.27.8.19.18.17.4.9-docs.md:19-28`).
  Not applicable: the opt-out exists for a host whose documented Scope deviates from what other addons
  copy (the Skin Tester's `ignorePanel = false`). LootHistory documents no such deviation, and the
  owner's ruling names only the Skin Tester (`SF1_SMOKE_FEEDBACK.md`, item `SF1-ST`).

## C. Whole-module adoption

None: no new major in this range.
