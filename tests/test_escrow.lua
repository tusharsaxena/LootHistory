local T = _G.LH_TEST
local NS = T.NS
local assertEqual, assertTrue = T.assertEqual, T.assertTrue
local m = T.mocks
local S = dofile("tests/ledger_support.lua")
local case, R, H, setBag = S.case, S.R, S.H, S.setBag

-- modules/Escrow.lua (timeline-ledger spec §3, §5.1 case 2, §5.4): the mail and auction-house
-- columns. An arrival there is holdings-only until it resolves; a post is a MOVE; a send to an own
-- alt is an ALT_MAIL loss on the sender and, when the alt takes it, an ALT_MAIL gain (Phase 7); an
-- auction that left the list is held as an exit until a return, a sale mail or EXIT_TTL.

local function rowsBy(dir)
  local out = {}
  for _, r in ipairs(H()) do if r.dir == dir then out[#out + 1] = r end end
  return out
end

case("Escrow: mail to an own alt is an ALT_MAIL loss; the alt's mail and own-origin are credited", function()
  S.reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 3 } }); m.__money = 5000
  S.genesis()
  NS.db.global.holdings["Alt-Realm"] = { meta = { genesis = 1 }, scanned = { bags = 1 }, items = {},
    currency = {}, links = {} }
  NS.State.pendingMail = { to = "Alt-Realm", items = { [7] = 3 }, money = 1000, sent = true, expires = 200 }
  NS.Attribution:StampOut("MAIL_SEND", { dirs = { OUT = true } })
  S.show("MailInfo")
  setBag(0, {}); m.__money = 3970                         -- 1000 sent + 30 postage
  R():MarkDirty("bags"); R():MarkDirty("money"); R():Flush()
  assertEqual(#rowsBy("MOVE"), 0); assertEqual(#rowsBy("IN"), 0)   -- the alt's gain waits for its take
  local alts, postage = {}, nil
  for _, r in ipairs(rowsBy("OUT")) do
    assertEqual(r.holder, S.me())
    if r.source == "ALT_MAIL" then alts[r.kind] = r else postage = r end
  end
  assertEqual(alts.ITEM.quantity, 3); assertEqual(alts.ITEM.to, "Alt-Realm/mail")
  assertEqual(alts.GOLD.quantity, 1000)
  assertEqual(postage.kind, "GOLD"); assertEqual(postage.quantity, 30); assertEqual(postage.source, "MAIL_SEND")
  local alt = NS.db.global.holdings["Alt-Realm"]
  assertEqual(alt.items[7].mail, 3)
  assertEqual(alt.escrow.mailOwn[7], 3); assertEqual(alt.escrow.mailMoney, 1000)
  assertEqual(alt.escrow.mailAlt[7], 3); assertEqual(alt.escrow.mailMoneyAlt, 1000)
  assertEqual(NS.State.pendingMail, nil)
end)

