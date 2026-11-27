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
  -- The holdings tooltip (#34): the post-call registry, the live item count and the class colors.
  { pat = "%f[%w_]TooltipDataProcessor%f[^%w_]",  use = "Compat.HookTooltipType(typeName, fn)" },
  { pat = "%f[%w_]C_Item%.GetItemCount%f[^%w_]",  use = "Compat.LiveItemCounts(itemID)" },
  { pat = "%f[%w_]RAID_CLASS_COLORS%f[^%w_]",     use = "Compat.ClassColor(classFile)" },
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

-- clients-§3: which client this is is asked only through LibKa0s-Compat-1.0, routed by
-- core/CompatClient.lua, whose library-absent stubs are the one place outside the library that may
-- read a project constant; regional names likewise (forever-quirks-§4). Everything else asks
-- NS.Compat.ClientKey() / IsForever() / ForClient() / RegionalNames(). An interface-number test is
-- banned with them: it changes every patch and says nothing about the game type.
local CLIENT_READS = {
  { pat = "%f[%w_]WOW_PROJECT_[%u_]+",               use = "Compat.ClientKey() / IsForever() / ForClient()" },
  { pat = "%f[%w_]RegionalUniqueNamesEnabled%f[^%w_]", use = "Compat.RegionalNames()" },
  { pat = "%f[%w_]GetBuildInfo%f[^%w_]",             use = "Compat.ClientKey() (never an interface number)" },
}

test("Compat routing: only core/CompatClient.lua reads the client's project constants or regional names", function()
  local files = shippedFiles(nil)
  assertTrue(#files > 0, "the TOC lists no file, so this gate saw nothing")
  local hits = {}
  for _, path in ipairs(files) do
    if path ~= "core/CompatClient.lua" and path:match("%.lua$") then
      for n, code in ipairs(codeLines(path)) do
        for _, b in ipairs(CLIENT_READS) do
          if code:find(b.pat) then hits[#hits + 1] = path .. ":" .. n .. " -> use " .. b.use end
        end
      end
    end
  end
  assertEqual(#hits, 0, "client reads outside the compat family:\n  " .. table.concat(hits, "\n  "))
end)

test("Compat routing: the compat family loads Compat, CompatClient, CompatTooltip, straight above the Sim seam", function()
  -- red under: CompatClient below core/SimSeam.lua, where its members escape the wrap; or above
  -- core/Compat.lua, which publishes the NS.Compat it adds to.
  local order = {}
  for i, path in ipairs(shippedFiles("core/")) do order[path] = i end
  assertTrue(order["core/CompatClient.lua"] ~= nil, "the TOC lists core/CompatClient.lua")
  assertEqual(order["core/CompatClient.lua"], order["core/Compat.lua"] + 1, "straight after core/Compat.lua")
  assertTrue(order["core/CompatTooltip.lua"] ~= nil, "the TOC lists core/CompatTooltip.lua")
  assertEqual(order["core/CompatTooltip.lua"], order["core/CompatClient.lua"] + 1, "the family stays contiguous")
  assertEqual(order["core/SimSeam.lua"], order["core/CompatTooltip.lua"] + 1, "straight before core/SimSeam.lua")
end)
