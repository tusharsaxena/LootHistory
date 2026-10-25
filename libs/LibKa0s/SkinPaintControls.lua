-- LibKa0s-Skin-1.0 — the Ka0s paint primitives, part three: the controls. EllesmereUI's names
-- (Button, WhiteButtonLabel, StateButtonLabel, EditBox, Checkbox, Dropdown, ScrollBar, Tab,
-- SetTabSelection, CloseButton, PageButton, SquareIcon, SortHeaderBar, ApplyBarFill) and the
-- Ka0s extras (Slider, NavItem, Drawer, ListRow, IconBorder).
--
-- A file of its own so no primitive file reaches layout-§1's 1000-line band: part of the same
-- major, paired on the shell's minor (`__controlsMinor` / `__controlsShellMinor`), painting with
-- SkinPaint.lua's helpers (`lib.__P`). The technique is SkinPaint.lua's header: stock art faded and
-- recorded, Ka0s regions made once per target, Ka0s Default leaving a stock control stock, every
-- border on the holder and every wash on the fill holder under the target's text.
--
-- HOVER AND FOCUS are HookScript'd once per target and read the target's record at call time, so a
-- skin switch recolors them with no new hook and a pooled control that moved to another owner
-- hovers in that owner's skin. Call a primitive AFTER the host sets its own scripts: a later
-- SetScript replaces the hook. `S.CloseButton(btn, { own = true })` is the one exception: a close
-- button the library built has no host script, so it SetScripts its pair as Core's does today.
--
-- No primitive here draws a LibKa0s-Media icon: the page arrow is in-client art
-- (`Interface\ChatFrame\ChatFrameExpandArrow`) and every other texture is WHITE8X8.

local lib = LibStub and LibStub("LibKa0s-Skin-1.0", true)
if not lib then return end   -- the shell refused (no Core, or below its floor): nothing to attach to
if lib.__paintShellMinor ~= lib.MINOR or not lib.__P then return end   -- no helpers from this copy

local CONTROLS_MINOR = 1
if lib.__controlsMinor and lib.__controlsMinor >= CONTROLS_MINOR
  and lib.__controlsShellMinor == lib.MINOR then return end
lib.__controlsMinor      = CONTROLS_MINOR
lib.__controlsShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.SkinPaintControls = CONTROLS_MINOR

local prim, P = lib.prim, lib.__P
local rgb, rgba = P.rgb, P.rgba

local ARROW_ART = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local GLYPH_FONT = "GameFontNormalLarge"
local CHECK_GETTERS = { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }
local CHECKED_GETTERS = { "GetCheckedTexture", "GetDisabledCheckedTexture" }

local BTN = { fill = "btn.bg", border = "btn.border", style = "btn.borderStyle", size = "btn.borderSize" }
local BTN_PRIMARY = { fill = "btnPrimary.bg", border = "btnPrimary.border",
                      style = "btnPrimary.borderStyle", size = "btnPrimary.borderSize" }
local INPUT = { fill = "input.bg", border = "input.border", style = "input.borderStyle",
                size = "input.borderSize" }

--- The live record of `frame`, for a hook: nil once the frame was released.
local function live(frame) return lib.painted[frame] end

--- Recolor a box's edge: the backdrop's, or the holder's flat edges.
local function edgeColor(rec, frame, c)
  if not c then return end
  if P.hasBackdrop(frame) and not rec.regions.nine and not rec.regions.edgeTop then
    return frame:SetBackdropBorderColor(rgba(c))
  end
  for _, side in ipairs({ "Top", "Bottom", "Left", "Right" }) do
    local t = rec.regions["edge" .. side]
    if t then t:SetColorTexture(rgba(c)) end
  end
end

-- ── buttons ──────────────────────────────────────────────────────────────────────────────────

--- A button's label: its own font string, else `btn.text` / `btn.Text`.
local function labelOf(btn)
  return P.call(btn, "GetFontString", "FontString") or P.field(btn, "text", "FontString")
    or P.field(btn, "Text", "FontString")
end

--- Read Button's second argument: EllesmereUI's `keepKeys` (true keeps the stock art and paints
--- only the label) or a Ka0s options table (`primary`, `keep`, `stock`).
local function buttonOpts(a)
  if type(a) == "table" then return a end
  return { keep = a == true }
