# 05 — Summary: LibKa0s v1.54.2 → v1.55.0

Steps 5–8 of `/wow-addon:revendor-libka0s`, suite phase 6, run 2026-09-23 on branch
`suite/2026-09-22-standards-sweep`. The owner delegated the decisions (CP-6). Nothing was pushed, the
addon version was not bumped, and `libs/` and `tests/_kit/` were not touched after the copy.

## The move

The tag moved from **v1.54.2** to **v1.55.0** (tag object `bb161b7`, commit `6f9c5e0`). Phase 5 did the
copy (`5856ca8`), and `01_DELTA.md` records its per-file minor table: every existing file's LibStub minor
is unchanged; three files are new, `Compat.lua` 1, `Bus.lua` 1 and `Schema.lua` 1; and the kit moved
from revision 24 to 25.

## Delivered on the copy (class A)

Kit revision 25's gates (the layout-§1 cap census, the `.gitattributes` body case in `test_eol`, the
(basename, directory) suite declaration, and the commit SHA in the automated-test record). Phase 5
wired all four, so nothing was left to decide here.

## Contract blockers (3g)

There was no library contract blocker. Phase 5 found three kit blockers and fixed them before this
pass: the shadowing local prose gate, the undeclared `test_layout_cap`, and the three missing
`LIB_FILES` rows (`8eb2638`, `5856ca8`, `a79c155`).

## Adopted

| # | Candidate | Commit | Tests added |
|---|---|---|---|
| C1 | `LibKa0s-Bus-1.0` `Catalog`: `NS.MSG` in `core/Constants.lua`, 20 literal lines in 6 files replaced | `e11ed8d` | 8. Characterization: 3 in `test_constants.lua` (each wire name and payload through its real sender). New: 4 in `test_constants.lua` (the three keys, strictness, the literal scan, the degraded names) and 1 in `test_surface_parity.lua` (stub by name, `New` ignored) |
| C2 | `LibKa0s-Compat-1.0` `GetSpellName`, wired as a field with the reader stub | `e4a021e` | 7. Characterization: 3 in `test_compat.lua` (each rung with its arity, the nil-id guard). New: 3 in `test_compat.lua` (library identity, the J3 fall-through, the degraded nil) and 1 in `test_surface_parity.lua` (eight unwired members ignored) |
| C3 | `LibKa0s-Schema-1.0`, full adopter: `settings/Schema.lua:392-583` replaced by the descriptor, a write-completing host stub and one-line delegates under every host name | `0ce528b` | 15. Characterization: 8 in `test_schema.lua` (return arity and words, log-then-react order, six degraded read/write pins). New: 5 in `test_schema.lua` (delegation, the pre-db refusal, the read-back tally, the shape checks, the degraded boot line) and 2 in `test_surface_parity.lua` (the stub instance against a live one, the stub library by name). Re-pinned: the walk-write counters in `test_panel.lua` and `test_slash.lua` now count at each row's `validate` |

Each runner row the gates need was added in the same commit: `Kit.setSurfaceSource` gained
`LibKa0s-Bus-1.0`, `LibKa0s-Compat-1.0` and `LibKa0s-Schema-1.0`. `tests/test_libka0s.lua`'s
silent-flag list gained `core/Constants.lua`, `core/Compat.lua` and `settings/Schema.lua`, and its
"no `NS.L`" list gained `settings/Schema.lua`.

**Behavior that changed on purpose**, each pinned (the readings are in `03_DECISIONS.md`):

- `GetSpellName` falls through a nil or `""` top rung (J3).
- On a degraded install, `GetSpellName` answers nil (the reader stub), so unlisted deconstruct
  variants lose their name-family match.
- A settings write before the store exists is refused rather than raising.
- The bulk tally counts read-back movement (JC-8).
- `Register` also checks row shape (`group`, `type`, duplicate paths), and a broken row prints the
  library's `schema error` line.

**Kept identical on purpose:** every wire string, the refusal words `unknown path: <path>` and
`invalid value`, the `[Set]` line bytes, every host name, both descriptors' bindings, and the degraded
boot line.

## Declined

None. No candidate met a decline rule: none of the three specs lets this repo defer, and each
adoption landed green without changing any behavior a test pinned or a player sees, apart from the
deliberate changes listed above that the specs prescribe. No issue was filed.

## Skipped or unreached

None. All three candidates were reached and adopted.

## Gates

All counts are from `~/.claude/wow-addon/bin/ka0s-bounded lua tests/run.lua` and
`~/.claude/wow-addon/bin/ka0s-bounded luacheck .`.

| Point | Tests | Lint |
|---|---|---|
| Baseline (`a79c155`) | 828 passed, 0 failed, 0 skipped, 828 total | 0 warnings / 0 errors in 65 files |
| C1 characterization, before the code | 831 passed, 0 failed | — |
| After C1 (`e11ed8d`) | 836 passed, 0 failed, 0 skipped, 836 total | 0 warnings / 0 errors in 65 files |
| C2 characterization, before the code | 839 passed, 0 failed | — |
| After C2 (`e4a021e`) | 843 passed, 0 failed, 0 skipped, 843 total | 0 warnings / 0 errors in 65 files |
| C3 characterization, before the code | 851 passed, 0 failed | — |
| C3 code, before the re-pins | 848 passed, 3 failed (the three cases that count walk writes through the two `NS.Schema.Set` spy helpers, as predicted in `03_DECISIONS.md`) | — |
| After C3 (`0ce528b`) | 858 passed, 0 failed, 0 skipped, 858 total | 0 warnings / 0 errors in 65 files |
| Close-out | 858 passed, 0 failed, 0 skipped, 858 total | 0 warnings / 0 errors in 65 files |

Complexity was checked with `ka0s-bounded lizard settings/Schema.lua`: the highest CCN is 11
(`R.Set` in the host stub), under the ceiling of 15. The perf suite was **skipped**: this repo has no
`tests/perf.lua` (a ratified `performance-§12` row), so there is nothing to re-run.
`docs/test-cases.md` was regenerated with `lua tests/run.lua --list` and totals 858. The README
Tests badge now reads 858/858.

## OPEN

- **`NS.Util.SplitPath` (`core/Util.lua:25`) has no production caller now.** The runtime splits its
  own paths. Deleting it (with its `tests/test_util.lua` case and the `module-map.md` mentions) is a
  follow-up the spec did not list.
- **Upstream readings this run took, for the spec owners.**
  - A catalog-only Bus adopter's stub carries only `Catalog`, and the parity case ignores `New`.
  - A Schema host stub's `Validate` may stay a real, silent resolution walk. The alternative is the
    reference's "0, 0, 0 and one line", which would print a new line on every degraded login.
  - The descriptors stay late-bound through the host names where suites spy on them.

  None of these deviates from the standard. Each narrows a spec.
- **In-game checks owed:** a spell cast that attributes as milling or prospecting (the Compat
  ladder on a live 12.x client), and one settings write, one Defaults click and one `/lh resetall`
  with debug on (the `[Set]` lines from the library's seam).
