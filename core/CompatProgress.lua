local _, NS = ...
-- core/CompatProgress.lua — the reputation and appearance reads (rep/appearance spec
-- docs/superpowers/specs/2026-11-27-rep-appearance-capture-design.md §3.2): FactionSnapshot,
-- ListFactions, AppearanceSource and IsNewLook. Split out of core/Compat.lua (compat, "When to
-- split") when the file passed its 1200-line re-check again; one cohesive topic, and the rules are
-- core/Compat.lua's: globals read bare at call time, never captured at load; a secret is never
-- compared, concatenated or indexed; a missing API answers its documented absent value, never a raise.
--
-- LOAD-BEARING POSITION: in the compat family, after core/CompatClient.lua (whose IsSecret every
-- member here asks at call time) and core/CompatTooltip.lua, and straight before core/SimSeam.lua,
-- which wraps every NS.Compat member at file load and GUARDS ListFactions; below the seam these
-- members would escape the wrap.

NS.Compat = NS.Compat or {}
local Compat = NS.Compat

-- ── Reputation and appearances (rep/appearance spec §3.2) ─────────────────────────────────────
--
-- The reads behind the REPUTATION and APPEARANCE rows. Every C API string goes through a plain-string
-- guard and every number through a secret test before it is compared or concatenated (client-quirks-§2):
-- a secret is never stored and never a table key. The renown, friendship, guild and paragon reads are
-- presence-checked: that fills an API gap inside reputation, a feature both clients have (clients-§3),
-- and WoW Forever simply answers "base". Appearances are a whole feature, declared Retail-only
-- (C.FEATURE.appearances) and gated where its rows register, never here.

-- A plain (non-secret), non-empty string, or nil. Compat.IsSecret (core/CompatClient.lua, above)
-- is read at call time.
local function plainText(v)
  if Compat.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end
-- A plain number, or nil (a secret, or anything that is not a number).
local function plainNumber(v)
  if Compat.IsSecret(v) or type(v) ~= "number" then return nil end
  return v
end
local function isSecretValue(v) return v ~= nil and Compat.IsSecret(v) end

local function factionData(id)
  local R = C_Reputation
  local d = R and R.GetFactionDataByID and R.GetFactionDataByID(id)
  if type(d) == "table" then return d end
  return nil
end

-- The faction's kind: "renown", "guild", "friendship" or "base", by the first answer that applies;
-- the friendship info rides along for its reader.
local function factionKind(id)
  local R, G = C_Reputation, C_GossipInfo
  if R and R.IsMajorFaction and R.IsMajorFaction(id) == true then return "renown" end
  local guild = R and R.GetGuildFactionData and R.GetGuildFactionData()
  if type(guild) == "table" and guild.factionID == id then return "guild" end
  local fr = G and G.GetFriendshipReputation and G.GetFriendshipReputation(id)
  if type(fr) == "table" and plainNumber(fr.friendshipFactionID) and fr.friendshipFactionID > 0 then
    return "friendship", fr
  end
  return "base"
end

-- Each reader answers name, rank, standing, threshold and the label's raw text (friendship only);
-- the numbers are raw and checked for secrets by the caller before any use.
local function readBase(id)
  local d = factionData(id)
  if not d then return nil end
  return d.name, d.reaction, d.currentStanding, nil, nil
end
local function readFriendship(id, fr)
  local G = C_GossipInfo
  local ranks = G.GetFriendshipReputationRanks and G.GetFriendshipReputationRanks(id)
  local name = plainText(fr.name)
  if not name then
    local d = factionData(id)
    name = d and d.name
  end
  return name, type(ranks) == "table" and ranks.currentLevel or nil, fr.standing, nil, fr.reaction
end
local function readRenown(id)
  local MF = C_MajorFactions
  local info = MF and MF.GetMajorFactionRenownInfo and MF.GetMajorFactionRenownInfo(id)
  if type(info) ~= "table" then return nil end
  local data = MF.GetMajorFactionData and MF.GetMajorFactionData(id)
  local name = type(data) == "table" and plainText(data.name) or nil
  if not name then
    local d = factionData(id)
    name = d and d.name
  end
  return name, info.renownLevel, info.renownReputationEarned, info.renownLevelThreshold, nil
end
local READERS = { base = readBase, guild = readBase, friendship = readFriendship, renown = readRenown }

-- The paragon bar's cumulative value while paragon is active for this character, else nil; a
-- secret answer reads as "not paragon" (false), which the caller turns into all nil.
local function paragonValue(id)
  local R = C_Reputation
  local is = R and (R.IsFactionParagonForCurrentPlayer or R.IsFactionParagon)
  if not (is and R.GetFactionParagonInfo) then return nil end
  local active = is(id)
  if isSecretValue(active) then return false end
  if active ~= true then return nil end
  local value = R.GetFactionParagonInfo(id)
  if isSecretValue(value) then return false end
  return plainNumber(value)
end

-- The standing's words: the reaction's FACTION_STANDING_LABEL<n> (gendered through GetText where the
-- client has it), the friendship rank's own text, or "Renown <n>".
local function standingLabel(repType, rank, text)
  if repType == "friendship" then return plainText(text) end
  if rank == nil then return nil end
  if repType == "renown" then
    local fmt = type(RENOWN_LEVEL_LABEL) == "string" and RENOWN_LEVEL_LABEL or "Renown %d"
    return fmt:format(rank)
  end
  local key = "FACTION_STANDING_LABEL" .. rank
  if type(_G[key]) ~= "string" then return nil end
  if type(GetText) == "function" and type(UnitSex) == "function" then
    return plainText(GetText(key, UnitSex("player"))) or _G[key]
  end
  return _G[key]
end

local function accountWide(id)
  local R = C_Reputation
  return R ~= nil and R.IsAccountWideReputation ~= nil and R.IsAccountWideReputation(id) == true
end

--- One faction's standing now, as values (never a table, so the hot path allocates nothing):
--- name, repType, rank, standing, threshold, paragon, accountWide, label. All nil when the faction
--- is unreadable or any numeric answer is secret. `standing` is absolute (base, guild, friendship)
--- or the renown level's earned reputation; `paragon` is the cumulative paragon value, or nil.
function Compat.FactionSnapshot(factionID)
  if plainNumber(factionID) == nil then return nil end
  local repType, fr = factionKind(factionID)
  local name, rank, standing, threshold, text = READERS[repType](factionID, fr)
  if isSecretValue(rank) or isSecretValue(standing) or isSecretValue(threshold) then return nil end
  name, standing = plainText(name), plainNumber(standing)
  if not (name and standing) then return nil end
  local paragon = paragonValue(factionID)
  if paragon == false then return nil end
  rank, threshold = plainNumber(rank), plainNumber(threshold)
  local label = paragon and (plainText(PARAGON) or "Paragon") or standingLabel(repType, rank, text)
  return name, repType, rank, standing, threshold, paragon, accountWide(factionID), label
end

-- One ListFactions row from the snapshot, or nothing for an unreadable faction.
local function addFactionRow(out, id)
  local name, repType, rank, standing, threshold, paragon, wide, label = Compat.FactionSnapshot(id)
  if not name then return end
  out[#out + 1] = { id = id, name = name, repType = repType, rank = rank, standing = standing,
    threshold = threshold, paragon = paragon, accountWide = wide, label = label }
end

-- Shut again, last index to first, every header the walk opened: nested headers close first, and an
-- index below the one closed does not shift.
local function collapseOpened(R, expanded)
  if not R.CollapseFactionHeader then return end
  for k = R.GetNumFactions(), 1, -1 do
    local d = R.GetFactionDataByIndex(k)
    local id = type(d) == "table" and plainNumber(d.factionID) or nil
    if id and expanded[id] then R.CollapseFactionHeader(k) end
  end
end

-- Show the legacy reputations for the walk when the player hides them (Retail's "Show Legacy
-- Reputations" filter drops those factions from the indexed list itself). Answers true when it
-- flipped the filter, so the caller hides them again; presence-checked, false where it is absent.
local function showLegacy(R)
  if not (R.AreLegacyReputationsShown and R.SetLegacyReputationsShown) then return false end
  if R.AreLegacyReputationsShown() ~= false then return false end
  R.SetLegacyReputationsShown(true)
  return true
end

--- Every faction the character's Reputation list holds, as rows { id, name, repType, rank, standing,
--- threshold, paragon, accountWide, label }. A collapsed header is opened for the walk (its children
--- come straight after it, so the forward walk then visits them) and shut again after, as
--- ListCurrencies does with the Currency tab; a hidden legacy filter is shown for the walk and hidden
--- again after the headers are shut. A header with no bar of its own is skipped. GUARDED in
--- core/SimSeam.lua: it changes the player's UI state, so it never runs under a simulation.
function Compat.ListFactions()
  local R = C_Reputation
  if not (R and R.GetNumFactions and R.GetFactionDataByIndex) then return {} end
  local legacy = showLegacy(R)
  local out, expanded = {}, {}
  local i = 1
  while i <= R.GetNumFactions() do
    local d = R.GetFactionDataByIndex(i)
    local id = type(d) == "table" and plainNumber(d.factionID) or nil
    if id and d.isHeader and d.isCollapsed and R.ExpandFactionHeader then
      R.ExpandFactionHeader(i); expanded[id] = true
    end
    if id and (not d.isHeader or d.isHeaderWithRep) then addFactionRow(out, id) end
    i = i + 1
  end
  collapseOpened(R, expanded)
  if legacy then R.SetLegacyReputationsShown(false) end
  return out
end

-- The source's item link: GetAppearanceSourceInfo answers a table on a newer client (its .itemLink)
-- and positional values on an older one (the link is the sixth). "" reads as nil.
local function appearanceLink(TC, sourceID)
  if not TC.GetAppearanceSourceInfo then return nil end
  local first, _, _, _, _, link = TC.GetAppearanceSourceInfo(sourceID)
  if type(first) == "table" then link = first.itemLink end
  return plainText(link)
end

--- One appearance source: itemID, itemLink, name, quality, visualID, itemSubType. All nil when the
--- source is unreadable. The link is what the client has now (no async retry); the subtype is the
--- item's own (GetItemInfoInstant's third answer).
function Compat.AppearanceSource(sourceID)
  local TC = C_TransmogCollection
  if plainNumber(sourceID) == nil or not (TC and TC.GetSourceInfo) then return nil end
  local info = TC.GetSourceInfo(sourceID)
  if type(info) ~= "table" then return nil end
  local itemID = plainNumber(info.itemID)
  local subType
  if itemID and C_Item and C_Item.GetItemInfoInstant then subType = select(3, C_Item.GetItemInfoInstant(itemID)) end
  return itemID, appearanceLink(TC, sourceID), plainText(info.name), plainNumber(info.quality),
    plainNumber(info.visualID), plainText(subType)
end

local function sourceKnown(TC, id)
  if TC.PlayerKnowsSource then return TC.PlayerKnowsSource(id) == true end
  local info = TC.GetSourceInfo and TC.GetSourceInfo(id)
  return type(info) == "table" and info.isCollected == true
end

--- Whether `sourceID` is the only collected source of `visualID`: true when no other source of the
--- visual is known. False when the API is missing or the visual is unreadable.
function Compat.IsNewLook(visualID, sourceID)
  local TC = C_TransmogCollection
  if plainNumber(visualID) == nil or not (TC and TC.GetAllAppearanceSources) then return false end
  local list = TC.GetAllAppearanceSources(visualID)
  if type(list) ~= "table" then return false end
  for _, id in ipairs(list) do
    if id ~= sourceID and plainNumber(id) and sourceKnown(TC, id) then return false end
  end
  return true
end
