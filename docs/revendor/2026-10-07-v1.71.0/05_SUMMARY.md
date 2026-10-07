# Summary (LootHistory)

LibKa0s v1.70.0 -> v1.71.0 from the local annotated tag (`cb274a4`, via `git archive`). Env 1 -> 2,
Slash key 19.1 -> 20.2, WidgetsLineChart 2 -> 3, WidgetsAutocomplete 1 -> 2 (Widgets key 12.1.4.3.2),
OptionsIdList 3 -> 4, test kit 37 -> 38 (adds `secrets.lua`). Both payloads match the tag under
`diff -r`.

In the same commit: the CLAUDE.md provenance line and the `docs/debug.md:14` stamp roll to v1.71.0;
`tests/test_libka0s.lua` relaxes the v1.69.0/v1.70.0 exact pins and gains a v1.71.0 case;
`docs/test-cases.md` is regenerated under kit 38 (Total 1477, Skipped 1) and the README badge moves
1476/1476 -> 1477/1477 (the new case). This resolves LH-A-13.

Adopted: none. Declined: none. Candidates listed in `02_CANDIDATES.md` as not adopted in this run.
