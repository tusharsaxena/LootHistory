local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

test("Reset prompt: offered only for an upgraded (armed), non-empty, undecided DB", function()
  local f = NS.ShouldOfferLedgerReset
  assertTrue(f({ history = { {} }, resetPromptPending = true }))
  assertFalse(f({ history = {}, resetPromptPending = true }))      -- empty history: purged since
  assertFalse(f({ history = { {} } }))                             -- never armed: fresh install
  assertFalse(f({ history = { {} }, resetPromptPending = true, resetPrompt = "kept" }))
  assertFalse(f({ history = { {} }, resetPromptPending = true, resetPrompt = "reset" }))
end)

test("Reset prompt: an Esc on the upgrade login is asked again on the NEXT session", function()
  -- red under: the offer keyed on the session-only NS.State.upgradedFrom -- the load that migrated
  -- also stamped schemaVersion 11, so the next login had no upgrade on record and never asked.
  -- Simulates that next session: a v11 DB, no choice stored, the persisted marker still armed.
  local g, M = NS.db.global, T.mocks
  local savedH, savedPrompt, savedPending, savedVer = g.history, g.resetPrompt, g.resetPromptPending, g.schemaVersion
  g.history, g.resetPrompt, g.resetPromptPending, g.schemaVersion = { {} }, nil, true, 11
  NS:RunMigrations()                   -- the second login's runner: nothing left to migrate
  local shown, realShow = {}, M.StaticPopup_Show
  M.StaticPopup_Show = function(which) shown[#shown + 1] = which end
  local ok, err = pcall(NS.OfferLedgerReset)
  M.StaticPopup_Show = realShow
  g.history, g.resetPrompt, g.resetPromptPending, g.schemaVersion = savedH, savedPrompt, savedPending, savedVer
  if not ok then error(err, 0) end
  assertEqual(shown[1], "KA0S_LOOTHISTORY_LEDGER_RESET")
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
  g.resetPrompt, g.resetPromptPending = nil, true
  T.mocks.StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET"].OnCancel(nil, nil, "clicked")
  assertEqual(g.resetPrompt, "kept")
  assertEqual(g.resetPromptPending, nil)
  g.resetPrompt, g.resetPromptPending = nil, true
  T.mocks.StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET"].OnCancel(nil, nil, "override")
  assertEqual(g.resetPrompt, nil)
  assertEqual(g.resetPromptPending, true, "Esc decided nothing, so the next session must still ask")
  g.resetPromptPending = nil
end)

test("Reset prompt: confirmed reset purges history and keeps holdings", function()
  local g = NS.db.global
  local savedH = g.history
  g.history = { { itemID = 1 }, { itemID = 2 } }
  g.holdings = { ["A-Realm"] = { money = 1, items = {}, currency = {}, links = {}, meta = {}, scanned = {} } }
  g.resetPrompt, g.resetPromptPending = nil, true
  T.mocks.StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET_CONFIRM"].OnAccept()
  assertEqual(#g.history, 0)
  assertEqual(g.resetPrompt, "reset")
  assertEqual(g.resetPromptPending, nil)
  assertEqual(g.holdings["A-Realm"].money, 1)
  assertTrue(type(g.ledgerSince) == "number")
  g.history = savedH
end)

test("Reset prompt: in combat the offer waits for PLAYER_REGEN_ENABLED and stand-down drops it", function()
  local g, M = NS.db.global, T.mocks
  local savedH, savedPending, savedPrompt = g.history, g.resetPromptPending, g.resetPrompt
  g.history, g.resetPrompt, g.resetPromptPending = { {} }, nil, true
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
  g.history, g.resetPromptPending, g.resetPrompt = savedH, savedPending, savedPrompt
end)

test("Reset prompt: closing the export window after \"Export first\" asks again, once", function()
  -- red under: the export window's OnHide hook missing, or not clearing the flag (every later
  -- close of the export window would re-pop the prompt).
  local g, M = NS.db.global, T.mocks
  local savedH, savedPending, savedPrompt = g.history, g.resetPromptPending, g.resetPrompt
  g.history, g.resetPrompt, g.resetPromptPending = { {} }, nil, true
  local shown, realShow = {}, M.StaticPopup_Show
  M.StaticPopup_Show = function(which) shown[#shown + 1] = which end
  local win
  local ok, err = pcall(function()
    NS.Export:Open({ title = "Export History", providers = {}, csv = function() return "" end })
    win = NS.Export:Window()
    assertTrue(win ~= nil, "the export window did not open")
    NS._ledgerResetAfterExport = true
    win:Hide(); win:__fire("OnHide")
    assertEqual(shown[1], "KA0S_LOOTHISTORY_LEDGER_RESET")
    assertEqual(NS._ledgerResetAfterExport, nil)
    win:Show(); win:Hide(); win:__fire("OnHide")
    assertEqual(#shown, 1, "a later close of the export window re-asked")
  end)
  if win then win:Hide() end
  NS._ledgerResetAfterExport = nil
  M.StaticPopup_Show = realShow
  g.history, g.resetPromptPending, g.resetPrompt = savedH, savedPending, savedPrompt
  if not ok then error(err, 0) end
end)
