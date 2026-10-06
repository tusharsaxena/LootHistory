local T = _G.LH_TEST
local NS = T.NS
local assertEqual, assertTrue = T.assertEqual, T.assertTrue
local m = T.mocks
local S = dofile("tests/ledger_support.lua")
local case, R, H, setBag = S.case, S.R, S.H, S.setBag

-- modules/Escrow.lua (timeline-ledger spec §3, §5.1 case 2, §5.4): the mail and auction-house
-- columns. An arrival there is holdings-only until it resolves; a send to an own alt and a post are
-- MOVEs; an auction that left the list is held as an exit until a return, a sale mail or EXIT_TTL.

local function rowsBy(dir)
  local out = {}
  for _, r in ipairs(H()) do if r.dir == dir then out[#out + 1] = r end end
  return out
end

case("Escrow: mail to an own alt is a MOVE pair; the alt's mail and own-origin are credited", function()
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
  assertEqual(#rowsBy("MOVE"), 4)                          -- item and gold, one row per holder each
  local outs = rowsBy("OUT")
  assertEqual(#outs, 1); assertEqual(outs[1].kind, "GOLD"); assertEqual(outs[1].quantity, 30)
  assertEqual(outs[1].source, "MAIL_SEND")
  local alt = NS.db.global.holdings["Alt-Realm"]
  assertEqual(alt.items[7].mail, 3)
  assertEqual(alt.escrow.mailOwn[7], 3); assertEqual(alt.escrow.mailMoney, 1000)
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

case("Escrow: mail money taken from an own alt's send is a MOVE", function()
  S.reset()
  m.__money = 0
  S.genesis()
  NS.Holdings:Escrow(S.me()).mailMoney = 1000
  S.show("MailInfo"); R():Flush()
  m.__money = 1000
  R():MarkDirty("money"); R():Flush()
  assertEqual(#H(), 1); assertEqual(H()[1].dir, "MOVE"); assertEqual(H()[1].to, S.me() .. "/money")
  assertEqual(NS.Holdings:Escrow(S.me()).mailMoney, 0)
end)

case("Escrow: the mailbox is unreadable once closed", function()
  S.reset()
  S.genesis()
  S.show("MailInfo")
  assertTrue(R():IsReadable("mail"))
  R():OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", NS.Compat.InteractionType("MailInfo"))
  assertEqual(R():IsReadable("mail"), false)
end)
