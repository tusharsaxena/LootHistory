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
  ["win.bg"]     = { 0.06, 0.06, 0.08, 0.92 },
  ["win.border"] = { 0, 0, 0, 1 },
  ["win.inner"]  = { 0.24, 0.24, 0.27, 0.85 },
  ["title.text"] = { 1, 0.82, 0, 1 },
  ["divider"]    = { 0.24, 0.24, 0.27, 0.85 },
}

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
  -- raises. The list is LibKa0s-Skin-1.0's VOCAB; tests/test_surface_parity.lua holds this table
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
