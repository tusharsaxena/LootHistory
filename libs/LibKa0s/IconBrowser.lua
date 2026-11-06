-- LibKa0s-IconBrowser-1.0 — IconBrowser.lua: the icon browser, a window over whatever opened it
-- where an icon is picked from every tab IconBrowserSources.lua offers the host, and a glyph's color
-- with it. Built by `IB:New(spec)`, once per host; each browser holds its own selection, search and
-- window.
--
--     window   IconBrowserWindow.lua's, titled `spec.title` (the host's brand)
--     header   Choose an icon, the gold rule under it
--     tabs     the host's own tabs first, then [ Markers ][ Game icons ][ Glyphs ] less the ones
--              `spec.hide` names (the host's Options instance's tab strip)
--     toolbar  Game icons: Show All / Spells / Items. Glyphs: Show All or one icon set (Open
--              Iconic / Phosphor / Game-icons, from the library), then the glyph color swatch (any
--              tab whose descriptor says `swatch`). Then the search box (a magnifier, a clear mark),
--              and at the right how many icons the tab holds, or "N of M icons" while a search
--              narrows it.
--     grid     COLS x ROWS icons and a scrollbar, GRID_GAP under the toolbar; the mouse wheel
--              scrolls too
--     hint     Game icons only: search by texture id, Wowhead for a name, and a button that shows
--              Wowhead's icon address in a copy window (the client cannot open a web page)
--     footer   the selected icon (a glyph in the color) and its name, then Choose and Cancel
--
-- Promoted from Ka0s Quick Comms (`settings/IconBrowser.lua`), because Outfitter Reborn wants the
-- same browser with the same semantics (library-stack-§7, *What earns promotion*). Every Quick
-- Comms dependency became a `spec` field: the title, the layers, the Options instance, the chat
-- line, the combat test, the timer, the copy window and the color picker's tracking. The library
-- registers no bus message: the host calls Cancel when its opener goes, and StandDown / StandUp
-- from its own lifecycle.
--
-- A click on an icon selects it, a double-click chooses it, and hovering one names it (its label,
-- or a game icon's texture id; a glyph's tooltip also names its set, and a Game-icons mark its
-- author, as CC BY 3.0 asks). Choose hands the opener the icon and, for a glyph, the color (none for
-- white), then closes. Cancel, the close X and Escape change nothing. The stored icon is preselected,
-- and the first tab that owns it (host tabs are asked first) opened and scrolled to it. An icon no
-- tab owns, or none, opens on the first tab with nothing selected: the footer asks for a click, and
-- Choose waits for one.
--
-- SEARCH filters the shown tab as it is typed (Sources.Search), from the top. The text is the
-- browser's for the session: a tab switch and a later open keep it and filter again.
--
-- THE GRID IS VIRTUALIZED: COLS x ROWS cell buttons are built once and re-dressed from the tab's
-- list at the scroll offset, so the Game icons tab's thousands of entries cost a few dozen frames.
--
-- ESCAPE hides every shown special frame, so while the browser is open the opener's own special
-- frames (`lift`) are taken out of UISpecialFrames and put back on the next frame after the browser
-- closes (`spec.schedule(0, fn)`, never while the client walks the list): Escape closes the browser
-- only. The swatch's color picker is not modal, so one the swatch opened is hidden when the browser
-- closes (`spec.releasePicker`, else the browser's own tracking).
--
-- IN COMBAT Choose is refused (`spec.inCombat`, else InCombatLockdown): nothing is handed out, the
-- browser stays open, and `spec.print` gets one gray line.
--
-- THE SKIN. Every color is a token read through the owner's facade (IconBrowserWindow.lua): the
-- selected cell `ib.selStrong`, the empty footer line `ib.note`, the search magnifier `log.tag` and
-- its clear mark `ib.markGray`, the hint box `drawer.boxBg` / `drawer.boxBorder`, the texts their
-- roles in the skin's body face (the count `text.disabled`, the icon's name `text.heading`, the status
-- and the hint `text.highlight`), the tooltip's title `gtip.title`, its lines `gtip.value` and the
-- credit `gtip.subtle`. The scroller is the skin's ScrollBar. A cell's hover keeps the client's art,
-- tinted where a skin has a hover color. Host-drawn colors repaint on every looks change.
--
-- Depends on LibStub, the IconBrowser shell (IconBrowserSources.lua) and its window
-- (IconBrowserWindow.lua, read at call time), the host's LibKa0s Options instance (`spec.helpers`:
-- CreatePanel, TabStrip, AttachTooltip, AceGUI, CHROME_GAP) and LibKa0s-Core-1.0; reads
-- LibKa0s-Widgets-1.0's CopyWindow and LibKa0s-Media-1.0's Icon at call time.

local lib = LibStub and LibStub("LibKa0s-IconBrowser-1.0", true)
if not lib then return end   -- the shell refused (no Core or Media): nothing to attach to

-- Minor 1: the browser, lifted from Quick Comms, a host-configured instance per `New`.
local BROWSER_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own, as WidgetsCopyWindow.lua is.
if lib.__browserMinor and lib.__browserMinor >= BROWSER_MINOR
  and lib.__browserShellMinor == lib.MINOR then return end
lib.__browserMinor      = BROWSER_MINOR
lib.__browserShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.IconBrowser = BROWSER_MINOR

local Src = lib.Sources

