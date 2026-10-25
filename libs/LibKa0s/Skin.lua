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
--   lib.owners[owner]    { label, get, set, source, skin, pendingReload, listeners }
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
--   * no OnUpdate, no events: a repaint is one pass over the owner's recorded frames.
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
-- (OptionsCompose minor 12's companions; LK-07 of the skinning run).
-- Minor 4: OwnerLabel and WriteChoice, the read and the write of a registration the Appearance tab's copy to
-- every Ka0s addon needs (OptionsAppearance.lua; LK-10 of the skinning run).
local MAJOR, MINOR = "LibKa0s-Skin-1.0", 4
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

local SOURCE_OK = { ka0s = true, eui = true }

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

--- Register `owner` (the addon folder name) at the consumer's file load. `opts.get()` answers the
--- profile's `{ source, skin }`; `opts.set(source, skin)` writes it (copy to every Ka0s addon);
--- `opts.label` names the addon to the player; `opts.log(line)`, optional, takes the one line the
--- EllesmereUI provider writes when it refuses or stops (SkinEUI.lua). The choice is read once,
--- here; afterwards it moves only through `SetChoice`. A second call updates the hooks and keeps the
--- applied choice. Answers the owner's facade.
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
--- through its own write seam. Never moves the applied choice (SetChoice does). Answers true when a
--- setter ran and did not raise; false for an unregistered owner, one with no setter, or a raise
--- (handed to the client's error handler).
function lib:WriteChoice(owner, source, skin)
  local o = self.owners[owner]
  if not o or type(o.set) ~= "function" then return false end
  local ok, err = pcall(o.set, cleanSource(source), cleanSkin(skin))
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

--- The owner's complete token table: its skin resolved (`ResolveSkin`), or, while EllesmereUI paints
--- the owner, the table SkinEUI.lua derives from EllesmereUI's accent, panel color and font. Shared:
--- never write to it. An unregistered owner reads Ka0s Default. Internal (SkinPaint.lua's P.T and
--- `Token` read it); a host reads tokens through `Token` and `Color`.
function lib:__Tokens(owner)
  local hook = self.__euiTokens
  local t = type(hook) == "function" and hook(owner) or nil
  if t then return t end
  local _, skin = self:GetChoice(owner)
  return self:ResolveSkin(skin)
end

--- The owner's resolved token `name` (from `__Tokens`): a color is `{ r, g, b, a }`, shared, never
--- written to. An unregistered owner reads Ka0s Default. nil for a token the skin leaves alone.
function lib:Token(owner, name)
  return self:__Tokens(owner)[name]
end

--- The owner's color token as r, g, b, a (alpha 1 when the token has three components), or nil.
function lib:Color(owner, name)
  local c = self:Token(owner, name)
  if type(c) ~= "table" then return nil end
  return c[1], c[2], c[3], c[4] or 1
end

--- True when `value` is the FROM_SKIN sentinel.
function lib.IsFromSkin(value)
  return value == lib.FROM_SKIN
end

--- `value`, or the owner's token `kind` when `value` is the FROM_SKIN sentinel or `fromSkin` (a
--- setting's companion "follow the skin" bool) is true.
function lib:Resolve(owner, kind, value, fromSkin)
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

--- Put every listed key of `profile` back on the skin (the owner's ruling R3). A key holding a
--- color (a table), or one with a `<key>FromSkin` companion beside it (OptionsCompose's `fromSkin`
--- pickers, minor 3), keeps its value and gets the companion set to true; a bool key (a companion
--- named directly) is set to true; any other key takes the FROM_SKIN sentinel. Keys may be dotted
--- paths into nested tables; a path whose table does not exist is skipped. Answers how many keys it
--- set. Called as `Skin.ResetToSkin(p, keys)`.
function lib.ResetToSkin(profile, keys, extra)
  if profile == lib then profile, keys = keys, extra end
  if type(profile) ~= "table" or type(keys) ~= "table" then return 0 end
  local n = 0
  for _, path in ipairs(keys) do
    local parent, leaf = walk(profile, tostring(path))
    if type(parent) == "table" then
      local v = parent[leaf]
      if type(v) == "table" or parent[leaf .. "FromSkin"] ~= nil then
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
