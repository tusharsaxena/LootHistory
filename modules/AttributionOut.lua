local _, NS = ...
NS.Attribution = NS.Attribution or {}
local Attribution = NS.Attribution

-- The LOSS side of attribution (timeline-ledger spec §5.4): where modules/Attribution.lua stamps
-- why something ARRIVED, this file stamps why something LEFT, and which interaction frame is open.
-- The Reconciler reads both through Attribution:ReasonContext when it writes a diff row.
--
-- Its own file and its own private bus target (`__outEv`), so Attribution:Enable's registration set
-- (pinned in tests/test_attribution.lua) is unchanged and this half tears down on its own.

local State = NS.State
local C = NS.Constants

local function stoodDown() return NS.IsStoodDown and NS.IsStoodDown() end

-- PLAYER_INTERACTION_MANAGER_FRAME_* type name -> scope key.
local SCOPE_OF = {
  Merchant = "merchant", Trainer = "trainer", TaxiNode = "taxi", MailInfo = "mailbox",
  Auctioneer = "auction", Banker = "bank", AccountBanker = "bank", GuildBanker = "guildBank",
}

function Attribution:StampOut(reason, opts, trigger)
  -- The hooksecurefunc carve-out (slash-commands-§7), second funnel: every hook below lands here or
  -- in one of the On* bodies, each of which checks the latch first, because a hook has no un-hook.
  if stoodDown() then
    if NS.State.debug and NS.Debug then NS.Debug("Attr", "stamp-out %s ignored: stood down", tostring(reason)) end
    return
  end
  State.outContext = {
    reason = reason,
    expires = GetTime() + ((opts and opts.ttl) or C.CONTEXT_TTL),
    dirs = opts and opts.dirs, kinds = opts and opts.kinds,
  }
  if NS.State.debug and NS.Debug then
    NS.Debug("Attr", "stamp-out %s%s", reason, trigger and (" via " .. trigger) or "")
  end
end

function Attribution:SetScope(name, on)
  if on then State.scopes[name] = true else State.scopes[name] = nil end
end

function Attribution:OnInteraction(shown, interactionType)
  for name, scope in pairs(SCOPE_OF) do
    if interactionType ~= nil and interactionType == NS.Compat.InteractionType(name) then
      self:SetScope(scope, shown)
      if NS.State.debug and NS.Debug then NS.Debug("Attr", "scope %s %s", scope, shown and "open" or "closed") end
    end
  end
end

-- One table, refilled per call: ReasonContext runs once per written row, out of combat.
local ctx = {}
function Attribution:ReasonContext(clock)
  ctx.now = clock
  ctx.out, ctx.loot, ctx.scopes, ctx.craftUntil = State.outContext, State.lootContext, State.scopes, State.craftUntil
  ctx.forced, ctx.consumable, ctx.currencySrc = nil, nil, nil
  return ctx
end

-- ── Hook bodies ─────────────────────────────────────────────────────────────────────────────

-- SendMail is a POST-hook: the attachments are still staged in the Send Mail frame when it runs
-- (to be verified by smoke LED-P2-06). The bags only change on MAIL_SEND_SUCCESS.
function Attribution:OnSendMail(recipient)
  if stoodDown() then return end
  local items, money = NS.Compat.ReadSendMail()
  local key = NS.Util.QualifyName(recipient)
  local own = key and key ~= NS.Util.PlayerKey() and NS.Holdings and NS.Holdings:Get(key) ~= nil
  State.pendingMail = { to = own and key or nil, items = items, money = money, sent = false, expires = GetTime() + 30 }
  self:StampOut("MAIL_SEND", { dirs = { OUT = true }, ttl = 30 }, "SendMail")
end

function Attribution:OnMailSent()
  local p = State.pendingMail
  if not p or stoodDown() then return end
  p.sent, p.expires = true, GetTime() + 10
  self:StampOut("MAIL_SEND", { dirs = { OUT = true } }, "MAIL_SEND_SUCCESS")
end

function Attribution:OnMailFailed() State.pendingMail = nil end

function Attribution:OnPost(itemLocation, quantity)
  if stoodDown() then return end
  local id = NS.Compat.ItemLocationID(itemLocation)
  if id then State.pendingPost[id] = (State.pendingPost[id] or 0) + (quantity or 1) end
  self:StampOut("AH_POST_FEE", { kinds = { GOLD = true }, dirs = { OUT = true }, ttl = 5 }, "PostAuction")
end

function Attribution:OnAuctionBuy()
  self:StampOut("AH_BUY", { kinds = { GOLD = true }, dirs = { OUT = true }, ttl = 5 }, "AuctionBuy")
end