-- Every word the browser shows, beside the sources' own in lib.STRINGS (a host overrides any of
-- them with `spec.L`, read with rawget).
local WORDS = {
  HEADER          = "Choose an icon",
  ALL             = "All",
  SPELLS          = "Spells",
  ITEMS           = "Items",
  SHOW            = "Show",
  SHOW_GAME_TIP   = "All the game's icons, or only the spell or the item icons.",
  SHOW_SETS_TIP   = "Every glyph, or only one icon set's.",
  ICON_COLOR      = "Icon color",
  ICON_COLOR_TIP  = "The color a glyph is drawn in. White is none.",
  SEARCH          = "Search",
  SEARCH_TIP      = "Markers by name, glyphs by name, game icons by texture id. Not case-sensitive.",
  CLICK_TO_SELECT = "Click an icon to select it.",
  NOTHING         = "Nothing to show here.",
  NOT_LOADED      = "The game's icon list has not loaded yet. Open this tab again in a moment.",
  NO_MATCH        = "No icon matches your search.",
  COUNT           = "%d icons",
  COUNT_OF        = "%d of %d icons",
  CELL_TIP        = "Click to select it, double-click to choose it.",
  COPY_WOWHEAD    = "Copy wowhead.com/icons",
  COPY_WOWHEAD_TIP = "Shows Wowhead's icon search address in a box to copy it from (Ctrl+C). The game cannot open a web page.",
  HINT            = "Search by texture id. To find an icon by its name (e.g. ability_cheapshot), look it up on Wowhead and type its id here.",
  LINK_TITLE      = "%s: Wowhead icons",
  CHOOSE          = "Choose",
  CHOOSE_TIP      = "Use the selected icon and close.",
  CANCEL          = "Cancel",
  CANCEL_TIP      = "Close without choosing. Nothing changes.",
  COMBAT          = "cannot choose an icon during combat",
}
lib.STRINGS = lib.STRINGS or {}
for k, v in pairs(WORDS) do lib.STRINGS[k] = v end

lib.WOWHEAD_ICONS = "https://www.wowhead.com/icons"

local COLS, ROWS = 12, 7
local CELL, ICON = 40, 32           -- a cell's pitch, and the icon in it
local WIDTH, HEIGHT = 560, 594
-- The page's left inset and the gap under the body.
local CONTENT_X, BODY_BOTTOM = 12, 12
-- The toolbar's band over the grid, and the gap between them (the swatch's row would touch the
-- grid's first row). HEIGHT leaves the hint and the footer (34) their bands under the grid.
local TOOLBAR_H, GRID_GAP = 30, 10
local HINT_GAP, HINT_H = 8, 36
local GRID_TOP = TOOLBAR_H + GRID_GAP
-- The game filter is TOOL_W wide; the search box sits SEARCH_GAP after the tab's controls, SEARCH_W
-- wide. Glyphs carries two controls, the set filter (SET_W) and the swatch (SWATCH_W), so its search
-- box is narrower (SEARCH_W_GLYPHS) and the count keeps its room at the right.
local TOOL_W, SEARCH_GAP, SEARCH_W, SEARCH_GLYPH = 180, 10, 190, 14
local SET_W, SWATCH_W, SEARCH_W_GLYPHS = 130, 110, 160
local SELECTED, NOTE = "ib.selStrong", "ib.note"
local MUTED_GOLD, MARK_GRAY = "log.tag", "ib.markGray"
local HINT_FILL, HINT_EDGE = "drawer.boxBg", "drawer.boxBorder"
-- The combat refusal's chat line: chat output, not a skinned surface.
local CHAT_GRAY = "|cffaaaaaa"
local FILTER_ORDER = { "all", "spells", "items" }

local Browser = {}
Browser.__index = Browser

local function W() return lib.__window end

--- One word: the host's override first (rawget: a Ka0s locale table answers an unknown key with
--- the key), else the library's.
local function text(b, key)
  local L = b.L
  local v = type(L) == "table" and rawget(L, key)
  if type(v) == "string" then return v end
  return lib.STRINGS[key]
end

local function color(b, token) return W().Color(b.owner, token) end
local function facade(b) return W().Facade(b.owner) end

-- ── Escape: the opener's special frames, out while the browser is open ──────────────────────

local function unlist(name)
  for i = #UISpecialFrames, 1, -1 do
    if UISpecialFrames[i] == name then
      table.remove(UISpecialFrames, i)
      return true
    end
  end
  return false
end

local function lift(b, names)
  if type(UISpecialFrames) ~= "table" then return end
  for _, name in ipairs(names or {}) do
    if b.pending[name] or unlist(name) then
      b.pending[name] = nil
      b.lifted[name] = true
    end
  end
end

-- `fn` on the next frame: the host's timer, else C_Timer, else now.
local function nextFrame(b, fn)
  local schedule = b.spec.schedule
  if type(schedule) == "function" then return schedule(0, fn) end
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then return C_Timer.After(0, fn) end
  fn()
end

-- On the next frame: an Escape that hid the browser is still walking the list now.
local function putBack(b)
  for name in pairs(b.lifted) do
    b.pending[name] = true
    b.lifted[name] = nil
  end
  if next(b.pending) == nil then return end
  nextFrame(b, function()
    if type(UISpecialFrames) ~= "table" then return end
    for name in pairs(b.pending) do
      b.pending[name] = nil
      unlist(name)
      table.insert(UISpecialFrames, name)
    end
  end)
end

-- ── the color picker the swatch opens ───────────────────────────────────────────────────────

