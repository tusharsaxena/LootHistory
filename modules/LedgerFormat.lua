local _, NS = ...
NS.LedgerFormat = NS.LedgerFormat or {}
local F = NS.LedgerFormat

-- Pure display helpers for ledger rows (History, Insights, and the Phase 3 Timeline). No frames.
-- Signed styling is BankLedger's (InsightsWidgets SignedCount/SignedMoney): green +N, red -N, a
-- gray em dash for exactly zero, which is a real answer rather than a missing one.

local C = NS.Constants
local DASH = "\226\128\148"

function F.Color(dir)
  local c = C.DirRGB[dir or "IN"] or C.DirRGB.MOVE
  return c[1], c[2], c[3]
end

function F.SignedQty(r) return NS.Ledger.Signed(NS.Util.RowDir(r), r.quantity or 1) end

-- Plain text (the cell color carries the direction). ASCII "-" because the default font has no
-- U+2212; a transfer is unsigned, it is neither a gain nor a loss.
function F.QtyText(r)
  local dir, q = NS.Util.RowDir(r), r.quantity or 1
  local sign = (dir == "IN" and "+") or (dir == "OUT" and "-") or ""
  if NS.Util.RowKind(r) == "GOLD" then return sign .. NS.Util.FormatMoney(q) end
  return sign .. tostring(q)
end

function F.QtyColor(r)
  if NS.Util.RowKind(r) == "GOLD" then local g = C.GOLD_RGB; return g[1], g[2], g[3] end
  return F.Color(NS.Util.RowDir(r))
end

function F.SignedCount(n)
  n = n or 0
  if n == 0 then return "|cff808080" .. DASH .. "|r" end
  if n > 0 then return "|cff40ff40+" .. n .. "|r" end
  return "|cffff4040-" .. (-n) .. "|r"
end

function F.SignedMoney(copper)
  copper = copper or 0
  if copper == 0 then return "|cff808080" .. DASH .. "|r" end
  if copper > 0 then return "|cff40ff40+" .. NS.Util.FormatMoney(copper) .. "|r" end
  return "|cffff4040-" .. NS.Util.FormatMoney(-copper) .. "|r"
end

function F.HolderLabel(h)
  if h == C.WARBAND_HOLDER then return "Warband" end
  return h or ""
end

-- The "Type & SubType" group (P9, History and Holdings): (raw key part, label, order value) for a
-- type/subtype pair. The label reads "<Type> · <SubType>", or just "<Type>" when the subtype is
-- missing or blank (never a trailing separator); a currency reads "Currency · <category>". The raw
-- key and order put \001 between the two parts, so groups run by type, then subtype, both
-- alphabetical (case-insensitive), with a bare type ahead of its subtyped siblings.
local MIDDOT = " \194\183 "
function F.TypeSub(itemType, itemSubType)
  local ty = (itemType ~= nil and itemType ~= "") and itemType or "Unknown"
  local st = (itemSubType ~= nil and itemSubType ~= "") and itemSubType or nil
  local raw = ty .. "\001" .. (st or "")
  return raw, st and (ty .. MIDDOT .. st) or ty, raw:lower()
end
