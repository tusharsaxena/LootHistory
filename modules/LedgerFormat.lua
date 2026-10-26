local _, NS = ...
NS.LedgerFormat = NS.LedgerFormat or {}
local F = NS.LedgerFormat

-- Pure display helpers for ledger rows (History, Insights, and the Phase 3 Timeline). No frames.
-- Signed styling is BankLedger's (InsightsWidgets SignedCount/SignedMoney): green +N, red -N, a
-- gray em dash for exactly zero, which is a real answer rather than a missing one.
--
-- THE COLORS ARE THE SKIN'S (LH-04), read at call time so a switch reaches the next paint: a
-- direction is sem.good / sem.bad / sem.neutral and a gold amount sem.gold (the old C.DirRGB and
-- C.GOLD_RGB values in Ka0s Default); the signed strings are sem.goodAlt / sem.badAlt and a zero
-- text.disabled, byte for byte |cff40ff40 / |cffff4040 / |cff808080 in Ka0s Default. The signed
-- pair is NOT the direction pair: BankLedger's brighter green and red, kept as two tokens rather
-- than one pixel moving (docs/api Skin's split roles).

local C = NS.Constants
local DASH = "\226\128\148"
local DIR_TOKEN = { IN = "sem.good", OUT = "sem.bad", MOVE = "sem.neutral" }

function F.Color(dir)
  local r, g, b = NS.Skin.Color(DIR_TOKEN[dir or "IN"] or DIR_TOKEN.MOVE)
  return r, g, b
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
  if NS.Util.RowKind(r) == "GOLD" then
    local cr, cg, cb = NS.Skin.Color("sem.gold")
    return cr, cg, cb
  end
  return F.Color(NS.Util.RowDir(r))
end

-- One signed figure: green with a "+", red with a "-", or the gray dash for exactly zero.
local function signed(n, text)
  if n == 0 then return NS.SkinEscape("text.disabled") .. DASH .. "|r" end
  if n > 0 then return NS.SkinEscape("sem.goodAlt") .. "+" .. text(n) .. "|r" end
  return NS.SkinEscape("sem.badAlt") .. "-" .. text(-n) .. "|r"
end

function F.SignedCount(n) return signed(n or 0, tostring) end

function F.SignedMoney(copper) return signed(copper or 0, NS.Util.FormatMoney) end

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
