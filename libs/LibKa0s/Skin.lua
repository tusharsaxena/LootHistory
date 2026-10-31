-- LibKa0s-Skin-1.0 — the skin engine: which skin each addon wears, what a token resolves to, and
-- the per-owner record of what was painted so a skin switch can repaint it live.
--
-- ── WHY THIS EXISTS ──────────────────────────────────────────────────────────────────────────
--
-- Every Ka0s window, panel, dialog and settings page is drawn from constants written into the
-- library and into each host (`Core.SKIN`, Widgets' file-local `SKIN`, the Options palettes, ~90
-- literals in LootHistory alone). A skin turns those constants into data: a token table, chosen per
-- addon (the owner's ruling R1), that every painter reads. Ka0s Default is today's constants, so a
-- host that never chooses another skin draws exactly what it drew before.
--
-- ── ONE LOADED COPY, MANY OWNERS ─────────────────────────────────────────────────────────────
--
-- LibStub keeps one copy of this major for the whole client, so every piece of state is keyed by
-- OWNER, the consumer's addon folder name, and written `lib.x = lib.x or {}` so a newer minor that
-- loads later keeps it. Two addons can show different skins at the same time, and one switching
-- never repaints the other's frames.
--
--   lib.skins[key]       the registered skin definitions (SkinDefs.lua registers them)
--   lib.owners[owner]    { label, get, set, source, skin, font, texture, pendingReload, listeners,
--                          tokens, tokGen }
--   lib.painted[frame]   weak-keyed: { owner, seq, calls = { [prim] = args }, order = { prim, ... } }
--   lib.byOwner[owner]   weak-keyed set of that owner's painted frames
--   lib.facades[owner]   the owner's facade S, one table kept across minors
--   lib.prim[name]       the painting primitives, fn(owner, ...); SkinPaint.lua fills them
--   lib.euiPainted[owner] true once EllesmereUI painted the owner this session (SkinEUI.lua)
--
-- None of these is contract: they are named so the secondary files and a newer minor can find
-- them, and a host reads the skin only through the members below and the facade.
--
-- ── THE FACADE ───────────────────────────────────────────────────────────────────────────────
--
-- `Skin:For(owner)` answers `lib.facades[owner]`. Every entry is a late-bound trampoline:
-- `S.Button(...)` looks `lib.prim.Button` up AT CALL TIME and calls it as `(owner, ...)`. A host
-- caches S at file load; a newer minor that loads later re-fills `lib.prim` and re-fills every
-- facade's entries in place, so the cached S always runs the winning copy's code. Nothing in a
-- facade closure captures a primitive. A primitive no loaded file provides answers nil.
--
-- ── WHAT IT DELIBERATELY IS NOT ──────────────────────────────────────────────────────────────
--
--   * no painting: the primitives are SkinPaint.lua's; this file only records and replays them;
--   * no SavedVariables: the host stores { source, skin } in its own profile and hands the engine
--     a getter and a setter (`RegisterOwner`); `SetChoice` never writes the profile;
--   * no EllesmereUI calls: the `eui` provider is SkinEUI.lua's. Here `eui` is a stored choice
--     whose tokens fall back to the owner's Ka0s skin until that file says EllesmereUI painted the
--     owner, and leaving it after that paint asks for a reload. SkinEUI.lua reaches this file
--     through four hook slots, each nil without it: `__euiOnOwner(owner)` (RegisterOwner),
--     `__euiRoute(owner, name)` (which primitive a call and a replay run), `__euiTokens(owner)`
--     (what `__Tokens` answers) and `__euiOnChoice(owner)` (SetChoice onto `eui`);
--   * no OnUpdate, no events: a repaint is one pass over the owner's recorded frames. The one
--     subscription is LibSharedMedia's own callback (minor 6), made the first time an owner's
--     override is checked, so a key a media pack registers late repaints the owners that name it.
--
-- Depends on LibStub and LibKa0s-Core-1.0. This file calls no Core member; the gate keeps the
-- payload's presence a single question. The major's one Core call is SkinEUI.lua's: it resolves
-- Core's SafeRegisterEvent at call time, and with a Core that lacks it makes no ADDON_LOADED /
-- PLAYER_LOGIN retry frame (owners then register with EllesmereUI only at RegisterOwner).

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

-- Minor 3: ResetToSkin sets a setting's `<key>FromSkin` companion where it has one, and a bool key
-- (a companion named directly) to true, so the sentinel never lands in a media pick or a bool
-- (OptionsCompose minor 12's companions; LK-07 of the skinning run). Only a STORED companion was
-- seen until minor 8, which recognizes one by its name.
-- Minor 4: OwnerLabel and WriteChoice, the read and the write of a registration the Appearance tab's copy to
-- every Ka0s addon needs (OptionsAppearance.lua; LK-10 of the skinning run).
-- Minor 5: each owner's two exceptions, the Appearance tab's "Ignore settings panel" and "Ignore
-- fonts" (the owner's request, 2026-10-27): GetIgnore, SetIgnore, WriteChoice's third argument, and
-- the two questions the paint paths ask (__PanelSkinned, __FontsIgnored).
-- Minor 6: each owner's font and texture override, the Appearance tab's "Font and texture" section
-- (LibKa0s#63): GetOverride, SetOverride, WriteChoice's fourth argument `media`, and `__Tokens`
-- laying the overrides over the skin's table (font.body, font.title and hud.font; bar.texture).
-- ResolveSkin stays override-free: a picker reads another skin's own tokens through it. VOCAB gains
-- BarTexture (SkinPaintExtras minor 4), the bar texture on a Texture or a StatusBar. An override
-- LibSharedMedia cannot resolve leaves the skin's own token in place, and the owner repaints when a
-- media pack registers the key later (`LibSharedMedia_Registered`); `FROM_SKIN` stored as an
-- override means the skin's own; `__BaseTokens` answers the owner's table without its overrides.
-- Minor 7: owner tokens (LK-01 of Ka0sAddonsCommonTasks docs/2026-10-29-SKINNING_ROLLOUT).
-- `RegisterOwner(owner, { tokens = { ["<ns>.<name>"] = { default, follow, skins } } })` names an
-- addon's own colors (or any token value), laid over the owner's table in `__Tokens` after its
-- overrides, so `Token`, `Color`, the facade and every primitive that reads a token NAME resolve
-- them. Ka0s Default answers `default` (the addon's pixels today), a skin its `skins` entry, else the
-- `follow` library token's value in that skin; the eui source the follow token's EllesmereUI value. A
-- name with no dot, a schema name or a malformed definition is refused and logged once. And
-- `__RemapName`, the check a primitive's `opts.tokens` slot remap makes of each name (LK-02).
-- And `__DrawsKey`, the key an owner draws by, which a primitive's `opts.stockDefault` asks (LK-05).
-- Minor 8: ResetToSkin sets a companion named directly (a key ending in `FromSkin`) to true whether
-- it is stored or not, where minor 3 recognized one only when it already held a bool and wrote the
-- sentinel into an absent one, which Resolve reads as not following (AceDB strips a companion equal
-- to its default). `opts.companions` sets every listed pick's companion, stored or not, for a host
-- that names its picks (LK-07 of Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_LIBRARY_FOLLOWUPS, R-6).
-- And `DrawsKey`, minor 7's `__DrawsKey` made public (lib-level, not a facade member; LK-10, R-9):
-- `__DrawsKey` stays one release as its alias. And Ignore fonts reaches the HUD (LK-01, R-1, D-09):
-- while the owner ignores fonts, `Token` answers nil for `hud.font` and `hud.outline` and `Resolve`
-- answers the stored value for them (nil for a stored FROM_SKIN), whatever the companion says.
-- And the stock look is retired (LK-02, R-2): no primitive reads `opts.stockDefault` any more
-- (SkinPaint minor 12), so the library itself no longer asks `DrawsKey`; a host may.
-- Minor 9: each owner's font outline, the Skin tab's "Font outline" (LK-03 of Ka0sAddonsCommonTasks
-- docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK, the owner's ruling D-06): `OUTLINE_MODES` ("all", the
-- default, "hud", "off"), GetOutline, SetOutline, WriteChoice's `media.outline`, and `__Tokens`
-- answering "" for `font.outline` under "hud" and for both `font.outline` and `hud.outline` under
-- "off". "all" reads the skin as it states them, and every skin states OUTLINE for both (SkinDefs
-- minor 17). The mode is applied here and nowhere else; P.font, BarStyle, Token and Resolve follow.
-- And VOCAB gains FontFlags (LK-04, D-07) and HudFontSize (LK-06, D-09), SkinPaintExtras minor 7's.
-- Minor 10: a font override of a shipped face brings that face's sizes (LK-F02 of Ka0sAddonsCommonTasks
-- docs/2026-10-31-FONT_PICKERS_AND_SKIN_FACES, its D-07): `__Tokens` lays SkinDefs' `__FACE_SIZES` row
-- over `font.bodySize`, `font.titleSize` and `hud.fontSize`, so body, title and HUD text all keep
-- Prototype's width. A face with no row, a media pack's, draws unscaled at Ka0s Default's sizes, and
-- so does a skin whose own face this client's locale cannot register (FONTS' langmask): the sizes it
-- states were measured for a face that is not drawn. And the default font outline is "hud" (LK-F05,
-- the owner's item 5, D-10): OUTLINE_DEFAULT moves, an owner that never set a mode and a value not in
-- OUTLINE_MODES resolve to it, and `__Tokens` applies it, so window text is unoutlined until an owner
-- picks All text. A stored mode stays. `__StoredOutline` tells a stored mode from the default, so a
-- font or texture write does not store the default as if the player had chosen it.
local MAJOR, MINOR = "LibKa0s-Skin-1.0", 10
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.Skin = MINOR

--- The stored value that means "take this setting from the skin" (the owner's ruling R3). A
--- profile key holding it resolves through `Resolve` to the owner's skin token.
lib.FROM_SKIN = "@skin"
--- The skin every owner wears until it chooses another, and the one an unknown key falls back to.
lib.DEFAULT = "ka0s"
--- The two skin sources: Ka0s's own skins, or EllesmereUI's (SkinEUI.lua).
lib.SOURCES = { "ka0s", "eui" }

-- The vocabulary the facade carries as trampolines into lib.prim: EllesmereUI's names first (its
-- SKINNING_API facade, API version 3), then the Ka0s extras.
lib.VOCAB = {
  "Shell", "Panel", "Inset", "FadeRegions", "FadeNineSlice", "Button", "WhiteButtonLabel",
  "StateButtonLabel", "EditBox", "Checkbox", "Dropdown", "ScrollBar", "Tab", "SetTabSelection",
  "CloseButton", "PageButton", "SquareIcon", "SortHeaderBar", "Font", "White", "ApplyBarFill",
  "GetAccentColor", "GetPanelColor", "GetFont",
  "TitleBar", "Divider", "Footer", "Card", "Slider", "NavItem", "Drawer", "ListRow", "MenuFrame",
  "Tooltip", "Strip", "Cover", "Text", "ChartStyle", "BarStyle", "IconBorder", "GlowColor",
  "BarTexture", "FontFlags", "HudFontSize",
}

local WEAK_KEYS = { __mode = "k" }

lib.skins    = lib.skins or {}
lib.__order    = lib.__order or {}
lib.owners   = lib.owners or {}
lib.painted  = lib.painted or setmetatable({}, WEAK_KEYS)
lib.byOwner  = lib.byOwner or {}
lib.facades  = lib.facades or {}
lib.prim     = lib.prim or {}
-- Owners EllesmereUI painted this session (SkinEUI.lua writes it; its paint is one-way).
lib.euiPainted = lib.euiPainted or {}
-- The last first-paint stamp handed out: a record's `seq` orders the frames a repaint replays.
lib.__paintSeq = lib.__paintSeq or 0
-- The resolved token tables, one per skin key. A cache, rebuilt on demand: emptied here so a newer
-- minor's resolution rules apply, and by RegisterSkin because a skin derives from Ka0s Default.
lib.__resolved = {}
-- Each owner's token table with its overrides over it, `{ base, font, texture, t }`. A cache like
-- `__resolved`, emptied on load so a newer minor's override rules apply.
lib.__overTok = {}
-- Each owner's token table with its owner tokens over it, `{ from, key, gen, t }` (minor 7). A cache
-- like `__overTok`, emptied on load.
lib.__ownTok = {}
-- Each owner's token table with its font outline mode applied, `{ from, mode, t }` (minor 9). A cache
-- like `__overTok`, emptied on load.
lib.__outTok = {}
-- The owner token names refused per owner, `[owner][name] = why`, so each is logged once. Kept across
-- minors: a newer copy re-registering the same bad name must not log it again.
lib.__tokRefused = lib.__tokRefused or {}

local SOURCE_OK = { ka0s = true, eui = true }
-- The font outline modes (minor 9; `lib.OUTLINE_MODES`, below, is their order).
local OUTLINE_OK = { all = true, hud = true, off = true }

--- Hand `err` to the client's error handler and carry on: one raising listener or primitive must
--- not stop the repaint of every frame after it.
local function report(err)
  local h = type(geterrorhandler) == "function" and geterrorhandler()
  if type(h) == "function" then h(err) end
end

local function requireOwner(owner, what)
  if type(owner) ~= "string" or owner == "" then
    error(MAJOR .. ": " .. what .. " needs an owner (the addon folder name)", 3)
  end
end

-- ── skins ────────────────────────────────────────────────────────────────────────────────────

--- Register a skin: `{ key, label, desc, swatches = { 4 hex }, tokens = {...} }`. A second
--- registration of a key replaces the first (a newer SkinDefs.lua re-registering its skins).
--- Answers the stored definition.
function lib:RegisterSkin(def)
  if type(def) ~= "table" or type(def.key) ~= "string" or def.key == "" then
    error(MAJOR .. ": RegisterSkin needs a table with a string key", 2)
  end
  if type(def.tokens) ~= "table" then
    error(MAJOR .. ": RegisterSkin('" .. def.key .. "') needs a tokens table", 2)
  end
  if not self.skins[def.key] then self.__order[#self.__order + 1] = def.key end
  def.label = type(def.label) == "string" and def.label or def.key
  def.desc = type(def.desc) == "string" and def.desc or ""
  def.swatches = type(def.swatches) == "table" and def.swatches or {}
  self.skins[def.key] = def
  self.__resolved = {}
  return def
end

--- The registered definition for `key`, or nil.
function lib:GetSkin(key)
  return self.skins[key]
end

--- Every registered skin's definition, in registration order (Ka0s Default first). A fresh array
--- of the stored definitions: read `key`, `label`, `desc` and `swatches`, never write them.
function lib:Skins()
  local out = {}
  for _, key in ipairs(self.__order) do
    if self.skins[key] then out[#out + 1] = self.skins[key] end
  end
  return out
end

--- The schema kind of a token name, or nil (lib.SCHEMA, from SkinDefs.lua).
local function kindOf(name)
  local idx = lib.__schemaIndex
  local entry = idx and idx[name]
  return entry and entry.kind
end

local function overlay(out, tokens)
  for name, v in pairs(tokens) do out[name] = v end
end

-- `false` is how a skin says "none" for a token Ka0s Default sets (a skin with no inner rule);
-- it resolves to nil. A bool token keeps its false.
local function dropNone(out)
  for name, v in pairs(out) do
    if v == false and kindOf(name) ~= "bool" then out[name] = nil end
  end
end

--- The skin key a choice actually draws: the key itself when registered, else Ka0s Default.
local function effectiveKey(key)
  if type(key) == "string" and lib.skins[key] then return key end
  return lib.DEFAULT
end

--- The complete token table of a skin: Ka0s Default's tokens with the skin's own over them. An
--- unregistered key resolves as Ka0s Default. Cached; the table is shared, so never write to it.
function lib:ResolveSkin(key)
  key = effectiveKey(key)
  local out = self.__resolved[key]
  if out then return out end
  out = {}
  local base = self.skins[self.DEFAULT]
  if base then overlay(out, base.tokens) end
  if key ~= self.DEFAULT and self.skins[key] then overlay(out, self.skins[key].tokens) end
  dropNone(out)
  self.__resolved[key] = out
  return out
end

-- ── owners and their choice ──────────────────────────────────────────────────────────────────

--- Read a host getter's answer: `{ source, skin }`, or two values.
local function readChoice(get)
  if type(get) ~= "function" then return end
  local ok, a, b = pcall(get)
  if not ok then report(a); return end
  if type(a) == "table" then return a.source or a[1], a.skin or a[2] end
  return a, b
end

local function cleanSource(source)
  if SOURCE_OK[source] then return source end
  return "ka0s"
end

local function cleanSkin(skin)
  if type(skin) == "string" and skin ~= "" then return skin end
  return lib.DEFAULT
end

--- An override's stored form: a non-empty string key, else nil ("the skin's own"). The FROM_SKIN
--- sentinel is "the skin's own" too, as everywhere else it is stored.
local function mediaKey(v)
  if type(v) == "string" and v ~= "" and v ~= lib.FROM_SKIN then return v end
  return nil
end

local function fnOr(v, old)
  if type(v) == "function" then return v end
  return old
end

--- Take a registration's hooks onto the owner's record, keeping any it leaves out.
local function takeHooks(o, opts, owner)
  o.reloads = o.reloads or {}
  o.get, o.set, o.log = fnOr(opts.get, o.get), fnOr(opts.set, o.set), fnOr(opts.log, o.log)
  o.label = type(opts.label) == "string" and opts.label or o.label or owner
end

-- ── owner tokens (minor 7) ───────────────────────────────────────────────────────────────────

--- True when `name` is a library token (a `lib.SCHEMA` name). With no SkinDefs.lua loaded nothing is.
local function isSchemaName(name)
  local idx = lib.__schemaIndex
  return idx ~= nil and idx[name] ~= nil
end

--- True when `ns` (a name's first dotted segment) is a library token family (`text`, `sem`,
--- `gtip`, ...: the first segment of any `lib.SCHEMA` name), so a later SkinDefs minor may add a
--- library token under it. The set is built once per schema index.
local function isFamily(ns)
  local idx = lib.__schemaIndex
  if idx == nil then return false end
  if lib.__famFrom ~= idx then
    local fam = {}
    for n in pairs(idx) do fam[n:match("^[^%.]+")] = true end
    lib.__fam, lib.__famFrom = fam, idx
  end
  return lib.__fam[ns] == true
end

--- Why `name` cannot be an owner token's name, or nil: it needs a dot inside it, and its namespace
--- is never a library token family, so no later library token can take it.
local function nameProblem(name)
  if type(name) ~= "string" or not name:find("^[^%.].*%.") or name:sub(-1) == "." then
    return "a name carries the owner's namespace and a dot (\"dw.upgrade\")"
  end
  local ns = name:match("^[^%.]+")
  if isSchemaName(name) or isFamily(ns) then return "its namespace, " .. ns .. ", is a library token family" end
  return nil
end

-- The Lua type a schema kind's value has.
local KIND_TYPE = { color = "table", colors = "table", string = "string", number = "number", bool = "boolean" }

--- Why `def` cannot be an owner token's definition, or nil. A `follow` token's kind must agree
--- with the default's type (a color never follows `font.body`).
local function defProblem(def)
  if type(def) ~= "table" then return "the definition is not a table { default, follow, skins }" end
  if def.default == nil then return "it has no default (Ka0s Default's value)" end
  local follow = def.follow
  if follow ~= nil and not (type(follow) == "string" and (lib.__schemaIndex == nil or isSchemaName(follow))) then
    return "follow names no library token"
  end
  local want = follow and KIND_TYPE[kindOf(follow)]
  if want and want ~= type(def.default) then
    return "follow is a " .. kindOf(follow) .. " token and the default a " .. type(def.default)
  end
  if def.skins ~= nil and type(def.skins) ~= "table" then return "skins is not a table" end
  return nil
end

--- Why owner token `name` with definition `def` cannot be taken, or nil when it can.
local function tokenProblem(name, def)
  return nameProblem(name) or defProblem(def)
end

--- Refuse owner token `name` and log it once per owner and name: through the owner's `opts.log`
--- when it gave one, else to the client's error handler.
local function refuseToken(o, owner, name, why, verb)
  local seen = lib.__tokRefused[owner] or {}
  lib.__tokRefused[owner] = seen
  local key = tostring(name)
  if seen[key] then return end
  seen[key] = why
  local line = MAJOR .. ": " .. owner .. " token " .. key .. " " .. (verb or "refused") .. ": " .. why
  if type(o.log) ~= "function" then return report(line) end
  local ok, err = pcall(o.log, line)
  if not ok then report(err) end
end

--- A definition's `skins` as taken: an entry whose value's type is not the default's is refused
--- (logged once, the rest kept); a key no registered skin carries is kept, for a skin registered
--- later, and logged once, since it is most often a misspelling.
local function takeSkins(o, owner, name, def)
  if def.skins == nil then return nil end
  local out, want = {}, type(def.default)
  for k, v in pairs(def.skins) do
    local at = name .. ".skins." .. tostring(k)
    if v ~= false and type(v) ~= want then
      refuseToken(o, owner, at, "the value is a " .. type(v) .. " and the default a " .. want)
    else
      if not lib.skins[k] then refuseToken(o, owner, at, "no registered skin has this key", "kept") end
      out[k] = v
    end
  end
  return out
end

--- Take a registration's owner tokens onto the record: each good name added or replaced, each bad
--- one refused. Nothing when `tokens` is not a table.
local function takeTokens(o, owner, tokens)
  if type(tokens) ~= "table" then return end
  o.tokens = o.tokens or {}
  for name, def in pairs(tokens) do
    local why = tokenProblem(name, def)
    if why then
      refuseToken(o, owner, name, why)
    else
      o.tokens[name] = { default = def.default, follow = def.follow, skins = takeSkins(o, owner, name, def) }
    end
  end
  o.tokGen = (o.tokGen or 0) + 1
end

--- True when `name` names a token `owner` can read: a library token, or one of the owner's own
--- tokens. Anything else (a name no token carries, or a value where a name belongs) answers false,
--- logged once per owner, `where` and name (opts.log, else the client's error handler). The question
--- a primitive's `opts.tokens` remap asks of each slot (SkinPaint minor 11). Internal.
function lib:__RemapName(owner, name, where)
  local o = self.owners[owner]
  if type(name) == "string" then
    if self.__schemaIndex == nil or isSchemaName(name) then return true end
    if o and o.tokens and o.tokens[name] then return true end
  end
  if o then
    local label = tostring(where) .. " " .. (type(name) == "string" and name or "<" .. type(name) .. ">")
    refuseToken(o, owner, label, "the remap names no token (a library or owner token NAME)")
  end
  return false
end

--- Register `owner` (the addon folder name) at the consumer's file load. `opts.get()` answers the
--- profile's `{ source, skin }`; `opts.set(source, skin, ignore, media)` writes it (copy to every
--- Ka0s addon; `ignore` (minor 5) `{ panel, fonts }` or nil, `media` (minor 6) `{ font, texture,
--- outline }` or nil, its `outline` (minor 9) a mode or nil the host stores and restores with
--- `SetOutline`, see WriteChoice); `opts.label` names the addon to the player; `opts.log(line)`,
--- optional, takes the one line the EllesmereUI provider writes when it refuses or stops
--- (SkinEUI.lua). The choice is read once, here; afterwards it moves only through `SetChoice`. A
--- second call updates the hooks and keeps the applied choice. Answers the owner's facade.
--- `opts.tokens` (minor 7), optional, is the owner's own tokens, `{ ["<ns>.<name>"] = { default =
--- <Ka0s Default's value>, follow = "<library token>", skins = { [<skin key>] = <value>|false } } }`:
--- read through `Token`, `Color`, the facade and any primitive opt that names a token, like a library
--- token. A name carries the owner's namespace and a dot, never a library token family's (`text`,
--- `sem`, ...); a bad name or definition is refused and logged once (`opts.log`, else the client's error handler), and the
--- rest still land. A second call adds its tokens and replaces a name it repeats; it does not repaint,
--- so register them at file load, before the first paint.
function lib:RegisterOwner(owner, opts)
  requireOwner(owner, "RegisterOwner")
  opts = type(opts) == "table" and opts or {}
  local o = self.owners[owner]
  if not o then
    local source, skin = readChoice(opts.get)
    o = { source = cleanSource(source), skin = cleanSkin(skin), listeners = {}, reloads = {} }
    self.owners[owner] = o
  end
  takeHooks(o, opts, owner)
  takeTokens(o, owner, opts.tokens)
  local hook = self.__euiOnOwner
  if type(hook) == "function" then
    local ok, err = pcall(hook, owner)
    if not ok then report(err) end
  end
  return self:For(owner)
end

--- True only for an owner that called RegisterOwner. Every factory that takes an owner paints
--- today's way, verbatim, for a name that is not one.
function lib:IsOwner(owner)
  return type(owner) == "string" and self.owners[owner] ~= nil
end

--- The registered owners, sorted.
function lib:Owners()
  local out = {}
  for name in pairs(self.owners) do out[#out + 1] = name end
  table.sort(out)
  return out
end

--- The label `owner` registered with (`opts.label`, else its folder name), or nil for a name that
--- never called RegisterOwner. What the Appearance tab's copy confirmation names each addon by.
function lib:OwnerLabel(owner)
  local o = self.owners[owner]
  return o and o.label or nil
end

--- Write (source, skin) into `owner`'s profile through the setter it registered (`opts.set`), under
--- pcall: the write of the Appearance tab's copy to every Ka0s addon, which reaches each addon only
--- through its own write seam. `ignore` (minor 5), optional, is `{ panel = bool, fonts = bool }`
--- and reaches the setter as its third argument; a setter written before minor 5 ignores it. Never
--- moves the applied choice (SetChoice and SetIgnore do). `media` (minor 6), optional, is
--- `{ font = key|false, texture = key|false }` and reaches the setter as its fourth argument, each
--- half an LSM key or false for "the skin's own"; a setter written before minor 6 ignores it, and
--- it never moves the applied overrides (SetOverride does). `media.outline` (minor 9), optional, one
--- of `OUTLINE_MODES` (else nil: left alone), never moves the applied mode (SetOutline does); a caller
--- writing it passes both overrides too, as a minor-6 setter stores both halves of any `media`.
--- Answers true when a setter ran and did not raise; false for an unregistered owner, one with no
--- setter, or a raise (handed to the client's error handler).
function lib:WriteChoice(owner, source, skin, ignore, media)
  local o = self.owners[owner]
  if not o or type(o.set) ~= "function" then return false end
  if type(ignore) == "table" then ignore = { panel = ignore.panel == true, fonts = ignore.fonts == true }
  else ignore = nil end
  if type(media) == "table" then
    media = { font = mediaKey(media.font) or false, texture = mediaKey(media.texture) or false,
              outline = OUTLINE_OK[media.outline] and media.outline or nil }
  else media = nil end
  local ok, err = pcall(o.set, cleanSource(source), cleanSkin(skin), ignore, media)
  if not ok then report(err); return false end
  return true
end

--- The owner's applied choice: source, skin. An unregistered owner answers "ka0s", "ka0s".
function lib:GetChoice(owner)
  local o = self.owners[owner]
  if not o then return "ka0s", self.DEFAULT end
  return o.source, o.skin
end

--- True once the owner needs a reload: it left the `eui` source, or a gate condition failed, after
--- EllesmereUI painted it this session. EllesmereUI's paint is one-way, so only a reload removes it.
function lib:PendingReload(owner)
  local o = self.owners[owner]
  return o ~= nil and o.pendingReload == true
end

--- Fire the owner's OnLooksChanged listeners, each under pcall.
local function notify(o)
  for _, fn in ipairs(o.listeners) do
    local ok, err = pcall(fn, o.source, o.skin)
    if not ok then report(err) end
  end
end

-- The override field each LibSharedMedia kind feeds.
local OVERRIDE_FIELD = { font = "font", statusbar = "texture" }

--- LibSharedMedia registered `key` of `kind` (its `LibSharedMedia_Registered` callback): repaint and
--- notify every owner whose override names that key, unless a reload is pending, since until now its
--- tokens fell back to the skin's own. Internal. Answers how many owners repainted.
function lib:__MediaRegistered(kind, key)
  local field = OVERRIDE_FIELD[kind]
  if not field or type(key) ~= "string" then return 0 end
  local n = 0
  for owner, o in pairs(self.owners) do
    if o[field] == key and not o.pendingReload then
      self:Repaint(owner)
      notify(o)
      n = n + 1
    end
  end
  return n
end

--- For SkinEUI.lua: fire `owner`'s OnLooksChanged listeners (EllesmereUI painted it, or its looks
--- changed live).
function lib:__NotifyLooks(owner)
  local o = self.owners[owner]
  if o then notify(o) end
end

--- Set `owner`'s pending-reload flag and, the first time, fire its OnReloadRequest listeners, each
--- under pcall. Answers true only on the call that set the flag. SetChoice and SkinEUI.lua call it.
function lib:__RequestReload(owner)
  local o = self.owners[owner]
  if not o or o.pendingReload then return false end
  o.pendingReload = true
  for _, fn in ipairs(o.reloads or {}) do
    local ok, err = pcall(fn, owner)
    if not ok then report(err) end
  end
  return true
end

local function addListener(list, fn)
  for _, have in ipairs(list) do
    if have == fn then return fn end
  end
  list[#list + 1] = fn
  return fn
end

--- Call `fn(owner)` once, when `owner` first needs a reload (`PendingReload` turns true): on the
--- switch SetChoice answers `reload = true` for, or when a gate condition fails after EllesmereUI
--- painted it. A caller raises its reload popup from this or from SetChoice's answer, not both.
--- Registering the same function twice keeps one entry. Answers fn.
function lib:OnReloadRequest(owner, fn)
  requireOwner(owner, "OnReloadRequest")
  local o = self.owners[owner]
  if not o or type(fn) ~= "function" then return end
  o.reloads = o.reloads or {}
  return addListener(o.reloads, fn)
end

--- A move onto `eui`, handed to SkinEUI.lua's slot: answers handled, reload. Handled is true when
--- EllesmereUI painted the owner on this call, or its gate closed after an earlier paint (then the
--- reload is asked for); otherwise SetChoice repaints as for any change.
function lib:__EUIChoice(owner, source)
  local hook = source == "eui" and self.__euiOnChoice
  if type(hook) ~= "function" then return false, false end
  local handled = hook(owner)
  if handled == "reload" then return true, self:__RequestReload(owner) end
  return handled == true, false
end

--- Move `owner` to (source, skin); nil keeps that half. Idempotent: a choice equal to GetChoice
--- does nothing. Otherwise the new skin is resolved first, every frame recorded for the owner is
--- repainted, and the owner's OnLooksChanged listeners fire. Leaving `eui` after EllesmereUI painted
--- the owner cannot repaint (its paint is one-way): the choice is stored, the owner's pending-reload
--- flag is set, and nothing is repainted. Leaving an `eui` EllesmereUI never painted is an ordinary
--- change: the owner was wearing its Ka0s skin all along. Moving onto `eui` hands the paint to
--- SkinEUI.lua when it is loaded, which paints with EllesmereUI when its gate holds and otherwise
--- leaves the owner on its Ka0s skin. Never writes the host's profile.
--- Answers changed, reload: `reload` is true exactly once per owner, on the switch that first
--- needs a reload, so a caller raises its reload popup at most once.
function lib:SetChoice(owner, source, skin)
  requireOwner(owner, "SetChoice")
  local o = self.owners[owner]
  if not o then return false, false end
  source = source == nil and o.source or cleanSource(source)
  skin = skin == nil and o.skin or cleanSkin(skin)
  if source == o.source and skin == o.skin then return false, false end
  local leavingEUI = o.source == "eui" and source ~= "eui"
  o.source, o.skin = source, skin
  self:ResolveSkin(skin)
  if leavingEUI and self.euiPainted[owner] then return true, self:__RequestReload(owner) end
  if o.pendingReload then return true, false end
  local handled, reload = self:__EUIChoice(owner, source)
  if handled then return true, reload end
  self:Repaint(owner)
  notify(o)
  return true, false
end

-- ── the owner's two exceptions ───────────────────────────────────────────────────────────────

--- The owner's exceptions: ignorePanel (its settings panel stays the client's), ignoreFonts (every
--- string keeps the face and size it was given). false, false for an unregistered owner.
function lib:GetIgnore(owner)
  local o = self.owners[owner]
  if not o then return false, false end
  return o.ignorePanel == true, o.ignoreFonts == true
end

--- Set `owner`'s exceptions; nil keeps that half. Never writes the host's profile (WriteChoice's
--- third argument does). A change repaints every frame recorded for the owner and fires its
--- OnLooksChanged listeners, so both apply live: fonts go back or come back, and the Options
--- instance hands its chrome back as it was and re-renders its pages (OptionsScroll minor 7).
--- Answers changed, reload; `reload` is always false (kept so a caller's two-value read holds).
function lib:SetIgnore(owner, panel, fonts)
  requireOwner(owner, "SetIgnore")
  local o = self.owners[owner]
  if not o then return false, false end
  if panel == nil then panel = o.ignorePanel == true else panel = panel == true end
  if fonts == nil then fonts = o.ignoreFonts == true else fonts = fonts == true end
  if panel == (o.ignorePanel == true) and fonts == (o.ignoreFonts == true) then return false, false end
  o.ignorePanel, o.ignoreFonts = panel, fonts
  if not o.pendingReload then
    self:Repaint(owner)
    notify(o)
  end
  return true, false
end

--- True while `owner`'s settings panel is to be painted (a registered owner whose ignorePanel is
--- off); the Options chrome and the AceGUI rows ask it before they paint. Internal.
function lib:__PanelSkinned(owner)
  local o = self.owners[owner]
  return o ~= nil and not o.ignorePanel
end

--- True when `owner` ignores fonts: P.font gives every string back its own face. Internal.
function lib:__FontsIgnored(owner)
  local o = self.owners[owner]
  return o ~= nil and o.ignoreFonts == true
end

-- The HUD's two font tokens: while the owner ignores fonts, the stored value wins for them in
-- `Resolve` and `Token` (minor 8, R-1). `hud.fontSize` is out of scope; `__Tokens` is unchanged,
-- since P.font already hands every painted string back through `__FontsIgnored`.
local HUD_FONT = { ["hud.font"] = true, ["hud.outline"] = true }

local function hudFontIgnored(self, owner, name)
  return HUD_FONT[name] == true and self:__FontsIgnored(owner)
end

-- ── the owner's font outline (minor 9) ───────────────────────────────────────────────────────

--- Where the skin's font flags apply for an owner (the Skin tab's "Font outline", D-06), in the tab's
--- order: "all", every string painted for the owner but the mono role, and the HUD; "hud" (the
--- default), the HUD only (`hud.outline`); "off", neither.
lib.OUTLINE_MODES = { "all", "hud", "off" }
lib.OUTLINE_DEFAULT = "hud"
-- The tokens each mode answers "" for in `__Tokens`; "all" leaves both as the skin states them.
local OUTLINE_DROP = { hud = { "font.outline" }, off = { "font.outline", "hud.outline" } }

--- The owner's font outline mode, one of `OUTLINE_MODES`: `OUTLINE_DEFAULT` ("hud") for an owner
--- that never set one and for an unregistered owner.
function lib:GetOutline(owner)
  local o = self.owners[owner]
  return o and o.outline or self.OUTLINE_DEFAULT
end

--- The mode `owner` stored, or nil for one that never moved off the default. Internal: a media write
--- carries this, not `GetOutline`, so the default stays a default in the host's profile.
function lib:__StoredOutline(owner)
  local o = self.owners[owner]
  return o and o.outline or nil
end

--- Put `owner`'s font outline back to never having been set: `OUTLINE_DEFAULT`, repainting as
--- SetOutline does, and nothing stored. Internal: the skin picker's dismissal undoes a preview, and
--- a default left stored would pin that owner when the default moves (`__StoredOutline`).
function lib:__ClearOutline(owner)
  self:SetOutline(owner, self.OUTLINE_DEFAULT)
  local o = self.owners[owner]
  if o then o.outline = nil end
end

--- Set `owner`'s font outline mode; a value not in `OUTLINE_MODES` (nil included) is `OUTLINE_DEFAULT`.
--- Idempotent. Never writes the host's profile (WriteChoice's `media.outline` does). A change
--- repaints every frame recorded for the owner and fires its OnLooksChanged listeners, unless a
--- reload is pending. "Ignore fonts" wins: P.font gives every string its own font, and `Token`
--- leaves `hud.outline` alone, whatever the mode. Answers changed.
function lib:SetOutline(owner, mode)
  requireOwner(owner, "SetOutline")
  local o = self.owners[owner]
  if not o then return false end
  if not OUTLINE_OK[mode] then mode = self.OUTLINE_DEFAULT end
  if mode == (o.outline or self.OUTLINE_DEFAULT) then return false end
  o.outline = mode
  if not o.pendingReload then
    self:Repaint(owner)
    notify(o)
  end
  return true
end

-- ── the owner's font and texture ─────────────────────────────────────────────────────────────

--- The owner's overrides: font, texture, each an LSM key (a `font` and a `statusbar` key), or nil
--- for "the skin's own". nil, nil for an unregistered owner.
function lib:GetOverride(owner)
  local o = self.owners[owner]
  if not o then return nil, nil end
  return o.font, o.texture
end

--- One half of SetOverride: nil keeps `old`, false or "" clears it, a string key sets it.
local function nextOverride(v, old)
  if v == nil then return old end
  return mediaKey(v)
end

--- Set `owner`'s font and texture overrides (the Appearance tab's "Font and texture"); nil keeps
--- that half, false, "" or FROM_SKIN clears it. Idempotent. An override LibSharedMedia cannot
--- resolve is kept (GetOverride answers it) but leaves the skin's own token in place until a media
--- pack registers the key, which repaints the owner. A font override replaces `font.body`,
--- `font.title` and `hud.font` (`font.mono` and every size stay the skin's); a texture override
--- replaces `bar.texture`. "Ignore fonts" wins over a font override: P.font gives every string its
--- own face either way. Never writes the host's profile (WriteChoice's fourth argument does). A
--- change repaints every frame recorded for the owner and fires its OnLooksChanged listeners,
--- unless a reload is pending. Answers changed.
function lib:SetOverride(owner, font, texture)
  requireOwner(owner, "SetOverride")
  local o = self.owners[owner]
  if not o then return false end
  font, texture = nextOverride(font, o.font), nextOverride(texture, o.texture)
  if font == o.font and texture == o.texture then return false end
  o.font, o.texture = font, texture
  if not o.pendingReload then
    self:Repaint(owner)
    notify(o)
  end
  return true
end

--- Call `fn(source, skin)` after each change of the owner's skin. Registering the same function
--- twice keeps one entry. Answers fn.
function lib:OnLooksChanged(owner, fn)
  requireOwner(owner, "OnLooksChanged")
  if type(fn) ~= "function" then return end
  local o = self.owners[owner]
  if not o then return end
  return addListener(o.listeners, fn)
end

-- ── tokens ───────────────────────────────────────────────────────────────────────────────────

-- The one LibSharedMedia subscription, kept across minors. CallbackHandler keeps one callback per
-- (event, target), and the callback reaches `lib` at call time, so a newer minor need not redo it.
lib.__mediaSub = lib.__mediaSub or {}

local function subscribeMedia(LSM)
  local sub = lib.__mediaSub
  if sub.lsm == LSM or type(LSM.RegisterCallback) ~= "function" then return end
  local ok = pcall(LSM.RegisterCallback, sub, "LibSharedMedia_Registered", function(_, kind, key)
    lib:__MediaRegistered(kind, key)
  end)
  if ok then sub.lsm = LSM end
end

--- True when `key` of `kind` resolves to a file: a path, or a key LibSharedMedia has (SkinPaint's
--- P.media rule). Subscribes to late registrations the first time it asks LibSharedMedia.
local function resolves(kind, key)
  if key:find("\\", 1, true) then return true end
  local LSM = LibStub("LibSharedMedia-3.0", true)
  if not (LSM and type(LSM.Fetch) == "function") then return false end
  subscribeMedia(LSM)
  return LSM:Fetch(kind, key, true) ~= nil
end

--- `t` with `face`'s sizes over its own (minor 10, D-07): the row SkinDefs measured for a shipped
--- face, so an override of it is as wide as Ka0s Default's text. Any other face, nil included, takes
--- Ka0s Default's sizes, which is every stored size unscaled: no client can measure it, and the
--- skin's sizes were measured for the skin's own face.
local function layFaceSizes(t, face)
  local rows = lib.__FACE_SIZES
  if not rows then return end
  local row = rows[face]
  if row then
    t["font.bodySize"], t["font.titleSize"], t["hud.fontSize"] = row[1], row[2], row[3]
    return
  end
  local ref = lib:ResolveSkin(lib.DEFAULT)
  t["font.bodySize"], t["font.titleSize"], t["hud.fontSize"] =
    ref["font.bodySize"], ref["font.titleSize"], ref["hud.fontSize"]
end

-- LibSharedMedia's locale groups; every other locale is "western".
local LOCALE_GROUP = { ruRU = "ruRU", koKR = "koKR", zhCN = "zhCN", zhTW = "zhTW" }

--- True for a shipped face this client's locale keeps out of LibSharedMedia (Media's `langmask`), so
--- it can never draw here. Static, so it needs no late-registration handling; a key Media does not
--- ship answers false.
local function faceRefused(face)
  local Media = LibStub("LibKa0s-Media-1.0", true)
  local entry = Media and Media.FONTS and Media.FONTS[face]
  if not (entry and entry.langmask and type(GetLocale) == "function") then return false end
  local group = LOCALE_GROUP[GetLocale()] or "western"
  for _, allowed in ipairs(entry.langmask) do
    if allowed == group then return false end
  end
  return true
end

--- `owner`'s font and texture overrides, each nil unless it resolves.
local function ownerMedia(owner)
  local o = lib.owners[owner]
  local font, texture = o and o.font, o and o.texture
  if font and not resolves("font", font) then font = nil end
  if texture and not resolves("statusbar", texture) then texture = nil end
  return font, texture
end

--- A copy of `base` with the overrides and their sizes on it.
local function layOverrides(base, font, texture, refused)
  local t = {}
  overlay(t, base)
  if font then
    t["font.body"], t["font.title"], t["hud.font"] = font, font, font
    layFaceSizes(t, font)
  elseif refused then
    layFaceSizes(t, nil)
  end
  if texture then t["bar.texture"] = texture end
  return t
end

--- `base` with `owner`'s overrides over it (minor 6): `base` itself when the owner sets none, so
--- Ka0s Default reads unchanged, else a derived copy cached on (base, font, texture). An override
--- that does not resolve is left out, so the skin's own face or texture stands rather than the
--- client's stock font or the flat bar (a media pack removed, or one that registers later). A font
--- override brings its face's sizes where SkinDefs has them, else Ka0s Default's, and with no font
--- override a skin whose own face this locale refuses takes Ka0s Default's too (minor 10). A nil
--- owner has no cache slot, so it gets the copy uncached.
local function withOverrides(owner, base)
  local font, texture = ownerMedia(owner)
  local refused = not font and (faceRefused(base["font.body"]) or faceRefused(base["hud.font"]))
  if not font and not texture and not refused then return base end
  local c = lib.__overTok[owner]
  if c and c.base == base and c.font == font and c.texture == texture then return c.t end
  local t = layOverrides(base, font, texture, refused)
  if owner == nil then return t end
  lib.__overTok[owner] = { base = base, font = font, texture = texture, t = t }
  return t
end

--- `t` with `owner`'s font outline mode applied (minor 9), the mode `GetOutline` answers: `t` itself
--- under "all" and with no owner named, else a derived copy, cached on (t, mode), whose dropped
--- tokens answer "".
local function withOutline(owner, t)
  if owner == nil then return t end
  local mode = lib:GetOutline(owner)
  local drop = OUTLINE_DROP[mode]
  if not drop then return t end
  local c = lib.__outTok[owner]
  if c and c.from == t and c.mode == mode then return c.t end
  local out = {}
  overlay(out, t)
  for _, name in ipairs(drop) do out[name] = "" end
  lib.__outTok[owner] = { from = t, mode = mode, t = out }
  return out
end

--- The owner's base table and the key its owner tokens resolve by: "eui" while EllesmereUI paints
--- the owner, else the skin key it draws.
local function baseOf(owner)
  local hook = lib.__euiTokens
  local t = type(hook) == "function" and hook(owner) or nil
  if t then return t, "eui" end
  local _, skin = lib:GetChoice(owner)
  local key = effectiveKey(skin)
  return lib:ResolveSkin(key), key
end

--- The owner's token table without its overrides (minor 6) or its owner tokens (minor 7): its skin
--- resolved (`ResolveSkin`), or, while EllesmereUI paints the owner, the table SkinEUI.lua derives
--- from EllesmereUI's accent, panel color and font. What the Skin tab's "Skin's default" entries name.
--- Shared: never write to it. Internal.
function lib:__BaseTokens(owner)
  return (baseOf(owner))
end

--- The key `owner` draws by: "eui" while EllesmereUI paints it (its derived tokens, the library's
--- technique when EllesmereUI is refused included), else the skin key it wears (`lib.DEFAULT` for
--- Ka0s Default, for a key no skin registers, and for an owner on `eui` before EllesmereUI paints
--- it: the live fallback). An unregistered owner answers `lib.DEFAULT`. Minor 7 (LK-05 of the
--- skinning rollout); public since minor 8 (R-9), lib-level and never a facade member.
function lib:DrawsKey(owner)
  local _, key = baseOf(owner)
  return key
end
--- Minor 7's internal name, kept one release as an alias for a copy or test that still names it.
lib.__DrawsKey = lib.DrawsKey

--- One owner token's value under `key` (a skin key, or "eui"), reading the follow token from `t`.
--- Ka0s Default answers the default, unless the owner's font or texture override moved the follow
--- token (`t` against the un-overridden `base`): then the override; a skin its own entry (`false` is
--- none, unless the token is a bool); otherwise, and always under eui, the follow token's value,
--- else the default.
local function ownValue(def, key, t, base)
  if key == lib.DEFAULT then
    local f = def.follow and t[def.follow]
    if f ~= nil and f ~= base[def.follow] then return f end
    return def.default
  end
  local v
  if key ~= "eui" and def.skins then v = def.skins[key] end
  if v ~= nil and v ~= false then return v end
  if v == false then
    if type(def.default) == "boolean" then return false end
    return nil
  end
  local f = def.follow and t[def.follow]
  if f ~= nil then return f end
  return def.default
end

--- `t` with `owner`'s owner tokens over it (minor 7): `t` itself when the owner registered none,
--- else a derived copy cached on (t, key, the owner's token generation). `base` is `t` without the
--- overrides.
local function withOwnTokens(owner, t, key, base)
  local o = lib.owners[owner]
  local own = o and o.tokens
  if not own or next(own) == nil then return t end
  local c = lib.__ownTok[owner]
  if c and c.from == t and c.key == key and c.gen == o.tokGen then return c.t end
  local out = {}
  overlay(out, t)
  for name, def in pairs(own) do out[name] = ownValue(def, key, t, base) end
  lib.__ownTok[owner] = { from = t, key = key, gen = o.tokGen, t = out }
  return out
end

--- The owner's complete token table: `__BaseTokens`, with the owner's font and texture overrides
--- over it (minor 6) where they resolve, its font outline mode applied (minor 9), and its owner
--- tokens over that (minor 7). Shared: never write to it. An unregistered owner reads Ka0s Default.
--- Internal (SkinPaint.lua's P.T and `Token` read it); a host reads tokens through `Token` and `Color`.
function lib:__Tokens(owner)
  local base, key = baseOf(owner)
  return withOwnTokens(owner, withOutline(owner, withOverrides(owner, base)), key, base)
end

--- The owner's resolved token `name` (from `__Tokens`): a color is `{ r, g, b, a }`, shared, never
--- written to. An unregistered owner reads Ka0s Default. nil for a token the skin leaves alone,
--- which `hud.font` and `hud.outline` are while the owner ignores fonts (minor 8, R-1).
function lib:Token(owner, name)
  if hudFontIgnored(self, owner, name) then return nil end
  return self:__Tokens(owner)[name]
end

--- The owner's color token as r, g, b, a (alpha 1 when the token has three components), or nil.
function lib:Color(owner, name)
  local c = self:Token(owner, name)
  if type(c) ~= "table" then return nil end
  return c[1], c[2], c[3], c[4] or 1
end

-- A remapped slot whose named token resolves to nil: the view answers nil, not the primitive's own.
local NONE = {}

local function orNone(v) if v == nil then return NONE end return v end

--- `T` seen through a caller's slot remap (LK-02; SkinPaint minor 11's P.remap): `tokens` is the
--- caller's `opts.tokens`, `{ [slot] = token name }`; `slots` maps each slot the primitive has to the
--- library token it paints from; `fills` names the slots that are fills, whose `<token>Top` /
--- `<token>Bottom` gradient pair follows the named token's (none when it has none). A slot whose
--- name is not a token the owner can read, or whose token is not a color (`bar.texture`), is left
--- as it was and logged once (`__RemapName`, from `where`). Answers `T` itself when nothing is remapped, else a read-only view over it. Internal.
function lib:__Remap(owner, T, tokens, slots, fills, where)
  if type(tokens) ~= "table" or next(tokens) == nil then return T end
  local ov
  for slot, target in pairs(slots) do
    local name = tokens[slot]
    local at = tostring(where) .. "." .. slot
    local ok = name ~= nil and self:__RemapName(owner, name, at)
    local v = ok and T[name]
    if ok and v ~= nil and type(v) ~= "table" then   -- a string, number or bool token: no color
      local o = self.owners[owner]
      if o then refuseToken(o, owner, at .. " " .. name, "the remap names a " .. type(v) .. " token, not a color") end
    elseif ok then
      ov = ov or {}
      ov[target] = orNone(T[name])
      if fills and fills[slot] then
        ov[target .. "Top"], ov[target .. "Bottom"] = orNone(T[name .. "Top"]), orNone(T[name .. "Bottom"])
      end
    end
  end
  if not ov then return T end
  return setmetatable({}, { __index = function(_, k)
    local v = ov[k]
    if v == NONE then return nil end
    if v ~= nil then return v end
    return T[k]
  end })
end

--- True when `value` is the FROM_SKIN sentinel.
function lib.IsFromSkin(value)
  return value == lib.FROM_SKIN
end

--- `value`, or the owner's token `kind` when `value` is the FROM_SKIN sentinel or `fromSkin` (a
--- setting's companion "follow the skin" bool) is true. While the owner ignores fonts, `hud.font`
--- and `hud.outline` answer the stored `value` whatever the companion says, and nil for a stored
--- FROM_SKIN, which names no face of its own (minor 8, R-1): the host's own setting stands.
function lib:Resolve(owner, kind, value, fromSkin)
  if hudFontIgnored(self, owner, kind) then
    if value == self.FROM_SKIN then return nil end
    return value
  end
  if value == self.FROM_SKIN or fromSkin == true then return self:Token(owner, kind) end
  return value
end

--- Walk a dotted path ("font.face") to the table holding its last segment.
local function walk(t, path)
  local segs = {}
  for seg in path:gmatch("[^%.]+") do segs[#segs + 1] = seg end
  if #segs == 0 then return nil end
  local parent = t
  for i = 1, #segs - 1 do
    parent = parent[segs[i]]
    if type(parent) ~= "table" then return nil end
  end
  return parent, segs[#segs]
end

--- Put every listed key of `profile` back on the skin (the owner's ruling R3). A key whose name
--- ends in `FromSkin` is a companion named directly and is set to true, stored or not and whatever
--- it held (minor 8). A key holding a color (a table), or one with a `<key>FromSkin` companion
--- beside it (OptionsCompose's `fromSkin` pickers, minor 3), keeps its value and gets the companion
--- set to true; with `opts.companions` every listed key does, stored or not (minor 8); any other
--- bool key is set to true; any other key takes the FROM_SKIN sentinel. Keys may be dotted paths
--- into nested tables; a path whose table does not exist is skipped. Answers how many keys it set.
--- Called as `Skin.ResetToSkin(p, keys[, opts])`.
function lib.ResetToSkin(profile, keys, opts, extra)
  if profile == lib then profile, keys, opts = keys, opts, extra end
  if type(profile) ~= "table" or type(keys) ~= "table" then return 0 end
  local companions = type(opts) == "table" and opts.companions == true
  local n = 0
  for _, path in ipairs(keys) do
    local parent, leaf = walk(profile, tostring(path))
    if type(parent) == "table" then
      local v = parent[leaf]
      if leaf:match("FromSkin$") then
        parent[leaf] = true
      elseif companions or type(v) == "table" or parent[leaf .. "FromSkin"] ~= nil then
        parent[leaf .. "FromSkin"] = true
      elseif type(v) == "boolean" then
        parent[leaf] = true
      else
        parent[leaf] = lib.FROM_SKIN
      end
      n = n + 1
    end
  end
  return n
end

-- ── the frame registry and the repaint ───────────────────────────────────────────────────────

local function ownerSet(owner)
  local set = lib.byOwner[owner]
  if not set then
    set = setmetatable({}, WEAK_KEYS)
    lib.byOwner[owner] = set
  end
  return set
end

--- Record that primitive `prim` painted `frame` for `owner` with these arguments, so a skin
--- switch can replay it. One record per frame; a frame painted for a second owner moves to it.
--- Repeating a primitive replaces its arguments and keeps its place in the replay order. Called
--- by the primitives; answers the record, whose `regions` table is the primitive's own.
function lib:Track(owner, frame, prim, ...)
  requireOwner(owner, "Track")
  if type(frame) ~= "table" or type(prim) ~= "string" then return nil end
  local rec = self.painted[frame]
  if rec and rec.owner ~= owner then
    local old = self.byOwner[rec.owner]
    if old then old[frame] = nil end
    rec = nil
  end
  if not rec then
    lib.__paintSeq = lib.__paintSeq + 1
    rec = { owner = owner, seq = lib.__paintSeq, calls = {}, order = {}, regions = {} }
    self.painted[frame] = rec
  end
  if not rec.calls[prim] then rec.order[#rec.order + 1] = prim end
  rec.calls[prim] = { n = select("#", ...), ... }
  ownerSet(owner)[frame] = true
  return rec
end

--- Forget `frame` (a pooled widget handed back): it is no longer repainted for anyone.
function lib:Untrack(frame)
  local rec = self.painted[frame]
  if not rec then return end
  local set = self.byOwner[rec.owner]
  if set then set[frame] = nil end
  self.painted[frame] = nil
end

--- The primitive a call of `name` for `owner` runs: SkinEUI.lua's route while EllesmereUI paints the
--- owner, else `lib.prim[name]`.
local function primOf(owner, name)
  local route = lib.__euiRoute
  local fn = type(route) == "function" and route(owner, name) or nil
  return fn or lib.prim[name]
end

--- Replay one frame's primitives, in the order they first painted it.
local function replay(owner, frame, rec)
  local calls = 0
  for _, name in ipairs(rec.order) do
    local fn, args = primOf(owner, name), rec.calls[name]
    if type(fn) == "function" and args then
      local ok, err = pcall(fn, owner, frame, unpack(args, 1, args.n))
      if not ok then report(err) end
      calls = calls + 1
    end
  end
  return calls
end

local function bySeq(a, b) return (a.seq or 0) < (b.seq or 0) end

--- Re-run every primitive recorded for `owner`'s frames with the owner's current skin, each frame
--- once, frames in the order they were first painted for the owner (a frame that moved to it counts
--- from the move) and each frame's primitives in their first-paint order. `lib.__repainting` is
--- true while it runs, so a primitive can tell a repaint from a first paint. Answers the number
--- of primitive calls made.
function lib:Repaint(owner)
  local set = self.byOwner[owner]
  if not set then return 0 end
  local recs = {}
  for frame in pairs(set) do
    local rec = self.painted[frame]
    if rec and rec.owner == owner then recs[#recs + 1] = { frame = frame, rec = rec, seq = rec.seq } end
  end
  table.sort(recs, bySeq)
  local calls, was = 0, self.__repainting
  self.__repainting = true
  for _, e in ipairs(recs) do calls = calls + replay(owner, e.frame, e.rec) end
  self.__repainting = was
  return calls
end

-- ── the facade ───────────────────────────────────────────────────────────────────────────────

local function trampoline(owner, name)
  return function(...)
    local fn = primOf(owner, name)
    if fn then return fn(owner, ...) end
  end
end

--- (Re)fill S's entries with this minor's closures, in place: a host's cached S keeps working
--- across a minor upgrade. Every closure reaches `lib` at call time and captures only the owner
--- and a name.
local function fillFacade(S, owner)
  S.owner, S.apiVersion, S.FROM_SKIN = owner, 3, lib.FROM_SKIN
  for _, name in ipairs(lib.VOCAB) do S[name] = trampoline(owner, name) end
  S.Token = function(name) return lib:Token(owner, name) end
  S.Color = function(name) return lib:Color(owner, name) end
  S.Resolve = function(kind, value, fromSkin) return lib:Resolve(owner, kind, value, fromSkin) end
  S.OnLooksChanged = function(fn) return lib:OnLooksChanged(owner, fn) end
  S.IsEnabled = function() return lib:IsOwner(owner) end
  S.GetStyle = function()
    local _, skin = lib:GetChoice(owner)
    return "ka0s:" .. effectiveKey(skin)
  end
  return S
end

--- The owner's facade S: the painting vocabulary bound to `owner`, plus Token, Color, Resolve,
--- OnLooksChanged, IsEnabled, GetStyle, apiVersion and FROM_SKIN. One table per owner, kept for
--- the session. Does not register the owner: an unregistered owner's facade reads Ka0s Default.
function lib:For(owner)
  requireOwner(owner, "For")
  local S = self.facades[owner]
  if not S then
    S = fillFacade({}, owner)
    self.facades[owner] = S
  end
  return S
end

-- A newer minor re-fills every facade an older one built, so the hosts' cached tables run this
-- copy's trampolines.
for owner, S in pairs(lib.facades) do fillFacade(S, owner) end
