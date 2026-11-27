local _, NS = ...
NS.Reconciler = NS.Reconciler or {}
local R = NS.Reconciler

-- Keeps db.global.holdings current (timeline-ledger spec §5.2). Every event only marks a part
-- dirty; Flush does the work, and never in combat (spec §5.2 "Combat"): a bag event storm in a
-- raid pull costs a table write per event and nothing else. Phase 2's flush plans the
-- diff -> gain/loss/transfer rows against the stored baseline before it writes holdings.
--
-- One writer: NS.Holdings is only ever written through the Apply* calls below. Scanner and Holdings
-- are read at CALL time, never captured at load, so the TOC order between them and this file is
-- only a convention.

local C = NS.Constants
local Compat = NS.Compat
local Perf = NS.Perf -- load-time upvalue (performance-§2); core/PerfSetup.lua loads above
local CT = C.Container
local WARBAND = C.WARBAND_HOLDER
-- The warband bank is Retail-only (C.FEATURE.warbandBank, clients-§4; the WoW Forever port's ruling
-- R1): where it is absent, the `tabs` and `warbandMoney` parts, their two events, the tab reads and
-- the char <-> warband pairing are never registered, so no row, event or read of them exists. The
-- account holder stays: account-wide currencies still file under it (the currency scan steps).
local WARBAND_BANK = C.FEATURE.warbandBank
-- BAG_UPDATE_DELAYED already closes a burst of BAG_UPDATEs; the short fuse also folds the money,
-- currency and equipment events a single vendor sale or loot fires beside it into one flush.
local DEBOUNCE = 0.35
-- The bank readiness guard's deadline (ruling R8): how long after the frame opens a container that
-- had slots may still answer 0 as "loading". Past it the 0 is believed (a bag taken out of a bank
-- socket while nothing was watching), so the guard can never leave the bank unread for good.
R.READY_WAIT = 5

R.dirty, R.readable = {}, {}

--- The open bank's state (ruling R8, both clients), or nil with no banker open:
---   "unviewable"  this banker does not show the character bank (a warband-only banker);
---   "loading"     a character-bank container that had slots on the last ready read answers 0,
---                 or, with no remembered counts (a first visit), fewer containers answer slots
---                 than the account has bought tabs; and the visit is younger than READY_WAIT;
---   "ready"       otherwise.
--- A per-container check, not "every container answers 0": a partly loaded bank (tab 1 ready, the
--- rest still 0) must wait too, or its unloaded tabs read as an UNTRACKED loss. A first visit's
--- read is the bank's genesis, so a partial one would book the late tabs as gains (LH-REV).
--- The comparison is LibKa0s-Compat's UnreadyBankContainers (LibKa0s#101); the deadline and the
--- memory are this module's. The bought-tab count is passed only with no memory at all, so a memory
--- that recorded no slots is taken as found, as it was before the library held the comparison.
local function bankShape()
  local shape = {}
  for _, id in ipairs(C.BANK_IDS) do shape[id] = Compat.GetContainerNumSlots(id) end
  return shape
end

function R:BankState()
  if not self.readable.bank then return nil end
  -- Three-valued: nil (the build cannot tell) is read as viewable.
  if Compat.CanViewCharacterBank() == false then return "unviewable" end
  if self._bankOpenAt and GetTime() - self._bankOpenAt >= R.READY_WAIT then return "ready" end
  local e = NS.Holdings:Get(NS.Util.PlayerKey())
  local last = e and e.meta.bankSlots
  local bought = not last and Compat.NumPurchasedBankTabs("Character") or nil
  return Compat.UnreadyBankContainers(bankShape(), last, bought) and "loading" or "ready"
end

-- While the bank is loading its visit's drift read waits (Flush), so the parts that read belongs to
-- wait with it: the warband tabs and, for that read, the warband gold.
function R:IsReadable(part)
  if part == "bank" then return self:BankState() == "ready" end
  if part == "tabs" then
    local state = self:BankState()
    return state ~= nil and state ~= "loading"
  end
  if part == "mail" then return self.readable.mail == true end
  if part == "auctions" then return self.readable.auctions == true end
  if part == "warbandMoney" then
    if self.driftPending and self:BankState() == "loading" then return false end
    return WARBAND_BANK and Compat.GetWarbandMoney() ~= nil
  end
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

-- Which interaction frame makes which containers readable, and which parts to rescan on open.
-- Outside the bank the client answers a bank slot as EMPTY, not as unknown, so reading it would
-- record the whole bank as lost; the same holds for a closed mailbox. Escrow's two (mailbox,
-- auction house) are listed here because the readable flags are this module's; what to DO with the
-- mail/auctions columns is modules/Escrow.lua's. `drift`: the first read of a visit is a drift pass.
-- A banker reads the warband tabs and gold too only where the warband bank is a feature.
-- The bank frame opens for three interaction types (BankFrameTemplates registers all three), and
-- LibKa0s-Compat's BankerKind names which bank each opens: "character" for Banker and
-- CharacterBanker (67, both clients; ruling R8), "account" for the warband-only AccountBanker. A
-- character banker arms a visit on both clients; an account banker only where the warband bank is a
-- feature (R1).
local function bankParts()
  if WARBAND_BANK then return { "bank", "tabs", "warbandMoney" } end
  return { "bank" }
end
R.BANKER_ARMS = {
  character = { flag = "bank", parts = bankParts(), drift = true },
}
if WARBAND_BANK then
  R.BANKER_ARMS.account = { flag = "bank", parts = bankParts(), drift = true }
end
-- Every other interaction that makes a part readable, by Enum.PlayerInteractionType member name.
R.READABLE_ON = {
  MailInfo   = { flag = "mail",         parts = { "mail" } },
  Auctioneer = { flag = "auctionHouse", parts = {} },
}

local function specFor(interactionType)
  if interactionType == nil then return nil end
  local kind = Compat.BankerKind(interactionType)
  if kind then return R.BANKER_ARMS[kind] end
  for name, spec in pairs(R.READABLE_ON) do
    if interactionType == Compat.InteractionType(name) then return spec end
  end
  return nil
