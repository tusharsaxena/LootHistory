# Summary (LootHistory)

LibKa0s v1.67.0 -> v1.68.0 from the local annotated tag `v1.68.0`; base v1.67.0 from the CLAUDE.md
provenance line, confirmed by `c47d050` and a payload match. `tests/_kit` 35 -> 35 (byte-identical).
CLAUDE.md provenance rolled in the same commit as the bytes (TP-LH-01). One file moved:
`WidgetsDragHandle.lua` `DRAG_MINOR` 3 -> 4. No file added or deleted. No blocker. No base
correction, no span bundle.

- Delivered on the re-vendor alone (class A): nothing visible; this addon builds no drag handle.
- Adopted: none.
- Declined: B1 `tooltipPlace` / `place`, not applicable (no drag strip). No issue filed: not a gap.
- Skipped or unreached: none.
- Consumer pins moved: none beyond the provenance line `tests/test_vendor_sync.lua` reads.
- Live stamps rolled: `CLAUDE.md` (provenance) and `docs/debug.md` (the vendored-set line; its
  DebugLog minors did not move).
- New in-client check: none.

Gates (all through `ka0s-bounded`):

- before the copy, tests: 1049 passed, 0 failed, 1 skipped, 1050 total
- after the copy, tests: 1049 passed, 0 failed, 1 skipped, 1050 total, including both vendor-sync
  cases ("libs/LibKa0s is the LibKa0s release CLAUDE.md says this addon bundles", "tests/_kit is
  the test kit that shipped with that release")
- luacheck: 0 warnings / 0 errors in 80 files
- vendor parity: `diff -r` of both payloads against the tag, with and without
  `--strip-trailing-cr`, empty
- complexity, sighted (`bash tests/_kit/run-automated-tests.sh --suite complexity --no-bundle`):
  pass, 0 warnings, max CCN 15
- inventory (`docs/test-cases.md`) and the README test badge: unchanged, the case count did not move
