# Forever quirks — Ka0s Loot History

The WoW Forever client behaviors this addon works around (documentation-§3, Tier 2). Loot History ships on Retail and WoW Forever, so it carries this file beside `docs/midnight-quirks.md`, which holds the Retail ones (forever-quirks-§1). The first part of this file is the collection's forever-quirks catalog, vendored whole from the Ka0s WoW Addon Standard (forever-quirks-§1) and replaced wholesale by `/dev-copilot:wow-revendor-standards`; never edit inside its markers. A correction belongs in this addon's own section, which follows it.

<!-- BEGIN VENDORED: forever quirks catalog v2.117.0 (source: WowAddonStandards) -->
> Part of the **[Ka0s WoW Addon Standard](https://github.com/tusharsaxena/WowAddonStandards/blob/master/standards/STANDARDS.md)** — the split standard. This section is vendored whole into the `docs/forever-quirks.md` of every addon that ships on WoW Forever (§1), so its links are absolute. Cross-references use the `filename-§N` form (see the index's section map).

## Forever quirks

The WoW Forever catalog: the client behaviors the collection has measured **on WoW Forever** (clients-§1),
each written up so the next addon reads it instead of rediscovering it. It is the Forever counterpart of
client-quirks, which is the **Retail** catalog. The two are kept apart because an addon that ships on one
client needs only that client's catalog, and because a behavior measured on one client is not assumed to
hold on the other.

*Why this section exists.* Through v2.116.0 the collection had one catalog, client-quirks, written on
Retail, and one Forever entry inside it (the two-word names, now §4). Ka0s Skill Master, Forever-only
since v2.105.0 (clients-§9), carried that Retail catalog whole in its `docs/midnight-quirks.md` and had
nowhere upstream to put what it measured on Forever: on 2026-11-10 (build 70862) the client answered a
secret number and refused an aura read, the Retail secret-value rules measured again on the other client.
The owner's ruling of 2026-11-10 split the catalog per client, one file per client an addon ships on
(SkillMaster `docs/superpowers/plans/2026-11-10-feedback-1.md`, *Owner decisions*).

### 1. How an entry is written, promoted and vendored (MUST)

**The entry shape is client-quirks-§1's**, unchanged: the behavior, *Measured*, *Cost*, *Client*, *Do*
and *Source*. Every entry here is *Client:* Forever, stamped with the client version and build it was
measured on (`1.60.1, build 70862`). A Forever entry is not assumed to hold on Retail, and a Retail entry
is not assumed to hold on Forever until §2 says it was measured here.

**Promotion (MUST).** An entry enters this catalog by a harvest, under one of two bars:

- **An engine behavior the Retail catalog already carries** enters on **one** repo's measurement on
  Forever. The two-repo bar was met when the behavior was first promoted; what the Forever measurement adds
  is the fact that the same engine does it here. The entry names the Retail entry it repeats
  (the client-quirks subsection, cited by its number) and adds the Forever build, call and error text, never a second copy of the Retail
  write-up.
- **A behavior new to Forever** needs **two** repos that met it independently, as client-quirks-§1
  requires. A behavior one repo found stays in that repo's own section of `docs/forever-quirks.md` and is
  listed in §5 as one repo, awaiting a second.

The two-word names entry (§4) predates both bars and stands on the owner's ruling of 2026-11-08.

**Expiry.** client-quirks-§1's rule, read per client: when the Forever client version or build moves past
the newest *Measured* stamp in an entry and an addon observes otherwise, the entry is corrected in a
standard release, not worked around in the addon. An entry nobody can reproduce moves to §5 as an open
probe rather than being deleted.

**What an addon does with this section (MUST): carry it as a vendored block in `docs/forever-quirks.md`.**
Every addon whose roster **Clients** value includes Forever (`Retail · Forever` or `Forever`, clients-§2)
carries `docs/forever-quirks.md` (documentation-§3), shaped as client-quirks-§1 describes for
`docs/midnight-quirks.md`: the vendored block, opened by a `BEGIN VENDORED` HTML comment naming the
**Forever** quirks catalog's version and source and closed by an `END VENDORED` HTML comment, each spelled
exactly as `/dev-copilot:wow-revendor-standards` writes it; then the addon's own section. The markers are
described here rather than shown, for client-quirks-§1's reason: this text travels inside them.

```markdown
[the BEGIN VENDORED comment, stamped forever quirks catalog v<X.Y.Z>]
… this section, whole …
[the END VENDORED comment]

## <Addon>-specific quirks

… the addon's own Forever quirks: one no second repo has met, its probe tables, its measured API shapes …
```

- The block is copied whole, replaced wholesale and never edited inside the markers, under client-quirks-§1's
  discipline. A correction belongs in the addon's own section, where the next harvest finds it.
- The own section **MUST NOT** restate a behavior the block carries, and a harvest that promotes an entry
  prunes the addon's copy.
- **One file per client.** A `Retail · Forever` addon carries both files, `docs/midnight-quirks.md` with the
  Retail catalog and `docs/forever-quirks.md` with this one, and files each own finding under the client it
  was measured on. A `Forever` addon carries `docs/forever-quirks.md` only; a `docs/midnight-quirks.md` in a
  Forever-only addon is a retired name (documentation-§3), and its own findings move into
  `docs/forever-quirks.md`. A `Retail` or `Retail (port pending)` addon carries no `docs/forever-quirks.md`.
- An addon with no Forever quirks of its own still carries the block, with an empty own section.

### 2. Which Retail entries hold on Forever

WoW Forever runs on the modern engine: it carries modern client APIs (clients-§3) alongside its
vanilla-era game data, and §3 measured its secret-value system and its taint attribution at work.
That is a reason to expect the Retail catalog's engine behaviors here, and it is **not** a measurement. Each
Retail section's status on Forever, as of build 70862:

| Retail entry | Status on Forever | Evidence |
|---|---|---|
| client-quirks-§2, secret values | **measured**: the secret-value system is live on Forever (§3) | §3, build 70862 |
| client-quirks-§2, a secret cannot be a table key; a secret written to SavedVariables as `nil`; secret geometry | **assumed**: follows from §3, not probed on Forever | none |
| client-quirks-§2, restricted spell cooldowns, `notInterruptible`, `InChatMessagingLockdown` | **assumed**, not probed on Forever | none |
| client-quirks-§3, events (silent valid events, state lagging its event, empowered casts, `ADDON_RESTRICTION_STATE_CHANGED`) | **assumed**, not probed on Forever. The instances that name a Retail-only feature (the warband bank tab, a Mythic+ observation) do not arise there, because the feature is absent (clients) | none |
| client-quirks-§4, Blizzard's aura buttons, escape and protected `Hide()` | **assumed**, not probed on Forever | none |
| client-quirks-§5, item cache, `C_TooltipInfo` templates, secret tooltip text, enum renumbering | **assumed**, not probed on Forever | none |
| client-quirks-§5, `GetNormalizedRealmName` nil early in login | **assumed**; on Forever the realm a character is keyed by is the ruleset, not this name (§4) | §4 |
| client-quirks-§5, a template-less `FontString` raises on `SetText` | **assumed**; the kit's mock enforces it under both profiles, which is not a client measurement | none |
| client-quirks-§6, the open probes | open on Forever as on Retail | none |

An *assumed* row is a working assumption: write the Retail workaround on Forever too, and record what you
see, with the build, in your own section. A measurement promotes the row to *measured* under §1's
one-repo bar.

### 3. Secret values on Forever (measured)

**`UnitStat` can answer a secret number.** *Client:* Forever (1.60.1, build 70862). *Measured:* the owner's
in-game error, 2026-11-10: inside an AceTimer callback, a comparison on the value `UnitStat("player", i)`
answered raised "attempt to compare field 'value' (a secret number value)" (the error as SkillMaster's
`tests/test_statdata.lua` records it). Whether the player was in combat is not recorded. *Cost:* a raise on every rescan of the
path that compares the stat; the stat line stops updating. *Do:* client-quirks-§2's rule: test
`issecretvalue` before any comparison or arithmetic on a stat reader's return, keep the last plain value
(marked stale) rather than the secret, and rescan on `PLAYER_REGEN_ENABLED`. The combat edge is assumed:
if the secret persists out of combat, the stale value stands until a later scan reads it plain. *Retail entry:*
client-quirks-§2, the secret-value family. *Source:* SkillMaster `docs/forever-quirks.md`, its own
section's measured findings; promoted under §1's one-repo bar for an engine behavior.

**`C_UnitAuras.GetBuffDataByIndex` can raise instead of answering a secret.** *Client:* Forever (1.60.1,
build 70862). *Measured:* the owner's in-game error, 2026-11-10: the read raised "Auras cannot be accessed
when secret while tainted by 'SkillMaster'". The call fails outright; it does not hand back a secret table
to test. *Cost:* a raise that takes down the whole scan, not one missing value, so an `issecretvalue` guard
on the return never runs. *Do:* call the aura reader through `pcall` and treat a failure as "auras are
secret now": keep the last plain list and read again after combat (the combat edge is assumed; if the
raise persists out of combat, the last list stands until a later read succeeds). *Retail entry:* client-quirks-§2, the
secret-value family. *Source:* SkillMaster `docs/forever-quirks.md`, its own section's measured findings;
promoted under §1's one-repo bar for an engine behavior.

