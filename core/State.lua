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
State.testRecords = nil     -- session-only synthetic dataset published by /lh test; when set, all read-path
                            -- queries (table + Insights) resolve against it instead of the live history
State.viaWhitelistIDs = nil -- session index (issue #14): { [itemID]=true } for ids with a record kept only
                            -- via the whitelist; derived from history (Database:RebuildWhitelistIndex), drives
                            -- the VisibleHistory whitelist-orphan hide. Rebuilt at init, maintained by Add.
