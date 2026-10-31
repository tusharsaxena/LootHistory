local _, NS = ...

-- The AH price tab's table: moved verbatim out of settings/Panel.lua, which reaches it through
-- P._buildAuctionTable when the tab renders. Loaded directly after it.

local P = NS.Panel
local O = NS.Options
local acquire, runRebuilders = P._acquire, P._runRebuilders

-- ── Auction House price table (unified collect + priority) ───────────────────────
-- ONE frame-light table replaces the old Data Collection + Priority sections. Every text column is a
-- FontString (a region, not a frame); only the genuinely-interactive cells (enable checkbox, ⓘ info)
-- plus the library's drag handle are real frames, and the row slots + their frames are created ONCE
-- and reused on every refresh — never re-allocated. This is load-bearing: the Blizzard Settings
-- canvas runs a super-linear pass over a panel's frames on tab-transition, so the previous ~213-frame
-- AH page froze the client ~1.7s when you navigated away from it (see docs/settings-panel.md).
-- The leading tick and the row's info button are LibKa0s-Media marks now, with the Blizzard art
-- beneath them as the fallback rung. This addon still ships no art files of its own.
--
-- ── WHAT R6 CHANGED, AND WHAT IT DELIBERATELY DID NOT ─────────────────────────────────────────
--
-- The ▲▼ arrows are gone (anti-pattern #75, options-ui-§18): the cascade is dragged now, through
-- LibKa0s-Widgets-1.0's shared ReorderList. That needed a REAL FRAME per row — the widget anchors
-- its handle to it, fades it to 0.35 while it is carried, and draws the bounded box behind it — so
-- each slot is a Frame with its FontStrings parented to it instead of eleven sets of regions on one
-- host. THE POOLING IS UNCHANGED: the slots are still created once and repainted in place, which is
-- the whole reason this page does not freeze the client.
--
-- The host draws NO row background and NO row border. The library owns both now, and a host copy
-- beside them is double chrome (options-ui-§18). It never had one, so there was nothing to delete.

-- THESE THREE BLIZZARD PATHS ARE THE FALLBACK RUNG, NOT THE ART. LibKa0s-Media ships all three
-- marks — `circle-check`, `ban` and `info` — so the catalog is what draws on a working
-- install and these are what the ladder walks down to when the library is absent, exactly as
-- every other art site in this addon does (core/MediaSetup.lua). They are spelled out rather
-- than deleted because NS.Icon answers nil twice over — no library, or no such name — and a
-- nil spliced into a `|T` escape is not a blank square, it is a swallowed escape.
local READY     = "Interface\\RaidFrame\\ReadyCheck-Ready"      -- fallback for `circle-check`
local NOTREADY  = "Interface\\RaidFrame\\ReadyCheck-NotReady"   -- fallback for `ban`
local INFO_ICON = "Interface\\FriendsFrame\\InformationIcon"    -- fallback for `info`

-- Shared column x-offsets, in px from each ROW's content origin — which is the far side of the drag
-- handle's gutter, not the row's left edge: the handle owns a fixed-width gutter at the far left and
-- row contents start beyond it (options-ui-§18). Headers and every cell add the same gutter, so the
-- columns line up: [handle] [tick] [Addon] [Price module] [On ☑] [Status]. The ⓘ is NOT a fixed
-- column — it trails each row's Price module text (positioned per-row in the refresh).
--
-- The old `order` column is gone with the arrows it held.
local ACOL = { tick = 2, addon = 26, module = 148, enabled = 330, status = 362 }
local AROW_H, AHEAD_H = 22, 32   -- row pitch; AHEAD_H = header→first-row gap (roomy header band)
local HEAD_Y = -8                -- header baseline inside the host (gap above the header)
-- THE SKIN (LH-04). The table's colors are tokens, read where the literals stood: the column headers
-- text.headingAlt (the off-gold this table has always drawn, kept apart from text.heading), a live
-- row's addon name text.bodyAlt and module text.body, an inactive row's text.disabled, the info mark
-- icon.hot / icon.dim, the info tooltip gtip.value over gtip.title, and the status sem.statusOk /
-- statusWarn / statusBad (STATUS_TOKEN below). repaintAuctionTable repaints the host on a switch,
-- parked or not, and the ticks are rebuilt first. tests/panel_auction_golden.txt does not move.
--
-- Status colors: collecting = green, not collecting = yellow, not installed = red.
--
-- SATURATED, NOT MUTED, and that is a correction rather than a preference. These read
-- {0.46,0.60,0.46} / {0.66,0.62,0.42} / {0.62,0.45,0.45} and the comment above them called them
-- "extremely muted" approvingly -- but desaturated that far, on this panel's near-black backdrop,
-- the three are three shades of gray-brown, and being legible at a glance is the entire job of a
-- status column.
--
-- The reference is the collection's own marks: ConsumableMaster's legend draws Blizzard's
-- ReadyCheck-Ready, ReadyCheck-NotReady and FavoritesIcon, which are vivid because the ART is
-- vivid. This column tints WHITE catalog art instead, so the saturation has to come from here; a
-- muted tint on white art just yields a muted mark.
--
-- These carry TWICE -- the Status column's text color, and the tick marks below, whose tint is
-- baked into the |T escape because an inline texture is not reached by SetTextColor. A skin that
-- moves one moves both, which is the point of their being one table. The values are the skin's
-- sem.status* tokens (the saturated triple above, in Ka0s Default).
local STATUS_TOKEN = {
  collecting = "sem.statusOk", notcollecting = "sem.statusWarn", notinstalled = "sem.statusBad",
}

-- THE SETTINGS-PANEL SCOPE. The AH price table is on the settings panel, so it follows the Scope's
-- "Ignore settings panel" like the AceGUI rows and the drag list (LibKa0s WidgetsReorder minor 3,
-- panel-scoped by default) beside it, and one page never mixes stock and skinned (D-03 of
-- Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_LIBRARY_FOLLOWUPS/). Every paint this file makes on the
-- table reads NS.SkinPanelColor, which answers Ka0s Default's value (the table's look before skins)
-- while the panel is ignored. Its strings go through S.Text(fs, token, PANEL), a recorded paint
-- that gives each its template face back while the panel is ignored, live both ways; the color is
-- then written over it (the same value while the panel is skinned), because the status colors are
-- the column's meaning and stay on a stock page.
local PANEL = { panel = true }
local function paintText(fs, token)
  NS.Skin.Text(fs, token, PANEL)
  fs:SetTextColor(NS.SkinPanelColor(token))
