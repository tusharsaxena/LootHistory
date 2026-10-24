-- tests/test_layers.lua — frame layering (frame-layering, standard v2.88.0; item 030).
--
-- WHAT THIS PINS. The one layers table (NS.Constants.LAYERS, frame-layering-§5) and where every
-- frame this addon draws for itself sits: the History window (T4 on demand: HIGH, toplevel,
-- clamped), the Export modal (T6: DIALOG, toplevel, clamped) and the shared row context menu (T8:
-- FULLSCREEN_DIALOG, clamped, dismissed by GLOBAL_MOUSE_DOWN with no full-screen catcher, closed on
-- every path its window closes). Everything else the addon shows is inherited from those parents or
-- is a library / Blizzard tier the table's header comment names.
--
-- WHY A FRESH INSTANCE. The kit's layer recorder (tests/_kit/mock_layers.lua) wraps CreateFrame
-- for the frames built AFTER it is installed, and the window, the modal and the row menu are all
-- memoized for the session -- the shared harness has usually built them by the time this suite
-- runs. So the cases that read layers load the library and the TOC into a namespace of their own,
-- on a mock of their own, with the recorder installed first; nothing here touches T.NS's frames.

local T = _G.LH_TEST
local NS, Loader = T.NS, T.Loader
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- frame-layering-§1's tier keys, the only names a layers table may use.
local TIER_KEYS = { HUD = true, CHROME = true, HUD_POPUP = true, WINDOW = true, ALERT = true,
  SCREEN_ALERT = true, MODAL = true, CHILD = true, POPUP = true, CURSOR = true }

-- One fresh, layer-recording instance: the library, the TOC, InitDB. Built once, on first use.
local fresh
local function instance()
  if fresh then return fresh end
  local M = dofile("tests/wow_mock.lua")()
  local restore = dofile("tests/_kit/mock_layers.lua")(M)
  local ns = {}
  Loader.loadAll(Loader.xmlFiles("libs/LibKa0s/LibKa0s.xml"), ns, M)
  Loader.loadAll(Loader.tocFiles("LootHistory.toc"), ns, M)
  ns:InitDB()
  -- Every frame built from here on, so a case can ask what one call created.
  local created = {}
  local prev = M.CreateFrame
  M.CreateFrame = function(...)
    local f = prev(...)
    created[#created + 1] = f
    return f
  end
  fresh = { M = M, NS = ns, created = created, restore = restore }
  return fresh
end

local function menuOf(I)
  local anchor = I.M.CreateFrame("Frame", nil, I.M.UIParent)
  local before = #I.created
  I.NS.BrowserTable:ShowMenu(anchor, { { label = "One", enabled = true, fn = function() end } })
  local made = {}
  for i = before + 1, #I.created do made[#made + 1] = I.created[i] end
  return I.NS.BrowserTable:MenuFrame(), made
end

-- ── the table ────────────────────────────────────────────────────────────────────────────────

test("Layers: NS.Constants.LAYERS names its strata by the standard's tier keys", function()
  local L = NS.Constants.LAYERS
  assertTrue(type(L) == "table" and type(L.STRATA) == "table" and type(L.LEVEL) == "table",
    "NS.Constants.LAYERS = { STRATA = {...}, LEVEL = {...} } (frame-layering-§5)")
  for k in pairs(L.STRATA) do
    assertTrue(TIER_KEYS[k] == true, "LAYERS.STRATA." .. tostring(k) .. " is not a frame-layering-§1 tier key")
  end
  assertEqual(L.STRATA.WINDOW, "HIGH")
  assertEqual(L.STRATA.MODAL, "DIALOG")
  assertEqual(L.STRATA.POPUP, "FULLSCREEN_DIALOG")
end)

test("Layers: no strata literal and no absolute level in the addon's own code", function()
  for _, path in ipairs(T.addonFiles) do
    local src = Loader.readFile(path)
    assertFalse(src:find('SetFrameStrata%("') ~= nil, path .. " writes a strata literal; read LAYERS.STRATA")
    assertFalse(src:find("SetFrameLevel%(%s*%d") ~= nil, path .. " writes an absolute frame level")
  end
end)

-- ── where each frame sits ────────────────────────────────────────────────────────────────────

test("Layers: the History window is the on-demand window tier, toplevel and clamped", function()
  local I = instance()
  I.NS.Browser:Show()
  local L = I.M.__layers(I.NS.Browser:GetWindow())
  assertEqual(L.strata, "HIGH")
  assertTrue(L.toplevel, "a click raises the window over the co-tier Settings panel (LOO-Z03)")
  assertTrue(L.clamped, "the window stays on screen")
end)

test("Layers: the Export modal is the modal tier, toplevel and clamped", function()
  local I = instance()
  I.NS.Export:Open({})
  local L = I.M.__layers(I.NS.Export:Window())
  assertEqual(L.strata, "DIALOG")
  assertTrue(L.toplevel, "a click raises the modal among the DIALOG tool windows (LOO-Z04)")
  assertTrue(L.clamped, "the modal stays on screen")
end)

test("Layers: the row menu is a clamped popup with no full-screen catcher", function()
  local I = instance()
  local m, made = menuOf(I)
  local L = I.M.__layers(m)
  assertEqual(L.strata, "FULLSCREEN_DIALOG")
  assertTrue(L.clamped, "a menu opened near the screen edge stays on screen (LOO-Z08)")
  assertFalse(L.toplevel, "a transient popup is not toplevel")
  for _, f in ipairs(made) do
    assertTrue(f == m or rawget(f, "__parent") == m,
      "ShowMenu built a frame that is neither the menu nor one of its rows (a catcher?)")
  end
  assertEqual(m.catcher, nil, "the FULLSCREEN click catcher is gone (LOO-Z02)")
  m:Hide()
end)

test("Layers: an outside press dismisses the row menu through GLOBAL_MOUSE_DOWN", function()
  local I = instance()
  local m = menuOf(I)
  assertTrue(m:IsShown())
  assertTrue(m:IsEventRegistered("GLOBAL_MOUSE_DOWN"), "listens while shown")
  -- A press on the menu itself is not outside: the item's OnClick needs the release.
  rawset(m, "IsMouseOver", function() return true end)
  m:__fire("OnEvent", "GLOBAL_MOUSE_DOWN", "LeftButton")
  assertTrue(m:IsShown(), "a press on the menu closed it")
  rawset(m, "IsMouseOver", function() return false end)
  m:__fire("OnEvent", "GLOBAL_MOUSE_DOWN", "RightButton")
  assertFalse(m:IsShown(), "an outside press left the menu up")
  m:__fire("OnHide")
  assertFalse(m:IsEventRegistered("GLOBAL_MOUSE_DOWN"), "stops listening once hidden")
end)

test("Layers: the row menu closes when the History window hides", function()
  local I = instance()
  I.NS.Browser:Show()
  local m = menuOf(I)
  assertTrue(m:IsShown())
  I.NS.Browser:GetWindow():__fire("OnHide")   -- Escape, the close button and B:Hide all land here
  assertFalse(m:IsShown(), "the row menu outlived its window (LOO-Z01)")
end)

test("Layers: BrowserTable:HideMenu is safe before the menu exists", function()
  local M = dofile("tests/wow_mock.lua")()
  local ns = {}
  Loader.loadAll(Loader.xmlFiles("libs/LibKa0s/LibKa0s.xml"), ns, M)
  Loader.loadAll(Loader.tocFiles("LootHistory.toc"), ns, M)
  ns.BrowserTable:HideMenu()
  assertEqual(ns.BrowserTable:MenuFrame(), nil, "HideMenu built the menu it was asked to hide")
end)
