-- LibKa0s-Widgets-1.0 — WidgetsDropdown: the flat dropdown and the one popup menu every instance of it
-- drops, with its cascading levels, lib.ContextMenu and lib.CloseMenu.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF Widgets.lua ──────────────────────────────────
--
-- Because of `layout-§1`. The cascading menus (Widgets minor 23) and the pixel lines (minor 25) took
-- Widgets.lua to 1312 lines, into the band, and the owner ruled the band files peeled (FU-L2 of
-- Ka0sAddonsCommonTasks docs/2026-11-06-FOLLOWUPS_V1_91). The dropdown and its menu moved here at
-- Widgets minor 26, unchanged: `lib.Dropdown`, `lib.ContextMenu` and `lib.CloseMenu` are the same
-- members with the same descriptors, and their history is Widgets.lua's header. It is NOT a major of
-- its own: it is part of `LibKa0s-Widgets-1.0`, paired on the shell's minor, so a menu from one
-- vendored copy never pairs with a shell from another without saying so.
--
-- WHAT CROSSES THE CUT. Widgets.lua loads first and publishes `lib.__dropdownKit` (the house flat
-- skin, its edge art, the panel opts and the token reader) beside its skin helpers (`lib.__skinOf`,
-- `lib.__panelOff`, `lib.__ownedMark`) and its pixel helpers (`lib.__pixelEdged`, `lib.__pixelLine`).
-- The search box and the mode strip stay in the shell; the strip's right-click reads
-- `lib.ContextMenu` at call time. A payload without this file has no dropdown and no shared menu.
--
-- Depends on LibStub, on the Widgets shell and on LibKa0s-Core-1.0, with the shell's attach floor.

local lib = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
if not lib then return end

local core = LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE or type(lib.__dropdownKit) ~= "table" then return end

local DROPDOWN_MINOR = 1
-- Minor 1: the dropdown and the shared menu, moved here unchanged from Widgets.lua (its minor 26).
-- Paired on the SHELL's minor as well as this file's own, as WidgetsCopyWindow.lua is.
if lib.__dropdownMinor and lib.__dropdownMinor >= DROPDOWN_MINOR
  and lib.__dropdownShellMinor == lib.MINOR then return end
lib.__dropdownMinor      = DROPDOWN_MINOR
lib.__dropdownShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.WidgetsDropdown = DROPDOWN_MINOR

local MAJOR = lib.MAJOR
local kit = lib.__dropdownKit
local SKIN, WHITE, PANEL, token = kit.SKIN, kit.WHITE, kit.PANEL, kit.token
local skinOf, panelOff, ownedMark = lib.__skinOf, lib.__panelOff, lib.__ownedMark
local pixelEdged, pixelLine = lib.__pixelEdged, lib.__pixelLine

-- The rungs below every piece of injected art. Named rather than inlined at the fallback site so
-- that "what does a host with no LibKa0s-Media draw?" is answerable by reading two lines.
local CHEVRON_FALLBACK = "Interface\\Buttons\\Arrow-Down-Up"
local CHECK_FALLBACK   = "Interface\\Buttons\\UI-CheckBox-Check"
-- A submenu row's arrow (minor 23): the client's own menus draw this one beside a row that opens
-- another (wow-ui-source@297d7aa Interface/AddOns/Blizzard_Menu/MenuVariants.lua:36).
local SUBMENU_ARROW    = "Interface\\ChatFrame\\ChatFrameExpandArrow"

local MENU_ROW_H, MENU_DIVIDER_H = 16, 8

-- The shared menu's row colors: selected, plain, the highlight under the pointer, and a title, a
-- disabled row and a divider (minor 21).
local MENU_PAL = { sel = { 1, 0.82, 0 }, text = { 0.9, 0.9, 0.9 }, hover = { 1, 0.82, 0, 0.15 },
                   title = { 1, 0.82, 0 }, off = { 0.5, 0.5, 0.5 }, rule = { 0.24, 0.24, 0.27, 0.85 } }
-- No addon registers this name, so its facade reads Ka0s Default: the menu is given back through it.
local DEFAULT_OWNER = MAJOR

--- True for a row that opens a child menu (minor 23): only a W.ContextMenu's, whose context says so.
local function hasSubmenu(dd, opt)
  return dd.__nest == true and type(opt.submenu) == "table" and #opt.submenu > 0
end

--- True for a row that keeps a tick column (minor 23): a W.ContextMenu row with `radio` or `selected`.
local function tickColumn(dd, opt)
  return dd.__tick ~= nil and (opt.radio == true or opt.selected ~= nil)
end

--- A tick-column row's state: `selected`, true or a predicate of the row, read on every paint.
local function rowTicked(opt)
  if type(opt.selected) == "function" then return opt.selected(opt) and true or false end
  return opt.selected == true
end

