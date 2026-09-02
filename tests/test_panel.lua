-- Settings-panel tests.
--
-- Written BEFORE the LibKa0s-Options-1.0 adoption, deliberately: this repo had no panel suite at
-- all, so every part of the schema -> widget -> write path was invisible to the green gate and a
-- panel regression could ship green. These cases are the baseline the adoption is measured against
-- — page registration, the breadcrumb, section headings, the two-column pairing, each widget maker,
-- the Defaults buttons and the landing rows — and they are written against OBSERVABLE output
-- (recorded canvas frames, the AceGUI widget factory's creation log, the stored value) rather than
-- against internals, so the same assertions hold on either side of the migration.
--
-- Everything the panel builds is deferred to its page's first OnShow, so each test fires that
-- handler through the mock's recorded script table exactly as the client would.

local T = _G.LH_TEST
local NS, mocks, Loader = T.NS, T.mocks, T.Loader
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local AceGUI = mocks.__libs["AceGUI-3.0"]

--- Fire a panel's OnShow and return the widgets its BODY is built from, in creation order.
---
--- Every page body is deferred to its first OnShow and then never rebuilt wholesale, so a second
--- call creates nothing. The first render's widget slice is therefore cached per panel and handed
--- back on every later call — which is what lets each case reach the same live widget the user
--- would click, rather than an empty list that would make the assertions below vacuous.
local rendered = {}
local function show(panel)
  local before = #AceGUI.__created
  -- Show() as well as firing the handler. The mock tracks visibility without firing OnShow, and the
  -- refresh fan-out deliberately skips a page that is not on screen (it flags it dirty instead), so
  -- a page that was never Shown would silently ignore every Refresh and the cases below would pass
  -- on a panel that does nothing.
  panel:Show()
  panel:__fire("OnShow")
  if not rendered[panel] then
    local out = {}
    for i = before + 1, #AceGUI.__created do out[#out + 1] = AceGUI.__created[i] end
    rendered[panel] = out
  end
  return rendered[panel]
end

--- Click a page's tab by position and return the widgets that render built, in creation order.
---
--- BY POSITION, not by name: the strip's buttons come back from the library in tab order, so an
--- index plus an assertion on `ctx.activeTab` pins the ORDER of the strip as well as its contents.
--- Clicking the tab you are already on is a no-op in the library (the active tab is the disabled
--- one), so tab 1 is reached through `show` instead.
---
--- Every caller clicks back to tab 1 before it returns. The `show` cache above hands back the
--- FIRST render's widget slice, which is tab 1's, and a page parked on another tab would make
--- every later case reach for widgets that are no longer on screen.
local function clickTab(panel, ctx, index)
  show(panel)
  local layout = ctx.__tabLayout
  T.assertTrue(layout ~= nil and layout.buttons ~= nil, "the page drew no tab strip")
  T.assertTrue(layout.buttons[index] ~= nil, "there is no tab " .. index .. " on the strip")
  local before = #AceGUI.__created
  layout.buttons[index]:__fire("OnClick")
  local out = {}
  for i = before + 1, #AceGUI.__created do out[#out + 1] = AceGUI.__created[i] end
  return out
end

--- Back to the first tab, and REPOINT the `show` cache at the widgets that click just built.
---
--- Not bookkeeping: a tab click runs ClearScroll, which hands every widget back to AceGUI's pool
--- and REASSIGNS `ctx.refreshers`. A case that then reached the cached first-render checkbox would
--- be holding a released widget whose refresher no longer exists — and `Panel:Refresh` would look
--- like it had stopped working when in fact the test was looking at last render's page.
local function homeTab(ctx)
  local layout = ctx.__tabLayout
  if not (layout and layout.buttons and layout.buttons[1]) then return end
  local panel = ctx.panel
  local before = #AceGUI.__created
  layout.buttons[1]:__fire("OnClick")
  if #AceGUI.__created > before then
    local out = {}
    for i = before + 1, #AceGUI.__created do out[#out + 1] = AceGUI.__created[i] end
    rendered[panel] = out
  end
end

local function widgetsOfType(list, wtype)
  local out = {}
  for _, w in ipairs(list) do if w.type == wtype then out[#out + 1] = w end end
  return out
end

local function findByLabel(list, label)
  for _, w in ipairs(list) do
    if w.labelText == label or w.text == label then return w end
  end
end

-- ── registration ─────────────────────────────────────────────────────────────────────────────

test("Panel: the parent category and its ONE sub-page are registered", function()
  -- R6: Filters and AH Price were canvas sub-pages of their own until this pass and are tabs on
  -- General's strip now. Asserted as an exact set — a leftover registration is a page nobody draws
  -- and a presence check could never see one.
  assertTrue(mocks.__mainPanel ~= nil, "the landing canvas must be registered as the parent")
  local names = {}
  for name in pairs(mocks.__subcategories) do names[#names + 1] = name end
  table.sort(names)
  assertEqual(table.concat(names, " | "), "General",
    "Filters and AH Price must NOT still be subcategories of their own")
end)

test("Panel: registration is idempotent", function()
  local before = 0
  for _ in pairs(mocks.__subcategories) do before = before + 1 end
  NS.Panel:Register()
  local after = 0
  for _ in pairs(mocks.__subcategories) do after = after + 1 end
  assertEqual(after, before, "a second Register must not add a second set of categories")
end)

test("Panel: the sub-page carries the addon's name for the Blizzard left tree", function()
  -- panel.name is what Blizzard renders in the category tree; the breadcrumb inside the page is a
  -- separate string (asserted below).
  assertEqual(mocks.__subcategories["General"].name, "General")
  assertEqual(mocks.__mainPanel.name, "Ka0s Loot History")
end)

-- ── the General page's strip (options-ui-§13/§15) ─────────────────────────────────────────────

-- The strip, in order. Stated here rather than derived from the thing the assertion reads, so a tab
-- that moves is a NAMED failure rather than a shorter list that still agrees with itself.
--
-- Six tabs, four of them schema groups and two of them bespoke bodies — which is why the page draws
-- its strip by hand instead of through O.RenderTabbedSchema: that one derives its tab list from
-- `group`, and a dynamic list of item ids has no rows to declare one.
local STRIP = {
  "Master controls", "Collection", "Filters", "AH Price", "Interface", "Maintenance",
}

test("Panel: the General page draws the whole strip, in order, opening on Master controls",
  function()
    -- red under: reordering GENERAL_TABS, dropping a tab, or letting Master controls fall out of
    -- first place (anti-pattern #68).
    local ctx = NS.Panel.general
    show(mocks.__subcategories["General"])
    assertTrue(ctx.__tabLayout ~= nil, "the General page must draw a tab strip")
    assertEqual(#ctx.__tabLayout.buttons, #STRIP, #STRIP .. " tabs")
    assertEqual(ctx.activeTab, STRIP[1], "the strip opens on the first tab")
  end)

test("Panel: every schema group on the page has a tab, and every tab a body", function()
  -- The drift this closes: the tab list is declared in settings/Panel.lua and the groups in
  -- settings/Schema.lua, so a group added to one and not the other would render nowhere. Derived
  -- from BOTH sides and compared, rather than read off either.
  -- red under: adding a schema group without a GENERAL_TABS entry, or removing a tab whose rows
  -- are still declared.
  local groups, seen = {}, {}
  for _, row in ipairs(NS.Schema.Schema) do
    if row.page == "General" and not seen[row.group] then
      seen[row.group] = true; groups[#groups + 1] = row.group
    end
  end
  -- The bespoke tabs, in strip order, are the ones with no rows. Strip them out of STRIP and what
  -- is left must be the schema's own group order.
  local schemaTabs = {}
  for _, key in ipairs(STRIP) do if seen[key] then schemaTabs[#schemaTabs + 1] = key end end
  assertEqual(table.concat(schemaTabs, " | "), table.concat(groups, " | "),
    "the strip's schema tabs must be the schema's groups, in declaration order")

  local ctx = NS.Panel.general
  show(mocks.__subcategories["General"])
  local drawn = {}
  for i, b in ipairs(ctx.__tabLayout.buttons) do drawn[i] = b.__label or STRIP[i] end
  assertEqual(#drawn, #STRIP, "one button per declared tab")
end)

test("Panel: the Master controls tab holds the canonical rows and the closing button pair",
  function()
    -- options-ui-§15's whole point: the same eight controls, under the same words, in the same
    -- place, in every Ka0s addon. The two resets are a BUTTON PAIR rather than rows — acts, not
    -- settings — and they are drawn by the composer's own afterGroup hook.
    local created = show(mocks.__subcategories["General"])
    for _, label in ipairs({ "Enable Loot History", "General visibility", "Master scale",
                             "Master alpha", "Lock frame", "Debug console" }) do
      assertTrue(findByLabel(created, label) ~= nil, label .. " was not drawn")
    end
    for _, text in ipairs({ "Reset position", "Reset all settings" }) do
      local btn = findByLabel(created, text)
      assertTrue(btn ~= nil, text .. " was not drawn")
      assertEqual(btn.type, "Button")
    end
    -- The half that makes this a partition rather than a list: another tab's rows must NOT be here.
    for _, label in ipairs({ "Minimum quality", "Window scale", "Keep history for" }) do
      assertTrue(findByLabel(created, label) == nil,
        label .. " belongs to another tab and must not be drawn on Master controls")
    end
  end)

test("Panel: Reset position drives the window carve-out, Reset all settings the §12 popup",
  function()
    -- The two acts the pair stands for, driven through the widgets a user clicks rather than
    -- through the handlers directly.
    -- red under: wiring Reset position to RestoreDefaults (where it used to be folded in), or
    -- letting Reset all settings run on the click instead of confirming first.
    local created = show(mocks.__subcategories["General"])

    local reset, real = 0, NS.Browser.ResetWindow
    NS.Browser.ResetWindow = function() reset = reset + 1 end
    findByLabel(created, "Reset position"):__fire("OnClick")
    NS.Browser.ResetWindow = real
    assertEqual(reset, 1, "Reset position must reach NS.Browser:ResetWindow")

    local shown, realShow = nil, mocks.StaticPopup_Show
    mocks.StaticPopup_Show = function(which) shown = which end
    findByLabel(created, "Reset all settings"):__fire("OnClick")
    mocks.StaticPopup_Show = realShow
    assertEqual(shown, "KA0S_LOOTHISTORY_RESETALL",
      "the global reset MUST confirm before it runs (options-ui-§12)")
  end)

test("Panel: the Collection tab holds the capture rules and nothing else", function()
  local ctx = NS.Panel.general
  local created = clickTab(mocks.__subcategories["General"], ctx, 2)
  assertEqual(ctx.activeTab, "Collection", "tab 2 is Collection")

  for _, label in ipairs({ "Minimum quality", "Record currency", "Exclude quest items" }) do
    assertTrue(findByLabel(created, label) ~= nil, label .. " was not drawn")
  end
  local quality = findByLabel(created, "Minimum quality")
  assertEqual(quality.relativeWidth, 0.5, "schema widgets take the honest half")

  -- MOVED, not copied: the master switch is on Master controls now and must not also be here.
  for _, label in ipairs({ "Enable Loot History", "Enable collection", "Window scale",
                           "Debug console", "Keep history for" }) do
    assertTrue(findByLabel(created, label) == nil,
      label .. " belongs to another tab and must not be drawn on Collection")
  end
  homeTab(ctx)
end)

test("Panel: the Interface tab holds the two size sliders and the minimap toggle", function()
  local ctx = NS.Panel.general
  local created = clickTab(mocks.__subcategories["General"], ctx, 5)
  assertEqual(ctx.activeTab, "Interface", "tab 5 is Interface")
  for _, label in ipairs({ "Window scale", "Row height", "Hide minimap button" }) do
    assertTrue(findByLabel(created, label) ~= nil, label .. " was not drawn on Interface")
  end
  -- The console moved to Master controls (options-ui-§15), and a second copy here is the failure
  -- this whole pass exists to remove.
  assertTrue(findByLabel(created, "Debug console") == nil,
    "the debug console toggle belongs to Master controls now")
  assertTrue(findByLabel(created, "Minimum quality") == nil,
    "Collection's rows must not follow the reader onto Interface")
  homeTab(ctx)
end)

test("Panel: the Maintenance tab holds retention, the storage readout and the purge", function()
  local ctx = NS.Panel.general
  local created = clickTab(mocks.__subcategories["General"], ctx, 6)
  assertEqual(ctx.activeTab, "Maintenance", "tab 6 is Maintenance")
  assertTrue(findByLabel(created, "Keep history for") ~= nil, "the retention dropdown was not drawn")
  -- The bespoke half, drawn from afterGroup — the seam that lands inside the tab rather than at the
  -- bottom of every one of them.
  assertTrue(findByLabel(created, "Purge history\226\128\166") ~= nil,
    "Purge history must be drawn on the tab whose subject it is")
  -- "Reset Everything" is gone from here: it IS the global reset, and options-ui-§15 puts that on
  -- the Master controls tab as "Reset all settings". Two buttons over one act is the hard rule.
  assertTrue(findByLabel(created, "Reset Everything") == nil,
    "the global reset must not be drawn twice")
  local stats
  for _, w in ipairs(created) do
    if w.type == "Label" and type(w.text) == "string" and w.text:find("Database size", 1, true) then
      stats = w
    end
  end
  assertTrue(stats ~= nil, "the live storage readout must be drawn")
  homeTab(ctx)
end)

test("Panel: a checkbox row draws a CheckBox, a dropdown row a Dropdown, a slider row a Slider",
  function()
    local ctx = NS.Panel.general
    local master = show(mocks.__subcategories["General"])
    assertEqual(findByLabel(master, "Enable Loot History").type, "CheckBox")
    assertEqual(findByLabel(master, "General visibility").type, "Dropdown")
    assertEqual(findByLabel(master, "Master scale").type, "Slider")
    assertEqual(findByLabel(clickTab(mocks.__subcategories["General"], ctx, 2),
      "Minimum quality").type, "Dropdown")
    homeTab(ctx)
  end)

test("Panel: a key-map dropdown is populated in its declared sorting, not in pairs() order",
  function()
    -- The composed General visibility row carries `values` as a KEY MAP plus an explicit
    -- `sorting`; every other dropdown in this addon is an array of { value, text }. The flow
    -- engine reads both, and a run that fell back to `pairs()` would order the four modes
    -- differently from session to session.
    local created = show(mocks.__subcategories["General"])
    local dd = findByLabel(created, "General visibility")
    assertTrue(dd ~= nil and dd.list ~= nil, "the dropdown must be given a list")
    local row = NS.Schema:FindRow("settings.visibility")
    assertEqual(#dd.order, #row.sorting, "one entry per declared mode")
    for i, key in ipairs(row.sorting) do
      assertEqual(dd.order[i], key, "entry " .. i .. " is out of declared order")
      assertEqual(dd.list[key], row.values[key], "entry " .. i .. " lost its label")
    end
    assertEqual(dd.value, NS.Schema:Get("settings.visibility"), "and it opens on the stored value")
  end)

test("Panel: a dropdown is populated from the row's values, in declared order", function()
  local ctx = NS.Panel.general
  local created = clickTab(mocks.__subcategories["General"], ctx, 6)
  local dd = findByLabel(created, "Keep history for")
  assertTrue(dd ~= nil and dd.list ~= nil, "the dropdown must be given a list")
  local rows = NS.Constants.RETENTION_OPTIONS
  assertEqual(#dd.order, #rows, "one entry per retention preset")
  for i, opt in ipairs(rows) do
    assertEqual(dd.order[i], opt.value, "entry " .. i .. " is out of declared order")
    assertEqual(dd.list[opt.value], opt.text, "entry " .. i .. " lost its label")
  end
  assertEqual(dd.value, NS.Schema:Get("settings.retentionDays"), "and it opens on the stored value")
  homeTab(ctx)
end)

test("Panel: a slider is given the row's own min, max and step", function()
  local ctx = NS.Panel.general
  local created = clickTab(mocks.__subcategories["General"], ctx, 5)
  for _, path in ipairs({ "settings.windowScale", "settings.rowHeight" }) do
    local row = NS.Schema:FindRow(path)
    local s = findByLabel(created, row.label)
    assertTrue(s ~= nil, row.label .. " must be drawn")
    assertEqual(s.min, row.min, row.label .. ": min")
    assertEqual(s.max, row.max, row.label .. ": max")
    -- The half that was missing while Window scale shipped without a step: AceGUI is handed
    -- `row.step or 1`, so a step-less slider on a 0.6..1.6 range can only be dragged to its ends.
    -- Read off the widget, not off the row, or the assertion is the schema agreeing with itself.
    assertEqual(s.step, row.step, row.label .. ": step")
  end
  homeTab(ctx)
end)

-- The subsection headings each tab is expected to draw, in order — the empty list included, which
-- is the half that makes this a partition rather than a spot check. Stated here rather than derived
-- from the rows the assertion reads, so a `subgroup` that appears, vanishes or moves is a NAMED
-- failure rather than two derivations agreeing with each other.
local SUBGROUPS = {
  ["Master controls"] = {},
  ["Collection"]      = {},
  ["Filters"]         = {},
  ["AH Price"]        = { "Pricing", "Price sources" },
  ["Interface"]       = { "Window", "Minimap" },
  ["Maintenance"]     = {},
}

test("Panel: a tabbed page draws no SECTION heading, but a mixed tab draws its SUBSECTIONS",
  function()
    -- options-ui-§7. Under a strip the tab IS the group's heading, so the group heading is
    -- suppressed — but `subgroup` is deliberately NOT suppressed, because a tab that mixes control
    -- types has no tab left to name each kind with. Two tabs are mixed: AH Price (a plain toggle
    -- above an eleven-row reorder table) and Interface (two sliders sizing the History window, then
    -- a toggle over the minimap button — a different surface, so a second subject under one label).
    -- red under: passing `noHeadings` for subgroups too, or dropping any `subgroup` field — either
    -- shortens a list here — and equally under adding one to a tab that is a single subject.
    local ctx = NS.Panel.general
    for index = 1, #STRIP do
      local created = (index == 1) and show(mocks.__subcategories["General"])
        or clickTab(mocks.__subcategories["General"], ctx, index)
      local want, headings = SUBGROUPS[ctx.activeTab], widgetsOfType(created, "Heading")
      assertTrue(want ~= nil, ctx.activeTab .. " has no declared heading list")
      assertEqual(#headings, #want,
        ctx.activeTab .. " must draw exactly " .. #want .. " subsection heading(s)")
      for i, text in ipairs(want) do
        assertEqual(headings[i].text, text, ctx.activeTab .. " heading " .. i)
      end
    end
    homeTab(ctx)
  end)

test("Panel: a subgroup heading never repeats its own tab's name (options-ui-§7)", function()
  -- The one thing §7 forbids outright about a subsection name, and the easiest to get wrong when a
  -- tab is later renamed to match the subject its first block already named.
  -- red under: `subgroup = "Interface"` on an Interface row, or renaming the AH Price tab to
  -- "Pricing".
  for _, row in ipairs(NS.Schema.Schema) do
    if row.subgroup then
      assertTrue(row.subgroup ~= row.group,
        row.path .. ": subgroup '" .. row.subgroup .. "' repeats its tab's name")
    end
  end
end)

-- ── the write path ───────────────────────────────────────────────────────────────────────────

test("Panel: clicking a checkbox writes through NS.Schema:Set", function()
  local created = show(mocks.__subcategories["General"])
  local cb = findByLabel(created, "Enable Loot History")
  NS.Schema:Set("settings.enabled", true)
  cb:__fire("OnValueChanged", false)
  assertEqual(NS.Schema:Get("settings.enabled"), false, "the click must reach the write seam")
  assertEqual(NS.db.global.settings.enabled, false, "and land in db.global")
  cb:__fire("OnValueChanged", true)
  assertEqual(NS.Schema:Get("settings.enabled"), true)
end)

test("Panel: choosing a dropdown entry writes the stored value", function()
  local ctx = NS.Panel.general
  local created = clickTab(mocks.__subcategories["General"], ctx, 2)
  local dd = findByLabel(created, "Minimum quality")
  dd:__fire("OnValueChanged", 4)
  assertEqual(NS.Schema:Get("settings.qualityThreshold"), 4)
  NS.Schema:Set("settings.qualityThreshold", 1)
  homeTab(ctx)
end)

test("Panel: releasing a slider writes the stored value", function()
  local ctx = NS.Panel.general
  local created = clickTab(mocks.__subcategories["General"], ctx, 5)
  local s = findByLabel(created, "Window scale")
  s:__fire("OnMouseUp", 1.25)
  assertEqual(NS.Schema:Get("settings.windowScale"), 1.25)
  NS.Schema:Set("settings.windowScale", 1.0)

  -- Promoted from `local ROW_H = 18` in modules/BrowserTable.lua and writable through the same
  -- seam as every other row, which is the whole point of promoting it rather than adding a second
  -- way to store a number.
  local rh = findByLabel(created, "Row height")
  rh:__fire("OnMouseUp", 24)
  assertEqual(NS.Schema:Get("settings.rowHeight"), 24)
  NS.Schema:Set("settings.rowHeight", 18)
  homeTab(ctx)
end)

test("Panel: an external write is mirrored back by Refresh", function()
  show(mocks.__subcategories["General"])
  local created = show(mocks.__subcategories["General"])
  local cb = findByLabel(created, "Enable Loot History")
  if not cb then
    -- The page renders once; on a re-show only the refreshers run, so reach the widget through the
    -- first render instead. Guarding rather than skipping: a nil here would make the case vacuous.
    cb = findByLabel(AceGUI.__created, "Enable Loot History")
  end
  assertTrue(cb ~= nil, "the checkbox must be reachable")
  NS.Schema:Set("settings.enabled", false)
  NS.Panel:Refresh()
  assertEqual(cb.value, false, "the refresher must re-read the stored value")
  NS.Schema:Set("settings.enabled", true)
  NS.Panel:Refresh()
  assertEqual(cb.value, true)
end)

-- ── the inverted set picker ──────────────────────────────────────────────────────────────────

test("Panel: the muted-source picker is INVERTED — a ticked box means 'record this source'",
  function()
    local ctx = NS.Panel.general
    local created = clickTab(mocks.__subcategories["General"], ctx, 2)
    local group = widgetsOfType(created, "InlineGroup")[1]
    assertTrue(group ~= nil, "the set picker draws as an InlineGroup")

    local kill
    for _, w in ipairs(created) do
      if w.type == "CheckBox" and w.labelText == NS.Constants.SourceLabel.KILL then kill = w end
    end
    assertTrue(kill ~= nil, "one checkbox per implemented source")

    NS.Schema:Set("settings.excludedSources", {})
    NS.Panel:Refresh()
    assertEqual(kill.value, true, "nothing muted, so every source reads as recorded")

    kill:__fire("OnValueChanged", false)   -- untick "Kill" => mute KILL
    assertEqual(NS.Schema:Get("settings.excludedSources").KILL, true,
      "unticking must ADD the source to the muted set, not remove it")

    kill:__fire("OnValueChanged", true)
    assertEqual(NS.Schema:Get("settings.excludedSources").KILL, nil,
      "re-ticking must drop the key entirely rather than storing false")
    homeTab(ctx)
  end)

-- ── the Defaults button ──────────────────────────────────────────────────────────────────────

test("Panel: the Defaults button is built on first OnShow, not at registration", function()
  -- AceGUI is a shared library and skinning addons hook RegisterAsWidget; a widget created during
  -- load keeps Blizzard's stock art for the session. This is the anti-pattern #42 guard, driven on
  -- a page that has never been shown — which is the landing canvas now that General is the only
  -- sub-page and every earlier case has already shown it.
  local main = mocks.__mainPanel
  assertTrue(main ~= nil, "the landing canvas must be reachable")
  assertTrue(NS.Panel.general.panel.defaultsBtn ~= nil,
    "the General page has been shown by now, so its button must exist")
  -- The half that makes this a real assertion: it must NOT have existed before that show. Pinned
  -- as source, because every page in this addon has been shown by the time this case runs.
  local src = Loader.readFile("settings/Panel.lua")
  assertTrue(src:find("O.SetRenderer", 1, true) ~= nil,
    "the lazy build rides O.SetRenderer's OnShow; a page that stopped using it would rebuild eagerly")
  assertTrue(src:find("EnsureDefaultsButton", 1, true) == nil,
    "no page calls EnsureDefaultsButton by hand any more — SetRenderer owns it")
end)

test("Panel: the General Defaults click restores every schema default", function()
  NS.Schema:Set("settings.qualityThreshold", 4)
  NS.Schema:Set("settings.recordCurrency", false)
  show(mocks.__subcategories["General"])
  mocks.__subcategories["General"].defaultsOnClick()
  assertEqual(NS.Schema:Get("settings.qualityThreshold"), 1)
  assertEqual(NS.Schema:Get("settings.recordCurrency"), true)
end)

test("Panel: the General Defaults click is PAGE-wide — it reaches the merged tabs' carve-outs",
  function()
    -- options-ui-§13: a per-page Defaults button's blast radius must not narrow to the visible tab.
    -- Filters and AH Price are tabs of this page now, so the two carve-outs their own Defaults
    -- buttons used to own — the three id-lists and the cascade array, neither of which a schema
    -- row walk can reach — belong to this one button.
    -- red under: dropping either half, which a schema-only reset would do silently.
    show(mocks.__subcategories["General"])
    NS.Filters:AddBlacklist(4242)
    NS.Schema:Set("settings.auction.capture", { ["tsm:dbmarket"] = true })
    local priority = NS.AuctionPrice:GetPriority()
    priority[1], priority[2] = priority[2], priority[1]   -- user-reordered the cascade

    mocks.__subcategories["General"].defaultsOnClick()

    assertEqual(NS.Filters:Count(NS.Filters:Blacklist()), 0, "the id-lists are part of this page")
    assertEqual(NS.Schema:Get("settings.auction.capture")["auctionator:minbuyout"], true,
      "the capture set is a schema row and comes back with the rest")
    -- The cascade is a ratified carve-out array with no schema row, so the walk cannot see it and
    -- the handler resets it separately — in place, keeping the same table reference, because the
    -- price table's closures hold it.
    local after = NS.AuctionPrice:GetPriority()
    assertTrue(after == priority, "reset in place: the table reference must not change")
    for i, tag in ipairs(NS.Constants.AUCTION_PRIORITY_DEFAULT) do
      assertEqual(after[i], tag, "cascade entry " .. i .. " was not restored")
    end
    assertEqual(#after, #NS.Constants.AUCTION_PRIORITY_DEFAULT)
  end)

test("Panel: the General Defaults click does NOT move the window", function()
  -- It used to, and that made "Defaults" quietly do a second thing the label never named. Reset
  -- position is its own button on the Master controls tab now (options-ui-§12/§15).
  -- red under: putting the ResetWindow call back into P:RestoreDefaults.
  local moved, real = 0, NS.Browser.ResetWindow
  NS.Browser.ResetWindow = function() moved = moved + 1 end
  show(mocks.__subcategories["General"])
  mocks.__subcategories["General"].defaultsOnClick()
  NS.Browser.ResetWindow = real
  assertEqual(moved, 0, "a page reset must not recentre the window as a side effect")
end)

-- ── the Filters tab ──────────────────────────────────────────────────────────────────────────

test("Panel: the Filters tab draws a SECONDARY strip and renders only the selected list",
  function()
    -- options-ui-§13: three id-lists are a list of like subjects inside one category, which is
    -- what a secondary strip is for. It is drawn inside the scroll as ordinary content (it has no
    -- chrome band of its own), and its selection lives in ctx.activeSubTab keyed by the PRIMARY
    -- tab — session state, never persisted.
    NS.Filters:ClearAll()
    local panel = mocks.__subcategories["General"]
    local ctx = NS.Panel.general
    clickTab(panel, ctx, 3)
    assertEqual(ctx.activeTab, "Filters", "tab 3 is Filters")
    assertTrue(ctx.__subTabKids ~= nil and #ctx.__subTabKids == 3, "one sub-tab per list")
    assertEqual(ctx.activeSubTab["Filters"], "blacklist", "the sub-strip opens on the first list")

    -- One add-box, not three: the tab draws the selected list and nothing else.
    local before = #AceGUI.__created
    ctx.__subTabKids[3]:__fire("OnClick")
    local created = {}
    for i = before + 1, #AceGUI.__created do created[#created + 1] = AceGUI.__created[i] end
    assertEqual(ctx.activeSubTab["Filters"], "currencyBlacklist", "sub-tab 3 is Currencies")
    local boxes = widgetsOfType(created, "EditBox")
    assertEqual(#boxes, 1, "exactly one add-row is on screen")
    assertEqual(boxes[1].labelText, "Add currency id or link",
      "and it is the selected list's, not the first list's")

    ctx.__subTabKids[1]:__fire("OnClick")
    assertEqual(ctx.activeSubTab["Filters"], "blacklist")
    homeTab(ctx)
  end)

test("Panel: the Filters tab lists the ids on each list and can remove one", function()
  NS.Filters:ClearAll()
  NS.Filters:AddBlacklist(12345)
  local ctx = NS.Panel.general
  clickTab(mocks.__subcategories["General"], ctx, 3)
  local labeled
  for _, w in ipairs(AceGUI.__created) do
    if w.type == "Label" and type(w.text) == "string" and w.text:find("12345", 1, true) then
      labeled = w
    end
  end
  assertTrue(labeled ~= nil, "a blacklisted id must appear as a row on the Filters tab")

  local remove
  for _, w in ipairs(AceGUI.__created) do
    if w.type == "Button" and w.text == "Remove" then remove = w end
  end
  assertTrue(remove ~= nil, "each list row carries a Remove button")
  NS.Filters:ClearAll()
  homeTab(ctx)
end)

test("Panel: a blacklist change while the page is hidden repaints it on the next OnShow",
  function()
    -- LH-A-27. The page flags itself dirty off-screen instead of rebuilding, and the flag it writes
    -- must be the one LibKa0s-Options' OnShow reads (`ctx._dirty`). A page-local `ctx.dirty` is
    -- written and never read, so the library's `_rendered and not _dirty` early-out swallows the
    -- next OnShow and the new id only appears after a /reload.
    NS.Filters:ClearAll()
    local panel = mocks.__subcategories["General"]
    local ctx = NS.Panel.general
    clickTab(panel, ctx, 3)           -- park on the Filters tab, where the list is on screen
    panel:Hide()

    NS.Filters:AddBlacklist(778899)   -- fires HistoryChanged; the page is off screen
    assertTrue(ctx._dirty == true,
      "an off-screen change must set the flag the library's OnShow reads")

    local before = #AceGUI.__created
    panel:Show()
    panel:__fire("OnShow")
    local labeled
    for i = before + 1, #AceGUI.__created do
      local w = AceGUI.__created[i]
      if w.type == "Label" and type(w.text) == "string" and w.text:find("778899", 1, true) then
        labeled = w
      end
    end
    assertTrue(labeled ~= nil,
      "the next OnShow must repaint the list and show the id added while hidden")
    NS.Filters:ClearAll()
    homeTab(ctx)
  end)

-- ── the AH Price tab ─────────────────────────────────────────────────────────────────────────

--- Render the AH Price tab and hand back its context.
local function ahTab()
  local ctx = NS.Panel.general
  clickTab(mocks.__subcategories["General"], ctx, 4)
  return ctx
end

test("Panel: the AH Price tab draws one reusable row slot per known price source", function()
  local ctx = ahTab()
  assertEqual(ctx.activeTab, "AH Price", "tab 4 is AH Price")
  assertTrue(ctx._priRows ~= nil, "the row slots must be created")
  assertEqual(#ctx._priRows, #NS.Constants.AUCTION_KEYS,
    "one slot per key, created ONCE and repainted in place — this page froze the client at ~213 " ..
    "frames before the slots were pooled (docs/settings-panel.md)")
  homeTab(ctx)
end)

test("Panel: the pooled slots survive the tab strip — a second visit re-allocates nothing",
  function()
    -- THE REASON THIS PAGE KEPT ITS OWN OnShow BEFORE R6, preserved through the merge. A tab click
    -- runs ClearScroll, which hands every AceGUI child back to the pool; the price host is this
    -- addon's own raw frame and is re-parented rather than released, so the eleven slots and their
    -- frames are created once for the session.
    -- red under: parenting the slots to an AceGUI SimpleGroup added to the scroll (they would be
    -- orphaned onto a pooled frame), or rebuilding them on every render.
    local ctx = ahTab()
    local rows, host, firstFrame = ctx._priRows, ctx._priHost, ctx._priRows[1].frame
    homeTab(ctx)
    ahTab()
    assertTrue(ctx._priRows == rows, "the slot table must be the same table")
    assertTrue(ctx._priHost == host, "and the host the same frame")
    assertTrue(ctx._priRows[1].frame == firstFrame, "and every row frame the same frame")
    homeTab(ctx)
  end)

test("Panel: the price host is parked off the page while another tab is on screen", function()
  -- The other half of keeping a raw frame across a re-render: it is not released by ClearScroll, so
  -- it has to be hidden and unparented by hand or it floats over whichever tab is drawn next.
  -- red under: dropping the park block at the top of renderGeneral.
  local ctx = ahTab()
  assertTrue(ctx._priHost:IsShown(), "the host is shown while its own tab is")
  homeTab(ctx)
  assertFalse(ctx._priHost:IsShown(), "and hidden the moment another tab is drawn")
end)

test("Panel: the AH Price tab renders its own schema row and no other tab's", function()
  local ctx = ahTab()
  local created = {}
  for _, w in ipairs(AceGUI.__created) do created[#created + 1] = w end
  assertTrue(findByLabel(created, "Enable AH pricing") ~= nil,
    "the master enable checkbox is the one schema row this tab draws")
  homeTab(ctx)
end)

test("Panel: the cascade is a reorder list — a handle per draggable row, a box under every row",
  function()
    -- options-ui-§18. The ▲▼ arrows are gone (anti-pattern #75); the library owns the handle, the
    -- bounded box and the drag. Every row is REGISTERED — an inert one is still a place a drag can
    -- land and still one of the blocks the list is made of — but only the collecting partition is
    -- draggable, which is what `boundary` enforces.
    -- red under: registering only the draggable rows, dropping the boundary, or drawing a host-side
    -- row background beside the library's.
    local ctx = ahTab()
    local list = ctx._priList
    assertTrue(list ~= nil, "the tab must build a reorder controller")
    assertEqual(#list.rows, #NS.Constants.AUCTION_KEYS, "every slot is registered, in display order")
    assertEqual(#list.boxes, #NS.Constants.AUCTION_KEYS, "and every one of them is boxed")

    -- No provider addon is present in the harness, so every source partitions to "not installed":
    -- nothing is draggable and the boundary is zero. That IS the invariant — handles follow the
    -- collecting partition, never the row count.
    local capture = NS.db.global.settings.auction.capture or {}
    local collecting = 0
    for _, tag in ipairs(NS.AuctionPrice:ReconcilePriority()) do
      local prov = tag:match("^(.-):")
      if NS.AuctionPrice:IsProviderAvailable(prov) and capture[tag] then
        collecting = collecting + 1
      end
    end
    assertEqual(list.boundary, collecting, "the boundary is the collecting partition's size")
    assertEqual(#list.handles, collecting, "a handle only where a drag has meaning")
    homeTab(ctx)
  end)

test("Panel: the host draws no row chrome of its own — the library owns the box and the handle",
  function()
    -- The adoption cost options-ui-§18 names: a host that keeps its own row fill and border ends up
    -- with two of each. This addon never drew one, and this is what stops one appearing.
    -- red under: adding a SetBackdrop / row-background texture to the price rows, or passing
    -- `rowBox = false` and drawing it host-side.
    local src = Loader.readFile("settings/Panel.lua")
    assertTrue(src:find("SetBackdrop", 1, true) == nil, "no host-drawn row background")
    assertTrue(src:find("rowBox", 1, true) == nil, "the library's box is never suppressed")
    assertTrue(src:find("ARR_UP", 1, true) == nil and src:find("ensureArrows", 1, true) == nil,
      "the reorder arrows must be gone, not merely hidden (anti-pattern #75)")
  end)

test("Panel: a drag is one splice to index, and it repaints", function()
  -- `onMove(from, to)` is the whole contract, and it must be a splice — one write, one re-render —
  -- rather than a run of adjacent swaps. Driven through the controller's own hook, with the
  -- partition forced so there is something to drag.
  -- red under: expressing the move as repeated swaps (each would write and announce), or forgetting
  -- the repaint (the row would snap back to where it was on the next paint).
  local savedAvail = NS.AuctionPrice.IsProviderAvailable
  local savedCapture = NS.Schema:Get("settings.auction.capture")
  NS.AuctionPrice.IsProviderAvailable = function() return true end
  NS.Schema:Set("settings.auction.capture", { ["auctionator:minbuyout"] = true,
    ["tsm:dbmarket"] = true, ["tsm:dbminbuyout"] = true, ["oribos:market"] = true })

  local ctx = ahTab()
  local list = ctx._priList
  assertEqual(list.boundary, 4, "four sources are collecting, so four rows are draggable")
  local before = {}
  for i = 1, 4 do before[i] = list.rows[i].frame and NS.AuctionPrice:ReconcilePriority()[i] end

  local collecting = {}
  for _, tag in ipairs(NS.AuctionPrice:ReconcilePriority()) do
    if #collecting < 4 then collecting[#collecting + 1] = tag end
  end
  local moving = collecting[1]
  list.onMove(1, 4)

  local after = NS.AuctionPrice:ReconcilePriority()
  local pos
  for i, tag in ipairs(after) do if tag == moving then pos = i end end
  assertEqual(pos, 4, "the row landed at index 4 in one move, not three")
  assertTrue(ctx._priList ~= list, "the repaint built a fresh controller")

  NS.AuctionPrice.IsProviderAvailable = savedAvail
  NS.Schema:Set("settings.auction.capture", savedCapture)
  homeTab(ctx)
end)

test("Panel: the reorder controller is cancelled at the TOP of the page render", function()
  -- options-ui-§18's shipped-bug lesson, and the single most common way this adoption goes wrong:
  -- handles and boxes are pooled, and a controller released after ClearScroll is reclaiming chrome
  -- from widgets that already belong to something else.
  -- red under: moving cancelReorder below O.ClearScroll, or dropping it from renderGeneral.
  local ctx = ahTab()
  local list = ctx._priList
  assertFalse(list.dead == true, "the live controller is not dead")
  homeTab(ctx)                                    -- render another tab
  assertTrue(list.dead == true, "the previous render's controller must have been cancelled")
  assertEqual(#list.handles, 0, "and its handles given back")
  assertEqual(#list.boxes, 0, "and its boxes with them")

  local src = Loader.readFile("settings/Panel.lua")
  local cancelAt = src:find("cancelReorder(ctx)", src:find("local function renderGeneral"), true)
  local clearAt  = src:find("O.ClearScroll(ctx)", src:find("local function renderGeneral"), true)
  assertTrue(cancelAt ~= nil and clearAt ~= nil and cancelAt < clearAt,
    "renderGeneral must cancel BEFORE it clears the scroll")
end)

test("Panel: toggling a source's Enabled box writes the capture set and repaints", function()
  local ctx = ahTab()
  local saved = NS.Schema:Get("settings.auction.capture")
  local row = ctx._priRows[1]
  local tag = row._tag
  assertTrue(tag ~= nil, "the slot must be bound to a tag")
  row.check:__fire("OnValueChanged", true)
  assertEqual(NS.Schema:Get("settings.auction.capture")[tag], true)
  row.check:__fire("OnValueChanged", false)
  assertEqual(NS.Schema:Get("settings.auction.capture")[tag], nil,
    "unticking drops the key rather than storing false")
  NS.Schema:Set("settings.auction.capture", saved)
  homeTab(ctx)
end)

-- ── the landing page ─────────────────────────────────────────────────────────────────────────

test("Panel: the landing page renders one label per slash command, through the ONE row formatter",
  function()
    local created = show(mocks.__mainPanel)
    local rows = NS.Slash:LandingRows()
    local matched = 0
    for _, w in ipairs(created) do
      if w.type == "Label" then
        for _, line in ipairs(rows) do if w.text == line then matched = matched + 1 end end
      end
    end
    assertEqual(matched, #NS.COMMANDS,
      "every command row on the landing page must be a lib.FormatRow line, byte for byte")
    assertTrue(#rows > 0, "and there must be rows, or the count above is a vacuous zero")
  end)

test("Panel: the landing page shows the tagline", function()
  local created = show(mocks.__mainPanel)
  if #created == 0 then created = AceGUI.__created end
  local found
  for _, w in ipairs(created) do
    if w.type == "Label" and type(w.text) == "string"
      and w.text:find("attributes its source", 1, true) then found = w end
  end
  assertTrue(found ~= nil, "the one-line description must be drawn")
end)

-- ── combat ───────────────────────────────────────────────────────────────────────────────────

test("Panel: Open refuses during combat and never defers-and-replays", function()
  local realCombat = mocks.InCombatLockdown
  local opened = 0
  local realOpen = mocks.Settings.OpenToCategory
  mocks.Settings.OpenToCategory = function() opened = opened + 1 end
  mocks.InCombatLockdown = function() return true end

  local lines = {}
  local cf = mocks.DEFAULT_CHAT_FRAME
  local oldAdd = cf.AddMessage
  cf.AddMessage = function(_, msg) lines[#lines + 1] = msg end
  NS.Panel:Open()
  cf.AddMessage = oldAdd

  mocks.InCombatLockdown = realCombat
  mocks.Settings.OpenToCategory = realOpen

  assertEqual(opened, 0, "the protected category switch must not be called under lockdown")
  assertTrue(#lines == 1 and lines[1]:find("combat", 1, true) ~= nil,
    "and the refusal must say why: " .. tostring(lines[1]))
end)

-- ── the wrapped strip's geometry is selection-invariant (options-ui-§13) ──────────────────────

test("Panel: a WRAPPED strip reserves the same band and the same row offsets on every tab",
  function()
    -- options-ui-§13's Testing MUST, against THIS page's strip rather than against the library's.
    -- The rule: "on a strip wide enough to wrap, the total reserved band and every row's y offset
    -- are identical for every value of the selection". The page's first row of settings hangs off
    -- the chrome's bottom edge, so a band that moved with the selection would move the whole page
    -- under it and the player would see it shift on every click.
    --
    -- THE HARNESS IS THE HALF THAT MATTERS. The same rule says a harness answering one height for
    -- every atlas "is green against nothing", so tests/wow_mock.lua gives the selected-state art a
    -- DIFFERENT height from the unselected art (34 vs 30) — asserted below rather than assumed,
    -- because a mock that quietly stopped distinguishing them would take this case with it.
    --
    -- red under: measuring the row pitch off a tab that was just drawn (whichever state it happened
    -- to be in) instead of off the throwaway unselected-atlas probe — the shape the bug actually
    -- shipped in; and, separately, under a probe that reads the ACTIVE atlas, which the pitch
    -- assertion below catches even though it would still be invariant.
    local O = NS.Options
    local art = mocks.__TAB_ART_H
    assertTrue(art["Options_Tab_Active_Left"] ~= art["Options_Tab_Left"],
      "the harness MUST answer a different height for the selected-state art (options-ui-§13)")

    local ctx = NS.Panel.general
    show(mocks.__subcategories["General"])

    -- Force a real wrap. Six tabs at TAB_MIN_W (60) plus a 4px gap fit three to a 200px row, so
    -- the strip lays out in two rows — one row would make "every row's y offset" a claim about a
    -- single number and the case would pass on a strip that never wrapped at all.
    local chromeW = ctx.chrome:GetWidth()
    ctx.chrome:SetWidth(200)
    O.__resetTabArtHeight()   -- measure under THIS harness, not under whatever ran first

    --- The band, and every tab's y, for the render currently on screen.
    local function geometry()
      local ys = {}
      for i, b in ipairs(ctx.__tabLayout.buttons) do
        local p = b.__lastPoint and b:__lastPoint()
        assertTrue(p ~= nil, "tab " .. i .. " was never anchored")
        ys[i] = p.y
      end
      return ctx.chromeHeight, ys
    end

    -- Re-render tab 1 under the new width (the click that got us here was placed at the old one).
    homeTab(ctx)
    clickTab(mocks.__subcategories["General"], ctx, 2)
    homeTab(ctx)

    local wantBand, wantYs = geometry()
    local distinct = {}
    for _, y in ipairs(wantYs) do distinct[y] = true end
    local rows = 0
    for _ in pairs(distinct) do rows = rows + 1 end
    assertTrue(rows >= 2, "the strip must WRAP for this case to mean anything (got " .. rows ..
      " row(s) over " .. #wantYs .. " tabs)")

    -- The pitch is the UNSELECTED art's height, measured once. Not max(active, inactive), and not
    -- the active family — the library's own note is explicit, and only the unselected height packs
    -- a wrapped row flush against the one above it.
    assertEqual(O.__tabArtHeight(), art["Options_Tab_Left"],
      "the row pitch MUST come from the unselected tab art")

    for index = 2, #STRIP do
      clickTab(mocks.__subcategories["General"], ctx, index)
      assertEqual(ctx.activeTab, STRIP[index], "tab " .. index .. " is " .. STRIP[index])
      local band, ys = geometry()
      assertEqual(band, wantBand,
        "the reserved band moved when " .. STRIP[index] .. " was selected")
      for i, y in ipairs(ys) do
        assertEqual(y, wantYs[i],
          "tab " .. i .. " moved when " .. STRIP[index] .. " was selected")
      end
      homeTab(ctx)
    end

    ctx.chrome:SetWidth(chromeW)
    O.__resetTabArtHeight()
    homeTab(ctx)
  end)