end

local function buttonBase(rec) return rec.regions.primary and "btnPrimary" or "btn" end

local function buttonHover(btn, rec, on)
  local T = P.T(rec.owner)
  local base = buttonBase(rec)
  local fs = labelOf(btn)
  local c = T[base .. (on and ".hover" or ".text")]
  if fs and c then fs:SetTextColor(rgb(c)) end
end

--- S.Button(btn, keepKeys | opts): a push button. The flat-control box from `btn.*` (or
--- `btnPrimary.*` with `opts.primary`): backdrop, gradient, non-flat edge on the holder; the stock
--- textures faded unless kept (`keepKeys == true` or `opts.keep`); the label in `btn.text` and the
--- body font, `btn.hover` under the pointer; `btn.icon` (a texture) in `btn.icon`. Ka0s Default
--- leaves a stock-template button stock. Draws no Media icon.
prim.Button = function(owner, btn, a)
  if not P.isFrame(btn) then return end
  local rec = P.track(owner, btn, "Button", a)
  local opts = buttonOpts(a)
  if P.stockDefault(owner, rec, btn, opts) then return end
  local T = P.T(owner)
  rec.regions.primary = opts.primary == true
  if not opts.keep then
    P.fadeAll(rec, P.stockRegions(btn, opts))
    P.box(rec, btn, T, opts.primary and BTN_PRIMARY or BTN, opts)
  end
  local base = buttonBase(rec)
  local fs = labelOf(btn)
  if fs then
    P.tint(rec, fs, T, base .. ".text")
    P.font(owner, rec, fs, "body")
  end
  local icon = P.field(btn, "icon", "Texture")
  if icon then P.tint(rec, icon, T, base .. ".icon", "SetVertexColor") end
  P.hook(rec, btn, "OnEnter", function(self, r) buttonHover(self, r, true) end)
  P.hook(rec, btn, "OnLeave", function(self, r) buttonHover(self, r, false) end)
end

--- S.WhiteButtonLabel(btn): the button's label in `btn.text` and the body font.
prim.WhiteButtonLabel = function(owner, btn)
  local fs = P.isFrame(btn) and labelOf(btn)
  if not fs then return end
  local rec = P.track(owner, btn, "WhiteButtonLabel")
  P.tint(rec, fs, P.T(owner), "btn.text")
  P.font(owner, rec, fs, "body")
end

--- S.StateButtonLabel(btn, on): the label in `text.accent` while `on`, `text.muted` otherwise.
prim.StateButtonLabel = function(owner, btn, on)
  local fs = P.isFrame(btn) and labelOf(btn)
  if not fs then return end
  local rec = P.track(owner, btn, "StateButtonLabel", on)
  P.tint(rec, fs, P.T(owner), on and "text.accent" or "text.muted")
end

-- ── text inputs ──────────────────────────────────────────────────────────────────────────────

local function focusColor(eb, rec, focused)
  local T = P.T(rec.owner)
  edgeColor(rec, eb, T[focused and "input.focus" or "input.border"])
end

--- S.EditBox(eb, opts): a text input. The flat-control box from `input.*`, the template's
--- Left/Middle/Right faded, the typed text in `input.text` (nil in Ka0s Default: left alone) and
--- the body font, the hint (`opts.placeholder`, else `eb.hint`) in `input.placeholder`, and the
--- edge in `input.focus` while it has the keys. `opts.padInput` sets 6px text insets;
--- `opts.noBorder` draws no edge. Draws no Media icon.
prim.EditBox = function(owner, eb, opts)
  if not P.isFrame(eb) then return end
  local rec = P.track(owner, eb, "EditBox", opts)
  opts = type(opts) == "table" and opts or {}
  if P.stockDefault(owner, rec, eb, opts) then return end
  local T = P.T(owner)
  P.fadeAll(rec, P.stockRegions(eb, opts))
  P.box(rec, eb, T, INPUT, opts)
  if type(eb.SetTextColor) == "function" then P.tint(rec, eb, T, "input.text") end
  P.font(owner, rec, eb, "body")
  local hint = P.isFS(opts.placeholder) and opts.placeholder or P.field(eb, "hint", "FontString")
  if hint then P.tint(rec, hint, T, "input.placeholder") end
  if opts.padInput and type(eb.SetTextInsets) == "function" then eb:SetTextInsets(6, 6, 0, 0) end
  if opts.noBorder then return end
  P.hook(rec, eb, "OnEditFocusGained", function(self, r) focusColor(self, r, true) end)
  P.hook(rec, eb, "OnEditFocusLost", function(self, r) focusColor(self, r, false) end)
