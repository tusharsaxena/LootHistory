-- LibKa0s-Toast-1.0 — the alert-toast shell.
--
-- ── WHY THIS EXISTS ──────────────────────────────────────────────────────────────────────────
--
-- Drop Watcher's upgrade toast (its `modules/Toast.lua`) carried a queue, a timed and hover-paused
-- lifetime, a close mark, a right-click dismiss, test-mode placement, scale and an alert sound
-- around four rows of its own content. Ka0s DPS Race wants the same alert for a new personal best
-- (DpsRace#5). This file is that shell, once, and the content stays in each addon (LibKa0s#60,
-- approved by the owner on 2026-10-25).
--
-- ── THE CONTRACT ─────────────────────────────────────────────────────────────────────────────
--
-- `Toast:New(d)` answers one toast instance. `d.build(frame, payload)` is the ONE presentation
-- argument: it draws the payload's rows on the toast's frame and answers the frame's width and
-- height (either may be nil to keep the current one), or `false` to skip the payload. Everything
-- else in `d` is a value or a getter the host reads out of its own profile: duration, scale, sound,
-- the drag predicate, the saved position. There is no behavior flag: a host that holds toasts in
-- combat does not call Show in combat (or calls Hold and Release), and a host that wants a toast
-- to replace another calls Remove first. docs/api/Toast/version-4-docs.md is the full contract.
--
-- Minor 2 (FS-FIX of Ka0sAddonsCommonTasks docs/2026-11-01-FULL_SKINNING): d.soundFile, additive,
-- for a host whose alert is a file rather than a sound kit id. A host that does not pass it plays
-- exactly what it played.
-- Minor 3 (R5-L2 of Ka0sAddonsCommonTasks docs/2026-11-03-SMOKE_ROUND5): a toast has no title bar, so an
-- owned toast asks its owner's facade for `Shell(f, { noTopBar = true })` after ApplySkin, now that
-- Shell's top band shows on a backdrop frame (SkinPaint minor 18). Core's `__SkinFacade` is read at
-- call time; a Core without it, or an unregistered owner, paints exactly as before.
-- Minor 4 (LK-T1, Drop Watcher issue #14): the stack, opt in. d.stack (how many show at once),
-- d.stackGrow ("DOWN" or "UP") and d.stackGap, each a value or a getter, and SetStack(n, grow) for
-- a host's settings rows. Each toast on screen has its own frame (pooled), countdown, hover pause and
-- close; the head sits at the saved point and each after it hangs off the one before. Visible() and
-- FrameFor(key) name what is up; Stats() adds visible, visibleKeys, stack and grow. Without
-- d.stack, or with 1, it is the minor 3 toast.
--
-- ── WHAT THE SHELL DOES ──────────────────────────────────────────────────────────────────────
--
-- * One toast at a time, or up to d.stack at once. `Show` queues; the next shows when the stack has
--   room. Past the cap (d.maxQueue, default MAX_QUEUE) a Show drops the oldest waiting payload; a
--   toast sent back from the screen to wait (Hold, a smaller stack) is never dropped for it.
-- * Lifetime. A toast closes after its duration; the countdown pauses while the pointer is over the
--   toast (or over a control the host attached) and resumes with the time it had left, never less
--   than a second. It also closes on its close mark or on a right-click anywhere on it. A sticky
--   toast (Show's `opts.sticky`, and every Preview) has no countdown.
-- * Placement. Draggable with the left button only while d.draggable() answers true (the host's
--   test mode). The position is handed to d.setPosition in UIParent's units and read back through
--   d.getPosition, so a scale change grows or shrinks the toast about the saved anchor and never
--   rewrites it. In a stack the saved point is the head's, and a drag on any toast moves the head.
-- * Chrome. frame-layering's T5 alert tier: HIGH strata, mouse-enabled, clamped to the screen.
--   The skin is Core's ApplySkin and the close mark Core's MakeCloseButton, both called with the
--   host's d.owner: on a Core whose ApplySkin knows skin owners (Core minor 13, with
--   LibKa0s-Skin-1.0 present and the owner registered) the toast wears the owner's skin, and on any
--   older Core (v1.77.0 ships minor 12) the extra argument is ignored and it wears Core's SKIN.
--   Neither is required: a Core without them draws an undecorated toast with no close mark, and a
--   right-click still closes it.
--
-- ── DEPENDENCIES ─────────────────────────────────────────────────────────────────────────────
--
-- LibStub and LibKa0s-Core-1.0 minor 1 or newer, for the same reason Glow gates on it: a host with a
-- partial payload gets every module absent rather than a working half. ApplySkin and
-- MakeCloseButton are presence-checked at call time. No other major is read, so this file runs
-- unchanged beside the v1.77.0 payload, which is how a consumer may vendor it ahead of a full
-- re-vendor. Nothing here is a protected call, so it works in combat.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Toast-1.0", 4
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.Toast = MINOR

-- The defaults a descriptor may leave out. Published so a host cites them rather than restating.
lib.DURATION = 8                         -- seconds on screen, when d.duration answers nothing usable
lib.MAX_QUEUE = 5                        -- payloads waiting, the oldest dropped past it
lib.WIDTH, lib.HEIGHT = 320, 64          -- the frame's size until the builder answers one
lib.POINT = { "TOP", "TOP", 0, -160 }    -- under the top of the screen, in UIParent's units
lib.STRATA = "HIGH"                      -- frame-layering's T5 alert tier
lib.PREVIEW = "LibKa0s-Toast-preview"    -- the key Preview queues under
lib.STACK_GAP = 6                        -- px between stacked toasts, in the toast's own units (minor 4)

local TAG = "TOAST"
local MIN_RESUME = 1    -- a resumed countdown never has less than this left
local CLOSE_INSET = 4   -- the close mark's offset from the top-right corner
local WATCH_POLL = 0.2  -- seconds between checks that the pointer left the toast (watchLeave)
local PARENT_HOPS = 20  -- how far Attach walks up a control's parents to find its toast

-- ── small readers ────────────────────────────────────────────────────────────────────────────

--- A descriptor field that may be a value or a getter, read at call time.
local function read(v)
  if type(v) == "function" then return v() end
  return v
end

local function positive(v)
  if type(v) == "number" and v == v and v > 0 then return v end
  return nil
end

--- A point table the frame can be anchored with: { point, relativePoint, x, y }.
local function validPoint(pt)
  return type(pt) == "table" and type(pt[1]) == "string" and pt or nil
end

local function debugOut(S, fmt, ...)
  local sink = S.d.debug
  if type(sink) == "function" then pcall(sink, TAG, fmt, ...) end
end

local function scaleOf(S) return positive(read(S.d.scale)) or 1 end

local function durationOf(S) return positive(read(S.d.duration)) or lib.DURATION end

--- How many toasts may be on screen at once: SetStack's, else d.stack's, floored, never under 1.
local function stackOf(S)
  local n = S.stackN
  if n == nil then n = read(S.d.stack) end
  n = positive(n)
  return n and math.max(1, math.floor(n)) or 1
end

--- The way the stack grows from its head: "UP", else "DOWN".
local function growOf(S)
  local g = S.stackGrow
  if g == nil then g = read(S.d.stackGrow) end
  return g == "UP" and "UP" or "DOWN"
end

local function gapOf(S)
  local g = read(S.d.stackGap)
  if type(g) == "number" and g == g and g >= 0 then return g end
  return lib.STACK_GAP
end

--- A key as the host's lists show it: `false` for an entry queued without one.
local function keyOf(entry)
  if entry.key == nil then return false end
  return entry.key
end

-- ── the records ──────────────────────────────────────────────────────────────────────────────
--
-- Each frame the shell builds is a record R = { S, frame, entry, timer, dueAt, remaining, watch,
-- dragHeld }, kept in S.pool in build order and reused. S.shown lists the records on screen, head
-- first; a record not in it has no entry and is free. Without d.stack there is one record, and the
-- shell is the version 3 toast. S.moving names the record a drag moves, while one does.

-- ── the timer ────────────────────────────────────────────────────────────────────────────────

local function cancelTimer(R)
  if R.timer and R.timer.Cancel then R.timer:Cancel() end
  R.timer, R.dueAt = nil, nil
end

local dismiss   -- forward: the timer and the frame's scripts close through it

local function startTimer(R, seconds)
  cancelTimer(R)
  R.dueAt = GetTime() + seconds
  local handle
  handle = C_Timer.NewTimer(seconds, function()
    if R.timer ~= handle then return end   -- a timer replaced before it fired
    R.timer, R.dueAt = nil, nil
    debugOut(R.S, "toast expired")
    dismiss(R)
  end)
  R.timer = handle
end

local function cancelWatch(R)
  if R.watch and R.watch.Cancel then R.watch:Cancel() end
  R.watch = nil
end

local function pause(R)
  cancelWatch(R)   -- the control the pointer entered now owns the resume
  R.dragHeld = nil  -- a hover or a host's Pause owns it now, not the drag (onDragStart)
  if not (R.entry and R.dueAt) then return end
  R.remaining = math.max(R.dueAt - GetTime(), 0)
  cancelTimer(R)
end

local function resume(R)
  cancelWatch(R)
  if not (R.entry and R.remaining) then return end
  if R.S.moving then R.dragHeld = true; return end   -- a drag holds it; endDrag resumes it
  local left = R.remaining
  R.remaining = nil
  startTimer(R, math.max(left, MIN_RESUME))
end

--- The pointer left onto something still over the toast (a child control). The countdown must not
--- rely on that child's OnLeave hook to resume it: a library-painted child's scripts can be SetScript
--- again under it (Core minor 13's close mark for a skin owner, on every skin switch), which drops
--- the hook. So poll until the pointer is off the toast, then resume.
local function watchLeave(R)
  cancelWatch(R)
  if not (R.entry and R.remaining) then return end
  local handle
  handle = C_Timer.NewTimer(WATCH_POLL, function()
    if R.watch ~= handle then return end
    R.watch = nil
    local f = R.frame
    if f.IsMouseOver and f:IsMouseOver() == true then watchLeave(R) else resume(R) end
  end)
  R.watch = handle
end

-- ── placement ────────────────────────────────────────────────────────────────────────────────

local function savedPoint(S)
  return validPoint(read(S.d.getPosition)) or validPoint(S.d.defaultPosition) or lib.POINT
end

--- The scale first, then the saved point in the toast's own units at that scale, so the anchor the
--- player placed stays where it is whatever the scale. Answers the point's name.
local function anchorHead(S, f, s)
  local pt = savedPoint(S)
  f:SetScale(s)
  f:ClearAllPoints()
  f:SetPoint(pt[1], UIParent, pt[2] or pt[1], (tonumber(pt[3]) or 0) / s, (tonumber(pt[4]) or 0) / s)
  return pt[1]
end

--- The side a stack keeps its edges on: the saved point's, so a toast placed at a left corner grows
--- along that edge whatever each toast's width.
local function sideOf(point)
  if point:find("LEFT", 1, true) then return "LEFT" end
  if point:find("RIGHT", 1, true) then return "RIGHT" end
  return ""
end

local function anchorFollower(f, prev, s, side, grow, gap)
  f:SetScale(s)
  f:ClearAllPoints()
  if grow == "UP" then
    f:SetPoint("BOTTOM" .. side, prev, "TOP" .. side, 0, gap)
  else
    f:SetPoint("TOP" .. side, prev, "BOTTOM" .. side, 0, -gap)
  end
end

--- GetPoint answers in the toast's (scaled) units; the host is handed UIParent's.
local function savePosition(S, f)
  local point, _, relativePoint, x, y = f:GetPoint(1)
  if type(point) ~= "string" or type(S.d.setPosition) ~= "function" then return end
  local s = tonumber(f:GetScale()) or 1
  S.d.setPosition({ point, type(relativePoint) == "string" and relativePoint or point,
    (tonumber(x) or 0) * s, (tonumber(y) or 0) * s })
end

--- The drag ends, whatever ended it: the point the player dragged to is saved, and every countdown
--- the drag held resumes (or, under the pointer, waits for it to leave, as a hover does).
local function endDrag(S)
  local moving = S.moving
  if not moving then return end
  S.moving = nil
  moving.frame:StopMovingOrSizing()
  savePosition(S, moving.frame)
  for _, R in ipairs(S.shown) do
    if R.dragHeld then
      R.dragHeld = nil
      local f = R.frame
      if f.IsMouseOver and f:IsMouseOver() == true then watchLeave(R) else resume(R) end
    end
  end
end

--- The head (or, with nothing on screen, the first frame) at the saved point; each toast after it
--- hangs off the one before. A head mid-drag is left where the pointer has it and only the rest are
--- anchored; a drag on a frame that is no longer the head ends first, keeping its point.
local function applyLayout(S)
  local shown = S.shown
  local head = shown[1] or S.pool[1]
  if not head then return end
  if S.moving and S.moving ~= head then endDrag(S) end
  local s = scaleOf(S)
  local side
  if S.moving == head then side = sideOf(savedPoint(S)[1]) else side = sideOf(anchorHead(S, head.frame, s)) end
  if #shown < 2 then return end
  local grow, gap = growOf(S), gapOf(S)
  for i = 2, #shown do anchorFollower(shown[i].frame, shown[i - 1].frame, s, side, grow, gap) end
end

-- ── the frame ────────────────────────────────────────────────────────────────────────────────

--- A drag on any toast moves the head, and the rest follow it; the saved point is the head's. The
--- drag holds every countdown on screen, so no toast closes under it (a hover pauses only the toast
--- the pointer is over, and the head it moves may be another).
local function onDragStart(R)
  local S = R.S
  if read(S.d.draggable) ~= true or S.moving then return end
  local head = S.shown[1] or R
  S.moving = head
  for _, shown in ipairs(S.shown) do
    if shown.dueAt then
      pause(shown)
      shown.dragHeld = true
    end
  end
  head.frame:StartMoving()
end

local function onDragStop(R) endDrag(R.S) end

--- Hover pauses the countdown, leaving resumes it, and a right-click closes: on the frame and on
--- every control the host attaches, so a pointer moving from the frame onto a button keeps it held.
--- Leaving onto something still over the toast watches for the pointer to go (watchLeave).
local function hookPointer(R, widget, set)
  local wire = set and widget.SetScript or widget.HookScript
  wire(widget, "OnEnter", function() pause(R) end)
  wire(widget, "OnLeave", function()
    local f = R.frame
    if f.IsMouseOver and f:IsMouseOver() == true then watchLeave(R) else resume(R) end
  end)
  wire(widget, "OnMouseUp", function(_, button)
    if button == "RightButton" then dismiss(R) end
  end)
end

local function decorate(R, f)
  local owner = R.S.d.owner
  if type(core.ApplySkin) == "function" then core.ApplySkin(f, nil, owner) end
  local skin = type(core.__SkinFacade) == "function" and core.__SkinFacade(owner)
  if skin then skin.Shell(f, { noTopBar = true }) end   -- no band on a toast (minor 3)
  if type(core.MakeCloseButton) ~= "function" then return end
  local close = core.MakeCloseButton(f, function() dismiss(R) end, owner)
  if not close then return end
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -CLOSE_INSET, -CLOSE_INSET)
  hookPointer(R, close, false)
  f.close = close
end

--- The first frame takes d.name; a pooled frame after it takes the name and its place (Name2, ...).
local function frameName(S, i)
  if i > 1 and type(S.d.name) == "string" then return S.d.name .. i end
  if i == 1 then return S.d.name end
  return nil
end

local function build(S)
  local i = #S.pool + 1
  local f = CreateFrame("Frame", frameName(S, i), UIParent, "BackdropTemplate")
  local R = { S = S, frame = f }
  S.pool[i] = R
  f:Hide()
  f:SetFrameStrata(lib.STRATA)
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetSize(positive(S.d.width) or lib.WIDTH, positive(S.d.height) or lib.HEIGHT)
  f:SetScript("OnDragStart", function() onDragStart(R) end)
  f:SetScript("OnDragStop", function() onDragStop(R) end)
  hookPointer(R, f, true)
  decorate(R, f)
  applyLayout(S)
  return R
end

--- A free record (no entry, not mid-draw), else a new frame.
local function acquire(S)
  for _, R in ipairs(S.pool) do
    if not R.entry and R ~= S.building then return R end
  end
  return build(S)
end

-- ── the queue ────────────────────────────────────────────────────────────────────────────────

--- Show appends and trims the oldest past the cap. A toast sent back from the screen (`front`: Hold,
--- a shrinking stack, a preview's full stack) goes to the head and trims nothing, so sending it back
--- never costs a payload; the queue may then hold up to the stack's size over the cap until the next
--- Show trims the oldest.
local function enqueue(S, entry, front)
  local q = S.queue
  if front then
    table.insert(q, 1, entry)
    return
  end
  q[#q + 1] = entry
  local cap = math.max(1, math.floor(positive(S.d.maxQueue) or lib.MAX_QUEUE))
  while #q > cap do table.remove(q, 1) end
end

--- A file PlaySoundFile takes: a non-empty path or a file data id.
local function soundFileOf(S)
  local file = read(S.d.soundFile)
  if type(file) == "number" or (type(file) == "string" and file ~= "") then return file end
  return nil
end

--- A host's d.soundFile is the whole answer when it names a file: on a client without PlaySoundFile
--- the toast is silent, never the default alert in its place. Otherwise the kit path.
local function playSound(S)
  if read(S.d.sound) ~= true then return end
  local file = soundFileOf(S)
  if file then
    if type(PlaySoundFile) == "function" then PlaySoundFile(file, "Master") end
    return
  end
  if type(PlaySound) ~= "function" then return end
  local kit = type(SOUNDKIT) == "table" and SOUNDKIT or {}
  local id = read(S.d.soundKit)
  if type(id) ~= "number" then id = kit.UI_EPICLOOT_TOAST or kit.RAID_WARNING end
  if type(id) == "number" then PlaySound(id, "Master") end
end

--- The builder, under pcall: a raise costs this payload, reported through the error handler, and
--- the next one still shows. Answers whether the payload is drawn. While it runs, S.building names
--- the record, so a control the builder Attaches is wired to the toast it is drawn on.
local function draw(S, R, entry)
  local f = R.frame
  S.building = R
  local ok, w, h = pcall(S.d.build, f, entry.payload)
  S.building = nil
  if not ok then
    local handler = type(geterrorhandler) == "function" and geterrorhandler() or nil
    if handler then pcall(handler, w) end
    debugOut(S, "builder failed: %s", tostring(w))
    return false
  end
  if w == false then return false end
  if positive(w) then f:SetWidth(w) end
  if positive(h) then f:SetHeight(h) end
  return true
end

--- Draw `entry` on a free frame and put it on screen at place `at` in the stack (the tail when nil).
local function present(S, entry, at)
  local R = acquire(S)
  if not draw(S, R, entry) then return false end
  R.entry, R.remaining, R.dragHeld = entry, nil, nil
  table.insert(S.shown, at or #S.shown + 1, R)
  applyLayout(S)
  R.frame:Show()
  playSound(S)
  if S.moving and not entry.sticky then
    R.remaining, R.dragHeld = durationOf(S), true   -- shown mid-drag: its countdown starts at endDrag
  elseif not entry.sticky then
    startTimer(R, durationOf(S))
  end
  debugOut(S, "toast shown (%d waiting)", #S.queue)
  return true
end

local function pump(S)
  if S.held then return end
  while #S.shown < stackOf(S) and #S.queue > 0 do
    present(S, table.remove(S.queue, 1))
  end
end

--- Take one toast down, without showing the next. Answers the entry it held.
local function takeDown(R)
  local S = R.S
  if S.moving == R then endDrag(S) end   -- the drag's point is kept, not lost with the toast
  cancelTimer(R)
  cancelWatch(R)
  local entry = R.entry
  R.entry, R.remaining, R.dragHeld = nil, nil, nil
  R.frame:Hide()
  for i = #S.shown, 1, -1 do
    if S.shown[i] == R then table.remove(S.shown, i) end
  end
  return entry
end

--- After a toast went: the rest close up on the head and what waits fills the stack.
local function reflow(S)
  if #S.shown > 0 then applyLayout(S) end
  pump(S)
end

dismiss = function(R)
  if not R.entry then return end
  takeDown(R)
  reflow(R.S)
end

--- The toast at the stack's tail goes back to the head of the queue, its full time kept for later.
local function requeueTail(S)
  enqueue(S, takeDown(S.shown[#S.shown]), true)
end

--- A stack that shrank sends its tail back to wait, the order kept; one that grew fills.
local function fitStack(S)
  while #S.shown > stackOf(S) do requeueTail(S) end
  applyLayout(S)
  pump(S)
end

local function removeKey(S, key)
  local n = 0
  for i = #S.queue, 1, -1 do
    if S.queue[i].key == key then
      table.remove(S.queue, i)
      n = n + 1
    end
  end
  return n
end

--- Take down every toast on screen under `key`. Answers how many went.
local function takeDownKey(S, key)
  local n = 0
  for i = #S.shown, 1, -1 do
    local R = S.shown[i]
    if R.entry.key == key then
      takeDown(R)
      n = n + 1
    end
  end
  return n
end

--- The record a control belongs to: the frame it is, or the first of its parents that is one.
local function recordFor(S, widget)
  local w = widget
  for _ = 1, PARENT_HOPS do
    for _, R in ipairs(S.pool) do
      if R.frame == w then return R end
    end
    local p = type(w.GetParent) == "function" and w:GetParent() or nil
    if p == nil or p == w then return nil end
    w = p
  end
  return nil
end

local function shownKeys(S)
  local keys = {}
  for i, R in ipairs(S.shown) do keys[i] = keyOf(R.entry) end
  return keys
end

-- ── the instance ─────────────────────────────────────────────────────────────────────────────

local STATE = setmetatable({}, { __mode = "k" })

local function state(self)
  local S = STATE[self]
  if not S then error(MAJOR .. ": call this on an instance from Toast:New", 3) end
  return S
end

local METHODS = {}

--- Queue `payload`; it shows now when the stack has room and the toast is not held.
--- opts.key names it for Remove; opts.sticky gives it no countdown. Answers true.
function METHODS:Show(payload, opts)
  local S = state(self)
  opts = type(opts) == "table" and opts or {}
  enqueue(S, { payload = payload, key = opts.key, sticky = opts.sticky == true })
  debugOut(S, "toast queued (%d waiting)%s", #S.queue, S.held and ", held" or "")
  pump(S)
  return true
end

--- Close the toast at the head; the rest close up and the next one shows.
function METHODS:Dismiss()
  local S = state(self)
  if S.shown[1] then dismiss(S.shown[1]) end
end

--- Drop every waiting payload queued under `key`, and close every toast on screen that is `key`'s.
--- Answers how many it let go.
function METHODS:Remove(key)
  local S = state(self)
  if key == nil then return 0 end
  local n = removeKey(S, key)
  local closed = takeDownKey(S, key)
  if closed > 0 then reflow(S) end
  return n + closed
end

--- The stand-down: every toast on screen goes, nothing waits, and a hold is released without
--- showing anything.
function METHODS:Clear()
  local S = state(self)
  S.queue, S.held = {}, false
  while S.shown[1] do takeDown(S.shown[1]) end
end

--- Stop showing: every toast on screen goes back to the head of the queue, in its order, with its
--- full time again, and nothing shows until Release. With `keepShown` the toasts on screen stay up
--- and run their course; only what would show after them waits (a host's hold set while a toast is
--- already up).
function METHODS:Hold(keepShown)
  local S = state(self)
  S.held = true
  if keepShown == true then return end
  while S.shown[1] do requeueTail(S) end
end

--- Undo Hold: what waits shows.
function METHODS:Release()
  local S = state(self)
  S.held = false
  pump(S)
end

--- Every countdown on screen stops, keeping the time it had left (a frame's OnEnter pauses its own).
function METHODS:Pause()
  for _, R in ipairs(state(self).shown) do pause(R) end
end

--- Every countdown on screen resumes with the time it had left (a frame's OnLeave resumes its own).
function METHODS:Resume()
  for _, R in ipairs(state(self).shown) do resume(R) end
end

--- Wire a control the builder made: hovering it holds its toast's countdown, and a right-click on it
--- closes that toast. Its own scripts are kept (HookScript). Called from the builder, the control
--- belongs to the toast being drawn; otherwise to the toast whose frame is among its parents, else
--- the head, else the first frame, which an Attach before the first Show builds (as version 3 wired
--- a control at any time).
function METHODS:Attach(widget)
  local S = state(self)
  if type(widget) ~= "table" or type(widget.HookScript) ~= "function" then return end
  local R = S.building or recordFor(S, widget) or S.shown[1] or S.pool[1] or build(S)
  hookPointer(R, widget, false)
end

--- Re-read the scale, the saved position and the stack (after the host's settings rows or a
--- profile switch). The descriptor answers again: an earlier SetStack lasts until this call.
function METHODS:Refresh()
  local S = state(self)
  S.stackN, S.stackGrow = nil, nil
  fitStack(S)
end

--- How many toasts show at once and the way they grow, at runtime (the host's settings rows):
--- `n` replaces d.stack and `grow` ("DOWN" or "UP") d.stackGrow until the next Refresh; a nil
--- argument leaves that half as it is. A smaller stack sends its tail back to the head of the queue;
--- a larger one fills.
--- Answers the stack and the direction now in force.
function METHODS:SetStack(n, grow)
  local S = state(self)
  if n ~= nil then S.stackN = n end
  if grow ~= nil then S.stackGrow = grow end
  fitStack(S)
  return stackOf(S), growOf(S)
end

--- Forget the saved position (d.setPosition(nil)): the toast goes back to d.defaultPosition.
function METHODS:ResetPosition()
  local S = state(self)
  if type(S.d.setPosition) == "function" then S.d.setPosition(nil) end
  applyLayout(S)
end

--- Show `payload` now, sticky, at the head, so it can be seen and placed (the host's test mode): a
--- full stack sends its tail back to the head of the queue, and a previous preview is replaced. It
--- closes like any toast, or through Remove(Toast.PREVIEW). It shows past a Hold without releasing
--- it: the preview is presented directly rather than pumped, so what waits behind a hold still waits
--- for Release.
function METHODS:Preview(payload)
  local S = state(self)
  removeKey(S, lib.PREVIEW)
  takeDownKey(S, lib.PREVIEW)
  if #S.shown >= stackOf(S) then requeueTail(S) end
  if not present(S, { payload = payload, key = lib.PREVIEW, sticky = true }, 1) then reflow(S) end
end

--- The payload at the head and its key, or nil.
function METHODS:Current()
  local head = state(self).shown[1]
  if not head then return nil end
  return head.entry.payload, head.entry.key
end

--- The keys of the toasts on screen, head first (`false` for one shown without a key): a fresh list.
function METHODS:Visible() return shownKeys(state(self)) end

--- The frame carrying the toast on screen under `key`, or nil (a waiting toast has none).
function METHODS:FrameFor(key)
  if key == nil then return nil end
  for _, R in ipairs(state(self).shown) do
    if R.entry.key == key then return R.frame end
  end
  return nil
end

--- The toast's state, for a host's diagnostics report and its suites. `keys` lists the waiting
--- payloads' keys, oldest first (`false` for one queued without a key), so a host can name what
--- waits without keeping a copy of the queue. `shown`, `paused`, `sticky` and `key` are the head's;
--- `visible` counts the toasts on screen and `visibleKeys` names them, head first.
function METHODS:Stats()
  local S = state(self)
  local keys = {}
  for i, entry in ipairs(S.queue) do keys[i] = keyOf(entry) end
  local head = S.shown[1]
  local entry = head and head.entry
  return {
    built = S.pool[1] ~= nil, shown = head ~= nil, waiting = #S.queue, held = S.held == true,
    paused = head ~= nil and head.remaining ~= nil, sticky = entry ~= nil and entry.sticky == true,
    key = entry and entry.key, keys = keys,
    visible = #S.shown, visibleKeys = shownKeys(S), stack = stackOf(S), grow = growOf(S),
  }
end

--- The head's frame; with nothing on screen the first frame built, or nil before the first toast.
function METHODS:Frame()
  local S = state(self)
  local R = S.shown[1] or S.pool[1]
  return R and R.frame
end

--- A new toast. `d.build` is required; every other field is optional (see the API document).
function lib:New(d)   -- luacheck: ignore 212/self
  if type(d) ~= "table" or type(d.build) ~= "function" then
    error(MAJOR .. ": New(d): d.build(frame, payload) is required", 2)
  end
  local inst = {}
  for name, fn in pairs(METHODS) do inst[name] = fn end
  STATE[inst] = { d = d, queue = {}, held = false, shown = {}, pool = {} }
  return inst
end
