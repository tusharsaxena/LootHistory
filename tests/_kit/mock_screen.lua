-- testkit/mock_screen.lua — the kit's opt-in fake screen and tooltip recorder (revision 57), for a
-- suite that asserts where a tooltip opens (WowAddonStandards standalone-windows, *Tooltip
-- placement*, Verification: "driving the fake screen through a right-fits and a right-does-not-fit
-- layout and asserting the side, the top alignment and the gap from the tooltip's recorded points").
--
-- Returns an INSTALLER, called on a finished mock, which returns the SCREEN:
--
--   local M = base()
--   local scr = dofile("tests/_kit/mock_screen.lua")(M, { width = 1920, height = 1080, scale = 1 })
--   local win = scr.frame{ left = 1500, bottom = 300, width = 300, height = 400 }
--   local row = scr.frame{ left = 1500, bottom = 600, width = 300, height = 20, parent = win }
--   local tip = scr.tooltip{ width = 200, height = 80 }
--   ...                                    -- place `tip` against `row`
--   local l, b, r, t = scr.rectOf(tip)      -- where it landed, in screen units
--   scr.restore()                          -- UIParent's geometry is the base's again
--
-- WHY. The base answers every capitalized method it does not define with the frame itself
-- (mock_base.lua's metatable), so GetLeft, GetTop and GetEffectiveScale hand back a table and a
-- placer that guards its reads (as LibKa0s-Tooltip-1.0 does) places nothing: no suite could drive
-- one. OPT-IN and a file of its own, as mock_layers.lua is, because most suites never ask.
--
-- UNITS. Every figure a case gives is in the frame's OWN units, as the client's GetLeft answers;
-- `scale` is the frame's effective scale (default 1), so screen units are own units times scale.
-- The screen is UIParent: `width` x `height` at `scale` (defaults 1920, 1080, 1).
--
-- WHAT IS INSTALLED. On M.UIParent, by rawset: GetWidth, GetHeight, GetEffectiveScale, GetLeft (0),
-- GetBottom (0), GetRight, GetTop and GetCenter. restore() puts the previous raw fields back.
--
-- scr.frame(spec) -> a tracked frame (M.CreateFrame) answering, by rawset:
--   GetLeft / GetBottom / GetRight / GetTop / GetWidth / GetHeight / GetCenter  from spec.left,
--     spec.bottom, spec.width, spec.height (own units; a missing figure answers nil, an unplaced
--     frame); GetEffectiveScale (spec.scale or 1); GetParent (spec.parent or M.UIParent);
--     IsShown / Show / Hide (spec.shown, default true).
--   frame:__place(left, bottom, width, height) moves it.
--
-- scr.tooltip(spec) -> a tracked frame that RECORDS, in one ordered log (`tip.__log`):
--   SetOwner(owner, anchor)        { op = "SetOwner", owner, anchor };  GetOwner() answers owner
--   ClearAllPoints()               { op = "ClearAllPoints" };           the points are emptied
--   SetPoint(p, rel, relP, x, y)   { op = "SetPoint", point, rel, relPoint, x, y }; also in
--                                  `tip.__points`, and the last one in `tip.__point`
--   SetAnchorType(a, x, y)         { op = "SetAnchorType", anchor, x, y }; GetAnchorType() answers a
--   Show / Hide / IsShown          shown state (spec.shown, default true)
--   and answers GetWidth / GetHeight (spec.width, spec.height) and GetEffectiveScale (spec.scale).
--   tip:__size(width, height) changes its size (late growth).
--
-- scr.rectOf(tip) -> left, bottom, right, top of the tooltip in SCREEN units, from its last point,
--   when that point is on M.UIParent's BOTTOMLEFT or on a frame this screen built; nil otherwise.
-- scr.ops(tip) -> the op names of its log, in order, as one string ("SetOwner ClearAllPoints ...").

local POINT_X = { LEFT = 0, RIGHT = 1, [""] = 0.5 }
local POINT_Y = { BOTTOM = 0, TOP = 1, [""] = 0.5 }

--- A point name as its x and y fraction of a box: "TOPLEFT" -> 0, 1; "BOTTOM" -> 0.5, 0.
local function fractions(point)
  local v = point:match("^(TOP)") or point:match("^(BOTTOM)") or ""
  local h = point:sub(#v + 1)
  if h == "CENTER" then h = "" end
  local fx, fy = POINT_X[h], POINT_Y[v]
  if not (fx and fy) then error("mock_screen: unknown point " .. tostring(point), 3) end
  return fx, fy
end

local UI_METHODS = { "GetWidth", "GetHeight", "GetEffectiveScale", "GetLeft", "GetBottom",
                     "GetRight", "GetTop", "GetCenter" }

return function(M, opts)
  opts = opts or {}
  local scr = {}
  local W, H, S = opts.width or 1920, opts.height or 1080, opts.scale or 1
  local built = setmetatable({}, { __mode = "k" })   -- the frames this screen built

  local ui = M.UIParent
  local saved = {}
  for _, k in ipairs(UI_METHODS) do saved[k] = rawget(ui, k) end
  local function installUI()
    rawset(ui, "GetWidth", function() return W end)
    rawset(ui, "GetHeight", function() return H end)
    rawset(ui, "GetEffectiveScale", function() return S end)
    rawset(ui, "GetLeft", function() return 0 end)
    rawset(ui, "GetBottom", function() return 0 end)
    rawset(ui, "GetRight", function() return W end)
    rawset(ui, "GetTop", function() return H end)
    rawset(ui, "GetCenter", function() return W / 2, H / 2 end)
  end
  installUI()

  --- Resize the screen: `width`, `height` and `scale` as at install (each optional).
  function scr.resize(w, h, s)
    W, H, S = w or W, h or H, s or S
  end

  function scr.restore()
    for _, k in ipairs(UI_METHODS) do rawset(ui, k, saved[k]) end
  end

  local function geometry(f, spec)
    f.__geo = { l = spec.left, b = spec.bottom, w = spec.width, h = spec.height }
    local g = function() return f.__geo end
    rawset(f, "GetLeft", function() return g().l end)
    rawset(f, "GetBottom", function() return g().b end)
    rawset(f, "GetWidth", function() return g().w end)
    rawset(f, "GetHeight", function() return g().h end)
    rawset(f, "GetRight", function()
      local q = g(); return q.l and q.w and q.l + q.w or nil
    end)
    rawset(f, "GetTop", function()
      local q = g(); return q.b and q.h and q.b + q.h or nil
    end)
    rawset(f, "GetCenter", function()
      local q = g()
      if not (q.l and q.b and q.w and q.h) then return nil end
      return q.l + q.w / 2, q.b + q.h / 2
    end)
    local scale = spec.scale or 1
    rawset(f, "GetEffectiveScale", function() return scale end)
    rawset(f, "__place", function(self, l, b, w, h)
      self.__geo = { l = l, b = b, w = w, h = h }; return self
    end)
    f.__shown = spec.shown ~= false
  end

  function scr.frame(spec)
    spec = spec or {}
    local parent = spec.parent or ui
    local f = M.CreateFrame("Frame", nil, parent)
    geometry(f, spec)
    rawset(f, "GetParent", function() return parent end)
    built[f] = true
    return f
  end

  local function log(tip, entry) tip.__log[#tip.__log + 1] = entry end

  function scr.tooltip(spec)
    spec = spec or {}
    local tip = M.CreateFrame("GameTooltip", nil, ui)
    geometry(tip, { width = spec.width or 200, height = spec.height or 80, scale = spec.scale })
    tip.__log, tip.__points = {}, {}
    rawset(tip, "GetParent", function() return ui end)
    rawset(tip, "SetOwner", function(self, owner, anchor)
      self.__owner, self.__anchor = owner, anchor
      log(self, { op = "SetOwner", owner = owner, anchor = anchor })
    end)
    rawset(tip, "GetOwner", function(self) return self.__owner end)
    rawset(tip, "ClearAllPoints", function(self)
      self.__points, self.__point = {}, nil
      log(self, { op = "ClearAllPoints" })
    end)
    rawset(tip, "SetPoint", function(self, point, rel, relPoint, x, y)
      local p = { op = "SetPoint", point = point, rel = rel, relPoint = relPoint or point,
                  x = x or 0, y = y or 0 }
      self.__points[#self.__points + 1] = p
      self.__point = p
      log(self, p)
    end)
    rawset(tip, "SetAnchorType", function(self, anchor, x, y)
      self.__anchorType = anchor
      log(self, { op = "SetAnchorType", anchor = anchor, x = x, y = y })
    end)
    rawset(tip, "GetAnchorType", function(self) return self.__anchorType end)
    rawset(tip, "__size", function(self, w, h) self.__geo.w, self.__geo.h = w, h; return self end)
    tip.__shown = spec.shown ~= false
    return tip
  end

  --- A frame's rect in screen units, or nil.
  local function screenRect(f)
    if f == ui then return 0, 0, W * S, H * S end
    if not built[f] then return nil end
    local l, b = f:GetLeft(), f:GetBottom()
    local w, h = f:GetWidth(), f:GetHeight()
    if not (l and b and w and h) then return nil end
    local s = f:GetEffectiveScale()
    return l * s, b * s, (l + w) * s, (b + h) * s
  end

  function scr.rectOf(tip)
    local p = tip.__point
    if not p then return nil end
    local rl, rb, rr, rt = screenRect(p.rel)
    if not rl then return nil end
    local rfx, rfy = fractions(p.relPoint)
    local fx, fy = fractions(p.point)
    local s = tip:GetEffectiveScale()
    local tw, th = tip:GetWidth() * s, tip:GetHeight() * s
    local ax = rl + (rr - rl) * rfx + p.x * s
    local ay = rb + (rt - rb) * rfy + p.y * s
    local left, bottom = ax - tw * fx, ay - th * fy
    return left, bottom, left + tw, bottom + th
  end

  function scr.ops(tip)
    local names = {}
    for _, e in ipairs(tip.__log or {}) do names[#names + 1] = e.op end
    return table.concat(names, " ")
  end

  return scr
end
