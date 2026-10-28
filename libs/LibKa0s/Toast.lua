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
-- to replace another calls Remove first. docs/api/Toast/version-1-docs.md is the full contract.
--
-- ── WHAT THE SHELL DOES ──────────────────────────────────────────────────────────────────────
--
-- * One toast at a time. `Show` queues; the next shows when the current one goes. Past the cap
--   (d.maxQueue, default MAX_QUEUE) the oldest waiting payload is dropped.
-- * Lifetime. A toast closes after its duration; the countdown pauses while the pointer is over the
--   toast (or over a control the host attached) and resumes with the time it had left, never less
--   than a second. It also closes on its close mark or on a right-click anywhere on it. A sticky
--   toast (Show's `opts.sticky`, and every Preview) has no countdown.
-- * Placement. Draggable with the left button only while d.draggable() answers true (the host's
--   test mode). The position is handed to d.setPosition in UIParent's units and read back through
--   d.getPosition, so a scale change grows or shrinks the toast about the saved anchor and never
--   rewrites it.
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

local MAJOR, MINOR = "LibKa0s-Toast-1.0", 1
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

local TAG = "TOAST"
local MIN_RESUME = 1    -- a resumed countdown never has less than this left
local CLOSE_INSET = 4   -- the close mark's offset from the top-right corner
local WATCH_POLL = 0.2  -- seconds between checks that the pointer left the toast (watchLeave)

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

-- ── the timer ────────────────────────────────────────────────────────────────────────────────

local function cancelTimer(S)
  if S.timer and S.timer.Cancel then S.timer:Cancel() end
  S.timer, S.dueAt = nil, nil
end

local dismiss   -- forward: the timer and the frame's scripts close through it

local function startTimer(S, seconds)
  cancelTimer(S)
  S.dueAt = GetTime() + seconds
  local handle
  handle = C_Timer.NewTimer(seconds, function()
    if S.timer ~= handle then return end   -- a timer replaced before it fired
    S.timer, S.dueAt = nil, nil
    debugOut(S, "toast expired")
    dismiss(S)
  end)
  S.timer = handle
end

local function cancelWatch(S)
  if S.watch and S.watch.Cancel then S.watch:Cancel() end
  S.watch = nil
end

local function pause(S)
  cancelWatch(S)   -- the control the pointer entered now owns the resume
  if not (S.current and S.dueAt) then return end
  S.remaining = math.max(S.dueAt - GetTime(), 0)
  cancelTimer(S)
end

local function resume(S)
  cancelWatch(S)
  if not (S.current and S.remaining) then return end
  local left = S.remaining
  S.remaining = nil
  startTimer(S, math.max(left, MIN_RESUME))
end

--- The pointer left onto something still over the toast (a child control). The countdown must not
--- rely on that child's OnLeave hook to resume it: a library-painted child's scripts can be SetScript
--- again under it (Core minor 13's close mark for a skin owner, on every skin switch), which drops
--- the hook. So poll until the pointer is off the toast, then resume.
local function watchLeave(S)
  cancelWatch(S)
  if not (S.current and S.remaining) then return end
  local handle
  handle = C_Timer.NewTimer(WATCH_POLL, function()
    if S.watch ~= handle then return end
    S.watch = nil
    local f = S.frame
    if f and f.IsMouseOver and f:IsMouseOver() == true then watchLeave(S) else resume(S) end
  end)
  S.watch = handle
end

-- ── placement ────────────────────────────────────────────────────────────────────────────────

--- The scale first, then the saved point in the toast's own units at that scale, so the anchor the
--- player placed stays where it is whatever the scale.
local function applyLayout(S)
  local f = S.frame
  if not f then return end
  local s = scaleOf(S)
  local pt = validPoint(read(S.d.getPosition)) or validPoint(S.d.defaultPosition) or lib.POINT
  f:SetScale(s)
  f:ClearAllPoints()
  f:SetPoint(pt[1], UIParent, pt[2] or pt[1], (tonumber(pt[3]) or 0) / s, (tonumber(pt[4]) or 0) / s)
end

--- GetPoint answers in the toast's (scaled) units; the host is handed UIParent's.
local function savePosition(S)
  local f = S.frame
  local point, _, relativePoint, x, y = f:GetPoint(1)
  if type(point) ~= "string" or type(S.d.setPosition) ~= "function" then return end
  local s = tonumber(f:GetScale()) or 1
  S.d.setPosition({ point, type(relativePoint) == "string" and relativePoint or point,
    (tonumber(x) or 0) * s, (tonumber(y) or 0) * s })
end

-- ── the frame ────────────────────────────────────────────────────────────────────────────────

local function onDragStart(S)
  if read(S.d.draggable) ~= true then return end
  S.moving = true
  S.frame:StartMoving()
end

local function onDragStop(S)
  if not S.moving then return end
  S.moving = false
  S.frame:StopMovingOrSizing()
  savePosition(S)
end

--- Hover pauses the countdown, leaving resumes it, and a right-click closes: on the frame and on
--- every control the host attaches, so a pointer moving from the frame onto a button keeps it held.
--- Leaving onto something still over the toast watches for the pointer to go (watchLeave).
local function hookPointer(S, widget, set)
  local wire = set and widget.SetScript or widget.HookScript
  wire(widget, "OnEnter", function() pause(S) end)
  wire(widget, "OnLeave", function()
    local f = S.frame
    if f and f.IsMouseOver and f:IsMouseOver() == true then watchLeave(S) else resume(S) end
  end)
  wire(widget, "OnMouseUp", function(_, button)
    if button == "RightButton" then dismiss(S) end
  end)
end

local function decorate(S, f)
  if type(core.ApplySkin) == "function" then core.ApplySkin(f, nil, S.d.owner) end
  if type(core.MakeCloseButton) ~= "function" then return end
  local close = core.MakeCloseButton(f, function() dismiss(S) end, S.d.owner)
  if not close then return end
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -CLOSE_INSET, -CLOSE_INSET)
  hookPointer(S, close, false)
  f.close = close
end

local function build(S)
  local f = CreateFrame("Frame", S.d.name, UIParent, "BackdropTemplate")
  S.frame = f
  f:Hide()
  f:SetFrameStrata(lib.STRATA)
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetSize(positive(S.d.width) or lib.WIDTH, positive(S.d.height) or lib.HEIGHT)
  f:SetScript("OnDragStart", function() onDragStart(S) end)
  f:SetScript("OnDragStop", function() onDragStop(S) end)
  hookPointer(S, f, true)
  decorate(S, f)
  applyLayout(S)
  return f
end

local function ensureFrame(S) return S.frame or build(S) end

-- ── the queue ────────────────────────────────────────────────────────────────────────────────

local function enqueue(S, entry, front)
  local q = S.queue
  if front then table.insert(q, 1, entry) else q[#q + 1] = entry end
  local cap = math.max(1, math.floor(positive(S.d.maxQueue) or lib.MAX_QUEUE))
  while #q > cap do table.remove(q, front and #q or 1) end
end

local function playSound(S)
  if read(S.d.sound) ~= true or type(PlaySound) ~= "function" then return end
  local kit = type(SOUNDKIT) == "table" and SOUNDKIT or {}
  local id = read(S.d.soundKit)
  if type(id) ~= "number" then id = kit.UI_EPICLOOT_TOAST or kit.RAID_WARNING end
  if type(id) == "number" then PlaySound(id, "Master") end
end

--- The builder, under pcall: a raise costs this payload, reported through the error handler, and
--- the next one still shows. Answers whether the payload is drawn.
local function draw(S, entry)
  local f = ensureFrame(S)
  local ok, w, h = pcall(S.d.build, f, entry.payload)
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

local function present(S, entry)
  if not draw(S, entry) then return false end
  S.current, S.remaining = entry, nil
  applyLayout(S)
  S.frame:Show()
  playSound(S)
  if not entry.sticky then startTimer(S, durationOf(S)) end
  debugOut(S, "toast shown (%d waiting)", #S.queue)
  return true
end

local function pump(S)
  if S.current or S.held then return end
  while #S.queue > 0 do
    if present(S, table.remove(S.queue, 1)) then return end
  end
end

--- Take the toast on screen down, without showing the next. Answers the entry it held.
local function takeDown(S)
  cancelTimer(S)
  cancelWatch(S)
  local entry = S.current
  if S.moving then S.frame:StopMovingOrSizing() end
  S.current, S.remaining, S.moving = nil, nil, false
  if S.frame then S.frame:Hide() end
  return entry
end

dismiss = function(S)
  if not takeDown(S) then return end
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

-- ── the instance ─────────────────────────────────────────────────────────────────────────────

local STATE = setmetatable({}, { __mode = "k" })

local function state(self)
  local S = STATE[self]
  if not S then error(MAJOR .. ": call this on an instance from Toast:New", 3) end
  return S
end

local METHODS = {}

--- Queue `payload`; it shows now when nothing is on screen and the toast is not held.
--- opts.key names it for Remove; opts.sticky gives it no countdown. Answers true.
function METHODS:Show(payload, opts)
  local S = state(self)
  opts = type(opts) == "table" and opts or {}
  enqueue(S, { payload = payload, key = opts.key, sticky = opts.sticky == true })
  debugOut(S, "toast queued (%d waiting)%s", #S.queue, S.held and ", held" or "")
  pump(S)
  return true
end

--- Close the toast on screen; the next one shows.
function METHODS:Dismiss() dismiss(state(self)) end

--- Drop every waiting payload queued under `key`, and close the one on screen when it is `key`'s.
--- Answers how many it let go.
function METHODS:Remove(key)
  local S = state(self)
  if key == nil then return 0 end
  local n = removeKey(S, key)
  if S.current and S.current.key == key then
    n = n + 1
    dismiss(S)
  end
  return n
end

--- The stand-down: the toast on screen goes, nothing waits, and a hold is released without showing
--- anything.
function METHODS:Clear()
  local S = state(self)
  S.queue, S.held = {}, false
  takeDown(S)
end

--- Stop showing: a toast on screen goes back to the head of the queue, with its full time again,
--- and nothing shows until Release. With `keepShown` the toast on screen stays up and runs its
--- course; only what would show after it waits (a host's hold set while a toast is already up).
function METHODS:Hold(keepShown)
  local S = state(self)
  S.held = true
  if keepShown == true then return end
  local entry = takeDown(S)
  if entry then enqueue(S, entry, true) end
end

--- Undo Hold: what waits shows.
function METHODS:Release()
  local S = state(self)
  S.held = false
  pump(S)
end

--- The countdown stops, keeping the time it had left (the frame's OnEnter calls this).
function METHODS:Pause() pause(state(self)) end

--- The countdown resumes with the time it had left (the frame's OnLeave calls this).
function METHODS:Resume() resume(state(self)) end

--- Wire a control the builder made: hovering it holds the countdown, and a right-click on it closes
--- the toast. Its own scripts are kept (HookScript).
function METHODS:Attach(widget)
  local S = state(self)
  if type(widget) == "table" and type(widget.HookScript) == "function" then hookPointer(S, widget, false) end
end

--- Re-read the scale and the saved position (after the host's scale row or a profile switch).
function METHODS:Refresh() applyLayout(state(self)) end

--- Forget the saved position (d.setPosition(nil)): the toast goes back to d.defaultPosition.
function METHODS:ResetPosition()
  local S = state(self)
  if type(S.d.setPosition) == "function" then S.d.setPosition(nil) end
  applyLayout(S)
end

--- Show `payload` now, sticky, so it can be seen and placed (the host's test mode): a toast on
--- screen goes back to the head of the queue, and a previous preview is replaced. It closes like any
--- toast, or through Remove(Toast.PREVIEW). It shows past a Hold without releasing it: the preview
--- is presented directly rather than pumped, so what waits behind a hold still waits for Release.
function METHODS:Preview(payload)
  local S = state(self)
  removeKey(S, lib.PREVIEW)
  local entry = takeDown(S)
  if entry and entry.key ~= lib.PREVIEW then enqueue(S, entry, true) end
  if not present(S, { payload = payload, key = lib.PREVIEW, sticky = true }) then pump(S) end
end

--- The payload on screen and its key, or nil.
function METHODS:Current()
  local S = state(self)
  if not S.current then return nil end
  return S.current.payload, S.current.key
end

--- The toast's state, for a host's diagnostics report and its suites. `keys` lists the waiting
--- payloads' keys, oldest first (`false` for one queued without a key), so a host can name what
--- waits without keeping a copy of the queue.
function METHODS:Stats()
  local S = state(self)
  local keys = {}
  for i, entry in ipairs(S.queue) do
    if entry.key == nil then keys[i] = false else keys[i] = entry.key end
  end
  return {
    built = S.frame ~= nil, shown = S.current ~= nil, waiting = #S.queue, held = S.held == true,
    paused = S.remaining ~= nil, sticky = S.current ~= nil and S.current.sticky == true,
    key = S.current and S.current.key, keys = keys,
  }
end

--- The frame, or nil before the first toast.
function METHODS:Frame() return state(self).frame end

--- A new toast. `d.build` is required; every other field is optional (see the API document).
function lib:New(d)   -- luacheck: ignore 212/self
  if type(d) ~= "table" or type(d.build) ~= "function" then
    error(MAJOR .. ": New(d): d.build(frame, payload) is required", 2)
  end
  local inst = {}
  for name, fn in pairs(METHODS) do inst[name] = fn end
  STATE[inst] = { d = d, queue = {}, held = false }
  return inst
end