end

function R:OnInteraction(shown, interactionType)
  local spec = specFor(interactionType)
  if not spec then return end
  if shown then
    -- Only the opening of a visit: a second banker frame inside it is not a fresh read.
    if spec.drift and not self.readable[spec.flag] then
      self.driftPending, self._bankOpenAt = true, GetTime()
    end
    self.readable[spec.flag] = true
    for _, p in ipairs(spec.parts) do self:MarkDirty(p) end
    scheduleFlush(self)
  else
    local waited = self:Flush() == "waiting"           -- final read while still readable
    self.readable[spec.flag] = nil
    if spec.drift then self.driftPending, self._bankOpenAt, self._driftWaited = nil, nil, nil end
    if spec.flag == "auctionHouse" then self.readable.auctions = nil end
    -- A bank shut while still loading read nothing: what the wait held is read without it.
    if waited then scheduleFlush(self) end
  end
end

-- Which part a BAG_UPDATE belongs to. Bank and warband tab bags fire it too; they are routed to
-- their own parts so a "bags" flush only ever reads the carried bags, and a closed bank is never
-- read as empty.
local function isIn(list, id)
  for _, v in ipairs(list) do if v == id then return true end end
  return false
end

-- A part that only needs its dirty bit and the flush fuse.
local function dirtyAndFlush(part)
  return function(self) self:MarkDirty(part); scheduleFlush(self) end
end

-- A bank re-read cue (ruling R8): a bank container or tab set changed, or finished loading, with no
-- BAG_UPDATE for it (BagSync, BagSmith). At an open bank it re-reads the bank parts; elsewhere the
-- bank is not readable, so it does nothing.
local function bankCue(self)
  if not self.readable.bank then return end
  self:MarkDirty("bank")
  if WARBAND_BANK then self:MarkDirty("tabs") end
  scheduleFlush(self)
end

-- event -> handler, built once at file scope (performance-§2: no per-event table). A BAG_UPDATE only
-- marks dirty; BAG_UPDATE_DELAYED, which closes its burst, lights the fuse.
local EVENT_HANDLERS = {
  BAG_UPDATE = function(self, a1)
    if isIn(C.BANK_IDS, a1) then self:MarkDirty("bank")
    elseif isIn(C.WARBAND_TAB_IDS, a1) then self:MarkDirty("tabs")
    else self:MarkDirty("bags", a1) end
  end,
  BAG_UPDATE_DELAYED = function(self) scheduleFlush(self) end,
  PLAYER_EQUIPMENT_CHANGED = dirtyAndFlush("equipped"),
  PLAYER_MONEY = dirtyAndFlush("money"),
  CURRENCY_DISPLAY_UPDATE = function(self, a1, a3, a4, a5)
    self:OnCurrencyUpdate(a1, a3, a4, a5)                 -- (id, quantity, change, gainSrc, lostSrc)
  end,
  CURRENCY_TRANSFER_LOG_UPDATE = function(self)
    self.pendingTransfer = true
    self:MarkDirty("currencyDelta"); scheduleFlush(self)
  end,
  PLAYERBANKSLOTS_CHANGED = dirtyAndFlush("bank"),
  BAG_CONTAINER_UPDATE = bankCue,
  BANK_TABS_CHANGED = bankCue,
  PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(self, a1) self:OnInteraction(true, a1) end,
  PLAYER_INTERACTION_MANAGER_FRAME_HIDE = function(self, a1) self:OnInteraction(false, a1) end,
  MAIL_INBOX_UPDATE = function(self)
    if self.readable.mail then self:MarkDirty("mail"); scheduleFlush(self) end
  end,
  OWNED_AUCTIONS_UPDATED = function(self)
    -- The owned list is only trustworthy once the client has answered the query, which is this event.
    if self.readable.auctionHouse then
      self.readable.auctions = true; self:MarkDirty("auctions"); scheduleFlush(self)
    end
  end,
}
-- The warband bank's two events, only where it is a feature (WARBAND_BANK above).
if WARBAND_BANK then
  EVENT_HANDLERS.ACCOUNT_MONEY = dirtyAndFlush("warbandMoney")
  EVENT_HANDLERS.PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED = dirtyAndFlush("tabs")
end

local function onEvent(self, event, a1, a3, a4, a5)
  local handler = EVENT_HANDLERS[event]
  if handler then handler(self, a1, a3, a4, a5) end
end

-- The combat-exit edge runs the work combat deferred (a pending login scan or a whole flush), so it
-- is not a capture event and stays outside the ledgerEvent bracket (tests/test_perf.lua pins it).
local function onRegenEnabled(self)
  if self.loginPending then self:LoginScan()
  elseif self.deferred then self.deferred = nil; self:Flush() end
end

-- Shape A bracket (performance-§2): every capture event, in combat included, is a dirty bit or a
-- debounce here; the flush it schedules is not inside this bucket (tests/perf.lua measures it), and
-- neither is the PLAYER_REGEN_ENABLED flush, which is dispatched before the bracket opens.
function R:OnEvent(event, a1, _, a3, a4, a5)
  if event == "PLAYER_REGEN_ENABLED" then return onRegenEnabled(self) end
  local t0 = Perf.on and debugprofilestop()
  onEvent(self, event, a1, a3, a4, a5)
  if t0 then Perf.Note("ledgerEvent", debugprofilestop() - t0) end
end

-- ── Phase 2: scan -> plan -> hold or commit (timeline-ledger spec §5.1-§5.5) ─────────────────
--
-- A pass READS every dirty, readable part without touching db.global.holdings; PLANS rows against
-- the stored baseline; and either HOLDS (keeps baseline and dirty bits, looks again shortly) or
-- COMMITS (consume claims, write holdings, write rows). Holding is what lets the two halves of one
-- bank deposit, which arrive a server round-trip apart, meet in one pass (BankLedger's
-- settleBaseline), and what gives a chat line the moment it needs to claim its delta.

