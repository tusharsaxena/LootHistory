-- LibKa0s-Skin-1.0 — SkinPaintHud: the HUD's two shared looks, S.BarGloss and S.HudFont.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF SkinPaintExtras.lua ──────────────────────────
--
-- Because of `layout-§1`. SkinPaintExtras.lua was 1217 lines, in the band past its re-check trigger,
-- and the owner ruled the band files peeled (FU-L2 of Ka0sAddonsCommonTasks
-- docs/2026-11-06-FOLLOWUPS_V1_91). Its named seam, the confirmation box (SkinAceConfirm.lua), alone
-- left it at 1058, so this section, the extras' last primitives, moved too, at SkinPaintExtras minor
-- 19, unchanged: `prim.BarGloss` and `prim.HudFont` with their font-object registry (`__hudFonts`,
-- `__hudLooks`, `__hudFontSeq`). Their history is SkinPaintExtras.lua's header and the Skin
-- document. Part of the same major, paired on the shell's minor (`__hudMinor` / `__hudShellMinor`),
-- and it paints with SkinPaint.lua's helpers (`lib.__P`), so it attaches only when that file attached
-- to the same shell, as SkinPaintExtras.lua does. It reads S.HudShadow, S.HudFontSize and S.FontFlags
-- off `lib.prim` at call time. A payload without this file has no BarGloss and no HudFont.

local lib = LibStub and LibStub("LibKa0s-Skin-1.0", true)
if not lib then return end   -- the shell refused (no Core, or below its floor): nothing to attach to
if lib.__paintShellMinor ~= lib.MINOR or not lib.__P then return end   -- no helpers from this copy

