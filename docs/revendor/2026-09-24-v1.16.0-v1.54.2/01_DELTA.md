Delta: LibKa0s v1.16.0 -> v1.54.2 (span: v1.16.0 v1.17.0 v1.18.0 v1.18.1 v1.19.0 v1.23.0 v1.24.0 v1.26.0 v1.27.0 v1.28.0 v1.29.0 v1.35.0 v1.36.0 v1.36.1 v1.36.2 v1.37.0 v1.38.0 v1.39.0 v1.42.0 v1.43.0 v1.44.0 v1.45.0 v1.46.1 v1.47.0 v1.50.0 v1.51.0 v1.52.0 v1.53.0 v1.54.2)

# 01 — Delta: the consolidated span bundle

Written 2026-09-24 for plan item LH-34 of the 2026-09-23 review and standards-audit remediation
(finding LootHistory-A-01, audit row LH-62), on branch `feat/2026-09-23-review-audit-remediation`.
It is the sanctioned record for a lapsed span (`audit-review-history`, standard v2.65.0): one folder
named for the first and last unrecorded tags, holding `01_DELTA.md` and `05_SUMMARY.md` only. The
re-vendors it records were each done and gated when they landed; nothing is re-vendored here and no
code changes. The per-tag deliberation files (02 to 04) are absent on purpose: a span carried by
sweeps had none to record, and per-tag back-fill folders are not written.

## The true previous base

The span's line-1 endpoints are the first and last **unrecorded** tags, not a delta base. The last
tag this store recorded before the span is **v1.15.0** (`docs/revendor/2026-08-25/`, the store's
first bundle and the audit horizon). The payload at the start of the span, vendored at `3a9c075`
("chore(libs): re-vendor LibKa0s v1.15.0"), is that tag. Read as a delta, the span runs
**v1.15.0 -> v1.54.2**.

Seven tags inside that range already have their own bundles and are **not** in the span list:
v1.25.0 (`2026-09-03/`), v1.30.0 (`2026-09-12/`), v1.31.0, v1.32.0, v1.33.0 (`2026-09-12-v1.3x.0/`)
and v1.34.0 (`2026-09-13-v1.34.0/`). Two of the bare-dated ones name a second tag in their line-1
heading as their base (v1.24.0 in `2026-09-03/`, v1.29.0 in `2026-09-12/`). The audit check reads
only the last tag of a bare-dated line 1, so those two count as unrecorded and are listed here.

Tags the library cut that this addon never vendored are not in the span either, because nothing
here ever carried them: v1.20.0, v1.21.0, v1.22.0, v1.40.0, v1.41.0, v1.46.0, v1.48.0, v1.48.1,
v1.49.0, v1.49.1, v1.54.0 and v1.54.1.

## The v1.55.0 bundle's base is right

The item text asked for a correction note here: that `docs/revendor/2026-09-23-v1.55.0/` names
v1.54.2 as its base on line 1 while this repo's previous vendored tag was v1.53.0. The history says
otherwise. `a8f2133` ("Adopt the kit's US-English gate, and delete the copy this repo was keeping",
2026-09-22) rolled the `CLAUDE.md` provenance line to **v1.54.2** and copied kit revision 24 in; the
library bytes are identical to v1.53.0, which is why a walk over `libs/LibKa0s` alone never saw it.
So v1.54.2 did land here, `2026-09-23-v1.55.0/`'s base is correct, and there is nothing to correct.
That frozen bundle is not edited either way.

## How the list was derived

The `AUDIT.md` re-vendor comparison (WowAddonStandards v2.65.0), run before this bundle existed:

```sh
horizon=$(ls -1 docs/revendor | sort | head -1 | cut -c1-10)          # -> 2026-08-25
git log --since="$horizon 00:00" --format=%H -- libs/LibKa0s tests/_kit | while read -r c; do
  git show "$c:CLAUDE.md" 2>/dev/null |
    grep -oE 'Bundles \[LibKa0s\]\([^)]*\) v[0-9]+\.[0-9]+\.[0-9]+' |
    grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1
done | sort -uV > vendored.txt                                        # 38 tags
# recorded.txt: the recorded-side loop over docs/revendor/*/           # 9 tags
grep -vxF -f recorded.txt vendored.txt                                 # 29 tags, the span above
```

Every in-scope commit resolved a tag from its `CLAUDE.md` provenance line, so no README.md
fallback was needed. After this bundle, the same comparison prints nothing.

**Correction to the item text.** LH-34 and the audit (LH-62) named 25 tags, v1.18.0 to v1.53.0.
That count used a bare-date `--since`, which drops the horizon day's own commits (v1.16.0 and
v1.17.0 on 2026-08-25), and walked `libs/LibKa0s` alone, which misses the kit-only v1.43.0 and
v1.54.2 re-vendors. The v2.65.0 comparison finds 29 tags in 33 commits. The folder is named for the
span it actually covers, `2026-09-24-v1.16.0-v1.54.2`, not `v1.18.0-v1.53.0`, as the item's own
plan-review correction directs.

## The 33 vendoring commits

"Standalone" means the commit is a re-vendor and nothing else; the same tags went into the sibling
Ka0s addons in the same sweeps. "Folded" means the copy rode inside a LootHistory feature commit
rather than standing alone (`versioning-git` makes that a SHOULD, not a MUST). A branch name means
the commit landed on that branch and reached master through the merge named.

