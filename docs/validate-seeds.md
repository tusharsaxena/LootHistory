# Seed validation — Loot History

The seed-validation contract `/dev-copilot:validate-seeds LootHistory <flavor>` runs. The command
supplies the loop (clean tree, one date, status, derive, rule, apply, gate, hand-back) and its
standing rules. This file supplies Loot History's procedure: the tool, the files it writes, the
precedent a ruling follows and the nuances of each client. The headings below are the interface
the command reads, so keep their names.

The seeds are the deconstruct spell ids in `modules/Attribution.lua`:

- `DECONSTRUCT_IDS`, one table per client: spell id to `DISENCHANT`, `MILLING` or `PROSPECTING`. A
  cast whose id is listed stamps that source, whatever the client's language.
- `NAME_SEEDS_BY_CLIENT`: the spells whose *localized* name is the family a cast's name is matched
  against, for the variants too numerous to list. A plain seed is the bare family word
  ("Milling"). A `dropLast` seed is one per-herb or per-ore mass spell, whose name minus its last word
  is the stem ("Mass Mill").
- `modules/SimDrivers.lua`'s `D.SPELLS`: the simulator's casts, checked against `DECONSTRUCT_IDS`
  only.

Nothing else in `core/` or `modules/` is a seed list of game ids that DB2 can check. The test-mode
and simulator item sets are invented sample data, and the per-client constants in
`core/Constants.lua` are the addon's own keys. A source belongs to one profession's skill line:
Disenchant to Enchanting (333), Milling to Inscription (773), Prospecting to Jewelcrafting (755).
`SkillLineAbility` says which line teaches a spell, and `SkillLine.ParentSkillLineID` folds an
expansion's child line into its profession.

Each run ends in a frozen bundle under `docs/seed-research/<date>-<flavor>/`. The tool is
`tools/seeds/seeds.py`, and its docstring is the reference for every candidate and flag kind. The
first runs are `docs/seed-research/2026-11-25-retail/` and `docs/seed-research/2026-11-25-forever/`
(LibKa0s#102).

## Flavors

| Flavor | Source | Seed files | Tools |
| --- | --- | --- | --- |
| `retail` | wago.tools product `wow` (Retail live) | `modules/Attribution.lua` (`DECONSTRUCT_IDS.retail`: `apply` writes it; `NAME_SEEDS_BY_CLIENT.retail`: a hand edit), `modules/SimDrivers.lua` (`D.SPELLS.retail`, checked only) | `tools/seeds/seeds.py --flavor retail` |
| `forever` | wago.tools product `wowf` (WoW Forever) | the same files' `forever` tables, every change a hand edit | `tools/seeds/seeds.py --flavor forever` |

No flavor reads ForeverDB. Spells and skill lines are client data, which DB2 holds (clients-§10),
so there is no server-side fact here for a second source to supply.

## Rules

- **Only `apply` writes `DECONSTRUCT_IDS.retail`**, and only for an accepted `ids:` candidate or an
  `ids` flag ruled `remove`. A new entry goes on a new line after its source's last line, three to a
  line. `NAME_SEEDS_BY_CLIENT`, `D.SPELLS` and the whole Forever table are hand edits. A `names` or
  `sim` flag ruled `fix` makes `apply` refuse until the file no longer holds what the flag is about.
- **Rulings are data.** They live in `tools/seeds/retail_rulings.json` and
  `tools/seeds/forever_rulings.json`, written only by `seeds.py rule`. A ruling is keyed
  `ids:<spell>` for a candidate or `shipped:<kind>:<list>:<id>` for a flag, never by build. It
  holds until the thing it ruled on stops being proposed.
- **Precedent, in this order, never re-litigated:**
  1. a ruling already in the flavor's rulings file;
  2. `modules/Attribution.lua`'s header comments. Its enumeration rule decides most candidates. The
     ids are "generic + per-expansion + a representative per-herb Mass Mill" and "base +
     per-expansion + a representative per-ore Mass Prospect", and the name family covers the rest.
     So a per-expansion spell (shape `expansion`) is accepted. A per-herb or per-ore mass spell
     (shape `mass`) is rejected, apart from the one representative. Another Enchanting spell named
     exactly Disenchant is rejected, because the 13262 seed's name matches it in every locale;
  3. WoW Forever's Milling and Prospecting are **EMPTY BY DECISION** (the Forever port's D15, ruling
     R2): the forever flavor checks and proposes Disenchant alone. It never proposes a Milling or
     Prospecting id, and it never filters Retail's list into Forever's;
  4. `docs/ARCHITECTURE.md`'s per-client feature table (the deconstruct seeds' rows) and the
     assertions in `tests/test_attribution.lua`, which pin today's lists. Roll an assertion the run
     changes; one that contradicts a ruling goes to the owner.
