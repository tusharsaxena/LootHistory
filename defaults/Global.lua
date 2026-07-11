local addonName, NS = ...

-- Account-wide defaults. History and settings both live under `global` (see TECHNICAL_DESIGN §3.2).
NS.defaults = NS.defaults or {}
NS.defaults.global = {
  schemaVersion = 1,
  history = {},          -- array of loot records
  settings = {
    enabled          = true,
    qualityThreshold = 2,      -- Uncommon (green) and above
    excludedSources  = {},     -- set of muted SourceType keys
    retentionDays    = 30,     -- 0 == Never
    windowScale      = 1.0,
    window           = {},     -- persisted position/size
  },
  minimap = { hide = false },  -- LibDBIcon state
  debug = false,
}
