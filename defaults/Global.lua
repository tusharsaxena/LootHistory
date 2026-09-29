local _, NS = ...

-- Account-wide defaults: what the account RECORDED, plus the two things the standard pins to the
-- global store. Every setting is profile-scoped and lives in defaults/Profile.lua (see
-- docs/schema.md and docs/profiles.md).
NS.defaults = NS.defaults or {}
NS.defaults.global = {
  -- Version stamp for the persisted DB, declared 0 per savedvariables-§1 (standard v2.65.0): the
  -- pre-migration floor, never the current version, and it never moves. AceDB's removeDefaults
  -- strips a stored value equal to its default at logout, and its defaults merge backfills a
  -- declared default onto an account that stored no stamp; 0 has neither problem, since any stamp
  -- the runner advanced differs from it and an unstamped account reads 0 and walks every step. The
  -- runner owns the stamp: NS:RunMigrations (core/Database.lua) walks the MIGRATIONS table there,
  -- and its highest `to`, NS.SCHEMA_VERSION, is what a migrated DB carries — 9 today, through
  -- v1→v2 (strip the retired per-record `viaWhitelist`) up to v8→v9 (every setting moved from this
  -- store into the `Default` profile). Every step is non-destructive.
  schemaVersion = 0,
  history = {},          -- array of loot records: recorded data, account-wide by design
  -- LibDBIcon's table. GLOBAL by launcher-§3: the minimap button belongs to the installation, and a
  -- profile switch must not move it or hide it.
  minimap = { hide = false },
  -- debug is session-only (NS.State.debug), never persisted here.
}
