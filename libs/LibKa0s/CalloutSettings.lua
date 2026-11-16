-- LibKa0s-Callout-1.0 — CalloutSettings.lua: the settings section a consumer drops into its own panel.
--
-- ── WHAT IT IS ───────────────────────────────────────────────────────────────────────────────
--
-- The Look, Sound and Texts rows of one call-out, a live preview and its two test buttons, and the
-- unlock-to-move toggle (the owner's decisions of 2026-11-13, docs/superpowers/plans/2026-11-13-
-- callout.md, row L4). A file of the Callout major, paired on Callout.lua's minor the way
-- WidgetsCopyWindow.lua is on Widgets', so a section from one vendored copy never pairs with a
-- call-out from another without saying so. A payload without this file loads whole and its
-- instances have no BuildSettings.
--
-- ── THE TWO BUILDS ───────────────────────────────────────────────────────────────────────────
--
-- WITH the host's LibKa0s-Options-1.0 instance (`opts.options`), `parent` is a page ctx (what the
-- instance's CreatePanel answers, or the ctx a RenderTabbedSchema host tab's render is handed), and
-- every control is the Options instance's own: the rows are ordinary path-less schema rows (the
-- W15 arm, read and written through each row's `get` / `set`, which call the instance's Get / Set),
-- drawn by `O.RenderRows`, so they are the panel's dropdowns, sliders, checkboxes, edit boxes and
-- color swatches, in the host's skin, under its combat lock. The font row is the one media picker
-- (`Ka0sMedia_Font`, options-ui-§23). Options-ui-§13 puts every section on a tab: `SettingsTabs`
-- answers the three tab entries for the host's `RenderTabbedSchema` (`opts.tabs`), each drawing
-- its tab through `BuildSettings(ctx, { options, tab })`; with no `opts.tab` the three sections are
-- drawn one under another, each under its heading, for a host that gives the call-out one tab.
--
-- ON THE HOST'S ROUTE (minor 3: the descriptor's `path` and `set`, or `opts.prefix`), the Options
-- build draws the rows `SchemaRows(prefix)` answers, each carrying its path, which the host has
-- registered in its own schema: the Options instance reads and writes them through its descriptor,
-- so architecture-§5's helper validates, stores, reacts (the row's onChange is the instance's Apply)
-- and announces, and the host's slash get / set / reset reaches every one. The Play pick and the
-- unlock toggle are session rows there too.
--
-- ONE TAB (minor 4, the owner's redesign of 2026-11-14, plan row L13): `SettingsTab` answers a single
-- host tab, "Callout", drawn by `BuildSettings(ctx, { options, layout = "side" })`: a "Preview"
-- heading over the preview block, then the Options instance's side tabs (O.SideTabs), Look (the
-- face rows and the six colors) and Sound. The stock texts' words and mutes are not drawn, and
-- `SchemaRows(prefix, { texts = false })` leaves their rows out of the host's schema too, so on the
-- route the host's seam refuses the instance's Set("texts.<KEY>") and Set("muted.<KEY>") and nothing
-- is stored. A host wanting its own words registers `SchemaRows(prefix)` without the option (the
-- rows stay undrawn) or passes them per call through Show. The documented shape for a host on the
-- route; `SettingsTabs` and the three-tab build stay as they were.
--
-- WITHOUT one, `parent` is a plain frame and the section is built of plain frames, one control per
-- line: a check button for a toggle, a value between - and + buttons for a number, a button that
-- steps through the choices for a list, a swatch that opens the client's color picker for a color.
-- The per-key text boxes are the Options build's alone.
--
-- ── THE PREVIEW ──────────────────────────────────────────────────────────────────────────────
--
-- Over each tab: a sample line ("5  GO!  STOP", each in its kind's color) drawn in the chosen face,
-- outline and shadow at the chosen size up to PREVIEW_MAX, repainted on every write (a refresher in
-- the page's `refreshers`, which the Options instance's write runs). The one tab's layout draws no
-- sample line (minor 5, the owner's call of 2026-11-14, plan row L17): its Preview heading, the
-- buttons and the rows stay, and the real call-out is what shows the look. "Test countdown" counts the
-- real call-out down from 5 to GO; "Play" shows the stock text picked beside it, with its voice, or
-- (minor 4) counts down from 10 to 1, numbers only, when "Countdown 10 to 1" is picked.
-- The picked text is session state, never saved. "Unlock to move" is the instance's SetLocked: the
-- real call-out shows its sample and takes the mouse until locked again (never saved either).
--
-- ── WORDS ────────────────────────────────────────────────────────────────────────────────────
--
-- Every word is `lib.SETTINGS_STRINGS`, US English; a host passes `opts.L` keyed to it (read with
-- rawget, because a Ka0s locale table answers an unknown key with the key). A stock text's own word
-- (READY, GO!) is the call-out's `STOCK` text.
--
-- Depends on the Callout shell (Callout.lua's `lib.__methods`) and, for the Options build, on the
-- host's Options instance it is handed. LibSharedMedia-3.0, LibKa0s-Media-1.0 and C_VoiceChat are
-- each read at build time and optional.

local lib = LibStub and LibStub("LibKa0s-Callout-1.0", true)
-- Minor 3 reads the shell's minor-2 privates (`__validFor`, `__defaultFor`, `__colorFor`, `__prefixOf`),
-- and minor 4 its minor-3 glow settings (`__glowColorFor`): an older shell gets no settings section
-- rather than one whose rows it refuses.
if not lib or type(lib.__methods) ~= "table" or type(lib.__validFor) ~= "function"
  or type(lib.__colorFor) ~= "function" or type(lib.__glowColorFor) ~= "function" then return end

-- Minor 1: the section (plan row L4).
-- Minor 2 (plan row L2, v1.97.0): `FONT_FACES`, the call-out's display faces (Oxanium Bold, the
-- default, and LibKa0s-Media-1.0 13's Bebas Neue and Russo One), lead the font row after "Skin font"
-- and "Game default", each offered when the host's LibSharedMedia lists it (without LSM, when the
-- winning Media copy ships it); every other face follows, sorted, as before.
-- Minor 3 (plan row L11, v1.98.0): `SchemaRows`, the settings as schema rows a host registers
-- under its own prefix (architecture-§5), and the Options build on the host's route, where every row
-- carries its path and is written through the host's seam. Needs the Callout shell at minor 2.
-- Minor 4 (plan row L13, v1.100.0): `SettingsTab`, the section as one host tab (a Preview block over
-- Look and Sound side tabs, through the Options instance's O.SideTabs, OptionsNav minor 7; Colors in
-- Look; no stock texts), `BuildSettings`' `opts.layout = "side"`, `SchemaRows`' and `SettingsRows`'
-- `opts.texts = false`, and the Play list's "Countdown 10 to 1"; and (plan row L15) the Glow rows in
-- Look, AuraMaster's text glow (on/off, Glow color, Use class color, Use the skin's color, Intensity,
-- Thickness, X and Y offset) in place of the Off / Soft / Strong choice. Needs the shell at minor 3.
-- Minor 5 (plan row L17, v1.102.0): the one tab's layout (`layout = "side"`, both builds) draws no
-- sample line; its Preview heading, Test countdown and Play, Text to play, Unlock to move and Reset
-- position stay. The three-tab build keeps its line. `FONT_FACES` leads with the new default face,
-- Oxanium SemiBold (Callout minor 4), then Oxanium Bold. Needs the shell at minor 3, as minor 4 did.
local SETTINGS_MINOR = 5
if lib.__settingsMinor and lib.__settingsMinor >= SETTINGS_MINOR
  and lib.__settingsShellMinor == lib.MINOR then return end
lib.__settingsMinor      = SETTINGS_MINOR
lib.__settingsShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.CalloutSettings = SETTINGS_MINOR

local METHODS = lib.__methods

lib.SETTINGS_STRINGS = {
  TAB_LOOK = "Look", TAB_SOUND = "Sound", TAB_TEXTS = "Texts", TAB_CALLOUT = "Callout",
  TAB_CALLOUT_TIP = "The call-out: a preview to test it with, how it looks and what it says.",
  TAB_LOOK_TIP = "How the call-out looks: its face, size, outline, shadow, glow and animation.",
  TAB_SOUND_TIP = "What the call-out says: a bundled voice, the game's text to speech, or nothing.",
  TAB_TEXTS_TIP = "Each kind's color, and each stock text's own words and voice.",
  PREVIEW = "Preview",
  TEST_COUNTDOWN = "Test countdown",
  TEST_COUNTDOWN_TIP = "Counts the call-out down from 5 to GO!, where it shows in play.",
  PLAY = "Play",
  PLAY_TIP = "Shows the text picked in Text to play, with its voice.",
  PLAY_KEY = "Text to play",
  PLAY_KEY_TIP = "The stock text Play shows, or a countdown from 10 to 1. Not saved.",
  PLAY_COUNTDOWN = "Countdown 10 to 1",
  UNLOCK = "Unlock to move",
  UNLOCK_TIP = "Shows the call-out with a drag strip so you can move it. Lock it again when it is in place. Not saved.",
  RESET_POSITION = "Reset position",
  RESET_POSITION_TIP = "Puts the call-out back in its default place.",
  FONT = "Font", FONT_TIP = "The call-out's face. Skin font is your skin's, Game default the game's own.",
  SIZE = "Size", SIZE_TIP = "The height of the call-out's text, 32 to 200.",
  OUTLINE = "Outline", OUTLINE_TIP = "The outline drawn around each letter.",
  OUTLINE_NONE = "None", OUTLINE_OUTLINE = "Outline", OUTLINE_THICK = "Thick outline",
  OUTLINE_MONO = "Monochrome",
  SHADOW = "Shadow", SHADOW_TIP = "A black shadow behind the text.",
  SHADOW_X = "Shadow X offset", SHADOW_Y = "Shadow Y offset",
  SHADOW_OFFSET_TIP = "How far the shadow sits from the text, -20 to 20.",
  GLOW = "Glow",
  GLOW_ON = "Glow behind the text",
  GLOW_ON_TIP = "Draw a soft glow behind the text, in addition to its outline and shadow.",
  GLOW_CUSTOM = "Glow color",
  GLOW_CUSTOM_TIP = "Draw the glow in the color of the swatch below. Off, the glow takes each word's kind color.",
  GLOW_COLOR = "Color", GLOW_COLOR_TIP = "The glow's own color, drawn while Glow color is on.",
  GLOW_CLASS = "Use class color",
  GLOW_CLASS_TIP = "Draw the glow in your class color instead of the swatch or the kind color.",
  GLOW_SKIN = "Use the skin's color",
  GLOW_SKIN_TIP = "Draw the glow in your skin's glow color. Use class color, when on, wins.",
  GLOW_INTENSITY = "Intensity", GLOW_INTENSITY_TIP = "How strongly the glow shows, 5 to 100%.",
  GLOW_THICKNESS = "Thickness (px)", GLOW_THICKNESS_TIP = "How far the glow reaches out from the text, 1 to 6 pixels.",
  GLOW_X = "X offset", GLOW_X_TIP = "Nudge the glow off the text, sideways, in pixels.",
  GLOW_Y = "Y offset", GLOW_Y_TIP = "Nudge the glow off the text, up or down, in pixels.",
  ANIM = "Animation", ANIM_TIP = "How a call-out arrives on screen.",
  ANIM_SLAM = "Slam", ANIM_PULSE = "Pulse", ANIM_GLOW = "Glow", ANIM_BLINK = "Blink",
  ANIM_SHAKE = "Shake", ANIM_NONE = "None",
  HOLD = "Hold (seconds)", HOLD_TIP = "How long a call-out stays before it fades, 0.2 to 10 seconds.",
  VOICE = "Voice",
  VOICE_TIP = "A bundled voice, the game's text to speech (the voices your system has installed), or off.",
  TTS_VOICE = "Text to speech voice", TTS_VOICE_TIP = "Which of the game's voices speaks.",
  TTS_VOICE_DEFAULT = "Default (%s)",
  TTS_RATE = "Speech rate", TTS_RATE_TIP = "How fast text to speech speaks, -10 to 10.",
  TTS_VOLUME = "Speech volume", TTS_VOLUME_TIP = "How loud text to speech speaks, 0 to 100.",
  CHANNEL = "Sound channel", CHANNEL_TIP = "The game's volume slider the voice follows.",
  CHANNEL_MASTER = "Master", CHANNEL_SFX = "Sound effects", CHANNEL_DIALOG = "Dialog",
  SPEAK_FROM = "Speak numbers from",
  SPEAK_FROM_TIP = "Countdown numbers above this are shown but not spoken, 1 to 20.",
  COLORS = "Colors",
  KIND_NUMBER = "Numbers", KIND_INFO = "Information", KIND_GO = "Go", KIND_STOP = "Stop",
  KIND_WARN = "Warnings", KIND_ERROR = "Errors",
  KIND_TIP = "The color of every call-out of this kind.",
  STOCK_TEXTS = "Stock texts",
  TEXT_TIP = "Your own words for %s. Empty shows %s.",
  MUTE = "Mute %s", MUTE_TIP = "%s shows without its voice.",
}

local PREVIEW_MAX = 64            -- the preview's text is at most this tall
local PREVIEW_COUNTDOWN = 5       -- Test countdown's first number
local SAMPLE = { { "5", "number" }, { "GO", "go" }, { "STOP", "stop" } }
local KIND_WORD = { number = "KIND_NUMBER", info = "KIND_INFO", go = "KIND_GO", stop = "KIND_STOP",
  warn = "KIND_WARN", error = "KIND_ERROR" }
lib.SETTINGS_TABS = { "look", "sound", "texts" }
local TAB_WORD = { look = "TAB_LOOK", sound = "TAB_SOUND", texts = "TAB_TEXTS" }
-- Minor 4: the one tab's side tabs, in order, and the Play list's countdown entry (a value no stock
-- key can take: those are upper case) with the number it counts down from.
lib.SETTINGS_SIDE_TABS = { "look", "sound" }
lib.PLAY_COUNTDOWN = "countdown10"
local PLAY_COUNTDOWN_FROM = 10
local LAYOUTS = { side = true }

-- The plain build's line pitch and column.
local PLAIN_LINE, PLAIN_LABEL_W, PLAIN_CONTROL_W, PLAIN_PAD = 26, 200, 160, 8

-- ── small readers ────────────────────────────────────────────────────────────────────────────

local function word(L, key)
  local v = type(L) == "table" and rawget(L, key)
  if type(v) == "string" then return v end
  return lib.SETTINGS_STRINGS[key]
end

local function resolve(major) return LibStub and LibStub(major, true) end

local function hex(r, g, b)
  local function c(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end
  return ("%02x%02x%02x"):format(c(r), c(g), c(b))
end

-- A color for a path-less swatch: both shapes in one table, so the host's colorDecode reads it
-- whichever it expects (named keys, the library's default, or an array).
local function bothShapes(r, g, b) return { r, g, b, 1, r = r, g = g, b = b, a = 1 } end

local function fromEither(c)
  if type(c) ~= "table" then return nil end
  local r, g, b = c.r or c[1], c.g or c[2], c.b or c[3]
  if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
  return r, g, b
end

-- ── the choices ──────────────────────────────────────────────────────────────────────────────

local function listOf(L, pairs_)
  local out = {}
  for i, p in ipairs(pairs_) do out[i] = { value = p[1], text = word(L, p[2]) } end
  return out
end

local function outlineValues(L)
  return listOf(L, { { "NONE", "OUTLINE_NONE" }, { "OUTLINE", "OUTLINE_OUTLINE" },
    { "THICKOUTLINE", "OUTLINE_THICK" }, { "MONOCHROME", "OUTLINE_MONO" } })
end

local function animValues(L)
  return listOf(L, { { "slam", "ANIM_SLAM" }, { "pulse", "ANIM_PULSE" }, { "glow", "ANIM_GLOW" },
    { "blink", "ANIM_BLINK" }, { "shake", "ANIM_SHAKE" }, { "none", "ANIM_NONE" } })
end

local function channelValues(L)
  return listOf(L, { { "Master", "CHANNEL_MASTER" }, { "SFX", "CHANNEL_SFX" }, { "Dialog", "CHANNEL_DIALOG" } })
end

-- The call-out's display faces, in the order the font row offers them after the skin's and the
-- game's: the owner's choice of 2026-11-13 (Orbitron, also planned, does not ship). Each is a
-- LibKa0s-Media-1.0 key and its LSM name. From minor 5 the default is Oxanium SemiBold (Callout
-- minor 4) and Oxanium Bold, the default to then, follows it.
lib.FONT_FACES = { lib.FONT_DEFAULT, "Ka0s Oxanium Bold", "Ka0s Bebas Neue", "Ka0s Russo One" }

--- Every face LibSharedMedia lists (or, without it, every LibKa0s-Media-1.0 face), sorted, as a list
--- and a set.
local function listedFaces()
  local names, seen = {}, {}
  local function add(n)
    if type(n) == "string" and not seen[n] then seen[n] = true; names[#names + 1] = n end
  end
  local LSM = resolve("LibSharedMedia-3.0")
  if LSM and type(LSM.List) == "function" then
    for _, n in ipairs(LSM:List("font") or {}) do add(n) end
  end
  local Media = resolve("LibKa0s-Media-1.0")
  if #names == 0 and Media and type(Media.FONTS) == "table" then
    for n in pairs(Media.FONTS) do add(n) end
  end
  table.sort(names)
  return names, seen
end

--- Every face the font row offers, in order: the skin's and the game's first, then `FONT_FACES`
--- (the default always, the others when they are listed: by LibSharedMedia when it lists any face,
--- else by LibKa0s-Media-1.0's `FONTS`), then every other listed face, sorted, as `{ value, text }`.
--- A face the Media copy ships but LibSharedMedia, present, does not list is not offered: Media's
--- RegisterLSM refused it for the client's locale (its langmask), and drawn from the raw file it
--- would render the player's text as boxes.
local function fontChoices()
  local names, seen = listedFaces()
  local out = { { value = lib.FONT_SKIN, text = lib.FONT_SKIN }, { value = lib.FONT_GAME, text = lib.FONT_GAME } }
  local taken = { [lib.FONT_SKIN] = true, [lib.FONT_GAME] = true }
  for _, n in ipairs(lib.FONT_FACES) do
    if n == lib.FONT_DEFAULT or seen[n] then
      taken[n] = true
      out[#out + 1] = { value = n, text = n }
    end
  end
  for _, n in ipairs(names) do
    if not taken[n] then out[#out + 1] = { value = n, text = n } end
  end
  return out
end

--- The Play list: "Countdown 10 to 1" first (minor 4), then every stock text in the major's order.
local function playValues(L)
  local out = { { value = lib.PLAY_COUNTDOWN, text = word(L, "PLAY_COUNTDOWN") } }
  for _, key in ipairs(lib.STOCK_ORDER) do out[#out + 1] = { value = key, text = lib.STOCK[key].text } end
  return out
end

local function playable(k) return k == lib.PLAY_COUNTDOWN or lib.STOCK[k] ~= nil end

-- ── the rows ─────────────────────────────────────────────────────────────────────────────────
--
-- Every row is built by one binder, `B = { inst, prefix }`, in one of two shapes:
--
-- PATH-LESS (`B.prefix` nil; SettingsRows and the plain build): Options' W15 arm, read and written
-- through the row's own `get` / `set`, which call the instance's Get / Set. On the host's write route
-- (the descriptor's `path` and `set`) those writes still reach the host's seam, through the instance.
--
-- SCHEMA ROWS (`B.prefix` the host's prefix; SchemaRows, and the Options build on the host's route,
-- minor 3): `path = prefix .. key`, `default` as the instance stores it, `validate` the instance's
-- own rule, and `onChange` the instance's Apply. The host registers them in its own schema, so
-- architecture-§5's helper writes every one of them and its slash get / set / reset reaches each.
-- `tab` is the tab's key; `group` its label, so RenderRows draws a heading per tab when all three
-- are drawn.

--- Bind `t` to setting `key`. `less` overrides the path-less row's get / set; `more` adds fields
--- to a schema row (a `normalize`, a `values` function, a color row's `get`). A schema row's `get`
--- comes with no `set`: Schema.Get answers through it, and a write still stores through the host's
--- seam (prepareWrite stores a row with no `set`), so it must answer the stored value's equal at the
--- default, or the host's reset count reads the row as changed.
local function bind(B, key, t, less, more)
  local inst = B.inst
  t.key = key
  if not B.prefix then
    t.get = less and less.get or function() return inst:Get(key) end
    t.set = less and less.set or function(v) inst:Set(key, v) end
    return t
  end
  t.path = B.prefix .. key
  t.default = lib.__defaultFor(inst, key)
  t.validate = function(v) return lib.__validFor(inst, key, v) end
  t.onChange = function() inst:Apply() end
  for k, v in pairs(more or {}) do t[k] = v end
  return t
end

local function row(list, tab, group, subgroup, t)
  t.tab, t.group, t.subgroup = tab, group, subgroup
  list[#list + 1] = t
  return t
end

local function slider(B, label, tip, key, lo, hi, step)
  return bind(B, key, { type = "number", label = label, tooltip = tip, min = lo, max = hi, step = step })
end

local function choice(B, label, tip, key, values)
  return bind(B, key, { type = "string", label = label, tooltip = tip, values = values })
end

local function check(B, L, key, w)
  return bind(B, key, { type = "bool", label = word(L, w), tooltip = word(L, w .. "_TIP") })
end

--- The glow's rows (minor 4, plan row L15) under their "Glow" subgroup, in AuraMaster's two columns:
---
---   [Glow behind the text]  [Glow color]
---   [Color]                 [Use class color]
---   [Use the skin's color]
---   [Intensity]             [Thickness (px)]
---   [X offset]              [Y offset]
---
--- The swatch and its class-color companion are options-ui-§17's pair, adjacent and never dimmed;
--- every other row but the toggle dims while the glow is off.
local function glowRows(B, L, out, g)
  local inst, sub = B.inst, word(L, "GLOW")
  local off = function() return not inst:Get("glow") end
  local function add(t, startsLine, dims)
    t.startsLine, t.disabledIf = startsLine or nil, dims and off or nil
    return row(out, "look", g, sub, t)
  end
  add(check(B, L, "glow", "GLOW_ON"), true)
  add(check(B, L, "glowCustom", "GLOW_CUSTOM"), false, true)
  add(bind(B, "glowColor", { type = "color", label = word(L, "GLOW_COLOR"), tooltip = word(L, "GLOW_COLOR_TIP"),
    hasAlpha = false, classColorSource = "player" }, {
      get = function() return bothShapes(fromEither(inst:Get("glowColor"))) end,
      set = function(c) inst:Set("glowColor", c) end },
    { get = function() return lib.__glowColorFor(inst) end }), true)
  local class = add(check(B, L, "useClassColorGlow", "GLOW_CLASS"))
  class.classColorSource = "player"
  add(check(B, L, "glowColorFromSkin", "GLOW_SKIN"), true, true)
  local pct = add(slider(B, word(L, "GLOW_INTENSITY"), word(L, "GLOW_INTENSITY_TIP"), "glowIntensity", 0.05, 1, 0.05),
    true, true)
  pct.isPercent = true
  add(slider(B, word(L, "GLOW_THICKNESS"), word(L, "GLOW_THICKNESS_TIP"), "glowThickness", 1, 6, 1), false, true)
  add(slider(B, word(L, "GLOW_X"), word(L, "GLOW_X_TIP"), "glowX", -20, 20, 1), true, true)
  add(slider(B, word(L, "GLOW_Y"), word(L, "GLOW_Y_TIP"), "glowY", -20, 20, 1), false, true)
end

local function lookRows(B, L, out)
  local inst, g = B.inst, word(L, "TAB_LOOK")
  row(out, "look", g, nil, bind(B, "font", { type = "string", label = word(L, "FONT"), tooltip = word(L, "FONT_TIP"),
    dialogControl = "Ka0sMedia_Font", values = fontChoices, startsLine = true }))
  row(out, "look", g, nil, slider(B, word(L, "SIZE"), word(L, "SIZE_TIP"), "size", lib.SIZE_MIN, lib.SIZE_MAX, 1))
  row(out, "look", g, nil, choice(B, word(L, "OUTLINE"), word(L, "OUTLINE_TIP"), "outline", outlineValues(L)))
  row(out, "look", g, nil, bind(B, "shadow", { type = "bool", label = word(L, "SHADOW"), tooltip = word(L, "SHADOW_TIP"),
    startsLine = true }))
  local noShadow = function() return not inst:Get("shadow") end
  local x = row(out, "look", g, nil, slider(B, word(L, "SHADOW_X"), word(L, "SHADOW_OFFSET_TIP"), "shadowX", -20, 20, 1))
  local y = row(out, "look", g, nil, slider(B, word(L, "SHADOW_Y"), word(L, "SHADOW_OFFSET_TIP"), "shadowY", -20, 20, 1))
  x.disabledIf, y.disabledIf, x.startsLine = noShadow, noShadow, true
  local anim = row(out, "look", g, nil, choice(B, word(L, "ANIM"), word(L, "ANIM_TIP"), "anim", animValues(L)))
  anim.startsLine = true
  row(out, "look", g, nil, slider(B, word(L, "HOLD"), word(L, "HOLD_TIP"), "hold", 0.2, 10, 0.1))
  glowRows(B, L, out, g)
end

--- The voice choices: the packs the host ships (`d.packs`), then text to speech and off.
local function voiceValues(inst)
  local out = {}
  for i, v in ipairs(inst:Voices()) do out[i] = { value = v.key, text = v.name } end
  return out
end

--- The client's text to speech voices as choices; empty without one.
local function ttsValues(inst)
  local out = {}
  for i, v in ipairs(inst:TtsVoices()) do out[i] = { value = v.voiceID, text = v.name } end
  return out
end

--- The schema row's choices: the stored default, `false` (the client's first voice), leads as
--- "Default (<first voice>)", so the dropdown names the voice spoken rather than showing blank. A
--- path-less row maps `false` to the first voice through its own `get` instead; a schema row has no
--- `get` here, since one answering the first voice's id would read as changed at the default.
local function ttsSchemaValues(inst, L)
  local out = ttsValues(inst)
  if out[1] then table.insert(out, 1, { value = false, text = word(L, "TTS_VOICE_DEFAULT"):format(out[1].text) }) end
  return out
end

--- The text to speech rows. Path-less (and in the Options build), only on a client that lists a
--- voice; as schema rows (`all`), always, since the settings exist whether or not this client has a
--- voice, with the choices read when they are drawn. Drawn disabled off "tts".
local function ttsRows(B, L, out, g, all)
  local inst = B.inst
  local tts = inst:TtsVoices()
  if #tts == 0 and not all then return end
  local notTts = function() return inst:Get("voice") ~= lib.TTS end
  local pickGet = function()
    local want = inst:Get("ttsVoice")
    for _, v in ipairs(tts) do if v.voiceID == want then return want end end
    return tts[1] and tts[1].voiceID
  end
  local values = B.prefix and function() return ttsSchemaValues(inst, L) end or ttsValues(inst)
  row(out, "sound", g, nil, bind(B, "ttsVoice", { type = "number", label = word(L, "TTS_VOICE"),
    tooltip = word(L, "TTS_VOICE_TIP"), values = values, startsLine = true, disabledIf = notTts },
    { get = pickGet }))
  local rate = row(out, "sound", g, nil, slider(B, word(L, "TTS_RATE"), word(L, "TTS_RATE_TIP"), "ttsRate", -10, 10, 1))
  local vol = row(out, "sound", g, nil, slider(B, word(L, "TTS_VOLUME"), word(L, "TTS_VOLUME_TIP"), "ttsVolume", 0, 100, 1))
  rate.disabledIf, vol.disabledIf, rate.startsLine = notTts, notTts, true
end

local function soundRows(B, L, out, all)
  local inst, g = B.inst, word(L, "TAB_SOUND")
  local voices = B.prefix and function() return voiceValues(inst) end or voiceValues(inst)
  local voice = row(out, "sound", g, nil, choice(B, word(L, "VOICE"), word(L, "VOICE_TIP"), "voice", voices))
  voice.startsLine = true
  row(out, "sound", g, nil, choice(B, word(L, "CHANNEL"), word(L, "CHANNEL_TIP"), "channel", channelValues(L)))
  local from = row(out, "sound", g, nil, slider(B, word(L, "SPEAK_FROM"), word(L, "SPEAK_FROM_TIP"),
    "speakFrom", 1, lib.MAX_FROM, 1))
  from.startsLine = true
  ttsRows(B, L, out, g, all)
end

local function trim(v) return type(v) == "string" and v:match("^%s*(.-)%s*$") or "" end

--- The six colors under their "Colors" subgroup, on tab `tab` (Texts in the three-tab shape, Look in
--- the one tab's) with that tab's group label `g`.
local function colorRows(B, L, out, g, tab)
  local inst, colors = B.inst, word(L, "COLORS")
  for i, kind in ipairs(lib.KINDS) do
    row(out, tab, g, colors, bind(B, "colors." .. kind, { type = "color", label = word(L, KIND_WORD[kind]),
      tooltip = word(L, "KIND_TIP"), hasAlpha = false, startsLine = i == 1 }, {
        get = function() return bothShapes(inst:GetColor(kind)) end,
        set = function(c)
          local r, gg, b = fromEither(c)
          if r then inst:SetColor(kind, r, gg, b) end
        end }, { get = function() return lib.__colorFor(inst, kind) end }))
  end
end

local function textsRows(B, L, out, withText)
  local inst, g = B.inst, word(L, "TAB_TEXTS")
  colorRows(B, L, out, g, "texts")
  local stock = word(L, "STOCK_TEXTS")
  for _, key in ipairs(lib.STOCK_ORDER) do
    local shown, textKey, muteKey = lib.STOCK[key].text, "texts." .. key, "muted." .. key
    if withText then
      row(out, "texts", g, stock, bind(B, textKey, { type = "string", dialogControl = "EditBox", label = shown,
        startsLine = true, tooltip = word(L, "TEXT_TIP"):format(shown, shown) }, {
          set = function(v)
            local text = trim(v)
            inst:Set(textKey, text ~= "" and text or nil)
          end }, { normalize = trim }))
    end
    row(out, "texts", g, stock, bind(B, muteKey, { type = "bool", label = word(L, "MUTE"):format(shown),
      tooltip = word(L, "MUTE_TIP"):format(shown), startsLine = not withText }, {
        set = function(v) inst:Set(muteKey, v and true or nil) end }))
  end
end

--- The one tab's Look (minor 4): the face rows, then the six colors under "Colors", all on "look".
local function lookTab(B, L, out)
  lookRows(B, L, out)
  colorRows(B, L, out, word(L, "TAB_LOOK"), "look")
end

--- Tab `tab`'s rows (nil: every tab), into `out`. `noTexts` is the one tab's shape (minor 4): Look
--- carries the colors, and there is no Texts tab. `all` and `withText` as soundRows and textsRows.
local function tabRows(B, L, out, tab, noTexts, all, withText)
  if tab == nil or tab == "look" then
    if noTexts then lookTab(B, L, out) else lookRows(B, L, out) end
  end
  if tab == nil or tab == "sound" then soundRows(B, L, out, all) end
  if not noTexts and (tab == nil or tab == "texts") then textsRows(B, L, out, withText) end
  return out
end

--- The section's rows: path-less schema rows bound to this instance, Look, Sound then Texts, or
--- one tab's (`opts.tab`). `opts.L` overrides the words; `opts.plain` leaves the text boxes out;
--- `opts.texts = false` (minor 4) is the one tab's shape: the colors in Look, no Texts rows.
function METHODS:SettingsRows(opts)
  opts = type(opts) == "table" and opts or {}
  return tabRows({ inst = self }, opts.L, {}, opts.tab, opts.texts == false, false, not opts.plain)
end

-- ── the preview ──────────────────────────────────────────────────────────────────────────────

local VIEW = setmetatable({}, { __mode = "k" })   -- instance -> its session state (the play pick)

local function session(inst)
  local v = VIEW[inst]
  if not v then v = { play = "GO", side = "look" }; VIEW[inst] = v end
  return v
end

--- The sample line, each word in its kind's color.
local function sampleText(inst)
  local parts = {}
  for i, s in ipairs(SAMPLE) do
    local text = s[1] == "GO" and lib.STOCK.GO.text or s[1] == "STOP" and lib.STOCK.STOP.text or s[1]
    parts[i] = "|cff" .. hex(inst:GetColor(s[2])) .. text .. "|r"
  end
  return table.concat(parts, "  ")
end

--- Paint a FontString (or an AceGUI Label, through its SetFont) in the chosen look.
local function paintPreview(inst, target, fs)
  local look = inst:Look()
  local size = math.min(look.size, PREVIEW_MAX)
  if type(target.SetFont) == "function" then target:SetFont(look.font, size, look.flags) end
  if type(target.SetText) == "function" then target:SetText(sampleText(inst)) end
  if not (fs and type(fs.SetShadowOffset) == "function") then return end
  if look.shadow then
    fs:SetShadowOffset(look.shadowX, look.shadowY)
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
  else
    fs:SetShadowOffset(0, 0)
  end
end

--- Show `what` (a stock key, a number or a custom spec; READY by default) silently, as a preview
--- of the look on the real call-out.
function METHODS:Preview(what)
  return self:Show(what or "READY", { voice = false })
end

--- Count the real call-out down from `from` (5) to GO!.
function METHODS:TestCountdown(from)
  local n = tonumber(from) or PREVIEW_COUNTDOWN
  return self:Countdown{ endsAt = GetTime() + n, from = n }
end

--- Play: the picked stock text, shown with its voice; or "Countdown 10 to 1" (minor 4), the real
--- call-out counting down from 10 to 1 with no finish, each number spoken as `speakFrom` allows.
local function playPicked(inst)
  local pick = session(inst).play
  if pick == lib.PLAY_COUNTDOWN then
    return inst:Countdown{ endsAt = GetTime() + PLAY_COUNTDOWN_FROM, from = PLAY_COUNTDOWN_FROM, finish = false }
  end
  return inst:Show(pick)
end

-- The preview block's own rows: the text Play shows, and the unlock toggle. Session state only:
-- `sessionOnly`, each storing through its own get / set, never in the host's profile. As schema rows
-- they carry a path too (`prefix .. "play"`, `prefix .. "unlocked"`), so the host's Options build
-- reaches them through its seam like every other row, and a reset puts back GO and the lock.
local function previewRows(B, L)
  local inst = B.inst
  local v = session(inst)
  local play = { type = "string", label = word(L, "PLAY_KEY"), tooltip = word(L, "PLAY_KEY_TIP"), values = playValues(L),
    key = "play", startsLine = true, sessionOnly = true,
    get = function() return v.play end, set = function(k) if playable(k) then v.play = k end end }
  local unlock = { type = "bool", label = word(L, "UNLOCK"), tooltip = word(L, "UNLOCK_TIP"), key = "unlocked",
    sessionOnly = true,
    get = function() return inst:Locked() == false end, set = function(on) inst:SetLocked(not on) end }
  if B.prefix then
    local g = word(L, "PREVIEW")
    play.path, play.default, play.group, play.preview = B.prefix .. "play", "GO", g, true
    play.validate = playable
    unlock.path, unlock.default, unlock.group, unlock.preview = B.prefix .. "unlocked", false, g, true
    unlock.validate = function(on) return type(on) == "boolean" end
  end
  return { play, unlock }
end

--- `p` as a prefix ending in one dot, or nil.
local function asPrefix(p)
  if type(p) ~= "string" or p == "" then return nil end
  return p:sub(-1) == "." and p or (p .. ".")
end

--- The call-out's settings as schema rows (architecture-§5), for the host to register in its own
--- schema under `prefix` (`"callout."`; the descriptor's `path` when nil): one row per setting a
--- control chooses, each `path = prefix .. key` with its `type`, `default` (what the instance reads
--- with nothing stored: `DEFAULTS`' value, a color in the host's shape), `validate`, `onChange` (the
--- instance's Apply), `min` / `max` / `step` or `values`, `label`, `tooltip`, `group` and `tab`; then
--- the two session rows. `opts.L` overrides the words, `opts.page` sets every row's `page`.
--- `opts.texts = false` (minor 4) leaves the stock texts' rows out (`texts.<KEY>` and `muted.<KEY>`,
--- the words the host sets itself) and puts the colors on `tab = "look"`: the one tab's shape. The
--- second answer is the named non-setting state the host owns beside them: `{ prefix .. "point" }`,
--- the drag's saved position, which no control sets (a host lists it in its schema's
--- `writeThrough`, or writes it in its own `d.set`, and names it either way).
function METHODS:SchemaRows(prefix, opts)
  opts = type(opts) == "table" and opts or {}
  prefix = asPrefix(prefix) or lib.__prefixOf(self)
  if not prefix then error(lib.MAJOR .. ": SchemaRows(prefix): a prefix (or the descriptor's path) is required", 2) end
  local B, L = { inst = self, prefix = prefix }, opts.L
  local out = tabRows(B, L, {}, nil, opts.texts == false, true, true)
  for _, r in ipairs(previewRows(B, L)) do out[#out + 1] = r end
  if opts.page ~= nil then
    for _, r in ipairs(out) do r.page = opts.page end
  end
  return out, { prefix .. "point" }
end

-- ── the Options build ────────────────────────────────────────────────────────────────────────

--- The preview block: the sample line (not in the one tab's layout, minor 5: `noLine`), then the
--- two button pairs and the block's own rows.
local function optionsPreview(B, O, ctx, L, view, noLine)
  local inst = B.inst
  local label = not noLine and O.TextRow(ctx, sampleText(inst), { justify = "CENTER" }) or nil
  view.preview = label
  if label then
    local function repaint() paintPreview(inst, label, label.label) end
    repaint()
    if type(ctx.refreshers) == "table" then ctx.refreshers[#ctx.refreshers + 1] = repaint end
    view.repaint = repaint
  end
  O.InlineButtonPair(ctx,
    { text = word(L, "TEST_COUNTDOWN"), tooltip = word(L, "TEST_COUNTDOWN_TIP"),
      onClick = function() inst:TestCountdown() end },
    { text = word(L, "PLAY"), tooltip = word(L, "PLAY_TIP"), onClick = function() playPicked(inst) end })
  O.RenderRows(ctx, previewRows(B, L), nil, nil, { noHeadings = true })
  O.InlineButtonPair(ctx, { text = word(L, "RESET_POSITION"), tooltip = word(L, "RESET_POSITION_TIP"),
    onClick = function() inst:ResetPosition() end })
end

--- The side tabs' entries, Look then Sound, in the host's words.
local function sideEntries(L)
  local out = {}
  for i, tab in ipairs(lib.SETTINGS_SIDE_TABS) do
    out[i] = { key = tab, label = word(L, TAB_WORD[tab]), tooltip = word(L, TAB_WORD[tab] .. "_TIP") }
  end
  return out
end

--- The one tab (minor 4): a "Preview" heading over the preview block, then the Options instance's
--- side tabs, Look (the colors in it) and Sound, the selected one's rows drawn beside the list. The
--- selection is session state, never saved. An Options copy with no O.SideTabs (before OptionsNav
--- minor 7) draws Look and Sound one under the other, each under its heading, instead. From minor 5
--- the block draws no sample line (`view.preview` and `view.repaint` are nil): the heading, the
--- buttons and the rows under it stay.
local function buildSide(B, O, ctx, L, view)
  local inst = B.inst
  if type(O.Section) == "function" then O.Section(ctx, word(L, "PREVIEW")) end
  optionsPreview(B, O, ctx, L, view, true)
  view.layout = "side"
  if type(O.SideTabs) ~= "function" then
    view.rows = tabRows(B, L, {}, nil, true, false, true)
    O.RenderRows(ctx, view.rows)
    return view
  end
  local v = session(inst)
  view.sideTabs = O.SideTabs(ctx, { entries = sideEntries(L), value = v.side,
    onSelect = function(key) v.side = key end,
    render = function(c, key)
      view.side = key
      view.rows = tabRows(B, L, {}, key, true, false, true)
      O.RenderRows(c, view.rows, nil, nil, { noHeadings = true })
    end })
  return view
end

-- What the Options build calls on the host's instance, each checked before anything is drawn.
local OPTIONS_MEMBERS = { "EnsureScroll", "TextRow", "InlineButtonPair", "RenderRows" }

local function buildOptions(inst, ctx, opts)
  local O, L = opts.options, opts.L
  local view = { kind = "options" }
  for _, member in ipairs(OPTIONS_MEMBERS) do
    if type(O[member]) ~= "function" then return nil end   -- an instance without it builds nothing
  end
  if not O.EnsureScroll(ctx) then return nil end
  -- On the host's route (`opts.prefix`, else the descriptor's `path`) every row carries its path,
  -- and the Options instance reads and writes it through its own descriptor: the host's seam, its
  -- reactions and its announce. The rows are the ones SchemaRows answers, which the host registered.
  local B = { inst = inst, prefix = asPrefix(opts.prefix) or lib.__prefixOf(inst) }
  view.prefix = B.prefix
  if opts.layout == "side" then return buildSide(B, O, ctx, L, view) end
  optionsPreview(B, O, ctx, L, view)
  local tab = opts.tab
  view.rows = tabRows(B, L, {}, tab, false, false, true)
  O.RenderRows(ctx, view.rows, nil, nil, { noHeadings = tab ~= nil })
  return view
end

--- The three tab entries for the host's `RenderTabbedSchema` (`opts.tabs`): `{ key, label,
--- tooltip, render }` each, keyed `opts.keyPrefix .. "look"` (and sound, texts; the prefix is
--- "callout." by default), each drawing its tab through BuildSettings. `opts.options` is required.
function METHODS:SettingsTabs(opts)
  opts = type(opts) == "table" and opts or {}
  local prefix = type(opts.keyPrefix) == "string" and opts.keyPrefix or "callout."
  local out = {}
  for i, tab in ipairs(lib.SETTINGS_TABS) do
    out[i] = { key = prefix .. tab, label = word(opts.L, TAB_WORD[tab]),
      tooltip = word(opts.L, TAB_WORD[tab] .. "_TIP"), before = opts.before,
      render = function(ctx)
        self:BuildSettings(ctx, { options = opts.options, tab = tab, L = opts.L, prefix = opts.prefix })
      end }
  end
  return out
end

--- The section as ONE host tab (minor 4), for the host's `RenderTabbedSchema` (`opts.tabs`) or a
--- host-drawn strip: `{ key, label, tooltip, before, render }`, keyed `opts.key` ("callout" by
--- default), labeled "Callout", drawing `BuildSettings(ctx, { options, layout = "side", L, prefix })`:
--- the Preview block over the Look and Sound side tabs. `opts.options` is required. The documented
--- shape for a host on the route, which registers `SchemaRows(prefix, { texts = false })` beside it.
function METHODS:SettingsTab(opts)
  opts = type(opts) == "table" and opts or {}
  return { key = type(opts.key) == "string" and opts.key or "callout", label = word(opts.L, "TAB_CALLOUT"),
    tooltip = word(opts.L, "TAB_CALLOUT_TIP"), before = opts.before,
    render = function(ctx)
      self:BuildSettings(ctx, { options = opts.options, layout = "side", L = opts.L, prefix = opts.prefix })
    end }
end

-- ── the plain build ──────────────────────────────────────────────────────────────────────────

local function plainLabel(parent, text, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PLAIN_PAD, y)
  fs:SetWidth(PLAIN_LABEL_W)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return fs
end

local function plainButton(parent, text, x, y, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, PLAIN_LINE - 4)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function valueText(r)
  local v = r.get()
  if type(r.values) == "table" then
    for _, item in ipairs(r.values) do if item.value == v then return item.text end end
  end
  if r.isPercent then return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
  if r.type == "number" then return (r.step or 1) < 1 and ("%.1f"):format(v) or tostring(v) end
  return tostring(v)
end

local function cycle(r, dir)
  local list, v = r.values, r.get()
  local at = 1
  for i, item in ipairs(list) do if item.value == v then at = i end end
  at = (at - 1 + dir) % #list + 1
  r.set(list[at].value)
end

local function nudge(r, dir)
  local v = r.get() + dir * (r.step or 1)
  v = math.max(r.min, math.min(r.max, v))
  r.set(math.floor(v / (r.step or 1) + 0.5) * (r.step or 1))
end

local PLAIN = {}

PLAIN.bool = function(parent, r, y, refresh)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", PLAIN_PAD + PLAIN_LABEL_W, y + 2)
  cb:SetScript("OnClick", function(self) r.set(self:GetChecked() and true or false); refresh() end)
  return cb, function() cb:SetChecked(r.get() and true or false) end
end

PLAIN.number = function(parent, r, y, refresh)
  if type(r.values) == "table" then return PLAIN.string(parent, r, y, refresh) end
  local x = PLAIN_PAD + PLAIN_LABEL_W
  local minus = plainButton(parent, "-", x, y, PLAIN_LINE, function() nudge(r, -1); refresh() end)
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT", parent, "TOPLEFT", x + PLAIN_LINE + 4, y - 4)
  local plus = plainButton(parent, "+", x + PLAIN_LINE + 60, y, PLAIN_LINE, function() nudge(r, 1); refresh() end)
  return { minus = minus, text = text, plus = plus }, function() text:SetText(valueText(r)) end
end

PLAIN.string = function(parent, r, y, refresh)
  if type(r.values) == "function" then r = setmetatable({ values = r.values() }, { __index = r }) end
  local b = plainButton(parent, "", PLAIN_PAD + PLAIN_LABEL_W, y, PLAIN_CONTROL_W, function() cycle(r, 1); refresh() end)
  return b, function() b:SetText(valueText(r)) end
end

PLAIN.color = function(parent, r, y, refresh)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(PLAIN_LINE - 6, PLAIN_LINE - 6)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", PLAIN_PAD + PLAIN_LABEL_W, y)
  local tex = b:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints(b)
  if tex.SetColorTexture then tex:SetColorTexture(1, 1, 1, 1) end
  b:SetScript("OnClick", function()
    local cpf = ColorPickerFrame
    if not (cpf and type(cpf.SetupColorPickerAndShow) == "function") then return end
    local r0, g0, b0 = fromEither(r.get())
    local function apply()
      r.set({ cpf:GetColorRGB() })
      refresh()
    end
    cpf:SetupColorPickerAndShow({ r = r0, g = g0, b = b0, hasOpacity = false, swatchFunc = apply,
      cancelFunc = function() r.set({ r0, g0, b0 }); refresh() end })
  end)
  return b, function()
    local cr, cg, cb = fromEither(r.get())
    if tex.SetVertexColor then tex:SetVertexColor(cr, cg, cb, 1) end
  end
end

local function plainHeading(parent, text, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PLAIN_PAD, y)
  fs:SetText(text)
  return fs
end

local function plainPreview(inst, parent, L, view, y, noLine)
  if not noLine then   -- the one tab's layout draws no sample line (minor 5)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PLAIN_PAD, y)
    fs:SetHeight(PREVIEW_MAX + PLAIN_PAD)
    view.preview = fs
    y = y - PREVIEW_MAX - PLAIN_PAD * 2
  end
  view.testButton = plainButton(parent, word(L, "TEST_COUNTDOWN"), PLAIN_PAD, y, PLAIN_CONTROL_W,
    function() inst:TestCountdown() end)
  view.playButton = plainButton(parent, word(L, "PLAY"), PLAIN_PAD + PLAIN_CONTROL_W + PLAIN_PAD, y,
    PLAIN_CONTROL_W, function() playPicked(inst) end)
  view.resetButton = plainButton(parent, word(L, "RESET_POSITION"), PLAIN_PAD + (PLAIN_CONTROL_W + PLAIN_PAD) * 2,
    y, PLAIN_CONTROL_W, function() inst:ResetPosition() end)
  return y - PLAIN_LINE
end

local function plainRow(parent, r, y, view, refresh)
  local make = PLAIN[r.type]
  if not make then return y end
  plainLabel(parent, r.label, y - 4)
  local control, sync = make(parent, r, y, refresh)
  view.controls[#view.controls + 1] = { row = r, control = control, sync = sync }
  return y - PLAIN_LINE
end

local function buildPlain(inst, parent, opts)
  if type(parent) ~= "table" or type(parent.CreateFontString) ~= "function" then return nil end
  local L = opts.L
  local view = { kind = "plain", controls = {} }
  local function refresh()
    if view.preview then paintPreview(inst, view.preview, view.preview) end
    for _, c in ipairs(view.controls) do c.sync() end
  end
  view.refresh = refresh
  -- The one tab's layout (minor 4) has no side tabs here: Look (its colors in it) and Sound, each
  -- under its heading, and no stock texts; from minor 5, no sample line either.
  local side = opts.layout == "side"
  local y = plainPreview(inst, parent, L, view, -PLAIN_PAD, side)
  for _, r in ipairs(previewRows({ inst = inst }, L)) do y = plainRow(parent, r, y, view, refresh) end
  local tab = not side and opts.tab or nil
  view.rows = inst:SettingsRows({ tab = tab, L = L, plain = true, texts = not side })
  local heading
  for _, r in ipairs(view.rows) do
    if tab == nil and r.group ~= heading then   -- one tab draws no heading of its own
      heading = r.group
      y = y - PLAIN_PAD
      plainHeading(parent, heading, y)
      y = y - PLAIN_LINE
    end
    y = plainRow(parent, r, y, view, refresh)
  end
  view.height = PLAIN_PAD - y
  refresh()
  return view
end

-- ── the entry point ──────────────────────────────────────────────────────────────────────────

--- Build the settings section into `parent`. With `opts.options` (the host's LibKa0s Options
--- instance) `parent` is a page ctx and the rows are that instance's own; without, `parent` is a
--- frame and the section is plain frames. `opts.tab` ("look", "sound" or "texts") draws one tab;
--- `opts.layout = "side"` (minor 4) draws the one tab instead (`SettingsTab`; `opts.tab` is then
--- not read): a Preview heading and block over the Look and Sound side tabs, or, in the plain
--- build, Look and Sound under their headings, with no stock texts either way.
--- `opts.L` overrides the words. Answers the view (`kind`, `rows`, `preview`; with the side
--- layout `layout`, `side` and `sideTabs`, and no `preview` from minor 5, since that layout draws
--- no sample line; for the plain build `controls`, `refresh` and `height`), or nil when there is
--- nothing to build into, or an unknown tab or layout.
function METHODS:BuildSettings(parent, opts)
  opts = type(opts) == "table" and opts or {}
  if opts.layout ~= nil and not LAYOUTS[opts.layout] then return nil end
  if opts.layout == nil and opts.tab ~= nil and not TAB_WORD[opts.tab] then return nil end
  if type(opts.options) == "table" then
    if type(parent) ~= "table" then return nil end
    return buildOptions(self, parent, opts)
  end
  return buildPlain(self, parent, opts)
end
