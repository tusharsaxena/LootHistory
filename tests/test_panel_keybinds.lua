-- tests/test_panel_keybinds.lua — the General page's Keybindings tab (options-ui-§20, item 015).
--
-- The tab is the library's: O.KeybindingsTab({ bindings = NS.BINDINGS }) gives the entry and its
-- body, and every capture, slot, conflict and sync rule is LibKa0s's own and pinned there
-- (tests/test_options_keybinds*.lua in LibKa0s). What this suite pins is THIS addon's wiring of it:
-- the hand-drawn General strip (settings/Panel.lua's GENERAL_TABS) ends in it; its rows are
-- NS.BINDINGS, in order, labeled with the client's BINDING_NAME_ text; a key bound through it is the
-- client's key (Kit.keybindThroughTab, over the kit's tests/_kit/mock_bindings.lua, which
-- tests/wow_mock.lua installs); a key set outside it shows in it after UPDATE_BINDINGS, which holds
-- only while the page's own render keeps the library's refreshers and rows alive; and this page's
-- combat lock refuses a write.
--
-- Its own file because tests/test_panel.lua sits at 1000 lines. After the panel suites, which
-- leave the General page built and parked on its first tab; every case here parks it there again.

local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local S = dofile("tests/panel_support.lua")
local show, clickTab, homeTab, tabAt, STRIP = S.show, S.clickTab, S.homeTab, S.tabAt, S.STRIP

local OptionsLib = mocks.LibStub("LibKa0s-Options-1.0")
local BINDING = "CLICK LootHistoryToggleWindow:LeftButton"

local function page() return mocks.__subcategories["General"] end