-- Never narrower than the button it drops from, but grown to the widest label it must show:
-- a class icon plus a Name-Realm outruns the 140px Character button. Measured with a spare
-- FontString in the row font (inline icon markup counts toward GetStringWidth), + the 8px
-- insets, the tick markup and a little slack; capped so one freak label can't fill the screen.
local function menuWidth(menu, dd, opts)
  local w = math.max(dd:GetWidth(), 90)
  if not menu.measure then
    menu.measure = menu:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    menu.measure:Hide()
  end
  -- Minor 17: measured in the face the rows wear, else a long label in a wider face truncates.
  lib.__skinFont(menu.measure, menu.__fontOwner, menu.__fontSkin, "GameFontHighlightSmall")
  for _, opt in ipairs(opts) do
    menu.measure:SetText((dd.multi and dd.__check or "") .. (opt.label or ""))
    -- A glyphed or ticked row indents its text by a further 14px, a submenu row's arrow takes 10.
    local pad = (opt.glyph or tickColumn(dd, opt)) and 38 or 24
    if hasSubmenu(dd, opt) then pad = pad + 10 end
    w = math.max(w, math.min(320, (menu.measure:GetStringWidth() or 0) + pad))
  end
  return w
end

-- One pooled row button. Only ever built for an index that has none: every dropdown after the first
-- reuses these, which is why paintMenuRow repaints every last field of one.
local function makeMenuRow(menu)
  local b = CreateFrame("Button", nil, menu)
  b:SetHeight(MENU_ROW_H)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("RIGHT", -8, 0)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)   -- a long label truncates on its row; it never wraps into the next
  b.fs = fs
  -- Optional leading glyph (the direction ▲/▼). A separate FontString in the MONO face the host
  -- named as `opts.glyphFont` — because the row font has no such glyph, and because which mono face
  -- a host draws in is the host's decision, not this library's (see the header). It stays a
  -- CHARACTER and does not become a mark: it takes its color from the same SetTextColor the label
  -- uses. The FACE is re-set on every paint — see the comment in paintMenuRow.
  --
  -- BUILT FROM A TEMPLATE, and it must be. A FontString created bare has no font, and the client
  -- answers `FontString:SetText(): Font not set` on the very next call — which paintMenuRow makes
  -- unconditionally, for every row, glyphed or not. The template is only ever a floor: a host that
  -- named a face overwrites it on each paint, and a host that named none draws nothing here anyway
  -- because the glyph is hidden. It exists so that the SetText below can never be the first thing
  -- this FontString hears.
  local gl = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gl:SetPoint("LEFT", 8, 0)
  gl:SetWidth(12)
  gl:SetJustifyH("CENTER")
  b.glyph = gl
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.82, 0, 0.15)
  -- Minor 16: kept, with the color it wears, so a skinned open repaints it (Populate).
  b.__hl, b.__hlc = hl, MENU_PAL.hover
  -- A divider row's line (minor 21), 4 down its 8. One physical pixel high (minor 25), sized on
  -- each paint (paintRowKind), where it was one UI unit, BOTTOMRIGHT -8, 3.
  b.__rule = b:CreateTexture(nil, "ARTWORK")
  b.__rule:SetPoint("TOPLEFT", 8, -4)
  b.__rule:SetPoint("TOPRIGHT", -8, -4)
  return b
end

--- A row's tick column (minor 23), the menu's check markup in a string of its own, so a radio wears
--- the multi-select tick. Built the first time a row needs one, from a template for the reason the
--- glyph is: a flat menu's rows never carry it.
local function rowTick(b)
  if b.__tick then return b.__tick end
  local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t:SetPoint("LEFT", 6, 0)
  t:SetWidth(16)
  t:SetJustifyH("CENTER")
  b.__tick = t
  return t
end

--- A submenu row's arrow (minor 23), built the first time a row needs one.
local function rowArrow(b)
  if b.__sub then return b.__sub end
  local a = b:CreateTexture(nil, "OVERLAY")
  a:SetSize(10, 10)
  a:SetPoint("RIGHT", -4, 0)
  a:SetTexture(SUBMENU_ARROW)
  a:SetVertexColor(0.7, 0.7, 0.72)
  b.__sub = a
  return a
end

--- True for a row that takes no click: a title, a divider, or a disabled row (`disabled`, true or a
--- predicate of the dropdown, read on every open).
local function rowInert(dd, opt)
  if opt.title or opt.divider then return true end
  if type(opt.disabled) == "function" then return opt.disabled(dd) and true or false end
  return opt.disabled == true
end

-- Selection state: single-select highlights the one active value; multi-select highlights
-- every value in the set (and highlights "all" when the set is empty = no filter).
--
-- An option may override both of those with its own `isActive(dd)` predicate, and a PRESET ROW has
-- to. A preset is a row whose value is not one of the values it selects — "Character: Current"
-- picks the current player's key, "all" picks nothing — so neither `_selected[opt.value]` nor
-- `opt.value == _value` can ever be true of it, and without a predicate such a row is the one row
-- in the menu that can never light up even when it is exactly what the dropdown is showing. The
-- predicate is asked FIRST and its answer is final: an option that carries one is describing a
-- state the value set alone does not express.
local function rowSelected(dd, opt)
  if opt.isActive then return opt.isActive(dd) and true or false end
  if dd.multi then
    return (opt.value == "all") and (not next(dd._selected)) or (dd._selected[opt.value] or false)
  end
  return (opt.value == dd._value)
