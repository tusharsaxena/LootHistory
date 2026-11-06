# Midnight quirks — GUID decode, tooltip scans, and other 12.0 traps

Catalog of WoW Midnight (Interface 120105, 12.1.5) behaviors that Ka0s Loot History handles. **Read this before touching capture, attribution, or item-info code.** Every quirk in the LootHistory-specific section below is dealt with in `core/Compat.lua` (the compat firewall — see [compat-layer.md](compat-layer.md)); attribution wiring that consumes them lives in `modules/Attribution.lua` (see [data-flow.md](data-flow.md)).

> **Not a secret-value *reader* — but its output seam is still secret-safe.** Unlike KickCD, LH does **not** read cooldown/cast timings or any of 12.0's "secret value" protected returns; it reads loot, item, mail, and quest data, none of which are secret-tainted. So no capture/attribution path ever holds a secret. **However**, the shared chat printer (`NS.Print`) and debug sink (`NS.Debug`) are still built secret-safe — every argument routes through `NS.SafeToString` (`core/Util.lua`) before it reaches `table.concat`/`string.format`, so a value that *is* secret logs as `<secret>` instead of crashing. This is the Ka0s standard's single-seam mandate (events-frames-taint-§8): the guard lives once in the shared helpers and every call site inherits it, regardless of whether this addon happens to feed it a secret today. There is no per-call-site `issecretvalue` handling, and there should be none.

