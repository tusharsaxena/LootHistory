# M2 design: reputation and appearance capture as History rows

Plan: `docs/superpowers/plans/2026-11-27-tooltip-toasts-farm.md` (rows M2.1 to M2.5; decisions D7, D8, D22).
Mockup: `docs/superpowers/specs/2026-11-27-tooltip-toasts-farm-mockups.html:447-468` ("Rep and appearances in History").
Branch: `feat/2026-11-27-rep-appearance-capture`, based on M1 (plan, `## Branches`).

All file:line references are to the tree at `c34962a` (M0.2). Re-check each anchor before editing,
because M1 lands first and may shift lines.

---

## 1. Goal

Record reputation changes (gains **and** losses) and, on Retail only, transmog appearance
collection (collected **and** removed) as History rows of two new kinds. They flow into the Type
filter, the table, Insights and both CSV exports, and each kind has its own capture switch that is
on by default (D8). Experience and profession skill-ups are **not** History rows (D8). They belong
to M3's gain feed. M2 only makes the rep and appearance capture points callable from that feed
later. M3.1 adds the tap; M2 adds no bus message.

### Decisions implemented

| Id | What M2 does |
|---|---|
| D7 | Reputation gain and loss on both clients; appearances on Retail only, declared through `C.FEATURE_CLIENTS` (clients-§4) |
| D8 | New kinds `REPUTATION` and `APPEARANCE`, new Type values, Insights, CSV, and the switches `settings.recordReputation` / `settings.recordAppearances` (default on) |
| D22 | A row carries the fields the farm tally needs later: `factionID` for the reputation line, and `newLook` for "new appearances" |

### Rulings this spec makes (architect's calls, within the owner's decisions)

