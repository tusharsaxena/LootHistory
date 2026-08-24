-- tests/test_widgets.lua — the LibKa0s-Widgets-1.0 adoption.
--
-- WHY THIS IS ITS OWN SUITE. Every case here is about the WIDGET rather than about a filter: it
-- exists because this addon deleted ~200 lines of hand-rolled dropdown out of modules/Browser.lua
-- and now leases the same behavior from a vendored library shared with every other Ka0s addon. A
-- reader asking "did the adoption lose anything, and does the degraded install still come up?" has
-- one file to read. The FILTER behavior those dropdowns drive stays in tests/test_browser.lua.
--
-- THE ROWS ARE BUILT FOR REAL. LibKa0s v1.11.0 and v1.11.1 both shipped a crash on the very first
-- click of a dropdown -- `FontString:SetText(): Font not set`, out of a menu row whose glyph
-- FontString was created bare -- and 553 green library cases sailed straight over it because every
-- one of them seeded a stand-in row instead of letting the widget build one. So the cases below
-- fire the dropdown's real OnClick, let the library's own EnsureMenu/Populate/makeMenuRow run, and
-- read the painted row back out. tests/wow_mock.lua was made stricter in the same commit for the
-- same reason: a FontString there is a distinct object and raises on SetText until it has a face.

local T = _G.LH_TEST
local NS, Loader = T.NS, T.Loader
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local B = NS.Browser