<!-- BEGIN VENDORED: quirks catalog v2.102.2 (source: WowAddonStandards) -->
> Part of the **[Ka0s WoW Addon Standard](https://github.com/tusharsaxena/WowAddonStandards/blob/master/standards/STANDARDS.md)** — the split standard. This section is vendored whole into every addon's `docs/midnight-quirks.md` (§1), so its links are absolute. Cross-references use the `filename-§N` form (see the index's section map).

## Client quirks

The client behaviors the collection paid for more than once. Each entry here was discovered
**independently in two or more Ka0s repositories**, written up in each, and promoted by a harvest so the
next addon reads it instead of rediscovering it. A behavior one repo found stays in that repo's
`docs/midnight-quirks.md` until a second repo meets it.

*Why this section exists.* By 2026-11-06 eleven addons kept a private `docs/midnight-quirks.md`, 2,073
lines and about 133 entries between them, and about 81 of those entries were 21 behaviors written up
independently two to eight times. Nine of the eleven opened with their own restatement of the 12.0 secret
rules. Three write-ups contradicted this standard, and one contradiction was this standard's own error
(events-frames-taint-§2, *The combat-start edge*). A catalog was proposed and deferred twice, on
2026-08-25 and 2026-09-22, because an inventory rots; the build stamp per entry (§1) is the answer to that
objection (WowAddonStandards `harvests/2026-11-06/02_FINDINGS.md`, F3-01; every write-up quoted in
`harvests/2026-11-06/03_EVIDENCE.md`, Part A).

### 1. How an entry is written, and how it expires (MUST)

Every entry **MUST** carry:

- **The behavior**, stated as what the client does, not as advice.
- **Measured:** the client build or date it was observed on, where any write-up recorded one. An entry with
  no measurement says *not measured*; that is a weaker entry, not a missing field.
- **Cost:** what happened to an addon that did not know it.
- **Do:** the workaround, as a rule an addon can follow.
- **Source:** the deepest write-up — the repo and document that probed furthest — and the harvest that
  promoted it. Every version is quoted in that harvest's `03_EVIDENCE.md`.

**Expiry.** An entry describes a client, and clients move. When the retail interface number moves past the
newest *Measured* stamp in an entry and an addon observes otherwise, the entry is corrected in a standard
release — not worked around in the addon. An entry nobody can reproduce moves to §6 as an open probe rather
than being deleted, because the behavior may only have moved.

**What an addon does with this section (MUST): carry it as a vendored block.** This section is the one
part of the standard an addon carries a **copy** of, because it is reference data about the game client
that a working addon needs offline, next to the code that works around it — not a rule, which is only ever
pointed at. Every addon's `docs/midnight-quirks.md` (documentation-§3) is two parts: the vendored block,
opened by a `BEGIN VENDORED` HTML comment naming the catalog's version and source and closed by an
`END VENDORED` HTML comment, each spelled exactly as `/dev-copilot:wow-revendor-standards` writes it; then
the addon's own section. The markers are described here rather than shown, because this text travels
inside them: a literal marker in the vendored copy would give the file a second end marker for the next
re-vendor to cut at.

```markdown
[the BEGIN VENDORED comment, stamped quirks catalog v<X.Y.Z>]
… this section, whole …
[the END VENDORED comment]

## <Addon>-specific quirks

… the addon's own quirks: one no second repo has met, its per-event costs, its own probe tables …
```

- The block is **copied whole and replaced wholesale** by `/dev-copilot:wow-revendor-standards`, stamped with
  the standard version it came from, under the same discipline as `libs/LibKa0s/` (anti-pattern #45): never
  a subset, **never edited inside the markers**. A local edit inside them is reverted by the next revendor,
  and the behavior it fixed comes back with no cause in the addon's history; a correction belongs in the
  addon's own section, where the next harvest finds it.
- The addon's own section **MUST NOT** restate a behavior the block carries. When a harvest promotes an
  entry, the revendor prunes the addon's copy: the upstream entry is the deeper write-up, and two live
  copies of one finding is the shape that drifted three times into contradiction.
- An addon with no quirks of its own still carries the block, with an empty own section.

**Contested behaviors are not rules.** Where two repos recorded opposite behavior and nobody has probed
the difference, the entry goes in §6 with both sides and the probe that would settle it.

Behaviors this standard already states elsewhere are not repeated here: the unknown-event raise
(events-frames-taint-§1), `Settings.OpenToCategory`'s numeric ID and collapsed parent (options-ui-§2),
the protected category switch in combat (options-ui-§2, anti-pattern #88), a secret through `tostring` and
`..` (events-frames-taint-§8), lockdown at `PLAYER_REGEN_DISABLED` (events-frames-taint-§2), the spec
readers' move to `C_SpecializationInfo` (compat, `LibKa0s-Compat-1.0`) and `SendChatMessage`'s move to
`C_ChatInfo` (compat).

### 2. Secret values

**A secret boolean cannot be tested at all.** `if`, `not`, `==` and `and`/`or` on a secret boolean raise
("attempt to compare … (a secret boolean value)"); the value is unusable in Lua, not merely unprintable.
`DurationObject`'s `HasExpired`, `HasStarted`, `IsActive` and `IsZero` come back secret in combat, and an
engine button's `IsShown` has answered a secret boolean out of combat. *Measured:* 12.0.7 (probe table);
12.1 (`IsShown`). *Cost:* a raise on every refresh tick of the path that tests it. *Do:* check
`issecretvalue` before any test; route a secret boolean to a C-side consumer
(`C_CurveUtil.EvaluateColorValueFromBoolean`, `SetAlphaFromBoolean`), or treat it as the cautious answer
(a secret lockdown reads as locked, a secret restriction as active, a secret claim as no claim). Two repos
disagree on whether to gate before the C-side call; that disagreement is recorded in `LibKa0s`
`docs/api/Compat` and is not ruled here. *Source:* KickCD `docs/midnight-quirks.md`, "Secret booleans are
unusable"; seven repos (harvest 2026-11-06, Q6).

**A secret cannot be a table key.** Indexing or assigning with a secret key raises "attempted to perform
indexed assignment on a table that cannot be indexed with secret keys". `UnitGUID` on a follower-dungeon
pet (`party3pet`) answers a secret string. *Cost:* a raise on every refresh tick for a roster keyed by
GUID. *Do:* guard a key with `IsSafeKey` (`LibKa0s-Compat-1.0`) or `issecretvalue` before keying; a
secret GUID is never a handle. *Source:* MultiMeters `docs/midnight-quirks.md`, the follower-dungeon pet
GUID; seven repos (Q7).

**A secret never reaches SavedVariables, and one that does is written as `nil`.** A value captured as
secret stays secret after combat ends, and the client writes a secret to SavedVariables as `nil` — or,
where it was a key, loses the entry. *Measured:* a reload probe, 2026-10-25. *Cost:* silent data loss on
the next reload. *Do:* store a plain value or nothing; never store a captured secret to read later.
*Source:* DpsRace `docs/known-limitations.md`, the reload probe; three repos (Q21).

**A frame handed a secret has secret geometry, and so does everything anchored to it.** After
`StatusBar:SetValue(secret)` (or `SetAlphaFromBoolean`, or anchoring to an aura engine container) the
frame `HasSecretValues`: its width, points and frame level read secret, out of combat too, and the
taint runs down the anchor chain to every frame anchored to it; a tooltip showing hidden information has
secret geometry. A secret size's `type` is `"number"`, so a type check lets it through, and
`BackdropTemplate`'s own arithmetic on a secret size raises. *Cost:* a raise inside Blizzard code, or a
layout computed from a secret. *Do:* compute layout from configuration and never read geometry back from a
frame that was handed a value; keep a record of the alpha you set rather than calling `GetAlpha()`; read a
frame level under a restricted anchor through a secret-safe guard (frame-layering). *Source:* AuraMaster
`docs/midnight-quirks.md`, the aura engine container entries (measured and dated); six repos and
`LibKa0s` `docs/api/Widgets` (Q8).

**A restricted spell's cooldown: branch on `isActive`, paint with the duration object.** In a restricted
state `C_Spell.GetSpellCooldown`'s timings are secret while `isEnabled` and `isActive` stay plain
(documented NeverSecret). `GetSpellCooldownDuration` answers a **zeroed** object, not `nil`, when there is
no cooldown, and a fresh object per call. *Cost:* raw `SetCooldown` with a secret start or duration raises;
a nil check passes the zeroed object. *Do:* decide from `isActive`; paint with
`Cooldown:SetCooldownFromDurationObject`, which accepts the object from tainted code. *Source:* KickCD
`docs/midnight-quirks.md`, the cooldown probe table; four repos (Q9).

**`notInterruptible` is secret, and the interruptibility events make it plain.** The cast info's
`notInterruptible` is secret; `UNIT_SPELLCAST_INTERRUPTIBLE` / `_NOT_INTERRUPTIBLE` deliver it plain.
`CastingBarFrameTemplate`'s built-in `OnUpdate` compares `GetTime()` with a secret `maxValue` and raises
when the bar shows another unit. *Do:* split the gate — the color path takes the secret C-side, the logic
path takes the event's plain value; do not inherit `CastingBarFrameTemplate` for a unit other than the
player. *Source:* KickCD `docs/midnight-quirks.md`, "split the gate in two"; two repos (Q13).

**`InChatMessagingLockdown` can answer a secret.** *Do:* read it through a guard and treat a secret as
locked. *Source:* DropWatcher and QuickComms `core/Compat.lua` (byte-identical), DpsRace; three repos (Q27).

### 3. Events

**A valid event can register without complaint and never fire.** `GUILDBANKFRAME_OPENED` registers and
never fires (*Measured:* 12.0.7); `UNIT_SPELLCAST_SUCCEEDED` is suppressed for protected interrupts;
`UNIT_HEALTH` and `UNIT_NAME_UPDATE` never fire for compound tokens such as `party1target`;
`GET_ITEM_INFO_RECEIVED` does not fire for an item already cached. This is the inverse of the
unknown-event raise (events-frames-taint-§1) and it is silent: nothing errors. *Cost:* a feature that
never runs, with nothing in the log. *Do:* confirm a new event fires in game before building on it, and
prefer an edge with a second source (a frame's `OnShow`, a gated timer) where the event is known to be
silent. *Source:* BankLedger `docs/midnight-quirks.md`, `GUILDBANKFRAME_OPENED`; four repos (Q20).

**Client state can lag its own event, or change with no event at all.** `IsMounted()` has flipped by the
time `PLAYER_MOUNT_DISPLAY_CHANGED` arrives while `C_PlayerInfo.GetGlidingInfo`'s `canGlide` sometimes has
not; after `INSPECT_READY` some slots still answer an item id with no link; switching bank tabs fires no
event, and the live warband tab has taken over a second to catch up; chat lockdown clears with no event.
*Cost:* a read at the edge answers the old state, and the display stays wrong until the next unrelated
event. *Do:* answer at the edge **and once more after a short settle** (a fraction of a second, a bounded
retry), never a poll. *Source:* MultiMeters `docs/midnight-quirks.md`, "some client state lags its own
event"; six repos (Q19).

**An empowered cast fires `UNIT_SPELLCAST_EMPOWER_*`, not the channel events.** `UnitChannelInfo`
reports it, but `UNIT_SPELLCAST_CHANNEL_START` / `_STOP` do not fire for it, and its release fires
`UNIT_SPELLCAST_SUCCEEDED` with the same cast GUID. *Do:* register the `EMPOWER_*` events wherever channels
are tracked. *Source:* KickCD `docs/midnight-quirks.md`, empowered casts; three repos (Q12).

**`ADDON_RESTRICTION_STATE_CHANGED` fires *before* enforcement.** The `Activating` state arrives before the
restriction begins, and access is still permitted during that dispatch; a dungeon restriction type has
gone active on entry and not cleared. Read the restriction type by its `Enum.AddOnRestrictionType` member
name — a member can be missing on some builds. *Measured:* 12.1.0, 2026-09-18. *Do:* treat `Activating`
as the last moment to read, not as the start of the restriction. The payload's second argument is
contested (§6). *Source:* AuraMaster `docs/midnight-quirks.md`, the restriction types; six repos (Q10).

### 4. Combat and secure frames

**Blizzard's aura buttons are forbidden to addon code, and `IsForbidden()` can say otherwise.** In
combat every call on a Blizzard aura button's objects raises "Attempt to access forbidden object from code
tainted by an AddOn"; in an instance (seen in Mythic+) the same buttons answer `IsForbidden()` `false` and
still refuse every read, `GetChildren` included. *Do:* never read Blizzard aura buttons; where a frame
must be inspected, `pcall` the read and treat a failure as forbidden. *Source:* PartyFrameEnhanced
`docs/midnight-quirks.md`, forbidden aura buttons; three repos (Q14).

**Escape runs a protected `Hide()` in combat.** A secure or protected frame listed in `UISpecialFrames` is
hidden by `CloseSpecialWindows`, which is a protected action in combat. *Do:* list a non-secure proxy in
`UISpecialFrames` and hide the protected frame from it out of combat, or keep protected frames out of the
list. *Source:* WhatGroup `docs/midnight-quirks.md`, the escape proxy; two repos (Q24).

### 5. Item, tooltip, enum and realm data

**Item data is nil until cached, and the load event has holes.** `GetItemInfo` answers nothing for an
uncached item; `GET_ITEM_INFO_RECEIVED` does not fire on an addon's first scan for an item the client
already holds; an uncached item's tooltip is not empty but a legible `RETRIEVING_ITEM_INFO` line; a failed
load drops its wait and nothing asks again. *Cost:* a blank or wrong row that never repairs. *Do:* load
through `LibKa0s-Item-1.0`'s cache-then-callback path (library-stack-§7), treat `RETRIEVING_ITEM_INFO` as
not-yet-loaded, and re-ask after a failed load. *Source:* ConsumableMaster `docs/midnight-quirks.md`, the
first-scan hole; seven repos (Q15).

**`C_TooltipInfo` returns raw templates.** Tooltip lines can carry the unexpanded plural grammar
`|4singular:plural;` (*Measured:* 12.1.5, "for the next 3 |4hour:hrs; 49 min") and a no-break space that
Lua's `%s` does not match. *Cost:* a parser that knew only the expanded words read no duration and called a
tradeable drop expired. *Do:* expand `|4…;` before matching, and match the no-break space explicitly.
*Source:* DropWatcher `docs/midnight-quirks.md`, the trade window; two repos (Q16).

**Tooltip line text can be secret** under an addon restriction, including through `TooltipDataProcessor`.
*Do:* guard each line before matching. *Source:* DropWatcher `docs/midnight-quirks.md`; two repos (Q17).

**Blizzard renumbers enums; resolve a member by name, never by number.** One build's
`Enum.TooltipDataLineType` and bank-tab values are not the next build's, and a member can be absent on a
build. *Cost:* a numeric guess for a member the build does not expose landed on an unrelated bank
container. *Do:* read `Enum.X.Member`, and handle its absence; localization-§4 already forbids the string
spelling. *Source:* DropWatcher `docs/midnight-quirks.md`, the research's enum values; five repos (Q18).

**`GetNormalizedRealmName` is nil early in login.** *Cost:* a stored `Name-` key with no realm. *Do:* never
build a `Name-Realm` key before the realm is known; defer, or fall back to `GetRealmName` with its spaces
and hyphens removed. *Source:* DropWatcher `docs/midnight-quirks.md`, realm names; four repos (Q25).

**A template-less `FontString` with no font raises on `SetText`.** "Font not set" from a `FontString`
created without a template or `SetFontObject` takes the addon down at load; a mock that does not enforce it
passes every test. *Do:* give every bare `FontString` a font object before its first `SetText`; the kit's
mock enforces it. *Source:* MultiMeters `tests/mock_frame.lua`, the font-not-set guard; three repos and
`LibKa0s` (Q22).

### 6. Open probes — contested behaviors (not rules)

Each needs an in-game probe, recorded with the build, before any section of this standard changes.

- **`string.format` on a secret.** events-frames-taint-§8 says it raises, with three repos; two say it
  works, one with a mid-combat observation. The likely difference is the specifier (`%s` against `%d` and
  `%.1f`) or that the result is itself a secret string. Probe each specifier, in combat, on a damage-meter
  value and a `UnitHealth` value. Until then §8's rule stands.
- **`ADDON_RESTRICTION_STATE_CHANGED`'s second argument.** One repo documents an
  `Enum.AddOnRestrictionState` value; three (one measured) record a boolean as well. Handle both shapes.
  The 2026-09-22 harvest called this settled, and it is not.
- **`SetAllPoints(parent)` on a secure button at load.** One repo records "Cannot anchor protected frames
  to regions" and uses the implicit-parent form; another anchors its secure rows with `SetAllPoints(row)`
  at birth and treats it as working, with its in-game smoke check still owed.
<!-- END VENDORED -->

## LootHistory-specific quirks

## Retail-only: presence guards, not flavor branching

LH ships Retail-only, so `core/Compat.lua` carries **no** `WOW_PROJECT_ID` branching. Every deprecated or flavor-varying API is gated by a direct `C_*` / global **presence check**; a missing API degrades the shim to `nil`/`false` rather than erroring (`core/Compat.lua:5-7`). Examples: `C_ChallengeMode.GetActiveKeystoneInfo` (`:30`), `IsInInstance` (`:39`), `C_Container.UseContainerItem` with a bare-global fallback (`:118`), `C_Container.GetContainerItemInfo` (`:127`), `C_TooltipInfo.GetHyperlink` (`:309`). This is the standard's compat-firewall rule: modules call `NS.Compat.X` and never test the game flavor inline.

## GUID decode — npcID in field 6, KILL vs CONTAINER

A dash-split WoW GUID (`Creature-0-…-<npcID>-…`) carries the creature/npc id in **field 6**, but only for *unit* kinds. `Compat.UNIT_KINDS` is the single source of truth for which kinds those are — `Creature`, `Vehicle`, `Pet`, `Vignette` (`core/Compat.lua:206`). `Compat.DecodeGUID` splits the GUID, returns the leading `kind`, and pulls field 6 as `npcID` **only** when the kind is in that set; non-unit kinds return `nil` for the id (`:210-218`).

The attribution engine keys loot-source resolution off that kind so KILL detection can't drift from the decoder (`modules/Attribution.lua:166-189`):

- **unit kind** (`UNIT_KINDS`) → `KILL`, detail `{ npcID }` (plus encounter id/difficulty while an encounter is live, and for `Constants.ENCOUNTER_GRACE` seconds after a successful `ENCOUNTER_END`, because the boss corpse is looted after that event fires; a wipe clears the encounter context at once).
- **`GameObject`** → `MPLUS` when a keystone context is active, else `CONTAINER`.
- **`Item`** → `CONTAINER` (a lootable Item-GUID, e.g. a disenchant/mill mat window).
- anything else → `OTHER`.

The keystone context that flips `GameObject` from CONTAINER to MPLUS comes from `Compat.GetActiveKeystoneLevel` (`core/Compat.lua:29`), stamped on `CHALLENGE_MODE_START` and kept alive through `CHALLENGE_MODE_COMPLETED` so the reward chest still reads MPLUS; a completion-time level of 0 never overwrites the started one (`modules/Attribution.lua:248-265`). It is **cleared** when the player leaves the party instance (`ZONE_CHANGED_NEW_AREA` with `Compat.InPartyInstance`, `core/Compat.lua:38`, false) or on `CHALLENGE_MODE_RESET`, so a herb, ore node or world chest looted afterwards reads CONTAINER again. A player who zones back into a running key gets no second `CHALLENGE_MODE_START`, so the same zone-change handler **re-arms** the context from the active keystone level (`modules/Attribution.lua:272-290`). Rows recorded as MPLUS before this lifetime existed cannot be repaired: nothing stored distinguishes them.

## Warbound bind state — two unreliable signals, merged

Bind state above BOE/BOP — warbound, in its two flavors — has **two** sources, and *neither one is sufficient by itself*. Reading only one is the bug this section exists to prevent; it has been shipped twice.

**Signal A: the structured bind type.** `C_Item.GetItemInfo`'s 14th return is `Enum.ItemBind`, and 11.0 added the account values: `7` ToWoWAccount and `8` ToBnetAccount → `"WARBAND"`, `9` ToBnetAccountUntilEquipped → `"WARBAND_UE"` (`Compat.BindState`). Locale-free and needs no tooltip — but **Blizzard does not keep it honest**: item `278014`, a cache whose tooltip plainly reads "Binds to Warband until equipped", reports **`2` (OnEquip)** here. Verified in-game, not inferred. So a warbound answer from the bind type is trustworthy; its *silence* proves nothing.

**Signal B: the tooltip text.** `GetItemInfo` also answers nothing at all for an item the client hasn't cached (bindType included), which for a just-looted item is the common case — so `Compat.ScanBound` pulls the structured tooltip via `C_TooltipInfo.GetHyperlink(link)` and reads `line.leftText`:

- `"WARBAND_UE"` ← `ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP` ("Binds to Warband until equipped") or `ITEM_ACCOUNTBOUND_UNTIL_EQUIP` ("Warbound until equipped").
- `"WARBAND"` ← `ITEM_BIND_TO_BNETACCOUNT` / `ITEM_BIND_TO_ACCOUNT` ("Binds to Warband") or `ITEM_BNETACCOUNTBOUND` / `ITEM_ACCOUNTBOUND` ("Warbound").

**Neither is authoritative alone**, so `Compat.BestBound` merges them by specificity (`WARBAND_UE` > `WARBAND` > the rest) and whichever signal *sees* warbound wins; a warbound verdict is never demoted to BoE/BoP. `ScanBound` also returns a second value, `readable` — a nil state means both "not warbound" and "the client hasn't built this tooltip yet", and any job that retries rows must not confuse the two (`Compat.ItemBindState` combines it with "is the item data cached" into `settled`).

**The readability trap:** an uncached item does *not* hand back an empty tooltip. It hands back a perfectly legible one reading `RETRIEVING_ITEM_INFO` ("Retrieving item information") and nothing else. Treating that as readable is how a repair pass declares every row settled while learning nothing — it is excluded explicitly in `ScanBound`.

Four traps live in the tooltip signal. **There is no account-bound state any more:** Warbands (11.0) retextualized *every* `ITEM_*ACCOUNTBOUND*` global to "Warbound", so a scanner that keeps an account list ends up filing warbound loot under it — which is exactly what the retired `"ACCOUNT"` token was. Each state has **two wordings**: `Binds to Warband…` while the item is still transferable, the bare `Warbound…` once it is bound — so the "Binds to…" forms must be matched too. And **the two `…_UNTIL_EQUIP` globals are not dependable at runtime**: a live client can hand back `nil` for them, and because both UE wordings *contain* their plain counterpart, keying the UE state on those globals alone silently degrades every warbound-until-equipped drop to plain warbound.

**A bind line is a WHOLE line.** Substring matching is the fourth way this has broken: `Warbound Cache of Void-Touched Armaments: Boots` is an item *name*, so a `find` for "warbound" hits line 1 and classifies the item as plain warbound before the real `Binds to Warband until equipped` line is ever reached. The six wordings are therefore matched as **complete lines** (trimmed, case-insensitive), with one deliberate exception: a line *starting* with `binds to warband` also counts, since no item name opens that way.

So the scan is deliberately **two steps per line, not longest-match-first**: decide *whether* the line is a warbound line (whole-line match against the six globals, or the four known wordings, or the `binds to warband` prefix), then decide *which* state from the `until equipped` qualifier — UE globals first, literal fallback second. Globals resolve by name at scan time, and the literal fallbacks are safe because this addon is English-only. Absent `C_TooltipInfo` entirely, `ScanBound` returns `nil` and the record simply stores whatever the bind type gave. See the `bound` field in [schema.md](schema.md), and the deferred repair in [schema.md](schema.md) — a migration cannot read either source, because it runs at `ADDON_LOADED` with a cold item cache.

## Item-info uncached fallback — link-color quality

`C_Item.GetItemInfo(link)` returns `nil` for an item the client hasn't cached yet, which for a just-looted item is the common case. `Compat.GetItemInfo` degrades to the item **link's own display data** instead of dropping the record (`core/Compat.lua:227-240`):

- `itemID` / `classID` come from `C_Item.GetItemInfoInstant` (synchronous, cache-independent).
- `name` falls back to the link's `[…]` bracket text.
- `quality` falls back to `NS.Item.QualityFromLink` (`lib.QualityFromLink` in `libs/LibKa0s/Item.lua`, reached through `core/ItemSetup.lua`), which reads the link's color in two rungs since Item minor 2 (LibKa0s v1.56.0). Since patch 11.1.5 the client colors a link by quality **number**, `|cnIQ<n>:`, and that rung is read first and needs no palette. The `|cffRRGGBB` hex rung stays as the fallback for the pre-11.1.5 links a stored row still holds: it reverses the hex through a hex→quality-id map built lazily from `ITEM_QUALITY_COLORS` and cached only once non-empty, so a first call that lands before the client populated the table is retried rather than pinned nil (`buildQualityByHex` in `libs/LibKa0s/Item.lua`). `tests/test_itemsetup.lua` pins both shapes.

The **primitive** moved into `LibKa0s-Item-1.0`; the **guess** did not. Falling back at all is this addon's policy — BankLedger's quality gate refuses an uncached item and records the skip instead — so `Compat.GetItemInfo` stays in `core/Compat.lua` and the library holds no opinion about how the primitives are composed.

So an uncached loot line still records the correct item id, name, and quality; the denormalized gear fields (ilvl, vendorPrice, subtype) simply come back `nil` until the item caches. `classID` is the locale-independent `Enum.ItemClass` token used for the quest-item gate (`Constants.ITEMCLASS_QUEST = 12`, `core/Constants.lua:90`).

## AH-mail detection — localized *_MAIL_SUBJECT globals

Auction-House proceeds arrive as mail, and LH attributes them to `AH` rather than `MAIL`. There's no flag on the mail row, so `Compat.IsAuctionHouseMail` decides from sender + subject, locale-independently (`core/Compat.lua:188-202`):

- sender equals the `AUCTION_HOUSE` global, **or**
- subject starts with the prefix of any of `AUCTION_WON_MAIL_SUBJECT`, `AUCTION_EXPIRED_MAIL_SUBJECT`, `AUCTION_REMOVED_MAIL_SUBJECT`, `AUCTION_INVOICE_MAIL_SUBJECT` (each global like `"Auction won: %s"` is trimmed at `%s` to `"Auction won: "` and prefix-matched).

`Attribution:StampMail` reads sender/subject via `Compat.GetMailHeader` (`GetInboxHeaderInfo`, `:173-179`) and stamps `AH` or `MAIL` accordingly (`modules/Attribution.lua:385-394`). AH is a stamped, first-class source — it has a live capture path (`Constants.SOURCE_IMPLEMENTED`, `core/Constants.lua:61-70`), as does every other source now that CRAFT/ROLL/REFUND are wired.

## Currency category — rebuild on a miss, blind to collapsed headers

A currency row's **Subtype** is its Currency-tab header ("The War Within", a season name). No API answers that for an id, so `Compat.CurrencyCategory` walks `C_CurrencyInfo.GetCurrencyListSize` / `GetCurrencyListInfo` / `GetCurrencyListLink`, tracks the most recent header, and caches `currencyID -> header` (`core/Compat.lua:442-542`, which also holds the listed-id test `Compat.ListedCurrencyID`).

- **The rule: rebuild once per missed id.** The cache is built at the first currency loot, and a currency the player discovers later (routine at a season start) is not in it. On a miss the resolver rebuilds the cache and looks again. A module-local `currencyCategoryMissed` set records each id that missed, so an id that is truly absent costs at most one list walk and every later lookup answers `nil` from the cache — until the list changes: a different `GetCurrencyListSize`, or a nil-id `CURRENCY_DISPLAY_UPDATE` (`Compat.CurrencyListChanged`), drops the cache and the memo, so an id that missed and is listed later still resolves its Subtype. Before this rule the first snapshot was kept for the whole session, and a new currency's row was persisted with `itemSubType = nil` for good.
- **The gap: collapsed headers.** `GetCurrencyListInfo` enumerates only the children of **expanded** headers. A currency under a header the player collapsed is not in the walk, so the rebuild cannot find it: the row keeps `itemSubType = nil` and falls out of the subtype filter (see ARCHITECTURE.md *Known limitations*). `C_CurrencyInfo.ExpandCurrencyList` could open the headers for the walk, but it is deliberately **not** called: it would run from a loot handler and change the player's Currency tab.
- **S-003 outcome:** not yet run in the client. smoke-tests.md CAP-19 carries the check; record here whether a currency under a collapsed header resolves after `/reload`.

## C_Spell moved the spell-name lookup

Attribution detects deconstruct casts (Disenchant / Milling / Prospecting), and Retail relocated the spell-name lookup to `C_Spell`. `Compat.GetSpellName` is `LibKa0s-Compat-1.0`'s member since v1.55.0: it prefers `C_Spell.GetSpellName(spellID)`, then `C_Spell.GetSpellInfo(spellID).name`, and falls back to the legacy `GetSpellInfo` when present (`core/Compat.lua:158-170`). `Attribution:DeconstructSource` resolves by **spell id first** — the locale-independent `DECONSTRUCT_ID` table — then, for the un-enumerated per-herb/ore "Mass Mill/Prospect" variants, falls back to a **localized name-family** match: the cast's *localized* name is compared against reference tokens derived at match time from seed spellIDs via `GetSpellName` (`NAME_SEEDS`), so the check follows the client locale and never compares against a hardcoded English literal (`modules/Attribution.lua:33-103`). This is locale-correct on every client, not enUS-only; matching a localized name at all is a localization-§4 / anti-pattern #37 departure, ratified in `docs/ARCHITECTURE.md` → Documented deviations.

## Unknown event names — one refusal costs one edge

Modern Retail **raises** `Attempt to register unknown event "<NAME>"` on a name the client does not
know, and a block of bare registrations loses every line after the one that raised. Every event this
addon listens to therefore registers through Core's per-event helper (`NS.SafeRegisterEvent` /
`NS.SafeRegisterUnitEvent`, `core/CoreSetup.lua`), which asks `C_EventUtils.IsEventValid` first and
`pcall`s the registration, and records a refused name once on `NS.RejectedEvents`
(events-frames-taint-§1).

- **The seam.** The helpers are `LibKa0s-Core-1.0`'s `SafeRegisterEvent` / `SafeRegisterUnitEvent`
  (Core minor 8) plus the host's `NS.SafeRegisterEvents` for a list: the `IsEventValid` front gate,
  then a `pcall`ed registration. The live wrappers add one `[Init]` debug line per newly refused name
  and return the library's answer; the library-absent stub carries the same three members as
  one-rung bodies (a plain `pcall`, no front gate). No authored `:RegisterEvent(` /
  `:RegisterUnitEvent(` call exists outside those helper bodies.
- **The rejected list is the addon's**, not the library's: `NS.RejectedEvents` is declared in
  `core/CoreSetup.lua` on both paths and passed at every site, and a refused name is appended once,
  however many disable/enable cycles meet it again. `Attribution.__events` holds only the names that
  actually registered, so `Attribution:Disable` unregisters exactly those.
- **The trade, taken deliberately.** A refused name is skipped, not worked around: the edge it covered
  is simply absent on that client. If a patch retired `ENCOUNTER_START`, loot would still record, and
  boss loot would lose its encounter detail until the event is replaced; if it retired
  `UNIT_SPELLCAST_SUCCEEDED`, deconstruct yields would fall to OTHER / INFERRED. Losing one edge is
  survivable; losing the rest of the block — every source stamp after the bad name — is not.
- **Discoverable.** `/lh debug events` prints the list (`rejected events: none` on 12.1, where every
  name is valid today), and with debug logging on each first refusal writes one `[Init]` line to the
  console.
