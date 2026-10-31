-- LibKa0s-Options-1.0 -- the skin picker's rows: the Skin tab's font, texture, outline and scope, on
-- the picker's window, by the same helpers and words, with the picker's contract in place of the tab's.
--
-- Peeled out of OptionsSkinPicker.lua at its minor 5, unchanged (LK-M2-PEEL of Ka0sAddonsCommonTasks
-- docs/2026-10-31-FINDINGS_REMEDIATION), on the seam CLAUDE.md's band census named for that file,
-- `onRow` through `syncControls`. The history is that file's header.
--
-- WHO CALLS IN. lib.__AttachSkinPicker calls lib.__AttachSkinPickerRows once per instance, handing
-- over the closures the rows use (`current` reads the picker shown last, which it reassigns), and
-- keeps the three functions this answers. `lib.__pickerKit` is the layout the two share. Nothing else
-- crosses the cut. A copy without this file draws the window with no rows.
--
-- A file of the Options major, paired on the shell's minor with the same multi-file idiom as
-- OptionsIds.lua.
--
-- THE ROWS (LK-A3, the owner's request). The Skin tab's font, texture, outline and scope, by the same
-- helpers (lib.__fillMedia and its neighbors, OptionsAppearance.lua) and the same words, with the
-- picker's contract in place of the tab's: a change PREVIEWS through Skin:SetOverride, SetOutline or
-- SetIgnore and writes nothing; Apply and the gear write what moved (save()); a dismissal puts back
-- what the window opened with. What a dismissal restores is guarded as the skin's preview always was:
-- `mediaLeft`, `outlineLeft` and `scopeLeft` hold what the preview left, nil while that half is as the
-- window opened it, and a half some other write moved since (the Skin tab, a profile change) stays
-- as that write left it. A default outline stays a default: taken back to it or put back, it is not
-- stored (Skin:__ClearOutline). D-10 reaches a preview's own override: any change of the look drawn
-- clears the font and texture, and the opened look gets back the ones it opened with.
--   A row needs the seam that saves it: with no `spec.set` there are no rows, so the picker never
-- offers what Apply could not keep; a Skin major without SetOverride, SetOutline or SetIgnore loses
-- that row, and no AceGUI loses them all, as the Skin tab draws no section either. Every addon's spec
-- has passed `set = NS.WriteSkinChoice`, which takes all four arguments, since the Skin tab's rows.
--   The widgets are AceGUI's and pooled, so they are held for a showing only: acquired at the show,
-- released at the close, and a closed picker holds no widget and leaves none shown. They sit on the
-- window with two anchors each, so fit() widening it needs no second pass. They wear the owner's skin
-- through Skin:__PaintAceWindow, on acquire and on every change of looks, whatever Ignore settings
-- panel says: that box's own tooltip says windows still wear the skin. Combat disables them when the
-- window draws them and refuses them after (O.__combatRefused); a refused row goes back to the truth.
-- The end of combat wakes rows drawn locked. The window registers no event: a picker can be up on a
-- stood-down addon, whose registration set must stay exact (slash-commands-§7). While rows are drawn
-- locked, and only then, a throttled OnUpdate reads the lock that drew them, the page lock's flag
-- included, and when it clears redraws once and removes itself. Every close takes it off, so a hidden
-- window carries none, and a window never drawn locked runs none.
-- Under the eui source they draw and work as on the tab: the leading row names EllesmereUI's face.
-- Ignore fonts disables the Font outline, as on the tab. No scope change asks for a reload
-- (Skin:SetIgnore answers false), so the one popup is still the skin's, on Apply, never in a preview.
--   These widgets take no click-to-clear from a parent: AceGUI's Frame and Button drop its focus when
-- clicked, and this window and its raw buttons are neither. dropFocus() does it for them, on a click on
-- the window's body or any of its controls and before the rows are synced, because the sync's SetList
-- empties an open pull-out and only Pullout:Open anchors and shows what it adds. It closes only a row
-- of this showing: another addon's dropdown is not the library's to close.
--   A Skin-tab write while the window is up saves what it reads, and it reads the applied state, so the
-- tab first takes the previews back (lib.__pickerSettle: revert(), no write) and then moves what this
-- window measures from (lib.__pickerRebase) to what it stored. The profile never gets a half nobody
-- applied, and a later Apply or dismissal starts from the store. The cost is the player's: a tab edit
-- drops a preview left unapplied here, which the rows show.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- Minor 1: the rows' section, moved here unchanged from OptionsSkinPicker.lua (its minor 5).
local ROWS_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own: see OptionsScroll.lua.
if lib.__pickerRowsMinor and lib.__pickerRowsMinor >= ROWS_MINOR
  and lib.__pickerRowsShellMinor == lib.MINOR then return end
lib.__pickerRowsMinor      = ROWS_MINOR
lib.__pickerRowsShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsSkinPickerRows = ROWS_MINOR

local type, ipairs, pairs, next, select = type, ipairs, pairs, next, select

--- The rows for instance `O`: `h` carries the window's closures. Answers `acquireControls`,
--- `syncControls` and `resetMedia`.
function lib.__AttachSkinPickerRows(O, h)
  local kit = lib.__pickerKit
  local PAD, ICON, DD_TOP, DD_H, BTN_H, BASE_H = kit.PAD, kit.ICON, kit.DD_TOP, kit.DD_H, kit.BTN_H, kit.BASE_H
  local MEDIA_H, ROW_GAP, LINE_H, CHECK_H, CHECK_W = kit.MEDIA_H, kit.ROW_GAP, kit.LINE_H, kit.CHECK_H, kit.CHECK_W
  local MEDIA_ROWS, combatLocked = kit.MEDIA_ROWS, kit.combatLocked
  local current, refused, refresh, setOpen, dropFocus = h.current, h.refused, h.refresh, h.setOpen, h.dropFocus
  local overrides, previewOverrides, previewOutline = h.overrides, h.previewOverrides, h.previewOutline
  local previewScope, mediaWrite, releaseControls = h.previewScope, h.mediaWrite, h.releaseControls
  local resetMedia, syncControls

  -- ── the rows ─────────────────────────────────────────────────────────────────────

  --- One row's change: an open skin list closes, combat refuses, and either way the rows read the
  --- truth again. `act(value)` previews.
  local function onRow(act)
    return function(_, _, value)
      setOpen(false)
      if not refused() then act(value) end
      refresh()
    end
  end

  local function previewMediaRow(which, value)
    local media = lib.__nextMedia(current().Skin, current().owner, which, value)
    previewOverrides(current(), media.font, media.texture)
  end

  --- A reset icon: that half back to the skin's own, a preview like the row's own entry for it.
  function resetMedia(which)
    setOpen(false)
    local rows = current().frame.rows
    if not (rows and select(which == "font" and 1 or 2, overrides(current()))) then return end
    if not refused() then previewMediaRow(which, lib.__skinMedia.FROM_SKIN) end
    refresh()
  end

  --- `w` on the window from `y`, its right edge `right` in from the window's.
  local function placeRow(f, w, y, right)
    local fr = w.frame
    fr:SetParent(f)
    fr:ClearAllPoints()
    fr:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
    fr:SetPoint("TOPRIGHT", f, "TOPRIGHT", -right, -y)
    fr:Show()
  end

  --- `line` worded `text` at `y`. Answers the next y.
  local function sectionAt(f, line, text, y)
    line:SetText(text)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
    line:Show()
    return y + LINE_H
  end

  --- Font and Texture: a media picker and, at its bar's right, its reset icon. Answers the next y.
  local function addMediaRows(p, rows, y)
    if type(p.Skin.SetOverride) ~= "function" then return y end
    local f, S = p.frame, p.S
    y = sectionAt(f, f.mediaLabel, S.MEDIA_HEADING, y)
    for _, row in ipairs(MEDIA_ROWS) do
      local which = row.which
      local dd = lib.__newMediaRow(O.AceGUI, which, true)
      dd:SetLabel(S[row.word])
      dd:SetCallback("OnValueChanged", onRow(function(value) previewMediaRow(which, value) end))
      if O.AttachTooltip then O.AttachTooltip(dd, S[row.word], S[row.tip]) end
      placeRow(f, dd, y, PAD + ICON + 6)
      rows[which] = dd
      local btn = f.reset[which]
      btn:ClearAllPoints()
      btn:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -PAD, -(y + MEDIA_H))
      btn:Show()
      y = y + MEDIA_H + ROW_GAP
    end
    return y
  end

  --- The Font outline, full width. Answers the next y.
  local function addOutlineRow(p, rows, y)
    if type(p.Skin.SetOutline) ~= "function" then return y end
    local S = p.S
    local dd = O.AceGUI:Create("Dropdown")
    dd:SetLabel(S.OUTLINE)
    dd:SetList(lib.__outlineItems(S))
    dd:SetCallback("OnValueChanged", onRow(function(mode) previewOutline(current(), mode) end))
    if O.AttachTooltip then O.AttachTooltip(dd, S.OUTLINE, S.OUTLINE_TIP) end
    placeRow(p.frame, dd, y, PAD)
    rows.outline = dd
    return y + MEDIA_H + ROW_GAP
  end

  local function checkRow(S, word, tip, act)
    local cb = O.AceGUI:Create("CheckBox")
    cb:SetLabel(S[word])
    cb:SetCallback("OnValueChanged", onRow(function(value) act(value == true) end))
    if O.AttachTooltip then O.AttachTooltip(cb, S[word], S[tip]) end
    return cb
  end

  --- The Scope: its line, then the two check boxes on one row. Answers the next y.
  local function addScopeRows(p, rows, y)
    if type(p.Skin.SetIgnore) ~= "function" then return y end
    local f, S = p.frame, p.S
    y = sectionAt(f, f.scopeLabel, S.SCOPE_HEADING, y)
    rows.panel = checkRow(S, "IGNORE_PANEL", "IGNORE_PANEL_TIP", function(on)
      previewScope(current(), on, lib.__readIgnore(current().Skin, current().owner).fonts)
    end)
    rows.fonts = checkRow(S, "IGNORE_FONTS", "IGNORE_FONTS_TIP", function(on)
      previewScope(current(), lib.__readIgnore(current().Skin, current().owner).panel, on)
    end)
    placeRow(f, rows.panel, y, PAD + CHECK_W + ROW_GAP)
    rows.fonts:SetWidth(CHECK_W)
    local fr = rows.fonts.frame
    fr:SetParent(f)
    fr:ClearAllPoints()
    fr:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y)
    fr:Show()
    return y + CHECK_H + ROW_GAP
  end

  --- A row can be offered: AceGUI to draw it, the Skin tab's helpers to read it, and the owner's write
  --- seam to keep it.
  local function rowsPossible(p)
    return O.AceGUI ~= nil and type(p.spec.set) == "function" and type(lib.__fillMedia) == "function"
  end

  --- The rows of this showing, acquired anew (a repeat show re-reads the spec's words), and the
  --- window's height from what was drawn.
  local function acquireControls(p)
    releaseControls(p)
    p.height = BASE_H
    if not rowsPossible(p) then return end
    local rows, top = {}, DD_TOP + DD_H + PAD
    local y = addMediaRows(p, rows, top)
    y = addOutlineRow(p, rows, y)
    y = addScopeRows(p, rows, y)
    if next(rows) then
      p.frame.rows = rows
      p.height = y - ROW_GAP + PAD + BTN_H + 10
    end
  end

  --- The Skin's painter for a window's widget on every row: a skin change restyles them, and a
  --- widget acquired from the pool wears it at once.
  local function paintControls(p)
    local Skin = p.Skin
    local paint = Skin.__PaintAceWindow or Skin.PaintAce
    if type(paint) ~= "function" then return end
    for _, w in pairs(p.frame.rows) do paint(Skin, p.owner, w) end
  end

  --- Font and Texture from what is applied: the leading row names the skin worn now, and a reset
  --- icon is live only while its half is an override.
  local function syncMedia(p, locked)
    local f, Skin, owner, S = p.frame, p.Skin, p.owner, p.S
    local media = mediaWrite(p)
    for _, row in ipairs(MEDIA_ROWS) do
      local which, dd = row.which, f.rows[row.which]
      if dd then
        lib.__fillMedia(dd, S, Skin, owner, which)
        dd:SetValue(media[which] or lib.__skinMedia.FROM_SKIN)
        dd:SetDisabled(locked)
        local btn = f.reset[which]
        local word, tip = lib.__resetTip(S, Skin, owner, which)
        btn.__tip = word .. "\n" .. tip
        if media[which] and not locked then btn:Enable() else btn:Disable() end
        btn:SetAlpha(media[which] and not locked and 1 or 0.4)
      end
    end
  end

  --- Every row of `p` from what is applied (never the store: a preview is applied, not stored).
  function syncControls(p)
    local f = p.frame
    local rows = f.rows
    local locked = rows ~= nil and combatLocked()
    f:SetScript("OnUpdate", locked and f.wake or nil)
    if not rows then return end
    dropFocus(p)
    local ignore = lib.__readIgnore(p.Skin, p.owner)
    syncMedia(p, locked)
    if rows.outline then
      rows.outline:SetValue(p.Skin:GetOutline(p.owner))
      rows.outline:SetDisabled(locked or ignore.fonts)   -- Ignore fonts wins, as on the tab
    end
    if rows.panel then
      rows.panel:SetValue(ignore.panel)
      rows.fonts:SetValue(ignore.fonts)
      rows.panel:SetDisabled(locked)
      rows.fonts:SetDisabled(locked)
    end
    paintControls(p)
  end

  return { acquireControls = acquireControls, syncControls = syncControls, resetMedia = resetMedia }
end
