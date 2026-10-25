-- tests/test_skinsetup.lua — the LibKa0s-Skin-1.0 seam (core/SkinSetup.lua, skinning-§3).
--
-- What this addon owes the skin engine, and nothing the library pins itself: the owner is
-- registered under the folder name with this addon's read and write seams; the two appearance keys
-- default to Ka0s Default and are schema rows on the Appearance tab; the tab sits after History and
-- before Keybindings; the profile's skin is applied right after AceDB exists and FIRST on every
-- profile event, whether or not the History window was ever built; and one pick, from this
-- addon's tab or from another addon's copy, is ONE effective SetChoice (one OnLooksChanged, at
-- most one reload request), however many store writes follow it.
--
-- After the panel suites, which leave the General page built and parked on its first tab; every
-- case here parks it there again and puts the skin back on Ka0s Default.

local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local P = dofile("tests/panel_support.lua")
local clickTab, homeTab, tabAt, STRIP, widgetsOfType = P.clickTab, P.homeTab, P.tabAt, P.STRIP,
  P.widgetsOfType

local Skin = mocks.LibStub("LibKa0s-Skin-1.0")
local OWNER = "LootHistory"

-- ONE listener of each kind for the whole file: the library keeps a listener for the session and
-- the same function twice is one entry, so each case resets the counters instead of registering.
local looks, reloads = 0, 0
NS.Skin.OnLooksChanged(function() looks = looks + 1 end)
Skin:OnReloadRequest(OWNER, function() reloads = reloads + 1 end)

local OptionsLib = mocks.LibStub("LibKa0s-Options-1.0")

-- Which settings pages were on screen before the first skin change (see reset, below). Taken at the
-- first reset rather than at file scope: the runner loads every suite file before it runs any, so
-- at file scope no page has been shown yet.
local WAS_SHOWN

--- Back on Ka0s Default, stored and applied, with the counters cleared.
---
--- AND THE LIBRARY'S DEFERRED RE-RENDER RUN. A skin change makes the Options instance re-render
--- its shown pages on the next frame (OptionsScroll.lua's one OnLooksChanged listener, through
--- C_Timer.After(0)); the client runs it a frame later, and the kit queues it on M.__timers. Left
--- queued it would run inside whichever later suite fires timers, re-rendering a page that suite
--- has already put away.
---
--- AND THE PAGES PUT BACK ON SCREEN. Away from Ka0s Default the library gives each settings page
--- an opaque backdrop texture (OptionsScroll.lua paintPage, `panel.__ka0sSkinBg`) and hides it on
--- the way back. The kit's CreateTexture answers the frame itself (tests/_kit/mock_base.lua), so in
--- this harness that texture IS the page and the way back hides the page with no OnHide, and the
--- next refresh drops it from the library's shown set. Dropping the alias and showing each page
--- that was on screen again, through its OnShow, restores what the client has: the page on screen
--- and in the shown set, its backdrop hidden.
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
  looks, reloads = 0, 0
end

--- Run `fn` with the skin reset before and after, whatever `fn` raised.
local function clean(fn)
  return function()
    reset()
    local ok, err = pcall(fn)
    reset()
    if not ok then error(err, 0) end
  end
end

-- ── the owner ────────────────────────────────────────────────────────────────────────────────

test("Skin seam: the owner is the folder name, and NS.Skin is its facade", function()
  -- red under: registering under the brand or a typo (the library keys every frame and every
  -- listener by owner), or publishing a facade of some other owner.
  assertTrue(Skin:IsOwner(OWNER), "core/SkinSetup.lua did not register the owner")
  assertTrue(rawequal(NS.Skin, Skin:For(OWNER)), "NS.Skin is not Skin:For(\"LootHistory\")")
  assertEqual(NS.Skin.owner, OWNER)
  assertEqual(Skin:OwnerLabel(OWNER), NS.BRAND, "the copy confirmation names the addon by its brand")
end)

