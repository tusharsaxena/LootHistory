-- tests/test_panel_filters.lua — the settings panel's **Filters tab**: its secondary strip, the
-- load checks, the id lists (LibKa0s-Options IdList) and the suggestion / name-lookup path.
--
-- Peeled out of tests/test_panel.lua, which had reached 1655 lines against layout-§1's 1500-line
-- cap. The seam is the one that addon's own automated-test bundle had already named: the Filters
-- tab's four contiguous sections are the largest block in the file that answers one question, and
-- nothing outside them reads their state. Not one assertion changed in the move.
--
-- The render helpers are shared rather than copied — see tests/panel_support.lua for why a second
-- copy of the `rendered` cache would make every case here pass on an empty widget list.

local T = _G.LH_TEST
local NS, mocks, Loader = T.NS, T.mocks, T.Loader
local test, assertEqual, assertTrue =
  T.test, T.assertEqual, T.assertTrue

local S = dofile("tests/panel_support.lua")
local AceGUI        = S.AceGUI
local clickTab      = S.clickTab
local homeTab       = S.homeTab
local widgetsOfType = S.widgetsOfType
local tabAt         = S.tabAt

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
    clickTab(panel, ctx, tabAt("Filters"))
    assertEqual(ctx.activeTab, "Filters", "the last tab is Filters")
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
    assertEqual(boxes[1].labelText, "Add currency id, link or name",
      "and it is the selected list's, not the first list's")

    ctx.__subTabKids[1]:__fire("OnClick")
    assertEqual(ctx.activeSubTab["Filters"], "blacklist")
    homeTab(ctx)
  end)

-- ── the Filters tab's load checks ─────────────────────────────────────────────────────────────
--
-- An IdList asks LibKa0s-Item-1.0 to load an item it cannot name yet, batched per page (LibKa0s
-- v1.35.0): the first unnamed id of a batch hands LoadItem the batch's one check, and later ids
-- only join the batch until that check runs. The harness's LoadItem is inert (no
-- C_Item.RequestLoadItemDataByID), so a check it swallows never runs and the batch outlives its
-- case on the shared NS.Panel.general: every later case's ask joins it and hands LoadItem no check
-- at all. So every case that draws the Filters tab captures its checks here and drains them.
local pendingLoads = {}

--- Run every captured load check until none is left. A check re-asks for an id still unnamed, as a
--- fresh batch with a check of its own, and the widget stops after five asks per id, so this ends;
--- the bound only turns a widget that never stops asking into a failure instead of a hang.
local function drainLoads()
  for _ = 1, 100 do
    local check = table.remove(pendingLoads, 1)
    if not check then return end
    check()
  end
  error("the IdList never stopped asking the client to load an item", 2)
end

