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
local NS, mocks = T.NS, T.mocks
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

test("Panel: the parent category and all three sub-pages are registered", function()
  assertTrue(mocks.__mainPanel ~= nil, "the landing canvas must be registered as the parent")
  for _, name in ipairs({ "General", "Filters", "AH Price" }) do
    assertTrue(mocks.__subcategories[name] ~= nil, name .. " subcategory was not registered")
  end
end)

test("Panel: registration is idempotent", function()
  local before = 0
  for _ in pairs(mocks.__subcategories) do before = before + 1 end
  NS.Panel:Register()
  local after = 0
  for _ in pairs(mocks.__subcategories) do after = after + 1 end
  assertEqual(after, before, "a second Register must not add a second set of categories")
end)

test("Panel: each sub-page carries the addon's name for the Blizzard left tree", function()
  -- panel.name is what Blizzard renders in the category tree; the breadcrumb inside the page is a
  -- separate string (asserted below).
  assertEqual(mocks.__subcategories["General"].name, "General")
  assertEqual(mocks.__subcategories["Filters"].name, "Filters")
  assertEqual(mocks.__subcategories["AH Price"].name, "AH Price")
  assertEqual(mocks.__mainPanel.name, "Ka0s Loot History")
end)

-- ── the General page: the schema render ──────────────────────────────────────────────────────