end

-- ── checkboxes ───────────────────────────────────────────────────────────────────────────────

local function checked(cb)
  if type(cb.GetChecked) ~= "function" then return false end
  return cb:GetChecked() and true or false
end

local function refreshMark(cb, rec)
  local mark = rec.regions.mark
  if not mark then return end
  if checked(cb) then mark:Show() else mark:Hide() end
end

-- The box and the mark: art when the skin names it, else WHITE8X8 in the color token.
local function paintArt(tex, T, art, color, method)
  local path = P.media("background", T[art])
  if path then
    tex:SetTexture(path)
    tex:SetVertexColor(1, 1, 1, 1)
  elseif T[color] then
    tex:SetTexture(P.WHITE8)
    tex[method](tex, rgba(T[color]))
  end
end

local function checkBox(rec, cb, T, inset)
  local box = P.tex(rec, "box", cb, "BACKGROUND", 1)
  if not box then return end
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", cb, "TOPLEFT", inset, -inset)
  box:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -inset, inset)
  paintArt(box, T, "check.texture", "check.bg", "SetVertexColor")
  box:Show()
  local mark = P.tex(rec, "mark", cb, "OVERLAY", 1)
  if not mark then return end
  local m = inset + 3
  mark:ClearAllPoints()
  mark:SetPoint("TOPLEFT", cb, "TOPLEFT", m, -m)
  mark:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -m, m)
  paintArt(mark, T, "check.markTexture", "check.mark", "SetVertexColor")
end

local function checkHooks(rec, cb)
  P.hook(rec, cb, "OnClick", refreshMark)
  P.hook(rec, cb, "OnShow", refreshMark)
  local hooks = P.saved(rec, "hooks")
  if hooks.SetChecked or type(hooksecurefunc) ~= "function" or type(cb.SetChecked) ~= "function" then
    return
  end
  hooks.SetChecked = true
  hooksecurefunc(cb, "SetChecked", function(self)
    local r = live(self)
    if r then refreshMark(self, r) end
  end)
end

--- S.Checkbox(cb, opts): a check button. The stock art faded (the stock check too, unless
--- `opts.stockCheck`); a box `opts.borderInset` (default 0) inside the button, `check.texture` art
--- or `check.bg`; a `check.border` edge on the holder (nil in Ka0s Default); a mark three pixels
--- inside the box, `check.markTexture` art or `check.mark`, shown while checked; `opts.hover` adds
--- a `menu.hover` highlight. Draws no Media icon.
prim.Checkbox = function(owner, cb, opts)
  if not P.isFrame(cb) then return end
  local rec = P.track(owner, cb, "Checkbox", opts)
  opts = type(opts) == "table" and opts or {}
  if P.stockDefault(owner, rec, cb, opts) then return end
  local T = P.T(owner)
  P.fadeAll(rec, P.stockRegions(cb, opts, CHECK_GETTERS))
  local inset = type(opts.borderInset) == "number" and opts.borderInset or 0
  if not opts.stockCheck then
    for _, g in ipairs(CHECKED_GETTERS) do P.fade(rec, P.call(cb, g, "Texture")) end
  end
  checkBox(rec, cb, T, inset)
  if opts.stockCheck then P.hide(rec, "mark") else refreshMark(cb, rec) end
  P.edges(rec, cb, T["check.border"], T["check.borderStyle"], T["check.borderSize"])
  local hl = opts.hover and P.tex(rec, "hover", cb, "HIGHLIGHT")
  if hl and T["menu.hover"] then
    hl:SetAllPoints(cb)
    hl:SetColorTexture(rgba(T["menu.hover"]))
  end
  checkHooks(rec, cb)