end

--- The glyph column's face (minor 19): the opener's `font.mono`, else the host's. Nil when the host
--- named none: that is what asks for a column at all, in every skin.
local function menuGlyphFace(menu, dd)
  local host, Skin, owner = dd.__glyphFont, menu.__fontSkin, menu.__fontOwner
  if not (host and Skin) then return host end
  local _, noFonts = Skin:GetIgnore(owner)
  if noFonts then return host end
  return Skin:For(owner).GetFont("mono") or host
end

--- A row's label color: a title's, a disabled row's, the selection's, the value's own, or plain.
local function rowColor(dd, opt, selected, pal)
  if opt.title then return pal.title end
  if rowInert(dd, opt) then return pal.off end
  if selected then return pal.sel end
  return opt.color or pal.text
end

--- A row's shape and tooltip (minor 21), every field written for the pool's sake, as below. An inert
--- row takes the mouse too: the menu has none of its own and `__OutsideClick` exempts a press by
--- geometry, so a press let through keeps the menu open and lands on whatever is under it. `hover`
--- (minor 23) is a cascading level's pointer handler, nil on a flat menu, which keeps no OnEnter.
local function paintRowKind(b, dd, opt, pal, hover)
  local tip = opt.tooltip
  b:SetHeight(opt.divider and MENU_DIVIDER_H or MENU_ROW_H)
  b.__rule:SetShown(opt.divider == true)
  if opt.divider then
    b.__rule:SetColorTexture(pal.rule[1], pal.rule[2], pal.rule[3], pal.rule[4])
    pixelLine(b.__rule, b, true)
  end
  b.__hl:SetShown(not rowInert(dd, opt))
  b:EnableMouse(true)
  if hover then
    b:SetScript("OnEnter", function(self)
      hover(self)
      if tip then lib.__rowTip(self, opt, pal) end
    end)
  else
    b:SetScript("OnEnter", tip and function(self) lib.__rowTip(self, opt, pal) end or nil)
  end
  b:SetScript("OnLeave", tip and function() lib.__rowTipOff() end or nil)
end

--- A row's tick column and submenu arrow (minor 23), and the label's two insets around them. Each is
--- written whenever the row has one, for the pool's sake.
local function paintRowMarks(b, dd, opt)
  local col, sub = tickColumn(dd, opt), hasSubmenu(dd, opt)
  if col or b.__tick then
    local t = rowTick(b)
    t:SetText(col and rowTicked(opt) and dd.__tick or "")
    t:SetShown(col)
  end
  if sub or b.__sub then rowArrow(b):SetShown(sub) end
  -- A glyphed or ticked row indents its text to clear the column; every other row starts at the margin.
  b.fs:ClearAllPoints()
  b.fs:SetPoint("LEFT", (opt.glyph or col) and 22 or 8, 0)
  b.fs:SetPoint("RIGHT", sub and -18 or -8, 0)
end

-- Repaint one row from its option. EVERY field is written on every pass, including the blank ones:
-- the rows are pooled across dropdowns, so a field left alone leaks the previous menu's glyph or
-- color onto this one.
local function paintMenuRow(b, dd, opt, selected, pal, glyphFace, hover)
  local check = (dd.multi and selected) and dd.__check or ""
  paintRowKind(b, dd, opt, pal, hover)
  b.fs:SetText(check .. (opt.label or ""))
  paintRowMarks(b, dd, opt)
  -- FONT SET ON EVERY PAINT, not once at creation, and that is the one thing this widget does
  -- differently from the version it was lifted out of. The row pool is shared across every dropdown
  -- in the process, which now spans addons — and two hosts need not name the same monospace face.
  -- A font set at creation would be whichever host opened a dropdown first.
  --
  -- A host that passes no face gets no glyph column: SetFont with a nil path raises, and a glyph
  -- drawn in the row's own proportional face is a box, which is the failure this widget's whole
  -- family of comments is about. The column is DROPPED, not crashed into — the SetText a line
  -- below runs on every row whether or not this branch did, which is why makeMenuRow builds the
  -- glyph from a font template.
  if glyphFace and opt.glyph then
    b.glyph:SetFont(glyphFace, 11, "")
  end
  b.glyph:SetText(opt.glyph or "")
  b.glyph:SetShown(opt.glyph ~= nil and glyphFace ~= nil)
  -- The selected row goes gold to mark the selection; otherwise the value keeps its own color
  -- (store / direction / class), so the menu reads like the column it filters. The glyph always
  -- keeps the direction's color — it IS the value, not a selection state.
  local c = rowColor(dd, opt, selected, pal)
  b.fs:SetTextColor(c[1], c[2], c[3])
  -- The highlight only when the menu's colors changed since this row last wore them.
  if b.__hl and b.__hlc ~= pal.hover then
    b.__hl:SetColorTexture(pal.hover[1], pal.hover[2], pal.hover[3], pal.hover[4])
    b.__hlc = pal.hover
  end
  if opt.color then b.glyph:SetTextColor(opt.color[1], opt.color[2], opt.color[3]) end
