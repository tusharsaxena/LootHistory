local _, NS = ...

-- The Profiles sub-page (options-ui-§3): AceDBOptions-3.0's own profile manager -- choose, create,
-- copy, delete and reset -- drawn by AceConfigDialog-3.0 into a canvas subcategory named
-- "Profiles". The ONE use of AceConfig in this addon (options-ui-§3's SHOULD); every other page is
-- raw AceGUI through LibKa0s-Options-1.0.
--
-- What a profile holds and what stays account-wide is docs/profiles.md: every setting, the three id
-- filter lists, the saved table view and the window geometry are per profile; the loot history and
-- the minimap button are not.
--
-- REGISTERED LAST, from P:Register (settings/Panel.lua), after General -- not at this file's load --
-- so the Settings tree order is that function's and cannot follow the TOC. The page has no Defaults
-- button (AceDBOptions carries its own Reset Profile), and no schema row lives here, so the global
-- reset has nothing of it to walk; the veto that says so is S.VetoedFromResetAll
-- (settings/Schema.lua).

NS.ProfilesPage = NS.ProfilesPage or {}
local PP = NS.ProfilesPage

-- The AceConfig registry key. Addon-scoped, so two addons' Profiles pages cannot collide on it.
PP.APP = "LootHistory-Profiles"

--- The builder handed to O.RegisterOptionsPage: answers the subcategory, or nil when a library the
--- page needs is missing (a legitimate opt-out, options-ui-§5, never an error).
function PP.Build(mainCategory)
  if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then return nil end
  if not LibStub then return nil end
  local AceDBOptions    = LibStub("AceDBOptions-3.0",    true)
  local AceConfig       = LibStub("AceConfig-3.0",       true)
  local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
  local AceGUI          = NS.AceGUI or LibStub("AceGUI-3.0", true)
  if not (AceDBOptions and AceConfig and AceConfigDialog and AceGUI) then return nil end
  if not (NS.db and NS.db.profile) then return nil end
  local O = NS.Options

  -- AceDBOptions answers a fully formed options table over the db: the current-profile picker,
  -- New, Copy From, Delete and Reset Profile. Registered once, when the page is built.
  AceConfig:RegisterOptionsTable(PP.APP, AceDBOptions:GetOptionsTable(NS.db))

  local ctx = O.CreatePanel("LootHistoryProfilesPanel", NS.L["Profiles"], {
    pageKey        = "Profiles",
    defaultsButton = false,   -- AceDBOptions' own Reset Profile is this page's reset
  })
  PP.ctx = ctx

  -- An AceGUI SimpleGroup on the page body: AceConfigDialog:Open renders into any AceGUI container,
  -- so the profile manager lands inside this canvas instead of opening a window of its own.
  local container = AceGUI:Create("SimpleGroup")
  container:SetLayout("Fill")
  container.frame:SetParent(ctx.body)
  container.frame:ClearAllPoints()
  container.frame:SetPoint("TOPLEFT",     ctx.body, "TOPLEFT",      8, -8)
  container.frame:SetPoint("BOTTOMRIGHT", ctx.body, "BOTTOMRIGHT", -8, 8)

  -- Through O.SetRenderer rather than a hand-parked OnShow (options-ui-§11): the Blizzard AddOns
  -- sidebar reaches a canvas panel without going through OpenOptionsPanel, and the renderer is what
  -- puts the library's combat lock in front of that path. The container is SHOWN on every render:
  -- AceGUI:Release hides a frame before pooling it, and neither AceGUI:Create nor
  -- AceConfigDialog:Open shows it again, so a pooled group would leave the page blank.
  O.SetRenderer(ctx, function()
    container.frame:Show()
    AceConfigDialog:Open(PP.APP, container)
  end)
  -- Re-render on the next show, so the picker reads the profile a slash verb or another page moved
  -- to while this one was hidden.
  ctx.panel:SetScript("OnHide", function() O.RefreshPanel(ctx, true) end)

  return Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, NS.L["Profiles"])
end
