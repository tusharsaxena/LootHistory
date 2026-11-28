-- tests/test_panel_toasts.lua — the Toasts page (toast spec
-- docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md §9, §13.2): settings/SchemaToasts.lua's
-- per-feed rows and settings/PanelToasts.lua's banner, strip, filter, acts and Defaults. Runs after
-- tests/test_toast_blizz.lua with the addon brought up; every case puts back the settings it wrote,
-- the banner's pick and the tab.

local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local S = dofile("tests/panel_support.lua")
local AceGUI = S.AceGUI
local show, findByLabel, widgetsOfType = S.show, S.findByLabel, S.widgetsOfType

local C = NS.Constants
local TP = NS.ToastsPage
local ST = NS.SchemaToasts
local O = NS.Options

local function prefix(fid) return "settings.toasts.feeds." .. fid .. "." end
local function stored(fid) return NS.db.profile.settings.toasts.feeds[fid] end

local function panel() return mocks.__subcategories["Toasts"] end

--- The widgets the page builds from here on, in creation order, while `fn` runs.
local function built(fn)
  local before = #AceGUI.__created
  fn()
  local out = {}
  for i = before + 1, #AceGUI.__created do out[#out + 1] = AceGUI.__created[i] end
  return out
end

--- Show the page on `fid` and tab `tab`, run `fn(widgets)` with that render's widgets, then put the
--- pick and the tab back (main, General) and every feed's settings as they were.
local function onPage(fid, tab, fn)
  local feeds = NS.db.profile.settings.toasts.feeds
  local saved, savedAlerts = {}, NS.db.profile.settings.toasts.hideAlerts
  for _, f in ipairs(C.TOAST_FEEDS) do saved[f] = NS.Util.DeepCopy(feeds[f]) end
  show(panel())
  local ctx = TP.ctx
  local widgets = built(function()
    ctx.activeTab = tab or "General"
    TP.Select(fid or "main")
  end)
  local ok, err = pcall(fn, widgets, ctx)
  for f, v in pairs(saved) do feeds[f] = v end
  NS.db.profile.settings.toasts.hideAlerts = savedAlerts
  NS.ToastModel.Rebuild()
  ctx.activeTab = "General"
  TP.Select("main")
  NS.Toasts:RefreshConfig()
  NS.GainFeed:Recompute()
  -- Off screen again, as a player leaves it: a page left shown keeps the library watching combat,
  -- and a later suite's bare PLAYER_REGEN_DISABLED would lock every settings page.
  panel():Hide()
  if not ok then error(err, 0) end
end