R.claims, R.recent, R.reasonMemo = {}, {}, {}
R.pendingCur, R.curGain, R.curLoss = {}, {}, {}
-- Extension points, in order. Escrow (Task 10) and currency deltas (Task 9) append to them.
R.SCAN_STEPS, R.PLAN_STEPS, R.COMMIT_STEPS = {}, {}, {}

local L = NS.Ledger

local function snapFor(snap, holder)
  local s = snap[holder]
  if not s then s = { items = {}, links = {} }; snap[holder] = s end
  return s
end
R.SnapFor = snapFor

local function addLinks(dst, src) for id, l in pairs(src or {}) do if not dst[id] then dst[id] = l end end end

-- part -> whose container it is, which column, how to read it. `slots`: a read also records each
-- container's slot count for the bank readiness guard (R:BankState).
local CONTAINER_READS = {
  bags     = { mine = true,  c = CT.BAGS,     ids = function() return C.BAG_IDS end },
  bank     = { mine = true,  c = CT.BANK,     ids = function() return C.BANK_IDS end, slots = true },
  equipped = { mine = true,  c = CT.EQUIPPED },
}
if WARBAND_BANK then
  CONTAINER_READS.tabs = { mine = false, c = CT.TABS, ids = function() return C.WARBAND_TAB_IDS end }
end

-- One dirty, readable container part into the snapshot; a `slots` read also keeps each
-- container's slot count.
local function readContainer(snap, me, spec)
  local S = NS.Scanner
  local counts, links
  if spec.ids then counts, links = S.ScanContainers(spec.ids()) else counts, links = S.ScanEquipped() end
  local s = snapFor(snap, spec.mine and me or WARBAND)
  s.items[spec.c] = counts
  addLinks(s.links, links)
  if not spec.slots then return end
  local sizes = {}
  for _, id in ipairs(spec.ids()) do sizes[id] = Compat.GetContainerNumSlots(id) end
  s.bankSlots = sizes
end

function R:Scan(me)
  local snap, d, S = {}, self.dirty, NS.Scanner
  -- At an open bank a bag change re-reads the bank and the warband tabs too: a shift-click split
  -- dragged out of the bank fires a bag event for the bags only (LED-P2-01), so waiting for the
  -- bank's own event would leave the withdraw one-sided. Both reads are bounded to the banker visit.
  if d.bags and self.readable.bank then d.bank, d.tabs = true, WARBAND_BANK or nil end
  for part, spec in pairs(CONTAINER_READS) do
    if d[part] and self:IsReadable(part) then readContainer(snap, me, spec) end
  end
  if d.money then snapFor(snap, me).money = S.ReadMoney() end
  if d.warbandMoney and self:IsReadable("warbandMoney") then
    local v = S.ReadWarbandMoney()
    if v then snapFor(snap, WARBAND).money = v end
  end
  if d.currency then
    local ch, wb = S.ScanCurrencies()
    snapFor(snap, me).currency = ch
    snapFor(snap, WARBAND).currency = wb
  end
  for _, step in ipairs(R.SCAN_STEPS) do step(self, snap, me) end
  return snap
end

local function columnOf(e, c)
  local out = {}
  for id, row in pairs(e.items) do if row[c] then out[id] = row[c] end end
  return out
end

-- Each scanned container's stored column beside its new counts, for those with a baseline.
local function baselineColumns(e, s)
  local before, after = {}, {}
  for c, counts in pairs(s.items) do
    if e.scanned[c] then before[c] = columnOf(e, c); after[c] = counts end
  end
  return before, after
end

-- Gold and currency against the stored baseline, each only once that part has one.
local function addPurseNet(net, e, s)
  if s.money and e.scanned.money then
    local dm = s.money - (e.money or 0)
    if dm ~= 0 then net.g = dm end
  end
  if s.currency and e.scanned.currency then
    for _, x in ipairs(L.Diff(e.currency, s.currency)) do net[L.ThingKey("CURRENCY", x.key)] = x.delta end
  end
end

