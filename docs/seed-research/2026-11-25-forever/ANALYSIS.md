# Analysis: WoW Forever seed validation, 2026-11-25 (build 1.60.1.71091)

The first run of `tools/seeds/seeds.py` on WoW Forever, under `docs/validate-seeds.md` (LibKa0s#102,
Ka0sAddonsCommonTasks `docs/2026-11-25-SEEDS_AND_FOREVERDB/`, item SF-LH-01). It checks
`modules/Attribution.lua`'s `DECONSTRUCT_IDS.forever` and `NAME_SEEDS_BY_CLIENT.forever`, and the
simulator's `D.SPELLS.forever`, against WoW Forever's own DB2 on wago.tools: product `wowf`,
1.60.1.71091, the newest non-bgdl build the builds API listed (created 2026-11-24 15:21:07), resolved
once for the run and pinned with `--build`. It never reads Retail's tables.

## What the build says

| Check | Result |
| --- | --- |
| Shipped ids checked | 3: Disenchant 13262 in the list, as the one name seed, and as the simulator's one cast |
| 13262 in `SpellName` | yes, **Disenchant** |
| 13262 taught on Enchanting (333) | yes |
| Other Enchanting-line spells in the Disenchant family | none |
| Profession lines on the build | Enchanting yes, Inscription no, Jewelcrafting no |

No candidate and no flag, so `forever_rulings.json` is empty and `apply` wrote nothing.

## Milling and Prospecting

They stay **EMPTY BY DECISION** (the Forever port's D15, ruling R2), and the tool never proposes them.
The build agrees with the decision: it has neither the Inscription nor the Jewelcrafting skill line,
so no Milling or Prospecting spell is taught to a player. Retail's ids are not filtered into this
list either. On this build none of Retail's other 19 ids names a spell, and an id that named some
other spell here would mis-attribute.

## ForeverDB

Not consulted. Spells and skill lines are client data, which DB2 holds (clients-§10). ForeverDB's
evidence is for server-side facts such as creatures, vendors and trainers, and none of this addon's
seed lists holds one.

## Judgment calls applied

None. Nothing changed.

## What a later run should re-check

- **A second Disenchant id.** If a Forever build gains another Enchanting spell in the family, it
  shows as a candidate. `DECONSTRUCT_IDS.forever` is one line and a hand edit, so accepting it
  means writing it by hand (`apply` refuses any Forever write).
- **Inscription or Jewelcrafting appearing.** RULINGS.md's *Build facts* line would show it. Seeding
  Milling or Prospecting would still need the owner to reverse ruling R2 first, with
  `C.SOURCE_ABSENT` changed to match.