| Tag | Commit | Date | Subject | Carried by |
|---|---|---|---|---|
| v1.16.0 | `3d79b33` | 2026-08-25 | Re-vendor LibKa0s v1.16.0 | standalone |
| v1.17.0 | `d164c11` | 2026-08-25 | Re-vendor LibKa0s v1.17.0 | standalone |
| v1.18.0 | `143fdd7` | 2026-08-26 | Adopt options-ui-§12: Reset Everything is wholesale, not a list of keys | folded |
| v1.18.1 | `07c79b0` | 2026-08-26 | Re-vendor LibKa0s v1.18.1: the landing logo stops pooling its texture | standalone |
| v1.19.0 | `0dff078` | 2026-08-27 | Carry LibKa0s v1.19.0 | standalone |
| v1.23.0 | `63700c3` | 2026-09-01 | Re-vendor LibKa0s v1.23.0: the tab strip and the page banner arrive | standalone |
| v1.24.0 | `179b0c7` | 2026-09-02 | feat(settings): master controls, two pages folded into General, price sources by drag | folded; feat/settings-revamp-v2 (merged `6d3c2de`) |
| v1.26.0 | `1f776a8` | 2026-09-08 | M3-05: re-vendor LibKa0s v1.26.0 | standalone, 2026-09-07 remediation plan |
| v1.27.0 | `c17e0d6` | 2026-09-08 | M4-01: adopt LibKa0s v1.27.0, and wire the gate that came with it | standalone, 2026-09-07 remediation plan |
| v1.28.0 | `a348d0c` | 2026-09-09 | re-vendor LibKa0s v1.28.0 — the perf usage block renders correctly | standalone |
| v1.29.0 | `9d75235` | 2026-09-09 | re-vendor LibKa0s v1.29.0 — the JSON dump folds into the report step | standalone |
| v1.35.0 | `b4b2f16` | 2026-09-13 | Re-vendor LibKa0s v1.35.0 (Options 18.16.5.3, kit 20) | feat/2026-09-13-idlist (merged `68e7df3`) |
| v1.35.0 | `fff585a` | 2026-09-13 | Re-vendor LibKa0s v1.35.0 (re-cut: IdList quality color, load batching, clear before onAdd) | same branch, tag re-cut |
| v1.35.0 | `67f0cc2` | 2026-09-13 | Re-vendor LibKa0s v1.35.0 (re-cut: autocomplete #31, name lookup beyond the bags) | same branch, tag re-cut |
| v1.35.0 | `8f40c51` | 2026-09-14 | Re-vendor LibKa0s v1.35.0 (re-cut: a shared name the bags carry is refused, #31) | same branch, tag re-cut |
| v1.35.0 | `1a9de0b` | 2026-09-14 | Re-vendor LibKa0s v1.35.0 (re-cut: host kinds inherit a base kind's decorations) | same branch, tag re-cut |
| v1.36.0 | `86f9593` | 2026-09-15 | Re-vendor LibKa0s v1.36.0 | chore/2026-09-14-revendor-v1.36.0 (merged `6952809`) |
| v1.36.1 | `27f7ba3` | 2026-09-15 | Re-vendor LibKa0s v1.36.1: fix pooled CheckBox gold-fill leak | same branch |
| v1.36.2 | `d8aa323` | 2026-09-15 | Re-vendor LibKa0s v1.36.2: drop grid-cell yellow fill, ASCII-only strings | same branch |
| v1.37.0 | `4b0c902` | 2026-09-16 | Re-vendor LibKa0s v1.37.0 | standalone |
| v1.38.0 | `af217b5` | 2026-09-16 | Re-vendor LibKa0s v1.38.0: a bare /lh opens the settings panel | standalone |
| v1.39.0 | `ff97ff9` | 2026-09-16 | Re-vendor LibKa0s v1.39.0: the Launcher major and the OptionsTabs peel | standalone |
| v1.42.0 | `8b0989e` | 2026-09-17 | Disabling the addon stands it down, and a perf run takes the same latch | folded (the stand-down feature) |
| v1.43.0 | `6429eda` | 2026-09-17 | Re-vendor LibKa0s v1.43.0: kit revision 23 bounds every run and stops holding built instances | standalone (kit only) |
| v1.44.0 | `f1873d1` | 2026-09-19 | Re-vendor LibKa0s v1.44.0 | chore/libka0s-v1.44.0 (merged `66267e3`) |
| v1.45.0 | `0320fc9` | 2026-09-19 | Re-vendor LibKa0s v1.45.0 | chore/libka0s-v1.45.0 (merged `3fa698a`) |
| v1.46.1 | `793cfd1` | 2026-09-19 | Re-vendor LibKa0s v1.46.1 | chore/libka0s-v1.46.1 (merged `f059dd3`) |
| v1.47.0 | `3c76b8d` | 2026-09-20 | Re-vendor LibKa0s v1.47.0 | chore/revendor-libka0s-v1.47.0 (merged `e4b159c`) |
| v1.50.0 | `89fabc4` | 2026-09-21 | Re-vendor LibKa0s v1.50.0 | standalone |
| v1.51.0 | `7567fd7` | 2026-09-22 | Re-vendor LibKa0s v1.51.0 | standalone |
| v1.52.0 | `6d4560c` | 2026-09-22 | Re-vendor LibKa0s v1.52.0 | standalone |
| v1.53.0 | `de985b6` | 2026-09-22 | Re-vendor LibKa0s v1.53.0 | standalone |
| v1.54.2 | `a8f2133` | 2026-09-22 | Adopt the kit's US-English gate, and delete the copy this repo was keeping | folded (kit revision 24; library bytes identical to v1.53.0) |

Each commit copied both payloads whole from the tag and rolled the provenance line in the same
commit, which `tests/test_vendor_sync.lua` enforces. Each was green on lint and the headless suite
when it landed; the commit bodies record the counts.
