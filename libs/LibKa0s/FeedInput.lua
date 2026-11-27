-- LibKa0s-Feed-1.0 -- FeedInput.lua, the toast feed's pointer, drag and strip.
--
-- Peeled out of Feed.lua on the seam the design named for it ("if Feed.lua passes 900, peel input
-- and unlock into FeedInput.lua"): with the input in it the shell was 954 lines. The shell reads it
-- through `lib.__input` at call time, and this file reads the shell's own steps through
-- `lib.__shell`, also at call time:
--
--   Hook(S, R)              a newly built row's OnEnter, OnLeave and OnMouseUp, set once
--   Dock(S)                 the drag handle on the stack's far edge and every strip re-placed
--   Strip(S)                the strip of the kind set, built once per kind, docked by Widgets
--   Lock(S)                 locked: a drag under way ends and is saved, the handle hides
--   Unlock(S)               unlocked unless in combat or without Widgets; answers still-locked
--   ClickThrough(S, on)     every row's mouse off (on) or back; on also ends hover and freeze
--
-- THE POINTER. Rows take the mouse unless the feed is click-through. OnEnter marks the row's
-- entry hovered and recomputes the freeze, which the shell DERIVES ("a live row is hovered and
-- motion.pin is on") on every enter, leave, drop and click-through change and never latches; then
-- `d.onEnter(row, payload, key)`. OnLeave clears the mark, recomputes the freeze (its end
-- re-lays out and drains) and wakes the clock, then `d.onLeave`; every onEnter gets exactly one
-- onLeave, a row dropped or freed while hovered included. OnMouseUp: the left button while
-- unlocked is a drag's and reaches nobody; the right one dismisses with motion.rightDismiss on;
-- anything else is `d.onClick(payload, button, key)`. Click-through on also ends every hover and
-- the freeze, and drains, because the client sends no OnLeave to a row whose mouse is off.
--
-- THE DRAG. SetLocked(false) docks a LibKa0s-Widgets-1.0 DragHandle with `d.strings.HANDLE` on
-- the stack's far edge (over it growing up, under it growing down) and makes the container
-- movable. In combat it is refused and answers true; without Widgets it answers true and stays
-- locked (the host's nudge rows still move the feed). On drag stop the container's rect, in
-- UIParent units, becomes a nudge from the slot (FeedModel's NudgeFromRect), kept in the snapshot,
-- the container is anchored from the slot again and `d.onMoved(x, y)` tells the host.
--
-- THE STRIP. SetStrip("test" | "sim", text) builds a W.TestStrip with the host's text and docks it
-- through the library's own HUD docking (Widgets minor 27, `dock = "hud"`, preview-mode's *Where the
-- strip sits*): on the container's top edge, outside it, CHROME_GAP off, flipped under its bottom
-- edge only while the top would leave the screen, no mouse, the display's chrome band, and stacked
-- beyond the drag handle while it shows (`clear`), so it never overlaps it. Nothing here anchors a
-- strip by hand; a move or a re-anchor fires no script, so Dock calls `strip:Place()`. It shows
-- whenever its kind is set, locked or not.
--
-- Minor 1 (LootHistory#38, task S3 of the Feed build): the input.

local lib = LibStub and LibStub("LibKa0s-Feed-1.0", true)
if not lib then return end

local INPUT_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own, as FeedModel.lua and FeedRow.lua are.
if lib.__inputMinor and lib.__inputMinor >= INPUT_MINOR and lib.__inputShellMinor == lib.MINOR then return end
lib.__inputMinor, lib.__inputShellMinor = INPUT_MINOR, lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.FeedInput = INPUT_MINOR

local HUGE = math.huge
local CHROME_GAP = 2   -- px between the stack and the drag handle (its far edge) or the strip (its top)

local I = {}

local function K() return lib.__shell end

local function finite(v) return type(v) == "number" and v == v and v ~= HUGE and v ~= -HUGE end

local function widgets() return LibStub and LibStub("LibKa0s-Widgets-1.0", true) or nil end

-- == the far edge =============================================================================

--- The drag handle on the stack's far edge, CHROME_GAP clear of it and centered: over the stack
--- growing up, under it growing down. (The strips are Widgets' to place, below.)
local function dockFar(S, f)
  local c, up = S.container, S.cfg.layout.grow ~= "DOWN"
  local near, far = up and "BOTTOM" or "TOP", up and "TOP" or "BOTTOM"
  f:ClearAllPoints()
  f:SetPoint(near, c, far, 0, up and CHROME_GAP or -CHROME_GAP)
end

--- Widgets' HUD dock spec for the feed's strips: the container's top edge, clear of the handle.
local function stripDock(S, spec)
  spec.dock, spec.target, spec.gap, spec.clear = "hud", S.container, CHROME_GAP, S.handle
  return spec
end

--- Every strip docked again, so one built before the drag handle stacks beyond it once it exists.
local function redockStrips(S)
  local W = widgets()
  if not (W and type(W.DockTestStrip) == "function") then return end
  for _, strip in pairs(S.strips) do W.DockTestStrip(strip, stripDock(S, {})) end
end

function I.Dock(S)
  if S.handle then dockFar(S, S.handle) end
  for _, strip in pairs(S.strips) do
    if type(strip.Place) == "function" then strip:Place() end
  end
end

-- == the strip ================================================================================

--- The strip of the kind set shows; every other strip is hidden.
local function showStrips(S)
  for kind, strip in pairs(S.strips) do strip:SetShown(kind == S.stripKind) end
end

function I.Strip(S)
  if not S.built then return end
  local kind, W = S.stripKind, widgets()
  if kind and not S.strips[kind] and W and type(W.TestStrip) == "function" then
    local strip = W.TestStrip(S.container, stripDock(S, { kind = kind, owner = S.d.owner, text = S.stripText }))
    if strip then S.strips[kind] = strip end
  end
  local strip = kind and S.strips[kind]
  if strip and strip.text then strip.text:SetText(S.stripText) end
  showStrips(S)
end

-- == the pointer ==============================================================================

--- The live entry a row's script fired for, or nil (a released or dropping row).
local function liveEntry(R)
  local e = R.entry
  if e and e.phase ~= "drop" and e.phase ~= "done" then return e end
  return nil
end

local function onRowEnter(S, R)
  local e = liveEntry(R)
  if not e or e.hovered then return end
  e.hovered = true
  K().refreeze(S)
  K().hostCall(S, S.d.onEnter, R.frame, e.payload, e.key)
end

local function onRowLeave(S, R)
  local e = R.entry
  if not (e and e.hovered) then return end
  local k = K()
  k.unhover(S, e)
  k.refreeze(S)
  k.wake(S)   -- a row paused alone (pin off) runs on
end

local function onRowClick(S, R, button)
  local e = liveEntry(R)
  if not e then return end
  if button == "LeftButton" and not S.locked then return end
  if button == "RightButton" and S.cfg.motion.rightDismiss then return K().dismiss(S, e) end
  K().hostCall(S, S.d.onClick, e.payload, button, e.key)
end

function I.Hook(S, R)
  local f = R.frame
  f:SetScript("OnEnter", function() onRowEnter(S, R) end)
  f:SetScript("OnLeave", function() onRowLeave(S, R) end)
  f:SetScript("OnMouseUp", function(_, button) onRowClick(S, R, button) end)
end

function I.ClickThrough(S, on)
  S.clickThrough = on
  for _, e in ipairs(S.live) do e.row.frame:EnableMouse(not on) end
  for _, e in ipairs(S.leaving) do e.row.frame:EnableMouse(not on) end
  if not (on and S.built) then return end
  local k = K()
  for _, e in ipairs(S.live) do k.unhover(S, e) end
  k.refreeze(S)
  k.drain(S)
  k.wake(S)
end

-- == the drag =================================================================================

local function inCombat() return type(InCombatLockdown) == "function" and InCombatLockdown() == true end

--- `f:name()` when it answers a finite number, else nil.
local function measure(f, name)
  local fn = f and f[name]
  local v = type(fn) == "function" and fn(f) or nil
  return finite(v) and v or nil
end

--- The container's rect in UIParent units, or nil where the client answers no geometry.
local function rectOf(c)
  local es, ues = measure(c, "GetEffectiveScale"), measure(UIParent, "GetEffectiveScale")
  if not (es and ues and ues > 0) then return nil end
  local l, b = measure(c, "GetLeft"), measure(c, "GetBottom")
  local r, t = measure(c, "GetRight"), measure(c, "GetTop")
  if not (l and b and r and t) then return nil end
  local k = es / ues
  return l * k, b * k, r * k, t * k
end

--- A drag ended: the rect as a nudge from the slot, kept in the snapshot, the container anchored
--- from the slot again, then the host told through d.onMoved(x, y).
local function moved(S)
  local c, L = S.container, S.cfg.layout
  if type(c.SetUserPlaced) == "function" then c:SetUserPlaced(false) end   -- the slot is the save
  local l, b, r, t = rectOf(c)
  local W, H = measure(UIParent, "GetWidth"), measure(UIParent, "GetHeight")
  if not (l and W and H) then return K().anchor(S) end
  local x, y = lib.__model.NudgeFromRect(L.slot, L.grow, l, b, r, t, W, H)
  L.x, L.y = x, y
  K().anchor(S)
  K().hostCall(S, S.d.onMoved, x, y)
end

--- The drag handle, built once on the first unlock when Widgets is present, with the host's label.
local function buildHandle(S)
  if S.handle then return S.handle end
  local W = widgets()
  if not (W and type(W.DragHandle) == "function") then return nil end
  local str = type(S.d.strings) == "table" and S.d.strings or {}
  local label, tip = rawget(str, "HANDLE"), rawget(str, "HANDLE_TIP")
  label = type(label) == "string" and label or ""
  local handle = W.DragHandle(S.container, {
    label = label, moveFrame = S.container, owner = S.d.owner,
    tooltip = type(tip) == "string" and { title = label, body = { tip } } or nil,
    canDrag = function() return not S.locked end,
    onDragStart = function() S.moving = true end,
    onDragStop = function() S.moving = nil; moved(S) end,
  })
  if not handle then return nil end
  if type(handle.ApplyWidth) == "function" then handle:ApplyWidth() end
  S.handle = handle
  dockFar(S, handle)
  redockStrips(S)
  return handle
end

function I.Lock(S)
  S.locked = true
  if S.moving then
    S.moving = nil
    S.container:StopMovingOrSizing()
    moved(S)
  end
  if S.handle then S.handle:Hide() end
  if S.container then S.container:SetMovable(false) end
  showStrips(S)
end

function I.Unlock(S)
  if not S.locked then return false end
  if inCombat() then return true end
  K().ensure(S)
  local handle = buildHandle(S)
  if not handle then return true end
  S.locked = false
  S.container:SetMovable(true)
  dockFar(S, handle)
  handle:Show()
  showStrips(S)
  return false
end

lib.__input = I
