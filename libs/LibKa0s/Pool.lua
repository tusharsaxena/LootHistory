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
-- Since minor 2 there is a second shape, for hosts that need an O(1) index INTO the active set:
--
--     { free = { … }, active = { [key] = … } }     -- built by NewKeyed()
--
-- Same free list, same objects, same factory contract; only `active` changes from an array to a
-- map, and it gets its own three members. The two shapes are NOT interchangeable and the file
-- refuses to mix them — see the guard in ReleaseAll.
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

local MAJOR, MINOR = "LibKa0s-Pool-1.0", 2
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

  -- Anything left is a keyed entry this loop could never reach, and passing over it silently is
  -- precisely the leak this module was written to end: every object hidden, none freed, `Acquire`
  -- falling through to `factory()` forever, and no suite anywhere going red. Two consumers keyed
  -- their active set before minor 2 gave them a way to say so, so the mistake is one a real host
  -- makes. Raise instead — a loud error at the call site costs one fix; a silent leak costs a
  -- session of growing memory with no cause in the history.
  --
  -- The net has one hole, and it is not closable: a keyed pool whose keys are themselves 1..n is
  -- indistinguishable from an array pool, so the loop above consumes it and this never fires. It
  -- recycles correctly by accident, until a key goes missing from the sequence. Real keyed hosts
  -- key by domain identity — spellIDs, frame names — which never form 1..n, so the hole is not
  -- where the mistake happens. tests/test_pool.lua pins both halves.
  if next(active) ~= nil then
    error("LibKa0s-Pool: ReleaseAll was handed a keyed pool — use ReleaseAllKeyed", 2)
  end
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

--- A fresh, empty KEYED pool — `active` is a map rather than an array.
---
--- Reach for this only when the host needs to find one live object by name on a hot path. KickCD
--- keys its icon-grid buttons by spellID so a cooldown-state message reaches one widget without
--- scanning; that index is the entire reason the variant exists. A host that only ever draws and
--- releases a list wants `New()`, which is cheaper to reason about.
---
--- @return table  { free = {}, active = {} } — the same shape, read differently
function lib.NewKeyed()
  return { free = {}, active = {} }
end

--- Take an object and file it under `key`, building one only if the free list is empty.
---
--- Re-acquiring a key that is already live returns the object already sitting there and builds
--- nothing. The alternative — overwriting — would orphan the first object: it would leave the map
--- holding only the second, and the first could never reach the free list again, which is the same
--- leak by a different route.
---
--- Like `Acquire`, the returned object is SHOWN.
---
--- @param pool table
--- @param key any  any non-nil table key
--- @param factory function  called with no arguments; must return an object with :Show()/:Hide()
--- @return table  the acquired object
function lib.AcquireKeyed(pool, key, factory)
  local live = pool.active[key]
  if live then return live end

  local o = table.remove(pool.free)
  if not o then o = factory() end
  pool.active[key] = o
  o:Show()
  return o
end

--- Hide every active object and RETURN IT TO THE FREE LIST, clearing every key.
---
--- `before` is called as `before(object, key)`. The key is handed over because a keyed host's
--- per-object teardown usually needs it — unregistering a ticker filed under the same id, say —
--- and recovering it by scanning the map would defeat the index the variant exists for.
---
--- @param pool table
--- @param before function|nil  called as before(object, key) before the object is hidden
function lib.ReleaseAllKeyed(pool, before)
  local active, free = pool.active, pool.free
  for key, o in pairs(active) do
    if before then before(o, key) end
    o:Hide()
    free[#free + 1] = o
    active[key] = nil
  end
end

--- How many objects are parked and how many are out, for a KEYED pool.
---
--- `Counts` cannot answer this: it reads `#active`, which is 0 for a map however full it is — the
--- same reading that made the original hand-rolled leak unobservable. A keyed host asserting on
--- recycling needs a counter that actually walks the map.
---
--- @param pool table
--- @return number free, number active
function lib.CountsKeyed(pool)
  local n = 0
  for _ in pairs(pool.active) do n = n + 1 end
  return #pool.free, n
end
