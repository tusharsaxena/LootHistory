local _, NS = ...

-- core/PoolSetup.lua — wires the addon into LibKa0s-Pool-1.0 (library-stack-§7).
--
-- ── WHAT THIS REPLACED, AND WHAT IT COST ─────────────────────────────────────────────────────
--
-- This addon's chart pool was the one that got it wrong. `releaseAll` hid every active widget and
-- dropped it: the free list stayed empty, `acquire` called `factory()` every time, and since
-- LayoutCharts releases thirty-five pools at the top of every pass, each filter change allocated a
-- fresh frame per chart element. Frames are never destroyed in WoW, so they stayed for the session.
-- BankLedger's copy of the same eleven lines had always been right.
--
-- The bug was fixed on its own first, deliberately, so that the fix is a fix in the history rather
-- than a side effect of a refactor.
--
-- ── WHAT A DEGRADED INSTALL GETS ─────────────────────────────────────────────────────────────
--
-- The same pool, locally. It is nine lines, it is the code that was here before, and writing it
-- out is cheaper than making every caller branch — a chart that cannot pool is a chart that
-- allocates, which is precisely the failure this module exists to end.

local Pool = LibStub and LibStub("LibKa0s-Pool-1.0", true)

NS.Pool = Pool or {
  New = function() return { free = {}, active = {} } end,

  Acquire = function(pool, factory)
    local o = table.remove(pool.free)
    if not o then o = factory() end
    pool.active[#pool.active + 1] = o
    o:Show()
    return o
  end,

  -- The `before` hook is not optional garnish in the fallback either: a host releasing a pool of
  -- panels releases each panel's own row pool first, and one member has to cover both.
  ReleaseAll = function(pool, before)
    local active = pool.active
    -- BACKWARD, mirroring LibKa0s-Pool-1.0 minor 3. Acquire pops the free list from the END,
    -- so parking the last rank first leaves rank 1 on top and the next Acquire hands each
    -- widget back to the rank it already held. Walking forward alternates that mapping every
    -- render, which is the flicker this module's degraded half must not reintroduce.
    for i = #active, 1, -1 do
      local o = active[i]
      if before then before(o) end
      o:Hide()
      pool.free[#pool.free + 1] = o
    end
    for i = #active, 1, -1 do active[i] = nil end
  end,

  Counts = function(pool) return #pool.free, #pool.active end,
}
