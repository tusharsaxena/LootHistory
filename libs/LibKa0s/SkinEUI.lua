-- LibKa0s-Skin-1.0 — the EllesmereUI provider: an owner whose source is `eui` is painted by
-- EllesmereUI's own skinning facade, in the player's EllesmereUI theme, while EllesmereUI's gate holds.
--
-- ── WHAT ELLESMEREUI OFFERS (its SKINNING_API.md, API version 3; described, never copied) ─────
--
-- `EllesmereUI.RegisterSkin(name, callback)` lists the addon in EllesmereUI's Third-Party Addons
-- list and calls `callback(S)` ONCE per session (at PLAYER_LOGIN, or at once when registered later),
-- and only while EllesmereUI's third-party skinning and that addon's entry are on. `S` carries the
-- primitives (`Shell`, `Button`, ...), whose names this major's vocabulary mirrors, and the getters
-- (`GetAccentColor`, `GetPanelColor`, `GetFont`, `OnLooksChanged`). Its paint is one-way: only a
-- reload takes it off. EllesmereUI's license reserves every right, so this file mirrors its names
-- and token model and nothing else.
--
-- ── THE GATE (skinning-§5) ───────────────────────────────────────────────────────────────────
--
--   eui     the EllesmereUI global with RegisterSkin, and its EllesmereUIBlizzardSkin child loaded
--           (the child holds the dispatcher; without it RegisterSkin only queues);
--   master  EllesmereUIDB.thirdPartySkinsOff not truthy;
--   own     EllesmereUIDB.thirdPartySkinAddons[owner] not false (nil is on);
--   facade  EllesmereUI handed this owner its facade this session.
--
-- The two EllesmereUIDB reads are **library-stack-§6's skinning exception** (WowAddonStandards
-- v2.89.0): this file, and no other, MAY read EllesmereUIDB.thirdPartySkinsOff and
-- EllesmereUIDB.thirdPartySkinAddons[<owner>], read-only, at call time, nil-guarded, never written.
-- EllesmereUI publishes no query for either switch. tests/test_skin_eui.lua fails when the name
-- appears in any other payload file.
--
-- ── WHAT IT DOES WITH THE FACADE ─────────────────────────────────────────────────────────────
--
--   * Registration: `RegisterOwner` registers the owner with EllesmereUI through a trampoline into
--     whichever copy of this major is live when EllesmereUI calls back, and every owner not yet
--     registered is retried at each RegisterOwner, on ADDON_LOADED("EllesmereUI") and at
--     PLAYER_LOGIN (Core's SafeRegisterEvent, on a frame made at the first RegisterOwner). That
--     member is resolved at call time and is the major's one Core call: with a Core that lacks it
--     no retry frame is made, and owners register only at RegisterOwner.
--   * EnterEUI, one function for the live switch and for the facade arriving late: it gives back
--     the Ka0s paint of every recorded frame an EllesmereUI primitive will take, replays the owner's
--     records (EllesmereUI's names go to EllesmereUI, the Ka0s extras repaint from its getters) and
--     latches `lib.euiPainted[owner]` for the session. From then on a gate failure or a source change
--     asks for a reload and never falls back live.
--   * Before EllesmereUI paints, an owner on `eui` wears its Ka0s skin (the live fallback).
--   * Fail closed: a facade missing a needed primitive is refused when it arrives (so the gate
--     never offers the choice) and before anything is painted, and
--     a primitive that raises stops EllesmereUI painting that owner; either is latched and logged
--     once through the owner's `opts.log`.
--   * Ka0s-only option keys (`primary`, `role`, ...) are stripped before EllesmereUI sees a call.
--   * Pooled and shared objects (AceGUI widgets, `Skin:__MarkShared` targets: the library's popup
--     menu, the reorder ghost, any library singleton) are NEVER handed to EllesmereUI: they keep the
--     library's technique, colored from EllesmereUI's getters, because a one-way paint on a pooled
--     frame would follow it into another addon.
--   * A call that remaps a slot to another token (`opts.tokens`, minor 2) is the library's too: a
--     danger button or a callout keeps its meaning, painted with the library's technique from the
--     EllesmereUI-derived tokens, since EllesmereUI's facade has no slot to take it.

local lib = LibStub and LibStub("LibKa0s-Skin-1.0", true)
if not lib then return end   -- the shell refused (no Core, or below its floor): nothing to attach to

-- Minor 2 (LK-02 of Ka0sAddonsCommonTasks docs/2026-10-29-SKINNING_ROLLOUT): a call whose options
-- carry a non-empty `tokens` remap takes the library's technique rather than EllesmereUI's.
local EUI_MINOR = 2
if lib.__euiMinor and lib.__euiMinor >= EUI_MINOR
  and lib.__euiShellMinor == lib.MINOR then return end
lib.__euiMinor      = EUI_MINOR
lib.__euiShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.SkinEUI = EUI_MINOR

local MAJOR = lib.MAJOR
local SKIN_CHILD = "EllesmereUIBlizzardSkin"
local WEAK_KEYS = { __mode = "k" }

lib.euiFacade     = lib.euiFacade or {}       -- owner -> the facade EllesmereUI handed it
lib.euiRegistered = lib.euiRegistered or {}   -- owner -> true once RegisterSkin took it
lib.euiRefused    = lib.euiRefused or {}      -- owner -> why EllesmereUI no longer paints it
lib.euiPainted    = lib.euiPainted or {}
lib.shared        = lib.shared or setmetatable({}, WEAK_KEYS)
lib.__euiLooks    = lib.__euiLooks or {}      -- owner -> true once its OnLooksChanged is hooked
lib.__euiTok      = {}                        -- owner -> { base, t }: the derived tokens, a cache

-- EllesmereUI's primitive names (its facade, API version 3), in its reference's order;
-- `SetTabSelection` arrived in version 2 and is the one a facade may lack.
local NATIVE_LIST = {
  "Shell", "Panel", "Inset", "FadeRegions", "FadeNineSlice", "Button", "WhiteButtonLabel",
  "StateButtonLabel", "EditBox", "Checkbox", "Dropdown", "ScrollBar", "Tab", "SetTabSelection",
  "CloseButton", "PageButton", "SquareIcon", "SortHeaderBar", "Font", "White", "ApplyBarFill",
}
local NATIVE = {}
for _, name in ipairs(NATIVE_LIST) do NATIVE[name] = true end
local OPTIONAL = { SetTabSelection = true }
local GETTERS = { "GetAccentColor", "GetPanelColor", "GetFont" }

-- The option keys EllesmereUI reads, per primitive; every other key of an options table is the
-- library's own and is stripped.
local ALLOWED = {
  Shell = { noBorder = true, noTopBar = true, bottomBar = true },
  Panel = { inset = true, noBorder = true, noBg = true },
  EditBox = { padInput = true, noBorder = true },
  Checkbox = { stockCheck = true },
}

-- The tokens EllesmereUI's getters drive while it paints an owner; every other token is Ka0s
-- Default's (EllesmereUI's look is dark and flat).
local ACCENT_TOKENS = { "text.accent", "tab.onLine", "nav.selBar", "check.mark", "slider.fill",
                        "input.focus", "list.selOutline" }
local PANEL_TOKENS = { "win.bg", "panel.bg", "menu.bg", "popup.bg", "drawer.bg", "card.bg" }
local FLAT_TOKENS = { "win.bgTop", "win.bgBottom", "win.bgTexture", "title.bgTop", "title.bgBottom" }
local FONT_TOKENS = { "font.body", "font.title" }

local function report(err)
  local h = type(geterrorhandler) == "function" and geterrorhandler()
  if type(h) == "function" then h(err) end
end

-- ── the gate ─────────────────────────────────────────────────────────────────────────────────

-- C_AddOns.IsAddOnLoaded answers (loadedOrLoading, loaded); no reader, or one that raises, is
-- not loaded.
local function loaded(name)
  local api = type(C_AddOns) == "table" and C_AddOns.IsAddOnLoaded
  if type(api) ~= "function" then return false end
  local ok, _, isLoaded = pcall(api, name)
  return ok and isLoaded == true
end

local function suiteReady()
  local eui = EllesmereUI
  return type(eui) == "table" and type(eui.RegisterSkin) == "function" and loaded(SKIN_CHILD)
end

-- library-stack-§6's skinning exception: the only EllesmereUIDB reads in the library.
local function euiDB()
  local d = EllesmereUIDB
  return type(d) == "table" and d or nil
end

local function masterOn()
  local d = euiDB()
  return not (d and d.thirdPartySkinsOff)
end

local function entryOn(owner)
  local d = euiDB()
  local t = d and d.thirdPartySkinAddons
  return not (type(t) == "table" and t[owner] == false)
end

--- The first three conditions (EllesmereUI's side), true when all hold.
local function gateOpen(owner)
  return suiteReady() and masterOn() and entryOn(owner)
end

--- The first primitive or getter a facade lacks, or nil.
local function missingFrom(S)
  for _, name in ipairs(NATIVE_LIST) do
    if not OPTIONAL[name] and type(S[name]) ~= "function" then return name end
  end
  for _, name in ipairs(GETTERS) do
    if type(S[name]) ~= "function" then return name end
  end
  return nil
end

--- Latch `why` for `owner` and write it to the owner's log once.
local function refuse(owner, why)
  if lib.euiRefused[owner] then return end
  lib.euiRefused[owner] = why
  local o = lib.owners[owner]
  if o and type(o.log) == "function" then
    local ok, err = pcall(o.log, MAJOR .. ": EllesmereUI skin off for " .. owner .. ": " .. why)
    if not ok then report(err) end
  end
end

--- True while EllesmereUI paints `owner`: on `eui`, painted this session, the facade held.
local function active(owner)
  local o = lib.owners[owner]
  return o ~= nil and o.source == "eui" and lib.euiPainted[owner] == true
    and lib.euiFacade[owner] ~= nil
end

-- ── what is never handed to EllesmereUI ──────────────────────────────────────────────────────

local function isAceWidget(t)
  return type(rawget(t, "type")) == "string" and rawget(t, "frame") ~= nil
    and type(rawget(t, "userdata")) == "table"
end

-- An AceGUI widget's frame carries `obj`, the widget (every AceGUI widget constructor sets it).
local function aceFrame(t)
  local o = type(t) == "table" and rawget(t, "obj")
  return type(o) == "table" and type(rawget(o, "type")) == "string" and rawget(o, "frame") ~= nil
end

local function parentOf(t)
  if type(t.GetParent) ~= "function" then return nil end
  local ok, p = pcall(t.GetParent, t)
  if ok and type(p) == "table" and p ~= t then return p end
  return nil
end

--- True for a pooled or shared object: an AceGUI widget or its frame (or a region of that frame),
--- or a target marked with `Skin:__MarkShared`.
local function isShared(t)
  if type(t) ~= "table" then return true end
  if lib.shared[t] or isAceWidget(t) or aceFrame(t) then return true end
  local p = parentOf(t)
  return p ~= nil and (lib.shared[p] == true or aceFrame(p))
end

--- Mark `target` as pooled or shared (the library's popup menu, its reorder ghost, an AceGUI widget
--- the library acquired): it is never handed to an EllesmereUI primitive, and keeps the library's
--- technique under `eui`. Weak: a collected target leaves the set. Answers target. Internal: the
--- library's own files mark their singletons; it is not host contract.
function lib:__MarkShared(target)
  if type(target) == "table" then self.shared[target] = true end
  return target
end

-- ── the call ─────────────────────────────────────────────────────────────────────────────────

-- An options table (a plain table, no GetObjectType) with only the keys EllesmereUI reads. Button's
-- second argument keeps only its array of region names (EllesmereUI's keepKeys).
local function strip(name, v)
  if type(v) ~= "table" or type(v.GetObjectType) == "function" then return v end
  if name == "Button" then
    local keep = {}
    for _, k in ipairs(v) do if type(k) == "string" then keep[#keep + 1] = k end end
    return #keep > 0 and keep or nil
  end
  local allowed = ALLOWED[name]
  if not allowed then return nil end
  local out
  for k, x in pairs(v) do
    if allowed[k] then
      out = out or {}
      out[k] = x
    end
  end
  return out
end

local function stripAll(name, n, ...)
  local args = { ... }
  for i = 1, n do args[i] = strip(name, args[i]) end
  return unpack(args, 1, n)
end

local function trackEUI(owner, target, name, ...)
  local P = lib.__P
  if P and type(P.track) == "function" then return P.track(owner, target, name, ...) end
  return lib:Track(owner, target, name, ...)
end

--- True when a call's options table remaps a slot (`opts.tokens`, non-empty): EllesmereUI's facade
--- cannot take it, so the library paints it (minor 2).
local function remapped(opts)
  return type(opts) == "table" and type(opts.GetObjectType) ~= "function"
    and type(opts.tokens) == "table" and next(opts.tokens) ~= nil
end

--- One EllesmereUI call for `owner`: recorded, the options stripped, under pcall. A shared target,
--- a call that remaps a slot, or an owner EllesmereUI stopped painting, takes the library's
--- technique instead.
local function euiCall(name)
  return function(owner, target, ...)
    if isShared(target) or lib.euiRefused[owner] or remapped((...)) then
      local fn = lib.prim[name]
      if fn then return fn(owner, target, ...) end
      return
    end
    trackEUI(owner, target, name, ...)
    local S = lib.euiFacade[owner]
    local fn = S and S[name]
    if type(fn) ~= "function" then return end   -- an optional primitive: EllesmereUI's look stands
    local ok, err = pcall(fn, target, stripAll(name, select("#", ...), ...))
    if not ok then refuse(owner, name .. " raised: " .. tostring(err)) end
  end
end

lib.__euiCalls = {}
for _, name in ipairs(NATIVE_LIST) do lib.__euiCalls[name] = euiCall(name) end

-- Skin.lua's route slot: EllesmereUI's names go to EllesmereUI while it paints the owner.
lib.__euiRoute = function(owner, name)
  if not NATIVE[name] or not active(owner) then return nil end
  return lib.__euiCalls[name]
end

-- ── the tokens the Ka0s extras paint from ────────────────────────────────────────────────────

local function getter(S, name)
  local fn = S[name]
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn)
  if not ok then return nil end
  return a, b, c, d
end

local function setAll(t, names, v)
  for _, name in ipairs(names) do t[name] = v end
end

local function derive(base, S)
  local t = {}
  for k, v in pairs(base) do t[k] = v end
  local r, g, b = getter(S, "GetAccentColor")
  if type(r) == "number" then setAll(t, ACCENT_TOKENS, { r, g, b, 1 }) end
  local pr, pg, pb, pa = getter(S, "GetPanelColor")
  if type(pr) == "number" then
    setAll(t, PANEL_TOKENS, { pr, pg, pb, type(pa) == "number" and pa or 1 })
    setAll(t, FLAT_TOKENS, nil)
  end
  local path = getter(S, "GetFont")
  if type(path) == "string" and path ~= "" then setAll(t, FONT_TOKENS, path) end
  return t
end

-- Skin.lua's token slot: while EllesmereUI paints the owner, Ka0s Default with EllesmereUI's
-- accent, panel color and font over it. Cached per owner until its looks change.
lib.__euiTokens = function(owner)
  if not active(owner) then return nil end
  local base = lib:ResolveSkin(lib.DEFAULT)
  local c = lib.__euiTok[owner]
  if c and c.base == base then return c.t end
  c = { base = base, t = derive(base, lib.euiFacade[owner]) }
  lib.__euiTok[owner] = c
  return c.t
end

-- ── entering EllesmereUI ─────────────────────────────────────────────────────────────────────

local function bySeq(a, b) return a.seq < b.seq end

--- Give back the Ka0s paint of every recorded frame of `owner` whose record names one of
--- EllesmereUI's primitives, so EllesmereUI paints over the stock frame.
local function giveBack(owner)
  local P, set = lib.__P, lib.byOwner[owner]
  if not (P and type(P.unpaint) == "function" and set) then return end
  local recs = {}
  for frame in pairs(set) do
    local rec = lib.painted[frame]
    if rec and rec.owner == owner then recs[#recs + 1] = { frame = frame, rec = rec, seq = rec.seq or 0 } end
  end
  table.sort(recs, bySeq)
  for _, e in ipairs(recs) do
    for _, name in ipairs(e.rec.order) do
      if NATIVE[name] and not isShared(e.frame) then
        P.unpaint(e.rec, e.frame)
        break
      end
    end
  end
end

--- Paint `owner` with EllesmereUI, once per session: on `eui`, the facade held and of the right
--- shape, the gate open. Answers true when EllesmereUI paints the owner (now or already).
function lib:__EnterEUI(owner)
  if self.euiPainted[owner] then return true end
  local o, S = self.owners[owner], self.euiFacade[owner]
  if not (o and S) or o.source ~= "eui" or o.pendingReload or self.euiRefused[owner] then return false end
  if not gateOpen(owner) then return false end
  local missing = missingFrom(S)
  if missing then
    refuse(owner, "its facade lacks " .. missing)
    return false
  end
  giveBack(owner)
  self.euiPainted[owner] = true
  self.__euiTok[owner] = nil
  self:Repaint(owner)
  self:__NotifyLooks(owner)
  return true
end

--- After EllesmereUI painted `owner`, a closed gate asks for a reload (it never falls back live).
--- Answers true when it did.
local function lapsed(owner)
  if not lib.euiPainted[owner] or gateOpen(owner) then return false end
  lib:__RequestReload(owner)
  return true
end

-- Skin.lua's SetChoice slot, for a move onto `eui`: "reload" when EllesmereUI painted and its gate
-- has since closed; true when this call painted with EllesmereUI; nil for an ordinary repaint (a
-- Ka0s fallback, or EllesmereUI already painting).
lib.__euiOnChoice = function(owner)
  if lib.euiPainted[owner] then
    if not gateOpen(owner) then return "reload" end
    return nil
  end
  if lib:__EnterEUI(owner) then return true end
  return nil
end

--- EllesmereUI's callback, reached through the trampoline RegisterSkin was handed: keep the facade,
--- follow its live looks, and paint if the owner is on `eui`.
function lib:__OnEUIFacade(owner, S)
  if type(owner) ~= "string" or type(S) ~= "table" then return end
  self.euiFacade[owner] = S
  self.__euiTok[owner] = nil
  -- The shape is checked on arrival, whatever the owner's source, so GetEUIStatus never offers
  -- a choice EnterEUI would refuse.
  local missing = missingFrom(S)
  if missing then refuse(owner, "its facade lacks " .. missing) end
  if not self.__euiLooks[owner] and type(S.OnLooksChanged) == "function" then
    self.__euiLooks[owner] = true
    local ok, err = pcall(S.OnLooksChanged, function()
      local live = LibStub(MAJOR, true)
      if live and live.__OnEUILooks then live:__OnEUILooks(owner) end
    end)
    if not ok then report(err) end
  end
  self:__EnterEUI(owner)
end

--- EllesmereUI's looks changed live: the Ka0s extras repaint from the new getters.
function lib:__OnEUILooks(owner)
  self.__euiTok[owner] = nil
  if not active(owner) then return end
  self:Repaint(owner)
  self:__NotifyLooks(owner)
end

-- ── registration ─────────────────────────────────────────────────────────────────────────────

local function tryRegister(owner)
  if lib.euiRegistered[owner] then return true end
  local eui = EllesmereUI
  if type(eui) ~= "table" or type(eui.RegisterSkin) ~= "function" then return false end
  lib.euiRegistered[owner] = true
  local ok, err = pcall(eui.RegisterSkin, owner, function(S)
    local live = LibStub(MAJOR, true)
    if live and live.__OnEUIFacade then live:__OnEUIFacade(owner, S) end
  end)
  if not ok then
    lib.euiRegistered[owner] = nil
    report(err)
    return false
  end
  return true
end

--- Register every owner EllesmereUI has not taken yet. Answers how many it took this call.
function lib:__RetryEUI()
  local n = 0
  for owner in pairs(self.owners) do
    if not self.euiRegistered[owner] and tryRegister(owner) then n = n + 1 end
  end
  return n
end

function lib:__OnEUIEvent(event, name)
  if event == "ADDON_LOADED" and name ~= "EllesmereUI" then return end
  self:__RetryEUI()
  local f = self.__euiEventFrame
  if not f then return end
  if event == "PLAYER_LOGIN" then
    if type(f.UnregisterAllEvents) == "function" then f:UnregisterAllEvents() end
  elseif type(f.UnregisterEvent) == "function" then
    f:UnregisterEvent("ADDON_LOADED")
  end
end

-- The retry frame, made at the first RegisterOwner (no frame exists until a host adopts), its two
-- events registered through Core's SafeRegisterEvent, resolved at call time (no Core floor rises).
local function ensureEvents()
  if lib.__euiEventFrame or type(CreateFrame) ~= "function" then return end
  local core = LibStub("LibKa0s-Core-1.0", true)
  local register = core and core.SafeRegisterEvent
  if type(register) ~= "function" then return end
  local f = CreateFrame("Frame")
  lib.__euiEventFrame = f
  f:SetScript("OnEvent", function(_, event, name)
    local live = LibStub(MAJOR, true)
    if live and live.__OnEUIEvent then live:__OnEUIEvent(event, name) end
  end)
  register(f, "ADDON_LOADED")
  register(f, "PLAYER_LOGIN")
end

-- Skin.lua's RegisterOwner slot.
lib.__euiOnOwner = function()
  ensureEvents()
  lib:__RetryEUI()
end

-- ── the status the Appearance tab reads ──────────────────────────────────────────────────────

-- The four conditions' US English, by key; `%s` is the owner's label. A caller that translates
-- overrides them by `conditions[i].key` (the Appearance tab's spec.strings).
local EUI_STRINGS = {
  eui = { "EllesmereUI and its Blizzard Skin module are loaded",
          "Install and enable EllesmereUI, including EllesmereUI Blizzard Skin." },
  master = { "EllesmereUI third-party skinning is on",
             "In EllesmereUI, turn on Skin Third-Party Addons under Blizzard Window Skins." },
  own = { "%s is on in EllesmereUI's Third-Party Addons list",
          "In EllesmereUI's Third-Party Addons list, turn on %s." },
  facade = { "EllesmereUI handed %s its skin this session", "Reload the UI." },
}

local function cond(key, ok, label)
  local s = EUI_STRINGS[key]
  return { key = key, ok = ok and true or false, label = s[1]:format(label), hint = s[2]:format(label) }
end

--- Whether `owner` may choose the `eui` source, and why not: `{ ok, painted, refused, conditions }`,
--- `conditions` the four in display order, each `{ key, ok, label, hint }` (`eui`, `master`, `own`,
--- `facade`). `ok` is true only when all four hold and nothing was refused; `refused` is the latched
--- reason EllesmereUI does not paint the owner. Reading it after EllesmereUI painted the owner, with
--- its gate now closed, sets the owner's pending reload (OnReloadRequest).
function lib:GetEUIStatus(owner)
  local o = self.owners[owner]
  local label = o and o.label or tostring(owner)
  local suite = suiteReady()
  local conditions = {
    cond("eui", suite, label),
    cond("master", suite and masterOn(), label),
    cond("own", suite and entryOn(owner), label),
    cond("facade", self.euiFacade[owner] ~= nil, label),
  }
  local ok = not self.euiRefused[owner]
  for _, c in ipairs(conditions) do ok = ok and c.ok end
  if o and o.source == "eui" then lapsed(owner) end
  return { ok = ok, painted = self.euiPainted[owner] == true, refused = self.euiRefused[owner],
           conditions = conditions }
end

-- A newer copy loading after owners registered retries them (an older copy may have had no
-- EllesmereUI global to register with).
if next(lib.owners) then lib.__euiOnOwner() end
