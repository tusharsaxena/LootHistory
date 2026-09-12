# 04 — Execution plan

1. **Re-vendor.** Copy both payloads whole from `v1.32.0`. Roll `CLAUDE.md:51` and the live
   reference in `docs/testing.md` (*When these diffs are supposed to be non-empty*) to v1.32.0.
   Gate: `lua tests/run.lua`, including `tests/test_vendor_sync.lua` against the tag, and
   `luacheck .`. One commit, `14f2977`: 727/727, 0/0.
2. **B1, tests first.**
   - Add the cases to `tests/test_slash.lua` and `tests/test_panel.lua`. Red at the first cut:
     729 passed, 2 failed (731), because each resetall and Defaults press logged 16 per-row `[Set]`
     lines.
   - Wire `bulkBegin` / `bulkEnd` on the Slash descriptor to `NS.Schema.BulkBegin` / `BulkEnd`, and
     mute `S:Set`'s per-row line while a bracket is open. Green: 731/731.
   - **The correction.** Rewrite the cases for the changed-row N, the `0 rows` press, the nested
     single line and the nested profile-reset silence. Red: 729 passed, 5 failed (734), because the
     line carried the library's 16 and each level logged. Tally in the seam by comparing old and new
     values, sum across levels, log at depth 0. Green: 734/734.
3. **Docs.** `docs/ARCHITECTURE.md` (Settings schema), `slash-dispatch.md`, `schema.md` (reset
   semantics), `settings-panel.md` (the Defaults button), `smoke-tests.md` (the debug log checks).
   The code citations the two edits shifted are re-pointed, and so are the ones into the two moved
   library files. `docs/test-cases.md` is regenerated and the README badge moves to 734.

Nothing under `libs/` or `tests/_kit/` was edited except by the copy.
