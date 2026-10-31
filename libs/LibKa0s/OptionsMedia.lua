-- LibKa0s-Options-1.0 -- the media pickers: AceGUI widget types Ka0sMedia_Font, Ka0sMedia_Statusbar,
-- Ka0sMedia_Border, Ka0sMedia_Background and Ka0sMedia_Sound. Each is a settings dropdown that shows
-- what it offers: the closed row draws the chosen entry in its own face or beside its swatch, and
-- every row of the pull-out does the same, with a play button on a sound row. It is the picker
-- AbsorbTracker gets from AceGUI-3.0-SharedMediaWidgets, for every addon that does not carry that
-- library (Ka0sAddonsCommonTasks docs/2026-10-31-FONT_PICKERS_AND_SKIN_FACES, D-08).
--
-- A sixteenth file of the Options major (minor 1), guarded with the same multi-file idiom as
-- OptionsSwitch.lua. A new file because OptionsWidgets.lua is in the band CLAUDE.md's census watches.
-- Nothing else needs it: both callers ask lib.__MediaWidgetType at call time and draw the stock
-- Dropdown when it answers nil, so a copy without this file loses the previews and no row.
--
-- BUILT FROM AceGUI's OWN Dropdown, as AuraMaster's AuraMasterDropdown is: the stock constructor
-- under a type name of ours, so the type has its own pool and a font set here never rides a pooled
-- object into another addon's dropdown. That gives the closed row the stock row's shape, and its
-- pull-out the stock scrolling, TOOLTIP strata on open (Dropdown-Pullout's Open) and clamping.
-- SetList's third argument is AceGUI's own seam for a custom row, Ka0sMedia_Item, the same trick on
-- Dropdown-Item-Toggle. The two base types are read from AceGUI's registry at call time; a registry
-- without them (the kit's AceGUI fake) registers nothing, and the callers draw a plain Dropdown.
--
-- OUR TYPE NAMES ONLY. AceGUI's registry is process-global (Options.lua's note above
-- lib.__PatchLSM30Border), so this file registers the six names above, versioned on MEDIA_MINOR so
-- the newest vendored copy's constructors win, and re-registers nothing that is anyone else's.
--
-- THE SKIN. Skin:AliasAceType(type, "Dropdown") makes SkinAce.lua paint the closed row and its
-- pull-out as a Dropdown (D-09: this pull-out is the library's, so it wears the skin; an LSM30_*
-- pull-out stays stock). A pull-out is pooled by AceGUI for every Dropdown in the client, and this
-- file leaves it as it found it: it only adds the OnOpen callback, which a release wipes.
--
-- THE CLOSED FACE SURVIVES THE PAINTER. SkinAce sets the row's face from the owner's body font, and
-- again from every durability hook (SetDisabled). So `text` is post-hooked once per object: a
-- font from anyone but this file is what the row wears for a plain entry, and the preview goes
-- back on over it at that font's size and flags. The hook rides only this type's objects.
--
-- FACES LOAD BEFORE THEY DRAW. Text set in a face the client has not loaded draws blank until it is
-- set again (OptionsScroll.lua's font preload). The panel's show has normally loaded them; a font
-- picker asks again on acquiring and on opening, and when that loaded anything it dresses its rows
-- again on the next frame, font and text both, since text is what draws blank. A picker dresses
-- again after acquiring whatever that call loaded: the panel's show preloads in the same tick as its
-- render, so the closed row's face may be one frame old with the call answering nothing new. Rows are
-- dressed on open, not in SetList: a page refresh rebuilds every list, and only an opened list needs
-- its faces.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- Minor 1: the five picker types and Ka0sMedia_Item, lib.__MediaWidgetType (LK-F03, D-08, D-09).
local MEDIA_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own -- see OptionsScroll.lua for why.
if lib.__mediaMinor and lib.__mediaMinor >= MEDIA_MINOR
  and lib.__mediaShellMinor == lib.MINOR then return end
lib.__mediaMinor      = MEDIA_MINOR
lib.__mediaShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsMedia = MEDIA_MINOR

local ITEM_TYPE = "Ka0sMedia_Item"
-- LibSharedMedia's kind -> the picker type that shows it.
local TYPES = {
  font = "Ka0sMedia_Font", statusbar = "Ka0sMedia_Statusbar", border = "Ka0sMedia_Border",
  background = "Ka0sMedia_Background", sound = "Ka0sMedia_Sound",
}
-- Every name a row may ask for -> its kind: the kind itself, our type, or the SharedMediaWidgets
-- type it stands in for.
local KIND_OF = {
  LSM30_Font = "font", LSM30_Statusbar = "statusbar", LSM30_Border = "border",
  LSM30_Background = "background", LSM30_Sound = "sound",
}
for kind, wtype in pairs(TYPES) do
  KIND_OF[kind], KIND_OF[wtype] = kind, kind
end

local SWATCH_W, SWATCH_H = 44, 13      -- fits the 16px row pitch Dropdown-Pullout fixes
local SWATCH_INSET       = 6           -- from the closed bar's left edge and the row's right
local TEXT_GAP           = 4
local ROW_TEXT_RIGHT     = -8          -- Dropdown-Item-Toggle's own text inset from the row's right
local PLAY_SIZE          = 14
local ROW_FACE_SIZE      = 12          -- a row's preview, Ka0s Prototype's body size
local BAR_TINT           = 0.65        -- a white statusbar texture reads as a bar on a dark field
local WHITE              = "Interface\\Buttons\\WHITE8X8"
local SPEAKER            = "Interface\\Common\\VoiceChat-Speaker"
local SPEAKER_ON         = "Interface\\Common\\VoiceChat-On"

local function getLSM() return LibStub("LibSharedMedia-3.0", true) end

--- What `key` of `kind` resolves to, or nil: a key LibSharedMedia lacks, or no LibSharedMedia.
local function resolve(kind, key)
  local LSM = getLSM()
  if not (LSM and key ~= nil and type(LSM.Fetch) == "function") then return nil end
  local path = LSM:Fetch(kind, key, true)
  if path == "" then return nil end
  return path
end

--- LibSharedMedia's keys of `kind`, sorted without regard to case, as a list table and its order.
local function allKeys(kind)
  local LSM = getLSM()
  local hash = LSM and type(LSM.HashTable) == "function" and LSM:HashTable(kind) or {}
  local list, order = {}, {}
  for key in pairs(hash) do
    list[key] = key
    order[#order + 1] = key
  end
  table.sort(order, function(a, b) return tostring(a):upper() < tostring(b):upper() end)
  return list, order
end

--- SetFont under pcall: a client may raise on a file it cannot open, or answer false.
local function setFace(fs, path, size, flags)
  local ok, set = pcall(fs.SetFont, fs, path, size, flags)
  return ok and set ~= false
end

-- ── the swatch and the play button ───────────────────────────────────────────────────────────

local function makeSwatch(parent)
  local s = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  s:SetSize(SWATCH_W, SWATCH_H)
  local bar = s:CreateTexture(nil, "ARTWORK")
  bar:SetAllPoints(s)
  bar:SetVertexColor(BAR_TINT, BAR_TINT, BAR_TINT, 1)
  s.bar = bar
  s:Hide()
  return s
end

--- Show `path` on swatch `s`: a bar, an edge over a dark fill, or a tiled fill. No path hides it.
local function dressSwatch(s, kind, path)
  if not path then
    s:Hide()
    return
  end
  if kind == "statusbar" then
    s:SetBackdrop(nil)
    s.bar:SetTexture(path)
    s.bar:Show()
  else
    s.bar:Hide()
    if kind == "border" then
      s:SetBackdrop({ bgFile = WHITE, edgeFile = path, edgeSize = 8,
                      insets = { left = 2, right = 2, top = 2, bottom = 2 } })
      s:SetBackdropColor(0.1, 0.1, 0.1, 1)
      s:SetBackdropBorderColor(1, 1, 1, 1)
    else
      s:SetBackdrop({ bgFile = path, tile = true, tileSize = 16 })
      s:SetBackdropColor(1, 1, 1, 1)
    end
  end
  s:Show()
end

local function playOnClick(btn)
  if btn.sound == nil or type(PlaySoundFile) ~= "function" then return end
  pcall(PlaySoundFile, btn.sound, "Master")
end

local function makePlay(parent)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(PLAY_SIZE, PLAY_SIZE)
  btn:SetNormalTexture(SPEAKER)
  btn:SetHighlightTexture(SPEAKER_ON, "ADD")
  btn:SetScript("OnClick", playOnClick)
  btn:Hide()
  return btn
end

local function dressPlay(btn, path)
  btn.sound = path
  if path then btn:Show() else btn:Hide() end
end

-- ── a pull-out row ───────────────────────────────────────────────────────────────────────────

--- The media key row value `value` previews: the leading row's mapped key, else the value itself.
local function previewOf(m, value)
  local mapped = m.previews and m.previews[value]
  if mapped ~= nil then return mapped end
  return value
end

--- The row's swatch or play button, made on first need and anchored at its right. The text stops
--- short of it: this type's rows are the only ones that ever do.
local function rowExtra(item, field, make)
  local e = item.__media[field]
  if e then return e end
  e = make(item.frame)
  e:SetPoint("RIGHT", item.frame, "RIGHT", -SWATCH_INSET, 0)
  item.__media[field] = e
  return e
end

local function dressRow(kind, m, item)
  local st = item.__media
  local path = resolve(kind, previewOf(m, item.userdata and item.userdata.value))
  if kind == "font" then
    local base = st.base
    if not (path and setFace(item.text, path, ROW_FACE_SIZE, base[3] or "")) and base[1] then
      setFace(item.text, base[1], base[2], base[3])
    end
    return
  end
  local extra
  if kind == "sound" then
    extra = rowExtra(item, "play", makePlay)
    dressPlay(extra, path)
  else
    extra = rowExtra(item, "swatch", makeSwatch)
    dressSwatch(extra, kind, path)
  end
  item.text:SetPoint("BOTTOMRIGHT", extra, "BOTTOMLEFT", -TEXT_GAP, 0)
end

local function itemRelease(self)
  local st = self.__media
  st.stockRelease(self)
  if st.swatch then st.swatch:Hide() end
  if st.play then dressPlay(st.play, nil) end
  -- One pool for every kind: a font row may be the next use of a row that made room for a swatch.
  if st.swatch or st.play then self.text:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", ROW_TEXT_RIGHT, 0) end
  if st.base[1] then setFace(self.text, st.base[1], st.base[2], st.base[3]) end
end

local function buildItem()
  local AceGUI = LibStub("AceGUI-3.0", true)
  local item = AceGUI.WidgetRegistry["Dropdown-Item-Toggle"]()
  item.type = ITEM_TYPE               -- released into this type's pool, never the stock one
  item.__media = { stockRelease = item.OnRelease, base = { item.text:GetFont() } }
  item.OnRelease = itemRelease
  return item
end

-- ── the picker ───────────────────────────────────────────────────────────────────────────────

local function dressRows(self)
  local m = self.__media
  for _, item in self.pullout:IterateItems() do
    if item.type == ITEM_TYPE then dressRow(m.kind, m, item) end
  end
end

--- The closed row's face: the preview's at `plain`'s size and flags, else `plain` itself.
local function dressFace(self)
  local m, fs, plain = self.__media, self.text, self.__media.plain
  if not plain[1] then return end
  local path = resolve("font", previewOf(m, self.value))
  m.dressing = true
  if not (path and setFace(fs, path, plain[2], plain[3])) then
    setFace(fs, plain[1], plain[2], plain[3])
  end
  m.dressing = false
end

local function dressClosed(self)
  local m = self.__media
  if m.kind == "font" then return dressFace(self) end
  local path = resolve(m.kind, previewOf(m, self.value))
  if m.play then dressPlay(m.play, path) else dressSwatch(m.swatch, m.kind, path) end
end

--- Set `fs`'s text again, through "" since a client may skip setting the same string.
local function retext(fs)
  local text = fs:GetText()
  if text == nil or text == "" then return end
  fs:SetText("")
  fs:SetText(text)
end

--- Dress the row and an open list again next frame, unless the widget was released meanwhile.
local function redressNext(self)
  if not (C_Timer and C_Timer.After) then return end
  local m, serial = self.__media, self.__media.serial
  C_Timer.After(0, function()
    if m.serial ~= serial then return end
    dressClosed(self)
    retext(self.text)
    if self.open then
      dressRows(self)
      for _, item in self.pullout:IterateItems() do
        if item.type == ITEM_TYPE then retext(item.text) end
      end
    end
  end)
end

--- Have every face loaded (OptionsScroll.lua). A face loaded by this call may draw blank this frame,
--- so it dresses again next frame; `always` does so whatever the call loaded.
local function loadFaces(self, always)
  if self.__media.kind ~= "font" then return end
  local preload, LSM = lib.__PreloadFonts, getLSM()
  local ok, loaded = false, 0
  if type(preload) == "function" and LSM then ok, loaded = pcall(preload, LSM) end
  if always or (ok and type(loaded) == "number" and loaded > 0) then redressNext(self) end
end

local function onAcquire(self)
  local m = self.__media
  m.stock.OnAcquire(self)
  m.serial = m.serial + 1
  local po = self.pullout
  local events = rawget(po, "events")
  local stockOpen = events and events.OnOpen
  po:SetCallback("OnOpen", function(...)
    if stockOpen then stockOpen(...) end
    loadFaces(self)
    dressRows(self)
  end)
  loadFaces(self, true)
  dressClosed(self)
end

local function onRelease(self)
  local m = self.__media
  m.serial = m.serial + 1
  m.stock.OnRelease(self)
  m.previews = nil
  if m.swatch then m.swatch:Hide() end
  if m.play then dressPlay(m.play, nil) end
  if m.kind == "font" and m.base[1] then
    m.plain = m.base
    dressFace(self)
  end
end

--- Add a stored key the list lacks, so the field never reads blank. On the widget's own list. Only
--- from SetValue: callers set the list first, and at SetList the old value may be the one leaving it.
local function keepStored(self, value)
  if value == nil or value == "" or self.list == nil or self.list[value] ~= nil then return end
  self.__media.stock.AddItem(self, value, tostring(value), ITEM_TYPE)
end

--- Dropdown's SetList on a copy, since a stored key is added to it; no `list` means every key of
--- this kind. `order` puts leading rows first, as on the stock widget. The third argument is ours.
local function setList(self, list, order)
  local m = self.__media
  local own = {}
  if list then
    for key, text in pairs(list) do own[key] = text end
    if type(order) ~= "table" then
      local sorted = {}
      for key in pairs(own) do sorted[#sorted + 1] = key end
      table.sort(sorted, function(a, b) return tostring(own[a]):upper() < tostring(own[b]):upper() end)
      order = sorted
    end
  else
    own, order = allKeys(m.kind)
  end
  m.stock.SetList(self, own, order, ITEM_TYPE)
  if self.open then dressRows(self) end
end

local function setValue(self, value)
  keepStored(self, value)
  self.__media.stock.SetValue(self, value)
  dressClosed(self)
end

--- `previews` maps a list value to the media key its row shows: a leading row that means "the
--- skin's default" previews the key it stands for. nil clears it. Ours; the stock Dropdown has none.
local function setPreviews(self, previews)
  self.__media.previews = previews
  dressClosed(self)
  if self.open then dressRows(self) end
end

local function setDisabled(self, disabled)
  local m = self.__media
  m.stock.SetDisabled(self, disabled)
  if m.swatch then m.swatch:SetAlpha(disabled and 0.4 or 1) end
  if m.play then
    if disabled then m.play:Disable() else m.play:Enable() end
  end
end

--- The closed row's swatch or play button, at the bar's left with the text starting after it.
local function closedExtra(w, m)
  local bar = rawget(w, "button_cover") or w.frame
  local extra
  if m.kind == "sound" then
    m.play = makePlay(bar)
    extra = m.play
  else
    m.swatch = makeSwatch(bar)
    extra = m.swatch
  end
  extra:SetPoint("LEFT", bar, "LEFT", SWATCH_INSET, 0)
  w.text:SetPoint("LEFT", extra, "RIGHT", TEXT_GAP, 0)
end

--- A font from anyone else (the painter sets an object, a restore either) is what a plain entry
--- wears. `name` is the FontString method to post-hook.
local function hookFace(w, m, name)
  if type(hooksecurefunc) ~= "function" then return end
  hooksecurefunc(w.text, name, function(fs)
    if m.dressing then return end
    m.plain = { fs:GetFont() }
    dressFace(w)
  end)
end

local function buildPicker(kind)
  local AceGUI = LibStub("AceGUI-3.0", true)
  local w = AceGUI.WidgetRegistry.Dropdown()
  w.type = TYPES[kind]                -- released into this type's pool, never the stock one
  local base = { w.text:GetFont() }
  local m = { kind = kind, serial = 0, base = base, plain = base,
              stock = { OnAcquire = w.OnAcquire, OnRelease = w.OnRelease, SetList = w.SetList,
                        SetValue = w.SetValue, SetDisabled = w.SetDisabled, AddItem = w.AddItem } }
  w.__media = m
  w.OnAcquire, w.OnRelease, w.SetList = onAcquire, onRelease, setList
  w.SetValue, w.SetDisabled, w.SetPreviews = setValue, setDisabled, setPreviews
  if kind == "font" then
    hookFace(w, m, "SetFont")
    hookFace(w, m, "SetFontObject")
  else
    closedExtra(w, m)
  end
  return w
end

-- ── registration ─────────────────────────────────────────────────────────────────────────────

--- Register the types once AceGUI and its two bases are there. Answers true while they hold.
local function register()
  local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
  if not AceGUI or type(AceGUI.RegisterWidgetType) ~= "function" then return false end
  local reg = AceGUI.WidgetRegistry
  if type(reg) ~= "table" or type(reg.Dropdown) ~= "function"
    or type(reg["Dropdown-Item-Toggle"]) ~= "function" then return false end
  local Skin = LibStub("LibKa0s-Skin-1.0", true)
  if (AceGUI:GetWidgetVersion(ITEM_TYPE) or 0) < MEDIA_MINOR then
    AceGUI:RegisterWidgetType(ITEM_TYPE, buildItem, MEDIA_MINOR)
  end
  for kind, wtype in pairs(TYPES) do
    if (AceGUI:GetWidgetVersion(wtype) or 0) < MEDIA_MINOR then
      AceGUI:RegisterWidgetType(wtype, function() return buildPicker(kind) end, MEDIA_MINOR)
    end
    if Skin and type(Skin.AliasAceType) == "function" then Skin:AliasAceType(wtype, "Dropdown") end
  end
  return true
end

--- The picker type for `name` (a LibSharedMedia kind, a Ka0sMedia_* type or the LSM30_* type it
--- stands in for), registered and ready for AceGUI:Create, or nil when `name` is none of those or
--- AceGUI lacks the stock Dropdown it builds on.
function lib.__MediaWidgetType(name)
  local kind = KIND_OF[name]
  if not (kind and register()) then return nil end
  return TYPES[kind]
end
