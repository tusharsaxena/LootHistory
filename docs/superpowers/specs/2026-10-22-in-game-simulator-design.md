# In-game simulator (`/lh sim`) — design spec

**Status:** built (LH-06 to LH-14 on `feat/2026-10-22-libka0s-issues-45-58`); in-client smoke SIM-1 to SIM-7 owed
**Date:** 2026-10-22
**Issues:** LootHistory#37 (this addon's simulator), LibKa0s#53 (the step panel), LibKa0s#54 (`LibKa0s-Sim-1.0`)
**Library:** LibKa0s v1.75.0, `LibKa0s-Sim-1.0` (Sim key 2.2.2: Sim minor 2, SimTimeline minor 2, SimPanel minor 2)
**Frozen.** This file records the design as decided for the 2026-10-22 run. It is not edited after the
fact; later changes go in a new spec. The requirements it was written from are the run bundle's
`inputs/req-lh-sim.md` (Ka0sAddonsCommonTasks, `docs/2026-10-22-LIBKA0S_ISSUES_45_58/`), and the
owner's binding rulings are that bundle's `inputs/OWNER_SCOPE.md` section C. Where the two differ,
the rulings win, and §11 lists each place they do.

---

## 1. Goal and the one principle

`/lh sim` runs the **real capture engine** against an invented world, solo and outside an instance,
so capture and ledger changes can be tested between live sessions.

- **Invented at the edges:** bags, bank, warband tabs, mail, auctions, the loot window, chat lines,
  encounters, keys, interaction frames, the hooked client calls and the player's own actions.
- **Real between the edges:** the self-line parsers, `Attribution` (stamp and consume), `Collector`
  (gate, record, claim), `Reconciler` (dirty, debounce, scan, plan, hold, commit), `Escrow`,
  `Ledger.PickReason`, `Holdings`, `Rollup`, the AH price cascade, and the History, Insights,
  Holdings and Timeline tabs.

**The principle.** The simulator never calls `Database:Add`, `Holdings:Apply*`, `Attribution:Stamp`
or `R:Write`, and never writes a source, reason or row. If a simulated row reads `AH_SOLD`, then
`Ledger.PickReason` decided it. `tests/test_sim_seam.lua` scans `modules/Sim*.lua` for those calls.

Test mode is the opposite (fixed preview data). The two exclude each other.

## 2. The library and the host

`LibKa0s-Sim-1.0` owns the generic half: the answer seam (`Sim:NewSeam`), the session (`Sim:New`:
start, refusal hook, two-phase stop, `Fire` through the host's `deliver`, `After` timers), the step
machine (step, run, pause, resume, restart, click-ahead, the host `gate`), the `/lh sim` verb grammar
(`RunVerb`) and the step panel, which is Sim-private (LK-11 outcome B). LootHistory owns everything
that touches its own data: the world, the providers, the drivers, the scenarios, the store swap, the
refusals, the real-event split and the marker.

**Host members never hang on the library instance** (OWNER_SCOPE C.4). LootHistory's fields live on
`NS.SimHost` (the world, counters, the seeded alt, the scenarios, the panel fields, the last stop) and
`NS.SimStores` (the session stores).

## 3. The host contract, and where LootHistory meets it

| Point | The contract | Met by |
|---|---|---|
| H1 | Every client read the simulator answers is an `NS.Compat` member read at call time | `core/Compat.lua` gained `NumLootItems`, `LootSourceGUID`, `Zone`, `PlayerMapID`, `InInstance`, `InGroup`, `PlayerInCombat`; read-side hooks install through `HookSecure` / `HookSecureMember` (LH-06). `tests/test_compat_routing.lua` |
| H2 | `NewSeam` runs straight after the Compat file; `Unwrapped()` is empty after load | `core/SimSeam.lua`, the TOC line after `core\Compat.lua` with a LOAD-BEARING comment (LH-10). `tests/test_sim_seam.lua` |
| H3 | One `deliver` reproducing the client's handler set and order for any event name, pseudo-events included | `NS.DeliverAll` over `NS.EVENT_ROWS` / `NS.HOOK_ROWS`, `hook:<name>` for a hook (`core/Dispatch.lua`, LH-07). `tests/test_dispatch.lua` |
| H4 | Session-only storage for every capture-path write, and a byte-identical before/after test | `NS.SimStores` and one accessor per store (LH-09); the swap in `modules/Sim.lua` (LH-10). `tests/test_sim_store.lua` |
| H5 | `refusal` covers stood-down, test mode and the world rules; test mode refuses while a simulation runs | `NS.SimHost.Refusal` (`modules/Sim.lua`) and `testModeRefusal` (`modules/BrowserTable.lua`). `tests/test_sim_session.lua` |
| H6 | `Stop("standDown")` is the first stand-down step; host reasons stop it | `call("SimStop")` first in `STAND_DOWN_STEPS` (`core/LifecycleSetup.lua`); `NS.OnProfileEvent` stops with `profile`; the world watch stops with `group`, `instance`, `combat`; real interference with `world` |
| H7 | One feature-verb row, `sim`, refused while disabled; no launcher entry | The `sim` row in `settings/Schema.lua`'s `NS.COMMANDS`, not in `LIVE_WHILE_DISABLED` (LH-13) |
| H8 | Preview-mode marker, a diagnostics `sim` section, a `Sim` debug tag | `SIMULATION` badge, strip and footer (`modules/Browser.lua`), the `sim` section (`modules/Diagnostics.lua`), the `Sim` tag (LH-10, LH-13) |
| H9 | Degradation stub and a surface-parity case | `NS.SimHost.NewSeamStub` / `NewSimStub` (`core/SimSeam.lua`); `tests/test_surface_parity.lua` |
| H10 | Panel position | **Overridden by C.11:** the position is session-only, held in the library instance's memory; no `store`, no window-state key, nothing written to SavedVariables |

## 4. The world (`modules/SimWorld.lua`)

`NS.SimHost.World.New(fixture, seed)` builds one session's world deterministically from the
scenario's fixture: bags, bank, warband tabs, worn gear, purse and warband gold, currencies, inbox,
the staged send-mail, owned auctions, the loot window, the situation (party instance, keystone, zone,
subzone, map), simulated combat, the trade partner, the quest and spell targeting. It never mirrors
the player's real bags (that would make the end-to-end suite non-deterministic and show real items
inside a simulated history).

