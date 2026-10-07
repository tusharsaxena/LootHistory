local _, NS = ...
NS.Escrow = NS.Escrow or {}
local Escrow = NS.Escrow

-- Mail and auction-house escrow (timeline-ledger spec §3, §5.1 case 2, §5.4 AH rows). Plugs into
-- the Reconciler's SCAN/PLAN/COMMIT steps; owns no events (the readable flags and MAIL_INBOX_UPDATE
-- / OWNED_AUCTIONS_UPDATED are the Reconciler's), so it has nothing to stand down.
--
-- The rules: an arrival in mail or auctions is HOLDINGS-ONLY (no row) until it resolves —
--   * mail taken into bags: own-origin part is a MOVE, the rest a gain (Ledger.ClassifyItems); the
--     part an own alt sent (`mailAlt`) is that alt's move landing: an IN ALT_MAIL;
--   * an auction that leaves the list: held as an EXIT until it comes back by mail (a return:
--     own-origin mail) or a sale mail names it (OUT AH_SOLD), or EXIT_TTL passes (sold).
-- Outbound: a send to an own alt is an OUT ALT_MAIL here and an in-flight credit of the alt's mail
-- (its IN is written when the alt takes it, timeline-ledger Phase 7); a post is a MOVE into auctions.

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

-- A sent mail to an own alt: what left the bags/purse is that alt's mail now. Two holders, so the
-- sender writes its OUT now (`senderOnly`) and the alt its IN when it takes the mail.
local function planMail(_, plan, me, clock)
  local p, net = NS.State.pendingMail, plan.net[me]
  if not (p and p.sent and p.to and p.expires >= clock and net) then return end
  for id, n in pairs(p.items) do
    local key = L.ThingKey("ITEM", id)
    local dlt = net[key]
    if dlt and dlt < 0 then
      local q = math.min(-dlt, n)
      plan.pairs[#plan.pairs + 1] = { key = key, qty = q, from = me, to = p.to,
        fromC = C.Container.BAGS, toC = C.Container.MAIL, creditMail = id, reason = "ALT_MAIL", senderOnly = true }
      reduce(net, key, q)
    end
  end
  if (p.money or 0) > 0 and net.g and net.g < 0 then
    local q = math.min(-net.g, p.money)
    plan.pairs[#plan.pairs + 1] = { key = "g", qty = q, from = me, to = p.to, fromC = "money",
      toC = C.Container.MAIL, creditMailMoney = true, reason = "ALT_MAIL", senderOnly = true }
    reduce(net, "g", q)
  end
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

