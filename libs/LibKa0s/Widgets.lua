-- LibKa0s-Widgets-1.0 — the collection's flat dropdown, and the one popup menu every instance of it
-- drops.
--
-- ── WHY THIS IS A LIBRARY AND NOT A COPY ──────────────────────────────────────────────────────
--
-- It was BankLedger's, local to modules/Browser.lua, and it was about to be MultiMeters' too. Two
-- copies of a widget is two skins to keep in step, and the collection stops looking like one
-- author's work the first time one copy is restyled and the other is not. That is the argument the
-- icons were consolidated under at v1.9.0; a widget that DRAWS those icons is the same argument one
-- layer up.
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
-- No search box, no keyboard navigation, no scrolling for a long list, no sub-menus, no per-row
-- disable. None of those is wanted by either shipped consumer, and every one of them is reachable
-- later without a major bump. A widget that grows features nobody asked for is a widget whose
-- degraded behavior nobody has tested.
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on no addon framework.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Widgets-1.0", 8
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR
lib.MODULES = lib.MODULES or {}
lib.MODULES.Widgets = MINOR

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- The rungs below every piece of injected art. Named rather than inlined at the fallback site so
-- that "what does a host with no LibKa0s-Media draw?" is answerable by reading two lines.
local CHEVRON_FALLBACK = "Interface\\Buttons\\Arrow-Down-Up"
local CHECK_FALLBACK   = "Interface\\Buttons\\UI-CheckBox-Check"
local HANDLE_FALLBACK  = "Interface\\Buttons\\UI-SortArrow"

local MENU_ROW_H = 16

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
local function paintMenuRow(b, dd, opt, selected)
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
    b.fs:SetTextColor(1, 0.82, 0)
  elseif opt.color then
    b.fs:SetTextColor(opt.color[1], opt.color[2], opt.color[3])
  else
    b.fs:SetTextColor(0.9, 0.9, 0.9)
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

local menu
local function EnsureMenu()
  if menu then return menu end
  menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
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
      paintMenuRow(b, dd, opt, rowSelected(dd, opt))
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
  dd:SetSize(width, 20)
  dd:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                   insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  dd:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
  dd:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.9)

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
    m:Populate(self2)
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", self2, "BOTTOMLEFT", 0, -1)
    m:Show()
    m:RegisterEvent("GLOBAL_MOUSE_DOWN")
  end)
  return dd
end

--- Build a flat-skin dropdown button that drops the shared popup menu.
---
--- @param parent table         the frame to parent it to
--- @param width number         the collapsed button's width; the menu never drops narrower
--- @param opts table|nil       { chevron =, check =, glyphFont = }, each a resolved path or nil
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

-- ── the copy window ──────────────────────────────────────────────────────────────────────────
--
-- WHY THIS IS HERE. There is no file I/O in WoW. Every "export this" surface in the collection
-- therefore ends in the same thing: a frame holding a multi-line EditBox with the text selected,
-- and an instruction to press Ctrl+C. There were four copies before this member — BankLedger's,
-- LootHistory's, MultiMeters' and the debug log's — and two of them were the same fifty-two lines
-- with the addon name substituted out.
--
-- It lives in Widgets rather than in a major of its own for the same reason the dropdown does:
-- Widgets already owns "a frame this collection kept re-drawing", and the three addons that need
-- this already vendor it. A new major would have bought a fourth vendor sweep for nothing.
--
-- WHAT THE HOST STILL OWNS. The art and the face arrive as DESCRIPTOR FIELDS, not as lookups: a
-- vendored copy cannot know which addon folder it sits in, so it cannot resolve a texture path or
-- ask Media for one without being told the host's name. That is the same bargain
-- LibKa0s-Media-1.0 and Core.MakeCloseButton already strike.

local COPY_DEFAULTS = {
  width = 640, height = 420, fontSize = 10, title = "Export",
  backdrop = { 0.06, 0.06, 0.08, 0.95 },
}

