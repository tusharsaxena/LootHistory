local _, NS = ...
NS.Probe = NS.Probe or {}
local P = NS.Probe

-- The WoW Forever port's probe verbs (ruling R4, Ka0sAddonsCommonTasks
-- docs/2026-11-22-LOOTHISTORY_BANKLEDGER_FOREVER_PORT/00_DESIGN.md, "Probe verbs").
--
-- `/lh debug probe start|stop|status|clear` (settings/Schema.lua's `debug` row). While started, this
-- file records the client facts the port's safe defaults rest on into ONE capped table under
-- `db.global.probe` (never a new SavedVariables global), stamped with the client key and build. The
-- owner plays, logs out, and the lead reads `WTF/Account/<acct>/SavedVariables/LootHistory.lua`.
-- docs/forever-probes.md maps each recorded kind to the probe it answers (P1-P11) and keeps the
-- `/run` lines as the fallback sheet.
--
-- WHAT IT RECORDS. A `start` entry: the money-text globals and what each answers for 123456 copper
-- (P9), the roll-won and bonus-roll strings (P8), the Disenchant spell name (13262), the character's
-- name forms, the instance (P11), the keyring's slots, contents and inventory slot (P3), the
-- visible currency rows with their account flags (P5) and the newest currency transfer (P5). Then,
-- as the client sends them: every interaction frame's type (P1); at a banker, the bank model (P2)
-- and every container's slot count at open, +1 s and +3 s (P1), the -2 socket reads (P10) and each
-- bank cue event with its delay after the open; each raw loot, money and currency chat line with its
-- sender fields (P4, P8); each loot window's slot links and first source GUID (P4); each currency
-- transfer (P5); the trade partner's and the mail recipient's name forms (P7); and the instance on
-- every zone-in (P11).
--
-- WHAT IT IS NOT. Session-only: a reload or relog stops it (the record stays; start it again), like
-- the debug flag. It is not a capture path: it registers on a private frame, never through
-- core/Dispatch.lua's rows, so it changes nothing the addon records, and it records nothing while a
-- simulation runs (the start refuses; an entry during one is dropped), so every fact is the live
-- client's. Every value passes `plain` first: a secret, a function or a table never reaches the
-- SavedVariables, and a long string is cut at TEXT_MAX. It is the one place the addon keeps raw
-- chat text, and only while the owner has asked it to.
--
-- Simulator-relevant reads still go through NS.Compat (tests/test_compat_routing.lua); the rest are
-- client reads no handler of the addon makes, read here and nowhere else.

P.CAP = 500           -- entries kept; the oldest goes first, counted in `dropped`
P.TEXT_MAX = 400      -- a recorded string is cut here
P.BANK_DELAYS = { 1, 3 }
P.BANK_WINDOW = 10    -- seconds after a bank open during which bank cue events are recorded
P.SLOT_SCAN = { -3, 30 }  -- container ids a bank snapshot walks for non-zero slot counts
P.SOCKETS = 9         -- the -2 socket slots read (P10)
P.LOOT_SLOTS = 20     -- loot window slots read
P.CURRENCY_ROWS = 60  -- currency list rows read
P.MONEY_SAMPLE = 123456
P.DISENCHANT = 13262
-- The banker interaction types, by Enum.PlayerInteractionType member name (P1).
P.BANKERS = { "Banker", "CharacterBanker", "AccountBanker" }

-- Every event the probe registers while started, in the order docs/forever-probes.md lists them.
P.EVENTS = {
  "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
  "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
  "BAG_CONTAINER_UPDATE", "BANK_TABS_CHANGED", "PLAYERBANKSLOTS_CHANGED", "BAG_UPDATE_DELAYED",
  "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_CURRENCY",
  "LOOT_OPENED", "CURRENCY_TRANSFER_LOG_UPDATE", "TRADE_SHOW", "PLAYER_ENTERING_WORLD",
}

local Compat = NS.Compat
local state = { running = false, frame = nil, bankOpenAt = nil, timers = {}, rejected = {}, hooked = false }
P._state = state

-- ── values ────────────────────────────────────────────────────────────────────────────────

--- A value safe to keep in the SavedVariables: a number, a boolean, a string (cut at TEXT_MAX), or
--- nil. A secret string or number answers "<secret>" (asked through NS.IsConcatSafe, at call time);
--- a table, a function or anything else answers its type in angle brackets.
function P.plain(v)
  local kind = type(v)
  if v == nil or kind == "boolean" then return v end
  if kind ~= "number" and kind ~= "string" then return "<" .. kind .. ">" end
  if not NS.IsConcatSafe(v) then return "<secret>" end
  if kind == "string" and #v > P.TEXT_MAX then return v:sub(1, P.TEXT_MAX) end
  return v
end
local plain = P.plain

--- Every value in `...` through `plain`, as an array (nil kept as a hole and `n` set).
local function plainAll(...)
  local out = { n = select("#", ...) }
  for i = 1, out.n do out[i] = plain((select(i, ...))) end
  return out
end

--- A call's answers through `plainAll`, or `{ err = <message> }` when it raised; nil when `fn` is
--- not a function, so an absent API reads as absent, never as a raise.
local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local res = { pcall(fn, ...) }
  if not res[1] then return { err = plain(tostring(res[2])) } end
  return plainAll(unpack(res, 2, table.maxn(res)))
end

local function present(v) return type(v) == "function" and "function" or (v == nil and "absent" or type(v)) end

-- ── the store ─────────────────────────────────────────────────────────────────────────────

--- The probe table, made on first need, or nil before the database exists.
function P.Store(create)
  local g = NS.db and NS.db.global
  if not g then return nil end
  if g.probe == nil and create then g.probe = { entries = {}, dropped = 0 } end
  return g.probe
end

--- Stamp the table with the client that is answering.
local function stamp(store)
  local version, build = Compat.ClientBuild()
  store.client, store.version, store.build = plain(Compat.ClientKey()), plain(version), plain(build)
  store.addonVersion = plain(NS.Version and NS.Version() or nil)
end

-- The oldest entry the cap may drop: the first that is not a `start` one. A start entry holds the
-- facts read once per start (P3, P5, P8, P9), so a long session never pushes them out; with
-- nothing else left, the oldest entry goes.
local function oldestDroppable(list)
  for i, e in ipairs(list) do
    if e.kind ~= "start" then return i end
  end
  return 1
end

--- Append one entry; drop the oldest non-start entry past CAP. Nothing while stopped or while a
--- simulation runs.
function P.Record(kind, fields)
  if not state.running then return nil end
  if NS.Sim and NS.Sim.IsActive and NS.Sim:IsActive() then return nil end
  local store = P.Store(true)
  if not store then return nil end
  local entry = fields or {}
  entry.kind, entry.t = kind, time()
  local list = store.entries
  list[#list + 1] = entry
  while #list > P.CAP do
    table.remove(list, oldestDroppable(list))
    store.dropped = (store.dropped or 0) + 1
  end
  return entry
end

-- ── the facts ─────────────────────────────────────────────────────────────────────────────

-- P9: which money-text functions exist, and what each answers.
local function moneyFacts()
  local CI = C_CurrencyInfo
  local bare, ns = GetCoinTextureString, CI and CI.GetCoinTextureString
  return {
    GetCoinTextureString = present(bare), GetMoneyString = present(GetMoneyString),
    C_CurrencyInfo_GetCoinTextureString = present(ns),
    nsText = try(ns, P.MONEY_SAMPLE), bareText = try(bare, P.MONEY_SAMPLE),
    moneyString = try(GetMoneyString, P.MONEY_SAMPLE),
    formatted = plain(NS.Util and NS.Util.FormatMoney and NS.Util.FormatMoney(P.MONEY_SAMPLE) or nil),
  }
end

-- P8 and the source strings LH-07 left to confirm.
local function stringFacts()
  return {
    LOOT_ROLL_YOU_WON = plain(LOOT_ROLL_YOU_WON),
    LOOT_ITEM_BONUS_ROLL_SELF = plain(LOOT_ITEM_BONUS_ROLL_SELF),
    disenchant = plain(Compat.GetSpellName(P.DISENCHANT)),
  }
end

-- The character's name forms (P4, P7): UnitName's two answers beside the keys the addon builds.
local function identityFacts()
  local name, second = UnitName("player")
  return {
    unitName = plain(name), unitNameSecond = plain(second),
    regionalNames = Compat.RegionalNames() == true,
    characterKey = plain(Compat.CharacterKey()), realmKey = plain(Compat.RealmKey()),
    playerKey = plain(NS.Util and NS.Util.PlayerKey and NS.Util.PlayerKey() or nil),
  }
end

-- P11.
local function instanceFacts()
  return try(GetInstanceInfo)
end

-- P3: the keyring's slots, what is in them, and the inventory slot the client maps it to.
local function keyringFacts()
  local n = Compat.GetContainerNumSlots(-1)
  local items = {}
  for slot = 1, math.min(n, 40) do
    local s = Compat.GetContainerSlot(-1, slot)
    if s then items[#items + 1] = { slot = slot, itemID = plain(s.itemID), link = plain(s.link), count = plain(s.count) } end
  end
  return { slots = n, items = items, inventorySlot = plain(Compat.BagInventorySlot(-1)) }
end

-- P5: the currency rows the list shows now (no header is opened or shut), with their flags.
local function currencyFacts()
  local CI = C_CurrencyInfo
  if not (CI and CI.GetCurrencyListSize and CI.GetCurrencyListInfo) then return nil end
  local rows = {}
  for i = 1, math.min(CI.GetCurrencyListSize() or 0, P.CURRENCY_ROWS) do
    local c = CI.GetCurrencyListInfo(i)
    if type(c) == "table" then
      rows[#rows + 1] = { name = plain(c.name), isHeader = plain(c.isHeader), quantity = plain(c.quantity),
        isAccountWide = plain(c.isAccountWide), isAccountTransferable = plain(c.isAccountTransferable),
        link = plain(CI.GetCurrencyListLink and CI.GetCurrencyListLink(i) or nil) }
    end
  end
  return rows
end

-- P5: the newest currency transfer, every plain field as the client names it.
local function transferFacts()
  local fn = C_CurrencyInfo and C_CurrencyInfo.FetchCurrencyTransferTransactions
  local list = type(fn) == "function" and fn() or nil
  if type(list) ~= "table" or #list == 0 then return nil end
  local out = { count = #list }
  for k, v in pairs(list[#list]) do
    if type(k) == "string" then out[k] = plain(v) end
  end
  return out
end

-- P2: the bank model's answers at a banker.
local function bankModel()
  local B = C_Bank
  if type(B) ~= "table" then return nil end
  return {
    canViewCharacter = try(B.CanViewBank, 0), canViewAccount = try(B.CanViewBank, 2),
    purchasedCharacter = try(B.FetchNumPurchasedBankTabs, 0), purchasedAccount = try(B.FetchNumPurchasedBankTabs, 2),
    maxCharacter = try(B.FetchMaxNumBankTabs, 0),
    usePlayerBags = try(B.ShouldUsePlayerBagsInBank), accountMoney = try(B.FetchDepositedMoney, 2),
    canViewCharacterBank = Compat.CanViewCharacterBank(),
  }
end

-- P1: every container's slot count. The bank ids always (a 0 is the fact); any other id when not 0.
local function slotCounts()
  local out, bank = {}, {}
  for _, id in ipairs(NS.Constants.BANK_IDS or {}) do bank[id] = true end
  for id = P.SLOT_SCAN[1], P.SLOT_SCAN[2] do
    local n = Compat.GetContainerNumSlots(id)
    if n ~= 0 or bank[id] then out[#out + 1] = { id = id, slots = n } end
  end
  return out
end

-- P10: one -2 socket slot read through an ItemLocation, onto `row`.
local function readSocketLocation(row, slot)
  local IL, CI = ItemLocation, C_Item
  if not (type(IL) == "table" and IL.CreateFromBagAndSlot and CI and CI.DoesItemExist) then return end
  local ok, loc = pcall(IL.CreateFromBagAndSlot, IL, -2, slot)
  if not (ok and loc) then return end
  local okExists, exists = pcall(CI.DoesItemExist, loc)
  row.locExists = okExists and plain(exists) or "<error>"
  if okExists and exists and CI.GetItemLink then row.locLink = plain(CI.GetItemLink(loc)) end
end

-- P10: the -2 socket reads, through an ItemLocation and through the container API.
local function socketFacts()
  local out = { slots = Compat.GetContainerNumSlots(-2) }
  for slot = 1, P.SOCKETS do
    local row = { slot = slot }
    readSocketLocation(row, slot)
    local s = Compat.GetContainerSlot(-2, slot)
    row.infoLink = s and plain(s.link) or nil
    out[#out + 1] = row
  end
  return out
end

--- The `start` entry's facts. Each part is read under its own pcall, so one raise costs one part.
local START_PARTS = {
  { "money", moneyFacts }, { "strings", stringFacts }, { "identity", identityFacts },
  { "instance", instanceFacts }, { "keyring", keyringFacts }, { "currencies", currencyFacts },
  { "transfer", transferFacts },
}
function P.StartFacts()
  local store = P.Store(true)
  local facts = { client = store and store.client, build = store and store.build }
  for _, part in ipairs(START_PARTS) do
    local ok, v = pcall(part[2])
    facts[part[1]] = ok and v or { err = plain(tostring(v)) }
  end
  return facts
end

-- ── the bank visit ────────────────────────────────────────────────────────────────────────

--- One bank snapshot, `phase` "open", "+1s" or "+3s"; `via` names what opened the visit.
function P.BankSnapshot(phase, via)
  local fields = { phase = phase, via = via, open = state.bankOpenAt ~= nil, slots = slotCounts(), model = bankModel() }
  if phase == "open" then fields.sockets = socketFacts() end
  return P.Record("bank", fields)
end

local function isBanker(kind)
  for _, name in ipairs(P.BANKERS) do
    if kind ~= nil and Compat.InteractionType(name) == kind then return name end
  end
  return nil
end

--- A bank open: the snapshot now and at each delay. A second open signal inside a visit is a cue.
local function bankOpened(via)
  if state.bankOpenAt then return false end
  state.bankOpenAt = GetTime()
  P.BankSnapshot("open", via)
  for _, delay in ipairs(P.BANK_DELAYS) do
    state.timers[#state.timers + 1] = NS.After(delay, function()
      if state.running then P.BankSnapshot("+" .. delay .. "s") end
    end)
  end
  return true
end

--- A bank cue event, with its delay after the open; nothing outside BANK_WINDOW.
local function bankCue(event, ...)
  local at = state.bankOpenAt
  if not at or GetTime() - at > P.BANK_WINDOW then return end
  P.Record("cue", { event = event, dt = GetTime() - at, args = plainAll(...) })
end

-- ── the handlers ──────────────────────────────────────────────────────────────────────────

local function chatLine(event, text, sender, _, _, sender2, ...)
  local guid = select(7, ...)
  P.Record("chat", { event = event, text = plain(text), sender = plain(sender), sender2 = plain(sender2), guid = plain(guid) })
end

local function lootOpened()
  local slots = {}
  for i = 1, math.min(Compat.NumLootItems(), P.LOOT_SLOTS) do
    local link = type(GetLootSlotLink) == "function" and GetLootSlotLink(i) or nil
    slots[#slots + 1] = { slot = i, link = plain(link), source = plain(Compat.LootSourceGUID(i)) }
  end
  P.Record("loot", { count = Compat.NumLootItems(), slots = slots })
end

local function tradeShown()
  local name, second = UnitName("NPC")
  local getUnitName = GetUnitName
  P.Record("trade", {
    unitName = plain(name), unitNameSecond = plain(second),
    getUnitName = type(getUnitName) == "function" and plain(getUnitName("NPC", true)) or nil,
    tradeTargetKey = plain(Compat.TradeTargetKey()),
  })
end

local HANDLERS = {
  PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(event, kind)
    local banker = isBanker(kind)
    P.Record("interaction", { event = event, type = plain(kind), banker = banker })
    if banker and not bankOpened(banker) then bankCue(event, kind) end
  end,
  PLAYER_INTERACTION_MANAGER_FRAME_HIDE = function(event, kind)
    if isBanker(kind) then bankCue(event, kind); state.bankOpenAt = nil end
  end,
  BANKFRAME_OPENED = function(event) if not bankOpened(event) then bankCue(event) end end,
  BANKFRAME_CLOSED = function(event) bankCue(event); state.bankOpenAt = nil end,
  BAG_CONTAINER_UPDATE = bankCue, BANK_TABS_CHANGED = bankCue,
  PLAYERBANKSLOTS_CHANGED = bankCue, BAG_UPDATE_DELAYED = bankCue,
  CHAT_MSG_LOOT = chatLine, CHAT_MSG_MONEY = chatLine, CHAT_MSG_CURRENCY = chatLine,
  LOOT_OPENED = lootOpened,
  CURRENCY_TRANSFER_LOG_UPDATE = function() P.Record("transfer", { transfer = transferFacts() }) end,
  TRADE_SHOW = tradeShown,
  PLAYER_ENTERING_WORLD = function() P.Record("instance", { instance = instanceFacts() }) end,
}
P._handlers = HANDLERS

--- A client event reaching the probe frame. A raise is recorded as an entry, never thrown.
function P.OnEvent(event, ...)
  local fn = HANDLERS[event]
  if not (fn and state.running) then return end
  local ok, err = pcall(fn, event, ...)
  if not ok then P.Record("error", { event = event, err = plain(tostring(err)) }) end
end

--- The mail recipient as typed and as the addon keys it (P7). Hooked once per session, on the first
--- start; there is no un-hook, so the body gates on `running`.
local function onSendMail(recipient)
  if not state.running then return end
  P.Record("mail", { recipient = plain(recipient),
    qualified = plain(NS.Util and NS.Util.QualifyName and NS.Util.QualifyName(recipient) or nil) })
end

-- ── the verbs ─────────────────────────────────────────────────────────────────────────────

local function frame()
  if not state.frame and type(CreateFrame) == "function" then
    state.frame = CreateFrame("Frame")
    state.frame:SetScript("OnEvent", function(_, event, ...) P.OnEvent(event, ...) end)
  end
  return state.frame
end

function P.IsRunning() return state.running end

--- Start recording. Answers false and a reason when it cannot.
function P.Start()
  if state.running then return false, "already running" end
  if NS.SimBlocks and NS.SimBlocks("The probe") then return false, "simulation" end
  local store = P.Store(true)
  local f = frame()
  if not (store and f) then return false, "unavailable" end
  stamp(store)
  store.started, store.stopped = time(), nil
  state.running, state.bankOpenAt = true, nil
  for _, event in ipairs(P.EVENTS) do NS.SafeRegisterEvent(f, event, nil, state.rejected) end
  store.rejected = plainAll(unpack(state.rejected))
  if not state.hooked then state.hooked = Compat.HookSecure("SendMail", onSendMail) end
  P.Record("start", P.StartFacts())
  return true
end

--- Stop recording: every event unregistered by name, every pending snapshot canceled.
function P.Stop()
  if not state.running then return false, "not running" end
  P.Record("stop", {})
  state.running, state.bankOpenAt = false, nil
  local f = state.frame
  for _, event in ipairs(P.EVENTS) do if f and f.UnregisterEvent then f:UnregisterEvent(event) end end
  for i = #state.timers, 1, -1 do
    if NS.CancelDeferral then NS.CancelDeferral(state.timers[i]) end
    state.timers[i] = nil
  end
  local store = P.Store(false)
  if store then store.stopped = time() end
  return true
end

--- Drop every entry. While running the table is made again and stamped, so recording goes on.
function P.Clear()
  local g = NS.db and NS.db.global
  if g then g.probe = nil end
  if state.running then
    local store = P.Store(true)
    if store then stamp(store); store.started = time() end
  end
  return true
end

--- The one status line.
function P.StatusLine()
  local store = P.Store(false)
  local n = store and #store.entries or 0
  local line = ("probe: %s, %d %s (cap %d)"):format(state.running and "running" or "stopped", n,
    n == 1 and "entry" or "entries", P.CAP)
  if store and store.dropped and store.dropped > 0 then line = line .. (", %d dropped"):format(store.dropped) end
  if store and store.client then
    line = line .. (", %s %s %s"):format(tostring(store.client), tostring(store.version or "?"), tostring(store.build or "?"))
  end
  return line
end

local VERBS = {
  start = function()
    local ok, why = P.Start()
    if ok then return NS.Print("probe started; /lh debug probe stop ends it. The record is saved at logout.") end
    if why ~= "simulation" then NS.Format("probe not started: %s", why) end
  end,
  stop = function()
    local ok, why = P.Stop()
    if ok then return NS.Print(P.StatusLine()) end
    NS.Format("probe not stopped: %s", why)
  end,
  status = function() NS.Print(P.StatusLine()) end,
  clear = function() P.Clear(); NS.Print(P.StatusLine()) end,
}

--- `/lh debug probe <word>`; a bare probe is `status`.
function P.OnVerb(word)
  word = word and tostring(word):lower() or ""
  local fn = VERBS[word ~= "" and word or "status"]
  if fn then return fn() end
  NS.Print("usage: /lh debug probe start|stop|status|clear")
end
