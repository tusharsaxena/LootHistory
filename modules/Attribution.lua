local addonName, NS = ...
NS.Attribution = NS.Attribution or {}
local Attribution = NS.Attribution

-- Source-resolution engine. Stamps a short-lived loot context from peripheral events and
-- consumes it on CHAT_MSG_LOOT (see docs/attribution.md).
--
-- Sources are resolved from the loot GUID's *kind* (Creature → KILL, GameObject → CONTAINER/
-- MPLUS, Item → CONTAINER) plus peripheral stampers (vendor/mail/trade/quest/container/craft). The
-- engine no longer resolves a human "source name" — the From column and its combat-log name cache
-- were removed. sourceDetail (npcID / encounter / keystone / questID) is retained.
--
-- Every stamp/consume and each trigger logs to the session debug console when `/lh debug` is on
-- (NS.State.debug); the logging is gated at the call site so nothing is built when debug is off
-- (standard §8). Turn it on and reproduce a loot to trace exactly which path attributes an item.

local State = NS.State
local Constants = NS.Constants

-- Deconstruct abilities (Disenchant / Milling / Prospecting) each stamp their OWN source. Their
-- materials arrive through a loot window whose Item source GUID would otherwise resolve to CONTAINER
-- (see OnLootOpened), so DECONSTRUCT_SOURCE also stops that window from clobbering the stamp.
--
-- Detection is primarily by spell NAME family (see DeconstructSource): modern retail has split
-- Milling/Prospecting into generic + per-expansion + per-herb/ore "Mass Mill/Prospect" spells — far
-- too many ids (and growing every patch) to enumerate — but they all share a name family. The id
-- table below is a locale-independent fallback for the primary per-expansion spells when the name is
-- unavailable (uncached). Name matching is enUS; non-English clients rely on the id fallback
-- (full localization is tracked as a backlog issue).
local DECONSTRUCT_ID = {
  [13262] = "DISENCHANT", [289991] = "DISENCHANT",
  -- Milling: generic + per-expansion
  [51005] = "MILLING", [382981] = "MILLING", [434913] = "MILLING", [1269575] = "MILLING",
  -- Prospecting: base + per-expansion
  [31252] = "PROSPECTING", [434018] = "PROSPECTING", [1231127] = "PROSPECTING",
  [374627] = "PROSPECTING", [302710] = "PROSPECTING", [382980] = "PROSPECTING",
  [382979] = "PROSPECTING", [382971] = "PROSPECTING", [382977] = "PROSPECTING",
  [382973] = "PROSPECTING", [382975] = "PROSPECTING", [382972] = "PROSPECTING",
}
-- The deconstruct source names, for the OnLootOpened guard.
local DECONSTRUCT_SOURCE = { DISENCHANT = true, MILLING = true, PROSPECTING = true }

-- Map a completed player cast to a deconstruct source, or nil. Name-family match first (covers
-- base / per-expansion / "Mass Mill|Prospect" / future variants, enUS), then the per-expansion id
-- fallback (locale-independent). Testable without events.
function Attribution:DeconstructSource(spellID, name)
  if name and name ~= "" then
    if name:find("Disenchant") then return "DISENCHANT" end
    if name:find("Milling") or name:find("^Mass Mill") then return "MILLING" end
    if name:find("Prospecting") or name:find("^Mass Prospect") then return "PROSPECTING" end
  end
  return DECONSTRUCT_ID[spellID]
end

