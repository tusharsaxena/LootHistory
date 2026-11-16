# 04 Execution plan

Nothing adopted, so no characterization tests and no adoption commits. The run is one commit, RV-LH:

1. Copy both payloads whole from the v1.105.0 extract; then re-copy `tests/_kit/mock_base.lua` and `tests/_kit/mock_events.lua` from the re-cut tag (LibKa0s LK-FIX-1, `8209c104`) once the first cut's kit failed the leak gate. Both payloads then diff clean against the re-cut tag outside the pruned media.
2. Roll the provenance line to v1.105.0; keep the `LibKa0s icons:` line.
3. Prune icons and sounds with the tag's `tools/prune-icons.lua`.
4. Fix what the new payload turned red (01_DELTA.md 3g): the DebugLog stub's `Report` and `Serialize`, the Options stub's `SideTabs`, the Compat minor 4 not-wired names, the Ka0s Default fallback's `list.stripe` and `list.hover` with their re-pins, the console counter on `text.muted`, the console's Clear-to-Copy gap, the Widgets 27 adoption pin, and `tests/test_libka0s.lua` (ten new `LIB_FILES`, 29 minor pins and the kit pin to floors, a v1.105.0 exact-pin case).
5. Keep CRLF in the working tree on every touched file (`eol=crlf`).
6. Regenerate `docs/test-cases.md` (`lua tests/run.lua --list`) and roll the README Tests badge.
7. Gate: `ka0s-bounded lua tests/run.lua` (leak gate at its default budget) and `ka0s-bounded luacheck .` (0/0), every file under 1500 lines.
