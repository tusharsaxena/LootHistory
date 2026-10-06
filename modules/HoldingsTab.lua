local _, NS = ...
NS.HoldingsTab = NS.HoldingsTab or {}
local HT = NS.HoldingsTab

-- The Holdings tab (timeline-ledger spec §8.2): one line per thing with its total; expanding a thing
-- shows each holder with the container split and how stale the oldest contributing scan is.
-- BuildModel is pure and carries all the logic; the view is a pooled list of fixed-height rows.
--
-- It reads the browser's shared filter like the other tabs, but only the fields NS.Holdings:Search
-- understands (text, quality, itemType, itemSubType, char). Date / Source / Bound / Zone describe a
-- loot EVENT, not something held, so they are ignored here; graying them per tab is spec §8.0 and
-- lands with the Timeline tab (docs/browser.md).

local ORDER = { "bags", "equipped", "bank", "mail", "auctions", "tabs" }
local LABEL = { bags = "Bags", equipped = "Equipped", bank = "Bank", mail = "Mail", auctions = "AH", tabs = "Warband" }
local ROW_H, INDENT, HEADER_H = 18, 16, 20
local TOTAL_W, VALUE_W = 110, 130
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0
local DAY = 86400

-- ── pure ──────────────────────────────────────────────────────────────────────────────────────

function HT.FormatContainers(containers)
  local parts = {}
  for _, c in ipairs(ORDER) do
    if containers and containers[c] then parts[#parts + 1] = LABEL[c] .. " " .. containers[c] end
  end
  return table.concat(parts, " · ")
end

function HT.FormatAge(scannedAt, now)
  if not scannedAt then return "never" end
  local s = (now or time()) - scannedAt
  if s < 60 then return "now" end
  if s < 3600 then return math.floor(s / 60) .. " m" end
  if s < DAY then return math.floor(s / 3600) .. " h" end
  return math.floor(s / DAY) .. " d"
end

-- What a whole stack is worth, in copper. Gold is its own value; a currency has none. An item is
-- priced the way a loot record is (NS.Util.RecordValue: the higher of the picked auction price and
-- the vendor price), from a record-shaped table built off the live price sources, since a held
-- stack has no stored capture to read a snapshot from.
local function valueOf(t)
  if t.kind == "GOLD" then return t.total end
  if t.kind ~= "ITEM" then return 0 end
  local ref = t.link or ("item:" .. t.id)
  local unit = NS.Util.RecordValue({
    auctionPrice = NS.AuctionPrice and NS.AuctionPrice:GatherAll(ref, t.id) or nil,
    vendorPrice  = NS.Compat.GetItemSellPrice(ref),
  })
  return (unit or 0) * t.total
end

local SORTS = {
  name  = function(a, b) return a.name:lower() < b.name:lower() end,
  total = function(a, b) if a.total ~= b.total then return a.total > b.total end return a.name < b.name end,
  value = function(a, b) if a.value ~= b.value then return a.value > b.value end return a.name < b.name end,
}

function HT.BuildModel(filter, expanded, sortKey)
  local things = NS.Holdings:Search(filter or {})
  for _, t in ipairs(things) do t.value = valueOf(t) end
  table.sort(things, SORTS[sortKey or "name"] or SORTS.name)
  local lines = {}
  for _, t in ipairs(things) do
    local open = expanded and expanded[t.key] or false
    lines[#lines + 1] = { kind = "thing", key = t.key, name = t.name, quality = t.quality,
      total = t.total, value = t.value, expanded = open, thingKind = t.kind }
    if open then
      for _, h in ipairs(t.holders) do
        lines[#lines + 1] = { kind = "holder", key = t.key, holder = h.holder, count = h.count,
          containers = h.containers, scannedAt = h.scannedAt }
      end
    end
  end
  return lines
end

-- ── view ──────────────────────────────────────────────────────────────────────────────────────

HT.expanded, HT.sortKey = {}, "name"

-- The two color helpers Insights already publishes from modules/AnalyticsFormat.lua (loaded first):
-- one answer for "what color is this quality / class" across both tabs.
local function rgb(c) return c[1], c[2], c[3] end

local function holderLabel(holder)
  if holder == NS.Constants.WARBAND_HOLDER then return "Warband", { 0.4, 0.78, 1 } end
  local e = NS.Holdings:Get(holder)
  return holder, NS.Analytics._classColor(e and e.meta and e.meta.classFile)
end

-- Gold counts are copper and read as coins; everything else is a plain count.
local function countText(key, n) if key == "g" then return NS.Util.FormatMoney(n) end return tostring(n) end

local function makeRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW_H)
  row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.value:SetPoint("RIGHT", row, "RIGHT", -4, 0); row.value:SetWidth(VALUE_W); row.value:SetJustifyH("RIGHT")
  row.total = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.total:SetPoint("RIGHT", row.value, "LEFT", -8, 0); row.total:SetWidth(TOTAL_W); row.total:SetJustifyH("RIGHT")
  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
  row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.detail:SetPoint("RIGHT", row.total, "LEFT", -8, 0); row.detail:SetJustifyH("RIGHT")
  row:SetScript("OnClick", function(self) if self.thingKey then HT:Toggle(self.thingKey) end end)
  return row
end

