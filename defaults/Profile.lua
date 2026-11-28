local _, NS = ...

-- Profile defaults: every setting but one (savedvariables-§2). A profile holds what the player
-- CONFIGURED: the schema rows under `settings`, the three id filter lists, the window geometry and
-- the saved table view. What the account RECORDED stays account-wide in defaults/Global.lua, and so
-- does the one setting that governs it, `retentionDays` (owner decision D6), so switching, copying
-- or resetting a profile never touches the loot history or what the next prune deletes
-- (docs/profiles.md).
NS.defaults = NS.defaults or {}

-- One loot toast feed's defaults (#38, toast spec §9.2), with `over` laid on top. Each call builds
-- fresh tables, so no two feeds (and no profile) share a nested table.
local function feed(over)
  local f = {
    enabled = false, slot = "BOTTOMRIGHT", x = 0, y = 0, grow = "up", align = "left", iconSide = "left",
    kinds = { item = true, money = true, currency = true, reputation = true, appearance = true, xp = true, skill = true },
    price = "both", ilvl = true, counts = true, source = true, minQuality = 0, hideSources = {},
    hl = { mount = true, mountSound = "", legendary = true, legendarySound = "",
           upgrade = true, upgradeSound = "", appearance = true, appearanceSound = "" },
    bgColorFromSkin = true, bgType = "solid", useClassColorBgColor = false, useClassColorBgColor2 = false,
    bgColor = { r = 0.07, g = 0.08, b = 0.1, a = 0.92 }, bgColor2 = { r = 0.12, g = 0.13, b = 0.16, a = 0.92 },
    bgTexture = "Solid",
    borderStyle = "None", borderSize = 1, borderColor = { r = 0.23, g = 0.24, b = 0.28, a = 1 },
    useClassColorBorder = false, borderStyleFromSkin = true, borderColorFromSkin = true, borderByQuality = false,
    font = "", fontSize = 13, fontSize2 = 11, fontColor = { r = 0.9, g = 0.89, b = 0.84, a = 1 },
    useClassColorFont = false, fontFlags = "@skin", fontShadow = true,
    fontFromSkin = true, fontColorFromSkin = true, fontShadowFromSkin = true,
    width = 320, rowHeight = 48, iconSize = 36, padding = 6, gap = 5,
    colors = { xp = { r = 0.898, g = 0.549, b = 1, a = 1 }, xpFromSkin = true,
               rep = { r = 0.31, g = 0.55, b = 1, a = 1 }, repFromSkin = true,
               skill = { r = 0.478, g = 0.655, b = 1, a = 1 }, skillFromSkin = true },
    enter = "right", enterTime = 0.3, hold = 5, fade = 1, pulse = true, timerBar = false, smooth = true,
    shown = 5, merge = 3, showInCombat = true, clickThrough = false, pin = true,
  }
  for k, v in pairs(over) do f[k] = v end
  return f
end

