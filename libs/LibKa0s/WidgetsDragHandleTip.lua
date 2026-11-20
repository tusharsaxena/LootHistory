-- LibKa0s-Widgets-1.0 -- the drag handle's tooltip: the descriptor's three bands evaluated on each
-- hover, the owner it is shown by, and where it opens (WidgetsDragHandle minors 3, 4 and 7).
--
-- Peeled out of WidgetsDragHandle.lua at its minor 14, unchanged (LK-92B of Ka0sAddonsCommonTasks
-- docs/2026-11-16-LIBKA0S_ISSUES_75_PLUS, design section 3.6), on the seam CLAUDE.md's band census
-- named for that file, its tooltip half: LibKa0s#92 rewrites exactly this half, and the file stood
-- at 1022 against an 1100 trigger. The history is that file's header; the descriptor's fields are
-- documented on lib.DragHandle there.
--
-- WHO CALLS IN. WidgetsDragHandle.lua reads lib.__dragTipKit (show, hide) at call time, on each
-- hover, never caching it, so the newest copy of this file is every handle's. `show(handle, frame,
-- spec, t, defaultPal)` shows descriptor `t` for the hovered `frame` of `handle`; `hide()` hides
-- it; `default(spec, key)` is a mark's descriptor where its host wrote none (still minor 1, SR-L2 of
-- the same bundle's smoke round 1, ruling 3: every title-bar control carries a tooltip). Nothing
-- else crosses the cut.
--
-- A file of the Widgets major, paired on the shell's minor with the same multi-file idiom as
-- WidgetsDragHandle.lua itself.
--
-- WHERE IT OPENS (still minor 1, LK-92B of the same bundle, LibKa0s#92 part B; design section 3.6).
-- A HUD strip is the display's TOP CHROME (WowAddonStandards standalone-windows, *Tooltip
-- placement*, the chrome reading v2.112.0 flagged), so its tooltip, and its marks', attaches
-- centered ABOVE THE STRIP (below only without room above: SR-L1, the bundle's smoke round 1, where
-- it opened below) through LibKa0s-Tooltip-1.0's PlaceAttached, read at hover time. It is
-- always owned by UIParent at ANCHOR_NONE and placed by absolute points, which a restricted layout
-- tree (AuraMaster's anchors) accepts, and never at the cursor (anti-pattern #119).
-- `tooltipOwner = "cursor"`, `tooltipAnchor` and a descriptor's `owner` and `anchor` are RETIRED:
-- still accepted, no longer read (the frozen -1.0 major removes no field).
--
-- THE PLACEMENT HOOK IS RETIRED TOO (minor 2, AF-LK-02 of Ka0sAddonsCommonTasks
-- docs/2026-11-19-ADOPTION_FEEDBACK). Through minor 1 a host's `tooltipPlace` (or a descriptor's
-- `place`) was called after Show and kept its own point when it answered `true`, so Aura Master's,
-- AbsorbTracker's, Consumable Master's and KickCD's strip tooltips opened BESIDE the strip (the
-- owner's image 11) while every window header's opened above its mark (image 10, Drop Watcher). The
-- owner's ruling is one rule: above the strip everywhere, below only without room. Both keys are
-- still accepted, so a host not yet updated does not error, and neither is read or called: the
-- strip's tooltip and its marks' always take the attached placement. Deprecated: a host drops them.
--
-- A STRIP WHOSE RECT READS SECRET (minor 3, SD-LK-99 of Ka0sAddonsCommonTasks
-- docs/2026-11-20-LIBKA0S_94_97_99_100, LibKa0s#99, the owner's ruling R-3). Through minor 2 a strip
-- whose edges read secret (Aura Master's container attached under a parent holding auras, in an
-- instance) fell back to a relative point on the strip, which the restricted tree refuses, so the
-- tooltip did not render. From minor 3 the placement walks the strip's ancestors (GetParent, up to
-- but not including UIParent, MAX_ANCESTORS deep) and attaches the tooltip above the NEAREST ONE
-- WHOSE RECT READS, with the same rule as the strip's (above, below only without room above). It
-- is still pinned by an absolute point on UIParent, computed from that ancestor's readable rect,
-- so nothing is anchored into the restricted tree. "Above the strip" stands whenever the strip's
-- own rect reads. When no ancestor reads either, the tooltip is hidden: no tooltip and no error,
-- and no relative point into the strip. The relative point survives only for a copy with no
-- Tooltip major to place by.

local lib = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
if not lib then return end

-- Minor 1: the tooltip half, moved here unchanged from WidgetsDragHandle.lua (its minor 14).
-- Minor 2 (AF-LK-02): `spec.tooltipPlace` and a descriptor's `place` are retired, accepted unread; every
-- strip and mark tooltip attaches centered above the strip (WHERE IT OPENS).
-- Minor 3 (SD-LK-99, LibKa0s#99): a strip whose rect reads secret places above its nearest readable
-- ancestor, and hides the tooltip when none reads, never by a point into the strip (A STRIP WHOSE
-- RECT READS SECRET).
local DRAGTIP_MINOR = 3
-- Paired on the SHELL's minor as well as this file's own: see WidgetsDragHandle.lua.
if lib.__dragTipMinor and lib.__dragTipMinor >= DRAGTIP_MINOR
  and lib.__dragTipShellMinor == lib.MINOR then return end
lib.__dragTipMinor      = DRAGTIP_MINOR
lib.__dragTipShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.WidgetsDragHandleTip = DRAGTIP_MINOR

--- One tooltip entry, EVALUATED NOW rather than captured at build time, with the color it asked
--- for. Three shapes, and the third is the reason there is a shape at all:
---
---   "text"                    used as it stands, in its band's color
---   function() -> string|nil  called on every hover; a nil return drops the line entirely
---   { <either>, r, g, b }     the same, in a color of its own rather than its band's
---
--- The function form is what lets ConsumableMaster's footer say "Locked. Unlock the bar…" or
--- "Lock the bar…" from the same handle. The colored form is what lets AuraMaster keep its
--- conditional "Attached — set its offsets on the Layout page." line GOLD where it sits today: it
--- is a body line, in a white band, and a shape whose bands were each one color would have
--- recolored it on adoption or pushed it into the gray footer with a blank line above it.
--- @return string|nil text, number|nil r, number|nil g, number|nil b
local function dhEntry(v)
  local r, g, b
  if type(v) == "table" then v, r, g, b = v[1], v[2], v[3], v[4] end
  if type(v) == "function" then v = v() end
  if v == nil then return nil end
  return v, r, g, b
end

--- The lines of one band that survive this hover, in order, each carrying the color it will be
--- drawn in. Nothing is drawn here, because whether the footer's blank spacer is drawn at all
--- depends on how many came back.
local function dhBand(entries, r, g, b)
  local out
  for _, entry in ipairs(entries or {}) do
    local s, er, eg, eb = dhEntry(entry)
    if s then
      out = out or {}
      out[#out + 1] = { s, er or r, eg or g, eb or b }
    end
  end
  return out
end

--- The three-band shape both copies built out of different text, EVALUATED ONCE for this hover: a
--- gold title, white wrapped body lines, then -- only when at least one survives -- gray footer
--- lines. Evaluated apart from the drawing, once per hover. The band colors are `pal`'s, the
--- handle's palette at this hover (minor 7), so an owned strip's tooltip follows its skin's switches.
local function dhTooltipLines(t, pal)
  local title, tr, tg, tb = dhEntry(t.title)
  local pt, pb, pf = pal.title, pal.body, pal.footer
  return {
    title  = { title or "", tr or pt[1], tg or pt[2], tb or pt[3] },
    body   = dhBand(t.body, pb[1], pb[2], pb[3]) or {},
    footer = dhBand(t.footer, pf[1], pf[2], pf[3]),
  }
end

--- Draw evaluated lines into an owned tooltip and show it. The blank spacer before the footer is
--- drawn only when a footer line survived.
local function dhDrawTooltip(tip, lines)
  local title = lines.title
  tip:SetText(title[1], title[2], title[3], title[4])
  for _, l in ipairs(lines.body) do tip:AddLine(l[1], l[2], l[3], l[4], true) end
  if lines.footer then
    tip:AddLine(" ")
    for _, l in ipairs(lines.footer) do tip:AddLine(l[1], l[2], l[3], l[4], true) end
  end
  tip:Show()
end

-- How far the readable-ancestor walk climbs, so a parent cycle cannot hang a hover.
local MAX_ANCESTORS = 32

--- `frame`'s parent, or nil at UIParent, at the top, or on a self-parent. UIParent is never a
--- placement target: its rect is the whole screen, and a tooltip "above" it says nothing.
local function dhParentOf(frame)
  local fn = type(frame) == "table" and frame.GetParent
  if type(fn) ~= "function" then return nil end
  local ok, p = pcall(fn, frame)
  if not ok or type(p) ~= "table" or p == frame or p == UIParent then return nil end
  return p
end

--- The library's placement: attached and centered above the STRIP (`handle`), whichever of its
--- frames is hovered (a mark places by its strip, as AuraMaster's StripOf did). When the strip's
--- rect does not read (secret, or unplaced), above its nearest ancestor whose rect does (minor 3,
--- LibKa0s#99), by the same absolute point on UIParent, so nothing anchors into the restricted
--- tree; when none reads, the tooltip is hidden. Answers the frame it placed by, or nil. Only a copy
--- with no Tooltip major attaches it by a relative point, under pcall, never at the cursor.
local function dhPlaceAttached(tip, handle)
  local Tip = LibStub("LibKa0s-Tooltip-1.0", true)
  if not (Tip and type(Tip.PlaceAttached) == "function") then
    tip:ClearAllPoints()
    pcall(tip.SetPoint, tip, "BOTTOM", handle, "TOP", 0, 2)
    return nil
  end
  local f = handle
  for _ = 0, MAX_ANCESTORS do
    if Tip.PlaceAttached(tip, f) then return f end
    f = dhParentOf(f)
    if not f then break end
  end
  tip:ClearAllPoints()
  if tip.Hide then tip:Hide() end
  return nil
end

--- Show the descriptor's tooltip for `frame`, the frame hovered: owned by UIParent at ANCHOR_NONE,
--- evaluated and drawn, SHOWN (so the placement reads the tooltip's measured size), then attached
--- above the strip, or above its nearest readable ancestor (minor 3). `handle` is the strip, whose
--- palette colors the bands (minor 7) and which every tooltip places by, whichever of its frames is hovered; `defaultPal` is WidgetsDragHandle.lua's
--- owner-less palette, for a handle that carries none. `spec.tooltipPlace` and `t.place` are retired
--- (minor 2) and not read; `frame` and `spec` stay in the signature WidgetsDragHandle.lua calls.
local function dhShowTooltip(handle, frame, spec, t, defaultPal)  -- luacheck: no unused args
  local tip = GameTooltip
  if not (t and tip and tip.SetOwner and tip.SetText) then return end
  local lines = dhTooltipLines(t, handle.__pal or defaultPal)
  tip:SetOwner(UIParent, "ANCHOR_NONE")
  dhDrawTooltip(tip, lines)
  dhPlaceAttached(tip, handle)
end

local function dhHideTooltip()
  if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
end

-- A mark's own words (SR-L2), for a strip whose host wrote no descriptor for the mark nor for the
-- strip; `spec.L` overrides any key (rawget, as every library string). The X's is LibKa0s-Tooltip-1.0's
-- CloseTip for the strip's `owner`: "Close" unless that owner said otherwise.
lib.DRAG_HANDLE_STRINGS = { HELP_TIP = "Drag to move", SETTINGS_TIP = "Open settings" }

--- The library's descriptor for mark `key` (HELP_TIP, CLOSE_TIP, SETTINGS_TIP): its words as a title.
local function dhDefaultTip(spec, key)
  local L = type(spec.L) == "table" and spec.L or nil
  local v = L and rawget(L, key)
  if type(v) == "string" then return { title = v } end
  if key == "CLOSE_TIP" then
    local Tip = LibStub("LibKa0s-Tooltip-1.0", true)
    return { title = Tip and type(Tip.CloseTip) == "function" and Tip.CloseTip(spec.owner) or "Close" }
  end
  return { title = lib.DRAG_HANDLE_STRINGS[key] }
end

lib.__dragTipKit = { show = dhShowTooltip, hide = dhHideTooltip, default = dhDefaultTip }
