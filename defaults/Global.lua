local addonName, NS = ...

-- Account-wide defaults. History and settings both live under `global` (see docs/saved-variables.md).
NS.defaults = NS.defaults or {}
NS.defaults.global = {
  -- Version stamp for the persisted DB. 1.0.0 ships as the initial shape (1). NS:RunMigrations
  -- (core/Database.lua) reads/writes this field once at init — the idempotent seam future schema
  -- changes hook into; today its body is a no-op beyond stamping version 1.
  schemaVersion = 1,
  history = {},          -- array of loot records
  settings = {
    enabled          = true,
    qualityThreshold = 1,      -- Common (white) and above
    excludeQuestItems = true,  -- on by default (opt-out): drop Quest-class items at capture
    excludedSources  = {},     -- set of muted SourceType keys
    retentionDays    = 30,     -- 0 == keep Always
    windowScale      = 1.0,
    window           = {},     -- persisted position/size
  },
  minimap = { hide = false },  -- LibDBIcon state
  -- debug is session-only (NS.State.debug), never persisted here.
}