- **Items are real Midnight ids**, so item, bind and price reads answer for real. One link carries
  bonus ids (read back through `Item.BonusIDsFromLink`) and one item is the uncached one whose rows
  fall back to the link's own name and color.
- **A simulated own alt**, `Simalt-<realm>`, is seeded into the session holdings so
  `Attribution:IsOwnAlt` answers true for the alt mail and alt trade steps.
- **Providers.** The file registers one provider per world read on `NS.SimSeam` at load: 23 keys
  (`World.PROVIDED`). Item, spell and currency reads and `PlayerClassFile` answer live (the simulated
  player is the real player). `InInstance`, `InGroup` and `PlayerInCombat` have no provider and are
  read only through `seam:Live`.
- **Guarded.** `ListCurrencies` is the one Compat member that changes client state (it expands and
  collapses Currency-tab headers). While a simulation runs it answers only the world's list and never
  reaches `C_CurrencyInfo.ExpandCurrencyList`.

## 5. Drivers (`modules/SimDrivers.lua`)

One driver per capture event and hooked client function. Each changes the world first, the order the
client uses, then fires through `NS.Sim:Fire` with the client's payload shapes: the 17-argument chat
lines written from the parser's own globals (`Util.LootGlobals`, `Util.CurrencyGlobals`), the loot
window over a Creature, GameObject or Item GUID, encounters, keys, zone changes, casts (disenchant
13262, milling, prospecting), quests, trades, interaction frames, mail, and the bag, money, currency,
bank, auction, transfer and regen bursts.

**Hooks are played, never called.** A hook driver fires `hook:<name>` with the real argument shapes;
`deliver` walks `NS.HOOK_ROWS`. No `modules/Sim*.lua` file calls a hooked client function (a static
test). Drivers whose post-hook reads the pre-call slot (use, destroy, take mail, send, post, craft,
quest reward) fire the hook before landing the effect; buy, buyback, repair and auction buy land the
effect first.

## 6. Scenarios and the ledger gate (`modules/SimScenario.lua`)

