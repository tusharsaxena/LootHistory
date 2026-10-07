local _, NS = ...
NS.Analytics = NS.Analytics or {}
local Analytics = NS.Analytics

-- The Insights tab's ledger half (timeline-ledger spec §6): a GAINS & LOSSES divider, the
-- pre-ledger caveat, and three back-to-back charts (by reason, by character, by kind) — losses grow
-- left of a fixed center axis in red, gains right in green, one shared scale per chart (BankLedger
-- InsightsWidgets BuildBackToBackRows / PeakShares). Drawn only when the range holds a loss or a
-- transfer, so a gains-only range (every legacy history) renders exactly as before.
--
-- Its chrome lives in inst.ledgerUI, NOT in inst.headers / inst.pool: the golden snapshot in
-- tests/test_analytics_layout.lua walks those two tables, and this section is pinned by its own cases.

local AL = {}
Analytics._ledger = AL

local C = NS.Constants
local BAR_H, BAR_GAP, LABEL_W, VALUE_W, SECTION_GAP = 16, 4, 130, 110, 14

-- ── Pure ────────────────────────────────────────────────────────────────────────────────────

function AL.HasLedger(stats)
  local L = stats and stats.ledger
  return L ~= nil and ((L.lostCount or 0) > 0 or (L.movedCount or 0) > 0)
end

function AL.Caveat(resetPrompt, ledgerSince, preLedgerRows)
  if resetPrompt ~= "kept" or not ledgerSince or (preLedgerRows or 0) == 0 then return nil end
  return ("Before %s only gains were recorded \226\128\148 totals for that period overstate net.")
    :format(NS.Util.FormatDate(ledgerSince))
end

-- The union of both maps' keys, each once.
local function unionKeys(inMap, outMap)
  local keys, seen = {}, {}
  for _, m in ipairs({ inMap, outMap }) do
    for k in pairs(m) do
      if not seen[k] then
        seen[k] = true
        keys[#keys + 1] = k
      end
    end
  end
  return keys
end

local function frac(v, peak)
  if peak > 0 then return v / peak end
  return 0
end

-- Biggest total first; an equal total orders by label.
local function byTotalThenLabel(a, b)
  if a.total ~= b.total then return a.total > b.total end
  return tostring(a.label) < tostring(b.label)
end

function AL.BackToBackRows(inMap, outMap, labelOf, labelColorOf, signedFmt, plainFmt)
  inMap, outMap = inMap or {}, outMap or {}
  local keys = unionKeys(inMap, outMap)
  local peak = 0
  for _, k in ipairs(keys) do peak = math.max(peak, inMap[k] or 0, outMap[k] or 0) end
  local rows = {}
  for _, k in ipairs(keys) do
    local i, o = inMap[k] or 0, outMap[k] or 0
    rows[#rows + 1] = {
      key = k, label = labelOf(k), labelColor = labelColorOf and labelColorOf(k) or nil,
      rightFrac = frac(i, peak), leftFrac = frac(o, peak),
      total = i + o, value = signedFmt(i - o),
      rightTip = "Gained: " .. plainFmt(i), leftTip = "Lost: " .. plainFmt(o),
    }
  end
  table.sort(rows, byTotalThenLabel)
  return rows
end

-- The by-character chart's label for a holder key (the stats key it by holder, as History's
-- Character column does): the Warband as "Warband", a character by its name without the realm.
function AL.HolderShort(k)
  local s = NS.LedgerFormat.HolderLabel(k)
  return s:match("^[^-]+") or s
end

-- ── Widgets ─────────────────────────────────────────────────────────────────────────────────

local function makeBar(parent)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(BAR_H)
  bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.label:SetJustifyH("LEFT")
  bar.label:SetWordWrap(false)
  bar.value = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.value:SetJustifyH("RIGHT")
  bar.track = bar:CreateTexture(nil, "BACKGROUND")
  bar.track:SetColorTexture(1, 1, 1, 0.06)
  bar.axis = bar:CreateTexture(nil, "OVERLAY")
  bar.axis:SetColorTexture(0.55, 0.55, 0.60, 0.9)
  bar.left = bar:CreateTexture(nil, "ARTWORK")
  bar.right = bar:CreateTexture(nil, "ARTWORK")
  bar:EnableMouse(true)
  bar:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:AddLine(self._fullLabel or "", 1, 0.82, 0)
    GameTooltip:AddLine(self._info or "", 0.9, 0.9, 0.9)
    GameTooltip:Show()
  end)
  bar:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return bar
end

-- Anchored to the track's CENTER, not its edges: the split sits on one vertical line in every row.
local function placeBar(bar, content, pad, y, w, row)
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", content, "TOPLEFT", pad, y)
  bar:SetWidth(w)
  bar.label:ClearAllPoints(); bar.label:SetPoint("LEFT", bar, "LEFT", 0, 0); bar.label:SetWidth(LABEL_W)
  bar.value:ClearAllPoints(); bar.value:SetPoint("RIGHT", bar, "RIGHT", 0, 0); bar.value:SetWidth(VALUE_W)
  local trackW = math.max(2, w - LABEL_W - VALUE_W - 12)
  local half = trackW / 2
  bar.track:ClearAllPoints(); bar.track:SetPoint("LEFT", bar, "LEFT", LABEL_W + 6, 0)
  bar.track:SetSize(trackW, BAR_H - 4)
  bar.axis:ClearAllPoints(); bar.axis:SetPoint("CENTER", bar.track, "CENTER", 0, 0)
  bar.axis:SetSize(1, BAR_H - 2)
  local out, gain = C.DirRGB.OUT, C.DirRGB.IN
  local lw, rw = half * row.leftFrac, half * row.rightFrac
  bar.left:ClearAllPoints(); bar.left:SetPoint("RIGHT", bar.track, "CENTER", 0, 0)
  bar.left:SetSize(math.max(1, lw), BAR_H - 4); bar.left:SetColorTexture(out[1], out[2], out[3], 0.95)
  bar.left:SetShown(lw > 0)
  bar.right:ClearAllPoints(); bar.right:SetPoint("LEFT", bar.track, "CENTER", 0, 0)
  bar.right:SetSize(math.max(1, rw), BAR_H - 4); bar.right:SetColorTexture(gain[1], gain[2], gain[3], 0.95)
  bar.right:SetShown(rw > 0)
