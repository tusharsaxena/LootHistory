-- LibKa0s-Pool-1.0 — the free/active widget pool this collection kept rewriting.
--
-- ── WHY THIS EXISTS, AND IT IS NOT LINE COUNT ────────────────────────────────────────────────
--
-- Four copies of this pool shipped across two addons. Three were correct. The fourth —
-- LootHistory's chart pool — hid its active objects and dropped them: nothing was ever returned to
-- the free list, so `acquire` fell through to `factory()` on every call, and since that addon's
-- layout pass releases thirty-five pools at the top of every re-render, each filter change
-- allocated a fresh frame per chart element. Frames are never destroyed in WoW, so they stayed for
-- the session.
--
-- None of that is visible from outside. The charts draw correctly, the suite stays green, and the
-- only symptom is a client that gets heavier the longer a window is used. Two addons wrote the
-- same eleven lines and one of them got the second half wrong — which is the argument for a
-- library in its purest form.
--
-- ── WHAT A POOL IS HERE ──────────────────────────────────────────────────────────────────────
--
-- A plain table with two arrays and NO METATABLE:
--
--     { free = { … }, active = { … } }
--
-- Plain on purpose. A host holding a pool built before a minor upgrade keeps working, a host
-- without this library writes a nine-line local copy rather than a redesign, and a pool is
-- inspectable in a debugger without knowing anything about this file.
--
-- ── WHAT IT DELIBERATELY IS NOT ──────────────────────────────────────────────────────────────
--
-- Not Blizzard's `CreateFramePool`: that one owns frame creation, resetter functions and a
-- template, and every caller here already has its own factory closure building a fully-wired
-- widget. Not a per-object `Release`: no consumer releases one object at a time, and a member
-- nobody calls is a member nobody tests.
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on no addon framework. No Core member is called;
-- the gate keeps the payload's presence a single question.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Pool-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.Pool = MINOR

--- A fresh, empty pool.
---
--- @return table  { free = {}, active = {} }
function lib.New()
  return { free = {}, active = {} }
end

--- Take an object from the pool, building one only if the free list is empty.
---
--- The returned object is SHOWN. Every consumer wants that — a pooled widget is acquired in order
--- to be drawn — and a caller that wants it hidden hides it, which is one line at one call site
--- rather than a flag on every call.
---
--- @param pool table
--- @param factory function  called with no arguments; must return an object with :Show()/:Hide()
--- @return table  the acquired object
function lib.Acquire(pool, factory)
  local o = table.remove(pool.free)
  if not o then o = factory() end
  pool.active[#pool.active + 1] = o
  o:Show()
  return o
end

--- Hide every active object and RETURN IT TO THE FREE LIST.
---
--- The second half is the whole module. A release that only hides is an allocator wearing a pool's
--- name, and that is not hypothetical — it shipped.
---
--- `before` is optional and runs on each object while it is still shown, which is what makes one
--- function cover a NESTED pool: a host releasing a pool of list panels releases each panel's own
--- row pool first, as
---
---     Pool.ReleaseAll(panelPool, function(p) Pool.ReleaseAll(p._rows) end)
---
--- Without the hook that host needs a second library member, and the two drift the way the four
--- hand-rolled copies did.
---
--- @param pool table
--- @param before function|nil  called as before(object) before the object is hidden
function lib.ReleaseAll(pool, before)
  local active = pool.active
  for i = 1, #active do
    local o = active[i]
    if before then before(o) end
    o:Hide()
    pool.free[#pool.free + 1] = o
  end
  for i = #active, 1, -1 do active[i] = nil end
end

--- How many objects are parked and how many are out.
---
--- Published because a leak is otherwise unobservable: a pool that fails to recycle answers `0, 0`
--- after a release where a correct one answers `n, 0`. That is the assertion a consumer's suite
--- makes, and the one nobody could make against the four hand-rolled copies.
---
--- @param pool table
--- @return number free, number active
function lib.Counts(pool)
  return #pool.free, #pool.active
end
