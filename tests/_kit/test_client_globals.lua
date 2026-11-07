-- testkit/test_client_globals.lua -- the missing-globals gate (kit revision 53, WFP-LK-06, LibKa0s#77):
-- no call, in the addon's tracked source, of a global function a client does not have. The scanner,
-- its heuristics and the name sets are `client_globals.lua` and `client_globals_*.lua` beside this file; read its
-- header for what counts as a finding, a guard and an allowed name.
--
-- WIRING, in the consumer's `tests/run.lua`: one line in the suites list, and nothing else.
--
--   { name = "test_client_globals", dir = "tests/_kit/" },
--
-- The scan is of the repo at `.`: tracked `.lua`, `libs/` included and `tests/` left out. `live` is
-- always checked, `forever` only when a root `.toc`'s `## Interface` carries a 16xxx number. Names
-- the addon calls on purpose go in `tests/client_globals_allow.lua`, `{ name, reason }` each. A
-- consumer that needs another root, allowlist or folders left out (`skip`, path prefixes, for tooling
-- that never ships) sets `Kit.clientGlobals = { root = ..., allow = ..., skip = { "tools/" } }` before
-- `Kit.run`.
--
-- It takes the kit as its chunk argument, for the reason `test_eol.lua` does.

local Kit = ...
local test, fail = Kit.test, Kit.fail

local facts = Kit.clientGlobals or {}

local function ownDir()
  local info = debug and debug.getinfo and debug.getinfo(1, "S")
  local dir = info and tostring(info.source or ""):match("^@(.*[/\\])")
  return dir or "tests/_kit/"
end

local CG = dofile(ownDir() .. "client_globals.lua")
local sets = CG.sets(ownDir())

local cached
local function look()
  if cached then return cached[1], cached[2], cached[3] end
  local files, toc = CG.collect(facts.root, facts.skip)
  local found = CG.scan(files, sets)
  local allow = CG.allowlist(facts.allow or "tests/client_globals_allow.lua")
  cached = { found, allow, CG.clientsFromToc(toc) }
  return found, allow, cached[3]
end

test("client globals: no call of a global a client lacks", function()
  local found, allow, clients = look()
  local bad = CG.judge(found, allow, clients)
  if #bad > 0 then
    fail("globals missing on " .. table.concat(clients, " and ") .. " (guard the call with a presence test, "
      .. "or add the name to tests/client_globals_allow.lua with its reason):\n  " .. table.concat(bad, "\n  "))
  end
end)

test("client globals: every allowlist row has a reason and a finding to excuse", function()
  local found, allow, clients = look()
  local _, problems, stale = CG.judge(found, allow, clients)
  for _, name in ipairs(stale) do problems[#problems + 1] = ("allowlist row %q matches no call"):format(name) end
  if #problems > 0 then fail("client globals allowlist:\n  " .. table.concat(problems, "\n  ")) end
end)

test("client globals: the check is falsifiable, a planted bare call is flagged for both clients", function()
  local found = CG.scan({ { "planted.lua", "local x\nSetDesaturation(x, true)" } }, sets)
  local got = {}
  for _, hit in ipairs(found) do got[#got + 1] = hit.line .. ":" .. hit.name .. ":" .. hit.client end
  if table.concat(got, ",") ~= "2:SetDesaturation:live,2:SetDesaturation:forever" then
    fail("the scanner reported " .. table.concat(got, ",") .. " for the planted call")
  end
end)