local HUD_MINOR = 2
-- Minor 1: the HUD's shared looks, moved here unchanged from SkinPaintExtras.lua (its minor 19).
-- Minor 2 (SD-LK-97.3 of Ka0sAddonsCommonTasks docs/2026-11-20-SKIN_DEFAULTS_AUDIT, LibKa0s#97; the
-- owner's U-4): S.BarGloss takes a bar of data's fill Texture too, its gloss a region of the
-- Texture's parent, so the Widgets Bar and the Charts bars wear Glass's gloss as a StatusBar does.
if lib.__hudMinor and lib.__hudMinor >= HUD_MINOR
  and lib.__hudShellMinor == lib.MINOR then return end
lib.__hudMinor      = HUD_MINOR
lib.__hudShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.SkinPaintHud = HUD_MINOR

local prim, P = lib.prim, lib.__P

-- ── the HUD's shared looks (minor 14) ────────────────────────────────────────────────────────

-- The one gloss look, as P.fill's tokens: no skin token says otherwise, `bar.gloss` is a bool.
local GLOSS = { glossTop = { 1, 1, 1, 0.25 }, glossBottom = { 1, 1, 1, 0 } }

--- S.BarGloss(statusBar, fromSkin) (minor 14): the skin's gloss on a bar of data, where `bar.gloss` is true: a
--- white gradient over the fill's top half, 0.25 at the top and clear at the middle. One layer, built
--- on first need, a region of the status bar at the bottom of OVERLAY, so it sits over the fill and
--- under a host's text, and it is anchored to the fill, so it never shines past it. That makes it the
--- one overlay that is no holder's: a holder would sit over a host's border and text. `fromSkin`
--- (minor 15) is the host's texture companion: the gloss belongs to the skin's texture, so `false`, a
--- player's own texture, hides it, and nil or true leave it to the skin. Recorded with the argument,
--- so a skin change shows or hides it with no host call and a replay keeps `false`; call it once
--- after the bar has its texture, again when the companion moves, and again if a host hands the bar
--- a new fill Texture. Draws no Media icon.
--- A Texture (minor 2, SD-LK-97.3): a bar of data drawn as a Texture, the Widgets Bar's fill and a
--- Charts bar's. The same look, a region of the Texture's parent frame at the same layer, anchored
--- to the Texture, and hidden while the Texture is: a host that hides and shows the Texture calls it
--- again, or shows the answer with it (the Bar does, on every layout). Answers the gloss while the
--- skin draws one (a StatusBar's too), else nil. Anything but a StatusBar or a Texture with a frame
--- parent is left alone.
local function glossOn(owner, fromSkin)
  return fromSkin ~= false and P.T(owner)["bar.gloss"] == true
end

local function glossFill(rec, parent, fill)
  local gloss = P.tex(rec, "gloss", parent, "OVERLAY", -8)
  if not gloss then return nil end
  gloss:ClearAllPoints()
  gloss:SetPoint("TOPLEFT", fill, "TOPLEFT")
  gloss:SetPoint("BOTTOMRIGHT", fill, "RIGHT")
  P.fill(rec, gloss, GLOSS, "gloss")
  return gloss
end

--- The Texture half (minor 2): the gloss on the Texture's parent, shown only while the Texture is.
local function textureGloss(owner, tex, fromSkin)
  local rec = P.track(owner, tex, "BarGloss", fromSkin)
  local parent = type(tex.GetParent) == "function" and tex:GetParent() or nil
  if not (rec and glossOn(owner, fromSkin) and P.isFrame(parent)) then
    if rec then P.hide(rec, "gloss") end
    return nil
  end
  local gloss = glossFill(rec, parent, tex)
  if gloss and type(tex.IsShown) == "function" and tex:IsShown() == false then gloss:Hide() end
  return gloss
end

prim.BarGloss = function(owner, statusBar, fromSkin)
  local kind = P.kind(statusBar)
  if kind == "Texture" then return textureGloss(owner, statusBar, fromSkin) end
  if kind ~= "StatusBar" then return nil end
  local rec = P.track(owner, statusBar, "BarGloss", fromSkin)
  local fill = statusBar:GetStatusBarTexture()
  if not (glossOn(owner, fromSkin) and fill) then
    P.hide(rec, "gloss")
    return nil
  end
  return glossFill(rec, statusBar, fill)
end

-- `__hudLooks`: a look's key -> { obj, ready }, its one font object for the session, across owners.
-- `__hudFonts`: a string -> the object it wears, which only says so. Kept across minors: a client
-- never frees a font object, so a newer copy must not start over.
lib.__hudFonts = lib.__hudFonts or setmetatable({}, { __mode = "k" })
lib.__hudLooks = lib.__hudLooks or {}
lib.__hudFontSeq = lib.__hudFontSeq or 0

--- The look's entry, made on first need. Nil where the client has no CreateFont. A replaced CreateFont
--- starts a fresh table, since the entries are another maker's: in the client that is an addon
--- wrapping it, once, and in a suite it is what lets a fake see what S.HudFont writes.
local function hudLook(key)
  if type(CreateFont) ~= "function" then return nil end
  if lib.__hudLookMaker ~= CreateFont then
    lib.__hudLookMaker, lib.__hudLooks = CreateFont, {}
  end
  local look = lib.__hudLooks[key]
  if look then return look end
  lib.__hudFontSeq = lib.__hudFontSeq + 1
  look = { obj = CreateFont("LibKa0sHud_" .. lib.__hudFontSeq) }
  lib.__hudLooks[key] = look
  return look
end

--- A stored shadow as x, y, r, g, b, a, or false: `true` is the client's 1, -1 in black, a table is
--- `{ x, y, r, g, b, a }`, anything else is none.
local function storedShadow(s)
  if s == true then return 1, -1, 0, 0, 0, 1 end
  if type(s) ~= "table" or type(s[1]) ~= "number" then return false end
  return s[1], s[2] or 0, s[3] or 0, s[4] or 0, s[5] or 0, s[6] or 1
end

--- The shadow a HUD string draws. With the host's companion on (nil counts), S.HudShadow's answer for
--- `opts.shadowToken`: false none, numbers those; nil, the owner ignoring fonts, and a companion off
--- leave the stored one.
local function hudShadow(owner, opts)
  if opts.shadowFromSkin ~= false then
    local x, y, r, g, b, a = prim.HudShadow(owner, opts.shadowToken)
    if x == false then return false end
    if x ~= nil then return x, y, r, g, b, a end
  end
  return storedShadow(opts.shadow)
end

--- Face, size and flags on `target`, answering whether the face took. The client answers false for a
--- file it has not loaded, which on a fresh font object leaves no font at all, so the client's own
--- face goes on instead.
local function setHudFace(target, face, size, flags)
  if target:SetFont(face, size, flags) ~= false then return true end
  if type(STANDARD_TEXT_FONT) == "string" then target:SetFont(STANDARD_TEXT_FONT, size, flags) end
  return false
end

--- BOTH shadow arms write: an off arm that skipped the calls would keep what the last pass set.
local function setHudShadow(target, x, y, r, g, b, a)
  if x == false then x, y, r, g, b, a = 0, 0, 0, 0, 0, 0 end
  target:SetShadowColor(r, g, b, a)
  target:SetShadowOffset(x, y)
end

--- Everything a font object carries, as a key: two strings with one key draw alike.
local function hudLookKey(face, size, flags, x, y, r, g, b, a)
  return ("%s|%s|%s|%s|%s|%s|%s|%s|%s"):format(face, tostring(size), flags, tostring(x), tostring(y),
    tostring(r), tostring(g), tostring(b), tostring(a))
end

--- Face, size, flags and shadow on `fs`'s font object, or on `fs` where the client has none. Answers
--- the object, or nil.
local function wearHudLook(fs, face, size, flags, ...)
  local look = hudLook(hudLookKey(face, size, flags, ...))
  if not look then
    setHudFace(fs, face, size, flags)
    setHudShadow(fs, ...)
    return nil
  end
  if not look.ready then
    look.ready = setHudFace(look.obj, face, size, flags)
    setHudShadow(look.obj, ...)
  end
  lib.__hudFonts[fs] = look.obj
  fs:SetFontObject(look.obj)
  P.holdFace(fs, look.obj:GetFont())
  return look.obj
end

--- S.HudFont(fs, opts) (minor 14): the one way to give a HUD string its face, size, flags and shadow.
--- It all goes on a named font object, the only place a 12.0.7 client draws a shadow, or on the string
--- where the client has no CreateFont. One object per LOOK (minor 16), shared by every string and
--- owner that draws it and never rewritten, because a client never frees one: a face the client
--- refused is tried again on the next call. `opts`, all optional: `face` (a path; the
--- skin's `hud.font`, unread while the owner ignores fonts (minor 15), else the client's), `size` (as it draws: pass `S.HudFontSize`'s
--- answer; 12 when not above 0), `flags` (through S.FontFlags, so "@skin" is safe), `shadow` (the
--- host's stored one: true, false or `{ x, y, r, g, b, a }`), `shadowFromSkin` (the host's companion;
--- false draws `shadow` under every skin), `shadowToken` (minor 16, S.HudShadow's `token`). S.HudShadow's three answers apply while the companion is
--- on: false no shadow, nil the stored `shadow`, numbers those. A keyed table is no shadow, with no
--- error. Answers the font object, or nil.
--- Not recorded: the face and size are the host's resolved values, which a replay would draw stale,
--- so call it from the appearance pass a skin change reaches, and set the text color after it.
prim.HudFont = function(owner, fs, opts)
  if type(fs) ~= "table" or P.isTexture(fs) or type(fs.SetFont) ~= "function" then return nil end
  opts = type(opts) == "table" and opts or {}
  local face = opts.face
  if type(face) ~= "string" or face == "" then
    face = P.media("font", lib:Token(owner, "hud.font")) or STANDARD_TEXT_FONT
  end
  if type(face) ~= "string" then return nil end
  local size, flags = prim.HudFontSize(owner, opts.size, false), prim.FontFlags(owner, opts.flags)
  return wearHudLook(fs, face, size, flags, hudShadow(owner, opts))
end
