-- LibKa0s-Feed-1.0 -- FeedModel.lua, the pure half of the toast feed.
--
-- No frames, no client calls and no globals beyond `math`: everything here is arithmetic over
-- plain tables, so the headless suites step it without a frame in sight. The shell (Feed.lua)
-- reads it through `lib.__model` at call time:
--
--   Snapshot(d)            the descriptor's layout, motion and style, read once (each a value or a
--                          getter) and normalized: a key that answers nothing usable takes the
--                          published default, and an unknown key is ignored
--   Origin(slot, grow)     the container point that sits at the slot: the grow-origin edge
--   SlotOffset(slot, x, y) slot, ox, oy: the nudge plus the slot's inset from the screen edge
--   NudgeFromRect(...)     the nudge that puts a dragged container's rect back where it is
--   RowHeight(spec, layout, titleSize, lineSize)   a row's height for the lines its spec fills
--   Layout(entries, layout)   every entry's targetY, newest first; answers the stack's height
--   Advance(e, m, dt, paused, width)   one tick of an entry's phase machine
--   Merge(e, payload, key, m, now, fn)   a push folded into a live or waiting entry
--   Drain(waiting, n, present, freed)   which waiting entries present when the wait ends
--
-- Minor 1 (LootHistory#38, task S1 of the Feed build): the whole model.

local lib = LibStub and LibStub("LibKa0s-Feed-1.0", true)
if not lib then return end

local MODEL_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own: a model attached to an older shell would
-- answer shapes that shell does not read, and nothing would say the two came from different copies.
if lib.__modelMinor and lib.__modelMinor >= MODEL_MINOR and lib.__modelShellMinor == lib.MINOR then return end
lib.__modelMinor, lib.__modelShellMinor = MODEL_MINOR, lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.FeedModel = MODEL_MINOR

local floor, min, max = math.floor, math.min, math.max
local HUGE = math.huge

local M = {}

-- == readers ==================================================================================

local function finite(v)
  return type(v) == "number" and v == v and v ~= HUGE and v ~= -HUGE
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

--- A descriptor field that may be a value or a getter. A getter that raises answers nothing.
local function read(v)
  if type(v) ~= "function" then return v end
  local ok, out = pcall(v)
  if ok then return out end
  return nil
end

local function positive(v, default)
  if finite(v) and v > 0 then return v end
  return default
end

local function nonNegative(v, default)
  if finite(v) and v >= 0 then return v end
  return default
end

local function bool(v, default)
  if v == true or v == false then return v end
  return default
end

local function oneOf(v, set, default)
  if type(v) == "string" and set[v] then return v end
  return default
end

local function nonEmpty(v)
  if type(v) == "string" and v ~= "" then return v end
  return nil
end

--- `{ r, g, b, a }` from a color table (array or r/g/b/a keys), a new table; nil for anything else.
local function color(v)
  if type(v) ~= "table" then return nil end
  local r, g, b, a = rawget(v, 1), rawget(v, 2), rawget(v, 3), rawget(v, 4)
  if r == nil then r, g, b, a = rawget(v, "r"), rawget(v, "g"), rawget(v, "b"), rawget(v, "a") end
  if not (finite(r) and finite(g) and finite(b)) then return nil end
  if not finite(a) then a = 1 end
  return { clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1), clamp(a, 0, 1) }
end

local function colorOr(v, default)
  return color(v) or { default[1], default[2], default[3], default[4] }
end

local function setOf(list)
  local s = {}
  for _, v in ipairs(list) do s[v] = true end
  return s
end

local SLOT_SET = setOf(lib.SLOTS)
local GROW = setOf({ "UP", "DOWN" })
local SIDE = setOf({ "left", "right" })
local ENTER = setOf({ "none", "fade", "left", "right", "up", "down" })
local BG_TYPE = setOf({ "none", "solid", "gradient", "texture" })

-- The look a style override falls back on, and the degraded look's own colors.
M.BG_COLOR = { 0, 0, 0, 0.7 }
M.BG_COLOR2 = { 0.15, 0.15, 0.15, 0.7 }
M.BORDER_COLOR = { 0.3, 0.3, 0.3, 1 }
M.FONT_COLOR = { 1, 1, 1, 1 }
M.BAR_COLOR = { 1, 1, 1, 1 }
M.GLOW_COLOR = { 1, 0.82, 0, 1 }
M.FONT_SIZE, M.FONT_SIZE2 = 12, 10

-- == the snapshot =============================================================================

