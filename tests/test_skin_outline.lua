-- tests/test_skin_outline.lua — the Skin tab's Font outline on this addon's seam (core/SkinSetup.lua;
-- LibKa0s v1.82.0, Skin minor 9; LH-01 of Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK,
-- ruling D-06).
--
-- What this addon owes the outline, and nothing the library pins itself: one profile key,
-- settings.appearance.outline ("all", the default, "hud", "off"), a skip-render row on the Skin tab
-- whose values are the library's three modes in its order; the write seam storing media.outline
-- (the tab's Font outline and another addon's copy) and leaving it alone when it is nil; `/lh set`
-- moving it live and refusing a mode the library does not know; and the stored mode applied with
-- the skin, at login and on every profile event.
--
-- After test_skin_overrides; every case puts the outline back on "all", stored and applied.

local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local Skin = mocks.LibStub("LibKa0s-Skin-1.0")
local OWNER = "LootHistory"
local PATH = "settings.appearance.outline"

local function stored() return NS.db.profile.settings.appearance.outline end

local function reset()
  NS.db.profile.settings.appearance.outline = "all"
  Skin:SetOutline(OWNER, "all")
  mocks.__fireTimers()
end

local function clean(fn)
  return function()
    reset()
    local ok, err = pcall(fn)
    reset()
    if not ok then error(err, 0) end
  end
end

--- Run `fn` with the chat frame silenced (the CLI's [Set] and confirmation lines).
local function quietly(fn)
  local cf = mocks.DEFAULT_CHAT_FRAME
  local add = cf.AddMessage
  cf.AddMessage = function() end
  local ok, err = pcall(fn)
  cf.AddMessage = add
  if not ok then error(err, 0) end
end

-- ── the key and the row ──────────────────────────────────────────────────────────────────────

test("Skin outline: a fresh profile stores All text, the library's default", function()
  -- red under: a default other than the library's (every addon's text would start unoutlined).
  assertEqual(NS.defaults.profile.settings.appearance.outline, "all")
  assertEqual(NS.defaults.profile.settings.appearance.outline, Skin.OUTLINE_DEFAULT)
  assertEqual(Skin:GetOutline(OWNER), "all")
end)

test("Skin outline: the row is a skip-render Skin tab row offering the library's three modes", function()
  local row = NS.Schema:FindRow(PATH)
  assertTrue(row ~= nil, PATH .. " is not a schema row")
  assertEqual(row.type, "string")
  assertEqual(row.page, "General")
  assertEqual(row.group, "Appearance", "the Skin tab's key")
  assertTrue(row.skipRender == true, "the library's tab draws it")
  local got = {}
  for _, opt in ipairs(row.values) do got[#got + 1] = opt.value end
  assertEqual(table.concat(got, ","), table.concat(Skin.OUTLINE_MODES, ","))
end)

test("Skin outline: the stored mode reads \"all\" before the profile store exists", function()
  local db = NS.db
  NS.db = nil
  local ok, mode = pcall(NS.SkinOutline)
  NS.db = db
  assertTrue(ok, "NS.SkinOutline raised without a store: " .. tostring(mode))
  assertEqual(mode, "all")
end)

-- ── the write seam ───────────────────────────────────────────────────────────────────────────

test("Skin outline: the write seam stores media.outline, and leaves it alone when it is nil", clean(function()
  -- red under: NS.WriteSkinChoice dropping media.outline (the tab's Font outline and the copy
  -- would move the look and never store it).
  NS.WriteSkinChoice(nil, nil, nil, { font = false, texture = false, outline = "hud" })
  assertEqual(stored(), "hud")
  NS.WriteSkinChoice(nil, nil, nil, { font = false, texture = false })
  assertEqual(stored(), "hud", "a media table without outline leaves it")
  NS.WriteSkinChoice("ka0s", "ka0s")
  assertEqual(stored(), "hud", "a write with no media leaves it")
  NS.WriteSkinChoice(nil, nil, nil, { font = false, texture = false, outline = "off" })
  assertEqual(stored(), "off")
end))

test("Skin outline: another addon's copy reaches the store through WriteChoice", clean(function()
  assertTrue(Skin:WriteChoice(OWNER, "ka0s", "ka0s", nil, { font = false, texture = false, outline = "off" }),
    "the copy's write did not reach this addon's setter")
  assertEqual(stored(), "off")
end))

-- ── the CLI and the profile ──────────────────────────────────────────────────────────────────

test("Skin outline: /lh set moves the applied mode live", clean(function()
  -- red under: a row with no onChange (the store moves, the text does not).
  quietly(function() NS.Slash:CliSet(PATH .. " hud") end)
  assertEqual(stored(), "hud")
  assertEqual(Skin:GetOutline(OWNER), "hud")
  assertEqual(NS.Skin.Token("font.outline"), "", "window text loses its outline")
  assertEqual(NS.Skin.Token("hud.outline"), "OUTLINE", "the HUD keeps it")
  quietly(function() NS.Slash:CliSet(PATH .. " off") end)
  assertEqual(NS.Skin.Token("hud.outline"), "", "Off takes both")
  quietly(function() NS.Slash:CliSet(PATH .. " all") end)
  assertEqual(NS.Skin.Token("font.outline"), "OUTLINE", "All text outlines window text")
end))

test("Skin outline: /lh set refuses a mode the library does not know", clean(function()
  quietly(function() NS.Slash:CliSet(PATH .. " thick") end)
  assertEqual(stored(), "all")
  assertEqual(Skin:GetOutline(OWNER), "all")
end))

test("Skin outline: the stored mode is applied with the skin", clean(function()
  -- addon:OnInitialize and the profile events call NS.ApplySkinChoice() with no argument.
  -- red under: the whole-pair path applying the skin, the Scope and the overrides but not this.
  NS.db.profile.settings.appearance.outline = "off"
  NS.ApplySkinChoice()
  assertEqual(Skin:GetOutline(OWNER), "off")
end))

test("Skin outline: a profile switch applies the incoming profile's mode, and back", clean(function()
  local db = NS.db
  local ok, err = pcall(function()
    quietly(function() NS.Slash:CliSet(PATH .. " hud") end)
    db:SetProfile("OutlineProbe")
    assertEqual(Skin:GetOutline(OWNER), "all", "a new profile keeps the default")
    db:SetProfile("Default")
    assertEqual(Skin:GetOutline(OWNER), "hud", "Default's own is back")
  end)
  if db:GetCurrentProfile() ~= "Default" then db:SetProfile("Default") end
  if db.DeleteProfile then pcall(db.DeleteProfile, db, "OutlineProbe", true) end
  if not ok then error(err, 0) end
end))