local function feedRows(fid)
  local out = {}
  for _, row in ipairs(NS.Schema.Schema) do
    if row.page == "Toasts" and row.feed == fid then out[#out + 1] = row end
  end
  return out
end

-- ── registration and chrome ──────────────────────────────────────────────────────────────────

test("Toasts page: registered as its own settings page, between General and Profiles", function()
  assertTrue(panel() ~= nil, "a Toasts subcategory")
  assertEqual(panel().name, "Toasts")
  local keys = {}
  for _, page in ipairs(O.__pages()) do keys[#keys + 1] = page.key end
  local at = {}
  for i, k in ipairs(keys) do at[k] = i end
  assertTrue(at.General ~= nil and at.Toasts ~= nil and at.Toasts > at.General, "Toasts after General")
  if at.Profiles then assertTrue(at.Toasts < at.Profiles, "and before Profiles") end
end)

test("Toasts page: the banner lists the three feeds, in order, and picks Main first", function()
  onPage("main", "General", function(_, ctx)
    local dd = ctx.__bannerDropdown
    assertTrue(dd ~= nil, "the banner draws its picker")
    assertEqual(dd.labelText, "Feed")
    assertEqual(table.concat(dd.order, ","), "main,progress,extra")
    assertEqual(dd.list.main, "Main feed"); assertEqual(dd.list.progress, "Progress feed")
    assertEqual(dd.list.extra, "Third feed")
    assertEqual(dd.value, "main")
  end)
end)

test("Toasts page: the strip is General, Content, Style, Motion, Behavior", function()
  onPage("main", "General", function(_, ctx)
    assertEqual(#ctx.__tabLayout.buttons, 5, "five tabs")
    assertEqual(table.concat(ST.TABS, ","), "General,Content,Style,Motion,Behavior")
    local groups, seen = {}, {}
    for _, row in ipairs(feedRows("main")) do
      if not seen[row.group] then seen[row.group] = true; groups[#groups + 1] = row.group end
    end
    assertEqual(table.concat(groups, ","), table.concat(ST.TABS, ","), "the rows' groups are the strip")
  end)
end)

test("Toasts page: picking a feed keeps the tab and filters the rows to that feed", function()
  local seen
  local saved = O.RenderRows
  O.RenderRows = function(ctx, rows, ...) seen = rows; return saved(ctx, rows, ...) end
  local ok, err = pcall(onPage, "main", "Style", function(_, ctx)
    TP.Select("progress")
    assertEqual(ctx.activeTab, "Style", "a feed pick keeps the tab (options-ui-§14)")
    assertEqual(ctx.unit, "progress")
    assertTrue(seen ~= nil and #seen > 0, "the Style tab drew rows")
    for _, row in ipairs(seen) do
      assertEqual(row.feed, "progress", row.path .. " is another feed's")
      assertEqual(row.group, "Style")
    end
    ctx.activeTab = "Behavior"
    TP.Select("extra")
    local page = 0
    for _, row in ipairs(seen) do
      if row.feed == nil then page = page + 1; assertEqual(row.path, "settings.toasts.hideAlerts") end
      if row.feed then assertEqual(row.feed, "extra") end
    end
    assertEqual(page, 1, "the page-wide alert row is drawn under every feed's Behavior tab")
    assertFalse(TP.Select("nosuch"), "an unknown feed is refused")
    assertEqual(TP.Selected(), "extra")
  end)
  O.RenderRows = saved
  if not ok then error(err, 0) end
end)

-- ── the rows (§9.2, §9.3) ────────────────────────────────────────────────────────────────────

test("Toasts rows: every feed emits the same leaves in the same order, stamped with its feed", function()
  local function leaves(fid)
    local out = {}
    for i, row in ipairs(feedRows(fid)) do
      assertEqual(row.page, "Toasts"); assertEqual(type(row.onChange), "function", row.path)
      out[i] = row.path:sub(#prefix(fid) + 1)
    end
    return table.concat(out, ",")
  end
  local main = leaves("main")
  assertTrue(#feedRows("main") >= 70, "the per-feed set is the whole page (" .. #feedRows("main") .. ")")
  assertEqual(leaves("progress"), main)
  assertEqual(leaves("extra"), main)
end)

test("Toasts rows: every path has a shipped default equal to the row's, and every FromSkin defaults true", function()
  for _, row in ipairs(NS.Schema.Schema) do
    if row.page == "Toasts" then
      local shipped = NS.SchemaLib.Read(NS.defaults.profile, row.path)
      assertTrue(shipped ~= nil, row.path .. " has no default in defaults/Profile.lua")
      if type(shipped) == "table" then
        for k, v in pairs(shipped) do assertEqual(row.default[k], v, row.path .. "." .. tostring(k)) end
      else
        assertEqual(row.default, shipped, row.path)
      end
      if row.path:sub(-8) == "FromSkin" then assertEqual(row.default, true, row.path .. " starts on the skin") end
    end
  end
end)

test("Toasts rows: the nudge sliders span the Feed's clamp, and the enter values are the Feed's words", function()
  for _, leaf in ipairs({ "x", "y" }) do
    local row = NS.Schema:FindRow(prefix("main") .. leaf)
    assertEqual(row.min, -C.TOAST_NUDGE_MAX); assertEqual(row.max, C.TOAST_NUDGE_MAX)
  end
  if NS.FeedLib then assertEqual(C.TOAST_NUDGE_MAX, NS.FeedLib.NUDGE_MAX) end
  local words = {}
  for i, o in ipairs(NS.Schema:FindRow(prefix("main") .. "enter").values) do words[i] = o.value end
  assertEqual(table.concat(words, ","), "none,fade,right,left,up,down")
  local slots = {}
  for i, o in ipairs(NS.Schema:FindRow(prefix("main") .. "slot").values) do slots[i] = o.value end
  assertEqual(table.concat(slots, ","), table.concat(C.TOAST_SLOTS, ","))
  assertEqual(NS.Schema:FindRow(prefix("main") .. "shown").max, C.TOAST_SHOWN_MAX)
end)

test("Toasts rows: every color has its class companion beside it, but the kind palette, and none is disabled", function()
  local rows = feedRows("main")
  for i, row in ipairs(rows) do
    if row.type == "color" then
      assertEqual(row.disabledIf, nil, row.path .. ": a swatch is never disabled (anti-pattern #74)")
      if not row.path:find("%.colors%.") then
        local nxt = rows[i + 1]
        assertTrue(nxt and nxt.label == "Use class color", row.path .. " has its class companion beside it")
      end
    end
  end
  assertTrue(NS.Schema:FindRow(prefix("main") .. "useClassColorBgColor") ~= nil, "the background's class color")
end)

test("Toasts rows: the appearance rows are Retail's", function()
  for _, leaf in ipairs({ "kinds.appearance", "hl.appearance", "hl.appearanceSound" }) do
    local row = NS.Schema:FindRow(prefix("main") .. leaf)
    assertTrue(row.clients == C.FEATURE_CLIENTS.appearances, leaf .. " is gated by the feature")
  end
  local seen
  local saved = O.RenderRows
  O.RenderRows = function(ctx, rows, ...) seen = rows; return saved(ctx, rows, ...) end
  local ok, err = pcall(onPage, "main", "Content", function()
    local found = false
    for _, row in ipairs(seen or {}) do
      if row.path == prefix("main") .. "kinds.appearance" then found = true end
    end
    assertEqual(found, not T.forever, "drawn on Retail only")
  end)
  O.RenderRows = saved
  if not ok then error(err, 0) end
end)

test("Toasts rows: a slot pick sets its growth and clears the nudge", function()
  onPage("main", "General", function()
    assertTrue(NS.Schema:Set(prefix("main") .. "slot", "TOPLEFT"))
    local f = stored("main")
    assertEqual(f.slot, "TOPLEFT"); assertEqual(f.grow, "down"); assertEqual(f.x, 0); assertEqual(f.y, 0)
    assertTrue(NS.Schema:Set(prefix("main") .. "slot", "BOTTOM"))
    assertEqual(stored("main").grow, "up")
  end)
end)

test("Toasts rows: a drag's nudge now lands through the Schema seam", function()
  onPage("main", "General", function()
    assertTrue(NS.Toasts:_Moved("progress", 40, -120))
    assertEqual(stored("progress").x, 40); assertEqual(stored("progress").y, -120)
  end)
end)

-- ── the acts (§9.1) ──────────────────────────────────────────────────────────────────────────

test("Toasts page: the General tab carries Test, Unlock and Reset feed; Style carries Reset style to skin", function()
  onPage("main", "General", function(widgets)
    assertTrue(findByLabel(widgets, "Test") ~= nil, "Test")
    assertTrue(findByLabel(widgets, "Unlock") ~= nil, "Unlock (the feed is locked)")
    assertTrue(findByLabel(widgets, "Reset feed\226\128\166") ~= nil, "Reset feed...")
    assertTrue(findByLabel(widgets, "Reset style to skin") == nil, "not on General")
  end)
  onPage("main", "Style", function(widgets)
    assertTrue(findByLabel(widgets, "Reset style to skin") ~= nil)
  end)
end)

test("Toasts page: the Content tab draws Hide sources with the set picker", function()
  onPage("progress", "Content", function(widgets)
    local group
    for _, w in ipairs(widgets) do if w.type == "InlineGroup" and w.titleText == "Hide sources" then group = w end end
    if not group then
      for _, w in ipairs(widgetsOfType(widgets, "InlineGroup")) do group = group or w end
    end
    assertTrue(group ~= nil, "the picker is drawn")
    assertEqual(#group.children, #C.SOURCE_OPTIONS, "one box per source")
    group.children[1].callbacks.OnValueChanged(nil, nil, true)
    assertTrue(stored("progress").hideSources[C.SOURCE_OPTIONS[1].value], "a ticked box hides that source")
    assertEqual(next(stored("main").hideSources), nil, "on the picked feed only")
  end)
end)

test("Toasts page: Add feed turns on the next feed that is off and picks it; none left says so", function()
  onPage("main", "General", function()
    assertTrue(TP.AddFeed())
    assertTrue(stored("progress").enabled, "Progress was the first off")
    assertEqual(TP.Selected(), "progress")
    assertTrue(TP.AddFeed())
    assertEqual(TP.Selected(), "extra")
    local lines = {}
    local savedPrint = NS.Print
    NS.Print = function(line) lines[#lines + 1] = line end
    local res = TP.AddFeed()
    NS.Print = savedPrint
    assertFalse(res)
    assertEqual(lines[1], "All three feeds are on.")
    assertEqual(TP.Selected(), "extra", "nothing changed")
  end)
end)

test("Toasts page: Reset style to skin turns on exactly the feed's Style companions", function()
  onPage("extra", "Style", function()
    local companions = ST.StyleCompanions("extra")
    assertTrue(#companions >= 8, "the background, border, text and kind companions")
    for _, path in ipairs(companions) do
      assertTrue(path:find(prefix("extra"), 1, true) == 1, path)
      NS.Schema:Set(path, false)
    end
    NS.Schema:Set(prefix("extra") .. "width", 400)
    NS.Schema:Set(prefix("main") .. "fontFromSkin", false)
    assertTrue(TP.ResetStyle("extra"))
    for _, path in ipairs(companions) do assertEqual(NS.Schema:Get(path), true, path) end
    assertEqual(stored("extra").width, 400, "a stored pick is left alone")
    assertEqual(stored("main").fontFromSkin, false, "another feed is left alone")
  end)
end)

test("Toasts page: Reset feed resets only that feed", function()
  onPage("progress", "General", function()
    NS.Schema:Set(prefix("progress") .. "width", 444)
    NS.Schema:Set(prefix("progress") .. "kinds.item", true)
    NS.Schema:Set(prefix("main") .. "width", 333)
    assertTrue(TP.ResetFeed("progress"))
    assertEqual(stored("progress").width, NS.defaults.profile.settings.toasts.feeds.progress.width)
    assertEqual(stored("progress").kinds.item, false, "back to the Progress feed's own default")
    assertEqual(stored("main").width, 333, "another feed is untouched")
  end)
end)

test("Toasts page: the Defaults restore all three feeds and the alert row", function()
  onPage("main", "General", function(_, ctx)
    NS.Schema:Set(prefix("main") .. "width", 301)
    NS.Schema:Set(prefix("extra") .. "hold", 9)
    NS.Schema:Set("settings.toasts.hideAlerts", true)
    ctx.panel.defaultsOnClick()
    assertEqual(stored("main").width, 320)
    assertEqual(stored("extra").hold, 5)
    assertEqual(NS.db.profile.settings.toasts.hideAlerts, false)
    assertEqual(TP.DEFAULTS_TOOLTIP, "Restore every setting of all three toast feeds, and the Blizzard alert "
      .. "option, to their defaults. Other pages are not changed.")
  end)
end)

test("Toasts page: the Unlock act unlocks the feed, and a refused unlock says so", function()
  onPage("main", "General", function()
    local lines = {}
    local savedPrint = NS.Print
    NS.Print = function(line) lines[#lines + 1] = line end
    mocks.InCombatLockdown = function() return true end
    local ok, err = pcall(function()
      assertFalse(TP.ToggleUnlock("main"), "refused in combat")
      assertEqual(lines[1], "The feed cannot be unlocked now.")
    end)
    mocks.InCombatLockdown = function() return false end
    NS.Print = savedPrint
    if not ok then error(err, 0) end
    local unlocked = TP.ToggleUnlock("main")
    if unlocked then
      assertTrue(NS.State.toastUnlocked.main)
      assertFalse(TP.ToggleUnlock("main"), "the second press locks it again")
    end
    assertEqual(NS.State.toastUnlocked.main, nil)
  end)
end)

test("Toasts page: drawn under the disabled notice while the addon is off", function()
  local O2 = NS.Options
  local seenOpts
  local saved = O2.RenderTabbedSchema
  O2.RenderTabbedSchema = function(ctx, key, ag, pw, opts) seenOpts = opts; return saved(ctx, key, ag, pw, opts) end
  local ok, err = pcall(onPage, "main", "General", function()
    assertTrue(type(seenOpts.disabledFor) == "function")
    assertFalse(seenOpts.disabledFor(), "enabled: drawn live")
    local savedOff = NS.AddonIsOff
    NS.AddonIsOff = function() return true end
    local off = seenOpts.disabledFor()
    NS.AddonIsOff = savedOff
    assertTrue(off, "disabled: the page renders under the notice")
    assertTrue(type(seenOpts.disabledNotice) == "string" and seenOpts.disabledNotice ~= "")
  end)
  O2.RenderTabbedSchema = saved
  if not ok then error(err, 0) end
end)
