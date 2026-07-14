# Saved variables

Single saved-variable: `LootHistoryDB`, an AceDB-3.0 store. `NS:InitDB` calls `AceDB:New("LootHistoryDB", NS.defaults, true)` (`core/Database.lua:5`). Everything — both the loot history **and** the user settings — lives in the **account-wide `db.global` scope**; the addon never touches `db.profile`. The `true` third argument names a shared default profile, but that profile is intentionally vestigial here: no data or setting is stored per-character.

Why account-wide: loot is collected across every character on the account and attributed with a `char` column on each record, so the browser and Insights tab can show one alt's drops, all alts, or any subset. A per-character profile store would fragment that history and force a schema + query rewrite; the account-wide decision is load-bearing (see [data-model.md](data-model.md)).

## `db.global` shape

Defaults are declared in `defaults/Global.lua`; AceDB merges them under `db.global` on first access.

```lua
db.global = {
  schemaVersion = 1,           -- DB schema stamp; NS:RunMigrations reads/writes this
  history = {},                -- dense array of loot records (one per loot event)
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

- `history` is a **dense array** — `Database:Delete`/`PruneOld` rebuild-and-swap rather than leaving holes (`core/Database.lua:293`, `:348`). Each record's field shape is documented in [data-model.md](data-model.md).
- `settings.excludedSources` is stored as the set of **muted** sources; the panel renders it inverted ("Record data from"), so a checked box means "record this source" (`settings/Schema.lua:59`).
- `savedView` only exists once the user clicks **Save** in the browser filter bar; until then reads fall back to the stock view.

Debug is **session-only** (`NS.State.debug`) and is deliberately **never persisted** here — it resets to off on every reload (`defaults/Global.lua:21`, `settings/Schema.lua:67`).

## The `Schema:Set` write seam

Every user *setting* mutation flows through one seam: `Schema:Set(path, value)` in `settings/Schema.lua:109` — validate → deep-copy → write to `NS.db.global` → fire the row's `onChange`. `settings/Schema.lua` holds one row per setting and is the single source of truth for the AceDB default, the panel widget, and the slash get/set/list/reset behavior (see [settings-panel.md](settings-panel.md) and [slash-dispatch.md](slash-dispatch.md)). Paths resolve against `NS.db.global`, not `.profile`.

The deep-copy (`settings/Schema.lua:101`) matters for the two table-valued settings (`excludedSources`, and any reset that passes a schema `default` table): without it, a write would alias the DB to a shared default table and let an in-place mutation poison the default for the rest of the session.

### Storage-only carve-outs

Two pieces of persisted state live in `db.global` but are written **directly**, bypassing `Schema:Set` — they are window/view runtime state, not user settings, and are intentionally not Schema rows (`modules/Browser.lua:79`):

- **`settings.window`** — the browser window geometry `{ point, x, y, w, h }` relative to UIParent. Saved by `SaveWindow` on move/resize (`modules/Browser.lua:85`), restored by `RestoreWindow` on show (`modules/Browser.lua:94`). This is the §6A standalone-window position/size persistence.
- **`savedView`** — the saved table view: group-by, sort keys, and the multi-select column filters (quality / source / type / zone) plus the date range and search text. Captured by `B:CaptureView` (`modules/Browser.lua:603`), written by `B:SaveView` (`modules/Browser.lua:662`), cleared to `nil` by `B:ResetView` (`modules/Browser.lua:668`). Player scope is **not** part of the view — it is a session-only "current player" default. When `savedView` is absent, `savedViewOrStock` returns the hard-coded `STOCK_VIEW` baseline (`modules/Browser.lua:397`).

Note `settings.windowScale` **is** a Schema row (Master Controls slider) even though `settings.window` is not — the scale is a user-facing setting, the geometry is runtime state.

## Init and migration lifecycle

`NS:InitDB` (`core/Database.lua:4`) creates the AceDB store, then immediately calls `NS:RunMigrations` to normalize the persisted schema **before any history read**.

`NS:RunMigrations` (`core/Database.lua:13`) is the idempotent schema-upgrade seam required by the Ka0s Standard. It reads and writes `db.global.schemaVersion`, and ships even with an effectively empty body — the *seam* is the requirement, so a future schema change gets a single upgrade path invoked once at init. Today it stamps `schemaVersion = 1` and does nothing else; it is a safe no-op when the DB isn't ready.

## Retention prune

`Database:PruneOld` (`core/Database.lua:348`) enforces `settings.retentionDays`: it drops every record older than `now - retentionDays × 86400`, rebuild-and-swap, and fires `Ka0s_LootHistory_HistoryChanged`. `retentionDays == 0` means "keep Always" and returns early. It runs at the appropriate lifecycle points and whenever the retention setting changes (the row's `onChange` calls `PruneOld` — `settings/Schema.lua:53`).
