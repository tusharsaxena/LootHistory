local _, NS = ...

-- Profile defaults: every setting but one (savedvariables-§2). A profile holds what the player
-- CONFIGURED: the schema rows under `settings`, the three id filter lists, the window geometry and
-- the saved table view. What the account RECORDED stays account-wide in defaults/Global.lua, and so
-- does the one setting that governs it, `retentionDays` (owner decision D6), so switching, copying
-- or resetting a profile never touches the loot history or what the next prune deletes
-- (docs/profiles.md).
NS.defaults = NS.defaults or {}
NS.defaults.profile = {
  -- Item-id filter lists (issue #14). Blacklisted ids are never recorded; rows already stored stay
  -- visible (point-in-time: a list change never hides or reveals history). Whitelisted ids are
  -- always recorded, bypassing the quality/source/quest gates. NOT Schema rows: an architecture-§5
  -- structural registry whose one writer is NS.Filters, driven by the settings ▸ Filters tab and
  -- the History right-click menu. The defaults ship all three sets empty.
  blacklist = {},        -- { [itemID] = true } — drop on capture (stored rows stay visible)
  whitelist = {},        -- { [itemID] = true } — always record, even below the gates
  currencyBlacklist = {},  -- { [currencyID] = true } — currencies never recorded on capture
  -- `savedView` (the remembered table view) is profile-scoped too, and deliberately undeclared: it
  -- exists only once the player clicks the filter bar's Save (modules/Browser.lua).
  settings = {
    enabled          = true,
    -- ── the Master controls tab (options-ui-§15) ──
    -- General visibility is a DROPDOWN, not a boolean, because a boolean can only ever answer two
    -- of the four. This addon never shipped a `show only in combat` checkbox, so the key is NEW
    -- rather than migrated: an install from before this release simply has no `visibility` and
    -- AceDB merges "always" in, which is what it always did.
    visibility       = "always",
    -- ADDON-WIDE, and distinct from `windowScale` below. `scale`/`alpha` govern every frame this
    -- addon draws (the History window and the export modal); `windowScale` is the History window's
    -- OWN scale and multiplies on top of it (options-ui-§15: the per-instance rows stay on the
    -- instance, the master rows are the addon-wide ones).
    scale            = 1.0,
    alpha            = 1.0,
    locked           = false,  -- stop the History window and the export modal being dragged
    qualityThreshold = 1,      -- Common (white) and above
    excludeQuestItems = true,  -- on by default (opt-out): drop Quest-class items at capture
    recordCurrency   = true,   -- record looted currency (Type=Currency rows); source-muted like items
    trackLedger      = true,   -- holdings + (Phase 2) gains/losses/transfers/gold; off = legacy gains-only
    recordGold       = true,   -- gold gains/losses as ledger rows (holdings track gold regardless)
    showTransfers    = false,  -- History's Direction filter includes transfers by default
    excludedSources  = {},     -- set of muted SourceType keys
    -- NO retentionDays here: it governs the account-wide history, so it is account-wide too
    -- (defaults/Global.lua, D6).
    windowScale      = 1.0,
    -- History-table row height, in pixels. Was `local ROW_H = 18` in modules/BrowserTable.lua and
    -- ships as the same 18, so a player who never touches it sees the table it always drew.
    rowHeight        = 18,
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
}

-- Copied element-by-element rather than aliased: AceDB hands the defaults table straight to the
-- live profile for keys it has to materialize, and the cascade is reordered in place by the AH
-- Price page — an alias would let a user's reorder rewrite the shipped constant for the session.
for i, tag in ipairs(NS.Constants.AUCTION_PRIORITY_DEFAULT) do
  NS.defaults.profile.settings.auction.priority[i] = tag
end
