local _, NS = ...

-- Account-wide defaults: what the account RECORDED, the one setting that governs it, and the two
-- things the standard pins to the global store. Every other setting is profile-scoped and lives in
-- defaults/Profile.lua (see docs/schema.md and docs/profiles.md).
NS.defaults = NS.defaults or {}
NS.defaults.global = {
  -- Version stamp for the persisted DB, declared 0 per savedvariables-§1 (standard v2.65.0): the
  -- pre-migration floor, never the current version, and it never moves. AceDB's removeDefaults
  -- strips a stored value equal to its default at logout, and its defaults merge backfills a
  -- declared default onto an account that stored no stamp; 0 has neither problem, since any stamp
  -- the runner advanced differs from it and an unstamped account reads 0 and walks every step. The
  -- runner owns the stamp: NS:RunMigrations (core/Database.lua) walks the MIGRATIONS table there,
  -- and its highest `to`, NS.SCHEMA_VERSION, is what a migrated DB carries — 12 today, through
  -- v1→v2 (strip the retired per-record `viaWhitelist`), v8→v9 (every setting moved from this
  -- store into the `Default` profile) and v9→v10 (`retentionDays` lifted back out of every profile
  -- into this store). Every step is non-destructive.
  schemaVersion = 0,
  history = {},          -- array of loot records: recorded data, account-wide by design
  -- Timeline ledger stores (schema v11). holdings[holder] is what each character and the virtual
  -- "§warband" holder currently owns; daily[day][holder][thingKey] is the sparse rollup Phase 3 reads.
  holdings = {},
  daily = {},
  -- ledgerSince (ts the v11 step ran), resetPrompt (nil | "reset" | "kept") and resetPromptPending
  -- (nil | true, the v11 step's persisted "ask about a reset" marker) are deliberately NOT
  -- declared: AceDB would strip a value equal to its default and backfill it onto old accounts.
  -- "Keep history for", in days (0 == keep Always). ACCOUNT-WIDE, outside every profile (owner
  -- decision D6): it decides what the login prune deletes from the shared history, so a profile
  -- switch, copy or reset must never change it. The schema row `settings.retentionDays` reads and
  -- writes this key through its own get/set (settings/Schema.lua).
  retentionDays = 30,
  rollupRetentionDays = 0,   -- the Timeline's daily rollup: 0 = Always (spec §11)
  -- rollupSeeded (ts of the one-time seed, modules/Rollup.lua) is deliberately NOT declared, for
  -- the reason ledgerSince is not: AceDB strips a value equal to its default.
  -- LibDBIcon's table. GLOBAL by launcher-§3: the minimap button belongs to the installation, and a
  -- profile switch must not move it or hide it.
  minimap = { hide = false },
  -- debug is session-only (NS.State.debug), never persisted here.
}
