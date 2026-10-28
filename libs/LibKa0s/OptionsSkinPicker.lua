-- LibKa0s-Options-1.0 -- the skin picker (LibKa0s#64): a small window an addon shows the first time
-- a profile runs, so the player picks a skin before opening any settings. The instance members
-- O.SkinPicker and O.HideSkinPicker, attached through lib.__AttachSkinPicker, and the words,
-- lib.SKIN_PICKER_STRINGS.
--
-- A fourteenth file of the Options major (minor 1), guarded with the same multi-file idiom as
-- OptionsAppearance.lua; Options minor 34 attaches it. It loads after OptionsAppearance.lua and
-- reuses that file's reload popup (lib.__appearanceReload) and its words for it.
--
-- WHAT IT DRAWS, top to bottom, in one window about 280 wide:
--   * the title, "Choose a skin", and the close control;
--   * a dropdown button: the skin worn now, as three swatches and its name. A click opens the list
--     of every skin (Skin:Skins() order) inside the window, under the button, each row three
--     swatches and the skin's name in that skin's own body face and size. A pick applies it as the
--     Skin tab's does (combat refusal, Skin:SetChoice, then the owner's write seam, then the one
--     reload popup SetChoice asks for) and closes the list, not the window;
--   * an eye button (Media icon "eye"), only when `spec.onPreview` is a function: the host's test
--     mode, so the player sees the skin on the addon's own frames;
--   * a gear button (Media icon "settings"): `spec.onSettings`, by default the settings panel opened
--     at the Skin tab; then the window closes. Refused in combat (the panel cannot open), and the
--     window stays up, so the first-run picker is not marked seen by a gear that opened nothing.
-- Closing it by any route (the close control, the gear, Escape, O.HideSkinPicker) calls
-- `spec.onClose` once, where the host records that the picker was seen.
--
-- LAYERING (frame-layering §1, §4): an on-demand window, T4: HIGH, toplevel, clamped, movable by
-- its body. The list is part of the window (the window grows to hold it), not a transient popup,
-- so it needs no strata of its own and closes with the window by construction.
--
-- SKIN. Every piece is painted for the owner through the Skin facade (Core.ApplySkin's Shell, the
-- close control's CloseButton, Dropdown, Button, MenuFrame, ListRow), so a skin switch repaints it
-- live through Skin:Repaint; the dropdown's label follows the owner's OnLooksChanged. The rows'
-- names keep their own skins' faces: no font primitive reaches them.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- Minor 1: O.SkinPicker, O.HideSkinPicker and lib.SKIN_PICKER_STRINGS (LibKa0s#64). One window per
-- owner on an instance, each refreshed only by its own owner's looks; a skin registered after the
-- first show gains its row on the next show; the gear in combat leaves the window up.
local PICKER_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own -- see OptionsScroll.lua for why.
if lib.__pickerMinor and lib.__pickerMinor >= PICKER_MINOR
  and lib.__pickerShellMinor == lib.MINOR then return end
lib.__pickerMinor      = PICKER_MINOR
lib.__pickerShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsSkinPicker = PICKER_MINOR

-- ── the words ────────────────────────────────────────────────────────────────────────────────
--
-- A literal table, as lib.APPEARANCE_STRINGS is; `spec.strings` overrides any key, `SKIN_<key>` a
-- skin's name, and the reload popup's keys (RELOAD, RELOAD_ACCEPT, RELOAD_LATER) default to
-- lib.APPEARANCE_STRINGS'. The two glyphs stand in for the icons on a payload without
-- LibKa0s-Media-1.0. ASCII throughout.
lib.SKIN_PICKER_STRINGS = {
  TITLE          = "Choose a skin",
  CHOOSE_TIP     = "Pick the skin this addon wears. You can change it later in its settings.",
  PREVIEW_TIP    = "Preview: open test mode",
  SETTINGS_TIP   = "Open the Skin settings",
  PREVIEW_GLYPH  = "o",
  SETTINGS_GLYPH = "*",
}

local WIDTH, PAD, TOP = 280, 12, 40
local DD_H, ROW_H, ICON = 26, 22, 24
local BASE_H = TOP + DD_H + PAD + ICON + 10
local SWATCH = 10
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"

local function skinMajor()
  return LibStub and LibStub("LibKa0s-Skin-1.0", true) or nil
end

local function report(err)
  local h = type(geterrorhandler) == "function" and geterrorhandler()
  if type(h) == "function" then h(err) end
end

--- The picker's words: lib.SKIN_PICKER_STRINGS over the Appearance tab's (for the reload popup),
--- with a host's translations over both, as a fresh table.
local function mergeStrings(overrides)
  local S = {}
  for k, v in pairs(lib.APPEARANCE_STRINGS or {}) do S[k] = v end
  for k, v in pairs(lib.SKIN_PICKER_STRINGS) do S[k] = v end
  if type(overrides) == "table" then
    for k, v in pairs(overrides) do
      if type(v) == "string" then S[k] = v end
    end
  end
  return S
end

--- r, g, b from "#rrggbb", or nil.
local function hexColor(hex)
  local r, g, b = tostring(hex):match("^#?(%x%x)(%x%x)(%x%x)")
  if not r then return nil end
  return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

--- Three swatch textures on `parent`, left to right from `x`.
local function makeSwatches(parent, x)
  local out = {}
  for i = 1, 3 do
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(SWATCH, SWATCH)
    t:SetPoint("LEFT", parent, "LEFT", x + (i - 1) * (SWATCH + 2), 0)
    out[i] = t
  end
  return out
end

--- Color the three swatches from a skin's first three, each hidden where the skin names none.
local function paintSwatches(list, def)
  for i, t in ipairs(list) do
    local r, g, b = hexColor((def and def.swatches or {})[i])
    if r then
      t:SetColorTexture(r, g, b, 1)
      t:Show()
    else
      t:Hide()
    end
  end
end

--- A Media icon's path for `owner`, read at call time, or nil.
local function iconPath(owner, name)
  local media = LibStub and LibStub("LibKa0s-Media-1.0", true)
  if not (media and type(media.Icon) == "function") then return nil end
  return media.Icon(owner, name)
end

--- A skin's body face for its row: its `font.body` through LibSharedMedia and its `font.bodySize`.
local function skinFace(Skin, key)
  local T = Skin:ResolveSkin(key)
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  local path = LSM and type(LSM.Fetch) == "function" and T["font.body"] and LSM:Fetch("font", T["font.body"], true)
  return path, T["font.bodySize"] or 12
end

--- Show `text` in the game tooltip while the pointer is over `btn`. Set before the skin's paint,
--- which hooks after the host's scripts.
local function attachTip(btn, text)
  btn.__tip = text
  btn:SetScript("OnEnter", function(self)
    if not (GameTooltip and GameTooltip.SetOwner) then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.__tip or "")
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function()
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
  end)
