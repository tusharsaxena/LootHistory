-- LibKa0s-Widgets-1.0 — the collection's flat dropdown, the one popup menu every instance of it
-- drops, the flat search box a filter bar puts beside it, and the mode strip (test mode or a
-- simulation) a window lays over data that is not the player's (minor 15).
--
-- ── WHY THIS IS A LIBRARY AND NOT A COPY ──────────────────────────────────────────────────────
--
-- It was BankLedger's, local to modules/Browser.lua, and about to be MultiMeters' too. Two copies
-- of a widget is two skins to keep in step, the argument the icons were consolidated under at v1.9.0.
--
-- The test-mode strip (`lib.TestStrip`, #48) is here for the same reason: DropWatcher drew it and
-- three hosts each marked test mode their own way. The owner's 2026-10-22 ruling promoted it, so all
-- four say "this is not your data" with one band, in one color, at one height.
--
-- The same strip marks a simulation (`opts.kind = "sim"`, minor 14, the owner's 2026-10-23 ruling): a
-- flavor of `TestStrip`, with its own cyan tint. A `ModeStrip` constructor with `TestStrip` kept as an
-- alias was REJECTED: a second name for one function, which the four hosts would not call anyway.
-- Re-check trigger: a third kind is asked for.
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
-- `lib.SearchBox`, below), no keyboard navigation and no scrolling for a long list. Neither is
-- wanted by a shipped consumer, and each is reachable later without a major bump. Row options and a
-- public open arrived with the hosts that needed them (minor 21), and cascading sub-menus with the
-- one that needed them (minor 23, W.ContextMenu only; a dropdown's rows are its values).
--
-- Two flat controls were censused with the search box at minor 13 (#52) and REJECTED:
--
--   * `W.Checkbox`. No consumer draws one. Re-check trigger: a second addon hand-builds a flat one.
--   * An exported flat skin (the `SKIN` table below, or an applier). The dropdown and the search box
--     are its only readers, and the autocomplete publishes its own copy as `AUTOCOMPLETE.BORDER` /
--     `.BG`. Re-check trigger: a third flat control outside this file copies the literals.
--
-- The test-mode strip is a band, a mark and a line of text, and deliberately nothing more. No
-- tooltip option (three hosts, three renderers; a host enables the mouse and hooks OnEnter), no color
-- option (the sameness is the point: test and sim are the library's), no wrap, measuring or
-- `Height()` (one host wraps, and one must never measure), no test-mode state (the host decides),
-- no placement or body shift (host layout, around `TEST_STRIP.HEIGHT`), and no icon fallback (with no
-- icon the text moves to the left edge). Re-check trigger for all six: a consumer needs a different
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
-- ── THE SCOPE SWITCHES (minor 17) ─────────────────────────────────────────────────────────────
--
-- An owned control draws EVERY string it makes in its skin's body face, through the facade: the
-- menu's rows (and the string the menu is measured on), the strip's line (in `text.accent`, the
-- template's gold under Ka0s Default), and, in the secondary files, the autocomplete's rows, the
-- chart's tick labels and the drag handle's label. Under Ka0s Default that face is Oxanium where the
-- template drew Friz Quadrata (decision D-13). The paint is recorded, so the owner's "Ignore fonts"
-- gives each string its template back, live. A face a host named (`opts.font`, `spec.labelFont`) is
-- that template from minor 19: the skin's face goes over it, and an owner-less control keeps it.
-- `opts.glyphFont` is the menu's glyph column, whose owned face is `font.mono` (minor 19).
--
-- `opts.panel = true` on any owned constructor (Dropdown, SearchBox, TestStrip, Autocomplete,
-- LineChart, DragHandle) says the control sits on its owner's SETTINGS PAGE: while that owner ignores
-- its settings panel (`Skin:GetIgnore(owner)`'s panel half) the control is drawn as an owner-less one,
-- live both ways, as the AceGUI rows and the reorder list are. Without it a control is a window's,
-- and wears the skin whatever that switch says (decisions D-01, D-02). LK-06a of
-- Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_LIBRARY_FOLLOWUPS, ruling R-5.
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on no addon framework.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

-- Minor 15: the shared dropdown menu is clamped to the screen (EnsureMenu), so a dropdown near a
-- screen edge drops a menu that stays on screen (frame-layering-§4; XS-22).
-- Minor 16: the skin owner (the header's SKIN OWNERS).
-- Minor 17: the scope switches (the header's THE SCOPE SWITCHES): every string an owned control draws
-- in its skin's body face, and `opts.panel`.
-- Minor 18 (cause L6 of Ka0sAddonsCommonTasks docs/2026-11-01-FULL_SKINNING): lib.__ownedMark. An owned
-- control a host gave no art draws the Ka0s icon, not the client rung, and the strip's icon wears
-- `icon.tint`.
-- Minor 19 (cause L8 of the same bundle): an owned menu's glyph column reads the skin's `font.mono`; a
-- host's `glyphFont` is what turns the column on, and what an owner-less menu and Ignore fonts draw.
-- A face a host names on an owned control (`opts.font`, `spec.labelFont`) is now its template.
-- Minor 20 (FS-FIX of the same bundle): an owned dropdown's tick and arrow follow a skin switch and
-- the Scope, live, where they were baked in the constructor.
-- Minor 21 (FS-FIX of the same bundle): `lib.ContextMenu`, the shared menu opened by a host; the row
-- options `title`, `disabled`, `divider`, `tooltip` and `keepOpen`, for a dropdown too; onSelect takes
-- the row; the dropdown's label is one line.
-- Minor 22 (R5-L5 of Ka0sAddonsCommonTasks docs/2026-11-03-SMOKE_ROUND5): `lib.IconText`, inline icon
-- markup cropped by the icon rule.
-- Minor 23 (G4 of OutfitterReborn docs/superpowers/specs/2026-11-05-smoke-round-2-design.md): cascading
-- menus. A W.ContextMenu row's `submenu = rows` opens a child menu beside the row, one pooled frame
-- per depth, the parent kept; the row options `radio` and `selected` draw a tick column.
-- Minor 24 (SF1-L1 of Ka0sAddonsCommonTasks docs/2026-11-06-REVENDOR_LIBKA0S_V1_89): the dropdown, the
-- search box and every menu level draw a one-PHYSICAL-pixel edge at any UI scale (lib.__pixelEdged).
-- Minor 25 (SF2-L1 of the same bundle): lib.__pixelLine. A menu's divider rule, at every cascade depth,
-- is one physical pixel high at any UI scale and re-sized on a scale change, and the row boxes and the
-- drag-handle strips of this major's secondaries are drawn through it.
-- Minor 26 (FU-L2 of Ka0sAddonsCommonTasks docs/2026-11-06-FOLLOWUPS_V1_91): the dropdown and the shared
-- menu it drops (its cascade, lib.ContextMenu and lib.CloseMenu) moved, unchanged, to WidgetsDropdown.lua
-- (layout-§1); the shell hands it lib.__dropdownKit. No member and no behavior changes.
local MAJOR, MINOR = "LibKa0s-Widgets-1.0", 26
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

-- The gray the search box's icon wears without a skin, and again while a panel-scoped one is given
-- back (minor 17).
local SEARCH_ICON_TINT = { 0.7, 0.7, 0.72 }

--- Make `f`'s backdrop edge one physical pixel at any UI scale and sub-pixel position, under every
--- skin and with none (minor 24): Core minor 16's pixel edges, where the live Core has them. A
--- backdrop of `edgeSize = 1` is one UI unit, which drew 1 or 2 px (SF1-L1). Answers `f`.
local function pixelEdged(f)
  if type(core.__PixelBackdrop) == "function" then core.__PixelBackdrop(f) end
  return f
end
lib.__pixelEdged = pixelEdged

-- A texture line one PHYSICAL pixel thick (minor 25, SF2-L1): Core minor 16's `__PixelSize` for the
-- size and its pixel watch for the re-size, the mechanism pixelEdged uses, so a UI scale or display
-- size change, or a SetScale of the holder or an ancestor, re-sizes every line recorded here. Hooks,
-- never an event. Recorded weakly: texture -> { holder, horizontal, n }.
lib.__pxLines = lib.__pxLines or setmetatable({}, { __mode = "k" })

--- Size one recorded line on its holder, now.
local function pxLineApply(tex, e)
  local size = type(core.__PixelSize) == "function" and core.__PixelSize(e.holder, e.n) or e.n
  if e.horizontal then tex:SetHeight(size) else tex:SetWidth(size) end
  return size
end

local function pxLinesRefresh()
  for tex, e in pairs(lib.__pxLines) do pxLineApply(tex, e) end
end

--- Core's pixel-scale listener for this major: the live copy's refresh, so a newer one replaces it.
local function pxLinesListener()
  local live = LibStub and LibStub(MAJOR, true) or lib
  if live.__RefreshPixelLines then live.__RefreshPixelLines() end
end

--- Make `tex` a line `n` physical pixels (1 by default) thick on `holder`: its height where
--- `horizontal`, else its width, sized now and again on every pixel-scale change. Under a Core older
--- than minor 16 it is `n` UI units, as before minor 25. Answers the size it laid.
local function pixelLine(tex, holder, horizontal, n)
  local e = lib.__pxLines[tex] or {}
  e.holder, e.horizontal, e.n = holder, horizontal == true, type(n) == "number" and n or 1
  lib.__pxLines[tex] = e
  local size = pxLineApply(tex, e)
  if type(tex.SetSnapToPixelGrid) == "function" then tex:SetSnapToPixelGrid(true) end
  if type(core.__WatchPixels) == "function" and type(core.__OnPixelScale) == "function" then
    core.__OnPixelScale(MAJOR, pxLinesListener)
    core.__WatchPixels(holder)
  end
  return size
end
lib.__pixelLine = pixelLine
lib.__RefreshPixelLines = pxLinesRefresh

-- ── the skin owner (minor 16; the header's SKIN OWNERS) ──────────────────────────────────────

--- The Skin major when `owner` is a registered skin owner, else nil. Read at call time.
local function skinOf(owner)
  if type(owner) ~= "string" or owner == "" or not LibStub then return nil end
  local Skin = LibStub("LibKa0s-Skin-1.0", true)
  if Skin and type(Skin.IsOwner) == "function" and Skin:IsOwner(owner) then return Skin end
  return nil
end
lib.__skinOf = skinOf

--- True while a control built with `panel` (`opts.panel == true`) sits on the settings page of an
--- owner that ignores its settings panel (minor 17): the control is then drawn as an owner-less one.
--- `Skin` is the Skin major `skinOf` answered, or nil. Read at call time.
local function panelOff(Skin, owner, panel)
  return panel == true and Skin ~= nil and type(Skin.GetIgnore) == "function"
    and Skin:GetIgnore(owner) == true
end
lib.__panelOff = panelOff

--- The path of Media icon `name` in `owner`'s copy for an owned control a host gave no art (minor
--- 18), or nil: no owner, no Media, or a panel-scoped control on an ignored panel, each of which
--- draws its client rung. `name` is one of docs/releasing.md's library-drawn icons, so the host
--- declares it. Read at call time.
local function ownedMark(owner, name, panel)
  local Skin = skinOf(owner)
  if not Skin or panelOff(Skin, owner, panel) then return nil end
  local media = LibStub("LibKa0s-Media-1.0", true)
  return media and type(media.Icon) == "function" and media.Icon(owner, name) or nil
end
lib.__ownedMark = ownedMark

-- Strings __skinFont put a skin face on, so an owner-less paint knows which to give back.
lib.__fonted = lib.__fonted or setmetatable({}, { __mode = "k" })

--- Put `owner`'s body face on `fs` through the owner's facade (minor 17), a recorded paint, so a skin
--- switch and "Ignore fonts" reach it; or, with no `Skin`, give a string this put a face on its
--- `template` back and forget it. A string it never fonted is not touched, so an owner-less control
--- paints exactly what it did.
function lib.__skinFont(fs, owner, Skin, template)
  if type(fs) ~= "table" then return end
  if Skin then
    Skin:For(owner).Font(fs)
    lib.__fonted[fs] = true
    return
  end
  if not lib.__fonted[fs] then return end
  lib.__fonted[fs] = nil
  local S = LibStub("LibKa0s-Skin-1.0", true)
  if S and type(S.Untrack) == "function" then S:Untrack(fs) end
  if template and type(fs.SetFontObject) == "function" then fs:SetFontObject(template) end
end

-- The opts a panel-scoped control hands its primitive. Read-only.
local PANEL = { panel = true }

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

-- The locals the shell and WidgetsDropdown.lua share, handed over at load (minor 26, FU-L2 of
-- Ka0sAddonsCommonTasks docs/2026-11-06-FOLLOWUPS_V1_91): the house flat skin, its edge art, the opts a
-- panel-scoped control hands its primitive, and the token reader. Read-only.
lib.__dropdownKit = { SKIN = SKIN, WHITE = WHITE, PANEL = PANEL, token = token }

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

--- A skinned search box's icon in its owner's `icon.tint` (minor 16), or its own gray while a
--- panel-scoped box's owner ignores its settings panel (minor 17).
local function tintSearchIcon(icon, owner, panel)
  local Skin = skinOf(owner)
  local c = Skin and token(Skin, owner, "icon.tint", nil)
  if panelOff(Skin, owner, panel) then c = SEARCH_ICON_TINT end
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
---                             line and its icon wear that owner's skin; `panel` (minor 17), true
---                             for a box on the owner's settings page (THE SCOPE SWITCHES)
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
  pixelEdged(box)
  box:SetFontObject("GameFontHighlightSmall")
  box:SetAutoFocus(false)

  local icon = opts.icon
  local left = SEARCH_INSET
  if type(icon) == "string" or type(icon) == "number" then
    local tex = box:CreateTexture(nil, "ARTWORK")
    tex:SetSize(SEARCH_ICON_SIZE, SEARCH_ICON_SIZE)
    tex:SetPoint("LEFT", SEARCH_ICON_X, 0)
    tex:SetTexture(icon)
    tex:SetVertexColor(SEARCH_ICON_TINT[1], SEARCH_ICON_TINT[2], SEARCH_ICON_TINT[3])
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
  -- Minor 17: `opts.panel`, the primitive given back and the icon its own gray while ignored.
  local Skin = skinOf(opts.owner)
  if Skin then
    local panel = opts.panel == true
    Skin:For(opts.owner).EditBox(box, panel and PANEL or nil)
    if box.icon then
      local function tint(tex, owner) tintSearchIcon(tex, owner, panel) end
      lib.__onSkin(Skin, opts.owner, box.icon, tint)
      tint(box.icon, opts.owner)
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

--- A tinted strip mark: an owned strip's icon in `icon.tint`, given back while a panel-scoped one is
--- ignored (minor 18).
local function stripMark(s, Skin, owner, panel)
  if s.__icon then Skin:For(owner).Mark(s.__icon, { panel = panel and true or nil }) end
end

-- The strip's icon (host-passed art, optional) and its line, laid out left to right; split out of
-- TestStrip so the constructor stays under CCN 15 (the v1.81.0 release run measured it at 16).
local function stripLine(s, opts)
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
  return text
end

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
--- @param opts table|nil   { text, icon, kind = 'test'|'sim'|nil, owner, panel, sim, onEnd, L }; text is the host's
---                         localized line ('' when absent), no icon puts the text at LEFT+6, any
---                         kind but exactly "sim" (nil, a non-string, "Sim", "preview") is "test",
---                         and `owner` (minor 16) is a registered skin owner whose skin the wash
---                         follows, and the line from minor 17 (`text.accent` in the body face);
---                         `panel` (minor 17), true for a strip on the owner's settings page
--- @return table  the Frame, with `strip.text` (FontString, OVERLAY, GameFontNormalSmall, LEFT at
---                the icon's RIGHT+6 or the strip's LEFT+6, RIGHT at -6, JustifyH LEFT, no wrap)
---                and `strip.kind` ("test" or "sim"), read-only and set once at birth: writing it
---                repaints nothing
-- ── the strip's right-click menu (minor 21, SF-F1) ──
--
-- A right-click opens `lib.ContextMenu` with what the strip can end. `opts.sim` is a Sim instance
-- (`LibKa0s-Sim-1.0`): the library ends it (`:Stop()`), steps it and restarts it, with nothing more
-- from the host. `opts.onEnd` is the host's own end for a mode the library cannot see, a test mode,
-- and it wins over the instance's Stop. A strip given neither takes no mouse, as before.
-- `opts.L` overrides END_TEST, END_SIM, STEP and RESTART.
local STRIP_L = { END_TEST = "End test", END_SIM = "End sim", STEP = "Step", RESTART = "Restart" }

local function stripRows(s, opts, L)
  local sim = opts.sim
  local live = type(sim) == "table" and type(sim.IsActive) == "function" and sim:IsActive()
  local rows = {}
  local function add(key, fn) rows[#rows + 1] = { label = L[key] or STRIP_L[key], value = key, onClick = fn } end
  if type(opts.onEnd) == "function" then
    add(s.kind == "sim" and "END_SIM" or "END_TEST", opts.onEnd)
  elseif live and type(sim.Stop) == "function" then
    add("END_SIM", function() sim:Stop("stop") end)
  end
  if live and type(sim.Steps) == "function" and type(sim.Step) == "function" and #sim:Steps() > 0 then
    add("STEP", function() sim:Step() end)
  end
  if live and type(sim.Restart) == "function" then add("RESTART", function() sim:Restart() end) end
  return rows
end

local function stripMenu(s, opts)
  if type(opts.onEnd) ~= "function" and type(opts.sim) ~= "table" then return end
  local L = type(opts.L) == "table" and opts.L or {}
  s:EnableMouse(true)
  s:SetScript("OnMouseUp", function(self, button)
    if button ~= "RightButton" then return end
    local rows = stripRows(self, opts, L)
    if #rows > 0 then lib.ContextMenu(self, rows, { owner = opts.owner, panel = opts.panel == true, cursor = true }) end
  end)
end

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
  local panel = opts.panel == true
  if Skin then Skin:For(opts.owner).Strip(fill, { kind = kind, panel = panel or nil }) end

  local text = stripLine(s, opts)
  s.text = text
  s.kind = kind
  -- Minor 17: an owned strip's line in `text.accent` and the body face; a panel-scoped strip's fill
  -- is put back to its own wash while ignored (the primitive cannot read a texture's color back).
  if Skin then
    Skin:For(opts.owner).Text(text, "accent", panel and PANEL or nil)
    stripMark(s, Skin, opts.owner, panel)
    if panel then
      lib.__onSkin(Skin, opts.owner, fill, function(f, owner)
        if panelOff(skinOf(owner), owner, true) then f:SetColorTexture(unpack(STRIP_FILL[kind])) end
      end)
    end
  end

  stripMenu(s, opts)
  s:Hide()   -- born unanchored: hidden, so it never flashes at the parent's center
  return s
end

-- ── inline icon markup (minor 22) ────────────────────────────────────────────────────────────

--- Inline `|T...|t` markup for Blizzard icon art (an item, spell, spec, class or currency fileID or
--- path) in a tooltip or chat line, cropped as the icon rule asks (docs/api/README.md's *Icon art*):
--- texcoords 5..59 of 64 a side, 0.078, past the art's own bevel. Markup cannot take an edge, so it
--- is cropped only. `size` is the height, 0 or nil for the line's own; `width` defaults to it. A
--- nil icon answers "". Not for an atlas glyph or a Ka0s catalog mark, which are drawn whole
--- (S.MarkText).
--- @param icon number|string|nil
--- @param size number|nil
--- @param width number|nil
--- @return string
function lib.IconText(icon, size, width)
  if icon == nil then return "" end
  size = tonumber(size) or 0
  width = tonumber(width) or size
  return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(tostring(icon), size, width)
end
