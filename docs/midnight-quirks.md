# Midnight quirks — GUID decode, tooltip scans, and other 12.0 traps

Catalog of WoW Midnight (Interface 120007, 12.0.7) behaviors that Ka0s Loot History handles. **Read this before touching capture, attribution, or item-info code.** Every quirk below is dealt with in `core/Compat.lua` (the compat firewall — see [compat-layer.md](compat-layer.md)); attribution wiring that consumes them lives in `modules/Attribution.lua` (see [attribution.md](attribution.md)).

> **Not a secret-value *reader* — but its output seam is still secret-safe.** Unlike KickCD, LH does **not** read cooldown/cast timings or any of 12.0's "secret value" protected returns; it reads loot, item, mail, and quest data, none of which are secret-tainted. So no capture/attribution path ever holds a secret. **However**, the shared chat printer (`NS.Print`) and debug sink (`NS.Debug`) are still built secret-safe — every argument routes through `NS.SafeToString` (`core/Util.lua`) before it reaches `table.concat`/`string.format`, so a value that *is* secret logs as `<secret>` instead of crashing. This is the Ka0s standard's single-seam mandate (events-frames-taint-§8): the guard lives once in the shared helpers and every call site inherits it, regardless of whether this addon happens to feed it a secret today. There is no per-call-site `issecretvalue` handling, and there should be none.

## Retail-only: presence guards, not flavor branching

LH ships Retail-only, so `core/Compat.lua` carries **no** `WOW_PROJECT_ID` branching. Every deprecated or flavor-varying API is gated by a direct `C_*` / global **presence check**; a missing API degrades the shim to `nil`/`false` rather than erroring (`core/Compat.lua:5-7`). Examples: `C_Map.GetBestMapForUnit` (`:10`), `C_ChallengeMode.GetActiveKeystoneInfo` (`:19`), `C_Container.UseContainerItem` with a bare-global fallback (`:29`), `C_TooltipInfo.GetHyperlink` (`:224`). This is the standard's compat-firewall rule: modules call `NS.Compat.X` and never test the game flavor inline.

## GUID decode — npcID in field 6, KILL vs CONTAINER

A dash-split WoW GUID (`Creature-0-…-<npcID>-…`) carries the creature/npc id in **field 6**, but only for *unit* kinds. `Compat.UNIT_KINDS` is the single source of truth for which kinds those are — `Creature`, `Vehicle`, `Pet`, `Vignette` (`core/Compat.lua:120`). `Compat.DecodeGUID` splits the GUID, returns the leading `kind`, and pulls field 6 as `npcID` **only** when the kind is in that set; non-unit kinds return `nil` for the id (`:124-132`).

The attribution engine keys loot-source resolution off that kind so KILL detection can't drift from the decoder (`modules/Attribution.lua:134-154`):

- **unit kind** (`UNIT_KINDS`) → `KILL`, detail `{ npcID }` (plus encounter id/difficulty when an encounter is live).
- **`GameObject`** → `MPLUS` when a keystone context is active, else `CONTAINER`.
- **`Item`** → `CONTAINER` (a lootable Item-GUID, e.g. a disenchant/mill mat window).
- anything else → `OTHER`.

The keystone context that flips `GameObject` from CONTAINER to MPLUS comes from `Compat.GetActiveKeystoneLevel` (`core/Compat.lua:19`), stamped on `CHALLENGE_MODE_START` and kept alive through `CHALLENGE_MODE_COMPLETED` so the reward chest still reads MPLUS (`modules/Attribution.lua:200-215`).

## Warband / account-bound tooltip scanning (C_TooltipInfo)

Bind state above BOE/BOP — Warbound and Account Bound — isn't in `C_Item.GetItemInfo`'s return tuple; it only appears as tooltip text. `Compat.ScanBound` pulls the structured tooltip via `C_TooltipInfo.GetHyperlink(link)` and scans `line.leftText` for the localized global strings (`core/Compat.lua:222-234`):

