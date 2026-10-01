Delta: LibKa0s v1.64.0 -> v1.65.0 (span: v1.64.0 v1.65.0)

# Unrecorded vendored tags (LootHistory)

Written beside `2026-10-01-v1.66.0/` by its re-vendor (GI-LH-RV), per the revendor-libka0s 3h read.
The store's newest single-tag bundle is `2026-09-29-v1.63.0`; the tags below were carried by the
2026-09-29 debug-logging sweep (DL-LH-*) and the 2026-09-30 debug-gaps sweep (DG-LH-*) without a
bundle.

```sh
tag_at() { git show "$1:CLAUDE.md" | grep -oE 'Bundles \[LibKa0s\]\([^)]*\) v[0-9]+\.[0-9]+\.[0-9]+' | grep -oE 'v[0-9.]+' | head -1; }
git log --since="2026-09-26 00:00" --format='%h %s' -- CLAUDE.md libs/LibKa0s tests/_kit   # with tag_at per commit
```

```
fbc50fb v1.65.0 DG-LH-01: re-vendor LibKa0s v1.65.0 (kit 34) and roll the provenance line
c13afda v1.64.0 DL-LH-03: re-vendor the final LibKa0s v1.64.0 (DebugLog 17, DebugLogDiagnostics 2, kit revision 34)
7ab6153 v1.64.0 DL-LH-01: re-vendor LibKa0s v1.64.0 (kit revision 33), resize smoke checks
06757a5 v1.63.0 SP-FIN-01: re-vendor the test kit at revision 32 (LibKa0s v1.63.0, re-cut)
e08c0dc v1.63.0 SP-LH-02: re-vendor LibKa0s v1.63.0
```

Recorded tags (`docs/revendor/*`) end at v1.63.0, so v1.64.0 and v1.65.0 are vendored and
unrecorded.
