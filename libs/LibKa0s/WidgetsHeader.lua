-- LibKa0s-Widgets-1.0 -- HeaderButtons: the one strip of title-bar marks every window the library
-- draws wears, right-aligned, left to right EXTRAS . SETTINGS . CLOSE (LibKa0s#86).
--
-- ── WHY THIS EXISTS ──────────────────────────────────────────────────────────────────────────
--
-- Every window LibKa0s drew built its own header controls: the debug console its Copy, Clear and
-- close, the copy window, the perf panel and the sim panel a close alone, the skin picker a close in
-- the header and a gear on its dropdown row. So which marks a window carried, their order, their
-- size, their spacing and their paint differed window to window, and no window but the picker could
-- reach its addon's settings. The owner's ruling of 2026-11-16 (Ka0sAddonsCommonTasks
-- docs/2026-11-16-LIBKA0S_ISSUES_75_PLUS, Q3): one strip, close in the corner, settings beside it,
-- a window's own extras inward of it in the window's order. Settings opens the owning addon's
-- settings, found through its launcher (Core minor 18's registry, filled by LibKa0s-Launcher-1.0's
-- New).
--
-- ── WHAT ONE STRIP MEANS ─────────────────────────────────────────────────────────────────────
--
-- One SIZE (an 18 px slot, the close mark's), one ART (12 px, the console's measured shape), one
-- pitch (PAD from the corner, GAP between marks, the console's 6 and 6), one paint path: a registered
-- skin owner's marks through its facade's `Mark` (`icon.tint` at rest, `text.link` under the pointer,
-- recorded, so a skin switch repaints them), every other window's in Ka0s Default's two colors. The
-- hover is `text.link` from smoke round 1's ruling 4 (SR-L3 of the same bundle), where the first cut
-- lit `icon.hot`, a brightening the owner could hardly see: the mark still lights under the pointer,
-- now in the skin's link color, the color the debug console's Diagnostics link wore. The close X
-- rests in `icon.tint` too (every skin's `close.rest` is its `icon.tint`) and keeps `close.hot`. The
-- art is the LibKa0s icon set's, out of the owner's copy (`Media.Icon`); a mark whose art does not
-- answer draws its word or its glyph instead. The `help` icon is not used: twelve addons do not
-- declare it, and a pruned icon draws blank.
--
-- The close mark stays Core.MakeCloseButton's, called with three arguments (standalone-windows,
-- *The Ka0s window edge*), or the host's own factory (`makeClose`), or a button the window already
-- has (`closeButton`, the icon browser's template X). Whichever it is, it says "Close"
-- (LibKa0s-Tooltip-1.0's CloseTip for the owner, or the window's `closeTip`), attached above it in
-- the owner's `gtip.title` by that major's AttachTitleTip; until smoke round 1's ruling 3 (SR-L2 of
-- the same bundle) it said nothing.
--
-- ── TOOLTIPS ─────────────────────────────────────────────────────────────────────────────────
--
-- A mark with a `tip` shows it in the game tooltip, owned at ANCHOR_NONE and placed by the chrome
-- rule, attached and centered ABOVE the mark (below only without room above; SR-L1 of the same
-- bundle's smoke round 1), through LibKa0s-Tooltip-1.0's PlaceAttached (read at hover time; without
-- it, above by a relative point, never at the cursor). Every mark carries one (SR-L2, ruling 3):
-- the first cut's `tips = false`, the debug console's, is retired and accepted unread, because a
-- tooltip above the title bar no longer sits on the log's first line (research note R9 C2's case).
--
-- A file of the Widgets major, paired on the shell's minor with the same multi-file idiom as
-- WidgetsCopyWindow.lua. Depends on LibStub and the Widgets shell; Core, Media, Skin and Tooltip are
-- resolved at call time, and each is optional.

local lib = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
if not lib then return end

-- Minor 1 (LK-86 of Ka0sAddonsCommonTasks docs/2026-11-16-LIBKA0S_ISSUES_75_PLUS, LibKa0s#86).
local HEADER_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own, as WidgetsCopyWindow.lua is.
if lib.__headerMinor and lib.__headerMinor >= HEADER_MINOR
  and lib.__headerShellMinor == lib.MINOR then return end
lib.__headerMinor      = HEADER_MINOR
lib.__headerShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.WidgetsHeader = HEADER_MINOR

local SIZE, ART, PAD, GAP = 18, 12, 6, 6

--- Read-only layout figures (the FOOTER precedent): a mark's slot and art, the inset from the
--- corner and the gap between marks. Skin-invariant.
lib.HEADER = { SIZE = SIZE, ART = ART, PAD = PAD, GAP = GAP }

--- The strip's own words, keyed for a host's `spec.L` override (rawget, as every library string).
lib.HEADER_STRINGS = { SETTINGS_TIP = "Open settings", SETTINGS_GLYPH = "*" }

-- Ka0s Default's `icon.tint` and `text.link` (SR-L3), for a window with no registered skin owner.
local REST = { 0.7, 0.7, 0.72 }
local HOT  = { 1, 0.5, 0 }

local function text(spec, key)
  local L = type(spec.L) == "table" and spec.L or nil
  local v = L and rawget(L, key)
  if type(v) == "string" then return v end
  return lib.HEADER_STRINGS[key]
end

--- `owner`'s copy of Media icon `name`, or nil (no owner, no Media, no name).
local function artOf(owner, name)
  if type(owner) ~= "string" or owner == "" or type(name) ~= "string" then return nil end
  local media = LibStub("LibKa0s-Media-1.0", true)
  return media and type(media.Icon) == "function" and media.Icon(owner, name) or nil
end

--- A mark at rest or under the pointer: the owner's facade (`Mark` for art, `Text` for a word) when
--- it is a registered skin owner, else Ka0s Default's two colors.
local function paint(b, hot)
  local Skin = lib.__skinOf and lib.__skinOf(b.__owner)
  if b.icon then
    if Skin then return Skin:For(b.__owner).Mark(b.icon, hot and { token = "text.link" } or nil) end
    local c = hot and HOT or REST
    return b.icon:SetVertexColor(c[1], c[2], c[3])
  end
  local c = hot and HOT or REST
  if Skin then c = Skin:Token(b.__owner, hot and "text.link" or "icon.tint") or c end
  b.label:SetTextColor(c[1], c[2], c[3])
end

--- The mark's tooltip: its `__tip`, read at hover time, in the owner's `gtip.title`, placed above it.
local function showTip(b)
  local tip, words = GameTooltip, b.__tip
  if type(words) ~= "string" or words == "" or not (tip and tip.SetOwner) then return end
  tip:SetOwner(b, "ANCHOR_NONE")
  local Skin = lib.__skinOf and lib.__skinOf(b.__owner)
  local c = Skin and Skin:Token(b.__owner, "gtip.title")
  if type(c) == "table" then tip:SetText(words, c[1], c[2], c[3], 1, true) else tip:SetText(words, nil, nil, nil, nil, true) end
  tip:Show()
  local Tip = LibStub("LibKa0s-Tooltip-1.0", true)
  if Tip and type(Tip.PlaceAttached) == "function" and Tip.PlaceAttached(tip, b) then return end
  tip:ClearAllPoints()
  tip:SetPoint("BOTTOM", b, "TOP", 0, 2)
end

local function hideTip(b)
  local tip = GameTooltip
  if not (tip and tip.Hide) then return end
  if type(tip.IsOwned) == "function" and not tip:IsOwned(b) then return end
  tip:Hide()
end

--- The mark's face: `spec.icon`'s art out of the owner's copy, else a word or a glyph.
local function dress(b, spec)
  local path = artOf(spec.owner, spec.icon)
  if path then
    b:SetSize(SIZE, SIZE)
    local tex = b:CreateTexture(nil, "OVERLAY")
    tex:SetPoint("CENTER")
    tex:SetSize(ART, ART)
    tex:SetTexture(path)
    b.icon = tex
    return
  end
  b:SetSize(spec.label and spec.width or SIZE, SIZE)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if lib.__skinFont then lib.__skinFont(fs, spec.owner, lib.__skinOf and lib.__skinOf(spec.owner), "GameFontNormalSmall") end
  fs:SetPoint("CENTER")
  fs:SetText(spec.label or spec.glyph or "")
  b.label = fs
end

--- One header mark (minor 1): a SIZE-square Button with `spec.icon`'s art at ART, out of the owner's
--- copy; without the art, `spec.label` as a word `spec.width` wide, else `spec.glyph`. Painted by the
--- one path above; `spec.tip` (also `b.__tip`, read on each hover) is its tooltip.
--- @param parent table
--- @param spec table  { owner, icon, label, width, glyph, tip, onClick(btn, button) }
--- @return table|nil  the Button (`.icon` or `.label`), nil where the client cannot make one
function lib.HeaderButton(parent, spec)
  spec = type(spec) == "table" and spec or {}
  local b = type(CreateFrame) == "function" and CreateFrame("Button", nil, parent) or nil
  if not b then return nil end
  b.__owner, b.__tip = spec.owner, spec.tip
  dress(b, spec)
  paint(b, false)
  -- A word's color is read, not recorded, so an owned mark is painted again after each skin switch.
  local Skin = lib.__skinOf and lib.__skinOf(spec.owner)
  if Skin and lib.__onSkin then lib.__onSkin(Skin, spec.owner, b, function(t) paint(t, false) end) end
  b:SetScript("OnEnter", function(self)
    paint(self, true)
    showTip(self)
  end)
  b:SetScript("OnLeave", function(self)
    paint(self, false)
    hideTip(self)
  end)
  local onClick = spec.onClick
  b:SetScript("OnClick", function(self, button)
    if type(onClick) == "function" then onClick(self, button) end
  end)
  return b
end

--- What `b` measures: its width when it says, else `fallback`.
local function widthOf(b, fallback)
  local w = type(b.GetWidth) == "function" and b:GetWidth()
  if type(w) == "number" and w > 0 then return w end
  return fallback or SIZE
end

--- The settings mark's click: hide `hideOnSettings` first (a FULLSCREEN window would cover the
--- panel), then the window's own override, else the owner's registered opener (Core minor 18).
local function settingsClick(spec)
  return function()
    local hide = spec.hideOnSettings
    if type(hide) == "table" and type(hide.Hide) == "function" then hide:Hide() end
    if type(spec.settings) == "function" then
      local ok, err = pcall(spec.settings)
      if not ok and type(geterrorhandler) == "function" then geterrorhandler()(err) end
      return
    end
    local core = LibStub("LibKa0s-Core-1.0", true)
    if core and type(core.OpenSettings) == "function" then core.OpenSettings(spec.owner) end
  end
end

--- The close mark's tooltip (SR-L2): the window's `closeTip` or `spec.L`'s CLOSE_TIP, else the
--- Tooltip major's CloseTip for the owner, read on each hover. Core's close already carries that; an
--- adopted or a host-made close gets it here, and a window's own words replace either.
local function tipClose(btn, spec)
  local Tip = LibStub("LibKa0s-Tooltip-1.0", true)
  if not (btn and Tip and type(Tip.AttachTitleTip) == "function") then return btn end
  local L = type(spec.L) == "table" and spec.L or nil
  local own = spec.closeTip or (L and rawget(L, "CLOSE_TIP"))
  if type(own) == "string" and own ~= "" then
    Tip.AttachTitleTip(btn, own, spec.owner)
  elseif rawget(btn, "__titleTip") == nil then
    local owner = spec.owner
    Tip.AttachTitleTip(btn, function() return Tip.CloseTip(owner) end, owner)
  end
  return btn
end

--- The close mark: the window's own (`closeButton`), else the host's factory or Core's, built with
--- the owner; nil where `close == false` or nothing can build one.
local function buildClose(bar, spec)
  local core = LibStub("LibKa0s-Core-1.0", true)
  if spec.closeButton ~= nil then return tipClose(spec.closeButton or nil, spec) end
  if spec.close == false then return nil end
  local make = spec.makeClose or (core and core.MakeCloseButton)
  if type(make) ~= "function" then return nil end
  local onClose = spec.close
  if type(onClose) ~= "function" then
    local f = spec.frame or (type(bar.GetParent) == "function" and bar:GetParent())
    onClose = function() if f and f.Hide then f:Hide() end end
  end
  return tipClose(make(bar, onClose, spec.owner), spec)
end

--- The settings mark, or nil where the window opted out (`settings = false`, with its reason).
local function buildSettings(bar, spec)
  if spec.settings == false then
    if type(spec.settingsOptOut) ~= "string" or spec.settingsOptOut == "" then
      error("LibKa0s-Widgets-1.0:HeaderButtons: settings = false needs spec.settingsOptOut, the reason", 3)
    end
    return nil
  end
  return lib.HeaderButton(bar, { owner = spec.owner, icon = "settings", glyph = text(spec, "SETTINGS_GLYPH"),
    tip = spec.settingsTip or text(spec, "SETTINGS_TIP"), onClick = settingsClick(spec) })
end

--- Place `list` (outermost first) from `bar`'s corner in: `spec.point` (RIGHT) at `spec.y` (0), PAD
--- in and GAP apart. Answers the offsets by key and the S.Header entries ({ frame, x }).
local function place(bar, list, spec)
  local offsets, right = {}, {}
  local point, y, gap = spec.point or "RIGHT", spec.y or 0, spec.gap or GAP
  local off = spec.pad or PAD
  for _, e in ipairs(list) do
    if spec.place ~= false then e.btn:SetPoint(point, bar, point, -off, y) end
    offsets[e.key] = -off
    right[#right + 1] = { frame = e.btn, x = off }
    off = off + widthOf(e.btn, (not e.btn.icon) and e.width or nil) + gap
  end
  return offsets, right
end

--- Build a window's header marks on `bar` (minor 1), right-aligned, left to right `spec.extras` in
--- their order, settings, close.
---
---   owner          string   the addon's folder: the Media icon folder, the skin owner when it
---                           registered one, and the settings registry key (Core.OpenSettings)
---   close          fn|false the close mark's click (default: hide `frame`, else the bar's parent);
---                           false builds none
---   makeClose      fn       optional: the host's close factory, makeClose(parent, onClick, owner)
---   closeButton    btn      optional: adopt a close the window already has
---   settings       fn|bool  nil or true: the owner's registered opener; a function overrides it;
---                           false opts out and needs `settingsOptOut`, the reason, or it raises
---   hideOnSettings frame    optional: hidden before settings opens (a FULLSCREEN window)
---   settingsTip    string   optional: the settings mark's tooltip (default HEADER_STRINGS.SETTINGS_TIP)
---   closeTip       string   optional: the close mark's tooltip (default Tooltip's CloseTip(owner), "Close")
---   extras         table    { { key, icon, label, width, glyph, tip, onClick }, ... }, left to right;
---                           every mark shows its `tip` (`tips = false` is retired, accepted unread)
---   point, y       anchor   the corner point (RIGHT) and its y (0): a frame with no title bar passes
---                           TOPRIGHT and the band's middle
---   pad, gap       number   the corner inset (6) and the gap between marks (6)
---   place          bool     false: record the offsets, anchor nothing (a template's own close)
---   frame          frame    the window; `frame.headerButtons` is set to the answer (else `bar`'s)
---   L              table    optional locale override, keyed to HEADER_STRINGS (and CLOSE_TIP)
---
--- @return table  { close, settings, extras = { [key] = btn }, order = { keys, left to right },
---                  offsets = { [key] = x from the corner, negative }, right = { { frame, x }, ... }
---                  outermost first for S.Header, optOut = the reason or nil }
function lib.HeaderButtons(bar, spec)
  spec = type(spec) == "table" and spec or {}
  local hb = { extras = {}, order = {}, optOut = spec.settings == false and spec.settingsOptOut or nil }
  hb.settings = buildSettings(bar, spec)
  hb.close = buildClose(bar, spec)
  local list = {}
  if hb.close then list[1] = { key = "close", btn = hb.close } end
  if hb.settings then list[#list + 1] = { key = "settings", btn = hb.settings } end
  local extras = type(spec.extras) == "table" and spec.extras or {}
  for i = #extras, 1, -1 do
    local x = extras[i]
    local b = lib.HeaderButton(bar, { owner = spec.owner, icon = x.icon, label = x.label, width = x.width,
      glyph = x.glyph, tip = x.tip, onClick = x.onClick })
    if b then
      hb.extras[x.key] = b
      list[#list + 1] = { key = x.key, btn = b, width = x.width }
    end
  end
  for i = #list, 1, -1 do hb.order[#hb.order + 1] = list[i].key end
  hb.offsets, hb.right = place(bar, list, spec)
  local host = spec.frame or bar
  if type(host) == "table" then host.headerButtons = hb end
  return hb
end