end

--- A row's tooltip: a string, or the host's renderer `fn(rowFrame, opt)`, on GameTooltip either way.
function lib.__rowTip(row, opt, pal)
  if type(GameTooltip) ~= "table" then return end
  lib.__tipUp = true
  if type(opt.tooltip) == "function" then return opt.tooltip(row, opt) end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(tostring(opt.tooltip), pal.text[1], pal.text[2], pal.text[3], 1, true)
  GameTooltip:Show()
end

function lib.__rowTipOff()
  if lib.__tipUp and type(GameTooltip) == "table" then GameTooltip:Hide() end
  lib.__tipUp = nil
end

-- The menu frames, one per depth (minor 23). `menus[1]` is the shared menu every dropdown and every
-- W.ContextMenu opens, `menu` below; a deeper one is a cascading level, pooled like the rows.
local menus = {}
local menu

--- Hide every level from `depth` down. A level's OnHide does the same in the client; this walk is
--- for a level closed while its parent stays (a sibling submenu, a hovered plain row) and for CloseMenu.
local function closeFrom(depth)
  for d = depth, #menus do
    if menus[d]:IsShown() then menus[d]:Hide() end
  end
end

--- After a keepOpen row's callback (minor 23): repaint its level and every level above it, each only
--- while it is still shown and still wears the context it was opened with.
local function repaintChain(frame, dd)
  while frame and dd do
    if not (frame:IsShown() and frame.__dd == dd) then return end
    frame:Populate(dd)
    frame, dd = frame.__up, dd.__parent
  end
end

-- One row's click handler. The menu hides BEFORE the callback, which is contract (minor 21): a
-- callback may open another menu, and hiding after it would close that one. `keepOpen` holds the menu
-- and repaints it after the callback, so a toggle row shows its new state, unless that callback closed
-- the menu or opened another: the shared frame's rows then belong to someone else. From minor 23 a
-- pick in a cascading level hides every level, and a keepOpen one repaints every level above it too.
local function rowOnClick(frame, dd, opt)
  return function()
    if dd.multi then
      -- Toggle in place and keep the menu open, so several can be picked in one visit.
      dd:ToggleSelected(opt.value)
      frame:Populate(dd)
      if dd.onMultiSelect then dd.onMultiSelect(dd._selected) end
      return
    end
    dd:SetValue(opt.value, opt.label)
    if not opt.keepOpen then closeFrom(1) end
    if dd.onSelect then dd.onSelect(opt.value, opt) end
    if opt.keepOpen then repaintChain(frame, dd) end
  end
end

--- Repaint the shared menu for the dropdown opening it (minor 16): its owner's skin when it has a
--- registered one, else Ka0s Default once an owner has painted it. An owner-less open of a menu no
--- owner ever painted touches nothing. A panel-scoped dropdown whose owner ignores its settings
--- panel opens it as an owner-less one (minor 17); the rows' face is the opener's (Populate).
local function skinMenu(m, dd)
  local owner = dd.__owner
  local Skin = skinOf(owner)
  if panelOff(Skin, owner, dd.__panel) then Skin = nil end
  m.__fontSkin, m.__fontOwner = Skin, Skin and owner or nil
  if Skin then
    if type(Skin.__MarkShared) == "function" then Skin:__MarkShared(m) end
    Skin:For(owner).MenuFrame(m)
    m.__pal = { sel = token(Skin, owner, "menu.textSel", MENU_PAL.sel),
                text = token(Skin, owner, "menu.text", MENU_PAL.text),
                hover = token(Skin, owner, "menu.hover", MENU_PAL.hover),
                title = token(Skin, owner, "menu.textSel", MENU_PAL.title),
                off = token(Skin, owner, "text.disabled", MENU_PAL.off),
                rule = token(Skin, owner, "divider", MENU_PAL.rule) }
    return
  end
  if not m.__pal then return end
  m.__pal = nil
  Skin = LibStub("LibKa0s-Skin-1.0", true)
  if Skin and type(Skin.For) == "function" then Skin:For(DEFAULT_OWNER).MenuFrame(m) end
end

local function noop() end

