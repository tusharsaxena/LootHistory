# Saved variables

Single saved-variable: `LootHistoryDB`, an AceDB-3.0 store. `NS:InitDB` calls `AceDB:New("LootHistoryDB", NS.defaults, true)` (`core/Database.lua:4`). Everything — both the loot history **and** the user settings — lives in the **account-wide `db.global` scope**; the addon never touches `db.profile`. The `true` third argument names a shared default profile, but that profile is intentionally vestigial here: no data or setting is stored per-character.

Why account-wide: loot is collected across every character on the account and attributed with a `char` column on each record, so the browser and Insights tab can show one alt's drops, all alts, or any subset. A per-character profile store would fragment that history and force a schema + query rewrite; the account-wide decision is load-bearing (see [data-model.md](data-model.md)).

## `db.global` shape

Defaults are declared in `defaults/Global.lua`; AceDB merges them under `db.global` on first access.

```lua
db.global = {
  schemaVersion = 2,           -- DB schema stamp; seeded 1, carried to 2 by NS:RunMigrations at init
  history = {},                -- dense array of loot records (one per loot event)
  blacklist = {},              -- { [itemID]=true } — dropped at capture; existing rows untouched (carve-out)
  whitelist = {},              -- { [itemID]=true } — always record, bypassing the gates (carve-out)
  settings = {
    enabled          = true,   -- master capture switch
    qualityThreshold = 1,      -- record Common (white) and above
    excludeQuestItems = true,  -- drop Quest-class items at capture (opt-out)
    excludedSources  = {},     -- set of MUTED SourceType keys
    retentionDays    = 30,     -- 0 == keep Always
    windowScale      = 1.0,    -- History browser window scale
    window           = {},     -- persisted position/size (storage-only, see below)
  },
  minimap = { hide = false },  -- LibDBIcon visibility state
  savedView = <table|nil>,     -- saved table view (storage-only, see below); absent until saved
}
```

- `history` is a **dense array** — `Database:Delete`/`PruneOld` rebuild-and-swap rather than leaving holes (`core/Database.lua:340`, `:400`). Each record's field shape is documented in [data-model.md](data-model.md).
- `settings.excludedSources` is stored as the set of **muted** sources; the panel renders it inverted ("Record data from"), so a checked box means "record this source" (`settings/Schema.lua:72`).
- `savedView` only exists once the user clicks **Save** in the browser filter bar; until then reads fall back to the stock view.

Debug is **session-only** (`NS.State.debug`) and is deliberately **never persisted** here — it resets to off on every reload (`defaults/Global.lua:28`, `settings/Schema.lua:80`).

## The `Schema:Set` write seam

Every user *setting* mutation flows through one seam: `Schema:Set(path, value)` in `settings/Schema.lua:124` — validate → deep-copy → write to `NS.db.global` → fire the row's `onChange`. `settings/Schema.lua` holds one row per setting and is the single source of truth for the AceDB default, the panel widget, and the slash get/set/list/reset behavior (see [settings-panel.md](settings-panel.md) and [slash-dispatch.md](slash-dispatch.md)). Paths resolve against `NS.db.global`, not `.profile`.

The deep-copy (`settings/Schema.lua:116`) matters for the two table-valued settings (`excludedSources`, and any reset that passes a schema `default` table): without it, a write would alias the DB to a shared default table and let an in-place mutation poison the default for the rest of the session.

### Storage-only carve-outs

Four pieces of persisted state live in `db.global` but are written **directly**, bypassing `Schema:Set` — they are runtime/data state, not user settings, and are intentionally not Schema rows (`modules/Browser.lua:80`):