test("Skin seam: the read answers Ka0s Default before the profile store exists", function()
  -- RegisterOwner calls `get` at FILE LOAD, before NS:InitDB; a getter that raised there would be a
  -- visible Lua error on every login.
  local db = NS.db
  NS.db = nil
  local ok, source, skin = pcall(NS.SkinChoice)
  NS.db = db
  assertTrue(ok, "NS.SkinChoice raised without a store: " .. tostring(source))
  assertEqual(source, "ka0s")
  assertEqual(skin, "ka0s")
end)

-- ── the keys and the rows ────────────────────────────────────────────────────────────────────

test("Skin seam: the appearance keys default to Ka0s Default, as two Appearance rows", function()
  -- red under: a default other than today's look, the keys moved out of `settings`, or a row that
  -- renders itself on top of the library's choice grids.
  local d = NS.defaults.profile.settings.appearance
  assertEqual(d.source, "ka0s")
  assertEqual(d.skin, "ka0s")
  for _, path in ipairs({ "settings.appearance.source", "settings.appearance.skin" }) do
    local row = NS.Schema:FindRow(path)
    assertTrue(row ~= nil, path .. " is not a schema row")
    assertEqual(row.page, "General", path .. ": page")
    assertEqual(row.group, "Appearance", path .. ": group")
    assertTrue(row.skipRender == true, path .. ": the tab draws it, so it must be skipRender")
  end
end)

