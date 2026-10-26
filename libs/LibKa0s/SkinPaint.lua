-- LibKa0s-Skin-1.0 — the Ka0s paint primitives, part one: the painter helpers every primitive
-- shares, the window primitives of EllesmereUI's vocabulary (Shell, Panel, Inset) and the
-- stock-art faders (FadeRegions, FadeNineSlice). SkinPaintExtras.lua carries the window family's
-- Ka0s extras, the text and font primitives and the getters; SkinPaintControls.lua the controls.
--
-- ── WHY IT IS A FILE OF ITS OWN ──────────────────────────────────────────────────────────────
--
-- Skin.lua is the engine and paints nothing; it records and replays. The primitives are what a
-- record replays, `lib.prim[name] = fn(owner, target, ...)`, and the facade's trampolines reach them
-- at call time. They live here, paired on the shell's minor (`__paintMinor` /
-- `__paintShellMinor`, the Widgets idiom), so a primitive from one vendored copy never attaches to
-- an engine from another without saying so. A payload without this file still runs the engine:
-- every vocabulary entry answers nil and touches nothing.
--
-- ── THE TECHNIQUE (Ka0sAddonsCommonTasks docs/2026-10-25-SKINNING, research §2 and §4) ────────
--
--   * Stock art is FADED by alpha, its prior alpha recorded, and never cleared, re-textured, hidden,
--     re-parented or re-scripted: SetAlpha survives the client's own SetTexture / Show swaps, and a
--     recorded alpha is a restore.
--   * Ka0s regions are created ONCE per target and kept in a weak per-target table that outlives
--     the record (`lib.__regions[target]`, which every record of the target answers as
--     `rec.regions`): a repaint, a record Skin:Untrack dropped and a move to another owner all reuse
--     them, holders, saved values and hook flags alike, because a frame is never collected and a
--     hook is never removed. Nothing is written onto a frame's table.
--   * A target painted for a second owner is GIVEN BACK first (everything the first owner's skin
--     faded, recolored, re-fonted, backdropped or drew is put back) and then painted for the new
--     owner, so no skin leaks into another addon's frame.
--   * STOCK art is faded under every skin. A target that carries the client's template art (a
--     button's normal texture, a template's Left/Middle/Right pieces, a NineSlice, or the regions a
--     caller names as `opts.stock`) has that art faded and is painted from the skin's tokens, Ka0s
--     Default's included (minor 6; until then Ka0s Default left a stock control as the client drew
--     it).
--   * Every Ka0s overlay that is not the target's own fill lives on a child HOLDER frame of the
--     target, never as a direct region of a frame that may reach an EllesmereUI primitive:
--     EllesmereUI's FadeRegions / Restrip fade every direct region of the frame it skins. There are
--     two, both SetAllPoints over the target. EDGES (borders, the divider line, a tab's underline,
--     a row's selection outline) go on the holder one frame level ABOVE the target. FILLS AND
--     WASHES (list-row stripe, hover and selection washes, the strip and cover washes, the extras'
--     fills and gradients) go on the fill holder one level BELOW it (never below 0), the
--     BackdropTemplate idiom: a region of a higher frame draws over every region of a lower one,
--     whatever its layer, so a fill above the target would bury the target's own text.
--   * SetBackdrop only on the target or the holder, and a target is passed by the library or the
--     owner that created it: never hand a primitive a Blizzard frame you did not create.
--   * Gradients are SetGradient on a white color texture; fonts go through one FontObject per owner
--     and role, so a 12.0.7 client draws the font object's shadow (a runtime SetShadow* on a
--     FontString no longer renders there).
--   * A nil token leaves the property alone, and a property a previous skin set from a nilable
--     token is put back when the new skin leaves it nil.
--
-- ── KA0S DEFAULT IS A SKIN LIKE THE OTHERS ───────────────────────────────────────────────────
--
-- Ka0s Default sets every token (SkinDefs minor 8) and paints from them exactly as the other skins
-- do (minor 6). Its values are the library's own look (Core.SKIN, Widgets' SKIN, LootHistory's
-- constants), so a primitive under it draws what that code drew, from tokens rather than from a
-- special case; tests/test_skin_paint*.lua pin the traces.
-- Colors whose alpha is 1 go to SetTextColor / SetVertexColor as three components, as every call
-- site writes them; fills and backdrop colors go as four.
--
-- No primitive draws a LibKa0s-Media icon: every texture is WHITE8X8 or in-client art.

local lib = LibStub and LibStub("LibKa0s-Skin-1.0", true)
if not lib then return end   -- the shell refused (no Core, or below its floor): nothing to attach to

