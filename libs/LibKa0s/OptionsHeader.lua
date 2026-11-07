-- LibKa0s-Options-1.0 -- the header block and the secondary tab strip: O.PageHeader and
-- O.SubTabStrip, the two chrome members that sit beside the page banner and the primary strip.
--
-- Peeled out of OptionsTabs.lua at its minor 17, unchanged (WFP-LK-08 of Ka0sAddonsCommonTasks
-- docs/2026-11-07-WOW_FOREVER_PORT), on the seam CLAUDE.md's band census named for that file ("the
-- header block and the sub-strip"). The history of both members is that file's header (minors 4, 10).
--
-- WHO CALLS IN. lib.__AttachTabs calls lib.__AttachHeader once per instance, after the members it
-- shares helpers with exist, handing over those helpers (`h`): the shell's sink, the skin call, the
-- chrome and ledger releases, the tab button and its dress, the width reader, the divider and the tab
-- art's height. Nothing
-- else crosses the cut. A copy without this file has no O.PageHeader and no O.SubTabStrip.
--
-- A file of the Options major, paired on the shell's minor with the same multi-file idiom as
-- OptionsTabbed.lua.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- Minor 1: the header block and the secondary strip, moved here unchanged from OptionsTabs.lua (its
-- minor 17).
local HEADER_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own: see OptionsScroll.lua.
if lib.__headerMinor and lib.__headerMinor >= HEADER_MINOR
  and lib.__headerShellMinor == lib.MINOR then return end
lib.__headerMinor      = HEADER_MINOR
lib.__headerShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsHeader = HEADER_MINOR

-- The same hard FLOOR OptionsTabs.lua declares: the header's frame comes from LibKa0s-Pool-1.0.
local Pool = LibStub and LibStub("LibKa0s-Pool-1.0", true)
local NEEDS_POOL = 1
if not Pool or (Pool.MINOR or 0) < NEEDS_POOL then return end

local L = lib.LAYOUT

