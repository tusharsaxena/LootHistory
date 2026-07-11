local addonName, NS = ...
NS.State = NS.State or {}
local State = NS.State

-- Short-lived source context, stamped by peripheral events and consumed by CHAT_MSG_LOOT.
-- Shape: { source, name, detail, confidence, expires }
State.lootContext = nil

-- Rolling instance context for enriching KILL/MPLUS attribution.
State.encounter = nil   -- { id, name, difficulty }
State.keystone  = nil   -- { level, mapID }

-- Session flags.
State.cleanupDone = false   -- retention prune runs once per session