--- A grouped table of `d` (a table, or a getter answering one), or an empty table.
local function group(v)
  local t = read(v)
  if type(t) == "table" then return t end
  return {}
end

local function snapLayout(raw)
  local L = {}
  L.slot = oneOf(rawget(raw, "slot"), SLOT_SET, "BOTTOMRIGHT")
  local x, y = rawget(raw, "x"), rawget(raw, "y")
  L.x = finite(x) and clamp(x, -lib.NUDGE_MAX, lib.NUDGE_MAX) or 0
  L.y = finite(y) and clamp(y, -lib.NUDGE_MAX, lib.NUDGE_MAX) or 0
  L.grow = oneOf(rawget(raw, "grow"), GROW, "UP")
  local shown = rawget(raw, "shown")
  L.shown = finite(shown) and clamp(floor(shown), 1, lib.SHOWN_MAX) or lib.SHOWN
  L.width = positive(rawget(raw, "width"), lib.WIDTH)
  L.rowHeight = positive(rawget(raw, "rowHeight"), lib.ROW_HEIGHT)
  L.padding = nonNegative(rawget(raw, "padding"), lib.PADDING)
  L.gap = nonNegative(rawget(raw, "gap"), lib.GAP)
  local inner = max(1, L.rowHeight - 2 * L.padding)
  L.iconSize = min(positive(rawget(raw, "iconSize"), lib.ICON_SIZE), inner)
  L.align = oneOf(rawget(raw, "align"), SIDE, "left")
  L.iconSide = oneOf(rawget(raw, "iconSide"), SIDE, "left")
  L.scale = positive(rawget(raw, "scale"), 1)
  return L
end

local function snapMotion(raw)
  local m = {}
  m.enter = oneOf(rawget(raw, "enter"), ENTER, "fade")
  m.enterTime = m.enter == "none" and 0 or nonNegative(rawget(raw, "enterTime"), lib.ENTER_TIME)
  m.hold = nonNegative(rawget(raw, "hold"), lib.HOLD)
  m.fadeTime = nonNegative(rawget(raw, "fadeTime"), lib.FADE_TIME)
  m.mergeWindow = nonNegative(rawget(raw, "mergeWindow"), lib.MERGE_WINDOW)
  m.pulse = bool(rawget(raw, "pulse"), true)
  m.timerBar = bool(rawget(raw, "timerBar"), false)
  m.smooth = bool(rawget(raw, "smooth"), true)
  m.pin = bool(rawget(raw, "pin"), true)
  m.rightDismiss = bool(rawget(raw, "rightDismiss"), true)
  m.settle = nonNegative(rawget(raw, "settle"), 0)
  return m
end

--- Every `<part>FromSkin` flag defaults to true, so a host that passes no style draws the skin.
--- The names are the ones the standard's composers emit (skinning-§6): ColorPair's `bgColorFromSkin`
--- and O.BarGroup's `barTextureFromSkin` and `barColorFromSkin`.
local FROM_SKIN = {
  "bgColorFromSkin", "borderStyleFromSkin", "borderColorFromSkin", "fontFromSkin", "fontSizeFromSkin",
  "fontShadowFromSkin", "fontColorFromSkin", "barTextureFromSkin", "barColorFromSkin",
  "glowColorFromSkin",
}

local function snapStyle(raw)
  local s = {}
  for _, k in ipairs(FROM_SKIN) do s[k] = bool(rawget(raw, k), true) end
  s.bgType = oneOf(rawget(raw, "bgType"), BG_TYPE, "solid")
  s.bgColor = colorOr(rawget(raw, "bgColor"), M.BG_COLOR)
  s.bgColor2 = colorOr(rawget(raw, "bgColor2"), M.BG_COLOR2)
  s.bgTexture = nonEmpty(rawget(raw, "bgTexture"))
  s.borderStyle = nonEmpty(rawget(raw, "borderStyle"))
  s.borderSize = positive(rawget(raw, "borderSize"), 1)
  s.borderColor = colorOr(rawget(raw, "borderColor"), M.BORDER_COLOR)
  s.borderTint = bool(rawget(raw, "borderTint"), false)
  s.borderClass = bool(rawget(raw, "borderClass"), false)
  s.font = nonEmpty(rawget(raw, "font"))
  s.fontSize = positive(rawget(raw, "fontSize"), M.FONT_SIZE)
  s.fontSize2 = positive(rawget(raw, "fontSize2"), M.FONT_SIZE2)
  s.fontFlags = type(rawget(raw, "fontFlags")) == "string" and rawget(raw, "fontFlags") or "@skin"
  s.fontShadow = bool(rawget(raw, "fontShadow"), true)
  s.fontColor = colorOr(rawget(raw, "fontColor"), M.FONT_COLOR)
  s.fontClass = bool(rawget(raw, "fontClass"), false)
  s.barTexture = nonEmpty(rawget(raw, "barTexture"))
  s.barColor = colorOr(rawget(raw, "barColor"), M.BAR_COLOR)
  s.glowColor = colorOr(rawget(raw, "glowColor"), M.GLOW_COLOR)
  return s
