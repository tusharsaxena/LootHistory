-- tests/test_skin_overrides.lua — the Skin tab's font and texture overrides on this addon's seam
-- (core/SkinSetup.lua; LibKa0s-Skin-1.0 minor 6, LibKa0s#63).
--
-- What this addon owes the overrides, and nothing the library pins itself: two profile keys, ""
-- for the skin's own, as skip-render rows on the Skin tab; the write seam takes the tab's and the
-- copy's fourth argument; one pick is ONE effective SetOverride (one OnLooksChanged) however many
-- store writes follow it; `/lh set` moves only its own half; and the stored pair is applied with
-- the skin, at login and on every profile event.
--
-- After test_skinsetup, which leaves the General page built and parked on its first tab; every
-- case here parks it there again and puts the overrides and the skin back on Ka0s Default.

local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local P = dofile("tests/panel_support.lua")
local clickTab, homeTab, tabAt, findByLabel = P.clickTab, P.homeTab, P.tabAt, P.findByLabel

local Skin = mocks.LibStub("LibKa0s-Skin-1.0")
local OWNER = "LootHistory"
local FROM_SKIN = "@skin"

local looks = 0
NS.Skin.OnLooksChanged(function() looks = looks + 1 end)

--- Back on Ka0s Default with no overrides, stored and applied, the counter cleared.
local function reset()
  NS.WriteSkinChoice("ka0s", "ka0s", { panel = true, fonts = false }, { font = false, texture = false })
  Skin:SetChoice(OWNER, "ka0s", "ka0s")
  Skin:SetIgnore(OWNER, true, false)
  Skin:SetOverride(OWNER, false, false)
  mocks.__fireTimers()
  looks = 0
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

--- Run `fn` with a LibSharedMedia stand-in that lists one face and one status bar: this harness
--- loads no LibSharedMedia, so the tab's lists would hold only the skin's own entry. List only,
--- no Fetch, so no override resolves to a path and the paint stays the skin's.
local function withMedia(fn)
  local libs = mocks.__libs
  local saved = libs["LibSharedMedia-3.0"]
  libs["LibSharedMedia-3.0"] = {
    List = function(_, kind) return kind == "font" and { "Probe Face" } or { "Probe Bar" } end,
  }
  local ok, err = pcall(fn)
  libs["LibSharedMedia-3.0"] = saved
  if not ok then error(err, 0) end
end

--- The first key a media dropdown offers past "the skin's own".
local function firstKey(dd)
  local keys = {}
  for key in pairs(dd.list or {}) do
    if key ~= FROM_SKIN then keys[#keys + 1] = key end
  end
  table.sort(keys)
  return keys[1]
end

-- ── the descriptor's media seam (options-ui-§23) ─────────────────────────

test("Skin overrides: the descriptor hands the library LibSharedMedia, for O.LSMValues and the preload", function()
  -- red under: a descriptor with no getLSM, whose LSMValues answers the one "no media" row and whose
  -- panel show never preloads the faces a picker's rows draw in.
  local libs = mocks.__libs
  local saved = libs["LibSharedMedia-3.0"]
  libs["LibSharedMedia-3.0"] = {
    HashTable = function(_, kind) return { [kind .. " probe"] = "path" } end,
  }
  local ok, err = pcall(function()
    local list = NS.Options.LSMValues("font")()
    assertEqual(list["font probe"], "font probe", "the library saw no LibSharedMedia")
  end)
  libs["LibSharedMedia-3.0"] = saved
  if not ok then error(err, 0) end
end)

-- ── the keys and the rows ────────────────────────────────────────────────────────────────────

test("Skin overrides: the font and texture keys default to the skin's own, as two Skin tab rows", function()
  -- red under: a default other than "" (the skin's own), the keys moved out of
  -- settings.appearance, or a row that renders itself on top of the library's dropdowns.
  local d = NS.defaults.profile.settings.appearance
  assertEqual(d.font, "")
  assertEqual(d.texture, "")
  for _, path in ipairs({ "settings.appearance.font", "settings.appearance.texture" }) do
    local row = NS.Schema:FindRow(path)
    assertTrue(row ~= nil, path .. " is not a schema row")
    assertEqual(row.type, "string", path .. ": type")
    assertEqual(row.page, "General", path .. ": page")
    assertEqual(row.group, "Appearance", path .. ": group (the Skin tab's key)")
    assertTrue(row.skipRender == true, path .. ": the tab draws it, so it must be skipRender")
  end
end)

test("Skin overrides: the stored pair reads false, false before the profile store exists", function()
  local db = NS.db
  NS.db = nil
  local ok, font, texture = pcall(NS.SkinOverride)
  NS.db = db
  assertTrue(ok, "NS.SkinOverride raised without a store: " .. tostring(font))
  assertEqual(font, false)
  assertEqual(texture, false)
end)

-- ── the write seam ───────────────────────────────────────────────────────────────────────────

test("Skin overrides: the write seam stores media's halves, \"\" for the skin's own", clean(function()
  -- The copy to every Ka0s addon reaches this addon only through Skin:WriteChoice, whose fourth
  -- argument is `{ font = key|false, texture = key|false }`. red under: NS.WriteSkinChoice dropping
  -- its fourth argument, or storing false where the row's type is a string.
  assertTrue(Skin:WriteChoice(OWNER, "ka0s", "ka0s", nil, { font = "Probe Face", texture = false }),
    "the copy's write did not reach this addon's setter")
  local a = NS.db.profile.settings.appearance
  assertEqual(a.font, "Probe Face")
  assertEqual(a.texture, "")
  local font, texture = NS.SkinOverride()
  assertEqual(font, "Probe Face")
  assertEqual(texture, false, "\"\" reads back as false, the skin's own")
end))

test("Skin overrides: a write with no media leaves both stored halves alone", clean(function()
  NS.WriteSkinChoice(nil, nil, nil, { font = "Probe Face", texture = "Probe Bar" })
  NS.WriteSkinChoice("ka0s", "obsidian")
  NS.WriteSkinChoice(nil, nil, { panel = true, fonts = true })
  local a = NS.db.profile.settings.appearance
  assertEqual(a.font, "Probe Face")
  assertEqual(a.texture, "Probe Bar")
end))

-- ── the tab ──────────────────────────────────────────────────────────────────────────────────

test("Skin overrides: one Font pick on the tab is one SetOverride, one repaint, in the profile", clean(function() withMedia(function()
  -- The tab calls Skin:SetOverride first, then the write seam with both halves; each row's
  -- onChange applies only its own half and finds it applied already. red under: an onChange that
  -- re-applies something else (a second repaint), or the write seam ignoring media.
  local ctx = NS.Panel.general
  local created = clickTab(mocks.__subcategories["General"], ctx, tabAt("Appearance"))
  local ok, err = pcall(function()
    local dd = findByLabel(created, "Font")
    assertTrue(dd ~= nil and dd.type == "Dropdown", "the Skin tab drew no Font dropdown")
    assertTrue(dd.list[FROM_SKIN] ~= nil, "the list starts with the skin's own")
    local key = firstKey(dd)
    assertTrue(key ~= nil, "the Font list offers no LibSharedMedia face")
    dd:__fire("OnValueChanged", key)
    local font, texture = Skin:GetOverride(OWNER)
    assertEqual(font, key, "the pick did not move the applied font")
    assertEqual(texture, nil, "and the texture stays the skin's own")
    assertEqual(NS.db.profile.settings.appearance.font, key, "the pick did not reach the profile")
    assertEqual(NS.db.profile.settings.appearance.texture, "")
    assertEqual(looks, 1, "one pick must repaint exactly once")
    dd:__fire("OnValueChanged", FROM_SKIN)
    assertEqual((Skin:GetOverride(OWNER)), nil, "the skin's own clears the override")
    assertEqual(NS.db.profile.settings.appearance.font, "", "and stores \"\"")
  end)
  homeTab(ctx)
  if not ok then error(err, 0) end
end) end))

test("Skin overrides: the Texture dropdown sits beside Font and writes its own half", clean(function() withMedia(function()
  local ctx = NS.Panel.general
  local created = clickTab(mocks.__subcategories["General"], ctx, tabAt("Appearance"))
  local ok, err = pcall(function()
    local dd = findByLabel(created, "Texture")
    assertTrue(dd ~= nil and dd.type == "Dropdown", "the Skin tab drew no Texture dropdown")
    local key = firstKey(dd)
    assertTrue(key ~= nil, "the Texture list offers no LibSharedMedia status bar")
    dd:__fire("OnValueChanged", key)
    local font, texture = Skin:GetOverride(OWNER)
    assertEqual(texture, key)
    assertEqual(font, nil)
    assertEqual(NS.db.profile.settings.appearance.texture, key)
    assertEqual(looks, 1, "one pick must repaint exactly once")
  end)
  homeTab(ctx)
  if not ok then error(err, 0) end
end) end))

-- ── the CLI and the profile ──────────────────────────────────────────────────────────────────

test("Skin overrides: /lh set reaches an override, and only its own half", clean(function()
  -- red under: a row with no onChange (the store moves, the screen does not), or one that applies
  -- both halves.
  Skin:SetOverride(OWNER, "Probe Face", nil)
  NS.WriteSkinChoice(nil, nil, nil, { font = "Probe Face", texture = false })
  looks = 0
  quietly(function() NS.Slash:CliSet("settings.appearance.texture Probe Bar") end)
  local font, texture = Skin:GetOverride(OWNER)
  assertEqual(texture, "Probe Bar", "the set applied")
  assertEqual(font, "Probe Face", "the other half untouched")
  assertEqual(looks, 1, "one set, one repaint")
end))

test("Skin overrides: a profile's stored pair is applied with its skin, \"\" clearing", clean(function()
  -- addon:OnInitialize and the profile events call NS.ApplySkinChoice() with no argument.
  -- red under: applying the skin and the exceptions but not the overrides.
  local a = NS.db.profile.settings.appearance
  a.font, a.texture = "Probe Face", "Probe Bar"
  NS.ApplySkinChoice()
  local font, texture = Skin:GetOverride(OWNER)
  assertEqual(font, "Probe Face")
  assertEqual(texture, "Probe Bar")
  a.font, a.texture = "", ""
  NS.ApplySkinChoice()
  font, texture = Skin:GetOverride(OWNER)
  assertEqual(font, nil, "a stored \"\" clears the applied font")
  assertEqual(texture, nil, "and the applied texture")
end))

test("Skin overrides: a profile switch applies the new profile's overrides", clean(function()
  local db = NS.db
  local ok, err = pcall(function()
    db:SetProfile("OverrideProbe")
    db.profile.settings.appearance.texture = "Probe Bar"
    db:SetProfile("Default")
    assertEqual(select(2, Skin:GetOverride(OWNER)), nil, "back on Default, Default's own texture")
    db:SetProfile("OverrideProbe")
    assertEqual(select(2, Skin:GetOverride(OWNER)), "Probe Bar", "the switch did not apply the override")
  end)
  if db:GetCurrentProfile() ~= "Default" then db:SetProfile("Default") end
  if db.DeleteProfile then pcall(db.DeleteProfile, db, "OverrideProbe", true) end
  if not ok then error(err, 0) end
end))
