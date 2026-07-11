local addonName, NS = ...

-- Account-wide defaults. History and settings both live under `global` (see TECHNICAL_DESIGN §3.2).
NS.defaults = NS.defaults or {}
NS.defaults.global = {
  schemaVersion = 3,
  history = {},          -- array of loot records
  settings = {
    enabled          = true,
    qualityThreshold = 0,      -- Poor (grey) and above — record everything (testing default)
    excludedSources  = {},     -- set of muted SourceType keys
    retentionDays    = 30,     -- 0 == Never
    windowScale      = 1.0,
    window           = {},     -- persisted position/size
  },
  minimap = { hide = false },  -- LibDBIcon state
  -- debug is session-only (NS.State.debug), never persisted here.
}