### 4. Names and realms

**On Forever a character's name is two words, unique per region, and its realm is a long label.** *Client:*
Forever (1.60.1, build 70790). *Measured:* the owner's in-game probe of 2026-11-08 (Ka0sAddonsCommonTasks
`docs/2026-11-07-WOW_FOREVER_PORT_STEP5/W1_FOREVER_NAME_PROBE.md`). Every character has a first name and a
surname, and only the pair is unique; `RegionalUniqueNamesEnabled()` answers true. The name APIs answer:

| Call | Forever answers | Retail answers |
|---|---|---|
| `UnitName(unit)`, `UnitFullName(unit)` | `"Traxex"`, `"Silentshot"`: the **surname** second | the name, then the realm (nil on your own realm) |
| `GetUnitName(unit, true)`, `Ambiguate(…, "short")` | `"Traxex Silentshot"` | `"Name"`, or `"Name-Realm"` across realms |
| a chat event's sender (arg 2) | `"Doom Dock"`, no realm suffix | `"Name-Realm"` |
| `GetRealmName()` / `GetNormalizedRealmName()` | `"CAMWOW AU1 Realm 2 PvP"` / `"CAMWOWAU1Realm2PvP"` | the realm, with and without its spaces |
| AceDB-3.0 40's `db.keys` | `char` `"Traxex Silentshot"`, `realm` `"PvP"`, `factionrealm` `"Alliance - PvP"` | `"Name - Realm"`, the realm |

