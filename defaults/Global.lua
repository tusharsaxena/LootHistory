local addonName, NS = ...

-- Account-wide defaults. History and settings both live under `global` (see docs/schema.md).
NS.defaults = NS.defaults or {}
NS.defaults.global = {
  -- Version stamp for the persisted DB. 1.0.0 ships as the initial shape (1). NS:RunMigrations
  -- (core/Database.lua) reads/writes this field once at init — the idempotent seam future schema
  -- changes hook into; NS:RunMigrations runs once at init and ships a v1→v2 migration that strips
  -- the retired per-record `viaWhitelist` field and bumps the stamp to 2 (non-destructive).
  schemaVersion = 1,
  history = {},          -- array of loot records
  -- Item-id filter lists (issue #14). Blacklisted ids are never recorded and their existing rows
  -- are hidden from every view (but kept in history — restorable by removing the id). Whitelisted
  -- ids are always recorded, bypassing the quality/source/quest gates. Managed via a custom UI
  -- (settings ▸ Filters) + the History right-click menu — NOT Schema rows, so they are an
  -- architecture-§5 carve-out like `window`/`savedView` (mutated directly, not via Schema:Set).
  blacklist = {},        -- { [itemID] = true } — drop on capture + hide existing rows
  whitelist = {},        -- { [itemID] = true } — always record, even below the gates
  currencyBlacklist = {},  -- { [currencyID] = true } — currencies never recorded on capture
  settings = {
    enabled          = true,
    qualityThreshold = 1,      -- Common (white) and above
    excludeQuestItems = true,  -- on by default (opt-out): drop Quest-class items at capture
    recordCurrency   = true,   -- record looted currency (Type=Currency rows); source-muted like items
    excludedSources  = {},     -- set of muted SourceType keys
    retentionDays    = 30,     -- 0 == keep Always
    windowScale      = 1.0,
    window           = {},     -- persisted position/size
    auction = {                -- AH-price cascade (see modules/AuctionPrice.lua)
      enabled = true,
      capture = {   -- which price keys to gather (set of tags)
        ["auctionator:minbuyout"] = true, ["tsm:dbmarket"] = true, ["tsm:dbminbuyout"] = true,
        ["tsm:dbregionmarketavg"] = true, ["tsm:dbregionminbuyoutavg"] = true,
        ["oribos:market"] = true, ["oribos:region"] = true,
      },
      -- Ordered provider:key selection list (carve-out; reordered via the panel UI). Filled below
      -- from its ONE declaration, core/Constants.lua's AUCTION_PRIORITY_DEFAULT — never restated
      -- here. A second literal drifted: this file shipped the 7 default-collected tags while the
      -- constant carried all 11, so `AuctionPrice:Pick` walked a cascade that could not reach the
      -- four non-default sources until the AH Price page's ReconcilePriority happened to run.
      priority = {},
    },
  },
  minimap = { hide = false },  -- LibDBIcon state
  -- debug is session-only (NS.State.debug), never persisted here.
}

-- Copied element-by-element rather than aliased: AceDB hands the defaults table straight to the
-- live profile for keys it has to materialize, and the cascade is reordered in place by the AH
-- Price page — an alias would let a user's reorder rewrite the shipped constant for the session.
for i, tag in ipairs(NS.Constants.AUCTION_PRIORITY_DEFAULT) do
  NS.defaults.global.settings.auction.priority[i] = tag
end