-- Minor 3: P.font records a target's prior font OBJECT only when it is a named font that is not the
-- target itself. The client's EditBox answers GetFontObject with an anonymous font object, not the
-- named one it was given, and handing that back through SetFontObject overflowed the client's stack
-- (Forever -> Midnight crashed the game, 2026-10-26); such a target gets its face back by path.
-- Minor 4: a skin's font sizes are RELATIVE to Ka0s Default's. Every skin sets `font.bodySize` and
-- `font.titleSize`, Ka0s Default's being the reference, and a target keeps its own stock size scaled
-- by the skin's size over the reference: a 10pt caption under a skin 10% larger is 11pt, not the
-- skin's body size. The owner's font objects are one per role AND size, so two targets of one role
-- at two sizes no longer share (and overwrite) one object's size. Layouts measured against the stock
-- fonts hold in every skin (the owner's notes, 2026-10-26).
-- Minor 5: a DARK label (luminance under .3: dark text on a bright primary button or a selected tab)
-- takes a shadowless font object, because the black drop shadow smears dark strokes; and P.label
-- gives every string a primitive colors the skin's face too, so no string is left on the client's
-- font and its shadow (an EditBox hint, a list header, a footer, on a light skin most of all).
-- Minor 6: no skin is special. Ka0s Default used to leave a stock control stock, keep Core's own
-- SKIN table for the window, fade nothing and leave AceGUI rows alone, falling back to the client's
-- look wherever it set no token. It now sets every token (SkinDefs minor 8) and paints from them
-- like every other skin (the owner's ruling, 2026-10-26: "make sure even the Ka0s Default has a
-- setting for everything").
local PAINT_MINOR = 6
if lib.__paintMinor and lib.__paintMinor >= PAINT_MINOR
  and lib.__paintShellMinor == lib.MINOR then return end
lib.__paintMinor      = PAINT_MINOR
lib.__paintShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.SkinPaint = PAINT_MINOR

-- Every region and holder a primitive created, weakly: FadeRegions never fades one of its own.
lib.__ours = lib.__ours or setmetatable({}, { __mode = "k" })
-- Each target's regions, weakly, across its records (see the header): kept across minors, since the
-- frames and hooks they name outlive any one copy of this file.
lib.__regions = lib.__regions or setmetatable({}, { __mode = "k" })
-- The per-owner font objects, "owner\0role" -> FontObject. Kept across minors: a font object is a
-- named client object and cannot be created twice under one name.
lib.__fonts = lib.__fonts or {}

local prim = lib.prim
local P = {}
-- The helpers, for SkinPaintControls.lua (the same copy: it attaches to this minor's shell only).
lib.__P = P

local WHITE8 = "Interface\\Buttons\\WHITE8X8"   -- Widgets', OptionsDrawer's and LootHistory's spelling
local CLEAR = { 0, 0, 0, 0 }
local WHITE = { 1, 1, 1, 1 }
P.WHITE8, P.CLEAR = WHITE8, CLEAR

-- The in-client border art the skins name, for a client whose LibSharedMedia lacks the key.
local CLIENT_BORDERS = {
  ["Blizzard Dialog"]      = "Interface\\DialogFrame\\UI-DialogBox-Border",
  ["Blizzard Dialog Gold"] = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
  ["Blizzard Tooltip"]     = "Interface\\Tooltips\\UI-Tooltip-Border",
}

-- The client's template art a stock target carries: answered by these getters, or kept in these
-- fields (the panel button, input box, dropdown and tab templates).
local STOCK_GETTERS = { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetCheckedTexture",
                        "GetDisabledCheckedTexture" }
local STOCK_FADE_GETTERS = { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture",
                             "GetHighlightTexture" }
local STOCK_KEYS = { "Left", "Middle", "Right", "Mid", "LeftActive", "MiddleActive", "RightActive",
                     "LeftDisabled", "MiddleDisabled", "RightDisabled", "LeftHighlight", "MiddleHighlight",
                     "RightHighlight" }
local NINE_KEYS = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
                    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }

-- ── reading the skin ─────────────────────────────────────────────────────────────────────────

local function core() return LibStub("LibKa0s-Core-1.0", true) end

--- The owner's resolved token table (shared; never written): `Skin:__Tokens`, so while EllesmereUI
--- paints the owner the primitives read the table SkinEUI.lua derives from EllesmereUI's getters.
function P.T(owner) return lib:__Tokens(owner) end


--- Answers false, always (minor 6): no skin is special, Ka0s Default included, so nothing branches
--- on it. Kept because LibKa0s-Options-1.0 asks it (OptionsScroll's `__chromeAway`, which draws a
--- page's skin chrome when this answers false), and an Options copy vendored beside this one may be
--- older than the change.
function P.isDefault() return false end

local function nilable(name)
  local e = lib.__schemaIndex and lib.__schemaIndex[name]
  return e ~= nil and e.nilable == true
end

--- r, g, b for an opaque color, r, g, b, a otherwise: text and vertex colors, as call sites write them.
function P.rgb(c)
  if c[4] == nil or c[4] == 1 then return c[1], c[2], c[3] end
  return c[1], c[2], c[3], c[4]
end
--- r, g, b, a always: fills and backdrop colors.
function P.rgba(c) return c[1], c[2], c[3], c[4] or 1 end
local rgb, rgba = P.rgb, P.rgba

local function asColor(c)
  if type(CreateColor) == "function" then return CreateColor(c[1], c[2], c[3], c[4] or 1) end
  return { r = c[1], g = c[2], b = c[3], a = c[4] or 1 }
end

--- A LibSharedMedia path for `key` of `kind`, or nil. A key that already is a path answers itself.
function P.media(kind, key)
  if type(key) ~= "string" or key == "" then return nil end
  local LSM = LibStub("LibSharedMedia-3.0", true)
  local path = LSM and type(LSM.Fetch) == "function" and LSM:Fetch(kind, key, true) or nil
  if path then return path end
  if kind == "border" and CLIENT_BORDERS[key] then return CLIENT_BORDERS[key] end
  if key:find("\\", 1, true) then return key end
  return nil
end

-- ── what a target is ─────────────────────────────────────────────────────────────────────────

--- "Texture", "FontString", a frame type, "table" for a plain table, or nil. Never indexes another
--- capitalized key: a region raises on a method it does not have, in the client as in the kit.
function P.kind(obj)
  if type(obj) ~= "table" then return nil end
  local get = obj.GetObjectType
  if type(get) ~= "function" then return "table" end
  local ok, k = pcall(get, obj)
  if ok and type(k) == "string" then return k end
  return "Frame"
end
function P.isTexture(obj) return P.kind(obj) == "Texture" end
function P.isFS(obj) return P.kind(obj) == "FontString" end
function P.isFrame(obj)
  local k = P.kind(obj)
  return k ~= nil and k ~= "Texture" and k ~= "FontString"
end

--- A frame's field when it holds a region of `want` ("Texture" / "FontString"), else nil.
function P.field(frame, key, want)
  if not P.isFrame(frame) then return nil end
  local v = rawget(frame, key)
  if v == nil then v = frame[key] end
  if P.kind(v) == want then return v end
  return nil
end

--- A frame method's answer when it is a region of `want`, else nil (pcall'd: a frame type without
--- the method answers nothing).
function P.call(frame, method, want)
  if not P.isFrame(frame) or type(frame[method]) ~= "function" then return nil end
  local ok, v = pcall(frame[method], frame)
  if ok and P.kind(v) == want and not lib.__ours[v] then return v end
  return nil
end

--- True for a frame that wears BackdropTemplate. The template's mixin copies its methods into the
--- frame's own table, and a frame without it has no SetBackdrop at all, so the raw field is the
--- question (and a test frame without the template is one with that field cleared).
function P.hasBackdrop(frame)
  return P.isFrame(frame) and type(rawget(frame, "SetBackdrop")) == "function"
end

--- The client's template art on `frame`, as a list of textures, plus `opts.stock`.
function P.stockRegions(frame, opts, getters)
  local out = {}
  for _, g in ipairs(getters or STOCK_FADE_GETTERS) do out[#out + 1] = P.call(frame, g, "Texture") end
  for _, k in ipairs(STOCK_KEYS) do out[#out + 1] = P.field(frame, k, "Texture") end
  local ns = P.isFrame(frame) and rawget(frame, "NineSlice")
  if P.isFrame(ns) then
    for _, k in ipairs(NINE_KEYS) do out[#out + 1] = P.field(ns, k, "Texture") end
  end
  if type(opts) == "table" and type(opts.stock) == "table" then
    for _, r in ipairs(opts.stock) do
      if P.isTexture(r) then out[#out + 1] = r end
    end
  end
  return out
end

--- True when `frame` carries template art (see the header's "Ka0s Default keeps STOCK art").
function P.hasStock(frame, opts)
  if #P.stockRegions(frame, opts, STOCK_GETTERS) > 0 then return true end
  return false
end

-- ── the record's regions ─────────────────────────────────────────────────────────────────────

local function saved(rec, kind)
  local s = rec.regions.saved
  if not s then s = {}; rec.regions.saved = s end
  local t = s[kind]
  if not t then t = {}; s[kind] = t end
  return t
end
P.saved = saved

-- A child frame over the target at its frame level + `offset` (never below 0), made once as
-- `rec.regions[key]`.
local function holderAt(rec, frame, key, offset)
  local h = rec.regions[key]
  if h then
    h:Show()
    return h
  end
  if type(CreateFrame) ~= "function" or not P.isFrame(frame) then return nil end
  h = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  if type(h) ~= "table" then return nil end
  h:SetAllPoints(frame)
  local lv = type(frame.GetFrameLevel) == "function" and frame:GetFrameLevel()
  if type(lv) == "number" then h:SetFrameLevel(math.max(0, lv + offset)) end
  lib.__ours[h] = true
  rec.regions[key] = h
  return h
end

--- The record's holder, for edges: a child frame over the target, one frame level up, made once.
function P.holder(rec, frame) return holderAt(rec, frame, "holder", 1) end

--- The record's fill holder, for fills and washes: a child frame over the target, one frame level
--- down (never below 0), made once, so what it draws sits under every region of the target.
function P.under(rec, frame) return holderAt(rec, frame, "under", -1) end

--- One texture region of the record, made once on `parent`.
function P.tex(rec, key, parent, layer, sublevel)
  local t = rec.regions[key]
  if t then return t end
  if not P.isFrame(parent) or type(parent.CreateTexture) ~= "function" then return nil end
  t = parent:CreateTexture(nil, layer, nil, sublevel)
  if type(t) ~= "table" or t == parent then return nil end   -- the kit's bare stub answers the frame
  lib.__ours[t] = true
  rec.regions[key] = t
  return t
end

--- One font string of the record, made once on `parent`.
function P.fs(rec, key, parent, layer, template)
  local f = rec.regions[key]
  if f then return f end
  if not P.isFrame(parent) or type(parent.CreateFontString) ~= "function" then return nil end
  f = parent:CreateFontString(nil, layer, template)
  if type(f) ~= "table" or f == parent then return nil end
  lib.__ours[f] = true
  rec.regions[key] = f
  return f
end

--- Hide the record's region `key` when it exists; never makes one.
function P.hide(rec, key)
  local r = rec.regions[key]
  if r then r:Hide() end
end

--- Paint `tex` with the fill token `base`: a vertical gradient when `<base>Top` and `<base>Bottom`
--- are both set, else the flat color; hidden when the skin sets neither.
function P.fill(rec, tex, T, base)
  if not tex then return end
  local top, bottom, c = T[base .. "Top"], T[base .. "Bottom"], T[base]
  local grads = saved(rec, "gradient")
  if top and bottom then
    tex:SetColorTexture(1, 1, 1, 1)
    tex:SetGradient("VERTICAL", asColor(bottom), asColor(top))
    grads[tex] = true
  elseif c then
    tex:SetColorTexture(rgba(c))
    if grads[tex] then
      tex:SetGradient("VERTICAL", asColor(WHITE), asColor(WHITE))
      grads[tex] = nil
    end
  else
    tex:Hide()
    return
  end
  tex:Show()
end

--- Fade `region` (stock art) to alpha 0, recording its prior alpha the first time.
function P.fade(rec, region)
  if not region then return end
  local alphas = saved(rec, "alpha")
  if alphas[region] == nil then alphas[region] = region:GetAlpha() end
  region:SetAlpha(0)
end

function P.fadeAll(rec, regions)
  for _, r in ipairs(regions) do P.fade(rec, r) end
end

--- Color `obj` (`method` "SetTextColor" or "SetVertexColor") from token `name`. A nilable token, or
--- any token on a stock target, records the prior color first, and puts it back when the token
--- resolves to nil.
function P.tint(rec, obj, T, name, method)
  if type(obj) ~= "table" then return end
  method = method or "SetTextColor"
  local c = T[name]
  local keep = nilable(name) or rec.regions.stock
  local priors = saved(rec, method)
  if c then
    if keep and priors[obj] == nil then
      local getter = obj[(method:gsub("^Set", "Get"))]
      priors[obj] = type(getter) == "function" and { getter(obj) } or false
    end
    obj[method](obj, rgb(c))
  elseif priors[obj] then
    obj[method](obj, unpack(priors[obj]))
    priors[obj] = nil
  end
end

--- Hook `script` on `frame` once per record: `fn(frame, rec)` runs after the frame's own handler,
--- reading the record at call time (a pooled frame that moved to another owner paints for it).
function P.hook(rec, frame, script, fn)
  local hooks = saved(rec, "hooks")
  if hooks[script] or type(frame.HookScript) ~= "function" then return end
  hooks[script] = true
  frame:HookScript(script, function(self, ...)
    local r = lib.painted[self]
    if r then fn(self, r, ...) end
  end)
end

-- ── fonts ────────────────────────────────────────────────────────────────────────────────────

local FONT_ROLE = {
  body  = { face = "font.body",  size = "font.bodySize" },
  title = { face = "font.title", size = "font.titleSize" },
  mono  = { face = "font.mono",  size = "font.bodySize" },
}

local function ownerFont(owner, role, path, size, flags, shadow)
  if type(CreateFont) ~= "function" then return nil end
  local tenths = math.floor(size * 10 + 0.5)
  local suffix = shadow and "" or "_ns"
  local key = owner .. "\0" .. role .. "\0" .. tenths .. suffix
  local obj = lib.__fonts[key]
  if not obj then
    obj = CreateFont("LibKa0sSkin_" .. owner:gsub("[^%w]", "") .. "_" .. role .. "_" .. tenths .. suffix)
    if type(obj) ~= "table" then return nil end
    lib.__fonts[key] = obj
  end
  obj:SetFont(path, size, flags)
  if shadow then
    obj:SetShadowOffset(1, -1)
    obj:SetShadowColor(0, 0, 0, 1)
  else
    obj:SetShadowOffset(0, 0)
  end
  return obj
end

--- `obj` when it is a font a target can be handed back safely: a font's global name, or a named
--- font object that is not the target. An anonymous one (what the client's EditBox answers, never
--- the font it was given) is nil, so the face goes back by path instead.
local function namedFont(fs, obj)
  if type(obj) == "string" then return obj ~= "" and obj or nil end
  if type(obj) ~= "table" or obj == fs or type(obj.GetName) ~= "function" then return nil end
  local ok, name = pcall(obj.GetName, obj)
  if ok and type(name) == "string" and name ~= "" then return obj end
  return nil
end

--- Put `fs` back on the font it had before the first skin font reached it: its named font object
--- when it had one, else its face by path, size and flags with its shadow, which SetFont leaves as
--- the skin's font object set it. The object is checked again here, so a record an older copy of
--- this file wrote never hands an anonymous one back.
function P.unfont(rec, fs)
  local fonts = saved(rec, "font")
  local s = fonts[fs]
  if not s then return end
  local obj = namedFont(fs, s.obj)
  if obj then
    fs:SetFontObject(obj)
  elseif s.path then
    fs:SetFont(s.path, s.size, s.flags)
    if s.shadowOffset and type(fs.SetShadowOffset) == "function" then
      fs:SetShadowOffset(unpack(s.shadowOffset))
    end
    if s.shadowColor and type(fs.SetShadowColor) == "function" then
      fs:SetShadowColor(unpack(s.shadowColor))
    end
  end
  fonts[fs] = nil
end

--- `{ getter(fs) }` when `fs` has the getter and it answers, else nil.
local function priorOf(fs, getter)
  if type(fs[getter]) ~= "function" then return nil end
  local got = { fs[getter](fs) }
  return #got > 0 and got or nil
end

--- The size a target of stock size `stock` takes under the owner's skin: `stock` scaled by the
--- skin's size token over Ka0s Default's (minor 4). A target with no stock size reads the reference
--- itself; a skin or a reference without the token leaves the stock size alone.
function P.fontSize(owner, token, stock)
  local want = P.T(owner)[token]
  local ref = lib:ResolveSkin(lib.DEFAULT)[token]
  stock = tonumber(stock)
  if type(want) ~= "number" then return stock or ref or 12 end
  if not stock or type(ref) ~= "number" or ref <= 0 then return want end
  return stock * want / ref
end

--- True for a color dark enough that a black drop shadow smears it (relative luminance under .3).
local function darkColor(c)
  return type(c) == "table" and type(c[1]) == "number"
    and (0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]) < 0.3
end

--- Give `fs` (a FontString, or an EditBox) the skin's font for `role` ("body", "title", "mono"),
--- through the owner's font object for that role. A nil face token puts the stock font back.
function P.font(owner, rec, fs, role, color)
  if type(fs) ~= "table" or type(fs.SetFontObject) ~= "function" then return end
  local T, spec = P.T(owner), FONT_ROLE[role] or FONT_ROLE.body
  local path = P.media("font", T[spec.face])
  if not path then return P.unfont(rec, fs) end
  local fonts = saved(rec, "font")
  if not fonts[fs] then
    local p, s, f = fs:GetFont()
    local obj = namedFont(fs, fs:GetFontObject())
    fonts[fs] = { obj = obj, path = p, size = s, flags = f,
                  shadowOffset = not obj and priorOf(fs, "GetShadowOffset") or nil,
                  shadowColor = not obj and priorOf(fs, "GetShadowColor") or nil }
  end
  local size = P.fontSize(owner, spec.size, fonts[fs].size)
  local flags = T["font.outline"] or ""
  local obj = ownerFont(owner, role, path, size, flags, T["font.shadow"] ~= false and not darkColor(color))
  if obj then
    fs:SetFontObject(obj)
  else
    fs:SetFont(path, size, flags)
  end
end

--- Color `fs` with the owner's token `token` and give it the skin's face for `role` (body when
--- omitted), shadowless when the color is dark (minor 5). The one call a primitive makes for a
--- string it labels, so no labeled string keeps the client's font under a skin that sets one.
function P.label(owner, rec, fs, T, token, role)
  if not P.isFS(fs) then return end
  P.tint(rec, fs, T, token)
  P.font(owner, rec, fs, role or "body", T[token])
end

-- ── edges and boxes ──────────────────────────────────────────────────────────────────────────

local SIDES = { "Top", "Bottom", "Left", "Right" }
local SIDE_ANCHOR = {
  Top    = { "TOPLEFT", "TOPRIGHT", "SetHeight" },
  Bottom = { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight" },
  Left   = { "TOPLEFT", "BOTTOMLEFT", "SetWidth" },
  Right  = { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth" },
}

local function mix(c, to, f)
  return { c[1] + (to - c[1]) * f, c[2] + (to - c[2]) * f, c[3] + (to - c[3]) * f, c[4] or 1 }
end

local function clearNine(rec, frame)
  local h = rec.regions.holder
  if not (h and rec.regions.nine) then return end
  h:SetBackdrop(nil)
  h:ClearAllPoints()
  h:SetAllPoints(frame)
  rec.regions.nine = nil
end

--- Hide every edge the record drew; never makes a holder.
function P.hideEdges(rec, frame)
  for _, side in ipairs(SIDES) do P.hide(rec, "edge" .. side) end
  clearNine(rec, frame)
end

-- A nine-slice border is the holder's own backdrop edge, drawn OUTSET by a quarter of its size so
-- the art's soft outer band sits outside the target and content anchors never move.
local function nineEdge(rec, frame, h, path, size, color)
  for _, side in ipairs(SIDES) do P.hide(rec, "edge" .. side) end
  local o = math.floor(size / 4)
  h:ClearAllPoints()
  h:SetPoint("TOPLEFT", frame, "TOPLEFT", -o, o)
  h:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o, -o)
  h:SetBackdrop({ edgeFile = path, edgeSize = size })
  h:SetBackdropBorderColor(rgba(color))
  rec.regions.nine = true
end

local function bevelColors(color, style)
  if style == "bevelOut" then return mix(color, 1, 0.35), mix(color, 0, 0.5) end
  if style == "bevelIn" then return mix(color, 0, 0.5), mix(color, 1, 0.35) end
  return color, color
end

--- Draw the target's border on its holder: `style` "flat", "bevelOut", "bevelIn" or
--- "nine:<LSM border key>", `size` pixels, `color` the edge color (a nine-slice's vertex color).
--- A nil color hides it.
function P.edges(rec, frame, color, style, size)
  if not color then return P.hideEdges(rec, frame) end
  local h = P.holder(rec, frame)
  if not h then return end
  size = type(size) == "number" and size or 1
  local key = type(style) == "string" and style:match("^nine:(.+)$")
  local path = key and P.media("border", key)
  if path then return nineEdge(rec, frame, h, path, size, color) end
  if key then style, size = "flat", 1 end
  clearNine(rec, frame)
  local light, dark = bevelColors(color, style)
  for _, side in ipairs(SIDES) do
    local t = P.tex(rec, "edge" .. side, h, "BORDER")
    if t then
      local a = SIDE_ANCHOR[side]
      t:ClearAllPoints()
      t:SetPoint(a[1], h, a[1])
      t:SetPoint(a[2], h, a[2])
      t[a[3]](t, size)
      t:SetColorTexture(rgba((side == "Top" or side == "Left") and light or dark))
      t:Show()
    end
  end
end

--- Save a stock frame's backdrop once, before the first SetBackdrop a primitive makes on it.
local function saveBackdrop(rec, frame)
  if rec.regions.backdrop ~= nil then return end
  local bd = type(frame.GetBackdrop) == "function" and frame:GetBackdrop() or nil
  local s = { bd = type(bd) == "table" and bd or false }
  if s.bd then
    s.c = { frame:GetBackdropColor() }
    s.b = { frame:GetBackdropBorderColor() }
  end
  rec.regions.backdrop = s
end

local function restoreBackdrop(rec, frame)
  local s = rec.regions.backdrop
  if not s then return end
  rec.regions.backdrop = nil
  if not s.bd then return frame:SetBackdrop(nil) end
  frame:SetBackdrop(s.bd)
  if s.c[1] then frame:SetBackdropColor(unpack(s.c)) end
  if s.b[1] then frame:SetBackdropBorderColor(unpack(s.b)) end
end
P.saveBackdrop, P.restoreBackdrop = saveBackdrop, restoreBackdrop

--- The library's flat-control backdrop: one WHITE8X8 table, then the fill, then the edge, four
--- components each (Widgets' dropdown and search box, LootHistory's buttons, cards and panels).
--- `insets` false is the shared popup menu's table, which has none.
function P.backdrop(rec, frame, fill, border, size, insets)
  saveBackdrop(rec, frame)
  local t = { bgFile = WHITE8, edgeFile = WHITE8, edgeSize = size }
  if insets ~= false then t.insets = { left = size, right = size, top = size, bottom = size } end
  frame:SetBackdrop(t)
  frame:SetBackdropColor(rgba(fill or CLEAR))
  frame:SetBackdropBorderColor(rgba(border or CLEAR))
end

local function boxFillParent(rec, frame, spec)
  if spec.extra then return P.under(rec, frame) end
  return frame
end

local function hasGradient(T, base) return base and T[base .. "Top"] and T[base .. "Bottom"] and true end

-- The gradient a backdrop cannot draw, over its fill: a region of the target (a primitive of
-- EllesmereUI's vocabulary), or of the fill holder (a Ka0s extra, whose backdrop fill is then
-- cleared: the gradient, drawn under the target, is the fill).
local function boxGradient(rec, frame, T, spec)
  local base = spec.fill
  if not hasGradient(T, base) then return P.hide(rec, "grad") end
  local parent = boxFillParent(rec, frame, spec)
  local t = P.tex(rec, "grad", parent, "BACKGROUND", 1)
  if not t then return end
  t:SetAllPoints(parent)
  P.fill(rec, t, T, base)
end

--- Read a box spec's tokens: fill color, border color, style, size, flat.
local function boxTokens(T, spec, opts)
  local fill = spec.fill and T[spec.fill] or nil
  local border = spec.border and T[spec.border] or nil
  if opts.noBg then fill = CLEAR end
  if opts.noBorder then border = nil end
  local style = spec.style and T[spec.style] or "flat"
  local size = spec.size and T[spec.size] or 1
  return fill, border, style, size, style == "flat"
end

-- A box on a frame with no backdrop: the fill as a region (of the target, or the fill holder for
-- an extra), the border on the holder.
local function regionBox(rec, frame, T, spec, border, style, size)
  local parent = boxFillParent(rec, frame, spec)
  local t = spec.fill and P.tex(rec, "fill", parent, "BACKGROUND", 0)
  if t then
    t:SetAllPoints(parent)
    P.fill(rec, t, T, spec.fill)
  end
  P.edges(rec, frame, border, style, size)
end

--- Paint a box: `spec` names the fill, border, style and size tokens (`extra` true for a Ka0s
--- extra, whose fill regions go on the fill holder; `insets` false for a menu's backdrop). A frame with
--- a backdrop wears the flat-control backdrop; a non-flat border goes on the holder. A spec whose
--- fill and border both resolve to nil leaves the frame alone, and puts back a backdrop a previous
--- skin set.
function P.box(rec, frame, T, spec, opts)
  opts = type(opts) == "table" and opts or {}
  local fill, border, style, size, flat = boxTokens(T, spec, opts)
  if not fill and not border and not opts.noBg then
    if P.hasBackdrop(frame) then restoreBackdrop(rec, frame) end
    P.hide(rec, "fill"); P.hide(rec, "grad")
    return P.hideEdges(rec, frame)
  end
  if not P.hasBackdrop(frame) then return regionBox(rec, frame, T, spec, border, style, size) end
  if spec.extra and hasGradient(T, spec.fill) then fill = CLEAR end
  P.backdrop(rec, frame, fill, flat and border or nil, flat and size or 1, spec.insets)
  boxGradient(rec, frame, T, spec)
  if flat then return P.hideEdges(rec, frame) end
  P.edges(rec, frame, border, style, size)
end

--- Recolor a backdrop the target already wears (its own art kept): fill four components, edge as
--- the call sites write it. A nil token leaves that half alone.
function P.recolor(frame, fill, border)
  if fill then frame:SetBackdropColor(rgba(fill)) end
  if border then frame:SetBackdropBorderColor(rgb(border)) end
end

-- ── putting a target back ────────────────────────────────────────────────────────────────────

local function restoreColors(rec, method)
  local priors = rec.regions.saved and rec.regions.saved[method]
  if not priors then return end
  for obj, c in pairs(priors) do
    if c then obj[method](obj, unpack(c)) end
    priors[obj] = nil
  end
end

--- Undo everything a primitive did to a target: faded art back to its alpha, fonts, text and vertex
--- colors and a backdrop back to what they were, every Ka0s region and both holders hidden. The
--- regions are kept for reuse.
function P.unpaint(rec, frame)
  local s = rec.regions.saved or {}
  for region, a in pairs(s.alpha or {}) do region:SetAlpha(a) end
  s.alpha = nil
  for fs in pairs(s.font or {}) do P.unfont(rec, fs) end
  restoreColors(rec, "SetTextColor")
  restoreColors(rec, "SetVertexColor")
  if P.hasBackdrop(frame) then restoreBackdrop(rec, frame) end
  P.hideEdges(rec, frame)
  for key, r in pairs(rec.regions) do
    if key ~= "holder" and lib.__ours[r] then r:Hide() end
  end
  if rec.regions.holder then rec.regions.holder:Hide() end
end

--- Mark a stock target (one wearing the client's template art) on its record, so its art is faded
--- under every skin. Answers false: since minor 6 no skin leaves a stock target as the client draws
--- it, Ka0s Default included, so the caller always paints. The owner argument is kept for callers.
function P.stockDefault(_, rec, frame, opts)
  if P.hasStock(frame, opts) then rec.regions.stock = true end
  return false
end

--- Record that `prim` painted `target` for `owner` (Skin:Track), and answer the record. A target
--- another owner painted is given back first; the record answers the target's lasting regions.
function P.track(owner, target, name, ...)
  if type(target) ~= "table" then return nil end
  local old = lib.painted[target]
  if old and old.owner ~= owner then P.unpaint(old, target) end
  local rec = lib:Track(owner, target, name, ...)
  if not rec then return nil end
  local regions = lib.__regions[target]
  if regions then
    rec.regions = regions
  else
    lib.__regions[target] = rec.regions
  end
  return rec
end

-- ── the window family ────────────────────────────────────────────────────────────────────────

local WHITE_CORE = "Interface\\Buttons\\WHITE8x8"   -- Core.SKIN's spelling

-- The table Shell hands Core.ApplySkin, in Core.SKIN's shape, from the skin's tokens (Ka0s Default's
-- included since minor 6: they carry Core.SKIN's values).
local function shellSkin(_, T, opts, flat)
  local size = flat and (T["win.borderSize"] or 1) or 1
  return {
    bgFile = WHITE_CORE, edgeFile = WHITE_CORE, edgeSize = size,
    insets = { left = size, right = size, top = size, bottom = size },
    bg = T["win.bg"] or CLEAR,
    border = (flat and not opts.noBorder) and T["win.border"] or CLEAR,
    innerBorder = (not opts.noBorder) and T["win.inner"] or nil,
    divider = T["divider"], title = T["title.text"],
  }
end

-- A band of the window (the gradient, the tiled art, the top and bottom bars): a region of the
-- target in BACKGROUND, inside the border, made once and hidden when the skin draws none.
local function band(rec, frame, key, sublevel, inset, height, bottom)
  local t = P.tex(rec, key, frame, "BACKGROUND", sublevel)
  if not t then return nil end
  t:ClearAllPoints()
  if bottom then
    t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
    t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
  else
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
  end
  if height then
    t:SetHeight(height)
  else
    t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
    t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
  end
  return t
end

local function shellBands(rec, frame, T, opts, inset)
  if T["win.bgTop"] and T["win.bgBottom"] then
    P.fill(rec, band(rec, frame, "grad", -7, inset), T, "win.bg")
  else
    P.hide(rec, "grad")
  end
  local art = P.media("background", T["win.bgTexture"])
  if art then
    local t = band(rec, frame, "art", -6, inset)
    if t then
      t:SetTexture(art); t:SetHorizTile(true); t:SetVertTile(true); t:Show()
    end
  else
    P.hide(rec, "art")
  end
  local h = T["title.height"] or 30
  if not opts.noTopBar and (T["title.bg"] or T["title.bgTop"]) then
    P.fill(rec, band(rec, frame, "top", -5, inset, h), T, "title.bg")
  else
    P.hide(rec, "top")
  end
  if opts.bottomBar and T["foot.bg"] then
    local bh = type(opts.bottomBar) == "number" and opts.bottomBar or h
    P.fill(rec, band(rec, frame, "bottom", -5, inset, bh, true), T, "foot.bg")
  else
    P.hide(rec, "bottom")
  end
end

-- A frame with no backdrop: the fill as a region, every edge on the holder.
local function shellRegions(rec, frame, T, opts)
  local t = band(rec, frame, "fill", -8, 0)
  P.fill(rec, t, T, "win.bg")
  local c = not opts.noBorder and T["win.border"] or nil
  P.edges(rec, frame, c, T["win.borderStyle"], T["win.borderSize"])
end

-- A frame with a backdrop: Core.ApplySkin with the skin's table, the inner rule cleared when the
-- skin has none (ApplySkin leaves an existing one tinted), and a non-flat edge on the holder.
local function shellBackdrop(owner, rec, frame, T, opts, style)
  local flat = style == "flat"
  local c = core()
  local skin = shellSkin(owner, T, opts, flat)
  if c and type(c.ApplySkin) == "function" then c.ApplySkin(frame, skin) end
  local inner = rawget(frame, "innerBorder")
  if not skin.innerBorder and P.isFrame(inner) then inner:SetBackdropBorderColor(0, 0, 0, 0) end
  if flat or opts.noBorder then return P.hideEdges(rec, frame) end
  P.edges(rec, frame, T["win.border"], style, T["win.borderSize"])
end

--- S.Shell(frame, opts): a window. On a frame with a backdrop it is Core.ApplySkin, from the skin's
--- tokens (the backdrop, the inner rule, `frame.title`'s color and `frame.divider`'s), plus what a
--- backdrop cannot draw: a nine-slice or bevel edge on the holder, the window gradient, the tiled
--- art, and the top bar (`title.bg`, unless `opts.noTopBar`) and bottom bar (`foot.bg`, when
--- `opts.bottomBar`, a height or true). `opts.noBorder` draws no edge and no inner rule.
--- Draws no Media icon.
prim.Shell = function(owner, frame, opts)
  if type(frame) ~= "table" then return end
  local rec = P.track(owner, frame, "Shell", opts)
  opts = type(opts) == "table" and opts or {}
  if P.stockDefault(owner, rec, frame, opts) then return end
  local T = P.T(owner)
  -- A payload with no SkinDefs.lua registers no skin, so no token resolves: the window is left as
  -- it is rather than painted with nothing (the header's degraded engine).
  if T["win.bg"] == nil then return end
  local style = T["win.borderStyle"] or "flat"
  if rec.regions.stock then P.fadeAll(rec, P.stockRegions(frame, opts)) end
  if P.hasBackdrop(frame) then
    shellBackdrop(owner, rec, frame, T, opts, style)
  else
    shellRegions(rec, frame, T, opts)
  end
  local inset = style == "flat" and T["win.borderSize"] or 1
  shellBands(rec, frame, T, opts, inset or 1)
  local title = rawget(frame, "title")
  if P.isFS(title) then P.font(owner, rec, title, "title") end
end

local PANEL = { fill = "panel.bg", border = "panel.border" }
local INSET = { fill = "input.bg", border = "input.border", style = "input.borderStyle",
                size = "input.borderSize" }

local function panel(owner, frame, opts, name, spec)
  if type(frame) ~= "table" then return end
  local rec = P.track(owner, frame, name, opts)
  opts = type(opts) == "table" and opts or {}
  if P.stockDefault(owner, rec, frame, opts) then return end
  local T = P.T(owner)
  if opts.nav then
    -- The settings nav rail keeps its own backdrop art and is recolored (OptionsNav's pane).
    return P.recolor(frame, T["nav.bg"], T["nav.border"])
  end
  if opts.inset then spec = INSET end
  P.box(rec, frame, T, spec, opts)
end

--- S.Panel(frame, opts): a flat panel, `panel.bg` under a `panel.border` edge (LootHistory's list
--- panels). `opts.inset` paints it as an inset (`input.*`); `opts.noBg`, `opts.noBorder` leave out
--- either half; `opts.nav` recolors the backdrop the frame already wears with `nav.bg` /
--- `nav.border` (the settings nav rail). Draws no Media icon.
prim.Panel = function(owner, frame, opts) return panel(owner, frame, opts, "Panel", PANEL) end

--- S.Inset(frame, opts): a recessed area, the input colors (`input.bg`, `input.border`, its style
--- and size). Draws no Media icon.
prim.Inset = function(owner, frame, opts) return panel(owner, frame, opts, "Inset", INSET) end

--- S.FadeRegions(frame, ...): fade every texture region of `frame` (and of each further frame) that
--- no primitive made, prior alphas recorded, under every skin (Ka0s Default too since minor 6).
prim.FadeRegions = function(owner, frame, ...)
  if not P.isFrame(frame) then return end
  local rec = P.track(owner, frame, "FadeRegions", ...)
  rec.regions.stock = true
  local frames = { frame, ... }
  for _, f in ipairs(frames) do
    if P.isFrame(f) and type(f.GetRegions) == "function" then
      for _, r in ipairs({ f:GetRegions() }) do
        if P.isTexture(r) and not lib.__ours[r] then P.fade(rec, r) end
      end
    end
  end
end

--- S.FadeNineSlice(frame): fade the nine pieces of `frame.NineSlice`, under every skin.
prim.FadeNineSlice = function(owner, frame)
  if not P.isFrame(frame) then return end
  local rec = P.track(owner, frame, "FadeNineSlice")
  rec.regions.stock = true
  local ns = rawget(frame, "NineSlice")
  if not P.isFrame(ns) then return end
  for _, k in ipairs(NINE_KEYS) do P.fade(rec, P.field(ns, k, "Texture")) end
end