end

-- The tick column's two states, built once (and again on a skin change, rebuildTicks) the way
-- modules/BrowserTable.lua builds its sort arrows — the row loop repaints pooled slots on every
-- refresh and has no business reformatting a constant string each time.
--
-- THE TINT IS LOAD-BEARING, and it is why these are NS.IconMarkup calls rather than bare paths.
-- Catalog art is white by contract (the shape lives entirely in the alpha channel), and white is
-- not a status: green-means-collecting / red-means-not is the whole signal this column carries.
-- An inline texture is drawn white and is NOT reached by the FontString's SetTextColor, so the
-- tint has to be baked into the escape's own vertex fields. On the fallback rung it multiplies
-- Blizzard's already-green tick by a green and its already-red mark by a red, so a degraded
-- install still reads green-or-red, a shade darker.
local TICK_ON, TICK_OFF
local function rebuildTicks()
  local r, g, b = NS.SkinPanelColor(STATUS_TOKEN.collecting)
  TICK_ON = NS.IconMarkup("circle-check", READY, 16, r, g, b)
  r, g, b = NS.SkinPanelColor(STATUS_TOKEN.notinstalled)
  TICK_OFF = NS.IconMarkup("ban", NOTREADY, 16, r, g, b)
end
rebuildTicks()

--- The handle gutter, READ off the library rather than restated (options-ui-§8/§18).
---
--- Zero without the library, and that is the honest answer rather than a fallback constant: the
--- degraded path draws no handle at all, so reserving a gutter for it would indent every column
--- past nothing.
local function handleGutter()
  local box = NS.ReorderRowBox and NS.ReorderRowBox()
  return (box and box.HANDLE_W) or 0
