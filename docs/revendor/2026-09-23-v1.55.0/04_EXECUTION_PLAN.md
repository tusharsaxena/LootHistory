# 04 — Execution plan: LibKa0s v1.55.0

Step 7 of `/wow-addon:revendor-libka0s`. One commit per candidate, in the `03_DECISIONS.md` order.
Each follows the same sequence: characterization cases first, green on the unchanged code; then the
code change and the new-behavior cases; then the gate (`ka0s-bounded lua tests/run.lua`, `ka0s-bounded
luacheck .`), which must be green before the commit. A candidate that goes red and cannot be made
green without changing pinned behavior is rolled back to its commit boundary and filed as a decline.
`libs/` and `tests/_kit/` are not touched.

## C1 — Bus `Catalog` (commit 1)

- **Characterization first** (`tests/test_constants.lua`, green on the unchanged code). Drive each
  real sender with `NS.bus.SendMessage` captured, and assert each wire name and its payload:
  `Database:Add` → `Ka0s_LootHistory_RecordAdded` `(record, index)`, `Database:FireHistoryChanged` →
  `Ka0s_LootHistory_HistoryChanged`, and one `SettingsChanged` reason per `onChange` family
  (`settings.qualityThreshold` → `"quality"`, `settings.scale` → `"chrome"`).
- **Code.** `core/Constants.lua` declares the three names once and resolves
  `LibStub("LibKa0s-Bus-1.0", true)`, falling back to a `Catalog`-only stub. It publishes
  `NS.MSG = Bus.Catalog(addonName, MSG)` and `NS.BusLib`. The 20 literal lines in six files become
  `NS.MSG.<KEY>`.
- **New cases.** `NS.MSG` holds exactly the three keys with their wire values. On the live build it
  is strict, so reading an undeclared key raises. No authored `.lua` outside `core/Constants.lua`
  types a `"Ka0s_LootHistory_` literal (a source scan over `ADDON_FILES`). The degraded build's
  `NS.MSG` carries the same three values (from `tests/degraded_env.lua`). Parity:
  `Kit.assertSurfaceParity(degradedNS.BusLib, "LibKa0s-Bus-1.0", { "New" })`, in
  `tests/test_surface_parity.lua`.
- **Runner.** `tests/run.lua` `Kit.setSurfaceSource` gains `["LibKa0s-Bus-1.0"]`.
- **Docs.** `docs/ARCHITECTURE.md` → `## Message bus` names `NS.MSG` and the major.
  `docs/message-bus.md` gets the same.
- **Proof.** The characterization cases stay green with the literals gone, and the scan goes red if
  a literal comes back.

## C2 — Compat `GetSpellName` (commit 2)

- **Characterization first** (`tests/test_compat.lua`, green on the unchanged code):
  `C_Spell.GetSpellName` present → its answer; `C_Spell` absent with a `GetSpellInfo` global → the
  global's first return, arity 1; a nil id → nil with no rung called; every rung absent → nil. The
  existing `:48` case stays.
- **Code.** `core/Compat.lua:80-87` becomes the one wired line plus the reader stub.
- **New cases.** J3 fall-through: `C_Spell.GetSpellName` answers nil or `""` →
  `C_Spell.GetSpellInfo(id).name`. The degraded build answers nil even with `C_Spell` present (the
  absent table). Parity: `Kit.assertSurfaceParity(degradedNS.Compat, "LibKa0s-Compat-1.0", <the eight
  unwired members>)`. The live `NS.Compat.GetSpellName` is the library's function, by identity.
- **Runner.** `Kit.setSurfaceSource` gains `["LibKa0s-Compat-1.0"]`.
- **Docs.** `docs/ARCHITECTURE.md` module-map row for `core/Compat.lua`, and `docs/compat-layer.md`.

## C3 — Schema, full adopter (commit 3)

- **Characterization first** (`tests/test_libka0s.lua` or `tests/test_schema.lua`, green on the
  unchanged code), on the degraded build, with a `db.global` seeded from `NS.defaults.global`:
  - `Get` reads a stored value (the runtime readers `NS.AddonIsOff`, `BrowserTable.rowHeight`);
  - `Set` stores a copy of a table value, runs `onChange`, and refuses an unknown path with
    `unknown path: <path>`;
  - the minimap row inverts through its own `set`;
  - `ApplyDefault` restores a row, and skips `minimap.hide` only inside a bracket;
  - `Sl:ResetEverything` keeps `minimap.hide` through `ReadPath` / `WritePath`;
  - `Register` answers 0.

  On the live build: the order of one write (`[Set]` line, then `onChange`), and the return arity of
  `Set` on success, unknown path and `validate` refusal (`true`; `false, "unknown path: x"`;
  `false, "invalid value"`).
- **Code.** `settings/Schema.lua:392-583` is replaced by the setup block (`LibStub(..., true)` or the
  host stub, `lib:New{...}`, `NS.SchemaRuntime`, `NS.SchemaLib`) and the one-line delegates under the
  unchanged host names.
- **Re-pins.** The walk-write counters in `tests/test_panel.lua:574` and `tests/test_slash.lua:200`
  count at each row's `validate`, per `03_DECISIONS.md`. Every other existing assertion stays as it
  is.
- **New cases.** Instance parity: `Kit.assertSurfaceParity(NS.SchemaRuntime,
  degradedNS.SchemaRuntime, "schema instance vs host stub")`. Stub-library parity by name, ignoring
  `STRINGS`. The live seam is the library's: `NS.SchemaRuntime.Set` is reached, and
  `S:ReadPath == lib.Read` in effect. `Register` measures 0 against the live `Validate`.
  `settings/Schema.lua` joins the "silent flag" and "no `NS.L`" seam lists in
  `tests/test_libka0s.lua`.
- **Runner.** `Kit.setSurfaceSource` gains `["LibKa0s-Schema-1.0"]`.
- **Docs.** `docs/ARCHITECTURE.md` → `## Settings schema` names the major and the instance.
  `docs/schema.md` covers the seam section. `tests/test_libka0s.lua`'s `LIB_FILES` comments stop
  saying "not adopted".

## Close-out (commit 4)

`docs/test-cases.md` regenerated with `lua tests/run.lua --list`, the `docs/testing.md` counts and the
README Tests badge updated, and `05_SUMMARY.md` written. The bundle (02-05) is committed. Line endings
are checked with `git ls-files --eol` over every touched path.

## As executed (differences from the plan above)

- **C3's degraded minimap cases changed shape.** The degraded Options stub's `MasterControls`
  composes no rows, so the degraded build has no `minimap.hide`, `settings.enabled` or session
  rows. The characterization case therefore pins that a write to the minimap row is refused and
  stores nothing. The sweep veto is exercised on a row the degraded build does have, by naming it in
  the same `RESET_EXEMPT` table for the length of the case. Both were green on the old code before
  the seam moved.
- **C2 needed a lint grant.** `.luacheckrc`'s `files["tests/"]` lets the suites plant `_G.C_Spell`
  and `_G.GetSpellInfo`, the same scoped mechanism the file already uses for `_G.C_TooltipInfo`.
- **C3's live `Register` probes** assert exactly one problem each (a duplicate path; a resolving
  row with no `group`), so each check is proven on its own.
- **Close-out also fixed** `docs/ARCHITECTURE.md`'s payload count ("eleven of its twelve majors",
  stale since `5856ca8`) to fourteen of fifteen, and re-pointed every doc citation into
  `settings/Schema.lua` that the seam's replacement moved (`common-tasks.md`, `slash-dispatch.md`,
  `schema.md`, `settings-panel.md`, `module-map.md`, `ARCHITECTURE.md`).