- **What "accept" means here.** Accept an id only when the build names it in its source's family
  and teaches it on its source's profession line, and the header's enumeration rule admits it.
  Remove a shipped id the build has no `SpellName` row for, or names outside the family. Either way
  the evidence is the bundle's `raw/`. When the data cannot decide (a family name no skill line
  teaches, which a client may or may not still fire), keep it and say so in the reason.
- **Evidence.** The bundle's `raw/*.csv.gz`: `SpellName` (`ID`, `Name_lang`), `SkillLineAbility`
  (`Spell`, `SkillLine`) and `SkillLine` (`ParentSkillLineID`). The first two are cut to the three
  professions' spells and the shipped ids, so a bundle stays small, and a replay reproduces the run.
  The names are the build's enUS strings. The client matches the *localized* name, so a family change
  is checked on a non-English client too (smoke LOC-4).
- **Privacy.** No player name, realm or GUID goes into a bundle, a ruling or a commit.

## Flavor: retail

### Status

```sh
python3 -I tools/seeds/seeds.py status --flavor retail
```

Prints `CURRENT <build> (<bundle>)`, or `NEW <build> (last ruled <build>, <bundle>)`, comparing the
live `wow` build (the newest non-bgdl build the builds API lists) with the newest `*-retail` bundle.

### Freeze and derive

```sh
python3 -I tools/seeds/seeds.py derive --flavor retail --build <build> --bundle docs/seed-research/<date>-retail --date <date>
```

It downloads three tables at `?build=<build>` (SpellName is about 11 MB, cached in
`tools/seeds/.cache/<build>/`, git-ignored), with the User-Agent `LootHistory-seed-check`. It fails
unless each export's file name carries the build asked for. Then it runs the coverage gate: Disenchant
13262, the three profession lines and 13262 on Enchanting must be there. **If the gate fails, stop**:
fix the tool's map, not the rulings. Report the candidate and flag counts and the unruled count.

### Rule

```sh
python3 -I tools/seeds/seeds.py check --bundle docs/seed-research/<date>-retail
python3 -I tools/seeds/seeds.py rule --tsv <scratchpad>/rulings.tsv --bundle docs/seed-research/<date>-retail
```

`check` lists every unruled key and exits 1, and must print `OK` after `rule`.

- **Candidates** (`accept` or `reject`): `ids:<spell>`, each noted with its shape (`plain`,
  `expansion` or `mass`) and its profession line.
- **Flags on `ids`** (`keep` or `remove`): `gone`, `family`, `line` and `unlined`. An `unlined` id
  that is the plain family word (51005 Milling, 31252 Prospecting) is a name seed, so it is kept.
- **Flags on `names`** (`keep` or `fix`): `gone`; `token`, where the name does not make the stem its
  role needs (a plain seed must be the bare family word, and a `dropLast` seed
  "Mass Mill|Prospect <one word>", since a two-word herb leaves a three-word stem); `unlisted`, where
  the seed's id is not in `DECONSTRUCT_IDS` under the same source. A `fix` replaces the seed by hand
  with a spell the run's candidates show, and accepts that spell's `ids:` candidate so the two lists
  stay paired.
- **Flags on `sim`** (`keep` or `fix`): `unlisted`.

### Apply

```sh
python3 -I tools/seeds/seeds.py report --bundle docs/seed-research/<date>-retail --date <date>
python3 -I tools/seeds/seeds.py apply  --bundle docs/seed-research/<date>-retail --date <date>
```

`report` comes before `apply`, so `RULINGS.md` is written while the candidates still include what
is about to be applied. Make every `fix` hand edit first: `apply` refuses while anything is unruled
or a `fix` is still owed. It rewrites only `DECONSTRUCT_IDS.retail` (CRLF kept, no trailing space
left by a removal), and a second `apply` changes nothing. To prove the result, copy the bundle to the
scratchpad and `derive --replay` the copy. It must report 0 unruled. Do not replay the committed
bundle after `apply`: its `candidates.json` is the record of what the run proposed.

### After

- Roll the assertions in `tests/test_attribution.lua` that pin the lists (the Retail id count and
  the name-seed string) and the fake names its cases key by seed id, and add a case for the ids the
  run added and removed. Run the suite under both kit profiles.
