local _, NS = ...
NS.ToastContent = NS.ToastContent or {}
local TC = NS.ToastContent
local C = NS.Constants

-- The toast row content (#38, toast spec docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md
-- §7.4): pure. TC.Content(fid, spec, payload, key) sits behind each feed's `d.content` and fills the
-- Feed's reused row spec from a payload. The Feed wipes the spec before each call and runs it under
-- pcall (LibKa0s docs/api/Feed/version-1.1.1.1-docs.md, *The payload and the row spec*); it draws
-- everything, this file only says what. Answers nothing (draw) or false (skip the payload).
--
-- This is the first cut (M3.3): the icon, the quality tint, the title and the count. The secondary
-- lines, the badge, the prefix, the sub line and the highlight are M3.4's.
--
-- Binds NS.Constants at load only; every other read (NS.Compat, NS.QualityColor, NS.Util) at call time.

-- One reused tint per quality, its values refilled on each call, so a skin switch's repaint reads the
-- skin's quality token and no paint allocates.
local tints = {}

local function qualityTint(q)
  q = tonumber(q)
  if not (q and NS.QualityColor) then return nil end
  local r, g, b = NS.QualityColor(q)
  if r == nil then return nil end
  local t = tints[q]
  if not t then t = {}; tints[q] = t end
  t[1], t[2], t[3], t[4] = r, g, b, 1
  t.r, t.g, t.b, t.a = r, g, b, 1
  return t
end

local function itemIcon(p)
  return p.icon or NS.Compat.ItemIcon(p.id) or C.TOAST_ICON_UNKNOWN
end

local function currencyIcon(p)
  return p.icon or NS.Compat.CurrencyIcon(p.id) or C.TOAST_ICON_UNKNOWN
end

local function countText(qty)
  qty = tonumber(qty) or 0
  return "x" .. qty
end

local function xpTitle(p)
  return "+" .. NS.Compat.FormatCount(tonumber(p.qty) or 0) .. " XP"
end

-- Per kind: the icon, whether the quality tints it, the title, and whether a count chip shows.
local KINDS = {
  ITEM       = { icon = itemIcon, tint = true, count = true },
  CURRENCY   = { icon = currencyIcon, tint = true, count = true },
  APPEARANCE = { tint = true },
  GOLD       = { title = function(p) return NS.Util.FormatMoney(tonumber(p.qty) or 0) end },
  REPUTATION = {},
  XP         = { title = xpTitle },
  SKILL      = {},
}

--- Fill the Feed's row `spec` for `payload` on feed `fid`. False skips a payload of no known kind.
function TC.Content(_, spec, payload)
  local p = payload
  local k = type(p) == "table" and KINDS[p.kind]
  if not k then return false end
  spec.icon = k.icon and k.icon(p) or C.TOAST_KIND_ICON[p.kind] or C.TOAST_ICON_UNKNOWN
  local tint = k.tint and qualityTint(p.quality) or nil
  spec.tint = tint
  spec.title = k.title and k.title(p) or p.name or ""
  spec.titleColor = tint
  if k.count then spec.count = countText(p.qty) end
end