- `"WARBAND"` ← `ITEM_ACCOUNTBOUND_UNTIL_EQUIP` ("Warbound until equipped") or `ITEM_BNETACCOUNTBOUND` ("Warbound").
- `"ACCOUNT"` ← `ITEM_ACCOUNTBOUND` ("Account Bound") or `ITEM_BIND_TO_BNETACCOUNT` (legacy).

Matching is done with `text:find(s, 1, true)` (plain, locale-independent via the globals, `:215-217`). This is Retail-only: absent `C_TooltipInfo`, `ScanBound` returns `nil` and `GetItemExtras` falls back to the numeric `bindType` (1/4 → BOP, 2/3 → BOE); a warband/account result always wins over the plain bind type (`:257-272`). See the `bound` field in [data-model.md](data-model.md).

## Item-info uncached fallback — link-color quality

`C_Item.GetItemInfo(link)` returns `nil` for an item the client hasn't cached yet, which for a just-looted item is the common case. `Compat.GetItemInfo` degrades to the item **link's own display data** instead of dropping the record (`core/Compat.lua:169-182`):

- `itemID` / `classID` come from `C_Item.GetItemInfoInstant` (synchronous, cache-independent).
- `name` falls back to the link's `[…]` bracket text.
- `quality` falls back to `Compat.QualityFromLink` — parsing the link's `|cffRRGGBB` color prefix and reversing it through a hex→quality-id map built from `ITEM_QUALITY_COLORS` (`:135-153`).

So an uncached loot line still records the correct item id, name, and quality; the denormalized gear fields (ilvl, sellPrice, subtype) simply come back `nil` until the item caches. `classID` is the locale-independent `Enum.ItemClass` token used for the quest-item gate (`Constants.ITEMCLASS_QUEST = 12`, `core/Constants.lua:44`).

## AH-mail detection — localized *_MAIL_SUBJECT globals

Auction-House proceeds arrive as mail, and LH attributes them to `AH` rather than `MAIL`. There's no flag on the mail row, so `Compat.IsAuctionHouseMail` decides from sender + subject, locale-independently (`core/Compat.lua:91-109`):

- sender equals the `AUCTION_HOUSE` global, **or**
- subject starts with the prefix of any of `AUCTION_WON_MAIL_SUBJECT`, `AUCTION_EXPIRED_MAIL_SUBJECT`, `AUCTION_REMOVED_MAIL_SUBJECT`, `AUCTION_INVOICE_MAIL_SUBJECT` (each global like `"Auction won: %s"` is trimmed at `%s` to `"Auction won: "` and prefix-matched).

`Attribution:StampMail` reads sender/subject via `Compat.GetMailHeader` (`GetInboxHeaderInfo`, `:80-86`) and stamps `AH` or `MAIL` accordingly (`modules/Attribution.lua:265-274`). AH is a stamped, first-class source — it has a live capture path (`Constants.SOURCE_IMPLEMENTED`, `core/Constants.lua:33-37`), unlike CRAFT/ROLL which are enum'd but not yet wired.

## C_Spell moved the spell-name lookup

Attribution detects deconstruct casts (Disenchant / Milling / Prospecting), and Retail relocated the spell-name lookup to `C_Spell`. `Compat.GetSpellName` prefers `C_Spell.GetSpellName(spellID)` and falls back to the legacy `GetSpellInfo` when present (`core/Compat.lua:72-77`). `Attribution:DeconstructSource` resolves by **spell id first** — the locale-independent `DECONSTRUCT_ID` table — then, for the un-enumerated per-herb/ore "Mass Mill/Prospect" variants, falls back to a **localized name-family** match: the cast's *localized* name is compared against reference tokens derived at match time from seed spellIDs via `GetSpellName` (`NAME_SEEDS`), so the check follows the client locale and never compares against a hardcoded English literal (`modules/Attribution.lua:32-84`). This is locale-independent on every client (Ka0s Standard localization-§4 / anti-pattern #37), not enUS-only.
