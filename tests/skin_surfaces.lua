-- tests/skin_surfaces.lua — this addon's painted surfaces, declared for the kit's skin-switch test
-- (tests/_kit/test_skin_switch.lua, kit revision 50, skinning-§1). tests/run.lua sets Kit.skinSwitch
-- from it. Loaded with dofile (it registers no case of its own).
--
-- THE GRAIN IS ONE PAINTED OBJECT. The kit spies on what `build` answers and on all of its regions
-- and children, and a surface passes when anything under it changes. So a whole window would pass on
-- its first recolored child and prove nothing about the rest. Each entry answers the object that
-- draws: a string, a texture, or a small frame such as one flat button.
--
-- THE FIXTURES are the ones tests/test_skin_chrome.lua, test_skin_table.lua and test_skin_insights.lua
-- build a fresh surface under: the kit's paint recorder, the session's windows and module fields
-- swapped out, and everything put back. Here the two halves are split, because `build` has to return
-- with the surface standing: a fixture queues its undo with `later`. One fixture stands for all its
-- surfaces, because a fresh Insights per surface took the run past a gigabyte and every skin switch
-- repaints all that stands. `shared` keeps the last fixture until a surface asks for another, and
-- `close`, which tests/test_skin_surfaces.lua calls after the kit's suite, takes the last one down.
-- The kit's spies come off after every surface, so sharing leaves nothing between two of them.
--
-- Scope: the AH price table lives on the settings panel, so Ignore settings panel keeps it stock
-- and it is `scope = "panel"`. Everything else is a window of this addon and follows either way.
-- This addon has no HUD, so no surface carries a companion (the Options document, Moving to).