local function bindThing(row, l)
  row.thingKey = l.key
  row.name:SetPoint("LEFT", row, "LEFT", 4, 0); row.name:SetPoint("RIGHT", row.total, "LEFT", -8, 0)
  row.name:SetText((l.expanded and "- " or "+ ") .. l.name)
  row.name:SetTextColor(rgb(NS.Analytics._qualityColor(l.quality or 1)))
  row.detail:SetText("")
  row.total:SetText(countText(l.key, l.total)); row.total:SetTextColor(1, 1, 1)
  row.value:SetText(NS.Util.FormatMoney(l.value)); row.value:SetTextColor(1, 1, 1)
end

-- Indented under its thing; the age goes gray once the oldest scan feeding it is a day old, the
-- point past which the count is a memory of the container rather than a reading of it.
local function bindHolder(row, l, now)
  row.thingKey = nil
  local label, color = holderLabel(l.holder)
  row.name:SetPoint("LEFT", row, "LEFT", 4 + INDENT, 0)
  row.name:SetText(label); row.name:SetTextColor(rgb(color))
  row.detail:SetText(HT.FormatContainers(l.containers))
  row.total:SetText(countText(l.key, l.count)); row.total:SetTextColor(0.85, 0.85, 0.85)
  local stale = l.scannedAt and (now - l.scannedAt) >= DAY
  row.value:SetText(HT.FormatAge(l.scannedAt, now))
  if stale then row.value:SetTextColor(0.5, 0.5, 0.5) else row.value:SetTextColor(0.85, 0.85, 0.85) end
end

local function makeHeader(pane, label, key, anchor)
  local b = CreateFrame("Button", nil, pane)
  b:SetHeight(HEADER_H)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.text:SetAllPoints(); b.text:SetText(label); b.text:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
  b.text:SetJustifyH(anchor)
  b:SetScript("OnClick", function() HT.sortKey = key; HT:Refresh() end)
  return b
end

function HT:Attach(pane)
  if self.pane then return end
  self.pane = pane
  -- Column header: Name · Total · Value, each a sort button, aligned over the row columns (the
  -- scroll frame's 26 px scrollbar gutter is mirrored so the right edges line up).
  local hName = makeHeader(pane, "Name", "name", "LEFT")
  hName:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, 0); hName:SetWidth(200)
  local hValue = makeHeader(pane, "Value", "value", "RIGHT")
  hValue:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -30, 0); hValue:SetWidth(VALUE_W)
  local hTotal = makeHeader(pane, "Total", "total", "RIGHT")
  hTotal:SetPoint("RIGHT", hValue, "LEFT", -8, 0); hTotal:SetWidth(TOTAL_W)

  -- Same scroll skin and anchors as the Insights pane (modules/Analytics.lua), below the header.
  local scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -HEADER_H)
  scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -26, 4)
  self.scroll = scroll
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  self.content = content
  scroll:SetScript("OnSizeChanged", function() HT:Refresh() end)
  self.rows = NS.Pool.New()
  self:Refresh()
end

-- Rebuild the visible list off the shared filter. Every row goes back to the pool first and comes
-- out again per line, so a refresh reuses the frames the last one made instead of adding to them.
function HT:Refresh()
  if not self.pane then return end
  local filter = NS.Browser and NS.Browser.CurrentFilter and NS.Browser:CurrentFilter() or {}
  local lines = HT.BuildModel(filter, self.expanded, self.sortKey)
  NS.Pool.ReleaseAll(self.rows)
  local w = math.max(1, (self.scroll.GetWidth and self.scroll:GetWidth()) or 1)
  local now = time()
  for i, l in ipairs(lines) do
    local row = NS.Pool.Acquire(self.rows, function() return makeRow(self.content) end)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetWidth(w)
    row.name:ClearAllPoints()
    if l.kind == "thing" then bindThing(row, l) else bindHolder(row, l, now) end
  end
  self.content:SetSize(w, math.max(1, #lines * ROW_H))
  self._visible = #lines
  if NS.State.debug and NS.Debug then NS.Debug("UI", "holdings: %d line(s), sort=%s", #lines, self.sortKey) end
end

function HT:Toggle(key)
  self.expanded[key] = (not self.expanded[key]) or nil
  self:Refresh()
end

--- Test seam: how many rows the last Refresh acquired.
function HT:VisibleRowCount() return self._visible or 0 end

--- HOLDINGS_CHANGED repaints the pane while it is on screen. The Reconciler sends it from Flush,
--- which never runs in combat (spec §5.2), so this handler never lands mid-pull.
function HT:Enable()
  if not NS.bus or self.__ev then return end
  self.__ev = NS.NewBusTarget()
  self.__ev:RegisterMessage(NS.MSG.HOLDINGS_CHANGED, function()
    if self.pane and self.pane:IsShown() then self:Refresh() end
  end)
end

--- The stand-down half (slash-commands-§7): the private bus target goes wholesale.
function HT:Disable()
  if not self.__ev then return end
  self.__ev:UnregisterAllMessages()
  self.__ev:UnregisterAllEvents()
  self.__ev = nil
end

NS.Browser:RegisterTab{ name = "Holdings", order = 40,
  build = function(pane) HT:Attach(pane) end,
  refresh = function() HT:Refresh() end }
