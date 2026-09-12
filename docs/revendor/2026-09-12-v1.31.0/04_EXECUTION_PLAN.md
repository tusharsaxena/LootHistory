# 04 — Execution plan

1. **Re-vendor.** Copy both payloads whole from `v1.31.0`. Roll `CLAUDE.md:51` and the live
   reference in `docs/testing.md` (*When these diffs are supposed to be non-empty*) to v1.31.0.
   Gate: `lua tests/run.lua`, including `tests/test_vendor_sync.lua` against the tag, and
   `luacheck .`. One commit, `438b38d`: 722/722, 0/0.
2. **B1, characterization first.** Add
   `Harness: NS.bus is the NewAddon object and carries the message half and the listed mixins` to
   `tests/test_harness.lua` with the wrapper still in place. The assertion that proves the change:
   `rawequal(NS.bus, NS.addon)`, the eight mixins present as functions, and a message sent through
   `NS.bus` reaching a separately embedded target with its argument intact.
   - Green with the wrapper: 723/723.
   - Delete the wrapper (`tests/wow_mock.lua`, the *message bus* block) and update the matching
     prose in `docs/testing.md`. Green without it: 723/723.
   - Falsify: drop `"AceEvent-3.0"` from `core/LootHistory.lua:4` for one run. The case goes red
     (652 passed, 71 failed). Restore the file.
   - Regenerate `docs/test-cases.md` and move the README badge to 723. One commit, `a2b70ed`.

The fences held. Nothing under `libs/` or `tests/_kit/` was edited except by the copy, no setup
file changed, and no close control was touched.
