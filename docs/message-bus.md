# Closed message bus

All inter-module communication uses `AceEvent`-style messages with a fixed name set. The bus is `NS.bus` — the AceEvent-embedded addon object created in [`core/LootHistory.lua:6`](../core/LootHistory.lua). New entries belong here, in the module headers, and in the [module map](module-map.md). **Don't invent new messages without a reason** — the closed list is what keeps cross-module coupling auditable.

## The three messages

| Message | Sender | Payload | Listeners |
|---|---|---|---|
| `Ka0s_LootHistory_RecordAdded` | `Database:Add` ([`core/Database.lua:65`](../core/Database.lua)) | `(record, index)` | Browser (refresh History), Analytics (live recompute), Panel (live stats) |
| `Ka0s_LootHistory_HistoryChanged` | `Database` — `DeleteAt` / `Delete` / `PruneOld` / `Purge`, via `fireHistoryChanged` ([`core/Database.lua:302`](../core/Database.lua)) | — | Browser, Analytics, Panel |
| `Ka0s_LootHistory_SettingsChanged` | `Schema` row `onChange` ([`settings/Schema.lua`](../settings/Schema.lua)) | `reason` string | Collector (`RefreshUpvalues`), Browser (`OnSettingsChanged`) |

Exactly one sender is allowed per message — the table is sender-authoritative.

## `Ka0s_LootHistory_RecordAdded` payload

Fired once per persisted loot event, immediately after the record is appended to the account-wide array in [`Database:Add`](../core/Database.lua) (`core/Database.lua:65`). The payload is `(record, index)`: the full record table (see [data-model.md](data-model.md)) and its 1-based position in `NS.db.global.history`. Consumers treat it as an incremental "one row added" signal — the Browser refreshes the History table, Analytics recomputes live, and the Settings panel updates its live storage stats. None of the current subscribers actually read the `index`; it is carried for cheap append-in-place refreshes without a full re-query.

Note the write path fires against the *real* history only. Browser test mode swaps a synthetic dataset in at the read seam (`Database:ActiveHistory`, `core/Database.lua:56`), but `Add`/prune never see that override, so `RecordAdded` is never emitted for test data.

## `Ka0s_LootHistory_HistoryChanged` payload

The bulk-mutation counterpart to `RecordAdded`: no payload, meaning "the history array changed structurally — re-query from scratch." All four senders route through the private `fireHistoryChanged` helper (`core/Database.lua:302`):

- `Database:DeleteAt(index)` — single-row delete from the table UI (compacts the array).
- `Database:Delete(pred)` — predicate delete.
- `Database:Purge()` — the `/lh purge` wipe.
- `Database:PruneOld()` — retention rebuild-and-swap (also invoked from the `retentionDays` setting's `onChange`, so a retention change surfaces as `HistoryChanged`, not `SettingsChanged`).

Because deletion and retention rebuild-and-swap (no holes; see [data-model.md](data-model.md)), indices are not stable across a `HistoryChanged`, which is why the payload is empty — subscribers must re-read, not patch by index.

## `Ka0s_LootHistory_SettingsChanged` payload

Sent from four schema-row `onChange` handlers in [`settings/Schema.lua`](../settings/Schema.lua), each with a distinct `reason` string: `"enabled"` (line 17), `"quality"` (line 40), `"questfilter"` (line 47), and `"excludes"` (line 63). These are exactly the settings that feed the Collector's hot-path upvalues — the reason lets a subscriber log/branch, but current consumers re-read all of them:

- **Collector** (`modules/Collector.lua:106`) calls `RefreshUpvalues()`, re-caching `enabled` / `qualityThreshold` / `excludeQuestItems` / `excludedSources` off the settings table so the `CHAT_MSG_LOOT` hot path never touches the DB.
- **Browser** (`modules/Browser.lua:1042`) calls `OnSettingsChanged()` to reflect the change in the open window.

### What does NOT broadcast

Two schema rows deliberately skip the bus and drive their side effect directly in `onChange`:

- `minimap.hide` → `NS.Browser:SetMinimapHidden(v)` (`settings/Schema.lua:23`).
- `settings.windowScale` → `NS.Browser:SetScale(v)` (`settings/Schema.lua:31`).

Neither emits `SettingsChanged`, because nothing else needs to react — they are one-consumer, view-only knobs. (Likewise `retentionDays` fires `HistoryChanged` via `PruneOld`, not `SettingsChanged`.) Keeping these off the bus means flipping the minimap button or the window scale never cascades into a Collector upvalue refresh or a table rebuild.

## The private-bus-target invariant

**Every consumer must register on its OWN `NS.NewBusTarget()` — never on the shared `NS.bus` / `NS.addon` as `self`.** This is the single hardest rule on the bus and it is load-bearing.

`NS.NewBusTarget()` (`core/LootHistory.lua:20`) returns a fresh, AceEvent-embedded table. `NS.bus:SendMessage(...)` still fans out to every embedded target, so a private target receives broadcasts exactly like the shared object would — but it owns its own callback slots.

The reason: **CallbackHandler keys registered callbacks by `(message, target)`.** If two modules both did `NS.bus:RegisterMessage("Ka0s_LootHistory_HistoryChanged", handler)`, they would share the single target `NS.bus`, so the second registration would overwrite the first under the same `(message, target)` key — and only the last registrant would ever be called. The bug is silent: no error, the message still fires, but one module's handler simply never runs.

Because multiple consumers subscribe to the same messages — `HistoryChanged` and `RecordAdded` each have three listeners (Browser, Analytics, Panel) — sharing `NS.bus` as the target would clobber all but the last. Each consumer therefore stores its own target and registers on it:

- Collector — `self.__ev = NS.NewBusTarget()` (`modules/Collector.lua:105`).
- Browser — `B.__ev = NS.NewBusTarget()` (`modules/Browser.lua:1041`).
- Analytics — `self.__ev = NS.NewBusTarget()` (`modules/Analytics.lua:454`).
- Panel — `local ev = NS.NewBusTarget()` (`settings/Panel.lua:374`).

Only the *senders* use `NS.bus` directly (`NS.bus:SendMessage(...)`); every *receiver* goes through its private target.

## Adding or removing a message

Adding a message means updating:

1. The single source emitter (one sender per message — the table above is sender-authoritative).
2. Every consumer that reacts to it — each on its **own** `NS.NewBusTarget()`, never the shared bus.
3. The table above (sender, payload, listeners).
4. The relevant module header comment.
5. The `CLAUDE.md` hard-rules pointer if the new message carries cross-module rules.
