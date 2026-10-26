-- tests/test_skin_settings.lua — this addon's own settings widgets on the skin (LH-06;
-- core/SkinSetup.lua's NS.SkinPaintAce / NS.SkinPaintAceTree / NS.SkinOnRelease over
-- LibKa0s-Skin-1.0's SkinAce, skinning-§3).
--
-- What this pins: every AceGUI widget settings/Panel.lua acquires itself is painted for this owner
-- under a non-default skin, EVEN THROUGH A HANDLE THAT IS NOT THE LIBRARY'S OWNER PROXY (each case
-- renders through the raw AceGUI fake, so the host's own NS.SkinPaintAce is what paints); a release
-- hands the widget back stock (the pool stays clean for the next acquirer); the AH price
-- placeholder's cleanup rides the chain rather than AceGUI's one OnRelease callback and still runs;
-- the AH table's session-held check boxes follow a switch; the Profiles page paints the tree
-- AceConfigDialog drew; Ka0s Default paints them like every other skin (it sets every token since
-- LibKa0s SkinDefs minor 8); and the degraded seam paints nothing and still runs a host's release work.
--
-- The kit's widgets are recorders without AceGUI's regions, so "painted" is read where the library
-- keeps it: `Skin.__ace[widget].owner` (SkinAce.lua's weak state table), set while owned and
-- cleared by the restore. After tests/test_skin_insights.lua, whose reset this file repeats.

local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local Skin = mocks.LibStub("LibKa0s-Skin-1.0")
local OptionsLib = mocks.LibStub("LibKa0s-Options-1.0")
local PS = dofile("tests/panel_support.lua")
local AceGUI = PS.AceGUI
local OWNER = "LootHistory"

-- ── the skin back on Ka0s Default (tests/test_skin_chrome.lua's reset) ──────────────────────────
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

local function ownerOf(w)
  local st = Skin.__ace and Skin.__ace[w]
  return st and st.owner or nil
end

-- The types SkinAce has a painter for; a SimpleGroup has none and is never owned.
local PAINTED = { Button = true, CheckBox = true, Label = true, InlineGroup = true }

--- Run `fn` on `skin` with NS.AceGUI swapped for the raw AceGUI fake (no owner proxy), so only the
--- host's own NS.SkinPaintAce can paint what the panel acquires. Put back whatever `fn` raised.
local function withRawAce(skin, fn)
  reset()
  local saved = NS.AceGUI
  local ctx = NS.Panel.general
  local ok, err = pcall(function()
    NS.ApplySkinChoice("ka0s", skin)
    mocks.__fireTimers()
    NS.AceGUI = AceGUI
    fn(ctx)
  end)
  NS.AceGUI = saved
  PS.homeTab(ctx)
  reset()
  if not ok then error(err, 0) end
end

--- Click `tab` and answer the widgets of a painted type that render acquired.
local function paintedOn(ctx, tab)
  local out = {}
  for _, w in ipairs(PS.clickTab(mocks.__subcategories["General"], ctx, PS.tabAt(tab))) do
    if PAINTED[w.type] then out[#out + 1] = w end
  end
  return out
end

-- ── the panel's own widgets ─────────────────────────────────────────────────────────────────────

test("skin settings: under a non-default skin the panel's own widgets paint, past the proxy", function()
  -- red under: dropping NS.SkinPaintAce from settings/Panel.lua's acquire (the raw handle here
  -- paints nothing of its own).
  withRawAce("obsidian", function(ctx)
    for _, tab in ipairs({ "Filters", "History" }) do
      local ws = paintedOn(ctx, tab)
      assertTrue(#ws > 0, tab .. " acquired no widget of a painted type")
      for _, w in ipairs(ws) do
        assertEqual(ownerOf(w), OWNER, tab .. ": a " .. w.type .. " is painted for this owner")
        assertTrue(type(rawget(w, "OnRelease")) == "function", tab .. ": its release is wrapped")
      end
    end
  end)
end)

test("skin settings: a release hands every painted widget back stock, the pool clean", function()
  -- red under: a host that replaced the widget's OnRelease outright (the restore never runs).
  withRawAce("obsidian", function(ctx)
    local ws = paintedOn(ctx, "History")
    for _, w in ipairs(ws) do assertEqual(ownerOf(w), OWNER, "owned before the release") end
    PS.homeTab(ctx)   -- ClearScroll: the History tab's scroll children go back to the pool
    for _, w in ipairs(ws) do
      -- The kit's ReleaseChildren forgets a group's children rather than releasing each (its
      -- documented difference), so a nested widget is released here as the client's would be.
      if not w.__released then AceGUI:Release(w) end
      assertEqual(ownerOf(w), nil, "and nothing of this owner rides it to the next acquirer")
      assertEqual(rawget(w, "OnRelease"), nil, "the wrapper is taken back")
    end
  end)
end)

test("skin settings: under Ka0s Default the panel's own widgets paint like every skin's", function()
  -- Ka0s Default is a skin like the others (LibKa0s SkinAce minor 2): no branch leaves it stock.
  withRawAce("ka0s", function(ctx)
    for _, tab in ipairs({ "Filters", "History" }) do
      local ws = paintedOn(ctx, tab)
      assertTrue(#ws > 0, tab .. " acquired no widget of a painted type")
      for _, w in ipairs(ws) do
        assertEqual(ownerOf(w), OWNER, tab .. ": a " .. w.type .. " is painted for this owner")
        assertTrue(type(rawget(w, "OnRelease")) == "function", tab .. ": its release is wrapped")
      end
    end
  end)
end)

-- ── the AH price tab: the placeholder's chained cleanup and the session-held check boxes ─────────

test("skin settings: the AH placeholder's cleanup rides the release chain and still parks the host", function()
  -- red under: the placeholder taking AceGUI's one OnRelease callback again (SetCallback), or the
  -- chain losing the host cleanup.
  withRawAce("obsidian", function(ctx)
    PS.clickTab(mocks.__subcategories["General"], ctx, PS.tabAt("AH price"))
    PS.homeTab(ctx)
    local host = ctx._priHost
    rawset(host, "SetParent", function(self, p) self.__lhParent = p; return self end)
    rawset(host, "GetParent", function(self) return self.__lhParent end)
    local ok, err = pcall(function()
      PS.clickTab(mocks.__subcategories["General"], ctx, PS.tabAt("AH price"))
      local placeholder
      for _, w in ipairs(AceGUI.__created) do
        if w.frame ~= nil and w.frame == host:GetParent() then placeholder = w end
      end
      assertTrue(placeholder ~= nil, "the host sits on a placeholder this render created")
      assertEqual(placeholder.callbacks.OnRelease, nil, "AceGUI's one OnRelease callback is left free")
      assertTrue(type(rawget(placeholder, "OnRelease")) == "function", "the cleanup is chained on")
      AceGUI:Release(placeholder)
      assertTrue(host:GetParent() == ctx.panel, "the released placeholder hands the host back")
      assertFalse(host:IsShown(), "and the parked host is hidden")
      assertEqual(rawget(placeholder, "OnRelease"), nil, "the chain is taken back")
    end)
    rawset(host, "SetParent", nil); rawset(host, "GetParent", nil); host.__lhParent = nil
    if not ok then error(err, 0) end
  end)
end)

test("skin settings: the AH table's held check boxes are painted on Ka0s Default and follow a switch", function()
  -- They are parented to the pooled row frames and never re-acquired, so the library's re-render
  -- never reaches them. red under: dropping NS.SkinPaintAce from repaintAuctionTable.
  reset()
  local ctx = NS.Panel.general
  local ok, err = pcall(function()
    PS.clickTab(mocks.__subcategories["General"], ctx, PS.tabAt("AH price"))
    PS.homeTab(ctx)
    for _, r in ipairs(ctx._priRows) do assertEqual(ownerOf(r.check), OWNER, "painted on Ka0s Default") end
    NS.ApplySkinChoice("ka0s", "obsidian")
    for _, r in ipairs(ctx._priRows) do assertEqual(ownerOf(r.check), OWNER, "painted on the switch") end
    NS.ApplySkinChoice("ka0s", "ka0s")
    for _, r in ipairs(ctx._priRows) do assertEqual(ownerOf(r.check), OWNER, "still painted on the way back") end
  end)
  PS.homeTab(ctx)
  reset()
  if not ok then error(err, 0) end
end)

-- ── the Profiles page ───────────────────────────────────────────────────────────────────────────

--- Build the Profiles page over stub AceConfig libraries whose Open draws one raw CheckBox into the
--- container, as AceConfigDialog acquires from AceGUI itself; answers that CheckBox after one show.
local function profilesRow(skin)
  local libs = mocks.__libs
  local drawn
  libs["AceDBOptions-3.0"] = { GetOptionsTable = function() return { type = "group" } end }
  libs["AceConfig-3.0"] = { RegisterOptionsTable = function() end }
  libs["AceConfigDialog-3.0"] = {
    Open = function(_, _, container)
      container:ReleaseChildren()
      drawn = AceGUI:Create("CheckBox")
      container:AddChild(drawn)
    end,
  }
  reset()
  local ok, err = pcall(function()
    NS.ApplySkinChoice("ka0s", skin)
    assertTrue(NS.ProfilesPage.Build({}) ~= nil, "the page registered")
    local ctx = NS.ProfilesPage.ctx
    ctx.panel:Show()
    ctx.panel:__fire("OnShow")
  end)
  libs["AceDBOptions-3.0"], libs["AceConfig-3.0"], libs["AceConfigDialog-3.0"] = nil, nil, nil
  mocks.__subcategories["Profiles"] = nil
  -- The kit's Hide fires no script, so OnHide is fired too: the library lets go of the page in its
  -- combat lock, or the page stays registered for PLAYER_REGEN_* into the suites after this one.
  if NS.ProfilesPage.ctx then
    NS.ProfilesPage.ctx.panel:Hide()
    NS.ProfilesPage.ctx.panel:__fire("OnHide")
  end
  local row = drawn
  if row and not row.__released then AceGUI:Release(row) end
  reset()
  if not ok then error(err, 0) end
  return row
end

test("skin settings: the Profiles page paints the tree AceConfigDialog drew, Ka0s Default too", function()
  -- red under: dropping NS.SkinPaintAceTree from the Profiles renderer. The row is read the moment
  -- it is drawn, so a recorder stands in for the release that the cleanup above performs.
  local seen
  local paintTree = NS.SkinPaintAceTree
  NS.SkinPaintAceTree = function(container)
    local n = paintTree(container)
    seen = ownerOf(container.children[1])
    return n
  end
  local ok, err = pcall(function()
    local row = profilesRow("obsidian")
    assertTrue(row ~= nil, "AceConfigDialog drew a row")
    assertEqual(seen, OWNER, "the drawn row is painted for this owner")
    assertEqual(ownerOf(row), nil, "and released stock")
    seen = "unset"
    profilesRow("ka0s")
    assertEqual(seen, OWNER, "Ka0s Default paints it as well")
  end)
  NS.SkinPaintAceTree = paintTree
  if not ok then error(err, 0) end
end)

-- ── the degraded seam ───────────────────────────────────────────────────────────────────────────

test("skin settings: degraded, PaintAce and PaintAceTree paint nothing and a release still runs", function()
  local dns, _, dm = dofile("tests/degraded_env.lua")()
  local ace = dm.__libs["AceGUI-3.0"]
  local w = ace:Create("SimpleGroup")
  assertEqual(dns.SkinPaintAce(w), false, "PaintAce is a no-op")
  assertEqual(dns.SkinPaintAceTree(w), 0, "PaintAceTree paints nothing")
  local ran
  dns.SkinOnRelease(w, function(released) ran = released end)
  ace:Release(w)
  assertTrue(ran == w, "the host's release work runs without the library")
end)