-- Every money take records whether its sender is an own holder, so the escrow plan books only an
-- own alt's gold as a mail -> money MOVE (another player's gold, a sale payout, stay gains).
function Attribution:OnTakeInboxMoney(index)
  if stoodDown() then return end
  local sender, subject = NS.Compat.GetMailHeader(index)
  local key = NS.Util.QualifyName(sender)
  local own = key ~= nil and NS.Holdings ~= nil and NS.Holdings:Get(key) ~= nil
  State.mailTaken = { own = own, expires = GetTime() + 10 }
  local kind, itemName = NS.Compat.AuctionMailKind(subject)
  if kind == "sold" then
    State.soldMail = { itemName = itemName, expires = GetTime() + 10 }
    self:StampOut("AH_SOLD", { kinds = { GOLD = true }, dirs = { IN = true } }, "TakeInboxMoney")
  end
end

function Attribution:OnTradeAccept(playerAccepted, targetAccepted)
  if playerAccepted == 1 and targetAccepted == 1 then
    State.tradeTarget = NS.Compat.TradeTargetKey()
    self:StampOut("TRADE_GIVE", { dirs = { OUT = true } }, "trade-complete")
  end
end

function Attribution:OnCraft()
  if stoodDown() then return end
  State.craftUntil = GetTime() + C.CRAFT_TTL
end

-- Guild bank open/close: GuildBankFrame's own OnShow/OnHide (BankLedger: GUILDBANKFRAME_* never
-- fire on 12.x). The frame is load-on-demand, so this runs again on ADDON_LOADED and is idempotent.
function Attribution:HookGuildBankFrame()
  if self._guildHooked then return true end
  local frame = _G.GuildBankFrame
  if not (frame and type(frame.HookScript) == "function") then return false end
  self._guildHooked = true
  frame:HookScript("OnShow", function() if not stoodDown() then Attribution:SetScope("guildBank", true) end end)
  frame:HookScript("OnHide", function() Attribution:SetScope("guildBank", false) end)
  return true
end

-- Installed ONCE per session (hooksecurefunc has no un-hook); each body gates on the latch.
local function installHooks(self)
  if self._outHooked then return end
  self._outHooked = true
  local H, HM = NS.Compat.HookSecure, NS.Compat.HookSecureMember
  H("RepairAllItems", function() self:StampOut("REPAIR", { kinds = { GOLD = true }, dirs = { OUT = true } }, "RepairAllItems") end)
  H("BuyMerchantItem", function() self:StampOut("BUY", { dirs = { OUT = true } }, "BuyMerchantItem") end)
  H("BuybackItem", function() self:StampOut("BUY", { dirs = { OUT = true } }, "BuybackItem") end)
  H("DeleteCursorItem", function() self:StampOut("DESTROY", { kinds = { ITEM = true }, dirs = { OUT = true } }, "DeleteCursorItem") end)
  H("SendMail", function(recipient) self:OnSendMail(recipient) end)
  H("TakeInboxMoney", function(index) self:OnTakeInboxMoney(index) end)
  local AH = C_AuctionHouse
  HM(AH, "PostItem", function(loc, _, qty) self:OnPost(loc, qty) end)
  HM(AH, "PostCommodity", function(loc, _, qty) self:OnPost(loc, qty) end)
  HM(AH, "PlaceBid", function() self:OnAuctionBuy() end)
  HM(AH, "ConfirmCommoditiesPurchase", function() self:OnAuctionBuy() end)
  local TS = C_TradeSkillUI
  HM(TS, "CraftRecipe", function() self:OnCraft() end)
  HM(TS, "CraftSalvage", function() self:OnCraft() end)
  HM(TS, "CraftEnchant", function() self:OnCraft() end)
end

function Attribution:EnableOut()
  if self.__outEv then return end
  installHooks(self)
  self:HookGuildBankFrame()
  local ev = NS.NewBusTarget()
  if not ev then return end
  self.__outEv = ev
  local function reg(event, fn) NS.SafeRegisterEvent(ev, event, fn, NS.RejectedEvents) end
  reg("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, t) self:OnInteraction(true, t) end)
  reg("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, t) self:OnInteraction(false, t) end)
  reg("MAIL_SEND_SUCCESS", function() self:OnMailSent() end)
  reg("MAIL_FAILED", function() self:OnMailFailed() end)
  reg("TRADE_ACCEPT_UPDATE", function(_, p, t) self:OnTradeAccept(p, t) end)
  reg("ADDON_LOADED", function(_, name) if name == "Blizzard_GuildBankUI" then self:HookGuildBankFrame() end end)
end

-- Stand-down: the target goes wholesale and every outbound state goes with it, so nothing stamped
-- while the addon was up attributes a change after it comes back.
function Attribution:DisableOut()
  if self.__outEv then
    self.__outEv:UnregisterAllEvents()
    self.__outEv:UnregisterAllMessages()
    self.__outEv = nil
  end
  State.outContext, State.pendingMail, State.soldMail, State.tradeTarget, State.craftUntil = nil, nil, nil, nil, nil
  State.mailTaken = nil
  for k in pairs(State.scopes) do State.scopes[k] = nil end
  for k in pairs(State.pendingPost) do State.pendingPost[k] = nil end
end