| Scenario | Steps (summary) | What the engine must write |
|---|---|---|
| `loot` | Kill (two loot lines, chat before bags and bags before chat, a poor drop, money), lockbox, quest turn-in | KILL rows with the npc id, gold IN KILL, CONTAINER and QUEST rows, the poor item only as a diff row, no duplicate |
| `key` | Enter the dungeon, key start, two pulls and kills in simulated combat, key completed, end chest, bonus roll, roll won, leave | KILL rows with the encounter, MPLUS chest rows with the keystone, BONUS_ROLL and ROLL as CERTAIN, the currency row, the key context cleared |
| `vendor` | Merchant open, sell 3, buy, destroy, repair, close, disenchant | item OUT SELL with gold IN SELL, item IN VENDOR with gold OUT BUY, OUT DESTROY, gold OUT REPAIR, DISENCHANT materials and OUT DECONSTRUCT |
| `ah` | Mailbox check, post 3, buy, later one sold and one expired, mailbox: take the sale money, the won and the expired item | MOVE bags to auctions, OUT AH_POST_FEE and AH_BUY, OUT AH_SOLD with gold IN AH_SOLD, the won item IN AH, the expired item back as an own-origin MOVE |
| `bank` | Bank open (genesis), deposit 2 stacks, warband bank open, deposit item and gold, withdraw 1, close | intra-holder MOVE rows, WARBAND_DEPOSIT and WARBAND_WITHDRAW pairs, the warband's genesis |
| `social` | Mailbox, send to the alt, trade with the alt, trade with a stranger, currency transfer | OUT ALT_MAIL, ALT_TRADE both ways, TRADE_GIVE and IN TRADE, CURRENCY_TRANSFER pair rows |

The `vendor`, `ah`, `bank` and `social` scenarios refuse while `settings.trackLedger` is off; `loot`
and `key` run on the Collector either way.

**The gate** (`NS.SimHost.Gate`) is the descriptor's `gate`: closed while the Reconciler has work in
flight (`R._pending`, `R._holdSince`, or `R.deferred` while the simulated world is not in combat), so
a step never lands on a half-classified change and every scenario ends settled. `step` on a closed
gate prints the settling line and does not advance; `run` polls.

**The step delay** is a fixed constant, `SIM_STEP_DELAY = 1.5` s in `modules/Sim.lua`, never a schema
row (C.11).

## 7. Saved data stays untouched

`NS.SimStores = { history, holdings, daily }`, `nil` while live. The capture paths reach each store
through one accessor (`Database`'s local `historyStore()`, `Holdings:Store()`, `Rollup:Store()`) that
answers the session table first. The Reconciler's coalescing check reads its amend target through
`Database:History()`. Retention, purge, the storage summary, the bound repair, the migrations and the
rollup's seed and prune name the saved stores and stay live.

**Destructive surfaces refuse while a simulation runs**, each with
`<what> is not available while a simulation runs.` (`NS.SimBlocks`): `/lh purge`, the settings
panel's Purge button and the purge confirm, the ledger reset offer and both its confirms, Forget this
character, **the row menu's Delete** (C.12, over the requirements' "allowed"), and a retention change
that would prune (the kept value is written back).

**Session genesis.** The start runs `R:LoginScan()` with the seam on. The session holdings are empty,
so the first pass is a silent genesis and writes no rows.

## 8. Session

