# Midnight quirks — GUID decode, tooltip scans, and other 12.0 traps

Catalog of WoW Midnight (Interface 120007, 12.0.7) behaviors that Ka0s Loot History handles. **Read this before touching capture, attribution, or item-info code.** Every quirk below is dealt with in `core/Compat.lua` (the compat firewall — see [compat-layer.md](compat-layer.md)); attribution wiring that consumes them lives in `modules/Attribution.lua` (see [data-flow.md](data-flow.md)).

> **Not a secret-value *reader* — but its output seam is still secret-safe.** Unlike KickCD, LH does **not** read cooldown/cast timings or any of 12.0's "secret value" protected returns; it reads loot, item, mail, and quest data, none of which are secret-tainted. So no capture/attribution path ever holds a secret. **However**, the shared chat printer (`NS.Print`) and debug sink (`NS.Debug`) are still built secret-safe — every argument routes through `NS.SafeToString` (`core/Util.lua`) before it reaches `table.concat`/`string.format`, so a value that *is* secret logs as `<secret>` instead of crashing. This is the Ka0s standard's single-seam mandate (events-frames-taint-§8): the guard lives once in the shared helpers and every call site inherits it, regardless of whether this addon happens to feed it a secret today. There is no per-call-site `issecretvalue` handling, and there should be none.

## Retail-only: presence guards, not flavor branching

LH ships Retail-only, so `core/Compat.lua` carries **no** `WOW_PROJECT_ID` branching. Every deprecated or flavor-varying API is gated by a direct `C_*` / global **presence check**; a missing API degrades the shim to `nil`/`false` rather than erroring (`core/Compat.lua:5-7`). Examples: `C_Map.GetBestMapForUnit` (`:10`), `C_ChallengeMode.GetActiveKeystoneInfo` (`:19`), `C_Container.UseContainerItem` with a bare-global fallback (`:29`), `C_TooltipInfo.GetHyperlink` (`:224`). This is the standard's compat-firewall rule: modules call `NS.Compat.X` and never test the game flavor inline.

## GUID decode — npcID in field 6, KILL vs CONTAINER

A dash-split WoW GUID (`Creature-0-…-<npcID>-…`) carries the creature/npc id in **field 6**, but only for *unit* kinds. `Compat.UNIT_KINDS` is the single source of truth for which kinds those are — `Creature`, `Vehicle`, `Pet`, `Vignette` (`core/Compat.lua:120`). `Compat.DecodeGUID` splits the GUID, returns the leading `kind`, and pulls field 6 as `npcID` **only** when the kind is in that set; non-unit kinds return `nil` for the id (`:124-132`).

The attribution engine keys loot-source resolution off that kind so KILL detection can't drift from the decoder (`modules/Attribution.lua:145-165`):

- **unit kind** (`UNIT_KINDS`) → `KILL`, detail `{ npcID }` (plus encounter id/difficulty when an encounter is live).
- **`GameObject`** → `MPLUS` when a keystone context is active, else `CONTAINER`.
- **`Item`** → `CONTAINER` (a lootable Item-GUID, e.g. a disenchant/mill mat window).
- anything else → `OTHER`.

The keystone context that flips `GameObject` from CONTAINER to MPLUS comes from `Compat.GetActiveKeystoneLevel` (`core/Compat.lua:19`), stamped on `CHALLENGE_MODE_START` and kept alive through `CHALLENGE_MODE_COMPLETED` so the reward chest still reads MPLUS (`modules/Attribution.lua:211-226`).

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

`C_Item.GetItemInfo(link)` returns `nil` for an item the client hasn't cached yet, which for a just-looted item is the common case. `Compat.GetItemInfo` degrades to the item **link's own display data** instead of dropping the record (`core/Compat.lua:126-139`):

- `itemID` / `classID` come from `C_Item.GetItemInfoInstant` (synchronous, cache-independent).
- `name` falls back to the link's `[…]` bracket text.
- `quality` falls back to `NS.Item.QualityFromLink` — parsing the link's `|cffRRGGBB` color prefix and reversing it through a hex→quality-id map built from `ITEM_QUALITY_COLORS` (`libs/LibKa0s/Item.lua:83`, reached through `core/ItemSetup.lua`).

The **primitive** moved into `LibKa0s-Item-1.0`; the **guess** did not. Falling back at all is this addon's policy — BankLedger's quality gate refuses an uncached item and records the skip instead — so `Compat.GetItemInfo` stays in `core/Compat.lua` and the library holds no opinion about how the primitives are composed.

So an uncached loot line still records the correct item id, name, and quality; the denormalized gear fields (ilvl, vendorPrice, subtype) simply come back `nil` until the item caches. `classID` is the locale-independent `Enum.ItemClass` token used for the quest-item gate (`Constants.ITEMCLASS_QUEST = 12`, `core/Constants.lua:48`).

## AH-mail detection — localized *_MAIL_SUBJECT globals

Auction-House proceeds arrive as mail, and LH attributes them to `AH` rather than `MAIL`. There's no flag on the mail row, so `Compat.IsAuctionHouseMail` decides from sender + subject, locale-independently (`core/Compat.lua:91-109`):

- sender equals the `AUCTION_HOUSE` global, **or**
- subject starts with the prefix of any of `AUCTION_WON_MAIL_SUBJECT`, `AUCTION_EXPIRED_MAIL_SUBJECT`, `AUCTION_REMOVED_MAIL_SUBJECT`, `AUCTION_INVOICE_MAIL_SUBJECT` (each global like `"Auction won: %s"` is trimmed at `%s` to `"Auction won: "` and prefix-matched).

`Attribution:StampMail` reads sender/subject via `Compat.GetMailHeader` (`GetInboxHeaderInfo`, `:80-86`) and stamps `AH` or `MAIL` accordingly (`modules/Attribution.lua:299-308`). AH is a stamped, first-class source — it has a live capture path (`Constants.SOURCE_IMPLEMENTED`, `core/Constants.lua:37-41`), as does every other source now that CRAFT/ROLL/REFUND are wired.

## C_Spell moved the spell-name lookup

Attribution detects deconstruct casts (Disenchant / Milling / Prospecting), and Retail relocated the spell-name lookup to `C_Spell`. `Compat.GetSpellName` prefers `C_Spell.GetSpellName(spellID)` and falls back to the legacy `GetSpellInfo` when present (`core/Compat.lua:72-77`). `Attribution:DeconstructSource` resolves by **spell id first** — the locale-independent `DECONSTRUCT_ID` table — then, for the un-enumerated per-herb/ore "Mass Mill/Prospect" variants, falls back to a **localized name-family** match: the cast's *localized* name is compared against reference tokens derived at match time from seed spellIDs via `GetSpellName` (`NAME_SEEDS`), so the check follows the client locale and never compares against a hardcoded English literal (`modules/Attribution.lua:32-97`). This is locale-independent on every client (Ka0s Standard localization-§4 / anti-pattern #37), not enUS-only.
