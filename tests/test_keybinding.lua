local T = _G.LH_TEST
local NS, M, Loader = T.NS, T.mocks, T.Loader
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- ── The Show window key binding (launcher-§6, anti-pattern #96, LibKa0s#58) ────────────────────
--
-- A root Bindings.xml declares ONE binding, `CLICK LootHistoryToggleWindow:LeftButton`, and the
-- client fires it by clicking the button of that global name. So the contract is two halves that
-- must agree by NAME: the XML, which the client reads on its own (it is never a TOC line), and the
-- plain button core/LauncherSetup.lua creates at load. The button's click is the launcher's own
-- toggleWindow handler -- the `/lh toggle` verb -- asked first for a refusal by hold, because a key
-- cannot be grayed the way the menu entry is (tests/test_disabled.lua step 8 owns those cases).

local BUTTON  = "LootHistoryToggleWindow"
local BINDING = "CLICK " .. BUTTON .. ":LeftButton"

local function readBindings()
  local f = io.open("Bindings.xml", "rb")
  assertTrue(f ~= nil, "Bindings.xml is missing from the addon root")
  local text = f:read("*a")
  f:close()
  return text
end

test("keybinding: Bindings.xml parses, names CLICK LootHistoryToggleWindow:LeftButton under header "
  .. "LOOTHISTORY, category ADDONS, no default attribute", function()
  -- red under: a renamed button (the binding then clicks nothing and raises nothing), a header the
  -- BINDING_HEADER_ global does not label, a `default` key that would take a key from the player,
  -- or Lua inside the binding (the click IS the action; a body would be a second handler).
  local text = readBindings()
  assertTrue(text:match("^%s*<Bindings>") ~= nil, "the file opens with <Bindings>")
  assertTrue(text:match("</Bindings>%s*$") ~= nil, "the file closes with </Bindings>")
  local tags = {}
  for tag in text:gmatch("<Binding%s[^>]*>") do tags[#tags + 1] = tag end
  assertEqual(#tags, 1, "exactly one <Binding>")
  local tag = tags[1]
  assertEqual(tag:match('name="([^"]*)"'), BINDING, "the binding's name")
  assertEqual(tag:match('header="([^"]*)"'), "LOOTHISTORY", "the binding's header")
  assertEqual(tag:match('category="([^"]*)"'), "ADDONS", "the binding's category")
  assertTrue(tag:match("%sdefault%s*=") == nil, "no default key: the player chooses one")
  assertTrue(tag:match("/>$") ~= nil, "self-closing: the binding carries no Lua")
end)

test("keybinding: Bindings.xml is not listed in LootHistory.toc", function()
  -- The client reads a root Bindings.xml by itself; listing it in the TOC loads it a second time as
  -- a UI file, which the client rejects with an error at login (toc-file rule).
  local toc = Loader.readFile("LootHistory.toc")
  assertTrue(toc:find("Bindings", 1, true) == nil, "LootHistory.toc must not name Bindings.xml")
end)

test("keybinding: the button exists, is named, is not secure, registers AnyDown", function()
  -- red under: a missing button (the key does nothing), a secure template (the press would be
  -- blocked in combat for a window that is not secure), or no click registration (a binding's
  -- CLICK only reaches a button registered for that click).
  local b = M.__namedFrames[BUTTON]
  assertTrue(b ~= nil, "no frame named " .. BUTTON)
  assertEqual(b.__frameType, "Button", "a plain Button")
  assertEqual(b.__name, BUTTON, "the global name the binding clicks")
  assertEqual(b.__parent, M.UIParent, "parented to UIParent")
  assertTrue(b.__template == nil, "no template, so nothing secure: "
    .. tostring(b.__template))
  assertEqual(b:IsShown(), false, "hidden: it is a click target, never drawn")
  assertTrue(b.__clicks ~= nil, "RegisterForClicks was never called")
  assertEqual(table.concat(b.__clicks, ","), "AnyDown", "registered for AnyDown")
  assertEqual(type(b:GetScript("OnClick")), "function", "it has a click handler")
end)

test("keybinding: labels: BINDING_HEADER_LOOTHISTORY == NS.BRAND and the BINDING_NAME global is set",
  function()
    -- The Key Bindings page shows the header and the row by these two globals; unset, it prints
    -- the raw token.
    assertEqual(_G.BINDING_HEADER_LOOTHISTORY, NS.BRAND, "the header label is the brand name")
    assertEqual(rawget(_G, "BINDING_NAME_" .. BINDING), NS.L["Toggle Loot History window"],
      "the binding's row label")
    assertEqual(rawget(_G, "BINDING_NAME_" .. BINDING), "Toggle Loot History window", "the English")
  end)

test("keybinding: one press toggles once (open then close) through the toggle verb", function()
  -- The handler is the launcher's toggleWindow and `/lh toggle`: B:Toggle, once per press.
  -- red under: a press that calls nothing, a press that calls Toggle twice (a click registered for
  -- both down and up), or a handler that skips the verb and calls B:Show directly.
  local b = M.__namedFrames[BUTTON]
  local B = NS.Browser
  local realToggle, calls, shown = B.Toggle, 0, false
  B.Toggle = function() calls = calls + 1; shown = not shown end
  local ok, err = pcall(function()
    NS.Schema:Set("settings.enabled", true)
    b:GetScript("OnClick")(b, "LeftButton", true)
    assertEqual(calls, 1, "the first press toggles once")
    assertEqual(shown, true, "the first press opens")
    b:GetScript("OnClick")(b, "LeftButton", true)
    assertEqual(calls, 2, "the second press toggles once more")
    assertEqual(shown, false, "the second press closes")
  end)
  B.Toggle = realToggle
  if not ok then error(err, 0) end
end)

test("keybinding: the button exists on a degraded install (no Launcher library)", function()
  -- The degraded launcher seam returns early; the button is created ABOVE that exit, so a key the
  -- player bound still works on a library-less install.
  local degradedNS, _, mocks = dofile("tests/degraded_env.lua")()
  assertTrue(degradedNS.Launcher == nil, "this environment really has no launcher")
  local b = mocks.__namedFrames[BUTTON]
  assertTrue(b ~= nil, "no " .. BUTTON .. " on the degraded path")
  assertEqual(type(b:GetScript("OnClick")), "function", "and it has its click handler")
end)
