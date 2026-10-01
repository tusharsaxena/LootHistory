# Candidates (LootHistory, v1.66.0 -> v1.67.0)

Sources: `git -C ../LibKa0s log --oneline v1.66.0..v1.67.0` (CA-LK-01, CA-LK-02, CA-LK-03), the
v1.67.0 CHANGELOG block, `docs/api/Core/version-10-docs.md` and
`docs/api/Options/version-28.2.34.2.3.8.1.7.4.2-docs.md`.

**Not interviewed.** The 2026-10-02 census adoption bundle (Ka0sAddonsCommonTasks
`docs/2026-10-02-LIBKA0S_CENSUS_ADOPTION/`) already assigns each new surface to an item, so this
re-vendor lists them and names the item that takes each.

## Class A: delivered on the re-vendor alone

- None that this addon sees. Core 10 and OptionsIdList 3 change nothing for a host that passes
  none of the new fields.

## Class B: host change required

| # | Surface | Evidence | Taken by |
|---|---|---|---|
| B1 | Options descriptor `addonName` (the loaded-addon guard on the help art) | CHANGELOG v1.67.0 "OptionsIdList minor 3"; Options docs, `addonName` row | **CA-LH-NM** (`settings/OptionsSetup.lua:171` passes the first vararg) |
| B2 | `Core.MakeResizable` `canResize` | `docs/api/Core/version-10-docs.md`, "The resize grip" | **CA-LH-01** (`canResize = not B:IsLocked()` on the History browser, LootHistory#33) |
| B3 | `Core.MakeResizable` `onResizeStop` | same | **CA-LH-01** (SaveWindow and the table refresh once per drag) |
| B4 | `Core.MakeResizable` `gripParent` | same | none: the History browser sizes the frame that owns its grip |

## Class C: whole-module adoption

- None new. Perf stays a settled decline (performance-§12 no-combat-path exemption,
  `docs/combat-path-sweep.md`).
