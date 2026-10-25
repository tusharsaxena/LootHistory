-- tests/test_skin_tools.lua — the tool surfaces on the skin (LH-05; core/SkinSetup.lua's owner,
-- skinning-§3).
--
-- What this pins: every LibKa0s factory this addon calls is handed the addon as its skin OWNER, in
-- the form that factory reads, so the library paints the surface for "LootHistory" and repaints it
-- on a switch. Most factories take `owner` / `addonName` and were wired by LH-02..LH-04 (the
-- dropdown, search box, autocomplete, test strip, line chart; the sim and perf panels through their
-- `name` / `addonName`). The three that were not, and what this file holds them to:
--
--   * the debug console and its copy window. LibKa0s-DebugLog-1.0 treats `addonName` as the owner
--     ONLY when the host passes neither `skin` nor `applySkin` (DebugLog minor 22): a host hook owns
--     the whole job and is never skinned over. core/DebugLogSetup.lua passed `applySkin` (routing to
--     B:ApplySkin), so the window edge followed the skin while the log lines, scroll bar and line
--     counter stayed on the constants. The hook is gone; the descriptor names the folder only.
--   * the export copy window. W.CopyWindow has the same rule (Widgets minor 16): modules/Export.lua's
--     `applySkin` kept the dense fill and the scroll bar off the skin.
--   * the AH price drag list. W.ReorderList takes `opts.owner` (WidgetsReorder minor 2); the seam
--     never passed it, so the row boxes, the handle tints and the ghost stayed on the constants.
--
-- And one host line: the launcher tooltip's record count reads gtip.subtle (Ka0s Default .7 gray,
-- the value it always drew), pinned in tests/test_launcher.lua beside the descriptor it belongs to.
--
-- After tests/test_skin_settings.lua; it leaves the skin on Ka0s Default.

local T = _G.LH_TEST
local NS, mocks, Loader = T.NS, T.mocks, T.Loader
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local Skin = mocks.LibStub("LibKa0s-Skin-1.0")
local OptionsLib = mocks.LibStub("LibKa0s-Options-1.0")
local OWNER = "LootHistory"

-- The skin back on Ka0s Default, tests/test_skin_chrome.lua's reset: a skin change queues the
-- library's settings-page re-render on the kit's timers (fired here, so it cannot land in a later
-- suite), and away from Ka0s Default the page backdrop texture IS the page in this harness, so a
-- page that was on screen BEFORE the switch (`shownPages`, read first) is put back on screen.
local function shownPages()
  local wasShown = {}
  for ctx in pairs(OptionsLib.__shownPages or {}) do
    if ctx.panel and ctx.panel:IsShown() then wasShown[ctx] = true end
  end
  return wasShown
end

local function reset(wasShown)
  NS.WriteSkinChoice("ka0s", "ka0s")
  Skin:SetChoice(OWNER, "ka0s", "ka0s")
  mocks.__fireTimers()
  for ctx in pairs(wasShown) do
    local panel = ctx.panel
    if rawequal(rawget(panel, "__ka0sSkinBg"), panel) then rawset(panel, "__ka0sSkinBg", nil) end
    if not (panel:IsShown() and OptionsLib.__shownPages[ctx]) then
      panel:Show()
      panel:__fire("OnShow")
    end
  end
  mocks.__fireTimers()
end

local function rgba(c)
  if type(c) ~= "table" then return tostring(c) end
  return ("%.3f,%.3f,%.3f,%.3f"):format(c[1], c[2], c[3], c[4] or 1)
end

