-- LibKa0s-Widgets-1.0 -- the drag handle's tooltip: the descriptor's three bands evaluated on each
-- hover, the owner it is shown by, and the host's placement hook (WidgetsDragHandle minors 3, 4 and 7).
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
-- it. Nothing else crosses the cut.
--
-- A file of the Widgets major, paired on the shell's minor with the same multi-file idiom as
-- WidgetsDragHandle.lua itself.
--
-- WHERE IT OPENS (still minor 1, LK-92B of the same bundle, LibKa0s#92 part B; design section 3.6).
-- A HUD strip is the display's TOP CHROME (WowAddonStandards standalone-windows, *Tooltip
-- placement*, the chrome reading v2.112.0 flagged), so its tooltip, and its marks', attaches
-- centered BELOW THE STRIP through LibKa0s-Tooltip-1.0's PlaceAttached, read at hover time. It is
-- always owned by UIParent at ANCHOR_NONE and placed by absolute points, which a restricted layout
-- tree (AuraMaster's anchors) accepts. A host's `tooltipPlace` (or a descriptor's `place`) still
-- wins when it answers `true`; a raise or any other answer falls back to the attached placer, never
-- the cursor (anti-pattern #119). `tooltipOwner = "cursor"`, `tooltipAnchor` and a descriptor's
-- `owner` and `anchor` are RETIRED: still accepted, no longer read (the frozen -1.0 major removes
-- no field).

local lib = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
if not lib then return end

-- Minor 1: the tooltip half, moved here unchanged from WidgetsDragHandle.lua (its minor 14).
local DRAGTIP_MINOR = 1
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

--- The host's placement hook for this descriptor, or nil (minor 4). The descriptor's own `place`
--- wins over `spec.tooltipPlace`. A value that is not a
--- function is ignored rather than called, so a typo costs the hook and not the tooltip's owner.
local function dhPlacer(spec, t)
  if type(t.place) == "function" then return t.place end
  if type(spec.tooltipPlace) == "function" then return spec.tooltipPlace end
  return nil
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

--- The library's placement: attached and centered below the STRIP (`handle`), whichever of its
--- frames is hovered (a mark places by its strip, as AuraMaster's StripOf did). Unreadable geometry,
--- or no Tooltip major, attaches it below the strip by a relative point, which a restricted tree
--- refuses, so under pcall; a refused point leaves the tooltip with no anchor (the points were
--- cleared), never at the cursor. Reached only when the strip's geometry cannot be read.
local function dhPlaceAttached(tip, handle)
  local Tip = LibStub("LibKa0s-Tooltip-1.0", true)
  if Tip and Tip.PlaceAttached(tip, handle, "top") then return end
  tip:ClearAllPoints()
  pcall(tip.SetPoint, tip, "TOP", handle, "BOTTOM", 0, -2)
end

--- Show the descriptor's tooltip for `frame`, the frame hovered and the frame a placement hook is
--- handed: owned by UIParent at ANCHOR_NONE, evaluated and drawn, SHOWN (so a placement reads the
--- tooltip's measured size), then the host's hook under pcall when there is one, and the library's
--- attached placement unless that hook answered a literal `true`. `handle` is the strip, whose
--- palette colors the bands (minor 7); `defaultPal` is WidgetsDragHandle.lua's owner-less palette,
--- for a handle that carries none.
local function dhShowTooltip(handle, frame, spec, t, defaultPal)
  local tip = GameTooltip
  if not (t and tip and tip.SetOwner and tip.SetText) then return end
  local lines = dhTooltipLines(t, handle.__pal or defaultPal)
  tip:SetOwner(UIParent, "ANCHOR_NONE")
  dhDrawTooltip(tip, lines)
  local place = dhPlacer(spec, t)
  if place then
    local ok, placed = pcall(place, tip, frame)
    if ok and placed == true then return end
  end
  dhPlaceAttached(tip, handle)
end

local function dhHideTooltip()
  if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
end

lib.__dragTipKit = { show = dhShowTooltip, hide = dhHideTooltip }