case("Escrow: taking mail splits own-origin (MOVE) from outside gains (IN)", function()
  S.reset()
  S.genesis()
  m.__inbox = { { items = { { itemID = 9, count = 4, link = "L9" } } } }
  S.show("MailInfo"); NS.Attribution:SetScope("mailbox", true)
  R():Flush()                                              -- the inbox's first scan: its genesis
  assertEqual(#H(), 0)
  NS.Holdings:Escrow(S.me()).mailOwn[9] = 1
  m.__inbox = {}; setBag(0, { [1] = { itemID = 9, link = "L9", count = 4 } })
  R():MarkDirty("mail"); R():MarkDirty("bags"); R():Flush()
  m.__now = 108; R():Flush()                               -- past the settle and claim waits
  assertEqual(#rowsBy("MOVE"), 1); assertEqual(rowsBy("MOVE")[1].from, S.me() .. "/mail")
  local ins = rowsBy("IN")
  assertEqual(#ins, 1); assertEqual(ins[1].quantity, 3); assertEqual(ins[1].source, "MAIL")
  assertEqual(NS.Holdings:Escrow(S.me()).mailOwn[9], nil)
end)

-- The alt's half of an own-alt mail: taking what an alt sent is an ALT_MAIL gain, while other
-- own-origin mail (an auction's return) is still a MOVE and the rest is an outside gain.
case("Escrow: taking an alt's mail is an ALT_MAIL gain; a returned auction stays a MOVE", function()
  S.reset()
  S.genesis()
  m.__inbox = { { items = { { itemID = 9, count = 6, link = "L9" } } } }
  S.show("MailInfo"); NS.Attribution:SetScope("mailbox", true)
  R():Flush()                                              -- the inbox's first scan: its genesis
  local esc = NS.Holdings:Escrow(S.me())
  esc.mailOwn[9] = 3; esc.mailAlt = { [9] = 2 }            -- 2 from an alt, 1 an auction's return
  m.__inbox = {}; setBag(0, { [1] = { itemID = 9, link = "L9", count = 6 } })
  R():MarkDirty("mail"); R():MarkDirty("bags"); R():Flush()
  m.__now = 108; R():Flush()
  local by = {}
  for _, r in ipairs(H()) do by[r.dir .. ":" .. r.source] = r; assertEqual(r.holder, S.me()) end
  assertEqual(#H(), 3)
  assertEqual(by["IN:ALT_MAIL"].quantity, 2); assertEqual(by["IN:ALT_MAIL"].from, S.me() .. "/mail")
  assertEqual(by["MOVE:TRANSFER"].quantity, 1)
  assertEqual(by["IN:MAIL"].quantity, 3)
  assertEqual(esc.mailOwn[9], nil); assertEqual(esc.mailAlt[9], nil)
end)

case("Escrow: posting moves bags to auctions and credits the auctions column", function()
  S.reset()
  setBag(0, { [1] = { itemID = 3, link = "L3", count = 2 } })
  S.genesis()
  S.show("Auctioneer")
  NS.State.pendingPost[3] = 2
  setBag(0, {})
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 1)
  assertEqual(H()[1].dir, "MOVE"); assertEqual(H()[1].to, S.me() .. "/auctions")
  assertEqual(NS.Holdings:Get(S.me()).items[3].auctions, 2)
  assertEqual(NS.State.pendingPost[3], nil)
end)

case("Escrow: an auction that leaves and comes back by mail is a return, not a sale", function()
  S.reset()
  S.genesis()
  S.show("Auctioneer")
  m.__ownedAuctions = { { itemID = 3, quantity = 2, link = "L3", status = 0 } }
  R():OnEvent("OWNED_AUCTIONS_UPDATED"); R():Flush()       -- auctions column genesis
  m.__ownedAuctions = {}
  R():OnEvent("OWNED_AUCTIONS_UPDATED"); R():Flush()
  assertEqual(#H(), 0)
  assertEqual(NS.Holdings:Escrow(S.me()).exits[3].n, 2)
  S.show("MailInfo"); R():Flush()                          -- empty inbox: mail column genesis
  m.__inbox = { { items = { { itemID = 3, count = 2, link = "L3" } } } }
  R():OnEvent("MAIL_INBOX_UPDATE"); R():Flush()
  assertEqual(#H(), 0)
  assertEqual(NS.Holdings:Escrow(S.me()).mailOwn[3], 2)
  assertEqual(NS.Holdings:Escrow(S.me()).exits[3], nil)
end)

case("Escrow: an AH sale mail books the pending exit as AH_SOLD", function()
  S.reset()
  m.__money = 0
  S.genesis()
  local esc = NS.Holdings:Escrow(S.me())
  esc.exits[3] = { n = 2, ts = m.__epoch }
  NS.db.global.holdings[S.me()].links[3] = "L3"            -- mock GetItemInfo names it "Item Name"
  NS.State.soldMail = { itemName = "Item Name", expires = 150 }
  NS.Attribution:StampOut("AH_SOLD", { kinds = { GOLD = true }, dirs = { IN = true } })
  m.__money = 9000
  R():MarkDirty("money"); R():Flush()
  m.__now = 102; R():Flush()
  local outs, ins = rowsBy("OUT"), rowsBy("IN")
  assertEqual(#outs, 1); assertEqual(outs[1].source, "AH_SOLD"); assertEqual(outs[1].quantity, 2)
  assertEqual(outs[1].itemID, 3)
  assertEqual(#ins, 1); assertEqual(ins[1].kind, "GOLD"); assertEqual(ins[1].source, "AH_SOLD")
  assertEqual(esc.exits[3], nil); assertEqual(NS.State.soldMail, nil)
end)

case("Escrow: an exit unresolved for 30 days is booked as sold", function()
  S.reset()
  S.genesis()
  NS.Holdings:Escrow(S.me()).exits[3] = { n = 1, ts = m.__epoch - NS.Escrow.EXIT_TTL - 1 }
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 1); assertEqual(H()[1].source, "AH_SOLD")
end)

case("Escrow: mail money taken from an own alt's send is an ALT_MAIL gain", function()
  S.reset()
  m.__money = 0
  S.genesis()
  NS.Holdings:Escrow(S.me()).mailMoney = 1000; NS.Holdings:Escrow(S.me()).mailMoneyAlt = 1000
  S.show("MailInfo"); R():Flush()
  m.__money = 1000
  R():MarkDirty("money"); R():Flush()
  assertEqual(#H(), 1); assertEqual(H()[1].dir, "IN"); assertEqual(H()[1].source, "ALT_MAIL")
  assertEqual(H()[1].holder, S.me()); assertEqual(H()[1].to, S.me() .. "/money")
  assertEqual(NS.Holdings:Escrow(S.me()).mailMoney, 0); assertEqual(NS.Holdings:Escrow(S.me()).mailMoneyAlt, 0)
end)

-- Gold sent before Phase 7 credited mailMoney but not mailMoneyAlt, and its sender-side MOVE pair
-- becomes OUT + IN in v13; taking it must stay a MOVE, or the alt's gain counts twice.
case("Escrow: mail money credited before Phase 7 (no mailMoneyAlt) is still a MOVE when taken", function()
  S.reset()
  m.__money = 0
  S.genesis()
  local esc = NS.Holdings:Escrow(S.me())
  esc.mailMoney = 1000
  S.show("MailInfo"); R():Flush()
  m.__money = 1000
  R():MarkDirty("money"); R():Flush()
  assertEqual(#H(), 1); assertEqual(H()[1].dir, "MOVE"); assertEqual(H()[1].source, "TRANSFER")
  assertEqual(H()[1].from, S.me() .. "/mail"); assertEqual(H()[1].to, S.me() .. "/money")
  assertEqual(#rowsBy("IN"), 0)
  assertEqual(esc.mailMoney, 0); assertEqual(esc.mailMoneyAlt, nil)
end)

case("Escrow: mixed mail money: the alt-sent part is an ALT_MAIL gain, the pre-Phase 7 rest a MOVE", function()
  S.reset()
  m.__money = 0
  S.genesis()
  local esc = NS.Holdings:Escrow(S.me())
  esc.mailMoney, esc.mailMoneyAlt = 1000, 400              -- 400 sent since Phase 7, 600 before it
  S.show("MailInfo"); R():Flush()
  m.__money = 700
  R():MarkDirty("money"); R():Flush()
  local by = {}
  for _, r in ipairs(H()) do by[r.dir .. ":" .. r.source] = r; assertEqual(r.holder, S.me()) end
  assertEqual(#H(), 2)
  assertEqual(by["IN:ALT_MAIL"].quantity, 400); assertEqual(by["MOVE:TRANSFER"].quantity, 300)
  assertEqual(esc.mailMoney, 300); assertEqual(esc.mailMoneyAlt, 0)
end)

case("Escrow: the mailbox is unreadable once closed", function()
  S.reset()
  S.genesis()
  S.show("MailInfo")
  assertTrue(R():IsReadable("mail"))
  R():OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", NS.Compat.InteractionType("MailInfo"))
  assertEqual(R():IsReadable("mail"), false)
end)

-- Final-review fixes: the mail money ALT_MAIL gain is only an own alt's gold, and a staged send is used up
-- only as far as it paired.
local function withSender(sender, body)
  local saved = m.GetInboxHeaderInfo
  m.GetInboxHeaderInfo = function() return nil, nil, sender[1], sender[2] end
  local ok, err = pcall(body)
  m.GetInboxHeaderInfo = saved
  if not ok then error(err, 0) end
end

local function altEntry()
  NS.db.global.holdings["Alt-Realm"] = { meta = { genesis = 1 }, scanned = { bags = 1 }, items = {},
    currency = {}, links = {} }
end

case("Escrow: a sale payout taken while an alt's gold waits stays AH_SOLD; the alt's gold is ALT_MAIL", function()
  S.reset()
  m.__money = 0
  S.genesis(); altEntry()
  NS.Holdings:Escrow(S.me()).mailMoney = 1000; NS.Holdings:Escrow(S.me()).mailMoneyAlt = 1000
  S.show("MailInfo"); R():Flush()
  withSender({ "Auction House", "Auction successful: Herb" }, function() NS.Attribution:OnTakeInboxMoney(1) end)
  m.__money = 500
  R():MarkDirty("money"); R():Flush()
  m.__now = 102; R():Flush()
  local ins = rowsBy("IN")
  assertEqual(#ins, 1); assertEqual(ins[1].kind, "GOLD"); assertEqual(ins[1].quantity, 500)
  assertEqual(ins[1].source, "AH_SOLD")
  assertEqual(#rowsBy("IN"), 1)
  assertEqual(NS.Holdings:Escrow(S.me()).mailMoney, 1000)
  m.__now = 120                                            -- the sale mail's window has passed
  withSender({ "Alt", "gold" }, function() NS.Attribution:OnTakeInboxMoney(2) end)
  m.__money = 1500
  R():MarkDirty("money"); R():Flush()
  m.__now = 128; R():Flush()
  assertEqual(#rowsBy("IN"), 2); assertEqual(#rowsBy("MOVE"), 0)
  local alt = rowsBy("IN")[2]
  assertEqual(alt.source, "ALT_MAIL"); assertEqual(alt.quantity, 1000)
  assertEqual(alt.to, S.me() .. "/money")
  assertEqual(NS.Holdings:Escrow(S.me()).mailMoney, 0)
end)

case("Escrow: gold from another player is a gain even while an alt's gold waits", function()
  S.reset()
  m.__money = 0
  S.genesis(); altEntry()
  NS.Holdings:Escrow(S.me()).mailMoney = 1000; NS.Holdings:Escrow(S.me()).mailMoneyAlt = 1000
  S.show("MailInfo"); R():Flush()
  withSender({ "Stranger-Otherrealm", "for you" }, function() NS.Attribution:OnTakeInboxMoney(1) end)
  m.__money = 300
  R():MarkDirty("money"); R():Flush()
  m.__now = 108; R():Flush()
  assertEqual(#rowsBy("MOVE"), 0)
  local ins = rowsBy("IN")
  assertEqual(#ins, 1); assertEqual(ins[1].kind, "GOLD"); assertEqual(ins[1].quantity, 300)
  assertTrue(ins[1].source ~= "ALT_MAIL")
  assertEqual(NS.Holdings:Escrow(S.me()).mailMoney, 1000)
end)

case("Escrow: a money-only pass leaves the staged items for the item pass; both are ALT_MAIL losses", function()
  S.reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 3 } }); m.__money = 5000
  S.genesis(); altEntry()
  NS.State.pendingMail = { to = "Alt-Realm", items = { [7] = 3 }, money = 1000, sent = true, expires = 200 }
  NS.Attribution:StampOut("MAIL_SEND", { dirs = { OUT = true } })
  S.show("MailInfo")
  m.__money = 3970                                         -- PLAYER_MONEY's fuse runs before the bags land
  R():MarkDirty("money"); R():Flush()
  local function altMail()
    local out = {}
    for _, r in ipairs(rowsBy("OUT")) do if r.source == "ALT_MAIL" then out[#out + 1] = r end end
    return out
  end
  assertEqual(#altMail(), 1); assertEqual(altMail()[1].kind, "GOLD")
  assertEqual(#rowsBy("OUT"), 2); assertEqual(#rowsBy("MOVE"), 0)
  assertTrue(NS.State.pendingMail ~= nil); assertEqual(NS.State.pendingMail.items[7], 3)
  assertEqual(NS.State.pendingMail.money, 0)
  setBag(0, {})
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#altMail(), 2)                               -- the item's loss joins the gold's
  assertEqual(#rowsBy("OUT"), 3)                           -- no OUT MAIL_SEND for the item
  local alt = NS.db.global.holdings["Alt-Realm"]
  assertEqual(alt.items[7].mail, 3)
  assertEqual(alt.escrow.mailOwn[7], 3); assertEqual(alt.escrow.mailMoney, 1000)
  assertEqual(alt.escrow.mailMoneyAlt, 1000)
  assertEqual(NS.State.pendingMail, nil)
end)
