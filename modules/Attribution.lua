local addonName, NS = ...
NS.Attribution = NS.Attribution or {}
local Attribution = NS.Attribution

-- Source-resolution engine. Stamps a short-lived loot context from peripheral events and
-- consumes it on CHAT_MSG_LOOT. Implemented in Milestone 1 (see docs/TECHNICAL_DESIGN §4).
