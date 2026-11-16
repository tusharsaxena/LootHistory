-- LibKa0s-Tooltip-1.0 -- where a tooltip opens: beside the window group, attached to a chrome
-- element, or toward the screen's center from a minimap button.
--
-- -- WHY THIS EXISTS ---------------------------------------------------------------------------
--
-- WowAddonStandards v2.112.0 (standalone-windows, *Tooltip placement*; launcher-§7; anti-pattern
-- #119) rules where every tooltip of a Ka0s window, HUD display, library-drawn window, library menu
-- and minimap button opens, and names a library surface, "LibKa0s tooltip placement", that every
-- placement goes through from the re-vendor of the tag that ships it. This is that surface
-- (LibKa0s#92, LK-92A of Ka0sAddonsCommonTasks docs/2026-11-16-LIBKA0S_ISSUES_75_PLUS, design
-- section 3.6). Its own major and not a Widgets or Core file: the consumers span Widgets, Charts, Sim,
-- IconBrowser, the Launcher and every addon, and a leaf with no dependency adds no edge between
-- them (Charts and the Launcher do not need Widgets today).
--
-- -- THE THREE PLACERS ---------------------------------------------------------------------------
--
--   PlaceBeside(tip, el, group, opts)   the BODY rule. Beside the window group, outside its outer
--       edge: TOPLEFT at the group's right edge + TIP_GAP when the tooltip fits on the right, else
--       TOPRIGHT at its left edge - TIP_GAP; the top level with the element's top, clamped on
--       screen. A companion panel's own tooltips prefer its side away from the main window. When
--       neither side fits, the chrome rule below the element (flipping above at the bottom).
--   PlaceAttached(tip, el, zone, opts)  the CHROME rule. Centered on the element: TOP on its
--       BOTTOM - TIP_GAP for the top chrome ("top", the default; a modal's controls too), BOTTOM on
--       its TOP + TIP_GAP for the bottom chrome ("bottom"); flipped only when the screen has no
--       room; clamped sideways.
--   PlaceLauncher(tip, button, opts)    the LAUNCHER rule. Toward the screen's center by the button
--       center's screen half (upper: below the button) and third (right: right edges level; left:
--       left edges; middle: centered), TIP_GAP off the button.
--
-- -- HOW A PLACEMENT IS APPLIED -------------------------------------------------------------------
--
-- On a tooltip that is ALREADY FILLED AND SHOWN, so its real width and height are known: own it
-- with `Own` (ANCHOR_NONE), add the lines, Show, then place. The body and chrome placers write ONE
-- absolute point against UIParent's BOTTOMLEFT, computed here. That is safe in a restricted layout
-- tree (a frame under DisableUntrustedLayoutScriptsTemplate refuses an anchor to it, so a HUD strip
-- there cannot be a relative target) and makes the clamp exact. The cost is that the tooltip does
-- not follow a window dragged while it shows, and the pointer leaves on a drag anyway. The launcher
-- placer is the one RELATIVE anchor: a minimap button is not restricted, and a relative point needs
-- no size.
--
-- Every edge is read in SCREEN units: a frame's GetLeft/GetBottom/GetRight/GetTop times its own
-- effective scale, and the screen is UIParent's size times UIParent's. A point is written back in
-- the tooltip's own units (divided by its effective scale), so a window at 0.8 and a tooltip at 1.0
-- measure true. The gap is TIP_GAP screen units under every skin and scale.
--
-- Comparison tooltips: before its point, the beside placer tells the tooltip the side it chose
-- through `SetAnchorType` (ANCHOR_RIGHT / ANCHOR_LEFT, 0, 0), which the client's comparison manager
-- reads to open ShoppingTooltip1/2 further out on the same side (rule 5). It is called BEFORE the
-- point, in the order the client's own bag uses (ContainerFrame's tooltip anchors), so the point it
-- writes is the last word. Those two literals are a comparison side, not a placement anchor.
--
-- -- THE RULES EVERY MEMBER OBEYS -----------------------------------------------------------------
--
--   1. A geometry read that is not a plain number (unplaced, or a secret value: `issecretvalue`,
--      read bare at call time) answers nil, and a placer whose geometry is unreadable places NOTHING
--      and answers nil, so the caller keeps its own anchor. No arithmetic ever touches a secret.
--      `opts.rect(frame) -> left, bottom, right, top` (screen units) lets a host supply guarded
--      reads for a frame the library cannot read (Aura Master's secret strip rect).
--   2. The solvers (`__solveBeside`, `__solveAttached`, `__solveLauncher`) are pure: numbers in,
--      the side and the point out, no frame touched. The placers read, solve and apply.
--   3. Globals (UIParent, issecretvalue) are read bare at call time, so a suite's fake screen moves
--      them after load.
--
-- Depends on LibStub only. No frames of its own, no events, no addon framework, no SavedVariables.

local MAJOR, MINOR = "LibKa0s-Tooltip-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.Tooltip = MINOR

-- The gap, in screen units, between a tooltip and what it is placed against (standalone-windows'
-- *Terms*: 2 px, skin-invariant). The placers read this file-local, so a write to lib.TIP_GAP
-- moves no tooltip, as W.FOOTER's figures do not.
local TIP_GAP = 2
lib.TIP_GAP = TIP_GAP

-- The window groups `SetGroup` registered: window -> its companions (a list, or a function that
-- answers one on each hover). Weak-keyed, so a released window is not kept alive by its
-- registration, and kept across a minor upgrade, so a newer copy keeps the older copy's groups.
lib.__groups = lib.__groups or setmetatable({}, { __mode = "k" })

local MAX_DEPTH = 32   -- an ancestor walk stops here, so a parent cycle cannot hang a hover

-- -- geometry reads ------------------------------------------------------------------------------

--- `v` when it is a plain, non-secret number, else nil.
local function num(v)
  if type(v) ~= "number" then return nil end
  local isSecret = issecretvalue
  if isSecret and isSecret(v) then return nil end
  return v
end

--- `frame:<method>()` as a plain number, or nil (a missing method, an unplaced frame, a secret).
local function read(frame, method)
  local fn = type(frame) == "table" and frame[method]
  if type(fn) ~= "function" then return nil end
  return num(fn(frame))
end

local function scaleOf(frame) return read(frame, "GetEffectiveScale") or 1 end

--- The screen's width and height in screen units, or nil.
local function screenSize()
  local ui = UIParent
  local w, h, s = read(ui, "GetWidth"), read(ui, "GetHeight"), scaleOf(ui)
  if not (w and h) or w <= 0 or h <= 0 then return nil end
  return w * s, h * s
end

--- A frame's left, bottom, right and top in screen units, or nil. `opts.rect` answers first.
local function rectOf(frame, opts)
  if opts and opts.rect then
    local l, b, r, t = opts.rect(frame)
    l, b, r, t = num(l), num(b), num(r), num(t)
    if l and b and r and t then return l, b, r, t end
    return nil
  end
  local l, b = read(frame, "GetLeft"), read(frame, "GetBottom")
  local r, t = read(frame, "GetRight"), read(frame, "GetTop")
  if not (l and b and r and t) then return nil end
  local s = scaleOf(frame)
  return l * s, b * s, r * s, t * s
end

--- The tooltip's width and height in screen units, or nil.
local function tipSize(tip)
  local w, h = read(tip, "GetWidth"), read(tip, "GetHeight")
  if not (w and h) then return nil end
  local s = scaleOf(tip)
  return w * s, h * s
end

-- -- the solvers (pure) ----------------------------------------------------------------------------

--- `top` slid only as far as it must for a `h` tall box to stay on a `screenH` tall screen: the
--- box's top never above the screen's, its bottom never below 0. A box taller than the screen
--- keeps its top on the screen's.
local function clampTop(top, h, screenH)
  if top - h < 0 then top = h end
  if top > screenH then top = screenH end
  return top
end

--- The body rule's side and point. `gl`, `gr`: the group's outer edges; `elemTop`: the hovered
--- element's top; the tooltip's size; the screen's; the gap; `prefer` "right" (the default) or
--- "left". Answers `side, point, x, y` (x, y in screen units from the screen's bottom-left), or nil
--- when neither side fits (the caller falls back to the chrome rule below the element).
function lib.__solveBeside(gl, gr, elemTop, tipW, tipH, screenW, screenH, gap, prefer)
  local fitsRight = gr + gap + tipW <= screenW
  local fitsLeft  = gl - gap - tipW >= 0
  local side
  if prefer == "left" then
    side = (fitsLeft and "left") or (fitsRight and "right") or nil
  else
    side = (fitsRight and "right") or (fitsLeft and "left") or nil
  end
  if not side then return nil end
  local y = clampTop(elemTop, tipH, screenH)
  if side == "right" then return "right", "TOPLEFT", gr + gap, y end
  return "left", "TOPRIGHT", gl - gap, y
end

--- The tooltip's center x on the element's center, slid only as far as it must to stay on screen
--- (a tooltip wider than the screen keeps its left edge on the screen's).
local function centerX(el, er, tipW, screenW)
  local left = (el + er) / 2 - tipW / 2
  if left + tipW > screenW then left = screenW - tipW end
  if left < 0 then left = 0 end
  return left + tipW / 2
end

--- The chrome rule's side and point. The element's left, bottom, right and top; the tooltip's size;
--- the screen's; the gap; `zone` "top" (the default) or "bottom". Answers `side, point, x, y`:
--- "below" with the tooltip's TOP at the element's bottom - gap, or "above" with its BOTTOM at the
--- element's top + gap. A top-chrome element goes below unless the screen's bottom has no room and
--- its top has; a bottom-chrome element the mirror. When neither has room, its own side.
function lib.__solveAttached(el, eb, er, et, tipW, tipH, screenW, screenH, gap, zone)
  local x = centerX(el, er, tipW, screenW)
  local belowY, aboveY = eb - gap, et + gap
  local roomBelow = belowY - tipH >= 0
  local roomAbove = aboveY + tipH <= screenH
  local below
  if zone == "bottom" then
    below = (not roomAbove) and roomBelow
  else
    below = roomBelow or not roomAbove
  end
  if below then return "below", "TOP", x, belowY end
  return "above", "BOTTOM", x, aboveY
end

--- The launcher rule's points. The button's left, bottom, right and top; the screen's size; the
--- gap. Answers `point, relativePoint, dx, dy`: the tooltip's `<V><H>` on the button's
--- `<opposite V><H>`, `<V>` TOP in the upper half (dy -gap) and BOTTOM in the lower (dy +gap),
--- `<H>` RIGHT, LEFT or "" by the screen third of the button's center.
function lib.__solveLauncher(bl, bb, br, bt, screenW, screenH, gap)
  local cx, cy = (bl + br) / 2, (bb + bt) / 2
  local h = ""
  if cx > screenW * 2 / 3 then h = "RIGHT" elseif cx < screenW / 3 then h = "LEFT" end
  if cy > screenH / 2 then return "TOP" .. h, "BOTTOM" .. h, 0, -gap end
  return "BOTTOM" .. h, "TOP" .. h, 0, gap
end

-- -- window groups ---------------------------------------------------------------------------------

local function parentOf(frame)
  local fn = type(frame) == "table" and frame.GetParent
  if type(fn) ~= "function" then return nil end
  local p = fn(frame)
  if type(p) ~= "table" or p == frame or p == UIParent then return nil end
  return p
end

local function isShown(frame)
  local fn = frame.IsShown
  return type(fn) ~= "function" or fn(frame) and true or false
end

--- The companions registered for `window`, as a list (a function is re-read here, each hover).
local function companionsOf(window)
  local c = lib.__groups[window]
  if type(c) == "function" then c = c() end
  return type(c) == "table" and c or {}
end

--- Register `window` as a group's main frame, with `companions` (a list of frames docked to it, or
--- a function answering one, re-read on each hover so a hidden panel drops out). `nil` registers
--- the window alone; `false` removes the registration.
function lib.SetGroup(window, companions)
  if type(window) ~= "table" then return end
  if companions == false then lib.__groups[window] = nil; return end
  lib.__groups[window] = companions or {}
end

--- The registered window `frame` is the main frame or a companion of, or nil.
local function registeredMain(frame)
  if lib.__groups[frame] then return frame end
  for window in pairs(lib.__groups) do
    for _, c in ipairs(companionsOf(window)) do
      if c == frame then return window end
    end
  end
  return nil
end

--- The group a frame list makes: main first, then every shown companion.
local function membersOf(main)
  local frames = { main }
  for _, c in ipairs(companionsOf(main)) do
    if c ~= main and isShown(c) then frames[#frames + 1] = c end
  end
  return frames
end

--- The window group `element` sits in: `frames, main, host`. The nearest ancestor (or the element)
--- that a `SetGroup` registered, as its main frame or a companion, decides it (`host` the member the
--- element is in); else the outermost ancestor under UIParent is a group of one. Nil for a non-frame.
function lib.GroupOf(element)
  if type(element) ~= "table" then return nil end
  local f, outer = element, element
  for _ = 1, MAX_DEPTH do
    local main = registeredMain(f)
    if main then return membersOf(main), main, f end
    outer = f
    f = parentOf(f)
    if not f then break end
  end
  return { outer }, outer, outer
end

local function isFrame(v)
  return type(v) == "table" and type(v.GetLeft) == "function" and rawget(v, 1) == nil
end

--- `group` as `frames, main`: a frame, a list (main first), `{ main = f, panels = {...} }`, a
--- function answering one of those, or nil (the element's GroupOf).
local function normalizeGroup(group, element)
  if type(group) == "function" then group = group() end
  if group == nil then
    local frames, main = lib.GroupOf(element)
    return frames, main
  end
  if isFrame(group) then return { group }, group end
  if type(group) ~= "table" then return nil end
  if group.main then
    local frames = { group.main }
    for _, p in ipairs(group.panels or {}) do
      if isShown(p) then frames[#frames + 1] = p end
    end
    return frames, group.main
  end
  return group, group[1]
end

--- The member of `frames` that `element` sits in (the element or its nearest such ancestor).
local function hostIn(frames, element)
  local set = {}
  for _, f in ipairs(frames) do set[f] = true end
  local f = element
  for _ = 1, MAX_DEPTH do
    if set[f] then return f end
    f = parentOf(f)
    if not f then return nil end
  end
  return nil
end

--- The group's outer edges in screen units, or nil when no member can be read.
local function spanOf(frames, opts)
  local gl, gr
  for _, f in ipairs(frames) do
    local l, _, r = rectOf(f, opts)
    if l then
      if not gl or l < gl then gl = l end
      if not gr or r > gr then gr = r end
    end
  end
  return gl, gr
end

--- The side a body tooltip prefers: `opts.prefer`, else a companion's side away from the main
--- window (by the two frames' centers), else right.
local function preferredSide(main, host, opts)
  if opts and (opts.prefer == "left" or opts.prefer == "right") then return opts.prefer end
  if not (host and main) or host == main then return "right" end
  local ml, _, mr = rectOf(main, opts)
  local hl, _, hr = rectOf(host, opts)
  if not (ml and hl) then return "right" end
  return (hl + hr) / 2 < (ml + mr) / 2 and "left" or "right"
end

-- -- applying a placement ------------------------------------------------------------------------

--- One absolute point on UIParent's bottom-left: `x`, `y` in screen units, written in the
--- tooltip's own.
local function pin(tip, point, x, y)
  local s = scaleOf(tip)
  tip:ClearAllPoints()
  tip:SetPoint(point, UIParent, "BOTTOMLEFT", x / s, y / s)
end

--- Remember the call so `Replace` can run it again after late growth. One table per tooltip, reused.
local function remember(tip, kind, a, b, c)
  local last = rawget(tip, "__ka0sTip")
  if type(last) ~= "table" then last = {}; tip.__ka0sTip = last end
  last.kind, last.a, last.b, last.c = kind, a, b, c
end

-- -- the public surface ----------------------------------------------------------------------------

--- Own `tip` for a placement: `SetOwner(opts.owner or element, "ANCHOR_NONE")`. `opts.owner =
--- UIParent` for an element in a restricted layout tree, which refuses to be an owner. Answers `tip`.
function lib.Own(tip, element, opts)
  local owner = (opts and opts.owner) or element
  if type(tip) == "table" and type(tip.SetOwner) == "function" and owner then
    tip:SetOwner(owner, "ANCHOR_NONE")
  end
  return tip
end

--- The chrome rule on a shown tooltip. `zone` "top" (the default; a modal's controls) or "bottom".
--- Answers "below" or "above", or nil with nothing placed when the geometry cannot be read.
function lib.PlaceAttached(tip, element, zone, opts)
  if type(tip) ~= "table" then return nil end
  remember(tip, "PlaceAttached", element, zone, opts)
  local sw, sh = screenSize()
  local tw, th = tipSize(tip)
  local el, eb, er, et = rectOf(element, opts)
  if not (sw and tw and el) then return nil end
  local side, point, x, y = lib.__solveAttached(el, eb, er, et, tw, th, sw, sh, TIP_GAP, zone)
  pin(tip, point, x, y)
  return side
end

--- The body rule on a shown tooltip. `group`: a frame, a list of frames (main first), `{ main = f,
--- panels = {...} }`, a function answering one, or nil (`GroupOf(element)`). `opts`: `prefer`
--- ("right" | "left"), `comparisons` (false skips SetAnchorType), `rect`. Answers "right", "left",
--- or the fallback's "below" / "above"; nil with nothing placed when the geometry cannot be read.
function lib.PlaceBeside(tip, element, group, opts)
  if type(tip) ~= "table" then return nil end
  local sw, sh = screenSize()
  local tw, th = tipSize(tip)
  local _, _, _, et = rectOf(element, opts)
  if not (sw and tw and et) then remember(tip, "PlaceBeside", element, group, opts); return nil end
  local frames, main = normalizeGroup(group, element)
  local gl, gr
  if frames then gl, gr = spanOf(frames, opts) end
  local side, point, x, y
  if gl then
    local prefer = preferredSide(main, hostIn(frames, element) or main, opts)
    side, point, x, y = lib.__solveBeside(gl, gr, et, tw, th, sw, sh, TIP_GAP, prefer)
  end
  if not side then
    local result = lib.PlaceAttached(tip, element, "top", opts)
    remember(tip, "PlaceBeside", element, group, opts)
    return result
  end
  remember(tip, "PlaceBeside", element, group, opts)
  if not (opts and opts.comparisons == false) and type(tip.SetAnchorType) == "function" then
    tip:SetAnchorType(side == "right" and "ANCHOR_RIGHT" or "ANCHOR_LEFT", 0, 0)
  end
  pin(tip, point, x, y)
  return side
end

--- The launcher rule: `tip`'s point on `button`, TIP_GAP off it, toward the screen's center.
--- Answers the tooltip's point ("TOPRIGHT", "BOTTOM", ...), or nil with nothing placed when the
--- geometry cannot be read.
function lib.PlaceLauncher(tip, button, opts)
  if type(tip) ~= "table" then return nil end
  remember(tip, "PlaceLauncher", button, opts)
  local sw, sh = screenSize()
  local bl, bb, br, bt = rectOf(button, opts)
  if not (sw and bl) then return nil end
  local point, rel, dx, dy = lib.__solveLauncher(bl, bb, br, bt, sw, sh, TIP_GAP)
  local s = scaleOf(tip)
  tip:ClearAllPoints()
  tip:SetPoint(point, button, rel, dx / s, dy / s)
  return point
end

--- Run `tip`'s last placement again, for a tooltip that grew after it was placed (item data
--- arriving after Show). Answers what that placer answers, or nil when nothing was placed yet.
function lib.Replace(tip)
  local last = type(tip) == "table" and rawget(tip, "__ka0sTip")
  if type(last) ~= "table" or not lib[last.kind] then return nil end
  return lib[last.kind](tip, last.a, last.b, last.c)
end