--- Fill a caller's descriptor out with the collection's defaults, without mutating theirs.
local function copyDescriptor(d)
  local out = {
    addonName = d.addonName,
    name      = d.name or (d.addonName .. "CopyWindow"),
    width     = d.width or COPY_DEFAULTS.width,
    height    = d.height or COPY_DEFAULTS.height,
    title     = d.title or COPY_DEFAULTS.title,
    font      = d.font,
    fontSize  = d.fontSize or COPY_DEFAULTS.fontSize,
    applySkin = d.applySkin,
    backdrop  = d.backdrop or COPY_DEFAULTS.backdrop,
    anchorTo  = d.anchorTo,
    -- Optional, minor 7, and NOT defaulted to anything. UIPanelScrollFrameTemplate derives its
    -- scrollbar children's names from its parent's, so an anonymous scroll frame leaves them
    -- unnamed — which is invisible until somebody tries to skin or find one. The debug log's own
    -- copy window had always named it and the three adopters here never had; that difference is
    -- what surfaced when DebugLog minor 12 converged onto this member. Left nil by default so a
    -- caller written before minor 7 keeps exactly the frame it already had rather than silently
    -- acquiring a global.
    scrollName = d.scrollName,
    -- Optional, minor 7. Defaults to Core's x, which is what all four callers want and what three
    -- of them already got. It exists because LibKa0s-DebugLog-1.0 has published a `makeCloseButton`
    -- descriptor field since ITS minor 4, documented as applying to BOTH of its windows — so when
    -- minor 12 converged its copy window onto this member, a hardcoded Core x here would have
    -- quietly narrowed a contract a host had already been told it could rely on.
    makeCloseButton = d.makeCloseButton,
  }
  out.editWidth = d.editWidth or (out.width - 50)
  return out
end

--- Build the frame. Called once, lazily, on the first Show — a modal rebuilt per open leaks a
--- frame per open for the life of the session, because frames are never destroyed in WoW.
local function buildCopyFrame(d)
  local f = CreateFrame("Frame", d.name, UIParent, "BackdropTemplate")
  f:SetSize(d.width, d.height)
  f:SetPoint("CENTER")
  -- FULLSCREEN so it sits above the DIALOG-strata modal that opened it. The modal stays visible
  -- underneath, which is what makes "copy this, then pick a different set" one trip rather than two.
  f:SetFrameStrata("FULLSCREEN")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)

  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", -1, -1)
  bar:SetHeight(26)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() f:StartMoving() end)
  bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("CENTER")
  title:SetText(d.title)
  f.title = title

  -- Resolved at CALL time rather than at load: Core is the first file in LibKa0s.xml and this is
  -- the third, so a load-time lookup would be fine here — but MakeCloseButton itself resolves Media
  -- at call time for exactly this reason, and one rule about when the payload is resolvable is
  -- easier to keep than two.
  local coreLib = LibStub and LibStub("LibKa0s-Core-1.0", true)
  local makeClose = d.makeCloseButton or (coreLib and coreLib.MakeCloseButton)
  if makeClose then
    local close = makeClose(bar, function() f:Hide() end, d.addonName)
    if close then close:SetPoint("RIGHT", bar, "RIGHT", -6, 0) end
  end

  local scroll = CreateFrame("ScrollFrame", d.scrollName, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -30)
  scroll:SetPoint("BOTTOMRIGHT", -28, 10)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  -- The face arrives as a PATH. SetFont does not accept a LibSharedMedia name, and a CSV is
  -- columns of digits that only line up in a fixed-width face.
  if d.font then edit:SetFont(d.font, d.fontSize, "") end
  edit:SetAutoFocus(false)
  edit:SetWidth(d.editWidth)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
  scroll:SetScrollChild(edit)

  f.scroll, f.edit = scroll, edit

  if d.applySkin then
    d.applySkin(f)
  elseif coreLib and coreLib.ApplySkin then
    coreLib.ApplySkin(f)
  end
  -- Denser than the shared skin. This frame is a wall of small monospace text, and the world
  -- behind it bleeding through costs legibility in a way it does not on a frame showing four
  -- controls.
  if f.SetBackdropColor then
    f:SetBackdropColor(d.backdrop[1], d.backdrop[2], d.backdrop[3], d.backdrop[4])
  end

  f:Hide()
  -- By NAME, type-guarded: UISpecialFrames is a list of GLOBAL frame names and the table itself is
  -- not guaranteed to exist outside a real client.
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, d.name)
  end
  return f
end

