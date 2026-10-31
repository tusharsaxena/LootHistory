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
-- WHAT IT DRAWS, top to bottom, in one window at least 308 wide, its center 75% of the way up the
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
--     live, and the reload flag SetChoice answers is kept for Apply. A pick whose look differs from
--     the one the window opened with previews with the font and texture overrides cleared, as Apply
--     will save it (minor 3); a pick back to it restores them. The owner's write seam is not called
--     and no popup is raised. It closes the list, not the window;
--   * the eye (Media icon "eye"), only when `spec.onPreview` is a function: the host's test mode, so
--     the player sees the skin on the addon's own frames; it keeps working while a preview is
--     pending, and the window is Raise()d once onPreview returns;
--   * the gear (Media icon "settings"): saves the pending pick as Apply does, then `spec.onSettings`,
--     by default the settings panel opened at `spec.page` (O.OpenOptionsPanel(page), OptionsRegistry
--     minor 4) and O.SelectTab(page, spec.tab or "Appearance"); then the window closes;
--   * the Skin tab's rows (LK-A3; see THE ROWS below): under "Font and texture", "Font" and "Texture",
--     each a full-width media picker with a reset icon at its right, then "Font outline"; "Scope", with
--     "Ignore settings panel" and "Ignore fonts" side by side;
--   * "Apply" (a primary button): saves the pending pick (spec.set(source, key)), then a changed scope
--     (spec.set(nil, nil, ignore)), then changed media (spec.set(nil, nil, nil, media)), then the one
--     reload popup when any pick in this showing asked for one, then closes the window;
--   * "Apply to all Ka0s addons", shown only while another skin owner is registered: Apply, then
--     every other owner gets the same source, skin, scope, font, texture and font outline
--     (lib.__copySkinTo with lib.__copySettings, the Skin tab's copy, LK-A3), one reload popup
--     naming every addon that needs one, then this window closes and every queued picker is
--     dismissed (its `spec.onClose` runs; it never shows).
-- The close control and Escape dismiss WITHOUT saving: a pending preview is put back (Skin:SetChoice
-- to the owner's stored choice as it reads NOW, through spec.get, no write: only the unsaved preview
-- is undone, so a skin the Skin tab or a profile change stored while the window was up stays, and
-- whatever the rows previewed, see THE ROWS), then the window closes. Every close route (Apply, the close control, the gear, Escape,
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
-- the next queued picker. The open skin list is a transient popup, T8: FULLSCREEN_DIALOG, so it lays
-- over the rows and the Apply buttons rather than pushing them down, may hang past the window's foot,
-- and is taken by no toplevel raise (LK-A3; it was part of the window, which grew to hold it). The media
-- pull-outs are AceGUI's and open at TOOLTIP over everything here. A child of the window, the list
-- closes with it by construction.
--
-- SKIN. Every piece is painted for the owner through the Skin facade (Core.ApplySkin's Shell, the
-- close control's CloseButton, Dropdown, Button, MenuFrame, ListRow), so a skin switch repaints it
-- live through Skin:Repaint; the dropdown's label follows the owner's OnLooksChanged. The rows'
-- names keep their own skins' faces: no font primitive reaches them.
--
-- A ROW'S NAME NEVER STAYS BLANK (LK-A2). Text set in a face the client has not loaded draws blank
-- until it is set again (OptionsScroll.lua's font preload), and a face it refuses draws nothing. So
-- every skin's body face, and only those, goes through lib.__PreloadFonts on every show, since this
-- window can come up for a player who never opens settings and must not load every LSM face; a
-- refused SetFont puts the row back in its template's face; and every open, and a skin switch
-- under an open list, dresses each row at once and again next frame, font and text through "", the
-- trick OptionsMedia.lua's font pickers use. The next frame's pass also takes a name that measures
-- nothing to the template's face, for a face the client accepted and cannot draw. Every open starts
-- from the skin's face again, so one that has loaded since is worn. The worn override's face and the
-- owner's own (EllesmereUI's may be none of the skins') go through the same preload, for the closed
-- rows. Every other face waits for a font row's pull-out to open: those rows are made with
-- lib.__createLazyMedia, so that first open is what loads them, as the panel's show does for a page.
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
-- Minor 3 (LK-07 of Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK, the owner's item 1
-- and ruling D-10): choosing another skin resets the font and texture overrides to its own. A pick
-- whose look differs from the one the window opened with (Skin:DrawsKey) previews with the owner's
-- overrides cleared (Skin:SetOverride, no write); a pick back to it restores them; Apply (and the
-- gear, and Apply to all) then writes the cleared overrides through spec.set's fourth argument; a
-- dismissal puts back the overrides the window opened with. Apply to all resets them for every other
-- owner whose look changes (lib.__copySkinTo, through lib.__chooseSkin, OptionsAppearance minor 4).
-- Still minor 3 (LK-11 of the same run, the owner's item 12 and ruling D-16): O.SkinVerb(spec), the
-- act behind every addon's `/<slash> skin` verb. The host hands it the spec its first-run start
-- builds, so it shows the same picker a new profile shows, whatever the profile's seen flag says. In
-- combat it shows nothing and prints VERB_COMBAT on every call (never through O.__combatRefused,
-- which prints once per combat), with one Cfg line through the descriptor's `debug`; queued, it
-- prints VERB_QUEUED; with no picker to show, VERB_UNAVAILABLE and a Cfg line naming the cause.
-- The row and the disabled refusal are the host's (slash-commands-§3: the verb table lives in the
-- addon).
-- Minor 4 (LK-F04 of Ka0sAddonsCommonTasks docs/2026-10-31-FONT_PICKERS_AND_SKIN_FACES, the owner's
-- item 4): APPLY_ALL_TIP says "that skin's default font and texture", the Skin tab's wording.
-- Still minor 4 (LK-A2 of the same run, the owner's blank Azeroth row): see A ROW'S NAME NEVER STAYS
-- BLANK above.
-- Still minor 4 (LK-A3 of the same run): see THE ROWS above. The window is 308 wide, not 280; the
-- open list is T8, over the window, where it grew the window; Apply to all carries the scope, font,
-- texture and outline; and the APPLY, APPLY_ALL and SETTINGS tips say so. Its review: dropFocus(), the
-- rows' wake at the end of combat, MEDIA_H at AceGUI's labeled 40 (44 hung each reset icon 4 below its
-- bar), the "Font and texture" line, lib.__pickerSettle and lib.__pickerRebase, and saveRows sending
-- the scope and outline that are applied, not the ones the rows last previewed. The wake's event gave
-- way to the OnUpdate in THE ROWS when re-vendoring turned seven addons' stand-down suites red.
local PICKER_MINOR = 4
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
  APPLY_TIP      = "Keep these choices and close the window.",
  APPLY_ALL      = "Apply to all Ka0s addons",
  APPLY_ALL_TIP  = "Keep these choices, and give every other loaded Ka0s addon that uses skins the " ..
                   "same skin source, skin, scope, font, texture and font outline.",
  PREVIEW_TIP    = "Preview: open test mode",
  SETTINGS_TIP   = "Keep these choices and open the Skin settings",
  PREVIEW_GLYPH  = "o",
  SETTINGS_GLYPH = "*",
  -- O.SkinVerb's words (LK-11). VERB_HELP is the `skin` row's help text, one wording for every host.
  VERB_HELP        = "Choose a skin: open the skin picker",
  VERB_COMBAT      = "|cffaaaaaacannot open the skin picker during combat|r",
  VERB_QUEUED      = "Another Ka0s addon's skin picker is open; this one opens when it closes.",
  VERB_UNAVAILABLE = "Skins are unavailable: LibKa0s-Skin-1.0 did not load.",
}

local WIDTH, PAD, TOP = 308, 12, 40
local DD_H, ROW_H, ICON, BTN_H, APPLY_W = 26, 22, 24, 24, 80
-- The owner's line sits at TOP; the dropdown row one line below it.
local LABEL_H = 18
local DD_TOP = TOP + LABEL_H + 4
local BASE_H = DD_TOP + DD_H + PAD + BTN_H + 10
-- The rows: a labeled dropdown's height (AceGUI's SetLabel sets 40 over OnAcquire's 44, its bar the
-- foot of it), the gap under each, a section's line, the check boxes, and the right check box's width
-- (the left one takes the rest: its label is the longer).
local MEDIA_H, ROW_GAP, LINE_H, CHECK_H, CHECK_W = 40, 4, 16, 24, 112
local MEDIA_ROWS = { { which = "font", word = "FONT", tip = "FONT_TIP" },
                     { which = "texture", word = "TEXTURE", tip = "TEXTURE_TIP" } }
local SWATCH = 10
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"
-- Where the window's center sits, as a share of UIParent's height from its bottom edge.
local HEIGHT_SHARE = 0.75
-- The rows' template, which draws a name whenever its skin's face does not.
local ROW_FONT = "GameFontHighlight"
-- The reset icons' art: the client's own refresh arrow, grayed to sit with the Media icons. Not the
-- Media icon "reset": a consumer's vendored icons are pruned to its `LibKa0s icons:` line, eleven of
-- them lack that file, and a texture that fails to load draws nothing and raises nothing.
local RESET_ART = "Interface\\Buttons\\UI-RefreshButton"
local WAKE_EVERY = 0.25   -- seconds between reads of the lock while rows are drawn locked

local function skinMajor()
  return LibStub and LibStub("LibKa0s-Skin-1.0", true) or nil
end

local function report(err)
  local h = type(geterrorhandler) == "function" and geterrorhandler()
  if type(h) == "function" then h(err) end
end

--- The page lock's predicate, what O.__combatRefused refuses by, or the client's without that file.
local function combatLocked()
  if type(lib.__IsCombatLocked) == "function" then return lib.__IsCombatLocked() and true or false end
  return (InCombatLockdown ~= nil and InCombatLockdown()) and true or false
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

--- The Skin tab is about to write `owner`, and the write reads the applied state: the shown picker's
--- previews go back first (THE ROWS). Internal.
function lib.__pickerSettle(owner)
  local cur = queue().current
  if cur and cur.owner == owner and cur.settle then cur.settle() end
end

--- The Skin tab wrote `owner`: the shown picker measures from what it stored. Internal.
function lib.__pickerRebase(owner)
  local cur = queue().current
  if cur and cur.owner == owner and cur.rebase then cur.rebase() end
end

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

--- The file of LibSharedMedia font `key`, or a false value.
local function fontPath(key)
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  return key and LSM and type(LSM.Fetch) == "function" and LSM:Fetch("font", key, true)
end

--- A skin's body face for its row: its `font.body` through LibSharedMedia and its `font.bodySize`.
local function skinFace(Skin, key)
  local T = Skin:ResolveSkin(key)
  return fontPath(T["font.body"]), T["font.bodySize"] or 12
end

--- The file of `owner`'s font override, or a false value.
local function wornFace(Skin, owner)
  if type(Skin.GetOverride) ~= "function" then return nil end
  return fontPath((Skin:GetOverride(owner)))
end

--- Have every skin's body face loaded, through OptionsScroll.lua's preload (looked up at call time;
--- a copy without that file has none). It is handed those faces alone, as an LSM's font table, so
--- it loads no other; the paths it has tried are the library's, so each loads once.
local function loadFaces(Skin, owner)
  local preload = lib.__PreloadFonts
  if type(preload) ~= "function" then return end
  local faces = {}
  for _, def in ipairs(Skin:Skins()) do faces[def.key] = skinFace(Skin, def.key) end
  faces["@worn"] = wornFace(Skin, owner)
  if type(lib.__baseTokens) == "function" then
    faces["@own"] = fontPath(lib.__baseTokens(Skin, owner)["font.body"])
  end
  pcall(preload, { HashTable = function() return faces end })
end

--- SetFont under pcall, answering whether `fs` took the face. A client may raise on a file it cannot
--- open, or answer false or nil; a nil counts only when the face reads back.
local function setFace(fs, path, size)
  local ok, set = pcall(fs.SetFont, fs, path, size, "")
  if not ok or set == false then return false end
  return set and true or fs:GetFont() == path
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
  -- The picker shown last: { frame, spec, S, owner, Skin, Sk, rows, open, shown, height, opened,
  -- openedDraws, openedMedia, openedOutline, openedWorn, openedIgnore, mediaLeft, outlineLeft,
  -- scopeLeft, pending, reload }. `opened` is the applied choice when the showing began, `openedDraws`
  -- the look it drew then (Skin:DrawsKey), `openedMedia` its overrides then (`{ font, texture }`, each
  -- a key or false), `openedOutline` the mode it had stored (nil: never set), `openedWorn` the mode
  -- that meant and `openedIgnore` its scope (`{ panel, fonts }`); the three `*Left` are what a preview
  -- left in those halves, nil while a half is as it opened (THE ROWS, above); `pending` the skin a
  -- pick previews and Apply has not saved, `reload` whether any pick in this showing asked for a
  -- reload; `height` the window's, its rows included. The frame's `rows` holds the AceGUI widgets of
  -- this showing, nil while it is closed.
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

  local function label(def, p)
    p = p or P
    return p.S["SKIN_" .. def.key] or def.label
  end

  local syncControls

  --- An open pull-out of `p`'s rows closed: see THE ROWS, on why this window has to ask.
  local function dropFocus(p)
    local ace, rows = O.AceGUI, p.frame and p.frame.rows
    local w = ace and ace.FocusedWidget
    if not (w and rows and type(ace.ClearFocus) == "function") then return end
    for _, row in pairs(rows) do
      if row == w then
        ace:ClearFocus()
        return
      end
    end
  end

  --- The dropdown button, the rows' states and their names' color: from the pending pick, else the
  --- stored choice, and the skin worn now; then the Skin tab's rows, from what is applied.
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
    syncControls(P)
  end

  --- The list shown or hidden over the window, for picker `p` (default the one shown last). The
  --- window's own height is its rows', open or not.
  local function layout(p)
    p = p or P
    local f = p.frame
    f.list:SetHeight(#p.rows * ROW_H + 4)
    f:SetHeight(p.height or BASE_H)
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

  --- `row`'s name set again, through "" since a client may skip setting the same string.
  local function setName(p, row)
    local def = p.Skin:GetSkin(row.key)
    row.text:SetText("")
    row.text:SetText(def and label(def, p) or row.key)
  end

  --- `row`'s name in its skin's face, else the template's, and its text set again.
  local function dressRow(p, row)
    local path, size = skinFace(p.Skin, row.key)
    if not (path and setFace(row.text, path, size)) then row.text:SetFontObject(ROW_FONT) end
    setName(p, row)
  end

  --- Next frame's pass over an open list: a face that finished loading paints, and a name that
  --- still measures nothing goes to the template's face until the next open tries again.
  local function redressOpen(p)
    if not p.open then return end
    for _, row in ipairs(p.rows) do
      dressRow(p, row)
      if row.text:GetStringWidth() == 0 then
        row.text:SetFontObject(ROW_FONT)
        setName(p, row)
      end
    end
  end

  --- Every row of `p` dressed now and again next frame: rows are built once, so this is what a face
  --- that arrived since they were built draws through.
  local function dressRows(p)
    for _, row in ipairs(p.rows) do dressRow(p, row) end
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function() redressOpen(p) end)
    end
  end

  local function setOpen(open, p)
    p = p or P
    dropFocus(p)
    p.open = open and true or false
    layout(p)
    if p.open then dressRows(p) end
  end

  local function reloadPopup(labels)
    if lib.__appearanceReload then lib.__appearanceReload(P.S, labels) end
  end

  local function ownerLabel(name)
    return P.Skin:OwnerLabel(name) or name
  end

  --- The look `p`'s owner draws now: Skin:DrawsKey, else (a Skin copy without it) its skin key.
  local function drawsNow(p)
    if type(p.Skin.DrawsKey) == "function" then return p.Skin:DrawsKey(p.owner) end
    return select(2, p.Skin:GetChoice(p.owner))
  end

  --- `p`'s overrides now, `font, texture`, each a key or false.
  local function overrides(p)
    if type(p.Skin.GetOverride) ~= "function" then return false, false end
    local font, texture = p.Skin:GetOverride(p.owner)
    return font or false, texture or false
  end

  --- `p`'s overrides moved to (font, texture), each a key or false, no write, and `mediaLeft` to
  --- match: nil when that is what the window opened with.
  local function previewOverrides(p, font, texture)
    p.Skin:SetOverride(p.owner, font, texture)
    local m = p.openedMedia
    p.mediaLeft = (font ~= m.font or texture ~= m.texture) and { font = font, texture = texture } or nil
  end

  --- `p`'s overrides as the window opened with them, put back (no write) when a preview moved them,
  --- and only while nothing else moved them since: the look drawn now is the opened one, and the
  --- overrides are still the pair the preview left. A Skin-tab write made while the window was up
  --- (another skin's reset, or an override) stays live, as the profile holds it.
  local function restoreMedia(p)
    local left = p.mediaLeft
    if not left then return end
    p.mediaLeft = nil
    if drawsNow(p) ~= p.openedDraws then return end
    local font, texture = overrides(p)
    if font ~= left.font or texture ~= left.texture then return end
    p.Skin:SetOverride(p.owner, p.openedMedia.font, p.openedMedia.texture)
  end

  --- `p`'s outline as the window opened with it: a mode it had stored, or never set.
  local function outlineAsOpened(p)
    if p.openedOutline == nil and type(p.Skin.__ClearOutline) == "function" then
      p.Skin:__ClearOutline(p.owner)
    else
      p.Skin:SetOutline(p.owner, p.openedOutline)
    end
  end

  --- `p`'s outline previewed at `mode`, no write; the mode it opened wearing is put back as it was.
  local function previewOutline(p, mode)
    if mode == p.openedWorn then
      outlineAsOpened(p)
      p.outlineLeft = nil
    else
      p.Skin:SetOutline(p.owner, mode)
      p.outlineLeft = mode
    end
  end

  local function restoreOutline(p)
    local left = p.outlineLeft
    if not left then return end
    p.outlineLeft = nil
    if p.Skin:GetOutline(p.owner) == left then outlineAsOpened(p) end
  end

  --- `p`'s scope previewed at (panel, fonts), no write.
  local function previewScope(p, panel, fonts)
    p.Skin:SetIgnore(p.owner, panel, fonts)
    local m = p.openedIgnore
    p.scopeLeft = (panel ~= m.panel or fonts ~= m.fonts) and { panel = panel, fonts = fonts } or nil
  end

  local function restoreScope(p)
    local left = p.scopeLeft
    if not left then return end
    p.scopeLeft = nil
    local panel, fonts = p.Skin:GetIgnore(p.owner)
    if panel == left.panel and fonts == left.fonts then
      p.Skin:SetIgnore(p.owner, p.openedIgnore.panel, p.openedIgnore.fonts)
    end
  end

  --- After a preview moved the Skin major from the look `before`: a look other than the one the
  --- window opened with wears its own font and texture (the overrides cleared, no write), whatever a
  --- row previewed under the last look; the opened look gets its overrides back (minor 3, D-10).
  local function previewMedia(before)
    if type(P.Skin.SetOverride) ~= "function" then return end
    local now = drawsNow(P)
    if now == before then return end
    if now == P.openedDraws then
      previewOverrides(P, P.openedMedia.font, P.openedMedia.texture)
    else
      previewOverrides(P, false, false)
    end
  end

  --- Preview `key`: refused in combat; otherwise the Skin major moves (the addon repaints live), the
  --- overrides follow the look (previewMedia), and the reload flag SetChoice answers is kept for
  --- Apply. No write, no popup. Closes the list, not the window.
  local function pick(key)
    setOpen(false)
    if refused() then return end
    local source = readChoice()
    local before = drawsNow(P)
    local _, reload = P.Skin:SetChoice(P.owner, source, key)
    previewMedia(before)
    P.pending = key
    if reload then P.reload = true end
    refresh()
  end

  --- The media write for `p`: every half, as the Skin tab writes them. `outline` is the mode stored.
  local function mediaWrite(p)
    if lib.__appliedMedia then return lib.__appliedMedia(p.Skin, p.owner) end
    local font, texture = overrides(p)
    return { font = font, texture = texture }
  end

  --- Save what the rows moved, each half through the seam the Skin tab writes it with, as it is
  --- applied now (what the rows show), and take it as what the window opened with: a gear the panel
  --- refuses leaves the window up.
  local function saveRows(p)
    if p.scopeLeft then
      local ignore = lib.__readIgnore(p.Skin, p.owner)
      p.openedIgnore, p.scopeLeft = ignore, nil
      safeCall(p.spec.set, nil, nil, { panel = ignore.panel, fonts = ignore.fonts })
    end
    if p.mediaLeft or p.outlineLeft then
      local media = mediaWrite(p)
      p.openedMedia, p.mediaLeft = { font = media.font, texture = media.texture }, nil
      if p.outlineLeft then
        p.openedOutline, p.openedWorn, p.outlineLeft = media.outline, p.Skin:GetOutline(p.owner), nil
      end
      safeCall(p.spec.set, nil, nil, nil, media)
    end
  end

  --- Save the pending pick through the owner's write seam, the stored source kept, then what the
  --- rows moved, overrides a skin pick cleared among it. Answers whether any pick in this showing
  --- asked for a reload; the caller raises the popup.
  local function save()
    local key = P.pending
    if key ~= nil then
      local source = readChoice()
      P.pending = nil
      safeCall(P.spec.set, source, key)
    end
    saveRows(P)
    local reload = P.reload
    P.reload = false
    return reload
  end

  --- A dismissal of picker `p`: its pending preview put back, the Skin major moved to the owner's
  --- stored choice as it reads now (spec.get, each half it gives no usable value for taken from the
  --- choice the window opened with), so only the unsaved preview is undone: a skin the Skin tab or
  --- a profile change stored meanwhile stays. Never the Skin major's applied choice: the pick moved
  --- it to the preview. The overrides the window opened with come back when the preview cleared
  --- them, then the outline and the scope the rows previewed. No write.
  local function revert(p)
    local pending = p.pending
    p.pending, p.reload = nil, false
    if pending ~= nil then
      local source, skin = readChoice(p, p.opened or {})
      p.Skin:SetChoice(p.owner, source, skin)
    end
    restoreMedia(p)
    restoreOutline(p)
    restoreScope(p)
  end

  --- Give the rows of this showing back to AceGUI's pool: a closed picker holds none.
  local function releaseControls(p)
    local f = p.frame
    local rows = f and f.rows
    if not rows then return end
    f.rows = nil
    for _, w in pairs(rows) do
      w.frame:Hide()
      O.AceGUI:Release(w)
    end
    for _, btn in pairs(f.reset) do btn:Hide() end
    f.mediaLabel:Hide()
    f.scopeLabel:Hide()
  end

  --- Picker `p`'s window has gone, by any route: a pending preview put back, `spec.onClose` once per
  --- showing, then the next queued picker, when `p` was the picker shown. It takes the record, never
  --- the upvalue P: the client fires OnHide inside Hide(), and the advance there can make another
  --- owner on this instance P before the hide that started it returns.
  local function closed(p)
    if not (p and p.shown) then return end
    p.shown = false
    p.frame:SetScript("OnUpdate", nil)
    setOpen(false, p)
    releaseControls(p)
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

  --- Apply to all: Apply for this owner, then every other owner gets the same source, skin, scope,
  --- font, texture and font outline (the Skin tab's copy, LK-A3), one reload popup naming each that
  --- needs it, every queued picker dismissed, then the close. Refused in combat with the window left
  --- up. The settings are read before save(), which changes none of them.
  local function applyAll()
    if O.__combatRefused and O.__combatRefused("skin picker", "copy") then return end
    local Skin = P.Skin
    local source, stored = readChoice()
    local key = P.pending or stored
    local ignore, media
    if lib.__copySettings then ignore, media = lib.__copySettings(Skin, P.owner) end
    local reloads = {}
    if save() then reloads[1] = ownerLabel(P.owner) end
    for _, name in ipairs(others()) do
      if lib.__copySkinTo(Skin, name, source, key, ignore, media) then reloads[#reloads + 1] = ownerLabel(name) end
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

  local resetMedia   -- the rows' section, below

  --- One icon button: the Media icon `icon` for the owner, else the text glyph; or, with `art`, that
  --- client file grayed.
  local function iconButton(f, icon, glyph, tip, onClick, art)
    local btn = CreateFrame("Button", nil, f)
    btn:SetSize(ICON, ICON)
    local path = art or iconPath(P.owner, icon)
    if path then
      local t = btn:CreateTexture(nil, "ARTWORK")
      t:SetPoint("CENTER")
      t:SetSize(ICON - 8, ICON - 8)
      t:SetTexture(path)
      if art and type(t.SetDesaturated) == "function" then t:SetDesaturated(true) end
      btn.icon = t
    else
      local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      fs:SetPoint("CENTER")
      fs:SetText(glyph)
      btn.text = fs
    end
    attachTip(btn, tip)
    btn:SetScript("OnClick", function(...)
      dropFocus(P)
      onClick(...)
    end)
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
    btn:SetScript("OnClick", function(...)
      dropFocus(P)
      onClick(...)
    end)
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
    row.text = fs
    dressRow(P, row)
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
    list:SetFrameStrata("FULLSCREEN_DIALOG")   -- T8: over the rows and the buttons (LAYERING)
    list:SetClampedToScreen(true)
    list:EnableMouse(true)                     -- a click between rows reaches no row under it
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
    f.reset = {}
    for _, row in ipairs(MEDIA_ROWS) do
      local which = row.which
      local btn = iconButton(f, nil, nil, "", function() resetMedia(which) end, RESET_ART)
      btn:Hide()
      f.reset[which] = btn
    end
  end

  --- One section's line, hidden until the rows under it are drawn.
  local function sectionLine(f)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, 0)
    if type(fs.SetJustifyH) == "function" then fs:SetJustifyH("LEFT") end
    fs:Hide()
    P.Sk.Text(fs, "body")
    return fs
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
    -- The two sections' lines, reading as the dropdowns' own labels do, shown while their rows are.
    f.mediaLabel = sectionLine(f)
    f.scopeLabel = sectionLine(f)
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

  -- ── the Skin tab's rows ─────────────────────────────────────────────────────────────────────

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
    local media = lib.__nextMedia(P.Skin, P.owner, which, value)
    previewOverrides(P, media.font, media.texture)
  end

  --- A reset icon: that half back to the skin's own, a preview like the row's own entry for it.
  function resetMedia(which)
    setOpen(false)
    local rows = P.frame.rows
    if not (rows and select(which == "font" and 1 or 2, overrides(P))) then return end
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
    dd:SetCallback("OnValueChanged", onRow(function(mode) previewOutline(P, mode) end))
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
      previewScope(P, on, lib.__readIgnore(P.Skin, P.owner).fonts)
    end)
    rows.fonts = checkRow(S, "IGNORE_FONTS", "IGNORE_FONTS_TIP", function(on)
      previewScope(P, lib.__readIgnore(P.Skin, P.owner).panel, on)
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
    f:SetScript("OnMouseDown", function() dropFocus(mine) end)
    -- Rows drawn locked wake when combat ends (THE ROWS): syncControls arms this, closed() disarms it.
    local waited = 0
    f.wake = function(self, elapsed)
      waited = waited + (elapsed or 0)
      if waited < WAKE_EVERY then return end
      waited = 0
      if combatLocked() then return end
      self:SetScript("OnUpdate", nil)
      if P == mine then refresh() end
    end
    P.Sk.OnLooksChanged(function()
      if P == mine then
        refresh()
        fit(mine)
        if mine.open then dressRows(mine) end
      end
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

  --- What `p` restores to from now, and no preview left in any row: a fresh showing, or the Skin tab's
  --- write.
  local function opening(p)
    local Skin, owner = p.Skin, p.owner
    p.opened = { Skin:GetChoice(owner) }
    p.openedDraws = drawsNow(p)
    local font, texture = overrides(p)
    p.openedMedia, p.mediaLeft = { font = font, texture = texture }, nil
    p.openedOutline, p.outlineLeft = nil, nil
    if type(Skin.__StoredOutline) == "function" then p.openedOutline = Skin:__StoredOutline(owner) end
    p.openedWorn = type(Skin.GetOutline) == "function" and Skin:GetOutline(owner) or nil
    local panel, fonts = false, false
    if type(Skin.GetIgnore) == "function" then panel, fonts = Skin:GetIgnore(owner) end
    p.openedIgnore, p.scopeLeft = { panel = panel, fonts = fonts }, nil
  end

  --- Show `owner`'s picker on this instance and make it the one shown: a fresh showing records the
  --- choice it opens with and is placed; a repeat while up re-reads `spec`, keeping the preview.
  local function show(owner, spec, Skin)
    local fresh = not (P and P.owner == owner and P.shown)
    P = pickers[owner] or { owner = owner, rows = {}, open = false }
    pickers[owner] = P
    P.spec, P.Skin, P.Sk, P.S = spec, Skin, Skin:For(owner), mergeStrings(spec.strings)
    loadFaces(Skin, owner)
    local f = P.frame or build()
    syncRows()
    applySpec(f)
    if fresh then
      P.pending, P.reload = nil, false
      opening(P)
      place(f)
    end
    acquireControls(P)
    setOpen(false)
    refresh()
    f:Show()
    local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
    if core and type(core.RaiseStaticPopups) == "function" then core.RaiseStaticPopups() end
    P.shown = true
    local mine = P
    queue().current = {
      owner = owner, inst = O, frame = f,
      settle = function() revert(mine) end,
      rebase = function()
        opening(mine)
        if P == mine then refresh() end
      end,
    }
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
  --- gear, never by a pick or a row, as the tab calls it; without one the rows are not drawn), onPreview (the eye; absent without it), onSettings (the gear; default:
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

  --- Why pickerTarget answered nil, for the verb's Cfg line: the one printed wording covers all three.
  local function unavailableCause(spec)
    local Skin = skinMajor()
    if not (Skin and type(Skin.IsOwner) == "function") then return "no Skin major" end
    if not Skin:IsOwner(spec.owner or defaultOwner or (P and P.owner)) then return "owner not registered" end
    return "no client"
  end

  --- The `/<slash> skin` verb's act (LK-11): O.SkinPicker(spec) on demand, saying why when nothing
  --- shows. The host passes the spec its first-run start builds. In combat: nothing shows, one gray
  --- VERB_COMBAT line on every call and one Cfg line, answering nil, "combat". Queued behind another
  --- owner's picker: VERB_QUEUED, nil, "queued". No picker to show (no Skin major, no client, an
  --- unregistered owner): VERB_UNAVAILABLE, nil, "unavailable", with a Cfg line naming which.
  --- Otherwise the picker's frame.
  function O.SkinVerb(spec)
    spec = type(spec) == "table" and spec or {}
    local S = mergeStrings(spec.strings)
    local say = O.__print or function() end
    local function cfg(what)
      if type(d) == "table" and type(d.debug) == "function" then
        d.debug("Cfg", "skin picker " .. tostring(spec.owner or defaultOwner) .. " " .. what)
      end
    end
    if inLockdown() then
      say(S.VERB_COMBAT)
      cfg("refused (in combat)")
      return nil, "combat"
    end
    local f, why = O.SkinPicker(spec)
    if f then return f end
    if why == "queued" then
      say(S.VERB_QUEUED)
      return nil, "queued"
    end
    say(S.VERB_UNAVAILABLE)
    cfg("unavailable (" .. unavailableCause(spec) .. ")")
    return nil, "unavailable"
  end
end
