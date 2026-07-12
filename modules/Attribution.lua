local addonName, NS = ...
NS.Attribution = NS.Attribution or {}
local Attribution = NS.Attribution

-- Source-resolution engine. Stamps a short-lived loot context from peripheral events and
-- consumes it on CHAT_MSG_LOOT (see docs/TECHNICAL_DESIGN §4).
--
-- Sources are resolved from the loot GUID's *kind* (Creature → KILL, GameObject → CONTAINER/
-- MPLUS, Item → CONTAINER) plus peripheral stampers (vendor/mail/trade/quest). The engine no
-- longer resolves a human "source name" — the From column and its combat-log name cache were
-- removed (loot from delves/containers/pushed items rarely had a resolvable name, so the column
-- was almost always blank). sourceDetail (npcID / encounter / keystone / questID) is retained.

local State = NS.State
local Constants = NS.Constants

-- Stamp the single-slot loot context. Consumed by the collector on the next self-loot line(s)
-- within CONTEXT_TTL. Not cleared on consume: one loot window emits many lines sharing a source.
function Attribution:Stamp(source, detail, confidence)
  State.lootContext = {
    source = source,
    detail = detail,
    confidence = confidence or Constants.Confidence.CERTAIN,
    expires = GetTime() + Constants.CONTEXT_TTL,
  }
end

-- Read the current context. Returns source, detail, confidence when fresh;
-- OTHER / nil / INFERRED when stale or unstamped.
function Attribution:Consume()
  local c = State.lootContext
  if c and c.expires >= GetTime() then
    return c.source, c.detail, c.confidence
  end
  return Constants.SourceType.OTHER, nil, Constants.Confidence.INFERRED
end

-- ── Pure source resolver ──────────────────────────────────────────────────────
-- Map a loot-slot GUID + current instance state to a source + source-specific detail.
-- Testable without events; the LOOT_OPENED handler feeds it live GUIDs. The unit-kind set lives
-- in Compat (single source of truth) so KILL detection can't drift from GUID decoding.
function Attribution:ResolveLootSource(guid, state)
  state = state or State
  local S = Constants.SourceType
  local kind, npcID = NS.Compat.DecodeGUID(guid)
  if NS.Compat.UNIT_KINDS[kind] then
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

-- ── Runtime stampers (events → context) ───────────────────────────────────────
-- Not invoked headlessly: Enable() is called from the addon OnEnable, so file-load in the
-- test harness never touches WoW event/hook APIs.

-- LOOT_OPENED: stamp from the first slot's source GUID (all slots in one window share a source
-- closely enough; TTL spans the resulting CHAT_MSG_LOOT burst).
function Attribution:OnLootOpened()
  local n = (GetNumLootItems and GetNumLootItems()) or 0
  for slot = 1, n do
    local guid = GetLootSourceInfo and GetLootSourceInfo(slot)
    if guid then
      local source, detail = self:ResolveLootSource(guid, State)
      self:Stamp(source, detail, Constants.Confidence.CERTAIN)
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
  State.keystone = { level = NS.Compat.GetActiveKeystoneLevel() }
end

function Attribution:OnChallengeModeCompleted()
  -- Keep the keystone context: the reward chest is looted shortly after completion.
  if State.keystone then
    State.keystone.level = NS.Compat.GetActiveKeystoneLevel() or State.keystone.level
  end
end

-- Peripheral (non-loot-window) sources. Each stamps just before its resulting self-loot line.
-- KILL/CONTAINER/MPLUS/QUEST/VENDOR/MAIL/TRADE/CRAFT are wired; AH/ROLL are planned (no stamper
-- yet) and hidden from the mute list via Constants.SOURCE_IMPLEMENTED. See TECHNICAL_DESIGN §4.4.
function Attribution:StampVendor()
  self:Stamp(Constants.SourceType.VENDOR, nil, Constants.Confidence.CERTAIN)
end

-- Opening a container item from bags pushes its contents to inventory with no LOOT_OPENED / GUID.
-- Stamp CONTAINER, but only when the used item actually has loot (so using a potion / equipping
-- gear via UseContainerItem never mis-stamps).
function Attribution:OnContainerItemUse(bag, slot)
  if NS.Compat.ContainerItemHasLoot(bag, slot) then
    self:Stamp(Constants.SourceType.CONTAINER, nil, Constants.Confidence.CERTAIN)
  end
end

-- Disenchant / Milling / Prospecting turn an item into materials that arrive as pushed loot right
-- when the cast SUCCEEDS (so the stamp is fresh within TTL). Attribute those to CRAFT. Broad
-- profession crafting (recipe casts) is not covered yet — its cast time can exceed the TTL; see
-- TODO.md. Spell IDs are stable across flavors.
local CRAFT_SPELLS = { [13262] = true, [51005] = true, [31252] = true } -- Disenchant / Milling / Prospecting
function Attribution:OnSpellSucceeded(_, unit, _castGUID, spellID)
  if unit == "player" and CRAFT_SPELLS[spellID] then
    self:Stamp(Constants.SourceType.CRAFT, nil, Constants.Confidence.CERTAIN)
  end
end

function Attribution:OnTradeAcceptUpdate(_, playerAccepted, targetAccepted)
  if playerAccepted == 1 and targetAccepted == 1 then
    self:Stamp(Constants.SourceType.TRADE, nil, Constants.Confidence.CERTAIN)
  end
end

function Attribution:StampMail()
  self:Stamp(Constants.SourceType.MAIL, nil, Constants.Confidence.CERTAIN)
end

function Attribution:OnQuestTurnedIn(_, questID)
  self:Stamp(Constants.SourceType.QUEST, questID and { questID = questID } or nil,
    Constants.Confidence.CERTAIN)
end

-- Register events + read-side hooks. Guarded so a missing API degrades gracefully per flavor.
function Attribution:Enable()
  local bus = NS.addon
  if not bus or self._enabled then return end
  self._enabled = true

  bus:RegisterEvent("LOOT_OPENED", function() self:OnLootOpened() end)
  bus:RegisterEvent("ENCOUNTER_START", function(...) self:OnEncounterStart(...) end)
  bus:RegisterEvent("ENCOUNTER_END", function() self:OnEncounterEnd() end)
  bus:RegisterEvent("CHALLENGE_MODE_START", function() self:OnChallengeModeStart() end)
  bus:RegisterEvent("CHALLENGE_MODE_COMPLETED", function() self:OnChallengeModeCompleted() end)
  bus:RegisterEvent("TRADE_ACCEPT_UPDATE", function(...) self:OnTradeAcceptUpdate(...) end)
  bus:RegisterEvent("QUEST_TURNED_IN", function(...) self:OnQuestTurnedIn(...) end)

  -- Player-only spell-success via a dedicated RegisterUnitEvent frame — avoids the raid-wide
  -- firehose a bare RegisterEvent("UNIT_SPELLCAST_SUCCEEDED") would deliver (every nameplate cast).
  local spellFrame = CreateFrame("Frame")
  spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  spellFrame:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
    self:OnSpellSucceeded(event, unit, castGUID, spellID)
  end)

  if hooksecurefunc then
    if type(BuyMerchantItem) == "function" then
      hooksecurefunc("BuyMerchantItem", function() self:StampVendor() end)
    end
    if type(TakeInboxItem) == "function" then
      hooksecurefunc("TakeInboxItem", function() self:StampMail() end)
    end
    if type(AutoLootMailItem) == "function" then
      hooksecurefunc("AutoLootMailItem", function() self:StampMail() end)
    end
  end
  NS.Compat.HookUseContainerItem(function(bag, slot) self:OnContainerItemUse(bag, slot) end)
end
