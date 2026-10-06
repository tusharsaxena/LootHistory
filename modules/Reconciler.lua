local _, NS = ...
NS.Reconciler = NS.Reconciler or {}
local R = NS.Reconciler

-- Keeps db.global.holdings current (timeline-ledger spec §5.2). Every event only marks a part
-- dirty; Flush does the work, and never in combat (spec §5.2 "Combat"): a bag event storm in a
-- raid pull costs a table write per event and nothing else. Phase 2 inserts the
-- diff -> gain/loss/transfer rows step into Flush; this file is shaped for that.
--
-- One writer: NS.Holdings is only ever written through the Apply* calls below. Scanner and Holdings
-- are read at CALL time, never captured at load, so the TOC order between them and this file is
-- only a convention.

local C = NS.Constants
local Compat = NS.Compat
local CT = C.Container
local WARBAND = C.WARBAND_HOLDER
-- BAG_UPDATE_DELAYED already closes a burst of BAG_UPDATEs; the short fuse also folds the money,
-- currency and equipment events a single vendor sale or loot fires beside it into one flush.
local DEBOUNCE = 0.35

R.dirty, R.readable = {}, {}

-- The two interactions that make the bank's containers readable. Outside them the client answers
-- a bank slot as EMPTY, not as unknown, so reading it would record the whole bank as lost.
local BANK_INTERACTIONS = { "Banker", "AccountBanker" }

function R:IsReadable(part)
  if part == "bank" or part == "tabs" then return self.readable.bank == true end
  if part == "warbandMoney" then return Compat.GetWarbandMoney() ~= nil end
  return true
end

function R:MarkDirty(part, arg)
  if part == "bags" then
    self.dirty.bags = self.dirty.bags or {}
    if arg ~= nil then self.dirty.bags[arg] = true end
  else
    self.dirty[part] = true
  end
end

-- Through NS.After so NS.CancelDeferrals (the stand-down) reaches the fuse. NS.After returns nil
-- when it ran straight through (headless without C_Timer); `_pending` is then already clear.
local function scheduleFlush(self)
  if self._pending then return end
  self._pending = NS.After(DEBOUNCE, function() self._pending = nil; self:Flush() end)
end

-- Which part a BAG_UPDATE belongs to. Bank and warband tab bags fire it too; they are routed to
-- their own parts so a "bags" flush only ever reads the carried bags, and a closed bank is never
-- read as empty.
local function isIn(list, id)
  for _, v in ipairs(list) do if v == id then return true end end
  return false
end

local function isBankInteraction(kind)
  for _, name in ipairs(BANK_INTERACTIONS) do
    if kind ~= nil and kind == Compat.InteractionType(name) then return true end
  end
  return false
end

function R:OnEvent(event, a1)
  if event == "BAG_UPDATE" then
    if isIn(C.BANK_IDS, a1) then self:MarkDirty("bank")
    elseif isIn(C.WARBAND_TAB_IDS, a1) then self:MarkDirty("tabs")
    else self:MarkDirty("bags", a1) end
  elseif event == "BAG_UPDATE_DELAYED" then scheduleFlush(self)
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then self:MarkDirty("equipped"); scheduleFlush(self)
  elseif event == "PLAYER_MONEY" then self:MarkDirty("money"); scheduleFlush(self)
  elseif event == "ACCOUNT_MONEY" then self:MarkDirty("warbandMoney"); scheduleFlush(self)
  elseif event == "CURRENCY_DISPLAY_UPDATE" then self:MarkDirty("currency"); scheduleFlush(self)
  elseif event == "PLAYERBANKSLOTS_CHANGED" then self:MarkDirty("bank"); scheduleFlush(self)
  elseif event == "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" then self:MarkDirty("tabs"); scheduleFlush(self)
  elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
    if isBankInteraction(a1) then
      self.readable.bank = true
      self:MarkDirty("bank"); self:MarkDirty("tabs"); self:MarkDirty("warbandMoney")
      scheduleFlush(self)
    end
  elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
    if isBankInteraction(a1) then
      self:Flush()                 -- the final read, while the bank is still readable
      self.readable.bank = nil
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if self.deferred then
      self.deferred = nil
      self:Flush()
      if self._genesisPending and not self.deferred then self:MarkLoginGenesis() end
    end
  end
end

-- Scan one dirty part into Holdings. Returns the holder it changed, or nil.
local function flushPart(part, me, now)
  local S, H = NS.Scanner, NS.Holdings
  if part == "bags" then
    local c, l = S.ScanContainers(C.BAG_IDS)
    return H:ApplyContainer(me, CT.BAGS, c, l, now) and me or nil
  elseif part == "equipped" then
    local c, l = S.ScanEquipped()
    return H:ApplyContainer(me, CT.EQUIPPED, c, l, now) and me or nil
  elseif part == "bank" then
    local c, l = S.ScanContainers(C.BANK_IDS)
    return H:ApplyContainer(me, CT.BANK, c, l, now) and me or nil
  elseif part == "tabs" then
    local c, l = S.ScanContainers(C.WARBAND_TAB_IDS)
    return H:ApplyContainer(WARBAND, CT.TABS, c, l, now) and WARBAND or nil
  elseif part == "money" then
    return H:ApplyMoney(me, S.ReadMoney(), now) and me or nil
  elseif part == "warbandMoney" then
    local v = S.ReadWarbandMoney()
    return v ~= nil and H:ApplyMoney(WARBAND, v, now) and WARBAND or nil
  end