--- A read-only copy window: text in, Ctrl+C out, Esc closes.
---
--- Returns a HANDLE, not a frame, so the frame stays lazy — nothing is created until the first
--- Show, which matters because a host builds this at file load and most sessions never open it.
--- Answers nil with no client and without an `addonName` (which the close control needs to find
--- the collection's own art).
---
--- @param d table  see docs/api/Widgets — addonName is the only required field
--- @return table|nil
function lib.CopyWindow(d)
  if type(d) ~= "table" or type(d.addonName) ~= "string" then return nil end
  if type(CreateFrame) ~= "function" then return nil end

  local desc = copyDescriptor(d)
  local frame
  local win = { __descriptor = desc }

  function win:GetFrame()
    if not frame then frame = buildCopyFrame(desc) end
    return frame
  end

  function win:GetText()
    return frame and frame.edit:GetText() or nil
  end

  function win:Hide()
    if frame then frame:Hide() end
  end

  --- THE ORDER IS LOAD-BEARING: width, then text, then cursor to the top, then show, then focus,
  --- then highlight. Highlighting before the frame is shown selects nothing, and focusing before
  --- the text is set leaves the cursor wherever the last export left it. All four hand-rolled
  --- copies got this right and the fifth author would have had to rediscover it.
  function win:Show(text)
    local f = self:GetFrame()

    -- Re-anchored on EVERY show, not once at build: the popup has to land over the window that
    -- spawned it, wherever the user has since dragged that window.
    f:ClearAllPoints()
    local anchor = desc.anchorTo and desc.anchorTo()
    if anchor and anchor.IsShown and anchor:IsShown() then
      f:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    else
      f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    local w = f.scroll:GetWidth()
    f.edit:SetWidth((type(w) == "number" and w > 0) and w or desc.editWidth)
    f.edit:SetText(text or "")
    f.edit:SetCursorPosition(0)
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
    return f
  end

  return win
end

-- ── ReorderList ───────────────────────────────────────────────────────────────────────────────
--
-- Drag a row of a list to a new position. The library owns the GESTURE and everything you see
-- while it is happening; the host owns the rows.
--
-- ── WHERE THE LINE IS DRAWN, AND WHY THERE ────────────────────────────────────────────────────
--
-- The two shipped consumers draw completely different rows. MultiMeters' Columns page is a state
-- glyph and a statistic name; ConsumableMaster's priority list is a live item tooltip, a
-- crafting-quality glyph, a pick star, a score button and a remove button. Neither would accept a
-- widget that owned its row content, and a `render(row, item)` callback wide enough for both is
-- not an abstraction -- it is a hole shaped like two addons.
--
-- So this owns no row content at all. It owns the handle, the copy that follows the cursor, the
-- insertion line, the index arithmetic, the clamp, and nothing else. A host builds its rows however
-- it already does -- AceGUI, raw frames, anything -- hands each one over, and gets `onMove` back.
-- That is also the whole of what was hard: the gesture took four rounds to get right in a client,
-- and the row content took none.
--
-- ── WHAT THE HOST STILL DECIDES ───────────────────────────────────────────────────────────────
--
-- Where the handle sits, how big it is, what art it wears, how tall a row is, whether the list has
-- two groups or one. All parameters. What it does NOT decide is what a drag LOOKS like, because
-- that is the thing every list in the collection should share -- the same ghost at the same alpha,
-- the same gold insertion line, the same fade on the row you picked up.
--
-- ── WHY THE ART ARRIVES AS A PARAMETER ────────────────────────────────────────────────────────
--
-- Same reason `chevron` and `check` do, and it is the reason stated at the top of this file:
-- `Media.Icon` takes the CONSUMING ADDON'S name to build a path, and a vendored copy cannot know
-- which addon folder it was copied into. `handleIcon` is a resolved path or nil, and nil falls to a
-- Blizzard texture, so a host with no LibKa0s-Media still gets a working handle.

-- The one copy carried under the cursor, process-wide. A singleton for the same reason the dropdown
-- menu is one: it lives on UIParent so it can follow the pointer OUT of whatever scroll frame the
-- list sits in, and a per-list copy would clip at the first edge it met.
local ghost

local function ensureGhost()
  if ghost then return ghost end

  ghost = CreateFrame("Frame", nil, UIParent)
  ghost:SetFrameStrata("TOOLTIP")
  ghost:SetSize(300, 30)
  -- LOAD-BEARING, NOT TIDY: a frame sitting under the pointer that accepts the mouse eats the very
  -- button-release that ends the drag it is drawing.
  ghost:EnableMouse(false)
  ghost:SetAlpha(0.9)
  ghost:Hide()

  ghost.bg = ghost:CreateTexture(nil, "BACKGROUND")
  ghost.bg:SetAllPoints(ghost)
  ghost.bg:SetColorTexture(0.12, 0.12, 0.12, 0.95)

  ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
  ghost.icon:SetSize(18, 18)
  ghost.icon:SetPoint("LEFT", ghost, "LEFT", 8, 0)

  ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ghost.text:SetPoint("LEFT", ghost.icon, "RIGHT", 6, 0)
  ghost.text:SetPoint("RIGHT", ghost, "RIGHT", -8, 0)
  ghost.text:SetJustifyH("RIGHT")

  -- `__`-PREFIXED IS INTERNAL, the same contract `dd.__check` carries: published so a suite can
  -- ask whether the carried copy exists, is shown, reads as the right row and follows the cursor,
  -- none of which is reachable from the controller. A host must not touch it -- what it draws is
  -- the one part of a drag this library deliberately does not let a host restyle.
  lib.__DragGhost = ghost

  return ghost
end

--- Put the ghost under the cursor, offset right so the pointer sits ON what it is carrying.
local function moveGhost()
  if not (ghost and ghost:IsShown()) then return end
  local x, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  if type(x) ~= "number" or type(y) ~= "number" or type(scale) ~= "number" or scale == 0 then
    return
  end
  ghost:ClearAllPoints()
  ghost:SetPoint("LEFT", UIParent, "BOTTOMLEFT", (x / scale) + 14, y / scale)
end

--- The insertion line for one container, built once and cached on it.
---
--- A FRAME CARRYING A TEXTURE, not a bare texture. A texture belongs to its own frame's draw layers,
--- so one created on the container draws UNDER every row -- each row is a child frame with its own
--- layers, and a parent's OVERLAY still loses to a child. The line has to be a sibling that
--- outranks them.
local function ensureLine(container, color)
  if not container then return nil end
  if container.__ka0sDropLine then return container.__ka0sDropLine end

  local line = CreateFrame("Frame", nil, container)
  line:SetHeight(3)
  -- Guarded on the ANSWER rather than on the method existing: a stub that returns itself for
  -- anything it does not implement answers a table here, and adding to it raises.
  local level = container.GetFrameLevel and container:GetFrameLevel()
  if type(level) == "number" then line:SetFrameLevel(level + 20) end

  local tex = line:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints(line)
  tex:SetColorTexture(color[1], color[2], color[3], color[4])

  line:Hide()
  container.__ka0sDropLine = line
  return line
end

--- Where a row dropped `rows` rows from `from` lands, clamped to its own group.
---
--- THE CLAMP IS AN INTERACTION RULE, not a safety check, and it only exists when the host says the
--- list has two groups. A flat list clamps to its own ends and nothing else.
local function dropIndex(from, rows, count, boundary)
  local lo, hi = 1, count
  if boundary and boundary > 0 and boundary < count then
    if from <= boundary then hi = boundary else lo = boundary + 1 end
  end

  local to = from + rows
  if to < lo then to = lo end
  if to > hi then to = hi end
  return to
end

--- Is the left button still down? Answers nil when the question cannot be asked.
local function mouseHeld()
  if type(IsMouseButtonDown) ~= "function" then return nil end
  local ok, held = pcall(IsMouseButtonDown, "LeftButton")
  if not ok then return nil end
  return held and true or false
end

-- ── the handle pool ──────────────────────────────────────────────────────────────────────────
--
-- THE LIBRARY OWNS ITS HANDLES. It does not cache them on the frames a host hands over, and the
-- reason is the whole of a bug that shipped:
--
-- Both consumers hand over frames their UI framework POOLS. Caching a handle on one looked right,
-- because the same host gets the same frame back at its next render -- but AceGUI's pool is
-- process-wide and typeless within a widget type. A released container is handed to whatever asks
-- next, and what asked next was a completely unrelated part of the page: a drag handle appeared on
-- "Drag to action bar", on an ID entry row, on a dropdown. The frame's identity is simply not the
-- host's to lend, and a cache keyed on it is a cache keyed on nothing.
--
-- So handles are acquired from a free list here and RELEASED on Cancel -- hidden, unanchored and
-- reparented off the host's frame in one step. A handle can then only ever be visible on a frame
-- this library put it on, during a render it is live for.

local handlePool, handleAttic = {}, nil

local function atticFrame()
  if not handleAttic then
    handleAttic = CreateFrame("Frame", nil, UIParent)
    handleAttic:Hide()
  end
  return handleAttic
end

-- ── the drag, hoisted out of the controller ───────────────────────────────────────────────────
--
-- These take a ROW and reach the controller through `row.list`, rather than closing over one.
--
-- THAT IS NOT STYLE. The handle is cached on a frame its host POOLS and reused across renders, so
-- a handler closing over the controller that built it would still be calling that controller after
-- it had been Cancel()led -- which is a drag that works exactly once and then freezes. `handle.__row`
-- fixes which row; this fixes which controller. Both halves are needed, and fixing only the first
-- is a bug that still passes a test written against the first.

local function showLine(row, to)
  local list = row.list
  local target = list.rows[to]
  if not (list.line and target) then return end
  local f = target.frame
  list.line:ClearAllPoints()
  -- ANCHORED TO THE TARGET ROW, never positioned by arithmetic. The index comes from the cursor,
  -- but where that index sits on screen is a question only the frames can answer -- and anchoring
  -- asks it without reading a single coordinate back.
  if to <= row.index then
    list.line:SetPoint("BOTTOMLEFT",  f, "TOPLEFT",  0, 0)
    list.line:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 0)
  else
    list.line:SetPoint("TOPLEFT",  f, "BOTTOMLEFT",  0, 0)
    list.line:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, 0)
  end
  list.line:Show()