-- Re-run one seam file against a fake LibKa0s major that records the descriptor it is handed, into
-- a scratch namespace (tests/test_launcher.lua's pattern), so the fields the library reads are
-- asserted rather than inferred from what a built frame happens to show.
local function capture(file, major, ns)
  local captured
  local fake = { New = function(_, d) captured = d; return {} end }
  local fakeLibStub = setmetatable({}, { __call = function(_, name)
    if name == major then return fake end
  end })
  local scratch = setmetatable({ LibStub = fakeLibStub }, { __index = mocks })
  Loader.load(file, ns, scratch)
  return captured
end

test("the debug console's descriptor names the owner and passes no applySkin", function()
  local d = capture("core/DebugLogSetup.lua", "LibKa0s-DebugLog-1.0", {
    Constants = { FONT_MONO = "mono" }, BRAND = NS.BRAND,
  })
  assertTrue(d ~= nil, "core/DebugLogSetup.lua must build its console through DebugLog:New")
  assertEqual(d.addonName, OWNER, "addonName is the folder, the owner core/SkinSetup.lua registered")
  assertTrue(d.applySkin == nil,
    "a host applySkin owns the whole job, so the library never paints the console for its owner")
  assertTrue(d.skin == nil, "a host skin table opts the console out of its owner the same way")
end)

test("the live debug console and its copy window are painted for this owner", function()
  NS.DebugLog:Show()
  local f = NS.DebugLog._frameForTest
  assertTrue(f ~= nil, "the console frame")
  -- DebugLogWindow's adopt(): an owned console colors its lines from the owner's palette.
  assertTrue(rawget(f, "__logLine") ~= nil, "the console was built unowned (no palette line)")
  local rec = Skin.painted[f]
  assertTrue(rec ~= nil and rec.owner == OWNER, "the console window is recorded for " .. OWNER)
  NS.DebugLog:ShowCopy()
  local cf = NS.DebugLog._copyFrameForTest
  assertTrue(cf ~= nil, "the console's copy window")
  assertTrue(rawget(cf, "__copyDesc") ~= nil, "the console's copy window was not painted for an owner")
  cf:Hide()
  NS.DebugLog:Hide()
end)

test("the console's palette follows a skin switch without a reload", function()
  NS.DebugLog:Show()
  local f = NS.DebugLog._frameForTest
  local pal = rawget(f, "__palette")
  assertTrue(type(pal) == "table", "the console keeps its palette on the frame")
  local before = rgba(pal.count)
  assertEqual(before, rgba(Skin:Token(OWNER, "log.count")), "Ka0s Default: the counter's own token")
  local wasShown = shownPages()
  local ok, err = pcall(function()
    NS.ApplySkinChoice("ka0s", "azeroth")
    for _, name in ipairs({ "count", "ts", "tag", "text" }) do
      local want = Skin:Token(OWNER, "log." .. name)
      assertEqual(rgba(pal[name]), rgba(want), "the console's " .. name .. " color after a switch")
    end
    assertTrue(rgba(pal.text) ~= "1.000,1.000,1.000,1.000",
      "Azeroth's log text is not Ka0s Default's white (the switch reached the palette)")
    assertTrue(Skin.painted[f] and Skin.painted[f].owner == OWNER, "still recorded for the owner")
  end)
  reset(wasShown)
  NS.DebugLog:Hide()
  if not ok then error(err, 0) end
end)

test("the export copy window is painted for this owner", function()
  NS.Export.__showCopy("a,b\n1,2")
  local f = NS.Export.__copyWindow:GetFrame()
  assertTrue(f ~= nil, "the export copy window")
  assertTrue(rawget(f, "__copyDesc") ~= nil,
    "the export copy window was painted by a host applySkin, not for its owner")
  local rec = Skin.painted[f]
  assertTrue(rec ~= nil and rec.owner == OWNER, "the export copy window is recorded for " .. OWNER)
  f:Hide()
end)

test("the reorder list seam names the owner", function()
  local list = NS.MakeReorderList({ stride = 20 })
  assertTrue(list ~= nil, "the reorder controller")
  assertTrue(list.skin ~= nil, "the drag list takes no skin palette: the seam passed no owner")
  list:Cancel()
end)

test("every remaining factory seam passes the owner", function()
  -- The sim panel's owner is the Sim descriptor's `name` and the perf panel's its `addonName`
  -- (SimPanel minor 7, PerfPanel minor 10): read here so a rename of either goes red.
  local sim = Loader.readFile("modules/Sim.lua")
  assertTrue(sim:find('name%s*=%s*"LootHistory"') ~= nil, "the Sim descriptor's name is the owner")
  local perf = Loader.readFile("core/PerfSetup.lua")
  assertTrue(perf:find("addonName%s*=%s*addonName") ~= nil, "the Perf descriptor's addonName")
  local w = Loader.readFile("core/WidgetsSetup.lua")
  local _, owners = w:gsub("owner%s*=%s*addonName", "")
  -- Dropdown, SearchBox, ReorderList, LineChart, Autocomplete, TestStrip.
  assertEqual(owners, 6, "each Widgets factory seam names the owner")
  local export = Loader.readFile("modules/Export.lua")
  assertTrue(export:find("applySkin%s*=") == nil, "modules/Export.lua passes no applySkin")
end)
