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
-- Minor 2: a refused rail click names its entry, for the shell's Cfg line (gap G3, 2026-09-30).
-- Minor 3: a registered skin owner's rail paints through its facade after its own paint: the pane
-- (S.Panel, `nav`) and each entry (S.NavItem: label, selection, bar) (LK-07 of the skinning run).
-- Minor 4: an entry's tooltip title through the page's O.__tipColor (`gtip.value`; OptionsScroll
-- minor 9), the instance read off the entry's last dress (LK-06d of Ka0sAddonsCommonTasks
-- docs/2026-10-30-SKIN_LIBRARY_FOLLOWUPS).
-- Still minor 4 (LK-06c of the same run, ruling R-5): an owned entry's hover art takes
-- `list.hoverArt` (S.NavItem's `hover`); every dress puts the art back on the client's first, so a
-- pooled entry drawn for no owner never keeps another owner's tint.
-- Minor 5 (cause L2 of Ka0sAddonsCommonTasks docs/2026-11-01-FULL_SKINNING): an entry's tooltip body through O.__tipColor (`gtip.line`).
-- Minor 6 (WFP-RV2-LK): O.NavRail gates `spec.entries` by `clients`.
-- Minor 7 (plan row L13 of docs/superpowers/plans/2026-11-13-callout.md): O.SideTabs, the rail's look
-- drawn INSIDE the page's content, under whatever the page drew above it: a list of tabs on the left
-- and the selected one's body on the right, both scrolling with the page. The rail is page chrome,
-- pinned beside the strip; a side-tab group divides one section, so it belongs to the content (the
-- reason O.SubTabStrip scrolls). The Callout's settings tab draws its Look and Sound with it.
local NAV_MINOR = 7
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
    GameTooltip:SetText(b.__ka0sNavText or "", b.__ka0sNavO.__tipColor("gtip.value", 1, 1, 1))
    local r, g, bl = b.__ka0sNavO.__tipColor("gtip.line")
    GameTooltip:AddLine(b.__ka0sNavTip, r, g, bl, true)
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
  b.__ka0sNavLabel, b.__ka0sNavSel, b.__ka0sNavHover = label, sel, hover
  attachEntryTooltip(b)
  return b
end

--- Put one pooled button into the state of one entry. EVERY field is re-applied, because the button
--- may have been another entry a moment ago (OptionsTabs.lua's dressTab says why at length).
--- The selected entry is the DISABLED one, as the active tab is: it neither highlights nor fires.
local function dressEntry(O, b, entry, selected, onSelect)
  b.__ka0sNavKey, b.__ka0sNavText, b.__ka0sNavTip = entry.key, entry.label, entry.tooltip
  b.__ka0sNavO = O   -- whose tooltip colors the next hover reads (minor 4): a pooled entry's last page
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
    if O.__combatRefused and O.__combatRefused("rail", entry.key) then return end
    if onSelect then pcall(onSelect, entry.key) end
  end)
  -- The hover art as the client draws it (minor 4), then the owner's skin over it.
  local hover = b.__ka0sNavHover
  if hover then
    if hover.SetDesaturated then hover:SetDesaturated(false) end
    hover:SetVertexColor(1, 1, 1)
  end
  if O.__chromePaint then
    O.__chromePaint("NavItem", b, { label = label, sel = b.__ka0sNavSel, selected = selected, hover = hover })
  end
end

-- ── the side tabs' frames (minor 7) ──────────────────────────────────────────────────────────
--
-- A side-tab group is an AceGUI SimpleGroup in the page's scroll, laid out by SIDE_LAYOUT: its one
-- child, the body, starts right of the rail and takes the rest of the width, and the group is as
-- tall as the body or the rail's entries, whichever is taller. The rail is a plain frame on the
-- group's frame, pinned to its left edge top to bottom, so it is as tall as the body it sits beside.
--
-- The group goes back to AceGUI's pool when the page's scroll is cleared, and its frame with it, so
-- the rail must not stay on it: the group's OnRelease callback hands the rail back to FREE_RAILS
-- (its entries to its own pool) and puts the group's layout back to List, AceGUI's default for a
-- container. A rail is taken from FREE_RAILS before one is built.

local SIDE_LAYOUT = "Ka0sSideTabs"
local FREE_RAILS = {}

--- AceGUI layout `SIDE_LAYOUT` (content, children): the body right of the rail, full height.
--- The rail's width and the entries' height are the group's own fields, set by O.SideTabs.
local function sideLayout(content, children)
  local obj = content.obj
  local railW = (obj and obj.__ka0sSideRailW) or RAIL_W
  local x = railW + RAIL_GAP
  local width = content.width or (content.GetWidth and content:GetWidth()) or 0
  local height = 0
  local body = children[1]
  if body then
    local f = body.frame
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", content, "TOPLEFT", x, 0)
    f:Show()
    body:SetWidth(math.max(0, width - x))
    if body.DoLayout then body:DoLayout() end
    height = f.height or (f.GetHeight and f:GetHeight()) or 0
  end
  height = math.max(height, (obj and obj.__ka0sSideMinH) or 0)
  if obj and obj.LayoutFinished then obj:LayoutFinished(nil, height) end
end

--- A rail for `group`, from FREE_RAILS or new, pinned to the group's left edge.
local function sideRail(group, width)
  local rail = table.remove(FREE_RAILS)
  if rail then
    rail:SetParent(group.frame)
  else
    rail = CreateFrame("Frame", nil, group.frame, "BackdropTemplate")
    if rail.SetBackdrop then
      rail:SetBackdrop(PANE_BACKDROP)
      rail:SetBackdropColor(PANE_FILL[1], PANE_FILL[2], PANE_FILL[3], PANE_FILL[4])
      rail:SetBackdropBorderColor(PANE_BORDER[1], PANE_BORDER[2], PANE_BORDER[3])
    end
    rail.__ka0sSidePool = Pool.New()
  end
  rail:ClearAllPoints()
  rail:SetPoint("TOPLEFT",    group.frame, "TOPLEFT",    0, 0)
  rail:SetPoint("BOTTOMLEFT", group.frame, "BOTTOMLEFT", 0, 0)
  rail:SetWidth(width)
  rail:Show()
  return rail
end

--- The group's OnRelease: the rail off the pooled frame and back on the free list. FREE_RAILS is
--- shared by every instance, so the rail goes back to client art first (lib.__chromeUnpaint, the
--- Skin record's saved backdrop, and untracked): a host with no skin that takes it next never draws
--- another owner's skin on its list, and the old owner's replays no longer reach it.
local function releaseSideRail(group, rail)
  if lib.__chromeUnpaint then lib.__chromeUnpaint(rail) end
  Pool.ReleaseAll(rail.__ka0sSidePool)
  rail:Hide()
  rail:ClearAllPoints()
  rail:SetParent(UIParent)
  FREE_RAILS[#FREE_RAILS + 1] = rail
  group.__ka0sSideRailW, group.__ka0sSideMinH = nil, nil
  if group.SetLayout then group:SetLayout("List") end
end

--- The selected entry: `value` when a drawn entry has it, else the first (a stale pointer heals).
local function sideSelected(entries, value)
  for _, e in ipairs(entries) do
    if e.key == value then return value end
  end
  return entries[1].key
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
    if O.__chromePaint then O.__chromePaint("Panel", rail, { nav = true }) end
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
    local entries = type(spec) == "table" and lib.__GateClients(spec.entries)   -- minor 6: `clients`
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

  --- The host's render for the selected tab, with the page's scroll pointed at the body: every
  --- member that draws into the page (O.RenderRows, O.Section, O.TextRow, O.InlineButtonPair, ...)
  --- reads ctx.scroll through O.EnsureScroll, so each draws into the body. The section trackers start
  --- fresh inside it, and the page's scroll and trackers come back whatever the render does.
  local function drawSideBody(ctx, body, render, key)
    local scroll, group, subgroup = ctx.scroll, ctx.lastGroup, ctx.lastSubgroup
    ctx.scroll, ctx.lastGroup, ctx.lastSubgroup = body, nil, nil
    local ok, err = pcall(render, ctx, key)
    ctx.scroll, ctx.lastGroup, ctx.lastSubgroup = scroll, group, subgroup
    if not ok and O.__print then
      O.__print(lib.STRINGS.RENDER_FAILED:format("side tab " .. tostring(key), tostring(err)))
    end
  end

  local function sideEntries(rail, entries, selected, onSelect)
    local buttons = {}
    local factory = function() return newEntry(rail) end
    Pool.ReleaseAll(rail.__ka0sSidePool)
    for i, entry in ipairs(entries) do
      local b = Pool.Acquire(rail.__ka0sSidePool, factory)
      dressEntry(O, b, entry, entry.key == selected, onSelect)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT",  rail, "TOPLEFT",   ENTRY_INSET, entryY(i))
      b:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -ENTRY_INSET, entryY(i))
      b:Show()
      buttons[i] = b
    end
    return buttons
  end

  --- A side-tab group (minor 7): the rail's look INSIDE the page's content, drawn where the page
  --- has got to, so whatever the page drew first (a preview, a heading) sits above it. A list of
  --- tabs on the left, the selected tab's body on the right; both scroll with the page.
  ---
  --- `spec` = { entries = { { key, label, tooltip, clients } }, value, onSelect, render, width }.
  --- `render(ctx, key)` draws the selected tab's body: it is called with the page's scroll pointed
  --- at the body, so O.RenderRows(ctx, rows) and the other members that add to the page draw there.
  --- Chrome members (O.TabStrip, O.NavRail, O.PageBanner, O.PageHeader) and O.ClearScroll are not
  --- called from it. The selection is the HOST's state, as O.NavRail's is: `value` names it (a key
  --- no drawn entry has selects the first, which is the key `render` is handed); a click calls
  --- `onSelect(key)` and then re-renders the page (O.RefreshPanel(ctx, true), the page's renderer,
  --- scroll offset kept), refused in combat as a rail click is. `width` is the list's, 120 by
  --- default; `clients` gates an entry as everywhere else.
  ---
  --- Returns the entry buttons in list order, the body (an AceGUI SimpleGroup) and the selected
  --- key, or nil having drawn nothing (no entry, no render, no AceGUI or no scroll).
  function O.SideTabs(ctx, spec)
    if not (ctx and type(spec) == "table" and type(spec.render) == "function") then return nil end
    local entries = lib.__GateClients(spec.entries)
    if type(entries) ~= "table" or #entries == 0 then return nil end
    local AceGUI, scroll = O.AceGUI, O.EnsureScroll(ctx)
    if not (AceGUI and scroll) then return nil end
    AceGUI:RegisterLayout(SIDE_LAYOUT, sideLayout)
    local selected, width = sideSelected(entries, spec.value), tonumber(spec.width) or RAIL_W
    local group = AceGUI:Create("SimpleGroup")
    group:SetFullWidth(true)
    group.__ka0sSideRailW, group.__ka0sSideMinH = width, 2 * ENTRY_TOP + #entries * ENTRY_H
    group:SetLayout(SIDE_LAYOUT)
    local body = AceGUI:Create("SimpleGroup")
    body:SetLayout("List")
    group:AddChild(body)
    scroll:AddChild(group)
    local rail = sideRail(group, width)
    group:SetCallback("OnRelease", function() releaseSideRail(group, rail) end)
    local buttons = sideEntries(rail, entries, selected, function(key)
      if type(spec.onSelect) == "function" then spec.onSelect(key) end
      O.RefreshPanel(ctx, true)
    end)
    if O.__chromePaint then O.__chromePaint("Panel", rail, { nav = true }) end
    drawSideBody(ctx, body, spec.render, selected)
    if body.DoLayout then body:DoLayout() end
    if group.DoLayout then group:DoLayout() end
    if scroll.DoLayout then scroll:DoLayout() end
    return buttons, body, selected
  end

  -- Test seams, `__`-prefixed and therefore outside every host's surface parity.
  O.__railInset         = lib.__railInset
  O.__railTop           = function(ctx) return railTop(ctx, activeArtHeight(O)) end
  O.__railEntryY        = entryY
  O.__navArtHeight      = function() return activeArtHeight(O) end
  O.__resetNavArtHeight = resetActiveArtHeight
  O.__sideLayout        = sideLayout
  O.__sideFreeRails     = function() return #FREE_RAILS end
end