test("Panel: the General page draws one tab per schema group, in declaration order", function()
  -- options-ui-§13. The page was three scrolling sections under three headings; it is a strip of
  -- three tabs now, and only the selected tab's rows are on screen. The strip's ORDER is the
  -- schema's declaration order, which is the whole contract RenderTabbedSchema offers.
  local ctx = NS.Panel.general
  show(mocks.__subcategories["General"])
  assertTrue(ctx.__tabLayout ~= nil, "the General page must draw a tab strip")
  assertEqual(#ctx.__tabLayout.buttons, 3, "three tabs: Collection, Interface, Maintenance")
  assertEqual(ctx.activeTab, "Collection", "the strip opens on the first tab")
end)

test("Panel: the Collection tab holds the capture rules and nothing else", function()
  local created = show(mocks.__subcategories["General"])
  assertTrue(#created > 0, "the first OnShow must build the page body")

  -- [Enable collection] [Minimum quality] on one line, [Record currency] [Exclude quest items] on
  -- the next, and the full-width source picker under both from afterGroup.
  local enable = findByLabel(created, "Enable collection")
  assertTrue(enable ~= nil, "the Enable collection checkbox must be drawn")
  assertEqual(enable.type, "CheckBox")
  assertEqual(enable.relativeWidth, 0.5, "schema widgets take the honest half")

  for _, label in ipairs({ "Minimum quality", "Record currency", "Exclude quest items" }) do
    assertTrue(findByLabel(created, label) ~= nil, label .. " was not drawn")
  end
  -- The half that makes this a partition rather than a list: another tab's rows must NOT be here.
  -- Without it the page could still be drawing all nine rows on one scroll and pass.
  for _, label in ipairs({ "Window scale", "Row height", "Hide minimap button", "Debug console",
                           "Keep history for" }) do
    assertTrue(findByLabel(created, label) == nil,
      label .. " belongs to another tab and must not be drawn on Collection")
  end
end)

test("Panel: the Interface tab holds the two size sliders and the two show/hide boxes", function()
  local ctx = NS.Panel.general
  local created = clickTab(mocks.__subcategories["General"], ctx, 2)
  assertEqual(ctx.activeTab, "Interface", "tab 2 is Interface")
  for _, label in ipairs({ "Window scale", "Row height", "Hide minimap button", "Debug console" }) do
    assertTrue(findByLabel(created, label) ~= nil, label .. " was not drawn on Interface")
  end
  assertTrue(findByLabel(created, "Enable collection") == nil,
    "Collection's rows must not follow the reader onto Interface")
  homeTab(ctx)
end)

test("Panel: the Maintenance tab holds retention, the storage readout and both reset actions",
  function()
    local ctx = NS.Panel.general
    local created = clickTab(mocks.__subcategories["General"], ctx, 3)
    assertEqual(ctx.activeTab, "Maintenance", "tab 3 is Maintenance")
    assertTrue(findByLabel(created, "Keep history for") ~= nil, "the retention dropdown was not drawn")
    -- The bespoke half, drawn from afterGroup — the only seam that survives a tab click, since
    -- onSelect re-enters RenderTabbedSchema and never the page renderer.
    assertTrue(findByLabel(created, "Purge history\226\128\166") ~= nil,
      "Purge history must be drawn on the tab whose subject it is")
    assertTrue(findByLabel(created, "Reset Everything") ~= nil,
      "Reset Everything moved here from the Window scale row")
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
    local created = show(mocks.__subcategories["General"])
    assertEqual(findByLabel(created, "Enable collection").type, "CheckBox")
    assertEqual(findByLabel(created, "Minimum quality").type, "Dropdown")
    assertEqual(findByLabel(clickTab(mocks.__subcategories["General"], ctx, 2), "Window scale").type,
      "Slider")
    homeTab(ctx)
  end)

test("Panel: a dropdown is populated from the row's values, in declared order", function()
  local ctx = NS.Panel.general
  local created = clickTab(mocks.__subcategories["General"], ctx, 3)
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
  local created = clickTab(mocks.__subcategories["General"], ctx, 2)
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

test("Panel: Reset Everything sits on the Maintenance tab, on its own line", function()
  -- An ACTION button, not a setting. It used to be attached as the right half of the Window scale
  -- row through the engine's `pairWith` hook — a placement argument, not a subject one — and it is
  -- beside the purge it is a bigger version of now. It is the only entry point to the
  -- confirm-gated total reset from the panel, so a render that quietly stopped drawing it would
  -- remove a destructive action's only visible affordance.
  local ctx = NS.Panel.general
  local created = clickTab(mocks.__subcategories["General"], ctx, 3)
  -- Labeled "Reset Everything", not "Reset All": the panel button purges history on top of what
  -- `/lh resetall` does, and one name for two effects is LH-R-04.
  local btn = findByLabel(created, "Reset Everything")
  assertTrue(btn ~= nil, "the Reset Everything button must be drawn")
  assertEqual(btn.type, "Button")
  -- Inset rather than a flat half, so its right border clears the ScrollFrame clip (options-ui-§8).
  assertEqual(btn.relativeWidth, NS.Options.BUTTON_PAIR_REL)
  homeTab(ctx)
end)

test("Panel: a tabbed page draws no section headings — the strip is the heading", function()
  -- RenderTabbedSchema renders the active tab's rows with `noHeadings`, so the three
  -- GameFontNormalLarge section headings this page used to stack are gone. The bespoke History
  -- section's own heading went with them: a "History" heading inside a tab called Maintenance is
  -- the page saying it twice.
  local ctx = NS.Panel.general
  for _, index in ipairs({ 1, 2, 3 }) do
    local created = (index == 1) and show(mocks.__subcategories["General"])
      or clickTab(mocks.__subcategories["General"], ctx, index)
    assertEqual(#widgetsOfType(created, "Heading"), 0,
      ctx.activeTab .. " must draw no section heading")
  end
  homeTab(ctx)
end)

-- ── the write path ───────────────────────────────────────────────────────────────────────────

test("Panel: clicking a checkbox writes through NS.Schema:Set", function()
  local created = show(mocks.__subcategories["General"])
  local cb = findByLabel(created, "Enable collection")
  NS.Schema:Set("settings.enabled", true)
  cb:__fire("OnValueChanged", false)
  assertEqual(NS.Schema:Get("settings.enabled"), false, "the click must reach the write seam")
  assertEqual(NS.db.global.settings.enabled, false, "and land in db.global")
  cb:__fire("OnValueChanged", true)
  assertEqual(NS.Schema:Get("settings.enabled"), true)
end)

test("Panel: choosing a dropdown entry writes the stored value", function()
  local created = show(mocks.__subcategories["General"])
  local dd = findByLabel(created, "Minimum quality")
  dd:__fire("OnValueChanged", 4)
  assertEqual(NS.Schema:Get("settings.qualityThreshold"), 4)
  NS.Schema:Set("settings.qualityThreshold", 1)
end)

test("Panel: releasing a slider writes the stored value", function()
  local ctx = NS.Panel.general
  local created = clickTab(mocks.__subcategories["General"], ctx, 2)
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
  local cb = findByLabel(created, "Enable collection")
  if not cb then
    -- The page renders once; on a re-show only the refreshers run, so reach the widget through the
    -- first render instead. Guarding rather than skipping: a nil here would make the case vacuous.
    cb = findByLabel(AceGUI.__created, "Enable collection")
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
    local created = show(mocks.__subcategories["General"])
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
  end)

-- ── the Defaults buttons ─────────────────────────────────────────────────────────────────────

test("Panel: the Defaults button is built on first OnShow, not at registration", function()
  -- AceGUI is a shared library and skinning addons hook RegisterAsWidget; a widget created during
  -- load keeps Blizzard's stock art for the session. This is the anti-pattern #42 guard.
  local fresh = NS.Panel.filters
  assertTrue(fresh ~= nil, "the Filters ctx must be reachable")
  -- The half that makes this a real assertion: the button must NOT exist yet. Without it the case
  -- passes just as happily on a panel that built its button during Register().
  assertTrue(fresh.panel.defaultsBtn == nil,
    "the Defaults button must not exist before the page is first shown")
  show(mocks.__subcategories["Filters"])
  assertTrue(fresh.panel.defaultsBtn ~= nil, "OnShow must have built the button")
end)

test("Panel: the General page's Defaults click restores every schema default", function()
  NS.Schema:Set("settings.qualityThreshold", 4)
  NS.Schema:Set("settings.recordCurrency", false)
  show(mocks.__subcategories["General"])
  mocks.__subcategories["General"].defaultsOnClick()
  assertEqual(NS.Schema:Get("settings.qualityThreshold"), 1)
  assertEqual(NS.Schema:Get("settings.recordCurrency"), true)
end)

test("Panel: the AH Price page's Defaults click restores the capture set AND the priority order",
  function()
    show(mocks.__subcategories["AH Price"])
    NS.Schema:Set("settings.auction.capture", { ["tsm:dbmarket"] = true })
    local priority = NS.AuctionPrice:GetPriority()
    priority[1], priority[2] = priority[2], priority[1]   -- user-reordered the cascade

    mocks.__subcategories["AH Price"].defaultsOnClick()

    assertEqual(NS.Schema:Get("settings.auction.capture")["auctionator:minbuyout"], true,
      "the capture set is a schema row and comes back with the rest")
    -- The cascade is a ratified carve-out array with no schema row, so the schema walk cannot see
    -- it and the page's own Defaults handler has to reset it separately — in place, keeping the
    -- same table reference, because the price table's closures hold it.
    local after = NS.AuctionPrice:GetPriority()
    for i, tag in ipairs(NS.Constants.AUCTION_PRIORITY_DEFAULT) do
      assertEqual(after[i], tag, "cascade entry " .. i .. " was not restored")
    end
    assertEqual(#after, #NS.Constants.AUCTION_PRIORITY_DEFAULT)
  end)

-- ── the Filters page ─────────────────────────────────────────────────────────────────────────

test("Panel: the Filters page draws a tab per id-list and renders only the selected one",
  function()
    -- options-ui-§13 on a page with no schema rows: a dynamic list of item ids has nothing
    -- RenderTabbedSchema could partition, so the strip is drawn straight from O.TabStrip and each
    -- tab renders its own section. Three stacked lists were three AceGUI teardown-and-rebuilds on
    -- every paint (anti-pattern #39 is why that matters on this page of all pages) and a reader
    -- scrolling past two lists to reach the third.
    NS.Filters:ClearAll()
    local panel = mocks.__subcategories["Filters"]
    local ctx = NS.Panel.filters
    show(panel)
    assertTrue(ctx.__tabLayout ~= nil, "the Filters page must draw a tab strip")
    assertEqual(#ctx.__tabLayout.buttons, 3, "one tab per list")
    assertEqual(ctx.activeTab, "blacklist", "the strip opens on the first tab")

    -- One add-box, not three: the page draws the selected list and nothing else.
    local created = clickTab(panel, ctx, 3)
    assertEqual(ctx.activeTab, "currencyBlacklist", "tab 3 is Currencies")
    local boxes = widgetsOfType(created, "EditBox")
    assertEqual(#boxes, 1, "exactly one add-row is on screen")
    assertEqual(boxes[1].labelText, "Add currency id or link",
      "and it is the selected list's, not the first list's")
    homeTab(ctx)
    assertEqual(ctx.activeTab, "blacklist")
  end)

test("Panel: the Filters page lists the ids on each list and can remove one", function()
  NS.Filters:ClearAll()
  NS.Filters:AddBlacklist(12345)
  local created = show(mocks.__subcategories["Filters"])
  if #created == 0 then
    -- Already rendered by an earlier case; drive the structural rebuild the page registers.
    NS.Panel.filters._dirty = true
    created = show(mocks.__subcategories["Filters"])
  end
  local labeled
  for _, w in ipairs(AceGUI.__created) do
    if w.type == "Label" and type(w.text) == "string" and w.text:find("12345", 1, true) then
      labeled = w
    end
  end
  assertTrue(labeled ~= nil, "a blacklisted id must appear as a row on the Filters page")

  local remove
  for _, w in ipairs(AceGUI.__created) do
    if w.type == "Button" and w.text == "Remove" then remove = w end
  end
  assertTrue(remove ~= nil, "each list row carries a Remove button")
  NS.Filters:ClearAll()
end)

test("Panel: a blacklist change while the Filters page is hidden repaints it on the next OnShow",
  function()
    -- LH-A-27. The page flags itself dirty off-screen instead of rebuilding, and the flag it writes
    -- must be the one LibKa0s-Options' OnShow reads (`ctx._dirty`). A page-local `ctx.dirty` is
    -- written and never read, so the library's `_rendered and not _dirty` early-out swallows the
    -- next OnShow and the new id only appears after a /reload.
    NS.Filters:ClearAll()
    local panel = mocks.__subcategories["Filters"]
    show(panel)                       -- first render, so the early-out is live from here on
    panel:Hide()

    NS.Filters:AddBlacklist(778899)   -- fires HistoryChanged; the page is off screen
    assertTrue(NS.Panel.filters._dirty == true,
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
  end)

test("Panel: the Filters page's Defaults click clears every id list", function()
  NS.Filters:AddBlacklist(1)
  NS.Filters:AddWhitelist(2)
  NS.Filters:AddCurrencyBlacklist(3)
  show(mocks.__subcategories["Filters"])
  -- No StaticPopup_Show in the harness beyond a recorder, so the handler takes its direct branch.
  local realShow = mocks.StaticPopup_Show
  mocks.StaticPopup_Show = nil
  mocks.__subcategories["Filters"].defaultsOnClick()
  mocks.StaticPopup_Show = realShow
  assertEqual(NS.Filters:Count(NS.Filters:Blacklist()), 0)
  assertEqual(NS.Filters:Count(NS.Filters:Whitelist()), 0)
  assertEqual(NS.Filters:Count(NS.Filters:CurrencyBlacklist()), 0)
end)

-- ── the AH Price page ────────────────────────────────────────────────────────────────────────

test("Panel: the AH Price page draws one reusable row slot per known price source", function()
  show(mocks.__subcategories["AH Price"])
  local ctx = NS.Panel.auction
  assertTrue(ctx._priRows ~= nil, "the row slots must be created")
  assertEqual(#ctx._priRows, #NS.Constants.AUCTION_KEYS,
    "one slot per key, created ONCE and repainted in place — this page froze the client at ~213 " ..
    "frames before the slots were pooled (docs/settings-panel.md)")
end)

test("Panel: the AH Price page renders only its own schema group", function()
  local created = show(mocks.__subcategories["AH Price"])
  assertTrue(findByLabel(created, "Enable AH pricing") ~= nil,
    "the master enable checkbox is the one schema row this page draws")
  -- The other half, and the one that fails if the page filter stops filtering: no row belonging to
  -- another group may appear here. Without this the page could draw the entire schema and pass.
  for _, label in ipairs({ "Enable collection", "Minimum quality", "Window scale",
                           "Record currency", "Hide minimap button" }) do
    assertTrue(findByLabel(created, label) == nil,
      label .. " belongs to another page and must not be drawn on AH Price")
  end
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
