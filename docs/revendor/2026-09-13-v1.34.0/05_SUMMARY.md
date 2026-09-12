# 05 — Summary: LibKa0s v1.33.0 → v1.34.0

**Tag moved v1.33.0 → v1.34.0 (`9165044` → `33bae81`).** Three library files moved: `Slash.lua`
(minor 9 → 10), `Options.lua` (minor 17 → 18) and `OptionsCompose.lua` (minor 4 → 5). The kit moved
revision 18 → 19. Every other file keeps its minor. The per-file table is in `01_DELTA.md`. Nothing
was deleted inside either payload.

**Reached the addon for free (class A).** The whole-value string parse, which here only refuses a
visibility value followed by extra words, and the tooltip, whose text does not move. See
`02_CANDIDATES.md` for what each means here. Kit revision 19 is not reached.

**References rolled.**

- `CLAUDE.md:51`, the provenance line.
- `docs/testing.md:133`, the sibling-checkout state sentence.

**Comments corrected.** None.

**Adopted:** none. **Declined:** none. **Skipped or unreached:** none.

**Gates at the re-vendor commit.**

| Point | `lua tests/run.lua` | `luacheck .` | `lizard -C 15` |
|---|---|---|---|
| Before the copy | 738 passed, 0 failed, 0 skipped, 738 total | 0 / 0 in 59 files | clean, no function above CCN 15 |
| After the copy, the roll and this bundle | 738 passed, 0 failed, 0 skipped, 738 total | 0 / 0 in 59 files | clean, no function above CCN 15 |

The vendored-payload pair ran rather than skipped, against `../LibKa0s` at `v1.34.0`, and passed.
No suite total moved. Nothing was pushed, and no issue was filed.