end

-- ── the attach ───────────────────────────────────────────────────────────────────────────────

--- Called by lib:New (Options minor 34), guarded. Attaches the picker's two members.
function lib.__AttachSkinPicker(O, d)
  local defaultOwner = type(d) == "table" and type(d.addonName) == "string" and d.addonName or nil
  local P   -- the picker shown last: { frame, spec, S, owner, Skin, Sk, rows, open, shown }
  local pickers = {}   -- every owner's picker on this instance, so a window is never orphaned

  --- The owner's stored choice: `spec.get` (`{ source, skin }` or two values), else the Skin major's.
  local function readChoice()
    local Skin, get = P.Skin, P.spec.get
    local source, skin
    if type(get) == "function" then
      local ok, a, b = pcall(get)
      if ok and type(a) == "table" then source, skin = a.source or a[1], a.skin or a[2]
      elseif ok then source, skin = a, b
      else report(a) end
    end
    if source ~= "eui" and source ~= "ka0s" then source = select(1, Skin:GetChoice(P.owner)) end
    if type(skin) ~= "string" or not Skin:GetSkin(skin) then skin = select(2, Skin:GetChoice(P.owner)) end
    return source, skin
  end

  local function label(def)
    return P.S["SKIN_" .. def.key] or def.label
  end

  --- The dropdown button, the rows' states and their names' color: from the choice and skin now.
  local function refresh()
    if not P or not P.frame then return end
    local _, skin = readChoice()
    local f, def = P.frame, P.Skin:GetSkin(skin)
    paintSwatches(f.dd.swatches, def)
    f.dd.text:SetText(def and label(def) or tostring(skin))
    local r, g, b = P.Sk.Color("text.body")
    for i, row in ipairs(P.rows) do
      row.state = row.key == skin and "selected" or (i % 2 == 0 and "stripe" or "normal")
      P.Sk.ListRow(row, row.state)
      if r then row.text:SetTextColor(r, g, b) end
    end
  end

  local function layout()
    local f = P.frame
    local listH = #P.rows * ROW_H + 4
    f.list:SetHeight(listH)
    f:SetHeight(BASE_H + (P.open and (listH + 2) or 0))
    if P.open then f.list:Show() else f.list:Hide() end
  end

  local function setOpen(open)
    P.open = open and true or false
    layout()
  end

  --- Move the owner to `key`, as the Skin tab's pick does: refused in combat, the Skin major first,
  --- then the owner's write seam, then the one reload popup. Closes the list, never the window.
  local function pick(key)
    setOpen(false)
    if O.__combatRefused and O.__combatRefused("skin picker", P.owner) then return end
    local source = readChoice()
    local _, reload = P.Skin:SetChoice(P.owner, source, key)
    if type(P.spec.set) == "function" then
      local ok, err = pcall(P.spec.set, source, key)
      if not ok then report(err) end
    end
    if reload and lib.__appearanceReload then
      lib.__appearanceReload(P.S, P.Skin:OwnerLabel(P.owner) or P.owner)
    end
    refresh()
  end

  --- The window has gone, by any route: `spec.onClose` once per showing.
  local function closed()
    if not (P and P.shown) then return end
    P.shown = false
    setOpen(false)
    local fn = P.spec.onClose
    if type(fn) == "function" then
      local ok, err = pcall(fn)
      if not ok then report(err) end
    end
  end

  local function hide()
    if not (P and P.frame) then return end
    P.frame:Hide()
    closed()
  end

  --- The gear: refused in combat with the window left up (nothing can open, and closing would mark
  --- the picker seen); otherwise `spec.onSettings`, or the panel at the Skin tab, then the close. A
  --- panel that refused to open (OpenOptionsPanel answering false) leaves the window up too.
  local function openSettings()
    if O.__combatRefused and O.__combatRefused("skin picker", P.owner) then return end
    local spec = P.spec
    if type(spec.onSettings) == "function" then
      local ok, err = pcall(spec.onSettings)
      if not ok then report(err) end
    else
      if O.OpenOptionsPanel and O.OpenOptionsPanel() == false then return end
      if O.SelectTab then O.SelectTab(spec.page, spec.tab or "Appearance") end
    end
    hide()
  end

  local function preview()
    local fn = P.spec.onPreview
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn)
    if not ok then report(err) end
  end

  --- One icon button: the Media icon `icon` for the owner, else the text glyph.
  local function iconButton(f, icon, glyph, tip, onClick)
    local btn = CreateFrame("Button", nil, f)
    btn:SetSize(ICON, ICON)
    local path = iconPath(P.owner, icon)
    if path then
      local t = btn:CreateTexture(nil, "ARTWORK")
      t:SetPoint("CENTER")
      t:SetSize(ICON - 8, ICON - 8)
      t:SetTexture(path)
      btn.icon = t
    else
      local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      fs:SetPoint("CENTER")
      fs:SetText(glyph)
      btn.text = fs
    end
    attachTip(btn, tip)
    btn:SetScript("OnClick", onClick)
    P.Sk.Button(btn)
    return btn
  end

  --- One row of the list: three swatches and the skin's name in its own face.
  local function makeRow(list, i, def)
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 2, -2 - (i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, -2 - (i - 1) * ROW_H)
    row.key = def.key
    row.swatches = makeSwatches(row, 6)
    paintSwatches(row.swatches, def)
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", row, "LEFT", 6 + 3 * (SWATCH + 2) + 6, 0)
    local path, size = skinFace(P.Skin, def.key)
    if path then fs:SetFont(path, size, "") end
    fs:SetText(label(def))
    row.text = fs
    row:SetScript("OnClick", function() pick(def.key) end)
    row:SetScript("OnEnter", function(self) P.Sk.ListRow(self, "hover") end)
    row:SetScript("OnLeave", function(self) P.Sk.ListRow(self, self.state or "normal") end)
    return row
  end

  --- A row for every registered skin the list lacks: skins only append to Skin:Skins(), so one
  --- registered after the first show gains its row at the end.
  local function syncRows()
    for i, def in ipairs(P.Skin:Skins()) do
      if not P.rows[i] then P.rows[i] = makeRow(P.frame.list, i, def) end
    end
  end

  local function buildList(f)
    local list = CreateFrame("Frame", nil, f, "BackdropTemplate")
    list:SetPoint("TOPLEFT", f.dd, "BOTTOMLEFT", 0, -2)
    list:SetPoint("TOPRIGHT", f.dd, "BOTTOMRIGHT", 0, -2)
    f.list = list
    P.Sk.MenuFrame(list)
    syncRows()
    list:Hide()
  end

  local function buildDropdown(f)
    local dd = CreateFrame("Button", nil, f, "BackdropTemplate")
    dd:SetHeight(DD_H)
    dd:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -TOP)
    dd:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -TOP)
    dd.swatches = makeSwatches(dd, 8)
    local fs = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", dd, "LEFT", 8 + 3 * (SWATCH + 2) + 6, 0)
    dd.text = fs
    local arrow = dd:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", dd, "RIGHT", -8, 0)
    arrow:SetTexture(ARROW)
    arrow:SetRotation(-math.pi / 2)
    dd.arrow = arrow
    attachTip(dd, P.S.CHOOSE_TIP)
    dd:SetScript("OnClick", function() setOpen(not P.open) end)
    f.dd = dd
    P.Sk.Dropdown(dd)
  end

  local function buildChrome(f)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -8)
    f.title = title
    local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
    if core and type(core.ApplySkin) == "function" then core.ApplySkin(f, nil, P.owner) else P.Sk.Shell(f) end
    if core and type(core.MakeCloseButton) == "function" then
      local close = core.MakeCloseButton(f, hide, P.owner)
      if close then
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
        f.close = close
      end
    end
  end

  local function build()
    lib.__pickerSeq = (lib.__pickerSeq or 0) + 1
    local name = "LibKa0sSkinPicker" .. tostring(P.owner):gsub("[^%w]", "") .. lib.__pickerSeq
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    P.frame = f
    f:Hide()
    f:SetSize(WIDTH, BASE_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    -- Escape (UISpecialFrames) hides it too. A hide of UIParent fires OnHide with the window still
    -- shown: that is not a close.
    f:SetScript("OnHide", function(self)
      if not (self.IsShown and self:IsShown()) then closed() end
    end)
    buildChrome(f)
    buildDropdown(f)
    buildList(f)
    f.settings = iconButton(f, "settings", P.S.SETTINGS_GLYPH, P.S.SETTINGS_TIP, openSettings)
    f.settings:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 10)
    f.preview = iconButton(f, "eye", P.S.PREVIEW_GLYPH, P.S.PREVIEW_TIP, preview)
    f.preview:SetPoint("RIGHT", f.settings, "LEFT", -6, 0)
    -- Only this window's own owner refreshes it, and only while it is the one shown last.
    local mine = P
    P.Sk.OnLooksChanged(function()
      if P == mine then refresh() end
    end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
    return f
  end

  --- Show the skin picker for `spec.owner` (default the descriptor's `addonName`), one shown per
  --- instance (a window per owner, the other owner's hidden first), and answer its frame; nil without the Skin major, a client, or for an owner that
  --- never registered. `spec`: get and set (the Skin tab's seams: set MUST be the owner's write
  --- seam), onPreview (the eye; absent without it), onSettings (the gear; default: the settings
  --- panel opened, then O.SelectTab(spec.page, spec.tab or "Appearance")), page, tab, onClose
  --- (called once each time the window closes, by any route), strings.
  function O.SkinPicker(spec)
    spec = type(spec) == "table" and spec or {}
    local Skin = skinMajor()
    local owner = spec.owner or defaultOwner or (P and P.owner)
    if not (Skin and type(Skin.IsOwner) == "function" and Skin:IsOwner(owner)) then return nil end
    if type(CreateFrame) ~= "function" then return nil end
    if P and P.owner ~= owner then hide() end
    P = pickers[owner] or { owner = owner, rows = {}, open = false }
    pickers[owner] = P
    P.spec, P.Skin, P.Sk, P.S = spec, Skin, Skin:For(owner), mergeStrings(spec.strings)
    local f = P.frame or build()
    syncRows()
    f.title:SetText(P.S.TITLE)
    f.dd.__tip, f.settings.__tip, f.preview.__tip = P.S.CHOOSE_TIP, P.S.SETTINGS_TIP, P.S.PREVIEW_TIP
    if type(spec.onPreview) == "function" then f.preview:Show() else f.preview:Hide() end
    setOpen(false)
    refresh()
    f:Show()
    P.shown = true
    return f
  end

  --- Hide the skin picker when it is up; its `spec.onClose` runs, as for any close.
  function O.HideSkinPicker()
    hide()
  end
end