-- The host's tracking when it passed one (a picker shared with its own swatches), else the
-- browser's: a click that opens the picker on the swatch is noted, and the picker's OnHide forgets.
local function trackPicker(b, swatch)
  if type(b.spec.trackPicker) == "function" then return b.spec.trackPicker(swatch) end
  local frame = swatch.frame
  if not (frame and frame.HookScript) then return end
  frame:HookScript("OnClick", function()
    local picker = ColorPickerFrame
    if not (picker and picker:IsShown()) then return end
    b.pickerOpen = true
    if not b.pickerHooked and picker.HookScript then
      b.pickerHooked = true
      picker:HookScript("OnHide", function() b.pickerOpen = false end)
    end
  end)
end

local function releasePicker(b, swatch)
  if type(b.spec.releasePicker) == "function" then return b.spec.releasePicker(swatch) end
  if not b.pickerOpen then return end
  b.pickerOpen = false
  local picker = ColorPickerFrame
  if picker and picker:IsShown() then picker:Hide() end
end

-- ── drawing ─────────────────────────────────────────────────────────────────────────────────

local function maxOffset(b)
  return math.max(0, math.ceil(#b.list / COLS) - ROWS)
end

-- The tint `icon` is drawn with: the color for a glyph, white for anything else.
local function tint(b, icon)
  if b.color and lib.IsGlyph(icon) then return lib.Tint(b.color) end
  return 1, 1, 1
end

-- What `icon` is called: by the tab that owns it, else the shown tab.
local function label(b, icon)
  local home = b.byKey[Src.TabFor(icon, b.tabs) or ""] or b.byKey[b.tab]
  return Src.Label(home, icon)
end

local function dressCell(b, cell, v)
  cell.ibIcon = v
  if v == nil then
    cell:Hide()
    return
  end
  cell.icon:SetTexture(v)
  W().Icon(b.owner, cell, cell, cell.icon, v)
  cell.icon:SetVertexColor(tint(b, v))
  cell.selected:SetShown(v == b.selected)
  cell:Show()
end

local function drawFooter(b)
  local w = b.w
  if b.selected ~= nil then
    w.preview:SetTexture(b.selected)
    W().Icon(b.owner, b.footerIcon, w.area, w.preview, b.selected)
    w.preview:SetVertexColor(tint(b, b.selected))
    w.preview:Show()
    w.name:SetText(label(b, b.selected))
  else
    w.preview:Hide()
    W().Edge(b.owner, b.footerIcon, w.area, w.preview, false)
    w.name:SetText((W().Escape(b.owner, NOTE) or "") .. text(b, "CLICK_TO_SELECT") .. "|r")
  end
  w.choose:SetDisabled(b.selected == nil)
end

-- Whether the typed text narrows the tab (Search ignores a blank one).
local function searching(b)
  return b.search:match("%S") ~= nil
end

local function drawStatus(b)
  local status = b.w.status
  if #b.list > 0 then
    status:Hide()
    return
  end
  local key = "NOTHING"
  if not b.loaded then
    key = "NOT_LOADED"
  elseif searching(b) and b.total > 0 then
    key = "NO_MATCH"
  end
  status:SetText(text(b, key))
  status:Show()
end

-- A cell's hover tooltip: its icon's name and what a click does.
local function tooltip(b, cell)
  if cell.ibIcon == nil or not GameTooltip then return end
  GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
  GameTooltip:SetText(label(b, cell.ibIcon), color(b, "gtip.title"))
  local credit = Src.Credit(cell.ibIcon, b.L)
  if credit then
    local r, g, bl = color(b, "gtip.subtle")
    GameTooltip:AddLine(credit, r, g, bl, true)
  end
  local r, g, bl = color(b, "gtip.value")
  GameTooltip:AddLine(text(b, "CELL_TIP"), r, g, bl, true)
  GameTooltip:Show()
end

-- The grid is virtualized: a scroll re-dresses the cell under the pointer without a new OnEnter,
-- so the tooltip a cell owns is re-said for its new icon, or hidden when the cell went empty.
local function refreshTooltip(b)
  if not GameTooltip or not GameTooltip:IsShown() then return end
  local owner = GameTooltip:GetOwner()
  for _, cell in ipairs(b.cells) do
    if cell == owner then
      if cell.ibIcon ~= nil and cell:IsShown() then tooltip(b, cell) else GameTooltip:Hide() end
      return
    end
  end
end

-- Re-dress every cell from the list at the offset, and the scrollbar, the count and the footer.
local function draw(b)
  local w = b.w
  b.drawing = true
  b.offset = math.max(0, math.min(b.offset, maxOffset(b)))
  for i, cell in ipairs(b.cells) do dressCell(b, cell, b.list[b.offset * COLS + i]) end
  w.slider:SetMinMaxValues(0, maxOffset(b))
  w.slider:SetValue(b.offset)
  w.slider:SetShown(maxOffset(b) > 0)
  w.count:SetText(searching(b) and text(b, "COUNT_OF"):format(#b.list, b.total) or text(b, "COUNT"):format(#b.list))
  drawStatus(b)
  drawFooter(b)
  refreshTooltip(b)
  b.drawing = false
end

local function setOffset(b, v)
  v = math.max(0, math.min(math.floor(v + 0.5), maxOffset(b)))
  if v == b.offset then return end
  b.offset = v
  draw(b)
end

-- The search box's text inset between its magnifier and its clear mark. AceGUI's EditBox resets
-- its input's insets to 0 (HideButton) on SetText, Enter and a drop, so each of those re-applies it.
local function applyInsets(b)
  local box = b.w.search
  local input = box and (box.editbox or box.frame)
  if input and input.SetTextInsets then input:SetTextInsets(SEARCH_GLYPH + 4, SEARCH_GLYPH + 6, 3, 3) end
end

local function isSwatchTab(b) return b.byKey[b.tab] ~= nil and b.byKey[b.tab].swatch == true end

-- Where the swatch and the search box sit on the shown tab: after the tab's own controls.
local function toolbarX(b)
  if b.tab == "game" then return nil, TOOL_W + SEARCH_GAP, SEARCH_W end
  if b.tab == "glyphs" then return SET_W + SEARCH_GAP, SET_W + SWATCH_W + 2 * SEARCH_GAP, SEARCH_W_GLYPHS end
  if isSwatchTab(b) then return 0, SWATCH_W + SEARCH_GAP, SEARCH_W end
  return nil, 0, SEARCH_W
end

local function drawSearch(b)
  local w = b.w
  local _, x, width = toolbarX(b)
  w.search:SetWidth(width)
  w.search.frame:ClearAllPoints()
  w.search.frame:SetPoint("TOPLEFT", w.area, "TOPLEFT", x, 0)
  if w.search:GetText() ~= b.search then
    w.search:SetText(b.search)
    applyInsets(b)
  end
  w.clear:SetShown(b.search ~= "")
end

-- The toolbar's controls for the tab, the swatch's color, the search box and the hint row.
local function drawToolbar(b)
  local w = b.w
  w.filter.frame:SetShown(b.tab == "game")
  w.filter:SetValue(b.filter)
  w.sets.frame:SetShown(b.tab == "glyphs")
  w.sets:SetValue(b.glyphSet)
  local swatchX = toolbarX(b)
  w.swatch.frame:SetShown(swatchX ~= nil)
  if swatchX then
    w.swatch.frame:ClearAllPoints()
    w.swatch.frame:SetPoint("TOPLEFT", w.area, "TOPLEFT", swatchX, 0)
  end
  w.swatch:SetColor(lib.Tint(b.color))
  drawSearch(b)
  w.hint:SetShown(b.tab == "game")
end

-- The area under the band the strip reserved (a strip that wraps reserves more).
local function anchorArea(b)
  local area, ctx = b.w.area, b.ctx
  area:ClearAllPoints()
  area:SetPoint("TOPLEFT", ctx.body, "TOPLEFT", CONTENT_X, -((b.helpers.CHROME_GAP or 8) + (ctx.chromeHeight or 0)))
  area:SetPoint("BOTTOMRIGHT", ctx.body, "BOTTOMRIGHT", -CONTENT_X, BODY_BOTTOM)
end

-- The strip, then the area. On the first open the chrome has no width yet, so the strip wraps every
-- tab onto its own row; the library re-places it from the chrome's OnSizeChanged once the width
-- arrives, and the area follows from a hook on the same script. Hooked, not set, and only after the
-- first strip: the library installs its handler with SetScript, which would wipe a hook made before.
local function drawTabs(b)
  local h, ctx = b.helpers, b.ctx
  if h.TabStrip then
    h.TabStrip(ctx, { tabs = b.tabs, value = b.tab, onSelect = function(key) b:SetTab(key) end })
  end
  if not b.areaHooked and ctx.chrome and ctx.chrome.HookScript then
    b.areaHooked = true
    ctx.chrome:HookScript("OnSizeChanged", function() anchorArea(b) end)
  end
  anchorArea(b)
end

-- The filter a tab's list is read with: the game filter, the glyph set, or none.
local function filterFor(b)
  if b.tab == "game" then return b.filter end
  if b.tab == "glyphs" then return b.glyphSet end
  return nil
end

-- The tab's list, searched, from the top, or scrolled to `icon` when the list holds it.
local function fill(b, icon)
  local desc = b.byKey[b.tab]
  local all
  all, b.loaded = Src.List(desc, filterFor(b))
  b.total = #all
  b.list = Src.Search(all, desc, b.search)
  b.offset = 0
  if icon == nil then return end
  for i, v in ipairs(b.list) do
    if v == icon then
      b.offset = math.floor((i - 1) / COLS)
      break
    end
  end
end

local function showTab(b, key, icon)
  b.tab = key
  fill(b, icon)
  drawTabs(b)
  drawToolbar(b)
  draw(b)
end

-- ── the window's parts ──────────────────────────────────────────────────────────────────────

local function makeCell(b, i)
  local grid = b.w.grid
  local cell = CreateFrame("Button", nil, grid)
  cell:SetSize(CELL - 2, CELL - 2)
  cell:SetPoint("TOPLEFT", grid, "TOPLEFT", ((i - 1) % COLS) * CELL, -math.floor((i - 1) / COLS) * CELL)
  local sel = cell:CreateTexture(nil, "BACKGROUND")
  sel:SetAllPoints(cell)
  sel:SetColorTexture(color(b, SELECTED))
  sel:Hide()
  cell.selected = sel
  local icon = cell:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON, ICON)
  icon:SetPoint("CENTER", cell, "CENTER", 0, 0)
  cell.icon = icon
  cell:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  -- Recorded once, so a skin change repaints it with no call here.
  facade(b).HoverArt(cell:GetHighlightTexture(), { panel = true })
  cell:SetScript("OnClick", function(self) b:Select(self.ibIcon) end)
  cell:SetScript("OnDoubleClick", function(self)
    b:Select(self.ibIcon)
    b:Choose()
  end)
  cell:SetScript("OnEnter", function(self) tooltip(b, self) end)
  cell:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return cell
end

local function paintText(b, fs, token) facade(b).Text(fs, token) end

local function buildGrid(b)
  local w = b.w
  local area = w.area
  local grid = CreateFrame("Frame", nil, area)
  w.grid = grid
  grid:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -GRID_TOP)
  grid:SetSize(COLS * CELL, ROWS * CELL)
  grid:EnableMouseWheel(true)
  grid:SetScript("OnMouseWheel", function(_, delta) setOffset(b, b.offset - delta) end)
  for i = 1, COLS * ROWS do b.cells[i] = makeCell(b, i) end
  w.status = grid:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  paintText(b, w.status, "text.highlight")
  w.status:SetPoint("CENTER", grid, "CENTER", 0, 0)
  w.status:Hide()
  local slider = CreateFrame("Slider", nil, area)
  w.slider = slider
  slider:SetPoint("TOPLEFT", grid, "TOPRIGHT", 6, 0)
  slider:SetPoint("BOTTOMLEFT", grid, "BOTTOMRIGHT", 6, 0)
  slider:SetWidth(16)
  slider:SetOrientation("VERTICAL")
  slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  slider:SetValueStep(1)
  slider:SetObeyStepOnDrag(true)
  w.track = slider:CreateTexture(nil, "BACKGROUND")
  w.track:SetAllPoints(slider)
  facade(b).ScrollBar(slider, { track = w.track })
  slider:SetScript("OnValueChanged", function(_, v) if not b.drawing then setOffset(b, v) end end)
  -- The scrollbar sits beside the grid, not in it: it scrolls on the wheel too.
  slider:EnableMouseWheel(true)
  slider:SetScript("OnMouseWheel", function(_, delta) setOffset(b, b.offset - delta) end)
end

-- An AceGUI widget placed by hand in the area, kept for the browser's life (never released).
local function place(b, widget, point, x, y)
  local area = b.w.area
  widget.frame:SetParent(area)
  widget.frame:ClearAllPoints()
  widget.frame:SetPoint(point, area, point, x, y)
  widget.frame:Show()
  return widget
end

local function tip(b, widget, titleKey, bodyKey)
  if b.helpers.AttachTooltip then b.helpers.AttachTooltip(widget, text(b, titleKey), text(b, bodyKey)) end
end

local function buildToolbar(b, AceGUI)
  local w = b.w
  w.filter = AceGUI:Create("Dropdown")
  w.filter:SetLabel("")
  w.filter:SetList({ all = text(b, "ALL"), spells = text(b, "SPELLS"), items = text(b, "ITEMS") }, FILTER_ORDER)
  w.filter:SetWidth(TOOL_W)
  w.filter:SetCallback("OnValueChanged", function(_, _, key) b:SetFilter(key) end)
  tip(b, w.filter, "SHOW", "SHOW_GAME_TIP")
  place(b, w.filter, "TOPLEFT", 0, 0)
  w.sets = AceGUI:Create("Dropdown")
  w.sets:SetLabel("")
  local sets, order = { all = text(b, "ALL") }, { "all" }
  for _, set in ipairs(Src.GlyphSets(b.L)) do
    sets[set.id] = set.label
    order[#order + 1] = set.id
  end
  w.sets:SetList(sets, order)
  w.sets:SetWidth(SET_W)
  w.sets:SetCallback("OnValueChanged", function(_, _, key) b:SetGlyphSet(key) end)
  tip(b, w.sets, "SHOW", "SHOW_SETS_TIP")
  place(b, w.sets, "TOPLEFT", 0, 0)
  w.swatch = AceGUI:Create("ColorPicker")
  w.swatch:SetLabel(text(b, "ICON_COLOR"))
  w.swatch:SetHasAlpha(false)
  w.swatch:SetWidth(SWATCH_W)
  local function pick(_, _, r, g, bl) b:SetColor(lib.ColorFrom(r, g, bl) or nil) end
  w.swatch:SetCallback("OnValueChanged", pick)
  w.swatch:SetCallback("OnValueConfirmed", pick)
  trackPicker(b, w.swatch)
  tip(b, w.swatch, "ICON_COLOR", "ICON_COLOR_TIP")
  place(b, w.swatch, "TOPLEFT", SET_W + SEARCH_GAP, 0)
  w.count = w.area:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  paintText(b, w.count, "text.disabled")
  w.count:SetPoint("TOPRIGHT", w.area, "TOPRIGHT", 0, -6)
end

local function paintGlyph(b, t, token)
  local r, g, bl = color(b, token)
  if r then t:SetVertexColor(r, g, bl) end
end

-- A LibKa0s glyph drawn on `parent` in color token `token`, SEARCH_GLYPH square, at the host's
-- folder (Media.Icon); no texture without the Media major.
local function glyph(b, parent, name, token)
  local t = parent:CreateTexture(nil, "OVERLAY")
  t:SetSize(SEARCH_GLYPH, SEARCH_GLYPH)
  local Media = LibStub("LibKa0s-Media-1.0", true)
  t:SetTexture(Media and type(Media.Icon) == "function" and Media.Icon(b.owner, name) or nil)
  b.glyphs[t] = token
  paintGlyph(b, t, token)
  return t
end

-- The search box: an EditBox with its Okay button off (it filters as it is typed), a magnifier
-- inside its left edge and a clear mark inside its right, the text inset between them.
local function buildSearch(b, AceGUI)
  local w = b.w
  w.search = AceGUI:Create("EditBox")
  w.search:SetLabel("")
  w.search:SetWidth(SEARCH_W)
  w.search:DisableButton(true)
  w.search:SetCallback("OnTextChanged", function(_, _, value) b:SetSearch(value) end)
  tip(b, w.search, "SEARCH", "SEARCH_TIP")
  place(b, w.search, "TOPLEFT", TOOL_W + SEARCH_GAP, 0)
  local input = w.search.editbox or w.search.frame
  applyInsets(b)
  if input.HookScript then
    local function again() applyInsets(b) end
    input:HookScript("OnEnterPressed", again)
    input:HookScript("OnReceiveDrag", again)
    input:HookScript("OnMouseDown", again)
  end
  w.magnifier = glyph(b, input, "search", MUTED_GOLD)
  w.magnifier:SetPoint("LEFT", input, "LEFT", 0, 0)
  w.clear = CreateFrame("Button", nil, input)
  w.clear:SetSize(SEARCH_GLYPH, SEARCH_GLYPH)
  w.clear:SetPoint("RIGHT", input, "RIGHT", -2, 0)
  w.clearGlyph = glyph(b, w.clear, "close", MARK_GRAY)
  w.clearGlyph:SetPoint("CENTER", w.clear, "CENTER", 0, 0)
  w.clear:SetScript("OnClick", function() b:SetSearch("") end)
  w.clear:Hide()
end

-- The hint box's fill and its four edges in their tokens.
local function paintHint(b)
  local w = b.w
  if not w.hintFill then return end
  w.hintFill:SetColorTexture(color(b, HINT_FILL))
  for _, t in ipairs(w.hintEdges) do t:SetColorTexture(color(b, HINT_EDGE)) end
end

-- A 1px line along `side` of `f` (painted by paintHint).
local function edge(f, side)
  local t = f:CreateTexture(nil, "BORDER")
  if side == "TOP" or side == "BOTTOM" then
    t:SetPoint(side .. "LEFT", f, side .. "LEFT", 0, 0)
    t:SetPoint(side .. "RIGHT", f, side .. "RIGHT", 0, 0)
    t:SetHeight(1)
  else
    t:SetPoint("TOP" .. side, f, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, f, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  return t
end

-- The hint row under the grid (Game icons only): the words, then the button, in a box.
local function buildHint(b, AceGUI)
  local w = b.w
  local hint = CreateFrame("Frame", nil, w.area)
  w.hint = hint
  hint:SetPoint("TOPLEFT", w.grid, "BOTTOMLEFT", 0, -HINT_GAP)
  hint:SetPoint("TOPRIGHT", w.slider, "BOTTOMRIGHT", 0, -HINT_GAP)
  hint:SetHeight(HINT_H)
  w.hintFill = hint:CreateTexture(nil, "BACKGROUND")
  w.hintFill:SetAllPoints(hint)
  w.hintEdges = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do w.hintEdges[#w.hintEdges + 1] = edge(hint, side) end
  paintHint(b)
  w.link = AceGUI:Create("Button")
  w.link:SetText(text(b, "COPY_WOWHEAD"))
  w.link:SetWidth(170)
  w.link:SetCallback("OnClick", function()
    local win = b:LinkWindow()
    if win then win:Show(lib.WOWHEAD_ICONS) end
  end)
  tip(b, w.link, "COPY_WOWHEAD", "COPY_WOWHEAD_TIP")
  w.link.frame:SetParent(hint)
  w.link.frame:ClearAllPoints()
  w.link.frame:SetPoint("RIGHT", hint, "RIGHT", -6, 0)
  w.link.frame:Show()
  w.hintText = hint:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  paintText(b, w.hintText, "text.highlight")
  w.hintText:SetPoint("LEFT", hint, "LEFT", 10, 0)
  w.hintText:SetPoint("RIGHT", w.link.frame, "LEFT", -10, 0)
  w.hintText:SetJustifyH("LEFT")
  w.hintText:SetWordWrap(true)
  w.hintText:SetText(text(b, "HINT"))
  hint:Hide()
end

local function buildFooter(b, AceGUI)
  local w = b.w
  w.preview = w.area:CreateTexture(nil, "ARTWORK")
  w.preview:SetSize(ICON, ICON)
  w.preview:SetPoint("BOTTOMLEFT", w.area, "BOTTOMLEFT", 0, 0)
  w.name = w.area:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  paintText(b, w.name, "text.heading")
  w.name:SetPoint("LEFT", w.preview, "RIGHT", 8, 0)
  w.name:SetJustifyH("LEFT")
  w.name:SetWordWrap(false)
  w.choose = AceGUI:Create("Button")
  w.choose:SetText(text(b, "CHOOSE"))
  w.choose:SetWidth(110)
  w.choose:SetCallback("OnClick", function() b:Choose() end)
  tip(b, w.choose, "CHOOSE", "CHOOSE_TIP")
  place(b, w.choose, "BOTTOMRIGHT", -116, 0)
  -- A long name (a typed texture path has no label) is cut short before the buttons.
  w.name:SetPoint("RIGHT", w.choose.frame, "LEFT", -8, 0)
  w.cancel = AceGUI:Create("Button")
  w.cancel:SetText(text(b, "CANCEL"))
  w.cancel:SetWidth(110)
  w.cancel:SetCallback("OnClick", function() b:Cancel() end)
  tip(b, w.cancel, "CANCEL", "CANCEL_TIP")
  place(b, w.cancel, "BOTTOMRIGHT", 0, 0)
end

-- A skin switch: every host-drawn color in the new skin (the texts, the scroller and the window are
-- the library's recorded paint), and the footer's note line redrawn in its escape.
local function repaint(b)
  for _, cell in ipairs(b.cells) do cell.selected:SetColorTexture(color(b, SELECTED)) end
  for t, token in pairs(b.glyphs) do paintGlyph(b, t, token) end
  paintHint(b)
  if b.request then drawFooter(b) end
end

local function build(b)
  local spec = b.spec
  W().EnsureTokens(b.owner)
  local made = W().Build({ owner = b.owner, name = b.name, pageName = b.name .. "Page",
    title = spec.title, header = text(b, "HEADER"), width = WIDTH, height = HEIGHT,
    layers = b.layers, helpers = b.helpers, onClose = function() b:Cancel() end })
  b.ctx = made.ctx
  b.catcher, b.frame, b.chrome = made.catcher, made.frame, made.chrome
  b.w.area = CreateFrame("Frame", nil, b.ctx.body)
  local AceGUI = b.helpers.AceGUI
  buildGrid(b)
  buildToolbar(b, AceGUI)
  buildSearch(b, AceGUI)
  buildHint(b, AceGUI)
  buildFooter(b, AceGUI)
  -- Hidden while open (Escape) is a Cancel.
  b.frame:HookScript("OnHide", function() if b.request then b:Cancel() end end)
  facade(b).OnLooksChanged(function() repaint(b) end)
end

-- Hide the browser and drop the request. The request is cleared first, so the frame's own OnHide
-- finds nothing left to cancel.
local function close(b)
  b.request = nil
  putBack(b)
  if GameTooltip then GameTooltip:Hide() end
  if b.w.swatch then releasePicker(b, b.w.swatch) end   -- the picker goes with the browser
  if b.linkWin then b.linkWin:Hide() end                 -- and so does the address
  if b.ctx then b.ctx.panel:Hide() end
  if b.frame then b.frame:Hide() end
  if b.catcher then b.catcher:Hide() end
end

-- ── the surface ─────────────────────────────────────────────────────────────────────────────

local named = {}

-- The browser's global frame name: `spec.name`, else the owner's folder and "IconBrowser", numbered
-- from the second browser an owner builds.
local function frameName(spec)
  if type(spec.name) == "string" and spec.name ~= "" then return spec.name end
  local n = (named[spec.owner] or 0) + 1
  named[spec.owner] = n
  return spec.owner .. "IconBrowser" .. (n > 1 and n or "")
end

--- A browser for one host, built on its first Open. `spec` = { owner (the host's folder: its skin
--- owner and its glyphs' path), title (the window's title: the host's brand), layers ({ strata,
--- level, over, popup? }), helpers (the host's LibKa0s Options instance), tabs (host tab
--- descriptors, shown first), hide ({ markers, game, glyphs } = true to hide), L (the host's
--- overrides of lib.STRINGS), name (the window's global name), print(line), inCombat() -> bool,
--- schedule(sec, fn), copyWindow(d) -> window, trackPicker(swatch),
--- releasePicker(swatch) }. Only `owner` and `helpers` are required.
--- @return table browser
function lib:New(spec)
  if type(spec) ~= "table" or type(spec.owner) ~= "string" or spec.owner == "" then
    error("LibKa0s-IconBrowser-1.0 New: spec.owner, the host's folder, is required", 2)
  end
  if type(spec.helpers) ~= "table" then
    error("LibKa0s-IconBrowser-1.0 New: spec.helpers, the host's Options instance, is required", 2)
  end
  local layers = type(spec.layers) == "table" and spec.layers or {}
  local b = setmetatable({
    spec = spec, owner = spec.owner, L = spec.L, helpers = spec.helpers, name = frameName(spec),
    layers = { strata = layers.strata or "DIALOG", level = layers.level, over = layers.over,
      popup = layers.popup or W().Above(layers.strata or "DIALOG") },
    COLS = COLS, ROWS = ROWS, GRID_TOP = GRID_TOP,
    cells = {}, w = {}, glyphs = {}, footerIcon = {}, lifted = {}, pending = {},
    filter = "all", glyphSet = "all", search = "", list = {}, total = 0, loaded = true, offset = 0,
  }, Browser)
  b.tabs = Src.Tabs(spec)
  b.byKey = {}
  for _, t in ipairs(b.tabs) do b.byKey[t.key] = t end
  b.tab = b.tabs[1] and b.tabs[1].key or nil
  return b
end

--- Open the browser over its opener. `req` = { icon, color (the stored ones), onChoose(icon,
--- color|nil), owner (what Cancel(owner) closes it for), lift (the opener's special-frame names),
--- valid() (false once the opener's member is gone) }. Replaces an open request, as Cancel.
--- Refused while stood down, without AceGUI or with no tab to show.
--- @return boolean opened
function Browser:Open(req)
  if self.request then self:Cancel() end
  if self.down or not self.helpers.AceGUI or not self.tab or type(req) ~= "table" then return false end
  if not self.ctx then build(self) end
  self.request = req
  local homeKey = req.icon ~= nil and Src.TabFor(req.icon, self.tabs) or nil
  -- An icon no tab owns is not selected: no cell could show it selected.
  self.selected = homeKey and req.icon or nil
  self.color = nil
  if lib.IsGlyph(self.selected) and req.color and lib.ValidColor(req.color) then self.color = req.color end
  self.filter, self.glyphSet = "all", "all"
  lift(self, req.lift)
  self.catcher:Show()
  self.frame:Show()
  self.ctx.panel:Show()
  showTab(self, homeKey or self.tabs[1].key, self.selected)
  return true
end

--- Select `icon` (nil clears the selection). It is drawn highlighted and named in the footer.
function Browser:Select(icon)
  if not self.request then return end
  self.selected = icon
  draw(self)
end

--- Show tab `key`, scrolled to the selection when it holds it. A key the host is not offered
--- (a hidden built-in) is refused.
function Browser:SetTab(key)
  if not (self.request and self.byKey[key]) then return end
  showTab(self, key, self.selected)
end

--- The Game icons tab's filter: "all", "spells" or "items".
function Browser:SetFilter(key)
  if not self.request then return end
  if key ~= "all" and key ~= "spells" and key ~= "items" then return end
  self.filter = key
  if self.tab == "game" then showTab(self, "game", self.selected) end
end

--- The Glyphs tab's set filter: "all" or a set's id (Sources.GlyphSets). Kept across tab switches
--- while open; each open starts on "all", so a stored glyph of any set can be shown selected.
function Browser:SetGlyphSet(key)
  if not self.request then return end
  local known = key == "all"
  for _, set in ipairs(Src.GlyphSets(self.L)) do
    if set.id == key then known = true end
  end
  if not known then return end
  self.glyphSet = key
  if self.tab == "glyphs" then showTab(self, "glyphs", self.selected) end
end

--- Search the shown tab for `text` (nil or blank shows it whole), as the search box does as it is
--- typed; from the top. The text is kept for the session, across tabs and opens.
function Browser:SetSearch(value)
  if not self.request then return end
  value = tostring(value or "")
  if value == self.search then return end
  self.search = value
  fill(self, nil)
  drawSearch(self)
  draw(self)
end

--- The glyph color ("rrggbb", or nil for white): every glyph in the grid and the footer is drawn in
--- it. A malformed color is refused.
function Browser:SetColor(hex)
  if not self.request then return end
  if hex ~= nil and not lib.ValidColor(hex) then return end
  self.color = hex or nil
  drawToolbar(self)
  draw(self)
end

--- Scroll the grid to row `row` (0 is the top), as the scrollbar and the mouse wheel do.
function Browser:ScrollTo(row)
  if self.request then setOffset(self, row) end
end

--- Choose the selection: the opener gets the icon and, for a glyph, the color (nil for any other
--- icon, or white), and the browser closes. Refused in combat and with nothing selected; an opener
--- whose `valid` answers false closes the browser instead.
--- @return boolean ok, string|nil reason ("notOpen", "combat", "noSelection")
function Browser:Choose()
  local req = self.request
  if not req then return false, "notOpen" end
  local inCombat = self.spec.inCombat
  if (type(inCombat) == "function" and inCombat()) or (type(inCombat) ~= "function" and InCombatLockdown and InCombatLockdown()) then
    if type(self.spec.print) == "function" then self.spec.print(CHAT_GRAY .. text(self, "COMBAT") .. "|r") end
    return false, "combat"
  end
  if self.selected == nil then return false, "noSelection" end
  if type(req.valid) == "function" and not req.valid() then
    close(self)
    return false, "notOpen"
  end
  local icon = self.selected
  local c = lib.IsGlyph(icon) and self.color or nil
  close(self)
  if type(req.onChoose) == "function" then req.onChoose(icon, c) end
  return true
end

--- Close without choosing. With `owner`, only a browser opened for that owner closes.
function Browser:Cancel(owner)
  if not self.request then return end
  if owner ~= nil and self.request.owner ~= owner then return end
  close(self)
end

--- Close the browser when its opener's `valid` answers false (the host calls this when what the
--- opener edits may have gone: a library change, a deletion).
function Browser:Revalidate()
  local req = self.request
  if req and type(req.valid) == "function" and not req.valid() then close(self) end
end

function Browser:IsOpen()
  return self.request ~= nil
end

--- The host's stand-down: the browser closes and refuses to open until StandUp.
function Browser:StandDown()
  self.down = true
  self:Cancel()
end

function Browser:StandUp()
  self.down = nil
end

--- The copy window the hint's button shows Wowhead's address in, over the browser (`layers.popup`).
--- `spec.copyWindow(d)` when the host passed one, else LibKa0s-Widgets-1.0's CopyWindow. Built on
--- first use; nil without either.
function Browser:LinkWindow()
  if self.linkWin then return self.linkWin end
  local d = { name = self.name .. "LinkWindow", scrollName = self.name .. "LinkScroll",
    title = text(self, "LINK_TITLE"):format(self.spec.title or self.owner), width = 420, height = 120,
    addonName = self.owner, anchorTo = function() return self.frame end }
  local win
  if type(self.spec.copyWindow) == "function" then
    win = self.spec.copyWindow(d)
  else
    local Widgets = LibStub("LibKa0s-Widgets-1.0", true)
    win = Widgets and type(Widgets.CopyWindow) == "function" and Widgets.CopyWindow(d) or nil
  end
  if win and type(win.GetFrame) == "function" then win:GetFrame():SetFrameStrata(self.layers.popup) end
  self.linkWin = win
  return win
end

--- What the browser shows (for tests and diagnostics), or nil while closed.
function Browser:State()
  if not self.request then return nil end
  return { tab = self.tab, filter = self.filter, glyphSet = self.glyphSet, selected = self.selected,
    color = self.color, offset = self.offset, count = #self.list, total = self.total, search = self.search,
    loaded = self.loaded, owner = self.request.owner }
end

--- The toolbar's and the footer's widgets (for tests), nil before the first Open.
function Browser:Widgets()
  if not self.ctx then return nil end
  local w = self.w
  return { filter = w.filter, sets = w.sets, swatch = w.swatch, choose = w.choose, cancel = w.cancel,
    slider = w.slider, grid = w.grid, status = w.status, count = w.count, preview = w.preview,
    previewEdge = self.footerIcon.ibIconEdge, name = w.name, area = w.area, search = w.search,
    clear = w.clear, hint = w.hint, hintText = w.hintText, link = w.link, track = w.track,
    hintFill = w.hintFill, hintEdges = w.hintEdges, magnifier = w.magnifier, clearGlyph = w.clearGlyph }
end