end

-- Human name for the addon behind a "provider:key" tag (e.g. "auctionator:minbuyout" → "Auctionator").
local function providerNameOf(tag)
  local prov = tag:match("^(.-):")
  return (prov and NS.Constants.AUCTION_PROVIDER_NAMES[prov]) or prov or tag
end

-- Short data-point label for a "provider:key" tag (the `data` column form from AUCTION_KEYS).
local function dataLabelOf(tag)
  local prov, key = tag:match("^(.-):(.+)$")
  for _, k in ipairs(NS.Constants.AUCTION_KEYS) do
    if k.provider == prov and k.key == key then return k.data or k.label end
  end
  return key or tag
end

-- Label/desc for a tag's ⓘ tooltip.
local function keyMetaOf(tag)
  local prov, key = tag:match("^(.-):(.+)$")
  for _, k in ipairs(NS.Constants.AUCTION_KEYS) do
    if k.provider == prov and k.key == key then return k.label, k.desc end
  end
  return tag, nil
end

-- GameTooltip on hover, shared by the ⓘ buttons. `getTitle`/`getBody` are read on enter so a reused
-- slot always shows its current tag's text.
local function tipScripts(btn, getTitle, getBody)
  btn:SetScript("OnEnter", function()
    if not GameTooltip then return end
    local title = getTitle and getTitle()
    if not title or title == "" then return end
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, NS.SkinPanelColor("gtip.value"))
    local body = getBody and getBody()
    -- In the tooltip's own default line color (the client's gold), now named: gtip.title.
    if body then
      local r, g, b = NS.SkinPanelColor("gtip.title")
      GameTooltip:AddLine(body, r, g, b, true)
    end
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

--- Release the live reorder controller, if there is one.
---
--- CALLED AT THE TOP OF THE PAGE RENDER, before the first widget is created — not merely before the
--- list is rebuilt. Handles and row boxes are POOLED, and releasing one is what takes it off the
--- host frame it was parented to; that frame goes back to AceGUI's pool the moment ClearScroll runs,
--- so a Cancel that ran afterwards would be reclaiming chrome from a widget that already belongs to
--- something else. This is the single most common way an adoption of this widget goes wrong
--- (options-ui-§18), so it is a named function called from exactly two places rather than a line
--- someone can move.
local function cancelReorder(ctx)
  local list = ctx._priList
  ctx._priList = nil
  if list then list:Cancel() end
end

