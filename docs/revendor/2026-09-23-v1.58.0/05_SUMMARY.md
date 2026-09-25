# 05 — Summary: LibKa0s v1.57.0 -> v1.58.0

Plan item M6-LH of the 2026-09-23 review and standards-audit remediation (milestone M6, the
launcher's left-click-settings / right-click-options-menu ruling), run 2026-09-25 on branch
`feat/2026-09-23-review-audit-remediation`. Nothing was pushed, the addon version was not bumped,
and `libs/` and `tests/_kit/` were not touched after the copy.

## The move

The tag moved from **v1.57.0** to **v1.58.0** (tag object `93cf3ad`, commit `34931c9`). One commit
copied both payloads whole, rolled the `CLAUDE.md` provenance line and made the adoption. One library
file moves a minor (`Launcher.lua` 3 -> 4) and no file is added or removed (`01_DELTA.md` 3c). The
kit stays at revision 26, byte-identical.

## Contract blockers (3g)

Four reds on the copy, cleared in the same commit: left-click stopped running `onClick`, the two
tooltip hints are fixed, and the disabled left-click refusal is gone.

## Adopted, declined, skipped

- **Adopted**: `setEnabled`, `toggleLock`, `toggleTestMode`, `isWindowShown` + `toggleWindow`, each
  wired to the addon's own handler (the `enable`/`disable`/`test`/`toggle` entries of `NS.COMMANDS`;
  the *Lock frame* row's `Schema:Set` for the lock, since there is no lock verb). Menu: Enabled ·
  Locked · Test mode · Show window, matching `ADDONS.md`.
- **Removed**: `onClick`, `leftClickLabel`, `disabledLine` (retired at minor 4).
- **Tests**: five new cases in `tests/test_launcher.lua` through `tests/mock_menu.lua` (the
  library's own `MenuUtil` stand-in, copied verbatim): left-click opens settings in both states;
  right-click degrades to the panel without `MenuUtil`; the menu's title, entries, order and
  checkmarks; each entry routes to its handler once; grayed-while-disabled entries call nothing even
  when force-clicked. The descriptor case, both tooltip cases and `test_disabled.lua` step 8 are
  re-pinned. 932/932.

## Gates after the adoption

| Gate | Result |
|---|---|
| `ka0s-bounded luacheck .` | 0 warnings / 0 errors in 68 files |
| `ka0s-bounded lua5.1 tests/run.lua` | 932 passed, 0 failed, 0 skipped, 932 total |
| `ka0s-bounded lizard` (authored code) | no function above CCN 15 |
| layout-§1 cap | largest authored file `modules/Browser.lua`, 1289 lines |

## OPEN

- The owner re-checks the minimap button in-client after M6 (smoke §11 in `docs/smoke-tests.md`
  now walks the menu, enabled and disabled).
