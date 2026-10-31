local _, NS = ...
NS.Analytics = NS.Analytics or {}
local Analytics = NS.Analytics

-- The Insights tab's seam onto LibKa0s-Charts-1.0 (LibKa0s#66). The library owns the pooled widgets,
-- the section chrome and the renderers; this file owns the host table, the one LOOT / CURRENCY
-- divider size, the "by Character" companion and the Insights half of a skin switch. The cards stay
-- in modules/Analytics.lua: they wear the skin's Card, and the library's stat card takes the Panel.
--
-- A library-absent install has no charts (Analytics:Attach says so); this file then only publishes
-- nil. Loaded AFTER modules/Analytics.lua, which reaches all of this at call time.
local Charts = LibStub and LibStub("LibKa0s-Charts-1.0", true)
Analytics._chartsLib = Charts

-- The hover lines stay core/Compat.lua's, the one place tooltip lines read gtip.*: a bar's label in
-- gtip.title, a legend chip's in gtip.body, a segment's and a list row's in gtip.value, all pinned
-- to the cursor, and a strip column's above the column.
local function tipToken(owner)
  if owner.track then return "gtip.title" end
  if owner.sw then return "gtip.body" end
  return "gtip.value"
end

local function showTip(owner, lines, anchor)
  if anchor == "ANCHOR_TOP" then
    NS.Compat.ShowLineTooltip(owner, lines[1], "gtip.value", anchor)
  else
    NS.Compat.ShowCursorTooltip(owner, lines[1], tipToken(owner))
  end
end

local function hideTip() NS.Compat.HideTooltip() end

-- A bar of data goes through NS.SkinBar, which keeps the flat fill for a target that takes no texture.
local function barFill(tex, c, a) NS.SkinBar(tex, c[1], c[2], c[3], a or c[4] or 1) end

--- The chart context `inst` draws through, one per content frame. A skin switch reaches it after
--- Analytics:Reskin (the context subscribes later), so the refresh here draws the synced palette.
function Analytics._newCharts(inst, content)
  return Charts:New(content, {
    owner = NS.Skin and NS.Skin.owner, pool = NS.Pool, tip = showTip, hideTip = hideTip,
    barFill = barFill,
    fonts = { divider = "GameFontNormal" }, -- _chartDivider scales it, as this tab always has
    onReskin = function()
      if inst.pane and inst.pane:IsVisible() then inst:Refresh() end
    end,
  })
end

--- A full-width divider with its title half again the skin's size.
function Analytics._chartDivider(ctx, content, title)
  local d = ctx:sectionDivider(content, title)
  local file, size, flags = d.fs:GetFont()
  d.fs:SetFont(file, size * 1.5, flags)
  return d
end

-- Render a "… by Character" companion: a per-character stacked bar (segments = a chart's categories,
-- colored by colorFn, hover-tipped via labelFn) plus a color-swatch legend naming each category.
-- catOrder is the global category order; colorFn(k)/labelFn(k) map a category key to color/label.
function Analytics:renderCharCompanion(poolKey, legendKey, header, matrix, catOrder, colorFn, labelFn, valueFmt, y, w, pad)
  local rows = Analytics._buildCharStackRows(matrix or {}, self.stats.byChar, catOrder, colorFn, valueFmt, labelFn)
  y = self.charts:renderStackedBarSection(self.pool[poolKey], header, rows, y, w, pad)
  if #rows > 0 then
    local legend = {}
    for _, k in ipairs(catOrder) do legend[#legend + 1] = { label = labelFn(k), color = colorFn(k) } end
    y = self.charts:renderLegend(self.pool[legendKey], legend, y, w, pad)
  end
  return y
end

-- Hide every chart section (used for the empty-range state).
function Analytics:HideAllCharts()
  for _, h in pairs(self.headers) do h:Hide() end
  self.dayStrip:Hide(); self.valueStrip:Hide(); self.hourStrip:Hide()
  self.zonePanel:Hide(); self.itemPanel:Hide(); self.itemValuePanel:Hide()
  self.currencyStrip:Hide()
  self.lootDivider:Hide(); self.currencyDivider:Hide()
  if Analytics._ledger then Analytics._ledger.Hide(self) end
end

-- ── the skin (LH-04) ──────────────────────────────────────────────────────────────────────────
--
-- The context repaints its own chrome and pools and then refreshes (onReskin above). This walk is
-- what stays Insights' own: the palette and the meaning colors (synced FIRST, whether or not the
-- pane was ever built, so a first build after a switch draws the new skin), the cards, the empty
-- line and the ledger half's chrome. Fires after the new skin is resolved (NS.Skin.OnLooksChanged).
function Analytics:Reskin()
  Analytics._syncSkinColors()
  if not self.content then return end
  -- A headline card's base face is read again here, after the repaint: Layout puts it back before it
  -- shrinks to fit, so a face saved at build time would undo a live outline change or skin switch.
  for _, c in pairs(self.cards or {}) do
    c.caption:SetTextColor(NS.SkinColor("text.disabled"))
    if c.bigStr then c.fontFile, c.baseSize, c.fontFlags = c.num:GetFont() end
  end
  self.emptyText:SetTextColor(NS.SkinColor("text.disabled"))
  if Analytics._ledger then Analytics._ledger.Reskin(self) end
end

if NS.Skin then NS.Skin.OnLooksChanged(function() Analytics:Reskin() end) end
