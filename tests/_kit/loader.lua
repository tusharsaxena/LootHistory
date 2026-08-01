-- testkit/loader.lua — headless source loading, shared across the collection.
--
-- Each file's chunk runs in an environment where WoW globals resolve to the mock set, falling back
-- to _G. Addon chunks are called with ("<AddonName>", NS), matching the client's `local addonName,
-- NS = ...` header; library chunks are called with no arguments.

local Loader = {}

-- Set by the consuming tests/run.lua before loading addon files. Library-only repos leave it nil.
Loader.addonName = nil

local function makeEnv(mocks)
  return setmetatable({}, {
    __index = function(_, k)
      local v = mocks[k]
      if v ~= nil then return v end
      return _G[k]
    end,
    -- Writes land in _G so an addon's SavedVariables global and any StaticPopupDialogs registration
    -- behave like the real client. Without this a sandboxed write to a WoW global is silently lost,
    -- and the SavedVariables migration paths become untestable.
    __newindex = function(_, k, v) _G[k] = v end,
  })
end

Loader.makeEnv = makeEnv

function Loader.load(path, NS, mocks)
  local chunk, err = loadfile(path)
  if not chunk then error("loadfile(" .. path .. "): " .. tostring(err)) end
  setfenv(chunk, makeEnv(mocks))
  if Loader.addonName then return chunk(Loader.addonName, NS) end
  return chunk()
end

function Loader.loadAll(paths, NS, mocks)
  for _, p in ipairs(paths) do
    Loader.load(p, NS, mocks)
  end
end

--- Load source held in a string rather than read straight off disk.
---
--- The multi-copy / minor-skew tests need two builds of the same file at different LibStub minors,
--- which only exists as a patched copy of the real source — loading the real file twice would just
--- re-run the same minor and register nothing the second time.
function Loader.loadSource(src, chunkname, NS, mocks)
  local chunk, err = loadstring(src, chunkname)
  if not chunk then error("loadstring(" .. tostring(chunkname) .. "): " .. tostring(err)) end
  setfenv(chunk, makeEnv(mocks))
  if Loader.addonName then return chunk(Loader.addonName, NS) end
  return chunk()
end

--- Read a file into a string. Used by loadSource callers and by suites that assert on source text.
function Loader.readFile(path)
  local f = io.open(path, "r")
  if not f then error("cannot open " .. tostring(path) .. " (tests run from the repo root)") end
  local body = f:read("*a")
  f:close()
  return body
end

--- An addon's own `.lua` files, in TOC order, as forward-slash paths.
---
--- Derived rather than hand-maintained because a repo typically has several load lists — the TOC
--- (what the client reads), tests/run.lua, an offline perf runner, a degraded-path list — and not
--- all of them are under the green gate. An ungated copy rots silently while the figures it
--- produces are still trusted.
---
--- `libs\` lines are skipped: vendored libraries are pulled in through their own XML, which this
--- cannot see, so runners prepend their own explicit lib list. Blank lines, comments and every
--- `## Directive:` are skipped too.
function Loader.tocFiles(tocPath)
  local f = io.open(tocPath, "r")
  if not f then error("cannot open " .. tostring(tocPath) .. " (tests run from the repo root)") end
  local out = {}
  for line in f:lines() do
    -- Strip the CR the CRLF policy puts on every line, then the surrounding whitespace.
    local entry = line:gsub("\r", ""):match("^%s*(.-)%s*$")
    if entry ~= "" and not entry:match("^#") and entry:lower():match("%.lua$")
      and not entry:lower():match("^libs[\\/]") then
      out[#out + 1] = entry:gsub("\\", "/")
    end
  end
  f:close()
  return out
end

return Loader
