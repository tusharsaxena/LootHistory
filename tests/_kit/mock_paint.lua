-- testkit/mock_paint.lua — the kit's opt-in paint recorder (revision 43): textures, font strings,
-- backdrops and NineSlice pieces that remember how they were painted, for a suite that asserts a skin.
-- Revision 44 adds the StatusBar family (below), for the skin's bar-texture primitive.
-- Revision 45: SetTextColor given no alpha keeps the alpha the string already had, as the client does.
--
-- Returns an INSTALLER, called on a finished mock, which returns its RESTORE:
--
--   local M = base()
--   local restore = dofile("tests/_kit/mock_paint.lua")(M)
--   ...                                    -- every frame M.CreateFrame builds now records paint
--   restore()                              -- M.CreateFrame is the base's again
--
-- WHY. Through revision 42 the base answered every capitalized method it does not define with the
-- frame (mock_base.lua's metatable): CreateTexture and CreateFontString handed back THE FRAME, and
-- SetColorTexture, SetVertexColor, SetTextColor, SetFont, SetBackdrop and the rest stored nothing, so
-- "this panel is painted the skin's background color, and a skin switch repainted it" was a sentence
-- no suite could assert (fidelity rules 1 and 3). mock_base.lua keeps that divergence as its default
-- (its "Known divergence" paragraph), because changing it would move consumers' parity baselines.
-- OPT-IN, and a file of its own, because mock_base.lua sits close to layout-§1's cap and most suites
-- never ask.
--
-- WHAT IS WRAPPED. M.CreateFrame, so every frame created AFTER install carries the frame methods
-- below, and M.UIParent when it is a table. A frame the base builds for itself (GameTooltip, the Ace
-- fakes' frames, M.__stubFrame()) stays plain until a suite hands it to M.__paintFrame(frame).
-- restore() puts back M.CreateFrame and every frame decorated in place (UIParent and the
-- __paintFrame ones); frames M.CreateFrame built while installed keep their recorder. Code that
-- cached `local CreateFrame = CreateFrame` at load time keeps the function it cached, so install
-- before loading the code under test when it does that.
--
-- THE FRAME METHODS, rawset on each frame:
--
--   CreateTexture(name, layer, template, sublevel)   a NEW Texture region owned by the frame
--   CreateFontString(name, layer, template)          a NEW FontString region owned by the frame
--   GetRegions() / GetNumRegions()                   those regions, in creation order
--   GetChildren() / GetNumChildren()                 every recorded frame whose raw `__parent` is
--                                                    this frame, in creation order (so the layer
--                                                    recorder's SetParent moves a child)
--   SetBackdrop(t) / GetBackdrop()                   the table as given; nil clears it and its colors
--   SetBackdropColor / GetBackdropColor              nil with no backdrop, white until set
--   SetBackdropBorderColor / GetBackdropBorderColor  likewise
--   SetAlpha(a) / GetAlpha()                         1 until set
--
-- A STATUSBAR (a frame CreateFrame was asked for as "StatusBar", revision 44) also answers, rawset:
--
--   GetObjectType() / IsObjectType(kind)             "StatusBar" (and "Frame", "Region")
--   SetStatusBarTexture(asset) / GetStatusBarTexture()   the bar's fill: a Texture region of the bar,
--                                                    made on first use, whose SetTexture takes a
--                                                    path; a Texture handed in becomes the fill
--   SetStatusBarColor(r, g, b, a) / GetStatusBarColor()  the fill's vertex color, white until set,
--                                                    kept across a SetStatusBarTexture as in the client
--   SetMinMaxValues / GetMinMaxValues, SetValue / GetValue   0, 1 and 0 until set
--
-- Show / Hide / IsShown, the scripts and HookScript's chaining are the base's, untouched. SetBackdrop
-- answers on any recorded frame, BackdropTemplate or not: the template is recorded by the base
-- (`__template`), and a suite that cares asserts it there.
--
-- A NINESLICE child is built when the template names one the client gives a NineSlice
-- (NINE_SLICE_TEMPLATES below; a comma-separated template list is read token by token), or by hand
-- with M.__paintNineSlice(frame). It is a recorded child frame at `frame.NineSlice` whose nine
-- pieces (M.__nineSliceKeys) are Texture regions of it, keyed by the client's piece names.
--
-- THE REGIONS. A region answers the methods modeled below and RAISES on any other capitalized
-- method, naming itself, as mock_lines.lua's Line does: a FontString told SetTexture fails in the
-- client, and it fails here. A region starts shown, white, opaque and unpainted. Paint calls record
-- what they were told: a color texture, a file and an atlas replace one another, as they do in the
-- client; the vertex color, gradient, tex coords and desaturation are kept beside them.
-- SetAtlas(name, true) sizes the region from the base's fixture (M.__atlasSizes) and records the
-- name in `__atlas`, the field the base's own frames record it in.
--
-- THE SURVEY. M.__paint(obj) -> a fresh table of what was painted on a region or a recorded frame:
-- kind, frameType, template, shown, alpha, layer, sublevel, color, vertex, gradient, texture, atlas,
-- texCoord, desaturated, blend, text, textColor, font, fontObject, shadowOffset, shadowColor,
-- backdrop, backdropColor, backdropBorderColor, and for a StatusBar statusBarTexture (the fill's
-- file) and statusBarColor (nil where nothing was painted; kind is "Frame" for a frame).

local NINE_SLICE_KEYS = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
                          "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }

local NINE_SLICE_TEMPLATES = {
  NineSlicePanelTemplate = true, PortraitFrameTemplate = true, ButtonFrameTemplate = true,
  DefaultPanelTemplate = true, DefaultPanelFlatTemplate = true, SimplePanelTemplate = true,
  InsetFrameTemplate = true, TooltipBackdropTemplate = true,
}

local FRAME_METHODS = { "CreateTexture", "CreateFontString", "GetRegions", "GetNumRegions",
                        "GetChildren", "GetNumChildren", "SetBackdrop", "GetBackdrop",
                        "SetBackdropColor", "GetBackdropColor", "SetBackdropBorderColor",
                        "GetBackdropBorderColor", "SetAlpha", "GetAlpha", "__paintRegions",
                        -- the StatusBar family (revision 44), put back too on an in-place frame
                        "GetObjectType", "IsObjectType", "SetStatusBarTexture", "GetStatusBarTexture",
                        "SetStatusBarColor", "GetStatusBarColor", "SetMinMaxValues", "GetMinMaxValues",
                        "SetValue", "GetValue", "__barFill" }

local WHITE = { 1, 1, 1, 1 }
local FULL_COORDS = { 0, 0, 0, 1, 1, 0, 1, 1 }

local function color(r, g, b, a) return { r, g, b, a or 1 } end
local function unpackOr(t, default) return unpack(t or default) end

-- ── the methods every region has ────────────────────────────────────────────────────────────

local COMMON = {}

function COMMON:Show() self.__shown = true end
function COMMON:Hide() self.__shown = false end
function COMMON:SetShown(v) self.__shown = not not v end
function COMMON:IsShown() return self.__shown end
function COMMON:IsVisible()
  local owner = self.__owner
  return self.__shown and (owner == nil or not owner.IsVisible or owner:IsVisible()) and true or false
end
function COMMON:SetAlpha(a) self.__alpha = a end
function COMMON:GetAlpha() return self.__alpha or 1 end
function COMMON:GetParent() return self.__owner end
function COMMON:SetParent(owner)
  local old = self.__owner
  local list = old and rawget(old, "__paintRegions")
  for i = #(list or {}), 1, -1 do
    if list[i] == self then table.remove(list, i) end
  end
  self.__owner = owner
  local into = owner and rawget(owner, "__paintRegions")
  if into then into[#into + 1] = self end
end
function COMMON:GetObjectType() return self.__kind end
function COMMON:IsObjectType(kind) return kind == self.__kind or kind == "Region" end
function COMMON:GetName() return self.__name end
function COMMON:SetDrawLayer(layer, sublevel) self.__layer, self.__sublevel = layer, sublevel end
function COMMON:GetDrawLayer() return self.__layer, self.__sublevel end
function COMMON:SetVertexColor(r, g, b, a) self.__vertex = color(r, g, b, a) end
function COMMON:GetVertexColor() return unpackOr(self.__vertex, WHITE) end
function COMMON:SetPoint(...) self.__points[#self.__points + 1] = { ... } end
function COMMON:ClearAllPoints() self.__points, self.__allPoints = {}, nil end
function COMMON:SetAllPoints(rel) self.__points, self.__allPoints = {}, rel or self.__owner end
function COMMON:GetNumPoints() return #self.__points end
function COMMON:GetPoint(i) return unpack(self.__points[i or 1] or {}) end
function COMMON:SetSize(w, h) self.__w, self.__h = w, h end
function COMMON:SetWidth(w) self.__w = w end
function COMMON:SetHeight(h) self.__h = h end
function COMMON:GetWidth() return self.__w or 0 end
function COMMON:GetHeight() return self.__h or 0 end
function COMMON:GetSize() return self.__w or 0, self.__h or 0 end
function COMMON:SetScale(s) self.__scale = s end
function COMMON:GetScale() return self.__scale or 1 end
function COMMON:SetIgnoreParentAlpha(b) self.__ignoreParentAlpha = not not b end
function COMMON:IsIgnoringParentAlpha() return self.__ignoreParentAlpha == true end

-- ── Texture ─────────────────────────────────────────────────────────────────────────────────

local TEXTURE = {}

function TEXTURE:SetColorTexture(r, g, b, a)
  self.__color, self.__texture, self.__atlas = color(r, g, b, a), nil, nil
end
function TEXTURE:SetTexture(path) self.__texture, self.__color, self.__atlas = path, nil, nil end
function TEXTURE:GetTexture() return self.__texture end
-- The size comes from the base's fixture, M.__atlasSizes, which the region carried from its frame.
function TEXTURE:SetAtlas(name, useAtlasSize)
  self.__atlas, self.__texture, self.__color = name, nil, nil
  local size = (self.__atlasSizes or {})[name]
  if useAtlasSize and size then self.__w, self.__h = size[1], size[2] end
end
function TEXTURE:GetAtlas() return self.__atlas end
function TEXTURE:SetGradient(orientation, minColor, maxColor)
  local function copy(c) return { r = c.r, g = c.g, b = c.b, a = c.a or 1 } end
  self.__gradient = { orientation = orientation, min = copy(minColor), max = copy(maxColor) }
end
function TEXTURE:SetTexCoord(...)
  local n, a = select("#", ...), { ... }
  if n == 4 then   -- left, right, top, bottom: the four corners UL, LL, UR, LR as the client answers
    a = { a[1], a[3], a[1], a[4], a[2], a[3], a[2], a[4] }
  end
  self.__texCoord = a
end
function TEXTURE:GetTexCoord() return unpackOr(self.__texCoord, FULL_COORDS) end
function TEXTURE:SetDesaturated(b) self.__desaturated = not not b end
function TEXTURE:IsDesaturated() return self.__desaturated == true end
function TEXTURE:SetDesaturation(x) self.__desaturated = (x or 0) > 0 end
function TEXTURE:GetDesaturation() return self.__desaturated and 1 or 0 end
function TEXTURE:SetBlendMode(mode) self.__blend = mode end
function TEXTURE:GetBlendMode() return self.__blend or "BLEND" end
function TEXTURE:SetHorizTile(b) self.__horizTile = not not b end
function TEXTURE:GetHorizTile() return self.__horizTile == true end
function TEXTURE:SetVertTile(b) self.__vertTile = not not b end
function TEXTURE:GetVertTile() return self.__vertTile == true end
function TEXTURE:SetTextureSliceMargins(l, t, r, b) self.__sliceMargins = { l, t, r, b } end
function TEXTURE:SetTextureSliceMode(mode) self.__sliceMode = mode end
function TEXTURE:SetSnapToPixelGrid(b) self.__snap = not not b end
function TEXTURE:SetTexelSnappingBias(x) self.__texelBias = x end
function TEXTURE:SetRotation(r) self.__rotation = r end
function TEXTURE:GetRotation() return self.__rotation or 0 end

-- ── FontString ──────────────────────────────────────────────────────────────────────────────

local FONTSTRING = {}

function FONTSTRING:SetText(v) self.__text = v end
function FONTSTRING:GetText() return self.__text end
function FONTSTRING:SetFormattedText(fmt, ...) self.__text = string.format(fmt, ...) end
-- No alpha keeps the alpha the string had (revision 45): the client's rule, measured off DpsRace's
-- Arm Race label, which drew its enabled color at the 0.4 of an earlier disabled paint.
function FONTSTRING:SetTextColor(r, g, b, a)
  if a == nil and self.__textColor then a = self.__textColor[4] end
  self.__textColor = color(r, g, b, a)
end
function FONTSTRING:GetTextColor() return unpackOr(self.__textColor, WHITE) end
function FONTSTRING:SetFont(path, size, flags) self.__font = { path, size, flags or "" } end
function FONTSTRING:GetFont()
  if self.__font then return unpack(self.__font) end
  local obj = self.__fontObject
  if type(obj) == "string" then obj = rawget(_G, obj) end
  if type(obj) == "table" and obj.GetFont then return obj:GetFont() end
  return nil
end
function FONTSTRING:SetFontObject(obj) self.__fontObject, self.__font = obj, nil end
function FONTSTRING:GetFontObject() return self.__fontObject end
function FONTSTRING:SetShadowOffset(x, y) self.__shadowOffset = { x, y } end
function FONTSTRING:GetShadowOffset() return unpackOr(self.__shadowOffset, { 0, 0 }) end
function FONTSTRING:SetShadowColor(r, g, b, a) self.__shadowColor = color(r, g, b, a) end
function FONTSTRING:GetShadowColor() return unpackOr(self.__shadowColor, { 0, 0, 0, 1 }) end
function FONTSTRING:SetJustifyH(v) self.__justifyH = v end
function FONTSTRING:GetJustifyH() return self.__justifyH or "CENTER" end
function FONTSTRING:SetJustifyV(v) self.__justifyV = v end
function FONTSTRING:GetJustifyV() return self.__justifyV or "MIDDLE" end
function FONTSTRING:SetWordWrap(b) self.__wordWrap = not not b end
function FONTSTRING:CanWordWrap() return self.__wordWrap ~= false end
function FONTSTRING:SetNonSpaceWrap(b) self.__nonSpaceWrap = not not b end
function FONTSTRING:CanNonSpaceWrap() return self.__nonSpaceWrap == true end
function FONTSTRING:SetIndentedWordWrap(b) self.__indentedWrap = not not b end
function FONTSTRING:SetMaxLines(n) self.__maxLines = n end
function FONTSTRING:GetMaxLines() return self.__maxLines or 0 end
function FONTSTRING:SetSpacing(n) self.__spacing = n end
function FONTSTRING:GetSpacing() return self.__spacing or 0 end
function FONTSTRING:SetTextScale(s) self.__textScale = s end
function FONTSTRING:GetTextScale() return self.__textScale or 1 end
-- Measured text is unarmed geometry: zero, like an unarmed frame's GetWidth (fidelity rule 2).
function FONTSTRING:GetStringWidth() return 0 end
function FONTSTRING:GetStringHeight() return 0 end
function FONTSTRING:GetUnboundedStringWidth() return 0 end

local function regionMeta(own)
  return {
    __index = function(_, key)
      local m = own[key] or COMMON[key]
      if m then return m end
      if type(key) == "string" and key:match("^%u") then
        error("testkit: a region has no " .. key .. " -- model it in testkit/mock_paint.lua if "
          .. "the client answers it, or stop calling it on this region", 2)
      end
      return nil
    end,
  }
end

local META = { Texture = regionMeta(TEXTURE), FontString = regionMeta(FONTSTRING) }

local function newRegion(sizes, owner, kind, name, layer, template, sublevel)
  local r = setmetatable({
    __kind = kind, __owner = owner, __name = name, __layer = layer, __sublevel = sublevel,
    __template = template, __shown = true, __points = {}, __atlasSizes = sizes,
  }, META[kind])
  local list = rawget(owner, "__paintRegions")
  list[#list + 1] = r
  return r
end

-- ── the frame half ──────────────────────────────────────────────────────────────────────────

local function wantsNineSlice(template)
  if type(template) ~= "string" then return false end
  for token in template:gmatch("[^,%s]+") do
    if NINE_SLICE_TEMPLATES[token] then return true end
  end
  return false
end

local function backdropColorGetter(field)
  return function(self)
    if rawget(self, "__backdrop") == nil then return nil end
    return unpackOr(rawget(self, field), WHITE)
  end
end

local function childrenOf(frames, parent)
  local out = {}
  for _, f in ipairs(frames) do
    if rawget(f, "__parent") == parent then out[#out + 1] = f end
  end
  return out
end

-- ── the StatusBar half (revision 44) ────────────────────────────────────────────────────────

--- The bar's fill texture, made once as a region of the bar (the client's bar texture is one).
local function barFill(bar, sizes)
  local fill = rawget(bar, "__barFill")
  if not fill then
    fill = newRegion(sizes, bar, "Texture", nil, "ARTWORK")
    rawset(bar, "__barFill", fill)
  end
  return fill
end

local function decorateStatusBar(f, sizes)
  rawset(f, "GetObjectType", function() return "StatusBar" end)
  rawset(f, "IsObjectType", function(_, kind) return kind == "StatusBar" or kind == "Frame" or kind == "Region" end)
  rawset(f, "SetStatusBarTexture", function(self, asset)
    if type(asset) == "table" then
      -- A Texture handed in becomes the fill, taking the color the old fill carried.
      local old = rawget(self, "__barFill")
      if old and old ~= asset then asset:SetVertexColor(old:GetVertexColor()) end
      rawset(self, "__barFill", asset)
      return
    end
    barFill(self, sizes):SetTexture(asset)
  end)
  rawset(f, "GetStatusBarTexture", function(self) return barFill(self, sizes) end)
  rawset(f, "SetStatusBarColor", function(self, r, g, b, a) barFill(self, sizes):SetVertexColor(r, g, b, a) end)
  rawset(f, "GetStatusBarColor", function(self)
    local fill = rawget(self, "__barFill")
    if not fill then return 1, 1, 1, 1 end
    return fill:GetVertexColor()
  end)
  rawset(f, "SetMinMaxValues", function(self, lo, hi) rawset(self, "__minMax", { lo, hi }) end)
  rawset(f, "GetMinMaxValues", function(self) return unpackOr(rawget(self, "__minMax"), { 0, 1 }) end)
  rawset(f, "SetValue", function(self, v) rawset(self, "__value", v) end)
  rawset(f, "GetValue", function(self) return rawget(self, "__value") or 0 end)
end

local function decorate(f, frames, sizes)
  if rawget(f, "__paintRegions") then return f end
  rawset(f, "__paintRegions", {})
  frames[#frames + 1] = f
  rawset(f, "CreateTexture", function(self, name, layer, template, sublevel)
    return newRegion(sizes, self, "Texture", name, layer, template, sublevel)
  end)
  rawset(f, "CreateFontString", function(self, name, layer, template)
    return newRegion(sizes, self, "FontString", name, layer, template)
  end)
  rawset(f, "GetRegions", function(self) return unpack(rawget(self, "__paintRegions")) end)
  rawset(f, "GetNumRegions", function(self) return #rawget(self, "__paintRegions") end)
  rawset(f, "GetChildren", function(self) return unpack(childrenOf(frames, self)) end)
  rawset(f, "GetNumChildren", function(self) return #childrenOf(frames, self) end)
  rawset(f, "SetBackdrop", function(self, t)
    rawset(self, "__backdrop", t)
    if t == nil then
      rawset(self, "__backdropColor", nil); rawset(self, "__backdropBorderColor", nil)
    end
  end)
  rawset(f, "GetBackdrop", function(self) return rawget(self, "__backdrop") end)
  rawset(f, "SetBackdropColor", function(self, r, g, b, a) rawset(self, "__backdropColor", color(r, g, b, a)) end)
  rawset(f, "GetBackdropColor", backdropColorGetter("__backdropColor"))
  rawset(f, "SetBackdropBorderColor", function(self, r, g, b, a)
    rawset(self, "__backdropBorderColor", color(r, g, b, a))
  end)
  rawset(f, "GetBackdropBorderColor", backdropColorGetter("__backdropBorderColor"))
  rawset(f, "SetAlpha", function(self, a) rawset(self, "__alpha", a) end)
  rawset(f, "GetAlpha", function(self) return rawget(self, "__alpha") or 1 end)
  if rawget(f, "__frameType") == "StatusBar" then decorateStatusBar(f, sizes) end
  return f
end

local SURVEY = {
  kind = "__kind", frameType = "__frameType", template = "__template", shown = "__shown",
  alpha = "__alpha", layer = "__layer", sublevel = "__sublevel", color = "__color",
  vertex = "__vertex", gradient = "__gradient", texture = "__texture", atlas = "__atlas",
  texCoord = "__texCoord", desaturated = "__desaturated", blend = "__blend", text = "__text",
  textColor = "__textColor", font = "__font", fontObject = "__fontObject",
  shadowOffset = "__shadowOffset", shadowColor = "__shadowColor", backdrop = "__backdrop",
  backdropColor = "__backdropColor", backdropBorderColor = "__backdropBorderColor",
}

local function survey(obj)
  local out = {}
  for key, field in pairs(SURVEY) do out[key] = rawget(obj, field) end
  out.kind = out.kind or "Frame"
  out.alpha = out.alpha or 1
  local fill = rawget(obj, "__barFill")
  if fill then
    out.statusBarTexture = rawget(fill, "__texture")
    out.statusBarColor = rawget(fill, "__vertex")
  end
  return out
end

return function(M)
  local frames, inPlace = {}, {}
  local prevCreate = M.CreateFrame
  local sizes = M.__atlasSizes or {}

  local function addNineSlice(f)
    local ns = M.CreateFrame("Frame", nil, f)
    for _, key in ipairs(NINE_SLICE_KEYS) do
      ns[key] = ns:CreateTexture(nil, key == "Center" and "BACKGROUND" or "BORDER")
    end
    f.NineSlice = ns
    return ns
  end

  M.CreateFrame = function(frameType, name, parent, template, ...)
    local f = prevCreate(frameType, name, parent, template, ...)
    if type(f) ~= "table" then return f end
    decorate(f, frames, sizes)
    if wantsNineSlice(template) then addNineSlice(f) end
    return f
  end

  local function decorateInPlace(f)
    if rawget(f, "__paintRegions") then return f end
    local saved = {}
    for _, key in ipairs(FRAME_METHODS) do saved[key] = rawget(f, key) end
    inPlace[#inPlace + 1] = { frame = f, saved = saved }
    return decorate(f, frames, sizes)
  end

  if type(M.UIParent) == "table" then decorateInPlace(M.UIParent) end

  M.__paint = survey
  M.__paintFrame = decorateInPlace
  M.__paintNineSlice = function(f)
    decorateInPlace(f)
    return addNineSlice(f)
  end
  M.__nineSliceKeys = NINE_SLICE_KEYS

  return function()
    M.CreateFrame = prevCreate
    for _, entry in ipairs(inPlace) do
      for _, key in ipairs(FRAME_METHODS) do rawset(entry.frame, key, entry.saved[key]) end
    end
    M.__paint, M.__paintFrame, M.__paintNineSlice, M.__nineSliceKeys = nil, nil, nil, nil
  end
end
