local _, NS = ...
NS.Attribution = NS.Attribution or {}
local Attribution = NS.Attribution

-- Source-resolution engine. Stamps a short-lived loot context from peripheral events and
-- consumes it on CHAT_MSG_LOOT (see docs/data-flow.md).
--
-- Sources are resolved from the loot GUID's *kind* (Creature → KILL, GameObject → CONTAINER/
-- MPLUS, Item → CONTAINER) plus peripheral stampers (vendor/mail/trade/quest/container/craft). The
-- engine no longer resolves a human "source name" — the From column and its combat-log name cache
-- were removed. sourceDetail (npcID / encounter / keystone / questID) is retained.
--
-- Every stamp/consume and each trigger logs to the session debug console when `/lh debug` is on
-- (NS.State.debug); the logging is gated at the call site so nothing is built when debug is off
-- (debug-logging). Turn it on and reproduce a loot to trace exactly which path attributes an item.

local State = NS.State
local Constants = NS.Constants

-- Deconstruct abilities (Disenchant / Milling / Prospecting) each stamp their OWN source. Their
-- materials arrive through a loot window whose Item source GUID would otherwise resolve to CONTAINER
-- (see OnLootOpened), so DECONSTRUCT_SOURCE also stops that window from clobbering the stamp.
--
-- Detection is by spell id first (DECONSTRUCT_ID, locale-independent), then by a NAME family for the
-- variants too numerous to enumerate: modern retail has split Milling/Prospecting into generic +
-- per-expansion + per-herb/ore "Mass Mill/Prospect" spells — far too many ids (and growing every
-- patch) to list — but they share a localized name family. Crucially the family is matched against
-- the *localized* name of a seed spell (resolved at match time via C_Spell), NEVER a hardcoded
-- English literal: GetSpellName returns the client-locale name, so "Milling" on enUS becomes
-- "Mahlen" on deDE and the check follows the player's language automatically
-- (Ka0s Standard localization-§4 / anti-pattern #37).
local DECONSTRUCT_ID = {
  [13262] = "DISENCHANT", [289991] = "DISENCHANT",
  -- Milling: generic + per-expansion + a representative per-herb "Mass Mill" (seed for the name family)
  [51005] = "MILLING", [382981] = "MILLING", [434913] = "MILLING", [1269575] = "MILLING",
  [434926] = "MILLING",
  -- Prospecting: base + per-expansion + a representative per-ore "Mass Prospect" (name-family seed)
  [31252] = "PROSPECTING", [434018] = "PROSPECTING", [1231127] = "PROSPECTING",
  [374627] = "PROSPECTING", [302710] = "PROSPECTING", [382980] = "PROSPECTING",
  [382979] = "PROSPECTING", [382971] = "PROSPECTING", [382977] = "PROSPECTING",
  [382973] = "PROSPECTING", [382975] = "PROSPECTING", [382972] = "PROSPECTING",
  [225904] = "PROSPECTING",
}
-- The deconstruct source names, for the OnLootOpened guard.
local DECONSTRUCT_SOURCE = { DISENCHANT = true, MILLING = true, PROSPECTING = true }

-- Name-family seeds: a stable spellID per source whose *localized* name is matched (substring, as a
-- prefix stem) against the cast's *localized* name — so any base / per-expansion variant that embeds
-- the family word attributes correctly on every client locale. `dropLast` strips the seed name's
-- final word: the per-herb/ore "Mass Mill <Herb>" / "Mass Prospect <Ore>" families share a localized
-- command prefix ("Mass Mill", "Massenmahlen …", …), so we match that prefix rather than enumerate
-- every herb/ore. All names come from C_Spell at match time — zero English literals in the compare.
local NAME_SEEDS = {
  { source = "DISENCHANT",  id = 13262 },                    -- "Disenchant" (prefix of "Disenchanting")
  { source = "MILLING",     id = 51005 },                    -- "Milling"
  { source = "MILLING",     id = 434926, dropLast = true },  -- "Mass Mill <Herb>"
  { source = "PROSPECTING", id = 31252 },                    -- "Prospecting"
  { source = "PROSPECTING", id = 225904, dropLast = true },  -- "Mass Prospect <Ore>"
}

-- The localized match token for a seed: its client-locale spell name, optionally minus its final
-- word (the per-herb/ore suffix), trimmed and lowercased. nil when the name is not yet cached.
local function seedToken(seed)
  local name = NS.Compat.GetSpellName(seed.id)
  if not name or name == "" then return nil end
  -- Fold U+00A0 first (see NS.Compat.FoldNBSP): `%s` is byte-wise ASCII, so a no-break space in
  -- the client's string table leaves `dropLast` with no word boundary to anchor on — it strips
  -- nothing, the stem this seed exists to produce is never produced, and the whole per-herb/ore
  -- family stops attributing. The trim below misses it for the same reason. The cast side of the
  -- compare in DeconstructSource is folded identically; fold one side only and a name that
  -- matched today stops matching.
  name = NS.Compat.FoldNBSP(name)
  if seed.dropLast then name = name:gsub("%s+%S+%s*$", "") end
  name = name:gsub("^%s+", ""):gsub("%s+$", ""):lower()
  return name ~= "" and name or nil
end

-- Map a completed player cast to a deconstruct source, or nil. Id match first (locale-independent),
-- then the localized name-family match for un-enumerated variants. Testable without events.
--
-- Second return `conclusive`: whether this answer is stable enough for OnSpellSucceeded to memoize.
-- An id match or a name-family hit is always conclusive. A *negative* is conclusive only when the
-- cast had a name AND every seed name resolved this call — otherwise the miss may just be a
-- not-yet-cached seed/cast name, so the caller must retry rather than freeze it.
function Attribution:DeconstructSource(spellID, name)
  local byId = DECONSTRUCT_ID[spellID]
  if byId then return byId, true end
  if name and name ~= "" then
    local cast = NS.Compat.FoldNBSP(name):lower()   -- same fold as seedToken; both sides or neither
    local allSeedsResolved = true
    for _, seed in ipairs(NAME_SEEDS) do
      local tok = seedToken(seed)
      if tok then
        if cast:find(tok, 1, true) then return seed.source, true end
      else
        allSeedsResolved = false
      end
    end
    return nil, allSeedsResolved
  end
  return nil, false
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
  -- THE hooksecurefunc CARVE-OUT, and the only gate of its kind in this addon (slash-commands-§7).
  -- Five hooks reach this funnel -- BuyMerchantItem, TakeInboxItem, AutoLootMailItem,
  -- UseContainerItem and GetQuestReward -- and `hooksecurefunc` has no un-hook, so gating the body
  -- and returning is the one move available. It MUST NOT be read as license to gate anything that
  -- has a real unregister: every event this module owns is torn out in Attribution:Disable.
  if NS.IsStoodDown and NS.IsStoodDown() then return end
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
--
-- It does NOT clear what it read, despite the name: the context is TTL-scoped by design and
-- expiry alone ends it, so two loots inside CONTEXT_TTL both attribute to the one stamp. That is
-- the intent -- one LOOT_READY can deliver several items -- and it is why this reads like a peek.
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
    -- A live encounter has no `expires`; a won one carries it for ENCOUNTER_GRACE after
    -- ENCOUNTER_END (the corpse is looted after the kill). `state.now` lets tests fix the clock.
    local enc = state.encounter
    if enc and (enc.expires == nil or (state.now or GetTime()) <= enc.expires) then
      detail.encounterID = enc.id
      detail.difficulty = enc.difficulty
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
        NS.Debug("Open", "LOOT_OPENED %s slots -> %s%s", tostring(n), tostring(source),
          detailStr(detail))
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

-- A kill keeps the context for Constants.ENCOUNTER_GRACE seconds, because the boss corpse is
-- looted AFTER this event; a wipe (success ~= 1) or a missing context clears it. The next
-- ENCOUNTER_START replaces the table, so a new pull drops the old expiry.
function Attribution:OnEncounterEnd(_, encounterID, _, _, _, success)
  local kept = success == 1 and State.encounter ~= nil
  if kept then
    State.encounter.expires = GetTime() + Constants.ENCOUNTER_GRACE
  else
    State.encounter = nil
  end
  if NS.State.debug and NS.Debug then
    NS.Debug("Attr", "encounter end id=%s %s", tostring(encounterID),
      kept and ("kill: context kept " .. Constants.ENCOUNTER_GRACE .. "s for the corpse")
        or "wipe/no context: cleared")
  end
end

function Attribution:OnChallengeModeStart()
  State.keystone = { level = NS.Compat.GetActiveKeystoneLevel() }
  if NS.State.debug and NS.Debug then
    NS.Debug("Attr", "keystone start +%s (GameObject loot → MPLUS)", tostring(State.keystone.level))
  end
end

function Attribution:OnChallengeModeCompleted()
  -- Keep the keystone context: the reward chest is looted shortly after completion. A completion-time
  -- level of 0 (or nil) is not a level, so it never overwrites the one CHALLENGE_MODE_START read.
  if State.keystone then
    local lvl = NS.Compat.GetActiveKeystoneLevel()
    if lvl and lvl > 0 then State.keystone.level = lvl end
    if NS.State.debug and NS.Debug then
      NS.Debug("Attr", "keystone completed +%s (reward chest still MPLUS)", tostring(State.keystone.level))
    end
  end
end

-- The keystone context's other end. Kept through completion (the reward chest), it goes when the
-- player leaves the party instance -- otherwise every herb, ore node and world chest looted later
-- in the session would record as MPLUS. Inside a party instance with no context, an active key
-- re-arms it: CHALLENGE_MODE_START does not fire again for a player who zoned back into a running
-- key. One IsInInstance call per zone change, plus one keystone read on the re-arm path.
function Attribution:OnZoneChanged()
  if not NS.Compat.InPartyInstance() then
    if State.keystone then
      State.keystone = nil
      if NS.State.debug and NS.Debug then
        NS.Debug("Attr", "keystone cleared (left the party instance; GameObject loot → CONTAINER)")
      end
    end
    return
  end
  if State.keystone then return end
  local lvl = NS.Compat.GetActiveKeystoneLevel()
  if lvl and lvl > 0 then
    State.keystone = { level = lvl }
    if NS.State.debug and NS.Debug then
      NS.Debug("Attr", "keystone re-armed +%s on re-entry (GameObject loot → MPLUS)", tostring(lvl))
    end
  end
end

-- A reset key is over: nothing looted afterwards belongs to it.
function Attribution:OnChallengeModeReset()
  State.keystone = nil
  if NS.State.debug and NS.Debug then NS.Debug("Attr", "keystone cleared (CHALLENGE_MODE_RESET)") end
end

-- Peripheral (non-loot-window) sources. Each stamps just before its resulting self-loot line.
-- KILL/CONTAINER/MPLUS/QUEST/VENDOR/MAIL/TRADE/AH are wired here; deconstruct sources stamp from the
-- cast. BONUS_ROLL/CRAFT/REFUND need no stamper — their loot line self-identifies (see Collector).
function Attribution:StampVendor()
  self:Stamp(Constants.SourceType.VENDOR, nil, Constants.Confidence.CERTAIN, "vendor-buy")
end

-- A won group-loot roll. The roll-won chat line ("You won: <item>") arrives just before that item's
-- own receive line, so stamping ROLL here lets the receive line attribute to the roll instead of a
-- stale kill/container context. Triggered from the collector's CHAT_MSG_LOOT handler — the roll-won
-- line rides that same event — rather than a peripheral event of its own.
function Attribution:StampRoll()
  self:Stamp(Constants.SourceType.ROLL, nil, Constants.Confidence.CERTAIN, "roll-won")
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
-- fallback). This fires on EVERY player cast, so it must stay cheap: the (spellID -> source) mapping
-- is immutable for a session, so we memoize per spellID and the steady-state cost is one table
-- lookup — no GetSpellName call, no name-family loop, no allocation on a repeated cast (e.g. a combat
-- rotation). Only conclusive results are cached (see DeconstructSource): a positive always, a
-- negative only once the seed names have resolved, so a not-yet-cached name can't freeze a wrong miss.
-- Debug logs ONLY the deconstruct hits (not the non-deconstruct majority) — no per-cast spam.
function Attribution:OnSpellSucceeded(_, unit, _castGUID, spellID)
  if unit ~= "player" then return end
  local cache = self._deconCache
  if not cache then cache = {}; self._deconCache = cache end
  local memo = cache[spellID]
  local src
  if memo ~= nil then
    src = memo or nil                          -- false sentinel = "known non-deconstruct"
  else
    local name = NS.Compat.GetSpellName(spellID)
    local resolved, conclusive = self:DeconstructSource(spellID, name)
    src = resolved
    if conclusive then cache[spellID] = resolved or false end
  end
  if src then
    self:Stamp(Constants.SourceType[src], nil, Constants.Confidence.CERTAIN, "deconstruct:" .. src)
    if NS.State.debug and NS.Debug then
      NS.Debug("Cast", "player spell=%s name=%s -> %s",
        tostring(spellID), tostring(NS.Compat.GetSpellName(spellID)), src)
    end
  end
