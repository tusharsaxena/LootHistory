-- LibKa0s-Options-1.0 -- the nav rail: a pinned vertical list at the left of a page's body, the FIRST
-- level of a page that edits one instance out of many; the pinned primary tab strip drawn to its
-- right is the second (options-ui-§13). A host folds what would otherwise be several sub-pages,
-- all retargeted by one picker, into one page, and the rail chooses among them.
--
-- A sixth file of the Options major (minor 1), guarded with the same multi-file idiom as
-- OptionsTabs.lua and OptionsScroll.lua. A new file rather than an append because both files it
-- reaches into are at their accepted size (CLAUDE.md's census): Options.lua and OptionsTabs.lua
-- carry only guarded reads of `lib.__railInset`, so a copy vendored without this file lays every
-- page out exactly as it did before the rail existed.
--
-- The look is AceGUI's TreeGroup tree pane -- a list on the left for the first level, gold tabs on
-- top for the second, so the two cannot be mistaken for one another. The geometry is AuraMaster's
-- Test10 (the 2026-09-26 settings lab), which its owner chose over nine alternatives.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- The primary strip's floor, for the primary strip's reason: the entries are pooled per page.
local Pool = LibStub and LibStub("LibKa0s-Pool-1.0", true)
local NEEDS_POOL = 1
if not Pool or (Pool.MINOR or 0) < NEEDS_POOL then return end

-- Minor 1: O.NavRail, the one inset the strip, the content panel and the scroll read
-- (lib.__railInset), and the rail's top measured off the selected tab's art.
local NAV_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own -- see OptionsScroll.lua for why.
if lib.__navMinor and lib.__navMinor >= NAV_MINOR
  and lib.__navShellMinor == lib.MINOR then return end
lib.__navMinor      = NAV_MINOR
lib.__navShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsNav = NAV_MINOR

local L = lib.LAYOUT

-- File-local, not lib.LAYOUT: tests/test_options.lua's LAYOUT gate reads Options.lua alone, and no
-- host sizes anything off these. A host wanting another width passes spec.width.
local RAIL_W      = 120   -- Test10's NAV_W
-- Rail edge to the content column. With it the content panel's left edge (PANEL_LEFT + inset) lands
-- 4px right of the rail's right edge (CONTENT_LEFT + width), and the first tab and the scroll start
-- at CONTENT_LEFT + width + 12 -- Test10's arrangement, without moving the body from outside.
local RAIL_GAP    = 12
local ENTRY_H     = 20
local ENTRY_TOP   = 8
local ENTRY_INSET = 5
local LABEL_X     = 6
local SELECT_TEX  = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"
local SELECT_RGB  = { 0.3, 0.5, 1 }
local LABEL_GOLD  = { 1, 0.82, 0 }
local LABEL_WHITE = { 1, 1, 1 }
local ACTIVE_CAP  = "Options_Tab_Active_Left"
local PANE_BACKDROP = {
  bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 3, right = 3, top = 5, bottom = 3 },
}
local PANE_FILL   = { 0.1, 0.1, 0.1, 0.5 }
local PANE_BORDER = { 0.4, 0.4, 0.4 }

-- ── the one inset ──────────────────────────────────────────────────────────────────────────

--- How far right of the content column everything beside the rail starts: the rail's width plus its
--- gap, or 0 for a page with no rail. LIBRARY-level, because OptionsTabs.lua's drawContentPanel is a
--- file-level local with no instance in reach; placeTabs and the shell's anchorScroll read this same
--- function, so the three cannot disagree -- the job __scrollTopInset does for the top edge.
--- @return number
function lib.__railInset(ctx)
  local w = ctx and ctx.railWidth
  if type(w) ~= "number" or w <= 0 then return 0 end
  return w + RAIL_GAP
end

-- ── the rail's top ───────────────────────────────────────────────────────────────────────────
--
-- The tab art is bottom-anchored in a TAB_H button, so the button's top is not where a tab visibly
-- starts. The rail's top is level with the SELECTED tab's art, the tallest thing on the row (the lab
-- measured the highest shown texture, which is that one). Its atlas is measured once on a probe
-- texture, as OptionsTabs.lua measures the unselected one, and cached on success only, so a call
-- made before the client resolves the atlas cannot pin a fallback for the session.
local measuredActiveH
local probeFrame