--- A W.ContextMenu's context (minor 21), or a cascading level's (minor 23, `parent` the level above):
--- what Populate reads off a dropdown, for rows a host passed. `tick` is the tick column's markup.
local function menuContext(rows, opts, parent, tick)
  local ctx = { _options = rows, _selected = {}, __check = "", __owner = opts.owner, __panel = opts.panel == true,
                __glyphFont = opts.glyphFont, __tick = tick, __nest = true, __parent = parent, SetValue = noop }
  ctx._value = ctx   -- no row's value: a row with none is not the selection (rowSelected)
  local width = tonumber(opts.width) or 90
  function ctx.GetWidth() return width end
  function ctx.onSelect(value, row)
    if type(row.onClick) == "function" then row.onClick(value, row) end
  end
  return ctx
end

--- Place level `c` beside `row`: to its right, its first row level with the row, or to its left when
--- the right would leave the screen; clamped either way. A rect not resolved yet (nil) goes right.
local function placeBeside(c, row)
  local right, edge, w = row:GetRight(), UIParent:GetRight(), c:GetWidth()
  if type(right) == "number" and type(edge) == "number" and type(w) == "number" and right + w > edge then
    c:SetPoint("TOPRIGHT", row, "TOPLEFT", 0, 4)
  else
    c:SetPoint("TOPLEFT", row, "TOPRIGHT", 0, 4)
  end
  c:SetClampedToScreen(true)
end

local EnsureMenu

--- Open `opt.submenu` as the level below `parent` (minor 23), beside `row`. The level already showing
--- exactly that is left alone; any other at that depth or deeper closes first, so opening a sibling's
--- submenu closes the levels under the last one.
local function openSub(parent, dd, row, opt)
  local depth = parent.__depth + 1
  local c = menus[depth]
  if c and c:IsShown() and c.__row == row and c.__src == opt then return end
  closeFrom(depth)
  c = EnsureMenu(depth)
  local ctx = menuContext(opt.submenu, { owner = dd.__owner, panel = dd.__panel, glyphFont = dd.__glyphFont },
    dd, dd.__tick)
  c.__dd, c.__up, c.__row, c.__src = ctx, parent, row, opt
  parent.__child = c
  skinMenu(c, ctx)
  local level = parent:GetFrameLevel()
  if type(level) == "number" then c:SetFrameLevel(level + 10) end
  c:Populate(ctx)
  c:ClearAllPoints()
  placeBeside(c, row)
  c:Show()
end

--- A cascading level's pointer handler for one row (minor 23): a live submenu row opens its level,
--- any other closes the levels below its own.
local function rowHover(frame, dd, opt)
  if hasSubmenu(dd, opt) and not rowInert(dd, opt) then
    return function(row) openSub(frame, dd, row, opt) end
  end
  return function() closeFrom(frame.__depth + 1) end
end

--- One row's click: none for an inert row, its level for a submenu row (minor 23), else the pick.
local function rowClick(frame, dd, opt)
  if rowInert(dd, opt) then return nil end
  if hasSubmenu(dd, opt) then return function(row) openSub(frame, dd, row, opt) end end
  return rowOnClick(frame, dd, opt)
end

--- True when a row of `dd` opens a level: only then do its rows answer the pointer, so a flat menu's
--- rows keep no OnEnter but a tooltip's.
local function levelNests(dd)
  if not dd.__nest then return false end
  for _, opt in ipairs(dd._options or {}) do
    if hasSubmenu(dd, opt) then return true end
  end
  return false
end

--- Lay out a level's rows for `dd` (a dropdown, or a W.ContextMenu's context).
local function populate(self, dd)
  for _, b in ipairs(self.buttons) do b:Hide() end
  local opts = dd._options or {}
  local w = menuWidth(self, dd, opts)
  local glyphFace = menuGlyphFace(self, dd)
  local nests = levelNests(dd)
  local y = 4
  for i, opt in ipairs(opts) do
    local b = self.buttons[i]
    if not b then
      b = makeMenuRow(self)
      self.buttons[i] = b
    end
    -- Minor 17: the opener's face on every open, or the template back; the rows are pooled.
    lib.__skinFont(b.fs, self.__fontOwner, self.__fontSkin, "GameFontHighlightSmall")
    b:SetWidth(w)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 0, -y)
    y = y + (opt.divider and MENU_DIVIDER_H or MENU_ROW_H)
    paintMenuRow(b, dd, opt, rowSelected(dd, opt), self.__pal or MENU_PAL, glyphFace,
      nests and rowHover(self, dd, opt) or nil)
    b:SetScript("OnClick", rowClick(self, dd, opt))
    b:Show()
  end
  self:SetSize(w, y + 4)
end

--- A level closing takes the levels below it, and any row tooltip, with it.
local function levelOnHide(self)
  self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
  lib.__rowTipOff()
  closeFrom(self.__depth + 1)
end

--- One menu frame for `depth`: the shared menu at depth 1, a cascading level below it (minor 23).
local function newMenuFrame(depth)
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  -- Minor 15: a dropdown near the bottom or right edge would otherwise drop rows off the screen.
  f:SetClampedToScreen(true)
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  f:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
  f:SetBackdropBorderColor(0, 0, 0, 1)
  pixelEdged(f)
  f:Hide()
  f.buttons, f.__depth = {}, depth
  f:SetScript("OnHide", levelOnHide)
  f.Populate = populate
  return f
