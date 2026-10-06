local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

test("Reset prompt: offered only for an upgraded, non-empty, undecided DB", function()
  local f = NS.ShouldOfferLedgerReset
  assertTrue(f({ history = { {} } }, 10))
  assertFalse(f({ history = {} }, 10))                         -- empty history: fresh install / purged
  assertFalse(f({ history = { {} } }, nil))                    -- already on v11 before this load
  assertFalse(f({ history = { {} }, resetPrompt = "kept" }, 10))
  assertFalse(f({ history = { {} }, resetPrompt = "reset" }, 10))
end)

test("Reset prompt: dialogs are registered with three choices", function()
  local d = T.mocks.StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET"]
  assertTrue(d ~= nil)
  assertTrue(d.button1 ~= nil and d.button2 ~= nil and d.button3 ~= nil)
  assertTrue(d.text:find("gains", 1, true) ~= nil)
  assertTrue(T.mocks.StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET_CONFIRM"] ~= nil)
end)

test("Reset prompt: Keep stores the choice; Esc leaves it undecided", function()
  local g = NS.db.global
  g.resetPrompt = nil
  T.mocks.StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET"].OnCancel(nil, nil, "clicked")
  assertEqual(g.resetPrompt, "kept")
  g.resetPrompt = nil
  T.mocks.StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET"].OnCancel(nil, nil, "override")
  assertEqual(g.resetPrompt, nil)
end)

test("Reset prompt: confirmed reset purges history and keeps holdings", function()
  local g = NS.db.global
  local savedH = g.history
  g.history = { { itemID = 1 }, { itemID = 2 } }
  g.holdings = { ["A-Realm"] = { money = 1, items = {}, currency = {}, links = {}, meta = {}, scanned = {} } }
  g.resetPrompt = nil
  T.mocks.StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET_CONFIRM"].OnAccept()
  assertEqual(#g.history, 0)
  assertEqual(g.resetPrompt, "reset")
  assertEqual(g.holdings["A-Realm"].money, 1)
  assertTrue(type(g.ledgerSince) == "number")
  g.history = savedH
end)

test("Reset prompt: in combat the offer waits for PLAYER_REGEN_ENABLED and stand-down drops it", function()
  local g, M = NS.db.global, T.mocks
  local savedH, savedUp, savedPrompt = g.history, NS.State.upgradedFrom, g.resetPrompt
  g.history, g.resetPrompt, NS.State.upgradedFrom = { {} }, nil, 10
  local shown, realShow, realCombat = {}, M.StaticPopup_Show, M.InCombatLockdown
  M.StaticPopup_Show = function(which) shown[#shown + 1] = which end
  M.InCombatLockdown = function() return true end
  NS.OfferLedgerReset()
  assertEqual(#shown, 0)
  NS.DropLedgerResetOffer()            -- stand-down path: nothing left to fire
  M.InCombatLockdown = function() return false end
  NS.OfferLedgerReset()
  assertEqual(shown[1], "KA0S_LOOTHISTORY_LEDGER_RESET")
  M.StaticPopup_Show, M.InCombatLockdown = realShow, realCombat
  g.history, NS.State.upgradedFrom, g.resetPrompt = savedH, savedUp, savedPrompt
end)
