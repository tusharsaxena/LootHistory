-- tests/test_skin_table.lua — the History table on the skin (LH-03; core/SkinSetup.lua's NS.Skin
-- over LibKa0s-Skin-1.0, skinning-§3).
--
-- What this pins: every surface of the History table draws from the skin's tokens, Ka0s Default
-- draws the values these surfaces drew before the skin engine (call for call where a primitive
-- paints), and a skin switch repaints them live with no reload: the header band, labels, the Bound
-- lock and the sort arrows (markup rebuilt on the switch), the pooled rows' stripe and hover on the
-- active AND the free list, the group-header row and its chevron and count, the cells' default text,
-- the padlock's bind state, the quality text, the row menu (S.MenuFrame, its hover, its enabled,
-- disabled and destructive entries), the scroll bar, and the header and row tooltips (gtip.*).
--
-- THE PAINT RECORDER. As tests/test_skin_chrome.lua: the shared mock's CreateTexture answers the
-- frame itself, so each case attaches a FRESH table to a pane built under the kit's opt-in recorder
-- (tests/_kit/mock_paint.lua), with the session's table fields and row menu swapped out and put
-- back, the recorder restored and the skin reset to Ka0s Default whatever the case raised.
--
-- After tests/test_skin_chrome.lua, whose reset this file repeats for the same reason.

local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local BT = NS.BrowserTable
local Skin = mocks.LibStub("LibKa0s-Skin-1.0")
local OptionsLib = mocks.LibStub("LibKa0s-Options-1.0")
local installPaint = dofile("tests/_kit/mock_paint.lua")
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

-- ── a fresh table under the recorder ────────────────────────────────────────────────────────────

-- Every BrowserTable field Attach and Refresh (re)write, put back after a fresh attach.
local BT_KEYS = { "frame", "pane", "headerFrame", "scroll", "rowHost", "rowPool", "emptyText",
                  "displayList", "matchCount", "sortKey", "sortAsc", "groupBy", "groupAsc" }

-- The rows a case binds: a group header (expanded, three rows) and a data row (an epic BoP item).
local RECORD = { ts = 1000, itemName = "Sword", quality = 4, bound = "BOP", itemType = "Weapon",
                 quantity = 1, char = "Ka0z-Realm", source = "KILL" }
local LIST = {
  { kind = "header", key = "Kill", label = "Kill", count = 3, collapsed = false },
  { kind = "row", record = RECORD },
  { kind = "header", key = "Mail", label = "Mail", count = 1, collapsed = true },
}

local function withFreshTable(fn)
  reset()
  local saved = {}
  for _, k in ipairs(BT_KEYS) do saved[k] = BT[k] end
  local restorePaint = installPaint(mocks)
  local oldMenu = BT:_SwapMenuForTest(nil)
  -- The client's FauxScrollFrameTemplate carries its bar at `ScrollBar` (a parentKey); the shared
  -- mock builds none, so this case hands the fresh scroll frame one.
  local createFrame = mocks.CreateFrame
  rawset(mocks, "CreateFrame", function(kind, name, parent, template, ...)
    local f = createFrame(kind, name, parent, template, ...)
    if template == "FauxScrollFrameTemplate" then rawset(f, "ScrollBar", createFrame("Slider", nil, f)) end
    return f
  end)
  local ok, err = pcall(function()
    BT.frame = nil
    BT.sortKey, BT.sortAsc, BT.groupBy = "date", false, "none"
    BT:Attach(mocks.CreateFrame("Frame", nil, mocks.UIParent))
    rawset(mocks, "CreateFrame", createFrame)
    BT.displayList = LIST
    BT:Bind()
    fn()
  end)
  rawset(mocks, "CreateFrame", createFrame)
  -- Hidden the way the client hides it: the mock's Hide fires no OnHide, and OnHide is what drops
  -- the menu's GLOBAL_MOUSE_DOWN registration (test_disabled counts every registration left).
  local menu = BT:MenuFrame()
  if menu then menu:Hide(); menu:__fire("OnHide") end
  BT:_SwapMenuForTest(oldMenu)
  restorePaint()
  for _, k in ipairs(BT_KEYS) do BT[k] = saved[k] end
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

local function recorded(frame, prim)
  local rec = Skin.painted[frame]
  return rec ~= nil and rec.owner == OWNER and rec.calls[prim] ~= nil