end

-- ── dropdowns, scroll bars, sliders ──────────────────────────────────────────────────────────

--- S.Dropdown(dd, opts): a dropdown button. The flat-control box from `input.*` (Widgets'
--- dropdown: its backdrop, fill and edge, call for call), the template's pieces faded, the arrow
--- (`dd.arrow` / `dd.Arrow`) in `icon.tint`, the label (`dd.text` / `dd.Text`) in `input.text` and
--- the body font. Draws no Media icon.
prim.Dropdown = function(owner, dd, opts)
  if not P.isFrame(dd) then return end
  local rec = P.track(owner, dd, "Dropdown", opts)
  opts = type(opts) == "table" and opts or {}
  if P.stockDefault(owner, rec, dd, opts) then return end
  local T = P.T(owner)
  P.fadeAll(rec, P.stockRegions(dd, opts))
  P.box(rec, dd, T, INPUT, opts)
  local arrow = P.field(dd, "arrow", "Texture") or P.field(dd, "Arrow", "Texture")
  if arrow then P.tint(rec, arrow, T, "icon.tint", "SetVertexColor") end
  local fs = P.field(dd, "text", "FontString") or P.field(dd, "Text", "FontString")
  if fs then
    P.tint(rec, fs, T, "input.text")
    P.font(owner, rec, fs, "body")
  end
end

local function thumbOf(sb, opts)
  if P.isTexture(opts.thumb) then return opts.thumb, true end
  return P.call(sb, "GetThumbTexture", "Texture") or P.field(sb, "ThumbTexture", "Texture"), false
end

-- The thumb: a texture the caller drew is filled; the bar's own thumb is tinted, and only away
-- from Ka0s Default unless the caller asks for the enabled / disabled state.
local function paintThumb(owner, rec, sb, T, opts)
  local thumb, own = thumbOf(sb, opts)
  if not thumb then return end
  if opts.state then
    local c = T[opts.state == "off" and "scroll.thumbOff" or "scroll.thumbOn"]
    if c then thumb:SetVertexColor(rgba(c)) end
    return
  end
  if own then
    if T["scroll.thumb"] then thumb:SetColorTexture(rgba(T["scroll.thumb"])) end
    return
  end
  if P.isDefault(owner) then return P.unpaint(rec, sb) end
  local art = P.media("background", T["scroll.thumbTexture"])
  if art then
    thumb:SetTexture(art)
  else
    P.tint(rec, thumb, T, "scroll.thumb", "SetVertexColor")
  end
end

--- S.ScrollBar(sb, opts): a scroll bar. `opts.track` / `opts.thumb`, textures the caller drew,
--- are filled with `scroll.track` / `scroll.thumb` (DebugLog's console bar); `opts.state` "on" /
--- "off" tints the bar's own thumb `scroll.thumbOn` / `scroll.thumbOff` (OptionsScroll's
--- always-shown bar); otherwise the bar's own thumb takes `scroll.thumbTexture` art or
--- `scroll.thumb`, and a `scroll.track` region is laid under it, away from Ka0s Default only.
--- Draws no Media icon.
prim.ScrollBar = function(owner, sb, opts)
  if type(sb) ~= "table" then return end
  local rec = P.track(owner, sb, "ScrollBar", opts)
  opts = type(opts) == "table" and opts or {}
  local T = P.T(owner)
  if P.isTexture(opts.track) and T["scroll.track"] then opts.track:SetColorTexture(rgba(T["scroll.track"])) end
  paintThumb(owner, rec, sb, T, opts)
  if opts.track or opts.state or P.isDefault(owner) or not T["scroll.track"] then return P.hide(rec, "track") end
  local t = P.tex(rec, "track", sb, "BACKGROUND", -1)
  if not t then return end
  t:SetAllPoints(sb)
  t:SetColorTexture(rgba(T["scroll.track"]))
  t:Show()
end

