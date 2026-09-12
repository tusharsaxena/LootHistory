# 05 — Summary: LibKa0s v1.32.0 → v1.33.0

**Tag moved v1.32.0 → v1.33.0 (`7d5e061` → `06ee368`).** Two library files moved: `Options.lua`
(minor 16 → 17) and `Slash.lua` (minor 8 → 9). The kit moved revision 17 → 18. Every other file
keeps its minor. The per-file table is in `01_DELTA.md`. Nothing was deleted inside either payload.

**Reached the addon for free (class A).** The font preload, the docstrings and the kit's
`OnProfileCopied` key. See `02_CANDIDATES.md` for what each means here.

**References rolled.**

- `CLAUDE.md:51`, the provenance line.
- `docs/testing.md:133`, the sibling-checkout state sentence.

**Comments corrected (kit revision 18).**

None.

**Adopted:** none. **Declined:** none. **Skipped or unreached:** none.

**Gates at the re-vendor commit.**

| Point | `lua tests/run.lua` | `luacheck .` | `lizard -C 15` |
|---|---|---|---|
| Before the copy | 738 passed, 0 failed, 0 skipped, 738 total | 0 / 0 in 59 files | clean, no function above CCN 15 |
| After the copy, the roll and the comments | 738 passed, 0 failed, 0 skipped, 738 total | 0 / 0 in 59 files | clean, no function above CCN 15 |

The vendored-payload pair ran rather than skipped, against `../LibKa0s` at `v1.33.0`, and passed.
No suite printed an error line. Nothing was pushed, and no issue was filed.