end

local function finishDrag(row)
  if not row then return end
  local list = row.list

  row.frame:SetScript("OnUpdate", nil)
  if ghost then ghost:Hide() end
  if list.line then list.line:Hide() end
  if row.frame.SetAlpha then row.frame:SetAlpha(1) end

  if not row.startY then return end
  row.startY  = nil
  row.sawDown = nil
  list.dragging = nil

  local to = dropIndex(row.index, row.rows or 0, #list.rows, list.boundary)
  list.say("drop %d -> %d (%d rows)", row.index, to, row.rows or 0)
  -- A drag that lands where it started is not a reorder, and reporting one would have the host
  -- rewrite its list and repaint for no change at all.
  if to ~= row.index and list.onMove and not list.dead then
    list.onMove(row.index, to)
  end
end

local function trackDrag(row)
  if not row or not row.startY then return end
  local list = row.list

  local _, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  if type(y) == "number" and type(scale) == "number" and scale ~= 0 then
    -- +0.5 then floor is round-to-nearest: a row dragged 60% of the way to the next slot has
    -- visibly left its own, and rounding down would drop it back where it started.
    row.rows = math.floor(((row.startY - (y / scale)) / list.stride) + 0.5)
  end

  moveGhost()
  showLine(row, dropIndex(row.index, row.rows or 0, #list.rows, list.boundary))

  -- THE POLL MAY NOT ACT ALONE, and this is why it has to see the button held first. If
  -- IsMouseButtonDown is unavailable, protected, or simply not true yet on the first frame, a poll
  -- that ended the drag on `not held` would finish it with zero rows travelled -- no error, no
  -- message, and indistinguishable from a press that was never received.
  local held = mouseHeld()
  if held then
    row.sawDown = true
  elseif held == false and row.sawDown then
    finishDrag(row)
  end
end

--- Dress the carried copy as the row it came from and put it under the cursor.
---
--- Its own function because `beginDrag` was doing two jobs -- starting a drag, and drawing one --
--- and the pair came to CCN 17 against a release gate of 15. Splitting on that seam rather than
--- anywhere cheaper: the state machine and the picture it paints are genuinely separable, and this
--- half is the one that grows when the ghost gains a field.
local function raiseGhost(row, list)
  local g = ensureGhost()

  local w = row.frame.GetWidth and row.frame:GetWidth()
  if type(w) == "number" and w > 0 then g:SetWidth(w) end
  g:SetHeight(row.height or list.stride)

  g.icon:SetTexture(row.ghostIcon or list.handleIcon or HANDLE_FALLBACK)
  local ic = row.ghostIconColor or { 1, 1, 1 }
  g.icon:SetVertexColor(ic[1], ic[2], ic[3])

  g.text:SetText(row.ghostText or "")
  local tc = row.ghostTextColor or { 1, 0.82, 0 }
  g.text:SetTextColor(tc[1], tc[2], tc[3])

  g:Show()
  moveGhost()
end

local function beginDrag(row)
  if not row then return end
  local list = row.list
  if row.startY or list.dead then return end

  local _, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  if type(y) ~= "number" or type(scale) ~= "number" or scale == 0 then return end

  row.startY  = y / scale
  row.rows    = 0
  row.sawDown = nil
  list.dragging = row
  row.frame:SetScript("OnUpdate", function() trackDrag(row) end)
  -- The row you picked up fades IN THE LIST, because the copy under the cursor is the one you are
  -- looking at now.
  if row.frame.SetAlpha then row.frame:SetAlpha(0.35) end

  raiseGhost(row, list)
  list.say("grab %d at y=%.1f", row.index, row.startY)
end

--- Build a reorderable list controller.
---
--- One controller per RENDER, not one per list: it holds the rows of the pass that built it, and a
--- repaint builds a new one. `Cancel` on the old one is what stops a drag outliving the list it
--- was describing.
---
--- @param opts table
---   stride     number            row top to next row top, in pixels. Required -- the drop target is
---                                arithmetic on this, never a hit test, so nothing depends on the
---                                rows having been laid out yet.
---   onMove     function(from,to) called once when a drag lands somewhere new. Never called for a
---                                drag that lands where it started.
---   boundary   number|nil        how many rows are in the FIRST group. nil or 0 means one flat
---                                list, which is the common case; MultiMeters' Columns page is the
---                                other one, where shown columns may not be dragged among hidden.
---   handleIcon string|nil        resolved texture path for the handle art; nil falls back.
---   handleSize number|nil        the handle's hit width; its height is the row's. Defaults to 24.
---   handleInset number|nil       px from the parent's left edge. Defaults to 0.
---   handleColor table|nil        { r, g, b } for the handle at rest. Defaults to a neutral gray.
---   handleHoverColor table|nil   { r, g, b } under the pointer. Defaults to the collection's gold.
---   handleTooltip string|nil     one line shown on hover. No tooltip without it.
---   iconSize   number|nil        the art drawn inside it, defaults to 16.
---   lineColor  table|nil         { r, g, b, a } for the insertion line; defaults to gold.
---   debug      function|nil      called as debug(fmt, ...) on grab and drop.
--- @return table controller
function lib.ReorderList(opts)
  opts = opts or {}

  local list = {
    stride     = opts.stride or 30,
    boundary   = opts.boundary,
    onMove     = opts.onMove,
    handleIcon = opts.handleIcon,
    color      = opts.lineColor or { 1, 0.82, 0, 0.9 },
    rows       = {},
    handles    = {},
    dead       = false,
  }

  function list.say(fmt, ...)
    if opts.debug then opts.debug(fmt, ...) end
  end

  -- A GHOST LEFT SHOWN BY A PREVIOUS CONTROLLER IS NOT THIS ONE'S TO INHERIT. Hosts are asked to
  -- Cancel on repaint and both shipped ones do, but the ghost is a process-wide singleton and this
  -- is the one moment where "nothing is being dragged" is known for certain.
  if ghost then ghost:Hide() end

  --- Stop any drag in flight, put the chrome away, and give every handle back. Idempotent.
  ---
  --- A HOST MUST CALL THIS BEFORE IT RENDERS ANYTHING, not merely before it rebuilds the list.
  --- Releasing a handle is what takes it off the host frame it was parented to, and that frame goes
  --- back into the host framework's pool the moment the host clears its page -- so a Cancel that
  --- runs after the page has started rebuilding is a Cancel that runs after some unrelated widget
  --- has already been handed the frame with a live handle still sitting on it.
  function list:Cancel()
    self.dead = true
    if ghost then ghost:Hide() end
    if self.line then self.line:Hide() end

    local row = self.dragging
    if row then
      row.frame:SetScript("OnUpdate", nil)
      if row.frame.SetAlpha then row.frame:SetAlpha(1) end
      row.startY = nil
    end
    self.dragging = nil

    local n = #self.handles
    for i = n, 1, -1 do
      local handle = self.handles[i]
      self.handles[i] = nil
      handle.__row = nil
      handle:Hide()
      handle:ClearAllPoints()
      handle:SetParent(atticFrame())
      handlePool[#handlePool + 1] = handle
    end
    if n > 0 then self.say("released %d handles", n) end
  end

  --- Build one handle. Called only when the free list is empty.
  local function newHandle()
    local handle = CreateFrame("Button", nil, atticFrame())
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")

    handle.art = handle:CreateTexture(nil, "ARTWORK")
    handle.art:SetPoint("CENTER", handle, "CENTER", 0, 0)

    -- READ AT FIRE TIME, never captured. A pooled handle outlives the controller that last used
    -- it, so a handler closing over either the row or the controller would drive a dead one --
    -- which is a drag that works once and then freezes.
    handle:SetScript("OnMouseDown", function(self) beginDrag(self.__row) end)
    handle:SetScript("OnDragStart", function(self) beginDrag(self.__row) end)
    handle:SetScript("OnMouseUp",   function(self) finishDrag(self.__row) end)
    handle:SetScript("OnDragStop",  function(self) finishDrag(self.__row) end)

    -- GOLD ON HOVER, so the handle says it is a control before you press it. The tint is the
    -- host's to choose and the default is the collection's gold; a host that wants its list's
    -- affordance to match its own palette says so, and one that says nothing matches everyone
    -- else's.
    handle:SetScript("OnEnter", function(self)
      local h = self.__hoverColor
      self.art:SetVertexColor(h[1], h[2], h[3])
      local tip = self.__tooltip
      if tip and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tip, 1, 1, 1)
        GameTooltip:Show()
      end
    end)
    handle:SetScript("OnLeave", function(self)
      local c = self.__restColor
      self.art:SetVertexColor(c[1], c[2], c[3])
      if GameTooltip then GameTooltip:Hide() end
    end)

    return handle
  end

  --- Register one row, in display order, and get back the handle that drags it.
  ---
  --- `spec.draggable = false` registers the row WITHOUT a handle. The row still counts for indices
  --- and still anchors the insertion line -- it is a place a drag can land, just not one a drag can
  --- start from. MultiMeters' hidden columns are that case: they have an order among themselves
  --- that nobody can act on, and offering a handle for it was offering a gesture with no meaning.
  function list:AddRow(frame, spec)
    spec = spec or {}

    local row = {
      list           = list,
      frame          = frame,
      index          = #self.rows + 1,
      ghostText      = spec.ghostText,
      ghostIcon      = spec.ghostIcon,
      ghostIconColor = spec.ghostIconColor,
      ghostTextColor = spec.ghostTextColor,
      height         = spec.height,
    }
    self.rows[row.index] = row

    if spec.draggable == false then return nil end

    local parent = spec.parent or frame
    local handle = table.remove(handlePool) or newHandle()
    self.handles[#self.handles + 1] = handle

    handle.__row        = row
    handle.__restColor  = opts.handleColor or { 0.7, 0.7, 0.7 }
    handle.__hoverColor = opts.handleHoverColor or { 1, 0.82, 0 }
    handle.__tooltip    = opts.handleTooltip

    handle:SetParent(parent)
    handle:SetSize(opts.handleSize or 24, spec.height or self.stride)
    handle:ClearAllPoints()
    handle:SetPoint("LEFT", parent, "LEFT", opts.handleInset or 0, 0)

    local size = opts.iconSize or 16
    handle.art:SetSize(size, size)
    handle.art:SetTexture(opts.handleIcon or HANDLE_FALLBACK)
    handle.art:SetVertexColor(handle.__restColor[1], handle.__restColor[2], handle.__restColor[3])
    handle:Show()

    row.handle = handle
    return handle
  end

  --- Name the frame the insertion line should live on -- normally the scroll's content frame, or
  --- whatever the rows share as a parent. Call it once, after the rows.
  function list:Finish(container)
    self.line = ensureLine(container, self.color)
    if self.line then self.line:Hide() end
    self.say("painted %d rows, %d draggable, boundary=%s",
      #self.rows, #self.handles, tostring(self.boundary or 0))
    return self.line
  end

  return list
end
