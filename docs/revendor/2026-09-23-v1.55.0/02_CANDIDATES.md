# 02 — Candidates: LibKa0s v1.55.0

Step 5 of `/wow-addon:revendor-libka0s`, taken non-interactively (suite phase 6, CP-6 delegated).
Sources, in the playbook's order:

- `git -C ../LibKa0s log --oneline v1.54.2..v1.55.0` (eight commits, listed in `01_DELTA.md`).
- The `CHANGELOG.md` block `## v1.55.0 — 2026-09-23` in `../LibKa0s`.
- The three new API documents: `../LibKa0s/docs/api/Compat/version-1-docs.md`,
  `../LibKa0s/docs/api/Bus/version-1-docs.md`, `../LibKa0s/docs/api/Schema/version-1-docs.md`.
  No existing major's minor moved (`01_DELTA.md` 3c), so there is no old/new document pair to diff.
- The per-consumer adoption deltas of the three design specs, which name this repo with file:line:
  `Ka0sAddonsCommonTasks/docs/2026-09-22-SUITE_STANDARDS_AND_LIBKA0S_SWEEP/3b-specs/compat.md` §8.0 and
  §8.5, `bus.md` §12 (common block, and *Catalog only* → **LootHistory**), `schema.md` §11 (common
  block, and **LootHistory — full adopter**).

Issue store: `gh issue list --search "LibKa0s" --state all` finds no recorded decline for Compat, Bus
or Schema (the `LIBKA0S-*` issues are older, settled rows about other majors). `grep -rn LibKa0s docs
--include=*.md | grep -iE 'declin|not adopt|exempt'` finds nothing on these three majors either. No
settled structural refusal exists for any candidate.

## Class A — delivered on the copy (not offered)

- **Kit revision 25** (`tests/_kit/`): the layout-§1 cap census gate, the `.gitattributes` body case
  in `test_eol`, the (basename, directory) suite declaration with shadow and unreferenced-suite
  reporting, and the commit SHA in the automated-test record. Each was wired in Phase 5 (`01_DELTA.md`
  3g) and runs green; nothing is left to decide.
- No existing library file changed a byte (`01_DELTA.md` 3c/3d), so no fix reached the addon through
  an existing major.

## Contract blockers (3g)

None. `01_DELTA.md` 3g records no library contract blocker; its three kit blockers were fixed in the
re-vendor commits (`8eb2638`, `5856ca8`, `a79c155`). Nothing from 3g is re-offered here.

## Class B/C — the candidates

All three are class C (a major this addon does not consume yet, `01_DELTA.md` 3e). The CHANGELOG
block names no other host-change candidate for this repo: its one host instruction beyond the three
majors is the `LIB_FILES` edit, already made in `5856ca8`.

### C1 — `LibKa0s-Bus-1.0`, `Catalog` only

- **What.** Declare the three message names once, as `NS.MSG`, through `Bus.Catalog`, in
  `core/Constants.lua`, and use the constants at every `SendMessage` / `RegisterMessage` site.
- **Evidence.** `bus.md` §12 *Catalog only* → **LootHistory**: "owes the table (debt row 9+13) ...
  replace the 20 literal lines across 6 files", factory `core/LootHistory.lua:20-26` stays.
  `../LibKa0s/docs/api/Bus/version-1-docs.md:184-220` (`Catalog`). The rule is
  `WowAddonStandards/standards/standards/architecture.md:97` (architecture-§4): "MUST declare every
  message name once as a constant ... never the literal"; wrapping in `Catalog` is a MAY.
