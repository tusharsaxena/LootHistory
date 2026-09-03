# 05 — Summary: LibKa0s v1.24.0 → v1.25.0

## The move

| | |
|---|---|
| From | v1.24.0 |
| To | **v1.25.0** |
| Files that moved | `OptionsCompose.lua`, `COMPOSE_MINOR` 1 → **2** |
| Kit revision | 14 → 14 (**unchanged**, still copied whole in the same commit) |
| Files removed upstream | none |
| Cross-major skew found | none |

## What reached this addon for free

**Nothing, and that is the honest answer rather than an empty section.** The one file that
moved adds an optional descriptor field; an addon that does not pass it gets exactly the
behaviour it had. No class-A delivery to report.

## What was adopted

Nothing — there were no candidates. See `02_CANDIDATES.md`: v1.25.0's single new surface
(`MasterControls`'s `leadButton`) places **one** page-wide host act beside
`options-ui-§15`'s reset buttons, and this addon passes the composer's tail through with
no such act of its own. There is no `04_EXECUTION_PLAN.md` in this bundle because nothing
was implemented.

## What was declined

Nothing was declined, so no GitHub issue was filed. A decline records a decision about
work that was **offered**; nothing was.

## Gates

| Gate | Result |
|---|---|
| `luacheck .` | **0 warnings / 0 errors** in 28 files |
| `lua tests/run.lua` | **699 passed, 0 failed** |
| `tests/test_vendor_sync.lua` | green — it resolves the tag named in `CLAUDE.md` and compares **both** payloads against it, so it is the case this whole re-vendor exists to satisfy |

`luacheck`'s figure is scoped by `.luacheckrc`'s `exclude_files`, which excludes the
vendored payload — so a clean run says the **host** is clean, not that `libs/` was checked.
The payload's own gate is upstream, and its evidence is the release bundle in the library
repo at `docs/automated-tests/20260903-161751/`.

## Not pushed

Committed only. Pushing is `/wow-addon:finalize`'s.