**Refusals, in order:** stood down (the collection's refusal-by-hold line); test mode on; real
combat; any instance; a real group; a real interaction frame open; the ledger settling; the login
deferrals not yet run (`NS.State.cleanupDone` and `NS.State.loginSettled`); a ledger scenario with
`trackLedger` off. The library refuses an unknown scenario and a second session first.

**Start:** the world, counters and session stores; `R:ResetState()` and
`Attribution:ResetContexts()`; `NS.RealEventFilter` set; the private world-watch target; the session
genesis; Browser `OnDatasetChanged`; `ready()`. The library prints
`Simulation started (<scenario>): nothing is saved; your history and holdings are not touched.`

**Real input during a session** (`NS.SimHost.OnRealEvent`, the `NS.RealEventFilter`):

- *Interference* stops with reason `world`, then the event runs live into the saved stores: the
  player's own loot, currency or money line, `LOOT_OPENED`, `ENCOUNTER_START`, `CHALLENGE_MODE_START`,
  `QUEST_TURNED_IN`, `TRADE_ACCEPT_UPDATE`, `MAIL_SEND_SUCCESS`,
  `PLAYER_INTERACTION_MANAGER_FRAME_SHOW`, and any real hook call.
- *Setup* (`ADDON_LOADED`) is delivered live without a stop.
- *Absorbed*: everything else (bags, money, currency, equipment, bank, auctions, casts, another
  player's chat line). The stop's drift scan sees what it changed.
- *World watch* (its own bus target, because the shared one binds `PLAYER_ENTERING_WORLD`):
  `GROUP_ROSTER_UPDATE` stops with `group` when the player is in a real group,
  `PLAYER_ENTERING_WORLD` / `ZONE_CHANGED_NEW_AREA` with `instance` when in a real instance,
  `PLAYER_REGEN_DISABLED` with `combat`.
- *Lifecycle*: the stand-down (`standDown`, first step), a profile switch, copy or reset (`profile`),
  and `/reload` or logout (the session is never saved).

**Stop** (the library's two-phase stop, then the host's `OnStop` steps, each isolated): cancel the
Reconciler's flush and recheck fuses (`NS.CancelDeferral`), reset the Reconciler and the attribution
contexts, release the session stores, drop the real-event filter and the world watch, schedule a real
`R:LoginScan()` one second out unless standing down (what really changed meanwhile becomes
`UNTRACKED` drift), announce (Browser, `HISTORY_CHANGED`, `HOLDINGS_CHANGED` per session holder
through `R:AnnounceHolders`), record the last stop, and write one `[Sim]` line.

## 9. UI

- **Panel.** The library's step panel. LootHistory supplies only presentation fields
  (`NS.SimHost.PANEL`, `modules/SimPanel.lua`): the title `Ka0s Loot History - Simulation`, each
  step's label, a tooltip naming what the step injects and, once it has run, the rows it recorded, the
  Start and Stop tooltips, `anchorTo` (the History window while shown, so the panel docks beside it)
  and the `confirm` done mark. No `button`, `tooltip` or `store` (C.7, C.11).
- **Marker** (preview-mode). While a session runs the History window's title badge reads
  `SIMULATION` in cyan, the test-mode strip reads
  `SIMULATION: an invented world drives the real capture; nothing is saved. /lh sim stop ends it.`,
  and the footer leads with `Simulating: <scenario> · step k/n`. A Sim listener repaints them on every
  transition.
- **Diagnostics.** A `sim` section: active, scenario, step k/n, events and hooks fired, session rows
  and holders, the last stop, the seam's wrapped-key count and the guarded keys.
- **Debug.** A `Sim` tag, gated at the call site.
- **No launcher entry and no key binding** (C.11).

## 10. Slash surface

One `NS.COMMANDS` row, `sim`, a feature verb: refused with the disabled line while the addon is off.
The grammar is the library's `RunVerb`: bare `/lh sim` (status, usage, panel), `start <scenario>`,
`run`, `step`, `pause`, `resume`, `restart`, `stop`, `status`, `panel`. LootHistory adds one host
verb, `loot [n]` (1 to 10, default 3): n self-loot lines from a kill, through the drivers. On a
library-less install `NS.Sim` is the inert stub and the verb answers the library-absent line.

## 11. Where the rulings override the requirements

| Requirements said | Ruling (OWNER_SCOPE C) | Built |
|---|---|---|
| Row-menu Delete allowed during a simulation | C.12: refused | `NS.SimBlocks("Delete")` in the row menu |
| Panel position remembered in the profile's window state (H10) | C.11: session-only | No `store`; nothing written |
| A configurable step delay | C.11: a fixed constant | `SIM_STEP_DELAY = 1.5` |
| Possibly a launcher entry | C.11: slash-only, no launcher entry, no key binding | None |
| Host fields on the library instance | C.4: a host table | `NS.SimHost`, `NS.SimStores` |
| A panel button and tooltip override | C.7: the library's own | None passed |

## 12. Tests

`tests/test_compat_routing.lua`, `test_dispatch.lua`, `test_sim_seam.lua`, `test_sim_session.lua`,
`test_sim_world.lua`, `test_sim_drivers.lua`, `test_sim_e2e.lua` (the DW-90 regression: every
scenario by step and by run, against the mock's real solo answers, with its pinned rows and no
duplicate), `test_sim_store.lua` (byte-identical saved stores for all six), `test_sim_panel.lua`
and `test_sim_slash.lua`, plus cases in `test_disabled`, `test_diagnostics`, `test_surface_parity` and
`test_profiles`. In-client checks are SIM-1 to SIM-7 in `docs/smoke-tests.md`, owed to the owner.

## 13. Known limitations

- **The real clock.** A simulation runs on `time()` / `GetTime()`, so the Reconciler's debounce,
  claim wait and settle hold take real seconds, and `run` waits on them.
- **Items must be cached for full names.** The fixture's item reads answer live; an item the client
  has not cached falls back to the link's own name and color until it is.
