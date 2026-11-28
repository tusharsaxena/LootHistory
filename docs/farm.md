# Farm mode

Farm mode (#39) times a farming run and tallies what it earned: money, items at vendor and AH value,
currencies, the activity behind them (mobs, nodes, fish, quests, containers) and what the run cost.
The design is `docs/superpowers/specs/2026-11-27-39-farm-mode-design.md`, with the owner's decisions
in `docs/superpowers/plans/2026-11-27-tooltip-toasts-farm.md` (D15 to D23, D26, D27). This page is
the runtime account: where a session lives, how its clock moves, how a reload, a logout or a crash
ends it, what it counts and where each count comes from, how big it gets, and what the simulator
and test mode do with it.

| File | Role |
|---|---|
| `modules/FarmModel.lua` | Pure: every rule over a session table (the clock, the tallies, the packed log, totals, rates, trims, best per zone, the activity lines, the formatters). No client call, no bus. |
| `modules/Farm.lua` | The runtime: store routing, registration, the edges (start, pause, resume, finish, suspend, restore), the gain and cost receivers, the loot-window notifications, the idle ticker, the price pass and `FARM_CHANGED`. |
| `core/CompatFarm.lua` | The client reads farm mode adds: `LootSourceGUIDs`, `IsPlayerAFK`, `QuestTitle` and `HookLogoutFamily` ([compat-layer.md](compat-layer.md)). |
| `modules/FarmList.lua` | The virtualized list the Details window and the sessions list draw. |
| `modules/FarmPanel.lua` | The companion panel (`LootHistoryFarmPanel`) and the docked sessions list (`LootHistoryFarmSessions`). |
| `modules/FarmDetails.lua` | The Details window (six tabs) and the summary shown after a manual finish. |
| `modules/FarmTab.lua` | The History window's Farm tab, the shared row actions and the rename and delete popups. |
| `modules/FarmTestData.lua` | Test mode's six sample sessions. |
| `settings/SchemaFarm.lua`, `settings/PanelFarm.lua` | The Farm settings page: 21 rows, General 6 and Activity 15 ([settings-panel.md](settings-panel.md#the-farm-page)). |

## The store and a session

`db.global.farm` is account-wide recorded data, keyed by character (`NS.Util.PlayerKey()`):

```lua
db.global.farm[charKey] = { active = <session>|nil, sessions = { <session>, ... }, nextId = 1 }
db.global.farmKeep = 100     -- sessions kept per character; 0 keeps all (row settings.farm.keep)
```

Each character has at most one open session (`active`) and a list of finished ones, oldest first.
Ids are unique within a character only. A session carries its own shape stamp, `v = 1`, so a later
reshape can migrate by `v` without a `schemaVersion` step; the store itself is additive (`farm = {}`
in `defaults/Global.lua`), so no migration was owed for it. The full field list is in
[schema.md](schema.md#the-farm-store).

`Farm:LiveStore()` is `db.global.farm`. `Farm:Store()` is where writes go: the simulator's
`NS.SimStores.farm` while a simulation runs, else the live store. `Farm:ActiveStore()` is what the
lists read: test mode's `NS.State.testFarm` while test mode is on, else `Store()`. `Farm:Active()` is
read-only (`Store()[me].active`); only `Farm:Mine()` creates a character's entry, so a read never
writes saved data.

**Registration follows the store.** `Farm:Reconcile()` runs after every edge. With no open session
the farm session holds no registration at all: no row, event, message, hook or timer, and
`NS.GainFeed._farm` is nil. With one open (and the addon up), `goLive` registers the three event
rows (owner `Farm`: `ZONE_CHANGED_NEW_AREA` and `PLAYER_DEAD` on `Farm.__ev`, `PLAYER_FLAGS_CHANGED`
for `player` on `Farm.__unitFrame`), the four lifecycle events (`PLAYER_LOGOUT`, `PLAYER_CAMPING`,
`PLAYER_QUITING`, `LOGOUT_CANCEL`) straight on `Farm.__ev`, the `Ka0s_LootHistory_Gain` receiver, the
`Database:OnWrite` cost hook, `GainFeed:SetFarm(C.FARM.GAIN_KINDS)` and the idle ticker. The
lifecycle events are not capture rows: a real logout must reach them while a simulation runs, and the
simulator's real-event filter absorbs every `NS.Deliver` row but the toasts'.

## The clock (F2, F3)

A session's time is `activeSec` (banked running seconds) plus, while running, the seconds since
`runningSince`. Every stamp is a `time()` epoch, because `GetTime()` restarts on a reload. Paused time
never counts, and a finished session's paused seconds are `(endedAt - startedAt) - activeSec`.

- **Manual pause** (`/lh farm pause`, the panel's Pause): the clock stops and gains are dropped until
  Resume. Costs still count (F2). Pausing an idle or AFK pause turns it into a manual one.
- **Idle** (F2, D16): every `C.FARM.IDLE_TICK` (30 s) the ticker stamps `lastSeen`. A running session
  with no gain for `idleMinutes` (default 5, 0 is off) pauses `idle`, banked back to the later of
  `lastGainAt` and `runningSince`, so the idle minutes leave the clock. The ticker is a self-re-arming
  `NS.After` chain that re-arms only where `C_Timer.NewTimer` exists (headless `NS.After` runs straight
  through).
- **AFK** (F3): `PLAYER_FLAGS_CHANGED` for `player` reads `Compat.IsPlayerAFK()`. AFK pauses a running
  session at that moment when **Pause when AFK** is on; clearing the flag resumes an AFK pause. A nil
  answer (secret or unknown) changes nothing.
- **An idle or AFK pause resumes on the next gain**, which is tallied first. A manual pause does not.
- **Stand-down**: `Farm:Disable` pauses a running session `standDown`, and the stand-up resumes it. A
  session already paused keeps its reason.
- Rates are per active hour and read `—` under `C.FARM.MIN_RATE_SEC` (60 s).

## Ending a session: finish, logout, reload, crash (F5, F6)

**Finish** (`Farm:Finish(reason, at)`): the last price fill, then `FarmModel.Close` banks the clock,
stamps `endedAt` and `endReason` (`manual`, `logout` or `stale`), sets `primaryZone` (the zone with
the most time, a tie to the first seen), names the session after it, snapshots `totals`, trims the
log to `LOG_CAP` and drops the runtime fields. The session goes onto the saved list and the list is
trimmed to `farmKeep`. **A session with an empty log is discarded** (F6) and the chat says
`farm session discarded: nothing was gained.`; any log line, a pause line included, keeps it. Only
a manual finish (the verb, the panel's Finish, the Start or finish key binding) opens the summary.

**The logout intent.** `NS.State.farmLogoutIntent` is a `GetTime()` stamp, held for
`C.FARM.INTENT_TTL` (30 s, the logout countdown with room):

- set by post-hooks on `Logout`, `Quit` and `ForceQuit`, and by `PLAYER_CAMPING` and `PLAYER_QUITING`;
- cleared by post-hooks on `CancelLogout`, `ReloadUI` and `C_UI.Reload`, and by `LOGOUT_CANCEL`.

`Compat.HookLogoutFamily` installs the hooks once per client session at the first `Farm:Enable`,
each presence-gated through `Compat.HookSecure` / `HookSecureMember`; each body returns while stood
down, because a `hooksecurefunc` cannot be removed. The Retail routes are cited at
wow-ui-source@ab5cb850: `/logout` calls `Logout()`, `/quit` calls `Quit()`, `/reload` calls
`ReloadUI()` (`Blizzard_ChatFrameBase/Shared/SlashCommands.lua`), the game menu rebuilds its Log Out
and Exit callbacks on every show (`Blizzard_GameMenu/Shared/GameMenuFrame.lua`), the QUIT pop-up
calls `ForceQuit` or `CancelLogout` and the CAMP pop-up's Cancel calls `CancelLogout`
(`GameDialogDefs.lua`). On WoW Forever every symbol is present (the kit's Forever export), but no
Forever interface source was available to cite the routing (spec D-4), so smoke check FOREVER-22
verifies it in game. The events are the second path either way.

**`PLAYER_LOGOUT`** acts on the live store only, and returns while a simulation runs (the live
session is then never written, and the next load handles it through rule 2 below). With a fresh
intent the session is finished as `logout`. Without one it is **suspended**: the clock is banked,
`resumeOnLoad` and `wasRunning` are set, `lastSeen` is stamped. The seconds of a reload or a
reconnect stay off the clock.

**Restore** runs once per client session, at the first stand-up. For this character's open session:

1. Suspended (`resumeOnLoad`): resumed if it was running.
2. Still running (no clean logout: a crash, Alt-F4, a disconnect): banked to `lastSeen`, then resumed.
3. Paused: stays paused; a `standDown` pause resumes.

In each case a session last seen more than `C.FARM.STALE_SEC` (30 minutes) ago is instead finished as
`stale` at its `lastSeen` (F5), with the chat line
`farm session from <day> was left open; it has been finished and saved.` A session belongs to its
character, so an open session on one character survives playing another and is restored or closed
when its character logs in.

## What a session counts

**Gains** arrive on `Ka0s_LootHistory_Gain` from the pre-gate gain feed (`modules/GainFeed.lua`), so
they count whether or not History recorded a row: below the minimum quality, a muted source or a
blacklisted item still counts. `FarmModel.ApplyGain` reads the payload's fields
([message-bus.md](message-bus.md)):

| Kind | Counted when | What it adds |
|---|---|---|
| `ITEM` | `IN`, an id, a farm source (F4) | the item's quantity and source, `activity.items`, its quality; the per-unit vendor and AH price from the gain's row, or later from the price pass |
| `GOLD` | `IN`, a farm source | copper by source |
| `CURRENCY` | `IN`, an id, a farm source | the currency's quantity and source, `activity.currency` |
| `REPUTATION` | an id | the signed delta by faction (`OUT` subtracts) |
| `XP` | always | experience |
| `SKILL` | a new rank | the line's lowest and highest rank seen |
| `APPEARANCE` | `IN` and a new look (Retail) | `activity.looks` |

**The farm sources** (F4, `C.FARM.GAIN_SOURCES`): Kill, Container, Mythic+, Gathering, Fishing, Quest,
Bonus Roll, Roll and Other, and Other only from a chat line (a holdings-diff gain with no line is not
farmed). Vendor, mail, auction house, trade and every ledger reason never count. A Quest item, money
or currency gain also adds a quest reward.

**The price pass** (F7, F8): an item whose gain carried no price is queued. One coalesced
`NS.After(C.FARM.PRICE_DELAY)` pass prices up to `C.FARM.PRICE_BATCH` (20) queued items from
`Compat.GetItemExtras` and the AH cascade, re-arms instead in combat, keeps the first known price, and
runs once more at Finish. AH value falls back to the vendor price for an item with no AH price.

**Activity from loot windows, containers and quests.** Attribution owns `LOOT_OPENED` and
`QUEST_TURNED_IN`, so it tells the farm session directly, after it classifies the window and only
while `NS.Farm._live` is set ([data-flow.md](data-flow.md)):

- a fishing window counts a fish, and a gathering window (a node inside a Herb Gathering or Mining
  cast's `C.GATHERING_TTL`, ruling F1) a node, one per window, so each tap of a multi-tap node counts;
- a kill window counts each distinct corpse: every slot's `LootSourceGUIDs` pairs, so an AoE loot of
  three corpses counts three, and a corpse seen before (a skinning window on it) counts nothing. The
  corpse set is remembered across a reload in a ring of `C.FARM.MOB_RING` (256) GUIDs;
- a container window counts a container, except an Item window that follows a bag item the container
  hook already counted (within `C.CONTAINER_TTL`); a GameObject chest counts as one;
- a quest turned in counts a quest and logs its title (`Compat.QuestTitle`).

These stamp `lastSeen` but never `lastGainAt`, so they do not hold off the idle pause. **Zones** and
**deaths** come from the session's own rows: a zone change banks the time spent in the old zone and
logs the new one; a death is counted even on a manual pause, since it is not a gain.

**Costs** (D19) come from a `Database:OnWrite` hook over the rows History writes: this character's
`OUT` gold under `REPAIR`, `BUY` or `AH_POST_FEE`, and currency spent under `BUY`. The hook adds the
write's `delta`, never the row's quantity, because the Reconciler amends a row inside its coalesce
window. A repair paid from the warband bank has the holder `§warband` and does not count. Costs count
paused or running. **Costs need ledger capture**: with **Track holdings and losses** or **Record
gold** off, no loss row exists, so the Costs line reads `n/a (needs ledger capture)` and net equals
gross.

## Storage and caps

The log is one packed string per line, `<t>|<k>|<fields>`, `t` the seconds since the start; a `|`
inside a free-text field becomes `/`. Thirteen kinds round-trip through `FarmModel.Pack` /
`FarmModel.Unpack`. While open the log is trimmed by `C.FARM.LOG_BATCH` (100) oldest lines once it
passes `LOG_CAP + LOG_BATCH` (2,100), counting them in `logDropped`, and Finish trims it to exactly
`LOG_CAP` (2,000). Totals never come from the log, so a trim changes no total.

`Farm.EstimateBytes(s)` is `256 + 60·log lines + 90·items + 40·(currencies + costs + zones)`, about
110 KB for a full log, and a one-hour session writes a few hundred lines. `Farm:StorageStats()` sums it
over every character's sessions, open ones included, and the General page's storage readout prints
`Farm sessions: N (~X)` under the history line.

**The keep cap** (D18) is account-wide, `db.global.farmKeep`, default 100, 0 keeps all, and
reset-exempt: the Farm page's Defaults and *Reset all settings* leave it. Each finish trims that
character's oldest sessions past the cap. Lowering the cap below what a character holds asks first
(`KA0S_LOOTHISTORY_FARM_TRIM`); Cancel puts the last confirmed value back.

## The simulator and test mode

**The simulator** (`modules/Sim.lua`) swaps `NS.SimStores.farm = {}` in at its start and out at its
stop; each swap calls `Farm:OnStoreSwapped()` (Reconcile, then `FARM_CHANGED("store")`). During a
simulation `Store()` is the session store, so a live open session is never written and its idle
ticker is down; `/lh farm start` opens a simulated session that tallies the scenario's gains, costs
and loot windows and is dropped unsaved at the stop. The panel shows it with the cyan Sim mode strip
(the minimized panel wears the title badge instead). Farm's three event rows are absorbed by the
simulator's filter, so the simulated world's deliveries reach it through `NS.DeliverAll`.
`tests/test_sim_store.lua` pins the saved `db.global.farm` byte-identical across every scenario, and a
sim session tallying exactly the gains the feed sent.

**Test mode** publishes `NS.State.testFarm = NS.FarmTestData.Build(time())`: six finished sessions over
the History sample's characters, in Isle of Dorn three times, the Ringing Deeps twice and Hallowfall
once, each with 40 log lines, built from a fixed seed so two builds for one time are equal. The Farm
tab and the sessions list read it through `ActiveStore()`; nothing writes it, so Rename and Delete
refuse with `test mode shows sample sessions; nothing to rename or delete.` The panel never shows it:
it reads `Store()` and always shows the live (or simulated) session. Test mode ends at combat start,
which clears the sample with it.

## Where to look next

- The UI surfaces, their layering and tooltips: [ARCHITECTURE.md](ARCHITECTURE.md#frame-layering),
  [ARCHITECTURE.md](ARCHITECTURE.md#tooltip-placement) and [browser.md](browser.md) for the Farm tab.
- The `/lh farm` verb and the key bindings: [slash-dispatch.md](slash-dispatch.md),
  [ARCHITECTURE.md](ARCHITECTURE.md#the-show-window-key-binding).
- Stand-down: [disabled-state.md](disabled-state.md). Perf buckets `farmGain` and `farmWindow`:
  [performance.md](performance.md). The event census: [combat-path-sweep.md](combat-path-sweep.md).
- The in-game checks: [smoke-tests.md](smoke-tests.md#farm-mode).
