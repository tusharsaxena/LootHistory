# Summary (LootHistory)

LibKa0s v1.71.0 -> v1.75.0 from the local annotated tag (`265a89e`, via `git archive`), base read
from the CLAUDE.md provenance line. v1.72.0, v1.73.0 and v1.74.0 were never vendored here, so this
one bundle covers them and no span bundle is owed. Minors: Core 10 -> 11, Item 2 -> 3, Media 4 -> 5
with MediaIcons 1 (new), Widgets 12 -> 13, DebugLog 19 -> 20, DebugLogDiagnostics 2 -> 3, Options
28 -> 29 with OptionsIdList 4 -> 5, OptionsTabs 8 -> 9 and OptionsDrawer 1 (new), Perf 14 -> 15 with
PerfPanel 6 -> 7, and the new majors Glow 1 and Sim 1 (SimTimeline 1, SimPanel 1). Test kit 38 -> 41.
Both payloads matched the tag under `diff -r` before the prune.

**Icon declaration and prune.** The provenance sentence at `CLAUDE.md:56` ran on into prose, so it
was split; the declaration under it is `LibKa0s icons: ban, chat, chevron-down, chevron-right,
circle-check, clear, close, confirm, copy, graph, info, lock, segment, sort-down, sort-up,
spreadsheet.` The tag's `tools/prune-icons.lua` kept 17 files (16 `.tga` + the Open Iconic license)
and removed 5,823: 208 flat Open Iconic marks, all of `phosphor/` (1,435 files) and all of
`game-icons/` (4,180 files).

**Credits.** README `## Credits` keeps JetBrains Mono (OFL 1.1) and widens the Open Iconic (MIT)
credit to what is drawn: the History and Holdings menus, sort and group marks, the Bound lock, the
dropdown and checkbox marks, the export icon, the settings page's tick, info and handle marks, the
window close and the debug console's copy and clear. No Phosphor or Game-icons credit: neither ships.
The test-mode strip's `info` mark joins the credit with LH-04, which adds the strip.

**Blockers fixed in the re-vendor commit** (01_DELTA.md): the Options stub gains `Drawer` and loses
its dead `__releaseChrome` mirror (LibKa0s#45); the Item stub gains a `BonusIDsFromLink` with the
library's walk, pinned against the live answer; the whole-catalog icon walk becomes a declaration
check (declaration == `DRAWN`, each with its file); the `info` art check asserts the declaration
first; the v1.71.0 pins relax and a v1.75.0 case pins the release; `LIB_FILES` gains the six new
files; the Widgets dropdown case moves its pin to minor 13; `docs/debug.md`, `docs/testing.md` and
`docs/ARCHITECTURE.md` are brought up to date.

**Adopted in this commit:** none. **Adoptions owed, each its own item:** `Item.BonusIDsFromLink`
(LH-02), `W.SearchBox` (LH-03), `W.TestStrip` (LH-04), `LibKa0s-Sim-1.0` (LH-06..LH-14).
**Declined:** none, so no issue filed. **Not candidates:** Glow, W.StepPanel, O.Drawer,
Media.ICON_SETS/IconAuthor, Perf.Note's `false`.

**Gates.** `lua tests/run.lua` (bounded): 1526 passed, 0 failed, 1 skipped (the diagnostics
contract's declared opt-out). `luacheck .`: 0 warnings / 0 errors in 118 files. `docs/test-cases.md`
regenerated (Total 1526, Skipped 1); README badge 1524/1524 -> 1526/1526 (two new cases: the
BonusIDsFromLink comparison and the v1.75.0 pin). In-client smoke SM-LH-1..6 is the owner's.
