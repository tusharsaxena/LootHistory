local addonName, NS = ...
NS.BrowserTable = NS.BrowserTable or {}
local BrowserTable = NS.BrowserTable

-- Virtualized pooled-row table: filter -> group -> sort -> slice -> bind.
-- Implemented in Milestone 3 (see docs/TECHNICAL_DESIGN §7).