end

--- Read every dirty part that is readable now, apply it, and announce each holder that moved ONCE.
--- A part that is not readable (the bank with no banker open) stays dirty for the next flush.
function R:Flush()
  if Compat.InCombatLockdown() then self.deferred = true; return end
  local me, now, changed = NS.Util.PlayerKey(), time(), {}
  for part in pairs(self.dirty) do
    if self:IsReadable(part) then
      if part == "currency" then
        local char, wb = NS.Scanner.ScanCurrencies()
        if NS.Holdings:ApplyCurrency(me, char, now) then changed[me] = true end
        if NS.Holdings:ApplyCurrency(WARBAND, wb, now) then changed[WARBAND] = true end
      else
        local h = flushPart(part, me, now)
        if h then changed[h] = true end
      end
      self.dirty[part] = nil
    end
  end
  local e = NS.Holdings:Get(me)
  if e and not e.meta.classFile then e.meta.classFile = Compat.PlayerClassFile() end
  local n = 0
  for h in pairs(changed) do
    n = n + 1
    NS.bus:SendMessage(NS.MSG.HOLDINGS_CHANGED, h)
  end
  -- Only a flush that moved something writes a line (debug-logging-§9, quiet steady state).
  if n > 0 and NS.State.debug and NS.Debug then NS.Debug("Holdings", "flush: %d holder(s) changed", n) end
end

--- Genesis for this character, and for the warband when its gold was read (spec §5.6).
function R:MarkLoginGenesis()
  self._genesisPending = nil
  local now = time()
  NS.Holdings:MarkGenesis(NS.Util.PlayerKey(), now)
  if NS.Holdings:Get(WARBAND) then NS.Holdings:MarkGenesis(WARBAND, now) end
end

--- The login read (spec §5.6): everything carried, plus warband gold where the client answers it.
--- The bank and the warband tabs need the banker, so a fresh holder stays `partial` until then. A
--- login inside combat (a reload mid-pull) defers the read AND the genesis stamp to the regen edge,
--- so genesis never lands on a holder that was not actually scanned.
function R:LoginScan()
  for _, p in ipairs({ "equipped", "money", "currency", "warbandMoney" }) do self:MarkDirty(p) end
  self:MarkDirty("bags")
  self:Flush()
  if self.deferred then self._genesisPending = true; return end
  self:MarkLoginGenesis()
end

local EVENTS = {
  "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_MONEY", "ACCOUNT_MONEY",
  "CURRENCY_DISPLAY_UPDATE", "PLAYERBANKSLOTS_CHANGED", "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED",
  "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "PLAYER_REGEN_ENABLED",
}

local function trackLedgerOn()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  return s ~= nil and s.trackLedger ~= false
end

--- Two private bus targets, and the split is the point: `_settings` hears SettingsChanged("ledger")
--- for as long as the addon is up, so ticking trackLedger back on can re-register; `__ev` carries
--- the capture events and exists only while trackLedger is on.
function R:Enable()
  if not self._settings then
    self._settings = NS.NewBusTarget()
    self._settings:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, reason)
      if reason ~= "ledger" and reason ~= "profile" then return end
      if trackLedgerOn() then self:Enable() else self:DisableCapture() end
    end)
  end
  if self.__ev or not trackLedgerOn() then return end
  self.__ev = NS.NewBusTarget()
  -- Per event through Core's helper (events-frames-taint-§1): a refused name costs only itself.
  for _, ev in ipairs(EVENTS) do
    NS.SafeRegisterEvent(self.__ev, ev, function(_, ...) self:OnEvent(ev, ...) end, NS.RejectedEvents)
  end
  self._enabled = true
end

--- Capture off (trackLedger unticked) while the module keeps listening for the setting coming back.
function R:DisableCapture()
  if self.__ev then self.__ev:UnregisterAllEvents(); self.__ev = nil end
  self.dirty, self.readable = {}, {}
  self.deferred, self._pending, self._genesisPending = nil, nil, nil
  self._enabled = nil
end

--- The full stand-down (slash-commands-§7): the capture events AND the settings listener. Called
--- from NS.StandDown; `_pending`'s timer is canceled there by NS.CancelDeferrals.
function R:Disable()
  self:DisableCapture()
  if self._settings then self._settings:UnregisterAllMessages(); self._settings = nil end
end
