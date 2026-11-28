local T = _G.LH_TEST
local NS, M, Loader = T.NS, T.mocks, T.Loader
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- ── The Show window key binding (launcher-§6, anti-pattern #96, LibKa0s#58) ────────────────────
--
-- A root Bindings.xml declares ONE binding, `CLICK LootHistoryToggleWindow:LeftButton`, in the
-- addon's own category `BINDING_HEADER_LOOTHISTORY` (standard v2.88.0), and the
-- client fires it by clicking the button of that global name. So the contract is two halves that
-- must agree by NAME: the XML, which the client reads on its own (it is never a TOC line), and the
-- plain button core/LauncherSetup.lua creates at load. The button's click is the launcher's own
-- toggleWindow handler -- the `/lh toggle` verb -- asked first for a refusal by hold, because a key
-- cannot be grayed the way the menu entry is (tests/test_disabled.lua step 8 owns those cases).

local BUTTON  = "LootHistoryToggleWindow"
local BINDING = "CLICK " .. BUTTON .. ":LeftButton"
-- The farm pair (#39, farm spec §8): after Show window, in the same category.
local FARM_TOGGLE = "LootHistoryToggleFarm"
local FARM_SF     = "LootHistoryFarmStartFinish"
local FARM_TOGGLE_BINDING = "CLICK " .. FARM_TOGGLE .. ":LeftButton"
local FARM_SF_BINDING     = "CLICK " .. FARM_SF .. ":LeftButton"

local function readBindings()
  local f = io.open("Bindings.xml", "rb")
  assertTrue(f ~= nil, "Bindings.xml is missing from the addon root")
  local text = f:read("*a")
  f:close()
  return text
end

test("keybinding: Bindings.xml has the launcher-§6 shape: Show window, then the two farm bindings, "
  .. "in category BINDING_HEADER_LOOTHISTORY, no header, no default, labeled", function()
  -- The kit's shared check (Kit.assertBindingsXml, kit revision 42): every <Binding> carries
  -- category="BINDING_HEADER_LOOTHISTORY" (its own section in Options -> Keybindings, titled with
  -- the brand) and no header= (a header inside a category draws as a blank spacer row); no default
  -- key; the names equal NS.BINDINGS' commands in order; each has a BINDING_NAME_ label; and the
  -- category global is the brand.
  -- red under: the shared ADDONS category or a header= coming back, a renamed button (the binding
  -- then clicks nothing and every player's saved key is lost), a `default` key, or NS.BINDINGS and
  -- the file disagreeing.
  local list = T.assertBindingsXml("Bindings.xml", {
    category = "BINDING_HEADER_LOOTHISTORY",
    commands = NS.BINDINGS,
    brand    = NS.BRAND,
    labels   = { [BINDING] = "Toggle history browser", [FARM_TOGGLE_BINDING] = "Toggle farm session",
                 [FARM_SF_BINDING] = "Start or finish farm session" },
  })
  assertEqual(#list, 3, "exactly three <Binding>s")
  assertEqual(list[1].name, BINDING, "the binding's name never changes: saved keys survive")
  assertEqual(list[2].name, FARM_TOGGLE_BINDING, "the farm toggle second")
  assertEqual(list[3].name, FARM_SF_BINDING, "Start or finish third")
  -- No Lua in the element: the click IS the action, and a body would be a second handler.
  local text = readBindings()
  for tag in text:gmatch("<Binding%s[^>]*>") do
    assertTrue(tag:match("/>$") ~= nil, "self-closing: the binding carries no Lua")
  end
end)

test("keybinding: NS.BINDINGS is one table, Bindings.xml order, Show window first, each with a tooltip",
  function()
    -- launcher-§6's one bindings table, read by the Keybindings tab (options-ui-§20) and this suite.
    -- red under: a second list somewhere else, the Show window binding not first, or a row with no
    -- tooltip (the tab's label would hover blank).
    assertEqual(type(NS.BINDINGS), "table", "NS.BINDINGS is declared")
    assertEqual(#NS.BINDINGS, 3, "three bindings")
    assertEqual(NS.BINDINGS[1].command, BINDING, "Show window first")
    assertEqual(NS.BINDINGS[1].tooltip, NS.L["Shows or hides the history browser."], "its tooltip")
    assertEqual(NS.BINDINGS[1].tooltip, "Shows or hides the history browser.", "the English")
    assertEqual(NS.BINDINGS[2].command, FARM_TOGGLE_BINDING, "the farm toggle second")
    assertEqual(NS.BINDINGS[2].tooltip, "Shows or hides the farm session panel.", "its tooltip")
    assertEqual(NS.BINDINGS[3].command, FARM_SF_BINDING, "Start or finish third")
    assertEqual(NS.BINDINGS[3].tooltip,
      "Starts a farm session, or finishes the running one and shows its summary.", "its tooltip")
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
    -- Options -> Keybindings titles the section with the category global and the row with the
    -- BINDING_NAME_ one; unset, it prints the raw token. The row says what it toggles and no brand:
    -- the section title already carries it (launcher-§6).
    assertEqual(_G.BINDING_HEADER_LOOTHISTORY, NS.BRAND, "the header label is the brand name")
    assertEqual(rawget(_G, "BINDING_NAME_" .. BINDING), NS.L["Toggle history browser"],
      "the binding's row label")
    assertEqual(rawget(_G, "BINDING_NAME_" .. BINDING), "Toggle history browser", "the English")
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

-- ── The two farm bindings (#39, farm spec §8, D21) ──────────────────────────────────────────────
--
-- The same contract as Show window: a named, plain, hidden Button registered for AnyDown, created
-- above the launcher seam's degraded exit, asked for a refusal by hold first, and one press is ONE
-- call of the `/lh farm` verb in NS.COMMANDS (spied in place), never the model underneath it.

--- Run `fn(calls)` with the `/lh farm` verb's handler replaced by a recorder of the word it is handed.
local function withFarmVerb(fn)
  local entry
  for _, c in ipairs(NS.COMMANDS) do if c[1] == "farm" then entry = c end end
  assertTrue(entry ~= nil, "a /lh farm verb exists")
  local real, calls = entry[3], {}
  entry[3] = function(rest) calls[#calls + 1] = rest end
  local ok, err = pcall(fn, calls)
  entry[3] = real
  if not ok then error(err, 0) end
end

test("keybinding: the two farm buttons exist, are named, are not secure, register AnyDown", function()
  -- red under: a missing or renamed button (the key clicks nothing), a secure template, or no click
  -- registration.
  for _, name in ipairs({ FARM_TOGGLE, FARM_SF }) do
    local b = M.__namedFrames[name]
    assertTrue(b ~= nil, "no frame named " .. name)
    assertEqual(b.__frameType, "Button", name .. ": a plain Button")
    assertEqual(b.__parent, M.UIParent, name .. ": parented to UIParent")
    assertTrue(b.__template == nil, name .. ": no template, so nothing secure")
    assertEqual(b:IsShown(), false, name .. ": hidden")
    assertEqual(table.concat(b.__clicks or {}, ","), "AnyDown", name .. ": registered for AnyDown")
  end
end)

test("keybinding: the farm labels are set and say what each binding does", function()
  assertEqual(rawget(_G, "BINDING_NAME_" .. FARM_TOGGLE_BINDING), "Toggle farm session")
  assertEqual(rawget(_G, "BINDING_NAME_" .. FARM_SF_BINDING), "Start or finish farm session")
end)

test("keybinding: one farm toggle press is one bare /lh farm; Start or finish picks the word", function()
  -- red under: a press that calls the panel or the model directly (it skips the verb's gate), a press
  -- that runs the verb twice, or Start or finish naming the wrong word for the session's state.
  NS.Schema:Set("settings.enabled", true)
  withFarmVerb(function(calls)
    local t = M.__namedFrames[FARM_TOGGLE]
    t:GetScript("OnClick")(t, "LeftButton", true)
    assertEqual(#calls, 1, "one press, one verb call")
    assertEqual(calls[1], "", "the bare verb toggles the panel")
    local sf = M.__namedFrames[FARM_SF]
    local realActive = NS.Farm.Active
    local open = false
    NS.Farm.Active = function() return open and {} or nil end
    local ok, err = pcall(function()
      sf:GetScript("OnClick")(sf, "LeftButton", true)
      open = true
      sf:GetScript("OnClick")(sf, "LeftButton", true)
    end)
    NS.Farm.Active = realActive
    if not ok then error(err, 0) end
    assertEqual(table.concat(calls, ","), ",start,finish", "no session: start; a session open: finish")
  end)
end)

test("keybinding: a farm press refuses with the RefusalLine while the addon cannot act", function()
  -- red under: a press that runs the verb during a refusal by hold, or one that says nothing.
  withFarmVerb(function(calls)
    local realRefusal, realPrint, printed = NS.RefusalLine, NS.Print, {}
    NS.RefusalLine = function() return "refused for the test." end
    NS.Print = function(line) printed[#printed + 1] = line end
    local ok, err = pcall(function()
      for _, name in ipairs({ FARM_TOGGLE, FARM_SF }) do
        local b = M.__namedFrames[name]
        b:GetScript("OnClick")(b, "LeftButton", true)
      end
    end)
    NS.RefusalLine, NS.Print = realRefusal, realPrint
    if not ok then error(err, 0) end
    assertEqual(#calls, 0, "no verb call while refused")
    assertEqual(table.concat(printed, "|"), "refused for the test.|refused for the test.", "one line per press")
  end)
end)

test("keybinding: the farm buttons exist on a degraded install (no Launcher library)", function()
  local _, _, mocks = dofile("tests/degraded_env.lua")()
  for _, name in ipairs({ FARM_TOGGLE, FARM_SF }) do
    local b = mocks.__namedFrames[name]
    assertTrue(b ~= nil, "no " .. name .. " on the degraded path")
    assertEqual(type(b:GetScript("OnClick")), "function", name .. " has its click handler")
  end
end)
