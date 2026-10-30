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
--   NS.WriteSkinChoice(s,k,i,m) the write seam: both halves through NS.Schema:Set, the one seam
--                           `/lh set` and the panel already write through (architecture-§5); `i`,
--                           the Scope's `{ panel, fonts }`, writes the two exceptions, and `m`, the
--                           Font and texture section's `{ font, texture }` (LibKa0s-Skin-1.0 minor
--                           6), writes the two overrides, "" for false (the skin's own); its
--                           `outline`, when not nil (Skin minor 9), writes the Font outline.
--   NS.ApplySkinIgnore(p,f) moves the applied exceptions: `Skin:SetIgnore`, live; no argument
--                           applies the stored pair, a nil half keeps that half.
--   NS.SkinOverride()       the stored overrides: font, texture, each an LSM key or false for the
--                           skin's own; false, false before NS:InitDB.
--   NS.ApplySkinOverride(f,t) moves the applied overrides: `Skin:SetOverride`, live; no argument
--                           applies the stored pair, a nil half keeps that half, false or "" clears.
--   NS.SkinOutline()        the stored Font outline: "all" (the default), "hud" or "off"; "all"
--                           before NS:InitDB.
--   NS.ApplySkinOutline(m)  moves the applied Font outline: `Skin:SetOutline`, live (LibKa0s v1.82.0,
--                           Skin minor 9, ruling D-06); no argument applies the stored mode.
--   NS.SKIN_OUTLINE_OPTIONS the outline row's values: "all", "hud", "off", the library's order.
--   NS.ApplySkinChoice(s,k) moves the applied skin: `Skin:SetChoice`, which resolves, repaints
--                           every frame recorded for this owner and THEN fires OnLooksChanged. No
--                           argument applies the stored pair (addon:OnInitialize, the profile
--                           events), and with it the stored exceptions, overrides and outline; a nil half
--                           keeps that half (each Skin tab row's onChange).
--   NS.SKIN_SOURCE_OPTIONS  the source row's values, and NS.SKIN_OPTIONS the skin row's (every
--   NS.SKIN_OPTIONS         registered skin, in the library's order). settings/Schema.lua reads both.
--   NS.SKIN_FALLBACK        the host copy of the Ka0s Default tokens the degraded facade answers.
--   NS.SkinColor(name)      a color token as a call site writes it (three components when opaque),
--                           so a literal that became a token keeps its arity on Ka0s Default.
--   NS.SkinRGB(name)        a color token as a fresh { r, g, b } triple (the Insights and Holdings
--                           color tables' shape).
--   NS.SkinEscape(name)     a color token as a "|cffrrggbb" escape, rounded to the byte, so markup
--                           written as a literal keeps its bytes on Ka0s Default (|cffff5555).
--   NS.SkinBar(t, r,g,b,a)  a bar of data (a chart fill, a stacked segment, a Timeline column):
--                           the owner's bar texture tinted r, g, b, a through `S.BarTexture`
--                           (SkinPaintExtras minor 4), recorded, so a skin switch or a Texture
--                           override re-applies it; SetColorTexture, the flat look, without it.
--   NS.QualityColor(q)      an item quality's r, g, b: the skin's q.* token where it sets one (a
--                           legibility override), else the client's ITEM_QUALITY_COLORS; nil for none.
--   NS.SkinPaintAce(w)      an AceGUI widget this addon acquired itself, painted for this owner:
--   NS.SkinPaintAceTree(c)  `Skin:PaintAce` / `Skin:PaintAceTree` with the owner bound (the facade
--                           carries neither). Nothing while the owner ignores its settings panel;
--                           release restores stock.
--   NS.SkinOnRelease(w, fn) host release work chained onto the widget's own OnRelease
--                           (`Skin:OnRelease`), so it and the skin's restore both run.
--   NS.SkinPanelIgnored()   true while this owner ignores its settings panel: the public
--                           `Skin:GetIgnore` panel half; false degraded or before the owner exists.
--   NS.SkinPanelColor(name) a color token for a HOST paint on the settings panel (the AH price
--                           table), as NS.SkinColor writes it: the live skin's, or Ka0s Default's (the
--                           value the surface drew before skins) while the panel is ignored, so one
--                           page never mixes stock and skinned (D-03 of the skin library follow-ups).
--   NS.MaybeShowSkinPicker() the first-run skin picker (LibKa0s OptionsSkinPicker 1, LibKa0s#64):
--                           `O.SkinPicker` while the profile's `pickerSeen` is false and the addon
--                           stands up; held to PLAYER_REGEN_ENABLED in combat. Answers the frame,
--                           or nil, "queued" behind another Ka0s addon's picker.
--   NS.HideSkinPicker()     takes a shown picker down (its pending preview put back) or out of the
--                           queue WITHOUT marking it seen: the stand-down, a profile that has seen
--                           it, and first on every profile event; drops a held combat deferral.
--   NS.SkinPickerSpec()     the spec MaybeShowSkinPicker hands O.SkinPicker.
--   NS.RunSkinVerb()        the reserved `/lh skin` verb's act (LibKa0s v1.82.0, OptionsSkinPicker
--                           minor 3, ruling D-16): `O.SkinVerb` with that spec, whatever
--                           `pickerSeen` says. The library prints its own lines (combat on every
--                           call, queued, unavailable); without LibKa0s the stub answers nil,
--                           "absent" and this prints the library-absent line.
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
-- The Skin tab and another addon's "Copy to every Ka0s addon" both call Skin:SetChoice
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
local PANEL_PATH, FONTS_PATH = "settings.appearance.ignorePanel", "settings.appearance.ignoreFonts"
local FONT_PATH, TEXTURE_PATH = "settings.appearance.font", "settings.appearance.texture"
local OUTLINE_PATH = "settings.appearance.outline"
local OUTLINE_DEFAULT = "all"
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
  -- The tool surfaces (LH-05): the launcher tooltip's record count (core/LauncherSetup.lua). The
  -- degraded close mark (core/CoreSetup.lua) reads btn.icon, not this.
  ["gtip.subtle"]   = { 0.7, 0.7, 0.7, 1 },
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
  -- LibKa0s SkinDefs minor 7: Ka0s Default's checkbox is a square box in the control colors.
  ["check.bg"]      = { 0.1, 0.1, 0.12, 0.9 },
  ["check.border"]  = { 0.24, 0.24, 0.27, 0.9 },
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

--- A bar of data in the owner's bar texture, tinted r, g, b, a (LibKa0s#63). Never a track, a
--- rule, an axis, a swatch chip, a stripe or a highlight: those stay flat colors. Read through
--- NS.Skin at call time. A facade without BarTexture (a Skin copy before SkinPaintExtras minor 4),
--- or a target that is neither a Texture nor a StatusBar (which the primitive leaves alone), paints
--- today's flat color, so no bar ever goes unpainted.
function NS.SkinBar(tex, r, g, b, a)
  if type(tex) ~= "table" then return end
  local paint = NS.Skin and NS.Skin.BarTexture
  local kind = type(tex.GetObjectType) == "function" and tex:GetObjectType() or nil
  if type(paint) == "function" and (kind == "Texture" or kind == "StatusBar") then
    return paint(tex, r, g, b, a)
  end
  if type(tex.SetColorTexture) == "function" then tex:SetColorTexture(r, g, b, a) end
end

-- The six qualities the skin schema names (q.poor .. q.legendary); every other quality (artifact,
-- heirloom, token) is the client's color under every skin.
local QUALITY_TOKEN = { [0] = "q.poor", "q.common", "q.uncommon", "q.rare", "q.epic", "q.legendary" }

--- An item quality's r, g, b. The q.* tokens: Ka0s Default writes the client's own colors out (since
--- LibKa0s SkinDefs minor 8), a skin may override them for legibility. nil for a quality the client
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

-- The Font outline modes (LibKa0s-Skin-1.0 minor 9's OUTLINE_MODES), with the Skin tab's words.
NS.SKIN_OUTLINE_OPTIONS = {
  { value = "all", text = "All text" },
  { value = "hud", text = "HUD text only" },
  { value = "off", text = "Off" },
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

--- A stored override as the profile keeps it: the LSM key, or "" for the skin's own (false, nil, "").
local function storedKey(v)
  if type(v) == "string" and v ~= "" then return v end
  return ""
end

--- The write seam: both halves through NS.Schema:Set (validate, store, the [Set] line, onChange).
--- `media` (LibKa0s-Skin-1.0 minor 6) is `{ font = key|false, texture = key|false }`: the Skin tab's
--- Font and texture pick and another addon's copy both hand it here, after Skin:SetOverride moved
--- the applied pair, so each row's onChange re-applies its own half as a no-op. Since minor 9 it
--- may carry `outline` too (the Font outline, after Skin:SetOutline moved it); nil leaves it alone.
function NS.WriteSkinChoice(source, skin, ignore, media)
  local S = NS.Schema
  if not (NS.db and S and S.Set) then return end
  if source ~= nil then S:Set(SOURCE_PATH, source) end
  if skin ~= nil then S:Set(SKIN_PATH, skin) end
  if type(ignore) == "table" then
    S:Set(PANEL_PATH, ignore.panel == true)
    S:Set(FONTS_PATH, ignore.fonts == true)
  end
  if type(media) == "table" then
    S:Set(FONT_PATH, storedKey(media.font))
    S:Set(TEXTURE_PATH, storedKey(media.texture))
    if media.outline ~= nil then S:Set(OUTLINE_PATH, media.outline) end
  end
end

--- The stored Font outline, nil-safely: "all" until the profile store exists.
function NS.SkinOutline()
  local S = NS.Schema
  if not (NS.db and S and S.Get) then return OUTLINE_DEFAULT end
  return S:Get(OUTLINE_PATH) or OUTLINE_DEFAULT
end

--- The stored overrides, nil-safely: each an LSM key, or false for the skin's own; false, false
--- until the profile store exists.
function NS.SkinOverride()
  local S = NS.Schema
  if not (NS.db and S and S.Get) then return false, false end
  local font, texture = storedKey(S:Get(FONT_PATH)), storedKey(S:Get(TEXTURE_PATH))
  return font ~= "" and font or false, texture ~= "" and texture or false
end

--- The stored exceptions, nil-safely: false, false until the profile store exists.
local function storedIgnore()
  local S = NS.Schema
  if not (NS.db and S and S.Get) then return false, false end
  return S:Get(PANEL_PATH) == true, S:Get(FONTS_PATH) == true
end

-- ── the first-run skin picker (LibKa0s OptionsSkinPicker 1, LibKa0s#64) ───────────────────────
--
-- WHEN. Once after login (addon:OnEnterWorld, on its once-per-session path, so only on an addon
-- that stands up), after OnInitialize applied the stored skin; and again after every profile event
-- (NS.OnProfileEvent), because a new, copied or reset profile carries its own `pickerSeen`. Never
-- while the addon stands down, and never in combat: a start in combat is held for the
-- PLAYER_REGEN_ENABLED edge, one target at most, the idiom of the ledger reset offer
-- (settings/Slash.lua NS.OfferLedgerReset).
--
-- SEEN. The library calls `onClose` once per showing, by any route the player takes (Apply, its
-- close control, the gear, Escape), and once for a picker still queued behind another Ka0s addon's
-- when that addon's "Apply to all Ka0s addons" dismisses it unshown; that is the one write of
-- `pickerSeen`, through NS.Schema:Set. A close this addon makes itself (NS.HideSkinPicker: the
-- stand-down, a profile event) is not the player's and writes nothing.
--
-- PREVIEW (LibKa0s PK-02, owner decision D6 as changed). A pick only previews: the Skin major moves
-- and the addon repaints, but `set` (NS.WriteSkinChoice) runs only on Apply, the gear or Apply to
-- all. The close control and Escape put back the owner's stored choice as it reads at the close
-- (the library's revert reads `get`, NS.SkinChoice, since PK-03), so a store that moved under the
-- preview is worn without a host re-apply. A profile event still takes the picker down FIRST
-- (NS.OnProfileEvent), before the new profile's skin is applied, so the new profile's whole pair
-- (exceptions and overrides with it) is what NS.ApplySkinChoice leaves worn, and a new or reset
-- profile then shows it fresh. The eye leaves the picker up: the library's window is DIALOG and
-- raised after onPreview returns (PK-03), so the HIGH History window it opens cannot cover it.
--
-- COMBAT. The library's queue waits out combat before it shows the NEXT owner's picker (PK-03), but
-- a first O.SkinPicker call with nothing up shows at once, whatever the lockdown, so this addon's
-- own start is still held to PLAYER_REGEN_ENABLED below.
--
-- QUEUED. One picker is up at a time across every Ka0s addon (lib.__pickerQueue): while another
-- addon's is up, O.SkinPicker queues this one and answers nil, "queued", which
-- NS.MaybeShowSkinPicker passes through; it shows when the other closes.

local PICKER_PATH = "settings.appearance.pickerSeen"
local pickerTarget       -- the one-shot PLAYER_REGEN_ENABLED target, while a start is held
local quietClose = false -- true while NS.HideSkinPicker takes the picker down

--- The eye: the History window in test mode, so the player sees the skin on this addon's frames;
--- the library raises the picker over it once this returns. SetTestMode's start opens the window
--- itself; a mode already on only needs the window shown. A refused start (the window not allowed
--- on screen) prints its own line.
local function previewSkin()
  local BT = NS.BrowserTable
  if not (BT and BT.SetTestMode) then return end
  if BT.testMode then
    if NS.Browser and NS.Browser.Show then NS.Browser:Show() end
  else
    BT:SetTestMode(true, "skin picker")
  end
end

--- The player's close: the picker seen, and nothing else. The library's put-back already wears the
--- stored choice (PK-03 reads `get` at the close), so the skin is not this callback's to move.
local function pickerClosed()
  if quietClose then return end
  local S = NS.Schema
  if not (NS.db and S and S.Set) then return end
  S:Set(PICKER_PATH, true)
end

function NS.SkinPickerSpec()
  return {
    owner = addonName, get = NS.SkinChoice, set = NS.WriteSkinChoice,
    -- The gear's default: O.OpenOptionsPanel("General") (OptionsRegistry minor 4 opens that page's
    -- own subcategory, not the landing page), then O.SelectTab("General", "Appearance"), the Skin
    -- tab's key on this addon's one schema page (settings/Panel.lua).
    page = "General", tab = "Appearance",
    onPreview = previewSkin, onClose = pickerClosed,
  }
end

local function dropPickerDeferral()
  if pickerTarget then pickerTarget:UnregisterAllEvents(); pickerTarget = nil end
end

--- True while this profile has not closed the picker and the addon stands up.
local function pickerDue()
  local S = NS.Schema
  if not (NS.db and S and S.Get) then return false end
  if NS.IsStoodDown and NS.IsStoodDown() then return false end
  return S:Get(PICKER_PATH) == false
end

function NS.HideSkinPicker()
  dropPickerDeferral()
  local O = NS.Options
  if not (O and type(O.HideSkinPicker) == "function") then return end
  quietClose = true
  local ok, err = pcall(O.HideSkinPicker)
  quietClose = false
  if not ok then error(err, 0) end
end

--- `/lh skin`: the picker a new profile shows, on demand. The dispatcher refuses it while the addon
--- is disabled (settings/Schema.lua's gate: `skin` is a feature verb). Answers the picker's frame, or
--- nil and the reason ("combat", "queued", "unavailable", "absent").
function NS.RunSkinVerb()
  local O = NS.Options
  local verb = O and type(O.SkinVerb) == "function" and O.SkinVerb
  local win, why
  if verb then win, why = verb(NS.SkinPickerSpec()) else why = "absent" end
  if win == nil and why == "absent" and NS.Print then
    NS.Print(NS.L["%s is unavailable: the LibKa0s library did not load."]:format("/lh skin"))
  end
  return win, why
end

--- Show the picker when this profile has not seen it: answers O.SkinPicker's frame, or nil, "queued"
--- while another Ka0s addon's picker is up (it shows when that one closes), or nil.
function NS.MaybeShowSkinPicker()
  local O = NS.Options
  if not (O and type(O.SkinPicker) == "function") then return nil end
  if not pickerDue() then
    NS.HideSkinPicker()
    return nil
  end
  if NS.Compat and NS.Compat.InCombatLockdown() then
    if pickerTarget then return nil end
    pickerTarget = NS.NewBusTarget and NS.NewBusTarget()
    if not pickerTarget then return nil end
    NS.SafeRegisterEvent(pickerTarget, "PLAYER_REGEN_ENABLED", function()
      dropPickerDeferral()
      NS.MaybeShowSkinPicker()
    end, NS.RejectedEvents)
    return nil
  end
  return O.SkinPicker(NS.SkinPickerSpec())
end

-- AceGUI keeps ONE callback per event name (options-ui-§19). Without the library's chain there is
-- no skin restore to share the release with, so the host's work takes the callback, as it did
-- before the skin engine.
local function releaseByCallback(widget, fn)
  if type(widget) ~= "table" or type(fn) ~= "function" or type(widget.SetCallback) ~= "function" then
    return nil
  end
  widget:SetCallback("OnRelease", function(w) fn(w) end)
  return fn
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
    "BarTexture", "FontFlags", "HudFontSize",
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
  -- A bar of data as it was drawn before the skin engine: the flat color, no texture.
  S.BarTexture = function(tex, r, g, b, a)
    if type(tex) == "table" and type(tex.SetColorTexture) == "function" then tex:SetColorTexture(r, g, b, a) end
  end
  S.GetPanelColor = function() return color("win.bg") end
  S.GetFont = function() return STANDARD_TEXT_FONT end
  S.ChartStyle = function() return {} end
  S.BarStyle = function() return {} end
  -- The two answers a caller hands SetFont (SkinPaintExtras minor 7, LibKa0s v1.82.0): never nil,
  -- which SetFont refuses. A picked flag as is; From skin ("@skin") or none reads as the outline
  -- the library's default mode ("all") would give. A positive size as is, else 12, unscaled.
  S.FontFlags = function(v)
    if type(v) == "string" and v ~= S.FROM_SKIN then return v end
    return "OUTLINE"
  end
  S.HudFontSize = function(size)
    local n = tonumber(size)
    return (n and n > 0) and n or 12
  end

  NS.Skin = S
  function NS.ApplySkinChoice() return false, false end
  function NS.ApplySkinIgnore() return false, false end
  function NS.ApplySkinOverride() return false end
  function NS.ApplySkinOutline() return false end
  -- Nothing to paint an AceGUI row with: stock AceGUI, as the client draws it.
  function NS.SkinPaintAce() return false end
  function NS.SkinPaintAceTree() return 0 end
  NS.SkinOnRelease = releaseByCallback
  -- No library, no Scope: the settings panel is never "ignored", and a panel paint is a plain one.
  function NS.SkinPanelIgnored() return false end
  NS.SkinPanelColor = NS.SkinColor
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
-- leaving an EllesmereUI that painted this session). The Skin tab raises the library's popup
-- for its own picks.
local RELOAD_LINE = NS.L and NS.L["Reload your interface (/reload) to finish changing the skin."]
  or "Reload your interface (/reload) to finish changing the skin."

-- The AceGUI rows (SkinAce.lua). NS.AceGUI is normally the Options instance's owner proxy, which
-- paints on Create already; PaintAce for the same owner repaints in place, so a host call after it
-- is harmless, and it is what paints a widget acquired any other way (AceConfigDialog's, on the
-- Profiles page) and repaints one this addon keeps for the session (the AH table's check boxes).
-- Each guards on the member, so a copy whose SkinAce secondary did not attach paints nothing.
function NS.SkinPaintAce(widget)
  if type(Skin.PaintAce) ~= "function" then return false end
  return Skin:PaintAce(addonName, widget)
end

function NS.SkinPaintAceTree(container)
  if type(Skin.PaintAceTree) ~= "function" then return 0 end
  return Skin:PaintAceTree(addonName, container)
end

function NS.SkinOnRelease(widget, fn)
  if type(Skin.OnRelease) ~= "function" then return releaseByCallback(widget, fn) end
  return Skin:OnRelease(widget, fn)
end

function NS.SkinPanelIgnored()
  if type(Skin.GetIgnore) ~= "function" then return false end
  return (Skin:GetIgnore(addonName)) == true
end

--- The skin's value, or while the panel is ignored Ka0s Default's own (`Skin:ResolveSkin`, the
--- library's table for a skin key), in NS.SkinColor's arity. nil for a token neither sets.
function NS.SkinPanelColor(name)
  if not NS.SkinPanelIgnored() or type(Skin.ResolveSkin) ~= "function" then return NS.SkinColor(name) end
  local c = Skin:ResolveSkin(Skin.DEFAULT or DEFAULT)[name]
  if type(c) ~= "table" then return nil end
  if c[4] == nil or c[4] == 1 then return c[1], c[2], c[3] end
  return c[1], c[2], c[3], c[4]
end

function NS.ApplySkinIgnore(panel, fonts)
  if type(Skin.SetIgnore) ~= "function" then return false, false end
  if panel == nil and fonts == nil then panel, fonts = storedIgnore() end
  local changed, reload = Skin:SetIgnore(addonName, panel, fonts)
  if reload and NS.Print then NS.Print(RELOAD_LINE) end
  return changed, reload
end

--- No argument applies the stored overrides; a nil half keeps that half, false or "" clears it
--- (the skin's own). A copy without SetOverride (a Skin major before minor 6) moves nothing.
function NS.ApplySkinOverride(font, texture)
  if type(Skin.SetOverride) ~= "function" then return false end
  if font == nil and texture == nil then font, texture = NS.SkinOverride() end
  return Skin:SetOverride(addonName, font, texture)
end

--- No argument applies the stored mode; the library reads a mode it does not know as "all". A copy
--- without SetOutline (a Skin major before minor 9) moves nothing.
function NS.ApplySkinOutline(mode)
  if type(Skin.SetOutline) ~= "function" then return false end
  if mode == nil then mode = NS.SkinOutline() end
  return Skin:SetOutline(addonName, mode)
end

--- No argument applies the stored pair AND the stored exceptions, overrides and outline (addon:OnInitialize,
--- the profile events); a nil half keeps that half and leaves the rest alone (each Skin tab row).
function NS.ApplySkinChoice(source, skin)
  local whole = source == nil and skin == nil
  if whole then source, skin = NS.SkinChoice() end
  local changed, reload = Skin:SetChoice(addonName, source, skin)
  if reload and NS.Print then NS.Print(RELOAD_LINE) end
  if whole then
    NS.ApplySkinIgnore()
    NS.ApplySkinOverride()
    NS.ApplySkinOutline()
  end
  return changed, reload
end
