local addonName, NS = ...
NS.State = NS.State or {}
local State = NS.State

-- Short-lived source context, stamped by peripheral events and consumed by CHAT_MSG_LOOT.
-- Shape: { source, detail, confidence, expires }
State.lootContext = nil

-- Rolling instance context for enriching KILL/MPLUS attribution.
State.encounter = nil   -- { id, name, difficulty }
State.keystone  = nil   -- { level }

-- Session flags (runtime only; reset every load/reload — never persisted to SavedVariables).
State.cleanupDone = false   -- retention prune runs once per session
State.debug = false         -- session-only logging flag; independent of window visibility. /lh debug on|off; default off
