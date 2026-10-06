local _, NS = ...
NS.Escrow = NS.Escrow or {}
local Escrow = NS.Escrow

-- Mail and auction-house escrow (timeline-ledger spec §3, §5.1 case 2, §5.4 AH rows). Plugs into
-- the Reconciler's SCAN/PLAN/COMMIT steps; owns no events (the readable flags and MAIL_INBOX_UPDATE
-- / OWNED_AUCTIONS_UPDATED are the Reconciler's), so it has nothing to stand down.
--
-- The rules: an arrival in mail or auctions is HOLDINGS-ONLY (no row) until it resolves —
--   * mail taken into bags: own-origin part is a MOVE, the rest a gain (Ledger.ClassifyItems);
--   * an auction that leaves the list: held as an EXIT until it comes back by mail (a return:
--     own-origin mail) or a sale mail names it (OUT AH_SOLD), or EXIT_TTL passes (sold).
-- Outbound: a send to an own alt is a MOVE pair into the alt's mail; a post is a MOVE into auctions.

local L = NS.Ledger
local R = NS.Reconciler
local C = NS.Constants

Escrow.EXIT_TTL = 30 * 86400

local function addLinks(dst, src) for id, l in pairs(src or {}) do if not dst[id] then dst[id] = l end end end

-- ── Scan ────────────────────────────────────────────────────────────────────────────────────
R.SCAN_STEPS[#R.SCAN_STEPS + 1] = function(self, snap, me)
  local d = self.dirty
  if d.mail and self:IsReadable("mail") then
    local s = R.SnapFor(snap, me)
    local c, l = NS.Compat.ScanInbox()
    s.items[C.Container.MAIL] = c; addLinks(s.links, l)
  end
  if d.auctions and self:IsReadable("auctions") then
    local s = R.SnapFor(snap, me)
    local c, l = NS.Compat.ScanOwnedAuctions()
    s.items[C.Container.AUCTIONS] = c; addLinks(s.links, l)
  end
end

-- ── Plan ────────────────────────────────────────────────────────────────────────────────────

-- Move a net entry `q` toward zero (q > 0 for a loss, q < 0 for a gain); zeros are removed.
local function reduce(net, key, q)
  local v = net[key] + q
  net[key] = (v ~= 0) and v or nil
end

-- A sent mail to an own alt: what left the bags/purse is that alt's mail now.
local function planMail(_, plan, me, clock)
  local p, net = NS.State.pendingMail, plan.net[me]
  if not (p and p.sent and p.to and p.expires >= clock and net) then return end
  for id, n in pairs(p.items) do
    local key = L.ThingKey("ITEM", id)
    local dlt = net[key]
    if dlt and dlt < 0 then
      local q = math.min(-dlt, n)
      plan.pairs[#plan.pairs + 1] = { key = key, qty = q, from = me, to = p.to,
        fromC = C.Container.BAGS, toC = C.Container.MAIL, creditMail = id }
      reduce(net, key, q)
    end
  end
  if (p.money or 0) > 0 and net.g and net.g < 0 then
    local q = math.min(-net.g, p.money)
    plan.pairs[#plan.pairs + 1] = { key = "g", qty = q, from = me, to = p.to, fromC = "money",
      toC = C.Container.MAIL, creditMailMoney = true }
    reduce(net, "g", q)
  end
  plan.mailConsumed = true
end

-- A post: what left the bags is in this character's auctions now (before the owned list says so).
local function planPost(_, plan, me)
  local net = plan.net[me]
  if not net then return end
  for id, n in pairs(NS.State.pendingPost) do
    local key = L.ThingKey("ITEM", id)
    local dlt = net[key]
    if dlt and dlt < 0 then
      local q = math.min(-dlt, n)
      plan.moves[#plan.moves + 1] = { holder = me, id = id, qty = q, from = C.Container.BAGS,
        to = C.Container.AUCTIONS, creditAuctions = true }
      reduce(net, key, q)
    end
  end
end

-- Gold an own alt mailed in: taking it is a MOVE inside this holder (mail -> money).
local function planMailMoney(self, plan, me)
  local net, e = plan.net[me], NS.Holdings:Get(me)
  local esc = e and e.escrow
  if not (net and net.g and net.g > 0 and esc and (esc.mailMoney or 0) > 0 and self.readable.mail) then return end
  local q = math.min(net.g, esc.mailMoney)
  plan.pairs[#plan.pairs + 1] = { key = "g", qty = q, from = me, to = me, fromC = C.Container.MAIL,
    toC = "money", debitMailMoney = q }
  reduce(net, "g", -q)                                     -- a gain: reduce toward zero from above
end

local function itemName(e, id)
  local _, name = NS.Compat.GetItemInfo((e and e.links[id]) or ("item:" .. id))
  return name
end

-- Exits: a mail arrival of an exited item is its return; a sale mail naming it is its sale; an exit
-- older than EXIT_TTL is booked as sold. Never on a genesis pass, which writes no rows: a sale
-- resolved there would leave the exit gone and its OUT row never written.
local function planExits(self, plan, me, clock, now)
  plan.returns, plan.sold, plan.extra = {}, {}, plan.extra or {}
  if self.silent then return end
  local e = NS.Holdings:Get(me)
  local esc = e and e.escrow
  local arrived = plan.arrivals[me] and plan.arrivals[me].mail or {}
  if esc then
    for id, x in pairs(esc.exits) do
      local back = math.min(arrived[id] or 0, x.n)
      if back > 0 then plan.returns[id] = back end
    end
    local sold = NS.State.soldMail
    for id, x in pairs(esc.exits) do
      local left = x.n - (plan.returns[id] or 0)
      local byMail = sold and sold.expires >= clock and sold.itemName and sold.itemName == itemName(e, id)
      if left > 0 and (byMail or (now - x.ts) >= Escrow.EXIT_TTL) then
        plan.sold[id] = left
        plan.extra[#plan.extra + 1] = { holder = me, key = L.ThingKey("ITEM", id), dir = "OUT",
          reason = "AH_SOLD", qty = left }
      end
    end
  end
end

R.PLAN_STEPS[#R.PLAN_STEPS + 1] = planMail
R.PLAN_STEPS[#R.PLAN_STEPS + 1] = planPost
R.PLAN_STEPS[#R.PLAN_STEPS + 1] = planMailMoney
R.PLAN_STEPS[#R.PLAN_STEPS + 1] = function(self, plan, me, clock) planExits(self, plan, me, clock, time()) end

-- ── Commit ──────────────────────────────────────────────────────────────────────────────────
local function commitPairs(plan)
  local Hd = NS.Holdings
  for _, p in ipairs(plan.pairs) do
    if p.creditMail then Hd:CreditEscrow(p.to, C.Container.MAIL, p.creditMail, p.qty, true) end
    if p.creditMailMoney and Hd:Get(p.to) then
      local esc = Hd:Escrow(p.to); esc.mailMoney = (esc.mailMoney or 0) + p.qty
    end
    if p.debitMailMoney then
      local esc = Hd:Escrow(p.from); esc.mailMoney = math.max(0, (esc.mailMoney or 0) - p.debitMailMoney)
    end
  end
end

local function commitMoves(plan)
  local Hd = NS.Holdings
  for _, mv in ipairs(plan.moves) do
    if mv.creditAuctions then
      Hd:CreditEscrow(mv.holder, C.Container.AUCTIONS, mv.id, mv.qty, false)
      local left = (NS.State.pendingPost[mv.id] or 0) - mv.qty
      NS.State.pendingPost[mv.id] = (left > 0) and left or nil
    end
    if mv.from == C.Container.MAIL then
      local own = Hd:Escrow(mv.holder).mailOwn
      local left = (own[mv.id] or 0) - mv.qty
      own[mv.id] = (left > 0) and left or nil
    end
  end
end

local function commitExits(plan, me, now)
  local hasExits = next(plan.exits[me] or {}) ~= nil
  local e = NS.Holdings:Get(me)
  if not (e and (e.escrow or hasExits)) then return end
  local esc = NS.Holdings:Escrow(me)
  for id, n in pairs(plan.exits[me] or {}) do
    local x = esc.exits[id] or { n = 0 }
    x.n, x.ts = x.n + n, now
    esc.exits[id] = x
  end
  for id, back in pairs(plan.returns or {}) do
    esc.mailOwn[id] = (esc.mailOwn[id] or 0) + back
    esc.exits[id].n = esc.exits[id].n - back
  end
  for id, n in pairs(plan.sold or {}) do esc.exits[id].n = esc.exits[id].n - n end
  for id, x in pairs(esc.exits) do if x.n <= 0 then esc.exits[id] = nil end end
  if next(plan.sold or {}) then NS.State.soldMail = nil end
end

R.COMMIT_STEPS[#R.COMMIT_STEPS + 1] = function(_, plan, me, _, now)
  commitPairs(plan)
  commitMoves(plan)
  commitExits(plan, me, now or time())
  if plan.mailConsumed then NS.State.pendingMail = nil end
end