- **Measured.** `git grep -n '"Ka0s_LootHistory_' -- ':!libs' ':!tests/_kit' ':!docs'` → 20 production
  lines: `core/Database.lua:265,292,706`; `modules/Analytics.lua:666,668`;
  `modules/Browser.lua:1229,1230,1240`; `modules/Collector.lua:228`; `settings/Panel.lua:159,169,492`;
  `settings/Schema.lua:159,171,177,183,267,275,282,293` (the spec's list, line for line). No
  `architecture-§4` row exists in `docs/ARCHITECTURE.md` → `## Documented deviations`, so this is an
  **unratified MUST breach**, not a recorded gap.
- **Files.** `core/Constants.lua`, the six files above, a test in `tests/test_constants.lua`, the
  parity case in `tests/test_surface_parity.lua`, `tests/run.lua` (surface-source row),
  `docs/ARCHITECTURE.md` → `## Message bus`, `docs/message-bus.md`.
- **Recommendation.** Adopt. The wire strings do not change (every one already passes `Catalog`'s
  checks: PascalCase `<Event>`, the `Ka0s_LootHistory_` prefix), so no receiver and no test that
  sends a literal moves.
- **Blast radius.** Mechanical replacement of 20 literals with constants; additive otherwise. The
  factory `NS.NewBusTarget` stays (untracked receivers, per the spec and `bus.md` §8).

### C2 — `LibKa0s-Compat-1.0`, `GetSpellName` only

- **What.** `NS.Compat.GetSpellName` becomes the library's member, with the reader stub
  (`function() return nil end`) when the major is absent.
- **Evidence.** `compat.md` §8.5: "`core/Compat.lua:82-87` `GetSpellName` -> library. **Behavior
  change:** a modern nil or `""` falls through to `C_Spell.GetSpellInfo` and the legacy global (inert
  on a live client ...); nil id guard unchanged. Keep `NS.Compat.GetSpellName` a field:
  `tests/test_attribution.lua:156-261` monkeypatches it. Tests: `tests/test_compat.lua:48` stays green."
  `../LibKa0s/docs/api/Compat/version-1-docs.md:162-167` (reader stub), `:177-241` (wiring, the gate,
  the table-map surface-source row). Member contract: `compat.md` §2.2 row 5.
- **Measured.** `grep -n "IsSecret\|CanAccess\|issecret\|Spec" core/Compat.lua` → no hit, so this
  host wires one member and no guard; the other eight members go in the parity `ignore` list.
- **Files.** `core/Compat.lua`, `tests/test_compat.lua`, `tests/test_surface_parity.lua`,
  `tests/run.lua`, `docs/ARCHITECTURE.md` (module map row), `docs/compat-layer.md`.
- **Recommendation.** Adopt. Closes the recorded duplication (harvest C2-F01) for the one member this
  addon shares with two other addons.
- **Blast radius.** Replaces a six-line host body. One deliberate behavior change on the ladder's
  miss path (J3), reachable only when `C_Spell.GetSpellName` answers nil or `""`.

### C3 — `LibKa0s-Schema-1.0`, full adopter

- **What.** `settings/Schema.lua` becomes the Schema setup file: `LibStub("LibKa0s-Schema-1.0", true)`
  or a write-completing, log-silent host stub; `lib:New{ rows = S.Schema, resolveRoot, debug,
  debugEnabled, print, resetExempt, L }`, stashed as `NS.SchemaRuntime`; the host's public names
  (`S:FindRow`, `S:ReadPath`, `S:WritePath`, `S.SameValue`, `S.BulkBegin`, `S.BulkEnd`,
  `S:ApplyDefault`, `S:Set`, `S:Get`, `S:Default`, `S:Register`) delegate to the instance or the lib.
- **Evidence.** `schema.md` §11 **LootHistory — full adopter** (`settings/Schema.lua:392-417`,
  `:423-428`, `:445-480`, `:449-455`, `:509-512`, `:515-546`, `:548-557`, `:569-583`), and the common
  block ("bind the host's existing public names to instance members so no call site moves", the
  library-absent case, `docs/ARCHITECTURE.md` Settings Schema section). API:
  `../LibKa0s/docs/api/Schema/version-1-docs.md:115-221` (instance surface, `Set` pipeline, bracket,
  `Validate`), `:284-358` (the degradation stub and how a host pins it), `:385-409` (adoption notes).
- **Files.** `settings/Schema.lua`, `tests/test_schema.lua`, `tests/test_surface_parity.lua`,
  `tests/test_libka0s.lua`, `tests/run.lua`, `docs/ARCHITECTURE.md`, `docs/schema.md`.
- **Recommendation.** Adopt, keeping every host name and the host's refusal wording (through the
  descriptor's `L`), so nothing a test pins or a player sees moves. The spec's deltas that do move
  behavior are listed under C3 in `03_DECISIONS.md` with the reading taken.
- **Blast radius.** **Replaces** the seam the whole addon writes through: `settings/Schema.lua:392-583`
  (192 lines with comments: registry, walks, copy, bracket, `Set`/`Get`/`Default`/`ApplyDefault`,
  `Register`) is deleted and rewired, and a host stub of the same order is added for the degraded
  path. The largest of the three
  by a wide margin: 203 test lines in ten files name the seam as `NS.Schema`
  (`git grep -h "NS.Schema[:.]" tests/ ':!tests/_kit' | wc -l`), before counting `test_schema.lua`'s
  local alias.
