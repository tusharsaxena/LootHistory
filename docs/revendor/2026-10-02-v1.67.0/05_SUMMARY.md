# Summary (LootHistory)

LibKa0s v1.66.0 -> v1.67.0 from the local tag `v1.67.0`; `tests/_kit` 35 -> 35 (byte-identical);
CLAUDE.md provenance rolled in the same commit (CA-LH-RV). Core 9 -> 10, Options 27 -> 28,
OptionsIdList 2 -> 3. No file added or deleted. No blocker. No base correction, no span bundle.

- Delivered on the re-vendor alone (class A): nothing visible; the new fields are off by default.
- Adopted here: none. `addonName` is CA-LH-NM's; `canResize` and `onResizeStop` are CA-LH-01's.
- Declined: none. `gripParent` has no use here.
- Consumer pins moved: none beyond the provenance line `tests/test_vendor_sync.lua` reads.
- Live stamps rolled: `CLAUDE.md` (provenance) and `docs/debug.md` (the vendored-set line).
- New in-client check: none. The census bundle's smoke list (`03_SMOKE_TESTS.md` LH-1 to LH-3,
  ID-4) belongs to CA-LH-01 and CA-LH-NM.

Gate after the copy (all through `ka0s-bounded`):

- tests: 1040 passed, 0 failed, 1 skipped, 1041 total (the same as before the copy)
- luacheck: 0 warnings / 0 errors in 80 files
- vendor parity: `diff -r` of both payloads against the tag, empty
- complexity, sighted (`bash tests/_kit/run-automated-tests.sh --suite complexity --no-bundle`):
  pass, 0 warnings, max CCN 15