-- Compact one-line summary of a sourceDetail table, for the debug trace. Only called inside a
-- `NS.State.debug` guard, so it never allocates when debug is off.
local function detailStr(d)
  if not d then return "" end
  local p = {}
  if d.npcID then p[#p + 1] = "npc=" .. d.npcID end
  if d.encounterID then p[#p + 1] = "enc=" .. d.encounterID end
  if d.difficulty then p[#p + 1] = "diff=" .. d.difficulty end
  if d.keystoneLevel then p[#p + 1] = "key=+" .. d.keystoneLevel end
  if d.questID then p[#p + 1] = "quest=" .. d.questID end
  return #p > 0 and (" [" .. table.concat(p, " ") .. "]") or ""
end

-- Stamp the single-slot loot context. Consumed by the collector on the next self-loot line(s)
-- within CONTEXT_TTL. Not cleared on consume: one loot window emits many lines sharing a source.
-- `trigger` is an optional label for the debug trace only.
function Attribution:Stamp(source, detail, confidence, trigger)
  State.lootContext = {
    source = source,
    detail = detail,
    confidence = confidence or Constants.Confidence.CERTAIN,
    expires = GetTime() + Constants.CONTEXT_TTL,
  }
  if NS.State.debug and NS.Debug then
    NS.Debug("Attr", "stamp %s%s%s", source, trigger and (" via " .. trigger) or "", detailStr(detail))
  end
end

-- Read the current context. Returns source, detail, confidence when fresh;
-- OTHER / nil / INFERRED when stale or unstamped.
function Attribution:Consume()
  local c = State.lootContext
  if c and c.expires >= GetTime() then
    if NS.State.debug and NS.Debug then
      NS.Debug("Attr", "consume -> %s (%s)%s", c.source, c.confidence, detailStr(c.detail))
    end
    return c.source, c.detail, c.confidence
  end
  if NS.State.debug and NS.Debug then
    NS.Debug("Attr", "consume -> OTHER (INFERRED) — no fresh context")
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
  -- A deconstruct (disenchant/mill/prospect) delivers its materials through a loot window whose
  -- Item source GUID would resolve to CONTAINER. Keep the more specific deconstruct context the
  -- spell just stamped rather than overwriting it with this, its own, mat window.
  local c = State.lootContext
  if c and c.expires >= GetTime() and DECONSTRUCT_SOURCE[c.source] then
    if NS.State.debug and NS.Debug then NS.Debug("Open", "LOOT_OPENED kept %s (deconstruct mat window)", c.source) end
    return
  end
  local n = (GetNumLootItems and GetNumLootItems()) or 0
  for slot = 1, n do
    local guid = GetLootSourceInfo and GetLootSourceInfo(slot)
    if guid then
      local source, detail = self:ResolveLootSource(guid, State)
      if NS.State.debug and NS.Debug then
        NS.Debug("Open", "LOOT_OPENED slot=%s guid=%s -> %s", slot, tostring(guid), source)
      end
      self:Stamp(source, detail, Constants.Confidence.CERTAIN, "LOOT_OPENED")
      return
    end
  end
  if NS.State.debug and NS.Debug then NS.Debug("Open", "LOOT_OPENED (%s slots, no source GUID)", n) end
end

function Attribution:OnEncounterStart(_, encounterID, encounterName, difficultyID)
  State.encounter = { id = encounterID, name = encounterName, difficulty = difficultyID }
  if NS.State.debug and NS.Debug then
    NS.Debug("Attr", "encounter start id=%s diff=%s (KILL loot now carries it)",
      tostring(encounterID), tostring(difficultyID))
  end
end

function Attribution:OnEncounterEnd()
  State.encounter = nil
  if NS.State.debug and NS.Debug then NS.Debug("Attr", "encounter end") end
end

function Attribution:OnChallengeModeStart()
  State.keystone = { level = NS.Compat.GetActiveKeystoneLevel() }
  if NS.State.debug and NS.Debug then
    NS.Debug("Attr", "keystone start +%s (GameObject loot → MPLUS)", tostring(State.keystone.level))
  end
end

function Attribution:OnChallengeModeCompleted()
  -- Keep the keystone context: the reward chest is looted shortly after completion.
  if State.keystone then
    State.keystone.level = NS.Compat.GetActiveKeystoneLevel() or State.keystone.level
    if NS.State.debug and NS.Debug then
      NS.Debug("Attr", "keystone completed +%s (reward chest still MPLUS)", tostring(State.keystone.level))
    end
  end
end

-- Peripheral (non-loot-window) sources. Each stamps just before its resulting self-loot line.
-- KILL/CONTAINER/MPLUS/QUEST/VENDOR/MAIL/TRADE/CRAFT are wired; AH/ROLL are planned (no stamper
-- yet) and hidden from the mute list via Constants.SOURCE_IMPLEMENTED. See docs/attribution.md.
function Attribution:StampVendor()
  self:Stamp(Constants.SourceType.VENDOR, nil, Constants.Confidence.CERTAIN, "vendor-buy")
end

-- Opening a container item from bags pushes its contents to inventory with no LOOT_OPENED / GUID.
-- Stamp CONTAINER, but only when the used item actually has loot AND we're not applying a pending
-- spell to it (clicking a bag item as a Disenchant/Enchant target also routes through
-- UseContainerItem — that must NOT be read as opening a container).
function Attribution:OnContainerItemUse(bag, slot)
  local hasLoot = NS.Compat.ContainerItemHasLoot(bag, slot)
  local targeting = NS.Compat.IsSpellTargeting()
  if NS.State.debug and NS.Debug then
    NS.Debug("Open", "UseContainerItem bag=%s slot=%s hasLoot=%s spellTargeting=%s",
      tostring(bag), tostring(slot), tostring(hasLoot), tostring(targeting))
  end
  if hasLoot and not targeting then
    self:Stamp(Constants.SourceType.CONTAINER, nil, Constants.Confidence.CERTAIN, "container-open")
  end
end

-- Deconstruct abilities turn an item into materials that arrive right when the cast SUCCEEDS (so the
-- stamp is fresh within TTL). Each maps to its OWN source via DeconstructSource (name family + id
-- fallback). Every player cast is logged at debug (spell id + name) to spot any missed variant.
function Attribution:OnSpellSucceeded(_, unit, _castGUID, spellID)
  if unit ~= "player" then return end
  local name = NS.Compat.GetSpellName(spellID)
  local src = self:DeconstructSource(spellID, name)
  if NS.State.debug and NS.Debug then
    NS.Debug("Cast", "player spell=%s name=%s deconstruct=%s",
      tostring(spellID), tostring(name), tostring(src or false))
  end
  if src then
    self:Stamp(Constants.SourceType[src], nil, Constants.Confidence.CERTAIN, "deconstruct:" .. src)
  end
end

function Attribution:OnTradeAcceptUpdate(_, playerAccepted, targetAccepted)
  if playerAccepted == 1 and targetAccepted == 1 then
    self:Stamp(Constants.SourceType.TRADE, nil, Constants.Confidence.CERTAIN, "trade-complete")
  end
end

-- Taking a mail attachment. Auction-House mail (won auctions, expired/cancelled returns) is
-- attributed to AH; everything else to MAIL. The mail's sender/subject decides (locale-independent
-- via global strings — see Compat.IsAuctionHouseMail).
function Attribution:StampMail(mailIndex)
  local sender, subject = NS.Compat.GetMailHeader(mailIndex)
  local isAH = NS.Compat.IsAuctionHouseMail(sender, subject)
  if NS.State.debug and NS.Debug then
    NS.Debug("Mail", "mail-take idx=%s sender=%s subject=%s -> %s",
      tostring(mailIndex), tostring(sender), tostring(subject), isAH and "AH" or "MAIL")
  end
  local source = isAH and Constants.SourceType.AH or Constants.SourceType.MAIL
  self:Stamp(source, nil, Constants.Confidence.CERTAIN, isAH and "mail-ah" or "mail-take")
end

function Attribution:OnQuestTurnedIn(_, questID)
  self:Stamp(Constants.SourceType.QUEST, questID and { questID = questID } or nil,
    Constants.Confidence.CERTAIN, "QUEST_TURNED_IN")
end

-- Quest reward taken. Stamped from the GetQuestReward hook (client call, runs before the server
-- pushes the reward items) so the QUEST stamp is fresh when the reward loot line arrives —
-- QUEST_TURNED_IN alone can fire after that line and miss it. Detail carries the quest ID when
-- the quest frame still exposes it.
function Attribution:StampQuestReward()
  local questID = NS.Compat.CurrentQuestID()
  self:Stamp(Constants.SourceType.QUEST,
    (questID and questID > 0) and { questID = questID } or nil,
    Constants.Confidence.CERTAIN, "GetQuestReward")
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
      hooksecurefunc("TakeInboxItem", function(mailIndex) self:StampMail(mailIndex) end)
    end
    if type(AutoLootMailItem) == "function" then
      hooksecurefunc("AutoLootMailItem", function(mailIndex) self:StampMail(mailIndex) end)
    end
  end
  NS.Compat.HookUseContainerItem(function(bag, slot) self:OnContainerItemUse(bag, slot) end)
  NS.Compat.HookGetQuestReward(function() self:StampQuestReward() end)
end
