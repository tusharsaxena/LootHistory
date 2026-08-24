-- tests/test_poolsetup.lua — the LibKa0s-Pool-1.0 seam.
--
-- The library's own suite covers the pool's semantics. What only this repo can assert is that the
-- seam is wired and that THIS addon — the one whose pool leaked — recycles.

local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local function counting()
  local made = 0
  return function()
    made = made + 1
    local o = { __shown = false }
    function o:Show() self.__shown = true end
    function o:Hide() self.__shown = false end
    return o
  end, function() return made end
end

test("PoolSetup: the seam is published", function()
  assertTrue(type(NS.Pool) == "table", "NS.Pool exists")
  assertTrue(type(NS.Pool.New) == "function")
  assertTrue(type(NS.Pool.Acquire) == "function")
  assertTrue(type(NS.Pool.ReleaseAll) == "function")
end)

test("PoolSetup: a released object is reused rather than rebuilt", function()
  local p = NS.Pool.New()
  local factory, made = counting()
  for _ = 1, 3 do NS.Pool.Acquire(p, factory) end
  NS.Pool.ReleaseAll(p)
  for _ = 1, 3 do NS.Pool.Acquire(p, factory) end
  assertEqual(made(), 3, "the second pass builds nothing — this is the assertion the leak failed")
end)

test("PoolSetup: ReleaseAll returns every active object to the free list", function()
  local p = NS.Pool.New()
  local factory = counting()
  NS.Pool.Acquire(p, factory); NS.Pool.Acquire(p, factory)
  NS.Pool.ReleaseAll(p)
  local free, active = NS.Pool.Counts(p)
  assertEqual(active, 0)
  assertEqual(free, 2)
end)
