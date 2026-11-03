-- tests/test_skin_chrome.lua — the History window's and the export modal's chrome on the skin
-- (LH-02; core/SkinSetup.lua's NS.Skin over LibKa0s-Skin-1.0, skinning-§3).
--
-- What this pins: every chrome surface of the two windows draws from the skin's tokens, Ka0s
-- Default draws the values these surfaces drew before the skin engine, and a skin switch repaints
-- every one of them live, with no reload: the window edge (the Shell), the title bar and its
-- divider, the close control, the tab labels and underline, the filter bar's dropdowns, search box
-- and buttons (one flat-button helper, B.MakeFlatButton, for both windows), the footer and the
-- export modal's title, which nothing tinted before. And the degraded facade still draws the
-- flat button and the divider today's way.
--
-- THE PAINT RECORDER. The shared mock's CreateTexture answers the frame itself, and its frames
-- carry no BackdropTemplate methods, so a primitive's paint is invisible there. Each window case
-- therefore builds FRESH windows under the kit's opt-in recorder (tests/_kit/mock_paint.lua), with
-- the session's windows swapped out (B:_SwapWindowForTest, E:_SwapWindowForTest) and put back, the
-- recorder restored and the skin reset to Ka0s Default whatever the case raised.
--
-- After tests/test_skinsetup.lua, whose reset this file repeats for the same reason (see reset).

local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local B, E = NS.Browser, NS.Export
local Skin = mocks.LibStub("LibKa0s-Skin-1.0")
local OptionsLib = mocks.LibStub("LibKa0s-Options-1.0")
local installPaint = dofile("tests/_kit/mock_paint.lua")
local SW = dofile("tests/skin_support.lua")
local OWNER = "LootHistory"

-- ── the skin back on Ka0s Default ───────────────────────────────────────────────────────────────
--
-- tests/test_skinsetup.lua's reset, for the same two reasons: a skin change queues the library's
-- settings-page re-render on the kit's timers, and away from Ka0s Default the library's page
-- backdrop texture IS the page in this harness (the kit's CreateTexture), so the way back hides the
-- page. Both are put right here.
local WAS_SHOWN
local function reset()
  if not WAS_SHOWN then
    WAS_SHOWN = {}
    for ctx in pairs(OptionsLib.__shownPages or {}) do
      if ctx.panel and ctx.panel:IsShown() then WAS_SHOWN[ctx] = true end
    end
  end
  NS.WriteSkinChoice("ka0s", "ka0s")
  Skin:SetChoice(OWNER, "ka0s", "ka0s")
  mocks.__fireTimers()
  for ctx in pairs(WAS_SHOWN) do
    local panel = ctx.panel
    if rawequal(rawget(panel, "__ka0sSkinBg"), panel) then rawset(panel, "__ka0sSkinBg", nil) end
    if not (panel:IsShown() and OptionsLib.__shownPages[ctx]) then
      panel:Show()
      panel:__fire("OnShow")
    end
  end
  mocks.__fireTimers()
end

-- ── fresh windows under the recorder ────────────────────────────────────────────────────────────

-- Every B field EnsureFrame and BuildFilterBar (re)write, put back after a fresh build.
local B_KEYS = { "_dd", "_search", "_onSearchText", "_autocomplete", "_exportBtn", "_ddWidths", "_bar",
                 "_barCtl", "_barW", "_footer", "_dbFooter", "_minW", "_minH" }

local function withFreshWindows(fn)
  reset()
  local saved = {}
  for _, k in ipairs(B_KEYS) do saved[k] = B[k] end
  local filter, special = B.activeFilter, #mocks.UISpecialFrames
  local restorePaint = installPaint(mocks)
  local oldWin, oldExp = B:_SwapWindowForTest(nil), E:_SwapWindowForTest(nil)
  local ok, err = pcall(function()
    B:Show()
    E:Open({ title = "Export History", providers = {} })
    fn(B:GetWindow(), E:Window())
  end)
  local win, exp = B:GetWindow(), E:Window()
  if win and win ~= oldWin then win:Hide() end
  if exp and exp ~= oldExp then exp:Hide() end
  B:_SwapWindowForTest(oldWin)
  E:_SwapWindowForTest(oldExp)
  restorePaint()
  for _, k in ipairs(B_KEYS) do B[k] = saved[k] end
  B.activeFilter = filter
  for i = #mocks.UISpecialFrames, special + 1, -1 do table.remove(mocks.UISpecialFrames, i) end
  reset()
  if not ok then error(err, 0) end
end

-- "r,g,b,a" at three decimals, alpha 1 when absent: one spelling for a recorded and a token color.
local function rgba(c)
  if type(c) ~= "table" then return tostring(c) end
  return ("%.3f,%.3f,%.3f,%.3f"):format(c[1], c[2], c[3], c[4] or 1)
end
local function tokenOf(name) return rgba({ Skin:Color(OWNER, name) }) end

local function textColor(fs) return rgba(rawget(fs, "__textColor")) end

-- The recorded line the Divider primitive drew on the divider frame's holder.
local function dividerLine(bar)
  for _, child in ipairs({ bar:GetChildren() }) do
    for _, r in ipairs(rawget(child, "__paintRegions") or {}) do
      if rawget(r, "__color") then return r end
    end
  end
end

-- The export modal's Export to CSV button: its child whose label reads so.
local function csvButton(exp)
  for _, child in ipairs({ exp:GetChildren() }) do
    local fs = rawget(child, "text")
    if type(fs) == "table" and rawget(fs, "__text") == "Export to CSV" then return child end
  end
end

local function recorded(frame, prim)
  local rec = Skin.painted[frame]
  return rec ~= nil and rec.owner == OWNER and rec.calls[prim] ~= nil
end

-- Every chrome color the two windows draw, against `want(name)` (a token name -> "r,g,b,a").
local function assertChrome(win, exp, want, label)
  assertEqual(rgba(rawget(win, "__backdropColor")), want("win.bg"), label .. ": the window fill")
  -- Since LibKa0s v1.78.0 (SkinPaint 9) the edge is a region of a holder above the window's
  -- children, so a title bar or footer cannot cover it at the corners.
  local edge = Skin.painted[win] and Skin.painted[win].regions.edgeTop
  assertTrue(edge ~= nil, label .. ": the window has no edge on its holder")
  assertEqual(rgba(rawget(edge, "__color")), want("win.border"), label .. ": the window edge")
  assertEqual(textColor(win.title), want("title.text"), label .. ": the window title")
  -- No line under the title (R4-SEP, Ka0sAddonsCommonTasks docs/2026-11-03-SMOKE_ROUND4): the
  -- 1px `dividerBar` stays only as the tab strip's anchor and draws nothing in any skin.
  assertTrue(dividerLine(win.dividerBar) == nil, label .. ": a line is drawn under the title")
  for name, tab in pairs(win.tabs) do
    assertTrue(recorded(tab, "Tab"), label .. ": tab " .. name .. " is the skin's Tab")
    local regions = Skin.painted[tab].regions
    local active = regions.selected == true
    assertEqual(textColor(tab.label), want(active and "tab.onText" or "tab.text"), label .. ": tab " .. name)
    assertTrue(regions.fill ~= nil, label .. ": tab " .. name .. " has no backing")
    if active then
      assertEqual(rgba(rawget(regions.line, "__color")), want("tab.onLine"), label .. ": tab underline " .. name)
    end
  end
  assertEqual(textColor(B._footer), want("text.disabled"), label .. ": the footer")
  assertEqual(textColor(B._dbFooter), want("text.disabled"), label .. ": the DB-size footer")
  for _, key in ipairs({ "export", "save", "reset", "clear" }) do
    local b = B._barCtl[key]
    assertEqual(rgba(rawget(b, "__backdropColor")), want("btn.bg"), label .. ": " .. key .. " fill")
    assertEqual(rgba(rawget(b, "__backdropBorderColor")), want("btn.border"), label .. ": " .. key .. " edge")
    assertEqual(textColor(b.text), want("btn.text"), label .. ": " .. key .. " label")
  end
  assertEqual(textColor(exp.titleFS), want("title.text"), label .. ": the export modal's title")
  local csv = csvButton(exp)
  assertTrue(csv ~= nil, label .. ": no Export to CSV button found")
  assertEqual(rgba(rawget(csv, "__backdropColor")), want("btn.bg"), label .. ": Export to CSV fill")
  assertEqual(textColor(csv.text), want("btn.text"), label .. ": Export to CSV label")
  if csv.icon then
    assertEqual(rgba(rawget(csv.icon, "__vertex")), want("btn.icon"), label .. ": Export to CSV mark")
  end
  assertEqual(rgba(rawget(exp, "__backdropColor")), want("win.bg"), label .. ": the export modal's fill")
end

-- Today's values, the literals these surfaces drew before the skin engine.
local TODAY = {
  ["win.bg"] = { 0.06, 0.06, 0.08, 0.92 }, ["win.border"] = { 0, 0, 0, 1 },
  ["title.text"] = { 1, 0.82, 0 }, ["divider"] = { 0.24, 0.24, 0.27, 0.85 },
  ["tab.onText"] = { 1, 0.82, 0 }, ["tab.text"] = { 0.7, 0.7, 0.72 }, ["tab.onLine"] = { 1, 0.82, 0 },
  -- The tabs read these since the text roles took over (the same gold and gray on Ka0s Default).
  ["text.accent"] = { 1, 0.82, 0 }, ["text.muted"] = { 0.7, 0.7, 0.72 },
  ["text.disabled"] = { 0.5, 0.5, 0.5 },
  ["btn.bg"] = { 0.1, 0.1, 0.12, 0.9 }, ["btn.border"] = { 0.24, 0.24, 0.27, 0.9 },
  ["btn.text"] = { 1, 1, 1 }, ["btn.hover"] = { 1, 0.82, 0 }, ["btn.icon"] = { 0.85, 0.85, 0.85 },
}
local function today(name) return rgba(TODAY[name]) end

-- ── Ka0s Default ────────────────────────────────────────────────────────────────────────────────

test("skin chrome: on Ka0s Default every chrome surface draws the value it drew before skins", function()
  withFreshWindows(function(win, exp)
    assertChrome(win, exp, today, "Ka0s Default")
    -- The backdrop the flat button wears is the one both old copies spelled out.
    local bd = rawget(B._exportBtn, "__backdrop")
    assertEqual(bd.edgeSize, 1, "the flat button's edge is 1px")
    assertEqual(bd.insets.left, 1, "with 1px insets")
    assertEqual(bd.bgFile, "Interface\\Buttons\\WHITE8X8")
  end)
end)

test("skin chrome: every surface is painted for this addon's owner, so a switch reaches it", function()
  withFreshWindows(function(win, exp)
    assertTrue(recorded(win, "Shell"), "the window edge is the skin's Shell")
    assertTrue(recorded(win.titleBar, "TitleBar"), "the title bar is the skin's TitleBar")
    assertTrue(not recorded(win.dividerBar, "Divider"), "the title bar has a Divider under it (R4-SEP)")
    assertTrue(recorded(win.closeButton, "CloseButton"), "the close control is the skin's CloseButton")
    assertTrue(recorded(B._footer, "Text") and recorded(B._dbFooter, "Text"), "both footers are skin text")
    for key, ctl in pairs(B._barCtl) do
      if key == "search" then
        assertTrue(recorded(ctl, "EditBox"), "the search box is painted for the owner")
      elseif B._dd[key] then
        assertEqual(ctl.__owner, OWNER, "dropdown " .. key .. " names the owner")
        assertTrue(recorded(ctl, "Dropdown"), "dropdown " .. key .. " is painted for the owner")
      else
        assertTrue(recorded(ctl, "Button"), key .. " is the skin's Button")
      end
    end
    assertTrue(recorded(exp, "Shell"), "the export modal's edge is the skin's Shell")
    assertTrue(recorded(csvButton(exp), "Button"), "Export to CSV is the skin's Button")
    -- No line under the title (R4-SEP): the anchor frame holds no line, and no `divider` field
    -- names a texture for the window edge to tint.
    assertTrue(dividerLine(win.dividerBar) == nil, "a line is drawn under the title")
    assertTrue(rawget(win, "divider") == nil, "a `divider` field the window edge would tint")
  end)
end)

test("skin chrome: a flat button is white at rest and gold under the pointer, its tip in gtip.body", function()
  withFreshWindows(function()
    local b = B._exportBtn
    local lines, stock = {}, rawget(mocks.GameTooltip, "AddLine")
    rawset(mocks.GameTooltip, "AddLine", function(_, text, r, g, bl)
      lines[#lines + 1] = { text = text, c = rgba({ r, g, bl }) }
    end)
    local ok, err = pcall(function()
      b:__fire("OnEnter")
      assertEqual(textColor(b.text), today("btn.hover"), "gold under the pointer, as before")
      assertEqual(#lines, 1, "the action's tooltip shows")
      assertEqual(lines[1].c, rgba({ 0.9, 0.9, 0.9 }), "the tooltip line in gtip.body (.9, as before)")
      b:__fire("OnLeave")
      assertEqual(textColor(b.text), today("btn.text"), "white again")
    end)
    rawset(mocks.GameTooltip, "AddLine", stock)
    if not ok then error(err, 0) end
  end)
end)

-- ── a skin switch ───────────────────────────────────────────────────────────────────────────────

test("skin chrome: a skin switch repaints every chrome surface live, and Ka0s Default puts it back", function()
  withFreshWindows(function(win, exp)
    NS.ApplySkinChoice("ka0s", "obsidian")
    -- The case means something only where Obsidian differs from today.
    for _, name in ipairs({ "win.bg", "tab.onText", "btn.bg", "btn.text", "title.text" }) do
      assertTrue(tokenOf(name) ~= today(name), "Obsidian's " .. name .. " is today's value: pick another skin")
    end
    assertChrome(win, exp, tokenOf, "Obsidian")
    local b = B._barCtl.save
    b:__fire("OnEnter")
    assertEqual(textColor(b.text), tokenOf("btn.hover"), "the hover color follows the skin")
    b:__fire("OnLeave")
    local close = win.closeButton
    if close.icon then
      assertEqual(rgba(rawget(close.icon, "__vertex")), tokenOf("close.rest"), "the close control at rest")
    end
    -- SelectTab paints the labels from the skin too (on History, the one pane this window built:
    -- another tab's pane would attach its module to this throwaway window).
    for _, tab in pairs(win.tabs) do tab.label:SetTextColor(0, 0, 0) end
    B:SelectTab("History")
    for name, tab in pairs(win.tabs) do
      assertEqual(textColor(tab.label), tokenOf(name == "History" and "tab.onText" or "tab.text"),
        "SelectTab paints tab " .. name .. " in the skin")
    end

    NS.ApplySkinChoice("ka0s", "ka0s")
    assertChrome(win, exp, today, "back on Ka0s Default")
  end)
end)

-- Cause L8 and L9 of the full skinning run: the History grip names its owner, so a skin that tints
-- the grip reaches it, and the export modal's bar is `title.height` with its title placed by the skin.
test("skin chrome: the History grip follows the skin, and the export title bar is title.height", function()
  withFreshWindows(function(win, exp)
    assertEqual(exp.titleBar:GetHeight(), Skin:Token(OWNER, "title.height"), "the export bar's height")
    assertTrue(recorded(exp.titleBar, "TitleBar"), "the export bar is the skin's TitleBar")
    local grip, spy = win.resizeGrip, {}
    rawset(grip, "GetNormalTexture", function() return spy end)
    function spy.SetVertexColor(_, r, g, b) spy.c = rgba({ r, g, b }) end
    function spy.GetObjectType() return "Texture" end
    function spy.SetDesaturated() end
    Skin:SetChoice(OWNER, "ka0s", "obsidian")
    local want = rgba({ Skin:Color(OWNER, "icon.grip") })
    assertTrue(want ~= "nil,nil,nil,1", "the skin tints no grip")
    assertEqual(spy.c ~= nil and spy.c:sub(1, 17), want:sub(1, 17), "the grip takes the skin's tint")
  end)
end)

-- Cause L6: the strip names its owner, so the library tints its mark, and a switch reaches it.
test("skin chrome: the test strip's info mark takes icon.tint and follows a switch", function()
  withFreshWindows(function(win)
    local strip = NS.MakeTestStrip(win, "strip")
    local mark = strip.__icon
    assertTrue(mark ~= nil and recorded(mark, "Mark"), "the strip's mark is the skin's Mark")
    assertEqual(rgba(rawget(mark, "__vertex")), tokenOf("icon.tint"), "Ka0s Default's tint")
    local before = rawget(mark, "__vertex")
    Skin:SetChoice(OWNER, "ka0s", "obsidian")
    assertTrue(rgba(rawget(mark, "__vertex")) ~= rgba(before), "the switch moved no tint")
    assertEqual(rgba(rawget(mark, "__vertex")), tokenOf("icon.tint"), "the switch skin's tint")
  end)
end)

-- ── the arity rule and the degraded facade ──────────────────────────────────────────────────────

test("skin chrome: NS.SkinColor keeps a call site's arity (three components when opaque)", function()
  assertEqual(select("#", NS.SkinColor("tab.onText")), 3, "an opaque token answers r, g, b")
  assertEqual(select("#", NS.SkinColor("btn.bg")), 4, "a translucent token answers r, g, b, a")
  assertEqual(NS.SkinColor("no.such.token"), nil)
end)

test("skin chrome: the degraded facade draws a tab and a checkbox, and MarkText keeps its markup", function()
  local dns, _, dm = dofile("tests/degraded_env.lua")()
  local S = dns.Skin
  local tab = dm.CreateFrame("Button", nil, dm.UIParent)
  tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  S.Tab(tab, { text = tab.label, selected = false })
  assertEqual(rgba(tab.label.__color), today("tab.text"))
  S.SetTabSelection(tab, true)
  assertEqual(rgba(tab.label.__color), today("tab.onText"))
  -- The base mock's CreateTexture answers the frame itself, so the box hands out its own textures.
  local box = SW.checkButton(dm.CreateFrame("CheckButton", nil, dm.UIParent))
  local textures = {}
  rawset(box, "CreateTexture", function()
    textures[#textures + 1] = dm.CreateFrame("Frame")
    return textures[#textures]
  end)
  rawset(dm, "hooksecurefunc", SW.hooksecurefunc)
  S.Checkbox(box)
  assertEqual(#textures, 2, "the box and the tick")
  local tick = textures[2]
  assertEqual(tick:IsShown(), false, "the tick starts hidden")
  box:SetChecked(true)
  assertEqual(tick:IsShown(), true, "the tick shows while checked")
  box:SetChecked(false)
  assertEqual(tick:IsShown(), false, "the tick hides again")
  assertEqual(rgba({ dns.SkinColor("menu.text") }), rgba({ 0.9, 0.9, 0.9, 1 }), "the row menu's label has its token")
  assertEqual(S.MarkText("a\\b", 14), "|Ta\\b:14:14|t")
end)

test("skin chrome: the degraded window edge hides a frame's divider, as Core.ApplySkin does (R4-SEP)", function()
  local dns, _, dm = dofile("tests/degraded_env.lua")()
  local f = dm.CreateFrame("Frame", nil, dm.UIParent, "BackdropTemplate")
  local d = f:CreateTexture(nil, "ARTWORK")
  local tinted
  rawset(d, "SetColorTexture", function() tinted = true end)
  f.divider = d
  d:Show()
  dns.ApplySkin(f)
  assertTrue(not d:IsShown(), "a line under the title stays shown on a degraded install")
  assertTrue(not tinted, "the degraded edge tints a line under the title")
end)

test("skin chrome: the degraded facade draws the flat button and the divider today's way", function()
  local dns, _, dm = dofile("tests/degraded_env.lua")()
  local S = dns.Skin
  local b = dm.CreateFrame("Button", nil, dm.UIParent, "BackdropTemplate")
  local seen = {}
  rawset(b, "SetBackdrop", function(_, t) seen.bd = t end)
  rawset(b, "SetBackdropColor", function(_, ...) seen.fill = rgba({ ... }) end)
  rawset(b, "SetBackdropBorderColor", function(_, ...) seen.edge = rgba({ ... }) end)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  S.Button(b)
  assertEqual(seen.bd and seen.bd.edgeSize, 1, "the WHITE8X8 box at edgeSize 1")
  assertEqual(seen.fill, today("btn.bg"))
  assertEqual(seen.edge, today("btn.border"))
  assertEqual(rgba(b.text.__color), today("btn.text"))
  b:__fire("OnEnter")
  assertEqual(rgba(b.text.__color), today("btn.hover"))
  b:__fire("OnLeave")
  assertEqual(rgba(b.text.__color), today("btn.text"))

  local bar = dm.CreateFrame("Frame", nil, dm.UIParent)
  local ct
  rawset(bar, "SetColorTexture", function(_, ...) ct = rgba({ ... }) end)   -- the kit's texture is the frame
  S.Divider(bar)
  assertEqual(ct, today("divider"), "the divider frame's line in today's gray")
end)

-- ── the header on the title band (R5-WIN) ───────────────────────────────────────────────────────
--
-- R5-WIN of Ka0sAddonsCommonTasks docs/2026-11-03-SMOKE_ROUND5 (feedback items 2 and 5; the lead's
-- calls 2 and 6): every header child is anchored LEFT, CENTER or RIGHT to the title band's own frame
-- (S.Band, LibKa0s SkinPaintExtras minor 17) at y 0, in every skin, and a child title bar under
-- noTopBar takes the band's rect. The band itself sits at Shell's inset (`win.borderSize` in from a
-- flat edge, else 1) and is `title.height` tall. Headless, only the anchor shape can be measured: a
-- LEFT, CENTER or RIGHT point on the band at y 0 IS the band's vertical middle.

local CENTERED = { LEFT = true, CENTER = true, RIGHT = true }

-- A region's recorded anchors as { point, rel, relPoint, x, y } lists: the harness's frames
-- (tests/wow_mock.lua) record named fields, the paint recorder's regions positional ones.
local function points(region)
  local out = {}
  for _, e in ipairs(rawget(region, "__points") or {}) do
    if e.point then
      out[#out + 1] = { e.point, e.relativeTo, e.relativePoint, e.x, e.y }
    else
      out[#out + 1] = e
    end
  end
  return out
end

local function bandOf(frame)
  local rec = Skin.painted[frame]
  return rec and rec.regions.band
end

local function assertBand(frame, key, what)
  local t = Skin:ResolveSkin(key)
  local inset = (t["win.borderStyle"] or "flat") == "flat" and t["win.borderSize"] or 1
  local band = bandOf(frame)
  assertTrue(band ~= nil, what .. ": no band holder")
  local pts = points(band)
  assertEqual(#pts, 2, what .. ": the band's two anchors")
  local p1, r1, q1, x1, y1 = unpack(pts[1])
  assertEqual(p1 .. q1, "TOPLEFTTOPLEFT", what .. ": the band's first point")
  assertTrue(r1 == frame, what .. ": the band is on the window")
  assertEqual(x1, inset, what .. ": the band's left inset")
  assertEqual(y1, -inset, what .. ": the band's top inset")
  assertEqual(band:GetHeight(), t["title.height"] or 30, what .. ": the band's height")
  return band
end

local function assertOnBand(region, band, what)
  local pts = points(region)
  assertTrue(#pts >= 1 and #pts <= 2, what .. ": anchored")
  for _, pt in ipairs(pts) do
    local point, rel, relPoint, _, y = unpack(pt)
    assertTrue(CENTERED[point], ("%s: a %s point, never TOP*"):format(what, tostring(point)))
    assertEqual(relPoint, point, what .. ": to the band's own " .. tostring(point))
    assertTrue(rel == band, what .. ": anchored to the band")
    assertEqual(y, 0, what .. ": y 0, the band's middle")
  end
end

-- The rect a frame was last given by SetAllPoints, spied for the replay a skin switch runs.
local function spyAllPoints(f)
  rawset(f, "SetAllPoints", function(self, rel) rawset(self, "__allRect", rel) end)
  rawset(f, "ClearAllPoints", function(self) rawset(self, "__allRect", nil) end)
end

local function assertHeader(frame, bar, title, close, key, what)
  local band = assertBand(frame, key, what)
  assertTrue(rawget(bar, "__allRect") == band, what .. ": the title bar takes the band's rect")
  assertOnBand(title, band, what .. " title")
  assertOnBand(close, band, what .. " close")
  assertEqual(points(close)[1][4], -6, what .. ": the close is 6 px in from the band's right")
end

test("skin chrome: both windows' headers sit on the title band in every skin (R5-WIN)", function()
  withFreshWindows(function(win, exp)
    assertTrue(exp.closeButton ~= nil, "the export modal keeps its close control")
    spyAllPoints(win.titleBar); spyAllPoints(exp.titleBar)
    -- Away first, so the first skin of the loop is a switch too (a choice already worn replays nothing).
    Skin:SetChoice(OWNER, "ka0s", SW.key(Skin))
    for _, def in ipairs(Skin:Skins()) do
      Skin:SetChoice(OWNER, "ka0s", def.key)
      assertHeader(win, win.titleBar, win.title, win.closeButton, def.key, def.key .. ": History")
      assertHeader(exp, exp.titleBar, exp.titleFS, exp.closeButton, def.key, def.key .. ": export")
      local badge = points(win.testBadge)
      assertEqual(#badge, 1, def.key .. ": the badge has one anchor")
      local point, rel, relPoint, _, y = unpack(badge[1])
      assertEqual(point .. relPoint, "LEFTRIGHT", def.key .. ": the badge beside the title")
      assertTrue(rel == win.title and y == 0, def.key .. ": the badge on the title's middle")
    end
  end)
end)