end

-- Build the ledger chrome once, from Analytics:BuildCharts (modules/AnalyticsCharts.lua, which
-- publishes the section factories, loads before this file).
function AL.Build(inst, content)
  local charts = Analytics._charts
  inst.ledgerUI = {
    divider = charts.sectionDivider(content, "GAINS & LOSSES"),
    caveat = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"),
    headers = {
      reason = charts.sectionHeader(content, "Gains Vs Losses By Reason"),
      char   = charts.sectionHeader(content, "Gains Vs Losses By Character"),
      kind   = charts.sectionHeader(content, "Gains Vs Losses By Kind"),
    },
    pools = { reason = NS.Pool.New(), char = NS.Pool.New(), kind = NS.Pool.New() },
  }
  inst.ledgerUI.caveat:SetJustifyH("LEFT")
  inst.ledgerUI.caveat:SetTextColor(1, 0.82, 0)
  AL.Hide(inst)
end

function AL.Hide(inst)
  local ui = inst.ledgerUI
  if not ui then return end
  ui.divider:Hide(); ui.caveat:Hide()
  for _, h in pairs(ui.headers) do h:Hide() end
  for _, p in pairs(ui.pools) do NS.Pool.ReleaseAll(p) end
end

local function section(inst, key, rows, y, w, pad)
  local ui = inst.ledgerUI
  local header = ui.headers[key]
  if #rows == 0 then header:Hide(); return y end
  header:ClearAllPoints(); header:SetPoint("TOPLEFT", inst.content, "TOPLEFT", pad, y); header:Show()
  y = y - 18
  for _, row in ipairs(rows) do
    local bar = NS.Pool.Acquire(ui.pools[key], function() return makeBar(inst.content) end)
    bar._fullLabel = tostring(row.label)
    bar._info = row.rightTip .. "   " .. row.leftTip
    bar.label:SetText(row.label)
    local lc = row.labelColor
    bar.label:SetTextColor(lc and lc[1] or 0.9, lc and lc[2] or 0.9, lc and lc[3] or 0.9)
    bar.value:SetText(row.value)
    placeBar(bar, inst.content, pad, y, w - pad * 2, row)
    bar:Show()
    y = y - (BAR_H + BAR_GAP)
  end
  return y - SECTION_GAP
end

local KIND_LABEL = { ITEM = "Items", CURRENCY = "Currency", GOLD = "Gold" }

-- Draw the caveat (when due) and, for a range with a loss or transfer, the three back-to-back
-- charts, top-down from y; returns the new y. Called first by Analytics:LayoutCharts.
function AL.Layout(inst, stats, y, w, pad)
  local ui = inst.ledgerUI
  for _, p in pairs(ui.pools) do NS.Pool.ReleaseAll(p) end
  local g = NS.db and NS.db.global or {}
  local note = AL.Caveat(g.resetPrompt, g.ledgerSince, stats.ledger and stats.ledger.preLedgerRows)
  if note then
    ui.caveat:ClearAllPoints(); ui.caveat:SetPoint("TOPLEFT", inst.content, "TOPLEFT", pad, y)
    ui.caveat:SetText(note); ui.caveat:Show()
    y = y - 18
  else
    ui.caveat:Hide()
  end
  if not AL.HasLedger(stats) then AL.Hide(inst); if note then ui.caveat:Show() end; return y end
  ui.divider:ClearAllPoints()
  ui.divider:SetPoint("TOPLEFT", inst.content, "TOPLEFT", pad, y)
  ui.divider:SetPoint("TOPRIGHT", inst.content, "TOPRIGHT", -pad, y)
  ui.divider:Show()
  y = y - 30
  local L, LF = stats.ledger, NS.LedgerFormat
  local function srcLabel(k) return C.SourceLabel[k] or k end
  local function classOf(ch) local ce = stats.byChar and stats.byChar[ch]; return ce and ce.classFile end
  local function charColor(ch)
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classOf(ch) or ""]
    return cc and { cc.r, cc.g, cc.b } or nil
  end
  y = section(inst, "reason", AL.BackToBackRows(L.reasonIn, L.reasonOut, srcLabel, nil, LF.SignedCount, tostring),
    y, w, pad)
  y = section(inst, "char", AL.BackToBackRows(L.charIn, L.charOut, AL.HolderShort,
    charColor, LF.SignedMoney, function(v) return NS.Util.FormatMoney(v) end), y, w, pad)
  y = section(inst, "kind", AL.BackToBackRows(L.kindIn, L.kindOut, function(k) return KIND_LABEL[k] or k end,
    nil, LF.SignedCount, tostring), y, w, pad)
  return y
end
