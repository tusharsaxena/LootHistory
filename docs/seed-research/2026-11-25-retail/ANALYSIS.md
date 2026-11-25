# Analysis: Retail seed validation, 2026-11-25 (build 12.1.5.70961)

The first run of `tools/seeds/seeds.py` on Retail, under `docs/validate-seeds.md` (LibKa0s#102,
Ka0sAddonsCommonTasks `docs/2026-11-25-SEEDS_AND_FOREVERDB/`, item SF-LH-01). It checks every id in
`modules/Attribution.lua`'s `DECONSTRUCT_IDS.retail` and `NAME_SEEDS_BY_CLIENT.retail`, and the
simulator's `D.SPELLS.retail`, against the live Retail build on wago.tools: product `wow`,
12.1.5.70961, the newest non-bgdl build the builds API listed (created 2026-11-17 20:16:02), resolved
once for the run and pinned with `--build`. The lists had never been checked against DB2: they were
written by hand. Every candidate and flag is ruled in `tools/seeds/retail_rulings.json`, and
`RULINGS.md` beside this file lists each one with its reason.

## What the build says about the shipped ids

28 ids checked: 20 in `DECONSTRUCT_IDS.retail`, 5 name seeds and 3 simulator casts.

| Check | Result |
| --- | --- |
| Ids the build has no `SpellName` row for | 2: 382971 and 382972 (filed under Prospecting) |
| Ids whose name is outside their source's family | 2: 434913 is **Cheat to Hunger Phase** and 434926 is **Lingering Influence**, both filed under Milling |
| Ids taught by another profession's line | 0 |
| Ids no `SkillLineAbility` row teaches | 6: the two above, plus 51005 Milling, 31252 Prospecting, 302710 Prospecting and 289991 Disenchanting |
| Name seeds whose name does not make the stem their role needs | 1: the `dropLast` Mass Mill seed 434926, whose stem was "Lingering" |
| Simulator casts not in the list under their source | 0 |

**The defect that mattered: the Mass Mill name seed.** `seedToken` drops the seed name's last word
and matches the rest as a substring of the cast's name. With 434926 named Lingering Influence, the
Milling stem was "lingering". No Mass Mill cast contains that word, and nothing else carried a Mass
Mill cast: the plain seed's "milling" is not in "Mass Mill <Herb>", and no Mass Mill id was listed. So
on this build every mass mill stamped no Milling source. A cast whose name contains "lingering" would
also have stamped Milling. The seed is now 311413, **Mass Mill Deathblossom**, a one-word herb, so the
stem is "Mass Mill" in enUS. The same reasoning holds in any locale whose herb name is one word.

## What the run proposed

67 candidates and 11 flags, all ruled.

| Proposed | Ruled | Why |
| --- | --- | --- |
| 10 per-expansion Milling spells: 382982 Shadowlands, 382984 Kul Tiras and Zandalar, 382986 Legion, 382987 Draenor, 382988 Pandaria, 382989 Cataclysm, 382990 Northrend, 382991 Outland, 382994 Classic, 444181 Khaz Algar | accepted | The header enumerates "generic + per-expansion" Milling ids, and the list held only Dragon Isles (382981) and Midnight (1269575) |
| 3 per-expansion Prospecting spells: 325248 Shadowlands, 382978 Cataclysm, 382995 Classic | accepted | The same rule for "base + per-expansion" Prospecting ids |
| 311413 Mass Mill Deathblossom | accepted | The new representative Mass Mill, paired with the name seed's hand edit |
| 41 other Mass Mill and Mass Prospect spells (190381 to 359492) | rejected | The header lists one representative per mass family, and the localized stem covers the rest |
| 12 other Enchanting spells named exactly Disenchant (300381 to 1280952) | rejected | The 13262 name seed's name is the same string in every locale, so the family matches them already. Which id a cast fires cannot be read from DB2 |
| flag `gone`: 382971, 382972 | removed | No spell of either id exists, so neither can match a cast |
| flag `family`: 434913, 434926 (and their `unlined` flags) | removed | Neither is a Milling spell. Khaz Algar Milling, which 434913 probably meant, is 444181 (accepted) |
| flag `unlined`: 51005, 31252 | kept | The plain family words and the Milling and Prospecting name seeds. No line teaches them since the per-expansion split, but their names are what the family resolves |
| flag `unlined`: 289991 Disenchanting, 302710 Prospecting | kept | Family names. The data cannot say whether a client still fires them, so they stay |
| flag `token`: name seed 434926 | fixed by hand | The seed became 311413, as above |

`apply` then wrote `DECONSTRUCT_IDS.retail`: 4 ids out, 14 in, 30 ids now. A replay of this bundle
against the applied file (run in a scratch copy) reports 53 candidates and 4 flags, every one ruled.
Those are the 53 rejections and the four kept `unlined` ids.

## Judgment calls applied

The owner's fix policy (spec §8.2) applies every mismatch the evidence supports. These are the calls
the data did not make on its own, so the owner can reverse any of them at smoke:

1. **311413 Mass Mill Deathblossom as the representative.** Any one-word Mass Mill herb gives the same
   enUS stem. Deathblossom is the newest one-word herb this build teaches. A multi-word one (359490
   Mass Mill First Flower) would leave "Mass Mill First". The old seed's own herb is unknown: 434926
   names no mass spell on this build. Smoke CAP-35, and LOC-4 for a non-English client.
2. **Accepting the per-expansion spells, which the name family covers anyway.** The family already
   matches every "<X> Milling" and "<X> Prospecting" in enUS. The header enumerates them by id
   regardless, because an id match needs no cached name and no locale. Accepting them follows that
   rule. Smoke CAP-36 and CAP-37.
3. **Removing 434913 and 434926 rather than keeping them as harmless.** They name other spells, so
   an id match on them would stamp Milling on a cast that is no milling. Smoke CAP-38.
4. **Keeping 289991 and 302710.** No skill line teaches either. Both names are in the family, and
   removing them would gain nothing if a client still fires them.

## Needs owner review

- **The name family's substring match over-reaches.** "disenchant" is a substring of the
  Enchanting crafts **Disenchanting Rod** (278418) and **Khadgar's Disenchanting Rod** (390855), so a
  cast of either stamps DISENCHANT. The craft's own "You create" line still resolves as Craft (CAP-10),
  so the likely cost is a stray stamp that the next loot window consumes. This is a matching-rule
  question in `Attribution:DeconstructSource`, not seed data, and this run changed nothing for it.
- **The LOC-4 history.** LOC-4 (a mass mill on a non-English client) is recorded as passed on
  2026-10-10. On this build the Mass Mill seed could not have matched in any locale, so either 434926
  named a Mass Mill on the build the owner ran then, or the mass-mill step was not exercised. CAP-35
  re-checks it.

## What a later run should re-check

- **New expansion spells.** The next expansion's "<X> Milling" and "<X> Prospecting" arrive as
  `expansion` candidates and are accepted by the same rule. Its mass spells are rejected unless the
  representative breaks.
- **The representative's stem.** A `token` flag on 311413 or 225904 means the build renamed the herb
  or ore to more than one word. Pick another one-word representative from the candidates.
- **The four kept `unlined` ids.** If a build drops their `SpellName` rows, they turn into `gone`
  flags and are removed. 51005 and 31252 would then need new plain name seeds.
