# Re-cut: v1.85.0 moved for the owner's rulings and the gate

Tag `v1.85.0` moved again before it was pushed. This re-vendor adds this file instead of a new folder, and the other files here stay as written. `FS-LH-RV` copied the commit at `09a835c`.

- **New commit:** `2ad1a5080112cc1323fe79f7e134b00768a7ebca`
- **Why:** the owner's rulings of 2026-11-01 (each skin's own bar, icon, glow and cover values; a skin's None defers to the player's stored border and a real style wins) and the kit's typed-value gate and switch test.

## Per-file minors between the two commits

| File | Old | New |
|---|---|---|
| Skin.lua | 14 | 15 |
| SkinDefs.lua | 24 | 25 |
| SkinDefsOthers.lua | 6 | 7 |
| SkinPaint.lua | 16 | 17 |
| SkinPaintExtras.lua | 15 | 16 |
| SkinPaintControls.lua | 14 | 15 |
| SkinEUI.lua | 3 | 4 |
| OptionsCompose.lua | 17 | 18 |
| Media.lua | 11 | 12 |
| Widgets.lua | 20 | 21 |

Kit 49 -> 50.

## This addon

- **Blockers:** the degraded facade gains `BarBorder`, which answers its three, and `HoverArt`, a no-op. `tests/run.lua` declares `test_skin_values` and `test_skin_switch` by the pair. No Widgets stub exists here, so `ContextMenu` is owed nowhere; `O.LabelFont` was already stubbed.
- **Adopted (FS-LH-GATE):** `Kit.skinValues` with `calls` for `NS.SkinBar`, `setCell` and `NS.IconMarkup`, and no allow row: the kit's categories take all five rows `tests/test_skin_literals.lua` carried, and that suite is deleted. `Kit.skinSwitch` declares the surfaces in `tests/skin_surfaces.lua`.
- **Not owed:** no HUD, so no companion, no `Skin.FollowOnce` and no numeric-path repair. No `S.Mark` or `S.HoverArt` call in this addon, so nothing on a pooled AceGUI widget to untrack. No bar border, so nothing draws through `S.BarBorder`.
- **Look:** the moved tokens are `bar.bg`, `bar.border`, `icon.border`, `glow.color`, `cover.dim` and `bar.borderStyle`, and no surface of this addon reads them. Step 5 stands as `05_SUMMARY.md` gives it. No smoke check's expected result moved, so no owner pass mark is cleared.
- **Pins:** the v1.85.0 case in `tests/test_libka0s.lua` takes the minors above and kit 50, the v1.83.0 Media pin relaxes to `>=`, and `tests/test_widgets.lua` takes Widgets 21.
- **Icons:** `CLAUDE.md` is unchanged. The prune kept 23 files.
