local addonName, NS = ...

-- Account-wide defaults. History and settings both live under `global` (see TECHNICAL_DESIGN §3.2).
NS.defaults = NS.defaults or {}
NS.defaults.global = {
  -- Version stamp for the persisted DB. 0.1.0 ships as the initial shape (1). A migration
  -- runner is a post-release concern: this addon is unreleased, so no upgrade path is needed
  -- yet. When the first schema change ships post-release, add a runner that reads this field.
  schemaVersion = 1,
  history = {},          -- array of loot records
  settings = {
    enabled          = true,
    qualityThreshold = 1,      -- Common (white) and above
    excludedSources  = {},     -- set of muted SourceType keys
    retentionDays    = 30,     -- 0 == keep Always
    windowScale      = 1.0,
    window           = {},     -- persisted position/size
  },
  minimap = { hide = false },  -- LibDBIcon state
  -- debug is session-only (NS.State.debug), never persisted here.
}
