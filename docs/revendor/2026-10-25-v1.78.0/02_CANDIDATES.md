# Candidates (LootHistory, LibKa0s v1.77.0 -> v1.78.0)

The run's owner scope (Ka0sAddonsCommonTasks `docs/2026-10-25-SKINNING/inputs/OWNER_SCOPE.md`) and
its `plan-data/items.json` decide the adoptions: LootHistory is leg 1's prototype consumer of the
new Skin major, adopted across items LH-01 to LH-06. The LH-RV item spec says this bundle is a delta
report only and records the Skin major as "adopted in this run" rather than interviewing. So no
interview ran, nothing is declined and no issue is filed. Adoptions land in their own items, after
this re-vendor.

## Class A: delivered on the copy, nothing to adopt

- **The library's controls and windows keep their v1.77.0 look** while this addon registers no skin
  owner (Core 13, Widgets 16, DebugLog 22, PerfPanel 10, SimPanel 7, Options 31-33): an unregistered
  name paints call for call as before. Evidence: CHANGELOG v1.78.0, "Core minor 13, Widgets
  16.2.6.4.4.1 and SkinDefs minor 3"; tag `docs/api/Core/version-13-docs.md`.
- **Media 6's faces and Glass art** register with LibSharedMedia from `RegisterLSM`, which
  `core/MediaSetup.lua` already calls; in leg 1 those keys resolve into this addon's copy. Evidence:
  tag `docs/api/Media/version-6.1-docs.md`; CHANGELOG, "Media minor 6".
- **Peels with no member change:** `WidgetsCopyWindow.lua`, `DebugLogWindow.lua`.
- **Kit 43**, paired with the payload (`mock_paint.lua` opt-in).

## Class B and C: host change required, all decided by the run

| Candidate | Evidence | Files it would touch | Blast radius | Decision |
|---|---|---|---|---|
| `LibKa0s-Skin-1.0` (class C, a new major): `Skin:RegisterOwner("LootHistory", opts)`, appearance profile keys, live repaint | tag `docs/api/Skin/version-4.4.2.1.1.1.1-docs.md`; CHANGELOG, "LibKa0s-Skin-1.0 (new major ...)" | new `core/SkinSetup.lua`, defaults, Schema, the History and Export windows, tests, docs | additive seam, then a re-paint of host-owned chrome | adopted in this run: **LH-01** (seam), **LH-02** (window chrome), **LH-03** (History table), **LH-04** (Insights, Timeline, Holdings), **LH-06** (host AceGUI widgets), **LH-05** (tool surfaces and docs) |
| `O.AppearanceTab` / `O.AppearanceRows` (OptionsAppearance 1), the Appearance tab on General | tag `docs/api/Options/version-33.3.35.4.6.10.3.12.6.3.2.5.1-docs.md:64-66`, :1738-1739, :2234 | `settings/Schema.lua` / the General page tabs, locales, tests | additive: a new tab | adopted in this run: **LH-01** |
| `owner` on `W.Dropdown`, `W.SearchBox`, `W.TestStrip`, `W.Autocomplete`, `W.LineChart`, `W.ReorderList`; the folder name already passed to `CopyWindow` and `MakeCloseButton` | tag `docs/api/Widgets/version-16.2.6.4.4.1-docs.md` (*Skin owners*) | `core/WidgetsSetup.lua`, `modules/Browser*.lua`, `modules/Export.lua` | additive opts field | adopted in this run: **LH-02** to **LH-05** |
| `fromSkin` on `FontGroup` / `BorderGroup` / `BarGroup` (OptionsCompose 12) | tag Options doc; CHANGELOG, "OptionsCompose minor 12: `fromSkin`" | none today: this addon declares none of the three composers | additive | not a candidate here: no row to carry it |
| `Skin:PaintAce` / `Skin:OnRelease` for host-acquired AceGUI widgets (SkinAce 1) | tag Skin doc; CHANGELOG, "SkinAce minor 1" | settings pages that acquire outside `O.AceGUI` | additive | adopted in this run: **LH-06** |
| Kit `mock_paint.lua` | tag `docs/api/testkit/version-43-docs.md` | `tests/` | additive | with the adopting items' headless skin tests |

## Not candidates here

- **`LibKa0s-Glow-1.0`:** still unconsumed; this addon draws no glow (settled at v1.75.0).
- **The Options stub's two Appearance members** are a blocker (01_DELTA 3g), fixed in the re-vendor
  commit, not a candidate.