-- The tags in display order: Collecting → Not collecting → Addon not installed, each group keeping
-- the natural priority-array order within it. Also hands back the collecting group, whose display
-- slots 1..#collecting are the draggable ones and whose indices a drag's onMove speaks in.
local function partitionTags(priority, capture)
  local collecting, notCollecting, notInstalled = {}, {}, {}
  for _, tag in ipairs(priority) do
    local prov = tag:match("^(.-):")
    if not NS.AuctionPrice:IsProviderAvailable(prov) then notInstalled[#notInstalled + 1] = tag
    elseif capture[tag] then collecting[#collecting + 1] = tag
    else notCollecting[#notCollecting + 1] = tag end
  end
  local order = {}
  for _, t in ipairs(collecting)    do order[#order + 1] = t end
  for _, t in ipairs(notCollecting) do order[#order + 1] = t end
  for _, t in ipairs(notInstalled)  do order[#order + 1] = t end
  return order, collecting
end

-- A source's Status cell: its text and its color token.
local function auctionStatus(avail, on)
  if not avail then return "Addon not installed", STATUS_TOKEN.notinstalled end
  if on then return "Collecting data", STATUS_TOKEN.collecting end
  return "Not collecting data", STATUS_TOKEN.notcollecting
end

-- Repaint one reused row slot for `tag`.
local function paintAuctionRow(r, tag, capture)
  local prov = tag:match("^(.-):")
  local avail = NS.AuctionPrice:IsProviderAvailable(prov)
  local on = capture[tag] and true or false
  local live = on and avail          -- collecting right now
  r._tag = tag

  r.tick:SetText(live and TICK_ON or TICK_OFF)

  -- Addon name: no per-provider color any more — just near-white, dimmed when inactive.
  r.addon:SetText(providerNameOf(tag))
  paintText(r.addon, live and "text.bodyAlt" or "text.disabled")

  r.module:SetText(dataLabelOf(tag)); paintText(r.module, live and "text.body" or "text.disabled")
  -- ⓘ trails the Price module text with a small gap (per-row, since the text width varies).
  local mw = r.module:GetStringWidth() or 0
  r.info:ClearAllPoints()
  r.info:SetPoint("LEFT", r.frame, "LEFT", r._gutter + ACOL.module + mw + 6, 0)

  local text, token = auctionStatus(avail, on)
  r.status:SetText(text)
  paintText(r.status, token)

  r.info.tex:SetVertexColor(NS.SkinPanelColor(live and "icon.hot" or "icon.dim"))

  -- Enabled box: checked only when actually collecting (an uninstalled source reads unchecked),
  -- and non-interactive when the addon isn't present.
  r.check:SetValue(live)
  r.check:SetDisabled(not avail)
end

-- Re-partition the tags into three groups and repaint the reused row slots. Only the Collecting
-- group (top) is draggable, and `boundary` is what stops a drag leaving it. The partition, the row
-- paint and the status cell are the helpers above (GI-LH-02: this was one function at CCN 36 once
-- lizard could see it); tests/test_panel_auction.lua pins every row's paint.
local function refreshAuctionTable(ctx)
  local rows = ctx._priRows
  if not rows then return end
  local hf = ctx._priHost
  local priority = NS.AuctionPrice:ReconcilePriority()
  local capture = NS.db.profile.settings.auction.capture or {}
  local order, collecting = partitionTags(priority, capture)
  local nActive = #collecting

  -- A repaint is a NEW controller: it holds the rows of the pass that built it (the library says so
  -- in as many words), and the old one is describing a partition that no longer exists. Safe here
  -- without the top-of-render rule above, because a repaint creates no AceGUI widget and releases
  -- none — the handles go back to the pool and come straight out of it again.
  cancelReorder(ctx)
  local list = NS.MakeReorderList{
    stride   = AROW_H,
    boundary = nActive,
    handleTooltip = "Drag to re-rank",
    -- ONE WRITE, not a run of adjacent swaps. `from`/`to` are display indices, and the collecting
    -- group occupies display slots 1..nActive, so they are indices into `collecting` directly.
    onMove = function(from, to)
      NS.AuctionPrice:MovePriorityWithin(collecting, from, to)
      runRebuilders(ctx)
    end,
  }
  ctx._priList = list

  for i, tag in ipairs(order) do
    local r = rows[i]
    paintAuctionRow(r, tag, capture)

    -- Registered in DISPLAY order, every row, draggable or not: an inert row is still a place a drag
    -- can LAND, still counts for the index arithmetic, and still wants the bounded box — a stack
    -- where only some rows have an edge reads as a rendering fault rather than as a rule.
    if list then
      list:AddRow(r.frame, {
        draggable = i <= nActive,
        dimmed    = i > nActive,
        ghostText = providerNameOf(tag) .. " — " .. dataLabelOf(tag),
      })
    end
  end

  if list then list:Finish(hf) end
end

-- The context whose host holds the table: one per session (the host is built once and parked).
local auctionCtx

-- A skin switch (NS.Skin.OnLooksChanged): the ticks rebuilt, then the headers and every row slot
-- repainted IN PLACE, on screen or parked on the panel while another tab is up. Only the paint:
-- the partition and the reorder controller belong to refreshAuctionTable, which a parked host
-- must not run (it would hand a hidden host a new controller).
local function repaintAuctionTable()
  rebuildTicks()
  local ctx = auctionCtx
  if not (ctx and ctx._priRows) then return end
  for _, fs in ipairs(ctx._priHeads or {}) do paintText(fs, "text.headingAlt") end
  local capture = NS.db.profile.settings.auction.capture or {}
  for _, r in ipairs(ctx._priRows) do
    if r._tag then paintAuctionRow(r, r._tag, capture) end
    -- The row's AceGUI CheckBox is held for the session and never re-acquired, so the library's
    -- re-render cannot repaint it: PaintAce repaints it in the new skin, or puts it back stock on
    -- Ka0s Default.
    if r.check then NS.SkinPaintAce(r.check) end
  end
end
if NS.Skin then NS.Skin.OnLooksChanged(repaintAuctionTable) end

-- Build the unified AH price table: gold left-aligned column headers and 11 reusable row slots (one
-- per known price source). Slots + their frames are created ONCE here; refreshAuctionTable repaints
-- them in place on every enable-toggle / drag / Defaults, so no frame is ever re-allocated. Native
-- FontStrings carry all text; only the checkbox, the ⓘ and the library's handle are frames.
--
-- THE HOST IS A RAW FRAME THIS ADDON OWNS FOR THE SESSION, not an AceGUI child. That is the whole of
-- how the pooling survives a tab strip: the tab body is re-rendered on every click, and ClearScroll
-- hands every AceGUI child back to the pool — which would orphan eleven slots of raw FontStrings
-- parented to a SimpleGroup and put the ~1.7s freeze back. So the host is created once, parked on
-- the panel while another tab is on screen, and RE-PARENTED to a fresh full-width placeholder each
-- time this tab is drawn. Nothing is ever allocated twice and nothing is ever released.
local function buildAuctionTable(ctx)
  local scroll = O.EnsureScroll(ctx)
  if not scroll then return end

  local descLabel = acquire("Label")
  descLabel:SetFullWidth(true)
  descLabel:SetText("Tick a source to collect its price at loot time; ticked sources are ranked "
    .. "top-to-bottom (drag by the handle) and the highest-ranked one you have a price for is the "
    .. "value shown. Sources you don't collect, or whose addon isn't installed, drop to the bottom.")
  scroll:AddChild(descLabel)
  O.AddSpacer(scroll, 8)

  local N = #NS.Constants.AUCTION_KEYS
  local placeholder = acquire("SimpleGroup")
  placeholder:SetLayout(nil); placeholder:SetFullWidth(true)
  placeholder:SetHeight(AHEAD_H + AROW_H * N + 8)
  scroll:AddChild(placeholder)

  local hf = ctx._priHost
  if not hf then
    hf = CreateFrame("Frame", nil, ctx.panel)
    ctx._priHost = hf
  end
  auctionCtx = ctx
  hf:SetParent(placeholder.frame)
  hf:ClearAllPoints()
  hf:SetAllPoints(placeholder.frame)
  hf:Show()
  -- The undo of the reparent above, on the placeholder's own release (options-ui-§19). Guarded on
  -- the host still sitting on THIS placeholder: every render creates a fresh one, so an old one
  -- released late must never pull the host off the new one. CHAINED onto the widget's OnRelease
  -- (NS.SkinOnRelease, the library's Skin:OnRelease) rather than taking AceGUI's one OnRelease
  -- callback, so this cleanup and the skin's restore both run whichever is installed first.
  NS.SkinOnRelease(placeholder, function(w)
    if hf:GetParent() == w.frame then
      hf:Hide(); hf:SetParent(ctx.panel); hf:ClearAllPoints()
    end
  end)

  if not ctx._priRows then
    local gutter = handleGutter()

    -- Gold, left-aligned column headers at the shared offsets (a roomy band above the first row),
    -- kept on the context for repaintAuctionTable.
    ctx._priHeads = {}
    local function header(x, text)
      local fs = hf:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
      fs:SetPoint("TOPLEFT", hf, "TOPLEFT", gutter + x, HEAD_Y); fs:SetJustifyH("LEFT")
      fs:SetText(text); paintText(fs, "text.headingAlt")
      ctx._priHeads[#ctx._priHeads + 1] = fs
    end
    header(ACOL.addon, "Addon"); header(ACOL.module, "Price module")
    header(ACOL.enabled, "On"); header(ACOL.status, "Status")

    -- Reusable row slots (created once). Each is a real Frame, because that is what ReorderList
    -- anchors its handle and its bounded box to and what it fades while the row is carried; the
    -- cells inside it are FontStrings plus the ⓘ and an AceGUI checkbox.
    local rows = {}
    for i = 1, N do
      local rf = CreateFrame("Frame", nil, hf)
      rf:SetPoint("TOPLEFT",  hf, "TOPLEFT",  0, -(AHEAD_H + (i - 1) * AROW_H))
      rf:SetPoint("TOPRIGHT", hf, "TOPRIGHT", 0, -(AHEAD_H + (i - 1) * AROW_H))
      rf:SetHeight(AROW_H)
      local r = { frame = rf, _gutter = gutter }

      -- The text cells take their face and color from paintAuctionRow (paintText); the tick column
      -- holds only an inline texture, so its face sets nothing a player sees.
      local function fs(x)
        local f = rf:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        f:SetPoint("LEFT", rf, "LEFT", gutter + x, 0); f:SetJustifyH("LEFT"); return f
      end
      r.tick = fs(ACOL.tick); r.addon = fs(ACOL.addon)
      r.module = fs(ACOL.module); r.status = fs(ACOL.status)

      local info = CreateFrame("Button", nil, rf)
      info:SetSize(16, 16)
      info:SetPoint("LEFT", rf, "LEFT", gutter + ACOL.module, 0)   -- repositioned per row
      local itex = info:CreateTexture(nil, "ARTWORK"); itex:SetAllPoints()
      -- White catalog art is what the per-row SetVertexColor below wants: it dims the mark to 0.55
      -- for an inactive row, and a multiply only reads as "dimmed" against white.
      itex:SetTexture((NS.Icon and NS.Icon("info")) or INFO_ICON)
      info.tex = itex; r.info = info
      tipScripts(info, function() return (keyMetaOf(r._tag or "")) end,
                       function() return (select(2, keyMetaOf(r._tag or ""))) end)

      -- AceGUI CheckBox (the standard gold-tick control used across the panel) rather than a raw
      -- UICheckButtonTemplate — the template left a scaling artifact at this size. Parented to the
      -- ROW, never added as a scroll child, so ClearScroll cannot reclaim it either.
      local cb = acquire("CheckBox")
      cb:SetLabel("")
      cb.frame:SetParent(rf); cb.frame:ClearAllPoints()
      cb.frame:SetPoint("LEFT", rf, "LEFT", gutter + ACOL.enabled, 0); cb.frame:SetWidth(26)
      cb.frame:Show()
      cb:SetCallback("OnValueChanged", function(_, _, val)
        local tag = r._tag
        if not tag then return end
        local src = NS.Schema:Get("settings.auction.capture") or {}
        local c = {}
        for k, v in pairs(src) do c[k] = v end
        c[tag] = val or nil
        NS.Schema:Set("settings.auction.capture", c)
        runRebuilders(ctx)
      end)
      r.check = cb

      rows[i] = r
    end
    ctx._priRows = rows
  end

  -- REGISTERED ON EVERY RENDER, not only on the pass that built the slots. renderGeneral reassigns
  -- ctx.rebuilders each time (ClearScroll reassigns the library's refreshers beside it), so a
  -- rebuilder added once inside the build branch above would be dropped the first time the reader
  -- left this tab and came back — and with it the repaint every enable-toggle and every drag needs.
  ctx.rebuilders[#ctx.rebuilders + 1] = function() refreshAuctionTable(ctx) end

  refreshAuctionTable(ctx)   -- first paint, and every later paint of this tab
end

P._buildAuctionTable = buildAuctionTable
P._cancelReorder = cancelReorder
