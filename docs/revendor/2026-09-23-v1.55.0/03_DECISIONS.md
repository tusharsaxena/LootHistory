# 03 — Decisions: LibKa0s v1.55.0

Step 6 of `/wow-addon:revendor-libka0s`. There was no interview: the owner delegated the calls to
this run (suite phase 6, CP-6), under these rules. Adopt what the spec prescribes for this repo, one
major per commit, characterization test first, with the degraded case and the parity gate the spec
asks for. Decline as *not now* (`state:triaged`) only where the spec lets this repo defer, or where
the adoption cannot land green without changing behavior a test pins or a player sees, after one
honest attempt. Decline as *never* (`state:will-not-do`) only for a structural misfit the spec or
this repo's docs record. A decline is filed as a public GitHub issue on this repo.

Order (rule 4 of CP-6, the playbook's Step 6 order): a live defect first, then a recorded gap, then
new capability, smallest blast radius first within a class.

1. **C1 Bus `Catalog`**: fixes a live defect. The 20 literal message names breach architecture-§4's
   declare-once MUST, and no register row ratifies it (`02_CANDIDATES.md` C1).
2. **C2 Compat `GetSpellName`**: closes a recorded gap (harvest C2-F01). Smallest radius.
3. **C3 Schema, full adopter**: closes a recorded gap (harvest C2-F03). Largest radius.

Each decision is written here as it lands.

## C1 — `LibKa0s-Bus-1.0` `Catalog`: **adopt**

Decided 2026-09-23. `bus.md` §12 prescribes it for this repo and offers no deferral ("owes the
table"). The wire strings stay the same, so nothing a player sees and no test that sends a literal
changes.

Readings taken where the spec left a choice:

- **Home: `core/Constants.lua`.** This addon has no `core/Bus.lua`. architecture-§4 puts the table in
  `core/Constants.lua` for that case, and so does the spec.
- **The stub carries `Catalog` only, and the parity case ignores `New`.** The common block asks for
  "the §7 stub" and a `Kit.assertSurfaceParity(stub, "LibKa0s-Bus-1.0")` case. The §7 stub's `New`
  builds a record, and a catalog-only adopter never calls `New`: its receivers stay on the untracked
  `NS.NewBusTarget` (spec: "Factory `core/LootHistory.lua:20-26` stays"). A stub `New` would be dead
  host code with no caller. So the case names `New` in its `ignore` list, with that reason. This is
  the same mechanism Compat's gate uses for members a host does not wire, and a member the major
  adds later still fails parity until the host decides.
- **Tests keep their literals.** `tests/test_database.lua:32` and the others assert the wire string
  itself. That is the contract a receiver in another file depends on, so they stay independent pins.
  The declare-once MUST covers the addon's `SendMessage` and `RegisterMessage` call sites.
- **`Kit.setSurfaceSource` gains `["LibKa0s-Bus-1.0"]`**, as the Compat gate amendment requires for
  a table-map runner. The Bus spec's by-name case needs the same row.

## C2 — `LibKa0s-Compat-1.0` `GetSpellName`: **adopt**

Decided 2026-09-23. `compat.md` §8.5 prescribes it and names no deferral.

- **One member wired, as a field.** `NS.Compat.GetSpellName = CompatLib and CompatLib.GetSpellName or
  <reader stub>`. It stays a field on `NS.Compat` because `tests/test_attribution.lua:156-261`
  replaces it at runtime. The other eight members are not wired. `grep` finds no secret guard and no
  spec read in `core/Compat.lua`, so they go in the parity case's `ignore` list, and a member the
  major adds later fails parity until this repo decides.
- **The reader stub answers `nil`**, the absent table's value
  (`../LibKa0s/docs/api/Compat/version-1-docs.md:162-167`). **Consequence on a degraded install,
  accepted:** without the library, `modules/Attribution.lua` gets no localized seed names, so the
  name-family match for deconstruct variants the id tables do not list stops matching. The
  enumerated ids still match, and nothing raises: `seedToken` and `OnSpellcastSucceeded` already
  treat a nil name as "not cached". A degraded install is a partial payload, which
  `library-stack-§7` forbids, and the API document rejects a stub that re-implements the top rung
  because that would re-create the duplication. The degraded case pins the `nil`.
- **The J3 change is pinned, not avoided.** If `C_Spell.GetSpellName` answers nil or `""`, the
  library now falls through to `C_Spell.GetSpellInfo(id).name` and then to the legacy global.
  Before, the first rung present was authoritative. On a live client both rungs read the same spell
  data, so this can only turn a nil into a name. A new case pins the fall-through.
- **The runner's `Kit.setSurfaceSource` gains `["LibKa0s-Compat-1.0"]`** (compat.md §4, gate
  amendment). Without it, the by-name parity call raises "the surface source answers nil".

## C3 — `LibKa0s-Schema-1.0`, full adopter: **adopt**

Decided 2026-09-23. `schema.md` §11 makes this repo a full adopter and offers it no deferral. (The
MAY-defer clause, V-3, covers only the partial adopters AuraMaster and MultiMeters.)

Readings taken, each chosen so that nothing a test pins or a player sees moves:

- **Every host name stays, as a one-line delegate.** `S:FindRow`, `S:Get`, `S:Set`, `S:Default`,
  `S:ApplyDefault`, `S.BulkBegin`, `S.BulkEnd` → instance members. `S:ReadPath`, `S:WritePath` and
  `S.SameValue` → `lib.Read` / `lib.Write` / `lib.SameValue`. `S:Register` → `inst.Validate`. The
  host keeps its colon-called names (O-1 is still open upstream), and the instance is published as
  `NS.SchemaRuntime`.
- **The two descriptors stay late-bound through the host names**
  (`settings/OptionsSetup.lua:179-200`, `settings/Slash.lua:371-386`). The spec says to point them at
  the members "only when the host has no pre-seam gate". This host has no gate, so in substance
  every descriptor call already reaches the instance, one alias away. Binding the values directly
  would bypass the write-seam spies that four suites put on `NS.Schema.Set`
  (`tests/test_panel.lua:575`, `tests/test_slash.lua:201`, `:778`, `tests/test_disabled.lua:376`)
  and would make those pins weaker. This narrows the spec, not the standard.
- **Refusal wording is kept through `L`**: `{ NOT_FOUND = "unknown path: %s", INVALID = "invalid
  value" }`. `tests/test_schema.lua:520` and `:560` pin those words, and the API document names `L`
  as the way to keep them.
- **No `format` is passed.** The `[Set] <path> = <value>` line keeps `tostring(value)`, which is
  what it prints today. The spec's delta for this repo names no `format`.
- **No `announce`**, as the spec says. The bus messages stay in each row's `onChange`.
- **`S:ApplyDefault` → `inst.ApplyDefault`, with `resetExempt = S.RESET_EXEMPT`.** As a result, a
  bulk walk's writes go to the instance's own `Set` and no longer through the host name. The two
  test helpers that counted walk writes with a spy on `NS.Schema.Set` (`tests/test_panel.lua:574`,
  `tests/test_slash.lua:200`) are re-pinned to count at each row's `validate`, which step 3 of the
  seam runs on every write, whatever entry reached it. The assertion ("every unexempt row still goes
  through the seam") does not change. Only how it is observed does.
- **The tally is read-back (JC-8).** It differs from today's before-versus-argument test only inside
  a bracket, and only for a closure row whose `set` stores something other than its argument (here,
  a refused `state.testMode` start). The library's count is the true one, because the row did not
  move. This is a deliberate change, per the spec.
- **`S:Register` → `inst.Validate{ types = bool/number/string/color/table, defaultsRoot → NS.defaults.global }`**,
  returning `errors + missing`, the sum the spec names for this host. The check gains `group` and
  duplicate-path validation (JC-13), and it must measure zero before the commit. The line printed for
  a broken row becomes the library's `schema error: row #i (<path>): ...`. That is a developer
  diagnostic that never prints on a healthy schema, and no test pins the old words
  (`git grep "schema path does not resolve"` finds only `settings/Schema.lua`).
- **The degradation stub is write-completing and log-silent**, trimmed from the library's
  `referenceStub` (`../LibKa0s/tests/test_schema.lua:183-318`), with refusals in this host's words.
  One change from the reference: **`Validate` stays a real, silent resolution walk** instead of
  "`0, 0, 0` and one honest line". Today's degraded load runs the host's own boot check and prints
  nothing for a healthy schema. A line on every degraded login would be a new chat line the player
  sees, and the resolution walk is the only part of `Validate` that this host's degraded boot ever
  ran.
- **Perf.** No re-run is owed: this repo has no `tests/perf.lua`, which is a ratified
  `performance-§12` row.
- **Left in place:** `NS.Util.SplitPath` (`core/Util.lua:25`). After the adoption, no production
  code calls it. The spec's list for this repo does not name it, so deleting it is recorded as OPEN
  in `05_SUMMARY.md` and not done here.