--- S.Slider(slider, opts): a slider. Its track (`slider.track`, a region; `slider.trackBorder` on
--- the holder), its fill (`opts.fill`, a texture the caller drew: `slider.fill`) and its thumb
--- (`opts.thumb`, else the slider's own: `slider.thumb`). Every slider token is nil in Ka0s
--- Default, which leaves the slider as drawn. Draws no Media icon.
prim.Slider = function(owner, slider, opts)
  if not P.isFrame(slider) then return end
  local rec = P.track(owner, slider, "Slider", opts)
  opts = type(opts) == "table" and opts or {}
  if P.stockDefault(owner, rec, slider, opts) then return end
  local T = P.T(owner)
  if T["slider.track"] then
    P.fadeAll(rec, P.stockRegions(slider, opts))
    local t = P.tex(rec, "track", slider, "BACKGROUND", 0)
    if t then
      t:SetAllPoints(slider)
      t:SetColorTexture(rgba(T["slider.track"]))
      t:Show()
    end
  else
    P.hide(rec, "track")
  end
  P.edges(rec, slider, T["slider.trackBorder"], "flat", 1)
  if P.isTexture(opts.fill) then P.tint(rec, opts.fill, T, "slider.fill", "SetVertexColor") end
  local thumb = P.isTexture(opts.thumb) and opts.thumb or P.call(slider, "GetThumbTexture", "Texture")
  if thumb then P.tint(rec, thumb, T, "slider.thumb", "SetVertexColor") end
end

-- ── tabs ─────────────────────────────────────────────────────────────────────────────────────

local function tabFill(rec, tab, T, opts, selected)
  local fill = P.isTexture(opts.fill) and opts.fill or P.tex(rec, "fill", tab, "BACKGROUND", 0)
  if not fill then return end
  if not opts.fill then fill:SetAllPoints(tab) end
  local art = P.media("background", T[selected and "tab.onTexture" or "tab.texture"])
  if art then
    fill:SetTexture(art)
    fill:SetVertexColor(1, 1, 1, 1)
    return fill:Show()
  end
  P.fill(rec, fill, T, (selected and T["tab.onBg"]) and "tab.onBg" or "tab.bg")
end

local function tabLine(rec, tab, T, selected)
  local c = selected and T["tab.onLine"]
  local h = c and P.holder(rec, tab)
  local t = h and P.tex(rec, "line", h, "ARTWORK")
  if not t then return P.hide(rec, "line") end
  t:ClearAllPoints()
  t:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT")
  t:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT")
  t:SetHeight(2)
  t:SetColorTexture(rgba(c))
  t:Show()
end

--- S.Tab(tab, opts): a tab. The stock art faded (with `opts.stock`, regions the caller drew from
--- the client's art, such as the settings strip's atlases); the backing (`opts.fill`, else a region)
--- `tab.onTexture` / `tab.texture` art, else `tab.onBg` / `tab.bg` and its gradient; a `tab.onLine`
--- underline on the holder while selected; the label (`opts.text`, else the tab's own) in
--- `tab.onText` / `tab.text` and the body font. `opts.selected` is the first state;
--- `S.SetTabSelection` moves it. Ka0s Default leaves a stock tab stock. Draws no Media icon.
prim.Tab = function(owner, tab, opts)
  if not P.isFrame(tab) then return end
  local rec = P.track(owner, tab, "Tab", opts)
  opts = type(opts) == "table" and opts or {}
  if opts.selected ~= nil and (rec.regions.selected == nil
    or not (lib.__repainting or rec.regions.keepSelection)) then
    rec.regions.selected = opts.selected == true
  end
  if P.stockDefault(owner, rec, tab, opts) then return end
  local T, selected = P.T(owner), rec.regions.selected == true
  P.fadeAll(rec, P.stockRegions(tab, opts))
  tabFill(rec, tab, T, opts, selected)
  tabLine(rec, tab, T, selected)
  local fs = P.isFS(opts.text) and opts.text or labelOf(tab)
  if fs then
    P.tint(rec, fs, T, selected and "tab.onText" or "tab.text")
    P.font(owner, rec, fs, "body")
  end
end

--- S.SetTabSelection(tab, selected): move a painted tab to selected or not, and repaint it. Not
--- recorded: the state lives in the tab's record, so a skin switch keeps it.
prim.SetTabSelection = function(owner, tab, selected)
  local rec = lib.painted[tab]
  if not rec then return end
  rec.regions.selected = selected == true
  local args = rec.calls.Tab
  if not args then return end
  rec.regions.keepSelection = true
  local ok, err = pcall(prim.Tab, owner, tab, unpack(args, 1, args.n))
  rec.regions.keepSelection = nil
  if not ok then error(err, 0) end
end

-- ── small buttons and icons ──────────────────────────────────────────────────────────────────

local function closeArt(btn, rec)
  local icon = P.field(btn, "icon", "Texture")
  if icon then return icon, "SetVertexColor" end
  local glyph = P.field(btn, "glyph", "FontString") or rec.regions.glyph
  if glyph then return glyph, "SetTextColor" end
  return nil
end

local function closeHover(btn, rec, on)
  local art, method = closeArt(btn, rec)
  local c = P.T(rec.owner)[on and "close.hot" or "close.rest"]
  if art and c then art[method](art, rgb(c)) end
end

-- A stock close button away from Ka0s Default: its art faded, an ASCII "x" drawn in its place
-- (the shipped library's player-facing strings stay ASCII; Core's multiplication sign is the one
-- ratified exception, tests/test_prose.lua).
local function closeGlyph(rec, btn)
  local fs = P.fs(rec, "glyph", btn, "OVERLAY", GLYPH_FONT)
  if not fs then return end
  fs:SetPoint("CENTER")
  fs:SetText("x")
  fs:Show()
end

--- S.CloseButton(btn, opts): a window's close control. Its art (`btn.icon`, a texture, or
--- `btn.glyph`, a font string) in `close.rest`, `close.hot` under the pointer. A stock close button
--- (the client's template) is left stock in Ka0s Default; elsewhere its art is faded and an "x"
--- glyph drawn. `opts.own` (a button the library built, Core.MakeCloseButton's) SetScripts the hover pair
--- as Core does; otherwise it is HookScript'd. Draws no Media icon (Core's `close` icon is the
--- caller's).
prim.CloseButton = function(owner, btn, opts)
  if not P.isFrame(btn) then return end
  local rec = P.track(owner, btn, "CloseButton", opts)
  opts = type(opts) == "table" and opts or {}
  if P.stockDefault(owner, rec, btn, opts) then return end
  if rec.regions.stock then
    P.fadeAll(rec, P.stockRegions(btn, opts))
    closeGlyph(rec, btn)
  end
  local art, method = closeArt(btn, rec)
  local c = P.T(owner)["close.rest"]
  if art and c then art[method](art, rgb(c)) end
  if opts.own then
    btn:SetScript("OnEnter", function(self) local r = live(self); if r then closeHover(self, r, true) end end)
    btn:SetScript("OnLeave", function(self) local r = live(self); if r then closeHover(self, r, false) end end)
    return
  end
  P.hook(rec, btn, "OnEnter", function(self, r) closeHover(self, r, true) end)
  P.hook(rec, btn, "OnLeave", function(self, r) closeHover(self, r, false) end)
end

local PAGE_ROTATION = { prev = math.pi, left = math.pi, next = 0, right = 0,
                        up = math.pi / 2, down = -math.pi / 2 }

--- S.PageButton(btn, dir): a paging arrow ("prev", "next", "up", "down"; "left", "right"). The
--- Button look, plus an in-client arrow (`ChatFrameExpandArrow`, turned to `dir`) in `btn.icon`.
--- Ka0s Default leaves a stock-template arrow button stock. Draws no Media icon.
prim.PageButton = function(owner, btn, dir)
  if not P.isFrame(btn) then return end
  local rec = P.track(owner, btn, "PageButton", dir)
  if P.stockDefault(owner, rec, btn) then return end
  local T = P.T(owner)
  P.fadeAll(rec, P.stockRegions(btn))
  P.box(rec, btn, T, BTN)
  local t = P.tex(rec, "arrow", btn, "OVERLAY")
  if not t then return end
  t:ClearAllPoints()
  t:SetPoint("CENTER", btn, "CENTER")
  t:SetSize(12, 12)
  t:SetTexture(ARROW_ART)
  t:SetRotation(PAGE_ROTATION[dir] or 0)
  P.tint(rec, t, T, "btn.icon", "SetVertexColor")
  t:Show()
end

--- S.SquareIcon(frame, opts): an icon button. `opts.crop` trims the icon art's built-in border
--- (`opts.icon`, else `frame.icon` / `frame.Icon`, to .08-.92); an `icon.border` edge on the holder
--- (nil in Ka0s Default). Draws no Media icon.
prim.SquareIcon = function(owner, frame, opts)
  if not P.isFrame(frame) then return end
  local rec = P.track(owner, frame, "SquareIcon", opts)
  opts = type(opts) == "table" and opts or {}
  local icon = P.isTexture(opts.icon) and opts.icon or P.field(frame, "icon", "Texture")
    or P.field(frame, "Icon", "Texture")
  if icon and opts.crop then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  P.edges(rec, frame, P.T(owner)["icon.border"], "flat", 1)
end

--- S.IconBorder(frame, opts): an `icon.border` edge, `opts.size` pixels, on the frame's holder
--- (nil in Ka0s Default: none). Draws no Media icon.
prim.IconBorder = function(owner, frame, opts)
  if not P.isFrame(frame) then return end
  local rec = P.track(owner, frame, "IconBorder", opts)
  local size = type(opts) == "table" and opts.size or 1
  P.edges(rec, frame, P.T(owner)["icon.border"], "flat", size)
end

--- S.SortHeaderBar(bar, opts): a list's header row. `list.header.bg` behind it (nil in Ka0s
--- Default), each of `opts.texts` in `list.header.text`, each of `opts.arrows` (textures) in
--- `icon.tint`. Draws no Media icon.
prim.SortHeaderBar = function(owner, bar, opts)
  if type(bar) ~= "table" then return end
  local rec = P.track(owner, bar, "SortHeaderBar", opts)
  opts = type(opts) == "table" and opts or {}
  local T = P.T(owner)
  P.box(rec, bar, T, { fill = "list.header.bg", extra = true })
  for _, fs in ipairs(type(opts.texts) == "table" and opts.texts or {}) do
    if P.isFS(fs) then P.tint(rec, fs, T, "list.header.text") end
  end
  for _, t in ipairs(type(opts.arrows) == "table" and opts.arrows or {}) do
    if P.isTexture(t) then P.tint(rec, t, T, "icon.tint", "SetVertexColor") end
  end
end

--- S.ApplyBarFill(target): the accent (`text.accent`) on a status bar (SetStatusBarColor) or a
--- texture (SetVertexColor). Draws no Media icon.
prim.ApplyBarFill = function(owner, target)
  if type(target) ~= "table" then return end
  P.track(owner, target, "ApplyBarFill")
  local c = P.T(owner)["text.accent"]
  if not c then return end
  if P.isTexture(target) then return target:SetVertexColor(rgba(c)) end
  if P.isFrame(target) and type(target.SetStatusBarColor) == "function" then
    target:SetStatusBarColor(rgba(c))
  end
end

-- ── navigation, drawers, list rows ───────────────────────────────────────────────────────────

--- S.NavItem(item, opts): a nav-rail entry. Its label (`opts.label`) in `nav.selText` while
--- `opts.selected`, `nav.text` otherwise (OptionsNav's white and gold); its selection texture
--- (`opts.sel`) in `nav.selBg` (OptionsNav's select tint); a `nav.selBar` on the holder while
--- selected (nil in Ka0s Default). Draws no Media icon.
prim.NavItem = function(owner, item, opts)
  if type(item) ~= "table" then return end
  local rec = P.track(owner, item, "NavItem", opts)
  opts = type(opts) == "table" and opts or {}
  local T = P.T(owner)
  if P.isFS(opts.label) then P.tint(rec, opts.label, T, opts.selected and "nav.selText" or "nav.text") end
  if P.isTexture(opts.sel) then P.tint(rec, opts.sel, T, "nav.selBg", "SetVertexColor") end
  local c = opts.selected and T["nav.selBar"] or nil
  P.edges(rec, item, c, "flat", 2)
end

-- OptionsDrawer's four-edge set: the fill, then the left, right, bottom and top edges, each a
-- texture colored by SetVertexColor, four components.
local DRAWER_EDGES = { "left", "right", "bottom", "top" }
local function paintEdgeSet(e, fill, edge)
  if type(e) ~= "table" then return end
  if fill and P.isTexture(e.fill) then e.fill:SetVertexColor(rgba(fill)) end
  if not edge then return end
  for _, k in ipairs(DRAWER_EDGES) do
    if P.isTexture(e[k]) then e[k]:SetVertexColor(rgba(edge)) end
  end
end

local DRAWER_HEAD = { fill = "drawer.bg", border = "drawer.border", style = "drawer.borderStyle",
                      size = "drawer.borderSize", extra = true }
local DRAWER_HEAD_OPEN = { fill = "drawer.bgOpen", border = "drawer.borderOpen",
                           style = "drawer.borderStyle", size = "drawer.borderSize", extra = true }

--- S.Drawer(head, opts): a settings drawer's header (and box). Its label (`opts.label`) in
--- `drawer.textSet` when `opts.set`, `drawer.text` otherwise; its summary (`opts.summary`) in
--- `drawer.summarySet` / `drawer.summary`; then its edge set (`opts.edges`, OptionsDrawer's
--- `{ fill, left, right, bottom, top }`) in `drawer.bgOpen` / `drawer.borderOpen` while `opts.open`,
--- else `drawer.bg` / `drawer.border`, and the box's (`opts.box`) in `drawer.boxBg` /
--- `drawer.boxBorder`. A header with no edge set is boxed on its holders (the fill under its text,
--- the edge over it). Draws no Media icon.
local function drawerText(rec, T, opts)
  local set = opts.set and true or false
  if P.isFS(opts.label) then P.tint(rec, opts.label, T, set and "drawer.textSet" or "drawer.text") end
  if P.isFS(opts.summary) then P.tint(rec, opts.summary, T, set and "drawer.summarySet" or "drawer.summary") end
end

prim.Drawer = function(owner, head, opts)
  if type(head) ~= "table" then return end
  local rec = P.track(owner, head, "Drawer", opts)
  opts = type(opts) == "table" and opts or {}
  local T, open = P.T(owner), opts.open and true or false
  drawerText(rec, T, opts)
  if type(opts.edges) == "table" then
    paintEdgeSet(opts.edges, T[open and "drawer.bgOpen" or "drawer.bg"],
      T[open and "drawer.borderOpen" or "drawer.border"])
  elseif P.isFrame(head) then
    P.box(rec, head, T, open and DRAWER_HEAD_OPEN or DRAWER_HEAD)
  end
  paintEdgeSet(opts.box, T["drawer.boxBg"], T["drawer.boxBorder"])
end

local ROW_STATE = { stripe = { stripe = true }, hover = { hover = true }, selected = { selected = true },
                    normal = {} }

local function rowWash(rec, row, key, c, layer)
  local h = c and P.under(rec, row)
  local t = h and P.tex(rec, key, h, layer)
  if not t then return P.hide(rec, key) end
  t:SetAllPoints(h)
  t:SetColorTexture(rgba(c))
  t:Show()
end

--- S.ListRow(row, state): a list row's washes, on its fill holder under the row's text:
--- `list.stripe` when `state.stripe`, `list.hover` when `state.hover`, `list.sel` when
--- `state.selected`, with a `list.selOutline` edge on the holder over it.
--- `state` is a table or one of "stripe", "hover", "selected", "normal". Call it from the row's
--- bind step: the latest state is what a skin switch repaints. Draws no Media icon.
prim.ListRow = function(owner, row, state)
  if not P.isFrame(row) then return end
  local rec = P.track(owner, row, "ListRow", state)
  local s = type(state) == "table" and state or ROW_STATE[state] or ROW_STATE.normal
  local T = P.T(owner)
  rowWash(rec, row, "stripe", s.stripe and T["list.stripe"] or nil, "BACKGROUND")
  rowWash(rec, row, "hover", s.hover and T["list.hover"] or nil, "BORDER")
  rowWash(rec, row, "sel", s.selected and T["list.sel"] or nil, "BORDER")
  P.edges(rec, row, s.selected and T["list.selOutline"] or nil, "flat", 1)
end