-- One holder's net change per thing, plus its intra-holder moves and escrow traffic. Only
-- containers that already had a baseline take part (a container's first scan is its genesis).
local function planHolder(plan, holder, e, s)
  local before, after = baselineColumns(e, s)
  local own = e.escrow and { mail = e.escrow.mailOwn } or nil
  local moves, ids, arrivals, exits = L.ClassifyItems(before, after, own)
  local net = {}
  for id, dlt in pairs(ids) do net[L.ThingKey("ITEM", id)] = dlt end
  addPurseNet(net, e, s)
  plan.net[holder] = net
  for _, mv in ipairs(moves) do mv.holder = holder; plan.moves[#plan.moves + 1] = mv end
  plan.arrivals[holder], plan.exits[holder] = arrivals, exits
end

function R:Plan(snap, me, clock)
  local plan = { net = {}, moves = {}, pairs = {}, arrivals = {}, exits = {} }
  if not self.silent then
    for holder, s in pairs(snap) do
      local e = NS.Holdings:Get(holder)
      if e and e.meta.genesis then planHolder(plan, holder, e, s) end
    end
  end
  -- A bank drift pass pairs nothing: what moved while nobody watched is each holder's own drift.
  if self.drift then return plan end
  for _, step in ipairs(R.PLAN_STEPS) do step(self, plan, me, clock) end
  return plan
end

-- Plan step 1: char <-> warband transfers (warband bank deposit/withdraw, warband gold, account
-- currency moving between the two holders). Two holders, so the reason names the direction. Only
-- where the warband bank is a feature: elsewhere both reasons are absent (C.SOURCE_ABSENT).
if WARBAND_BANK then
  R.PLAN_STEPS[#R.PLAN_STEPS + 1] = function(_, plan, me)
    local a, b = plan.net[me], plan.net[WARBAND]
    if not (a and b) then return end
    for _, p in ipairs(L.PairHolders(me, a, WARBAND, b)) do
      p.reason = (p.from == WARBAND) and "WARBAND_WITHDRAW" or "WARBAND_DEPOSIT"
      plan.pairs[#plan.pairs + 1] = p
    end
  end
end

-- Reasons are decided when a change is FIRST seen, not when its hold ends: a stamp with a 1.5 s
-- TTL would be gone by then. Memoized per holder/thing/direction and dropped at commit.
local function computeReason(self, key, dir, clock)
  if self.forceReason then return self.forceReason end
  local kind, id = L.ParseThingKey(key)
  local ctx = NS.Attribution.ReasonContext and NS.Attribution:ReasonContext(clock) or { now = clock, scopes = {} }
  ctx.consumable = (kind == "ITEM" and dir == "OUT" and NS.Compat.IsConsumable(id)) or nil
  ctx.currencySrc = self.CurrencyReasonFor and self:CurrencyReasonFor(kind, id, dir) or nil
  return L.PickReason(kind, dir, ctx)
end

function R:ReasonFor(holder, key, dir, clock)
  local mk = holder .. "\001" .. tostring(key) .. "\001" .. dir
  return self.reasonMemo[mk] or computeReason(self, key, dir, clock)
end

local function memoReasons(self, plan, clock)
  for holder, net in pairs(plan.net) do
    for key, dlt in pairs(net) do
      local dir = dlt > 0 and "IN" or "OUT"
      local mk = holder .. "\001" .. tostring(key) .. "\001" .. dir
      if not self.reasonMemo[mk] then self.reasonMemo[mk] = computeReason(self, key, dir, clock) end
    end
  end
end

-- What can still be waiting for its other half: items while a bank, mailbox or auction house is
-- open (a deposit, a mail take, a post), gold only at a bank (warband gold). A one-sided gold change
-- at a mailbox (postage) or a vendor has no other half coming and is never held for one.
function R:DecideHold(plan, clock)
  if self.forceReason or self.silent then return false end
  local itemPairing = self.readable.bank or self.readable.mail or self.readable.auctionHouse
  local goldPairing = self.readable.bank
  local oneSided, unclaimed = false, false
  for _, net in pairs(plan.net) do
    for key, dlt in pairs(net) do
      local isItem = tostring(key):sub(1, 2) == "i:"
      if (isItem and itemPairing) or (key == "g" and goldPairing) then oneSided = true end
      if dlt > 0 and L.ClaimAvailable(self.claims, key, clock) < dlt then unclaimed = true end
    end
  end
  local hold = L.ShouldHold(oneSided, unclaimed, self._holdSince, clock)
  if hold then memoReasons(self, plan, clock) end
  return hold
end

-- Commit step 1: consume chat claims against gains; the matched chat rows are stamped as the
-- ledger rows they now are (spec §5.3), and only the unclaimed remainder becomes a diff row.
R.COMMIT_STEPS[#R.COMMIT_STEPS + 1] = function(self, plan, _, clock)
  if self.forceReason then return end
  for holder, net in pairs(plan.net) do
    for key, dlt in pairs(net) do
      if dlt > 0 then
        local rest, matched = L.ConsumeClaim(self.claims, key, dlt, clock)
        for _, row in ipairs(matched or {}) do
          row.dir, row.holder, row.claimed = "IN", holder, true
          row.kind = NS.Util.RowKind(row)
        end
        net[key] = (rest ~= 0) and rest or nil
      end
    end
  end
end

-- ── Currency deltas and account transfers (timeline-ledger spec §5.2) ───────────────────────

-- CURRENCY_DISPLAY_UPDATE carries the change itself (timeline-ledger spec §5.2), so currency needs
-- no list rescan: the delta is folded into a per-id accumulator (combat-safe, no allocation after a
-- currency's first event) and the raw source/destroy enums are kept for the reason. A nil id is the
-- client's bulk refresh: rescan the whole list instead, and drop the category resolver's cache.
function R:OnCurrencyUpdate(id, change, gainSrc, lostSrc)
  if not id then
    Compat.CurrencyListChanged()   -- the list may have changed: a missed id may be listed now
    self:MarkDirty("currency"); scheduleFlush(self); return
  end
  if not change or change == 0 then return end
  self.pendingCur[id] = (self.pendingCur[id] or 0) + change
  if gainSrc ~= nil then self.curGain[id] = gainSrc end
  if lostSrc ~= nil then self.curLoss[id] = lostSrc end
  self:MarkDirty("currencyDelta"); scheduleFlush(self)
end

function R:CurrencyReasonFor(kind, id, dir)
  if kind ~= "CURRENCY" then return nil end
  local name = Compat.CurrencySourceName(self.curGain[id], self.curLoss[id], dir == "IN" and 1 or -1)
  return L.CurrencyReason(name, dir)
end

-- Scan step: the pending deltas become a currency map per holder (account-wide -> §warband),
-- built on the stored baseline. A full list rescan in the same pass is authoritative instead, and
-- so is a holder with no currency baseline yet (a delta on nothing would invent its whole balance)
-- or a delta for an id the baseline does not hold: the event also carries hidden and tracking
-- currencies the list never shows, and a folded one would come back as an UNTRACKED OUT at the
-- next full rescan. A genuinely new currency is listed, so the rescan picks it up.
R.SCAN_STEPS[#R.SCAN_STEPS + 1] = function(self, snap, me)
  if not self.dirty.currencyDelta or self.dirty.currency then return end
  for id, dlt in pairs(self.pendingCur) do
    local holder = Compat.CurrencyIsAccountWide(id) and WARBAND or me
    local s = snapFor(snap, holder)
    local e = NS.Holdings:Get(holder)
    if not (e and e.scanned.currency and e.currency[id] ~= nil) then
      local ch, wb = NS.Scanner.ScanCurrencies()
      snapFor(snap, me).currency = ch
      snapFor(snap, WARBAND).currency = wb
      return
    end
    if not s.currency then
      s.currency = {}
      for k, v in pairs(e.currency) do s.currency[k] = v end
    end
    local v = (s.currency[id] or 0) + dlt
    s.currency[id] = (v > 0) and v or nil
  end
end

-- Plan step: a warband-transferable currency sent to an own alt (CURRENCY_TRANSFER_LOG_UPDATE) is a
-- holder move: an OUT here and an IN on the alt, both CURRENCY_TRANSFER. Whatever the transfer
-- consumed beyond the amount received stays a plain OUT (reason TRANSFER — the transfer's cost).
R.PLAN_STEPS[#R.PLAN_STEPS + 1] = function(self, plan, me)
  local net = plan.net[me]
  if not (net and self.pendingTransfer) then return end
  local t = Compat.LatestCurrencyTransfer()
  if not (t and t.currencyID and t.toKey and t.toKey ~= me) then return end
  local key = L.ThingKey("CURRENCY", t.currencyID)
  local dlt = net[key]
  if not dlt or dlt >= 0 then return end
  local q = math.min(-dlt, t.quantity or 0)
  if q <= 0 then return end
  plan.pairs[#plan.pairs + 1] = { key = key, qty = q, from = me, to = t.toKey,
    fromC = "currency", toC = "currency", creditCurrency = t.currencyID, reason = "CURRENCY_TRANSFER" }
  net[key] = (dlt + q ~= 0) and (dlt + q) or nil
end

-- Commit step: credit the recipient's stored currency, freeze the currency reasons into the memo
-- (WriteRows runs after this), then clear the accumulators. A bank drift pass sets the currency
-- delta aside, so it leaves them for the normal pass that follows.
R.COMMIT_STEPS[#R.COMMIT_STEPS + 1] = function(self, plan, _, clock)
  for _, p in ipairs(plan.pairs) do
    if p.creditCurrency then NS.Holdings:CreditCurrency(p.to, p.creditCurrency, p.qty) end
  end
  memoReasons(self, plan, clock)
  if self.drift then return end
  for k in pairs(self.pendingCur) do self.pendingCur[k] = nil end
  for k in pairs(self.curGain) do self.curGain[k] = nil end
  for k in pairs(self.curLoss) do self.curLoss[k] = nil end
  self.pendingTransfer = nil
end

local function applySnap(snap, now)
  local Hd, changed = NS.Holdings, {}
  for holder, s in pairs(snap) do
    for c, counts in pairs(s.items) do
      if Hd:ApplyContainer(holder, c, counts, s.links, now) then changed[holder] = true end
    end
    if s.money ~= nil and Hd:ApplyMoney(holder, s.money, now) then changed[holder] = true end
    if s.currency and Hd:ApplyCurrency(holder, s.currency, now) then changed[holder] = true end
    if s.bankSlots then Hd:NoteBankSlots(holder, s.bankSlots) end
  end
  return changed
end

-- ── The row writer ──────────────────────────────────────────────────────────────────────────

local function rowAllowed(kind, id)
  local p = NS.db.profile
  local s = p.settings
  if kind == "ITEM" then return not (p.blacklist and p.blacklist[id]) end
  if kind == "CURRENCY" then
    return s.recordCurrency ~= false and not (p.currencyBlacklist and p.currencyBlacklist[id])
  end
  return s.recordGold ~= false
end

local function linkFor(holder, id)
  for _, h in ipairs({ holder, NS.Util.PlayerKey(), WARBAND }) do
    local e = NS.Holdings:Get(h)
    if e and e.links[id] then return e.links[id] end
  end
  return "item:" .. id
end

-- Called as R:MakeRow(...); it reads no Reconciler state, hence the `_` receiver.
function R.MakeRow(_, holder, kind, id, dir, reason, qty, now, from, to, pairId)
  local zone, subzone = NS.Zone()
  local row = {
    ts = now, char = NS.Util.PlayerKey(), classFile = Compat.PlayerClassFile(),
    holder = holder, dir = dir, kind = kind, quantity = qty, source = reason,
    confidence = (reason == "OTHER" or reason == "UNTRACKED") and C.Confidence.INFERRED or C.Confidence.CERTAIN,
    zone = zone, subzone = subzone, mapID = NS.PlayerMapID(), from = from, to = to, pairId = pairId,
  }
  if kind == "ITEM" then
    local link = linkFor(holder, id)
    local _, name, quality = NS.Compat.GetItemInfo(link)
    local ilvl, bound, sell, itype, isub = NS.Compat.GetItemExtras(link)
    row.itemID, row.itemLink, row.itemName, row.quality = id, link, name or ("item:" .. id), quality
    row.itemLevel, row.bound, row.vendorPrice, row.itemType, row.itemSubType = ilvl, bound, sell, itype, isub
    if dir ~= "MOVE" then row.auctionPrice = NS.AuctionPrice:GatherAll(link, id) end
  elseif kind == "CURRENCY" then
    row.currencyID = id
    row.itemName = NS.Compat.CurrencyName(id) or ("currency:" .. id)
    row.itemType, row.itemSubType = C.CURRENCY_TYPE, NS.Compat.CurrencyCategory(id)
    row.quality, row.bound = NS.Compat.CurrencyQuality(id), NS.Compat.CurrencyBound(id)
  else
    row.itemName, row.itemType = "Gold", C.GOLD_TYPE
  end
  return row
end

-- Write one ledger row, or amend the same-key row written under COALESCE_WINDOW seconds ago. An
-- amended row keeps the pairId it was written with. The row is read back through Database:History,
-- the session store during a simulation (req-lh-sim §4).
function R:Write(holder, key, dir, reason, qty, now, from, to, pairId)
  local kind, id = L.ParseThingKey(key)
  if not kind or qty <= 0 or not rowAllowed(kind, id) then return nil end
  local ck = L.CoalesceKey(holder, key, dir, reason, from and (from .. ">" .. (to or "")) or nil)
  local recent = self.recent[ck]
  if L.Amendable(recent, now) and NS.Database:History()[recent.index] == recent.row then
    NS.Database:Amend(recent.index, qty)
    return recent.row
  end
  local row = self:MakeRow(holder, kind, id, dir, reason, qty, now, from, to, pairId)
  local index = NS.Database:Add(row)
  self.recent[ck] = { row = row, index = index, ts = now }
  return row
end

-- The CONTAINER a pair end names for a thing ("money", "currency", bags or tabs), not the holder
-- half of a location string: that is NS.Ledger.LocationHolder's job.
local function containerFor(key, holder, explicit)
  if explicit then return explicit end
  if key == "g" then return "money" end
  if tostring(key):sub(1, 2) == "c:" then return "currency" end
  return holder == WARBAND and CT.TABS or CT.BAGS
end

-- A move between two holders (timeline-ledger Phase 7): the sender's OUT and the receiver's IN share
-- one pairId, `ts:n`. If the OUT amended a row inside the coalescing window, the IN takes that row's id.
-- An own-alt mail (`senderOnly`) has its IN written when the alt takes it, in another pass and often
-- another session, so neither half carries a pairId: an id only the OUT held would read as an orphan.
local function writePair(self, p, now, from, to)
  local reason = p.reason or "TRANSFER"
  if p.senderOnly then
    self:Write(p.from, p.key, "OUT", reason, p.qty, now, from, to)
    return
  end
  self.pairSeq = (self.pairSeq or 0) + 1
  local out = self:Write(p.from, p.key, "OUT", reason, p.qty, now, from, to, now .. ":" .. self.pairSeq)
  self:Write(p.to, p.key, "IN", reason, p.qty, now, from, to, out and out.pairId or nil)
end

-- A swap between the bags and what you wear (a fishing pole equipped in place of a weapon, a bag put in
-- a bag slot) moves nothing anywhere, so it writes no row (the owner, 2026-11-27: "Swapping a weapon
-- for a fishing pole counts as a transfer - this should not happen"). It is still classified as a move,
-- so neither side reads as a loss or a gain; only the Transfer row is left out.
local function isSwap(mv)
  return (mv.from == CT.BAGS and mv.to == CT.EQUIPPED) or (mv.from == CT.EQUIPPED and mv.to == CT.BAGS)
end

local function writeMoves(self, plan, now)
  for _, mv in ipairs(plan.moves) do
    local key, from, to = L.ThingKey("ITEM", mv.id), mv.holder .. "/" .. mv.from, mv.holder .. "/" .. mv.to
    -- What an own alt mailed is that alt's move landing here: a gain (Escrow marks it `alt`).
    local alt = mv.alt or 0
    if alt > 0 then self:Write(mv.holder, key, "IN", "ALT_MAIL", alt, now, from, to) end
    if not isSwap(mv) then self:Write(mv.holder, key, "MOVE", "TRANSFER", mv.qty - alt, now, from, to) end
  end
end

local function writePairs(self, plan, now)
  for _, p in ipairs(plan.pairs) do
    local from = p.from .. "/" .. containerFor(p.key, p.from, p.fromC)
    local to = p.to .. "/" .. containerFor(p.key, p.to, p.toC)
    if p.to ~= p.from then writePair(self, p, now, from, to)
    -- A pair within one holder is one row (an alt's gold taken from mail: its `dir` says IN).
    else self:Write(p.from, p.key, p.dir or "MOVE", p.reason or "TRANSFER", p.qty, now, from, to) end
  end
end

local function writeNet(self, plan, now, clock)
  for holder, net in pairs(plan.net) do
    for key, dlt in pairs(net) do
      local dir = dlt > 0 and "IN" or "OUT"
      self:Write(holder, key, dir, self:ReasonFor(holder, key, dir, clock), math.abs(dlt), now)
    end
  end
end

-- Moves, then pairs, then plan steps' extra rows, then each holder's remaining net change.
function R:WriteRows(plan, now, clock)
  -- A genesis pass applies holdings and writes nothing, whatever a plan step added.
  if self.silent then self.reasonMemo = {}; return end
  writeMoves(self, plan, now)
  writePairs(self, plan, now)
  for _, x in ipairs(plan.extra or {}) do self:Write(x.holder, x.key, x.dir, x.reason, x.qty, now) end
  writeNet(self, plan, now, clock)
  self.reasonMemo = {}
end

-- ── Claims API (the chat paths post here, Task 8) ───────────────────────────────────────────
function R:PostClaim(key, qty, row)
  if not self._enabled or not key or not qty or qty <= 0 then return end
  L.PostClaim(self.claims, key, qty, row, GetTime())
end

-- ── Flush ───────────────────────────────────────────────────────────────────────────────────

-- While holding, look again every CLAIM_WAIT seconds (bounded by SETTLE_TIMEOUT in ShouldHold).
-- Events drive the real re-checks; this is the deadline. `_flushing` stops a deferral that runs
-- straight through (no C_Timer) from re-entering Flush.
-- `_recheck` holds the NS.After handle, so ResetState can cancel exactly this fuse; it is `true`
-- only for the instant the deferral is being armed, which is what stops a straight-through run
-- from arming a second one.
function R:ScheduleRecheck()
  if self._recheck then return end
  self._recheck = true
  local h = NS.After(L.CLAIM_WAIT, function()
    self._recheck = nil
    if not self._flushing then self:Flush() end
  end)
  self._recheck = h
end

local function clearReadDirty(self)
  for part in pairs(self.dirty) do
    if self:IsReadable(part) then self.dirty[part] = nil end
  end
end

-- Holders seen in this pass: a warband entry with no genesis gets it now (its first scan), and a
-- character's `partial` flag is recomputed once its bank has been read.
local function settleGenesis(snap, now)
  for holder in pairs(snap) do
    local e = NS.Holdings:Get(holder)
    if e and (e.meta.genesis or holder == WARBAND) then NS.Holdings:MarkGenesis(holder, now) end
  end
end

local function flushBody(self)
  local me, now, clock = NS.Util.PlayerKey(), time(), GetTime()
  L.PruneClaims(self.claims, clock)
  local snap = self:Scan(me)
  local plan = self:Plan(snap, me, clock)
  if self:DecideHold(plan, clock) then
    self._holdSince = self._holdSince or clock
    self:ScheduleRecheck()
    return
  end
  self._holdSince = nil
  for _, step in ipairs(R.COMMIT_STEPS) do step(self, plan, me, clock, now) end
  local changed = applySnap(snap, now)
  self:WriteRows(plan, now, clock)
  clearReadDirty(self)
  if not self.silent then settleGenesis(snap, now) end
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

-- Bank drift (timeline-ledger spec §5.6, P4 Task 4). The bank and the warband tabs are only
-- readable at a banker, so whatever changed there while the addon was not watching (disabled, or
-- another PC) is first seen on the opening read of the next visit. That read runs as its own pass
-- over these parts alone, like a login: UNTRACKED, no hold, no pairing, no claims. Every other dirty
-- part keeps normal classification in the pass that follows. A container never read before has no
-- baseline, so its first read is its genesis (no rows) either way.
-- A drift read that waited for a loading bank (R8) runs after whatever the player did meanwhile,
-- so it reads the bags beside the bank: a stack moved between them in the wait then pairs as one
-- MOVE (an intra-holder move is classified even here), where a bank-only read would book its bank
-- half as UNTRACKED and leave the bags half one-sided (LH-REV). Any other bag change of the wait is
-- UNTRACKED with the rest of the drift.
local DRIFT_PARTS = bankParts()
local DRIFT_PARTS_WAITED = bankParts()
DRIFT_PARTS_WAITED[#DRIFT_PARTS_WAITED + 1] = "bags"

local function driftPass(self)
  local rest, only = self.dirty, {}
  for _, p in ipairs(self._driftWaited and DRIFT_PARTS_WAITED or DRIFT_PARTS) do
    if rest[p] then only[p], rest[p] = rest[p], nil end
  end
  self._driftWaited = nil
  -- A hold the normal pass is in (its start, its memoized reasons) survives the drift pass.
  -- So does a login's UNTRACKED (a combat login deferred to the regen edge with the banker open).
  local memo, since, prevForce = self.reasonMemo, self._holdSince, self.forceReason
  self.dirty, self.reasonMemo = only, {}
  self.forceReason, self.drift = C.SourceType.UNTRACKED, true
  flushBody(self)
  self.forceReason, self.drift = prevForce, nil
  self.reasonMemo, self._holdSince = memo, since
  for p in pairs(self.dirty) do rest[p] = true end         -- anything the pass could not read
  self.dirty = rest
end

-- A loading bank looks again at the readiness deadline (R.READY_WAIT after the open), besides the
-- re-read cues. Armed only from inside Flush, so a deferral that runs straight through (headless
-- without C_Timer) sees `_flushing` and cannot recurse.
local function scheduleReadyCheck(self)
  if self._readyCheck then return end
  local left = R.READY_WAIT - (GetTime() - (self._bankOpenAt or GetTime()))
  self._readyCheck = true
  local h = NS.After(left > 0 and left or 0, function()
    self._readyCheck = nil
    if self.readable.bank and not self._flushing then self:Flush() end
  end)
  self._readyCheck = h
end

--- Scan, plan, then hold or commit. A part that is not readable (the bank with no banker open, or
--- a bank still loading or not shown at this banker, R8) stays dirty for the next flush; in combat
--- the whole pass waits for the regen edge. While the visit's drift read waits for a loading bank,
--- the whole pass waits with it (every part stays dirty), so nothing is classified before the bank
--- is; it answers "waiting" then. A login pass (silent or UNTRACKED) never waits: it is its own
--- read, and its genesis stamp follows it.
function R:Flush()
  if Compat.InCombatLockdown() then
    self.deferred, self._deferredAt = true, self._deferredAt or GetTime()
    return
  end
  if self._deferredAt then
    L.HoldClaims(self.claims, self._deferredAt, GetTime())
    self._deferredAt = nil
  end
  self._flushing = true
  local state = self:BankState()
  local waiting = self.driftPending and state == "loading" and not (self.silent or self.forceReason)
  if waiting then self._driftWaited = true
  elseif self.driftPending and state and state ~= "loading" then self.driftPending = nil; driftPass(self) end
  if not waiting then flushBody(self) end
  if state == "loading" then scheduleReadyCheck(self) end
  self._flushing = nil
  return waiting and "waiting" or nil
end

--- Genesis for this character, and for the warband when its gold was read (spec §5.6). Called as
--- R:MarkLoginGenesis(); it reads no Reconciler state, hence the `_` receiver.
function R.MarkLoginGenesis(_)
  local now = time()
  NS.Holdings:MarkGenesis(NS.Util.PlayerKey(), now)
  if NS.Holdings:Get(WARBAND) then NS.Holdings:MarkGenesis(WARBAND, now) end
end

-- Login reconcile (timeline-ledger spec §5.6). The first login after v11 writes the snapshot as
-- this holder's GENESIS and no rows. Every later login diffs against the stored snapshot: whatever
-- changed while the addon was not watching is written as UNTRACKED — no holds (nothing is in
-- flight), no claims (no chat line belongs to it) — so holdings and the rows reconcile. The bank
-- and the warband tabs need the banker, so a fresh holder stays `partial` until then. A login
-- inside combat (a reload mid-pull) defers the read AND the genesis stamp to the regen edge, so
-- genesis never lands on a holder that was not actually scanned.
local LOGIN_PARTS = { "bags", "equipped", "money", "currency" }
if WARBAND_BANK then LOGIN_PARTS[#LOGIN_PARTS + 1] = "warbandMoney" end

function R:LoginScan()
  self._sessionStarted = true
  if Compat.InCombatLockdown() then self.loginPending, self.deferred = true, true; return end
  self.loginPending, self.deferred = nil, nil
  for _, p in ipairs(LOGIN_PARTS) do self:MarkDirty(p) end
  local e = NS.Holdings:Get(NS.Util.PlayerKey())
  local first = not (e and e.meta.genesis)
  if first then self.silent = true else self.forceReason = C.SourceType.UNTRACKED end
  self:Flush()
  self.silent, self.forceReason = nil, nil
  self:MarkLoginGenesis()
end

-- The sixteen capture rows (core/Dispatch.lua) on the private `__ev` target, appended at FILE LOAD
-- so their order is TOC order. Each fn hands R:OnEvent the client's full payload; R:OnEvent keeps
-- its (event, a1, _, a3, a4, a5) shape because the suites drive it directly. ACCOUNT_MONEY and
-- PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED are the warband bank's (`clients`, clients-§4): fourteen
-- rows where it is absent. BAG_CONTAINER_UPDATE and BANK_TABS_CHANGED are the bank's re-read cues
-- (R8, both clients).
for _, row in ipairs({
  { "BAG_UPDATE" }, { "BAG_UPDATE_DELAYED" }, { "PLAYER_EQUIPMENT_CHANGED" }, { "PLAYER_MONEY" },
  { "ACCOUNT_MONEY", clients = C.FEATURE_CLIENTS.warbandBank },
  { "CURRENCY_DISPLAY_UPDATE" }, { "PLAYERBANKSLOTS_CHANGED" },
  { "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", clients = C.FEATURE_CLIENTS.warbandBank },
  { "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" }, { "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }, { "PLAYER_REGEN_ENABLED" },
  { "CURRENCY_TRANSFER_LOG_UPDATE" }, { "MAIL_INBOX_UPDATE" }, { "OWNED_AUCTIONS_UPDATED" },
  { "BAG_CONTAINER_UPDATE" }, { "BANK_TABS_CHANGED" },
}) do
  if Compat.ForClient(row.clients) then
    NS.EventRow("Reconciler", "ledger", row[1], function(ev, ...) return R:OnEvent(ev, ...) end)
  end
end

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
  -- Per event through Core's helper (events-frames-taint-§1, inside NS.RegisterRows): a refused
  -- name costs only itself.
  NS.RegisterRows("Reconciler", self.__ev, "ledger")
  self._enabled = true
  -- Back up after a stand-down (disable, perf suspend) in a session that already logged in: what
  -- changed while nothing was watching is drift, exactly like a login.
  if self._sessionStarted then
    NS.After(1, function() if self._enabled then self:LoginScan() end end)
  end
end

--- Every piece of working state, cleared WITHOUT unregistering (LootHistory#37, req-lh-sim §3.4):
--- dirty bits, readable containers, claims, the coalescing map, memoized reasons, the currency
--- accumulators, the settle hold, and the flush and recheck fuses, each canceled by its own handle
--- (NS.CancelDeferral) so the login deferrals keep running. DisableCapture runs it on the way down;
--- the simulator runs it at start and stop, so a simulated claim never attributes the next real loot.
function R:ResetState()
  NS.CancelDeferral(self._pending)
  NS.CancelDeferral(self._recheck)
  NS.CancelDeferral(self._readyCheck)
  self.dirty, self.readable = {}, {}
  self.deferred, self._pending, self.driftPending = nil, nil, nil
  self._deferredAt = nil
  self._readyCheck, self._bankOpenAt, self._driftWaited = nil, nil, nil
  self.claims, self.recent, self.reasonMemo = {}, {}, {}
  self.pendingCur, self.curGain, self.curLoss, self.pendingTransfer, self.loginPending = {}, {}, {}, nil, nil
  self._holdSince, self._recheck = nil, nil
end

--- Capture off (trackLedger unticked) while the module keeps listening for the setting coming back.
function R:DisableCapture()
  NS.UnregisterRows("Reconciler")
  if self.__ev then self.__ev:UnregisterAllEvents(); self.__ev = nil end
  self:ResetState()
  self._enabled = nil
end

--- The full stand-down (slash-commands-§7): the capture events AND the settings listener. Called
--- from NS.StandDown; DisableCapture's ResetState cancels the two fuses, and NS.CancelDeferrals
--- (later in the same stand-down) everything else.
function R:Disable()
  self:DisableCapture()
  if self._settings then self._settings:UnregisterAllMessages(); self._settings = nil end
end

--- Announce `holders` (a list of holder keys) as changed, once each. The simulator's stop calls it
--- for its session store's holders (modules/Sim.lua), whose holdings every reader just stopped
--- seeing; it goes through here because the Reconciler is HOLDINGS_CHANGED's one sender
--- (docs/message-bus.md). Called as R:AnnounceHolders(holders); it reads no Reconciler state.
function R.AnnounceHolders(_, holders)
  for _, holder in ipairs(holders or {}) do NS.bus:SendMessage(NS.MSG.HOLDINGS_CHANGED, holder) end
end

-- "Forget this character" (spec §8.2): drop a character's holdings and its Timeline cells. History
-- rows are kept -- they are what happened. The logged-in character would be re-created by its next
-- scan, and the warband is not a character, so both are refused. The Reconciler announces the change
-- because it is HOLDINGS_CHANGED's one sender (docs/message-bus.md).
-- Called as R:ForgetHolder(holder); it reads no Reconciler state, hence the `_` receiver.
function R.ForgetHolder(_, holder)
  if NS.SimBlocks("Forget this character") then return false, "simulation" end
  if holder == nil or holder == WARBAND then return false, "warband" end
  if holder == NS.Util.PlayerKey() then return false, "current" end
  local had = NS.Holdings:ForgetHolder(holder)
  local cells = (NS.Rollup and NS.Rollup:ForgetHolder(holder)) or 0
  if not (had or cells > 0) then return false end
  NS.bus:SendMessage(NS.MSG.HOLDINGS_CHANGED, holder)
  return true
end