- Write the bundle's `ANALYSIS.md` by hand, in the 2026-11-25 bundles' shape: what the build says,
  what was proposed, accepted and rejected and why, the *Judgment calls applied*, and what a later
  run should re-check.
- Add a smoke check to `docs/smoke-tests.md` for every shipped-data change, and list it under
  *Pending sign-off*. A run that changes nothing adds none. A replaced name seed also updates LOC-4's
  `/dump` line.
- Regenerate `docs/test-cases.md` (`lua tests/run.lua --list`).

### Stage

`modules/Attribution.lua`, `tools/seeds/retail_rulings.json`, `docs/seed-research/<date>-retail`,
plus any test, smoke or inventory edits. Commit message:
`Seeds (retail): re-validated against <build> (<date>)`.

## Flavor: forever

### Status

```sh
python3 -I tools/seeds/seeds.py status --flavor forever
```

Prints `CURRENT <build> (<bundle>)` or `NEW <build> (...)`, comparing the live `wowf` build with the
newest `*-forever` bundle.

### Freeze and derive

```sh
python3 -I tools/seeds/seeds.py derive --flavor forever --build <build> --bundle docs/seed-research/<date>-forever --date <date>
```

The same three tables from product `wowf`. The gate needs Disenchant 13262 on Enchanting (333).
Inscription and Jewelcrafting are not required, and the bundle's `RULINGS.md` *Build facts* line
records whether the build has them at all.

### Rule

```sh
python3 -I tools/seeds/seeds.py check --bundle docs/seed-research/<date>-forever
python3 -I tools/seeds/seeds.py rule --tsv <scratchpad>/rulings.tsv --bundle docs/seed-research/<date>-forever
```

Nuances:

- **Disenchant alone.** Candidates are Enchanting-line spells in the Disenchant family. The flags are
  Retail's kinds, over the one id, the one name seed and the simulator's one cast.
- **Milling and Prospecting are EMPTY BY DECISION.** Even if a later Forever build gains Inscription
  or Jewelcrafting, the tool does not propose for them. Seeding them would need the owner to reverse
  ruling R2 first, and `C.SOURCE_ABSENT` would have to change with it.

### Apply

```sh
python3 -I tools/seeds/seeds.py report --bundle docs/seed-research/<date>-forever --date <date>
python3 -I tools/seeds/seeds.py apply  --bundle docs/seed-research/<date>-forever --date <date>
```

`apply` refuses any Forever write. `DECONSTRUCT_IDS.forever` is one line and a hand edit, so an
accepted Forever candidate is written by hand, then the bundle is proved as for Retail. With nothing
accepted or removed, `apply` changes nothing.

### After

- Roll any `tests/test_attribution.lua` assertion that pins a changed Forever row, under both kit
  profiles.
- Write the bundle's `ANALYSIS.md` by hand, in the 2026-11-25 bundles' shape.
- Add a FOREVER smoke check for every list that changed, listed under *Pending sign-off*.

### Stage

`modules/Attribution.lua` (if changed), `tools/seeds/forever_rulings.json`,
`docs/seed-research/<date>-forever`, plus any test or smoke edits. Commit message:
`Seeds (forever): re-validated against <build> (<date>)`.

## Gate

```sh
~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua
KA0S_KIT_CLIENT=forever ~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua
~/.claude/dev-copilot/bin/ka0s-bounded luacheck .
python3 -m pytest -q tools/seeds
```

luacheck must report 0 warnings and 0 errors, and every suite 0 failed. Without pytest,
`python3 -m unittest discover -s tools/seeds` runs the same cases.

## Notes

- **Bundle size.** A Retail bundle's `raw/` is about 60 KB and a Forever one about 16 KB, because the
  cut keeps only the rows `derive` reads.
- **The localized match is not checked here.** The tool reads the build's enUS names. Whether a
  German or French mass name still leaves its stem when the last word is dropped is smoke LOC-4's job.
- **The name family over-reaches on purpose, and that is a code question.** A substring match on
  "disenchant" also catches the Enchanting crafts "Disenchanting Rod" and "Khadgar's Disenchanting
  Rod". The 2026-11-25 Retail bundle's ANALYSIS lists them for the owner. No seed change can fix
  that.
- **A ruling outlives its candidate.** After `apply`, an accepted id stops being proposed. Its
  ruling stays in the file as provenance, and that is not an error.
- **A shared helper** for the build pin, the cache, the bundle and the rulings is LibKa0s#91's to
  decide. Until then the tool copies Quick Comms' and Drop Watcher's pattern and imports nothing
  across repos.
