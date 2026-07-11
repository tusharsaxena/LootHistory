local addonName, NS = ...
NS.Attribution = NS.Attribution or {}
local Attribution = NS.Attribution

-- Source-resolution engine. Stamps a short-lived loot context from peripheral events and
-- consumes it on CHAT_MSG_LOOT (see docs/TECHNICAL_DESIGN §4).

local State = NS.State
local Constants = NS.Constants

-- Stamp the single-slot loot context. Consumed by the collector on the next self-loot line(s)
-- within CONTEXT_TTL. Not cleared on consume: one loot window emits many lines sharing a source.
function Attribution:Stamp(source, name, detail, confidence)
  State.lootContext = {
    source = source,
    name = name,
    detail = detail,
    confidence = confidence or Constants.Confidence.CERTAIN,
    expires = GetTime() + Constants.CONTEXT_TTL,
  }
end

-- Read the current context. Returns source, name, detail, confidence when fresh;
-- OTHER / nil / nil / INFERRED when stale or unstamped.
function Attribution:Consume()
  local c = State.lootContext
  if c and c.expires >= GetTime() then
    return c.source, c.name, c.detail, c.confidence
  end
  return Constants.SourceType.OTHER, nil, nil, Constants.Confidence.INFERRED
end

-- ── Pure source resolver ──────────────────────────────────────────────────────
-- Map a loot-slot GUID + current instance state to a source + source-specific detail.
-- Testable without events; the LOOT_OPENED handler feeds it live GUIDs.
local UNIT_KINDS = { Creature = true, Vehicle = true, Pet = true, Vignette = true }

function Attribution:ResolveLootSource(guid, state)
  state = state or State
  local S = Constants.SourceType
  local kind, npcID = NS.Compat.DecodeGUID(guid)
  if UNIT_KINDS[kind] then
    local detail = { npcID = npcID }
    if state.encounter then
      detail.encounterID = state.encounter.id
      detail.difficulty = state.encounter.difficulty
    end
    return S.KILL, detail
  elseif kind == "GameObject" then
    if state.keystone then
      return S.MPLUS, { keystoneLevel = state.keystone.level }
    end
    return S.CONTAINER, nil
  elseif kind == "Item" then
    return S.CONTAINER, nil
  end
  return S.OTHER, nil
end

-- ── Kill-name cache (combat log deaths → creature name) ───────────────────────
-- CHAT_MSG_LOOT/LOOT_OPENED expose the looted creature's GUID but not its name; we harvest
-- name from UNIT_DIED/PARTY_KILL combat-log events and look it up by GUID at loot time.
Attribution.nameCache = {}
Attribution.nameOrder = {}
local NAME_CACHE_CAP = 80

function Attribution:CacheName(guid, name)
  if not guid or not name then return end
  if not self.nameCache[guid] then
    self.nameOrder[#self.nameOrder + 1] = guid
    if #self.nameOrder > NAME_CACHE_CAP then
      local old = table.remove(self.nameOrder, 1)
      self.nameCache[old] = nil
    end
  end
  self.nameCache[guid] = name
end

-- Resolve the human sourceName for a stamped source. KILL uses the death-name cache;
-- MAIL/TRADE/VENDOR/QUEST names are supplied by their own stampers. CONTAINER has no
-- reliable name from a loot GUID, so it stays nil (renders as an em-dash).
function Attribution:ResolveSourceName(source, guid)
  if source == Constants.SourceType.KILL then
    return self.nameCache[guid]
  end
  return nil
end

-- ── Runtime stampers (events → context) ───────────────────────────────────────
-- Not invoked headlessly: Enable() is called from the addon OnEnable, so file-load in the
-- test harness never touches WoW event/hook APIs.

-- Harvest creature names from combat-log deaths for the kill-name cache.
function Attribution:OnCombatLogEvent()
  local _, subevent, _, _, _, _, _, destGUID, destName = CombatLogGetCurrentEventInfo()
  if subevent == "UNIT_DIED" or subevent == "PARTY_KILL" then
    self:CacheName(destGUID, destName)
  end
end

-- LOOT_OPENED: stamp from the first slot's source GUID (all slots in one window share a source
-- closely enough; TTL spans the resulting CHAT_MSG_LOOT burst).
function Attribution:OnLootOpened()
  local n = (GetNumLootItems and GetNumLootItems()) or 0
  for slot = 1, n do
    local guid = GetLootSourceInfo and GetLootSourceInfo(slot)
    if guid then
      local source, detail = self:ResolveLootSource(guid, State)
      local name = self:ResolveSourceName(source, guid)
      self:Stamp(source, name, detail, Constants.Confidence.CERTAIN)
      return
    end
  end