--- The header block and the secondary strip for instance `O`. `h` is OptionsTabs.lua's helper table.
function lib.__AttachHeader(O, h)
  local print, skin, releaseChrome, releaseStaleBanner = h.print, h.skin, h.releaseChrome, h.releaseStaleBanner
  local releaseLedger, newTabButton, dressTab = h.releaseLedger, h.newTabButton, h.dressTab
  local frameWidth, drawChromeDivider, tabArtHeight = h.frameWidth, h.drawChromeDivider, h.tabArtHeight

  --- A host-drawn block pinned above the tab strip and the scroll, in the band the page banner
  --- occupies (options-ui-§14). The library owns the band arithmetic; the host owns everything
  --- inside the frame it is handed.
  ---
  --- This exists because controls that apply to EVERY tab must sit above the strip. A control that
  --- governs the whole page but is drawn under one tab reads as belonging to that tab, and it
  --- disappears the moment the player clicks a different one -- creating the thing the page edits,
  --- choosing which one is being edited, and the acts that apply to it whole (enable, unlock, copy,
  --- reset, delete) are all page-wide. O.PageBanner draws exactly one Dropdown and is documented as
  --- the page's ONLY picker, so what is generalized here is the BAND, not the banner.
  ---
  --- `spec` = { height = <number>, build = function(ctx, frame) end, divider = <boolean, default
  --- true> }. Returns the frame, or nil having drawn nothing.
  ---
  --- A page draws AT MOST ONE chrome block: this and O.PageBanner both release the chrome band and
  --- both write ctx.__bannerHeight, so the second call wins rather than stacking a second band. A
  --- page that needs a picker AND other page-wide controls puts the picker inside this frame and
  --- does not call PageBanner.
  ---
  --- Draw it BEFORE the strip, for the reason PageBanner gives: the strip's reservation reads
  --- ctx.__bannerHeight, and called the other way round it would not know about it.
  function O.PageHeader(ctx, spec)
    if not (ctx and ctx.chrome and spec) then return nil end
    local height = tonumber(spec.height)
    if not (height and height > 0) then return nil end

    releaseChrome(ctx)

    -- ONE FRAME PER PAGE (minor 4), from a pool of one held on the ctx, for the reason
    -- drawContentPanel gives for its panel: until minor 4 this was a CreateFrame per render, and
    -- the client never destroys a frame. The pool hides and parks it; the parent is the page's own
    -- chrome, which outlives every render. What the host's builder put INSIDE it is the host's to
    -- release, as it always was -- the frame coming back is the same one, so a host that
    -- creates raw regions into it on every build stacks them, where AceGUI widgets it Releases do not.
    ctx.__headerPool = ctx.__headerPool or Pool.New()
    local chrome = ctx.chrome
    local frame = Pool.Acquire(ctx.__headerPool, function() return CreateFrame("Frame", nil, chrome) end)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT",  ctx.chrome, "TOPLEFT",  0, 0)
    frame:SetPoint("TOPRIGHT", ctx.chrome, "TOPRIGHT", 0, 0)
    frame:SetHeight(height)
    frame:Show()
    ctx.__chromeKids[#ctx.__chromeKids + 1] = frame

    -- The hairline sits at the RAW height, never the widened band: it separates the block from
    -- what comes after it, so it is measured off the block's own bottom edge.
    if spec.divider ~= false then skin("Divider", drawChromeDivider(ctx, height), { token = "tab.rule" }) end

    local band = O.__bannerBand(height)
    ctx.__bannerHeight = band
    O.SetChromeHeight(ctx, band)

    -- pcall'd and REPORTED, for the reason every host callback in this file is: the builder reaches
    -- into live addon state, and a raise inside the render pass would cost the strip and the whole
    -- page under it rather than the block.
    if type(spec.build) == "function" then
      local ok, err = pcall(spec.build, ctx, frame)
      if not ok then print(lib.STRINGS.HEADER_FAILED:format(tostring(err))) end
    end
    -- After the builder, not before: a builder that makes a Dropdown of its own must not be handed
    -- back the banner's, which may still be running its callback (see releaseStaleBanner).
    releaseStaleBanner(ctx)

    return frame
  end

  --- A SECONDARY tab strip, drawn inside the scroll as ordinary page content (options-ui-§13).
  ---
  --- The primary strip is pinned in the chrome band and does not scroll; a secondary strip belongs
  --- to the content it divides, so it scrolls with it. Pinning a second band would double the
  --- chrome and push the page down twice for a division that is not page-wide.
  ---
  --- `spec` = { tabs = { { key, label, tooltip } }, value, onSelect }. Returns the buttons in tab
  --- order and the total height the strip occupies, so the host can size the frame it handed in --
  --- or nil having drawn nothing. It draws NO content panel: the page already has one.
  ---
  --- THE STATE KEY IS THE HOST'S, not ctx.activeTab -- `spec.value` and `spec.onSelect` are the
  --- whole contract, and the library reads neither back. The convention this establishes for the
  --- collection is `ctx.activeSubTab` as a TABLE keyed by the primary tab's key, so switching
  --- category and back remembers the subject you were on and a stale pointer heals per category.
  --- Session state either way, and never persisted (options-ui-§13).
  function O.SubTabStrip(ctx, parent, spec)
    spec = lib.__GateTabSpec(spec)
    if not (ctx and parent and spec and type(spec.tabs) == "table" and #spec.tabs > 0) then
      return nil
    end
    if not O.AceGUI then return nil end

    -- Its own ledger, released on entry exactly as TabStrip releases __tabKids: a secondary strip
    -- is redrawn whenever its category is, and buttons left parented to the host's frame would
    -- stack -- with the older set on top, swallowing the clicks.
    releaseLedger(ctx, "__subTabKids")

    -- NOT POOLED, unlike the primary strip's, and the asymmetry is the parent. A secondary strip
    -- hangs off a frame the HOST added as an AceGUI child, which ClearScroll gives back to AceGUI's
    -- own pool -- so its buttons have to be unparented on release, and an unparented button is one
    -- a free list could only ever hand back drawn onto nothing. The two-tier render means a sub
    -- strip is rebuilt only when its category is, not on every click within it.
    local buttons, widths = {}, {}
    for i, tab in ipairs(spec.tabs) do
      local b = newTabButton(parent)
      buttons[i] = b
      widths[i]  = dressTab(b, tab, tab.key == spec.value, spec.onSelect)
      ctx.__subTabKids[#ctx.__subTabKids + 1] = b
    end

    -- The SAME selection-invariant pitch the primary strip packs by, and `top` is 0 because there
    -- is no banner above a strip that is already inside the page.
    local pitch = tabArtHeight()
    local placement, rowCount =
      O.__tabPlacement(widths, frameWidth(parent), L.TAB_GAP, 0, pitch)
    for _, place in ipairs(placement) do
      local b = buttons[place.index]
      b:SetWidth(place.width)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", parent, "TOPLEFT", place.x, place.y)
      b:Show()
    end

    return buttons, O.__tabBand(0, rowCount, L.TAB_H, pitch)
  end
end