-- Gold an own alt mailed in: taking it is the alt's move landing here, an IN ALT_MAIL (mail -> money,
-- one row: the alt wrote its OUT when it sent the gold). Only the part credited since Phase 7
-- (`mailMoneyAlt`) is: gold sent before it already has its pair (v13 makes that an OUT + IN), so
-- the rest of mailMoney is a MOVE as it always was. The alt part is taken first: a stale legacy
-- balance (a send that came back) must not turn new alt gold into MOVEs. Not while a
-- sale mail's payout is live (that gold is AH_SOLD), and not when the mail just taken names a
-- sender who is not an own holder (another player's gold is a gain). A take the TakeInboxMoney
-- hook never saw (no mailTaken) falls back to the mailMoney balance alone.
-- The guards, in order: a gold gain, a mail money balance, a readable mailbox; then neither a live
-- sale mail nor a just-taken mail from someone who is not an own holder.
local function mailMoneyGain(self, net, esc)
  if not (net and net.g and net.g > 0) then return false end
  return esc ~= nil and (esc.mailMoney or 0) > 0 and self.readable.mail and true or false
end

local function mailMoneyMasked(clock)
  local sold, taken = NS.State.soldMail, NS.State.mailTaken
  if sold and sold.expires >= clock then return true end
  return (taken and taken.expires >= clock and not taken.own) and true or false
end

local function planMailMoney(self, plan, me, clock)
  local net, e = plan.net[me], NS.Holdings:Get(me)
  local esc = e and e.escrow
  if not mailMoneyGain(self, net, esc) or mailMoneyMasked(clock) then return end
  local q = math.min(net.g, esc.mailMoney)
  local alt = math.min(q, esc.mailMoneyAlt or 0)
  if alt > 0 then
    plan.pairs[#plan.pairs + 1] = { key = "g", qty = alt, from = me, to = me, fromC = C.Container.MAIL,
      toC = "money", debitMailMoney = alt, debitMailMoneyAlt = alt, dir = "IN", reason = "ALT_MAIL" }
  end
  if q > alt then
    plan.pairs[#plan.pairs + 1] = { key = "g", qty = q - alt, from = me, to = me, fromC = C.Container.MAIL,
      toC = "money", debitMailMoney = q - alt }
  end
  reduce(net, "g", -q)                                     -- a gain: reduce toward zero from above
end

-- Mail taken into bags: the part of its own-origin MOVE that an own alt sent (`escrow.mailAlt`, a
-- subset of mailOwn) is marked `alt`; the row writer books it as an IN ALT_MAIL, the rest a MOVE.
local function planMailAlt(_, plan)
  for _, mv in ipairs(plan.moves) do
    if mv.from == C.Container.MAIL then
      local e = NS.Holdings:Get(mv.holder)
      local alt = e and e.escrow and e.escrow.mailAlt
      local n = alt and alt[mv.id] or 0
      if n > 0 then mv.alt = math.min(n, mv.qty) end
    end
  end
end

local function itemName(e, id)
  local _, name = NS.Compat.GetItemInfo((e and e.links[id]) or ("item:" .. id))
  return name
end

-- A live sale mail naming the item, or an exit older than EXIT_TTL.
local function exitSold(e, id, x, saleName, now)
  if saleName and saleName == itemName(e, id) then return true end
  return (now - x.ts) >= Escrow.EXIT_TTL
end

-- A mail arrival of an exited item, up to the exit's count, is its return.
local function planReturns(returns, esc, arrivals)
  local arrived = arrivals and arrivals.mail or {}
  for id, x in pairs(esc.exits) do
    local back = math.min(arrived[id] or 0, x.n)
    if back > 0 then returns[id] = back end
  end
end

-- The item name a sale mail still inside its window names, or nil.
local function liveSaleName(clock)
  local sold = NS.State.soldMail
  if sold and sold.expires >= clock then return sold.itemName end
  return nil
end

-- Exits: a mail arrival of an exited item is its return; a sale mail naming it is its sale; an exit
-- older than EXIT_TTL is booked as sold. Never on a genesis pass, which writes no rows: a sale
-- resolved there would leave the exit gone and its OUT row never written.
local function planExits(self, plan, me, clock, now)
  plan.returns, plan.sold, plan.extra = {}, {}, plan.extra or {}
  if self.silent then return end
  local e = NS.Holdings:Get(me)
  local esc = e and e.escrow
  if not esc then return end
  planReturns(plan.returns, esc, plan.arrivals[me])
  local saleName = liveSaleName(clock)
  for id, x in pairs(esc.exits) do
    local left = x.n - (plan.returns[id] or 0)
    if left > 0 and exitSold(e, id, x, saleName, now) then
      plan.sold[id] = left
      plan.extra[#plan.extra + 1] = { holder = me, key = L.ThingKey("ITEM", id), dir = "OUT",
        reason = "AH_SOLD", qty = left }
    end
  end
end

R.PLAN_STEPS[#R.PLAN_STEPS + 1] = planMail
R.PLAN_STEPS[#R.PLAN_STEPS + 1] = planPost
R.PLAN_STEPS[#R.PLAN_STEPS + 1] = planMailAlt
R.PLAN_STEPS[#R.PLAN_STEPS + 1] = planMailMoney
R.PLAN_STEPS[#R.PLAN_STEPS + 1] = function(self, plan, me, clock) planExits(self, plan, me, clock, time()) end

-- ── Commit ──────────────────────────────────────────────────────────────────────────────────
local function commitPairs(plan)
  local Hd = NS.Holdings
  for _, p in ipairs(plan.pairs) do
    if p.creditMail and Hd:CreditEscrow(p.to, C.Container.MAIL, p.creditMail, p.qty, true) then
      local alt = Hd:MailAlt(p.to)
      alt[p.creditMail] = (alt[p.creditMail] or 0) + p.qty
    end
    if p.creditMailMoney and Hd:Get(p.to) then
      local esc = Hd:Escrow(p.to); esc.mailMoney = (esc.mailMoney or 0) + p.qty
      esc.mailMoneyAlt = (esc.mailMoneyAlt or 0) + p.qty
    end
    if p.debitMailMoney then
      local esc = Hd:Escrow(p.from); esc.mailMoney = math.max(0, (esc.mailMoney or 0) - p.debitMailMoney)
      if p.debitMailMoneyAlt then
        esc.mailMoneyAlt = math.max(0, (esc.mailMoneyAlt or 0) - p.debitMailMoneyAlt)
      end
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
      if (mv.alt or 0) > 0 then
        local alt = Hd:MailAlt(mv.holder)
        left = (alt[mv.id] or 0) - mv.alt
        alt[mv.id] = (left > 0) and left or nil
      end
    end
  end
end

-- New exits join the item's pending one; the shared ts restarts (LH-R-06, a known limitation).
local function addExits(esc, exits, now)
  for id, n in pairs(exits) do
    local x = esc.exits[id] or { n = 0 }
    x.n, x.ts = x.n + n, now
    esc.exits[id] = x
  end
end

-- Returns become own-origin mail; returns and sales both draw the exit down, and a spent exit goes.
local function resolveExits(esc, returns, sold)
  for id, back in pairs(returns) do
    esc.mailOwn[id] = (esc.mailOwn[id] or 0) + back
    esc.exits[id].n = esc.exits[id].n - back
  end
  for id, n in pairs(sold) do esc.exits[id].n = esc.exits[id].n - n end
  for id, x in pairs(esc.exits) do if x.n <= 0 then esc.exits[id] = nil end end
end

local function commitExits(plan, me, now)
  local exits = plan.exits[me] or {}
  local e = NS.Holdings:Get(me)
  if not (e and (e.escrow or next(exits) ~= nil)) then return end
  local esc = NS.Holdings:Escrow(me)
  addExits(esc, exits, now)
  local sold = plan.sold or {}
  resolveExits(esc, plan.returns or {}, sold)
  if next(sold) then NS.State.soldMail = nil end
end

-- The staged send is used up only as far as it paired: a money-only pass (PLAYER_MONEY's fuse
-- before the bag change lands) leaves the items for the next pass; `expires` retires leftovers.
local function consumeMail(plan)
  local pm = NS.State.pendingMail
  if not pm then return end
  local any = false
  for _, p in ipairs(plan.pairs) do
    if p.creditMail then
      local left = (pm.items[p.creditMail] or 0) - p.qty
      pm.items[p.creditMail] = (left > 0) and left or nil
      any = true
    end
    if p.creditMailMoney then pm.money = math.max(0, (pm.money or 0) - p.qty); any = true end
  end
  if any and next(pm.items) == nil and (pm.money or 0) <= 0 then NS.State.pendingMail = nil end
end

R.COMMIT_STEPS[#R.COMMIT_STEPS + 1] = function(_, plan, me, _, now)
  commitPairs(plan)
  commitMoves(plan)
  commitExits(plan, me, now or time())
  consumeMail(plan)
end