end

--- The menu frame for `depth` (1 when nil), built the first time it is asked for. Only depth 1 listens
--- for the outside press, and it answers for every level.
EnsureMenu = function(depth)
  depth = depth or 1
  if menus[depth] then return menus[depth] end
  local f = newMenuFrame(depth)
  menus[depth] = f
  if depth > 1 then return f end
  menu = f

  -- ── HOW AN OUTSIDE CLICK CLOSES THIS, AND WHY IT IS NOT A CATCHER ──────────────────────────
  --
  -- Through minor 4 this was a full-screen `Button` at FULLSCREEN strata whose OnClick hid it. That
  -- frame INTERCEPTED the click, and intercepting was the defect: it swallowed a right-click whole,
  -- and dismissing the menu cost a left-click that did nothing else.
  --
  -- So the menu no longer intercepts anything. It LISTENS: `GLOBAL_MOUSE_DOWN` fires for a press
  -- anywhere in the UI, on any button, whether or not something else consumed it — so the menu can
  -- react to a click it never touched, and the click goes on to reach whatever is under the cursor.
  -- One press now both dismisses the menu and does the thing the player pressed on.
  --
  -- Registered while shown and dropped on hide, rather than for the life of the process: a handler
  -- that would otherwise run on every mouse press for the session, in every host.
  -- The button that was pressed arrives as the next argument and is deliberately not read: no
  -- button is enumerated anywhere in this widget, so a mouse with more of them behaves the same.
  f:SetScript("OnEvent", function(self, event)
    if event == "GLOBAL_MOUSE_DOWN" then self:__OutsideClick() end
  end)

  -- Two presses are NOT outside, and both exemptions are load-bearing:
  --
  --   * On the menu — otherwise the menu would close under the player's own row click, on the
  --     press, before the release the row's OnClick needs.
  --   * On the dropdown that dropped it — that button's own OnClick is the toggle. Close on the
  --     press and the release finds the menu hidden and re-opens it, and the menu becomes
  --     impossible to close by the button that opened it. Only the OWNER is exempt: a press on a
  --     different dropdown closes this menu, and that dropdown's OnClick then opens its own, which
  --     is how exactly one menu stays open across the process.
  --
  -- From minor 23 a press on ANY shown level is on the menu, and an outside press closes them all.
  function f:__OutsideClick()
    for _, level in ipairs(menus) do
      if level:IsShown() and level:IsMouseOver() then return end
    end
    local owner = self._owner
    if owner and owner.IsMouseOver and owner:IsMouseOver() then return end
    closeFrom(1)
  end
  return f
end

--- Open the shared menu for `dd`, placed by `place(menu)`, as `owner`'s: a press on `owner` is no
--- outside press. The levels of a cascade the menu wore close first (minor 23).
local function openMenu(owner, dd, place)
  local m = EnsureMenu()
  closeFrom(2)
  m._owner, m.__dd = owner, dd
  skinMenu(m, dd)
  m:Populate(dd)
  m:ClearAllPoints()
  place(m)
  m:Show()
  m:RegisterEvent("GLOBAL_MOUSE_DOWN")
  return m
end

local function placeAtCursor(m)
  local x, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  if type(scale) ~= "number" or scale <= 0 then scale = 1 end
  m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end

-- A preset row that reports itself active NAMES THE WHOLE SELECTION, so its label is the collapsed
-- button's label and the count below is never consulted. Asked first because the label has to hold
-- even when the selected value has no option row at all: option lists are usually data-driven, and
-- a value that has dropped out of the data would otherwise fall the button back to "All" while the
-- filter is still on.
local function activePresetLabel(dd)
  for _, o in ipairs(dd._options or {}) do
    if o.isActive and o.isActive(dd) then return o.label end
  end
  return nil
end

-- Label every selected value: from its option row when there is one, else the raw value. A
-- selection whose row is not in the CURRENT option list still counts and still reads sensibly —
-- which is the whole difference from walking the options and asking which are selected, the shape
-- this had through minor 3. A filter that is on must never summarize as "All".
local function selectionLabels(dd)
  local labels = {}
  for k in pairs(dd._selected or {}) do labels[k] = tostring(k) end
  for _, o in ipairs(dd._options or {}) do
    if o.value ~= "all" and labels[o.value] ~= nil then labels[o.value] = o.label end
  end
  return labels
end

-- The collapsed text for a labeled selection.
local function summarizeSelection(labels, allLabel)
  local n, firstLabel
  for _, lbl in pairs(labels) do
    n = (n or 0) + 1
    firstLabel = firstLabel or lbl
  end
  if not n then return allLabel end
  if n == 1 then return firstLabel end
  return (allLabel:match("^(.-):") or allLabel) .. ": " .. n .. " selected"
end