end

function Attribution:OnTradeAcceptUpdate(_, playerAccepted, targetAccepted)
  if playerAccepted == 1 and targetAccepted == 1 then
    self:Stamp(Constants.SourceType.TRADE, nil, Constants.Confidence.CERTAIN, "trade-complete")
  end
end

-- Taking a mail attachment. Auction-House mail (won auctions, expired/canceled returns) is
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
  bus:RegisterEvent("ENCOUNTER_END", function(...) self:OnEncounterEnd(...) end)
  bus:RegisterEvent("CHALLENGE_MODE_START", function() self:OnChallengeModeStart() end)
  bus:RegisterEvent("CHALLENGE_MODE_COMPLETED", function() self:OnChallengeModeCompleted() end)
  bus:RegisterEvent("TRADE_ACCEPT_UPDATE", function(...) self:OnTradeAcceptUpdate(...) end)
  bus:RegisterEvent("QUEST_TURNED_IN", function(...) self:OnQuestTurnedIn(...) end)
  -- The keystone context's lifetime. PLAYER_ENTERING_WORLD is deliberately NOT used: the addon
  -- object already binds it to OnEnterWorld (core/LifecycleSetup.lua), and a second registration
  -- of that event on the same target would replace that handler.
  bus:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() self:OnZoneChanged() end)
  bus:RegisterEvent("CHALLENGE_MODE_RESET", function() self:OnChallengeModeReset() end)
  -- Recorded as they are registered, so Attribution:Disable unregisters exactly what Enable
  -- registered rather than from a hand-typed second list that drifts the day an event is added.
  self.__events = { "LOOT_OPENED", "ENCOUNTER_START", "ENCOUNTER_END", "CHALLENGE_MODE_START",
                    "CHALLENGE_MODE_COMPLETED", "TRADE_ACCEPT_UPDATE", "QUEST_TURNED_IN",
                    "ZONE_CHANGED_NEW_AREA", "CHALLENGE_MODE_RESET" }

  -- Player-only spell-success via a dedicated RegisterUnitEvent frame — avoids the raid-wide
  -- firehose a bare RegisterEvent("UNIT_SPELLCAST_SUCCEEDED") would deliver (every nameplate cast).
  -- HELD ON THE MODULE, not in a local: Attribution:Disable has to reach it to unregister, and a
  -- frame only the closure knows about is a per-unit registration no stand-down can take out and no
  -- suite can see. Re-used across a disable/enable cycle rather than rebuilt, so the cycle does not
  -- leak one frame per turn of the switch.
  local spellFrame = self.__spellFrame or CreateFrame("Frame")
  self.__spellFrame = spellFrame
  spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  spellFrame:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
    self:OnSpellSucceeded(event, unit, castGUID, spellID)
  end)

  -- INSTALLED ONCE PER SESSION, and that is forced rather than chosen: every hook here goes in
  -- through `hooksecurefunc`, which has no un-hook, so a second Enable after a stand-down would
  -- stack a second copy of each. The carve-out slash-commands-§7 grants for exactly this API is a
  -- hook that GATES ITS OWN BODY and returns, and Attribution:Stamp is where that gate sits -- one
  -- funnel, and every one of these five lands in it.
  if not self._hooked then
    self._hooked = true
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
end

--- The stand-down half of Enable (slash-commands-§7). The nine shared-target events go by name --
--- UnregisterAllEvents there would take the Collector's two and the addon's own with them -- and
--- the per-unit spell frame goes wholesale, which is the registration a draw gate leaves visibly in
--- place and no early return can take out.
function Attribution:Disable()
  if not self._enabled then return end
  local bus = NS.addon
  if bus and bus.UnregisterEvent then
    for _, event in ipairs(self.__events or {}) do bus:UnregisterEvent(event) end
  end
  if self.__spellFrame then self.__spellFrame:UnregisterAllEvents() end
  -- The short-lived source context goes down with the registrations. A stamp left behind would be
  -- consumed by the first loot line after the addon came back, attributing it to a kill that
  -- happened while the addon was off.
  NS.State.lootContext, NS.State.encounter, NS.State.keystone = nil, nil, nil
  self._enabled = nil
end
