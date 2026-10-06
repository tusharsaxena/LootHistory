local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local A = function() return NS.Attribution end
local S = function() return NS.State end

local function reset()
  T.mocks.__now = 100
  local st = S()
  st.outContext, st.pendingMail, st.pendingPost, st.soldMail, st.tradeTarget, st.craftUntil = nil, nil, {}, nil, nil, nil
  for k in pairs(st.scopes) do st.scopes[k] = nil end
end

test("AttributionOut: StampOut writes the outbound slot with TTL and filters", function()
  reset()
  A():StampOut("REPAIR", { kinds = { GOLD = true }, dirs = { OUT = true } })
  local o = S().outContext
  assertEqual(o.reason, "REPAIR"); assertEqual(o.expires, 100 + NS.Constants.CONTEXT_TTL)
  assertTrue(o.kinds.GOLD); assertTrue(o.dirs.OUT)
  assertEqual(S().lootContext == o, false)          -- never the inbound slot
end)

test("AttributionOut: interaction show/hide toggles scopes", function()
  reset()
  local M = NS.Compat.InteractionType
  A():OnInteraction(true, M("Merchant"));  assertTrue(S().scopes.merchant)
  A():OnInteraction(true, M("Trainer"));   assertTrue(S().scopes.trainer)
  A():OnInteraction(false, M("Merchant")); assertEqual(S().scopes.merchant, nil)
  A():OnInteraction(true, M("MailInfo"));  assertTrue(S().scopes.mailbox)
end)

test("AttributionOut: ReasonContext exposes both slots and the scopes, resetting per-call fields", function()
  reset()
  NS.Attribution:Stamp("KILL", nil, "CERTAIN")
  A():StampOut("DESTROY", { kinds = { ITEM = true } })
  local c = A():ReasonContext(101)
  assertEqual(c.now, 101); assertEqual(c.loot.source, "KILL"); assertEqual(c.out.reason, "DESTROY")
  c.forced, c.consumable = "UNTRACKED", true
  c = A():ReasonContext(102)
  assertEqual(c.forced, nil); assertEqual(c.consumable, nil)
end)

test("AttributionOut: SendMail to an own alt resolves the holder and stages attachments", function()
  reset()
  NS.db.global.holdings = { ["Alt-Realm"] = { meta = {}, scanned = {}, items = {}, currency = {}, links = {} } }
  T.mocks.__sendMail = { items = { [1] = { itemID = 7, count = 3 } }, money = 500 }
  A():OnSendMail("Alt")
  local p = S().pendingMail
  assertEqual(p.to, "Alt-Realm"); assertEqual(p.items[7], 3); assertEqual(p.money, 500)
  assertFalse(p.sent)
  A():OnMailSent()
  assertTrue(S().pendingMail.sent)
  assertEqual(S().outContext.reason, "MAIL_SEND")
  T.mocks.__sendMail = { items = {}, money = 0 }
end)

test("AttributionOut: SendMail to a stranger leaves `to` nil", function()
  reset()
  NS.db.global.holdings = {}
  A():OnSendMail("Stranger-Otherrealm")
  assertEqual(S().pendingMail.to, nil)
end)

test("AttributionOut: posting records the item in flight and stamps the deposit", function()
  reset()
  A():OnPost({ __itemID = 3 }, 2)
  A():OnPost({ __itemID = 3 }, 1)
  assertEqual(S().pendingPost[3], 3)
  assertEqual(S().outContext.reason, "AH_POST_FEE")
  assertTrue(S().outContext.kinds.GOLD)
end)

test("AttributionOut: taking AH sale money stamps AH_SOLD and names the item", function()
  reset()
  local saved = T.mocks.GetInboxHeaderInfo
  T.mocks.GetInboxHeaderInfo = function() return nil, nil, "Auction House", "Auction successful: Herb" end
  A():OnTakeInboxMoney(1)
  assertEqual(S().outContext.reason, "AH_SOLD"); assertTrue(S().outContext.dirs.IN)
  assertEqual(S().soldMail.itemName, "Herb")
  T.mocks.GetInboxHeaderInfo = saved
end)

test("AttributionOut: a completed trade stamps TRADE_GIVE and records the partner", function()
  reset()
  T.mocks.__tradeTarget = "Bob"
  A():OnTradeAccept(1, 0); assertEqual(S().outContext, nil)
  A():OnTradeAccept(1, 1)
  assertEqual(S().outContext.reason, "TRADE_GIVE"); assertEqual(S().tradeTarget, "Bob-Realm")
  T.mocks.__tradeTarget = nil
end)

test("AttributionOut: a craft arms the reagent window", function()
  reset()
  A():OnCraft()
  assertEqual(S().craftUntil, 100 + NS.Constants.CRAFT_TTL)
end)

test("AttributionOut: guild bank frame OnShow/OnHide drive the guildBank scope", function()
  reset()
  local scripts = {}
  local frame = { HookScript = function(_, what, fn) scripts[what] = fn end }
  rawset(_G, "GuildBankFrame", frame)
  A()._guildHooked = nil
  assertTrue(A():HookGuildBankFrame())
  scripts.OnShow(); assertTrue(S().scopes.guildBank)
  scripts.OnHide(); assertEqual(S().scopes.guildBank, nil)
  assertTrue(A():HookGuildBankFrame())           -- idempotent, no second hook
  rawset(_G, "GuildBankFrame", nil)
end)

test("AttributionOut: stood down, stamps and scopes are ignored", function()
  reset()
  local saved = NS.IsStoodDown
  NS.IsStoodDown = function() return true end
  A():StampOut("DESTROY")
  A():OnCraft()
  assertEqual(S().outContext, nil); assertEqual(S().craftUntil, nil)
  NS.IsStoodDown = saved
end)

test("AttributionOut: EnableOut registers on a private target; DisableOut unregisters and clears", function()
  reset()
  A():EnableOut()
  local ev = A().__outEv
  assertTrue(ev ~= nil and ev ~= NS.addon)
  assertTrue(ev.__events.PLAYER_INTERACTION_MANAGER_FRAME_SHOW ~= nil)
  assertTrue(ev.__events.MAIL_SEND_SUCCESS ~= nil)
  S().scopes.merchant = true
  A():DisableOut()
  assertEqual(A().__outEv, nil)
  assertEqual(next(ev.__events), nil)
  assertEqual(S().scopes.merchant, nil)
end)