--- The Keybindings tab's row records from ONE render, in draw order. The tab's render keeps none of
--- them (the library's own `render` discards what O.KeybindRows answers), so they are read off the
--- library's live set, keeping only the rows whose group that render created: the harness's AceGUI
--- fake does not run a released group's OnRelease, so rows of earlier renders stay in the set.
local function rowsOf(ctx, created)
  local order = {}
  for i, w in ipairs(created) do order[w] = i end
  local rows = {}
  for row, c in pairs(OptionsLib.__keybindLive) do
    if c == ctx and not row.dead and order[row.group] then rows[#rows + 1] = row end
  end
  table.sort(rows, function(a, b) return order[a.group] < order[b.group] end)
  return rows
end

--- Open the Keybindings tab and answer its rows; `fn(ctx, rows)` runs with the page on it, and the
--- page goes back to its first tab and the binding store back to empty whatever `fn` raised.
local function onTab(fn)
  local ctx = NS.Panel.general
  mocks.clearBindings()
  local created = clickTab(page(), ctx, tabAt("Keybindings"))
  local ok, err = pcall(fn, ctx, rowsOf(ctx, created))
  mocks.clearBindings()
  homeTab(ctx)
  if not ok then error(err, 0) end
end

test("Keybindings tab: the General strip ends in Keybindings, the library's own entry", function()
  -- options-ui-§20: the LAST tab of the General page, labeled exactly Keybindings, Master controls
  -- still first (options-ui-§15). The strip is hand-drawn, so last means GENERAL_TABS' last entry.
  -- red under: a tab added after it, a `before` placement, a host-typed label, or the tab missing.
  local ctx = NS.Panel.general
  show(page())
  local buttons = ctx.__tabLayout and ctx.__tabLayout.buttons
  assertTrue(buttons ~= nil, "the General page draws a tab strip")
  assertEqual(STRIP[#STRIP], "Keybindings", "the declared strip ends in Keybindings")
  assertEqual(#buttons, #STRIP, #STRIP .. " tabs")
  assertEqual(STRIP[1], "Master controls", "Master controls stays first")
  local last = buttons[#buttons]
  assertEqual(last.__ka0sTabTipLabel, OptionsLib.KEYBIND_STRINGS.TAB_LABEL, "the library's label")
  assertEqual(last.__ka0sTabTip, OptionsLib.KEYBIND_STRINGS.TAB_TIP, "the library's tooltip")
  onTab(function(c)
    assertEqual(c.activeTab, "Keybindings", "the last button opens the Keybindings tab")
  end)
end)

test("Keybindings tab: its rows are NS.BINDINGS in order, labeled with the BINDING_NAME_ text",
  function()
    -- red under: a row list of the panel's own, a row the client's page labels differently, or a
    -- tab whose body is not the library's rows.
    onTab(function(_, rows)
      assertEqual(#rows, #NS.BINDINGS, "one row per binding")
      for i, b in ipairs(NS.BINDINGS) do
        assertEqual(rows[i].command, b.command, "row " .. i .. " is NS.BINDINGS[" .. i .. "]")
        assertEqual(rows[i].label.text, rawget(_G, "BINDING_NAME_" .. b.command),
          "row " .. i .. " shows the client's label")
      end
      assertEqual(rows[1].label.text, "Toggle history browser", "the English")
    end)
  end)

test("Keybindings tab: a key bound through the tab is the client's key (GetBindingKey)", function()
  -- options-ui-§20's Testing bullet: Kit.keybindThroughTab presses a slot and a key as a player
  -- does. red under: a tab that keeps its own copy of the key, or writes a profile instead of the
  -- client's store.
  onTab(function(_, rows)
    local status = T.keybindThroughTab(rows[1], 1, "K", { shift = true })
    assertEqual(mocks.GetBindingKey(BINDING), "SHIFT-K", "the client's store holds the key")
    assertEqual(status, mocks.KEY_BOUND, "the outcome line says so, in the client's words")
    assertEqual(rows[1].slots[1].text, "SHIFT-K", "and Key 1 shows it")
  end)
end)

test("Keybindings tab: a key set outside the tab (SetBinding) shows in it after UPDATE_BINDINGS",
  function()
    -- Options -> Keybindings and this tab are one store. The library repaints on UPDATE_BINDINGS
    -- while a row is on screen; this pins that this page's render leaves its rows live to hear it.
    -- red under: a render that releases the rows it just drew, or a tab that caches a key.
    onTab(function(_, rows)
      assertEqual(rows[1].slots[1].text, mocks.NOT_BOUND, "Key 1 starts unbound")
      assertTrue(mocks.SetBinding("CTRL-J", BINDING), "the client's page binds a key")
      if mocks.__fire then mocks.__fire("UPDATE_BINDINGS") end
      local f = OptionsLib.__keybindEventFrame
      if f and f.__fire and not (f.IsEventRegistered and f:IsEventRegistered("UPDATE_BINDINGS")) then
        f:__fire("OnEvent", "UPDATE_BINDINGS")
      end
      while mocks.__fireTimers() > 0 do end
      assertEqual(rows[1].slots[1].text, "CTRL-J", "the tab shows the key the client's page set")
    end)
  end)

test("Keybindings tab: in combat the tab refuses, and no key is written", function()
  -- options-ui-§20 / §2: no key is bound, cleared or saved in combat.
  -- red under: a write that reaches SetBinding in combat, or a refusal that says nothing.
  -- The tab is opened first: in combat the page's lock refuses the tab switch itself.
  onTab(function(_, rows)
    local realCombat = mocks.InCombatLockdown
    mocks.InCombatLockdown = function() return true end
    local ok, err = pcall(function()
      local status = T.keybindThroughTab(rows[1], 1, "L")
      assertEqual(mocks.GetBindingKey(BINDING), nil, "nothing was bound")
      assertEqual(status, OptionsLib.KEYBIND_STRINGS.COMBAT, "the outcome line refuses")
    end)
    mocks.InCombatLockdown = realCombat
    if not ok then error(err, 0) end
  end)
end)

test("Keybindings tab: the General page's Defaults tooltip ends with O.KEYBINDS_UNCHANGED", function()
  -- options-ui-§20: Defaults and Reset all settings never touch a key, because a key is not a
  -- setting this addon stores, and the button says so before it is clicked.
  -- red under: a Defaults button with no tooltip, or one that does not end with the sentence.
  local tip = NS.Panel.general.panel.defaultsTooltip
  assertEqual(type(tip), "string", "the Defaults button has a tooltip")
  local tail = NS.Options.KEYBINDS_UNCHANGED
  assertEqual(tip:sub(-#tail), tail, "it ends with the library's sentence: " .. tostring(tip))
end)

test("Panel: the General Defaults tooltip is the library's Reset all settings tooltip (item 020)",
  function()
    -- LOO-L-new4 (U-04, options-ui-§12): the header Defaults IS the global reset, so it reads the
    -- reset's words from O.ResetAllTooltip -- the same descriptor read the composed button makes --
    -- with O.KEYBINDS_UNCHANGED after it, and no host wording around the member.
    -- red under: a host-written lead in front of the library's text, or the two tooltips drifting.
    local O = NS.Options
    assertEqual(NS.Panel.general.panel.defaultsTooltip, O.ResetAllTooltip(O.KEYBINDS_UNCHANGED))
  end)