test("Skin seam: the skin row's values are every registered skin, in the library's order", function()
  local values = NS.Schema:FindRow("settings.appearance.skin").values
  local skins = Skin:Skins()
  assertEqual(#values, #skins, "one value per registered skin")
  for i, def in ipairs(skins) do assertEqual(values[i].value, def.key, "value " .. i) end
  assertEqual(values[1].value, "ka0s", "Ka0s Default first")
end)

test("Skin seam: /lh set refuses a skin that is not registered and applies one that is", clean(function()
  -- The `values` check is the CLI parser's (LibKa0s-Slash-1.0), so this drives the verb, quietly.
  local cf = mocks.DEFAULT_CHAT_FRAME
  local add = cf.AddMessage
  cf.AddMessage = function() end
  local ok, err = pcall(function()
    NS.Slash:CliSet("settings.appearance.skin no-such-skin")
    assertEqual(NS.db.profile.settings.appearance.skin, "ka0s", "an unknown skin was stored")
    assertEqual(looks, 0, "a refused set repainted")
    NS.Slash:CliSet("settings.appearance.skin obsidian")
  end)
  cf.AddMessage = add
  if not ok then error(err, 0) end
  assertEqual(NS.db.profile.settings.appearance.skin, "obsidian", "a registered skin was refused")
  local _, applied = Skin:GetChoice(OWNER)
  assertEqual(applied, "obsidian", "a bare set must move the applied skin (the row's onChange)")
  assertEqual(looks, 1, "one set, one repaint")
end))

-- ── the tab ──────────────────────────────────────────────────────────────────────────────────

test("Skin seam: Appearance sits after History and before Keybindings", function()
  -- skinning-§3 and options-ui-§20: Keybindings stays last; eight tabs, the options-ui-§13 budget.
  assertEqual(#STRIP, 8, "eight tabs")
  assertEqual(tabAt("Appearance"), tabAt("History") + 1, "Appearance follows History")
  assertEqual(tabAt("Keybindings"), #STRIP, "Keybindings stays last")
  local ctx = NS.Panel.general
  clickTab(mocks.__subcategories["General"], ctx, tabAt("Appearance"))
  assertEqual(ctx.activeTab, "Appearance")
  homeTab(ctx)
end)

--- Open the Appearance tab and answer the radio choice whose label ends with `name`.
local function choiceNamed(name)
  local ctx = NS.Panel.general
  local created = clickTab(mocks.__subcategories["General"], ctx, tabAt("Appearance"))
  for _, w in ipairs(widgetsOfType(created, "CheckBox")) do
    local label = tostring(w.labelText or "")
    if label:sub(-#name) == name then return w, ctx end
  end
  return nil, ctx
end

test("Skin seam: one tab pick is one effective SetChoice, one repaint and no reload", clean(function()
  -- The tab calls SetChoice first, then the write seam, which writes both rows through
  -- NS.Schema:Set; each row's onChange applies only its own half and finds it applied already.
  -- red under: an onChange that re-applies the whole stored pair (two repaints, the first to a
  -- half-written skin), or a seam that writes the profile around NS.Schema:Set.
  local cb, ctx = choiceNamed("Obsidian")
  local ok, err = pcall(function()
    assertTrue(cb ~= nil, "the Appearance tab drew no Obsidian choice")
    cb:SetValue(true); cb:__fire("OnValueChanged", true)
    assertEqual(looks, 1, "one pick must repaint exactly once")
    assertEqual(reloads, 0, "a Ka0s-to-Ka0s pick asks for no reload")
    local source, skin = Skin:GetChoice(OWNER)
    assertEqual(source, "ka0s")
    assertEqual(skin, "obsidian", "the pick did not move the applied skin")
    assertEqual(NS.db.profile.settings.appearance.skin, "obsidian", "the pick did not reach the profile")
  end)
  homeTab(ctx)
  if not ok then error(err, 0) end
end))

test("Skin seam: another addon's copy to every Ka0s addon repaints LootHistory once", clean(function()
  -- The library's copy (OptionsAppearance.lua copyTo) calls SetChoice for the other owner, then
  -- WriteChoice, which reaches this addon's registered setter. Driven through a fake second owner.
  Skin:RegisterOwner("SkinProbeAddon", { label = "Skin Probe", get = function() return "ka0s", "ember" end,
    set = function() end })
  Skin:SetChoice("SkinProbeAddon", "ka0s", "ember")
  local source, skin = "ka0s", "ember"
  Skin:SetChoice(OWNER, source, skin)
  assertTrue(Skin:WriteChoice(OWNER, source, skin), "the copy's write did not reach this addon's setter")
  assertEqual(looks, 1, "a copy must repaint this addon exactly once")
  assertEqual(NS.db.profile.settings.appearance.skin, "ember", "the copy did not land in the profile")
  local _, applied = Skin:GetChoice(OWNER)
  assertEqual(applied, "ember")
end))

-- ── the profile events ───────────────────────────────────────────────────────────────────────

test("Skin seam: a profile switch applies the new profile's skin first, window built or not", clean(function()
  -- B:AdoptProfile returns early when the window was never built, so the skin must not ride it.
  -- The spy stands in for a window that does not exist and records what was applied by then.
  -- red under: applying the skin after (or inside) B:AdoptProfile, or not at all on a switch.
  local db, B = NS.db, NS.Browser
  local adopt, seen = B.AdoptProfile, nil
  B.AdoptProfile = function() seen = select(2, Skin:GetChoice(OWNER)) end
  local ok, err = pcall(function()
    db:SetProfile("SkinProbe")
    db.profile.settings.appearance.skin = "glass"
    db:SetProfile("Default")
    assertEqual(select(2, Skin:GetChoice(OWNER)), "ka0s", "back on Default, Default's skin")
    looks = 0
    db:SetProfile("SkinProbe")
    assertEqual(seen, "glass", "the skin was not applied before the window's adopt")
    assertEqual(select(2, Skin:GetChoice(OWNER)), "glass", "the switch did not move the applied skin")
    assertEqual(looks, 1, "one switch, one repaint")
  end)
  B.AdoptProfile = adopt
  if db:GetCurrentProfile() ~= "Default" then db:SetProfile("Default") end
  if db.DeleteProfile then pcall(db.DeleteProfile, db, "SkinProbe", true) end
  if not ok then error(err, 0) end
end))
