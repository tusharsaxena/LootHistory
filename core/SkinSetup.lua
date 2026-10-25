local addonName, NS = ...

-- core/SkinSetup.lua — the LibKa0s-Skin-1.0 seam: which skin this addon wears (skinning-§3).
--
-- ── WHAT IT PUBLISHES ────────────────────────────────────────────────────────────────────────
--
--   NS.Skin                 the owner's facade, `Skin:For("LootHistory")`: the painting vocabulary
--                           (Shell, TitleBar, Button, ...) and Token / Color / Resolve /
--                           OnLooksChanged. Every surface that draws reads its colors here.
--   NS.SkinChoice()         the stored (source, skin) pair, read through NS.Schema:Get; "ka0s",
--                           "ka0s" before NS:InitDB has built the profile store.
--   NS.WriteSkinChoice(s,k) the write seam: both halves through NS.Schema:Set, the one seam
--                           `/lh set` and the panel already write through (architecture-§5).
--   NS.ApplySkinChoice(s,k) moves the applied skin: `Skin:SetChoice`, which resolves, repaints
--                           every frame recorded for this owner and THEN fires OnLooksChanged. No
--                           argument applies the stored pair (addon:OnInitialize, the profile
--                           events); a nil half keeps that half (each Appearance row's onChange).
--   NS.SKIN_SOURCE_OPTIONS  the source row's values, and NS.SKIN_OPTIONS the skin row's (every
--   NS.SKIN_OPTIONS         registered skin, in the library's order). settings/Schema.lua reads both.
--   NS.SKIN_FALLBACK        the host copy of the Ka0s Default tokens the degraded facade answers.
--   NS.SkinColor(name)      a color token as a call site writes it (three components when opaque),
--                           so a literal that became a token keeps its arity on Ka0s Default.
--   NS.SkinRGB(name)        a color token as a fresh { r, g, b } triple (the Insights and Holdings
--                           color tables' shape).
--   NS.SkinEscape(name)     a color token as a "|cffrrggbb" escape, rounded to the byte, so markup
--                           written as a literal keeps its bytes on Ka0s Default (|cffff5555).
--   NS.QualityColor(q)      an item quality's r, g, b: the skin's q.* token where it sets one (a
--                           legibility override), else the client's ITEM_QUALITY_COLORS; nil for none.
--
-- ── WHERE IT LOADS ───────────────────────────────────────────────────────────────────────────
--
-- After core/CoreSetup.lua, whose NS.ApplySkin the degraded facade's Shell routes to, and before
-- core/WidgetsSetup.lua and every module that builds a frame, so NS.Skin exists for all of them.
-- settings/Schema.lua reads NS.SKIN_OPTIONS at file load and is far below. The fixed name is the
-- one LibKa0s's docs/api/CONSUMERS.md cites. Nothing here reads the profile at load:
-- RegisterOwner calls `get` once, before AceDB exists, and it answers Ka0s Default; the profile's
-- pair is applied by NS.ApplySkinChoice right after NS:InitDB (core/LootHistory.lua).
--
-- ── WHY A ROW'S onChange PASSES ONE HALF ─────────────────────────────────────────────────────
--
-- The Appearance tab and another addon's "Copy to every Ka0s addon" both call Skin:SetChoice
-- FIRST and write the store after, one half at a time. A row reaction that re-applied the whole
-- stored pair would apply the half-written one in between: a second repaint, to a skin the player
-- never picked. Applying only the row's own half against the applied choice makes each write a
-- no-op (SetChoice is idempotent), so a pick is ONE effective SetChoice and one repaint, while a
-- bare `/lh set settings.appearance.skin obsidian` still repaints.
--
-- Nothing skin-related keys off SETTINGS_CHANGED. A surface that has to rebuild on a skin change
-- (markup built once, a pooled row) subscribes to NS.Skin.OnLooksChanged, which fires after the
-- new skin is resolved and the recorded frames are repainted.

local Skin = LibStub and LibStub("LibKa0s-Skin-1.0", true)

local SOURCE_PATH, SKIN_PATH = "settings.appearance.source", "settings.appearance.skin"
local DEFAULT = "ka0s"

-- The Ka0s Default tokens the DEGRADED facade answers, copied from the library and limited to the
-- ones this addon reads. They are the window edge NS.ApplySkin's fallback (core/CoreSetup.lua)
-- draws. Both arms publish the table, so tests/test_surface_parity.lua can hold each entry to the
-- live library's Ka0s Default value: a copy that drifts goes red there. A surface converted to a
-- token adds the token here in the same change.
NS.SKIN_FALLBACK = {
  ["win.bg"]        = { 0.06, 0.06, 0.08, 0.92 },
  ["win.border"]    = { 0, 0, 0, 1 },
  ["win.inner"]     = { 0.24, 0.24, 0.27, 0.85 },
  ["title.text"]    = { 1, 0.82, 0, 1 },
  ["divider"]       = { 0.24, 0.24, 0.27, 0.85 },
  -- The History window's chrome (LH-02): the tab labels and underline, the flat buttons, the plain
  -- search box, the footer and the strip tooltips' lines.
  ["tab.onText"]    = { 1, 0.82, 0, 1 },
  ["tab.text"]      = { 0.7, 0.7, 0.72, 1 },
  ["tab.onLine"]    = { 1, 0.82, 0, 1 },
  ["btn.bg"]        = { 0.1, 0.1, 0.12, 0.9 },
  ["btn.border"]    = { 0.24, 0.24, 0.27, 0.9 },
  ["btn.text"]      = { 1, 1, 1, 1 },
  ["btn.hover"]     = { 1, 0.82, 0, 1 },
  ["btn.icon"]      = { 0.85, 0.85, 0.85, 1 },
  ["input.bg"]      = { 0.1, 0.1, 0.12, 0.9 },
  ["input.border"]  = { 0.24, 0.24, 0.27, 0.9 },
  ["text.disabled"] = { 0.5, 0.5, 0.5, 1 },
  ["gtip.body"]     = { 0.9, 0.9, 0.9, 1 },
  -- The History table (LH-03): its header labels, arrows and chevrons, the pooled rows' stripe and
  -- hover, the cells' default text, the row menu (its edge is the muted-gold borderAlt), the
  -- tooltips' title and hint lines, the padlock's five bind states and the destructive entry.
  ["list.header.text"] = { 1, 0.82, 0, 1 },
  ["list.stripe"]   = { 1, 1, 1, 0.03 },
  ["list.hover"]    = { 1, 0.82, 0, 0.10 },
  ["text.body"]     = { 0.9, 0.9, 0.9, 1 },
  ["menu.bg"]       = { 0.06, 0.06, 0.08, 0.98 },
  ["menu.border"]   = { 0, 0, 0, 1 },
  ["menu.borderAlt"] = { 0.62, 0.5, 0.18, 1 },
  ["menu.hover"]    = { 1, 0.82, 0, 0.15 },
  ["gtip.title"]    = { 1, 0.82, 0, 1 },
  ["gtip.muted"]    = { 0.5, 0.5, 0.5, 1 },
  ["sem.boundNone"] = { 0.60, 0.60, 0.60, 0.40 },
  ["sem.boundBoE"]  = { 0.92, 0.92, 0.92, 0.95 },
  ["sem.boundBoP"]  = { 0.30, 0.82, 0.42, 1 },
  ["sem.boundWarband"] = { 0.30, 0.58, 0.98, 1 },
  ["sem.boundWarbandUE"] = { 0.95, 0.52, 0.12, 1 },
  ["sem.danger"]    = { 1, 1 / 3, 1 / 3, 1 },
  -- Insights, Timeline, Holdings and the AH price table (LH-04): the KPI cards and list panels, the
  -- section headings, rules and caveat, the chart chrome and series, the value / subtle / bright
  -- text grays, the toggle's box and tick, the tooltip value column, the AH info mark, and the
  -- meaning colors (gain and loss, the signed counts, the Warband, the AH status, Insights' bind
  -- split and its no-quality gray).
  ["text.muted"]    = { 0.7, 0.7, 0.72, 1 },
  ["text.heading"]  = { 1, 0.82, 0, 1 },
  ["text.headingAlt"] = { 0.91, 0.77, 0.42, 1 },
  ["text.accent"]   = { 1, 0.82, 0, 1 },
  ["text.value"]    = { 0.8, 0.8, 0.82, 1 },
  ["text.bodyAlt"]  = { 0.86, 0.86, 0.86, 1 },
  ["text.subtle"]   = { 0.85, 0.85, 0.85, 1 },
  ["text.highlight"] = { 1, 1, 1, 1 },
  ["gtip.value"]    = { 1, 1, 1, 1 },
  ["icon.hot"]      = { 1, 1, 1, 1 },
  ["icon.dim"]      = { 0.55, 0.55, 0.55, 1 },
  ["card.bg"]       = { 0.1, 0.1, 0.12, 0.85 },
  ["card.border"]   = { 0.24, 0.24, 0.27, 0.9 },
  ["panel.bg"]      = { 0.08, 0.08, 0.10, 0.6 },
  ["panel.border"]  = { 0.24, 0.24, 0.27, 0.7 },
  ["section.rule"]  = { 1, 0.82, 0, 0.35 },
  ["check.bg"]      = { 0.24, 0.24, 0.27, 1 },
  ["check.mark"]    = { 1, 0.82, 0, 1 },
  ["chart.axis"]    = { 0.45, 0.45, 0.5, 0.8 },
  ["chart.axisAlt"] = { 0.55, 0.55, 0.60, 0.9 },
  ["chart.bar"]     = { 0.40, 0.60, 0.95, 0.9 },
  ["chart.track"]   = { 1, 1, 1, 0.06 },
  ["chart.total"]   = { 1, 0.82, 0, 1 },
  ["chart.other"]   = { 0.55, 0.62, 0.72, 1 },
  ["chart.otherLine"] = { 0.7, 0.7, 0.72, 1 },
  ["chart.marker"]  = { 0.8, 0.8, 0.8, 0.6 },
  -- Insights' categorical palette: three seven-hue ramps (a list of colors, held entry by entry).
  ["chart.series"]  = {
    { 0.90, 0.25, 0.25, 1 }, { 0.95, 0.55, 0.15, 1 }, { 0.88, 0.82, 0.22, 1 }, { 0.35, 0.75, 0.38, 1 },
    { 0.28, 0.55, 0.90, 1 }, { 0.42, 0.38, 0.82, 1 }, { 0.72, 0.42, 0.86, 1 },
    { 0.97, 0.58, 0.58, 1 }, { 0.98, 0.76, 0.50, 1 }, { 0.94, 0.90, 0.55, 1 }, { 0.60, 0.87, 0.63, 1 },
    { 0.58, 0.76, 0.97, 1 }, { 0.68, 0.64, 0.92, 1 }, { 0.86, 0.68, 0.94, 1 },
    { 0.62, 0.18, 0.18, 1 }, { 0.70, 0.40, 0.10, 1 }, { 0.60, 0.56, 0.12, 1 }, { 0.18, 0.52, 0.28, 1 },
    { 0.15, 0.38, 0.66, 1 }, { 0.28, 0.24, 0.58, 1 }, { 0.50, 0.28, 0.62, 1 },
  },
  ["sem.good"]      = { 0.35, 0.80, 0.45, 1 },
  ["sem.bad"]       = { 1, 0.33, 0.33, 1 },
  ["sem.neutral"]   = { 0.62, 0.62, 0.66, 1 },
  ["sem.gold"]      = { 1, 0.86, 0.55, 1 },
  ["sem.warband"]   = { 0.25, 0.75, 0.95, 1 },
  ["sem.warbandAlt"] = { 0.4, 0.78, 1, 1 },
  ["sem.goodAlt"]   = { 0.25, 1, 0.25, 1 },
  ["sem.badAlt"]    = { 1, 0.25, 0.25, 1 },
  ["sem.unknown"]   = { 0.6, 0.6, 0.6, 1 },
  ["sem.statusOk"]  = { 0.30, 0.95, 0.35, 1 },
  ["sem.statusWarn"] = { 1, 0.82, 0.10, 1 },
  ["sem.statusBad"] = { 1, 0.32, 0.32, 1 },
  ["sem.boundBoPAlt"] = { 0.85, 0.45, 0.45, 1 },
  ["sem.boundBoEAlt"] = { 0.55, 0.80, 0.60, 1 },
  ["sem.boundNoneAlt"] = { 0.60, 0.60, 0.65, 1 },
}

--- A color token's components AS A CALL SITE WRITES THEM: r, g, b for an opaque color and r, g, b,
--- a otherwise (the library's own text and vertex rule), so a site that passed three components
--- before it read a token still passes three on Ka0s Default. nil for a token the skin leaves alone.
--- Read through NS.Skin at call time, so it answers the live skin, or the host copy degraded.
function NS.SkinColor(name)
  local r, g, b, a = NS.Skin.Color(name)
  if r == nil then return nil end
  if a == nil or a == 1 then return r, g, b end
  return r, g, b, a
end

--- A color token as a fresh { r, g, b } triple (nil for a token the skin leaves alone): the shape
--- the Insights and Holdings color tables have always handed their renderers, which read [1]..[3].
function NS.SkinRGB(name)
  local r, g, b = NS.Skin.Color(name)
  if r == nil then return nil end
  return { r, g, b }
end

--- A color token as a "|cffrrggbb" escape, each channel rounded to the nearest byte (1/3 is 55,
--- .5 is 80), so markup a call site wrote as a literal keeps its bytes on Ka0s Default. nil for a
--- token the skin leaves alone.
function NS.SkinEscape(name)
  local r, g, b = NS.Skin.Color(name)
  if r == nil then return nil end
  local function byte(v) return math.floor(v * 255 + 0.5) end
  return ("|cff%02x%02x%02x"):format(byte(r), byte(g), byte(b))
end

-- The six qualities the skin schema names (q.poor .. q.legendary); every other quality (artifact,
-- heirloom, token) is the client's color under every skin.
local QUALITY_TOKEN = { [0] = "q.poor", "q.common", "q.uncommon", "q.rare", "q.epic", "q.legendary" }

--- An item quality's r, g, b. The q.* tokens are legibility overrides only: Ka0s Default sets none
--- (the client's own colors), a light skin darkens the ones it must. nil for a quality the client
--- has no color for, so a caller keeps its own fallback.
function NS.QualityColor(q)
  local name = QUALITY_TOKEN[q]
  if name then
    local r, g, b = NS.Skin.Color(name)
    if r ~= nil then return r, g, b end
  end
  local c = ITEM_QUALITY_COLORS and q ~= nil and ITEM_QUALITY_COLORS[q]
  if c then return c.r, c.g, c.b end
  return nil
end

NS.SKIN_SOURCE_OPTIONS = {
  { value = "ka0s", text = "Ka0s skins" },
  { value = "eui",  text = "EllesmereUI" },
}

-- The skin row's values: every registered skin, Ka0s Default first. Without the library the one
-- skin the degraded facade can draw.
NS.SKIN_OPTIONS = {}
if Skin and type(Skin.Skins) == "function" then
  for _, def in ipairs(Skin:Skins()) do
    NS.SKIN_OPTIONS[#NS.SKIN_OPTIONS + 1] = { value = def.key, text = def.label or def.key }
  end
end
if #NS.SKIN_OPTIONS == 0 then NS.SKIN_OPTIONS[1] = { value = DEFAULT, text = "Ka0s Default" } end

--- The stored pair, lazily and nil-safely: Ka0s Default until the profile store exists.
function NS.SkinChoice()
  local S = NS.Schema
  if not (NS.db and S and S.Get) then return DEFAULT, DEFAULT end
  return S:Get(SOURCE_PATH) or DEFAULT, S:Get(SKIN_PATH) or DEFAULT
end

--- The write seam: both halves through NS.Schema:Set (validate, store, the [Set] line, onChange).
function NS.WriteSkinChoice(source, skin)
  local S = NS.Schema
  if not (NS.db and S and S.Set) then return end
  if source ~= nil then S:Set(SOURCE_PATH, source) end
  if skin ~= nil then S:Set(SKIN_PATH, skin) end
end

-- ── the degraded arm ─────────────────────────────────────────────────────────────────────────

if not Skin then
  local function color(name)
    local c = NS.SKIN_FALLBACK[name]
    if c then return c[1], c[2], c[3], c[4] or 1 end
  end
  local function noop() end
  local S = { owner = addonName, apiVersion = 3, FROM_SKIN = "@skin" }
  -- Every vocabulary name answers, and a primitive with no host meaning is a no-op that never
  -- raises (Shell, TitleBar, Divider, Button, Card, Panel, MenuFrame and Text draw today's look from
  -- the host copy). The list is LibKa0s-Skin-1.0's VOCAB; tests/test_surface_parity.lua holds this table
  -- to the live facade key for key.
  for _, name in ipairs({
    "Shell", "Panel", "Inset", "FadeRegions", "FadeNineSlice", "Button", "WhiteButtonLabel",
    "StateButtonLabel", "EditBox", "Checkbox", "Dropdown", "ScrollBar", "Tab", "SetTabSelection",
    "CloseButton", "PageButton", "SquareIcon", "SortHeaderBar", "Font", "White", "ApplyBarFill",
    "GetAccentColor", "GetPanelColor", "GetFont",
    "TitleBar", "Divider", "Footer", "Card", "Slider", "NavItem", "Drawer", "ListRow", "MenuFrame",
    "Tooltip", "Strip", "Cover", "Text", "ChartStyle", "BarStyle", "IconBorder", "GlowColor",
  }) do S[name] = noop end

  S.Token = function(name)
    local c = NS.SKIN_FALLBACK[name]
    return c
  end
  S.Color = color
  S.Resolve = function(kind, value, fromSkin)
    if fromSkin or value == S.FROM_SKIN then return S.Token(kind) end
    return value
  end
  S.OnLooksChanged = function(fn) return fn end   -- the skin never changes without the library
  S.IsEnabled = function() return false end
  S.GetStyle = function() return "ka0s:" .. DEFAULT end

  -- The window edge is CoreSetup's pre-library skin, byte for byte what a working install draws.
  S.Shell = function(frame) if NS.ApplySkin then NS.ApplySkin(frame) end end
  -- A title bar's text in the title color, the one NS.ApplySkin gives a shelled frame's `title`.
  S.TitleBar = function(bar, opts)
    local fs = (type(opts) == "table" and opts.text) or (bar and (bar.title or bar.text))
    if fs and fs.SetTextColor then fs:SetTextColor(color("title.text")) end
  end
  S.Text = function(fs, role)
    local r, g, b, a = color(role == "title" and "title.text" or ("text." .. tostring(role)))
    if r and fs and fs.SetTextColor then fs:SetTextColor(r, g, b, a) end
  end
  -- A rule: a texture colored in place, or a frame given one texture filling it (made once). The
  -- History window's divider is a frame (modules/Browser.lua), so a degraded install still draws it.
  local rules = setmetatable({}, { __mode = "k" })
  S.Divider = function(target, opts)
    if type(target) ~= "table" then return end
    local r, g, b, a = color(type(opts) == "table" and opts.token or "divider")
    if not r then return end
    local tex = target
    if type(target.GetObjectType) == "function" and target:GetObjectType() ~= "Texture" then
      tex = rules[target]
      if not tex and type(target.CreateTexture) == "function" then
        tex = target:CreateTexture(nil, "ARTWORK")
        if type(tex) == "table" and tex.SetAllPoints then tex:SetAllPoints(target) end
        rules[target] = tex
      end
    end
    if type(tex) == "table" and type(tex.SetColorTexture) == "function" then tex:SetColorTexture(r, g, b, a) end
  end
  -- The flat button (modules/BrowserWidgets.lua B.MakeFlatButton) as it was drawn before the skin
  -- engine: the WHITE8X8 box, a white label, gold under the pointer, the mark at .85.
  local WHITE = "Interface\\Buttons\\WHITE8X8"
  -- The flat-control box every one of these drew: WHITE8X8 under a 1px edge, inset by one.
  local function box(frame, fill, edge)
    if type(frame) ~= "table" or type(frame.SetBackdrop) ~= "function" then return false end
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    frame:SetBackdropColor(color(fill))
    frame:SetBackdropBorderColor(color(edge))
    return true
  end
  -- Insights' KPI card (modules/Analytics.lua) and list panel (modules/AnalyticsCharts.lua) as they
  -- were drawn before the skin engine; a card's `opts.title` in the heading gold.
  S.Card = function(frame, opts)
    box(frame, "card.bg", "card.border")
    local fs = type(opts) == "table" and opts.title
    if type(fs) == "table" and fs.SetTextColor then fs:SetTextColor(NS.SkinColor("text.heading")) end
  end
  S.Panel = function(frame) box(frame, "panel.bg", "panel.border") end
  S.Button = function(btn)
    if not box(btn, "btn.bg", "btn.border") then return end
    local fs = rawget(btn, "text")
    if type(fs) == "table" and fs.SetTextColor then fs:SetTextColor(NS.SkinColor("btn.text")) end
    local icon = rawget(btn, "icon")
    if type(icon) == "table" and icon.SetVertexColor then icon:SetVertexColor(NS.SkinColor("btn.icon")) end
    if type(btn.HookScript) == "function" and type(fs) == "table" and fs.SetTextColor then
      btn:HookScript("OnEnter", function() fs:SetTextColor(NS.SkinColor("btn.hover")) end)
      btn:HookScript("OnLeave", function() fs:SetTextColor(NS.SkinColor("btn.text")) end)
    end
  end
  -- The History row menu (modules/BrowserTable.lua EnsureRowMenu) as it was drawn before the skin
  -- engine: the WHITE8X8 box with no insets, its fill, and the muted-gold edge (`alt`).
  S.MenuFrame = function(frame, opts)
    if type(frame) ~= "table" or type(frame.SetBackdrop) ~= "function" then return end
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(color("menu.bg"))
    frame:SetBackdropBorderColor(color(type(opts) == "table" and opts.alt and "menu.borderAlt" or "menu.border"))
  end
  S.GetPanelColor = function() return color("win.bg") end
  S.GetFont = function() return STANDARD_TEXT_FONT end
  S.ChartStyle = function() return {} end
  S.BarStyle = function() return {} end

  NS.Skin = S
  function NS.ApplySkinChoice() return false, false end
  return
end

-- ── the live seam ────────────────────────────────────────────────────────────────────────────

NS.Skin = Skin:For(addonName)
Skin:RegisterOwner(addonName, {
  label = NS.BRAND,
  get = NS.SkinChoice,
  set = NS.WriteSkinChoice,
})

-- The one line a reload request earns on the path that has no popup of its own (a profile event
-- leaving an EllesmereUI that painted this session). The Appearance tab raises the library's popup
-- for its own picks.
local RELOAD_LINE = NS.L and NS.L["Reload your interface (/reload) to finish changing the skin."]
  or "Reload your interface (/reload) to finish changing the skin."

function NS.ApplySkinChoice(source, skin)
  if source == nil and skin == nil then source, skin = NS.SkinChoice() end
  local changed, reload = Skin:SetChoice(addonName, source, skin)
  if reload and NS.Print then NS.Print(RELOAD_LINE) end
  return changed, reload
end