Players know a realm by its ruleset (Normal, PvP, RP-PvP), not by its label, and there is no cross-realm play to
put a realm on another player. *Cost:* `local name, realm = UnitName(unit)` reads the surname as a realm and
builds `"Traxex-Silentshot"`; a one-value `UnitName(unit)` keeps only the first name, so two characters that
share one ("Traxex Silentshot", "Traxex Ironhide") collide in a key, a filter or a roster; a surface sized for
one Retail word truncates the pair; a `Name-Realm` key built from `GetNormalizedRealmName` is unique but is
not the identity the player or AceDB uses. *Do:* read a character through `LibKa0s-Compat-1.0`'s identity readers (from `LibKa0s v1.94.0`):
`UnitCharacterName(unit)` for any unit, `CharacterKey()` and `RealmKey()` for the player, and `RegionalNames()`
for the question itself. They implement this rule. When `RegionalUniqueNamesEnabled` exists and answers true,
a character's identity is its **whole name**: `GetUnitName(unit, true)` for any unit, or
`UnitNameUnmodified("player")`'s two returns joined by a space for the player, and its realm is the
**ruleset** AceDB 40 derives from `C_GameRules` (`Hardcore`, `RP-PvP`, `RP`, `PvP`, `PvE`). The ruleset is the realm key for stored realm data too, by the owner's
ruling of 2026-11-08, so two PvP realms share one realm key. An addon whose
profile store is AceDB reads those as `db.keys.char` and `db.keys.realm` and never derives them again. That
test is feature detection inside the compat family (clients-§3, compat), never a client check in feature
code. Never read `UnitName`'s second return as a realm, never split a name on whitespace or key on its first
word, and size every surface that shows a name, a realm or a profile key for the long form, or truncate it
with the whole value in a tooltip. *Source:* the owner's ruling and probe of 2026-11-08 during the WoW
Forever port's step 5, recorded ahead of the two-repo bar by that ruling; AceDB-3.0 minor 40's key block.
Carried in client-quirks-§5 from v2.103.0 to v2.116.0, and moved here in v2.117.0.