end

--- `{ layout, motion, style, maxQueue }`, read once from `d` and normalized.
function M.Snapshot(d)
  d = type(d) == "table" and d or {}
  local q = read(rawget(d, "maxQueue"))
  return {
    layout = snapLayout(group(rawget(d, "layout"))),
    motion = snapMotion(group(rawget(d, "motion"))),
    style = snapStyle(group(rawget(d, "style"))),
    maxQueue = finite(q) and q >= 1 and floor(q) or lib.MAX_QUEUE,
  }
end

-- == placement ================================================================================

--- "LEFT", "" or "RIGHT": the slot's column.
local function hpart(slot)
  if slot:find("LEFT", 1, true) then return "LEFT" end
  if slot:find("RIGHT", 1, true) then return "RIGHT" end
  return ""
end

--- "TOP", "MID" or "BOTTOM": the slot's row.
local function vrow(slot)
  if slot:find("TOP", 1, true) then return "TOP" end
  if slot:find("BOTTOM", 1, true) then return "BOTTOM" end
  return "MID"
end

local function insets(slot)
  local I, h, v = lib.SLOT_INSET, hpart(slot), vrow(slot)
  local ix = (h == "LEFT" and I) or (h == "RIGHT" and -I) or 0
  local iy = (v == "BOTTOM" and I) or (v == "TOP" and -I) or 0
  return ix, iy
end

--- The container point anchored at the slot: its grow-origin edge, so a height change never moves
--- the newest row.
function M.Origin(slot, grow)
  return (grow == "DOWN" and "TOP" or "BOTTOM") .. hpart(slot)
end

--- The slot and the offsets, in UIParent units, that put the container's origin at the nudge.
function M.SlotOffset(slot, x, y)
  local ix, iy = insets(slot)
  return slot, (x or 0) + ix, (y or 0) + iy
end

--- The nudge, clamped, for a container whose rect (in UIParent units) is left, bottom, right, top on
--- a screen W wide and H high.
function M.NudgeFromRect(slot, grow, left, bottom, right, top, W, H)
  local h, v = hpart(slot), vrow(slot)
  local originX = (h == "LEFT" and left) or (h == "RIGHT" and right) or (left + right) / 2
  local slotX = (h == "LEFT" and 0) or (h == "RIGHT" and W) or W / 2
  local originY = grow == "DOWN" and top or bottom
  local slotY = (v == "BOTTOM" and 0) or (v == "TOP" and H) or H / 2
  local ix, iy = insets(slot)
  local N = lib.NUDGE_MAX
  return clamp(originX - slotX - ix, -N, N), clamp(originY - slotY - iy, -N, N)
end

-- == heights and layout =======================================================================

local function filled(s) return type(s) == "string" and s ~= "" end

--- How many secondary lines `spec` fills: each of lines[1..3] with a left or right part, and sub.
local function secondaryLines(spec)
  local n = 0
  local lines = type(spec) == "table" and spec.lines
  if type(lines) == "table" then
    for i = 1, 3 do
      local line = lines[i]
      if type(line) == "table" and (filled(line.left) or filled(line.right)) then n = n + 1 end
    end
  end
  if type(spec) == "table" and filled(spec.sub) then n = n + 1 end
  return n
end

--- A row's height: never under layout.rowHeight; else the padding, the title line and each filled
--- secondary line (font size + 2 each).
function M.RowHeight(spec, layout, titleSize, lineSize)
  local pad = layout.padding or lib.PADDING
  local titleH = (titleSize or M.FONT_SIZE) + 2
  local lineH = (lineSize or M.FONT_SIZE2) + 2
  return max(layout.rowHeight or lib.ROW_HEIGHT, pad * 2 + titleH + secondaryLines(spec) * lineH)
end

--- Each entry's targetY, `entries[1]` the newest at 0, each next one above (or below) the last by
--- its height and the gap. Answers the stack's height, 1 when empty.
function M.Layout(entries, layout)
  local gap, y, last = layout.gap or lib.GAP, 0, nil
  for i = 1, #entries do
    local e = entries[i]
    if last then y = y + last.h + gap end
    e.targetY = y
    last = e
  end
  if not last then return 1 end
  return y + last.h
