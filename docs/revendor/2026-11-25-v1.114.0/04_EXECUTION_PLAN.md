# 04 Execution plan

1. **The re-vendor commit** (SF-LH-02): both payloads, the provenance roll, the floored and new pins in `tests/test_libka0s.lua` (3g), the regenerated `docs/test-cases.md` and README badge, the span bundle `2026-11-25-v1.112.0-v1.113.0` and this bundle.
2. **The adoption commits** (SF-LH-02), characterization test first:
   - a characterization case pinning the History row tooltip's current lines on both clients without ForeverDB;
   - `core/ForeverDBSetup.lua`: the seam over `LibStub("LibKa0s-ForeverDB-1.0", true)` with the documented all-absent stand-in, publishing `NS.ForeverDB`;
   - the tooltip lines (Drops from, top three with chances; Sold by, lowest price and its vendor), built only when the setting is on, the client is WoW Forever and `Available()` answers true; the first hover is what loads the data addon;
   - a `showForeverDB` setting (default on) beside the other History display options, whose tooltip says it needs ForeverDB on WoW Forever;
   - the TOC `## OptionalDeps` and `.pkgmeta` `optional-dependencies: forever-db`;
   - tests on the kit fake (`present`, `missing`, `reshaped`, nothing loaded at login) and a Retail-profile case that proves it inert;
   - the perf ceiling's note (about 12 MB on disk, loaded on first use), the docs, and the smoke rows.

The assertion that proves the change is the tooltip's exact added lines against the fake's invented rows, and the unchanged line list without ForeverDB.