--- The "all" sentinel's label, else the first row that is a value: a title or a divider, which may
--- stand first (minor 21), names nothing.
local function allRowLabel(dd)
  local first
  for _, o in ipairs(dd._options or {}) do
    if o.value == "all" then return o.label or "All" end
    if first == nil and not (o.title or o.divider) then first = o.label end
  end
  return first or "All"
end

--- The tick markup a multi-select row leads with (see MakeDropdown): the host's art, an owned
--- dropdown's Ka0s `confirm` in `icon.hot` (minor 18), else the client rung.
local function dropdownCheck(opts)
  local art = not opts.check and ownedMark(opts.owner, "confirm", opts.panel)
  if art then return skinOf(opts.owner):For(opts.owner).MarkText(art, 0, "icon.hot") .. " " end
  return "|T" .. (opts.check or CHECK_FALLBACK) .. ":0|t "
end

--- The arrow's art: the host's, an owned dropdown's Ka0s `chevron-down` (minor 18), else the client
--- rung.
local function dropdownArrow(opts)
  return opts.chevron or ownedMark(opts.owner, "chevron-down", opts.panel) or CHEVRON_FALLBACK
end

--- An owned dropdown's marks again after its skin changed (minor 20): the tick holds its tint as
--- text, and the Scope swaps both marks for the client's. The menu reads `__check` on every open.
local function redressDropdown(dd)
  dd.__check = dropdownCheck(dd.__markOpts)
  dd.arrow:SetTexture(dropdownArrow(dd.__markOpts))
end

-- A dropdown button: shows the current label plus a ▼ texture; clicking opens the shared menu.
local function MakeDropdown(parent, width, opts)
  opts = opts or {}
  local dd = CreateFrame("Button", nil, parent, "BackdropTemplate")
  dd:SetSize(width, SKIN.height)
  dd:SetBackdrop({ bgFile = SKIN.edge, edgeFile = SKIN.edge, edgeSize = 1,
                   insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  dd:SetBackdropColor(unpack(SKIN.fill))
  dd:SetBackdropBorderColor(unpack(SKIN.line))
  pixelEdged(dd)

  -- The tick a multi-select dropdown puts in front of every chosen row. INLINE |T…|t markup,
  -- resolved per dropdown so a degraded install appends the Blizzard string it always did rather
  -- than concatenating a nil into an escape. An owned one is resolved again on a skin change
  -- (redressDropdown, minor 20).
  --
  -- PER-DROPDOWN, not a file-local, and that is the difference from the version this was lifted
  -- out of: one popup menu is shared by every dropdown in the process, and that process now spans
  -- addons which need not agree on their art. paintMenuRow and menuWidth both read it off the
  -- dropdown they are handed rather than off an upvalue, for exactly that reason.
  --
  -- It is a MARK, and it has to be: the button this menu drops from wears the host's chevron, and
  -- Blizzard's beveled tick on the rows below it would be the one place where two eras of art meet
  -- inside a single widget. The trailing space is the gap to the label; the path stays as the host
  -- resolved it, EXTENSIONLESS or not.
  dd.__check = dropdownCheck(opts)
  -- The mono face the optional row glyph is drawn in, read by paintMenuRow on every pass. Absent
  -- means the host wants no glyph column at all.
  dd.__glyphFont = opts.glyphFont

  local fs = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", 6, 0)
  fs:SetPoint("RIGHT", -16, 0)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)   -- minor 21: a long pick truncates; it never wraps past the button's edge
  dd.text = fs

  -- The ▼ affordance. It is a texture rather than a character because the ▼ glyph is not in the
  -- default WoW font and renders as a box — and it is the host's `chevron-down` mark when the host
  -- has one, with Blizzard's own arrow kept as the rung below it. The vertex color is set here and
  -- not by the host, which is what makes shared white art wear this widget's gray rather than its
  -- own.
  local arrow = dd:CreateTexture(nil, "OVERLAY")
  arrow:SetSize(12, 12)
  arrow:SetPoint("RIGHT", -4, 0)
  arrow:SetTexture(dropdownArrow(opts))
  arrow:SetVertexColor(0.7, 0.7, 0.72)
  dd.arrow = arrow   -- kept for the out-of-game art suite; nothing at runtime reads it back

  dd._selected = {}   -- multi-select value set (empty = "All"); only used when dd.multi is true
  function dd:SetOptions(o)
    self._options = o
    if self.multi then self:UpdateMultiLabel() end
  end
  function dd:SetValue(v, label) self._value = v; self.text:SetText(label or "") end
  function dd:SelectValue(v)
    for _, o in ipairs(self._options or {}) do
      if o.value == v then self:SetValue(o.value, o.label); return end
    end
    self:SetValue(v, tostring(v))
  end

  function dd:SetMulti(on) self.multi = on and true or false end
  function dd:SetSelected(set)
    local s = {}
    if type(set) == "table" then for k, on in pairs(set) do if on then s[k] = true end end end
    self._selected = s
    self:UpdateMultiLabel()
  end
  -- `dd.presets` (optional, set by the host: { [value] = function(dd) end }) lets specific option
  -- values REPLACE the selection instead of toggling into it — a one-click "only me". The handler
  -- owns `dd._selected` outright and is responsible for writing it; UpdateMultiLabel runs after it
  -- either way. It is asked before the "all" sentinel so a host may override even that, and it is a
  -- plain field on the dropdown rather than a constructor option because the closure it carries
  -- usually needs the dropdown the host is still in the middle of building.
  function dd:ToggleSelected(value)
    local preset = self.presets and self.presets[value]
    if preset then
      preset(self)
    elseif value == "all" then
      self._selected = {}
    else
      self._selected[value] = (not self._selected[value]) or nil
    end
    self:UpdateMultiLabel()
  end
  -- Collapsed-button summary: an active preset's own label when one reports itself active, else the
  -- "All" label when nothing is picked, the single selection's label when one is, else
  -- "<Prefix>: N selected" (the prefix comes from the "all" sentinel's label).
  function dd:UpdateMultiLabel()
    local preset = activePresetLabel(self)
    if preset then self.text:SetText(preset); return end
    self.text:SetText(summarizeSelection(selectionLabels(self), allRowLabel(self)))
  end

  dd:SetScript("OnClick", function(self2)
    local m = EnsureMenu()
    if m:IsShown() and m._owner == self2 then m:Hide(); return end
    openMenu(self2, self2, function(menuFrame) menuFrame:SetPoint("TOPLEFT", self2, "BOTTOMLEFT", 0, -1) end)
  end)
  -- Minor 16: the skin owner, read by skinMenu on every open; its button wears the owner's skin.
  -- Minor 17: `opts.panel`, a dropdown on its owner's settings page (the header's SCOPE SWITCHES).
  dd.__owner = opts.owner
  dd.__panel = opts.panel == true
  local Skin = skinOf(opts.owner)
  if Skin then
    Skin:For(opts.owner).Dropdown(dd, dd.__panel and PANEL or nil)
    dd.__markOpts = opts
    lib.__onSkin(Skin, opts.owner, dd, redressDropdown)
  end
  return dd
end

--- Build a flat-skin dropdown button that drops the shared popup menu.
---
--- @param parent table         the frame to parent it to
--- @param width number         the collapsed button's width; the menu never drops narrower
--- @param opts table|nil       { chevron =, check =, glyphFont = }, each a resolved path or nil;
---                             `owner` (minor 16), a registered skin owner: the button and the menu
---                             it drops wear that owner's skin (the header's SKIN OWNERS), the
---                             menu's rows in its body face from minor 17; `panel` (minor 17), true
---                             for a dropdown on the owner's settings page (THE SCOPE SWITCHES)
--- @return table  the dropdown
function lib.Dropdown(parent, width, opts)
  return MakeDropdown(parent, width, opts)