local function probeTexture()
  probeFrame = probeFrame or CreateFrame("Frame", nil, UIParent)
  if probeFrame.Hide then probeFrame:Hide() end
  local tex = probeFrame.__ka0sNavProbe
  if not tex and probeFrame.CreateTexture then
    tex = probeFrame:CreateTexture(nil, "BACKGROUND")
    probeFrame.__ka0sNavProbe = tex
  end
  return tex
end

--- The selected tab's art height; the strip's own pitch (and through it TAB_H) where nothing measures.
local function activeArtHeight(O)
  if measuredActiveH then return measuredActiveH end
  local h
  local tex = probeTexture()
  if tex and tex.SetAtlas then
    tex:SetAtlas(ACTIVE_CAP, true)
    h = tex.GetHeight and tex:GetHeight()
  end
  if type(h) == "number" and h > 0 and h <= L.TAB_H then
    measuredActiveH = h
    return h
  end
  return (O.__tabArtHeight and O.__tabArtHeight()) or L.TAB_H
end

local function resetActiveArtHeight()
  measuredActiveH, probeFrame = nil, nil
end

--- The rail's top edge below the body's top: the banner's band, then the empty strip above the art.
local function railTop(ctx, artH)
  return -(((ctx and ctx.__bannerHeight) or 0) + (L.TAB_H - artH))
end

local function entryY(i)
  return -(ENTRY_TOP + (i - 1) * ENTRY_H)
end

-- ── the frames ───────────────────────────────────────────────────────────────────────────────

--- The rail itself: ONE per page, built on the first render that draws a rail and kept, the way
--- OptionsTabs.lua keeps a page's rule texture. A child of the BODY, so the combat cover's level walk
--- (lib.__coverLevel) finds it and the cover goes over it.
local function railFrame(ctx)
  local rail = ctx.__railFrame
  if rail then return rail end
  rail = CreateFrame("Frame", nil, ctx.body, "BackdropTemplate")
  if rail.SetBackdrop then
    rail:SetBackdrop(PANE_BACKDROP)
    rail:SetBackdropColor(PANE_FILL[1], PANE_FILL[2], PANE_FILL[3], PANE_FILL[4])
    rail:SetBackdropBorderColor(PANE_BORDER[1], PANE_BORDER[2], PANE_BORDER[3])
  end
  ctx.__railFrame = rail
  return rail
end