end

-- The bound rows, in display order: header, data, header.
local function rows()
  local out = {}
  for _, row in ipairs(BT.rowPool.active) do out[#out + 1] = row end
  return out
end

-- A "|cffrrggbb" escape of a recorded or token color, rounded to the byte.
local function escape(c)
  local function byte(v) return ("%02x"):format(math.floor(v * 255 + 0.5)) end
  return "|cff" .. byte(c[1]) .. byte(c[2]) .. byte(c[3])
end

-- Capture GameTooltip:AddLine for the length of `fn`.
local function tipLines(fn)
  local lines, stock = {}, rawget(mocks.GameTooltip, "AddLine")
  rawset(mocks.GameTooltip, "AddLine", function(_, text, r, g, b, wrap)
    lines[#lines + 1] = { text = text, c = rgba({ r, g, b }), wrap = wrap }
  end)
  local ok, err = pcall(fn)
  rawset(mocks.GameTooltip, "AddLine", stock)
  if not ok then error(err, 0) end
  return lines
end

-- Every table color, against `want(name)` (a token name -> "r,g,b,a"), and the quality and bound
-- colors against `quality` / `bound` (r, g, b, a tables).
local function assertTable(want, label)
  local hdr = BT.headerFrame
  for key, btn in pairs(hdr.buttons) do
    if btn.fs then assertEqual(textColor(btn.fs), want("list.header.text"), label .. ": header " .. key) end
    if btn.tex then
      assertEqual(rgba(rawget(btn.tex, "__vertex")), want("list.header.text"), label .. ": the Bound lock")
    end
  end
  local r, g, b = Skin:Color(OWNER, "list.header.text")
  local arrow = NS.IconMarkup("sort-down", "Interface\\Buttons\\Arrow-Down-Up", 0, r, g, b)
  local dateLabel = rawget(hdr.buttons.date.fs, "__text")
  assertTrue(dateLabel:find(arrow, 1, true) ~= nil, label .. ": the sort arrow is not in the header color: " .. dateLabel)
  local all = {}
  for _, row in ipairs(BT.rowPool.active) do all[#all + 1] = row end
  for _, row in ipairs(BT.rowPool.free) do all[#all + 1] = row end
  assertTrue(#all >= 3, label .. ": fewer than three pooled rows")
  for i, row in ipairs(all) do
    assertEqual(rgba(rawget(row.stripe, "__color")), want("list.stripe"), label .. ": row " .. i .. " stripe")
    assertEqual(rgba(rawget(row.hl, "__color")), want("list.hover"), label .. ": row " .. i .. " hover")
    assertEqual(textColor(row.header), want("list.header.text"), label .. ": row " .. i .. " group header")
  end
  local bound = rows()
  local head = rawget(bound[1].header, "__text")
  local chevron = NS.IconMarkup("chevron-down", "Interface\\Buttons\\UI-MinusButton-Up", 0, r, g, b)
  assertTrue(head:find(chevron, 1, true) == 1, label .. ": the chevron is not in the header color: " .. head)
  local count = escape({ Skin:Color(OWNER, "text.disabled") }) .. "(3)|r"
  assertTrue(head:find(count, 1, true) ~= nil, label .. ": the count is not in text.disabled: " .. head)
  local data = bound[2]
  assertEqual(textColor(data.cells.type), want("text.body"), label .. ": a default cell")
  local br, bg, bb, ba = Skin:Color(OWNER, "sem.boundBoP")
  assertEqual(rgba(rawget(data.boundIcon, "__vertex")), rgba({ br, bg, bb }), label .. ": the BoP lock")
  assertEqual(rawget(data.boundIcon, "__alpha"), ba or 1, label .. ": the BoP lock's alpha")
  local qr, qg, qb = NS.QualityColor(4)
  assertEqual(textColor(data.cells.item), rgba({ qr, qg, qb }), label .. ": the item's quality text")
end

-- Today's values, the literals these surfaces drew before the skin engine.
local TODAY = {
  ["list.header.text"] = { 1, 0.82, 0 }, ["list.stripe"] = { 1, 1, 1, 0.03 },
  ["list.hover"] = { 1, 0.82, 0, 0.10 }, ["text.body"] = { 0.9, 0.9, 0.9 },
  ["text.disabled"] = { 0.5, 0.5, 0.5 },
  ["menu.bg"] = { 0.06, 0.06, 0.08, 0.98 }, ["menu.borderAlt"] = { 0.62, 0.5, 0.18, 1 },
  ["menu.hover"] = { 1, 0.82, 0, 0.15 },
  ["gtip.title"] = { 1, 0.82, 0 }, ["gtip.body"] = { 0.9, 0.9, 0.9 }, ["gtip.muted"] = { 0.5, 0.5, 0.5 },
}
local function today(name) return rgba(TODAY[name]) end

-- ── Ka0s Default ────────────────────────────────────────────────────────────────────────────────

test("skin table: on Ka0s Default every table surface draws the value it drew before skins", function()
  withFreshTable(function()
    assertTable(today, "Ka0s Default")
    local data = rows()[2]
    assertEqual(rgba(rawget(data.boundIcon, "__vertex")), rgba({ 0.30, 0.82, 0.42 }), "BoP green, as before")
    local c = mocks.ITEM_QUALITY_COLORS[4]
    assertEqual(textColor(data.cells.item), rgba({ c.r, c.g, c.b }), "the client's epic color, as before")
    assertTrue(rawget(rows()[1].header, "__text"):find("|cff808080(3)|r", 1, true) ~= nil, "the count's bytes")
    -- The header band and the scroll bar are recorded, and paint nothing on Ka0s Default.
    assertTrue(recorded(BT.headerFrame, "SortHeaderBar"), "the header is the skin's SortHeaderBar")
    assertEqual(#(rawget(BT.headerFrame, "__paintRegions") or {}), 0, "Ka0s Default lays no band under the header")
    local sb = rawget(BT.scroll, "ScrollBar")
    assertTrue(recorded(sb, "ScrollBar"), "the scroll bar is the skin's ScrollBar")
    assertEqual(#(rawget(sb, "__paintRegions") or {}), 0, "Ka0s Default lays no track under the bar")
    assertEqual(textColor(BT.emptyText), today("text.disabled"), "the empty-state line")
  end)
end)

test("skin table: the row menu is the skin's MenuFrame, call for call today's backdrop", function()
  withFreshTable(function()
    BT:ShowRowMenu(rows()[2], RECORD)
    local m = BT:MenuFrame()
    assertTrue(recorded(m, "MenuFrame"), "the row menu is the skin's MenuFrame")
    local bd = rawget(m, "__backdrop")
    assertEqual(bd.bgFile, "Interface\\Buttons\\WHITE8X8")
    assertEqual(bd.edgeFile, "Interface\\Buttons\\WHITE8X8")
    assertEqual(bd.edgeSize, 1)
    assertTrue(bd.insets == nil, "the row menu's backdrop has no insets")
    assertEqual(rgba(rawget(m, "__backdropColor")), today("menu.bg"), "the menu fill")
    assertEqual(rgba(rawget(m, "__backdropBorderColor")), today("menu.borderAlt"), "the muted gold edge")
    local labels = {}
    for i, b in ipairs(m.buttons) do
      if b:IsShown() then
        labels[i] = rawget(b.fs, "__text")
        assertEqual(rgba(rawget(b.hl, "__color")), today("menu.hover"), "item " .. i .. " hover")
      end
    end
    -- Link to chat is disabled (no link), Blacklist item enabled; Delete in today's red bytes.
    assertEqual(textColor(m.buttons[1].fs), today("text.disabled"), "a disabled entry")
    assertEqual(textColor(m.buttons[5].fs), today("text.body"), "an enabled entry")
    assertTrue(labels[5]:find("|cffff5555Delete|r", 1, true) ~= nil, "Delete keeps |cffff5555: " .. labels[5])
  end)
end)

test("skin table: the header and row tooltips read gtip.*", function()
  withFreshTable(function()
    local lines = tipLines(function() BT.headerFrame.buttons.item:__fire("OnEnter") end)
    assertEqual(lines[1].c, today("gtip.title"), "the column name")
    assertEqual(lines[2].c, today("gtip.body"), "the column's description")
    assertTrue(lines[2].wrap == true, "the description still wraps")
    lines = tipLines(function() BT.headerFrame.buttons.bound:__fire("OnEnter") end)
    assertEqual(#lines, 6, "the Bound title and five legend lines")
    for i = 2, 6 do assertEqual(lines[i].c, today("gtip.body"), "legend line " .. i) end
    -- An item row: the inferred note and the hint after the hyperlink, both gtip.muted.
    local data = rows()[2]
    RECORD.itemLink, RECORD.confidence = "|cffa335ee|Hitem:7::|h[Sword]|h|r", "INFERRED"
    local ok, err = pcall(function()
      lines = tipLines(function() data:__fire("OnEnter") end)
    end)
    RECORD.itemLink, RECORD.confidence = nil, nil
    if not ok then error(err, 0) end
    assertEqual(#lines, 2, "the inferred note and the hint")
    assertEqual(lines[1].c, today("gtip.muted"), "the inferred note")
    assertEqual(lines[2].c, today("gtip.muted"), "the hint")
  end)
end)

test("skin table: the sample tooltip reads q.* and gtip.*", function()
  local seen
  local stock = NS.Compat.ShowTintedTooltip
  NS.Compat.ShowTintedTooltip = function(_, lines) seen = lines end
  local ok, err = pcall(BT.ShowSampleTooltip, {}, { itemName = "Sword", quality = 4, itemType = "Weapon",
    itemSubType = "Daggers", confidence = "INFERRED" })
  NS.Compat.ShowTintedTooltip = stock
  if not ok then error(err, 0) end
  local function c(line) return rgba({ line[2], line[3], line[4] }) end
  local qr, qg, qb = NS.QualityColor(4)
  assertEqual(c(seen[1]), rgba({ qr, qg, qb }), "the name in its quality color")
  assertEqual(c(seen[2]), today("gtip.body"), "Type · SubType")
  for i = 3, 5 do assertEqual(c(seen[i]), today("gtip.muted"), "line " .. i) end
end)

-- ── a skin switch ───────────────────────────────────────────────────────────────────────────────

test("skin table: a skin switch repaints the table live, pooled free rows too, and Ka0s Default puts it back", function()
  withFreshTable(function()
    -- Park one row on the free list, so the walk has both lists to reach.
    BT.displayList = { LIST[1], LIST[2] }
    BT:Bind()
    assertTrue(#BT.rowPool.free >= 1, "no row on the free list")
    NS.ApplySkinChoice("ka0s", "azeroth")
    -- The case means something only where Azeroth differs from today.
    for _, name in ipairs({ "list.header.text", "list.stripe", "list.hover", "text.body", "gtip.title",
                            "menu.bg", "menu.hover" }) do
      assertTrue(tokenOf(name) ~= today(name), "Azeroth's " .. name .. " is today's value: pick another skin")
    end
    assertTrue(tokenOf("sem.boundBoP") ~= rgba({ 0.30, 0.82, 0.42, 1 }), "Azeroth's BoP is today's")
    assertTrue(#BT.rowPool.free >= 1, "the switch's rebind took the free row")
    for _, row in ipairs(BT.rowPool.free) do
      assertEqual(rgba(rawget(row.stripe, "__color")), tokenOf("list.stripe"), "a free row's stripe")
      assertEqual(rgba(rawget(row.hl, "__color")), tokenOf("list.hover"), "a free row's hover")
    end
    BT.displayList = LIST
    BT:Bind()
    assertTable(tokenOf, "Azeroth")
    -- The menu opened under Azeroth wears Azeroth; Delete takes sem.danger.
    BT:ShowRowMenu(rows()[2], RECORD)
    local m = BT:MenuFrame()
    assertEqual(rgba(rawget(m, "__backdropColor")), tokenOf("menu.bg"), "the menu fill follows the skin")
    assertEqual(rgba(rawget(m.buttons[1].hl, "__color")), tokenOf("menu.hover"), "the menu hover")
    local danger = escape({ Skin:Color(OWNER, "sem.danger") })
    assertTrue(danger ~= "|cffff5555", "Azeroth's sem.danger is today's")
    assertTrue(rawget(m.buttons[5].fs, "__text"):find(danger .. "Delete|r", 1, true) ~= nil, "Delete in sem.danger")
    m:Hide()
    local lines = tipLines(function() BT.headerFrame.buttons.item:__fire("OnEnter") end)
    assertEqual(lines[1].c, tokenOf("gtip.title"), "the header tooltip follows the skin")

    NS.ApplySkinChoice("ka0s", "ka0s")
    assertTable(today, "back on Ka0s Default")
    BT:ShowRowMenu(rows()[2], RECORD)
    assertEqual(rgba(rawget(m, "__backdropColor")), today("menu.bg"), "the menu fill back")
    assertEqual(rgba(rawget(m.buttons[1].hl, "__color")), today("menu.hover"), "the menu hover back")
  end)
end)

-- ── the seam helpers and the degraded facade ────────────────────────────────────────────────────

test("skin table: NS.QualityColor reads q.* where the skin sets it, else the client's color", function()
  local c = mocks.ITEM_QUALITY_COLORS[4]
  assertEqual(rgba({ NS.QualityColor(4) }), rgba({ c.r, c.g, c.b }), "Ka0s Default sets no q.*")
  NS.ApplySkinChoice("ka0s", "azeroth")
  local ok, err = pcall(function()
    assertEqual(rgba({ NS.QualityColor(5) }), rgba({ Skin:Color(OWNER, "q.legendary") }), "Azeroth's legendary")
    assertEqual(select("#", NS.QualityColor(5)), 3, "three components")
  end)
  reset()
  if not ok then error(err, 0) end
  assertEqual(NS.SkinEscape("sem.danger"), "|cffff5555")
  assertEqual(NS.SkinEscape("text.disabled"), "|cff808080")
  assertEqual(NS.SkinEscape("no.such.token"), nil)
end)

test("skin table: the degraded facade draws the row menu today's way", function()
  local dns, _, dm = dofile("tests/degraded_env.lua")()
  local f = dm.CreateFrame("Frame", nil, dm.UIParent, "BackdropTemplate")
  local seen = {}
  rawset(f, "SetBackdrop", function(_, t) seen.bd = t end)
  rawset(f, "SetBackdropColor", function(_, ...) seen.fill = rgba({ ... }) end)
  rawset(f, "SetBackdropBorderColor", function(_, ...) seen.edge = rgba({ ... }) end)
  dns.Skin.MenuFrame(f, { alt = true })
  assertEqual(seen.bd and seen.bd.edgeSize, 1, "the WHITE8X8 box at edgeSize 1")
  assertTrue(seen.bd.insets == nil, "with no insets")
  assertEqual(seen.fill, today("menu.bg"))
  assertEqual(seen.edge, today("menu.borderAlt"))
  assertEqual(dns.SkinEscape("sem.danger"), "|cffff5555", "Delete's bytes degraded too")
end)

test("skin table: a skin with a face reaches the table's cells, and Ka0s Default leaves them stock", function()
  -- The owner's note (2026-10-26): on Azeroth the table's text was the client's font under its dark
  -- drop shadow. red under: cells built from GameFont templates and never handed to the skin's Font.
  withFreshTable(function()
    BT.displayList = LIST
    BT:Bind()
    local cell
    for _, row in ipairs(rows()) do
      for _, fs in pairs(row.cells or {}) do cell = cell or fs end
    end
    assertTrue(cell ~= nil, "a bound data row has cells")
    -- The face the cell draws: through the owner's font object where the client has CreateFont, else
    -- set by path (this suite's case); either way GetFont answers the skin's face.
    local FACE = "Fonts\\AtkinsonHyperlegible-Regular.ttf"
    local function owned(fs) return (fs:GetFont()) == FACE end
    -- The suite's strings answer no template font, so the cell is given the face its GameFont
    -- template would hand it in the client; that is the face Ka0s Default must put back.
    cell:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    assertTrue(not owned(cell), "Ka0s Default sets no face: the cell keeps its template's font")
    -- This suite loads no LibSharedMedia, so no skin face resolves and Font rightly leaves every cell
    -- alone. The face is answered here, for the case's length, at the engine's one media lookup.
    local P = Skin.__P
    local media = P.media
    P.media = function(kind, key)
      if kind == "font" and key == "Ka0s Atkinson" then return FACE end
      return media(kind, key)
    end
    local ok, err = pcall(function()
      NS.ApplySkinChoice("ka0s", "azeroth")
      assertTrue(owned(cell), "under Azeroth the cell wears the skin's body face")
      NS.ApplySkinChoice("ka0s", "ka0s")
    end)
    P.media = media
    if not ok then error(err, 0) end
    assertEqual((cell:GetFont()), "Fonts\\FRIZQT__.TTF", "and Ka0s Default puts the template's face back")
  end)
end)
