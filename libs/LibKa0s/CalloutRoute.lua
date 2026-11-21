-- LibKa0s-Callout-1.0 — CalloutRoute.lua: where a write goes, and the setting verbs that write.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF Callout.lua ──────────────────────────────────
--
-- Because of `layout-§1`. LibKa0s#97's skin-following look took Callout.lua to 1416 lines, past the
-- ~1300 split point its census entry set, and the owner ruled the band files peeled (FU-LK-CALLOUT of
-- Ka0sAddonsCommonTasks docs/2026-11-21-SYNC_FOLLOWUPS). The write-route section, the seam that entry
-- named, moved here at Callout minor 6, unchanged, with the setting verbs that are its only callers
-- (`Get`, `Set`, `GetColor`, `SetColor`, `ResetPosition`) and the private readers CalloutSettings.lua's
-- schema rows take off an instance (`__validFor`, `__defaultFor`, `__colorFor`, `__glowColorFor`,
-- `__prefixOf`, `__known`). Every member is the same member with the same contract; their history is
-- Callout.lua's header. It is NOT a major of its own: it is part of `LibKa0s-Callout-1.0`, paired on
-- the shell's minor, so a route from one vendored copy never pairs with a shell from another without
-- saying so.
--
-- WHAT CROSSES THE CUT. Callout.lua loads first and publishes its method table (`lib.__methods`) and
-- the locals this file reads (`lib.__calloutKit`): the readers, the stored settings, the colors and
-- the instance's state. This file publishes `lib.__write`, which the shell's drag reads at call time
-- to save the point. A payload without this file builds call-outs that show and count down but have
-- no setting verbs, no saved drag point and no settings section (CalloutSettings.lua needs
-- `__validFor`).
--
-- Depends on LibStub and the Callout shell, and on nothing else.

local lib = LibStub and LibStub("LibKa0s-Callout-1.0", true)
if not lib or type(lib.__methods) ~= "table" or type(lib.__calloutKit) ~= "table" then return end

local ROUTE_MINOR = 1
-- Minor 1: the write route, the setting verbs and the private readers of Callout minor 5, moved
-- unchanged (Callout minor 6).
-- Paired on the SHELL's minor as well as this file's own, as CalloutSettings.lua is.
if lib.__routeMinor and lib.__routeMinor >= ROUTE_MINOR
  and lib.__routeShellMinor == lib.MINOR then return end
lib.__routeMinor      = ROUTE_MINOR
lib.__routeShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.CalloutRoute = ROUTE_MINOR

local METHODS = lib.__methods
local kit = lib.__calloutKit
local nonEmpty, rgb, validColor, copy = kit.nonEmpty, kit.rgb, kit.validColor, kit.copy
local store, get, offered, voiceOf = kit.store, kit.get, kit.offered, kit.voiceOf
local ownColor, colorOf, isSkinFace, state = kit.ownColor, kit.colorOf, kit.isSkinFace, kit.state
local applyPosition = kit.applyPosition
local VALID, KIND, PACK = kit.VALID, kit.KIND, kit.PACK

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

-- ── the setting verbs ─────────────────────────────────────────────────────────────────────────

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
  if key == "font" and isSkinFace(get(S, key)) then return lib.FONT_SKIN end   -- "@skin" reads as the Skin font
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

--- Forget the saved point: the frame goes back to the default.
function METHODS:ResetPosition()
  local S = state(self)
  write(S, "point", nil)
  if S.frame then applyPosition(S) end
end

-- What CalloutSettings.lua's schema rows (minor 3) read off an instance, private for the same
-- reason: a row's validate (`__validFor`), its default (`__defaultFor`, a color in the host's shape),
-- a color row's reader (`__colorFor`, the kind's swatch: its stored color or default, never the
-- skin's color it may draw in, re-encoded in the host's shape, so a stored array still reaches a
-- swatch that decodes named keys and a reset count reads a default as one), the host's prefix
-- (`__prefixOf`, nil without `d.path`) and whether a leaf key is one (`__known`).
lib.__validFor = function(inst, key, v) return validFor(state(inst), key, v) end
lib.__defaultFor = function(inst, key) return copy(defaultOf(state(inst), key, true)) end
lib.__colorFor = function(inst, kind)
  local S = state(inst)
  local r, g, b = ownColor(S, KIND[kind] and kind or "info")
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

-- The write itself, for the shell's drag (savePosition), which reads it at call time.
lib.__write = write
