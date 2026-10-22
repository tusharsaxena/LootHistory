-- tests/test_compat_routing.lua — the simulator-relevant reads stay routed through NS.Compat.
--
-- A STATIC gate, read off the shipped source rather than exercised. LibKa0s-Sim-1.0's answer seam
-- wraps NS.Compat members at file load, right after core/Compat.lua, and reaches nothing else. Two
-- shapes defeat it without raising a thing:
--
--   1. A bare client read in a handler. The live client answers it and every live suite stays green,
--      while a simulated run reads the real world instead of the scripted one and records nothing
--      (Drop Watcher's DW-90, the lesson behind LootHistory#37 and LibKa0s#54).
--   2. A FILE-SCOPE capture of a member, `local x = NS.Compat.Member`. It binds the unwrapped
--      function before the seam can wrap it. A capture of the TABLE (`local Compat = NS.Compat`)
--      reads the member at call time and is fine; so is a capture inside a function body, which
--      runs after the seam is in place.
--
-- Comments are stripped before matching, because the modules explain these very calls in prose.
-- The deliberately bare reads (docs/compat-layer.md, "Deliberately left bare") are not listed.

local T = _G.LH_TEST
local Loader = T.Loader
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- The reads that must go through a Compat member, and the member that serves each.
local BANNED = {
  { pat = "%f[%w_]GetNumLootItems%f[^%w_]",       use = "Compat.NumLootItems()" },
  { pat = "%f[%w_]GetLootSourceInfo%f[^%w_]",     use = "Compat.LootSourceGUID(slot)" },
  { pat = "%f[%w_]IsInInstance%f[^%w_]",          use = "Compat.InInstance() / InPartyInstance()" },
  { pat = "%f[%w_]IsInGroup%f[^%w_]",             use = "Compat.InGroup()" },
  { pat = "%f[%w_]UnitAffectingCombat%f[^%w_]",   use = "Compat.PlayerInCombat()" },
  { pat = "%f[%w_]hooksecurefunc%f[^%w_]",        use = "Compat.HookSecure / HookSecureMember" },
  { pat = "%f[%w_]UnitClass%s*%(%s*[\"']player",  use = "Compat.PlayerClassFile()" },
}

local function shippedFiles(prefix)
  local out = {}
  for _, path in ipairs(Loader.tocFiles("LootHistory.toc")) do
    if prefix == nil or path:sub(1, #prefix) == prefix then out[#out + 1] = path end
  end
  return out
end

-- Each source line with its `--` comment removed. Naive about a `--` inside a string, which the
-- gate would only ever over-report, never miss.
local function codeLines(path)
  local lines = {}
  for line in (Loader.readFile(path) .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("\r$", "")
    lines[#lines + 1] = (line:gsub("%-%-.*$", ""))
  end
  return lines
end

test("Compat routing: modules/ makes no bare simulator-relevant client read", function()
  local files = shippedFiles("modules/")
  assertTrue(#files > 0, "the TOC lists no modules/ file, so this gate saw nothing")
  local hits = {}
  for _, path in ipairs(files) do
    for n, code in ipairs(codeLines(path)) do
      for _, b in ipairs(BANNED) do
        if code:find(b.pat) then
          hits[#hits + 1] = path .. ":" .. n .. " -> use " .. b.use
        end
      end
    end
  end
  assertEqual(#hits, 0, "bare client reads the Sim-1.0 seam cannot reach:\n  "
    .. table.concat(hits, "\n  "))
end)

test("Compat routing: no file-scope capture of a Compat member outside core/Compat.lua", function()
  local files = shippedFiles(nil)
  assertTrue(#files > 0, "the TOC lists no file, so this gate saw nothing")
  local hits = {}
  for _, path in ipairs(files) do
    if path ~= "core/Compat.lua" and path:match("%.lua$") then
      for n, code in ipairs(codeLines(path)) do
        -- File scope is the unindented `local`; a member reference NOT followed by a call.
        if code:match("^local%s") then
          local rhs = code:match("=(.*)$") or ""
          for member, after in rhs:gmatch("Compat%.([%w_]+)%s*(.?)") do
            if after ~= "(" and after ~= "." and after ~= ":" then
              hits[#hits + 1] = path .. ":" .. n .. " captures Compat." .. member
            end
          end
        end
      end
    end
  end
  assertEqual(#hits, 0, "a file-scope capture binds the member before the seam wraps it:\n  "
    .. table.concat(hits, "\n  "))
end)