### 5. Open probes and one-repo findings (not rules)

Each needs an in-game probe, recorded with the build, or a second repo, before it becomes an entry.

- **The missing-API surface.** The Forever client (build 70790) lacks some Retail APIs, `SetDesaturation`
  among them, which LibKa0s tracks in LibKa0s#44. Feature-detect at the call site or in the compat family
  (clients-§3) until the library's list is complete.
- **Secret values in combat on Forever.** §3's two measurements are out of a timer callback and a buff
  scan, with combat state not recorded. Whether meter values, cast spell IDs, castGUIDs and a pet's GUID are
  secret in combat on Forever is not measured; CombatTrail treats each as possibly secret, and an in-combat
  probe would settle it.
- **One repo, awaiting a second.** Each is recorded in that repo's own section of its quirks doc and
  promotes under §1 when a second repo meets it:
  - `C_SkillInfo.GetSkillLineInfo(i)` answers one table with `isCollapsed`, `rank`, `maxRank`, `modifier`,
    `skillID` and `parentSkillLineID`, not the Retail-style `skillRank` / `skillMaxRank`; none of the 1.12
    skill globals exist. *Measured:* build 70862. *Source:* SkillMaster.
  - `C_Item.GetWeaponEnchantInfo(weaponSlot)` takes an `Enum.WeaponSlot` (`MainHand` 0, `OffHand` 1,
    `Ranged` 2), raises on 16 and without one, and answers an array of records. *Measured:* build 70862.
    *Source:* SkillMaster.
  - Each profession and secondary skill is listed twice in the skill list, the vanilla line and a child line
    whose `parentSkillLineID` is the vanilla one, in either order. *Measured:* build 70862. *Source:*
    SkillMaster.
  - Registering `COMBAT_LOG_EVENT_UNFILTERED` raises `ADDON_ACTION_FORBIDDEN`, which `pcall` does not
    catch. *Measured:* build 70862. *Source:* CombatTrail.
  - `C_DamageMeter` ships whole, its two enums match Retail, and the player source's `amountPerSecond` is
    nil out of combat. *Measured:* build 70862, out of combat. *Source:* CombatTrail.
  - `Enum.ItemConsumableSubclass` keeps Retail's numbers and adds Draught 13, Device 14 and
    ItemenhancementTemporary 15, while the stones and oils report subclass 8. *Measured:* the enum is read
    from BlizzardInterfaceResources' `forever` 1.60.1 (70532) dump, not probed in game; the stones' and oils'
    subclass 8 is from the owner's item dump on build 70862. *Source:* ConsumableMaster.
<!-- END VENDORED -->

## LootHistory-specific quirks

### WoW Forever