end

-- == motion ===================================================================================

--- The enter's offset at eased progress `k`: from the side it slides in from, to 0.
local function slide(enter, k, width, h)
  local rest = 1 - k
  if enter == "left" then return -rest * width, 0 end
  if enter == "right" then return rest * width, 0 end
  if enter == "up" then return 0, rest * h end
  if enter == "down" then return 0, -rest * h end
  return 0, 0
end

local function advanceDrop(e, dt)
  local D = lib.DROP_FADE
  e.t = e.t + dt
  if e.t >= D then
    e.alpha = 0
    return 0, 0, 0, 0, true
  end
  e.alpha = (e.a0 or 1) * (1 - e.t / D)
  return e.alpha, 0, 0, 0, false
end

--- The alpha, offsets and bar for an entry `t` seconds into its life.
local function phaseAt(e, m, width)
  local E, H, Fd, t = m.enterTime, m.hold, m.fadeTime, e.t
  if t < E then
    e.phase = "enter"
    local p = 1 - t / E
    local k = 1 - p * p
    if m.enter == "fade" then return k, 0, 0, 1 end
    local dx, dy = slide(m.enter, k, width, e.h or lib.ROW_HEIGHT)
    return 1, dx, dy, 1
  end
  if e.sticky then
    e.phase = "hold"
    return 1, 0, 0, nil
  end
  if t < E + H then
    e.phase = "hold"
    return 1, 0, 0, 1 - (t - E) / H
  end
  if t < E + H + Fd then
    e.phase = "fade"
    return 1 - (t - E - H) / Fd, 0, 0, 0
  end
  return nil
end

--- One tick of `dt` seconds for entry `e` under motion `m`. `t` moves only while not `paused`; the
--- pulse runs regardless, and a drop runs to its end whatever else holds. A sticky entry stops at
--- the end of its enter and draws no bar (nil). Answers alpha, dx, dy, bar, done.
function M.Advance(e, m, dt, paused, width)
  dt = finite(dt) and dt > 0 and dt or 0
  if (e.pulse or 0) > 0 then e.pulse = max(0, e.pulse - dt) end
  if e.phase == "drop" then return advanceDrop(e, dt) end
  e.t = e.t or 0
  if not paused then e.t = e.t + dt end
  if e.sticky and e.t > m.enterTime then e.t = m.enterTime end
  local alpha, dx, dy, bar = phaseAt(e, m, width or lib.WIDTH)
  if alpha == nil then
    e.phase, e.alpha = "done", 0
    return 0, 0, 0, 0, true
  end
  e.alpha = alpha
  return alpha, dx, dy, bar, false
end

--- Fold a push of `payload` under `key` into entry `e` at time `now`. Answers false when `e` cannot
--- take it (dropping, or past the merge window); else true and the merge reducer's error, if any
--- (on an error, or a reducer answering nil, the newer payload is kept). A live entry restarts its hold without replaying its
--- enter, snaps back to full alpha and pulses when motion.pulse is on; a waiting entry only takes
--- the payload and the time.
function M.Merge(e, payload, key, m, now, fn)
  if e.phase == "drop" or e.phase == "done" then return false end
  if not (m.mergeWindow > 0 and e.lastAt and now - e.lastAt <= m.mergeWindow) then return false end
  local merged, err = payload, nil
  if type(fn) == "function" then
    local ok, out = pcall(fn, e.payload, payload, key)
    if not ok then err = out elseif out ~= nil then merged = out end   -- nil: the newer payload
  end
  e.payload, e.lastAt = merged, now
  if e.phase == "wait" then return true, err end
  local E = m.enterTime
  e.t = min(e.t or 0, E)
  if e.t >= E then e.phase, e.alpha = "hold", 1 end
  if m.pulse then e.pulse = lib.PULSE_TIME end
  return true, err
end

--- The end of a wait: the newest `n` of `waiting` (oldest first) go to `present`, so the newest ends
--- at the anchor; the rest go to `freed`. `waiting` is emptied. Answers how many present.
function M.Drain(waiting, n, present, freed)
  local count = #waiting
  local keep = clamp(floor(n or 0), 0, count)
  local first = count - keep + 1
  for i = 1, count do
    local e = waiting[i]
    waiting[i] = nil
    if i >= first then present[#present + 1] = e else freed[#freed + 1] = e end
  end
  return keep
end

lib.__model = M
