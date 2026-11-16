-- LibKa0s-Options-1.0 -- the skin picker's queue: the one window across every Ka0s addon, the
-- library-level lib.__pickerQueue, and the end-of-combat wait before the next owner shows.
--
-- Peeled out of OptionsSkinPicker.lua at its minor 12, unchanged (LK-P1 of Ka0sAddonsCommonTasks
-- docs/2026-11-16-LIBKA0S_ISSUES_75_PLUS), on the seam CLAUDE.md's band census named for that file,
-- the queue. The history is that file's header.
--
-- WHO CALLS IN. OptionsSkinPicker.lua reads lib.__pickerQueueKit (queue, admit, inLockdown,
-- advance, dismissWaiting, dropWaiting) at call time, never caching it, so the newest copy of this
-- file is every picker's. OptionsAppearance.lua's Skin tab calls lib.__pickerSettle and
-- lib.__pickerRebase around a write. Nothing else crosses the cut.
--
-- A file of the Options major, paired on the shell's minor with the same multi-file idiom as
-- OptionsIds.lua.
--
-- ONE WINDOW ACROSS ADDONS. LibStub keeps one copy of this major for the whole client, so its library
-- table is every Ka0s addon's, and lib.__pickerQueue (created if absent, adopted by a newer minor)
-- holds the picker shown now (`current`) and the owners waiting (`waiting`, one entry per owner).
-- While one owner's picker is up, O.SkinPicker for another owner, on any instance, queues it (a
-- repeat call refreshes its spec) and shows nothing; when the shown picker closes, the next one
-- waiting shows. O.HideSkinPicker() on an instance takes its queued owners out of the queue (they were
-- never seen, so no onClose) and hides its window when it is the one up.
--
-- NEVER SHOWN MID-COMBAT BY THE QUEUE. A close under InCombatLockdown() shows no next owner: the
-- queue waits out combat on OptionsRegistry.lua's end-of-combat park (lib.__parkRegistration, its
-- one PLAYER_REGEN_ENABLED frame, registered only while something is parked) and advances when combat
-- ends. While it waits, O.SkinPicker for any other owner queues behind it too. The predicate is the
-- client's InCombatLockdown() alone, as the park's own is: the page lock's flag is cleared by another
-- frame's handler for the same event, which may run after the park's replay. A copy without the park
-- shows the next owner at once, as before.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- Minor 1: the queue's section, moved here unchanged from OptionsSkinPicker.lua (its minor 12).
local QUEUE_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own: see OptionsScroll.lua.
if lib.__pickerQueueMinor and lib.__pickerQueueMinor >= QUEUE_MINOR
  and lib.__pickerQueueShellMinor == lib.MINOR then return end
lib.__pickerQueueMinor      = QUEUE_MINOR
lib.__pickerQueueShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsSkinPickerQueue = QUEUE_MINOR

local function report(err)
  local h = type(geterrorhandler) == "function" and geterrorhandler()
  if type(h) == "function" then h(err) end
end

--- Call `fn(...)` under pcall when it is a function, reporting a raise.
local function safeCall(fn, ...)
  if type(fn) ~= "function" then return end
  local ok, err = pcall(fn, ...)
  if not ok then report(err) end
end

-- ── the queue (library level) ────────────────────────────────────────────────────────────────
--
-- `current` is `{ owner, inst, frame }`, the picker shown now; `waiting` the owners queued behind it,
-- oldest first, each `{ owner, inst, spec, show }` (`show(spec)` shows it on its own instance);
-- `parked` is true while the queue waits out combat. Read through queue() at call time, never
-- cached: a newer minor adopts the same table.

local function queue()
  local q = lib.__pickerQueue
  if type(q) ~= "table" then
    q = {}
    lib.__pickerQueue = q
  end
  if type(q.waiting) ~= "table" then q.waiting = {} end
  return q
end
queue()

--- The Skin tab is about to write `owner`, and the write reads the applied state: the shown picker's
--- previews go back first (THE ROWS). Internal.
function lib.__pickerSettle(owner)
  local cur = queue().current
  if cur and cur.owner == owner and cur.settle then cur.settle() end
end

--- The Skin tab wrote `owner`: the shown picker measures from what it stored. Internal.
function lib.__pickerRebase(owner)
  local cur = queue().current
  if cur and cur.owner == owner and cur.rebase then cur.rebase() end
end

--- Queue `entry` behind the picker shown now: one entry per owner, a repeat refreshing it in place.
local function enqueue(entry)
  local q = queue()
  for _, e in ipairs(q.waiting) do
    if e.owner == entry.owner then
      e.inst, e.spec, e.show = entry.inst, entry.spec, entry.show
      return
    end
  end
  q.waiting[#q.waiting + 1] = entry
end

--- The client's lockdown, the park's own predicate (see the header: not the page lock's flag).
local function inLockdown()
  return (InCombatLockdown ~= nil and InCombatLockdown()) and true or false
end

local advance

--- Park the queue until combat ends (OptionsRegistry.lua's lib.__parkRegistration), once however
--- many closes ask. The replay advances only when nothing came up meanwhile. Answers whether the
--- queue is parked; false without the park, and the caller then shows at once.
local function waitOutCombat(q)
  if q.parked then return true end
  if type(lib.__parkRegistration) ~= "function" then return false end
  local ok = lib.__parkRegistration(function()
    local now = queue()
    now.parked = nil
    if not now.current then advance() end
  end)
  q.parked = ok and true or nil
  return ok and true or false
end

--- The shown picker closed: the next owner waiting shows, skipping one that can no longer; in combat
--- the queue waits for its end instead.
function advance()
  local q = queue()
  q.current = nil
  if #q.waiting > 0 and inLockdown() and waitOutCombat(q) then return end
  while not q.current and #q.waiting > 0 do
    local e = table.remove(q.waiting, 1)
    safeCall(e.show, e.spec)
  end
end

--- Apply to all: every queued picker is dismissed, its onClose run, none shown.
local function dismissWaiting()
  local q = queue()
  local list = q.waiting
  q.waiting = {}
  for _, e in ipairs(list) do safeCall(e.spec and e.spec.onClose) end
end

--- O.HideSkinPicker: the instance's queued owners leave the queue, never seen, so no onClose.
local function dropWaiting(inst)
  local list = queue().waiting
  for i = #list, 1, -1 do
    if list[i].inst == inst then table.remove(list, i) end
  end
end

--- O.SkinPicker's routing for `owner` on instance `inst`: while another owner's picker is up, or
--- while the queue waits out combat, `owner` is queued (`show(spec)` shows it later) and this
--- answers "queued"; for the owner already up on another instance, "up" and that window; else nil,
--- and the caller shows it on `inst`.
local function admit(owner, inst, spec, show)
  local q = queue()
  local cur = q.current
  if (cur and cur.owner ~= owner) or (not cur and q.parked) then
    enqueue({ owner = owner, inst = inst, spec = spec, show = show })
    return "queued"
  end
  if cur and cur.inst ~= inst then return "up", cur.frame end
  return nil
end

-- What OptionsSkinPicker.lua reads at call time.
lib.__pickerQueueKit = {
  queue = queue, admit = admit, inLockdown = inLockdown, advance = advance,
  dismissWaiting = dismissWaiting, dropWaiting = dropWaiting,
}
