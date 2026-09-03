# Closed message bus

All inter-module communication uses `AceEvent`-style messages with a fixed name set. The bus is `NS.bus` — the AceEvent-embedded addon object created in [`core/LootHistory.lua:6`](../core/LootHistory.lua). New entries belong here, in the module headers, and in the [module map](module-map.md). **Don't invent new messages without a reason** — the closed list is what keeps cross-module coupling auditable.

## The three messages

| Message | Sender | Payload | Listeners |
|---|---|---|---|
| `Ka0s_LootHistory_RecordAdded` | `Database:Add` ([`core/Database.lua:287`](../core/Database.lua)) | `(record, index)` | Browser (refresh History), Analytics (live recompute), Panel (live stats) — Browser and Analytics repaint through `NS.Coalesce(…, Constants.RECORD_ADDED_COALESCE)`, one pass per 0.2s burst |
| `Ka0s_LootHistory_HistoryChanged` | `Database` — `Delete` / `PruneOld` / `Purge` and the public `FireHistoryChanged` (called by `NS.Filters` on a blacklist/whitelist edit, to refresh the Filters settings tab's list UI) via `fireHistoryChanged`, plus `RepairBoundStates` sending directly on a productive pass ([`core/Database.lua`](../core/Database.lua)) | — | Browser, Analytics, Panel (History stats + the Filters tab) |
| `Ka0s_LootHistory_SettingsChanged` | `Schema` row `onChange` ([`settings/Schema.lua`](../settings/Schema.lua)) | `reason` string | Collector (`RefreshUpvalues`), Browser (`OnSettingsChanged`) |

Exactly one sender is allowed per message — the table is sender-authoritative.

## `Ka0s_LootHistory_RecordAdded` payload

Fired once per persisted loot event, immediately after the record is appended to the account-wide array in [`Database:Add`](../core/Database.lua) (`core/Database.lua:287`). The payload is `(record, index)`: the full record table (see [schema.md](schema.md)) and its 1-based position in `NS.db.global.history`. Consumers treat it as an incremental "one row added" signal — the Browser refreshes the History table, Analytics recomputes live, and the Settings panel updates its live storage stats. None of the current subscribers actually read the `index`; it is carried for cheap append-in-place refreshes without a full re-query.

Note the write path fires against the *real* history only. Browser test mode swaps a synthetic dataset in at the read seam (`Database:ActiveHistory`, `core/Database.lua:278`), but `Add`/prune never see that override, so `RecordAdded` is never emitted for test data.

## `Ka0s_LootHistory_HistoryChanged` payload

The bulk-mutation counterpart to `RecordAdded`: no payload, meaning "the history array changed structurally — re-query from scratch." Every emission is `Database`'s, so it stays the single sending module — four of the five through the private `fireHistoryChanged` helper, and the deferred bound repair directly, because it is defined above that helper in `core/Database.lua`:

- `Database:Delete(pred)` — predicate delete.
- `Database:Purge()` — the `/lh purge` wipe.
- `Database:PruneOld()` — retention rebuild-and-swap (also invoked from the `retentionDays` setting's `onChange`, so a retention change surfaces as `HistoryChanged`, not `SettingsChanged`).
- `Database:RepairBoundStates()` — the deferred warbound-state split, which fires **only when a pass actually fixed rows** (`fixed > 0`). It sends directly rather than through `fireHistoryChanged`, because the repair is defined above that helper; the window can already be open when a pass lands and renders the Bound column off those rows, so it repaints rather than leaving stale locks until the next open.
- `Database:FireHistoryChanged()` — the public wrapper `NS.Filters` calls after a **blacklist/whitelist** edit. Filtering is point-in-time, so a list edit never changes what a query returns for already-stored rows; the message exists so the Settings ▸ General ▸ Filters tab's live id list re-renders. Emitting through this wrapper keeps `Database` the one sender (the Filters module never sends on the bus itself).

Because deletion and retention rebuild-and-swap (no holes; see [schema.md](schema.md)), indices are not stable across a `HistoryChanged`, which is why the payload is empty — subscribers must re-read, not patch by index.

> The blacklist/whitelist edit also re-caches the Collector's list upvalues via a **direct** `NS.Collector:RefreshUpvalues()` call (not a `SettingsChanged` message) — the lists aren't schema settings and the Collector is their only capture-side consumer, so no second `SettingsChanged` sender is introduced.

## `Ka0s_LootHistory_SettingsChanged` payload

Sent from eight schema-row `onChange` handlers in [`settings/Schema.lua`](../settings/Schema.lua), carrying six distinct `reason` strings between them: `"enabled"`, `"quality"`, `"currency"` (the `recordCurrency` toggle), `"questfilter"`, `"excludes"`, and `"chrome"` — the last one new with the Master controls tab, sent by `settings.scale` / `settings.alpha` / `settings.locked` so the Browser re-applies the addon-wide chrome to both of its frames. The first five are exactly the settings that feed the Collector's hot-path upvalues — the reason lets a subscriber log/branch, but current consumers re-read all of them:

- **Collector** (`modules/Collector.lua`) calls `RefreshUpvalues()`, re-caching `enabled` / `qualityThreshold` / `excludeQuestItems` / `recordCurrency` / `excludedSources` (and the id lists) off the settings table so the `CHAT_MSG_LOOT` and `CHAT_MSG_CURRENCY` hot paths never touch the DB.
- **Browser** (`modules/Browser.lua:1186`) calls `OnSettingsChanged()` to reflect the change in the open window.

### What does NOT broadcast

Three schema rows deliberately skip the bus and drive their side effect directly in `onChange`:

- `minimap.hide` → `NS.Browser:SetMinimapHidden(v)` (`settings/Schema.lua:284`).
- `settings.windowScale` → `NS.Browser:SetScale(v)` (`settings/Schema.lua:264`).
- `settings.rowHeight` → `NS.BrowserTable:Bind()` (`settings/Schema.lua:277`).

Neither emits `SettingsChanged`, because nothing else needs to react — they are one-consumer, view-only knobs. (Likewise `retentionDays` fires `HistoryChanged` via `PruneOld`, not `SettingsChanged`.) Keeping these off the bus means flipping the minimap button or the window scale never cascades into a Collector upvalue refresh or a table rebuild.

## The private-bus-target invariant

**Every consumer must register on its OWN `NS.NewBusTarget()` — never on the shared `NS.bus` / `NS.addon` as `self`.** This is the single hardest rule on the bus and it is load-bearing.

`NS.NewBusTarget()` (`core/LootHistory.lua:20`) returns a fresh, AceEvent-embedded table. `NS.bus:SendMessage(...)` still fans out to every embedded target, so a private target receives broadcasts exactly like the shared object would — but it owns its own callback slots.

The reason: **CallbackHandler keys registered callbacks by `(message, target)`.** If two modules both did `NS.bus:RegisterMessage("Ka0s_LootHistory_HistoryChanged", handler)`, they would share the single target `NS.bus`, so the second registration would overwrite the first under the same `(message, target)` key — and only the last registrant would ever be called. The bug is silent: no error, the message still fires, but one module's handler simply never runs.

Because multiple consumers subscribe to the same messages — `HistoryChanged` has four listeners (Browser, Analytics, the Panel's History-stats section, and the Panel's Filters tab) and `RecordAdded` three — sharing `NS.bus` as the target would clobber all but the last. Each consumer therefore stores its own target and registers on it (the Panel uses two: `P.__ev` for the History stats and `P.__evFilters` for the Filters tab's live list rebuild):

- Collector — `self.__ev = NS.NewBusTarget()` (`modules/Collector.lua:222`).
- Browser — `B.__ev = NS.NewBusTarget()` (`modules/Browser.lua:1261`).
- Analytics — `self.__ev = NS.NewBusTarget()` (`modules/Analytics.lua:651`).
- Panel — `local ev = NS.NewBusTarget()`, **twice**: the History tab's storage readout (`settings/Panel.lua:155`) and the Filters tab's id-lists (`settings/Panel.lua:426`), each on its own target.

Only the *senders* use `NS.bus` directly (`NS.bus:SendMessage(...)`); every *receiver* goes through its private target.

## Adding or removing a message

Adding a message means updating:

1. The single source emitter (one sender per message — the table above is sender-authoritative).
2. Every consumer that reacts to it — each on its **own** `NS.NewBusTarget()`, never the shared bus.
3. The table above (sender, payload, listeners).
4. The relevant module header comment.
5. The closed-bus rule in [common-tasks.md](common-tasks.md) if the new message carries cross-module rules.