-- ── reaching the library's process-wide popup ────────────────────────────────────────────────
--
-- The menu is a file-local singleton inside libs/LibKa0s/Widgets.lua, parented to UIParent and
-- deliberately unreachable from a host (that is the whole reason CloseMenu exists). A suite still
-- has to see it, so it is caught on the way past: CreateFrame is wrapped for the duration of the
-- click and the created frame that carries a `buttons` table is the menu. Nothing is read off a
-- ROW that the library did not paint onto it -- rows are pooled across every dropdown in the
-- process and stashing state on one is the documented way to corrupt another addon's menu.
local function clickAndCaptureMenu(dd)
  local created = {}
  local stock = T.mocks.CreateFrame
  T.mocks.CreateFrame = function(...)
    local f = stock(...)
    created[#created + 1] = f
    return f
  end
  local ok, err = pcall(function() dd:__fire("OnClick") end)
  T.mocks.CreateFrame = stock
  if not ok then error(err, 0) end
  for _, f in ipairs(created) do
    if rawget(f, "buttons") then return f end
  end
  -- Built by an earlier case: the singleton survives, so find it through the dropdown's own click
  -- having repopulated it. Only the first case in the process ever creates it.
  return nil
end

-- The popup, captured once and remembered — every later click repopulates this same frame.
local MENU

local function menuFor(dd)
  local m = clickAndCaptureMenu(dd)
  MENU = m or MENU
  assertTrue(MENU ~= nil, "the library's popup menu was never created by a click")
  return MENU
end

local function rowTexts(m)
  local out = {}
  for i, b in ipairs(m.buttons) do out[i] = b.fs:GetText() end
  return out
end

local GOLD = { 1, 0.82, 0 }
local function isGold(fs)
  local c = fs.__color or {}
  return c[1] == GOLD[1] and c[2] == GOLD[2] and c[3] == GOLD[3]
end

local function newDropdown(width)
  local parent = T.mocks.CreateFrame("Frame")
  return NS.MakeDropdown(parent, width or 120)
end

-- ── the seam ─────────────────────────────────────────────────────────────────────────────────

test("Widgets: the seam builds a real library dropdown, art passed as parameters", function()
  local lib = T.mocks.LibStub("LibKa0s-Widgets-1.0", true)
  assertTrue(lib ~= nil, "LibKa0s-Widgets-1.0 did not register")
  assertEqual(lib.MODULES.Widgets, 4, "this adoption is written against Widgets minor 4")
  local seen
  local stockDropdown = lib.Dropdown
  lib.Dropdown = function(parent, width, opts) seen = opts; return stockDropdown(parent, width, opts) end
  local dd = newDropdown(100)
  lib.Dropdown = stockDropdown
  assertTrue(dd ~= nil, "the seam must return the library's dropdown")
  assertEqual(seen.chevron, NS.Icon("chevron-down"), "the chevron is resolved host-side and passed")
  assertEqual(seen.check, NS.Icon("confirm"), "the multi-select tick is resolved host-side and passed")
  -- glyphFont is a PRECONDITION for a row carrying `glyph`, and a face nothing uses is noise.
  assertEqual(seen.glyphFont, nil,
    "no option this addon builds carries a glyph, so no monospace face may be passed")
end)

test("Widgets: no option table in this addon sets a glyph", function()
  -- The other half of the case above: the seam passing no face is only correct while this stays
  -- true. The class icon and the tick are inline texture markup, not monospace characters.
  for _, path in ipairs({ "modules/Browser.lua", "modules/Export.lua", "core/WidgetsSetup.lua" }) do
    local src = Loader.readFile(path)
    assertTrue(src:find("glyph%s*=") == nil,
      path .. " sets `glyph` on an option, which needs opts.glyphFont passed by the seam")
  end
end)

-- ── a real row build ─────────────────────────────────────────────────────────────────────────

test("Widgets: the first click builds real menu rows through the library's own makeMenuRow",
  function()
    local dd = newDropdown(120)
    dd:SetOptions({
      { value = "all", label = "Source: All" },
      { value = "KILL", label = "Creature" },
      { value = "AH", label = "Auction House", color = { 0.5, 0.6, 0.7 } },
    })
    dd:SetValue("KILL", "Creature")
    local m = menuFor(dd)
    assertEqual(#m.buttons, 3, "one pooled row per option")
    assertEqual(rowTexts(m)[1], "Source: All")
    assertEqual(rowTexts(m)[3], "Auction House")
    -- A row's label and its glyph are two FontStrings, not one object.
    assertTrue(m.buttons[1].fs ~= m.buttons[1].glyph, "label and glyph must be distinct FontStrings")
    -- The single-select row holding the current value is the gold one.
    assertTrue(isGold(m.buttons[2].fs), "the row holding _value is highlighted")
    assertFalse(isGold(m.buttons[1].fs))
    -- An unselected row keeps its own color.
    assertEqual(m.buttons[3].fs.__color[1], 0.5)
  end)

test("Widgets: a selected multi-select row is ticked and gold", function()
  local dd = newDropdown(100)
  dd:SetMulti(true)
  dd:SetOptions({
    { value = "all", label = "Quality: All" },
    { value = 4, label = "Epic" },
  })
  dd:SetSelected({ [4] = true })
  local m = menuFor(dd)
  assertTrue(isGold(m.buttons[2].fs), "a selected multi-select row is gold")
  assertTrue(rowTexts(m)[2]:find("|T", 1, true) == 1,
    "a selected multi-select row carries the tick markup ahead of its label: " .. rowTexts(m)[2])
  assertEqual(rowTexts(m)[1], "Quality: All", "an unselected row is the bare label")
end)

-- ── the two seams that came upstream from this addon ─────────────────────────────────────────

test("Widgets: the Character preset row lights up through its own isActive", function()
  local ck = NS.Util.PlayerKey()
  local dd = newDropdown(146)
  dd:SetMulti(true)
  dd:SetOptions({
    { value = "all", label = "Character: All" },
    { value = "current", label = "Character: Current",
      isActive = function(d)
        local sel = d._selected or {}
        if not sel[ck] then return false end
        for k in pairs(sel) do if k ~= ck then return false end end
        return true
      end },
    { value = ck, label = ck },
  })
  dd:SetSelected({ [ck] = true })
  local m = menuFor(dd)
  assertFalse(isGold(m.buttons[1].fs), "the All sentinel is not lit while something is selected")
  assertTrue(isGold(m.buttons[2].fs),
    "the preset row selects a value that is not its own, so only isActive can light it")
  assertEqual(dd.text:GetText(), "Character: Current",
    "an active preset's own label is the collapsed button's label")
end)

test("Widgets: the Character preset is a one-click 'only me', not a toggle of its own value",
  function()
    local ck = NS.Util.PlayerKey()
    local dd = newDropdown(146)
    dd:SetMulti(true)
    dd:SetOptions({ { value = "all", label = "Character: All" },
                    { value = "current", label = "Character: Current" } })
    dd.presets = { current = function(d) d._selected = { [ck] = true } end }
    dd:SetSelected({ ["Someone-Else"] = true })
    dd:ToggleSelected("current")
    assertEqual(dd._selected[ck], true, "the preset replaces the selection with the current player")
    assertEqual(dd._selected["Someone-Else"], nil, "and drops what was selected before")
    assertEqual(dd._selected.current, nil, "the preset's own value never enters the selection")
  end)

test("Widgets: a selected character with no option row still counts in the collapsed label",
  function()
    -- The option lists are data-driven, so a character with no rows in the current dataset is not
    -- offered. Minor 3 walked the options and asked which were selected, so such a value was
    -- invisible and the button read "Character: All" while the filter was still on.
    local dd = newDropdown(146)
    dd:SetMulti(true)
    dd:SetOptions({ { value = "all", label = "Character: All" },
                    { value = "Ka0z-Realm", label = "Ka0z-Realm" } })
    dd:SetSelected({ ["Ghost-Realm"] = true })
    assertEqual(dd.text:GetText(), "Ghost-Realm", "an off-list selection reads as its raw value")
    dd:SetSelected({ ["Ghost-Realm"] = true, ["Ka0z-Realm"] = true })
    assertEqual(dd.text:GetText(), "Character: 2 selected", "and it still counts")
  end)

-- ── the ten live instances ───────────────────────────────────────────────────────────────────

test("Widgets: the filter bar builds all nine of its dropdowns through the seam", function()
  local saved = B._dd
  local bar = T.mocks.CreateFrame("Frame")
  B:BuildFilterBar(bar)
  local dd = B._dd
  assertTrue(dd ~= nil, "the filter bar must build with the library present")
  for _, key in ipairs({ "group", "date", "bound", "quality", "type", "subtype",
                         "source", "zone", "char" }) do
    assertTrue(type(dd[key]) == "table" and type(dd[key].SetOptions) == "function",
      "dd." .. key .. " is not a library dropdown")
  end
  assertFalse(dd.group.multi, "Group-by is single-select")
  for _, key in ipairs({ "bound", "quality", "type", "subtype", "source", "zone", "char" }) do
    assertEqual(dd[key].multi, true, "dd." .. key .. " must be multi-select")
  end
  assertTrue(dd.char.presets ~= nil and dd.char.presets.current ~= nil,
    "the Character dropdown carries the 'current' preset")
  B._dd = saved
end)

test("Widgets: the Character options fold the class icon into the label, not into an icon field",
  function()
    -- `opt.icon` is NOT in the library and is deliberately not being added: inline |T…|t markup in
    -- a label is measured by the library's menuWidth, which is the supported way to put art on a
    -- row.
    local saved = NS.State.testRecords
    NS.State.testRecords = {
      { ts = 1, char = "Ka0z-Realm", classFile = "MAGE", source = "KILL", quality = 2 },
    }
    local opts = B._options.char()
    NS.State.testRecords = saved
    local row
    for _, o in ipairs(opts) do if o.value == "Ka0z-Realm" then row = o end end
    assertTrue(row ~= nil, "the fixture character must be offered")
    assertEqual(row.icon, nil, "no option may carry an `icon` field; the library has no such seam")
    assertTrue(row.label:find("|A", 1, true) ~= nil or row.label:find("|T", 1, true) ~= nil,
      "the class icon must be folded into the label markup: " .. tostring(row.label))
    assertTrue(row.label:find("Ka0z-Realm", 1, true) ~= nil, "and the name must still be there")
  end)

-- ── CloseMenu from every non-click close path ────────────────────────────────────────────────

local function countingCloseMenu(fn)
  local lib = T.mocks.LibStub("LibKa0s-Widgets-1.0", true)
  local stock, n = lib.CloseMenu, 0
  lib.CloseMenu = function() n = n + 1; return stock() end
  local ok, err = pcall(fn)
  lib.CloseMenu = stock
  if not ok then error(err, 0) end
  return n
end

test("Widgets: the History window's OnHide closes the shared popup", function()
  local win = B:GetWindow() or (function() B:Show(); B:Hide(); return B:GetWindow() end)()
  assertTrue(win ~= nil, "the browser window must be buildable headlessly")
  assertTrue(countingCloseMenu(function() win:__fire("OnHide") end) > 0,
    "OnHide must call CloseMenu -- this is the Escape/UISpecialFrames path")
end)

test("Widgets: Browser:Hide closes the shared popup", function()
  assertTrue(countingCloseMenu(function() B:Hide() end) > 0,
    "the slash-command close must call CloseMenu")
end)

test("Widgets: the export modal's close path closes the shared popup", function()
  -- LIVE BUG BEFORE THE ADOPTION: the modal's close button just called frame:Hide(), and the
  -- UISpecialFrames registration had no OnHide handler at all, so Escape out of the export window
  -- left the Data Set menu floating over the game with nothing left to hide it.
  local created = {}
  local stock = T.mocks.CreateFrame
  T.mocks.CreateFrame = function(...)
    local f = stock(...)
    created[#created + 1] = f
    return f
  end
  NS.Export:Open({ title = "Export History", providers = {}, csv = function() return "" end })
  T.mocks.CreateFrame = stock
  local modal
  for _, f in ipairs(created) do
    if f:GetScript("OnHide") then modal = f end
  end
  assertTrue(modal ~= nil, "the export modal must register an OnHide handler")
  assertTrue(countingCloseMenu(function() modal:__fire("OnHide") end) > 0,
    "the export modal's OnHide must call CloseMenu")
end)

test("Widgets: every frame that owns a dropdown sits below the menu's FULLSCREEN_DIALOG", function()
  -- The popup is at FULLSCREEN_DIALOG and its click-catcher one strata below, at FULLSCREEN. A
  -- host frame at or above either would swallow the outside click that is meant to close the menu.
  local RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
                 FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
  local checked = 0
  for path, pattern in pairs({
    ["modules/Browser.lua"] = 'frame:SetFrameStrata%("([A-Z_]+)"%)',
    ["modules/Export.lua"]  = 'frame:SetFrameStrata%("([A-Z_]+)"%)',
  }) do
    for strata in Loader.readFile(path):gmatch(pattern) do
      checked = checked + 1
      assertTrue(RANK[strata] ~= nil, path .. " names an unknown strata: " .. strata)
      assertTrue(RANK[strata] < RANK.FULLSCREEN,
        path .. " parks a dropdown host at " .. strata .. ", at or above the menu's catcher")
    end
  end
  assertTrue(checked >= 2, "the derivation found no strata calls and is asserting nothing")
end)

-- ── degraded: no library, no surface ─────────────────────────────────────────────────────────

local function loadDegraded()
  local mocks = dofile("tests/wow_mock.lua")()
  local lines = {}
  mocks.DEFAULT_CHAT_FRAME.AddMessage = function(_, line) lines[#lines + 1] = line end
  local ns = {}
  Loader.loadAll(Loader.tocFiles("LootHistory.toc"), ns, mocks)
  return ns, lines, mocks
end

test("degraded install: the dropdown seam answers nil and CloseMenu is a safe no-op", function()
  local ns = loadDegraded()
  assertEqual(ns.MakeDropdown(nil, 100), nil,
    "with no library the seam must answer nil, never a dead control that opens no menu")
  ns.CloseMenu()   -- must not raise: there is no library and so no menu to close
end)

test("degraded install: the filter bar refuses to draw and the browser still comes up", function()
  local ns, _, mocks = loadDegraded()
  ns:InitDB()
  ns.Browser:BuildFilterBar(mocks.CreateFrame("Frame"))
  assertEqual(ns.Browser._dd, nil, "no dropdowns means no _dd, which every reader already guards")
  -- The view/filter paths downstream of the bar all tolerate a nil _dd, so the addon still works.
  local v = ns.Browser:CaptureView()
  assertEqual(v.date, "all")
  ns.Browser:ApplyView(ns.Browser._stockView, "current")
  ns.Browser:Hide()
end)

test("degraded install: the export modal refuses rather than calling methods on a nil dropdown",
  function()
    local ns, lines = loadDegraded()
    ns:InitDB()
    ns.Export:Open({ title = "Export History", providers = {}, csv = function() return "" end })
    local body = table.concat(lines, "\n")
    assertTrue(body:find(ns.LIBKA0S_MISSING, 1, true) ~= nil,
      "the refusal must be explained through the shared cause clause: " .. body)
  end)
