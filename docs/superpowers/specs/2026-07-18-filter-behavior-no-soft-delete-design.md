# Design: Point-in-time blacklist/whitelist — remove soft-add / soft-delete

**Date:** 2026-07-18
**Branch:** `feat/filter-behavior-no-soft-delete`
**Status:** Approved (design), pending implementation plan

## Problem

The blacklist/whitelist feature currently uses a **soft-add / soft-delete** model that
makes filtering *stateful over time* rather than point-in-time:

- **Whitelist ("soft-add").** A below-threshold item that only passed the capture gate
  because its id was whitelisted is written to the DB with a per-record flag
  `record.viaWhitelist = true`. If that id later leaves the whitelist, the row is *hidden*
  at read time (a "soft-delete") — the row still lives in the DB.
- **Blacklist ("soft-delete" at read time).** New captures of a blacklisted id are already
  dropped at capture time (point-in-time). But there is an *additional* retroactive
  read-time hide: any already-stored row whose itemID is *currently* on the blacklist is
  hidden in the browser/export/insights, with no annotation written on the row.

Both read-time hides funnel through a single seam, `Database:VisibleHistory()`, feeding
`ActiveHistory()` → `Query` / `Stats` / `Export`.

We are reversing this decision. Every looting, blacklist, and whitelist operation becomes
**point-in-time**: a record's presence is decided once, at loot time, by the filter state
at that moment. Nothing hides or resurrects a stored row afterward.

## Decisions (ratified with the user)

1. **Existing data — let previously-hidden rows reappear.** The migration is
   non-destructive. It strips the dead `viaWhitelist` field and bumps the schema version;
   it does **not** delete blacklisted rows or orphaned whitelist rows. Rows hidden under the
   old behavior simply become visible again.
2. **Blacklist scope — future loots only.** Adding an item to the blacklist prevents future
   captures. It does **not** retroactively delete or hide existing records of that item.

## Target behavior

| Operation | New (point-in-time) behavior |
|---|---|
| Loot a blacklisted item | Dropped at capture — never written to the DB. (Already the case.) |
| Loot a whitelisted below-gate item | Written as a **plain** record — no flag. (Already written today, minus the flag.) |
| Remove an id from the whitelist | No effect on existing records — they stay, unflagged. |
| Add an id to the blacklist | No effect on existing records — only future loots are dropped. |
| Read (browser / export / insights) | Returns raw stored history — no hide, no filter seam. |

## Changes

### Capture — `modules/Collector.lua`
- Keep `ShouldRecord` as-is: blacklist vetoes (`return false, "blacklist"`), whitelist
  rescues below-gate items (`return true, "whitelist"`). This is already point-in-time.
- Remove the `viaWhitelist` local computation (`~l.101`) and the
  `record.viaWhitelist = viaWhitelist` stamp (`~l.112`). A whitelisted below-gate item is
  still written — just as a plain record.
- `RefreshUpvalues` still caches `blacklist`/`whitelist` for the capture hot path — unchanged.

### Read seam — `core/Database.lua`
- Delete `VisibleHistory()`, `RebuildWhitelistIndex()`, and the local `whitelistOrphanExists()`.
- `ActiveHistory()` collapses to: return the test dataset if present, else the raw `history`.
- `Database:Add` no longer maintains the whitelist index (drop the `viaWhitelist` branch,
  `~l.119-123`).
- Remove the now-orphaned `RebuildWhitelistIndex()` calls at init and in
  `DeleteAt` / `Delete` / `Purge` / `PruneOld`.
- `Query`, `Stats`, `Export` need no direct change — they inherit the simpler `ActiveHistory`.

### Session state — `core/State.lua`
- Remove `State.viaWhitelistIDs` (the derived index that backed the whitelist hide).

### Filters — `modules/Filters.lua`
- **Unchanged.** It only edits the db.global id-sets and fires
  `Collector:RefreshUpvalues()` + `Database:FireHistoryChanged()`. No flag logic lived here.
- The db.global `blacklist`/`whitelist` carve-out remains the ratified carve-out it is.

### Migration — `core/Database.lua:RunMigrations`
- First real migration. Bump `schemaVersion` 1 → 2.
- Iterate `history`, set `r.viaWhitelist = nil` to strip the dead field.
- Non-destructive: no rows deleted; no blacklist purge; no orphan deletion.

### UX copy — `settings/Panel.lua` (and any matching slash/tooltip copy)
- Reword the blacklist/whitelist descriptive copy (`~l.389-390`, `~l.507-508`) and the
  browser right-click **"Blacklist item"** tooltip (`modules/BrowserTable.lua:963`) so the
  behavior reads as **"affects future loots only"**, not "removes from / adds to history."

### Accepted consequence
- The right-click **"Blacklist item"** action will no longer make the clicked row vanish —
  it only stops future captures. This is the intended effect of the "future loots only"
  decision, not a regression to fix.

## Tests — `tests/`
- **`test_collector.lua:135-160`** — rewrite: a whitelisted below-gate item is written
  *without* any flag; removing the id from the whitelist does **not** hide or delete it.
- **`test_database.lua:188-236`** — remove/replace the `VisibleHistory` tests and the
  "Query/Stats/Export exclude blacklisted ids" test; those exclusions no longer exist. Add
  coverage that `ActiveHistory` returns raw history unchanged.
- **`test_export.lua:116-128`** — rewrite: `InsightsCSV` no longer omits blacklisted items.
- **`test_filters.lua`** — survives as-is (it exercises the id-set API, not the flag).
- **New migration test** — a seeded row with `viaWhitelist = true` comes back with the field
  stripped and visible after migration; `schemaVersion` is 2.

## Docs & bookkeeping
- Update `docs/ARCHITECTURE.md` and `docs/attribution.md` where they describe
  soft-add/soft-delete, `viaWhitelist`, or the issue-#14 semantics.
- `docs/saved-variables.md` — the blacklist/whitelist carve-out entry stays.
- Regenerate `docs/test-cases.md` (`lua tests/run.lua --list > docs/test-cases.md`) and bump
  the README `tests` badge count in the same change (hard rule).

## Standards note
Nothing here deviates from the Ka0s WoW Addon Standard: `viaWhitelist` was app-specific
state, the db.global carve-out is untouched, and versioned schema migration is standard
practice. No deviation to flag.

## Verification
- `lua tests/run.lua` (green, non-zero on failure) and `luacheck .` (0 errors) before commit.
- In-game smoke (per `docs/smoke-tests.md`): loot a blacklisted item → not recorded; loot a
  whitelisted below-gate item → recorded; un-whitelist it → still present; blacklist an item
  you already own → existing rows remain visible.