return function(NS, mocks)
  local OWNER = "LootHistory"
  local Skin = mocks.LibStub("LibKa0s-Skin-1.0")
  local OptionsLib = mocks.LibStub("LibKa0s-Options-1.0")
  local installPaint = dofile("tests/_kit/mock_paint.lua")
  local SW = dofile("tests/skin_support.lua")

  local baseCreateFrame
  local undo = {}
  local function later(fn) undo[#undo + 1] = fn end

  -- tests/test_skin_chrome.lua's reset: a skin change queues the library's page re-render on the
  -- kit's timers, and away from Ka0s Default the page backdrop texture IS the page in this harness.
  local wasShown
  local function settle()
    NS.WriteSkinChoice("ka0s", "ka0s")
    Skin:SetChoice(OWNER, "ka0s", "ka0s")
    mocks.__fireTimers()
    for ctx in pairs(wasShown or {}) do
      local panel = ctx.panel
      if rawequal(rawget(panel, "__ka0sSkinBg"), panel) then rawset(panel, "__ka0sSkinBg", nil) end
      if not (panel:IsShown() and OptionsLib.__shownPages[ctx]) then
        panel:Show()
        panel:__fire("OnShow")
      end
    end
    mocks.__fireTimers()
  end

  local standing, built

  local function close()
    for i = #undo, 1, -1 do undo[i]() end
    undo, standing, built = {}, nil, nil
    settle()
  end

  --- `fixture`'s answers, built once while it is the one standing.
  local function shared(fixture)
    if standing ~= fixture then
      close()
      standing, built = fixture, { fixture() }
    end
    return unpack(built)
  end

  local function begin()
    if wasShown then return end
    baseCreateFrame = mocks.CreateFrame
    wasShown = {}
    for ctx in pairs(OptionsLib.__shownPages or {}) do
      if ctx.panel and ctx.panel:IsShown() then wasShown[ctx] = true end
    end
  end

  local function recorder() later(installPaint(mocks)) end

  -- ── the History window and the export modal ─────────────────────────────────────────────────

  local B_KEYS = { "_dd", "_search", "_onSearchText", "_autocomplete", "_exportBtn", "_ddWidths", "_bar",
                   "_barCtl", "_barW", "_footer", "_dbFooter", "_minW", "_minH" }

  local function build_windows()
    local B, E = NS.Browser, NS.Export
    begin()
    local saved = {}
    for _, k in ipairs(B_KEYS) do saved[k] = B[k] end
    local filter, special = B.activeFilter, #mocks.UISpecialFrames
    recorder()
    local oldWin, oldExp = B:_SwapWindowForTest(nil), E:_SwapWindowForTest(nil)
    later(function()
      local win, exp = B:GetWindow(), E:Window()
      if win and win ~= oldWin then win:Hide() end
      if exp and exp ~= oldExp then exp:Hide() end
      B:_SwapWindowForTest(oldWin)
      E:_SwapWindowForTest(oldExp)
      for _, k in ipairs(B_KEYS) do B[k] = saved[k] end
      B.activeFilter = filter
      for i = #mocks.UISpecialFrames, special + 1, -1 do table.remove(mocks.UISpecialFrames, i) end
    end)
    B:Show()
    E:Open({ title = "Export History", providers = {} })
    return B:GetWindow(), E:Window()
  end

  local function edgeOf(frame) return Skin.painted[frame].regions.edgeTop end

  local function csvButton(exp)
    for _, child in ipairs({ exp:GetChildren() }) do
      local fs = rawget(child, "text")
      if type(fs) == "table" and rawget(fs, "__text") == "Export to CSV" then return child end
    end
  end

  -- The line the Divider primitive drew on the divider frame's holder.
  local function dividerLine(bar)
    for _, child in ipairs({ bar:GetChildren() }) do
      for _, r in ipairs(rawget(child, "__paintRegions") or {}) do
        if rawget(r, "__color") then return r end
      end
    end
  end

  -- ── the History table ───────────────────────────────────────────────────────────────────────

  local BT_KEYS = { "frame", "pane", "headerFrame", "scroll", "rowHost", "rowPool", "emptyText",
                    "displayList", "matchCount", "sortKey", "sortAsc", "groupBy", "groupAsc" }
  local RECORD = { ts = 1000, itemName = "Sword", quality = 4, bound = "BOP", itemType = "Weapon",
                   quantity = 1, char = "Ka0z-Realm", source = "KILL" }
  local LIST = {
    { kind = "header", key = "Kill", label = "Kill", count = 3, collapsed = false },
    { kind = "row", record = RECORD },
    { kind = "header", key = "Mail", label = "Mail", count = 1, collapsed = true },
  }

  local function build_historyTable()
    local BT = NS.BrowserTable
    begin()
    local saved = {}
    for _, k in ipairs(BT_KEYS) do saved[k] = BT[k] end
    recorder()
    local oldMenu = BT:_SwapMenuForTest(nil)
    later(function()
      -- OnHide is what drops the menu's GLOBAL_MOUSE_DOWN registration; the mock's Hide fires none.
      local menu = BT:MenuFrame()
      if menu then menu:Hide(); menu:__fire("OnHide") end
      BT:_SwapMenuForTest(oldMenu)
      for _, k in ipairs(BT_KEYS) do BT[k] = saved[k] end
    end)
    -- The client's FauxScrollFrameTemplate carries its bar at `ScrollBar`; the mock builds none.
    local createFrame = mocks.CreateFrame
    rawset(mocks, "CreateFrame", function(kind, name, parent, template, ...)
      local f = createFrame(kind, name, parent, template, ...)
      if template == "FauxScrollFrameTemplate" then rawset(f, "ScrollBar", createFrame("Slider", nil, f)) end
      return f
    end)
    later(function() rawset(mocks, "CreateFrame", createFrame) end)
    BT.frame = nil
    BT.sortKey, BT.sortAsc, BT.groupBy = "date", false, "none"
    BT:Attach(mocks.CreateFrame("Frame", nil, mocks.UIParent))
    rawset(mocks, "CreateFrame", createFrame)
    BT.displayList = LIST
    BT:Bind()
    return BT, BT.rowPool.active
  end

  -- ── Insights, the Timeline, Holdings ────────────────────────────────────────────────────────

  -- A module built afresh under the recorder, with templated strings on the client's 12-point face.
  local function fresh(mod, keys)
    begin()
    local saved = {}
    for _, k in ipairs(keys) do saved[k] = mod[k]; mod[k] = nil end
    later(function() for _, k in ipairs(keys) do mod[k] = saved[k] end end)
    recorder()
    local painted = mocks.CreateFrame
    rawset(mocks, "CreateFrame", function(...)
      local f = painted(...)
      if (...) == "CheckButton" then SW.checkButton(f) end
      local createFS = rawget(f, "CreateFontString")
      if createFS then
        rawset(f, "CreateFontString", function(self, name, layer, template)
          local s = createFS(self, name, layer, template)
          if template then s:SetFont("Fonts\\FRIZQT__.TTF", 12, "") end
          return s
        end)
      end
      return f
    end)
    later(function() rawset(mocks, "CreateFrame", painted) end)
    return mocks.CreateFrame("Frame", nil, mocks.UIParent)
  end

  -- The tab's own filter, unfiltered: the shared bar's parked Character scope belongs to other suites.
  local function unfiltered(tab)
    local B, stock = NS.Browser, NS.Browser.CurrentFilter
    B.CurrentFilter = function(self, t) if t == tab then return {} end return stock(self, t) end
    later(function() B.CurrentFilter = stock end)
  end

  local A_KEYS = { "pane", "scroll", "content", "cards", "headers", "lootDivider", "currencyDivider",
                   "dayStrip", "valueStrip", "hourStrip", "zonePanel", "itemPanel", "itemValuePanel",
                   "currencyStrip", "emptyText", "pool", "ledgerUI", "stats", "charts" }

  local function build_insights()
    local A = NS.Analytics
    local FX = dofile("tests/fixture_insights.lua")
    local pane = fresh(A, A_KEYS)
    A:Attach(pane)
    local h = FX.richHistory()
    h[#h + 1] = { ts = 1600000000, char = "Alpha-Realm", classFile = "WARRIOR", kind = "GOLD", itemName = "Gold",
                  source = "REPAIR", dir = "OUT", quantity = 300 }
    A.stats = FX.statsFor(h)
    local stock = rawget(A, "Refresh")
    later(function() A.Refresh = stock end)
    A.Refresh = function(self) self:LayoutCharts(-100, 780, 8) end
    A:Refresh()
    return A
  end

  local TL_KEYS = { "pane", "bar", "title", "hint", "totalOnlyBtn", "chart", "emptyMsg", "missing", "strip",
                    "stripAxis", "stripPool", "legend", "legendPool", "legendH", "legendButtons", "model",
                    "chartW", "flowTipOwner", "legendTipOwner", "thing" }

  local function build_timeline()
    local TL, g = NS.Timeline, NS.db.global
    local holdings, daily = g.holdings, g.daily
    later(function() g.holdings, g.daily = holdings, daily end)
    g.holdings, g.daily = {}, {}
    local now = os.time()
    NS.Holdings:ApplyMoney("Mock-Realm", 50000, now - 86400)
    NS.Holdings:ApplyMoney("Mock-Realm", 70000, now)
    NS.Holdings:ApplyMoney(NS.Constants.WARBAND_HOLDER, 10000, now)
    local hook = mocks.hooksecurefunc
    rawset(mocks, "hooksecurefunc", SW.hooksecurefunc)
    later(function() rawset(mocks, "hooksecurefunc", hook) end)
    unfiltered("Timeline")
    local pane = fresh(TL, TL_KEYS)
    TL.thing = "g"
    TL:Attach(pane)
    TL:Layout(640, 320)
    return TL
  end

  local HT_KEYS = { "pane", "header", "scroll", "content", "rows", "_rowList", "_visible", "_headerText" }

  local function build_holdingsTab()
    local HT, g = NS.HoldingsTab, NS.db.global
    local holdings, expanded = g.holdings, HT.expanded
    later(function() g.holdings, HT.expanded = holdings, expanded end)
    g.holdings = {}
    local now = os.time()
    NS.Holdings:ApplyMoney("Mock-Realm", 70000, now)
    NS.Holdings:ApplyMoney(NS.Constants.WARBAND_HOLDER, 10000, now - 3 * 86400)
    HT.expanded = { g = true }
    unfiltered("Holdings")
    HT:Attach(fresh(HT, HT_KEYS))
    return HT
  end

  -- ── the AH price table, on the settings panel ───────────────────────────────────────────────

  local function build_auction()
    local PS = dofile("tests/panel_support.lua")
    begin()
    local ctx = NS.Panel.general
    local AP = NS.AuctionPrice
    local avail, capture = AP.IsProviderAvailable, NS.Schema:Get("settings.auction.capture")
    later(function()
      AP.IsProviderAvailable = avail
      NS.Schema:Set("settings.auction.capture", capture)
      PS.homeTab(ctx)
    end)
    AP.IsProviderAvailable = function(_, prov) return prov == "tsm" end
    NS.Schema:Set("settings.auction.capture", { ["tsm:dbmarket"] = true })
    PS.clickTab(mocks.__subcategories["General"], ctx, PS.tabAt("AH price"))
    -- Parked: another tab is on screen when the skin moves (the host is repainted all the same).
    PS.homeTab(ctx)
    return ctx
  end

  local function auctionRow(ctx, tag)
    for _, r in ipairs(ctx._priRows) do if r._tag == tag then return r end end
  end

  -- ── the tools ───────────────────────────────────────────────────────────────────────────────

  local function build_console()
    begin()
    NS.DebugLog:Show()
    later(function() NS.DebugLog:Hide() end)
    return NS.DebugLog._frameForTest
  end

  local function build_exportCopy()
    begin()
    NS.Export.__showCopy("a,b\n1,2")
    local f = NS.Export.__copyWindow:GetFrame()
    later(function() f:Hide() end)
    return f
  end

  local function windows() return shared(build_windows) end
  local function historyTable() return shared(build_historyTable) end
  local function insights() return shared(build_insights) end
  local function timeline() return shared(build_timeline) end
  local function holdingsTab() return shared(build_holdingsTab) end
  local function auction() return shared(build_auction) end
  local function console() return shared(build_console) end
  local function exportCopy() return shared(build_exportCopy) end

  -- ── the declaration ─────────────────────────────────────────────────────────────────────────

  local function hdr(BT) return BT.headerFrame.buttons end

  local surfaces = {
    { name = "the window's edge", build = function() return edgeOf((windows())) end },
    { name = "the window's title", build = function() return (windows()).title end },
    { name = "the window's divider", build = function() return dividerLine((windows()).dividerBar) end },
    { name = "the close control", build = function() return (windows()).closeButton end },
    { name = "the selected tab's label", build = function() return (windows()).tabs.History.label end },
    { name = "an unselected tab's label", build = function() return (windows()).tabs.Insights.label end },
    { name = "the record footer", build = function() windows(); return NS.Browser._footer end },
    { name = "the DB-size footer", build = function() windows(); return NS.Browser._dbFooter end },
    { name = "the filter bar's Export button", build = function() windows(); return NS.Browser._barCtl.export end },
    { name = "the filter bar's Save button", build = function() windows(); return NS.Browser._barCtl.save end },
    { name = "the filter bar's Reset button", build = function() windows(); return NS.Browser._barCtl.reset end },
    { name = "the filter bar's Clear button", build = function() windows(); return NS.Browser._barCtl.clear end },
    { name = "the export modal's edge", build = function()
      local _, exp = windows(); return edgeOf(exp)
    end },
    { name = "the export modal's title", build = function()
      local _, exp = windows(); return exp.titleFS
    end },
    { name = "the export modal's CSV button", build = function()
      local _, exp = windows(); return csvButton(exp)
    end },
    { name = "the test strip", build = function()
      local win = windows(); return NS.MakeTestStrip(win, "strip")
    end },

    { name = "a table header label", build = function() return hdr(historyTable()).item.fs end },
    { name = "the sorted header's arrow", build = function() return hdr(historyTable()).date.fs end },
    { name = "the Bound header's lock", build = function()
      local b = hdr(historyTable()); return b.bound and b.bound.tex
    end },
    { name = "a row's stripe", build = function()
      local _, rows = historyTable(); return rows[1].stripe
    end },
    { name = "a row's hover", build = function()
      local _, rows = historyTable(); return rows[1].hl
    end },
    { name = "a group header row", build = function()
      local _, rows = historyTable(); return rows[1].header
    end },
    { name = "a default cell", build = function()
      local _, rows = historyTable(); return rows[2].cells.type
    end },
    { name = "the padlock", build = function()
      local _, rows = historyTable(); return rows[2].boundIcon
    end },
    { name = "an item's quality text", build = function()
      local _, rows = historyTable(); return rows[2].cells.item
    end },
    { name = "the row menu", build = function()
      local BT, rows = historyTable()
      BT:ShowRowMenu(rows[2], RECORD)
      return BT:MenuFrame()
    end },

    { name = "a KPI card", build = function() return insights().cards.items.frame end },
    { name = "a KPI headline", build = function() return insights().cards.items.num end },
    { name = "a KPI caption", build = function() return insights().cards.items.caption end },
    { name = "a section heading", build = function()
      local A = insights(); return select(2, next(A.headers))
    end },
    { name = "a section divider's rule", build = function() return insights().lootDivider.rules[1] end },
    { name = "a section divider's title", build = function() return insights().lootDivider.fs end },
    { name = "a list panel", build = function() return insights().zonePanel end },
    { name = "the ledger's caveat", build = function() return insights().ledgerUI.caveat end },
    { name = "a bar's track", build = function() return insights().pool.bound.active[1].track end },
    { name = "a strip bar's fill", build = function() return insights().pool.day.active[1].fill end },
    { name = "a strip bar's label", build = function() return insights().pool.day.active[1].axis end },
    { name = "a legend chip", build = function() return insights().pool.sourceleg.active[1].fs end },
    { name = "the ledger's center axis", build = function()
      return insights().ledgerUI.pools.reason.active[1].axis
    end },

    { name = "the Timeline's toggle", build = function() return timeline().totalOnlyBtn end },
    { name = "the Timeline's title", build = function() return timeline().title end },
    { name = "the Timeline's hint", build = function() return timeline().hint end },
    { name = "the Timeline's strip axis", build = function() return timeline().stripAxis end },

    { name = "the Holdings header band", build = function() return holdingsTab().header end },
    { name = "a Holdings header label", build = function() return holdingsTab().header.cells.name.fs end },
    { name = "a Holdings row's stripe", build = function() return holdingsTab().rows.active[1].stripe end },
    { name = "a Holdings row's hover", build = function() return holdingsTab().rows.active[1].hl end },
    { name = "a Holdings row's cell", build = function() return holdingsTab().rows.active[1].cells.total end },

    { name = "the AH table's header", scope = "panel", build = function() return auction()._priHeads[1] end },
    { name = "the AH table's addon name", scope = "panel", build = function()
      return auctionRow(auction(), "tsm:dbmarket").addon
    end },
    { name = "the AH table's status", scope = "panel", build = function()
      return auctionRow(auction(), "tsm:dbmarket").status
    end },
    { name = "the AH table's tick", scope = "panel", build = function()
      return auctionRow(auction(), "tsm:dbmarket").tick
    end },

    { name = "the debug console", build = console },
    { name = "the export copy window", build = exportCopy },
  }

  return {
    owner = OWNER,
    skin = function() return Skin end,
    close = close,
    baseCreateFrame = function() return baseCreateFrame end,
    surfaces = surfaces,
  }
end