--- Run `fn` with LoadItem capturing every load check the page hands it, then drain the checks and
--- put LoadItem back, whether `fn` passed or not. `fn`'s error wins over the drain's.
local function capturingLoads(fn)
  local Item = mocks.LibStub("LibKa0s-Item-1.0")
  local savedLoad = Item.LoadItem
  Item.LoadItem = function(_, check)
    if check then pendingLoads[#pendingLoads + 1] = check end
  end
  local ok, err = pcall(fn)
  local drained, drainErr = pcall(drainLoads)
  pendingLoads = {}
  Item.LoadItem = savedLoad
  if not ok then error(err, 0) end
  if not drained then error(drainErr, 0) end
end

--- `fn` as a test body run under capturingLoads.
local function withLoadsCaptured(fn)
  return function() capturingLoads(fn) end
end

test("Panel: the Filters tab lists the ids on each list and can remove one", withLoadsCaptured(function()
  NS.Filters:ClearAll()
  NS.Filters:AddBlacklist(12345)
  local ctx = NS.Panel.general
  clickTab(mocks.__subcategories["General"], ctx, tabAt("Filters"))
  local labeled
  for _, w in ipairs(AceGUI.__created) do
    -- An IdList entry is an InteractiveLabel (it carries the client's own tooltip on hover).
    if w.type == "InteractiveLabel" and type(w.text) == "string" and w.text:find("12345", 1, true) then
      labeled = w
    end
  end
  assertTrue(labeled ~= nil, "a blacklisted id must appear as a row on the Filters tab")

  -- removeStyle = "icon" (LibKa0s v1.44.0): an X at the LEFT of the line, not a right-hand Remove
  -- button. red under: removeStyle omitted from the O.IdList spec.
  local x
  for _, w in ipairs(AceGUI.__created) do
    if w.type == "Icon" and w.__removeAtlas == "transmog-icon-remove" then x = w end
  end
  assertTrue(x ~= nil, "each list row carries an X icon wearing the library's remove atlas")
  local removeBtn
  for _, w in ipairs(AceGUI.__created) do
    if w.type == "Button" and w.text == "Remove" then removeBtn = w end
  end
  assertTrue(removeBtn == nil, "no right-hand Remove button is drawn")
  NS.Filters:ClearAll()
  homeTab(ctx)
end))

test("Panel: a blacklist change while the page is hidden repaints it on the next OnShow",
  withLoadsCaptured(function()
    -- LH-A-27. The page flags itself dirty off-screen instead of rebuilding, and the flag it writes
    -- must be the one LibKa0s-Options' OnShow reads (`ctx._dirty`). A page-local `ctx.dirty` is
    -- written and never read, so the library's `_rendered and not _dirty` early-out swallows the
    -- next OnShow and the new id only appears after a /reload.
    NS.Filters:ClearAll()
    local panel = mocks.__subcategories["General"]
    local ctx = NS.Panel.general
    clickTab(panel, ctx, tabAt("Filters"))   -- park on Filters, where the list is on screen
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
      if w.type == "InteractiveLabel" and type(w.text) == "string" and w.text:find("778899", 1, true) then
        labeled = w
      end
    end
    assertTrue(labeled ~= nil,
      "the next OnShow must repaint the list and show the id added while hidden")
    NS.Filters:ClearAll()
    homeTab(ctx)
  end))

--- Every IdList entry among `ws`, in draw order, with the LINE and the COLUMN it landed in.
---
--- A list's entries are packed into shared Flow rows (SimpleGroups the library creates one per
--- line), so the row's position in creation order IS its line: a row is created before the widgets
--- that go into it, and the library fills a row left to right before starting the next. An entry is
--- an InteractiveLabel whose text carries the id -- either `|cff808080(12345)|r` after the name, or
--- the library's "Unknown item 12345" while the client cannot name it yet (entryLabel,
--- libs/LibKa0s/OptionsWidgets.lua:2643-2654). Nothing else this page draws matches either shape.
local function packedEntries(ws)
  local out = {}
  for line, w in ipairs(ws) do
    local kids = type(w.children) == "table" and w.children or {}
    local col = 0
    for _, kid in ipairs(kids) do
      if type(kid) == "table" and kid.type == "InteractiveLabel" and type(kid.text) == "string" then
        local id = kid.text:match("%((%d+)%)|r") or kid.text:match("^Unknown %a+ (%d+)")
        if id then
          col = col + 1
          out[#out + 1] = { id = tonumber(id), line = line, col = col }
        end
      end
    end
  end
  return out
end

--- Click the Filters sub-tab at `index` and answer the widgets that render drew.
local function clickSubTab(ctx, index)
  local before = #AceGUI.__created
  ctx.__subTabKids[index]:__fire("OnClick")
  local out = {}
  for i = before + 1, #AceGUI.__created do out[#out + 1] = AceGUI.__created[i] end
  return out
end

-- LibKa0s v1.47.0 / OptionsWidgets minor 24; the canvas fit that makes it a MAXIMUM is v1.50.0,
-- minor 27. BOTH halves are one case on purpose. The first is the
-- adoption and is red without it -- with no `columns` on the item lists every entry takes a line of
-- its own. The second is the DECISION the adoption made (per list, not wholesale) and would pass on
-- its own against a page that never heard of `columns`; it is here so a later sweep that puts
-- `columns = 2` on the shared spec has to argue with a named assertion rather than a silent
-- truncation of every currency id (see the O.IdList call in settings/Panel.lua).
test("Panel: the item lists pack two entries to a line and Currencies keeps one",
  withLoadsCaptured(function()
    NS.Filters:ClearAll()
    NS.Filters:AddBlacklist(11111)
    NS.Filters:AddBlacklist(22222)
    NS.Filters:AddBlacklist(33333)
    NS.Filters:AddCurrencyBlacklist(3008)
    NS.Filters:AddCurrencyBlacklist(2914)
    local panel = mocks.__subcategories["General"]
    local ctx = NS.Panel.general
    -- SAY WHAT CANVAS THIS PACKS INTO. `columns` is a maximum fitted to the measured content width,
    -- and the kit's ScrollFrame fixture is 400 (380 of content) -- under the icon style's 520px
    -- floor, so the library would correctly draw ONE column and this case would be asserting the
    -- fixture rather than the packing. 700 pays for two in either style; see S.withCanvas.
    S.withCanvas(700, function()
      local drawn = packedEntries(clickTab(panel, ctx, tabAt("Filters")))
      assertEqual(#drawn, 3, "the three blacklisted ids are drawn")
      -- filterEntries sorts by id and the library packs ROW-MAJOR (1 2 / 3 4), so the sort still
      -- reads left to right and then down. red under: no `columns` (one entry a line), and red
      -- under a column-major packing, which the flat order alone would not notice.
      assertEqual(drawn[1].id, 11111, "the lowest id is first")
      assertEqual(drawn[2].id, 22222)
      assertEqual(drawn[3].id, 33333)
      assertEqual(drawn[1].line, drawn[2].line, "the first two share one line")
      assertEqual(drawn[1].col, 1, "the first is the left column")
      assertEqual(drawn[2].col, 2, "the second is beside it, not under it")
      assertTrue(drawn[3].line > drawn[2].line, "the third starts the next line down")
      assertEqual(drawn[3].col, 1, "and is the left column of that line")

      local currency = packedEntries(clickSubTab(ctx, 3))
      assertEqual(#currency, 2, "both muted currencies are drawn")
      assertTrue(currency[2].line > currency[1].line, "each currency keeps a line to itself")
      assertEqual(currency[1].col, 1)
      assertEqual(currency[2].col, 1)
    end)
    clickSubTab(ctx, 1)
    NS.Filters:ClearAll()
    homeTab(ctx)
  end))

-- ── the Filters tab's id lists (LibKa0s-Options IdList) ───────────────────────────────────────
--
-- Each list is one O.IdList: an edit box taking an id, a shift-clicked link or (items only) a name,
-- then one line per stored id with an X at its left (removeStyle = "icon", LibKa0s v1.44.0). The
-- host owns storage, so every add and remove goes through the NS.Filters writer it always went
-- through, and the stored sets keep their shape.

-- The kit's opt-in id lookups (revision 20), installed on a SCRATCH table rather than on the
-- shared mock. wow_mock's C_Item.GetItemInfoInstant answers 211296 for ANY key -- the capture
-- suites stand on that -- so a name lookup through it would resolve every string typed. The two
-- item lookups are swapped in around each case below and restored after it, so no other suite sees
-- a different C_Item. Currencies need no swap: wow_mock's GetCurrencyInfo already names 3008/2914.
local ids = dofile("tests/_kit/mock_ids.lua")({})

local ITEM_ADD_LABEL     = "Add item id, link or name"
local CURRENCY_ADD_LABEL = "Add currency id, link or name"

--- Run `fn(ctx)` on the Filters tab parked on sub-list `key`, with the kit's item lookups in and
--- the page's load checks captured (capturingLoads), and always put everything back: the pending
--- load checks, the lookups, LoadItem, the three lists and the page's tab.
local function onFilterList(key, fn)
  local item = mocks.C_Item
  local savedInstant, savedName = item.GetItemInfoInstant, item.GetItemNameByID
  item.GetItemInfoInstant = ids.C_Item.GetItemInfoInstant
  item.GetItemNameByID    = ids.C_Item.GetItemNameByID
  ids.clearIdRecords()
  NS.Filters:ClearAll()
  local ctx = NS.Panel.general
  ctx.activeSubTab = ctx.activeSubTab or {}
  ctx.activeSubTab["Filters"] = key
  local ok, err = pcall(capturingLoads, function()
    clickTab(mocks.__subcategories["General"], ctx, tabAt("Filters"))
    assertEqual(ctx.activeSubTab["Filters"], key, "the Filters tab opened on the wrong list")
    fn(ctx)
  end)
  item.GetItemInfoInstant, item.GetItemNameByID = savedInstant, savedName
  ids.clearIdRecords()
  NS.Filters:ClearAll()
  homeTab(ctx)
  if not ok then error(err, 0) end
end

--- The newest widget still on screen (never released) of `wtype` that `pred` accepts.
local function liveWidget(wtype, pred)
  for i = #AceGUI.__created, 1, -1 do
    local w = AceGUI.__created[i]
    if w.type == wtype and not w.__released and (not pred or pred(w)) then return w end
  end
end

local function liveText(wtype, needle)
  return liveWidget(wtype, function(w)
    return type(w.text) == "string" and w.text:find(needle, 1, true) ~= nil
  end)
end

--- Type `text` into the list's add box and press Enter, as a player does.
local function typeAndEnter(label, text)
  local eb = liveWidget("EditBox", function(w) return w.labelText == label end)
  assertTrue(eb ~= nil, "no add box labeled '" .. label .. "' is on screen")
  eb:SetText(text)
  eb:__fire("OnEnterPressed", text)
  return eb
end

--- Every key of a stored set is a number and every value is `true` -- the shape the Collector's
--- capture gate reads and every existing SavedVariables file already holds.
local function assertSetShape(set, want, what)
  local n = 0
  for k, v in pairs(set) do
    n = n + 1
    assertEqual(type(k), "number", what .. ": a stored key must stay a number")
    assertEqual(v, true, what .. ": a stored value must stay true")
  end
  local wantN = 0
  for id in pairs(want) do
    wantN = wantN + 1
    assertTrue(set[id] == true, what .. ": id " .. id .. " is not on the list")
  end
  assertEqual(n, wantN, what .. ": the list holds ids nobody added")
end

test("Panel: Filters: an item list adds by id, through AddBlacklist, and keeps the [id] = true shape",
  function()
    -- red under: an onAdd that does not reach NS.Filters:AddBlacklist, or one that stores the text
    -- typed (a string key) rather than the resolved id.
    onFilterList("blacklist", function()
      local calls, real = {}, NS.Filters.AddBlacklist
      NS.Filters.AddBlacklist = function(self, id) calls[#calls + 1] = id; return real(self, id) end
      local ok, err = pcall(typeAndEnter, ITEM_ADD_LABEL, "12345")
      NS.Filters.AddBlacklist = real
      if not ok then error(err, 0) end
      assertEqual(#calls, 1, "one add calls the Filters writer once")
      assertEqual(calls[1], 12345)
      assertSetShape(NS.db.global.blacklist, { [12345] = true }, "blacklist")
      assertTrue(liveText("InteractiveLabel", "12345") ~= nil, "the new id is drawn as an entry")
    end)
  end)

test("Panel: Filters: an item list adds by a shift-clicked link, and the add still moves it off the other list",
  function()
    -- The exclusivity is Filters:_move's, unchanged; the widget only hands it the id.
    -- red under: an onAdd that writes db.global.whitelist itself instead of calling AddWhitelist.
    onFilterList("whitelist", function()
      NS.Filters:AddBlacklist(67890)
      typeAndEnter(ITEM_ADD_LABEL, "|cff0070dd|Hitem:67890::::::::80:::::|h[Some Blade]|h|r")
      assertSetShape(NS.db.global.whitelist, { [67890] = true }, "whitelist")
      assertSetShape(NS.db.global.blacklist, {}, "blacklist")
    end)
  end)

test("Panel: Filters: an item list adds by name, ignoring case, and names the entry", function()
  -- red under: an item list built with no kind (id-only), which refuses every name.
  onFilterList("blacklist", function()
    ids.addIdRecord("item", 6948, "Hearthstone", 134414)
    typeAndEnter(ITEM_ADD_LABEL, "hearthstone")
    assertSetShape(NS.db.global.blacklist, { [6948] = true }, "blacklist")
    local entry = liveText("InteractiveLabel", "Hearthstone")
    assertTrue(entry ~= nil, "the entry reads the item's name")
    assertTrue(entry.text:find("(6948)", 1, true) ~= nil, "and its id beside it: " .. entry.text)
    assertEqual(entry.image and entry.image[1], 134414, "and carries the item's icon")
  end)
end)

test("Panel: Filters: an unknown name adds nothing, keeps the text and says why", function()
  -- red under: a submit that adds before it resolves, or clears the box on a miss.
  onFilterList("blacklist", function()
    local eb = typeAndEnter(ITEM_ADD_LABEL, "No Such Thing")
    assertSetShape(NS.db.global.blacklist, {}, "blacklist")
    local status = liveText("Label", "No item named 'No Such Thing' that the game can find.")
    assertTrue(status ~= nil, "the status line names the reason")
    assertEqual(status.color and status.color.g, 0.5, "in the widget's warning orange")
    assertEqual(eb.text, "No Such Thing", "the text stays so the player can correct it")
  end)
end)

test("Panel: Filters: the Currencies list takes an id or a currency link, and refuses a name it cannot know",
  function()
  -- The client has no currency name search: a name resolves only against the ids the list and the
  -- loot history already hold (the suggestion cases below), so a name neither holds is refused.
  -- red under: the currency list built with kind "item" (an item link would be taken as a
  -- currency id, and the refusal would read "No item named ...").
  onFilterList("currencyBlacklist", function()
    typeAndEnter(CURRENCY_ADD_LABEL, "3008")
    typeAndEnter(CURRENCY_ADD_LABEL, "|cffffffff|Hcurrency:2914::|h[Weathered Harbinger Crest]|h|r")
    assertSetShape(NS.db.global.currencyBlacklist, { [3008] = true, [2914] = true },
      "currencyBlacklist")
    assertTrue(liveText("InteractiveLabel", "Valorstones") ~= nil, "a currency entry reads its name")

    typeAndEnter(CURRENCY_ADD_LABEL, "Honor Points")
    assertTrue(liveText("Label", "No currency named 'Honor Points'") ~= nil,
      "a name nothing knows is refused with the reason")
    typeAndEnter(CURRENCY_ADD_LABEL, "|Hitem:12345::|h[Not a currency]|h")
    assertSetShape(NS.db.global.currencyBlacklist, { [3008] = true, [2914] = true },
      "currencyBlacklist")
    assertSetShape(NS.db.global.blacklist, {}, "an item list")
  end)
end)

test("Panel: Filters: each entry's X calls that list's own Filters writer, and an emptied list reads (none)",
  function()
    -- red under: any list's onRemove pointing at another list's writer, or removeStyle omitted
    -- (LibKa0s v1.44.0 draws the X at the LEFT of the line, not a right-hand Remove button).
    for _, case in ipairs({
      { key = "blacklist",         seed = "AddBlacklist",         verb = "RemoveBlacklist" },
      { key = "whitelist",         seed = "AddWhitelist",         verb = "RemoveWhitelist" },
      { key = "currencyBlacklist", seed = "AddCurrencyBlacklist", verb = "RemoveCurrencyBlacklist" },
    }) do
      onFilterList(case.key, function()
        -- The seed fires HistoryChanged, which repaints the page on screen with the seeded entry.
        NS.Filters[case.seed](NS.Filters, 3008)
        local calls, real = {}, NS.Filters[case.verb]
        NS.Filters[case.verb] = function(self, id) calls[#calls + 1] = id; return real(self, id) end
        local x = liveWidget("Icon", function(w) return w.__removeAtlas == "transmog-icon-remove" end)
        local noRemoveBtn = liveWidget("Button", function(w) return w.text == "Remove" end) == nil
        local ok, err = pcall(function()
          assertTrue(x ~= nil, case.key .. ": the entry carries an X icon")
          assertTrue(noRemoveBtn, case.key .. ": no right-hand Remove button is drawn")
          x:__fire("OnClick")
        end)
        NS.Filters[case.verb] = real
        if not ok then error(err, 0) end
        assertEqual(#calls, 1, case.key .. ": the X calls " .. case.verb .. " once")
        assertEqual(calls[1], 3008)
        assertSetShape(NS.db.global[case.key], {}, case.key)
        assertTrue(liveText("Label", "(none)") ~= nil, case.key .. ": an empty list reads (none)")
      end)
    end
  end)

test("Panel: Filters: one add redraws the page once, not twice", function()
  -- The writer fires HistoryChanged synchronously, and the page's own listener repaints on it; the
  -- widget then asks for its own redraw. Two full repaints per click is the anti-pattern #39 cost
  -- this page is gated against, and the first one releases the status line the widget clears after.
  -- red under: dropping the write guard that holds the HistoryChanged repaint off during an add.
  onFilterList("blacklist", function()
    local before = #AceGUI.__created
    typeAndEnter(ITEM_ADD_LABEL, "4321")
    local boxes = 0
    for i = before + 1, #AceGUI.__created do
      local w = AceGUI.__created[i]
      if w.type == "EditBox" and w.labelText == ITEM_ADD_LABEL then boxes = boxes + 1 end
    end
    assertEqual(boxes, 1, "exactly one repaint follows one add")
    assertSetShape(NS.db.global.blacklist, { [4321] = true }, "blacklist")
  end)
end)

test("Panel: Filters: an item the client has not cached is named once its load lands", function()
  -- The widget asks LibKa0s-Item-1.0 to load an unnamed item under one check per batch (LibKa0s
  -- v1.35.0), and the check redraws through ctx.rebuild once the name has landed; this page's
  -- rebuild runs its registered rebuilders. onFilterList captures the check.
  -- red under: the Filters list not registering its rebuilder in ctx.rebuilders (the load lands and
  -- nothing repaints).
  onFilterList("blacklist", function()
    ids.addIdRecord("item", 55551, "Late Arrival", 7, true)   -- uncached: no name yet
    typeAndEnter(ITEM_ADD_LABEL, "55551")
    assertTrue(liveText("InteractiveLabel", "Unknown item 55551") ~= nil,
      "an uncached item reads as unknown until it loads")
    assertEqual(#pendingLoads, 1, "the list asked the client to load the item, under one check")
    ids.addIdRecord("item", 55551, "Late Arrival", 7)          -- the client now has it
    table.remove(pendingLoads, 1)()
    assertTrue(liveText("InteractiveLabel", "Late Arrival") ~= nil,
      "the load repaints the list with the item's name")
  end)
end)

-- ── the Filters tab's suggestions and name lookup (LibKa0s v1.35.0, issue #31) ───────────────
--
-- The client has no item-name search: C_Item.GetItemInfoInstant(name) answers only for an item the
-- player carries or carried this session. So a name resolves, and the dropdown lists it, only
-- through ids something already knows -- here every id on the lists and every id the loot history
-- holds, passed as the IdList's `candidates`. The owner typed "Potion of the Hushed Zephyr" (three
-- crafted-quality ranks, none in the bags) into an add box and was told nothing matched.
--
-- The dropdown is the library's frame, not an AceGUI widget, so these cases find it among the
-- frames CreateFrame hands out (the one carrying `rows`), as LibKa0s's own suite does. It is built
-- once per Options instance, the first time it shows, so the first case to show it records it.

local ZEPHYR = "Potion of the Hushed Zephyr"
local madeFrames, suggestFrame = {}, nil

--- The library's suggestion dropdown, once some case has shown it.
local function dropdown()
  if suggestFrame then return suggestFrame end
  for _, f in ipairs(madeFrames) do
    if type(f.rows) == "table" then suggestFrame = f; return f end
  end
end

--- The ids the dropdown's visible rows carry, in order; "" while it is hidden.
local function shownIds()
  local dd = dropdown()
  if not (dd and dd:IsShown()) then return "" end
  local out = {}
  for _, row in ipairs(dd.rows) do
    if row:IsShown() and row.entry then out[#out + 1] = row.entry.id end
  end
  return table.concat(out, ",")
end

--- Type into the add box labeled `label` as AceGUI's EditBox reports it, then let the debounce run.
local function typeText(label, text)
  local eb = liveWidget("EditBox", function(w) return w.labelText == label end)
  assertTrue(eb ~= nil, "no add box labeled '" .. label .. "' is on screen")
  eb:SetText(text)
  eb:__fire("OnTextChanged", text)
  mocks.__fireTimers()
  return eb
end

--- The three Zephyr ranks as loot-history rows, named, with their crafted-quality tiers.
local ZEPHYR_HISTORY = { { itemID = 191395 }, { itemID = 191396 }, { currencyID = 3008 },
  { itemID = 191397 } }
local ZEPHYR_RECORDS = { { 191395, ZEPHYR }, { 191396, ZEPHYR }, { 191397, ZEPHYR } }
local ZEPHYR_TIERS = { [191395] = 1, [191396] = 2, [191397] = 3 }

--- The player's bags as C_Container answers them: bag 0 holds the ids in `bags` (a set), one a slot.
local function containerOf(bags)
  local slots = {}
  for id in pairs(bags) do slots[#slots + 1] = id end
  table.sort(slots)
  return {
    GetContainerNumSlots = function(bag) return bag == 0 and #slots or 0 end,
    GetContainerItemID   = function(bag, slot) return bag == 0 and slots[slot] or nil end,
  }
end

--- onFilterList with `opts.history` as the loot history, `opts.records` ({ id, name }) as the items
--- the client can name, `opts.bags` as the items the player carries -- the client's NAME lookup
--- answers only for those ids (it looks in the bags and nowhere else), and C_Container lists them --
--- and each id's crafted-quality tier from `opts.tiers`. The history, CreateFrame, C_Container and
--- the tier lookup go back however the case ends; onFilterList puts the item lookups back.
local function onSuggestList(key, opts, fn)
  local db = NS.db.global
  local savedHistory, realCreate, savedTiers = db.history, mocks.CreateFrame, mocks.C_TradeSkillUI
  local savedContainer = mocks.C_Container
  db.history = opts.history or {}
  mocks.CreateFrame = function(...)
    local f = realCreate(...)
    madeFrames[#madeFrames + 1] = f
    return f
  end
  local tiers = opts.tiers or {}
  mocks.C_TradeSkillUI = { GetItemCraftedQualityByItemInfo = function(id) return tiers[id] end }
  mocks.C_Container = containerOf(opts.bags or {})
  local ok, err = pcall(onFilterList, key, function(ctx)
    local bags, byAny = opts.bags or {}, ids.C_Item.GetItemInfoInstant
    mocks.C_Item.GetItemInfoInstant = function(q)
      if type(q) == "string" and not tonumber(q) and not q:find("item:", 1, true) then
        local id = byAny(q)
        if not (id and bags[id]) then return nil end
      end
      return byAny(q)
    end
    for _, r in ipairs(opts.records or {}) do ids.addIdRecord("item", r[1], r[2], 1) end
    fn(ctx)
  end)
  db.history, mocks.CreateFrame, mocks.C_TradeSkillUI = savedHistory, realCreate, savedTiers
  mocks.C_Container = savedContainer
  madeFrames = {}
  if not ok then error(err, 0) end
end

test("Panel: Filters: typing lists matching items from the loot history and from the lists", function()
  -- red under: an IdList with no candidates (nothing the player does not carry is ever listed).
  onSuggestList("blacklist", {
    history = ZEPHYR_HISTORY,
    records = { ZEPHYR_RECORDS[1], ZEPHYR_RECORDS[2], ZEPHYR_RECORDS[3], { 6948, "Hearthstone" } },
  }, function()
    NS.Filters:AddWhitelist(6948)   -- on the OTHER item list; repaints the page on screen
    typeText(ITEM_ADD_LABEL, "hushed")
    assertEqual(shownIds(), "191395,191396,191397", "every rank the loot history holds")
    typeText(ITEM_ADD_LABEL, "hearth")
    assertEqual(shownIds(), "6948", "and an id the other item list holds")
  end)
end)

test("Panel: Filters: a name the game cannot look up resolves through the loot history", function()
  -- The Zephyr case in one rank: the item is in the history but not in the bags, so the client's
  -- name lookup finds nothing and only the history's id can resolve it.
  -- red under: no candidates (refused as "No item named ... that the game can find.").
  onSuggestList("blacklist", {
    history = { { itemID = 55001 } },
    records = { { 55001, "Starlit Draught" } },
  }, function()
    typeAndEnter(ITEM_ADD_LABEL, "starlit draught")
    assertSetShape(NS.db.global.blacklist, { [55001] = true }, "blacklist")
  end)
end)

test("Panel: Filters: picking a suggestion adds that rank through the Filters writer, once", function()
  -- red under: no candidates (no row to pick), or an onAdd that writes the set itself.
  onSuggestList("blacklist", { history = ZEPHYR_HISTORY, records = ZEPHYR_RECORDS, tiers = ZEPHYR_TIERS },
    function()
      typeText(ITEM_ADD_LABEL, "zephyr")
      assertEqual(shownIds(), "191395,191396,191397", "the ranks are listed to pick from")
      local calls, real = {}, NS.Filters.AddBlacklist
      NS.Filters.AddBlacklist = function(self, id) calls[#calls + 1] = id; return real(self, id) end
      local ok, err = pcall(function() dropdown().rows[2]:__fire("OnClick") end)
      NS.Filters.AddBlacklist = real
      if not ok then error(err, 0) end
      assertEqual(#calls, 1, "one pick calls the Filters writer once")
      assertEqual(calls[1], 191396, "with the rank picked")
      assertSetShape(NS.db.global.blacklist, { [191396] = true }, "blacklist")
      assertEqual(shownIds(), "", "the pick closes the list")
    end)
end)

test("Panel: Filters: a name several ranks share lists every rank, and Enter without a pick adds none",
  function()
    -- One rank in the bags: the client's own lookup answers that rank alone, and adding it would add
    -- a rank the player did not pick. The owner's ruling: refuse it, and list every rank to pick from.
    -- red under: no candidates (the client's hit on the rank in the bags is added silently).
    onSuggestList("blacklist", { history = ZEPHYR_HISTORY, records = ZEPHYR_RECORDS,
                                 tiers = ZEPHYR_TIERS, bags = { [191395] = true } }, function()
      typeText(ITEM_ADD_LABEL, ZEPHYR)
      assertEqual(shownIds(), "191395,191396,191397", "every rank is its own row")
      for i, row in ipairs(dropdown().rows) do
        if i > 3 then break end
        assertTrue(type(row.labelText) == "string" and row.labelText:find("Tier" .. i, 1, true) ~= nil,
          "row " .. i .. " is labeled with its rank: " .. tostring(row.labelText))
      end
      typeAndEnter(ITEM_ADD_LABEL, ZEPHYR)
      assertSetShape(NS.db.global.blacklist, {}, "neither one rank nor all of them")
      assertTrue(liveText("Label", "Several items are named '" .. ZEPHYR ..
        "' \226\128\148 pick one from the list, or use the id.") ~= nil, "the refusal says why")
      assertEqual(shownIds(), "191395,191396,191397", "the ranks the refusal points at stay listed")
    end)
  end)

test("Panel: Filters: a name two ranks in the bags share, with none in the history, adds none on Enter",
  function()
    -- The owner's own case: potions crafted or bought are carried but were never looted, so the
    -- loot history (and so the candidates) never holds them. The client's name lookup answers one
    -- of the two ranks; adding it would add a rank the player did not pick.
    -- red under: LibKa0s 48b486d, whose shared-name check reads the candidates and not the bags.
    onSuggestList("blacklist", { records = { ZEPHYR_RECORDS[1], ZEPHYR_RECORDS[2] },
                                 tiers = ZEPHYR_TIERS, bags = { [191395] = true, [191396] = true } },
      function()
        typeAndEnter(ITEM_ADD_LABEL, ZEPHYR)
        assertSetShape(NS.db.global.blacklist, {}, "neither one rank nor both")
        assertTrue(liveText("Label", "Several items are named '" .. ZEPHYR ..
          "' \226\128\148 pick one from the list, or use the id.") ~= nil, "the refusal says why")
      end)
  end)

test("Panel: Filters: currency names resolve through the loot history, and a refusal says where names work",
  function()
    -- red under: the Currencies list with no candidates, or the old "Currencies are added by id or
    -- link." (which told the player names never work).
    onSuggestList("currencyBlacklist", { history = { { currencyID = 2914 }, { itemID = 6948 } } }, function()
      typeText(CURRENCY_ADD_LABEL, "weathered")
      assertEqual(shownIds(), "2914", "a currency the loot history holds is listed")
      typeAndEnter(CURRENCY_ADD_LABEL, "weathered harbinger crest")
      assertSetShape(NS.db.global.currencyBlacklist, { [2914] = true }, "currencyBlacklist")
      typeAndEnter(CURRENCY_ADD_LABEL, "Honor Points")
      -- "this page", not the library's "this list": the page looks in the loot history too.
      assertTrue(liveText("Label", "No currency named 'Honor Points' that this page knows. " ..
        "Currency names work for currencies in your loot history") ~= nil,
        "a currency refusal says where a name can come from")
    end)
    onSuggestList("blacklist", {}, function()
      typeAndEnter(ITEM_ADD_LABEL, "No Such Thing")
      assertTrue(liveText("Label", "items in your loot history") ~= nil,
        "an item refusal names the loot history too")
    end)
    assertTrue(Loader.readFile("settings/Panel.lua"):find("Currencies are added by id or link.", 1, true) == nil,
      "the old wording is gone")
  end)

--- The candidates the IdList on list `key` was handed, read after `fn` set the page up.
local function candidatesOn(key, opts, fn)
  local O, real, spec = NS.Options, NS.Options.IdList, nil
  O.IdList = function(ctx, s) spec = s; return real(ctx, s) end
  local ok, err = pcall(onSuggestList, key, opts, function(ctx)
    fn(ctx)
    assertTrue(spec ~= nil and type(spec.candidates) == "function", key .. ": the IdList has candidates")
    opts.got = table.concat(spec.candidates(), ",")
  end)
  O.IdList = real
  if not ok then error(err, 0) end
  return opts.got
end

test("Panel: Filters: the candidates are the lists, then the loot history newest first, each id once",
  function()
    -- Newest first because the widget pre-warms at most 200 uncached candidates a build and indexes
    -- at most 2000: on a long history, oldest first drops recent loot from the suggestions.
    -- red under: the history walked oldest first, or an id on a list counted again from the history.
    local history = { { itemID = 101 }, { itemID = 9 }, { currencyID = 3008 }, { itemID = 102 },
                      { itemID = 103 }, { currencyID = 2914 } }
    local got = candidatesOn("blacklist", { history = history }, function()
      NS.Filters:AddBlacklist(9); NS.Filters:AddWhitelist(8)
    end)
    assertEqual(got, "9,8,103,102,101", "Blacklist, Whitelist, then the history's items newest first")
    got = candidatesOn("currencyBlacklist", { history = history }, function()
      NS.Filters:AddCurrencyBlacklist(3008)
    end)
    assertEqual(got, "3008,2914", "the currency list, then the history's currencies newest first")
  end)

--- The add box's tooltip lines, as hovering it shows them.
local function hoverLines(label)
  local eb = liveWidget("EditBox", function(w) return w.labelText == label end)
  assertTrue(eb ~= nil, "no add box labeled '" .. label .. "' is on screen")
  local tip, lines = mocks.GameTooltip, {}
  local savedAdd = rawget(tip, "AddLine")
  tip.AddLine = function(_, text) lines[#lines + 1] = text end
  local ok, err = pcall(eb.__fire, eb, "OnEnter")
  tip.AddLine = savedAdd
  if not ok then error(err, 0) end
  return table.concat(lines, "\n")
end

--- The hint a refusal of `text` ends with: what follows `lead` in the status line.
local function refusalHint(label, text, lead)
  typeAndEnter(label, text)
  local status = liveText("Label", lead)
  assertTrue(status ~= nil, "no refusal reading '" .. lead .. "'")
  return status.text:sub(select(2, status.text:find(lead, 1, true)) + 1)
end

test("Panel: Filters: each add box's tooltip ends with the hint its refusal ends with", function()
  -- The page passes one hint as both the refusal's {hint} and the tooltip's last sentence, so the
  -- two cannot disagree. red under: the hint dropped from either tooltip.
  onSuggestList("blacklist", {}, function()
    local hint = refusalHint(ITEM_ADD_LABEL, "No Such Thing", "that the game can find. ")
    assertTrue(#hint > 0, "the item refusal carries a hint")
    local tip = hoverLines(ITEM_ADD_LABEL)
    assertEqual(tip:sub(-#hint), hint, "the item box's tooltip ends with the refusal's hint")
  end)
  onSuggestList("currencyBlacklist", {}, function()
    local hint = refusalHint(CURRENCY_ADD_LABEL, "Honor Points", "that this page knows. ")
    assertTrue(#hint > 0, "the currency refusal carries a hint")
    local tip = hoverLines(CURRENCY_ADD_LABEL)
    assertEqual(tip:sub(-#hint), hint, "the currency box's tooltip ends with the refusal's hint")
  end)
end)
