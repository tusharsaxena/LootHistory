# 05 — Summary: LibKa0s v1.55.0 -> v1.56.0

Plan item RV-LH of the 2026-09-23 review and standards-audit remediation, run 2026-09-24 on branch
`feat/2026-09-23-review-audit-remediation`. Nothing was pushed, the addon version was not bumped,
and `libs/` and `tests/_kit/` were not touched after the copy.

## The move

The tag moved from **v1.55.0** to **v1.56.0** (tag object `4622018`, commit `514fc0a`). One commit
copied both payloads whole and rolled the `CLAUDE.md` provenance line. Fourteen library files move
a minor and no file is added or removed (`01_DELTA.md` 3c). The kit moves from revision 25 to 26
and gains `asserts.lua`, `mock_events.lua` and `prose_lists.lua`.

## Contract blockers (3g)

Two reds, both from the stricter payload, recorded and left to this addon's M3 items as the plan
directs:

- `tests/test_surface_parity.lua`: the Schema instance stub lacks `SetMany` (Schema minor 2).
- `tests/test_widgets.lua:106`: the adoption pin expects Widgets minor 9 and the copy carries 10.

## Adopted, declined, skipped

Not decided here. The candidates v1.56.0 offers (Schema `SetMany` / `row.normalize` /
`writeThrough`, Launcher `isEnabled` / `disabledLine`, Core's `SafeRegisterEvent` family, the Slash
`DisabledLine` constant pin, the `RenderTabbedSchema` options) are this addon's M3 items.

## Gates on the copy

| Gate | Result |
|---|---|
| `ka0s-bounded luacheck .` | 0 warnings / 0 errors in 65 files |
| `ka0s-bounded lua5.1 tests/run.lua` | 856 passed, 2 failed, 0 skipped, 858 total |
| `ka0s-bounded lizard` (authored code) | no function above CCN 15 |
| layout-§1 cap | largest authored file `modules/Browser.lua`, 1271 lines |

## OPEN

- The two reds above.
- `docs/test-cases.md` and the README Tests badge are stale on kit revision 26's `§` case names;
  a later item regenerates them, never this commit.
