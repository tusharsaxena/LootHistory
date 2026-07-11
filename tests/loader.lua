-- Loads addon source files headlessly: each file's chunk is called with ("LootHistory", NS)
-- and given an environment where WoW globals resolve to the mock set, falling back to _G.

local Loader = {}
Loader.addonName = "LootHistory"

local function makeEnv(mocks)
  return setmetatable({}, {
    __index = function(_, k)
      local v = mocks[k]
      if v ~= nil then return v end
      return _G[k]
    end,
  })
end

function Loader.load(path, NS, mocks)
  local chunk, err = loadfile(path)
  if not chunk then error("loadfile(" .. path .. "): " .. tostring(err)) end
  setfenv(chunk, makeEnv(mocks))
  return chunk(Loader.addonName, NS)
end

function Loader.loadAll(paths, NS, mocks)
  for _, p in ipairs(paths) do
    Loader.load(p, NS, mocks)
  end
end

return Loader
