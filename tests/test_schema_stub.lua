-- tests/test_schema_stub.lua — the host Schema stub's write behavior, on a real degraded load.
--
-- tests/test_surface_parity.lua proves the stub instance carries every member the live runtime
-- does. That is a check on NAMES. This file checks what the stub's writers DO, because a member
-- that is present and wrong passes parity and still breaks the degraded build that calls it.
--
-- The instance under test is the one settings/Schema.lua's `hostSchemaStub()` built during a real
-- load with libs/ absent (tests/degraded_env.lua), never a hand-written copy. Its store is a table
-- this file hands it through `degradedNS.db`, and the rows it writes are probe rows appended through
-- the stub's own `AddRows` and removed again after each case, so no shipped row's onChange runs.
--
-- The semantics mirrored are LibKa0s docs/api/Schema/version-2-docs.md, "The batch: SetMany", and
-- its degradation-stub table: all or nothing, log-silent.

local T = _G.LH_TEST
local test, assertTrue, assertEqual, assertFalse = T.test, T.assertTrue, T.assertEqual, T.assertFalse

local loadDegraded = dofile("tests/degraded_env.lua")
local degradedNS = loadDegraded()
local R = degradedNS.SchemaRuntime

-- Two probe rows with a validate each, a store the stub can resolve, and an onChange log. The rows
-- and the store are removed however the case ends, so a failing assertion leaves nothing behind.
local function withProbes(fn)
  local log = {}
  local store = { settings = { __probeA = 1, __probeB = 1 } }
  local function row(name)
    local path = "settings." .. name
    return {
      path = path, type = "number", default = 1,
      validate = function(v) return type(v) == "number" and v < 5 end,
      onChange = function(v)
        log[#log + 1] = {
          path = path, value = v, inBulk = R.InBulk(),
          a = store.settings.__probeA, b = store.settings.__probeB,
        }
      end,
    }
  end
  local rows = R.AllRows()
  local first = #rows + 1
  R.AddRows({ row("__probeA"), row("__probeB") })
  local savedDb = degradedNS.db
  degradedNS.db = { global = store }
  local ok, err = pcall(fn, store.settings, log)
  degradedNS.db = savedDb
  table.remove(rows, first + 1)
  table.remove(rows, first)
  if not ok then error(err, 0) end
end

test("Schema stub: SetMany refuses a batch holding an invalid entry and stores nothing", function()
  withProbes(function(stored, log)
    local ok, err, _, index = R.SetMany({
      { path = "settings.__probeA", value = 2 },
      { path = "settings.__probeB", value = 9 },
    })
    assertFalse(ok, "a batch with an invalid entry must refuse")
    assertTrue(type(err) == "string" and err ~= "", "the refusal carries a reason")
    assertEqual(index, 2, "the refusal names the failing entry's position")
    assertEqual(stored.__probeA, 1, "the valid entry before the failure must not be stored")
    assertEqual(stored.__probeB, 1)
    assertEqual(#log, 0, "a refused batch runs no onChange")
  end)
end)

test("Schema stub: SetMany refuses an unknown path by its index", function()
  withProbes(function(stored)
    local ok, _, _, index = R.SetMany({
      { path = "settings.__probeA", value = 3 },
      { path = "settings.nope", value = 1 },
    })
    assertFalse(ok)
    assertEqual(index, 2)
    assertEqual(stored.__probeA, 1)
  end)
end)

test("Schema stub: SetMany stores every entry, then runs every onChange in order", function()
  withProbes(function(stored, log)
    assertTrue(R.SetMany({
      { path = "settings.__probeA", value = 2 },
      { path = "settings.__probeB", value = 3 },
    }) == true, "a valid batch answers true")
    assertEqual(stored.__probeA, 2)
    assertEqual(stored.__probeB, 3)
    assertEqual(#log, 2)
    assertEqual(log[1].path, "settings.__probeA")
    assertEqual(log[2].path, "settings.__probeB")
    -- The library's phase 3: reactions run after EVERY store has landed, so the first row's
    -- onChange already sees the second row's value.
    assertEqual(log[1].b, 3, "onChange must run after the whole batch is stored")
    assertFalse(log[1].inBulk, "without opts.act the batch opens no bracket")
  end)
end)

test("Schema stub: SetMany with opts.act runs its stores and reactions inside one bracket", function()
  withProbes(function(_, log)
    assertTrue(R.SetMany({ { path = "settings.__probeA", value = 4 } }, { act = "copy", scope = "probe" }))
    assertTrue(log[1].inBulk, "opts.act brackets the batch, so a sweep veto sees it")
    assertFalse(R.InBulk(), "the bracket is closed when SetMany returns")
  end)
end)
