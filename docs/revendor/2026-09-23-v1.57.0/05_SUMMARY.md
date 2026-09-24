# 05 — Summary: LibKa0s v1.56.0 -> v1.57.0

Plan item M5-LH of the 2026-09-23 review and standards-audit remediation (milestone M5, the
always-on launcher status tooltip), run 2026-09-24 on branch
`feat/2026-09-23-review-audit-remediation`. Nothing was pushed, the addon version was not bumped,
and `libs/` and `tests/_kit/` were not touched after the copy.

## The move

The tag moved from **v1.56.0** to **v1.57.0** (tag object `d03e836`, commit `aa37bc9`). One commit
copied both payloads whole, rolled the `CLAUDE.md` provenance line and made the adoption. One library
file moves a minor (`Launcher.lua` 2 -> 3) and no file is added or removed (`01_DELTA.md` 3c). The
kit stays at revision 26, byte-identical.

## Contract blocker (3g)

One red on the copy, cleared in the same commit. Launcher minor 3 draws the whole tooltip and appends
the host's `onTooltipShow`, so this addon's hand-drawn title, hints and refusal line were drawn twice
(anti-pattern #89).

## Adopted, declined, skipped

- **Adopted**: `version`, `isLocked`, `isTestMode`, `leftClickLabel`; `onTooltipShow` cut to the
  record count. Pinned by four cases in `tests/test_launcher.lua`: the exact enabled and disabled
  lines, lock and test mode read on every show, and the descriptor's fields through a scratch load.
- **Declined**: `slash`. The library already reads `/lh` out of `disabledLine()`.

## Gates after the adoption

| Gate | Result |
|---|---|
| `ka0s-bounded luacheck .` | 0 warnings / 0 errors in 67 files |
| `ka0s-bounded lua5.1 tests/run.lua` | 929 passed, 0 failed, 0 skipped, 929 total |
| `ka0s-bounded lizard` (authored code) | no function above CCN 15 |
| layout-§1 cap | largest authored file `modules/Browser.lua`, 1289 lines |

## OPEN

- The owner re-runs in-client smoke #1 (minimap buttons) after M5. The launcher block in
  `docs/smoke-tests.md` now describes the new tooltip.