--- Wired ONCE per entry and re-aimed by every dress, as a tab's tooltip is (HookScript would
--- accumulate a pair of handlers per render on a pooled button).
local function attachEntryTooltip(b)
  b:SetScript("OnEnter", function()
    if not (GameTooltip and b.__ka0sNavTip) then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetText(b.__ka0sNavText or "", 1, 1, 1)
    GameTooltip:AddLine(b.__ka0sNavTip, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
end

--- A bare entry: the button, its label, the hover glow and the selection bar. The pool's factory;
--- nothing here depends on WHICH entry it will be.
local function newEntry(rail)
  local b = CreateFrame("Button", nil, rail)
  b:SetHeight(ENTRY_H)
  local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("LEFT", b, "LEFT", LABEL_X, 0)
  label:SetJustifyH("LEFT")
  local hover = b:CreateTexture(nil, "HIGHLIGHT")
  hover:SetTexture(SELECT_TEX)
  hover:SetBlendMode("ADD")
  hover:SetAllPoints(b)
  local sel = b:CreateTexture(nil, "BACKGROUND")
  sel:SetTexture(SELECT_TEX)
  sel:SetVertexColor(SELECT_RGB[1], SELECT_RGB[2], SELECT_RGB[3])
  sel:SetBlendMode("ADD")
  sel:SetAllPoints(b)
  b.__ka0sNavLabel, b.__ka0sNavSel = label, sel
  attachEntryTooltip(b)
  return b
end

--- Put one pooled button into the state of one entry. EVERY field is re-applied, because the button
--- may have been another entry a moment ago (OptionsTabs.lua's dressTab says why at length).
--- The selected entry is the DISABLED one, as the active tab is: it neither highlights nor fires.
local function dressEntry(O, b, entry, selected, onSelect)
  b.__ka0sNavKey, b.__ka0sNavText, b.__ka0sNavTip = entry.key, entry.label, entry.tooltip
  b.__ka0sNavSelected = selected
  local label = b.__ka0sNavLabel
  local rgb = selected and LABEL_WHITE or LABEL_GOLD
  label:SetText(entry.label or "")
  label:SetTextColor(rgb[1], rgb[2], rgb[3])
  b.__ka0sNavSel:SetAlpha(selected and 1 or 0)
  b:SetEnabled(not selected)
  b:SetScript("OnClick", function()
    if selected then return end
    -- A rail switch is a structural re-render, refused in combat exactly as a tab click is
    -- (options-ui-§2, §13). The library owns the refusal; a host adds no guard of its own.
    if O.__combatRefused and O.__combatRefused() then return end
    if onSelect then pcall(onSelect, entry.key) end
  end)
end

-- ── the instance half ────────────────────────────────────────────────────────────────────────

function lib.__AttachNav(O)
  local function placeRail(ctx, width)
    local rail = railFrame(ctx)
    rail:ClearAllPoints()
    rail:SetPoint("TOPLEFT",    ctx.body, "TOPLEFT",    L.CONTENT_LEFT, railTop(ctx, activeArtHeight(O)))
    rail:SetPoint("BOTTOMLEFT", ctx.body, "BOTTOMLEFT", L.CONTENT_LEFT, L.PANEL_BOTTOM)
    rail:SetWidth(width)
    rail:Show()
    return rail
  end

  --- A live scroll moves at once, whether or not the page reserved a band (a bannerless page has
  --- none); a strip drawn next reads the inset as it places itself. Re-reserving the same band is
  --- SetChromeHeight's idempotent re-anchor. With no scroll yet, EnsureScroll anchors it later.
  local function reanchor(ctx)
    if (ctx.scroll or (ctx.chromeHeight or 0) > 0) and O.SetChromeHeight then
      O.SetChromeHeight(ctx, ctx.chromeHeight or 0)
    end
  end

  --- The pinned nav rail (options-ui-§13): the first level of a page that edits one instance out of
  --- many. Draw it AFTER O.PageBanner and BEFORE O.TabStrip: it reads the band the banner reserved
  --- (`ctx.__bannerHeight`) for its top, and the strip reads the width it records for its inset.
  ---
  --- `spec` = { entries = { { key, label, tooltip } }, value, onSelect, width }. `width` defaults to
  --- 120. The selection is the HOST's state, as SubTabStrip's is: `spec.value` and `spec.onSelect`
  --- are the whole contract. Returns the entry buttons in rail order, or nil having drawn nothing (an
  --- empty list releases the rail and gives the page its full width back).
  ---
  --- Entries are POOLED per page and released on every call, as the primary strip's tabs are. The
  --- rail is chrome, not scroll content: O.ClearScroll does not touch it.
  function O.NavRail(ctx, spec)
    if not (ctx and ctx.body) then return nil end
    ctx.__railPool = ctx.__railPool or Pool.New()
    Pool.ReleaseAll(ctx.__railPool)
    ctx.__railKids = {}
    local entries = type(spec) == "table" and spec.entries
    if type(entries) ~= "table" or #entries == 0 then
      ctx.railWidth = 0
      if ctx.__railFrame then ctx.__railFrame:Hide() end
      reanchor(ctx)
      return nil
    end
    local width = tonumber(spec.width) or RAIL_W
    ctx.railWidth = width
    local rail = placeRail(ctx, width)
    local factory = function() return newEntry(rail) end
    local buttons = {}
    for i, entry in ipairs(entries) do
      local b = Pool.Acquire(ctx.__railPool, factory)
      dressEntry(O, b, entry, entry.key == spec.value, spec.onSelect)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT",  rail, "TOPLEFT",   ENTRY_INSET, entryY(i))
      b:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -ENTRY_INSET, entryY(i))
      b:Show()
      buttons[i], ctx.__railKids[i] = b, b
    end
    reanchor(ctx)
    return buttons
  end

  -- Test seams, `__`-prefixed and therefore outside every host's surface parity.
  O.__railInset         = lib.__railInset
  O.__railTop           = function(ctx) return railTop(ctx, activeArtHeight(O)) end
  O.__railEntryY        = entryY
  O.__navArtHeight      = function() return activeArtHeight(O) end
  O.__resetNavArtHeight = resetActiveArtHeight
end
