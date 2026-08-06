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

--- The `.lua` files a `<Ui>` XML pulls in, in XML order, as forward-slash paths prefixed with the
--- XML's own directory — so `Loader.xmlFiles("libs/LibKa0s/LibKa0s.xml")` returns
--- `libs/LibKa0s/Core.lua`, not `Core.lua`, and the result is directly loadable by `Loader.loadAll`.
---
--- This is the other half of the gap `tocFiles` documents: a vendored library is pulled in through
--- its own XML, which the TOC scan cannot see, so every runner in the collection re-typed the same
--- eight-entry list. Eight hand-typed copies of one list is eight chances to drop an entry, and one
--- of them did — a consumer's list named six of the eight files and nothing noticed, because a load
--- list that is short does not raise; it just leaves a module undefined for the cases that never
--- reach it.
---
--- Deliberately line-based and flat: `LibKa0s.xml` is a flat list of `<Script file="…"/>`, there are
--- no nested `<Include>`s to follow, and a real XML parser here would be a dependency bought to
--- solve a problem nobody has. A line whose first non-space characters open an XML comment is
--- skipped, so a commented-out entry does not load.
---
--- A missing XML raises with the same "tests run from the repo root" message `tocFiles` and
--- `readFile` use, rather than returning an empty list: an empty list loads nothing at all and reads
--- exactly like a clean run.
function Loader.xmlFiles(xmlPath)
  local f = io.open(xmlPath, "r")
  if not f then error("cannot open " .. tostring(xmlPath) .. " (tests run from the repo root)") end
  -- The XML's own directory, with a trailing slash, or "" when it sits at the repo root.
  local dir = tostring(xmlPath):gsub("\\", "/"):match("^(.*/)[^/]*$") or ""
  local out = {}
  for line in f:lines() do
    local entry = line:gsub("\r", ""):match("^%s*(.-)%s*$")
    if not entry:match("^<!%-%-") then
      local file = entry:match("file%s*=%s*[\"']([^\"']+)[\"']")
      if file and file:lower():match("%.lua$") then
        out[#out + 1] = dir .. file:gsub("\\", "/")
      end
    end
  end
  f:close()
  return out
end

return Loader
