-- LibKa0s-Widgets-1.0 — the collection's flat dropdown, the one popup menu every instance of it
-- drops, the flat search box a filter bar puts beside it, and the mode strip (test mode or a
-- simulation) a window lays over data that is not the player's (minor 15).
--
-- ── WHY THIS IS A LIBRARY AND NOT A COPY ──────────────────────────────────────────────────────
--
-- It was BankLedger's, local to modules/Browser.lua, and it was about to be MultiMeters' too. Two
-- copies of a widget is two skins to keep in step, and the collection stops looking like one
-- author's work the first time one copy is restyled and the other is not. That is the argument the
-- icons were consolidated under at v1.9.0; a widget that DRAWS those icons is the same argument one
-- layer up.
--
-- The test-mode strip (`lib.TestStrip`, #48) is here for the same reason. DropWatcher drew it, and
-- LootHistory, BankLedger and MultiMeters each marked test mode their own way: a red title-bar
-- word in two of them and a title suffix in the third, which a hidden header hides with it. The
-- owner's 2026-10-22 ruling promoted DropWatcher's strip so all four say "this is not your data"
-- with one band, in one color, at one height.
--
-- The same strip marks a simulation (`opts.kind = "sim"`, minor 14): a flavor of `TestStrip`, with
-- its own cyan tint, and not a new function. The owner's 2026-10-23 ruling asked for the strip to
-- be made generic so a simulation is marked the way test mode is. A `ModeStrip` constructor with
-- `TestStrip` kept as an alias was REJECTED: it is a second name for one function, a member added
-- purely for naming, and the four existing hosts would keep calling `TestStrip` anyway. Re-check
-- trigger: a third kind is asked for.
--
-- ── WHY IT DOES NOT DEPEND ON LibKa0s-Media-1.0 ───────────────────────────────────────────────
--
-- Because it cannot. `Media.Icon` takes the CONSUMING ADDON'S NAME to build a path, and this file
-- is vendored — every consumer has its own copy at its own path, and a copy cannot know which addon
-- folder it was copied into. So every piece of art arrives as a parameter: `opts.chevron` and
-- `opts.check` are resolved paths, and each falls to the Blizzard texture the host had before the
-- collection shipped art of its own. A host with no LibKa0s-Media still gets a working dropdown.
--
-- Same reasoning for `opts.glyphFont`: the optional leading glyph is a CHARACTER in a monospace
-- face, and which face is the host's decision.
--
-- ── WHAT IT DELIBERATELY IS NOT ───────────────────────────────────────────────────────────────
--
-- The dropdown's menu has no search box inside it (the filter bar's search box beside it is
-- `lib.SearchBox`, below), no keyboard navigation, no scrolling for a long list, no sub-menus, no
-- per-row disable. None of those is wanted by either shipped consumer, and every one of them is
-- reachable later without a major bump. A widget that grows features nobody asked for is a widget
-- whose degraded behavior nobody has tested.
--
-- Two flat controls were censused with the search box at minor 13 (#52) and REJECTED:
--
--   * `W.Checkbox`, a flat checkbox. No consumer draws one today. Re-check trigger: a second addon
--     hand-builds a flat checkbox.
--   * An exported flat skin (the `SKIN` table below, or an applier that paints it). It stays
--     file-local: the dropdown and the search box are its only readers, and the autocomplete
--     publishes its own copy as `AUTOCOMPLETE.BORDER` / `.BG`. Re-check trigger: a third flat
--     control outside this file copies the literals.
--
-- The test-mode strip is a band, a mark and a line of text, and deliberately nothing more. It has
-- no tooltip option (three hosts, three tooltip renderers; a host enables the mouse and hooks
-- OnEnter itself), no color option (the sameness is the point: the two fixed flavors, test and
-- sim, are the library's, and a host still cannot pass a color), no wrap, no measuring and no
-- `Height()` (one host wraps, and one must never measure), no test-mode state (the host decides
-- when it shows and what it says), no placement and no body shift (that is host layout; a host
-- leaves its own gap around `TEST_STRIP.HEIGHT`), and no icon fallback (no icon is a valid state:
-- the text moves to the left edge). Re-check trigger for all six: a consumer needs a different
-- color, a tooltip renderer or a measured height with the same semantics as another.
--
-- ── SKIN OWNERS (minor 16) ────────────────────────────────────────────────────────────────────
--
-- Every constructor here takes an optional skin OWNER, the caller's addon folder name: `opts.owner`
-- for the dropdown, the search box and the strip, the descriptor's `addonName` for the copy window
-- (WidgetsCopyWindow.lua). A name counts only when that addon registered it with LibKa0s-Skin-1.0
-- (`Skin:IsOwner`), resolved at CALL time like Media: then the control is painted through that
-- owner's facade after today's paint (`S.Dropdown`, `S.EditBox`, `S.Strip`, `S.Shell`,
-- `S.MenuFrame`) and follows the owner's skin switches. An unregistered name, or a client without the Skin major, draws exactly what minor 15
-- drew. The shared popup menu is one frame for every addon, so it is repainted on EVERY open: to
-- the opening dropdown's owner when it has one, and otherwise, once an owner has painted it, back to
-- Ka0s Default through a facade no addon registers (`DEFAULT_OWNER` below). The secondary files
-- (DragHandle, ReorderList, LineChart, Autocomplete, CopyWindow) take it the same way and share the
-- helpers below, which are internal (`__`) and not host contract.
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on no addon framework.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

-- Minor 15: the shared dropdown menu is clamped to the screen (EnsureMenu), so a dropdown near a
-- screen edge drops a menu that stays on screen (frame-layering-§4; XS-22).
-- Minor 16: the skin owner (the header's SKIN OWNERS).
local MAJOR, MINOR = "LibKa0s-Widgets-1.0", 16
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR
lib.MODULES = lib.MODULES or {}
lib.MODULES.Widgets = MINOR

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- The house flat skin: the dropdown's button and the search box wear it. Hoisted out of
-- MakeDropdown's literals at minor 13 with no visible change. FILE-LOCAL on purpose (see the
-- header's rejections): `focus` is the gold line a search box wears while it has the keys.
local SKIN = {
  edge   = WHITE,
  fill   = { 0.1, 0.1, 0.12, 0.9 },
  line   = { 0.24, 0.24, 0.27, 0.9 },
  focus  = { 1, 0.82, 0, 0.9 },
  height = 20,
}

-- The rungs below every piece of injected art. Named rather than inlined at the fallback site so
-- that "what does a host with no LibKa0s-Media draw?" is answerable by reading two lines.
local CHEVRON_FALLBACK = "Interface\\Buttons\\Arrow-Down-Up"
local CHECK_FALLBACK   = "Interface\\Buttons\\UI-CheckBox-Check"

local MENU_ROW_H = 16

-- ── the skin owner (minor 16; the header's SKIN OWNERS) ──────────────────────────────────────

--- The Skin major when `owner` is a registered skin owner, else nil. Read at call time.
local function skinOf(owner)
  if type(owner) ~= "string" or owner == "" or not LibStub then return nil end
  local Skin = LibStub("LibKa0s-Skin-1.0", true)
  if Skin and type(Skin.IsOwner) == "function" and Skin:IsOwner(owner) then return Skin end
  return nil
end
lib.__skinOf = skinOf

-- owner -> weak-keyed { [target] = fn(target, owner) }, re-run after each of the owner's skin
-- changes; owner -> true once the one OnLooksChanged listener for it exists. Kept across minors.
lib.__skinned = lib.__skinned or {}
lib.__skinHooked = lib.__skinHooked or {}

--- Re-run every recorded repaint of `owner`'s controls, each under pcall.
function lib.__repaintSkinned(owner)
  for target, fn in pairs(lib.__skinned[owner] or {}) do
    local ok, err = pcall(fn, target, owner)
    if not ok and type(geterrorhandler) == "function" then geterrorhandler()(err) end
  end
end

--- Record `fn(target, owner)` to run again after each change of `owner`'s skin (for what no skin
--- primitive paints: a palette read from tokens). One listener per owner, a trampoline into the
--- live copy of this major, so a newer minor's repaint runs.
function lib.__onSkin(Skin, owner, target, fn)
  local set = lib.__skinned[owner]
  if not set then
    set = setmetatable({}, { __mode = "k" })
    lib.__skinned[owner] = set
  end
  set[target] = fn
  if lib.__skinHooked[owner] then return end
  lib.__skinHooked[owner] = true
  Skin:OnLooksChanged(owner, function()
    local W = LibStub("LibKa0s-Widgets-1.0", true)
    if W and type(W.__repaintSkinned) == "function" then W.__repaintSkinned(owner) end
  end)
end

--- `name` of `owner`'s skin, or `fallback`.
local function token(Skin, owner, name, fallback)
  local c = Skin:Token(owner, name)
  if c == nil then return fallback end
  return c
end

-- The shared menu's row colors: selected, plain, and the highlight under the pointer.
local MENU_PAL = { sel = { 1, 0.82, 0 }, text = { 0.9, 0.9, 0.9 }, hover = { 1, 0.82, 0, 0.15 } }
-- No addon registers this name, so its facade reads Ka0s Default: the menu is given back through it.
local DEFAULT_OWNER = MAJOR

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
  for _, opt in ipairs(opts) do
    menu.measure:SetText((dd.multi and dd.__check or "") .. (opt.label or ""))
    local pad = opt.glyph and 38 or 24   -- a glyphed row indents its text by a further 14px
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
  return b
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

-- Repaint one row from its option. EVERY field is written on every pass, including the blank ones:
-- the rows are pooled across dropdowns, so a field left alone leaks the previous menu's glyph or
-- color onto this one.
local function paintMenuRow(b, dd, opt, selected, pal)
  local check = (dd.multi and selected) and dd.__check or ""
  b.fs:SetText(check .. opt.label)
  -- A glyphed row indents its text to clear the glyph; every other row starts at the margin.
  b.fs:ClearAllPoints()
  b.fs:SetPoint("LEFT", opt.glyph and 22 or 8, 0)
  b.fs:SetPoint("RIGHT", -8, 0)
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
  if dd.__glyphFont and opt.glyph then
    b.glyph:SetFont(dd.__glyphFont, 11, "")
  end
  b.glyph:SetText(opt.glyph or "")
  b.glyph:SetShown(opt.glyph ~= nil and dd.__glyphFont ~= nil)
  -- The selected row goes gold to mark the selection; otherwise the value keeps its own color
  -- (store / direction / class), so the menu reads like the column it filters. The glyph always
  -- keeps the direction's color — it IS the value, not a selection state.
  if selected then
    b.fs:SetTextColor(pal.sel[1], pal.sel[2], pal.sel[3])
  elseif opt.color then
    b.fs:SetTextColor(opt.color[1], opt.color[2], opt.color[3])
  else
    b.fs:SetTextColor(pal.text[1], pal.text[2], pal.text[3])
  end
  -- The highlight only when the menu's colors changed since this row last wore them.
  if b.__hl and b.__hlc ~= pal.hover then
    b.__hl:SetColorTexture(pal.hover[1], pal.hover[2], pal.hover[3], pal.hover[4])
    b.__hlc = pal.hover
  end
  if opt.color then b.glyph:SetTextColor(opt.color[1], opt.color[2], opt.color[3]) end
end

-- One row's click handler.
local function rowOnClick(menu, dd, opt)
  return function()
    if dd.multi then
      -- Toggle in place and keep the menu open, so several can be picked in one visit.
      dd:ToggleSelected(opt.value)
      menu:Populate(dd)
      if dd.onMultiSelect then dd.onMultiSelect(dd._selected) end
    else
      dd:SetValue(opt.value, opt.label)
      menu:Hide()
      if dd.onSelect then dd.onSelect(opt.value) end
    end
  end
end

--- Repaint the shared menu for the dropdown opening it (minor 16): its owner's skin when it has a
--- registered one, else Ka0s Default once an owner has painted it. An owner-less open of a menu no
--- owner ever painted touches nothing.
local function skinMenu(m, dd)
  local owner = dd.__owner
  local Skin = skinOf(owner)
  if Skin then
    if type(Skin.__MarkShared) == "function" then Skin:__MarkShared(m) end
    Skin:For(owner).MenuFrame(m)
    m.__pal = { sel = token(Skin, owner, "menu.textSel", MENU_PAL.sel),
                text = token(Skin, owner, "menu.text", MENU_PAL.text),
                hover = token(Skin, owner, "menu.hover", MENU_PAL.hover) }
    return
  end
  if not m.__pal then return end
  m.__pal = nil
  Skin = LibStub("LibKa0s-Skin-1.0", true)
  if Skin and type(Skin.For) == "function" then Skin:For(DEFAULT_OWNER).MenuFrame(m) end
end

local menu
local function EnsureMenu()
  if menu then return menu end
  menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  -- Minor 15: a dropdown near the bottom or right edge would otherwise drop rows off the screen.
  menu:SetClampedToScreen(true)
  menu:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  menu:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
  menu:SetBackdropBorderColor(0, 0, 0, 1)
  menu:Hide()
  menu.buttons = {}

  -- ── HOW AN OUTSIDE CLICK CLOSES THIS, AND WHY IT IS NOT A CATCHER ──────────────────────────
  --
  -- Through minor 4 this was a full-screen `Button` at FULLSCREEN strata, shown alongside the menu,
  -- whose OnClick hid it. That frame INTERCEPTED the click, and intercepting was the defect:
  --
  --   * A `Button` with no `RegisterForClicks` takes `LeftButtonUp` and nothing else. A right-click
  --     anywhere while a menu was open landed on the catcher, found no handler for that button and
  --     was SWALLOWED — the menu stayed open and whatever was underneath never heard the click. It
  --     survived from minor 1 because neither shipped consumer had a right-click surface on the
  --     same window as a dropdown; LootHistory was the first, and there a right-click on a history
  --     row simply did nothing.
  --   * Even the left-click it did handle was eaten. Dismissing the menu cost a click that did
  --     nothing else, which is not how a menu should feel.
  --
  -- So the menu no longer intercepts anything. It LISTENS: `GLOBAL_MOUSE_DOWN` fires for a press
  -- anywhere in the UI, on any button, whether or not something else consumed it — so the menu can
  -- react to a click it never touched, and the click goes on to reach whatever is under the cursor.
  -- One press now both dismisses the menu and does the thing the player pressed on.
  --
  -- Registered while shown and dropped on hide, rather than for the life of the process: this is a
  -- handler that would otherwise run on every mouse press in the game for the rest of the session,
  -- in every host that ever vendored this file, and no host agreed to that.
  -- The button that was pressed arrives as the next argument and is deliberately not read: no
  -- button is enumerated anywhere in this widget, so a mouse with more of them behaves the same.
  menu:SetScript("OnEvent", function(self, event)
    if event == "GLOBAL_MOUSE_DOWN" then self:__OutsideClick() end
  end)
  menu:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)

  -- Two presses are NOT outside, and both exemptions are load-bearing:
  --
  --   * On the menu — otherwise the menu would close under the player's own row click, on the
  --     press, before the release the row's OnClick needs.
  --   * On the dropdown that dropped it — that button's own OnClick is the toggle. Close on the
  --     press and the release finds the menu hidden and re-opens it, and the menu becomes
  --     impossible to close by the button that opened it. Only the OWNER is exempt: a press on a
  --     different dropdown closes this menu, and that dropdown's OnClick then opens its own, which
  --     is how exactly one menu stays open across the process.
  function menu:__OutsideClick()
    if self:IsMouseOver() then return end
    local owner = self._owner
    if owner and owner.IsMouseOver and owner:IsMouseOver() then return end
    self:Hide()
  end

  function menu:Populate(dd)
    for _, b in ipairs(self.buttons) do b:Hide() end
    local opts = dd._options or {}
    local w = menuWidth(self, dd, opts)
    for i, opt in ipairs(opts) do
      local b = self.buttons[i]
      if not b then
        b = makeMenuRow(self)
        self.buttons[i] = b
      end
      b:SetWidth(w)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 0, -4 - (i - 1) * MENU_ROW_H)
      paintMenuRow(b, dd, opt, rowSelected(dd, opt), self.__pal or MENU_PAL)
      b:SetScript("OnClick", rowOnClick(self, dd, opt))
      b:Show()
    end
    self:SetSize(w, #opts * MENU_ROW_H + 8)
  end
  return menu
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

-- A dropdown button: shows the current label plus a ▼ texture; clicking opens the shared menu.
local function MakeDropdown(parent, width, opts)
  opts = opts or {}
  local dd = CreateFrame("Button", nil, parent, "BackdropTemplate")
  dd:SetSize(width, SKIN.height)
  dd:SetBackdrop({ bgFile = SKIN.edge, edgeFile = SKIN.edge, edgeSize = 1,
                   insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  dd:SetBackdropColor(unpack(SKIN.fill))
  dd:SetBackdropBorderColor(unpack(SKIN.line))

  -- The tick a multi-select dropdown puts in front of every chosen row. INLINE |T…|t markup,
  -- resolved ONCE per dropdown so a degraded install appends the Blizzard string it always did
  -- rather than concatenating a nil into an escape.
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
  dd.__check = "|T" .. (opts.check or CHECK_FALLBACK) .. ":0|t "
  -- The mono face the optional row glyph is drawn in, read by paintMenuRow on every pass. Absent
  -- means the host wants no glyph column at all.
  dd.__glyphFont = opts.glyphFont

  local fs = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", 6, 0)
  fs:SetPoint("RIGHT", -16, 0)
  fs:SetJustifyH("LEFT")
  dd.text = fs

  -- The ▼ affordance. It is a texture rather than a character because the ▼ glyph is not in the
  -- default WoW font and renders as a box — and it is the host's `chevron-down` mark when the host
  -- has one, with Blizzard's own arrow kept as the rung below it. The vertex color is set here and
  -- not by the host, which is what makes shared white art wear this widget's gray rather than its
  -- own.
  local arrow = dd:CreateTexture(nil, "OVERLAY")
  arrow:SetSize(12, 12)
  arrow:SetPoint("RIGHT", -4, 0)
  arrow:SetTexture(opts.chevron or CHEVRON_FALLBACK)
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
    local allLabel = (self._options and self._options[1] and self._options[1].label) or "All"
    self.text:SetText(summarizeSelection(selectionLabels(self), allLabel))
  end

  dd:SetScript("OnClick", function(self2)
    local m = EnsureMenu()
    if m:IsShown() and m._owner == self2 then m:Hide(); return end
    m._owner = self2
    skinMenu(m, self2)
    m:Populate(self2)
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", self2, "BOTTOMLEFT", 0, -1)
    m:Show()
    m:RegisterEvent("GLOBAL_MOUSE_DOWN")
  end)
  -- Minor 16: the skin owner, read by skinMenu on every open; its button wears the owner's skin.
  dd.__owner = opts.owner
  local Skin = skinOf(opts.owner)
  if Skin then Skin:For(opts.owner).Dropdown(dd) end
  return dd
end

--- Build a flat-skin dropdown button that drops the shared popup menu.
---
--- @param parent table         the frame to parent it to
--- @param width number         the collapsed button's width; the menu never drops narrower
--- @param opts table|nil       { chevron =, check =, glyphFont = }, each a resolved path or nil;
---                             `owner` (minor 16), a registered skin owner: the button and the menu
---                             it drops wear that owner's skin (the header's SKIN OWNERS)
--- @return table  the dropdown
function lib.Dropdown(parent, width, opts)
  return MakeDropdown(parent, width, opts)
end

--- Close the shared popup menu, if it is open. Safe to call when no dropdown has ever opened the
--- menu (menu is still nil) and safe to call when the menu is already hidden — both are plain
--- no-ops.
---
--- A HOST CANNOT DO THIS ITSELF: the popup is a process-wide singleton, built lazily on the first
--- click of any dropdown in the process and parented to `UIParent` at `FULLSCREEN_DIALOG` (see
--- EnsureMenu above), not to any one host's frame. It outlives every window that ever opened it,
--- so no host holds a reference to it and no host's own Hide/OnHide reaches it — the widget kept
--- that shape on purpose (see the header comment on `dd.__check`) precisely so that two addons'
--- dropdowns can share one pool. `menu:Hide()` is enough on this end: the menu's own `OnHide`
--- script (set in EnsureMenu) drops its `GLOBAL_MOUSE_DOWN` registration, so this function does not
--- unregister anything itself.
---
--- Without this, a host that closes its own window by any route that is not a click on the
--- dropdown — Escape, a slash command, anything that is not a mouse press at all —
--- leaves the menu ORPHANED: still shown, still at FULLSCREEN_DIALOG, floating over the game with
--- no owner left to hide it. A host must call this from every non-click close path it has. Since
--- minor 5 the menu closes itself on a mouse press anywhere outside it, which narrows the window
--- but does not close it: a host window hidden by Escape or a slash command is hidden without any
--- click at all.
function lib.CloseMenu()
  if menu and menu:IsShown() then menu:Hide() end
end

-- ── the search box (minor 13) ───────────────────────────────────────────────────────────────
--
-- WHY THIS IS HERE. LootHistory, BankLedger and DropWatcher each hand-built the same flat EditBox
-- for their filter bars: the dropdown's fill and line, a gray hint while empty, Escape and Enter
-- to let go of the keys. Three copies of a control that sits beside this file's dropdown is the
-- header's argument again (#52). The gold focus line is new for all three (the owner's ruling).

local SEARCH_ICON_SIZE, SEARCH_ICON_X = 11, 5
local SEARCH_INSET, SEARCH_INSET_ICON = 6, 21

local function searchText(box)
  local t = box:GetText()
  return type(t) == "string" and t or ""
end

local function paintSearchBorder(box, c)
  if box.SetBackdropBorderColor then box:SetBackdropBorderColor(unpack(c)) end
end

--- A skinned search box's icon in its owner's `icon.tint` (minor 16).
local function tintSearchIcon(icon, owner)
  local Skin = skinOf(owner)
  local c = Skin and token(Skin, owner, "icon.tint", nil)
  if c then icon:SetVertexColor(c[1], c[2], c[3]) end
end

--- Build the flat filter-bar search box. A host EXTENDS it with HookScript and never SetScripts the
--- five scripts below, which this constructor sets: OnTextChanged (the hint, then `opts.onChange`),
--- OnEscapePressed and OnEnterPressed (ClearFocus), OnEditFocusGained (the gold line) and
--- OnEditFocusLost (the gray line). There are no setters: the host rewrites `box.hint:SetText`
--- directly, and `lib.Autocomplete(box, ...)` composes after construction. The icon art is
--- HOST-PASSED, a resolved path or a fileID, because this file cannot call Media (the header); a
--- host that passes one declares that icon's name, and it joins no library-drawn icon set.
---
--- @param parent table       the frame to parent it to
--- @param width number|nil   the box's width; nil sets none, for a host that anchors both edges
--- @param opts table|nil     { hint = string|nil, icon = path|fileID|nil,
---                             onChange = function(text, box)|nil, owner = string|nil }; `owner`
---                             (minor 16) is a registered skin owner: the box, its hint, its focus
---                             line and its icon wear that owner's skin
--- @return table  the EditBox, with `box.hint` (FontString) and `box.icon` (Texture or nil)
function lib.SearchBox(parent, width, opts)
  opts = opts or {}
  local box = CreateFrame("EditBox", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  if type(width) == "number" then box:SetWidth(width) end
  box:SetHeight(SKIN.height)
  if box.SetBackdrop then
    box:SetBackdrop({ bgFile = SKIN.edge, edgeFile = SKIN.edge, edgeSize = 1,
                      insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    box:SetBackdropColor(unpack(SKIN.fill))
  end
  paintSearchBorder(box, SKIN.line)
  box:SetFontObject("GameFontHighlightSmall")
  box:SetAutoFocus(false)

  local icon = opts.icon
  local left = SEARCH_INSET
  if type(icon) == "string" or type(icon) == "number" then
    local tex = box:CreateTexture(nil, "ARTWORK")
    tex:SetSize(SEARCH_ICON_SIZE, SEARCH_ICON_SIZE)
    tex:SetPoint("LEFT", SEARCH_ICON_X, 0)
    tex:SetTexture(icon)
    tex:SetVertexColor(0.7, 0.7, 0.72)
    box.icon = tex
    left = SEARCH_INSET_ICON
  end
  box:SetTextInsets(left, SEARCH_INSET, 0, 0)

  local hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("LEFT", left, 0)
  hint:SetPoint("RIGHT", -SEARCH_INSET, 0)
  hint:SetJustifyH("LEFT")
  hint:SetText(type(opts.hint) == "string" and opts.hint or "")
  box.hint = hint

  local onChange = opts.onChange
  box:SetScript("OnTextChanged", function(self)
    local text = searchText(self)
    self.hint:SetShown(text == "")
    if onChange then onChange(text, self) end
  end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEditFocusGained", function(self) paintSearchBorder(self, SKIN.focus) end)
  box:SetScript("OnEditFocusLost", function(self) paintSearchBorder(self, SKIN.line) end)
  hint:SetShown(searchText(box) == "")
  -- Minor 16: after the scripts, so the facade's focus hooks run after the gold / gray line.
  local Skin = skinOf(opts.owner)
  if Skin then
    Skin:For(opts.owner).EditBox(box)
    if box.icon then
      lib.__onSkin(Skin, opts.owner, box.icon, tintSearchIcon)
      tintSearchIcon(box.icon, opts.owner)
    end
  end
  return box
end

-- ── the mode strip (test mode or a simulation) ───────────────────────────────────────────────

-- One fill per kind. FILE-LOCAL, like SKIN: there is no color option, only these two flavors.
--   test: DropWatcher's C.TONE.warn (1, 0.65, 0.15) at 12%.
--   sim:  the collection's simulation cyan (DropWatcher TB.SIM_TONE, LootHistory SIM_MARK) at 12%.
local STRIP_FILL = {
  test = { 1.00, 0.65, 0.15, 0.12 },
  sim  = { 0.35, 0.80, 1.00, 0.12 },
}
local STRIP_H, STRIP_ICON, STRIP_INSET = 18, 12, 6

--- Read-only layout figures, so a host lays out around the strip's own height rather than copying
--- it (the DRAG_HANDLE / ROW_BOX precedent). A host adds its own gaps around it. Writing to this
--- table moves nothing: the constructor reads the file-local.
lib.TEST_STRIP = { HEIGHT = STRIP_H }

--- Build the mode strip: a full-width band a window lays between its chrome and its data, saying
--- the data under it is not real, in test mode (amber, the default) or a simulation
--- (`kind = "sim"`, cyan). It draws itself and nothing else.
---
--- Born HIDDEN, UNANCHORED and `TEST_STRIP.HEIGHT` tall, with the mouse never enabled. After this
--- returns the strip never anchors, shows, hides, re-measures or changes its height or its text's
--- anchors, so a host's later `SetHeight`, `strip.text:SetWordWrap` and `strip.text:SetText`
--- stick. The icon art is HOST-PASSED, a resolved path or a fileID (the host's `info` icon),
--- because this file cannot call Media (the header): a host that passes one declares that icon's
--- name. The fill and the icon are stored as `__fill` / `__icon`, which are not the contract.
---
--- @param parent table     the frame to parent it to
--- @param opts table|nil   { text, icon, kind = 'test'|'sim'|nil, owner }; text is the host's
---                         localized line ('' when absent), no icon puts the text at LEFT+6, any
---                         kind but exactly "sim" (nil, a non-string, "Sim", "preview") is "test",
---                         and `owner` (minor 16) is a registered skin owner whose skin the wash
---                         follows
--- @return table  the Frame, with `strip.text` (FontString, OVERLAY, GameFontNormalSmall, LEFT at
---                the icon's RIGHT+6 or the strip's LEFT+6, RIGHT at -6, JustifyH LEFT, no wrap)
---                and `strip.kind` ("test" or "sim"), read-only and set once at birth: writing it
---                repaints nothing
function lib.TestStrip(parent, opts)
  opts = type(opts) == "table" and opts or {}
  local kind = opts.kind == "sim" and "sim" or "test"
  local s = CreateFrame("Frame", nil, parent)
  s:SetHeight(STRIP_H)   -- the local, not lib.TEST_STRIP: a host write cannot move it

  local fill = s:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(s)
  fill:SetColorTexture(unpack(STRIP_FILL[kind]))
  s.__fill = fill
  -- Minor 16: a registered skin owner's strip takes its wash from that skin (`strip.test` /
  -- `strip.sim`); the meaning colors are the library's, a skin changes only their legibility.
  local Skin = skinOf(opts.owner)
  if Skin then Skin:For(opts.owner).Strip(fill, { kind = kind }) end

  local icon = opts.icon
  if type(icon) == "string" or type(icon) == "number" then
    local tex = s:CreateTexture(nil, "ARTWORK")
    tex:SetSize(STRIP_ICON, STRIP_ICON)
    tex:SetPoint("LEFT", s, "LEFT", STRIP_INSET, 0)
    tex:SetTexture(icon)
    s.__icon = tex
  end

  -- From a template, so it is never fontless when SetText arrives.
  local text = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if s.__icon then
    text:SetPoint("LEFT", s.__icon, "RIGHT", STRIP_INSET, 0)
  else
    text:SetPoint("LEFT", s, "LEFT", STRIP_INSET, 0)
  end
  text:SetPoint("RIGHT", s, "RIGHT", -STRIP_INSET, 0)
  text:SetJustifyH("LEFT")
  text:SetWordWrap(false)   -- with both anchors, a long line truncates with an ellipsis
  text:SetText(type(opts.text) == "string" and opts.text or "")
  s.text = text
  s.kind = kind

  s:Hide()   -- born unanchored: hidden, so it never flashes at the parent's center
  return s
end
