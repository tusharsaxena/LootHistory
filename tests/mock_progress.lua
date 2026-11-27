-- tests/mock_progress.lua — an opt-in test double of the client's reputation and transmog-collection
-- reads, for the REPUTATION and APPEARANCE rows (rep/appearance spec docs/superpowers/specs/
-- 2026-11-27-rep-appearance-capture-design.md, section 8). The kit (tests/_kit/) models none of
-- C_Reputation, C_MajorFactions, C_GossipInfo's friendship reads or C_TransmogCollection, so this
-- addon keeps its own, outside the vendored folder.
--
--   local PM = dofile("tests/mock_progress.lua")
--   local h = PM.install(T.mocks)      -- plants the four namespaces (empty world)
--   h.faction(72, { name = "Stormwind", reaction = 5, standing = 3000 })
--   h.list = { { id = 1, header = true, collapsed = true, depth = 0 }, { id = 72, depth = 1 } }
--   h.source(77, { itemID = 2589, name = "Linen Cloth", quality = 1, visualID = 9, collected = true })
--   h.uninstall()                      -- puts the mock's own fields back
--
-- WHAT IS MODELED, after Retail 12.x's documentation:
--   * A faction is { name, reaction, standing (absolute), kind = "base" | "guild" | "friendship" |
--     "renown", level / earned / threshold (renown), friendRank / friendText (friendship), paragon
--     (cumulative, while active), accountWide }. GetFactionDataByID answers { factionID, name,
--     reaction, currentStanding }; IsMajorFaction, GetGuildFactionData, GetFriendshipReputation(+Ranks),
--     GetMajorFactionRenownInfo / GetMajorFactionData, IsFactionParagonForCurrentPlayer,
--     GetFactionParagonInfo and IsAccountWideReputation answer from it.
--   * The Reputation LIST (`h.list`): entries { id, header, collapsed, withRep, depth }. A collapsed
--     header hides every following entry deeper than it, as the client does. GetNumFactions and
--     GetFactionDataByIndex walk what is visible; ExpandFactionHeader / CollapseFactionHeader flip the
--     visible entry at that index and log "expand:<id>@<index>" / "collapse:<id>@<index>" in h.calls.
--   * A source is { itemID, name, quality, visualID, link, collected }. GetSourceInfo answers
--     { sourceID, itemID, name, quality, visualID, isCollected }; GetAppearanceSourceInfo answers a
--     table with .itemLink, or with h.positional the older positional shape (the link sixth);
--     GetAllAppearanceSources(visualID) the sources of that visual, ascending; PlayerKnowsSource the
--     `collected` flag.
-- To model a client without a member, set it nil on the planted namespace (h.R, h.MF, h.G, h.TC);
-- the uninstall puts the mock's own tables back whatever was changed.

local PM = {}

local NAMES = { "C_Reputation", "C_MajorFactions", "C_GossipInfo", "C_TransmogCollection" }