end

--- Open the shared popup menu on `rows` (minor 21), a dropdown's options, each with its row options
--- (`title`, `divider`, `disabled`, `tooltip`, `keepOpen`; minor 23: `submenu`, `radio`, `selected`)
--- and `onClick(value, row)`, from `anchor`, a press on which is no outside press. A second call on it
--- closes the menu, as a dropdown's second click does, unless `opts.cursor` opens at the pointer.
--- `opts`: { owner, panel, glyphFont, width, cursor, check }. Answers the menu, or nil with no anchor
--- or no rows. docs/api/Widgets has the table.
function lib.ContextMenu(anchor, rows, opts)
  if type(anchor) ~= "table" or type(rows) ~= "table" or #rows == 0 then return nil end
  opts = type(opts) == "table" and opts or {}
  local m = EnsureMenu()
  if m:IsShown() and m._owner == anchor and not opts.cursor then
    closeFrom(1)
    return m
  end
  local ctx = menuContext(rows, opts, nil, dropdownCheck(opts))
  return openMenu(anchor, ctx, opts.cursor and placeAtCursor or function(frame)
    frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -1)
  end)
end

--- Close the shared popup menu, if it is open. Safe to call when no dropdown has ever opened the
--- menu (menu is still nil) and safe to call when the menu is already hidden — both are plain
--- no-ops.
---
--- A HOST CANNOT DO THIS ITSELF: the popup is a process-wide singleton parented to `UIParent` at
--- `FULLSCREEN_DIALOG` (EnsureMenu), so it outlives every window that opened it and no host's own
--- Hide reaches it. The menu's own `OnHide` drops its `GLOBAL_MOUSE_DOWN` registration.
---
--- A host that closes its window by any route that is not a mouse press (Escape, a slash command)
--- leaves the menu ORPHANED, floating over the game with no owner to hide it, so it calls this from
--- every such path. The outside-press close (minor 5) cannot help: no click happened.
function lib.CloseMenu()
  if menu and menu:IsShown() then menu:Hide() end
  closeFrom(2)   -- minor 23: every cascading level, which OnHide closes too in the client
end
