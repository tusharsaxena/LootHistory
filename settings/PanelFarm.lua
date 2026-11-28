local _, NS = ...
NS.FarmPage = NS.FarmPage or {}
local FPg = NS.FarmPage
local O = NS.Options

-- The Farm page (#39, farm spec docs/superpowers/specs/2026-11-27-39-farm-mode-design.md §9.3; D23,
-- options-ui-§13/§14): a settings page of its own, between Toasts and Profiles, whose strip is
-- settings/SchemaFarm.lua's two tabs, General first. The shape is NS.ToastsPage.Build's without the
-- banner: every row is an ordinary schema row, so the generic tabbed renderer draws them all. The farm
-- key bindings are on General > Keybindings (O.KeybindingsTab reads NS.BINDINGS); no third copy here.
--
-- The page Defaults is page-wide (options-ui-§13): every Farm row back to its default, in one bulk
-- bracket, which the seam's resetExempt veto keeps off `settings.farm.keep` (account-wide, D18).

FPg.DEFAULTS_TOOLTIP = "Restores every setting on the Farm page to its default. Sessions kept per "
  .. "character is account-wide and stays as it is."

--- The page builder (settings/Panel.lua P:Register, after Toasts and before Profiles).
function FPg.Build(mainCategory)
  local ctx = O.CreatePanel(nil, "Farm", {
    pageKey = NS.SchemaFarm.PAGE, defaultsButton = true,
    defaultsTooltip = FPg.DEFAULTS_TOOLTIP .. " " .. O.KEYBINDS_UNCHANGED,
  })
  FPg.ctx = ctx
  ctx.panel.defaultsOnClick = function() O.RestoreDefaults(NS.SchemaFarm.PAGE, ctx) end
  O.SetRenderer(ctx, function(c)
    O.ClearScroll(c)
    O.RenderTabbedSchema(c, NS.SchemaFarm.PAGE)
  end)
  Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, "Farm")
end
