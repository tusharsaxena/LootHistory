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
-- and no icon fallback (with no icon the text moves to the left edge). Re-check trigger for all five:
-- a consumer needs a different color, a tooltip renderer or a measured height with the same
-- semantics as another. Placement was a sixth rejection ("host layout, around TEST_STRIP.HEIGHT")
-- until minor 27, when the owner's 2026-11-15 rulings put every window's strip directly under its
-- title bar and every HUD's on its top edge: the docking (`opts.dock`, `lib.DockTestStrip`, THE
-- DOCKING below) is the library's, so no host anchors one by hand. Showing it stays the host's.
--
-- ── THE FOOTER (minor 27) ─────────────────────────────────────────────────────────────────────
--
-- `lib.Footer` is the band along a window's bottom edge, in the look the owner ruled on 2026-11-15
-- (Ka0s Combat Trail's HUD and race windows): no fill, a one-pixel hairline in `divider` along its
-- top, a left and an optional right line in `text.muted`, an optional slot of catalog marks on the
-- right, and the resize grip's corner. `FOOTER.HEIGHT` (24) is skin-invariant, like the title bar's
-- `title.height`. Every string and every mark's action stay the host's.
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
-- Minors 18 to 20 (causes L6, L8 and FS-FIX of Ka0sAddonsCommonTasks docs/2026-11-01-FULL_SKINNING):
-- lib.__ownedMark (an owned control with no host art draws the Ka0s icon, the strip's in `icon.tint`);
-- an owned menu's glyph column in `font.mono`, a host's named face its template; an owned dropdown's
-- tick and arrow follow a switch and the Scope, live.
-- Minor 21 (FS-FIX): `lib.ContextMenu`; the row options `title`, `disabled`, `divider`, `tooltip`,
-- `keepOpen`; onSelect takes the row; one-line labels. Minor 22 (R5-L5): `lib.IconText`.
-- Minor 23 (G4 of OutfitterReborn's smoke round 2): cascading menus (`submenu`, `radio`, `selected`).
-- Minors 24 and 25 (SF1-L1, SF2-L1 of docs/2026-11-06-REVENDOR_LIBKA0S_V1_89): one-PHYSICAL-pixel
-- edges (lib.__pixelEdged) and lines (lib.__pixelLine), re-sized on a scale change.
-- Minor 26 (FU-L2): the dropdown and its menus moved, unchanged, to WidgetsDropdown.lua (layout-§1).
-- Minor 27 (the owner's 2026-11-15 window-chrome rulings): lib.Footer and lib.FOOTER (THE FOOTER), and
-- the strip's docking, `opts.dock` / lib.DockTestStrip, with Place, BodyOffset and IsFlipped.
-- Minor 28 (RangeMaster#17): the HUD dock's measurements are guarded; one the client refuses (a
-- region anchored to a nameplate) answers nil, and the strip sits on the display's top edge.
-- Minor 30 (LibKa0s#94): the footer lays only its SHOWN marks, re-laid on a mark's show or hide, the
-- footer's show and `foot:Relayout()`. And (SD-LK-97.1, LibKa0s#97): THE OWNER CHECK, below.
local MAJOR, MINOR = "LibKa0s-Widgets-1.0", 30
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

-- ── THE OWNER CHECK (minor 30, SD-LK-97.1 of LibKa0s#97) ─────────────────────────────────────
--
-- A widget built with no owner inside an owned window draws Ka0s Default under every skin, silently.
-- A host that registers a sink (its debug line writer, which writes only while its logging is on)
-- hears of each one; nothing is walked until some host registers one. The owner is NOT inferred: a
-- widget owner-less on purpose (a stock twin) would change its look at re-vendor.
lib.__ownerSinks = lib.__ownerSinks or {}
lib.__ownerWarned = lib.__ownerWarned or setmetatable({}, { __mode = "k" })

--- The nearest frame from `parent` up that a registered owner's skin painted, and that owner.
local function paintedAncestor(Skin, parent)
  local f, depth = parent, 0
  while type(f) == "table" and depth < 32 do
    local rec = Skin.painted[f]
    if rec and Skin:IsOwner(rec.owner) then return f, rec.owner end
    f = type(f.GetParent) == "function" and f:GetParent() or nil
    depth = depth + 1
  end
end

--- Hear of every library widget built with no registered skin owner inside a frame `owner`'s skin
--- paints: `sink(message, widget, frame)`, under pcall, once per widget. A nil sink stops it.
function lib.OwnerWarnings(owner, sink)
  if type(owner) ~= "string" or owner == "" then return end
  lib.__ownerSinks[owner] = type(sink) == "function" and sink or nil
end

-- Tell `who`'s sink of `widget`, built with `owner` (nil or unregistered) inside `frame`.
local function warnOwner(sink, widget, frame, who, owner, kind)
  local name = type(frame.GetName) == "function" and frame:GetName() or nil
  local given = owner == nil and "no skin owner" or ("the unregistered owner %q"):format(tostring(owner))
  local ok, err = pcall(sink, ("LibKa0s: a %s was built with %s inside %s, which %s's skin paints; pass owner = %q"
    .. " so it follows the skin"):format(tostring(kind), given, name or "an unnamed frame", who, who), widget, frame)
  if not ok and type(geterrorhandler) == "function" then geterrorhandler()(err) end
end

--- The check each constructor runs on what it built (`kind` names it in the message). Internal.
function lib.__checkOwner(widget, parent, owner, kind)
  if next(lib.__ownerSinks) == nil or type(widget) ~= "table" or lib.__ownerWarned[widget] then return end
  if skinOf(owner) then return end
  local Skin = LibStub("LibKa0s-Skin-1.0", true)
  if not (Skin and type(Skin.painted) == "table" and type(Skin.IsOwner) == "function") then return end
  local frame, who = paintedAncestor(Skin, parent)
  local sink = who and lib.__ownerSinks[who]
  if not sink then return end
  lib.__ownerWarned[widget] = true
  warnOwner(sink, widget, frame, who, owner, kind)
end

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
  lib.__checkOwner(box, parent, opts.owner, "SearchBox")
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
--- returns an undocked strip never anchors, shows, hides, re-measures or changes its height or its
--- text's anchors, so a host's later `SetHeight`, `strip.text:SetWordWrap` and `strip.text:SetText`
--- stick. A docked one (`opts.dock`, minor 27, THE DOCKING) anchors itself and nothing more: it is
--- still born hidden, and the host still shows and hides it. The icon art is HOST-PASSED, a resolved path or a fileID (the host's `info` icon),
--- because this file cannot call Media (the header): a host that passes one declares that icon's
--- name. The fill and the icon are stored as `__fill` / `__icon`, which are not the contract.
---
--- @param parent table     the frame to parent it to
--- @param opts table|nil   { text, icon, kind = 'test'|'sim'|nil, owner, panel, sim, onEnd, L, and from
---                         minor 27 the docking fields: dock = 'title'|'hud', titleBar, window, inset,
---                         onOffset, target, gap, clear (lib.DockTestStrip's spec) }; text is the host's
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

  -- A HUD's strip takes no mouse (THE DOCKING), so it never wires the menu.
  if opts.dock ~= "hud" then stripMenu(s, opts) end
  s:Hide()   -- born hidden, so it never flashes at the parent's center
  if opts.dock ~= nil then lib.DockTestStrip(s, opts) end
  lib.__checkOwner(s, parent, opts.owner, "TestStrip")
  return s
end

-- ── THE DOCKING (minor 27) ────────────────────────────────────────────────────────────────────
--
-- The owner's 2026-11-15 rulings (WowAddonStandards v2.110.0, preview-mode's *Where the strip sits*):
--
--   * dock = "title": in a window, directly under its title bar, full width, above tabs, a filter bar
--     and the body. Everything below the title bar moves down by `strip:BodyOffset()` while it shows
--     (the strip's height; 0 while hidden), and `spec.onOffset(offset, strip)` is told on each show
--     and hide, so the host relays its body without anchoring the strip. `spec.window`: while the
--     title bar is hidden (a headerless layout that still draws its body) the strip sits on the
--     window's top edge instead. `spec.inset` pulls both sides in (default 0).
--   * dock = "hud": on a HUD display's top edge, OUTSIDE it, where a header would be, spanning its
--     width, `spec.gap` (default 0) above it, and flipped under its bottom edge while the top would
--     leave the screen. It takes no mouse, takes the display's strata one chrome level above it
--     (frame-layering-§2), and moves with it. `spec.clear` is a frame (the display's drag handle)
--     the strip stacks beyond while that frame shows, so it never overlaps it.
--
-- The strip re-places itself when it shows, when the title bar, the window, the display or the clear
-- frame shows, hides or resizes; a host that MOVES a display calls `strip:Place()` after the move,
-- since a move fires no script. The strip never shows or hides itself.
--
-- Every measurement goes through `measure` (minor 28): a display anchored to a nameplate cannot be
-- measured, the client raising on the read, so a refused read answers nil, which the placement reads
-- as "no flip" and "nothing to clear". The strip still docks on such a display's top edge. A value
-- the client calls secret (`issecretvalue`) is no number either (minor 29, LibKa0s#95): an attached
-- display's height, edges or level can read secret out of combat, and arithmetic on one raises.

local STRIP_HUD_LEVEL = 5   -- the display's chrome band: this many levels over the display

local function num(v)
  if type(v) ~= "number" then return nil end
  local secret = issecretvalue
  if secret and secret(v) then return nil end
  return v
end
local function shown(f) return type(f) == "table" and type(f.IsShown) == "function" and f:IsShown() == true end

local function call(f, method, ...)
  local fn = type(f) == "table" and f[method]
  if type(fn) == "function" then return fn(f, ...) end
  return nil
end

--- `f:method()` as a number, or nil: nil too when the client refuses the read (a region anchored to a
--- nameplate, "Can't measure restricted regions"), which raises rather than answering (minor 28).
local function measure(f, method)
  local fn = type(f) == "table" and f[method]
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, f)
  return ok and num(v) or nil
end

--- The screen's top in screen pixels, and `f`'s top and bottom in the same units, or nil.
local function screenEdges(f)
  local scale = measure(f, "GetEffectiveScale") or 1
  local top, bottom = measure(f, "GetTop"), measure(f, "GetBottom")
  return top and top * scale, bottom and bottom * scale, scale
end

local function screenTop()
  local ui = UIParent
  local top = measure(ui, "GetTop")
  return top and top * (measure(ui, "GetEffectiveScale") or 1)
end

local function stripHeight(s)
  return measure(s, "GetHeight") or STRIP_H
end

--- How far past the display's top (or bottom, `below`) the clear frame reaches while it shows, in
--- the strip's units; 0 when it does not show or cannot say.
local function clearReach(s, d, below)
  if not shown(d.clear) then return 0 end
  local tTop, tBottom = screenEdges(d.target)
  local cTop, cBottom = screenEdges(d.clear)
  local scale = measure(s, "GetEffectiveScale") or 1
  local reach
  if below then reach = tBottom and cBottom and (tBottom - cBottom) else reach = cTop and tTop and (cTop - tTop) end
  if not reach or reach <= 0 then return 0 end
  return reach / scale
end

--- True while the strip on the display's top edge would reach past the screen's top.
local function wouldLeaveTop(s, d, lift)
  local sTop = screenTop()
  local tTop = screenEdges(d.target)
  if not (sTop and tTop) then return false end
  local scale = measure(s, "GetEffectiveScale") or 1
  return tTop + (lift + stripHeight(s)) * scale > sTop + 0.5
end

local function placeHud(s, d)
  local t = d.target
  local gap = num(d.gap) or 0
  local up = gap + clearReach(s, d, false)
  local flip = wouldLeaveTop(s, d, up)
  s:ClearAllPoints()
  if flip then
    local down = gap + clearReach(s, d, true)
    s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -down)
    s:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT", 0, -down)
  else
    s:SetPoint("BOTTOMLEFT", t, "TOPLEFT", 0, up)
    s:SetPoint("BOTTOMRIGHT", t, "TOPRIGHT", 0, up)
  end
  s.__flipped = flip
  local strata = call(t, "GetFrameStrata")
  if type(strata) == "string" then call(s, "SetFrameStrata", strata) end
  local level = num(call(t, "GetFrameLevel"))
  if level then call(s, "SetFrameLevel", level + STRIP_HUD_LEVEL) end
end

local function placeTitle(s, d)
  local inset = num(d.inset) or 0
  local bar = d.titleBar
  s:ClearAllPoints()
  if type(d.window) == "table" and not shown(bar) then
    s:SetPoint("TOPLEFT", d.window, "TOPLEFT", inset, -inset)
    s:SetPoint("TOPRIGHT", d.window, "TOPRIGHT", -inset, -inset)
  else
    s:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", inset, 0)
    s:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -inset, 0)
  end
  s.__flipped = false
end

--- Anchor a docked strip where its dock puts it, now. A no-op on an undocked strip.
local function place(s)
  local d = s.__dock
  if not d then return end
  if d.dock == "hud" then placeHud(s, d) else placeTitle(s, d) end
end

--- The strip's height while a title-docked strip shows, else 0: what the host moves its body by.
local function bodyOffset(s)
  local d = s.__dock
  if not d or d.dock ~= "title" or not shown(s) then return 0 end
  return stripHeight(s)
end

local function tellOffset(s)
  local d = s.__dock
  if d and type(d.onOffset) == "function" then d.onOffset(bodyOffset(s), s) end
end

--- Hook `frame`'s `scripts` once per strip, each re-placing the strip while it is docked.
local function watch(s, frame, scripts)
  if type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return end
  s.__dockHooked = s.__dockHooked or setmetatable({}, { __mode = "k" })
  if s.__dockHooked[frame] then return end
  s.__dockHooked[frame] = true
  for _, name in ipairs(scripts) do
    frame:HookScript(name, function() place(s) end)
  end
end

local RELAYOUT = { "OnShow", "OnHide", "OnSizeChanged" }

--- Read a dock spec into the strip's record, or nil when it names no usable dock.
local function dockOf(spec)
  if spec.dock == "title" and type(spec.titleBar) == "table" then
    return { dock = "title", titleBar = spec.titleBar, window = spec.window, inset = spec.inset,
             onOffset = spec.onOffset }
  end
  if spec.dock == "hud" and type(spec.target) == "table" then
    return { dock = "hud", target = spec.target, gap = spec.gap, clear = spec.clear }
  end
  return nil
end

local function wireStrip(s)
  if s.__dockWired then return end
  s.__dockWired = true
  s:HookScript("OnShow", function(self) place(self); tellOffset(self) end)
  s:HookScript("OnHide", tellOffset)
end

--- Dock `strip` (a `lib.TestStrip`) by `spec`: { dock = "title", titleBar, window, inset, onOffset }
--- or { dock = "hud", target, gap, clear } (THE DOCKING). Anchors it now, re-places it on every
--- show, and gives it `strip:Place()`, `strip:BodyOffset()` and `strip:IsFlipped()`. A HUD's strip
--- has its mouse turned off and its menu unwired. A spec with no usable dock changes nothing and
--- answers nil; otherwise answers the strip. Never shows or hides it. Docking again replaces the dock.
--- @param strip table
--- @param spec table
--- @return table|nil
function lib.DockTestStrip(strip, spec)
  if type(strip) ~= "table" or type(spec) ~= "table" then return nil end
  local d = dockOf(spec)
  if not d then return nil end
  strip.__dock = d
  strip.Place = place
  strip.BodyOffset = bodyOffset
  strip.IsFlipped = function(self) return self.__flipped == true end
  if d.dock == "hud" then
    strip:EnableMouse(false)
    strip:SetScript("OnMouseUp", nil)
    watch(strip, d.target, RELAYOUT)
    watch(strip, d.clear, RELAYOUT)
  else
    watch(strip, d.titleBar, RELAYOUT)
    watch(strip, d.window, RELAYOUT)
  end
  if type(strip.HookScript) == "function" then wireStrip(strip) end
  place(strip)
  return strip
end

-- ── the footer (minor 27; the header's THE FOOTER) ──────────────────────────────────────────

-- The figures, file-local like STRIP_H, so a write to lib.FOOTER moves no footer. GRIP is the right
-- inset that clears Core.MakeResizable's grip (16 px, 1 px in from the corner) with a gap, the
-- figure DebugLogWindow's line counter clears it by.
local FOOT_H, FOOT_PAD, FOOT_GRIP = 24, 8, 22
local FOOT_MARK, FOOT_MARK_ART, FOOT_MARK_GAP = 16, 12, 4
-- Ka0s Default's `divider` (Core.SKIN.divider), `text.muted` and the marks' `icon.tint` / `icon.hot`,
-- for a footer with no registered owner.
local FOOT_LINE  = { 0.24, 0.24, 0.27, 0.85 }
local FOOT_TEXT  = { 0.7, 0.7, 0.72 }
local MARK_REST  = { 0.7, 0.7, 0.72 }
local MARK_HOT   = { 1, 1, 1 }

--- Read-only layout figures (the TEST_STRIP precedent): the footer's height, its side padding, the
--- right inset that clears the resize grip, and a mark's slot, art and pitch. Skin-invariant.
lib.FOOTER = { HEIGHT = FOOT_H, PAD = FOOT_PAD, GRIP = FOOT_GRIP,
               MARK = FOOT_MARK, MARK_ART = FOOT_MARK_ART, MARK_GAP = FOOT_MARK_GAP }

local function footText(foot, justify)
  local fs = foot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetJustifyH(justify)
  fs:SetWordWrap(false)
  fs:SetText("")
  if not foot.__skin then fs:SetTextColor(FOOT_TEXT[1], FOOT_TEXT[2], FOOT_TEXT[3]) end
  return fs
end

--- A mark's tint at rest or under the pointer: the owner's `icon.tint` / `icon.hot`, else Ka0s Default's.
local function tintMark(foot, tex, hot)
  local Skin = foot.__skin
  if Skin then
    Skin:For(foot.__owner).Mark(tex, hot and { token = "icon.hot" } or nil)
  else
    local c = hot and MARK_HOT or MARK_REST
    tex:SetVertexColor(c[1], c[2], c[3])
  end
end

--- One mark of the control slot: a Button FOOTER.MARK square, its art FOOTER.MARK_ART, host-passed.
local function footMark(foot, spec)
  local b = CreateFrame("Button", nil, foot)
  b:SetSize(FOOT_MARK, FOOT_MARK)
  local tex = b:CreateTexture(nil, "ARTWORK")
  tex:SetSize(FOOT_MARK_ART, FOOT_MARK_ART)
  tex:SetPoint("CENTER", b, "CENTER", 0, 0)
  if type(spec.icon) == "string" or type(spec.icon) == "number" then tex:SetTexture(spec.icon) end
  b.icon = tex
  tintMark(foot, tex, false)
  local onEnter, onLeave, onClick = spec.onEnter, spec.onLeave, spec.onClick
  b:SetScript("OnEnter", function(self)
    tintMark(foot, tex, true)
    if type(onEnter) == "function" then onEnter(self) end
  end)
  b:SetScript("OnLeave", function(self)
    tintMark(foot, tex, false)
    if type(onLeave) == "function" then onLeave(self) end
  end)
  b:SetScript("OnClick", function(self, button)
    if type(onClick) == "function" then onClick(self, button) end
  end)
  return b
end

--- Lay the footer's right side from its corner in: the grip's inset (or the padding), the SHOWN
--- marks outermost first, then the right line; the left line runs up to the right line. A hidden
--- mark takes no slot (minor 30, LibKa0s#94): it is anchored where the next shown one goes, so it
--- keeps a point, and the chain does not advance past it.
local function footLayout(foot)
  local edge = foot.__grip and FOOT_GRIP or FOOT_PAD
  local anchor, point, x = foot, "RIGHT", -edge
  for _, b in ipairs(foot.marks) do
    b:ClearAllPoints()
    b:SetPoint("RIGHT", anchor, point, x, 0)
    if b:IsShown() then anchor, point, x = b, "LEFT", -FOOT_MARK_GAP end
  end
  if anchor ~= foot then x = -FOOT_PAD end
  foot.right:ClearAllPoints()
  foot.right:SetPoint("RIGHT", anchor, point, x, 0)
  foot.left:ClearAllPoints()
  foot.left:SetPoint("LEFT", foot, "LEFT", FOOT_PAD, 0)
  foot.left:SetPoint("RIGHT", foot.right, "LEFT", -FOOT_PAD, 0)
end

local function footSet(fs, text) fs:SetText(type(text) == "string" and text or "") end

--- A registered owner's footer: the hairline in `divider` and both lines in `text.muted`, recorded,
--- so they follow its skin switches. A window's footer: neither Ignore switch's panel half applies.
local function skinFooter(foot)
  local S = foot.__skin:For(foot.__owner)
  S.Divider(foot.line)
  S.Text(foot.left, "muted")
  S.Text(foot.right, "muted")
end

--- `opts.resize`: Core.MakeResizable on `parent` with the grip built on the footer (`gripParent`),
--- so it sits in the footer's bottom-right corner, which is the window's. A copy of the host's
--- table: `gripParent` and `owner` default to the footer and the footer's owner.
local function footResize(foot, parent, resize, owner)
  local core1 = LibStub and LibStub("LibKa0s-Core-1.0", true)
  if not (core1 and type(core1.MakeResizable) == "function") then return nil end
  local o = {}
  for k, v in pairs(resize) do o[k] = v end
  if o.gripParent == nil then o.gripParent = foot end
  if o.owner == nil then o.owner = owner end
  return core1.MakeResizable(parent, o)
end

--- Build a window's footer (minor 27): a bare Frame `FOOTER.HEIGHT` (24) tall across `parent`'s
--- bottom edge, BORN SHOWN and anchored, with no fill. It draws a one-physical-pixel hairline along
--- its top, `opts.inset` (1) in from each side so it meets the window's edge; `foot.left` (the
--- status line, LEFT at PAD) and `foot.right` (RIGHT, clear of the marks), both one line, in
--- `text.muted`; the control slot, `opts.marks` laid right to left from the corner, outermost first,
--- the hidden ones skipped (minor 30); and, with `opts.grip` or `opts.resize`, the right inset that
--- clears the resize grip's corner. A mark's OnShow or OnHide, and the footer's own OnShow, re-lay
--- it (hooked once each); `foot:Relayout()` re-lays it on demand.
---
--- The host owns every string (`foot:SetLeft`, `foot:SetRight`), every mark's art, action and
--- tooltip, and when the footer shows; a host that hides it gives `FOOTER.HEIGHT` back to its body.
--- Mark art is HOST-PASSED, a resolved path or a fileID (this file cannot call Media, the header),
--- and the host declares each name.
---
--- @param parent table     the window
--- @param opts table|nil   { left, right, marks = { { icon, onClick(btn, button), onEnter(btn),
---                         onLeave(btn) }, ... }, grip = bool, resize = Core.MakeResizable opts,
---                         inset = number, owner = string }; `owner` a registered skin owner
--- @return table  the Frame, with `foot.line` (Texture), `foot.left`, `foot.right` (FontStrings),
---                `foot.marks` (Buttons, each with `.icon`), `foot.grip` (the grip `opts.resize`
---                made, or nil), and `foot:SetLeft(text)`, `foot:SetRight(text)`, `foot:SetGrip(on)`,
---                `foot:Relayout()`
function lib.Footer(parent, opts)
  opts = type(opts) == "table" and opts or {}
  local foot = CreateFrame("Frame", nil, parent)
  foot:SetHeight(FOOT_H)   -- the local, not lib.FOOTER: a host write cannot move it
  foot:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  foot:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  foot.__skin, foot.__owner = skinOf(opts.owner), opts.owner

  local inset = num(opts.inset) or 1
  local line = foot:CreateTexture(nil, "ARTWORK")
  line:SetPoint("TOPLEFT", foot, "TOPLEFT", inset, 0)
  line:SetPoint("TOPRIGHT", foot, "TOPRIGHT", -inset, 0)
  line:SetColorTexture(FOOT_LINE[1], FOOT_LINE[2], FOOT_LINE[3], FOOT_LINE[4])
  pixelLine(line, foot, true)
  foot.line = line

  foot.left, foot.right = footText(foot, "LEFT"), footText(foot, "RIGHT")
  footSet(foot.left, opts.left)
  footSet(foot.right, opts.right)
  foot.marks = {}
  for _, spec in ipairs(type(opts.marks) == "table" and opts.marks or {}) do
    if type(spec) == "table" then foot.marks[#foot.marks + 1] = footMark(foot, spec) end
  end
  if foot.__skin then skinFooter(foot) end

  foot.SetLeft = function(self, text) footSet(self.left, text) end
  foot.SetRight = function(self, text) footSet(self.right, text) end
  foot.SetGrip = function(self, on) self.__grip = on and true or nil; footLayout(self) end
  foot.Relayout = function(self) footLayout(self) end
  foot.__grip = (opts.grip == true or type(opts.resize) == "table") or nil
  -- A host shows or hides a mark per tab: each mark's show and hide re-lay the footer. The client
  -- fires neither on a mark whose window is hidden, so the footer's own show re-lays it too.
  local function relay() footLayout(foot) end
  for _, b in ipairs(foot.marks) do
    b:HookScript("OnShow", relay)
    b:HookScript("OnHide", relay)
  end
  foot:HookScript("OnShow", relay)
  footLayout(foot)
  if type(opts.resize) == "table" then foot.grip = footResize(foot, parent, opts.resize, opts.owner) end
  lib.__checkOwner(foot, parent, opts.owner, "Footer")
  return foot
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
