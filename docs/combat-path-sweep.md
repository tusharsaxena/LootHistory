# The combat-path sweep

The committed evidence behind this addon's `performance-§12` no-combat-path exemption. The
exemption itself, and the criteria it rests on, are on [performance.md](performance.md) and in the
register row in [ARCHITECTURE.md § Documented deviations](ARCHITECTURE.md#documented-deviations).
**Re-run the sweep before trusting this page**: a new hit that can run while the player is fighting
is the change that ends the exemption.

## Why `CHAT_MSG_LOOT` stays inside criterion (a)

**(a) — no combat path.** The addon owns **no `OnUpdate` handler and no repeating ticker**, and no
event handler doing more than occasional work while the player is in combat. The second half of that
is affirmed here explicitly rather than left to be read off a table, because it is the one place
criterion (a) could plausibly fail: `CHAT_MSG_LOOT` fires mid-fight, and on a line it keeps it does
a `C_TooltipInfo` tooltip build (`Compat.ScanBound`) and a `pcall` into every installed pricing
addon. It does not fail, and the reason is in the code rather than in the adjective —
`Collector:ShouldRecord` (`modules/Collector.lua:129`) runs **before** any of that work and returns
at `:135`, so every line the filters drop, which on the shipped rare-and-above default is nearly all
chat loot traffic, costs a pattern match and a threshold comparison. What reaches the tooltip build
is a few kept items per boss kill, not a few per frame. The whole-repo sweep below is the rest of
the evidence; the claim without it is an assertion.

## The sweep — `RegisterEvent` / `SetScript("OnUpdate"` / `C_Timer`

Whole-repo, excluding `libs/`, `tests/_kit/` and `tests/`. Regenerate with:

```sh
grep -rn "RegisterEvent\|RegisterUnitEvent" core modules settings defaults locales
grep -rn 'SetScript("OnUpdate"' core modules settings defaults locales
grep -rn "C_Timer\|NewTicker" core modules settings defaults locales
```

**`OnUpdate` handlers: none. Repeating tickers: none.** The second grep returns zero lines, and
`NewTicker` appears nowhere in the third's output.

**Game events: fifteen registrations, fifteen rows.** The first grep returns **thirty-two** lines;
seventeen of them are not registrations: the twelve lines of Core's per-event helper bodies in
`core/CoreSetup.lua` (the degraded stub at `:153-162`, the live wrappers at `:237-251`; see
[ARCHITECTURE.md § Event subscriptions](ARCHITECTURE.md#event-subscriptions)),
`core/LifecycleSetup.lua:111`, the guard above the call, `modules/Attribution.lua:407-408`, the local
helper the nine bus events go through, and `modules/Attribution.lua:423-424`, the pattern names inside
a comment. The rows are in the order the grep prints them, so the two can be held side by side.

| Event | Registered at | Work done per fire |
|---|---|---|
| `PLAYER_ENTERING_WORLD` | `core/LifecycleSetup.lua:112` | Handled by `addon:OnEnterWorld` (`core/LootHistory.lua:75`). Once per session — latches `NS.State.cleanupDone`, then returns. Schedules the two one-shot timers below. |
| `CHAT_MSG_LOOT` | `modules/Collector.lua:229` | **The only in-combat handler that does real work, and it does it only past the filters.** Every line: parse, then `ShouldRecord` (`:129`) against threshold, source, class, blacklist and whitelist — a dropped line returns at `:135` having allocated nothing: the gate config it hands `ShouldRecord` is one module-level `gateCfg` table, refreshed with the settings and given only the line's `itemID` per call, not a table built per line (`LootHistory-R-16`). A **kept** line then runs `NS.Compat.GetItemExtras` (`:138`), which is `C_Item.GetItemInfoInstant` + `C_Item.GetItemInfo` and then `Compat.ScanBound` — a real `C_TooltipInfo.GetHyperlink` build walked line by line — followed by `NS.AuctionPrice:GatherAll` (`:139`), one `pcall`ed fetch per installed provider across the Auctionator / TSM / Oribos cascade (all seven default capture keys are on). That is meaningfully more than a table insert, which is why it is written out here. It is bounded by the gate above it and by loot itself: a few kept items per kill. |
| `CHAT_MSG_CURRENCY` | `modules/Collector.lua:231` | Currency lines, and **not** the same shape as the row above: no tooltip build and no price cascade. Link parse, blacklist check, three `Compat.Currency*` lookups, one record insert. |
| `LOOT_OPENED` | `modules/Attribution.lua:412` | Stamps the single-slot loot context (one table write). Not combat-gated, but a loot window is not a hot path. |
| `ENCOUNTER_START` | `modules/Attribution.lua:413` | Two field writes, once per encounter. |
| `ENCOUNTER_END` | `modules/Attribution.lua:414` | One field write (the grace expiry on a kill) or one clear (a wipe), once per encounter. |
| `CHALLENGE_MODE_START` | `modules/Attribution.lua:415` | Two field writes, once per key. |
| `CHALLENGE_MODE_COMPLETED` | `modules/Attribution.lua:416` | One keystone-level read and at most one field write, once per key. The context is kept for the reward chest. |
| `TRADE_ACCEPT_UPDATE` | `modules/Attribution.lua:417` | Out of combat by construction. |
| `QUEST_TURNED_IN` | `modules/Attribution.lua:418` | One context stamp. |
| `ZONE_CHANGED_NEW_AREA` | `modules/Attribution.lua:419` | One API call per zone change (`IsInInstance`, through `Compat.InPartyInstance`), then either clears the keystone context or, on re-entry to an active key, one `GetActiveKeystoneInfo` read and one small table. Zone changes are rare and never a combat loop. |
| `CHALLENGE_MODE_RESET` | `modules/Attribution.lua:420` | One field write, once per reset key. |
| `UNIT_SPELLCAST_SUCCEEDED` | `modules/Attribution.lua:431` | **Unit-filtered to `player`** through its own `RegisterUnitEvent` frame, precisely so the raid-wide firehose a bare registration would deliver never arrives. One spell-id lookup against the deconstruct table. |
| `PLAYER_REGEN_DISABLED` | `modules/Browser.lua:1263` | **On the combat edge, once a fight, never inside one.** `B:ApplyVisibility` (`:1158`): if the window is not shown it returns immediately; otherwise one `settings.visibility` read, no combat-state read at all (the handler passes the edge in), and at most one `Hide`. It only ever hides — a window the setting starts allowing again is still the player's to open. |
| `PLAYER_REGEN_ENABLED` | `modules/Browser.lua:1269` | The other edge of the same handler, same cost. |

**`C_Timer` calls: five, every one of them one-shot. No `C_Timer.NewTicker` anywhere.** Grep the
three patterns and most of what comes back is prose and guards; the call sites are the table below.
`core/ItemSetup.lua:70` and `settings/OptionsSetup.lua:207` carry the guard and the call on one
line, which is why counting call sites by eye off the grep undercounts.

**Three of the five now go through `NS.After`, and that is the change v1.41.0 made here.**
`C_Timer.After` cannot be canceled, and `slash-commands-§7` asks for every timer **canceled**
rather than left armed to wake up and find a flag. `core/LifecycleSetup.lua`'s `NS.After` takes a
`C_Timer.NewTimer` handle where the client has one, tracks it in a live set, and `NS.CancelDeferrals`
drops the lot on the way down. The retention prune is why: it is a SavedVariables write on a
five-second fuse lit by `PLAYER_ENTERING_WORLD`, and before this a player who switched the addon off
inside those five seconds got the write anyway, from a game event, while it was disabled.

| Call | Where | What it is |
|---|---|---|
| `NS.After(5, …)` | `core/LootHistory.lua:83` | Login-deferred retention prune + the first warbound repair pass. Once per session, and **cancelable**. |
| `NS.After(20, …)` | `core/LootHistory.lua:87` | The second warbound repair pass, once the item cache is warm. Once per session, and cancelable. |
| `C_Timer.After(0.4, cb)` | `core/ItemSetup.lua:70` | `NS.Item.LoadItem`'s item-cache retry, in the degraded-install fallback; the live path is the same line in the library (`libs/LibKa0s/Item.lua:134`) — **one-shot, and only when the caller passes a callback.** Two callers: `core/Database.lua:220`, the warbound repair pass, passes none, so it requests the item and arms **no timer at all**; the Filters tab's LibKa0s `IdList` passes one per **batch**, not per id (LibKa0s v1.35.0): every uncached id one render asks for shares a single check, which repaints the list once if any name has landed and re-asks the rest, up to five asks per id — an options panel the player opened by hand. |
| `NS.After(delay, …)` | `core/Util.lua:256` | `Util.Coalesce`'s window, `RECORD_ADDED_COALESCE` = 0.2 s. **Not a ticker and it cannot become one:** each closure holds a `pending` flag that swallows every trigger until the timer fires, so a burst of *n* `RecordAdded` messages arms exactly one. Three independent closures exist — `modules/Browser.lua`, `modules/Analytics.lua` and `settings/Panel.lua`, one per subscribing surface — so the ceiling is three pending timers at once. Through `NS.After` since v1.41.0: a repaint already in flight when the player switches the addon off is canceled rather than waking to find nothing to paint, which is the shape `slash-commands-§7` singles out as the most expensive one. |
| `C_Timer.After(delay, fn)` | `settings/OptionsSetup.lua:207` | The library's 50 ms slider and color-picker drag throttles, handed in through the descriptor. The return value is unused: the library keeps its own armed flag (OptionsWidgets minor 31). No schema row is a color today; the sliders reach it. |

The last two rows stay on raw `C_Timer.After` on purpose: neither is a deferral of the addon's own. One is the item-cache retry inside a **degraded-install fallback** for a library function, and the other is a throttle the **library** arms from a settings widget the player is dragging. Routing either through `NS.CancelDeferrals` would mean a stand-down reaching into somebody else's work.

The message bus (`RegisterMessage`, `modules/Analytics.lua`, `modules/Browser.lua`,
`settings/Panel.lua`) fires from this addon's own writes, which are the events above. It used to be
excluded from the sweep on that reasoning plus "and only when a window is open" — and that
exclusion was wrong, in a way worth recording rather than quietly deleting.

`Database:Add` fires `Ka0s_LootHistory_RecordAdded` once per **looted item**. With the browser open
that reached a full `BrowserTable:Refresh`, seven filter-dropdown builders each scanning the whole
dataset, a `Database:StorageStats` pass with a per-record byte estimate, and — on the Insights tab —
a full `Analytics:Refresh`. Roughly **nine O(history) passes per loot line**, uncoalesced, on a
plain non-secure frame that `docs/ARCHITECTURE.md` says can be open during combat. "Only when a
window is open" described exactly the case that mattered and read as though it dismissed it.

The 2026-08-03 review recorded F-004 as fixed — "the record-added repaint is coalesced" — and it
was not true of the tree. It is now: `NS.Coalesce` (`core/Util.lua`) collapses a burst into one run
per `RECORD_ADDED_COALESCE` window, wired at `modules/Browser.lua:1257`,
`modules/Analytics.lua:667` and — for the History tab's storage readout, which walks the whole
history to estimate bytes — `settings/Panel.lua:170`. `HistoryChanged` stays immediate, because a
delete or a prune is one deliberate action. Issue #27.

The bus is therefore **in** the sweep's scope from now on, and the entry above is what it found.

## The allocation that is not measured, and stays that way

The other half of the Insights widget-pool story in [browser.md](browser.md#widget-pools-are-recycled-and-that-is-tested),
written down because a silent skip reads exactly like an oversight.

`wantedByProvider` (`modules/AuctionPrice.lua:61`) regroups the capture set into
`{ provider = { key = true } }` on every call, and `GatherAll` calls it at `:76` — once per **kept**
loot line, the `CHAT_MSG_LOOT` row above. It allocates one `out` table plus one sub-map per
provider named in the set: on the shipped default (`core/Constants.lua:154-158`, seven keys across
Auctionator, TSM and Oribos) that is exactly **four small tables per kept line**, from a set that
changes only when the player edits the Price sources table in settings. The obvious repair is to
memoize it and refresh on a settings change.

It is not being taken, and the reason is the exemption itself rather than an argument about size.
**There is no `tests/perf.lua` here in which to add a scenario, and by the register's own terms
there is not going to be one** — so the number that would decide this cannot be produced, and
"four tables is cheap" would be the same unmeasured assertion the exemption exists to refuse. What is
already on that line makes the guess a bad bet in any case: `NS.Compat.GetItemExtras`
(`modules/Collector.lua:138`) walks a `C_TooltipInfo` build line by line, and `GatherAll` then makes
one `pcall`ed call into every installed pricing addon. A memo would also buy real state — an
invalidation path, and a cached table handed out to three third-party fetchers — against a saving
nobody in this repo can size.

So it is left alone deliberately. `LOOTHISTORY-R-10`, 2026-09-08; the collection plan gates it on
"a scenario that measures it, added first — otherwise skip", and that gate cannot open here.

**What re-opens it:** the exemption ending — the trigger on [performance.md](performance.md#what-re-arms-the-wiring) — which brings a harness with
it, or `wantedByProvider` acquiring a caller that runs more often than once per kept loot line.

## What re-arming would reuse

**The teardown machinery exists anyway, and it is the DISABLE path's.** `slash-commands-§7` builds
the stand-down on the same seam performance-§6's suspend would have used, and this addon has that
seam: `core/LifecycleSetup.lua`'s `NS.StandDown` / `NS.StandUp`, behind one `LibKa0s-Lifecycle-1.0`
latch. The latch takes named **holds**, and `NS.HOLD_PERF` is published and honored although nothing
here takes it — so if this exemption is ever re-examined, arming the harness is a registration
rather than a second teardown path written beside the first. A parallel lifecycle mechanism is the
anti-pattern (`anti-patterns #85`), and declining the harness is not a license to grow one.
`tests/test_disabled.lua` drives both holds through the latch, so the invariant that matters —
releasing one hold must not resurrect an addon the other is still holding down — is under test here
today. See [disabled-state.md](disabled-state.md). `libs/LibKa0s/` is
still vendored **whole** — `Perf.lua` and `PerfPanel.lua` included — because the folder is copied
whole or not at all (library-stack-§7, anti-pattern #48), and `perf` stays a reserved verb
(slash-commands-§2): it is simply never registered, so it can never come to mean anything else here.