local function visibleOf(list)
  local out, hideDepth = {}, nil
  for _, e in ipairs(list) do
    local depth = e.depth or 0
    local hidden = hideDepth ~= nil and depth > hideDepth   -- under a collapsed header
    if not hidden then
      hideDepth = nil
      out[#out + 1] = e
      if e.header and e.collapsed then hideDepth = depth end
    end
  end
  return out
end

local function reputation(h)
  local R = {}
  function R.GetFactionDataByID(id)
    local f = h.factions[id]
    if not f then return nil end
    return { factionID = id, name = f.name, reaction = f.reaction, currentStanding = f.standing }
  end
  function R.IsMajorFaction(id) local f = h.factions[id]; return f ~= nil and f.kind == "renown" end
  function R.GetGuildFactionData()
    for id, f in pairs(h.factions) do
      if f.kind == "guild" then return { factionID = id, name = f.name } end
    end
    return nil
  end
  function R.IsFactionParagonForCurrentPlayer(id) local f = h.factions[id]; return f ~= nil and f.paragon ~= nil end
  function R.GetFactionParagonInfo(id) local f = h.factions[id]; return f and f.paragon, 10000 end
  function R.IsAccountWideReputation(id) local f = h.factions[id]; return f ~= nil and f.accountWide == true end
  function R.GetNumFactions() return #visibleOf(h.list) end
  function R.GetFactionDataByIndex(i)
    local e = visibleOf(h.list)[i]
    if not e then return nil end
    local f = h.factions[e.id] or {}
    return { factionID = e.id, name = f.name, isHeader = e.header == true, isCollapsed = e.collapsed == true,
             isHeaderWithRep = e.withRep == true }
  end
  function R.ExpandFactionHeader(i)
    local e = visibleOf(h.list)[i]
    if e and e.header then e.collapsed = false; h.calls[#h.calls + 1] = "expand:" .. e.id .. "@" .. i end
  end
  function R.CollapseFactionHeader(i)
    local e = visibleOf(h.list)[i]
    if e and e.header then e.collapsed = true; h.calls[#h.calls + 1] = "collapse:" .. e.id .. "@" .. i end
  end
  return R
end

local function majorFactions(h)
  local MF = {}
  function MF.GetMajorFactionRenownInfo(id)
    local f = h.factions[id]
    if not (f and f.kind == "renown") then return nil end
    return { renownLevel = f.level, renownReputationEarned = f.earned, renownLevelThreshold = f.threshold }
  end
  function MF.GetMajorFactionData(id)
    local f = h.factions[id]
    if not (f and f.kind == "renown") then return nil end
    return { factionID = id, name = f.name }
  end
  return MF
end

local function gossip(h, base)
  local G = setmetatable({}, { __index = base })
  function G.GetFriendshipReputation(id)
    local f = h.factions[id]
    if not (f and f.kind == "friendship") then return { friendshipFactionID = 0 } end
    return { friendshipFactionID = id, name = f.name, standing = f.standing, reaction = f.friendText }
  end
  function G.GetFriendshipReputationRanks(id)
    local f = h.factions[id]
    if not (f and f.kind == "friendship") then return nil end
    return { currentLevel = f.friendRank, maxLevel = 8 }
  end
  return G
end

local function transmog(h)
  local TC = {}
  function TC.GetSourceInfo(id)
    local s = h.sources[id]
    if not s then return nil end
    return { sourceID = id, itemID = s.itemID, name = s.name, quality = s.quality, visualID = s.visualID,
             isCollected = s.collected == true }
  end
  function TC.GetAppearanceSourceInfo(id)
    local s = h.sources[id]
    if not s then return nil end
    if h.positional then return 1, s.visualID, false, 0, s.collected == true, s.link end
    return { category = 1, itemAppearanceID = s.visualID, itemLink = s.link }
  end
  function TC.GetAllAppearanceSources(visualID)
    local out = {}
    for id, s in pairs(h.sources) do if s.visualID == visualID then out[#out + 1] = id end end
    table.sort(out)
    return out
  end
  function TC.PlayerKnowsSource(id) local s = h.sources[id]; return s ~= nil and s.collected == true end
  return TC
end

--- Install the double on a finished mock; answers the handle (see the header).
--- @param M table the mock
--- @return table
function PM.install(M)
  local saved = {}
  for _, name in ipairs(NAMES) do saved[name] = { v = rawget(M, name) } end
  local h = { factions = {}, list = {}, sources = {}, calls = {}, positional = false }
  function h.faction(id, f) h.factions[id] = f; return f end
  function h.source(id, s) h.sources[id] = s; return s end
  h.R, h.MF, h.G, h.TC = reputation(h), majorFactions(h), gossip(h, saved.C_GossipInfo.v), transmog(h)
  M.C_Reputation, M.C_MajorFactions, M.C_GossipInfo, M.C_TransmogCollection = h.R, h.MF, h.G, h.TC
  function h.uninstall()
    for name, s in pairs(saved) do rawset(M, name, s.v) end
  end
  return h
end

return PM
