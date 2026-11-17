-- LibKa0s-Callout-1.0 — the big center-screen call-out: countdown numbers, stock and custom texts.
--
-- ── WHY THIS EXISTS ──────────────────────────────────────────────────────────────────────────
--
-- Combat Trail's race countdown drew its numbers off a chain of timers that drifted against the race
-- clock it was counting down to, and every other Ka0s addon that wants a "3, 2, 1, GO" or a big
-- "MOVE" would write the same frame, font, animation and voice again. This file is that call-out,
-- once (the owner's decisions of 2026-11-13, docs/superpowers/plans/2026-11-13-callout.md;
-- adoption issue LibKa0s#85).
--
-- ── THE CONTRACT ─────────────────────────────────────────────────────────────────────────────
--
-- `Callout:New(d)` answers one instance. `d.db` (required) is the host's profile table the instance
-- reads and writes its settings into, or a getter answering it (so a profile switch is followed);
-- `Callout.DEFAULTS` is the table a host seeds it from. Everything else in `d` is optional: `name`
-- (the frame's global name), `addon` and `vendorPath` (where the payload sits, for the voice packs
-- and the bundled fonts), `soundsBase` (the folder holding the packs, overriding the one `addon`
-- implies), `skin` (a registered skin owner, for the "Skin font" choice, the drag strip and,
-- from minor 3, the glow's skin color), `label` (the drag strip's text) and `debug` (`debug(tag, msg)`). docs/api/Callout/version-4.5-docs.md
-- is the full contract.
--
-- ── WHERE A WRITE GOES (minor 2) ─────────────────────────────────────────────────────────────
--
-- With `d.path` (the prefix the host registered the call-out's schema rows under, `"callout."`) and
-- `d.set` (the host's single write seam, `NS.SetByPath`), every write the instance makes, a drag's
-- saved point included, is `d.set(d.path .. key, value)`: architecture-§5's helper validates, stores,
-- reacts and announces, and the instance only ever READS `d.db`. Without them the instance writes
-- `d.db` itself, as at minor 1; that route still works and is not conforming for a Ka0s host, whose
-- every setting needs a row and whose every write goes through its helper.
--
-- ── TIMING ───────────────────────────────────────────────────────────────────────────────────
--
-- `Countdown{ endsAt, from, finish, onTick, onDone }`. The number shown is ALWAYS
-- `math.ceil(endsAt - GetTime())`, read in an OnUpdate while the countdown runs, so it flips on the
-- frame the true remaining time crosses the integer, and a host drawing its own clock off the same
-- `endsAt` can never disagree with it. There is no timer chain to drift. The OnUpdate is armed only
-- while a countdown runs or a call-out waits out its hold, on a clock frame of its own with no
-- parent (so hiding the UI does not stop a countdown's onDone), and is cleared the moment neither
-- is true. Animations are AnimationGroups, which the client runs; no Lua runs per frame for them.
--
-- ── SOUND ────────────────────────────────────────────────────────────────────────────────────
--
-- The `voice` setting is a pack key of `Callout.PACKS` (a folder under media/sounds/callout/),
-- "tts" (the client's text to speech, C_VoiceChat.SpeakText with the player's chosen voice from
-- C_VoiceChat.GetTtsVoices) or "off". Both calls are presence-checked at call time, and their
-- signatures are the same on Retail and WoW Forever (Blizzard's generated API documentation, live and
-- forever branches, read 2026-11-13: SpeakText(voiceID, text, rate, volume, overlap)), so nothing
-- here is version-variant and nothing routes through LibKa0s-Compat-1.0. A pack line the consumer
-- pruned away (PlaySoundFile answers false) is silence, reported once per file through `d.debug`.
--
-- ── DEPENDENCIES ─────────────────────────────────────────────────────────────────────────────
--
-- LibStub and LibKa0s-Core-1.0 minor 1 or newer, the gate every module here takes so a partial
-- payload is every module absent. LibKa0s-Media-1.0 (the bundled fonts), LibKa0s-Skin-1.0 (the skin's
-- font), LibKa0s-Widgets-1.0 (the drag strip) and LibSharedMedia-3.0 are each resolved at the call
-- that needs them and optional. No SavedVariables of its own, no secret value passes through it,
-- and nothing here is a protected call, so it works in combat.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

-- Minor 1: the major (plan row L3).
-- Minor 2 (plan row L11, v1.98.0): the host-write route (`d.path` and `d.set`, `d.colorEncode`),
-- the leaf keys `texts.<KEY>`, `muted.<KEY>` and `colors.<kind>` that Get and Set take, and a color
-- read in either shape.
-- Minor 3 (plan row L15, v1.100.0): the glow behind the text as AuraMaster's text glow is: an on/off
-- `glow`, `glowIntensity`, `glowThickness`, `glowX` / `glowY`, and its color (`glowCustom` with
-- `glowColor`, `useClassColorGlow`, `glowColorFromSkin`; off, each word's kind color, as before).
-- A stored "off" / "soft" / "strong" reads as the same look (`GLOW_LEGACY`, `MigrateGlow`), and
-- Set("glow", choice) still takes one, written as those keys. Six more voice packs (plan row L16),
-- the arena announcer the default `voice`.
-- Minor 4 (plan row L17, v1.102.0): new look defaults, the owner's own in-game settings: the face
-- Oxanium SemiBold (`FONT_DEFAULT`), a 1 px shadow up and to the right (`shadowX = 1`,
-- `shadowY = 1`), and a black glow at full intensity, 1 px thick, 1 px right and 1 px down
-- (`glowCustom`, `glowColor = { 0, 0, 0 }`, `glowIntensity = 1`, `glowThickness = 1`, `glowX = 1`,
-- `glowY = -1`). A host that stored its own values reads them as before; `GLOW_LEGACY` is unchanged.
local MAJOR, MINOR = "LibKa0s-Callout-1.0", 4
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.Callout = MINOR

-- ── the voice packs ──────────────────────────────────────────────────────────────────────────
--
-- One row per bundled pack: the `voice` setting's key, the folder under media/sounds/callout/ its
-- lines sit in, and the name a settings row shows. Order is the settings row's order: the arena
-- announcer (the default), then the female voices, then the male. A new pack is a row here and a
-- folder of LINES; nothing else names a pack. The first two packs (v1.96.0) keep their keys
-- `female` and `male`, so a stored choice still reads; every pack since is keyed by its folder.
lib.PACKS = {
  { key = "male-arena-john", folder = "male-arena-john", name = "Arena announcer (John)" },
  { key = "female",          folder = "female-kathleen", name = "Female (Kathleen)" },
  { key = "female-kristin",  folder = "female-kristin",  name = "Female (Kristin)" },
  { key = "female-cori",     folder = "female-cori",     name = "Female (Cori)" },
  { key = "female-bella",    folder = "female-bella",    name = "Female (Bella)" },
  { key = "male",            folder = "male-joe",        name = "Male (Joe)" },
  { key = "male-john",       folder = "male-john",       name = "Male (John)" },
  { key = "male-norman",     folder = "male-norman",     name = "Male (Norman)" },
}
lib.TTS, lib.OFF = "tts", "off"           -- the two `voice` values that are not a pack

local PACK = {}
for _, p in ipairs(lib.PACKS) do PACK[p.key] = p end

-- ── the texts ────────────────────────────────────────────────────────────────────────────────
--
-- The kinds, each with a default color the player can change.
lib.KINDS = { "number", "info", "go", "stop", "warn", "error" }
local KIND = {}
for _, k in ipairs(lib.KINDS) do KIND[k] = true end

-- The stock call-outs: key -> the text shown, its kind and what a voice says. `say` is the words
-- the packs speak (text to speech says the same), so PAUSE says "Pause" and LAST_TEN "Ten
-- seconds" whatever the text shown. Each key's pack line is its lower-case name (`NEW_BEST` -> `new_best.ogg`); the numbers 1 to 20 are `1.ogg` .. `20.ogg`.
lib.STOCK = {
  READY     = { text = "READY",     kind = "info",  say = "Ready" },
  GO        = { text = "GO!",       kind = "go",    say = "Go" },
  START     = { text = "START",     kind = "go",    say = "Start" },
  STOP      = { text = "STOP",      kind = "stop",  say = "Stop" },
  WARNING   = { text = "WARNING",   kind = "warn",  say = "Warning" },
  ERROR     = { text = "ERROR",     kind = "error", say = "Error" },
  DONE      = { text = "DONE",      kind = "info",  say = "Done" },
  FINISH    = { text = "FINISH",    kind = "go",    say = "Finish" },
  NEW_BEST  = { text = "NEW BEST",  kind = "go",    say = "New best" },
  PAUSE     = { text = "PAUSED",    kind = "warn",  say = "Pause" },
  RESUME    = { text = "RESUME",    kind = "info",  say = "Resume" },
  CANCELED = { text = "CANCELED", kind = "stop",  say = "Canceled" },
  PULL      = { text = "PULL",      kind = "warn",  say = "Pull" },
  INTERRUPT = { text = "INTERRUPT", kind = "warn",  say = "Interrupt" },
  MOVE      = { text = "MOVE",      kind = "warn",  say = "Move" },
  DEFENSIVE = { text = "DEFENSIVE", kind = "warn",  say = "Defensive" },
  REBUFF    = { text = "REBUFF",    kind = "info",  say = "Rebuff" },
  EXPIRING  = { text = "EXPIRING",  kind = "warn",  say = "Expiring" },
  UPGRADE   = { text = "UPGRADE",   kind = "go",    say = "Upgrade" },
  TIME_UP   = { text = "TIME UP",   kind = "stop",  say = "Time up" },
  VICTORY   = { text = "VICTORY",   kind = "go",    say = "Victory" },
  FAILED    = { text = "FAILED",    kind = "error", say = "Failed" },
  LAST_TEN  = { text = "LAST TEN",  kind = "warn",  say = "Ten seconds" },
}
lib.STOCK_ORDER = { "READY", "GO", "START", "STOP", "WARNING", "ERROR", "DONE", "FINISH", "NEW_BEST",
  "PAUSE", "RESUME", "CANCELED", "PULL", "INTERRUPT", "MOVE", "DEFENSIVE", "REBUFF", "EXPIRING",
  "UPGRADE", "TIME_UP", "VICTORY", "FAILED", "LAST_TEN" }

lib.MAX_FROM = 20                         -- the longest countdown, and the highest number with a line

-- Every line a pack carries, file names without the extension: the stock keys, then 1 .. 20.
lib.LINES = {}
for _, key in ipairs(lib.STOCK_ORDER) do lib.LINES[#lib.LINES + 1] = key:lower() end
for n = 1, lib.MAX_FROM do lib.LINES[#lib.LINES + 1] = tostring(n) end
lib.SOUND_EXT = ".ogg"

-- ── the choices ──────────────────────────────────────────────────────────────────────────────

lib.FONT_SKIN, lib.FONT_GAME = "Skin font", "Game default"   -- the two font values that are no face
lib.FONT_DEFAULT = "Ka0s Oxanium SemiBold"   -- a LibKa0s-Media-1.0 face, also its LSM name (minor 4; Bold to minor 3)
lib.OUTLINES = { "NONE", "OUTLINE", "THICKOUTLINE", "MONOCHROME" }
lib.GLOWS = { "off", "soft", "strong" }    -- the retired glow choice (to minor 2), GLOW_LEGACY's keys
lib.ANIMS = { "slam", "pulse", "glow", "blink", "shake", "none" }
lib.CHANNELS = { "Master", "SFX", "Dialog" }
lib.SIZE_MIN, lib.SIZE_MAX = 32, 200
-- frame-layering-§1's T5 non-interactive screen alert (`SCREEN_ALERT`): FULLSCREEN, mouse disabled
-- while locked. HIGH is the interactive toast's tier, and the Blizzard Settings panel (HIGH, toplevel)
-- would cover a call-out unlocked or tested from it.
lib.STRATA = "FULLSCREEN"
lib.WIDTH = 900                           -- the frame's width; its height follows the size

--- The settings a host seeds its profile with (AceDB copies a defaults table, so pass this one; a
--- host copying by hand copies `point` and `colors` too, never shares them).
lib.DEFAULTS = {
  font = lib.FONT_DEFAULT, size = 96, outline = "THICKOUTLINE",
  shadow = true, shadowX = 1, shadowY = 1,
  colors = {
    number = { 1, 1, 1 },        info = { 0.35, 0.75, 1 },  go = { 0.3, 1, 0.45 },
    stop   = { 1, 0.35, 0.3 },   warn = { 1, 0.78, 0.2 },   error = { 1, 0.2, 0.25 },
  },
  -- The glow behind the text (minor 3): on. From minor 4 black at full intensity, 1 px thick, 1 px
  -- right and 1 px down (to minor 3: the old "soft" look, 0.35 and 2 px, in each word's kind color).
  glow = true, glowIntensity = 1, glowThickness = 1, glowX = 1, glowY = -1,
  glowCustom = true, glowColor = { 0, 0, 0 }, useClassColorGlow = false, glowColorFromSkin = false,
  anim = "slam", hold = 1.5,
  point = { "CENTER", "CENTER", 0, 180 },
  voice = "male-arena-john", channel = "Master", speakFrom = 5,
  ttsVoice = false, ttsRate = 0, ttsVolume = 100,   -- false: the client's first voice
  texts = {},                                        -- key -> the player's own text for a stock key
  muted = {},                                        -- key -> true: that stock key shows unspoken
}

--- What a stored minor-2 `glow` choice reads as (minor 3): the halo was the text's size times 1.04
--- ("soft") or 1.1 ("strong") at alpha 0.35 or 0.7, so at the default size 96 "soft" is 2 px out and
--- "strong" 5. A setting stored on its own wins over the choice. Never mutate it.
lib.GLOW_LEGACY = {
  off    = { glow = false },
  soft   = { glow = true, glowIntensity = 0.35, glowThickness = 2 },
  strong = { glow = true, glowIntensity = 0.7, glowThickness = 5 },
}

local TAG = "CALLOUT"
local HEIGHT_FACTOR = 1.5                 -- the frame's height over the font size
local FADE = 0.25                         -- seconds a call-out takes to fade at the end of its hold
local HANDLE_GAP = 2
local HANDLE_LEVEL = 10                   -- the drag strip's level over the frame's

-- ── small readers ────────────────────────────────────────────────────────────────────────────

local function inList(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function between(lo, hi) return function(v) return finite(v) and v >= lo and v <= hi end end

local function oneOf(list) return function(v) return inList(list, v) end end

local function nonEmpty(v) return type(v) == "string" and v ~= "" end

local function isBool(v) return type(v) == "boolean" end

--- A stored color's channels, in either shape: named keys (`{ r =, g =, b = }`, the Options
--- descriptor's default codec) or an array (`{ r, g, b }`, what the instance writes into `d.db`
--- itself). Nil for anything else.
local function rgb(c)
  if type(c) ~= "table" then return nil end
  local r, g, b = c.r, c.g, c.b
  if r == nil and g == nil and b == nil then r, g, b = c[1], c[2], c[3] end
  if finite(r) and finite(g) and finite(b) then return r, g, b end
  return nil
end

local function validColor(c) return rgb(c) ~= nil end


-- The nine region points SetPoint takes. A stored anchor outside them would raise in SetPoint.
local ANCHOR = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

local function validPoint(pt)
  return type(pt) == "table" and ANCHOR[pt[1]] == true and (pt[2] == nil or ANCHOR[pt[2]] == true)
    and (pt[3] == nil or finite(pt[3])) and (pt[4] == nil or finite(pt[4]))
end

local function validVoice(v) return PACK[v] ~= nil or v == lib.TTS or v == lib.OFF end

local function validTexts(v)
  if type(v) ~= "table" then return false end
  for k, s in pairs(v) do
    if not (lib.STOCK[k] and type(s) == "string") then return false end
  end
  return true
end

local function validMuted(v)
  if type(v) ~= "table" then return false end
  for k, m in pairs(v) do
    if not (lib.STOCK[k] and type(m) == "boolean") then return false end
  end
  return true
end

-- What each setting may hold. A stored value that fails is read as the default (never written).
local VALID = {
  font = nonEmpty, size = between(lib.SIZE_MIN, lib.SIZE_MAX), outline = oneOf(lib.OUTLINES),
  shadow = isBool, shadowX = between(-20, 20), shadowY = between(-20, 20),
  glow = isBool, glowIntensity = between(0.05, 1), glowThickness = between(1, 6),
  glowX = between(-20, 20), glowY = between(-20, 20), glowCustom = isBool, glowColor = validColor,
  useClassColorGlow = isBool, glowColorFromSkin = isBool,
  anim = oneOf(lib.ANIMS), hold = between(0.2, 10),
  point = validPoint, voice = validVoice, channel = oneOf(lib.CHANNELS),
  speakFrom = function(v) return between(1, lib.MAX_FROM)(v) and v == math.floor(v) end,
  ttsVoice = function(v) return v == false or finite(v) end,
  ttsRate = between(-10, 10), ttsVolume = between(0, 100),
  texts = validTexts, muted = validMuted,
}
lib.SETTINGS = {}
for key in pairs(VALID) do lib.SETTINGS[#lib.SETTINGS + 1] = key end
table.sort(lib.SETTINGS)

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end

local function debugOut(S, msg)
  local sink = S.d.debug
  if type(sink) == "function" then pcall(sink, TAG, msg) end
end

--- Report `what` through d.debug the first time only.
local function logOnce(S, what)
  if S.logged[what] then return end
  S.logged[what] = true
  debugOut(S, what)
end

--- A host callback, under pcall: a raise reaches the error handler and the call-out runs on.
local function call(S, fn, ...)
  if type(fn) ~= "function" then return end
  local ok, err = pcall(fn, ...)
  if ok then return end
  local handler = type(geterrorhandler) == "function" and geterrorhandler() or nil
  if handler then pcall(handler, err) end
  debugOut(S, "callback failed: " .. tostring(err))
end

-- ── the settings ─────────────────────────────────────────────────────────────────────────────

local function store(S)
  local t = S.d.db
  if type(t) == "function" then t = t() end
  return type(t) == "table" and t or nil
end

local function get(S, key)
  local t = store(S)
  local v = t and t[key]
  if v ~= nil and VALID[key](v) then return v end
  local legacy = t and lib.GLOW_LEGACY[t.glow]   -- a minor-2 glow choice, read as its look (minor 3)
  if legacy and legacy[key] ~= nil then return legacy[key] end
  return lib.DEFAULTS[key]
end

--- The pack keys this instance offers, as a set: the packs whose folder `d.packs` names (the host's
--- `LibKa0s sounds:` line, each `callout/<folder>` or the bare folder), or every pack when `d.packs`
--- is not a table. Read once per instance: the shipped payload does not change in a session.
local function offered(S)
  if S.offered then return S.offered end
  local out, want = {}, S.d.packs
  local ships
  if type(want) == "table" then
    ships = {}
    for _, f in ipairs(want) do
      if type(f) == "string" then ships[(f:gsub("^callout/", ""))] = true end
    end
  end
  for _, p in ipairs(lib.PACKS) do
    if not ships or ships[p.folder] then out[p.key] = true end
  end
  S.offered = out
  return out
end

--- The voice as the instance speaks it. A stored (or default) pack the host does not ship reads as
--- the first pack it does ship, else off: an undeclared pack is never played.
local function voiceOf(S)
  local v = get(S, "voice")
  if not PACK[v] or offered(S)[v] then return v end
  for _, p in ipairs(lib.PACKS) do
    if offered(S)[p.key] then return p.key end
  end
  return lib.OFF
end

local function colorOf(S, kind)
  local t = store(S)
  local r, g, b = rgb(t and type(t.colors) == "table" and t.colors[kind])
  if r then return r, g, b end
  local c = lib.DEFAULTS.colors[kind] or lib.DEFAULTS.colors.info
  return c[1], c[2], c[3]
end

-- ── the write route (minor 2) ────────────────────────────────────────────────────────────────

--- The host's prefix for this instance's rows, ending in one dot; nil without `d.path`.
local function prefixOf(S)
  local p = S.d.path
  if not nonEmpty(p) then return nil end
  return p:sub(-1) == "." and p or (p .. ".")
end

--- Whether every write goes through the host's seam: `d.set` and `d.path` both given.
local function hostWrites(S) return type(S.d.set) == "function" and prefixOf(S) ~= nil end

--- A color as this instance stores it: the host's `d.colorEncode` when it gives one; else, for a
--- host that names its rows (`d.path`) or for a schema row's default (`named`), the named-key shape
--- the Options descriptor's default codec reads; else the array the instance has always written
--- into `d.db`.
local function encodeColor(S, r, g, b, named)
  if type(S.d.colorEncode) == "function" then return S.d.colorEncode(r, g, b, 1) end
  if named or prefixOf(S) then return { r = r, g = g, b = b, a = 1 } end
  return { r, g, b }
end

-- The leaf keys: one stock key's own text or mute, one kind's color. `texts.GO`, `muted.STOP`,
-- `colors.warn`. Each is one schema row on the host's route.
local LEAF_OF = {
  texts = function(sub) return lib.STOCK[sub] ~= nil end,
  muted = function(sub) return lib.STOCK[sub] ~= nil end,
  colors = function(sub) return KIND[sub] == true end,
}
local LEAF_VALID = {
  texts = function(v) return type(v) == "string" end,
  muted = function(v) return type(v) == "boolean" end,
  colors = validColor,
}

--- `head, sub` for a leaf key (`"texts", "GO"`), nil for any other.
local function leafOf(key)
  if type(key) ~= "string" then return nil end
  local head, sub = key:match("^(%a+)%.([%w_]+)$")
  if head and LEAF_OF[head] and LEAF_OF[head](sub) then return head, sub end
  return nil
end

--- A key Get and Set take: a setting of SETTINGS, or a leaf.
local function known(key) return VALID[key] ~= nil or leafOf(key) ~= nil end

--- What `key` may hold, for this instance: a pack the host does not ship is no voice.
local function validFor(S, key, v)
  local head = leafOf(key)
  if head then return LEAF_VALID[head](v) end
  if not VALID[key] or not VALID[key](v) then return false end
  if key == "voice" and PACK[v] and not offered(S)[v] then return false end
  return true
end

--- The default a write of nil puts back, as this instance stores it. A leaf's is what an empty
--- `texts` / `muted` reads as (`""`, `false`) and its kind's default color; the voice's is the first
--- pack the host ships when the default pack is not among them.
local function defaultOf(S, key, named)
  local head, sub = leafOf(key)
  if head == "texts" then return "" end
  if head == "muted" then return false end
  if head == "colors" or key == "glowColor" then
    local c = head and lib.DEFAULTS.colors[sub] or lib.DEFAULTS.glowColor
    return encodeColor(S, c[1], c[2], c[3], named)
  end
  if key == "voice" then
    local v = lib.DEFAULTS.voice
    if offered(S)[v] then return v end
    for _, p in ipairs(lib.PACKS) do
      if offered(S)[p.key] then return p.key end
    end
    return lib.OFF
  end
  return copy(lib.DEFAULTS[key])
end

--- A whole `texts` / `muted` table on the host's route, where only its leaves have rows: one leaf
--- write per stock key, `d.set(prefix .. head .. "." .. KEY, v)`, a key the table leaves out (or a
--- nil table) written as its default. Every leaf is written; answers whether every one landed.
local function writeWhole(S, head, value)
  local ok = true
  for _, k in ipairs(lib.STOCK_ORDER) do
    local leaf, v = head .. "." .. k, nil
    if type(value) == "table" then v = value[k] end
    if v == nil then v = defaultOf(S, leaf) end
    if S.d.set(prefixOf(S) .. leaf, v) == false then ok = false end
  end
  return ok
end

--- Write one validated value. On the host's route that is `d.set(prefix .. key, value)`, nil sent as
--- the default (a schema row's validate takes no nil), and a whole `texts` / `muted` split into its
--- leaves; else it is stored into `d.db`, a leaf by a copy of its table with the one key changed,
--- and nil removes it. Answers whether it landed.
local function write(S, key, value)
  if hostWrites(S) then
    if key == "texts" or key == "muted" then return writeWhole(S, key, value) end
    if value == nil then value = defaultOf(S, key) end
    return S.d.set(prefixOf(S) .. key, copy(value)) ~= false
  end
  local t = store(S)
  if not t then return false end
  local head, sub = leafOf(key)
  if not head then
    t[key] = copy(value)
    return true
  end
  local whole = head == "colors" and copy(type(t.colors) == "table" and t.colors or {}) or copy(get(S, head))
  whole[sub] = copy(value)
  t[head] = whole
  return true
end

-- ── the font ─────────────────────────────────────────────────────────────────────────────────

local function resolve(major) return LibStub and LibStub(major, true) end

local function gameFont()
  if type(STANDARD_TEXT_FONT) == "string" then return STANDARD_TEXT_FONT end
  return "Fonts\\FRIZQT__.TTF"
end

--- The host's skin facade (`d.skin`, a registered owner), or nil.
local function skinFacade(S)
  local Skin = resolve("LibKa0s-Skin-1.0")
  local owner = S.d.skin
  if not (Skin and type(owner) == "string" and type(Skin.IsOwner) == "function" and type(Skin.For) == "function"
    and Skin:IsOwner(owner)) then
    return nil
  end
  return Skin:For(owner)
end

local function skinFont(S)
  local facade = skinFacade(S)
  return facade and type(facade.GetFont) == "function" and facade.GetFont() or nil
end

--- A face by name: LibSharedMedia's, else LibKa0s-Media-1.0's bundled file of that name.
local function namedFont(S, name)
  local LSM = resolve("LibSharedMedia-3.0")
  local path = LSM and type(LSM.Fetch) == "function" and LSM:Fetch("font", name, true)
  if type(path) == "string" then return path end
  local Media = resolve("LibKa0s-Media-1.0")
  if Media and type(Media.Font) == "function" then return Media.Font(S.d.addon, name, S.d.vendorPath) end
  return nil
end

local function fontPath(S)
  local name = get(S, "font")
  if name == lib.FONT_GAME then return gameFont() end
  if name == lib.FONT_SKIN then return skinFont(S) or gameFont() end
  return namedFont(S, name) or namedFont(S, lib.FONT_DEFAULT) or gameFont()
end

local function fontFlags(S)
  local o = get(S, "outline")
  return o == "NONE" and "" or o
end

--- SetFont answers false for a face the client cannot load; the game's face stands in.
local function setFont(fs, path, size, flags)
  if fs:SetFont(path, size, flags) == false then fs:SetFont(gameFont(), size, flags) end
end

-- ── the glow (minor 3) ───────────────────────────────────────────────────────────────────────
--
-- AuraMaster's text glow, on the halo this file has always drawn: one FontString behind the text,
-- in the text's face with a thick outline, `glowThickness` px bigger on every side, moved by
-- (`glowX`, `glowY`), at alpha `glowIntensity` while `glow` is on. Its color, first that answers:
-- the player's class color (`useClassColorGlow`, LibKa0s-Core-1.0's ClassColor, RAID_CLASS_COLORS),
-- the skin's glow color (`glowColorFromSkin`, the facade's GlowColor, `glow.color`), the swatch
-- (`glowCustom`, `glowColor`), else the word's kind color. A class or skin that answers nothing
-- falls through to the next. No OnUpdate: it is set when a call-out is painted.

local function skinGlow(S)
  local facade = skinFacade(S)
  if not (facade and type(facade.GlowColor) == "function") then return nil end
  local r, g, b = facade.GlowColor()
  if finite(r) and finite(g) and finite(b) then return r, g, b end
  return nil
end

local function classGlow()
  if type(core.ClassColor) ~= "function" then return nil end
  local r, g, b = core.ClassColor("player")
  if finite(r) and finite(g) and finite(b) then return r, g, b end
  return nil
end

local function glowColorOf(S, kind)
  local r, g, b
  if get(S, "useClassColorGlow") then r, g, b = classGlow() end
  if not r and get(S, "glowColorFromSkin") then r, g, b = skinGlow(S) end
  if r then return r, g, b end
  if get(S, "glowCustom") then return rgb(get(S, "glowColor")) end
  return colorOf(S, kind)
end

-- ── the animations ───────────────────────────────────────────────────────────────────────────
--
-- Each is a list of steps on the content frame (or, for "glow", on the halo behind the text). Built once
-- per instance, the first time it plays.
local ANIM_STEPS = {
  slam = {
    { type = "Scale", from = 2.2, to = 1, dur = 0.18, order = 1, smooth = "OUT" },
    { type = "Alpha", from = 0, to = 1, dur = 0.12, order = 1 },
  },
  pulse = {
    { type = "Scale", from = 1, to = 1.18, dur = 0.12, order = 1, smooth = "OUT" },
    { type = "Scale", from = 1.18, to = 1, dur = 0.18, order = 2, smooth = "IN" },
  },
  glow = {
    { type = "Alpha", from = 1, to = 0, dur = 0.6, order = 1, smooth = "OUT", halo = true },
  },
  blink = {
    { type = "Alpha", from = 1, to = 0.15, dur = 0.12, order = 1 },
    { type = "Alpha", from = 0.15, to = 1, dur = 0.12, order = 2 },
    { type = "Alpha", from = 1, to = 0.15, dur = 0.12, order = 3 },
    { type = "Alpha", from = 0.15, to = 1, dur = 0.12, order = 4 },
  },
  shake = {
    { type = "Translation", x = 14, dur = 0.04, order = 1 },
    { type = "Translation", x = -28, dur = 0.08, order = 2 },
    { type = "Translation", x = 28, dur = 0.08, order = 3 },
    { type = "Translation", x = -14, dur = 0.04, order = 4 },
  },
}

local STEP_SETUP = {
  Scale = function(a, s)
    a:SetScaleFrom(s.from, s.from)
    a:SetScaleTo(s.to, s.to)
    a:SetOrigin("CENTER", 0, 0)
  end,
  Alpha = function(a, s)
    a:SetFromAlpha(s.from)
    a:SetToAlpha(s.to)
  end,
  Translation = function(a, s) a:SetOffset(s.x or 0, s.y or 0) end,
}

local function buildGroup(target, steps)
  local ag = target:CreateAnimationGroup()
  for _, s in ipairs(steps) do
    local a = ag:CreateAnimation(s.type)
    a:SetDuration(s.dur)
    a:SetOrder(s.order or 1)
    if s.smooth then a:SetSmoothing(s.smooth) end
    STEP_SETUP[s.type](a, s)
  end
  return ag
end

local function animGroup(S, name)
  local ag = S.anims[name]
  if ag then return ag end
  local steps = ANIM_STEPS[name]
  if not steps then return nil end
  ag = buildGroup(steps[1].halo and S.halo or S.content, steps)
  if steps[1].halo then ag:SetToFinalAlpha(true) end
  S.anims[name] = ag
  return ag
end

local function stopAnims(S)
  for _, ag in pairs(S.anims) do ag:Stop() end
  if S.fade then S.fade:Stop() end
end

-- ── the frame ────────────────────────────────────────────────────────────────────────────────

local function paint(S, kind)
  local r, g, b = colorOf(S, kind)
  S.text:SetTextColor(r, g, b, 1)
  S.halo:SetTextColor(glowColorOf(S, kind))
  S.halo:SetAlpha(get(S, "glow") and get(S, "glowIntensity") or 0)
end

local function applyLook(S)
  local path, size, flags = fontPath(S), get(S, "size"), fontFlags(S)
  setFont(S.text, path, size, flags)
  setFont(S.halo, path, size + 2 * math.floor(get(S, "glowThickness") + 0.5), "THICKOUTLINE")
  S.halo:ClearAllPoints()
  S.halo:SetPoint("CENTER", S.content, "CENTER", get(S, "glowX"), get(S, "glowY"))
  if get(S, "shadow") then
    S.text:SetShadowOffset(get(S, "shadowX"), get(S, "shadowY"))
    S.text:SetShadowColor(0, 0, 0, 1)
  else
    S.text:SetShadowOffset(0, 0)
    S.text:SetShadowColor(0, 0, 0, 0)
  end
  S.frame:SetSize(lib.WIDTH, math.floor(size * HEIGHT_FACTOR + 0.5))
  paint(S, S.current and S.current.kind or "info")
end

local function applyPosition(S)
  local pt = get(S, "point")
  S.frame:ClearAllPoints()
  S.frame:SetPoint(pt[1], UIParent, pt[2] or pt[1], pt[3] or 0, pt[4] or 0)
end

--- The drag's point, written like any other write: through the host's seam on its route (a raise
--- there reaches the error handler, not the drag's script), into `d.db` otherwise.
local function savePosition(S)
  local point, _, relativePoint, x, y = S.frame:GetPoint(1)
  if type(point) ~= "string" then return end
  local pt = { point, type(relativePoint) == "string" and relativePoint or point,
    finite(x) and x or 0, finite(y) and y or 0 }
  if not validPoint(pt) then return end
  call(S, write, S, "point", pt)
end

local function onDragStart(S)
  if S.locked then return end
  S.frame:StartMoving()
  S.moving = true
end

local function onDragStop(S)
  S.moving = nil
  S.frame:StopMovingOrSizing()
  savePosition(S)
end

--- A lock (or a Suspend) during a drag: the mouse-up never reaches a frame that no longer takes the
--- mouse, so the move ends here and the point is saved (Toast.lua's endDrag, the same shape).
local function endDrag(S)
  if not S.moving then return end
  S.moving = nil
  S.frame:StopMovingOrSizing()
  savePosition(S)
end

--- The drag strip over the frame while it is unlocked, when LibKa0s-Widgets-1.0 is present. It is a
--- child of the frame, which never animates (the animations play on S.content), and it ignores the
--- frame's alpha and sits HANDLE_LEVEL over it (frame-layering-§2).
local function buildHandle(S)
  local Widgets = resolve("LibKa0s-Widgets-1.0")
  if not (Widgets and type(Widgets.DragHandle) == "function") then return end
  local handle = Widgets.DragHandle(S.frame, {
    label = type(S.d.label) == "string" and S.d.label or "Call-out",
    moveFrame = S.frame, owner = S.d.skin, ignoreParentAlpha = true, level = HANDLE_LEVEL,
    canDrag = function() return not S.locked end,
    onDragStart = function() S.moving = true end,
    onDragStop = function() S.moving = nil; savePosition(S) end,
  })
  if not handle then return end
  handle:SetPoint("BOTTOM", S.frame, "TOP", 0, HANDLE_GAP)
  if type(handle.ApplyWidth) == "function" then handle:ApplyWidth() end
  handle:Hide()
  S.handle = handle
end

local function finishFade(S)
  S.frame:Hide()
  S.frame:SetAlpha(1)
  S.current = nil
end

local function buildFade(S)
  local ag = buildGroup(S.frame, { { type = "Alpha", from = 1, to = 0, dur = FADE, order = 1 } })
  ag:SetScript("OnFinished", function() finishFade(S) end)
  S.fade = ag
end

local tick   -- forward: the clock's OnUpdate calls it; defined with the countdown below

local function build(S)
  if S.frame then return S.frame end
  local f = CreateFrame("Frame", S.d.name, UIParent)
  S.frame = f
  f:Hide()
  f:SetFrameStrata(lib.STRATA)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(false)            -- never takes the mouse while locked
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() onDragStart(S) end)
  f:SetScript("OnDragStop", function() onDragStop(S) end)
  -- The text and its halo sit on an inner frame the animations play on, so the frame (the drag
  -- target, the fade, and the drag strip's parent) never scales, shakes or blinks.
  local content = CreateFrame("Frame", nil, f)
  content:SetAllPoints(f)
  S.content = content
  S.halo = content:CreateFontString(nil, "BACKGROUND")   -- placed by applyLook, at the glow's offset
  S.text = content:CreateFontString(nil, "OVERLAY")
  S.text:SetPoint("CENTER", content, "CENTER", 0, 0)
  S.clock = CreateFrame("Frame")   -- no parent: a hidden UI does not stop the countdown
  buildFade(S)
  buildHandle(S)
  applyLook(S)
  applyPosition(S)
  return f
end

-- ── the clock ────────────────────────────────────────────────────────────────────────────────

local function wake(S)
  if S.awake then return end
  S.awake = true
  S.clock:SetScript("OnUpdate", function() tick(S) end)
end

local function sleep(S)
  if not S.awake then return end
  S.awake = false
  S.clock:SetScript("OnUpdate", nil)
end

local function startFade(S)
  S.hideAt = nil
  if not S.locked then return end   -- unlocked, the sample stays up to be placed
  for _, ag in pairs(S.anims) do ag:Stop() end
  S.fade:Play()
end

local function hideNow(S)
  S.hideAt = nil
  if not S.frame then return end
  stopAnims(S)
  finishFade(S)
end

-- ── the sound ────────────────────────────────────────────────────────────────────────────────

local function soundsBase(S)
  if nonEmpty(S.d.soundsBase) then return S.d.soundsBase end
  if not nonEmpty(S.d.addon) then return nil end
  return "Interface\\AddOns\\" .. S.d.addon .. "\\" .. (S.d.vendorPath or "libs\\LibKa0s")
    .. "\\media\\sounds\\callout"
end

local function playFile(S, file)
  if type(PlaySoundFile) ~= "function" then
    logOnce(S, "no PlaySoundFile: call-outs are silent")
    return false
  end
  if PlaySoundFile(file, get(S, "channel")) == false then
    logOnce(S, "sound file missing, silent: " .. tostring(file))
    return false
  end
  return true
end

local function playLine(S, voice, line)
  local base = soundsBase(S)
  if not base then
    logOnce(S, "no d.addon or d.soundsBase: the voice packs cannot be found")
    return false
  end
  return playFile(S, base .. "\\" .. PACK[voice].folder .. "\\" .. line .. lib.SOUND_EXT)
end

--- The player's TTS voice when the client still has it, else the client's first voice.
local function ttsVoiceId(S, voices)
  local want = get(S, "ttsVoice")
  for _, v in ipairs(voices) do
    if v.voiceID == want then return want end
  end
  return voices[1] and voices[1].voiceID
end

local function ttsVoices()
  local vc = C_VoiceChat
  local list = vc and vc.GetTtsVoices and vc.GetTtsVoices()
  local out = {}
  if type(list) ~= "table" then return out end
  for _, v in ipairs(list) do
    if type(v) == "table" and finite(v.voiceID) then
      out[#out + 1] = { voiceID = v.voiceID, name = tostring(v.name or v.voiceID) }
    end
  end
  return out
end

local function speak(S, text)
  local vc = C_VoiceChat
  if not (vc and vc.SpeakText) then
    logOnce(S, "no C_VoiceChat.SpeakText: text to speech is silent")
    return false
  end
  local id = ttsVoiceId(S, ttsVoices())
  if not id then
    logOnce(S, "no text to speech voice installed")
    return false
  end
  vc.SpeakText(id, text, get(S, "ttsRate"), get(S, "ttsVolume"), true)
  return true
end

--- What an entry says, by the voice setting. Answers whether anything was played.
local function sound(S, entry)
  if entry.voice == false then return false end
  if entry.stock and get(S, "muted")[entry.key] then return false end
  local voice = voiceOf(S)
  if voice == lib.OFF then return false end
  if entry.sound then return playFile(S, entry.sound) end
  if entry.number and entry.number > get(S, "speakFrom") then return false end
  if voice == lib.TTS then return speak(S, entry.say or entry.text) end
  if entry.line then return playLine(S, voice, entry.line) end
  return false
end

-- ── the entries ──────────────────────────────────────────────────────────────────────────────

local function numberEntry(n)
  local s = tostring(n)
  return { key = s, text = s, kind = "number", say = s, line = s, number = n }
end

local function stockEntry(S, key)
  local stock = lib.STOCK[key]
  if not stock then return nil end
  local own = get(S, "texts")[key]
  return { key = key, text = nonEmpty(own) and own or stock.text, kind = stock.kind,
    say = stock.say, line = key:lower(), stock = true }
end

local function customEntry(spec)
  if spec.text == nil then return nil end
  return { text = tostring(spec.text), kind = KIND[spec.kind] and spec.kind or "info",
    sound = (nonEmpty(spec.sound) or finite(spec.sound)) and spec.sound or nil,
    voice = spec.voice, hold = spec.hold, anim = spec.anim, key = spec.key }
end

--- A stock key, a number from 1 to 20 (or its string), or a custom spec, as an entry; nil for none.
local function entryFor(S, what)
  local n = tonumber(what)
  if n and n == math.floor(n) and n >= 1 and n <= lib.MAX_FROM then return numberEntry(n) end
  if type(what) == "string" then return stockEntry(S, what) end
  if type(what) == "table" then return customEntry(what) end
  return nil
end

local function merge(entry, opts)
  if type(opts) ~= "table" then return entry end
  if opts.hold ~= nil then entry.hold = opts.hold end
  if opts.anim ~= nil then entry.anim = opts.anim end
  if opts.voice == false then entry.voice = false end
  return entry
end

--- Draw `entry` now, play its animation and its sound.
local function present(S, entry)
  build(S)
  S.current = entry
  S.text:SetText(entry.text)
  S.halo:SetText(entry.text)
  paint(S, entry.kind)
  stopAnims(S)
  S.frame:SetAlpha(1)
  S.frame:Show()
  local anim = inList(lib.ANIMS, entry.anim) and entry.anim or get(S, "anim")
  local ag = animGroup(S, anim)
  if ag then ag:Play() end
  sound(S, entry)
end

local function holdFor(S, entry)
  if VALID.hold(entry.hold) then return entry.hold end
  return get(S, "hold")
end

--- Show `entry` and fade it after its hold.
local function showHeld(S, entry)
  present(S, entry)
  S.hideAt = GetTime() + holdFor(S, entry)
  wake(S)
end

-- ── the countdown ────────────────────────────────────────────────────────────────────────────

local function finishCountdown(S, cd)
  local finish = cd.finish
  if finish == nil then finish = "GO" end
  local entry = finish ~= false and entryFor(S, finish)
  if entry then showHeld(S, entry) else startFade(S) end
  call(S, cd.onDone)
end

local function stepCountdown(S, now)
  local cd = S.cd
  local n = math.ceil(cd.endsAt - now)
  if n == cd.last or n > cd.from then return end
  cd.last = n
  if n >= 1 then
    S.hideAt = nil   -- the number replaces a held Show (or the last finish); its hold goes with it
    present(S, numberEntry(n))
    call(S, cd.onTick, n)
    return
  end
  S.cd = nil
  finishCountdown(S, cd)
end

tick = function(S)
  local now = GetTime()
  if S.cd then stepCountdown(S, now) end
  if S.hideAt and now >= S.hideAt then startFade(S) end
  if not (S.cd or S.hideAt) then sleep(S) end
end

-- ── the instance ─────────────────────────────────────────────────────────────────────────────

local STATE = setmetatable({}, { __mode = "k" })

local function state(self)
  local S = STATE[self]
  if not S then error(MAJOR .. ": call this on an instance from Callout:New", 3) end
  return S
end

local METHODS = {}

--- Count down to `spec.endsAt` (a GetTime() value): the number shown is ceil(endsAt - now), from
--- `spec.from` (at most 20; the default is 20) down to 1, then `spec.finish` (a stock key, a
--- custom spec, or false for none; "GO" when nil). `spec.onTick(n)` is called as each number
--- shows, `spec.onDone()` once at zero. A countdown already running is replaced. Answers false
--- (and does nothing) while suspended or for an endsAt that is not a number.
function METHODS:Countdown(spec)
  local S = state(self)
  if S.suspended or type(spec) ~= "table" or not finite(spec.endsAt) then return false end
  local from = tonumber(spec.from) or lib.MAX_FROM
  from = math.max(1, math.min(lib.MAX_FROM, math.floor(from)))
  build(S)
  -- A held call-out keeps its hold: through a lead-in (endsAt more than `from` away) it fades on its
  -- own schedule, and the first number replaces it (stepCountdown clears the hold).
  S.cd = { endsAt = spec.endsAt, from = from, finish = spec.finish,
    onTick = spec.onTick, onDone = spec.onDone }
  wake(S)
  tick(S)
  return true
end

--- Stop the countdown without its finish or its onDone, and take the call-out down.
function METHODS:Cancel()
  local S = state(self)
  local had = S.cd ~= nil
  S.cd = nil
  hideNow(S)
  sleep(S)
  return had
end

--- Whether a countdown runs, and the number it shows (nil before its first).
function METHODS:Running()
  local cd = state(self).cd
  if not cd then return false, nil end
  return true, cd.last
end

--- Show a stock key, a number 1-20, or a custom `{ text, kind, sound, voice = false, hold, anim }`.
--- `opts` may carry `hold`, `anim` and `voice = false`. It shows over a running countdown, whose
--- next number replaces it. Answers false for nothing to show, or while suspended.
function METHODS:Show(what, opts)
  local S = state(self)
  if S.suspended then return false end
  local entry = entryFor(S, what)
  if not entry then
    debugOut(S, "nothing to show for " .. tostring(what))
    return false
  end
  showHeld(S, merge(entry, opts))
  return true
end

--- Take the call-out down now (a running countdown goes on, and shows its next number).
function METHODS:Hide()
  local S = state(self)
  hideNow(S)
  if not S.cd then sleep(S) end
end

--- The stand-down: the countdown stops with no onDone, the call-out goes, the frame locks, and
--- Show and Countdown answer false until Resume.
function METHODS:Suspend()
  local S = state(self)
  S.suspended, S.cd = true, nil
  self:SetLocked(true)
  hideNow(S)
  sleep(S)
end

function METHODS:Resume() state(self).suspended = false end

function METHODS:Suspended() return state(self).suspended == true end

--- A leaf as the instance reads it: a stock key's own text (`""` for none), its mute, a kind's
--- color as `{ r, g, b, r =, g =, b = }`.
local function getLeaf(S, head, sub)
  if head == "texts" then return get(S, "texts")[sub] or "" end
  if head == "muted" then return get(S, "muted")[sub] == true end
  local r, g, b = colorOf(S, sub)
  return { r, g, b, r = r, g = g, b = b }
end

--- One setting, as the instance reads it: the host's stored value, or the default when it holds
--- none or one that is not valid. From minor 2 a leaf key (`texts.GO`, `muted.STOP`, `colors.go`)
--- answers that one entry.
function METHODS:Get(key)
  local S = state(self)
  local head, sub = leafOf(key)
  if head then return getLeaf(S, head, sub) end
  if not VALID[key] then return nil end
  if key == "voice" then return voiceOf(S) end
  return copy(get(S, key))
end

--- A minor-2 glow choice ("off" / "soft" / "strong") given to Set: written as the keys its
--- `GLOW_LEGACY` row names, `glow` first, so a v1.98.0 caller's write still lands (minor 3).
local LEGACY_KEYS = { "glow", "glowIntensity", "glowThickness" }
local function setLegacyGlow(self, S, choice)
  local row = lib.GLOW_LEGACY[choice]
  for _, key in ipairs(LEGACY_KEYS) do
    if row[key] ~= nil and not write(S, key, row[key]) then return false end
  end
  self:Apply()
  return true
end

--- Before a `glow` write replaces a stored minor-2 choice, store the intensity and thickness that
--- choice implied where no valid one is (MigrateGlow's rule), so a toggle leaves the look as it was:
--- "strong" ticked off and on again still reads 70% and 5, not the defaults. Answers whether every
--- write landed (minor 3).
local function keepLegacyLook(S)
  local t = store(S)
  local row = t and lib.GLOW_LEGACY[t.glow]
  if not row then return true end
  for _, key in ipairs(LEGACY_KEYS) do
    if key ~= "glow" and row[key] ~= nil and not VALID[key](t[key]) and not write(S, key, row[key]) then
      return false
    end
  end
  return true
end

--- Write one setting and apply it. nil clears it back to the default. On the host's route (`d.path`
--- and `d.set`) the write is `d.set(d.path .. key, value)`, a whole `texts` / `muted` as one write
--- per stock key's leaf; otherwise it lands in `d.db`. A `glowColor` in either shape is stored in
--- the instance's (minor 3), as SetColor's is. `glow` takes the boolean, and still takes a minor-2
--- choice, written as its `GLOW_LEGACY` keys; Get answers the boolean either way. Answers
--- false for an unknown key, an invalid value, no table to write into, or a host seam that refused.
function METHODS:Set(key, value)
  local S = state(self)
  if key == "glow" and lib.GLOW_LEGACY[value] then return setLegacyGlow(self, S, value) end
  if not known(key) or (value ~= nil and not validFor(S, key, value)) then return false end
  if key == "glowColor" and value ~= nil then value = encodeColor(S, rgb(value)) end
  if key == "glow" and not keepLegacyLook(S) then return false end
  if not write(S, key, value) then return false end
  self:Apply()
  return true
end

function METHODS:GetColor(kind)
  return colorOf(state(self), KIND[kind] and kind or "info")
end

--- A kind's color, written into the host's `colors` (as `{ r, g, b }` into `d.db`, or through the
--- host's seam in its own shape, `d.colorEncode`'s); no r clears it to the default.
function METHODS:SetColor(kind, r, g, b)
  local S = state(self)
  if not KIND[kind] then return false end
  local value
  if r ~= nil then
    if not validColor({ r, g, b }) then return false end
    value = encodeColor(S, r, g, b)
  end
  if not write(S, "colors." .. kind, value) then return false end
  self:Apply()
  return true
end

--- Re-read every setting onto the frame (after a profile switch, or the host's own write).
function METHODS:Apply()
  local S = state(self)
  if not S.frame then return end
  applyLook(S)
  applyPosition(S)
end

--- Unlocked, the frame takes the mouse, shows a sample and its drag strip, and a drag saves the
--- point; locked (the default), it is mouse-transparent and the sample goes.
function METHODS:SetLocked(locked)
  local S = state(self)
  locked = locked ~= false
  if locked == S.locked then return end
  S.locked = locked
  if not S.frame then
    if locked then return end
    build(S)
  end
  if locked then endDrag(S) end
  S.frame:EnableMouse(not locked)
  if S.handle then S.handle:SetShown(not locked) end
  if not locked then
    present(S, merge(entryFor(S, "READY"), { voice = false }))
    S.hideAt = nil
  elseif not S.cd then
    hideNow(S)
  end
end

function METHODS:Locked() return state(self).locked end

--- Forget the saved point: the frame goes back to the default.
function METHODS:ResetPosition()
  local S = state(self)
  write(S, "point", nil)
  if S.frame then applyPosition(S) end
end

--- The `voice` choices, in order: the packs the host ships (`d.packs`), then text to speech and
--- off. A fresh list.
function METHODS:Voices()
  local S = state(self)
  local out = {}
  for _, p in ipairs(lib.PACKS) do
    if offered(S)[p.key] then out[#out + 1] = { key = p.key, name = p.name } end
  end
  out[#out + 1] = { key = lib.TTS, name = "Game text to speech" }
  out[#out + 1] = { key = lib.OFF, name = "Off" }
  return out
end

--- The client's text to speech voices, { voiceID, name } each; empty without C_VoiceChat.
function METHODS:TtsVoices()   -- luacheck: ignore 212/self
  return ttsVoices()
end

--- The frame, built on first use.
function METHODS:Frame() return build(state(self)) end

--- The look as the frame draws it: `{ font, size, flags, shadow, shadowX, shadowY, glow }`, the
--- font resolved to a file path, and from minor 3 `glow` a boolean with `glowIntensity`,
--- `glowThickness`, `glowX` and `glowY`. A fresh table, for a host's (or CalloutSettings.lua's) preview.
function METHODS:Look()
  local S = state(self)
  return { font = fontPath(S), size = get(S, "size"), flags = fontFlags(S), shadow = get(S, "shadow"),
    shadowX = get(S, "shadowX"), shadowY = get(S, "shadowY"), glow = get(S, "glow"),
    glowIntensity = get(S, "glowIntensity"), glowThickness = get(S, "glowThickness"),
    glowX = get(S, "glowX"), glowY = get(S, "glowY") }
end

--- The glow's color as a call-out of `kind` ("info" when not a kind) is drawn with it (minor 3).
function METHODS:GetGlowColor(kind)
  return glowColorOf(state(self), KIND[kind] and kind or "info")
end

--- The instance's state, for a host's diagnostics report and its suites.
function METHODS:Stats()
  local S = state(self)
  local cur, cd = S.current, S.cd
  local logged = 0
  for _ in pairs(S.logged) do logged = logged + 1 end
  return {
    built = S.frame ~= nil, shown = S.frame ~= nil and S.frame:IsShown() == true,
    running = cd ~= nil, number = cd and cd.last, endsAt = cd and cd.endsAt,
    key = cur and cur.key, text = cur and cur.text, kind = cur and cur.kind,
    awake = S.awake == true, suspended = S.suspended == true, locked = S.locked, logged = logged,
  }
end

--- Rewrite a minor-2 `glow` choice stored in `t` (the host's call-out table) as the minor-3 keys
--- (`GLOW_LEGACY`), for a host's own migration: `glow` becomes the boolean, and the intensity and
--- thickness the choice implied are stored where no valid one is. Answers whether it changed `t`.
--- The instance reads an unmigrated table the same way, so a host that never calls it looks the same.
function lib:MigrateGlow(t)   -- luacheck: ignore 212/self
  local legacy = type(t) == "table" and lib.GLOW_LEGACY[t.glow]
  if not legacy then return false end
  for key, v in pairs(legacy) do
    if key == "glow" or not VALID[key](t[key]) then t[key] = v end
  end
  return true
end

--- A new call-out. `d.db` is required; every other field is optional (see the API document).
function lib:New(d)   -- luacheck: ignore 212/self
  if type(d) ~= "table" or (type(d.db) ~= "table" and type(d.db) ~= "function") then
    error(MAJOR .. ": New(d): d.db (the host's settings table, or a getter) is required", 2)
  end
  -- A seam with no prefix would leave every write going around it, silently: refuse it here.
  if d.set ~= nil and (type(d.set) ~= "function" or not nonEmpty(d.path)) then
    error(MAJOR .. ": New(d): d.set (the host's write seam) needs d.path, the prefix its rows sit under", 2)
  end
  local inst = {}
  for name, fn in pairs(METHODS) do inst[name] = fn end
  STATE[inst] = { d = d, anims = {}, logged = {}, locked = true, suspended = false, awake = false }
  return inst
end

-- The method table every New copies, for this major's paired files (CalloutSettings.lua adds the
-- settings section to it) and nobody else. Private: a host calls methods on an instance.
lib.__methods = METHODS

-- What CalloutSettings.lua's schema rows (minor 3) read off an instance, private for the same
-- reason: a row's validate (`__validFor`), its default (`__defaultFor`, a color in the host's shape),
-- a color row's reader (`__colorFor`, the kind's color as it reads, re-encoded in the host's shape,
-- so a stored array still reaches a swatch that decodes named keys), the host's prefix
-- (`__prefixOf`, nil without `d.path`) and whether a leaf key is one (`__known`).
lib.__validFor = function(inst, key, v) return validFor(state(inst), key, v) end
lib.__defaultFor = function(inst, key) return copy(defaultOf(state(inst), key, true)) end
lib.__colorFor = function(inst, kind)
  local S = state(inst)
  local r, g, b = colorOf(S, kind)
  return encodeColor(S, r, g, b, true)
end
-- Minor 3: the glow swatch's reader, the same way.
lib.__glowColorFor = function(inst)
  local S = state(inst)
  local r, g, b = rgb(get(S, "glowColor"))
  return encodeColor(S, r, g, b, true)
end
lib.__prefixOf = function(inst) return prefixOf(state(inst)) end
lib.__known = known
