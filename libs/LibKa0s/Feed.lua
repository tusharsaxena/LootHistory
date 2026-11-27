-- LibKa0s-Feed-1.0 -- the toast feed: a stack of short-lived rows, the newest at the anchor.
--
-- == WHY THIS EXISTS ==========================================================================
--
-- Ka0s Loot History's toasts (its issue #38) need a feed rather than an alert: up to ten rows on
-- screen at once, the newest at the anchor and the oldest dropped when the feed is full, each row
-- entering, holding and fading on one clock, a repeat of the same key merged into its row in place,
-- and the whole feed frozen while the pointer is over it. LibKa0s-Toast-1.0 is the other shape (the
-- oldest toast at the saved point, one timer per toast), and a feed mode there would be a behavior
-- flag that turns its members around, so this is a major of its own, promoted with one consumer on
-- the owner's ruling of 2026-11-27 (Loot History plan D24, ruling X1 of the #38 design).
-- docs/api/Feed/version-1.1.1.1-docs.md is the full contract and carries that record.
--
-- == THE CONTRACT =============================================================================
--
-- `Feed:New(d)` answers one feed instance. `d.content(spec, payload, key)` is the ONE presentation
-- argument: it fills a reused flat row spec (icon, tint, badge, title, count, prefix, up to three
-- secondary lines, sub, highlight) from the host's payload, or answers `false` to skip it.
-- `d.merge(old, new, key)` optionally reduces two payloads under one key. Everything else is a
-- value or a getter carrying a player's setting, in three grouped tables read once into a snapshot:
-- `d.layout` (where and how big), `d.motion` (how rows move) and `d.style` (how they look over the
-- owner's skin). There is no combat flag and no overflow option: a host holds the feed with Hold
-- and Release, and a full feed drops its oldest row.
--
-- == THE FILES ================================================================================
--
-- Four files, one major. This shell owns the constants, `New`, the instance state and the method
-- table, which it publishes as `lib.__methods`. FeedModel.lua is the pure half (no frames: the
-- snapshot, the layout math, the phase machine, merge and drain) behind `lib.__model`,
-- FeedRow.lua builds and paints rows behind `lib.__row`, and FeedInput.lua owns the pointer, the
-- drag and the strip behind `lib.__input` (peeled from here at 954 lines, on the design's 900-line
-- trigger), reaching back through `lib.__shell`. All three are paired on this file's minor and
-- read at call time, so a newer secondary reaches a feed on the next call.
--
-- == THE ENGINE ===============================================================================
--
-- Nothing is built until the first Push or Preview. Then one container (lib.STRATA, not toplevel,
-- clamped to the screen, no mouse of its own) is anchored by its grow-origin edge at the layout's
-- slot, and rows are its children, each in a level band of its own (LEVELS, below), laid out by
-- an absolute Y. `S.live` is the
-- stack, newest first; `S.leaving` holds rows dropped by the shown cap, by Dismiss or past their
-- fade, which fade out over DROP_FADE where they stood while the stack closes up without them;
-- `S.waiting` holds payloads pushed while the feed is frozen or held, in arrival order. Rows and
-- entries come from the feed's own pools, and each row record carries one reused spec table, so a
-- push allocates nothing once the pools are warm.
--
-- One clock drives every row: an UNPARENTED frame (a hidden UI never stops a countdown) whose
-- OnUpdate is set only while some row needs a tick, and cleared at the end of a tick where none
-- does. A tick is at most MAX_DT long, so a loading-screen hitch never skips a row's life. `content`
-- runs on present, merge, Update, Repaint, RepaintAll, a skin switch and the settle re-read, never
-- from the tick; a raise there reaches geterrorhandler() and skips the payload.
--
-- The freeze is DERIVED, "a live row is hovered and motion.pin is on", recomputed on every enter,
-- leave, drop and click-through change (refreeze), never latched; FeedInput.lua sets the hover. A
-- drop or a free of a hovered row only marks it due (unhover sets S.refreezeDue), because a drop
-- can run inside the drain's own loop; every member that can drop or free one ends with
-- flushFreeze, and the tick refreezes when it is due, so no path leaves a stale freeze behind.
--
-- LEVELS (frame-layering-§3). Each feed's container takes a base of its own, LEVEL_BASE plus
-- LEVEL_STRIDE per feed built (wrapping after LEVEL_FEEDS), so peer feeds stack whole; each row
-- takes a band of its own over it, fixed when the row is built (FeedRow.lua's ROW_BAND).
--
-- Minor 1 (LootHistory#38, tasks S1 to S3 of the Feed build): the skeleton, the engine, the input.
--
-- == DEPENDENCIES =============================================================================
--
-- LibStub and LibKa0s-Core-1.0 minor 20 or newer (ClassColor's stand-in, for the class-colored
-- border and text). Pool, Media, Skin, Widgets and LibSharedMedia-3.0 are resolved at call time
-- behind type checks, with no floor. Nothing here is a protected call, so it works in combat.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 20   -- ClassColor (Core minor 20)
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Feed-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.Feed = MINOR

-- The defaults a descriptor may leave out. Published so a host cites them rather than restating.
lib.STRATA = "HIGH"   -- frame-layering's T5 interactive toast tier
lib.SLOTS = {         -- the nine anchor slots, in reading order; never mutate it
  "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}
lib.MAX_QUEUE = 10      -- payloads waiting while frozen or held, the oldest dropped past it
lib.SHOWN = 5           -- rows on screen at once
lib.SHOWN_MAX = 10      -- the most rows layout.shown may ask for
lib.WIDTH = 320         -- px, the container's and every row's width
lib.ROW_HEIGHT = 48     -- px, the least a row is high
lib.ICON_SIZE = 36      -- px, clamped to the row's inner height
lib.PADDING = 6         -- px inside a row
lib.GAP = 5             -- px between rows
lib.SLOT_INSET = 20     -- px from the screen edge a slot keeps
lib.NUDGE_MAX = 600     -- UIParent units a nudge may move the feed from its slot, either way
lib.ENTER_TIME = 0.25   -- s, the enter
lib.HOLD = 5            -- s at full alpha
lib.FADE_TIME = 1       -- s, the fade
lib.MERGE_WINDOW = 3    -- s a key stays open to a merge after its last push
lib.PULSE_TIME = 0.6    -- s a merge pulses the border
lib.SLIDE_TIME = 0.15   -- s a row takes to reach a new Y when motion.smooth is on
lib.DROP_FADE = 0.2     -- s a dropped or dismissed row fades out over
lib.MAX_DT = 0.1        -- s, the most one tick advances, so a hitch never skips a row's life

local TAG = "Feed"
local LEVEL_BASE = 1     -- the first feed's container level
local LEVEL_STRIDE = 128 -- levels per feed: over FeedRow's ROW_BAND * ROW_BANDS (6 * 20 = 120)
local LEVEL_FEEDS = 16   -- feeds before the bases wrap, kept far under the client's level ceiling
local abs, min, max = math.abs, math.min, math.max
local HUGE = math.huge

-- == the instance =============================================================================

local STATE = setmetatable({}, { __mode = "k" })

local function state(self)
  local S = STATE[self]
  if not S then error(MAJOR .. ": call this on an instance from Feed:New", 3) end
  return S
end

local function model() return lib.__model end
local function rows() return lib.__row end
local function input() return lib.__input end

local function now() return type(GetTime) == "function" and GetTime() or 0 end

local function finite(v) return type(v) == "number" and v == v and v ~= HUGE and v ~= -HUGE end

local function wipe(t)
  for k in pairs(t) do t[k] = nil end
  return t
end

local function debugOut(S, fmt, ...)
  local sink = S.d.debug
  if type(sink) == "function" then pcall(sink, TAG, fmt, ...) end
end

--- A raise from host code: to the client's error handler, and the feed runs on.
local function report(S, err)
  local handler = type(geterrorhandler) == "function" and geterrorhandler() or nil
  if handler then pcall(handler, err) end
  debugOut(S, "host callback failed: %s", tostring(err))
end

--- A host callback under pcall, when it is one.
local function hostCall(S, fn, ...)
  if type(fn) ~= "function" then return end
  local ok, err = pcall(fn, ...)
  if not ok then report(S, err) end
end

--- `e` no longer hovered; the host's onLeave pairs the onEnter it had. The freeze is now due a
--- recompute (refreeze): the member that dropped or freed `e` runs it once its own loop is done.
local function unhover(S, e)
  if not e.hovered then return end
  e.hovered = nil
  S.refreezeDue = true
  if e.row then hostCall(S, S.d.onLeave, e.row.frame, e.payload, e.key) end
end

-- == pools ====================================================================================

local function newEntry(S, key, payload, sticky, preview)
  local e = table.remove(S.entryFree) or {}
  e.key, e.payload, e.sticky, e.preview = key, payload, sticky == true, preview == true
  e.t, e.lastAt, e.pulse = 0, now(), 0
  return e
end

local function unindex(S, e)
  if e.key ~= nil and S.byKey[e.key] == e then S.byKey[e.key] = nil end
end

local function acquireRow(S)
  local R = table.remove(S.free)
  if not R then
    S.rowsBuilt = S.rowsBuilt + 1
    R = rows().Build(S.container, S.rowsBuilt)
    input().Hook(S, R)
  end
  R.frame:EnableMouse(not S.clickThrough)
  return R
end

local function releaseRow(S, R)
  rows().Reset(R)
  R.entry = nil
  S.free[#S.free + 1] = R
end

--- Hand `e` back: its row released and hidden, its key let go, the table wiped into the pool.
local function freeEntry(S, e)
  unhover(S, e)
  unindex(S, e)
  if e.row then releaseRow(S, e.row) end
  S.entryFree[#S.entryFree + 1] = wipe(e)
end

local function removeFrom(list, e)
  for i = #list, 1, -1 do
    if list[i] == e then return table.remove(list, i) end
  end
  return nil
end

-- == the clock ================================================================================

local tick   -- forward: the clock's OnUpdate calls it

local function wake(S)
  if S.awake or not S.clock then return end
  S.awake = true
  S.lastTick = now()
  S.clock:SetScript("OnUpdate", S.onUpdate)
end

local function sleep(S)
  if not S.awake then return end
  S.awake = false
  S.clock:SetScript("OnUpdate", nil)
end

-- == content and paint ========================================================================

--- `spec` emptied, its three secondary-line tables (`lines`, the row's own) kept and emptied too.
local function wipeSpec(spec, lines)
  for i = 1, 3 do wipe(lines[i]) end
  wipe(spec)
  spec.lines = lines
end

--- `d.content` for `e` into its row's spec, under pcall. Answers whether the payload shows.
local function runContent(S, e)
  local spec = e.row.spec
  wipeSpec(spec, e.row.specLines)
  local ok, res = pcall(S.d.content, spec, e.payload, e.key)
  if not ok then
    report(S, res)
    return false
  end
  return res ~= false
end

--- Content, the paint and the placement for `e`'s row. Answers whether it shows.
local function paintEntry(S, e)
  if not runContent(S, e) then return false end
  local R = e.row
  rows().Paint(R, R.spec, S.cfg)
  e.h = rows().Place(R, S.cfg.layout, S.cfg.style)
  e.paintedAt, e.settled = now(), false
  return true
end

-- == layout ===================================================================================

--- `e`'s row at its Y plus the enter's offsets; a SetPoint only when one of the three moved.
local function placeRow(S, e, dx, dy)
  local f = e.row.frame
  dx, dy = dx or 0, dy or 0
  if e.py == e.y and e.pdx == dx and e.pdy == dy then return end
  e.py, e.pdx, e.pdy = e.y, dx, dy
  f:ClearAllPoints()
  if S.cfg.layout.grow == "DOWN" then
    f:SetPoint("TOP", S.container, "TOP", dx, -e.y + dy)
  else
    f:SetPoint("BOTTOM", S.container, "BOTTOM", dx, e.y + dy)
  end
end

--- Every live row's target Y, newest first, and the container's height. A row with no Y yet, or
--- any row while motion.smooth is off, takes its target at once; the rest slide over SLIDE_TIME.
--- While frozen the rows hold their Y.
local function relayout(S)
  local h = model().Layout(S.live, S.cfg.layout)
  S.container:SetHeight(h)
  local smooth = S.cfg.motion.smooth
  for _, e in ipairs(S.live) do
    if e.y == nil or (not smooth and not S.frozen) then e.y = e.targetY end
    e.vy = abs(e.targetY - e.y) / lib.SLIDE_TIME
    placeRow(S, e, e.dx, e.dy)
  end
end

--- One tick of Y for `e`, toward its target at its slide speed.
local function slideY(S, e, dt)
  if S.frozen or e.y == e.targetY or e.targetY == nil then return end
  local step, d = (e.vy or 0) * dt, e.targetY - e.y
  if step <= 0 or abs(d) <= step then e.y = e.targetY else e.y = e.y + (d > 0 and step or -step) end
end

local function anchor(S)
  local L, M = S.cfg.layout, model()
  local c = S.container
  c:SetScale(L.scale)
  c:SetWidth(L.width)
  local slot, ox, oy = M.SlotOffset(L.slot, L.x, L.y)
  c:ClearAllPoints()
  c:SetPoint(M.Origin(L.slot, L.grow), UIParent, slot, ox / L.scale, oy / L.scale)
  input().Dock(S)
end

-- == present, drop, queue =====================================================================

--- Start `e`'s drop: out of the stack at once, fading from its current alpha where it stands.
local function drop(S, e)
  if not removeFrom(S.live, e) then return false end
  unindex(S, e)
  unhover(S, e)
  e.phase, e.t, e.a0 = "drop", 0, e.alpha or 1
  S.leaving[#S.leaving + 1] = e
  return true
end

--- The rows past the shown cap, oldest first, into their drop.
local function capShown(S)
  local shown = S.cfg.layout.shown
  while #S.live > shown do drop(S, S.live[#S.live]) end
end

--- `e`'s first frame state: the alpha and offsets its phase machine answers at t = 0.
local function firstFrame(S, e)
  local alpha, dx, dy = model().Advance(e, S.cfg.motion, 0, false, S.cfg.layout.width)
  e.dx, e.dy = dx, dy
  e.row.frame:SetAlpha(alpha)
  e.shownAlpha = alpha
end

--- `e` on screen at the anchor. Answers false (and frees `e`) when content skips it.
local function present(S, e)
  local R = acquireRow(S)
  e.row, R.entry = R, e
  if not paintEntry(S, e) then
    freeEntry(S, e)
    return false
  end
  e.phase, e.t, e.y = "enter", 0, nil
  table.insert(S.live, 1, e)
  firstFrame(S, e)
  capShown(S)
  relayout(S)
  R.frame:Show()
  wake(S)
  return true
end

--- `e` onto the waiting list, the oldest dropped past maxQueue.
local function queue(S, e)
  e.phase = "wait"
  S.waiting[#S.waiting + 1] = e
  while #S.waiting > S.cfg.maxQueue do freeEntry(S, table.remove(S.waiting, 1)) end
  return "queued"
end

--- The end of a wait: only the newest `shown` waiting entries present, oldest first, so the newest
--- ends at the anchor; the rest are freed.
local function drain(S)
  if S.frozen or S.held or #S.waiting == 0 then return end
  local P, Fr = wipe(S.drainPresent), wipe(S.drainFreed)
  model().Drain(S.waiting, S.cfg.layout.shown, P, Fr)
  for i = 1, #Fr do freeEntry(S, Fr[i]) end
  for i = 1, #P do present(S, P[i]) end
  wipe(P)
  wipe(Fr)
end

--- The freeze, derived: any live row hovered while motion.pin is on. Its end re-lays out and drains.
local function refreeze(S)
  local was, frozen = S.frozen, false
  if S.cfg and S.cfg.motion.pin then
    for _, e in ipairs(S.live) do
      if e.hovered then frozen = true end
    end
  end
  S.frozen, S.refreezeDue = frozen, nil
  if was and not frozen then
    relayout(S)
    drain(S)
    wake(S)
  end
end

--- The freeze recomputed when a drop or a free of a hovered row made it due. Never called from
--- inside drop() itself: a drop runs within the drain's loop and within stepList's.
local function flushFreeze(S)
  if S.refreezeDue then refreeze(S) end
end

--- `e` out of the stack into its drop fade, the freeze recomputed, the stack closed up.
local function dismiss(S, e)
  drop(S, e)
  refreeze(S)
  relayout(S)
  wake(S)
end

-- == merge ====================================================================================

--- A push of `payload` under `key` folded into the entry already there. Answers "merged", false
--- (the merged payload's content skipped it, and its row drops), or nil when nothing could take it.
local function tryMerge(S, key, payload)
  local e = key ~= nil and S.byKey[key] or nil
  if not e then return nil end
  local took, err = model().Merge(e, payload, key, S.cfg.motion, now(), S.d.merge)
  if not took then return nil end
  if err ~= nil then report(S, err) end
  if e.phase == "wait" then return "merged" end
  if not S.frozen and removeFrom(S.live, e) then table.insert(S.live, 1, e) end
  if not paintEntry(S, e) then
    drop(S, e)
    relayout(S)
    wake(S)
    flushFreeze(S)
    return false
  end
  e.shownAlpha = e.alpha or 1
  e.row.frame:SetAlpha(e.shownAlpha)
  relayout(S)
  wake(S)
  return "merged"
end

-- == the tick =================================================================================

local function paused(S, e, m) return S.frozen or (e.hovered == true and not m.pin) end

--- Whether `e` still needs the clock after this tick.
local function busy(S, e, m)
  if e.phase == "drop" or (e.pulse or 0) > 0 or (e.row and e.row.glowOn) then return true end
  if not S.frozen and e.y ~= e.targetY then return true end
  if m.settle > 0 and not e.settled then return true end
  if paused(S, e, m) then return false end
  return e.phase == "enter" or e.phase == "fade" or (e.phase == "hold" and not e.sticky)
end

--- The settle re-read: one more content call at paintedAt + settle, for state that lags its event.
local function settle(S, e, m, t)
  if m.settle <= 0 or e.settled or not e.paintedAt or t < e.paintedAt + m.settle then return end
  e.settled = true
  if not runContent(S, e) then return drop(S, e) end
  local R = e.row
  rows().Paint(R, R.spec, S.cfg)
  e.h = rows().Place(R, S.cfg.layout, S.cfg.style)
  S.dirty = true
end

--- Advance `e` by `dt` and draw what changed. Answers true when its life is over.
local function stepEntry(S, e, dt, m, clock)
  local alpha, dx, dy, bar, done = model().Advance(e, m, dt, paused(S, e, m), S.cfg.layout.width)
  if done then return true end
  local R = e.row
  if alpha ~= e.shownAlpha then
    R.frame:SetAlpha(alpha)
    e.shownAlpha = alpha
  end
  if e.phase ~= "drop" then slideY(S, e, dt) end
  e.dx, e.dy = dx, dy
  placeRow(S, e, dx, dy)
  rows().Bar(R, m.timerBar and bar or nil)   -- every tick: a Refresh that turned it off hides it
  rows().Animate(R, e.pulse, clock)
  return false
end

--- Step every entry of `list`; the finished ones are freed. Answers whether any still needs a tick
--- and whether any left the list.
local function stepList(S, list, dt, m, clock, t)
  local need, gone, i = false, false, 1
  while i <= #list do
    local e = list[i]
    if stepEntry(S, e, dt, m, clock) then
      table.remove(list, i)
      freeEntry(S, e)
      gone = true
    else
      if e.phase ~= "drop" then settle(S, e, m, t) end
      if list[i] == e then
        need = need or busy(S, e, m)
        i = i + 1
      else
        gone = true
      end
    end
  end
  return need, gone
end

--- Whether a live row still slides toward its target Y.
local function moving(S)
  if S.frozen then return false end
  for _, e in ipairs(S.live) do
    if e.y ~= e.targetY then return true end
  end
  return false
end

tick = function(S, dt)
  if not finite(dt) or dt < 0 then dt = 0 end
  local m, t = S.cfg.motion, now()
  S.clockT = (S.clockT or 0) + dt
  S.dirty = false
  local needLive, goneLive = stepList(S, S.live, dt, m, S.clockT, t)
  local needLeaving = stepList(S, S.leaving, dt, m, S.clockT, t)
  if goneLive or S.dirty or S.refreezeDue then
    refreeze(S)
    relayout(S)
    needLive = needLive or moving(S)
  end
  if not (needLive or needLeaving) then sleep(S) end
end

-- == the build ================================================================================

local function snapshot(S)
  S.cfg = model().Snapshot(S.d)
  S.cfg.owner = S.d.owner
end

local function repaintAll(S)
  if not S.built then return end
  local R = rows()
  for i = #S.live, 1, -1 do
    local e = S.live[i]
    if paintEntry(S, e) then e.row.frame:SetAlpha(e.alpha or 1) else drop(S, e) end
  end
  for _, e in ipairs(S.leaving) do R.Restyle(e.row, S.cfg) end
  relayout(S)
  wake(S)
  flushFreeze(S)
end

--- The container, the clock and the skin subscription, once, on the first Push or Preview.
local function ensure(S)
  if S.built then return end
  snapshot(S)
  local c = CreateFrame("Frame", type(S.d.name) == "string" and S.d.name or nil, UIParent)
  c:SetFrameStrata(lib.STRATA)
  c:SetToplevel(false)
  c:SetClampedToScreen(true)
  c:EnableMouse(false)
  c:SetHeight(1)
  c:SetFrameLevel(LEVEL_BASE + LEVEL_STRIDE * ((lib.__feedsBuilt or 0) % LEVEL_FEEDS))
  lib.__feedsBuilt = (lib.__feedsBuilt or 0) + 1
  S.container = c
  S.clock = CreateFrame("Frame")   -- no parent: a hidden UI does not stop the countdown
  S.onUpdate = function()
    local t = now()
    local dt = min(max(0, t - (S.lastTick or t)), lib.MAX_DT)
    S.lastTick = t
    tick(S, dt)
  end
  S.built = true
  anchor(S)
  c:Show()
  local skin = type(core.__SkinFacade) == "function" and core.__SkinFacade(S.d.owner)
  if skin and type(skin.OnLooksChanged) == "function" then
    skin.OnLooksChanged(function() repaintAll(S) end)
  end
  input().Strip(S)
  debugOut(S, "feed built")
end

-- == the members ==============================================================================

local METHODS = {}

--- Show `payload` under `key` (nil never merges). Answers "new", "merged", "queued" or false.
function METHODS:Push(key, payload, opts)
  local S = state(self)
  ensure(S)
  local merged = tryMerge(S, key, payload)
  if merged ~= nil then return merged end
  local e = newEntry(S, key, payload, type(opts) == "table" and opts.sticky)
  local prev = key ~= nil and S.byKey[key] or nil   -- a live row past its merge window keeps running
  if key ~= nil then S.byKey[key] = e end
  if S.frozen or S.held then return queue(S, e) end
  local shown = present(S, e)
  flushFreeze(S)   -- the shown cap may have dropped a hovered row
  if shown then return "new" end
  if prev and key ~= nil and S.byKey[key] == nil then S.byKey[key] = prev end
  return false
end

--- The live or waiting payload under `key`, or nil.
function METHODS:Get(key)
  local S = state(self)
  local e = key ~= nil and S.byKey[key]
  if e then return e.payload end
  return nil
end

--- Replace the payload under `key` and repaint it in place: no hold restart, no pulse, no move.
--- Answers whether an entry took it. A live row whose content now skips it drops.
function METHODS:Update(key, payload)
  local S = state(self)
  local e = key ~= nil and S.byKey[key]
  if not e then return false end
  e.payload = payload
  if e.phase == "wait" then return true end
  if not paintEntry(S, e) then drop(S, e) end
  relayout(S)
  wake(S)
  flushFreeze(S)
  return true
end

--- Re-run `content` for the row under `key`. Answers whether there was one on screen.
function METHODS:Repaint(key)
  local S = state(self)
  local e = key ~= nil and S.byKey[key]
  if not (e and e.row) then return false end
  if not paintEntry(S, e) then drop(S, e) end
  relayout(S)
  wake(S)
  flushFreeze(S)
  return true
end

--- Re-run `content` and the style paint for every live row.
function METHODS:RepaintAll()
  repaintAll(state(self))
end

--- Start the drop fade of the row under `key`; a waiting payload under it is let go. Answers
--- whether there was one.
function METHODS:Dismiss(key)
  local S = state(self)
  local e = key ~= nil and S.byKey[key]
  if not e then return false end
  if e.phase == "wait" then
    removeFrom(S.waiting, e)
    freeEntry(S, e)
    return true
  end
  dismiss(S, e)
  return true
end

local function freeAll(S, list)
  for i = #list, 1, -1 do
    local e = list[i]
    list[i] = nil
    freeEntry(S, e)
  end
end

--- The stand-down: every row released and hidden, nothing waits, the clock disarmed, hover and
--- freeze cleared, the handle and the strip hidden, locked again. The pools are kept.
function METHODS:Clear()
  local S = state(self)
  freeAll(S, S.live)
  freeAll(S, S.leaving)
  freeAll(S, S.waiting)
  wipe(S.byKey)
  sleep(S)
  S.frozen, S.stripKind, S.refreezeDue = false, nil, nil
  input().Lock(S)
  if S.container then S.container:SetHeight(1) end
end

--- New payloads wait (merging there) until Release; live rows keep running.
function METHODS:Hold()
  state(self).held = true
end

--- End a Hold and drain the waiting list.
function METHODS:Release()
  local S = state(self)
  S.held = false
  if S.built then drain(S) end
end

--- Re-read every getter, re-snapshot layout, motion and style, re-anchor and repaint.
function METHODS:Refresh()
  local S = state(self)
  if not S.built then return end
  snapshot(S)
  anchor(S)
  capShown(S)
  repaintAll(S)
  for _, e in ipairs(S.live) do e.py = nil end
  relayout(S)
  refreeze(S)   -- motion.pin may have changed, and the cap may have dropped a hovered row
end

--- Drop only the preview rows (at once: a preview replaced is not a preview fading).
function METHODS:ClearPreview()
  local S = state(self)
  local any = false
  for _, list in ipairs({ S.live, S.leaving }) do
    for i = #list, 1, -1 do
      local e = list[i]
      if e.preview then
        table.remove(list, i)
        freeEntry(S, e)
        any = true
      end
    end
  end
  if not any then return end
  relayout(S)
  wake(S)
  flushFreeze(S)   -- a hovered preview row freed here gets no OnLeave of its own
end

--- Push each `{ key, payload }` of `list` sticky, as preview rows, through the same present and
--- paint path; neither a hold nor a freeze queues them, and they take no merge. Replaces the
--- previous preview rows. Answers how many showed.
function METHODS:Preview(list)
  local S = state(self)
  ensure(S)
  self:ClearPreview()
  if type(list) ~= "table" then return 0 end
  for _, item in ipairs(list) do
    if type(item) == "table" then present(S, newEntry(S, item[1], item[2], true, true)) end
  end
  flushFreeze(S)   -- the shown cap may have dropped a hovered row
  local n = 0
  for _, e in ipairs(S.live) do
    if e.preview then n = n + 1 end
  end
  return n
end

--- Lock (true) or unlock (false) the feed for dragging. Answers whether it is now locked: an
--- unlock is refused in combat and without LibKa0s-Widgets-1.0, and answers true.
function METHODS:SetLocked(locked)
  local S = state(self)
  if locked == false then return input().Unlock(S) end
  input().Lock(S)
  return true
end

function METHODS:IsLocked()
  return state(self).locked ~= false
end

--- Let the pointer through every row (true), or take it again (false). On, every hover and the
--- freeze end (the client sends no OnLeave to a row whose mouse is off) and the waiting list drains.
function METHODS:SetClickThrough(on)
  input().ClickThrough(state(self), on == true)
end

--- Dock the "test" or "sim" strip with the host's `text` on the stack's top edge through Widgets'
--- HUD docking (flipped under it near the screen's top, clear of the drag handle), or hide it with
--- nil.
function METHODS:SetStrip(kind, text)
  local S = state(self)
  S.stripKind = (kind == "test" or kind == "sim") and kind or nil
  S.stripText = type(text) == "string" and text or ""
  input().Strip(S)
end

--- The keys on screen, newest first (`false` for a key-less row). A new table per call.
function METHODS:Visible()
  local S = state(self)
  local out = {}
  for i, e in ipairs(S.live) do
    if e.key == nil then out[i] = false else out[i] = e.key end
  end
  return out
end

--- The feed's state, every field always present. `shown` is the layout's cap once built.
function METHODS:Stats()
  local S = state(self)
  return {
    live = #S.live, waiting = #S.waiting, dropping = #S.leaving, frozen = S.frozen == true,
    held = S.held == true, locked = S.locked ~= false, clickThrough = S.clickThrough == true,
    awake = S.awake == true, shown = S.cfg and S.cfg.layout.shown or 0, built = S.built == true,
  }
end

--- The container once built, else nil.
function METHODS:Frame()
  return state(self).container
end

--- Internal test seam, not contract: one tick of `dt` seconds, armed or not.
function METHODS:__Step(dt)
  local S = state(self)
  if not S.built then return end
  S.lastTick = now()
  tick(S, dt)
end

--- A new feed. `d.content` is required; every other field is optional (see the API document).
function lib:New(d)   -- luacheck: ignore 212/self
  if type(d) ~= "table" or type(d.content) ~= "function" then
    error(MAJOR .. ": New(d): d.content(spec, payload, key) is required", 2)
  end
  local inst = {}
  for name, fn in pairs(METHODS) do inst[name] = fn end
  STATE[inst] = {
    d = d, live = {}, leaving = {}, waiting = {}, rows = {}, free = {}, entryFree = {}, byKey = {},
    drainPresent = {}, drainFreed = {}, strips = {}, rowsBuilt = 0,
    frozen = false, held = false, locked = true, clickThrough = false, awake = false, built = false,
  }
  return inst
end

-- The shell's own steps, for FeedInput.lua and nobody else, read there at call time.
lib.__shell = {
  anchor = anchor, ensure = ensure, refreeze = refreeze, wake = wake, drain = drain,
  dismiss = dismiss, unhover = unhover, hostCall = hostCall,
}

-- The method table every New copies, for this major's paired files and nobody else. Private: a
-- host calls methods on an instance.
lib.__methods = METHODS