end

function Attribution:OnEncounterStart(_, encounterID, encounterName, difficultyID)
  State.encounter = { id = encounterID, name = encounterName, difficulty = difficultyID }
end

function Attribution:OnEncounterEnd()
  State.encounter = nil
end

function Attribution:OnChallengeModeStart()
  local level, mapID
  if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
    level = C_ChallengeMode.GetActiveKeystoneInfo()
  end
  if C_Map and C_Map.GetBestMapForUnit then mapID = C_Map.GetBestMapForUnit("player") end
  State.keystone = { level = level, mapID = mapID }
end

function Attribution:OnChallengeModeCompleted()
  -- Keep the keystone context: the reward chest is looted shortly after completion.
  if State.keystone and C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
    State.keystone.level = C_ChallengeMode.GetActiveKeystoneInfo() or State.keystone.level
  end
end

-- Peripheral (non-loot-window) sources. Each stamps just before its resulting self-loot line.
function Attribution:OnMerchantShow()
  self._merchantName = (UnitName and UnitName("npc")) or nil
end

function Attribution:StampVendor()
  self:Stamp(Constants.SourceType.VENDOR, self._merchantName, nil, Constants.Confidence.CERTAIN)
end

function Attribution:OnTradeShow()
  self._tradePartner = (UnitName and UnitName("npc")) or nil
end

function Attribution:OnTradeAcceptUpdate(_, playerAccepted, targetAccepted)
  if playerAccepted == 1 and targetAccepted == 1 then
    self:Stamp(Constants.SourceType.TRADE, self._tradePartner, nil, Constants.Confidence.CERTAIN)
  end
end

function Attribution:StampMail(index)
  local sender
  if GetInboxHeaderInfo and index then
    sender = select(3, GetInboxHeaderInfo(index))
  end
  self:Stamp(Constants.SourceType.MAIL, sender, nil, Constants.Confidence.CERTAIN)
end

function Attribution:OnQuestTurnedIn(_, questID)
  local title = (GetTitleText and GetTitleText()) or nil
  self:Stamp(Constants.SourceType.QUEST, title, questID and { questID = questID } or nil,
    Constants.Confidence.CERTAIN)
end

-- Register events + read-side hooks. Guarded so a missing API degrades gracefully per flavor.
function Attribution:Enable()
  local bus = NS.addon
  if not bus or self._enabled then return end
  self._enabled = true

  bus:RegisterEvent("LOOT_OPENED", function() self:OnLootOpened() end)
  bus:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function() self:OnCombatLogEvent() end)
  bus:RegisterEvent("ENCOUNTER_START", function(...) self:OnEncounterStart(...) end)
  bus:RegisterEvent("ENCOUNTER_END", function() self:OnEncounterEnd() end)
  bus:RegisterEvent("CHALLENGE_MODE_START", function() self:OnChallengeModeStart() end)
  bus:RegisterEvent("CHALLENGE_MODE_COMPLETED", function() self:OnChallengeModeCompleted() end)
  bus:RegisterEvent("MERCHANT_SHOW", function() self:OnMerchantShow() end)
  bus:RegisterEvent("TRADE_SHOW", function() self:OnTradeShow() end)
  bus:RegisterEvent("TRADE_ACCEPT_UPDATE", function(...) self:OnTradeAcceptUpdate(...) end)
  bus:RegisterEvent("QUEST_TURNED_IN", function(...) self:OnQuestTurnedIn(...) end)

  if hooksecurefunc then
    if type(BuyMerchantItem) == "function" then
      hooksecurefunc("BuyMerchantItem", function() self:StampVendor() end)
    end
    if type(TakeInboxItem) == "function" then
      hooksecurefunc("TakeInboxItem", function(index) self:StampMail(index) end)
    end
    if type(AutoLootMailItem) == "function" then
      hooksecurefunc("AutoLootMailItem", function(index) self:StampMail(index) end)
    end
  end
end