Client: **Forever**, 1.60.1. Unless a row says otherwise, each behavior was read from the 1.60.1
interface files (build 71037, Gethe/wow-ui-source `forever` 734f065) and from other addons' Forever
code, during the WoW Forever port's research (Ka0sAddonsCommonTasks
`docs/2026-11-22-LOOTHISTORY_BANKLEDGER_FOREVER_PORT/inputs/research/`). None has been measured in
game yet. `/lh debug probe` records the facts that would settle each one, and
[forever-probes.md](forever-probes.md) names the probe (P1 to P12) and the safe default the addon
ships until it reports. None is assumed to hold on Retail, and none has met a second repo yet, so
each stays here (forever-quirks-§1); Ka0s Bank Ledger's port meets the bank rows independently,
which is the second repo a harvest needs. Each client read lives in `core/CompatClient.lua` or a
table picked once by `NS.Compat.ClientKey()` (clients-§3, §5), and
[ARCHITECTURE.md](ARCHITECTURE.md#per-client-features-clients-4) lists where each is gated.

| Quirk | What the client does | What the addon does |
|---|---|---|
| The bank is bags, and has no warband half | The character bank is `Enum.BagIndex.CharacterBankTab_1` to `_9` (6..14, where Retail has 6..11): tab 1 is the base bank and tabs 2..9 are bags socketed into it. `AccountBankTab_1..9` (15..23) exist in the enum, but there is no warband bank to open, and `C_Bank.CanViewBank(Enum.BankType.Account)` answers false. | The bank group is matched by member name, never by Retail's numbers (LibKa0s-Compat's `ContainerGroups()`, whose Forever row declares no account bank). The warband bank is Retail-only by declaration (ruling R1): no tabs or warband-gold part, no warband events or reasons, no Holdings Warband split. Probe P1, P12. |
| The bank loads late | Other addons report that a Forever bank is not always loaded when it first opens: a bank container can answer 0 slots at the open and its real count a moment later. A read at the open would record every item in that container as lost, and the next read as found again. | The bank readiness guard (ruling R8, both clients): a bank container that had slots on the last ready read and now answers 0 keeps the part dirty for up to `R.READY_WAIT` (5 s), `BAG_CONTAINER_UPDATE` and `BANK_TABS_CHANGED` cue the re-read, and the counts are kept in `meta.bankSlots`. Probe P1 times it at the open, +1 s and +3 s. |
| Which banker interaction | The bank frame opens for `Banker` (8), `CharacterBanker` (67) and `AccountBanker` (68); which one a Forever banker NPC sends is not known. | The bank part arms on `Banker` and `CharacterBanker` on both clients, and on `AccountBanker` on Retail only (`R.BANKER_ARMS` by `Compat.BankerKind`, ruling R8). A character bank that cannot be viewed (`C_Bank.CanViewBank(Enum.BankType.Character)` false) is never read. Probe P1. |
| The keyring | `Enum.BagIndex.Keyring` (-1) is a live container on Forever. Retail's enum carries the member too, where -1 was the bank before 11.2. | The Keyring is in the bags group on WoW Forever only (`C.BAG_IDS` -1..5), so a key moved between the keyring and the bags is internal; Retail's groups do not name it (ruling R5). Probe P3, on both clients. |
| A bag socketed into the bank | Bank tabs 2..9 are bags placed into sockets, which read as container -2. | Ignored for now (ruling R6): a bag moved into a socket reads as a bag leaving the bags. Probe P2 and P10 record what -2 reads, for a later decision. |
| The roll-won line | `LOOT_ROLL_YOU_WON` is `"\|HlootHistory:%d\|h[Loot]\|h: You won: %s"`: a loot-history id comes first, where Retail's is `"You won: %s"`. A parser that takes the first capture reads the id, and `LOOT_ROLL_YOU_WON:format(link)` raises. | `Util.ParseRollWon` takes the global's `%s` capture, found once from the global; the simulator's `D.RollWonText` and the suites' `T.rollWonLine` fill each `%d` and `%s` in the global's order. Probe P8. |
| No bare money-text global | Only `C_CurrencyInfo.GetCoinTextureString` is documented; there is no bare `GetCoinTextureString` global. | `Util.FormatMoney` tries `C_CurrencyInfo.GetCoinTextureString`, then `GetMoneyString`, then `Ng Ns Nc` text, on both clients (ruling R8), and never reads the bare global. Probe P9. |
| Two-word names on the addon's surfaces | forever-quirks-§4: a character is `"First Surname"` with no realm. | The holder key is the whole name (`Util.PlayerKey` through `Compat.CharacterKey`, the lead's call D6); a typed or traded name is kept whole and gets no realm. The realm cut in the short labels finds no hyphen, so the name stays whole; the Insights bars cut a label at 16 glyphs with the whole name in the hover, and the Timeline legend's tooltip carries the whole name. Whether a surname can hold a hyphen is an open probe. |
| No Mythic+, bonus rolls, Milling or Prospecting | Forever has no keystones, no bonus-roll coins and neither profession. | The `MPLUS`, `BONUS_ROLL`, `MILLING` and `PROSPECTING` sources are Retail-only by declaration (ruling R2); Disenchant stays, seeded by spell 13262 alone. A disenchanted item's loss keeps the `DECONSTRUCT` reason on Forever, worded "Disenchanted" there (`C.SOURCE_LABEL_WORDS`, owner ruling F1), so it never shares the materials' "Disenchant" label; Retail's reads "Deconstructed". Whether `GetSpellName(13262)` resolves is an open probe. |