NS.defaults.profile = {
  -- Item-id filter lists (issue #14). Blacklisted ids are never recorded; rows already stored stay
  -- visible (point-in-time: a list change never hides or reveals history). Whitelisted ids are
  -- always recorded, bypassing the quality/source/quest gates. NOT Schema rows: an architecture-§5
  -- structural registry whose one writer is NS.Filters, driven by the settings ▸ Filters tab and
  -- the History right-click menu. The defaults ship all three sets empty.
  blacklist = {},        -- { [itemID] = true } — drop on capture (stored rows stay visible)
  whitelist = {},        -- { [itemID] = true } — always record, even below the gates
  currencyBlacklist = {},  -- { [currencyID] = true } — currencies never recorded on capture
  -- `savedViews` (one remembered view per browser tab, { [tab] = view }; schema v14 split the single
  -- `savedView` into it) is profile-scoped too, and deliberately undeclared: a tab's slot exists only
  -- once the player clicks the filter bar's Save on that tab, or the Timeline remembers a pick
  -- (modules/Browser.lua).
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
    -- Ammunition and thrown weapons (arrows, bullets, throwing knives): not recorded, captured or in
    -- the ledger. On by default on WoW Forever, where every shot spends one and the rows flood the
    -- history (the owner, 2026-11-27: "too spammy otherwise"); Retail has neither.
    excludeAmmo      = NS.Compat.ClientKey() == "forever",
    recordCurrency   = true,   -- record looted currency (Type=Currency rows); source-muted like items
    recordReputation = true,   -- reputation gains and losses as Type=Reputation rows
    recordAppearances = true,  -- (Retail) collected/removed appearances as Type=Appearance rows
    trackLedger      = true,   -- holdings + (Phase 2) gains/losses/transfers/gold; off = legacy gains-only
    recordGold       = true,   -- gold gains/losses as ledger rows (holdings track gold regardless)
    showTransfers    = true,   -- History's Direction filter includes transfers by default
    excludedSources  = {},     -- set of muted SourceType keys
    -- NO retentionDays here: it governs the account-wide history, so it is account-wide too
    -- (defaults/Global.lua, D6).
    windowScale      = 1.0,
    -- History-table row height, in pixels. Was `local ROW_H = 18` in modules/BrowserTable.lua and
    -- ships as the same 18, so a player who never touches it sees the table it always drew.
    rowHeight        = 18,
    timelineMaxLines = 8,      -- lines besides the Total on the Timeline (2-16)
    -- The pace of a playing simulation: seconds between steps, 0.5-10 in steps of 0.5
    -- (modules/Sim.lua Host.StepDelay). A new key with a default, so AceDB merges it into every
    -- existing profile and no migration is owed.
    sim              = { stepDelay = 1 },
    -- The holdings block in item and currency tooltips (#34). New keys with defaults: AceDB merges
    -- them into every existing profile, so no migration is owed.
    tooltip          = { enabled = true, containers = true, warband = true, totalMin2 = true, modifier = "none" },
    -- The loot toast feeds (#38, toast spec §9.2): Main on, Progress and Third off (T15). New keys
    -- with defaults: AceDB merges them into every existing profile, so no migration is owed. The
    -- gain feed reads `enabled` and `kinds` from M3.1 on; the rows that write them are M3.6's.
    toasts = {
      hideAlerts = false,
      feeds = {
        main     = feed{ enabled = true, slot = "BOTTOMRIGHT", x = -220, y = 180, grow = "up" },
        progress = feed{ slot = "TOP", x = 0, y = -160, grow = "down",
                         kinds = { item = false, money = false, currency = false, reputation = true,
                                   appearance = false, xp = true, skill = true } },
        extra    = feed{ slot = "TOPLEFT", x = 0, y = -120, grow = "down" },
      },
    },
    -- The skin this addon wears (skinning-§3; owner ruling R1, per addon): where it comes from
    -- ("ka0s", the Ka0s skins, or "eui", EllesmereUI's) and which Ka0s skin. "ka0s"/"ka0s" is Ka0s
    -- Default, today's look. The skin's default is the client's, NS.DEFAULT_SKIN (core/SkinSetup.lua,
    -- Skin:DefaultSkin, skinning-§2): Ka0s Default on Retail, WoW Forever on Forever. New keys with defaults, so AceDB merges them into every existing
    -- profile and no migration is owed. Applied through core/SkinSetup.lua. The two exceptions
    -- (the Skin tab's Scope, LibKa0s-Skin-1.0 minor 5): leave the settings panel the client's,
    -- leave every font the client's. New keys with defaults too: a new profile leaves the settings
    -- panel the client's and skins the fonts (the owner's call, 2026-10-27). The font and texture
    -- overrides (the Skin tab's Font and texture, LibKa0s-Skin-1.0 minor 6): an LSM key each, ""
    -- for the skin's own. `pickerSeen`: the first-run skin picker was closed on this profile, so a
    -- new or reset profile shows it once (LibKa0s OptionsSkinPicker 1). `outline`: the Skin tab's
    -- Font outline (LibKa0s-Skin-1.0 minor 9, ruling D-06), "all" text, "hud" text
    -- only (the default since LibKa0s v1.83.0), or "off".
    appearance       = { source = "ka0s", skin = NS.DEFAULT_SKIN or "ka0s", ignorePanel = true, ignoreFonts = false,
                         font = "", texture = "", outline = "hud", pickerSeen = false },
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
      -- four non-default sources until the AH price page's ReconcilePriority happened to run.
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
