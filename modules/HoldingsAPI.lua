local addonName, NS = ...
NS.API = NS.API or {}
NS.API.v1 = NS.API.v1 or {}
NS.HoldingsAPI = NS.HoldingsAPI or {}
local A = NS.HoldingsAPI
local api = NS.API.v1

-- The public API, v1 (#34, spec section 8; public-api): other addons read the holdings tally
-- through `LootHistory.API.v1`. The contract is docs/ARCHITECTURE.md's `## Public API (v1)`.
--
-- PUBLICATION. `_G.LootHistory = { API = NS.API }`, through rawset, at file load, so an addon that
-- reads it at its own PLAYER_LOGIN finds it. It is SETUP: it survives a stand-down, and its answers
-- go empty instead. Nothing else is ever published at `_G.LootHistory` (architecture-§1): never NS,
-- never NS.API's own table under another name.
--
-- EVERY ANSWER IS A COPY. Each table returned is freshly built; none is, or holds, a table
-- reachable from db.global.holdings, the tally's cache or its scratch rows, so a consumer that
-- writes into an answer changes nothing the next call returns.
--
-- THE RELAY. HOLDINGS_CHANGED (the Reconciler is its one sender, architecture-§4) is re-fired as
-- `HoldingsChanged` through this module's own CallbackHandler registry, which is not the bus, so
-- this module is one more receiver and never a second sender. A simulation's flushes concern its
-- session store, which the API never reads, so they are not relayed. Without CallbackHandler the
-- two registration functions are no-ops that answer false, so the v1 shape is the same either way.
--
-- Reads NS.Holdings, NS.Compat, NS.Util, NS.Sim and NS.db at call time; binds NS.HoldingsTally at
-- load (the TOC places this file below it).

local Tally = NS.HoldingsTally
local C = NS.Constants
local WARBAND = C.WARBAND_HOLDER
local EVENT = "HoldingsChanged"

-- ── availability (spec section 8.4) ──────────────────────────────────────────────────────────

-- trackLedger is per profile while holdings are account-wide, so the answer follows the logged-in
-- character's profile.
local function ledgerOn()
  local p = NS.db and NS.db.profile
  local s = p and p.settings
  return s ~= nil and s.trackLedger ~= false
end

--- Up, enabled and the ledger on. A perf capture (any hold) stands the addon down, so it reads
--- unavailable too.
function A.IsAvailable()
  return not NS.IsStoodDown() and not NS.AddonIsOff() and ledgerOn()
end
local available = A.IsAvailable

local function store() return NS.Holdings:SavedStore() end

local function copy(src)
  local out = {}
  if src then for k, v in pairs(src) do out[k] = v end end
  return out
end

-- ── the eleven functions (spec section 8.2), all dot-called ──────────────────────────────────

function api.Version() return C.API_VERSION end

function api.IsAvailable() return available() end

--- Characters ascending, then the warband last when present.
function api.Holders()
  local out = {}
  if not available() then return out end
  local hasWarband = false
  for h in pairs(store()) do
    if h == WARBAND then hasWarband = true else out[#out + 1] = h end
  end
  table.sort(out)
  if hasWarband then out[#out + 1] = WARBAND end
  return out
end

-- The stored entry for `holder`, or nil for a non-string, an unknown holder, or while unavailable.
local function entryOf(holder)
  if type(holder) ~= "string" or not available() then return nil end
  return store()[holder]
end

-- `name` and `realm` of a holder key: the warband reads the account's word; a regional client's key
-- (WoW Forever, "First Surname") is the name whole; Retail's "Name-Realm" splits at the first "-".
local function splitKey(holder)
  if holder == WARBAND then return C.ACCOUNT.holder, nil end
  if NS.Compat.RegionalNames() then return holder, nil end
  local name, realm = holder:match("^([^-]+)-(.+)$")
  if name then return name, realm end
  return holder, nil
end

function api.HolderInfo(holder)
  local e = entryOf(holder)
  if not e then return nil end
  local meta = e.meta or {}
  local name, realm = splitKey(holder)
  return { name = name, realm = realm, class = meta.classFile, isWarband = holder == WARBAND,
           isCurrent = holder == NS.Util.PlayerKey(), lastSeen = meta.lastSeen,
           partial = meta.partial == true }
end

--- `total, { [holder] = { [container] = n } }`, live overlay included; `nil, {}` while unavailable
--- or for a non-number id.
function api.ItemCount(itemID)
  if type(itemID) ~= "number" or not available() then return nil, {} end
  local total, rows, n = Tally:Item(itemID)
  local per = {}
  for i = 1, n do per[rows[i].holder] = copy(rows[i].containers) end
  return total, per
end

--- `total, { [holder] = n }`, the same rules.
function api.CurrencyCount(currencyID)
  if type(currencyID) ~= "number" or not available() then return nil, {} end
  local total, rows, n = Tally:Currency(currencyID)
  local per = {}
  for i = 1, n do per[rows[i].holder] = rows[i].count end
  return total, per
end

-- One holder's copper: the logged-in character's purse live, the warband's deposit live where the
-- client answers, everyone else's stored.
local function moneyOf(holder, e, me)
  if holder == me then return NS.Compat.GetMoney() end
  if holder == WARBAND then
    local w = NS.Compat.GetWarbandMoney()
    if w ~= nil then return w end
  end
  return e and e.money or 0
end

--- Copper for `holder`, or the sum over every holder (the logged-in character included) when nil.
function api.Money(holder)
  if not available() then return nil end
  local s, me = store(), NS.Util.PlayerKey()
  if holder ~= nil then
    if type(holder) ~= "string" or (s[holder] == nil and holder ~= me) then return nil end
    return moneyOf(holder, s[holder], me)
  end
  local sum = s[me] == nil and moneyOf(me, nil, me) or 0
  for h, e in pairs(s) do sum = sum + moneyOf(h, e, me) end
  return sum
end

local META = { "genesis", "partial", "completeAt", "lastSeen", "classFile" }

--- A deep copy of the stored entry: no live overlay, and escrow and meta.bankSlots (internal) left
--- out.
function api.Holdings(holder)
  local e = entryOf(holder)
  if not e then return nil end
  local items, meta = {}, {}
  for id, row in pairs(e.items or {}) do items[id] = copy(row) end
  local m = e.meta or {}
  for i = 1, #META do meta[META[i]] = m[META[i]] end
  return { items = items, currency = copy(e.currency), money = e.money or 0, links = copy(e.links),
           scanned = copy(e.scanned), meta = meta }
end

function api.Scanned(holder)
  local e = entryOf(holder)
  if not e then return nil end
  return copy(e.scanned)
end

-- ── the callback relay (spec section 8.3) ────────────────────────────────────────────────────

local function unbound() return false end

--- Embed RegisterCallback / UnregisterCallback from CallbackHandler, or the two no-ops answering
--- false when it is absent (the degraded arm). Idempotent: a registry once bound is kept.
function A._BindCallbacks()
  if A._registry then return true end
  local CBH = LibStub and LibStub("CallbackHandler-1.0", true)
  if not CBH then
    api.RegisterCallback, api.UnregisterCallback = unbound, unbound
    return false
  end
  A._registry = CBH:New(api, "RegisterCallback", "UnregisterCallback", false)
  return true
end

local function fire(holder)
  if A._registry then A._registry:Fire(EVENT, holder) end
end

local function onHoldingsChanged(_, holder)
  if NS.Sim and NS.Sim:IsActive() then return end
  fire(holder)
end

local function onSettingsChanged(_, reason)
  if reason ~= "ledger" and reason ~= "profile" then return end
  local now = available()
  if now == A._lastAvailable then return end
  A._lastAvailable = now
  fire(nil)
end

--- One private bus target: HOLDINGS_CHANGED relayed per holder, SETTINGS_CHANGED (`ledger`,
--- `profile`) relayed as nil when availability flips. Fires nil once so consumers re-query.
function A:Enable()
  if self.__ev or not NS.bus then return end
  self.__ev = NS.NewBusTarget()
  self.__ev:RegisterMessage(NS.MSG.HOLDINGS_CHANGED, onHoldingsChanged)
  self.__ev:RegisterMessage(NS.MSG.SETTINGS_CHANGED, onSettingsChanged)
  self._lastAvailable = available()
  fire(nil)
end

--- The stand-down half: fires nil once, then the target goes wholesale. Third-party registrations
--- stay on the registry and go quiet, because nothing relays to them.
function A:Disable()
  if not self.__ev then return end
  fire(nil)
  self.__ev:UnregisterAllMessages()
  self.__ev:UnregisterAllEvents()
  self.__ev = nil
  self._lastAvailable = nil
end

A._BindCallbacks()

-- public-api: only `API`, never NS. rawset needs no .luacheckrc entry (core/LauncherSetup.lua).
rawset(_G, addonName, { API = NS.API })
