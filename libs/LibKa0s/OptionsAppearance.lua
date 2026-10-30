-- LibKa0s-Options-1.0 -- the Appearance tab (skinning-§3): where a player picks the skin an addon
-- wears. The instance members O.AppearanceTab and O.AppearanceRows, attached through
-- lib.__AttachAppearance, and the words, lib.APPEARANCE_STRINGS. Its key stays "Appearance"; since
-- minor 3 its label reads "Skin" (hosts name the key in `before` and in a stored active tab).
--
-- A thirteenth file of the Options major (minor 1), guarded with the same multi-file idiom as
-- OptionsKeybinds.lua; Options minor 33 attaches it. It loads after OptionsKeybinds.lua, so its
-- default place on a strip names that file's tab key.
--
-- WHAT IT DRAWS, top to bottom, under the page's own headings (the order since minor 4, LK-08):
--   * the skin SOURCE: Ka0s skins | EllesmereUI, two radio choices. EllesmereUI is choosable only
--     while LibKa0s-Skin-1.0's gate holds for the owner (Skin:GetEUIStatus); under it, every one of
--     the gate's conditions is listed with the client's ready-check mark or cross, and a failing
--     one with its one-line fix;
--   * the LOOK: the library's fixed note about what a skin changes, then one radio choice per
--     registered skin (Skin:Skins(), registration order), each with its four swatches, its name and
--     its one-line description;
--   * FONT AND TEXTURE (minor 3): two dropdowns side by side, the owner's font and bar texture
--     (LibSharedMedia-3.0's font and statusbar keys, sorted), each led by "Skin's own (<its key>)",
--     through Skin:SetOverride and `spec.set`'s fourth argument (LibKa0s-Skin-1.0 minor 6); under
--     each (minor 4) its "Reset font" / "Reset texture" button, at the dropdown's width, disabled
--     while that half is already the skin's own; under those (minor 4) the "Font outline" dropdown,
--     All text | HUD text only | Off, through Skin:SetOutline and `media.outline` in `spec.set`'s
--     fourth argument, disabled while "Ignore fonts" is on (which wins);
--   * SCOPE (minor 2): two check boxes on the dropdowns' half-width grid, "Ignore settings panel"
--     (this addon's settings pages stay the client's) and "Ignore fonts" (every string keeps its own
--     face and size), through Skin:SetIgnore and `spec.set`'s third argument;
--   * OTHER KA0S ADDONS (its own heading since minor 4): COPY TO EVERY KA0S ADDON..., a button that,
--     after a confirmation naming the other loaded owners by label, gives each of them this owner's
--     source, skin, scope, font, texture and font outline, through Skin:SetChoice, Skin:SetIgnore,
--     Skin:SetOverride and Skin:SetOutline (a live repaint) and then its own registered setter
--     (Skin:WriteChoice). With no other owner loaded it is disabled and a line says why.
--
-- THE WRITE SEAM. The tab writes this owner's choice only through `spec.set(source, skin, ignore,
-- media)`, `ignore` being `{ panel, fonts }` on a scope write, `media` `{ font, texture }` (each an
-- LSM key or false) on a font or texture write, and both nil on a source or skin write (a skin
-- write that reset the overrides is followed by a media write, minor 4), which
-- MUST be the owner's write seam (options-ui-§1). Since minor 4 `media` carries `outline` too (one of
-- Skin's OUTLINE_MODES), and every media write carries all three. Skin:SetChoice first, so the repaint
-- is the library's and an owner's onChange calling SetChoice again is a no-op (SetChoice is idempotent),
-- then spec.set. The reload popup is raised once, by the tab, from SetChoice's pending-reload answer.
--
-- POPUPS. Both are Blizzard StaticPopups (LIBKA0S_SKIN_COPY, LIBKA0S_SKIN_RELOAD), defined when they
-- are shown so the words are the spec's. A StaticPopup is a shared Blizzard frame at DIALOG, above
-- the settings window: the library never re-stratas or restyles it (frame-layering, skinning-§7).

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- Minor 1: O.AppearanceTab, O.AppearanceRows, lib.APPEARANCE_STRINGS and the two popups.
-- Minor 2: the Scope section (Ignore settings panel, Ignore fonts) between the skins and the copy
-- button, and the copy carries both (the owner's request, 2026-10-27; LibKa0s-Skin-1.0 minor 5).
-- Minor 3 (LibKa0s#63): the tab is labeled "Skin" (its key stays "Appearance"); a "Font and texture"
-- section between the skins and the scope, two dropdowns through Skin:SetOverride and `spec.set`'s
-- fourth argument; and the copy carries them (LibKa0s-Skin-1.0 minor 6). "Skin's own" names the face
-- the owner wears without its overrides (Skin:__BaseTokens, EllesmereUI's when it paints), and a
-- stored key LibSharedMedia lacks stays listed as "<key> (not loaded)". Amended before release
-- (PK-02): the skins' heading reads "Look", not the tab's own "Skin" (options-ui-§7), and the
-- other owners and one owner's skin copy are library-level (lib.__skinOthers, lib.__copySkinTo),
-- so the skin picker's "Apply to all Ka0s addons" shares them.
-- Minor 4 (LK-03 of Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK, the owner's ruling
-- D-06): the "Font outline" dropdown under the Scope's check boxes (LibKa0s-Skin-1.0 minor 9's
-- SetOutline), grayed while Ignore fonts is on; `media` gains `outline` and every media write carries
-- the font, the texture and the outline; the copy carries it, and lib.__copySkinTo takes a `media`
-- with any of its halves left out (nil: the target's own). Still minor 4 (LK-07, the owner's item 1
-- and ruling D-10): choosing another skin resets the font and texture overrides to the new skin's
-- own, through lib.__chooseSkin (the look drawn, Skin:DrawsKey, before against after), from the
-- tab's pick, its copy and the skin picker's Apply to all (lib.__copySkinTo); never inside
-- Skin:SetChoice, which re-applies a stored skin at load. And still minor 4 (LK-08, the owner's item
-- 6 and ruling D-11): "Reset font" and "Reset texture" under the two dropdowns, each disabled while
-- its half is the skin's own; the Font outline dropdown moves from the Scope into the Font and
-- texture section, under them; the Scope's check boxes take the dropdowns' half width; the copy
-- button gets its own heading, "Other Ka0s addons"; and the note leads the Look section.
local APPEARANCE_MINOR = 4
-- Paired on the SHELL's minor as well as this file's own -- see OptionsScroll.lua for why.
if lib.__appearanceMinor and lib.__appearanceMinor >= APPEARANCE_MINOR
  and lib.__appearanceShellMinor == lib.MINOR then return end
lib.__appearanceMinor      = APPEARANCE_MINOR
lib.__appearanceShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsAppearance = APPEARANCE_MINOR

-- ── the words ────────────────────────────────────────────────────────────────────────────────
--
-- A literal table, as lib.KEYBIND_STRINGS is: the library carries no locale, and a host that has
-- one passes `spec.strings` with any of these keys. Three more families of keys translate what the
-- Skin major names: `SKIN_<key>` and `SKIN_<key>_DESC` a skin's name and description, and
-- `COND_<key>` and `COND_<key>_HINT` (with %s for the addon's label) one EllesmereUI condition.
-- ASCII throughout but for COPY's ellipsis, which options-ui-§21 asks of a button that opens a
-- confirmation (tests/test_prose.lua ratifies it for this file alone).
lib.APPEARANCE_STRINGS = {
  TAB_LABEL      = "Skin",
  TAB_TIP        = "The skin this addon wears: its windows, panels, settings pages and HUD, and the " ..
                   "font and bar texture it draws them with.",
  SOURCE_HEADING = "Skin source",
  SOURCE_KA0S    = "Ka0s skins",
  SOURCE_KA0S_TIP = "Draw this addon with the Ka0s skin chosen below.",
  SOURCE_EUI     = "EllesmereUI",
  SOURCE_EUI_TIP = "Take this addon's look from EllesmereUI. If EllesmereUI cannot skin it, the " ..
                   "Ka0s skin chosen below is used instead.",
  EUI_READY      = "EllesmereUI can skin this addon.",
  EUI_NOT_READY  = "EllesmereUI cannot skin this addon yet:",
  EUI_MISSING    = "EllesmereUI skins are not available with this copy of the library.",
  SKIN_HEADING   = "Look",
  SKIN_EUI_NOTE  = "While EllesmereUI skins this addon, the skin below is used only if it cannot.",
  COPY           = "Copy to every Ka0s addon\226\128\166",
  MEDIA_HEADING  = "Font and texture",
  FONT           = "Font",
  FONT_TIP       = "Replace every font this addon's skin draws with this one. \"Ignore fonts\" wins: " ..
                   "with it on, every string keeps the game's own font.",
  TEXTURE        = "Texture",
  TEXTURE_TIP    = "Replace the bar texture of every bar and chart this addon draws.",
  SKIN_OWN       = "Skin's own (%s)",
  MEDIA_MISSING  = "%s (not loaded)",
  SCOPE_HEADING  = "Scope",
  IGNORE_PANEL   = "Ignore settings panel",
  IGNORE_PANEL_TIP = "Keep this addon's settings panel in the game's own look. Its windows still " ..
                   "wear the skin.",
  IGNORE_FONTS   = "Ignore fonts",
  IGNORE_FONTS_TIP = "Keep every font in this addon as the game draws it, face and size. The skin " ..
                   "still colors the text.",
  OUTLINE        = "Font outline",
  OUTLINE_TIP    = "Where the skin draws its outline around text: on all of this addon's text, on " ..
                   "its HUD text only, or nowhere. A font outline you set on an element yourself " ..
                   "still applies. Not read while \"Ignore fonts\" is on.",
  OUTLINE_ALL    = "All text",
  OUTLINE_HUD    = "HUD text only",
  OUTLINE_OFF    = "Off",
  RESET_FONT     = "Reset font",
  RESET_FONT_TIP = "Use the skin's own font again (%s).",
  RESET_TEXTURE  = "Reset texture",
  RESET_TEXTURE_TIP = "Use the skin's own bar texture again (%s).",
  COPY_HEADING   = "Other Ka0s addons",
  COPY_TIP       = "Give every other loaded Ka0s addon that uses skins this addon's skin source, " ..
                   "skin, scope, font, texture and font outline. You are asked first.",
  COPY_NONE      = "No other loaded Ka0s addon uses skins yet.",
  COPY_CONFIRM   = "Give these addons the skin source, skin, scope, font, texture and font outline of %s?\n\n%s" ..
                   "\n\nAddons that are not loaded are unchanged.",
  COPY_ACCEPT    = "Copy",
  CANCEL         = "Cancel",
  RELOAD         = "%s needs a reload to stop using the EllesmereUI skin.",
  RELOAD_ACCEPT  = "Reload now",
  RELOAD_LATER   = "Later",
  NOTE           = "Skins change every visual element. HUD style options follow the skin unless " ..
                   "you set them yourself.",
  UNAVAILABLE    = "Skins are not available for this addon.",
}

-- The column width of one choice, relative, three to a line under the clip inset (options-ui-§8).
local W_CHOICE = 0.32
-- Half the row, two to a line (options-ui-§6's 50/50 cells): the dropdowns, their reset buttons, the
-- scope's check boxes and the copy button share it, so they line up (minor 4, D-11).
local function halfWidth(O) return O.BUTTON_PAIR_REL or 0.492 end
local MARK_OK   = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
local MARK_FAIL = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t"
local SWATCH    = "|TInterface\\Buttons\\WHITE8X8:12:12:0:0:8:8:0:8:0:8:%d:%d:%d|t"
local COPY_POPUP, RELOAD_POPUP = "LIBKA0S_SKIN_COPY", "LIBKA0S_SKIN_RELOAD"
-- The dropdown value that means "the skin's own" (LibKa0s-Skin-1.0's FROM_SKIN), and the two
-- overrides: the LSM kind each lists and the skin token its first entry names.
local FROM_SKIN = "@skin"
local MEDIA = { font = { kind = "font", token = "font.body", reset = "RESET_FONT" },
                texture = { kind = "statusbar", token = "bar.texture", reset = "RESET_TEXTURE" } }
-- The font outline modes in the dropdown's order (LibKa0s-Skin-1.0 minor 9's OUTLINE_MODES), each
-- with its word's key.
local OUTLINE_ORDER = { "all", "hud", "off" }
local OUTLINE_WORD = { all = "OUTLINE_ALL", hud = "OUTLINE_HUD", off = "OUTLINE_OFF" }

--- The Skin major, or nil. Asked at call time: it loads before this major, but a client may lack it.
local function skinMajor()
  return LibStub and LibStub("LibKa0s-Skin-1.0", true) or nil
end

local function report(err)
  local h = type(geterrorhandler) == "function" and geterrorhandler()
  if type(h) == "function" then h(err) end
end

--- lib.APPEARANCE_STRINGS with a host's translations over it, as a fresh table.
local function mergeStrings(overrides)
  local S = {}
  for k, v in pairs(lib.APPEARANCE_STRINGS) do S[k] = v end
  if type(overrides) == "table" then
    for k, v in pairs(overrides) do
      if type(v) == "string" then S[k] = v end
    end
  end
  return S
end

--- One swatch's markup from "#rrggbb", or "" for a value that is not one.
local function swatch(hex)
  local r, g, b = tostring(hex):match("^#?(%x%x)(%x%x)(%x%x)")
  if not r then return "" end
  return SWATCH:format(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
end

--- A skin's choice label: its four swatches, then its name (translated by `SKIN_<key>`).
local function skinLabel(S, def)
  local parts = {}
  for i = 1, 4 do parts[i] = swatch((def.swatches or {})[i]) end
  return table.concat(parts) .. "  " .. (S["SKIN_" .. def.key] or def.label)
end

--- One EllesmereUI condition's line: the mark, the label, and for a failing one its fix.
local function conditionText(S, c, label)
  local text = S["COND_" .. tostring(c.key)]
  text = text and text:format(label) or c.label
  if c.ok then return MARK_OK .. " " .. text end
  local hint = S["COND_" .. tostring(c.key) .. "_HINT"]
  hint = hint and hint:format(label) or c.hint
  return MARK_FAIL .. " " .. text .. ". " .. tostring(hint)
end

--- LibSharedMedia-3.0's keys of `kind`, sorted, or an empty list without it. Asked at call time.
local function mediaKeys(kind)
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  local out = {}
  if not LSM then return out end
  if type(LSM.List) == "function" then
    for _, key in ipairs(LSM:List(kind) or {}) do out[#out + 1] = key end
  elseif type(LSM.HashTable) == "function" then
    for key in pairs(LSM:HashTable(kind) or {}) do out[#out + 1] = key end
  end
  table.sort(out)
  return out
end

-- ── the popups ───────────────────────────────────────────────────────────────────────────────

local function reloadUI()
  if C_UI and type(C_UI.Reload) == "function" then return C_UI.Reload() end
  if type(ReloadUI) == "function" then return ReloadUI() end
end

--- Show a StaticPopup `which` defined from `def` now. Answers true when the client has the popups.
local function showPopup(which, def, a1, a2, data)
  if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return false end
  def.timeout, def.whileDead, def.hideOnEscape, def.preferredIndex = 0, true, true, 3
  StaticPopupDialogs[which] = def
  StaticPopup_Show(which, a1, a2, data)
  return true
end

--- The reload popup for `label` (an addon label, or several joined), worded by `S`. Internal.
function lib.__appearanceReload(S, label)
  return showPopup(RELOAD_POPUP, { text = S.RELOAD, button1 = S.RELOAD_ACCEPT, button2 = S.RELOAD_LATER,
                                   OnAccept = reloadUI }, label)
end

--- The copy confirmation: `run` on accept, the other owners' labels listed. Internal.
function lib.__appearanceConfirmCopy(S, label, names, run)
  return showPopup(COPY_POPUP, {
    text = S.COPY_CONFIRM, button1 = S.COPY_ACCEPT, button2 = S.CANCEL,
    OnAccept = function(_, data) if type(data) == "function" then data() end end,
  }, label, table.concat(names, "\n"), run)
end

-- ── the other owners, and one owner's copy ───────────────────────────────────────────────────

--- Every registered skin owner but `owner`, sorted (Skin:Owners() order). Internal: the copy button
--- here and the skin picker's "Apply to all Ka0s addons" (OptionsSkinPicker.lua) both read it.
function lib.__skinOthers(Skin, owner)
  local out = {}
  for _, name in ipairs(Skin:Owners()) do
    if name ~= owner then out[#out + 1] = name end
  end
  return out
end

--- `name`'s applied media, `{ font, texture, outline }` (each override an LSM key or false for the
--- skin's own; `outline` nil on a Skin copy before minor 9), or nil on a Skin copy before minor 6.
local function appliedMedia(Skin, name)
  if type(Skin.GetOverride) ~= "function" then return nil end
  local font, texture = Skin:GetOverride(name)
  return { font = font or false, texture = texture or false,
           outline = type(Skin.GetOutline) == "function" and Skin:GetOutline(name) or nil }
end

--- Move `name` to (source, skin) and, when the look it draws changed (Skin:DrawsKey before and
--- after; any change of the choice on a Skin copy without it), its font and texture back to the
--- skin's own (D-10: choosing another skin resets both overrides). Never inside Skin:SetChoice,
--- which also runs at load to re-apply a stored skin and must keep the stored overrides. Writes no
--- profile. Answers changed, reload (SetChoice's) and cleared (true when an override was reset).
--- Internal: the Skin tab's pick, its copy and the skin picker's Apply to all share it.
function lib.__chooseSkin(Skin, name, source, skin)
  local draws = type(Skin.DrawsKey) == "function"
  local before = draws and Skin:DrawsKey(name)
  local changed, reload = Skin:SetChoice(name, source, skin)
  if not (changed and type(Skin.SetOverride) == "function" and type(Skin.GetOverride) == "function") then
    return changed, reload, false
  end
  local font, texture = Skin:GetOverride(name)
  if not (font or texture) or (draws and Skin:DrawsKey(name) == before) then return changed, reload, false end
  Skin:SetOverride(name, false, false)
  return changed, reload, true
end

--- Give `name` (source, skin) and, when given, the scope `ignore` and the overrides `media`: the Skin
--- major first (lib.__chooseSkin, so a target whose look changes starts from the new skin's own
--- font and texture, then SetIgnore, SetOverride and, for `media.outline`, SetOutline: the live
--- repaint), then the owner's own setter (Skin:WriteChoice, nil leaving that half of its profile
--- alone). A `media` half left out (nil) keeps the target's own after the move, and the write
--- carries the target's applied font, texture and outline, so a setter that stores every half it is
--- given keeps what it has (minor 4); with no `media`, a reset the move made is written the same
--- way, so the target's profile matches what it wears. Answers the reload flag SetChoice answered.
--- Internal; the caller refuses combat.
function lib.__copySkinTo(Skin, name, source, skin, ignore, media)
  local _, reload, cleared = lib.__chooseSkin(Skin, name, source, skin)
  if ignore and type(Skin.SetIgnore) == "function" then Skin:SetIgnore(name, ignore.panel, ignore.fonts) end
  if media then
    if type(Skin.SetOverride) == "function" then Skin:SetOverride(name, media.font, media.texture) end
    if media.outline ~= nil and type(Skin.SetOutline) == "function" then Skin:SetOutline(name, media.outline) end
  end
  if media or cleared then media = appliedMedia(Skin, name) or media end
  Skin:WriteChoice(name, source, skin, ignore, media)
  return reload
end

-- ── the attach ───────────────────────────────────────────────────────────────────────────────

--- Called by lib:New (Options minor 33), guarded. Attaches the tab's two members.
function lib.__AttachAppearance(O, d)
  local defaultOwner = type(d) == "table" and type(d.addonName) == "string" and d.addonName or nil

  --- Color one AceGUI label in the page owner's muted role, away from Ka0s Default only.
  local function muted(w)
    local Sk = O.__chromeAway and O.__chromeAway()
    if not (Sk and w and type(w.SetColor) == "function") then return end
    local r, g, b = Sk.Color("text.muted")
    if r then w:SetColor(r, g, b) end
  end

  --- One full-width line of text in the view's parent: O.TextRow on the page's own scroll, a Label
  --- in a host-built body.
  local function textLine(view, text, quiet)
    local w
    if view.parent == view.ctx.scroll and O.TextRow then
      w = O.TextRow(view.ctx, text)
    else
      w = O.AceGUI:Create("Label")
      w:SetFullWidth(true)
      w:SetText(text)
      view.parent:AddChild(w)
    end
    if quiet then muted(w) end
    return w
  end

  --- A subject heading: the library's Section on the page's own scroll, a Heading in a host body.
  local function heading(view, text)
    if view.parent == view.ctx.scroll and O.Section then
      local h = O.Section(view.ctx, text)
      view.ctx.lastGroup = text   -- so the next heading takes its top spacer, as RenderRows' do
      return h
    end
    local h = O.AceGUI:Create("Heading")
    h:SetText(text)
    h:SetFullWidth(true)
    view.parent:AddChild(h)
    return h
  end

  local function flowGroup(view)
    local g = O.AceGUI:Create("SimpleGroup")
    g:SetLayout("Flow")
    g:SetFullWidth(true)
    view.parent:AddChild(g)
    return g
  end

  --- One radio choice in `group`; `onPick` runs when the player checks it.
  local function radio(view, group, label, tip, onPick)
    local cb = O.AceGUI:Create("CheckBox")
    cb:SetType("radio")
    cb:SetLabel(label)
    cb:SetRelativeWidth(W_CHOICE)
    cb:SetCallback("OnValueChanged", function(_, _, value)
      if value then onPick() end
      view.sync()
    end)
    if O.AttachTooltip and tip then O.AttachTooltip(cb, label, tip) end
    if view.ctx.__renderDisabled then cb:SetDisabled(true) end
    group:AddChild(cb)
    return cb
  end

  --- The owner's stored choice: `spec.get` (`{ source, skin }` or two values), else the Skin major's.
  local function readChoice(view)
    local Skin, get = view.Skin, view.spec.get
    local source, skin
    if type(get) == "function" then
      local ok, a, b = pcall(get)
      if ok and type(a) == "table" then source, skin = a.source or a[1], a.skin or a[2]
      elseif ok then source, skin = a, b
      else report(a) end
    end
    if source ~= "eui" and source ~= "ka0s" then source = select(1, Skin:GetChoice(view.owner)) end
    if type(skin) ~= "string" or not Skin:GetSkin(skin) then skin = select(2, Skin:GetChoice(view.owner)) end
    return source, skin
  end

  --- Move this owner to (source, skin): the Skin major first (lib.__chooseSkin: a change of the look
  --- it draws resets its font and texture to the new skin's own), then the owner's write seam, with
  --- every media half after it when the move reset an override, then the one reload popup SetChoice
  --- asks for. Refused in combat, as every settings write is.
  local function choose(view, source, skin)
    if O.__combatRefused and O.__combatRefused("appearance", view.owner) then return end
    local _, reload, cleared = lib.__chooseSkin(view.Skin, view.owner, source, skin)
    if type(view.spec.set) == "function" then
      local ok, err = pcall(view.spec.set, source, skin)
      if not ok then report(err) end
      if cleared then
        ok, err = pcall(view.spec.set, nil, nil, nil, appliedMedia(view.Skin, view.owner))
        if not ok then report(err) end
      end
    end
    if reload then lib.__appearanceReload(view.S, view.label) end
  end

  local function others(view)
    return lib.__skinOthers(view.Skin, view.owner)
  end

  --- This owner's scope, `{ panel, fonts }`: the Skin major's applied pair (false, false on a copy
  --- before Skin minor 5).
  local function readIgnore(view)
    if type(view.Skin.GetIgnore) ~= "function" then return { panel = false, fonts = false } end
    local panel, fonts = view.Skin:GetIgnore(view.owner)
    return { panel = panel == true, fonts = fonts == true }
  end

  --- This owner's overrides, `{ font, texture, outline }` (each override an LSM key or false for the
  --- skin's own; `outline` the applied font outline mode, nil on a Skin copy before minor 9), or nil
  --- on a Skin copy before minor 6.
  local function readMedia(view)
    return appliedMedia(view.Skin, view.owner)
  end

  --- Give every other owner this owner's choice, scope, font and texture: SetChoice, SetIgnore and
  --- SetOverride (the live repaint) then its own setter. Refused in combat here too: the confirmation is a StaticPopup
  --- above the page's combat cover, so it can be accepted after combat starts, long after onCopy's
  --- own check.
  local function copyTo(view, names)
    if O.__combatRefused and O.__combatRefused("appearance", "copy") then return end
    local Skin = view.Skin
    local source, skin = readChoice(view)
    local ignore = readIgnore(view)
    local media = readMedia(view)
    local reloads = {}
    for _, name in ipairs(names) do
      if lib.__copySkinTo(Skin, name, source, skin, ignore, media) then
        reloads[#reloads + 1] = Skin:OwnerLabel(name) or name
      end
    end
    if #reloads > 0 then lib.__appearanceReload(view.S, table.concat(reloads, ", ")) end
  end

  --- Move this owner's scope to (panel, fonts): the Skin major first (live, no reload), then the
  --- owner's write seam. Refused in combat, as every settings write is.
  local function setScope(view, panel, fonts)
    if O.__combatRefused and O.__combatRefused("appearance", view.owner) then return end
    view.Skin:SetIgnore(view.owner, panel, fonts)
    if type(view.spec.set) == "function" then
      local ok, err = pcall(view.spec.set, nil, nil, { panel = panel == true, fonts = fonts == true })
      if not ok then report(err) end
    end
  end

  --- One check box in `group`: `onToggle(value)` runs when the player flips it.
  local function toggle(view, group, label, tip, onToggle)
    local cb = O.AceGUI:Create("CheckBox")
    cb:SetLabel(label)
    cb:SetRelativeWidth(halfWidth(O))   -- the dropdowns' grid above, not the skins' (minor 4, D-11)
    cb:SetCallback("OnValueChanged", function(_, _, value)
      onToggle(value == true)
      view.sync()
    end)
    if O.AttachTooltip and tip then O.AttachTooltip(cb, label, tip) end
    if view.ctx.__renderDisabled then cb:SetDisabled(true) end
    group:AddChild(cb)
    return cb
  end

  --- Move this owner's font or texture (`which`) to `value` (an LSM key, or FROM_SKIN for the
  --- skin's own): the Skin major first (the live repaint), then the owner's write seam with both
  --- halves. Refused in combat, as every settings write is.
  local function setMedia(view, which, value)
    if O.__combatRefused and O.__combatRefused("appearance", view.owner) then return end
    local media = readMedia(view)
    media[which] = (type(value) == "string" and value ~= "" and value ~= FROM_SKIN) and value or false
    view.Skin:SetOverride(view.owner, media.font, media.texture)
    if type(view.spec.set) == "function" then
      local ok, err = pcall(view.spec.set, nil, nil, nil, media)
      if not ok then report(err) end
    end
  end

  --- Move this owner's font outline to `mode`: the Skin major first (the live repaint), then the
  --- owner's write seam with every media half. Refused in combat, as every settings write is.
  local function setOutline(view, mode)
    if O.__combatRefused and O.__combatRefused("appearance", view.owner) then return end
    view.Skin:SetOutline(view.owner, mode)
    if type(view.spec.set) == "function" then
      local ok, err = pcall(view.spec.set, nil, nil, nil, readMedia(view))
      if not ok then report(err) end
    end
  end

  --- The font outline dropdown in `group` (minor 4), its three modes in OUTLINE_ORDER.
  local function outlineDropdown(view, group)
    local S = view.S
    local items = {}
    for _, mode in ipairs(OUTLINE_ORDER) do items[mode] = S[OUTLINE_WORD[mode]] end
    local dd = O.AceGUI:Create("Dropdown")
    dd:SetLabel(S.OUTLINE)
    dd:SetRelativeWidth(halfWidth(O))
    dd:SetList(items, OUTLINE_ORDER)
    dd:SetCallback("OnValueChanged", function(_, _, value)
      setOutline(view, value)
      view.sync()
    end)
    if O.AttachTooltip then O.AttachTooltip(dd, S.OUTLINE, S.OUTLINE_TIP) end
    view.outlineLocked = view.ctx.__renderDisabled == true   -- a page drawn disabled stays so; sync reads it
    group:AddChild(dd)
    return dd
  end

  --- The owner's tokens without its overrides: what it wears as "the skin's own" (EllesmereUI's
  --- table while that paints it). ResolveSkin on a Skin copy without `__BaseTokens`.
  local function baseTokens(view)
    if type(view.Skin.__BaseTokens) == "function" then return view.Skin:__BaseTokens(view.owner) end
    local _, skin = view.Skin:GetChoice(view.owner)
    return view.Skin:ResolveSkin(skin)
  end

  --- The list one media dropdown offers: "Skin's own (<the face worn without overrides>)" first,
  --- then LSM's keys, then the stored override when LSM lacks it, so the field never shows blank.
  local function mediaList(view, which)
    local spec = MEDIA[which]
    local own = baseTokens(view)[spec.token]
    local items, order = { [FROM_SKIN] = view.S.SKIN_OWN:format(tostring(own or "-")) }, { FROM_SKIN }
    for _, key in ipairs(mediaKeys(spec.kind)) do
      if items[key] == nil then
        items[key] = key
        order[#order + 1] = key
      end
    end
    local media = readMedia(view)
    local stored = media and media[which]
    if stored and items[stored] == nil then
      items[stored] = view.S.MEDIA_MISSING:format(stored)
      order[#order + 1] = stored
    end
    return items, order
  end

  --- One media dropdown in `group`.
  local function mediaDropdown(view, group, which, label, tip)
    local dd = O.AceGUI:Create("Dropdown")
    dd:SetLabel(label)
    dd:SetRelativeWidth(halfWidth(O))
    dd:SetList(mediaList(view, which))
    dd:SetCallback("OnValueChanged", function(_, _, value)
      setMedia(view, which, value)
      view.sync()
    end)
    if O.AttachTooltip and tip then O.AttachTooltip(dd, label, tip) end
    if view.ctx.__renderDisabled then dd:SetDisabled(true) end
    group:AddChild(dd)
    return dd
  end

  --- One media half's reset button in `group` (minor 4, D-11): the skin's own again, through the
  --- same seam as the dropdown's "Skin's own" entry. `sync` disables it while that half is the
  --- skin's own, and words its tooltip with the skin's own key.
  local function resetButton(view, group, which)
    local btn = O.AceGUI:Create("Button")
    btn:SetText(view.S[MEDIA[which].reset])
    btn:SetRelativeWidth(halfWidth(O))
    btn:SetCallback("OnClick", function()
      if btn.disabled then return end
      setMedia(view, which, FROM_SKIN)
      view.sync()
    end)
    group:AddChild(btn)
    return btn
  end

  --- The font and texture section: two dropdowns side by side, their reset buttons under them, and
  --- the Font outline under those. Absent on a Skin copy before minor 6 (the outline, before minor 9).
  local function drawMedia(view)
    local S = view.S
    if type(view.Skin.SetOverride) ~= "function" then return end
    heading(view, S.MEDIA_HEADING)
    local group = flowGroup(view)
    view.media.font = mediaDropdown(view, group, "font", S.FONT, S.FONT_TIP)
    view.media.texture = mediaDropdown(view, group, "texture", S.TEXTURE, S.TEXTURE_TIP)
    -- A row of its own: a button on the dropdowns' line would top-align with their labels.
    local resets = flowGroup(view)
    view.resetLocked = view.ctx.__renderDisabled == true   -- a page drawn disabled stays so; sync reads it
    view.reset.font = resetButton(view, resets, "font")
    view.reset.texture = resetButton(view, resets, "texture")
    if type(view.Skin.SetOutline) == "function" then view.outline = outlineDropdown(view, flowGroup(view)) end
  end

  --- The scope section: the two exceptions, side by side. Absent on a Skin copy before minor 5.
  local function drawScope(view)
    local S = view.S
    if type(view.Skin.SetIgnore) ~= "function" then return end
    heading(view, S.SCOPE_HEADING)
    local group = flowGroup(view)
    view.ignore.panel = toggle(view, group, S.IGNORE_PANEL, S.IGNORE_PANEL_TIP, function(v)
      setScope(view, v, readIgnore(view).fonts)
    end)
    view.ignore.fonts = toggle(view, group, S.IGNORE_FONTS, S.IGNORE_FONTS_TIP, function(v)
      setScope(view, readIgnore(view).panel, v)
    end)
  end

  local function onCopy(view)
    if view.copy.disabled then return end
    if O.__combatRefused and O.__combatRefused("appearance", "copy") then return end
    local names = others(view)
    if #names == 0 then return end
    local labels = {}
    for i, name in ipairs(names) do labels[i] = view.Skin:OwnerLabel(name) or name end
    lib.__appearanceConfirmCopy(view.S, view.label, labels, function() copyTo(view, names) end)
  end

  --- The source section: the two choices, then the gate's conditions.
  local function drawSource(view)
    local S, Skin = view.S, view.Skin
    heading(view, S.SOURCE_HEADING)
    local status = type(Skin.GetEUIStatus) == "function" and Skin:GetEUIStatus(view.owner) or nil
    local group = flowGroup(view)
    view.source.ka0s = radio(view, group, S.SOURCE_KA0S, S.SOURCE_KA0S_TIP, function()
      choose(view, "ka0s", select(2, readChoice(view)))
    end)
    view.source.eui = radio(view, group, S.SOURCE_EUI, S.SOURCE_EUI_TIP, function()
      if view.source.eui.disabled then return end
      choose(view, "eui", select(2, readChoice(view)))
    end)
    local current = readChoice(view)
    if not (status and status.ok) and current ~= "eui" then view.source.eui:SetDisabled(true) end
    if not status then
      textLine(view, S.EUI_MISSING, true)
      return
    end
    textLine(view, status.ok and S.EUI_READY or S.EUI_NOT_READY, true)
    for _, c in ipairs(status.conditions or {}) do
      view.conditions[#view.conditions + 1] = textLine(view, conditionText(S, c, view.label), not c.ok)
    end
  end

  --- The skin section: the note about what a skin changes (its lead line since minor 4), then one
  --- choice per registered skin.
  local function drawSkins(view)
    local S = view.S
    heading(view, S.SKIN_HEADING)
    view.note = textLine(view, S.NOTE, true)
    if readChoice(view) == "eui" then textLine(view, S.SKIN_EUI_NOTE, true) end
    local group = flowGroup(view)
    for _, def in ipairs(view.Skin:Skins()) do
      local key = def.key
      local desc = S["SKIN_" .. key .. "_DESC"] or def.desc
      local cb = radio(view, group, skinLabel(S, def), desc, function()
        choose(view, (readChoice(view)), key)
      end)
      if type(cb.SetDescription) == "function" then cb:SetDescription(desc) end
      view.skins[key] = cb
      view.order[#view.order + 1] = key
    end
  end

  --- The other Ka0s addons section (its own heading since minor 4, D-11): the copy button in a row
  --- of its own, and its hint while no other owner is loaded.
  local function drawCopy(view)
    local S = view.S
    heading(view, S.COPY_HEADING)
    local btn = O.AceGUI:Create("Button")
    btn:SetText(S.COPY)
    btn:SetRelativeWidth(halfWidth(O))
    btn:SetCallback("OnClick", function() onCopy(view) end)
    if O.AttachTooltip then O.AttachTooltip(btn, S.COPY, S.COPY_TIP) end
    local lonely = #others(view) == 0 or type(view.Skin.WriteChoice) ~= "function"
    if lonely or view.ctx.__renderDisabled then btn:SetDisabled(true) end
    flowGroup(view):AddChild(btn)
    view.copy = btn
    if lonely then textLine(view, S.COPY_NONE, true) end
  end

  --- The reset buttons from the applied overrides: each disabled while its half is the skin's own
  --- (or the page was drawn disabled), its tooltip naming the skin's own key worn now.
  local function syncResets(view, media)
    if not next(view.reset) then return end
    local own = baseTokens(view)
    for which, btn in pairs(view.reset) do
      local spec = MEDIA[which]
      btn:SetDisabled(view.resetLocked or not (media and media[which]))
      if O.AttachTooltip then
        local tip = view.S[spec.reset .. "_TIP"]
        O.AttachTooltip(btn, view.S[spec.reset], tip:format(tostring(own[spec.token] or "-")))
      end
    end
  end

  --- O.AppearanceRows' view: the controls, and `sync`, which re-reads the store into them.
  local function newView(ctx, spec, parent, Skin, owner)
    local view = { ctx = ctx, spec = spec, parent = parent, Skin = Skin, owner = owner,
                   S = mergeStrings(spec.strings), label = Skin:OwnerLabel(owner) or owner,
                   source = {}, skins = {}, order = {}, conditions = {}, ignore = {}, media = {},
                   reset = {} }
    function view.sync()
      local source, skin = readChoice(view)
      if view.source.ka0s then view.source.ka0s:SetValue(source == "ka0s") end
      if view.source.eui then view.source.eui:SetValue(source == "eui") end
      for key, cb in pairs(view.skins) do cb:SetValue(key == skin) end
      local ignore = readIgnore(view)
      if view.ignore.panel then view.ignore.panel:SetValue(ignore.panel) end
      if view.ignore.fonts then view.ignore.fonts:SetValue(ignore.fonts) end
      local media = readMedia(view)
      for which, dd in pairs(view.media) do
        dd:SetList(mediaList(view, which))   -- the skin's own entry names the skin worn now
        dd:SetValue(media and media[which] or FROM_SKIN)
      end
      syncResets(view, media)
      if view.outline then
        view.outline:SetValue(view.Skin:GetOutline(view.owner))
        view.outline:SetDisabled(ignore.fonts or view.outlineLocked)   -- Ignore fonts wins
      end
    end
    return view
  end

  --- A host-tab entry for O.RenderTabbedSchema's `opts.tabs`, or for a host-drawn strip (its
  --- `render` is the body). See O.AppearanceRows for `spec`.
  function O.AppearanceTab(spec)
    spec = spec or {}
    local S = mergeStrings(spec.strings)
    local before = spec.before
    if before == nil then before = "Keybindings" end
    if before == false then before = nil end
    return {
      key = spec.key or "Appearance", label = S.TAB_LABEL, tooltip = S.TAB_TIP, before = before,
      render = function(ctx) O.AppearanceRows(ctx, spec) end,
    }
  end

  --- Draw the Appearance rows into `parent` (default: the page's scroll). Answers the view
  --- `{ owner, source = { ka0s, eui }, skins = { [key] = choice }, media = { font, texture },
  --- reset = { font, texture } (the two reset buttons, minor 4), ignore = { panel, fonts }, outline
  --- (the Font outline dropdown, minor 4; nil on a Skin copy before minor 9), order, conditions,
  --- copy, note, sync }`, or nil when degraded (no AceGUI, no Skin major, or an owner that
  --- never registered: then one line says skins are not available). `spec`: get (the owner's read,
  --- `{ source, skin }` or two values), set (MUST be the owner's write seam, called as
  --- set(source, skin), from the Scope section set(nil, nil, { panel, fonts }), and from the Font
  --- and texture section and the Font outline set(nil, nil, nil, { font, texture, outline })), owner (the
  --- skin owner, default the descriptor's `addonName`), strings (translations); key and before are
  --- the tab's.
  function O.AppearanceRows(ctx, spec, parent)
    spec = spec or {}
    parent = parent or O.EnsureScroll(ctx)
    if not O.AceGUI or not parent then return nil end
    local Skin = skinMajor()
    local owner = spec.owner or defaultOwner
    local view = { ctx = ctx, parent = parent }
    if not (Skin and type(Skin.IsOwner) == "function" and Skin:IsOwner(owner)) then
      textLine(view, mergeStrings(spec.strings).UNAVAILABLE)
      return nil
    end
    view = newView(ctx, spec, parent, Skin, owner)
    drawSource(view)
    drawSkins(view)
    drawMedia(view)
    drawScope(view)
    drawCopy(view)
    view.sync()
    if type(ctx.refreshers) == "table" then
      ctx.refreshers[#ctx.refreshers + 1] = function() view.sync() end
    end
    return view
  end
end