- **`settings.window`** — the browser window geometry `{ point, x, y, w, h }` relative to UIParent. Saved by `SaveWindow` on move/resize (`modules/Browser.lua:86`), restored by `RestoreWindow` on show (`modules/Browser.lua:95`). This is the standalone-windows window position/size persistence.
- **`savedView`** — the saved table view: group-by, sort keys, and the multi-select column filters (bound / quality / type / subtype / source / zone) plus the date range and search text. Captured by `B:CaptureView`, written by `B:SaveView`, cleared to `nil` by `B:ResetView`. Character scope is **not** part of the view — it is a session-only "current player" default. When `savedView` is absent, `savedViewOrStock` returns the hard-coded `STOCK_VIEW` baseline (`modules/Browser.lua:410`).
- **`blacklist` / `whitelist`** — the item-id filter lists (issue #14). A dynamic id-set has no Schema widget to drive, so they are managed by `NS.Filters` (`modules/Filters.lua`) — copy-on-write mutation, then a direct `Collector:RefreshUpvalues()` re-cache + `Database:FireHistoryChanged()` (the browser re-queries). Both lists are strictly **point-in-time**: they decide what happens at capture, not what happens to rows already stored. Blacklisted ids are dropped at capture (`CHAT_MSG_LOOT`) and never written to `history`; existing rows are never hidden or removed. Whitelisted ids are always recorded, bypassing the quality/source/quest gates, as plain rows with no special flag. Changing either list fires `Database:FireHistoryChanged()` and calls `Collector:RefreshUpvalues()` so the browser/Insights re-query (refreshing counts/lists) and future captures see the new lists — it never hides or reveals existing rows. An id lives on at most one list. See [data-model.md](data-model.md) and [settings-panel.md](settings-panel.md).

> **Standards note (accepted carve-out).** These four bypass the schema-as-single-source rule (CLAUDE §2, "every user-setting mutation goes through `Schema:Set`"). `window`/`savedView`/`windowScale` were the pre-existing precedent; `blacklist`/`whitelist` extend it for the same reason: a dynamic, unbounded set of arbitrary item ids has no fixed schema widget (CheckBox/Dropdown/Slider/MultiCheck) to express it. **Resolution (2026-07-17): ratified as a legitimate carve-out** — same class as `window`/`savedView`, managed by `NS.Filters` writing `NS.db.global` directly. The Ka0s Standard's own definition was left unchanged; if a future addon wants this pattern first-class, amend the standard's schema section then.

Note `settings.windowScale` **is** a Schema row (Master Controls slider) even though `settings.window` is not — the scale is a user-facing setting, the geometry is runtime state.

### Reset semantics

Three reset surfaces write these tables; each reaches a deliberately different scope so the carve-outs above are never silently missed (audit 2026-07-17):

| Reset | Trigger | Schema settings | `blacklist`/`whitelist` | `savedView` | `settings.window` | `history` |
|-------|---------|:---:|:---:|:---:|:---:|:---:|
| **Non-destructive** | "Defaults" button · `/lh resetall` (`Sl:CliResetAll`) | ✓ | ✓ (`Filters:ClearAll`) | — | — | — |
| **Destructive** | "Reset All" button → confirm (`Sl:ResetEverything`) | ✓ | ✓ | ✓ (`Browser:ResetView`) | ✓ (`Browser:ResetWindow`) | ✓ (`Database:Purge`) |
| **Single** | `/lh reset <path>` (`Sl:CliReset`) | one row | — | — | — | — |

- The **blacklist/whitelist** are user-configured filter *settings*, so both settings resets clear them — the non-destructive path clears the two id-sets (copy-on-write replace + one `_notify`) but never touches `history`; since the lists are point-in-time only, there is nothing in `history` left to reconcile. `Filters:ClearList` / `Filters:ClearAll` do a single copy-on-write replace + one `_notify`.
- **`savedView` and window geometry** are view/runtime state, so only the confirm-gated **Reset All** touches them (matching its "cannot be undone" wording). `savedView` also has its own filter-bar **Reset** button (`Browser:ResetView`).
- The Filters sub-page carries per-list **Clear all** buttons (confirm-gated, `KA0S_LOOTHISTORY_CLEAR_BLACKLIST`/`_WHITELIST`) so a list can be emptied without a full settings reset.
- The Filters subcategory's own header **Defaults** button (`KA0S_LOOTHISTORY_CLEAR_FILTERS` → `Filters:ClearAll`) clears **both** id-lists at once but touches **nothing else** — not the schema settings, `savedView`, window, or `history`. (The "Defaults" in the matrix above is the **General** page's button, which resets schema settings *and* the lists.)

## Init and migration lifecycle

`NS:InitDB` (`core/Database.lua:4`) creates the AceDB store, then immediately calls `NS:RunMigrations` to normalize the persisted schema **before any history read**.

`NS:RunMigrations` (`core/Database.lua:13`) is the idempotent schema-upgrade seam required by the Ka0s Standard. It reads and writes `db.global.schemaVersion`, runs once at init — from `InitDB`, after the AceDB store is ready, before any history read — and is a safe no-op when the DB isn't ready. It currently ships one migration, gated on `schemaVersion < 2`: it strips the retired per-record `viaWhitelist` field (a leftover from the old soft-add model) from every stored row, then bumps the stamp to `2`. The migration deletes no records — it only clears a field — and is idempotent: once a DB is already at `schemaVersion` `2`, re-running it is a no-op. The `defaults/Global.lua` seed value legitimately stays `1` for brand-new DBs; live DBs are carried to `2` by this migration on their first load after upgrade.

## Retention prune

`Database:PruneOld` (`core/Database.lua:400`) enforces `settings.retentionDays`: it drops every record older than `now - retentionDays × 86400`, rebuild-and-swap, and fires `Ka0s_LootHistory_HistoryChanged`. `retentionDays == 0` means "keep Always" and returns early. It runs at the appropriate lifecycle points and whenever the retention setting changes (the row's `onChange` calls `PruneOld` — `settings/Schema.lua:66`).