| # | Ruling | Why |
|---|---|---|
| A1 | `holder` is the earning **character**, even for a warband (account-wide) faction. `accountWide = true` is stored on the row | The mockup lists rep under the character (`mockups.html:455-457`); the Character filter matches holder; nothing is held, so `§warband` would claim ownership that does not exist |
| A2 | With `settings.trackLedger` off, only gains (`dir = IN`) are written. A loss or removal writes `[Drop] reason=ledger-off` | trackLedger off means "legacy gains-only" (`defaults/Profile.lua:46`, `modules/Collector.lua:316-322`) |
| A3 | Consecutive gains (or consecutive losses) for one faction from one source within `C.REP_COALESCE = 60` s grow the last row through `Database:Amend` instead of writing a new row | AoE farming would otherwise write one row per kill. The 60 s window is the Reconciler's existing coalescing span (`core/Database.lua:670-679` comment) |
| A4 | The rep baseline lives **in memory only**. It is seeded at stand-up by a full faction walk, `Compat.ListFactions`, that expands collapsed headers and restores them, as `Compat.ListCurrencies` already does (`core/Compat.lua:934-941`). A faction first seen at an event is seed-only (no row) | No new SavedVariables store, so no H4 store, no migration and no stale baseline across sessions. `/reload` reseeds, so a reload writes no phantom rows. Never records a whole standing as a gain (RLF bug, `utils/ReputationHelpers.lua:393-413`) |
| A5 | Rep progress is a scalar built from **absolute** values (§3.3), never progress relative to the rank | Avoids RLF's wrong-sign rank-down loss (`ReputationHelpers.lua:297`, `:416-447`) |
| A6 | Every appearance *source* added is a row (as Blizzard's own "added to your appearance collection" chat line works), flagged `newLook = true` when it is the first known source of its visual | The D22 tally and the D9 highlight read `newLook`; source collectors keep their rows |
| A7 | Rep and appearance rows ignore Minimum quality, both at capture and in the default view's floor | They are not item loot records |
| A8 | Rep and appearance rows obey **Record data from** (`excludedSources`), as currency does | One mute list for every recorded kind (`modules/Collector.lua:286-291`) |
| A9 | Rep name color is the skin token `sem.info` | The mockup's blue (`#4f8cff`, `mockups.html:456`) has no exact token; `sem.info` exists in every skin (`libs/LibKa0s/SkinDefs.lua:288`, `:476`). No hardcoded RGB, no LibKa0s change (D1) |
| A10 | Forever uses the same `FACTION_STANDING_CHANGED` row as Retail (one row, both clients), and M2.1 adds the event to `/lh debug probe` to confirm it there (§3.6) | RLF registers this event on Forever, since its IsRetail() includes Forever (`utils/AddonMethods.lua:46-51`, `Features/Reputation/Reputation.lua:229-236`). A chat-text parser would need secret guards and a name-to-ID map |

### Scope boundaries

- In: reputation rows (both clients), appearance rows (Retail), their read side, switches, sim, docs.
- Out: experience and skill-up rows (toast and tally only, M3/M4). Out: the gain feed (M3.1). Out: any toast.
  Out: hidden factions (Delver's Journey polling, `Reputation.lua:237-245`). Out: a faction blacklist.
  Out: a persisted rep baseline. Out: holdings, rollup and Timeline for the new kinds (§6.3).
- Appearances: Retail only, by declaration. Forever exposes `C_TransmogCollection`, so the API's
  presence cannot be the gate (`tests/_kit/client_globals_forever.lua` added/removed blocks).

---

## 2. Record shapes

Both kinds stamp `kind`, `dir` and `holder` **explicitly** on every row. `Util.RowKind` falls back
to ITEM for a row with an itemID and no kind (`core/Util.lua:364-368`), and the same inference is
inlined in `rowFacts` (`core/Database.lua:1088-1092`). No price fields are set, so
`Util.RecordValue` is nil and every value reads 0.

### 2.1 REPUTATION

| Field | Type | Required | Value |
|---|---|---|---|
| `ts` | number | yes | `time()` |
| `char` | string | yes | `NS.Util.PlayerKey()` |
| `classFile` | string | yes | `NS.Compat.PlayerClassFile()` |
| `holder` | string | yes | `= char` (A1) |
| `dir` | string | yes | `"IN"` when delta > 0, `"OUT"` when delta < 0 (`C.Dir`) |
| `kind` | string | yes | `"REPUTATION"` (`C.Kind.REPUTATION`) |
| `factionID` | number | yes | the event's faction id |
| `itemName` | string | yes | faction name (from `Compat.FactionSnapshot`); the text search matches it |
| `itemType` | string | yes | `C.REPUTATION_TYPE = "Reputation"` (Type column and filter) |
| `itemSubType` | string | yes | standing label **after** the change: `"Honored"`, `"Renown 12"`, the friendship rank text, or `"Paragon"` when paragon is active |
| `quantity` | number | yes | `abs(delta)`, an integer >= 1. The sign comes from `dir`, read by `Ledger.DirSign` (`core/Ledger.lua:23`) |
| `repType` | string | yes | `"base"` \| `"friendship"` \| `"renown"` \| `"guild"` |
| `rank` | number | optional | reaction index (base, guild), renown level (renown), friendship rank level; nil when unreadable |
| `standing` | number | optional | the bar value after the change: absolute `currentStanding` (base, guild), absolute friendship standing, `renownReputationEarned` (renown) |
| `accountWide` | boolean | optional | `true` for a warband faction, else nil |
| `source`, `sourceDetail`, `confidence` | | yes / optional / yes | §4 |
| `zone`, `mapID`, `subzone` | | as currency | `NS.Zone()`, `NS.PlayerMapID()` |

Not set: `itemID`, `currencyID`, `itemLink`, `quality`, `bound`, `vendorPrice`, `auctionPrice`, `itemLevel`.

### 2.2 APPEARANCE (Retail)

| Field | Type | Required | Value |
|---|---|---|---|
| `ts`, `char`, `classFile` | | yes | as above |
| `holder` | string | yes | `= char` |
| `dir` | string | yes | `"IN"` for `TRANSMOG_COLLECTION_SOURCE_ADDED`, `"OUT"` for `_REMOVED` |
| `kind` | string | yes | `"APPEARANCE"` |
| `sourceID` | number | yes | the event payload (itemModifiedAppearanceID) |
| `appearanceID` | number | optional | the visual id from `Compat.AppearanceSource` |
| `itemID` | number | optional | the source's item (enables Wowhead link, `modules/Export.lua:33-44`, and the tooltip) |
| `itemLink` | string | optional | the source's item link when the client has it; no async retry |
| `itemName` | string | yes | item name, or `"Appearance " .. sourceID` when unreadable |
| `quality` | number | optional | item quality (colors the name, `modules/BrowserTable.lua:938-939`) |
| `itemType` | string | yes | `C.APPEARANCE_TYPE = "Appearance"` |
| `itemSubType` | string | optional | the item's own subtype from `GetItemInfoInstant` (Cloth, Plate, One-Handed Swords) |
| `quantity` | number | yes | `1` |
| `newLook` | boolean | optional | IN rows only: `true` when this is the only collected source of its visual |
| `source`, `sourceDetail`, `confidence` | | | §4 |
| `zone`, `mapID`, `subzone` | | | as above |

Not set: `currencyID`, `bound`, `vendorPrice`, `auctionPrice`, `itemLevel` (A6: the item row from
the same loot already carries the value, and a second price would double Value).

### 2.3 Constants (core/Constants.lua)

- `C.Kind` gains `REPUTATION = "REPUTATION", APPEARANCE = "APPEARANCE"`. This is append only, in
  line with the comment at `core/Constants.lua:183-186`.
- `C.REPUTATION_TYPE = "Reputation"` and `C.APPEARANCE_TYPE = "Appearance"` go beside `C.CURRENCY_TYPE` (`:181`).
- `C.FEATURE_CLIENTS.appearances = { "retail" }` (`:18-21`). Extend the header comment (`:5-17`) with
  an `appearances` sentence: the two TRANSMOG rows, the switch row, test mode's appearance rows and
  the simulator's appearance step.
- `C.REP_COALESCE = 60` (seconds) and `C.REP_SEED_RETRY = 5` (seconds).
- `C.FEATURE.appearances` is derived by the existing loop (`:22`).

No `NS.SCHEMA_VERSION` bump. Both kinds are additive: old rows never carry them, and
`Database:Add` takes any field (`core/Database.lua:659-668`). The new settings keys merge from the
AceDB defaults (`defaults/Profile.lua:56-58` precedent).

---

## 3. Detection

### 3.1 Events

| Event | Owner | Target | Clients | Payload used |
|---|---|---|---|---|
| `FACTION_STANDING_CHANGED` | `Reputation` | `bus` | both | `factionID` (arg 1) only |
| `TRANSMOG_COLLECTION_SOURCE_ADDED` | `Appearance` | `bus` | `C.FEATURE_CLIENTS.appearances` | `sourceID` (arg 1) |
| `TRANSMOG_COLLECTION_SOURCE_REMOVED` | `Appearance` | `bus` | `C.FEATURE_CLIENTS.appearances` | `sourceID` (arg 1) |

The rows are declared at file load with `NS.EventRow` (`core/Dispatch.lua:40-44`). The appearance
rows are declared inside `if C.FEATURE.appearances then ... end`, the pattern from
`modules/Attribution.lua:22`, `:556-567`. `bus` is safe because AceEvent allows one handler per
event per target, and no other owner registers these three names (`core/Dispatch.lua:14-17`).
`PLAYER_ENTERING_WORLD` and `UPDATE_FACTION` are **not** registered (`modules/Attribution.lua:547-549`).
`MAJOR_FACTION_RENOWN_LEVEL_CHANGED` is not registered either: a level change also arrives as a
standing change, and the delta (§3.3) covers it.

### 3.2 Compat members (core/Compat.lua, all wrapped by the seam unless noted)

They are defined in `core/Compat.lua` so they load before `core/SimSeam.lua`
(`LootHistory.toc:35-47`; H1/H2, `core/SimSeam.lua:8-19`). Callers read them at call time only, as
`NS.Compat.X(...)`, never captured into a file-scope local (`tests/test_compat_routing.lua`).

```
Compat.FactionSnapshot(factionID)
  -> name, repType, rank, standing, threshold, paragon, accountWide, label
     (all nil when the faction is unreadable or any read is secret)
```
- `repType` comes from the first answer that applies:
  1. `C_Reputation.IsMajorFaction(id)` gives `"renown"`.
  2. `C_Reputation.GetGuildFactionData()` with `.factionID == id` gives `"guild"`.
  3. `C_GossipInfo.GetFriendshipReputation(id)` with `friendshipFactionID > 0` gives `"friendship"`.
  4. Anything else is `"base"`.

  Each API is presence-checked. That fills an API gap inside a feature both clients have
  (clients-§3), and on Forever simply answers `"base"`.
- base/guild: `name`, `rank = reaction`, `standing = currentStanding` (absolute), and
  `label = _G["FACTION_STANDING_LABEL" .. reaction]`. This uses `GetText(..., UnitSex("player"))`
  when `GetText` exists.
- friendship: `standing = info.standing` (absolute), `rank = GetFriendshipReputationRanks(id).currentLevel`,
  `label = info.reaction` (the rank text).
- renown: `C_MajorFactions.GetMajorFactionRenownInfo(id)` gives `rank = renownLevel`,
  `standing = renownReputationEarned` and `threshold = renownLevelThreshold`.
  `name = C_MajorFactions.GetMajorFactionData(id).name`, or the GetFactionDataByID name.
  `label = (RENOWN_LEVEL_LABEL or "Renown %d"):format(rank)`.
- `paragon`: when `C_Reputation.IsFactionParagonForCurrentPlayer` (or `IsFactionParagon`) is true,
  this is `currentValue` from `C_Reputation.GetFactionParagonInfo(id)` (cumulative), and
  `label = PARAGON or "Paragon"`. Otherwise it is nil.
- `accountWide`: `C_Reputation.IsAccountWideReputation(id) == true`.
- Secret guard: `name` goes through `plainString` (`core/CompatClient.lua:75-82` pattern; a local
  copy of the isSecret helper in `core/Compat.lua`, or call `NS.Compat.IsSecret` if M1 publishes one).
  A secret numeric answer returns all nil.
- It returns values and never a table: the hot path allocates nothing.

```
Compat.ListFactions() -> { { id, name, repType, rank, standing, threshold, paragon, accountWide, label }, ... }
```
- Walk `C_Reputation.GetNumFactions()` / `GetFactionDataByIndex(i)` forward. When an entry has
  `isHeader and isCollapsed`, call `C_Reputation.ExpandFactionHeader(i)` and record its `factionID`
  in `expanded`. Expanding inserts the header's children right after it, so the forward walk then
  visits them.
- Skip `isHeader and not isHeaderWithRep`. For each remaining entry, fill a row from
  `Compat.FactionSnapshot(factionID)`. Rows with a nil name are dropped.
- Restore: walk the list from the last index to the first and call `C_Reputation.CollapseFactionHeader(i)`
  on each entry whose `factionID` is in `expanded`. Reverse order collapses nested headers first, and
  indices below `i` do not shift.
- **GUARDED** in `core/SimSeam.lua` beside `ListCurrencies` (`:67-71`). While a session is active it
  answers `Host.world.factionList or {}`, built from the world (§3.8), and never expands a header.
  Add it to the SimSeam header comment's GUARDED paragraph (`:24-27`).

```
Compat.AppearanceSource(sourceID) -> itemID, itemLink, name, quality, visualID, itemSubType
```
- `C_TransmogCollection.GetSourceInfo(sourceID)` gives `itemID`, `name`, `quality` and `visualID`.
  `C_TransmogCollection.GetAppearanceSourceInfo(sourceID)` gives `itemLink`. Accept both shapes:
  when the first return is a table, read `.itemLink`; otherwise the link is the 6th return. Treat
  `""` as nil.
- `itemSubType` comes from `select(3, C_Item.GetItemInfoInstant(itemID))` when the itemID is set.
- Plain-string guards on `name` and `itemLink`. It returns all nil when unreadable.

```
Compat.IsNewLook(visualID, sourceID) -> boolean
```
- True when no source of `visualID` other than `sourceID` is collected.
  `C_TransmogCollection.GetAllAppearanceSources(visualID)` returns source ids. For each one other
  than `sourceID`, check `C_TransmogCollection.PlayerKnowsSource(id)`, or `GetSourceInfo(id).isCollected`
  when that function is absent. Return false on the first one collected. A missing API returns false.

`Compat.PlayerInCombat` (`core/Compat.lua:118`) already exists and is reused (§4).

### 3.3 Reputation delta algorithm (pure, `NS.Reputation.Delta`, unit-tested)

The baseline entry per faction is `{ repType, rank, standing, threshold, paragon }`. The table is
allocated once, at seed, and updated in place afterwards.

```
Delta(old, repType, rank, standing, threshold, paragon) -> delta | nil, reason
  if old == nil                     -> nil, "unseeded"   (seed only)
  if old.repType ~= repType         -> nil, "type-change" (reseed)
  local para = (paragon or 0) - (old.paragon or 0)
  if para < 0                       -> nil, "paragon-reset" (reseed)
  if repType == "renown" then
    if rank == old.rank             -> d = standing - old.standing
    elseif rank > old.rank and old.threshold and old.threshold > 0
                                    -> d = (old.threshold - old.standing)
                                         + (rank - old.rank - 1) * old.threshold
                                         + standing
    else                            -> nil, "renown-drop" (reseed)
  else  -- base, guild, friendship: standing is absolute
    d = standing - old.standing
  end
  return d + para                   (0 means unchanged)
```

Renown cannot fall, and the intermediate levels take the old level's threshold (one event rarely
jumps more than one level). At the cap, the standing stops moving and the paragon value carries on,
so the sum stays monotonic. Every reseed writes nothing and overwrites the baseline with the new
values.

### 3.4 Reputation capture path (`modules/Reputation.lua`, new)

The handler is `Reputation:OnStandingChanged(_, factionID)`, wrapped in a Shape-A perf bracket
(`local t0 = Perf.on and debugprofilestop()` ... `Perf.Note("repEvent", ...)`) around a file-local
`repEvent(self, factionID)`, as in `modules/Collector.lua:306-310`.

`repEvent` gate order (each guard writes its `[Drop]` line behind `NS.State.debug`):
1. `factionID` is secret or not a number: `[Drop] rep reason=secret|no-id`.
2. `name, repType, rank, standing, threshold, paragon, accountWide, label = NS.Compat.FactionSnapshot(factionID)`.
   A nil `name` gives `reason=unreadable`.
3. `local old = baseline[factionID]`, then `d, why = Rep.Delta(old, ...)`. The baseline is updated
   in place, or created when the entry is nil. When `d` is nil, write `reason=<why>`. When
   `d == 0`, write `reason=unchanged`. Then return. These paths allocate nothing (`baseline[id]` is
   created only once per faction, ever).
4. `dir = d > 0 and "IN" or "OUT"`. If `dir == "OUT" and not trackLedger`: `reason=ledger-off` (A2).
5. Source (§4). If `excludedSources[source]`: `reason=source` (A8).
6. Coalesce (A3). `last[factionID]` is `{ index, ts, dir, source }`. When
   `last.dir == dir and last.source == source and now - last.ts <= C.REP_COALESCE`
   and `NS.Database:HistoryRow(last.index)` is still that record (a new accessor that answers
   `historyStore()[i]`), then set `r.itemSubType = label`, `r.rank = rank` and
   `r.standing = standing`, call `NS.Database:Amend(last.index, |d|)` and set `last.ts = now`. Stop.
7. Otherwise build the record (§2.1), call `NS.Database:Add(record)`, store `last[factionID]`, and
   write the debug line `Rep "%s %s%d (%s) src=%s"`. Do **not** call Collector's `claim()`: nothing
   is held (`modules/Collector.lua:155-159`).

**Seeding.** `Reputation:Seed()` sets `baseline = {}` and copies each `Compat.ListFactions()` row
into it. While `Compat.PlayerInCombat()` is true it does not walk: it re-arms
`NS.After(C.REP_SEED_RETRY, ...)` (header expansion is UI state and is kept out of combat). Enable
arms the first seed with `NS.After(2, ...)`, so login data is ready. `NS.CancelDeferrals` cancels
it on stand-down. Any event that arrives before the seed is seed-only for its faction (`unseeded`).

**Noise.** Login and reload reseed in memory and write no rows. A duplicate event gives
`unchanged`. A paragon rollover gives `paragon-reset` and a reseed. A renown level-up is the
`rank > old.rank` branch. A switch to paragon at the cap is the same `repType` with a growing
`paragon`. A faction that moves from base to renown gives `type-change`.

**Combat.** The event fires on kills in combat. Per event the work is one `FactionSnapshot` (four
to six C API reads), the pure delta, and at most one `Add` or `Amend`. Nothing is allocated unless
a row is written.

### 3.5 Appearance capture path (`modules/Appearance.lua`, new; Retail rows only)

The handlers are `Appearance:OnSourceAdded(_, sourceID)` and `OnSourceRemoved(_, sourceID)`. They
use a Shape-A bracket on bucket `appearanceEvent`, around a file-local `appearanceEvent(self, sourceID, dir)`.

Gate order:
1. `sourceID` is secret or not a number: `[Drop] appearance reason=secret|no-id`.
2. Duplicates: if `seen[sourceID]` holds the same `dir` stamped within 5 s, then `reason=duplicate`.
   Otherwise set `seen[sourceID] = dir`, plus a parallel `seenAt[sourceID] = GetTime()`. Both maps
   are cleared by `ResetState`.
3. If `dir == "OUT" and not trackLedger`: `reason=ledger-off`.
4. `itemID, itemLink, name, quality, visualID, subType = NS.Compat.AppearanceSource(sourceID)`.
5. Source (§4). If `excludedSources[source]`: `reason=source`.
6. `newLook = dir == "IN" and visualID and NS.Compat.IsNewLook(visualID, sourceID) or nil`.
7. Build the record (§2.2) and call `NS.Database:Add`. Write the debug line
   `Appearance "%s %s src=%s new=%s"`. No `claim()`: an itemID claim would cancel the real item's
   diff row (`modules/Collector.lua:155-159`).

**Bursts** (ensembles, Trading Post sets) write one row per source, as the client reports them.
M3 merges the toasts; History's group-by keeps the table readable. No login gating: real loot in
the first 20 s must not be lost. Smoke check §9 confirms that no rows appear at login or reload. If
the probe shows a login burst, the follow-up is to ignore events until `NS.State.loginSettled`, and
that change is recorded in this spec's register. An `_ADDED` and `_REMOVED` pair for one source
writes two rows: a refund is a real gain followed by a real loss.

### 3.6 Forever

- Same `FACTION_STANDING_CHANGED` row. `FactionSnapshot` answers `"base"`. Forever's
  `C_Reputation` is the live set; the bare `GetFactionInfo` is absent on both clients
  (`tests/_kit/client_globals_forever.lua:52-92`).
- **Verification gate**, part of M2.1. Add `"FACTION_STANDING_CHANGED", "UPDATE_FACTION",
  "CHAT_MSG_COMBAT_FACTION_CHANGE", "TRANSMOG_COLLECTION_SOURCE_ADDED", "TRANSMOG_COLLECTION_SOURCE_REMOVED"`
  to the end of `P.EVENTS` (`modules/Probe.lua:50-56`), and list them in `docs/forever-probes.md:12-30`.
  If the Forever probe shows `FACTION_STANDING_CHANGED` rejected (it lands on `NS.RejectedEvents`),
  the follow-up is a Forever-only row on `UPDATE_FACTION` (`clients = { "forever" }`, its own
  per-client table row). That row fires a coalesced (`NS.Coalesce`, 0.5 s) full `ListFactions` diff
  through the same `Delta`. It never parses chat text. This is pre-designed and not built in M2
  unless the probe says so.

### 3.7 Secrets

Every C API string goes through the plain-string guard. A secret is never a table key: the baseline
is keyed by a numeric `factionID`, which is checked for secret first. A secret is never stored
(client-quirks-§2, `docs/midnight-quirks.md:91-115`). No chat text is parsed.

### 3.8 Simulator

- **Providers** (`modules/SimWorld.lua` PROVIDERS, `:482-513`):
  - `{ "FactionSnapshot", function(w, id) local f = w.factions[id]; if not f then return nil end return f.name, f.repType, f.rank, f.standing, f.threshold, f.paragon, f.accountWide, f.label end }`
  - `{ "ListFactions", listFactions }`, built from `w.factions` in `w.factionOrder`.
  - `{ "AppearanceSource", function(w, id) local a = w.appearances[id]; ... end }`
  - `{ "IsNewLook", function(w, visualID, sourceID) ... end }`, true when no other `w.appearances`
    entry with that visual is `collected`.
- **World seeds** (clients-§5: two lists picked once by `NS.Compat.ClientKey()`). Retail:
  `72` Stormwind (base, rank 5, standing 3000), `21` Booty Bay (base, rank 4, standing 1500) and
  `2590` Council of Dornogal (renown, rank 10, standing 500, threshold 2500). Forever: `72` and
  `21` alone. Appearances, Retail only: two sources with visual ids and the sim fixture's item ids.
  `World.New` copies the seed into `w.factions`, `w.factionOrder` and `w.appearances`. These are
  fixtures, like the item fixture, and not `tools/seeds` data.
- **Drivers** (`modules/SimDrivers.lua`, one rule per driver, `:5-11`):
  - `D.Reputation(factionID, delta)` first changes the world. For base and friendship it adds to
    `standing` and recomputes `rank`/`label` from `C.REP_BASE_BANDS`, a small static table in
    SimWorld. For renown it adds to `standing`, and on overflow raises `rank` and keeps the
    remainder. Then it fires `FACTION_STANDING_CHANGED(factionID, standing)` through `NS.Sim:Fire`.
  - `D.Appearance(sourceID, removed)` first flips `w.appearances[sourceID].collected`, then fires
    `TRANSMOG_COLLECTION_SOURCE_ADDED` or `_REMOVED`. The driver exists only where
    `C.FEATURE.appearances` holds.
- **Scenario step**: add rep steps to the existing quest scenario: a turn-in, then
  `D.Reputation(72, 250)`, which reads QUEST. Add a Retail-only appearance step to the loot
  scenario, gated `C.FEATURE.appearances` as the `key` scenario is gated (`docs/ARCHITECTURE.md:93`).
- **Real-event split** (`modules/Sim.lua:163-166`): add `FACTION_STANDING_CHANGED`,
  `TRANSMOG_COLLECTION_SOURCE_ADDED` and `TRANSMOG_COLLECTION_SOURCE_REMOVED` to `INTERFERENCE`.
  They are always the player's own, and the stop's drift pass does not cover them.
- **Session state** (H4). Rows go to `NS.SimStores.history` through `Database:Add` already. The
  in-memory baseline, the coalesce map and the appearance `seen` maps are capture state. Add
  `NS.Reputation:ResetState()` and `NS.Appearance:ResetState()` to `Host.Prepare` after
  `NS.Attribution:ResetContexts()` (`modules/Sim.lua:268-269`). Then call
  `NS.Reputation:Seed(true)` (the `true` skips the combat retry and the deferral), which seeds from
  the GUARDED world list. Add a STOP step after `releaseStores` and the filter reset
  (`modules/Sim.lua:391-410`):
  `function() NS.Reputation:ResetState(); NS.Appearance:ResetState(); NS.Reputation:Seed() end`.
  The live walk then reseeds, and the simulated standings never reach the real baseline.
  **Amended in the M2.5 review:** the stop must not re-walk. A real `FACTION_STANDING_CHANGED` is
  INTERFERENCE: it stops the session synchronously and then runs live, and by then the client holds
  the new standing, so a reseed at the stop absorbed it (`unchanged`), and a stop in combat left the
  baseline empty (`unseeded`). `Host.Prepare` therefore calls `NS.Reputation:SuspendBaseline()` (the
  real baseline set aside whole) in place of `ResetState`, and the stop step is
  `NS.Reputation:RestoreBaseline(); NS.Appearance:ResetState()`. Every real rep change interferes,
  so the restored baseline is exact.

---

## 4. Source attribution

New `Attribution:Peek()` in `modules/Attribution.lua`, next to `Consume` (`:182-216`). It is
non-decrementing: it never touches `w.left` or `State.fishingUntil` and never clears anything.
```
function Attribution:Peek()
  local now, c, w = GetTime(), State.lootContext, State.lootWindow
  if c and c.expires >= now then return c.source, c.detail, c.confidence end
  if w and w.left > 0 and w.expires >= now then return w.source, w.detail, w.confidence end
  return Constants.SourceType.OTHER, nil, Constants.Confidence.INFERRED
end
```
`Consume` must not be called for these kinds. It decrements the loot window (`:187`), which would
starve the window's loot lines, and it answers FISHING inside a cast (`:202-207`).

- **Reputation.** `s, d, c = Peek()`. If `s == QUEST`, keep `s, d, c`, which carries
  `{questID}` and CERTAIN (`:527-541`). Else if `NS.Compat.PlayerInCombat()`, use `KILL, nil, INFERRED`:
  rep earned in combat is a kill's, and no kill stamp exists before LOOT_OPENED (D22). Otherwise
  use `OTHER, nil, INFERRED`. Any other fresh stamp (a VENDOR or MAIL stamp, say) is ignored for
  rep. That gives the mockup's Quest and Kill rows (`mockups.html:456-457`).
- **Appearance.** `s, d = Peek()`, and confidence is always `INFERRED`. The tie between a stamp and
  a collected look is circumstantial. Loot gives KILL/CONTAINER/FISHING, a purchase gives VENDOR, a
  quest reward gives QUEST, and equip-time learning gives OTHER.

---

## 5. Capture switches

`defaults/Profile.lua` (after `recordCurrency`, `:44`):
```
recordReputation = true,   -- reputation gains and losses as Type=Reputation rows
recordAppearances = true,  -- (Retail) collected/removed appearances as Type=Appearance rows
```

`settings/Schema.lua`. Two rows go straight after `settings.recordCurrency` (`:332-338`) and
**before** `settings.excludedSources`, which must stay the last Loot row (`:340-349`):
```
{ path = "settings.recordReputation", default = PD.settings.recordReputation, type = "bool", widget = "CheckBox",
  page = "General", group = "Capture", subgroup = "Loot", label = "Record reputation",
  tooltip = "Record reputation gains and losses as Type=Reputation rows, with the faction and its standing. " ..
    "Obeys Record data from; losses need Track holdings and losses.",
  onChange = function() if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "reputation") end end },
{ path = "settings.recordAppearances", default = PD.settings.recordAppearances, type = "bool", widget = "CheckBox",
  clients = C.FEATURE_CLIENTS.appearances,
  page = "General", group = "Capture", subgroup = "Loot", label = "Record appearances",
  tooltip = "Record each appearance you collect as a Type=Appearance row, and its removal (a refund) as a loss. " ..
    "Obeys Record data from; removals need Track holdings and losses.",
  onChange = function() if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "appearance") end end },
```
Pairing (options-ui-§7, declaration order is the layout, `:300-307`). Record currency pairs with
Record reputation, and Record appearances opens the next line, alone (Retail). On Forever the row is
dropped by the registry (`libs/LibKa0s/OptionsRegistry.lua:47-71`), which is not the same as hidden.
Update the Capture layout comment at `:300-307` to say this.

Onchange reasons: `"reputation"` and `"appearance"`. Each module's listener re-runs
`RefreshUpvalues` on **every** reason (excludedSources, trackLedger), as Collector does
(`modules/Collector.lua:366-368`). On its own reason, or on `"profile"`, it calls `EnableCapture`
or `DisableCapture` to match the switch. This is the Reconciler's two-target pattern
(`modules/Reconciler.lua:872-890`): `_settings` lives while the addon is up, and the rows are
registered only while the switch is on. Turning a switch off **unregisters** the rows, which is
not a draw gate (slash-commands-§7, anti-pattern #85, `docs/disabled-state.md:7-17`).

Module shape, identical for both (`Reputation` shown):
```
Reputation:Enable()          -- _settings target (any reason -> RefreshUpvalues; own/profile -> toggle); then EnableCapture if on
Reputation:EnableCapture()   -- RegisterRows("Reputation", NS.addon, "bus"); arm Seed deferral; _enabled = true
Reputation:DisableCapture()  -- UnregisterRows("Reputation"); ResetState()
Reputation:Disable()         -- DisableCapture(); _settings:UnregisterAllMessages(); _settings = nil
Reputation:ResetState()      -- baseline = {}, last = {} (reuse tables: wipe)
```
`core/LifecycleSetup.lua`: in `STAND_UP_STEPS`, put `method("Reputation","Enable"), method("Appearance","Enable")`
straight after `method("Collector","Enable")`. In `STAND_DOWN_STEPS`, put
`method("Reputation","Disable"), method("Appearance","Disable")` straight after
`method("Collector","Disable")` (`:178-200`). Update the comment on the
`UnregisterAllEvents` step to read "PLAYER_ENTERING_WORLD plus the Collector's three, the
Reputation owner's one, the Appearance owner's two (Retail) and Attribution's ten (six on Forever)".
Count the Attribution rows from the source at edit time.

TOC: add `modules\Reputation.lua` and `modules\Appearance.lua` straight after `modules\Collector.lua`
(`LootHistory.toc:127`). Row order becomes
`Attribution,AttributionOut,Collector,Reputation,Appearance,Reconciler`. On Forever `Appearance`
has no rows.

Perf (`core/PerfSetup.lua:63-69`): append `{ key = "repEvent" }` (Reputation:OnStandingChanged)
and `{ key = "appearanceEvent" }` (Appearance:OnSource*). Both modules take `local Perf = NS.Perf`
at load. The TOC position below `core\PerfSetup.lua` already holds.

---

## 6. Read side

### 6.1 Must change

| File : function | Change |
|---|---|
| `core/Ledger.lua:318-324` `RowThingKey` | Return nil unless `kind == "GOLD"` or `KIND_PREFIX[kind]` exists. Without this, an APPEARANCE row with an itemID raises in `ThingKey` (`:11-14`) inside `Database:Add`'s write hook (`modules/Rollup.lua:67-75`). **First task of M2.1** |
| `core/Database.lua:758-763` `matchLedger` | Apply the min-quality floor only when `r.kind == nil or r.kind == "ITEM"` (A7) |
| `core/Database.lua:1173-1176` Stats legacy gate | `dir == "IN" and (kind == "ITEM" or kind == "CURRENCY") and not HOLDER_MOVE_REASON[src]` |
| `core/Database.lua` Stats | New aggregates, filled in the same loop. `reputation = { rows, gained, lost, byFaction = { [name] = { i, o } } }` sums `quantity` per dir (REPUTATION rows). `appearances = { collected, removed, newLooks, byChar = { [char] = n } }` (APPEARANCE rows; byChar counts IN). Both are returned in the result table (`:1180-1206`). `accumulateLedger` stays as is, so kindIn/kindOut count them and rep or appearance OUT rows count toward lostCount, which is correct: they are losses |
| `core/Database.lua:846-862` `Export` | Append `factionID, repType, rank, standing, accountWide, sourceID, appearanceID, newLook` to the explicit copy |
| `core/Database.lua` | Add `Database:HistoryRow(i)`, which returns `historyStore()[i]` (for the coalesce identity check, §3.4) |
| `modules/Export.lua:100-107` `COLUMNS` | Append **after** `to`: `factionID`, `repType`, `rank`, `standing`, `sourceID`, `appearanceID`, `newLook` (the last one `r.newLook and "true" or ""`). Extend the comment at `:59-63`. `accountWide` is not exported as a column; it stays in Database:Export |
| `modules/Export.lua:297-322` `InsightsCSV` | New `emitProgress(row, stats)` called **after** `emitLedger`. It emits only when `stats.reputation.rows > 0` or `stats.appearances.collected + removed > 0`. Its rows are `row("Reputation Gained", faction, i)` and `row("Reputation Lost", faction, o)` (factions sorted by name), `row("Appearances", "Collected", n)`, `row("Appearances", "Removed", n)` and `row("Appearances", "New looks", n)` |
| `modules/AnalyticsLedger.lua:208` `KIND_LABEL` | Add `REPUTATION = "Reputation", APPEARANCE = "Appearances"` |
| `modules/Analytics.lua` | A new `PROGRESS` divider plus two sections, laid out **last** (after the ledger block) and hidden unless their data is present, mirroring the currency block's divider (`:231-244`, `:571-592`). The sections are "Reputation By Faction" (`AL.BackToBackRows` of `byFaction` i vs o, which is the shape "Gains Vs Losses By Kind" uses, `AnalyticsLedger.lua:241`) and "Appearances Collected By Character" (a bar section over `appearances.byChar`). The rep bars use the `sem.info` color |
| `modules/BrowserTable.lua:559-581` `OnEnter` | Two new branches. First, a REPUTATION branch **before** the itemLink branch: `NS.Compat.ShowAmountTooltip(self2, r.itemName, NS.SkinRGB("sem.info"), r.itemSubType or "Amount", NS.LedgerFormat.QtyText(r), "Right-click for options")`. Second, after the itemLink branch: `elseif r.itemID and NS.Util.RowKind(r) == C.Kind.APPEARANCE and GameTooltip.SetItemByID`, which owns the tooltip, calls `SetItemByID(r.itemID)` and sets `shown = true` |
| `modules/BrowserTable.lua:938-939` `PaintCell` | For `colKey == "item"` when `RowKind(r) == REPUTATION`, use `fs:SetTextColor(NS.SkinColor("sem.info"))` (A9). The quality cell is already blank for a nil quality (`:240`) |
| `modules/BrowserTable.lua:1058` `RowMenuItems` | `Blacklist item` is enabled only when `record.itemID ~= nil and NS.Util.RowKind(record) == C.Kind.ITEM`. "Show in Timeline" is disabled on its own once RowThingKey answers nil |
| `modules/BrowserTableTestData.lua:285-357` `BuildTestData` | After `holderMoves(out)`, append **fixed literal** rows that use no PRNG draws, so the existing stream stays byte-identical. The rows are three REPUTATION rows (Stormwind +668 QUEST, Booty Bay −25 OUT KILL, and on Retail Council of Dornogal +1250 KILL renown) and, where `C.FEATURE.appearances` holds, two APPEARANCE rows (one `newLook`, one OUT). Timestamps are offsets from the walk's own base time, and the characters come from the sample roster's first two |
| `modules/LedgerFormat.lua` | No change. `QtyText` already signs any non-GOLD kind (`:28-41`) |
| `docs/schema.md` | New "Reputation records" and "Appearance records" sections beside "Currency records" (`:202-216`). Add the settings rows to the `:263` table, and the new COLUMNS to F4 (`:532`) |

### 6.2 Works without change, verified

- The Type filter collects distinct `itemType` from the data (`modules/BrowserWidgets.lua:154-164`),
  so `Reputation` and `Appearance` appear once rows exist.
- Group by type and the Type and SubType columns read `itemType` / `itemSubType` (`modules/BrowserTableGroup.lua:47-51`).
- The Direction column, the glyph and `QtyText` work from `dir`/`kind`.
- The Wowhead link takes itemID or itemLink (`modules/Export.lua:33-44`). For REPUTATION rows it
  answers empty: they carry no itemID or link.
- The bound-state repair skips rows with no `bound` (`core/Database.lua:561`).
- `AL.HasLedger` turns on for a rep loss, which is intended: the loss is a real ledger fact (`modules/AnalyticsLedger.lua:22-25`).

### 6.3 Explicitly does NOT change

| Surface | Why |
|---|---|
| Holdings (`modules/Holdings.lua`), Scanner, Reconciler claims and `ThingAllowed` | Nothing is held. Rep has no container, and an appearance is a collection, not a holding (`modules/Holdings.lua:153-154`, `modules/Reconciler.lua:545-553`). There is no `claim()`, because an itemID claim would cancel the real item's diff row |
| Daily rollup and Timeline (`modules/Rollup.lua`, `modules/TimelineModel.lua`) | There is no close `c`. ThingKey and ParseThingKey only understand `i:`/`c:`/`g` (`core/Ledger.lua:16-21`), and rep's scale (thousands) would pollute the thing picker. With RowThingKey nil, `Rollup:OnWrite` returns (`modules/Rollup.lua:67-75`), and TestData's `rowFlows` skips the row (`modules/TestData.lua:164-178`) |
| `NS.SCHEMA_VERSION` (16) | The change is additive (§2.3) |
| The Collector's loot, currency and money paths | They are separate owners; the gate order there is untouched |

---

## 7. Per-client rows and register rows

`docs/ARCHITECTURE.md` per-client table (`:79-93`), a new row:

`| Appearances (`appearances`): the two TRANSMOG_COLLECTION_SOURCE_ADDED / _REMOVED event rows (owner Appearance), the Record appearances switch row, test mode's appearance sample rows, the simulator's appearance driver, world seeds and loot-scenario step, and the Insights "Appearances Collected By Character" section's data | `retail` | `core/Constants.lua` (C.FEATURE_CLIENTS), `modules/Appearance.lua` (the rows), `settings/Schema.lua` (row clients), `modules/BrowserTableTestData.lua`, `modules/SimWorld.lua`, `modules/SimDrivers.lua`, `modules/SimScenario.lua` |`

A second new row, which names the shape both clients share:
`| Reputation's faction kinds: renown, friendship, guild and paragon progress read where the client answers them; WoW Forever answers base standings only (API-gap detection inside one feature, clients-§3) | `both` | `core/Compat.lua` (FactionSnapshot), modules/SimWorld.lua (per-client faction seeds) |`

ARCHITECTURE: update the module map rows and the event-subscriptions table for both owners, plus
the Dispatch owner order everywhere it is quoted (search for `Attribution, AttributionOut, Collector, Reconciler`;
`core/Dispatch.lua:10-12` comment included).

`docs/disabled-state.md` "What stands down" (`:68-86`): fix the first row's counts to the
Collector's three, Reputation's one, Appearance's two (Retail) and Attribution's. Add a row:
`| The Reputation and Appearance owners: their private _settings targets, their capture rows and their in-memory baselines, coalesce and duplicate maps, plus the pending seed deferral | Reputation:Disable / Appearance:Disable, from NS.StandDown; NS.CancelDeferrals drops the seed |`.
State that a capture switch turned off unregisters, the same as the trackLedger precedent.

`docs/performance.md` and `docs/combat-path-sweep.md`: the census gets two rows
(`FACTION_STANDING_CHANGED`: one snapshot, a pure delta, at most one Add or Amend; nothing
allocated when unchanged. `TRANSMOG_*`: three or four Compat reads and one Add) and two bucket rows
(`repEvent`, `appearanceEvent`).

---

## 8. Test plan (characterization first)

Do the characterization in M2.1, **before** any capture code. Pin the current behavior that M2
must keep:
- `tests/test_ledger.lua`: add cases that `RowThingKey` answers `"i:123"`, `"c:5"` and `"g"` for
  today's kinds.
- `tests/test_stats.lua`: the legacy breakdowns of an ITEM/CURRENCY fixture are unchanged (record
  the current numbers, then assert them after the gate change).
- `tests/test_export.lua:76-83`: record the header (it is extended in M2.4).

New and updated cases:

| Suite | Cases |
|---|---|
| `tests/test_ledger.lua` | `RowThingKey` is nil for REPUTATION, and for APPEARANCE with an itemID. `RowKind` answers the stamped kind. `Database:Add` of an APPEARANCE row with an itemID does not raise, and RECORD_ADDED fires (red before the fix) |
| `tests/test_reputation.lua` (new; add to `tests/run.lua`) | `Delta`: base gain, base loss, a loss across a rank boundary (negative, right size), renown same-level, a renown level-up (`(t-s0)+s1`), a two-level jump, renown drop gives nil, paragon accrual at the cap, paragon reset gives nil, type change gives nil, unseeded gives nil, unchanged gives 0. Capture: a row's every field (§2.1); OUT dropped with trackLedger off; source QUEST from a quest stamp (CERTAIN, questID); KILL INFERRED in combat; OTHER out of combat; a fresh VENDOR stamp still gives OTHER; `Peek` leaves `lootWindow.left` and `fishingUntil` alone; source mute; coalescing (same faction/dir/source within 60 s amends: qty grows, one row, standing updated; a dir change, a source change or 61 s gives a new row); seed-only on first sight; reload (ResetState then Seed) writes nothing; the seed retries in combat; `ListFactions` expands collapsed headers and restores them in reverse (a mock records Expand/Collapse calls); secret factionID or name drops; no allocation on the unchanged path (collectgarbage count around 100 events) |
| `tests/test_appearance.lua` (new) | Retail: the row's every field (§2.2), `newLook` true/false, REMOVED gives OUT, duplicate within 5 s dropped, ledger-off drops OUT, source mute, KILL from a loot window via Peek (INFERRED), the APPEARANCE row bypasses the min-quality floor, the tooltip branch uses SetItemByID. Forever (`T.forever`): no rows in `NS.EVENT_ROWS`, no `settings.recordAppearances` widget, `C.FEATURE.appearances == false` |
| `tests/test_dispatch.lua:17-43, :108, :113` | SNAPSHOT adds `bus:FACTION_STANDING_CHANGED`, `bus:TRANSMOG_COLLECTION_SOURCE_ADDED` and `bus:TRANSMOG_COLLECTION_SOURCE_REMOVED`, with a comment that they were added by hand, as the bank cues were. Forever's `retailOnly` adds the two TRANSMOG rows. Owner order becomes `Attribution,AttributionOut,Collector,Reputation,Appearance,Reconciler`, and on Forever `...,Collector,Reputation,Reconciler`. Add a case: turning `settings.recordReputation` off removes `bus:FACTION_STANDING_CHANGED` from the live registrations, and turning it on restores it |
| `tests/test_client_shape.lua:145-148, :171` | `FEATURE_EVENTS.appearances = { owner = "Appearance", "TRANSMOG_COLLECTION_SOURCE_ADDED", "TRANSMOG_COLLECTION_SOURCE_REMOVED" }`; `FEATURE_WORD.appearances = "appearance"` |
| `tests/test_disabled.lua` | Covered by its registration survey. Add an assertion that the Reputation and Appearance `_settings` targets are gone after stand-down |
| `tests/test_panel.lua:185-192, :148, :361` | The Capture order includes `label("Record reputation")` after Record currency, then on Retail `label("Record appearances")`, then the picker. The labels are present. A toggle case on the `recordCurrency` template (`:579-583`) |
| `tests/test_profiles.lua:94,124` | The two keys reset and copy like `recordCurrency` |
| `tests/test_debug_coverage.lua:283-300` | Each new drop reason writes its `[Drop]` line only behind debug |
| `tests/test_stats.lua` | Rep and appearance rows do not enter byQuality/byType/byItem/totals.records; `stats.reputation` and `stats.appearances` values; kindIn/kindOut include the new kinds |
| `tests/test_export.lua:76-83` | The header gains the seven columns after `to`. A rep row's and an appearance row's CSV cells. Database:Export copies the new fields. `tests/export_golden.txt` is unchanged (no rep or appearance in its fixtures) |
| `tests/analytics_golden.txt` | Unchanged; the new block is hidden with no data. A new case renders the block when present (headers shown) |
| `tests/test_browsertable.lua:632-644` | Exempt REPUTATION/APPEARANCE from the itemID/vendorPrice asserts and assert their own shape instead. `:620-630` still byte-identical. RowMenuItems: Blacklist item disabled for APPEARANCE, Show in Timeline disabled for both. PaintCell uses `sem.info` for rep |
| `tests/test_sim_seam.lua` | `Unwrapped()` empty with the four new members. `ListFactions` is GUARDED (it never calls ExpandFactionHeader while active) |
| `tests/test_sim*.lua` (driver/scenario suites) | `D.Reputation` writes a session-only row with QUEST after a turn-in. A real FACTION_STANDING_CHANGED during a session stops it (`world`). After the stop, the baseline equals the live walk, and a following real event's delta is computed from live, not from simulated standings. `D.Appearance` is Retail only |
| `tests/test_perf.lua` + `tests/perf.lua` | Bucket list includes `repEvent`, `appearanceEvent`; a `repUnchanged` scenario pins zero allocation |
| `tests/test_compat_routing.lua:22-30` | Add BANNED `C_Reputation%.` and `C_TransmogCollection%.` outside `core/Compat.lua`, using `Compat.FactionSnapshot / ListFactions / AppearanceSource / IsNewLook` |
| `modules/Probe.lua` probe suite | `P.EVENTS` order matches `docs/forever-probes.md` |

Kit mocks: add `C_Reputation`, `C_MajorFactions`, `C_GossipInfo.GetFriendshipReputation(+Ranks)`
and `C_TransmogCollection` stubs. Put them in the addon's own `tests/` helpers, **not** in `tests/_kit/`,
which is the vendored payload (`tests/test_vendor_sync.lua`). If the kit already provides a
settable surface for them, use that.

The gate runs on every task (plan `## Gate`): both kit profiles at 0 failed, luacheck 0/0 through
`ka0s-bounded`, and the seeds pytest.

---

## 9. Docs and smoke

- `docs/settings-panel.md:51`: two bullets after Record currency. Update the row and Capture counts
  (the scout cites `:112`, `:117`; recount at edit time).
- `docs/data-flow.md`: a new section "Reputation and appearances" (events, Peek, delta, seed,
  coalescing, the trackLedger rule), plus the simulator interference table (`:306-354`).
- `docs/module-map.md`: the two modules.
- `docs/message-bus.md`: no new message (stated explicitly).
- `docs/debug.md`: the tags `Rep` and `Appearance` and the drop reasons
  (`secret`, `no-id`, `unreadable`, `unseeded`, `type-change`, `paragon-reset`, `renown-drop`,
  `unchanged`, `ledger-off`, `source`, `duplicate`).
- `docs/forever-probes.md`: the five probe events.
- `docs/smoke-tests.md`. New Retail checks: a quest turn-in gives a Reputation IN row with source
  Quest, and 3 kills give one coalesced Kill row. A loss (an Insights "Lost" bar) is checked where
  one can be had, for example Booty Bay by killing a Bloodsail pirate. `/reload` gives no new rows.
  Collecting an appearance gives an Appearance row with `newLook`. Turning Record reputation off
  stops new rows. Login and reload give no appearance burst. New check `FOREVER-<next>` (Client:
  WoW Forever): no Record appearances box, no Appearance Type value, and a reputation gain gives a
  Reputation row. It carries the word "appearance" (FEATURE_WORD). Update the Index row counts.
- `docs/test-cases.md`: regenerate.
- `docs/ARCHITECTURE.md`: §7 above.
- `CLAUDE.md`: no change (no icons added).

---

## 10. Task breakdown

Each task ends green with one commit. The ledger row is updated in the same commit, and EOL is
repaired after the commit (plan `## Gate`).

| Task | Contents |
|---|---|
| **M2.1** Kinds, gate, Compat reads | (a) Characterization tests (§8, first block). (b) The `RowThingKey` fix plus its red-then-green test. (c) `C.Kind` members, the two TYPE constants, `FEATURE_CLIENTS.appearances`, `REP_COALESCE`, `REP_SEED_RETRY`. (d) `Compat.FactionSnapshot`, `ListFactions`, `AppearanceSource` and `IsNewLook` in `core/Compat.lua`, with `ListFactions` GUARDED in SimSeam, and the test mocks. (e) `Attribution:Peek()` plus its tests. (f) The five probe events plus `docs/forever-probes.md`. (g) The ARCHITECTURE per-client rows, `FEATURE_WORD`/`FEATURE_EVENTS` entries, and the smoke FOREVER absence check (needed for green: `test_client_shape` fails once `appearances` is declared). (h) BANNED-read entries |
| **M2.2** Reputation capture | `modules/Reputation.lua` (pure `Delta`, the capture path, seed, coalesce, ResetState, Enable/Disable/EnableCapture/DisableCapture), the TOC line, lifecycle steps, the `repEvent` bucket, the `recordReputation` default and Schema row (the capture switch has to exist for the module to read it), the test_dispatch SNAPSHOT/order, `tests/test_reputation.lua`, and test_panel/test_profiles/test_debug_coverage for the switch |
| **M2.3** Appearance capture | `modules/Appearance.lua` (rows gated by `C.FEATURE.appearances`), the TOC line, lifecycle steps, the `appearanceEvent` bucket, the `recordAppearances` default and Schema row with `clients`, test_dispatch Retail/Forever, test_client_shape `FEATURE_EVENTS`, and `tests/test_appearance.lua` |
| **M2.4** Read side + sim | `matchLedger`, the Stats gate plus aggregates, `HistoryRow`, `Database:Export` fields, Export COLUMNS plus `emitProgress`, `KIND_LABEL`, the Analytics PROGRESS block, the BrowserTable OnEnter/PaintCell/RowMenuItems, test data rows, and the Sim providers/seeds/drivers/scenario steps/INTERFERENCE/Prepare/stop steps. All of it with tests (§8). If this commit grows too large, split it into M2.4a (read side) and M2.4b (sim) |
| **M2.5** Docs + review + push | All doc updates in §9 and §7 (disabled-state, performance, combat-path-sweep, data-flow, schema, settings-panel, module-map, debug, smoke, test-cases regen), then a review-pass workflow and its fixes, then push M2. Do not merge |

---

## 11. Deviations to flag

None of this design departs from the standard. These points sit near a rule and are recorded so a
reviewer does not re-raise them:

- **clients-§3**: `Compat.FactionSnapshot` tells renown, friendship and paragon apart by API
  presence. That is feature detection filling an API gap *inside* reputation, a feature both clients
  have, and it does not decide whether reputation exists. Appearances, which is a whole feature, is
  declared (`C.FEATURE_CLIENTS.appearances`) and gated at registration (clients-§4). RLF's
  `IsEventValid` switch (`Reputation.lua:229-236`) is **not** copied.
- **events-frames-taint / UI state**: `Compat.ListFactions` expands and restores the player's
  Reputation-panel headers, the same as the existing `Compat.ListCurrencies`
  (`core/Compat.lua:934-941`). It runs out of combat and is GUARDED under the simulator. This
  follows precedent and is not a new deviation.
- **Contingency only**: if the Forever probe rejects `FACTION_STANDING_CHANGED`, the
  `UPDATE_FACTION` row in §3.6 must be declared `clients = { "forever" }` with its own per-client
  table row. It is not a deviation as long as it is declared that way.

## 12. Open questions for the owner

None block the build. The two in-game facts below are verification gates, handled through the probe
and the smoke checks, with the follow-ups already designed:
1. Is `FACTION_STANDING_CHANGED` valid on WoW Forever? (§3.6; follow-up pre-designed.)
2. Does `TRANSMOG_COLLECTION_SOURCE_ADDED` burst at login or reload? (§3.5; follow-up: gate it on `NS.State.loginSettled`.)

The owner may want to overrule the architect's rulings A1 (holder = character), A2 (losses need
trackLedger) and A3 (60 s rep coalescing). Each one is a single constant or condition, so it is
cheap to flip.
