-- LibKa0s-Options-1.0 -- the skin picker (LibKa0s#64): a small window an addon shows the first time
-- a profile runs, so the player picks a skin before opening any settings. The instance members
-- O.SkinPicker and O.HideSkinPicker, attached through lib.__AttachSkinPicker, the words,
-- lib.SKIN_PICKER_STRINGS, and the one queue every Ka0s addon's picker shares, lib.__pickerQueue.
--
-- A fourteenth file of the Options major (minor 1), guarded with the same multi-file idiom as
-- OptionsAppearance.lua; Options minor 34 attaches it. It loads after OptionsAppearance.lua and
-- reuses that file's reload popup (lib.__appearanceReload), its words for it, and its other owners
-- and one owner's skin copy (lib.__skinOthers, lib.__copySkinTo).
--
-- WHAT IT DRAWS, top to bottom, in one window at least 280 wide, its center 75% of the way up the
-- screen (re-anchored on every show, so it sits clear of the middle, where most addons' main windows
-- open; what keeps it in front of the window the eye opens is LAYERING, below):
--   * the title, "Choose a skin", and the close control;
--   * the addon's label (Skin:OwnerLabel, else the owner's name), frame.ownerLabel, on a line of its
--     own, painted as a heading and never cut off: the window widens to the label's unbounded width
--     (plus the side padding) on every show and every change of the owner's looks (minor 2, R-11);
--   * a dropdown button: the skin worn now, as three swatches and its name, with the eye and the
--     gear beside it. A click opens the list of every skin (Skin:Skins() order) inside the window,
--     under the button, each row three swatches and the skin's name in that skin's own body face and
--     size. A pick PREVIEWS it: refused in combat; otherwise Skin:SetChoice, so the addon repaints
--     live, and the reload flag SetChoice answers is kept for Apply. The owner's write seam is not
--     called and no popup is raised. It closes the list, not the window;
--   * the eye (Media icon "eye"), only when `spec.onPreview` is a function: the host's test mode, so
--     the player sees the skin on the addon's own frames; it keeps working while a preview is
--     pending, and the window is Raise()d once onPreview returns;
--   * the gear (Media icon "settings"): saves the pending pick as Apply does, then `spec.onSettings`,
--     by default the settings panel opened at `spec.page` (O.OpenOptionsPanel(page), OptionsRegistry
--     minor 4) and O.SelectTab(page, spec.tab or "Appearance"); then the window closes;
--   * "Apply" (a primary button): saves the pending pick (spec.set(source, key), then the one reload
--     popup when any pick in this showing asked for one), then closes the window;
--   * "Apply to all Ka0s addons", shown only while another skin owner is registered: Apply, then
--     every other owner gets the same source and skin (Skin:SetChoice, then Skin:WriteChoice: the
--     skin half of the Skin tab's copy; their scope and overrides are left alone), one reload popup
--     naming every addon that needs one, then this window closes and every queued picker is
--     dismissed (its `spec.onClose` runs; it never shows).
-- The close control and Escape dismiss WITHOUT saving: a pending preview is put back (Skin:SetChoice
-- to the owner's stored choice as it reads NOW, through spec.get, no write: only the unsaved preview
-- is undone, so a skin the Skin tab or a profile change stored while the window was up stays), then
-- the window closes. Every close route (Apply, the close control, the gear, Escape,
-- O.HideSkinPicker) calls `spec.onClose` once, where the host records that the picker was seen.
-- Apply, Apply to all, the gear and a pick are refused in combat and leave the window up; the close
-- control and Escape still close it, and the preview put back is no write.
--
-- ONE WINDOW ACROSS ADDONS. LibStub keeps one copy of this major for the whole client, so its library
-- table is every Ka0s addon's, and lib.__pickerQueue (created if absent, adopted by a newer minor)
-- holds the picker shown now (`current`) and the owners waiting (`waiting`, one entry per owner).
-- While one owner's picker is up, O.SkinPicker for another owner, on any instance, queues it (a
-- repeat call refreshes its spec) and shows nothing; when the shown picker closes, the next one
-- waiting shows. O.HideSkinPicker() on an instance takes its queued owners out of the queue (they were
-- never seen, so no onClose) and hides its window when it is the one up.
--
-- NEVER SHOWN MID-COMBAT BY THE QUEUE. A close under InCombatLockdown() shows no next owner: the
-- queue waits out combat on OptionsRegistry.lua's end-of-combat park (lib.__parkRegistration, its
-- one PLAYER_REGEN_ENABLED frame, registered only while something is parked) and advances when combat
-- ends. While it waits, O.SkinPicker for any other owner queues behind it too. The predicate is the
-- client's InCombatLockdown() alone, as the park's own is: the page lock's flag is cleared by another
-- frame's handler for the same event, which may run after the park's replay. A copy without the park
-- shows the next owner at once, as before.
--
-- LAYERING (frame-layering §1, §4): a dialog the player answers, T6: DIALOG, toplevel, clamped,
-- movable by its body. Not T4's HIGH: the eye's onPreview typically shows the addon's own main
-- window, itself HIGH and toplevel, and a toplevel window comes up over its strata peers when it is
-- shown or clicked, so at HIGH the window the eye opened covered the picker (and covered it again on
-- every click into it). At DIALOG no HIGH window can, whatever its level; the picker is also
-- Raise()d after onPreview returns, for a host whose preview shows a DIALOG window of its own (a
-- debug console, a sim panel). On every show it re-raises a shown StaticPopup (Core's
-- RaiseStaticPopups, frame-layering §4), so the reload popup one picker's Apply raised stays above
-- the next queued picker. The list is part of the window (the window grows to hold it), not a
-- transient popup, so it needs no strata of its own and closes with the window by construction.
--
-- SKIN. Every piece is painted for the owner through the Skin facade (Core.ApplySkin's Shell, the
-- close control's CloseButton, Dropdown, Button, MenuFrame, ListRow), so a skin switch repaints it
-- live through Skin:Repaint; the dropdown's label follows the owner's OnLooksChanged. The rows'
-- names keep their own skins' faces: no font primitive reaches them.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- Minor 1: O.SkinPicker, O.HideSkinPicker and lib.SKIN_PICKER_STRINGS (LibKa0s#64). One window per
-- owner on an instance, each refreshed only by its own owner's looks; a skin registered after the
-- first show gains its row on the next show; the gear in combat leaves the window up. Amended before
-- release (PK-02, the owner's in-game pass): the window sits 75% of the way up the screen; the title
-- names the addon (TITLE_FOR replaces TITLE); a pick previews and Apply saves, the close control
-- and Escape put the preview back; "Apply to all Ka0s addons"; one window across addons through
-- lib.__pickerQueue, a queued call answering nil, "queued"; the default gear opens spec.page itself.
-- A close acts on the picker it closes, never the instance's current one (the client's synchronous
-- OnHide can show the instance's next owner inside the hide). PK-03 (the consumer reviews): DIALOG,
-- not HIGH, raised after onPreview, re-raising a shown StaticPopup on show; a dismissal puts back
-- the owner's stored choice as it reads now, not the one the window opened with; the queue waits out
-- combat rather than showing the next owner mid-combat.
-- Minor 2 (LK-11, ruling R-11 of Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_LIBRARY_FOLLOWUPS): the
-- title is TITLE, "Choose a skin" (TITLE_FOR retired: a long label was cut off in a one-line title);
-- the addon's label has its own line, frame.ownerLabel, above the dropdown, painted "heading"; the
-- window widens to fit it on every show and skin change, never narrower than 280.
local PICKER_MINOR = 2
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
-- lib.APPEARANCE_STRINGS'. TITLE is shown as it is; the addon's label is never a word here (it is
-- the owner's, on its own line). The two glyphs stand in for the icons on a payload without
-- LibKa0s-Media-1.0. ASCII throughout.
lib.SKIN_PICKER_STRINGS = {
  TITLE          = "Choose a skin",
  CHOOSE_TIP     = "Pick a skin to try it on this addon. Apply keeps it; closing this window puts " ..
                   "back the skin you had. You can change it later in its settings.",
  APPLY          = "Apply",
  APPLY_TIP      = "Keep this skin and close the window.",
  APPLY_ALL      = "Apply to all Ka0s addons",
  APPLY_ALL_TIP  = "Keep this skin, and give every other loaded Ka0s addon that uses skins the same " ..
                   "skin source and skin. Their scope, font and texture stay as they are.",
  PREVIEW_TIP    = "Preview: open test mode",
  SETTINGS_TIP   = "Keep this skin and open the Skin settings",
  PREVIEW_GLYPH  = "o",
  SETTINGS_GLYPH = "*",
}

local WIDTH, PAD, TOP = 280, 12, 40
local DD_H, ROW_H, ICON, BTN_H, APPLY_W = 26, 22, 24, 24, 80
-- The owner's line sits at TOP; the dropdown row one line below it.
local LABEL_H = 18
local DD_TOP = TOP + LABEL_H + 4
local BASE_H = DD_TOP + DD_H + PAD + BTN_H + 10
local SWATCH = 10
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"
-- Where the window's center sits, as a share of UIParent's height from its bottom edge.
local HEIGHT_SHARE = 0.75

local function skinMajor()
  return LibStub and LibStub("LibKa0s-Skin-1.0", true) or nil
end

local function report(err)
  local h = type(geterrorhandler) == "function" and geterrorhandler()
  if type(h) == "function" then h(err) end
end

--- Call `fn(...)` under pcall when it is a function, reporting a raise.
local function safeCall(fn, ...)
  if type(fn) ~= "function" then return end
  local ok, err = pcall(fn, ...)
  if not ok then report(err) end
end

-- ── the queue (library level) ────────────────────────────────────────────────────────────────
--
-- `current` is `{ owner, inst, frame }`, the picker shown now; `waiting` the owners queued behind it,
-- oldest first, each `{ owner, inst, spec, show }` (`show(spec)` shows it on its own instance);
-- `parked` is true while the queue waits out combat. Read through queue() at call time, never
-- cached: a newer minor adopts the same table.

local function queue()
  local q = lib.__pickerQueue
  if type(q) ~= "table" then
    q = {}
    lib.__pickerQueue = q
  end
  if type(q.waiting) ~= "table" then q.waiting = {} end
  return q
end
queue()

--- Queue `entry` behind the picker shown now: one entry per owner, a repeat refreshing it in place.
local function enqueue(entry)
  local q = queue()
  for _, e in ipairs(q.waiting) do
    if e.owner == entry.owner then
      e.inst, e.spec, e.show = entry.inst, entry.spec, entry.show
      return
    end
  end
  q.waiting[#q.waiting + 1] = entry
end

--- The client's lockdown, the park's own predicate (see the header: not the page lock's flag).
local function inLockdown()
  return (InCombatLockdown ~= nil and InCombatLockdown()) and true or false
end

local advance

--- Park the queue until combat ends (OptionsRegistry.lua's lib.__parkRegistration), once however
--- many closes ask. The replay advances only when nothing came up meanwhile. Answers whether the
--- queue is parked; false without the park, and the caller then shows at once.
local function waitOutCombat(q)
  if q.parked then return true end
  if type(lib.__parkRegistration) ~= "function" then return false end
  local ok = lib.__parkRegistration(function()
    local now = queue()
    now.parked = nil
    if not now.current then advance() end
  end)
  q.parked = ok and true or nil
  return ok and true or false
end

--- The shown picker closed: the next owner waiting shows, skipping one that can no longer; in combat
--- the queue waits for its end instead.
function advance()
  local q = queue()
  q.current = nil
  if #q.waiting > 0 and inLockdown() and waitOutCombat(q) then return end
  while not q.current and #q.waiting > 0 do
    local e = table.remove(q.waiting, 1)
    safeCall(e.show, e.spec)
  end
end

--- Apply to all: every queued picker is dismissed, its onClose run, none shown.
local function dismissWaiting()
  local q = queue()
  local list = q.waiting
  q.waiting = {}
  for _, e in ipairs(list) do safeCall(e.spec and e.spec.onClose) end
end

--- O.HideSkinPicker: the instance's queued owners leave the queue, never seen, so no onClose.
local function dropWaiting(inst)
  local list = queue().waiting
  for i = #list, 1, -1 do
    if list[i].inst == inst then table.remove(list, i) end
  end
end

-- ── the pieces ───────────────────────────────────────────────────────────────────────────────

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

--- Center the window 75% of the way up UIParent, read now (its height can change between shows).
local function place(f)
  f:ClearAllPoints()
  local h = UIParent and type(UIParent.GetHeight) == "function" and UIParent:GetHeight() or 0
  if type(h) == "number" and h > 0 then
    f:SetPoint("CENTER", UIParent, "BOTTOM", 0, h * HEIGHT_SHARE)
  else
    f:SetPoint("CENTER")
  end
end

-- ── the attach ───────────────────────────────────────────────────────────────────────────────

--- Called by lib:New (Options minor 34), guarded. Attaches the picker's two members.
function lib.__AttachSkinPicker(O, d)
  local defaultOwner = type(d) == "table" and type(d.addonName) == "string" and d.addonName or nil
  -- The picker shown last: { frame, spec, S, owner, Skin, Sk, rows, open, shown, opened, pending,
  -- reload }. `opened` is the applied choice when the showing began, `pending` the skin a pick
  -- previews and Apply has not saved, `reload` whether any pick in this showing asked for a reload.
  local P
  local pickers = {}   -- every owner's picker on this instance, so a window is never orphaned

  local function refused()
    return O.__combatRefused and O.__combatRefused("skin picker", P.owner)
  end

  --- The owner's stored choice for picker `p` (default the one shown last): `spec.get`
  --- (`{ source, skin }` or two values), each half it gives no usable value for taken from
  --- `fallback` (a `{ source, skin }` pair), else from the Skin major's applied choice.
  local function readChoice(p, fallback)
    p = p or P
    local Skin, get = p.Skin, p.spec.get
    local source, skin
    if type(get) == "function" then
      local ok, a, b = pcall(get)
      if ok and type(a) == "table" then source, skin = a.source or a[1], a.skin or a[2]
      elseif ok then source, skin = a, b
      else report(a) end
    end
    local fs, fk
    if fallback then fs, fk = fallback[1], fallback[2]
    else fs, fk = Skin:GetChoice(p.owner) end
    if source ~= "eui" and source ~= "ka0s" then source = fs end
    if type(skin) ~= "string" or not Skin:GetSkin(skin) then skin = fk end
    return source, skin
  end

  local function label(def)
    return P.S["SKIN_" .. def.key] or def.label
  end

  --- The dropdown button, the rows' states and their names' color: from the pending pick, else the
  --- stored choice, and the skin worn now.
  local function refresh()
    if not P or not P.frame then return end
    local skin = P.pending or select(2, readChoice())
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

  --- The list shown or hidden and the window's height to match, for picker `p` (default the one
  --- shown last).
  local function layout(p)
    p = p or P
    local f = p.frame
    local listH = #p.rows * ROW_H + 4
    f.list:SetHeight(listH)
    f:SetHeight(BASE_H + (p.open and (listH + 2) or 0))
    if p.open then f.list:Show() else f.list:Hide() end
  end

  --- The window as wide as the owner's line needs, never narrower than WIDTH: the label's unbounded
  --- width (GetStringWidth, with both side anchors set, reports only what fits), for picker `p`.
  local function fit(p)
    p = p or P
    local fs = p and p.frame and p.frame.ownerLabel
    if not fs then return end
    local w = type(fs.GetUnboundedStringWidth) == "function" and fs:GetUnboundedStringWidth()
      or fs:GetStringWidth()
    p.frame:SetWidth(math.max(WIDTH, math.ceil(tonumber(w) or 0) + 2 * PAD))
  end

  local function setOpen(open, p)
    p = p or P
    p.open = open and true or false
    layout(p)
  end

  local function reloadPopup(labels)
    if lib.__appearanceReload then lib.__appearanceReload(P.S, labels) end
  end

  local function ownerLabel(name)
    return P.Skin:OwnerLabel(name) or name
  end

  --- Preview `key`: refused in combat; otherwise the Skin major moves (the addon repaints live) and
  --- the reload flag it answers is kept for Apply. No write, no popup. Closes the list, not the window.
  local function pick(key)
    setOpen(false)
    if refused() then return end
    local source = readChoice()
    local _, reload = P.Skin:SetChoice(P.owner, source, key)
    P.pending = key
    if reload then P.reload = true end
    refresh()
  end

  --- Save the pending pick through the owner's write seam, the stored source kept. Answers whether
  --- any pick in this showing asked for a reload; the caller raises the popup.
  local function save()
    local key = P.pending
    if key == nil then return false end
    local source = readChoice()
    P.pending = nil
    safeCall(P.spec.set, source, key)
    local reload = P.reload
    P.reload = false
    return reload
  end

  --- A dismissal of picker `p`: its pending preview put back, the Skin major moved to the owner's
  --- stored choice as it reads now (spec.get, each half it gives no usable value for taken from the
  --- choice the window opened with), so only the unsaved preview is undone: a skin the Skin tab or
  --- a profile change stored meanwhile stays. Never the Skin major's applied choice: the pick moved
  --- it to the preview. No write.
  local function revert(p)
    if p.pending == nil then return end
    p.pending, p.reload = nil, false
    local source, skin = readChoice(p, p.opened or {})
    p.Skin:SetChoice(p.owner, source, skin)
  end

  --- Picker `p`'s window has gone, by any route: a pending preview put back, `spec.onClose` once per
  --- showing, then the next queued picker, when `p` was the picker shown. It takes the record, never
  --- the upvalue P: the client fires OnHide inside Hide(), and the advance there can make another
  --- owner on this instance P before the hide that started it returns.
  local function closed(p)
    if not (p and p.shown) then return end
    p.shown = false
    setOpen(false, p)
    revert(p)
    safeCall(p.spec.onClose)
    local cur = queue().current
    if cur and cur.inst == O and cur.owner == p.owner then advance() end
  end

  --- Hide the picker shown last and close it, the record caught before Hide() can fire OnHide.
  local function hide()
    local p = P
    if not (p and p.frame) then return end
    p.frame:Hide()
    closed(p)
  end

  --- Apply: refused in combat with the window left up; otherwise save, the one reload popup when a
  --- pick asked for it, then the close.
  local function apply()
    if refused() then return end
    if save() then reloadPopup(ownerLabel(P.owner)) end
    hide()
  end

  --- The owners Apply to all reaches: every other registered skin owner (OptionsAppearance.lua's
  --- lib.__skinOthers), or none without that file or a Skin major that can write them.
  local function others()
    if not (lib.__skinOthers and lib.__copySkinTo and type(P.Skin.WriteChoice) == "function") then return {} end
    return lib.__skinOthers(P.Skin, P.owner)
  end

  --- Apply to all: Apply for this owner, then every other owner gets the same source and skin (the
  --- skin half of the Skin tab's copy), one reload popup naming each that needs it, every queued
  --- picker dismissed, then the close. Refused in combat with the window left up.
  local function applyAll()
    if O.__combatRefused and O.__combatRefused("skin picker", "copy") then return end
    local Skin = P.Skin
    local source, stored = readChoice()
    local key = P.pending or stored
    local reloads = {}
    if save() then reloads[1] = ownerLabel(P.owner) end
    for _, name in ipairs(others()) do
      if lib.__copySkinTo(Skin, name, source, key) then reloads[#reloads + 1] = ownerLabel(name) end
    end
    if #reloads > 0 then reloadPopup(table.concat(reloads, ", ")) end
    dismissWaiting()
    hide()
  end

  --- The gear: refused in combat with the window left up (nothing can open, and closing would mark
  --- the picker seen); otherwise the pending pick saved as Apply does, then `spec.onSettings`, or the
  --- panel opened at `spec.page` and its Skin tab selected, then the close. A panel that refused to
  --- open (OpenOptionsPanel answering false) leaves the window up too.
  local function openSettings()
    if refused() then return end
    if save() then reloadPopup(ownerLabel(P.owner)) end
    local spec = P.spec
    if type(spec.onSettings) == "function" then
      safeCall(spec.onSettings)
    else
      if O.OpenOptionsPanel and O.OpenOptionsPanel(spec.page) == false then return end
      if O.SelectTab then O.SelectTab(spec.page, spec.tab or "Appearance") end
    end
    hide()
  end

  --- The eye: the host's preview, then the window raised, so the addon window it showed (or raised)
  --- does not cover it among its DIALOG peers (a HIGH window cannot: see LAYERING).
  local function preview()
    local p = P
    safeCall(p.spec.onPreview)
    local f = p.frame
    if f and f:IsShown() and type(f.Raise) == "function" then f:Raise() end
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

  --- One text button (Apply, Apply to all), painted as a push button; `primary` for Apply.
  local function textButton(f, text, tip, onClick, primary)
    local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
    btn:SetHeight(BTN_H)
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("CENTER")
    fs:SetText(text)
    btn.text = fs
    attachTip(btn, tip)
    btn:SetScript("OnClick", onClick)
    P.Sk.Button(btn, primary and { primary = true } or nil)
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

  --- The list: under the dropdown row, the window's full inner width.
  local function buildList(f)
    local list = CreateFrame("Frame", nil, f, "BackdropTemplate")
    list:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(DD_TOP + DD_H + 2))
    list:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(DD_TOP + DD_H + 2))
    f.list = list
    P.Sk.MenuFrame(list)
    syncRows()
    list:Hide()
  end

  local function buildDropdown(f)
    local dd = CreateFrame("Button", nil, f, "BackdropTemplate")
    dd:SetHeight(DD_H)
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

  --- The dropdown's right edge meets the first icon shown beside it (the eye, else the gear).
  local function anchorDropdown(f)
    local beside = f.preview:IsShown() and f.preview or f.settings
    f.dd:ClearAllPoints()
    f.dd:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -DD_TOP)
    f.dd:SetPoint("RIGHT", beside, "LEFT", -6, 0)
  end

  local function buildButtons(f)
    f.settings = iconButton(f, "settings", P.S.SETTINGS_GLYPH, P.S.SETTINGS_TIP, openSettings)
    f.settings:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(DD_TOP + (DD_H - ICON) / 2))
    f.preview = iconButton(f, "eye", P.S.PREVIEW_GLYPH, P.S.PREVIEW_TIP, preview)
    f.preview:SetPoint("RIGHT", f.settings, "LEFT", -6, 0)
    f.apply = textButton(f, P.S.APPLY, P.S.APPLY_TIP, apply, true)
    f.apply:SetWidth(APPLY_W)
    f.apply:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 10)
    f.applyAll = textButton(f, P.S.APPLY_ALL, P.S.APPLY_ALL_TIP, applyAll)
    f.applyAll:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 10)
    f.applyAll:SetPoint("RIGHT", f.apply, "LEFT", -6, 0)
  end

  local function buildChrome(f)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -8)
    title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -8)
    if type(title.SetWordWrap) == "function" then title:SetWordWrap(false) end
    f.title = title
    -- The addon's label, one line, never cut off: fit() widens the window to it.
    local owner = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    owner:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -TOP)
    owner:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -TOP)
    if type(owner.SetWordWrap) == "function" then owner:SetWordWrap(false) end
    if type(owner.SetJustifyH) == "function" then owner:SetJustifyH("LEFT") end
    f.ownerLabel = owner
    P.Sk.Text(owner, "heading")
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
    f:SetFrameStrata("DIALOG")   -- T6, not HIGH: the eye's HIGH, toplevel main window cannot cover it
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    -- Only this window's own owner refreshes it, and only while it is the one shown last.
    local mine = P
    -- Escape (UISpecialFrames) hides it too. A hide of UIParent fires OnHide with the window still
    -- shown: that is not a close; nor is a late OnHide of a window already closed (closed() checks
    -- its own record's `shown`).
    f:SetScript("OnHide", function(self)
      if not (self.IsShown and self:IsShown()) then closed(mine) end
    end)
    buildChrome(f)
    buildDropdown(f)
    buildButtons(f)
    buildList(f)
    P.Sk.OnLooksChanged(function()
      if P == mine then refresh(); fit(mine) end
    end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
    return f
  end

  --- The words and the controls that come and go, from the spec now.
  local function applySpec(f)
    local S = P.S
    f.title:SetText(tostring(S.TITLE))
    f.ownerLabel:SetText(tostring(P.Skin:OwnerLabel(P.owner) or P.owner))
    fit(P)
    f.dd.__tip, f.settings.__tip, f.preview.__tip = S.CHOOSE_TIP, S.SETTINGS_TIP, S.PREVIEW_TIP
    f.apply.__tip, f.applyAll.__tip = S.APPLY_TIP, S.APPLY_ALL_TIP
    f.apply.text:SetText(S.APPLY)
    f.applyAll.text:SetText(S.APPLY_ALL)
    if type(P.spec.onPreview) == "function" then f.preview:Show() else f.preview:Hide() end
    if #others() > 0 then f.applyAll:Show() else f.applyAll:Hide() end
    anchorDropdown(f)
  end

  --- Show `owner`'s picker on this instance and make it the one shown: a fresh showing records the
  --- choice it opens with and is placed; a repeat while up re-reads `spec`, keeping the preview.
  local function show(owner, spec, Skin)
    local fresh = not (P and P.owner == owner and P.shown)
    P = pickers[owner] or { owner = owner, rows = {}, open = false }
    pickers[owner] = P
    P.spec, P.Skin, P.Sk, P.S = spec, Skin, Skin:For(owner), mergeStrings(spec.strings)
    local f = P.frame or build()
    syncRows()
    applySpec(f)
    if fresh then
      P.pending, P.reload, P.opened = nil, false, { Skin:GetChoice(owner) }
      place(f)
    end
    setOpen(false)
    refresh()
    f:Show()
    local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
    if core and type(core.RaiseStaticPopups) == "function" then core.RaiseStaticPopups() end
    P.shown = true
    queue().current = { owner = owner, inst = O, frame = f }
    return f
  end

  --- The Skin major and the owner `spec` names (default the descriptor's `addonName`, then the
  --- owner last shown here), or nil without the major, a client, or for an unregistered owner.
  local function pickerTarget(spec)
    local Skin = skinMajor()
    local owner = spec.owner or defaultOwner or (P and P.owner)
    if not (Skin and type(Skin.IsOwner) == "function" and Skin:IsOwner(owner)) then return nil end
    if type(CreateFrame) ~= "function" then return nil end
    return Skin, owner
  end

  --- Show the skin picker for `spec.owner` (default the descriptor's `addonName`), and answer its
  --- frame. One picker is up at a time across every Ka0s addon: while another owner's is up, or while
  --- the queue waits out combat, the call queues this one and answers nil, "queued" (a repeat
  --- refreshes its spec); it shows when the one up closes, or when combat ends. A call for the owner
  --- already up on another instance answers that window. Answers nil
  --- without the Skin major, a client, or for an owner that never registered. `spec`: get and set
  --- (the Skin tab's seams: set MUST be the owner's write seam, called by Apply, Apply to all and the
  --- gear, never by a pick), onPreview (the eye; absent without it), onSettings (the gear; default:
  --- O.OpenOptionsPanel(spec.page), then O.SelectTab(spec.page, spec.tab or "Appearance")), page,
  --- tab, onClose (called once each time the window closes, by any route, and for a queued picker
  --- Apply to all dismisses), strings.
  function O.SkinPicker(spec)
    spec = type(spec) == "table" and spec or {}
    local Skin, owner = pickerTarget(spec)
    if not Skin then return nil end
    local q = queue()
    local cur = q.current
    if (cur and cur.owner ~= owner) or (not cur and q.parked) then
      enqueue({ owner = owner, inst = O, spec = spec, show = function(s) return show(owner, s, Skin) end })
      return nil, "queued"
    end
    if cur and cur.inst ~= O then return cur.frame end
    return show(owner, spec, Skin)
  end

  --- Take this instance's pickers down: its queued owners leave the queue (never seen: no onClose),
  --- and its window, when it is the one up, hides, `spec.onClose` running as for any close.
  function O.HideSkinPicker()
    dropWaiting(O)
    hide()
  end
end
