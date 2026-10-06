-- Shared helpers for the Reconciler-driven suites (test_escrow). Frozen wall clock per case, the
-- shared mock restored on the way out whether the body passed or threw.
local T = _G.LH_TEST
local NS, m = T.NS, T.mocks
local S = {}

function S.R() return NS.Reconciler end
function S.H() return NS.db.global.history end
function S.me() return NS.Util.PlayerKey() end

function S.case(name, body)
  T.test(name, function()
    local savedTime, savedICL = m.time, m.InCombatLockdown
    local savedInbox, savedAuctions = m.__inbox, m.__ownedAuctions
    local savedClass, savedEnabled = m.__itemClassID, S.R()._enabled
    m.__epoch, m.__now = 5000, 100
    m.time = function() return m.__epoch end
    local ok, err = pcall(body)
    m.time, m.InCombatLockdown = savedTime, savedICL
    m.__inbox, m.__ownedAuctions = savedInbox, savedAuctions
    m.__itemClassID, S.R()._enabled = savedClass, savedEnabled
    if not ok then error(err, 0) end
  end)
end

function S.setBag(bagID, slots)
  m.__bags[bagID] = slots
  local n = 0; for s in pairs(slots) do if s > n then n = s end end
  m.__bagSlots[bagID] = n
end

function S.reset()
  NS.db.global.history, NS.db.global.holdings = {}, {}
  m.__bags, m.__bagSlots, m.__inventory, m.__money, m.__warbandMoney = {}, {}, {}, 0, 0
  m.__inbox, m.__ownedAuctions, m.__itemClassID = {}, {}, 4
  NS.db.profile.blacklist = {}
  NS.db.profile.settings.recordGold = true
  local r = S.R()
  r.dirty, r.readable, r.deferred, r._holdSince = {}, {}, nil, nil
  r.claims, r.recent, r.reasonMemo = {}, {}, {}
  r._pending, r._recheck = nil, nil                       -- a stale fuse from another case never suppresses scheduling
  r.pendingCur, r.curGain, r.curLoss, r.pendingTransfer, r.loginPending = {}, {}, {}, nil, nil
  r._enabled = true
  local st = NS.State
  st.outContext, st.lootContext, st.pendingMail, st.soldMail = nil, nil, nil, nil
  for k in pairs(st.scopes) do st.scopes[k] = nil end
  for k in pairs(st.pendingPost) do st.pendingPost[k] = nil end
end

function S.genesis()
  local r = S.R()
  for _, p in ipairs({ "bags", "equipped", "money" }) do r:MarkDirty(p) end
  r.silent = true; r:Flush(); r.silent = nil
  NS.Holdings:MarkGenesis(S.me(), m.__epoch)
end

function S.show(name) S.R():OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", NS.Compat.InteractionType(name)) end

return S
