-- LibKa0s-WaypointArrow-1.0 — a small movable arrow that points the way to a target, with the distance under it.
--
-- ── WHY THIS EXISTS ──────────────────────────────────────────────────────────────────────────
--
-- Skill Master drew its own waypoint arrow (owner feedback rounds 6 and 7) because the client's own
-- arrow follows a super-tracked pin and another addon answering TomTom's API hid it. Any Ka0s addon
-- that sets a waypoint wants the same frame, the same rotation math and the same care around secret
-- values, so it is written once here (the owner's decisions of 2026-11-14, Skill Master
-- docs/superpowers/plans/2026-11-14-feedback-round8.md, row L1). Skill Master is its one consumer;
-- the one-consumer promotion is a row in CLAUDE.md's register.
--
-- ── THE CONTRACT ─────────────────────────────────────────────────────────────────────────────
--
-- `WaypointArrow:New(d)` answers one instance. `d.addon` (or `d.mediaBase`) is required: it says
-- where the art sits. Everything else is optional: `name` (the frame's global name), `vendorPath`,
-- `parent`, `strata`, `skin` (a registered skin owner: the skin's colors and the text's role),
-- `point` (the saved position), `onMoved(point)` (a drag ended: persist the point), `canDrag()`,
-- `onClick(frame, button)`, `onEnter(frame)`, `onLeave(frame)`, `onArrive(target)`, `arrive`,
-- `near`, `far`, `format(yards, units)`, `strings` and `debug(tag, msg)`. The instance owns no SavedVariables: the
-- host keeps its settings at its own paths (WaypointArrowSettings.lua's rows) and hands them over
-- with `Configure`. docs/api/WaypointArrow/version-1.1-docs.md is the full contract.
--
-- ── GEOMETRY ─────────────────────────────────────────────────────────────────────────────────
--
-- World coordinates (C_Map.GetWorldPosFromMapPos, UnitPosition): x points north, y points west.
-- GetPlayerFacing() is radians counter-clockwise from north. The bearing to the target, measured the
-- same way, is atan2(ty - py, tx - px): +y is west, so a target due west is +pi/2. The arrow's
-- rotation is bearing - facing, folded into -pi .. pi, and Texture:SetRotation turns
-- counter-clockwise for a positive angle, so the art, drawn pointing up (straight ahead), turns
-- towards the target. The ground look cannot turn (its art is tilted), so it picks one of 72
-- pre-drawn frames, one per 5 degrees, with SetTexCoord (`GroundFrame`, `GroundTexCoord`).
--
-- ── GUARDS ───────────────────────────────────────────────────────────────────────────────────
--
-- GetPlayerFacing can answer nil or a secret value (instances, some indoor places) and the
-- positions can be secret or unknown: every read is pcall'd and checked with issecretvalue, and a
-- value that is not a plain number is no value. With no facing the art hides and the distance
-- stays; with no distance (another continent, an instance) the target's label shows alone, dim.
-- Within `arrive` yards `onArrive(target)` is called and the target is cleared. The frame is never
-- secure and calls nothing protected, so it stays shown, and moves, in combat. Its OnUpdate is
-- armed only while it is shown.
--
-- ── DEPENDENCIES ─────────────────────────────────────────────────────────────────────────────
--
-- LibStub and LibKa0s-Core-1.0 minor 1 or newer, the gate every module here takes. LibKa0s-Skin-1.0
-- (the skin's colors, `Color`; the text's role, `For(owner).Text`) is resolved at the call that
-- needs it and optional: without it the colors are the custom ones and the text the game's font.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-WaypointArrow-1.0", 2
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.WaypointArrow = MINOR

-- ── the looks ────────────────────────────────────────────────────────────────────────────────
--
-- Every file is tools/artwork/waypoint_arrow.py's, under media/waypoint/. A look is a BODY tinted
-- with the color and an OVERLAY drawn over it untinted (the highlights, the shading a multiply
-- cannot reach, the outline); raised adds a drop shadow that stays down and right while the arrow
-- turns; ground is an angle sheet.
lib.STYLES = { "flat", "ridge", "raised", "faceted", "ground" }
lib.DEFAULT_STYLE = "raised"
local LOOK = {
  flat    = { body = "arrow-fill", overlay = "flat-overlay" },
  ridge   = { body = "arrow-fill", overlay = "ridge-overlay" },
  raised  = { body = "arrow-fill", overlay = "raised-overlay", shadow = "raised-shadow" },
  faceted = { body = "arrow-fill", overlay = "faceted-overlay" },
  ground  = { body = "ground-body", overlay = "ground-overlay", sheet = true },
}
lib.MEDIA_DIR = "media\\waypoint"

-- Minor 2 (L1 of Skill Master docs/superpowers/plans/2026-11-14-feedback-round9.md): the art draws
-- 1.25x larger at scale 1, the owner's new 1.0. Everything below is in UNITS of the art's 48-unit
-- design box and is drawn at ART / UNITS pixels per unit (`unitPx`): the art, the shadow and its
-- offset, the ground cells, the text's gap and the frame's hit rect around the art. The TGAs are
-- not regenerated: they are 128 and 512 px, so a 60 px box still samples them down.
lib.UNITS = 48                      -- the art's design box, units
lib.ART = 60                        -- the drawn size of that box, px, at scale 1 (48 at minor 1)
lib.SHADOW_BOX = 64                 -- raised's shadow canvas, units (the blur is never cut as it turns)
lib.SHADOW_OFFSET = { 1.5, -3 }     -- units, x right and y up: the mockup's translate(1.5 3)
lib.TEXT_GAP = 2                    -- units between the art box and the text
lib.HIT_PAD = 8                     -- units of hit rect past the art box on its left and right
lib.TEXT_ROOM = 22                  -- units of hit rect under the art box, for the text

--- The ground look's angle sheet, as the generator lays it out.
lib.GROUND = {
  frames = 72, step = 5, cols = 8, cellW = 64, cellH = 44, sheet = 512,
  box = { -1, 12, 49, 46.375 },     -- the units one cell covers, x0 y0 x1 y1 (y down)
}

-- ── the settings ─────────────────────────────────────────────────────────────────────────────

lib.SCALE_MIN, lib.SCALE_MAX = 0.5, 2

-- The distance text (minor 2, L2): the canonical Font block's six leaves and its "Use the skin's
-- font" companion (OptionsCompose's FontGroup with `fromSkin` and `flagsFromSkin`), where the text
-- sits, a second line with the target's label, and the distance's units.
lib.TEXT_POSITIONS = { "BELOW", "ABOVE", "LEFT", "RIGHT", "HIDDEN" }
lib.DISTANCE_UNITS = { "yards", "compact" }
lib.FLAGS_FROM_SKIN = "@skin"       -- the Skin major's FROM_SKIN: the skin's HUD outline
lib.FONT_FLAGS = { "@skin", "", "OUTLINE", "THICKOUTLINE", "MONOCHROME", "OUTLINE, MONOCHROME" }
lib.FONT_DEFAULT = "Ka0s Prototype" -- FontGroup's own default face (Ka0s Default's pick)
lib.FONT_SIZE_MIN, lib.FONT_SIZE_MAX = 6, 32
lib.COMPACT_FROM = 1000             -- yards: from here "compact" reads thousands ("4.2k yd")
-- The position (minor 2, L3): offsets from the parent's CENTER in the PARENT's units (UIParent's: the
-- same spot on screen at every Arrow scale, applyPoint divides by the scale), PositionBlock's range.
lib.POSITION_MIN, lib.POSITION_MAX = -2000, 2000

--- The settings a host seeds its own paths with. Colors are { r, g, b, a }; a keyed { r =, g =,
--- b = } is read as well. The far color is Ka0s Default's `text.accent`, the near its `sem.good`.
lib.DEFAULTS = {
  style = lib.DEFAULT_STYLE,
  useSkinColors = true,
  farColor = { 1, 0.82, 0, 1 },
  nearColor = { 0.35, 0.80, 0.45, 1 },
  scale = 1,
  font = lib.FONT_DEFAULT, fontFromSkin = true, fontSize = 12, fontColor = { 1, 1, 1, 1 },
  useClassColorFont = false, fontFlags = lib.FLAGS_FROM_SKIN, fontShadow = true,
  textPosition = "BELOW", showLabel = false, distanceUnits = "yards",
  x = 0, y = 200, lock = false,
}
lib.SETTINGS = { "style", "useSkinColors", "farColor", "nearColor", "scale",
  "font", "fontFromSkin", "fontSize", "fontColor", "useClassColorFont", "fontFlags", "fontShadow",
  "textPosition", "showLabel", "distanceUnits", "x", "y", "lock" }
lib.SKIN_FAR, lib.SKIN_NEAR = "text.accent", "sem.good"   -- the skin's tokens "Use the skin's colors" reads

-- ── the measures ─────────────────────────────────────────────────────────────────────────────

lib.ARRIVE, lib.NEAR, lib.FAR = 5, 30, 300   -- yards: arrival, the near color's edge, the far color's
lib.THROTTLE = 0.03                          -- seconds between two measures while shown
lib.SAMPLE_YARDS, lib.SAMPLE_ROTATION = 240, math.rad(35)   -- the sample: 35 degrees to the left
lib.STRATA = "MEDIUM"
lib.DEFAULT_POINT = { point = "CENTER", relPoint = "CENTER", x = 0, y = 200 }
lib.STRINGS = { DISTANCE = "%d yd", DISTANCE_COMPACT = "%.1fk yd", SAMPLE = "Waypoint",
  -- Minor 2 (L4): the right-click menu's words.
  MENU_CLEAR = "Clear waypoint", MENU_SHARE = "Share in chat", MENU_MAP = "Show on map",
  MENU_LOCK = "Lock the arrow", MENU_UNLOCK = "Unlock the arrow", MENU_RESET = "Reset position",
  MENU_SHARE_TIP = "Opens the chat box with a /way line for this waypoint. Press Enter to send it to the channel the box is set to, or edit it first. Nothing is sent until you do.",
  MENU_NO_MAP = "This waypoint has no map point to share or show.",
  MENU_COMBAT = "Not available in combat.",
}
lib.MENU_ITEMS = { "clear", "share", "map", "lock", "reset" }   -- the stock items' ids, in order

local TAG = "ARROW"
local DIM = 0.6                 -- the label's alpha while no distance shows

-- ── small readers ────────────────────────────────────────────────────────────────────────────

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end

local function plainNumber(v)
  return not isSecret(v) and type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function inList(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

--- r, g, b of a color in either shape ({ r, g, b, a } or { r =, g =, b = }), or nil.
local function rgbOf(c)
  if type(c) ~= "table" then return nil end
  local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
  if not (plainNumber(r) and plainNumber(g) and plainNumber(b)) then return nil end
  return r, g, b
end

local function isBool(v) return type(v) == "boolean" end
local function isColor(v) return rgbOf(v) ~= nil end
local function oneOf(list) return function(v) return inList(list, v) end end

local VALID = {
  style = function(v) return LOOK[v] ~= nil end,
  useSkinColors = isBool,
  farColor = isColor,
  nearColor = isColor,
  scale = function(v) return plainNumber(v) and v >= lib.SCALE_MIN and v <= lib.SCALE_MAX end,
  font = function(v) return type(v) == "string" and v ~= "" end,
  fontFromSkin = isBool,
  fontSize = function(v) return plainNumber(v) and v >= lib.FONT_SIZE_MIN and v <= lib.FONT_SIZE_MAX end,
  fontColor = isColor,
  useClassColorFont = isBool,
  fontFlags = oneOf(lib.FONT_FLAGS),
  fontShadow = isBool,
  textPosition = oneOf(lib.TEXT_POSITIONS),
  showLabel = isBool,
  distanceUnits = oneOf(lib.DISTANCE_UNITS),
  x = function(v) return plainNumber(v) and v >= lib.POSITION_MIN and v <= lib.POSITION_MAX end,
  y = function(v) return plainNumber(v) and v >= lib.POSITION_MIN and v <= lib.POSITION_MAX end,
  lock = isBool,
}

local function resolve(major) return LibStub and LibStub(major, true) end

--- Pixels per art unit at scale 1 (minor 2).
local function unitPx() return lib.ART / lib.UNITS end

-- ── the pure math ────────────────────────────────────────────────────────────────────────────

--- The arrow's rotation (radians, counter-clockwise, -pi .. pi) from the player at (px, py) facing
--- `facing` to the target at (tx, ty), world yards (x north, y west); nil when any input is not a
--- plain number.
function lib.Rotation(px, py, tx, ty, facing)
  if not (plainNumber(px) and plainNumber(py) and plainNumber(tx) and plainNumber(ty)
    and plainNumber(facing)) then return nil end
  local r = math.atan2(ty - py, tx - px) - facing
  -- One turn's range, so the same direction always reads the same angle.
  while r > math.pi do r = r - 2 * math.pi end
  while r <= -math.pi do r = r + 2 * math.pi end
  return r
end

--- Yards between two world points (x, y), or nil.
function lib.Distance(px, py, tx, ty)
  if not (plainNumber(px) and plainNumber(py) and plainNumber(tx) and plainNumber(ty)) then return nil end
  local dx, dy = tx - px, ty - py
  return math.sqrt(dx * dx + dy * dy)
end

--- The fade at `yards`: 0 at `near` or closer, 1 at `far` or more, linear between; 1 (the far color)
--- for a distance that is not a number.
function lib.Fade(yards, near, far)
  near, far = near or lib.NEAR, far or lib.FAR
  if not plainNumber(yards) then return 1 end
  if far <= near then return yards <= near and 0 or 1 end
  return math.max(0, math.min(1, (yards - near) / (far - near)))
end

--- The color at fade `t` between `nearC` (t = 0) and `farC` (t = 1), each in either shape:
--- r, g, b.
function lib.Mix(farC, nearC, t)
  local fr, fg, fb = rgbOf(farC)
  local nr, ng, nb = rgbOf(nearC)
  if not fr then fr, fg, fb = rgbOf(lib.DEFAULTS.farColor) end
  if not nr then nr, ng, nb = fr, fg, fb end
  return nr + (fr - nr) * t, ng + (fg - ng) * t, nb + (fb - nb) * t
end

--- The ground sheet's frame for `rotation` (radians, counter-clockwise): 0 .. 71, the nearest
--- 5 degrees; nil for a rotation that is not a number.
function lib.GroundFrame(rotation)
  if not plainNumber(rotation) then return nil end
  local G = lib.GROUND
  return math.floor(math.deg(rotation) / G.step + 0.5) % G.frames
end

--- The texcoords (left, right, top, bottom) of ground frame `k`.
function lib.GroundTexCoord(k)
  local G = lib.GROUND
  local col, row = k % G.cols, math.floor(k / G.cols)
  return col * G.cellW / G.sheet, (col + 1) * G.cellW / G.sheet,
    row * G.cellH / G.sheet, (row + 1) * G.cellH / G.sheet
end

--- A distance as the text shows it (minor 2): `units` "yards" (the default) is `DISTANCE` of the
--- rounded yards; "compact" is the same below `COMPACT_FROM` and `DISTANCE_COMPACT` of the
--- thousands from there ("4.2k yd"). `strings` (optional) overrides `STRINGS` by key, read with
--- rawget. nil for a distance that is not a number.
function lib.FormatDistance(yards, units, strings)
  if not plainNumber(yards) then return nil end
  local function word(key)
    local v = type(strings) == "table" and rawget(strings, key)
    return type(v) == "string" and v or lib.STRINGS[key]
  end
  local n = math.floor(yards + 0.5)
  if units == "compact" and n >= lib.COMPACT_FROM then return word("DISTANCE_COMPACT"):format(n / 1000) end
  return word("DISTANCE"):format(n)
end

-- ── the client reads ─────────────────────────────────────────────────────────────────────────

local function facing()
  if type(GetPlayerFacing) ~= "function" then return nil end
  local ok, f = pcall(GetPlayerFacing)
  if not ok or not plainNumber(f) then return nil end
  return f
end

local function xyOf(pos)
  if isSecret(pos) or type(pos) ~= "table" then return nil end
  if type(pos.GetXY) == "function" then
    local ok, x, y = pcall(pos.GetXY, pos)
    if ok then return x, y end
    return nil
  end
  return pos.x, pos.y
end

--- A map point's (0..1) world position: instance, x, y; or nil.
local function mapWorld(mapID, x, y)
  local api = C_Map
  if not (plainNumber(mapID) and plainNumber(x) and plainNumber(y)) then return nil end
  if type(api) ~= "table" or type(api.GetWorldPosFromMapPos) ~= "function"
    or type(CreateVector2D) ~= "function" then return nil end
  local ok, instance, pos = pcall(api.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
  if not ok or not plainNumber(instance) then return nil end
  local wx, wy = xyOf(pos)
  if not (plainNumber(wx) and plainNumber(wy)) then return nil end
  return instance, wx, wy
end

--- The player's world position: their best map, their place on it, that point in the world.
local function playerWorld()
  local api = C_Map
  if type(api) ~= "table" or type(api.GetBestMapForUnit) ~= "function"
    or type(api.GetPlayerMapPosition) ~= "function" then return nil end
  local okMap, mapID = pcall(api.GetBestMapForUnit, "player")
  if not okMap or not plainNumber(mapID) then return nil end
  local okPos, pos = pcall(api.GetPlayerMapPosition, mapID, "player")
  if not okPos then return nil end
  local x, y = xyOf(pos)
  return mapWorld(mapID, x, y)
end

lib.MapWorldPos, lib.PlayerWorldPos, lib.PlayerFacing = mapWorld, playerWorld, facing

-- ── the instance state ───────────────────────────────────────────────────────────────────────

local STATE = setmetatable({}, { __mode = "k" })

local function state(self)
  local S = STATE[self]
  if not S then error(MAJOR .. ": call this on an instance from WaypointArrow:New", 3) end
  return S
end

local function debugOut(S, msg)
  local sink = S.d.debug
  if type(sink) == "function" then pcall(sink, TAG, msg) end
end

--- A host callback, under pcall: a raise reaches the error handler and the arrow runs on.
local function call(S, fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, ...)
  if ok then return a end
  local handler = type(geterrorhandler) == "function" and geterrorhandler() or nil
  if handler then pcall(handler, a) end
  debugOut(S, "callback failed: " .. tostring(a))
  return nil
end

local function setting(S, key)
  local v = S.settings[key]
  if v ~= nil and VALID[key](v) then return v end
  return lib.DEFAULTS[key]
end

local function skinOwner(S)
  local Skin = resolve("LibKa0s-Skin-1.0")
  local owner = S.d.skin
  if not (Skin and type(owner) == "string" and type(Skin.Color) == "function") then return nil end
  return Skin, owner
end

local function skinColor(S, token)
  local Skin, owner = skinOwner(S)
  if not Skin then return nil end
  local r, g, b = Skin:Color(owner, token)
  if not (plainNumber(r) and plainNumber(g) and plainNumber(b)) then return nil end
  return { r, g, b }
end

--- The far and near colors in use: the skin's (`SKIN_FAR`, `SKIN_NEAR`) while "Use the skin's
--- colors" is on and a skin answers, else the custom pair.
local function colors(S)
  if setting(S, "useSkinColors") then
    local far, near = skinColor(S, lib.SKIN_FAR), skinColor(S, lib.SKIN_NEAR)
    if far then return far, near or far end
  end
  return setting(S, "farColor"), setting(S, "nearColor")
end

local function mediaBase(S)
  local d = S.d
  if type(d.mediaBase) == "string" and d.mediaBase ~= "" then
    return (d.mediaBase:gsub("\\$", "")) .. "\\"
  end
  return "Interface\\AddOns\\" .. d.addon .. "\\" .. (d.vendorPath or "libs\\LibKa0s") .. "\\" .. lib.MEDIA_DIR .. "\\"
end

--- The host's path for `key` in `paths` (minor 2): its own entry, but for `fontFromSkin` the font
--- path plus "FromSkin" whenever a font path is named, where the Font block's companion lives
--- (OptionsCompose's rule, which Skin's ResetToSkin reads too).
local function pathOf(paths, key)
  if key == "fontFromSkin" and type(paths.font) == "string" and paths.font ~= "" then
    return paths.font .. "FromSkin"
  end
  local p = paths[key]
  if type(p) == "string" and p ~= "" then return p end
  return nil
end
lib.__pathOf = pathOf

--- A setting written through the host (minor 2): the arrow takes it, then `d.set(path, value)`
--- stores it at the host's path from `d.paths`, its architecture-§5 helper, so its settings rows
--- show it. Without `d.set` or a path the arrow alone holds it.
local function write(S, key, value)
  S.settings[key] = value
  local paths = S.d.paths
  local path = type(paths) == "table" and pathOf(paths, key) or nil
  if path and type(S.d.set) == "function" then call(S, S.d.set, path, value) end
end

-- ── the frame ────────────────────────────────────────────────────────────────────────────────

local function parentOf(S) return S.d.parent or UIParent end

local function effectiveScale(f)
  local ok, v = pcall(f.GetEffectiveScale, f)
  return ok and plainNumber(v) and v > 0 and v or 1
end

--- The arrow's own scale relative to its parent (the Arrow scale setting, which applyScale sets).
local function ownScale(S) return setting(S, "scale") end

--- An offset held to the settings' range, so a drag never stores a value `VALID` would refuse.
local function clampOffset(v) return math.max(lib.POSITION_MIN, math.min(lib.POSITION_MAX, v)) end

--- The frame's center as whole-unit offsets from its parent's center, in the PARENT's units (minor
--- 2, the x and y settings' units: the same spot on screen at every Arrow scale), or nil while
--- either center is unknown. GetCenter answers each frame in its own units, so both go to screen
--- units first: (fx * fs - px * ps) / ps.
local function centerOffsets(S)
  local f, parent = S.frame, parentOf(S)
  local ok, fx, fy = pcall(f.GetCenter, f)
  local okP, px, py = pcall(parent.GetCenter, parent)
  if not (ok and okP and plainNumber(fx) and plainNumber(fy) and plainNumber(px) and plainNumber(py)) then
    return nil
  end
  local k = effectiveScale(f) / effectiveScale(parent)
  return clampOffset(math.floor(fx * k - px + 0.5)), clampOffset(math.floor(fy * k - py + 0.5))
end

--- The point a drag left the frame at, its offsets in the parent's units: re-anchored CENTER to
--- the parent's CENTER when the centers are known (minor 2), else the frame's own first point, as
--- minor 1 read it, its offsets taken from the frame's units to the parent's.
local function droppedPoint(S)
  local x, y = centerOffsets(S)
  local k = ownScale(S)
  if x then
    S.frame:ClearAllPoints()
    S.frame:SetPoint("CENTER", parentOf(S), "CENTER", x / k, y / k)
    return { point = "CENTER", relPoint = "CENTER", x = x, y = y }
  end
  local point, _, relPoint, px, py = S.frame:GetPoint(1)
  if type(point) ~= "string" then return nil end
  return { point = point, relPoint = type(relPoint) == "string" and relPoint or point,
    x = plainNumber(px) and px * k or 0, y = plainNumber(py) and py * k or 0 }
end

--- A drag ended: the point is kept, a CENTER point is written to the x and y settings through the
--- host (so its sliders follow), and onMoved hears it either way.
local function savePoint(S)
  local p = droppedPoint(S)
  if not p then return end
  S.point = p
  if p.point == "CENTER" and p.relPoint == "CENTER" then
    write(S, "x", p.x)
    write(S, "y", p.y)
  end
  call(S, S.d.onMoved, { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y })
end

local ANCHOR = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

--- A saved point in either shape ({ point, relPoint, x, y } keyed, or Callout's { p, rp, x, y }), or nil.
local function pointOf(p)
  if type(p) ~= "table" then return nil end
  local point, relPoint, x, y = p.point or p[1], p.relPoint or p[2], p.x or p[3], p.y or p[4]
  if not ANCHOR[point] then return nil end
  if not ANCHOR[relPoint] then relPoint = point end
  return { point = point, relPoint = relPoint, x = plainNumber(x) and x or 0, y = plainNumber(y) and y or 0 }
end

--- The point the frame sits at: the x and y settings (CENTER from the parent's CENTER) once either
--- is configured (minor 2), else the saved point (`d.point`, SetPosition), else DEFAULT_POINT.
local function currentPoint(S)
  local sx, sy = S.settings.x, S.settings.y
  if (sx ~= nil and VALID.x(sx)) or (sy ~= nil and VALID.y(sy)) then
    return { point = "CENTER", relPoint = "CENTER", x = setting(S, "x"), y = setting(S, "y") }
  end
  return pointOf(S.point) or lib.DEFAULT_POINT
end

--- Anchor the frame at its point. The point's offsets are in the parent's units (minor 2) and
--- SetPoint reads them in the frame's own, which the Arrow scale scales, so they are divided by it:
--- changing the scale grows the arrow where it is, and a slider value is the same spot at any scale.
local function applyPoint(S)
  local p, k = currentPoint(S), ownScale(S)
  S.frame:ClearAllPoints()
  S.frame:SetPoint(p.point, parentOf(S), p.relPoint, p.x / k, p.y / k)
end

--- A drag starts unless the arrow's own lock is on (minor 2) or the host's `canDrag()` says no.
local function onDragStart(S)
  if setting(S, "lock") then return end
  if S.d.canDrag ~= nil and not call(S, S.d.canDrag) then return end
  S.frame:StartMoving()
  S.moving = true
end

local function onDragStop(S)
  if not S.moving then return end
  S.moving = nil
  S.frame:StopMovingOrSizing()
  savePoint(S)
end

local onUpdate   -- forward: armed by present, disarmed by takeDown

local function texture(parent, sublevel)
  local t = parent:CreateTexture(nil, "ARTWORK", nil, sublevel)
  t:Hide()
  return t
end

local function build(S)
  if S.frame then return S.frame end
  local f = CreateFrame("Frame", S.d.name, S.d.parent or UIParent)
  S.frame = f
  f:Hide()
  f:SetFrameStrata(type(S.d.strata) == "string" and S.d.strata or lib.STRATA)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() onDragStart(S) end)
  f:SetScript("OnDragStop", function() onDragStop(S) end)
  f:SetScript("OnMouseUp", function(_, button) lib.__mouseUp(S, f, button) end)
  f:SetScript("OnEnter", function() call(S, S.d.onEnter, f) end)
  f:SetScript("OnLeave", function() call(S, S.d.onLeave, f) end)
  -- The art box: the 48-unit box every look is drawn in, at the top of the frame.
  local box = CreateFrame("Frame", nil, f)
  S.box = box
  S.shadow, S.body, S.overlay = texture(box, 0), texture(box, 1), texture(box, 2)
  S.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  return f
end

-- Where the text sits (minor 2): its point, the art box's point, the gap's direction (x, y) and
-- the text's justification. HIDDEN has no row: the text hides.
local TEXT_ANCHOR = {
  BELOW = { "TOP", "BOTTOM", 0, -1, "CENTER" },
  ABOVE = { "BOTTOM", "TOP", 0, 1, "CENTER" },
  LEFT  = { "RIGHT", "LEFT", -1, 0, "RIGHT" },
  RIGHT = { "LEFT", "RIGHT", 1, 0, "LEFT" },
}

--- A measured string size, or nil while the client has not laid it out (0, or no number).
local function measured(v) return plainNumber(v) and v > 0 and v or nil end

--- The hit rect: the frame, grown on the text's side past the pad by what the text takes, so the
--- text drags and clicks with the arrow. Measured from the string when the client has laid it out,
--- else `TEXT_ROOM` under or over the box and nothing beside it.
local function hitRect(S)
  local a, k = S.textAnchor, unitPx()
  if not a then return S.frame:SetHitRectInsets(0, 0, 0, 0) end
  local gap, pad = lib.TEXT_GAP * k, lib.HIT_PAD * k
  if a[3] == 0 then
    local h = measured(S.text:GetStringHeight()) or (lib.TEXT_ROOM - lib.TEXT_GAP) * k
    local grow = -math.max(0, gap + h - pad)
    return S.frame:SetHitRectInsets(0, 0, a[4] > 0 and grow or 0, a[4] < 0 and grow or 0)
  end
  local grow = -math.max(0, gap + (measured(S.text:GetStringWidth()) or 0) - pad)
  S.frame:SetHitRectInsets(a[3] < 0 and grow or 0, a[3] > 0 and grow or 0, 0, 0)
end

--- The frame, the art box at its center with `HIT_PAD` round it, and the text beside the box on
--- the `textPosition` side, in art units. The frame's point is the art's center, so moving the
--- text never moves the arrow.
local function layout(S)
  local k, f, box, text = unitPx(), S.frame, S.box, S.text
  local side = lib.ART + 2 * lib.HIT_PAD * k
  f:SetSize(side, side)
  box:SetSize(lib.ART, lib.ART)
  box:ClearAllPoints()
  box:SetPoint("CENTER", f, "CENTER", 0, 0)
  local a = TEXT_ANCHOR[setting(S, "textPosition")]
  S.textAnchor, S.shownText = a, nil
  text:ClearAllPoints()
  if a then
    local gap = lib.TEXT_GAP * k
    text:SetPoint(a[1], box, a[2], a[3] * gap, a[4] * gap)
    text:SetJustifyH(a[5])
    text:Show()
  else
    text:Hide()
  end
  hitRect(S)
end

-- ── the text's font (minor 2) ────────────────────────────────────────────────────────────────

local function skinFacade(S)
  local Skin, owner = resolve("LibKa0s-Skin-1.0"), S.d.skin
  if not (Skin and type(owner) == "string" and type(Skin.For) == "function") then return nil end
  local ok, facade = pcall(Skin.For, Skin, owner)
  return ok and type(facade) == "table" and facade or nil
end

local function gameFace()
  return type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

--- A face by name: LibSharedMedia's, else LibKa0s-Media-1.0's bundled file of that name, else nil.
local function namedFont(S, name)
  local LSM = resolve("LibSharedMedia-3.0")
  local ok, path = false, nil
  if LSM and type(LSM.Fetch) == "function" then ok, path = pcall(LSM.Fetch, LSM, "font", name, true) end
  if ok and type(path) == "string" then return path end
  local Media = resolve("LibKa0s-Media-1.0")
  if not (Media and type(Media.Font) == "function" and type(S.d.addon) == "string") then return nil end
  ok, path = pcall(Media.Font, S.d.addon, name, S.d.vendorPath)
  return ok and type(path) == "string" and path or nil
end

--- The text's color as r, g, b, a: the player's class color while Use class color is on (and the
--- client answers one), else the swatch.
local function textColor(S)
  if setting(S, "useClassColorFont") and type(core.ClassColor) == "function" then
    local ok, r, g, b = pcall(core.ClassColor, "player")
    if ok and plainNumber(r) and plainNumber(g) and plainNumber(b) then return r, g, b, 1 end
  end
  local c = setting(S, "fontColor")
  local r, g, b = rgbOf(c)
  local a = c[4] or c.a
  return r, g, b, plainNumber(a) and a or 1
end

--- Face, size, flags and shadow on the text. With a skin owner, through its facade's `HudFont`
--- (the skin's HUD face while Use the skin's font is on, its size scaled by `HudFontSize`, "@skin"
--- flags through the skin's outline); without one, on the string, "@skin" reading "OUTLINE".
--- The font on the string itself, with no skin: "@skin" reads "OUTLINE", the client's shadow.
local function setOwnFont(fs, face, size, flags, shadow)
  if flags == lib.FLAGS_FROM_SKIN then flags = "OUTLINE" end
  if fs:SetFont(face or gameFace(), size, flags) == false then fs:SetFont(gameFace(), size, flags) end
  fs:SetShadowColor(0, 0, 0, shadow and 1 or 0)
  fs:SetShadowOffset(shadow and 1 or 0, shadow and -1 or 0)
end

local function applyFont(S)
  local fs, facade = S.text, skinFacade(S)
  local fromSkin = setting(S, "fontFromSkin")
  local face = not fromSkin and (namedFont(S, setting(S, "font")) or gameFace()) or nil
  local size, flags, shadow = setting(S, "fontSize"), setting(S, "fontFlags"), setting(S, "fontShadow")
  if facade and type(facade.HudFont) == "function" then
    if type(facade.HudFontSize) == "function" then size = facade.HudFontSize(size, fromSkin) end
    facade.HudFont(fs, { face = face, size = size, flags = flags, shadow = shadow, shadowFromSkin = false })
  else
    setOwnFont(fs, face, size, flags, shadow)
  end
  S.textRGBA = { textColor(S) }
  S.shownText = nil
end

--- Lay the current look onto the three textures: files, sizes, anchors, and the coords a turn or a
--- frame starts from.
local function applyStyle(S)
  local style = setting(S, "style")
  local look = LOOK[style]
  local base, k, half = mediaBase(S), unitPx(), lib.UNITS / 2
  S.body:SetTexture(base .. look.body)
  S.overlay:SetTexture(base .. look.overlay)
  for _, t in ipairs({ S.body, S.overlay }) do
    t:ClearAllPoints()
    t:SetRotation(0)
    t:SetTexCoord(0, 1, 0, 1)
    if look.sheet then
      local G = lib.GROUND
      local b = G.box
      t:SetSize((b[3] - b[1]) * k, (b[4] - b[2]) * k)
      t:SetPoint("CENTER", S.box, "CENTER", ((b[1] + b[3]) / 2 - half) * k, -((b[2] + b[4]) / 2 - half) * k)
    else
      t:SetSize(lib.ART, lib.ART)
      t:SetPoint("CENTER", S.box, "CENTER", 0, 0)
    end
  end
  S.shadow:ClearAllPoints()
  if look.shadow then
    S.shadow:SetTexture(base .. look.shadow)
    S.shadow:SetSize(lib.SHADOW_BOX * k, lib.SHADOW_BOX * k)
    S.shadow:SetPoint("CENTER", S.box, "CENTER", lib.SHADOW_OFFSET[1] * k, lib.SHADOW_OFFSET[2] * k)
  end
  S.style = style
end

local function applyScale(S)
  S.frame:SetScale(setting(S, "scale"))
end

-- ── drawing ──────────────────────────────────────────────────────────────────────────────────

local function hideArt(S)
  S.body:Hide()
  S.overlay:Hide()
  S.shadow:Hide()
end

--- Turn the art to `rotation`: SetRotation for the rotated looks, a sheet frame for the ground.
local function turn(S, rotation)
  local look = LOOK[S.style]
  if look.sheet then
    local k = lib.GroundFrame(rotation)
    local l, r, t, b = lib.GroundTexCoord(k)
    S.body:SetTexCoord(l, r, t, b)
    S.overlay:SetTexCoord(l, r, t, b)
    S.frameIndex = k
    return
  end
  S.body:SetRotation(rotation)
  S.overlay:SetRotation(rotation)
  if look.shadow then S.shadow:SetRotation(rotation) end
  S.frameIndex = nil
end

local function paintArt(S, rotation, yards)
  if rotation == nil then
    S.rotation = nil
    return hideArt(S)
  end
  S.body:Show()
  S.overlay:Show()
  S.shadow:SetShown(LOOK[S.style].shadow ~= nil)
  turn(S, rotation)
  local far, near = colors(S)
  local r, g, b = lib.Mix(far, near, lib.Fade(yards, S.near, S.far))
  S.body:SetVertexColor(r, g, b, 1)
  S.rotation, S.color = rotation, { r, g, b }
end

--- The distance: the host's `format(yards, units)` when it answers a string, else FormatDistance
--- in the configured units with the host's `strings`.
local function formatYards(S, yards)
  local units = setting(S, "distanceUnits")
  local text = call(S, S.d.format, yards, units)
  if type(text) == "string" then return text end
  return lib.FormatDistance(yards, units, S.d.strings)
end

--- The text and whether it is dim: the distance (and the label on a second line while Show the
--- label is on), or the label alone, dim, while no distance can be measured.
local function textLine(S, yards, label)
  local name = type(label) == "string" and label ~= "" and label or nil
  if not yards then return name or "", true end
  local dist = formatYards(S, yards)
  if name and setting(S, "showLabel") then return dist .. "\n" .. name, false end
  return dist, false
end

local function paintText(S, yards, label)
  if not S.textAnchor then return end
  local text, dim = textLine(S, yards, label)
  local c = S.textRGBA or { 1, 1, 1, 1 }
  S.text:SetTextColor(c[1], c[2], c[3], c[4])
  S.text:SetAlpha(dim and DIM or 1)
  if text == S.shownText then return end
  S.shownText = text
  S.text:SetText(text)
  hitRect(S)
end

-- ── the measure ──────────────────────────────────────────────────────────────────────────────

--- The target's world point (static, so measured once per target).
local function targetWorld(t)
  if t.world then return t.world end
  if plainNumber(t.instance) and plainNumber(t.wx) and plainNumber(t.wy) then
    t.world = { t.instance, t.wx, t.wy }
  else
    local instance, x, y = mapWorld(t.mapID, t.x, t.y)
    if instance ~= nil then t.world = { instance, x, y } end
  end
  return t.world
end

--- yards and rotation to a target, each nil when unknown.
local function measureTarget(t)
  local w = targetWorld(t)
  local instance, px, py = playerWorld()
  if not (w and instance ~= nil and instance == w[1]) then return nil, nil end
  local yards = lib.Distance(px, py, w[2], w[3])
  return yards, yards and lib.Rotation(px, py, w[2], w[3], facing()) or nil
end

local function measure(S)
  if S.sample then return lib.SAMPLE_YARDS, lib.SAMPLE_ROTATION, S.sample.label end
  local t = S.target
  if not t then return nil end
  if t.provider then
    local ok, yards, rotation = pcall(t.provider)
    if not ok then return nil, nil, t.label end
    return plainNumber(yards) and yards or nil, plainNumber(rotation) and rotation or nil, t.label
  end
  local yards, rotation = measureTarget(t)
  return yards, rotation, t.label
end

local takeDown   -- forward: the arrival clears the target
local closeMenu  -- forward: the menu section's; the arrow coming down closes its menu

local function arrived(S, yards)
  local arrive = S.d.arrive
  if arrive == false or S.sample or not yards then return false end
  return yards <= (plainNumber(arrive) and arrive or lib.ARRIVE)
end

--- One measure: the player's place and facing against the target, then the art and the text.
local function update(S)
  if not S.frame then return end
  local yards, rotation, label = measure(S)
  if not (S.sample or S.target) then return takeDown(S) end
  if arrived(S, yards) then
    local t = S.target
    S.target = nil
    takeDown(S)
    call(S, S.d.onArrive, t and t.spec)
    return
  end
  S.yards = yards
  paintArt(S, rotation, yards)
  paintText(S, yards, label)
end

onUpdate = function(S, elapsed)
  S.elapsed = S.elapsed + (elapsed or 0)
  if S.elapsed < lib.THROTTLE then return end
  S.elapsed = 0
  update(S)
end

local function present(S)
  if S.suspended then return end
  build(S)
  layout(S)
  applyFont(S)
  applyStyle(S)
  applyScale(S)
  applyPoint(S)
  S.frame:Show()
  S.elapsed = 0
  S.frame:SetScript("OnUpdate", function(_, elapsed) onUpdate(S, elapsed) end)
  update(S)
end

-- The frame down and its OnUpdate disarmed, explicitly: the one place it is disarmed. No OnHide
-- disarms it: the client fires OnHide on a shown child when its parent hides (Alt-Z, a cinematic)
-- and nothing re-arms it on the way back, while a hidden frame runs no OnUpdate anyway.
takeDown = function(S)
  if not S.frame then return end
  closeMenu(S)
  if S.moving then onDragStop(S) end
  S.frame:SetScript("OnUpdate", nil)
  S.frame:Hide()
end

-- ── the right-click menu (minor 2, L4) ───────────────────────────────────────────────────────
--
-- A right-click opens LibKa0s-Widgets-1.0's shared context menu (`W.ContextMenu`) at the pointer,
-- with the stock items in MENU_ITEMS order, then whatever the host's `d.menuItems(items, target,
-- arrow)` makes of them. `d.menu = false`, or a payload without the Widgets major, keeps minor 1's
-- right-click: `d.onClick(frame, "RightButton")`. The sample has no map point, so Share in chat and
-- Show on map are disabled under it; its Clear ends the sample only (`d.onSampleClear()`, else
-- HideSample), never the real target waiting under it. Clear acts only on the target the menu
-- opened over, and the arrow coming down closes its menu (`closeMenu`).

local function word(S, key)
  local own = type(S.d.strings) == "table" and rawget(S.d.strings, key)
  return type(own) == "string" and own or lib.STRINGS[key]
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and v == true
end

--- The zone's name of `mapID` (C_Map.GetMapInfo), or nil.
local function zoneName(mapID)
  local api = C_Map
  if type(api) ~= "table" or type(api.GetMapInfo) ~= "function" then return nil end
  local ok, info = pcall(api.GetMapInfo, mapID)
  local name = ok and type(info) == "table" and info.name or nil
  if isSecret(name) or type(name) ~= "string" or name == "" then return nil end
  return name
end

--- The `/way` line for a map target `spec` (`mapID`, `x`, `y` 0..1, optional `label`):
--- "/way <zone> 45.2, 63.1 <label>", the zone from C_Map.GetMapInfo, the coordinates in percent to
--- one decimal; the zone or the label left out when there is none. nil for a spec with no map point.
function lib.ShareText(spec)
  if type(spec) ~= "table" or not (plainNumber(spec.mapID) and plainNumber(spec.x) and plainNumber(spec.y)) then
    return nil
  end
  local parts = { "/way" }
  parts[#parts + 1] = zoneName(spec.mapID)
  parts[#parts + 1] = ("%.1f, %.1f"):format(spec.x * 100, spec.y * 100)
  if type(spec.label) == "string" and spec.label ~= "" then parts[#parts + 1] = spec.label end
  return table.concat(parts, " ")
end

-- What the chat box is opened with goes before the line. When the box sends, ChatEdit_ParseText
-- runs any text whose FIRST character is "/" as a slash command on the player's own client (a
-- waypoint addon's /way, or "unknown command") and sends nothing; a leading space is not "/", so
-- Enter sends the line to the box's channel as a message, and the others read "/way ...".
lib.SHARE_LEAD = " "

--- Open the chat box with `text` in it, never sending: ChatFrameUtil.OpenChat (12.0 and the clients
--- built on it), else the older ChatFrame_OpenChat global. True when one was called.
local function openChat(text)
  local util = type(ChatFrameUtil) == "table" and ChatFrameUtil.OpenChat or nil
  local fn = type(util) == "function" and util or ChatFrame_OpenChat
  if type(fn) ~= "function" then return false end
  return (pcall(fn, lib.SHARE_LEAD .. text))
end

--- Open the world map on `mapID`: C_Map.OpenWorldMap, else the OpenWorldMap global. Refused in
--- combat (the map is a UI panel, and opening it from addon code in combat is the taint the frame
--- otherwise avoids). True when one was called.
local function openMap(mapID)
  if inCombat() or not plainNumber(mapID) then return false end
  local api = type(C_Map) == "table" and C_Map.OpenWorldMap or nil
  local fn = type(api) == "function" and api or OpenWorldMap
  if type(fn) ~= "function" then return false end
  return (pcall(fn, mapID))
end
lib.__openChat, lib.__openMap = openChat, openMap

--- The target's spec, or nil (none, or the sample showing over it).
local function menuTarget(S)
  if S.sample then return nil end
  return S.target and S.target.spec or nil
end

--- Clear waypoint. It acts on the target the menu opened over, and on nothing else: a target that
--- arrived, or was replaced, while the menu was open is left alone. Under the sample it ends the
--- sample only (`d.onSampleClear()`, the host ending its test mode, else HideSample), and the real
--- target waiting under it stays.
local function clearItem(S, inst, target)
  local sample, captured = S.sample, S.target
  return { id = "clear", label = word(S, "MENU_CLEAR"), onClick = function()
    if sample then
      if S.sample ~= sample then return end
      if type(S.d.onSampleClear) == "function" then return call(S, S.d.onSampleClear) end
      return inst:HideSample()
    end
    if captured == nil or S.target ~= captured then return end
    if type(S.d.onClear) == "function" then return call(S, S.d.onClear, target) end
    inst:Clear()
  end }
end

local function mapItems(S, target)
  local line = lib.ShareText(target)
  local mapID = line and target.mapID or nil
  local noMap = word(S, "MENU_NO_MAP")
  return { id = "share", label = word(S, "MENU_SHARE"), disabled = line == nil,
      tooltip = line and word(S, "MENU_SHARE_TIP") or noMap,
      onClick = function() if line then openChat(line) end end },
    { id = "map", label = word(S, "MENU_MAP"), disabled = mapID == nil or inCombat(),
      tooltip = mapID == nil and noMap or (inCombat() and word(S, "MENU_COMBAT")) or nil,
      onClick = function() openMap(mapID) end }
end

--- The menu's rows: the stock items, then the host's `d.menuItems(items, target, inst)`, whose
--- answer (a list) replaces them; a host that edits the list in place may answer nothing.
local function menuItems(S, inst)
  local target = menuTarget(S)
  local share, map = mapItems(S, target)
  local locked = setting(S, "lock") == true
  local items = { clearItem(S, inst, target), share, map,
    { id = "lock", label = word(S, locked and "MENU_UNLOCK" or "MENU_LOCK"),
      onClick = function() inst:SetLocked(not locked) end },
    { id = "reset", label = word(S, "MENU_RESET"), onClick = function() inst:ResetPosition() end } }
  if type(S.d.menuItems) == "function" then
    local out = call(S, S.d.menuItems, items, target, inst)
    if type(out) == "table" then items = out end
  end
  return items
end

local function widgets()
  local W = resolve("LibKa0s-Widgets-1.0")
  return W and type(W.ContextMenu) == "function" and W or nil
end

--- A mouse-up on the frame: the right button opens the menu where there is one, and everything
--- else, the right button included without one, reaches `d.onClick`.
function lib.__mouseUp(S, f, button)
  local W = button == "RightButton" and S.d.menu ~= false and widgets() or nil
  if not W then return call(S, S.d.onClick, f, button) end
  local rows = menuItems(S, S.inst)
  if #rows == 0 then return end
  local ok, m = pcall(W.ContextMenu, f, rows, { owner = S.d.skin, cursor = true })
  if not ok then return debugOut(S, "menu failed: " .. tostring(m)) end
  S.menu = type(m) == "table" and m or nil
end

--- Close the shared menu if it is still this arrow's (its `_owner` is this frame and it is shown):
--- the menu is a UIParent-parented singleton that only an outside press closes, so the arrow coming
--- down (arrival, Clear, Suspend, the sample ending) closes it here. Another owner's menu is left.
closeMenu = function(S)
  local m = S.menu
  S.menu = nil
  if type(m) ~= "table" or m._owner ~= S.frame or type(m.IsShown) ~= "function" then return end
  local ok, shown = pcall(m.IsShown, m)
  local W = ok and shown and resolve("LibKa0s-Widgets-1.0") or nil
  if W and type(W.CloseMenu) == "function" then pcall(W.CloseMenu) end
end

-- ── the methods ──────────────────────────────────────────────────────────────────────────────

local METHODS = {}

--- Point at `spec`: `{ mapID, x, y }` (a map and a point on it, 0..1, as C_Map takes them) or
--- `{ instance, wx, wy }` (world yards, x north and y west), with an optional `label` (shown alone,
--- dim, while no distance can be measured). A shown arrow is retargeted. Answers false (and does
--- nothing) for a spec with neither, or while suspended.
function METHODS:SetTarget(spec)
  local S = state(self)
  if type(spec) ~= "table" then return false end
  local byMap = plainNumber(spec.mapID) and plainNumber(spec.x) and plainNumber(spec.y)
  local byWorld = plainNumber(spec.instance) and plainNumber(spec.wx) and plainNumber(spec.wy)
  if not (byMap or byWorld) then return false end
  S.target = { mapID = spec.mapID, x = spec.x, y = spec.y, instance = spec.instance, wx = spec.wx,
    wy = spec.wy, label = spec.label, spec = spec }
  if S.suspended then return false end
  if not S.sample then present(S) end
  return true
end

--- Point by `provider()`, which answers `yards, rotation` (rotation in radians, counter-clockwise
--- from straight ahead; either may be nil), read each measure under pcall. For a host that measures
--- its own way (a unit, a quest, a corpse). `label` as SetTarget's.
function METHODS:SetProvider(provider, label)
  local S = state(self)
  if type(provider) ~= "function" then return false end
  S.target = { provider = provider, label = label, spec = { provider = provider, label = label } }
  if S.suspended then return false end
  if not S.sample then present(S) end
  return true
end

--- Forget the target and hide (the sample, if shown, stays until HideSample).
function METHODS:Clear()
  local S = state(self)
  S.target = nil
  if S.sample then return end
  takeDown(S)
end

--- The spec handed to SetTarget or SetProvider, or nil.
function METHODS:Target()
  local t = state(self).target
  return t and t.spec or nil
end

--- Test mode (preview-mode): the arrow at the sample distance and angle, `label` under it while it
--- cannot measure. A real target set before or during it waits under the sample.
function METHODS:ShowSample(label)
  local S = state(self)
  if S.suspended then return false end
  local own = type(S.d.strings) == "table" and rawget(S.d.strings, "SAMPLE")
  closeMenu(S)   -- its items were the real target's
  S.sample = { label = type(label) == "string" and label or type(own) == "string" and own or lib.STRINGS.SAMPLE }
  present(S)
  return true
end

--- Test mode ended: the sample goes, and a real target is pointed at again.
function METHODS:HideSample()
  local S = state(self)
  if not S.sample then return end
  S.sample = nil
  closeMenu(S)   -- its items were the sample's
  if S.target then return present(S) end
  takeDown(S)
end

function METHODS:SampleShown() return state(self).sample ~= nil end

--- Merge settings in: any key of `SETTINGS`. A value that is not valid reads as the default (never
--- stored). A shown arrow takes them at once.
function METHODS:Configure(t)
  local S = state(self)
  if type(t) ~= "table" then return end
  for _, key in ipairs(lib.SETTINGS) do
    if t[key] ~= nil then S.settings[key] = t[key] end
  end
  self:Apply()
end

--- Configure from the host's own settings: `get(path)` for each key `paths` names
--- (`{ style = "waypoints.arrowStyle", ... }`); a key with no path is left as it is.
function METHODS:ConfigureFrom(get, paths)
  if type(get) ~= "function" or type(paths) ~= "table" then return end
  local t = {}
  for _, key in ipairs(lib.SETTINGS) do
    local path = pathOf(paths, key)
    if path then t[key] = get(path) end
  end
  self:Configure(t)
end

--- One setting as the arrow reads it: the configured value, else the default.
function METHODS:Get(key)
  local S = state(self)
  if not VALID[key] then return nil end
  return setting(S, key)
end

--- The far and near colors the arrow draws with now (after "Use the skin's colors"): two
--- { r, g, b } tables.
function METHODS:Colors()
  local far, near = colors(state(self))
  local fr, fg, fb = rgbOf(far)
  local nr, ng, nb = rgbOf(near)
  return { fr, fg, fb }, { nr, ng, nb }
end

--- Re-read every setting onto a built frame (after a skin change, or the host's own write).
function METHODS:Apply()
  local S = state(self)
  if not S.frame then return end
  layout(S)
  applyFont(S)
  applyStyle(S)
  applyScale(S)
  applyPoint(S)
  if S.frame:IsShown() then update(S) end
end

--- Move the frame to a saved point (`{ point, relPoint, x, y }`, keyed or positional, its offsets in
--- the parent's units from minor 2, as onMoved hands them); nil puts it back at `DEFAULT_POINT`. Not handed to onMoved: the host already holds it. From minor 2 it also
--- sets aside configured x and y settings until they are configured again.
function METHODS:SetPosition(point)
  local S = state(self)
  S.point = pointOf(point)
  S.settings.x, S.settings.y = nil, nil
  if S.frame then applyPoint(S) end
end

--- The point the frame sits at now: a fresh `{ point, relPoint, x, y }`.
function METHODS:GetPosition()
  local p = currentPoint(state(self))
  return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y }
end

--- Back to the default spot (`DEFAULTS.x`, `DEFAULTS.y`, which are DEFAULT_POINT's), written to
--- the host's x and y paths through `d.set` (minor 2), then onMoved(nil) so the host forgets its
--- saved point.
function METHODS:ResetPosition()
  local S = state(self)
  S.point = nil
  write(S, "x", lib.DEFAULTS.x)
  write(S, "y", lib.DEFAULTS.y)
  if S.frame then applyPoint(S) end
  call(S, S.d.onMoved, nil)
end

--- Minor 2: the arrow's own lock (`lock`): while on it cannot be dragged. Written through the host
--- like a drag's x and y.
function METHODS:SetLocked(on)
  write(state(self), "lock", on == true)
end

function METHODS:IsLocked() return setting(state(self), "lock") == true end

--- Minor 2: the right-click menu's rows as they would open now (the stock items and the host's).
function METHODS:MenuItems()
  local S = state(self)
  return menuItems(S, self)
end

--- Minor 2: open the right-click menu at the pointer, as a right-click does. False with no frame,
--- no Widgets major or `d.menu = false`.
function METHODS:OpenMenu()
  local S = state(self)
  if not S.frame or S.d.menu == false or not widgets() then return false end
  lib.__mouseUp(S, S.frame, "RightButton")
  return true
end

--- One measure now (a shown arrow measures on its own every THROTTLE seconds).
function METHODS:Update() update(state(self)) end

function METHODS:IsShown()
  local S = state(self)
  return S.frame ~= nil and S.frame:IsShown() == true
end

--- The stand-down: the arrow and the sample come down, the target is forgotten, and SetTarget,
--- SetProvider and ShowSample answer false until Resume.
function METHODS:Suspend()
  local S = state(self)
  S.suspended, S.sample, S.target = true, nil, nil
  takeDown(S)
end

function METHODS:Resume() state(self).suspended = false end

function METHODS:Suspended() return state(self).suspended == true end

--- The frame, built on first use.
function METHODS:Frame()
  local S = state(self)
  if S.frame then return S.frame end
  build(S)
  layout(S)
  return S.frame
end

--- The instance's state, for a host's diagnostics report and its suites.
function METHODS:Stats()
  local S = state(self)
  return {
    built = S.frame ~= nil, shown = S.frame ~= nil and S.frame:IsShown() == true,
    style = setting(S, "style"), scale = setting(S, "scale"),
    rotation = S.rotation, frameIndex = S.frameIndex, yards = S.yards,
    color = S.color and { S.color[1], S.color[2], S.color[3] } or nil,
    sample = S.sample ~= nil, target = S.target ~= nil, suspended = S.suspended == true,
    armed = S.frame ~= nil and S.frame:GetScript("OnUpdate") ~= nil,
  }
end

--- A new arrow. `d.addon` (or `d.mediaBase`) is required; every other field is optional (see the
--- API document).
function lib:New(d)   -- luacheck: ignore 212/self
  if type(d) ~= "table" or not ((type(d.addon) == "string" and d.addon ~= "")
    or (type(d.mediaBase) == "string" and d.mediaBase ~= "")) then
    error(MAJOR .. ": New(d): d.addon (or d.mediaBase), where the art sits, is required", 2)
  end
  local inst = {}
  for name, fn in pairs(METHODS) do inst[name] = fn end
  STATE[inst] = { d = d, inst = inst, settings = {}, suspended = false, elapsed = 0, point = pointOf(d.point),
    near = plainNumber(d.near) and d.near or lib.NEAR, far = plainNumber(d.far) and d.far or lib.FAR }
  return inst
end

--- Whether `style` is one of STYLES.
function lib.IsStyle(style) return inList(lib.STYLES, style) end

-- The method table every New copies, for this major's paired file and nobody else.
lib.__methods = METHODS
lib.__valid = VALID
