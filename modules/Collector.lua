local addonName, NS = ...
NS.Collector = NS.Collector or {}
local Collector = NS.Collector

-- Owns the acquisition path: CHAT_MSG_LOOT self-filter, quality gate, record build + write.
-- Implemented in Milestone 1 (see docs/TECHNICAL_DESIGN §5).
