local _, NS = ...
-- luacheck: ignore 212/self
NS.FarmPanel = NS.FarmPanel or {}
local FP = NS.FarmPanel
local FarmModel = NS.FarmModel  -- load-time upvalue: modules/FarmModel.lua loads above
local C = NS.Constants
local L = NS.L

-- modules/FarmPanel.lua — the farm session's companion panel, `LootHistoryFarmPanel` (#39, farm spec
-- docs/superpowers/specs/2026-11-27-39-farm-mode-design.md §7.1, mockups #39 "Companion panel").
--
-- A PRIMARY WINDOW (standalone-windows): a key binding, the launcher and the verb open it, and the
-- player keeps it up and moves it under the master lock, so its header is minimize · lock ·
-- settings · close (W.HeaderButtons: the extras, then settings, then close). It is the addon's one
-- PERSISTENT window, on C.LAYERS.STRATA.WINDOW_PERSISTENT (MEDIUM, frame-layering-§1 T4), toplevel
-- and clamped, below every window opened to read.
--
-- Four views, picked per paint from the open session (Farm:Active(), so the simulator's store while
-- one runs) and `settings.farm.panel.minimized`:
--   full       zone + status chip, the headline and its rate, the basis line, the money / vendor /
--              AH / costs grid, the activity lines (§6), the gold-per-hour grid; Pause · Finish ·
--              Details · Sessions
--   paused     zone + chip, the dimmed headline, the paused hint; Resume · Finish
--   min        zone + chip, the headline, "<elapsed> elapsed"; Pause or Resume · Finish
--   none       "No farm session running."; Start · Sessions
-- Details and Sessions are drawn only once their windows exist (modules/FarmDetails.lua, M4.3; the
-- sessions list, M4.4), so no button here is ever dead.
--
-- THE SESSIONS LIST (`LootHistoryFarmSessions`, §7.2) is the panel's COMPANION: only its Sessions
-- button opens it, so its header is close alone (B:MakeTitleMarks' companion form). It is docked to
-- the panel's right edge and moves with it (its title bar drags the panel), closes with it, and sits
-- on C.LAYERS.STRATA.WINDOW (HIGH, the owner's call, §11.3) beside it. The pair is one tooltip group
-- (LibKa0s-Tooltip-1.0 SetGroup), so a row's tooltip opens outside both. It lists this character's
-- saved sessions in Farm:ActiveStore(), newest first, through FarmList, at the headline value, gross;
-- the row half (columns, clicks, the menu and the popups) is modules/FarmTab.lua's, read at call time.
--
-- Refresh: a full paint on FARM_CHANGED and SETTINGS_CHANGED, coalesced (0.25 s) on the panel's own
-- bus target; a 1 Hz OnUpdate repaints the clock and the rates, set on show only while the session
-- runs and cleared on hide. Visibility (F9): General visibility hides the panel at a combat edge or
-- a settings change, and the next allowing edge shows it again. Position and the minimized state are
-- `settings.farm.panel` (named non-setting state, §4.5); this file is their only writer.

local WIDTH, TITLE_H, PAD = 300, 30, 12
local TICK = 1                 -- the OnUpdate's repaint period, seconds
local COALESCE = 0.25          -- FARM_CHANGED / SETTINGS_CHANGED repaint window
local DOUBLE_CLICK = 0.35      -- two title-bar presses this close toggle minimized
local BTN_W, BTN_H, BTN_GAP = 64, 20, 6
local DEFAULT_POINT = { point = "RIGHT", x = -40, y = 80 }

local MEASURE_LABEL = { money = "Money", vendor = "Vendor value", ah = "AH value" }
local GRID_COLS = { "money", "vendor", "ah" }
local GRID_HEAD = { "Money", "Vendor", "AH" }
local KV_LABELS = { "Elapsed", "Money looted", "Items, vendor value", "Items, AH value", "Costs" }
local PAUSE_WORDS = { afk = "AFK", manual = "manual", standDown = "addon disabled" }
local PLAY_FALLBACK = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
local PAUSE_FALLBACK = "Interface\\RaidFrame\\ReadyCheck-Waiting"

local frame
local sessions   -- the docked sessions list, built on its first show

local function debug(fmt, ...)
  if NS.State.debug and NS.Debug then NS.Debug("UI", fmt, ...) end
end

local function settings() return (NS.db and NS.db.profile and NS.db.profile.settings) or {} end
local function farmSettings() return settings().farm or {} end

-- The panel's named non-setting state (§4.5): { point, x, y, minimized }.
local function panelState()
  local s = settings()
  s.farm = s.farm or {}
  s.farm.panel = s.farm.panel or {}
  return s.farm.panel
end

local function tint(fs, token)
  local r, g, b = NS.SkinColor(token)
  if r then fs:SetTextColor(r, g, b) end
end

local function simulating() return NS.Sim ~= nil and NS.Sim:IsActive() end

-- Costs need ledger capture (§5.6): OUT gold rows exist only with both switches on.
local function costsTracked()
  local s = settings()
  return s.trackLedger ~= false and s.recordGold ~= false
end

-- ── the view ─────────────────────────────────────────────────────────────────────────────────

--- Which view the panel draws for session `s` ("full"|"paused"|"min"|"none").
function FP.ViewFor(s, minimized)
  if not s then return "none" end
  if minimized then return "min" end
  if not s.runningSince then return "paused" end
  return "full"
end

local function pauseWords(s)
  if s.pauseReason == "idle" then
    return ("idle %d min"):format(farmSettings().idleMinutes or 0)
  end
  return PAUSE_WORDS[s.pauseReason] or tostring(s.pauseReason or "manual")
end

--- The status chip's text and color token for session `s`.
function FP.ChipFor(s)
  if s.runningSince then
    local r, g, b = NS.SkinColor("sem.good")
    return NS.IconMarkup("media-play", PLAY_FALLBACK, 0, r, g, b) .. " " .. L["Running"], "sem.good"
  end
  local r, g, b = NS.SkinColor("text.disabled")
  return NS.IconMarkup("media-pause", PAUSE_FALLBACK, 0, r, g, b) .. " " .. L["Paused"] .. ": "
    .. pauseWords(s), "text.disabled"
end

--- The headline's numbers for session `s` at `now`: { elapsed, totals, measure, basis, value, rate,
--- other, otherValue, otherRate }; `other` is the basis the headline does not show.
function FP.Numbers(s, now)
  local fs = farmSettings()
  local measure, basis = fs.headlineValue or "ah", fs.headlineBasis or "gross"
  local t = NS.Farm:Totals(s)
  local elapsed = FarmModel.Elapsed(s, now)
  local other = basis == "net" and "gross" or "net"
  local value, otherValue = FarmModel.Value(t, measure, basis), FarmModel.Value(t, measure, other)
  return { elapsed = elapsed, totals = t, measure = measure, basis = basis, value = value,
    rate = FarmModel.PerHour(value, elapsed), other = other, otherValue = otherValue,
    otherRate = FarmModel.PerHour(otherValue, elapsed) }
end

--- The basis line under the headline: "Gross, AH value · net 749g 25s · 1,063g/h".
function FP.SubLine(n)
  local basis = n.basis == "net" and "Net" or "Gross"
  return ("%s, %s \194\183 %s %s \194\183 %s/h"):format(basis, MEASURE_LABEL[n.measure] or n.measure,
    n.other, FarmModel.CopperText(n.otherValue), FarmModel.RateText(n.otherRate))
end

--- The paused view's hint: an idle or AFK pause resumes on the next gain (F2), a manual one does not.
function FP.PausedHint(s)
  if s.pauseReason == "idle" or s.pauseReason == "afk" then
    return L["The clock is stopped. Your next gain or Resume starts it again."]
  end
  return L["The clock is stopped. Resume starts it again."]
end

-- ── the frame ────────────────────────────────────────────────────────────────────────────────

local function makeText(parent, template, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  NS.Skin.Font(fs)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  fs:Hide()
  return fs
end

local function minimizeFace()
  if panelState().minimized then return "add", "+", L["Expand the panel"] end
  return "minimise", "-", L["Minimize the panel"]
end

local function minimizeExtra()
  local icon, glyph, tip = minimizeFace()
  return { key = "minimize", icon = icon, glyph = glyph, tip = tip,
    onClick = function() FP:ToggleMinimized() end }
end

local function savePosition()
  local point, _, _, x, y = frame:GetPoint(1)
  local p = panelState()
  p.point, p.x, p.y = point, x, y
end

local function restorePosition()
  local p = panelState()
  local at = p.point and p or DEFAULT_POINT
  frame:ClearAllPoints()
  frame:SetPoint(at.point, UIParent, at.point, at.x or 0, at.y or 0)
end

local function titleBar(f)
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", -1, -1)
  bar:SetHeight(TITLE_H)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  -- Lock frame (options-ui-§15) gates the drag, as on the History window.
  bar:SetScript("OnDragStart", function()
    if NS.Browser:IsLocked() then return end
    f:StartMoving()
  end)
  bar:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    savePosition()
  end)
  -- A double-click on the title bar toggles minimized (§7.1): a frame has no OnDoubleClick, so two
  -- presses within DOUBLE_CLICK seconds are one.
  bar:SetScript("OnMouseDown", function()
    local now = GetTime()
    if bar.__lastDown and now - bar.__lastDown <= DOUBLE_CLICK then
      bar.__lastDown = nil
      FP:ToggleMinimized()
    else
      bar.__lastDown = now
    end
  end)
  f.titleBar = bar
  local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("CENTER")
  title:SetText(L["Farm session"])
  f.title = title
  -- The mode badge beside the title: the simulation's word, shown while one runs and its strip is
  -- not drawn (minimized, or a degraded install with no strip) -- preview-mode's header-word rule.
  local mark = NS.Browser.SIM_MARK
  local badge = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  badge:SetPoint("LEFT", title, "RIGHT", 8, 0)
  badge:SetText(L[mark.badge])
  badge:SetTextColor(mark.color[1], mark.color[2], mark.color[3])
  badge:Hide()
  f.simBadge = badge
  NS.Skin.TitleBar(bar)
  local marks = NS.Browser:MakeTitleMarks(bar, f, function() FP:Hide() end, nil,
    { minimizeExtra(), NS.Browser.LockExtra() })
  f.minimizeButton = f.headerButtons and f.headerButtons.extras and f.headerButtons.extras.minimize
  NS.Skin.Header(f, { title = title, right = marks, bars = { bar } })
end

local function bodyTexts(f)
  f.zone = makeText(f, "GameFontNormal")
  f.chip = makeText(f, "GameFontHighlightSmall", "RIGHT")
  f.value = makeText(f, "GameFontNormalHuge")
  f.rate = makeText(f, "GameFontHighlight", "RIGHT")
  f.sub = makeText(f)
  f.note = makeText(f)
  f.kv = {}
  for i, label in ipairs(KV_LABELS) do
    local k, v = makeText(f), makeText(f, nil, "RIGHT")
    k:SetText(L[label])
    f.kv[i] = { k = k, v = v }
  end
  f.actHead = makeText(f, "GameFontNormal")
  f.actHead:SetText(L["Activity"])
  f.gpHead = makeText(f, "GameFontNormal")
  f.gpHead:SetText(L["Gold per hour"])
  f.grid = {}
  for r = 1, 3 do
    f.grid[r] = {}
    for c = 1, 4 do f.grid[r][c] = makeText(f, nil, c == 1 and "LEFT" or "RIGHT") end
  end
  for c = 2, 4 do f.grid[1][c]:SetText(L[GRID_HEAD[c - 1]]) end
  f.grid[2][1]:SetText(L["Gross"])
  f.grid[3][1]:SetText(L["Net"])
  f.actPool = NS.Pool.New()
end

-- The footer's action buttons, one of each; a paint shows the view's subset, laid left to right.
local function footerButtons(f)
  f.footer = NS.MakeFooter(f)
  local B = NS.Browser
  local acts = {
    start = { "Start", function() NS.Farm:Start() end },
    pause = { "Pause", function() NS.Farm:PauseVerb() end },
    resume = { "Resume", function() NS.Farm:ResumeVerb() end },
    finish = { "Finish", function() NS.Farm:FinishVerb() end },
    details = { "Details", function() FP:OpenDetails() end },
    sessions = { "Sessions", function() FP:ToggleSessions() end },
  }
  f.buttons = {}
  for key, a in pairs(acts) do
    local b = B.MakeFlatButton(f.footer, L[a[1]], BTN_W, BTN_H, a[2])
    b:Hide()
    b.key = key
    f.buttons[key] = b
  end
end

local function ensureFrame()
  if frame then return frame end
  local f = CreateFrame("Frame", "LootHistoryFarmPanel", UIParent, "BackdropTemplate")
  frame = f
  f:SetSize(WIDTH, 120)
  -- The persistent window tier (frame-layering-§1 T4, NS.Constants.LAYERS): MEDIUM, below the
  -- History window and every window opened to read. Toplevel, so a click raises it among its peers.
  f:SetFrameStrata(C.LAYERS.STRATA.WINDOW_PERSISTENT)
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  titleBar(f)
  f.simStrip = NS.Browser.MakeSimStrip(f, function() FP:Layout() end)
  bodyTexts(f)
  footerButtons(f)
  f:HookScript("OnShow", function() FP:SyncTicker() end)
  f:HookScript("OnHide", function()
    NS.CloseMenu()
    f:SetScript("OnUpdate", nil)
    if sessions then sessions:Hide() end
    debug("farm panel hidden")
  end)
  NS.Browser:ApplySkin(f, nil, { noTopBar = true })
  restorePosition()
  NS.Browser:ApplyChrome(f)
  f:Hide()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "LootHistoryFarmPanel") end
  return f
end

-- ── painting ─────────────────────────────────────────────────────────────────────────────────

local function stripOffset(f)
  local strip = f.simStrip
  if strip and strip:IsShown() and strip.BodyOffset then return strip:BodyOffset() or 0 end
  return 0
end

-- Anchor `fs` at (x, -y) from the panel's top-left (or its right edge for a RIGHT text), shown.
local function put(fs, y, right, x)
  fs:ClearAllPoints()
  if right then
    fs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(x or PAD), -y)
  else
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x or PAD, -y)
  end
  fs:Show()
end

local function hideBody(f)
  for _, k in ipairs({ "zone", "chip", "value", "rate", "sub", "note", "actHead", "gpHead" }) do f[k]:Hide() end
  for _, p in ipairs(f.kv) do p.k:Hide(); p.v:Hide() end
  for _, row in ipairs(f.grid) do for _, fs in ipairs(row) do fs:Hide() end end
  NS.Pool.ReleaseAll(f.actPool)
end

local function layoutHead(f, y, dim)
  put(f.zone, y); put(f.chip, y, true)
  y = y + 20
  put(f.value, y); put(f.rate, y + 6, true)
  f.value:SetAlpha(dim and 0.6 or 1); f.rate:SetAlpha(dim and 0.6 or 1)
  return y + 28
end

local function layoutGrid(f, y)
  put(f.gpHead, y)
  y = y + 18
  for r, row in ipairs(f.grid) do
    put(row[1], y)
    for c = 2, 4 do put(row[c], y, true, PAD + (4 - c) * 70) end
    if r < #f.grid then y = y + 15 end
  end
  return y + 15
end

local function activityCell(f)
  return NS.Pool.Acquire(f.actPool, function()
    local cell = CreateFrame("Frame", nil, f)
    cell:SetSize((WIDTH - 3 * PAD) / 2, 15)
    cell.k = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.k:SetPoint("LEFT", cell, "LEFT", 0, 0)
    cell.v = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.v:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
    NS.Skin.Font(cell.k); NS.Skin.Font(cell.v)
    return cell
  end)
end

local function layoutActivity(f, y, lines)
  if #lines == 0 then return y end
  put(f.actHead, y)
  y = y + 18
  f.actCells = {}
  for i, line in ipairs(lines) do
    local cell = activityCell(f)
    local col = (i - 1) % 2
    cell:ClearAllPoints()
    cell:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + col * ((WIDTH - PAD) / 2), -(y + math.floor((i - 1) / 2) * 15))
    cell.k:SetText(L[line.label]); tint(cell.k, "text.muted")
    cell.v:SetText(line.text); tint(cell.v, "text.body")
    cell.key = line.key
    f.actCells[i] = cell
  end
  return y + math.ceil(#lines / 2) * 15 + 6
end

local function layoutFull(f, y)
  put(f.sub, y)
  y = y + 20
  for _, p in ipairs(f.kv) do
    put(p.k, y); put(p.v, y, true)
    y = y + 16
  end
  y = layoutActivity(f, y + 6, f.lines or {})
  return layoutGrid(f, y + 4)
end

local VIEW_BUTTONS = {
  full = { "pause", "finish", "details", "sessions" },
  paused = { "resume", "finish" },
  min = { "toggle", "finish" },
  none = { "start", "sessions" },
}

-- The footer's buttons for `view`: Details only once the Details window exists (M4.3), Sessions
-- only once the sessions list does (M4.4); `toggle` is Pause or Resume as the clock stands.
local function buttonAvailable(key)
  if key == "details" then return NS.FarmDetails ~= nil and NS.FarmDetails.Open ~= nil end
  if key == "sessions" then return FP.ToggleSessions ~= nil end
  return true
end

function FP:LayoutButtons(view, s)
  local f = frame
  for _, b in pairs(f.buttons) do b:Hide() end
  local x = 8
  f.shownButtons = {}
  for _, key in ipairs(VIEW_BUTTONS[view]) do
    if key == "toggle" then key = (s and s.runningSince) and "pause" or "resume" end
    local b = f.buttons[key]
    if b and buttonAvailable(key) then
      b:ClearAllPoints()
      b:SetPoint("LEFT", f.footer, "LEFT", x, 0)
      b:Show()
      x = x + BTN_W + BTN_GAP
      f.shownButtons[#f.shownButtons + 1] = key
    end
  end
end

--- Place every element of the current view and size the panel to it.
function FP:Layout()
  local f = frame
  if not f then return end
  hideBody(f)
  local view = f.view or "none"
  local y = TITLE_H + stripOffset(f) + 8
  if view == "none" then
    put(f.note, y)
    y = y + 18
  else
    y = layoutHead(f, y, view == "paused")
    if view == "full" then
      y = layoutFull(f, y)
    else
      put(f.note, y)
      y = y + 18
    end
  end
  f:SetHeight(y + 8 + NS.FooterHeight())
end

local function paintCosts(f, n)
  local v = f.kv[5].v
  if not costsTracked() then
    v:SetText(L["n/a (needs ledger capture)"])
    tint(v, "text.disabled")
  else
    local c = n.totals.costs or 0
    v:SetText(c > 0 and ("-" .. FarmModel.CopperText(c)) or FarmModel.CopperText(0))
    tint(v, "sem.bad")
  end
end

local function paintGrid(f, n)
  for r, basis in ipairs({ "gross", "net" }) do
    for c, measure in ipairs(GRID_COLS) do
      local rate = FarmModel.PerHour(FarmModel.Value(n.totals, measure, basis), n.elapsed)
      f.grid[r + 1][c + 1]:SetText(FarmModel.RateText(rate))
    end
  end
end

--- The numbers that move with the clock: the headline, its rate, the basis line, Elapsed and the
--- gold-per-hour grid (the 1 Hz OnUpdate's whole job), for the open session.
function FP:PaintNumbers()
  local f = frame
  local s = f and NS.Farm:Active()
  if not s then return end
  local n = FP.Numbers(s, time())
  f.value:SetText(FarmModel.CopperText(n.value))
  f.rate:SetText(FarmModel.RateText(n.rate) .. "/h")
  if f.view == "min" then f.note:SetText(FarmModel.Clock(n.elapsed) .. " " .. L["elapsed"]) end
  if f.view ~= "full" then return end
  f.sub:SetText(FP.SubLine(n))
  f.kv[1].v:SetText(FarmModel.Clock(n.elapsed))
  f.kv[2].v:SetText(FarmModel.CopperText(n.totals.money))
  f.kv[3].v:SetText(FarmModel.CopperText(n.totals.vendor))
  f.kv[4].v:SetText(FarmModel.CopperText(n.totals.ah))
  paintCosts(f, n)
  paintGrid(f, n)
end

local function paintStatic(f, s)
  for _, p in ipairs(f.kv) do tint(p.k, "text.muted"); tint(p.v, "text.body") end
  tint(f.value, "sem.gold"); tint(f.rate, "text.body"); tint(f.sub, "text.muted"); tint(f.note, "text.muted")
  tint(f.actHead, "text.heading"); tint(f.gpHead, "text.heading")
  if not s then
    f.note:SetText(L["No farm session running."])
    return
  end
  f.zone:SetText(s.zone ~= "" and s.zone or L["Unknown"])
  local chip, token = FP.ChipFor(s)
  f.chip:SetText(chip)
  tint(f.chip, token)
  if f.view == "paused" then f.note:SetText(FP.PausedHint(s)) end
  local fs = farmSettings()
  f.lines = FarmModel.ActivityLines(s.activity, fs.activity, fs.hideZero, f.lines)
end

--- The simulation's strip while one runs and the panel is expanded; minimized (or with no strip),
--- the title's badge instead (preview-mode). Test mode never reaches the panel: it always shows the
--- live (or simulated) session (§12.3).
function FP:UpdateStrip()
  local f = frame
  if not f then return end
  local sim = simulating()
  local min = panelState().minimized == true
  if f.simStrip then f.simStrip:SetShown(sim and not min) end
  f.simBadge:SetShown(sim and (min or f.simStrip == nil))
end

--- A full repaint: the view, the strip, the texts, the layout, the buttons and the ticker.
function FP:Refresh()
  local f = frame
  if not f then return end
  local s = NS.Farm:Active()
  f.view = FP.ViewFor(s, panelState().minimized == true)
  self:UpdateStrip()
  paintStatic(f, s)
  self:Layout()
  self:PaintNumbers()
  self:LayoutButtons(f.view, s)
  self:SyncTicker()
end

-- ── the ticker (1 Hz while shown and running) ────────────────────────────────────────────────

local function onUpdate(_, elapsed)
  FP._acc = (FP._acc or 0) + (elapsed or 0)
  if FP._acc < TICK then return end
  FP._acc = 0
  FP:PaintNumbers()
end

--- Set the OnUpdate while the panel shows a running session; clear it otherwise.
function FP:SyncTicker()
  local f = frame
  if not f then return end
  local s = NS.Farm:Active()
  local on = f:IsShown() and s ~= nil and s.runningSince ~= nil and not NS.IsStoodDown()
  f:SetScript("OnUpdate", on and onUpdate or nil)
end

-- ── marks ────────────────────────────────────────────────────────────────────────────────────

--- Repaint the lock mark for the lock as it stands (from B:OnSettingsChanged and B:AdoptProfile).
function FP:PaintLockMark()
  if frame then NS.Browser:PaintLockMarkOn(frame.lockButton) end
end

--- Repaint the minimize mark: `minimise` / "Minimize the panel", or `add` / "Expand the panel".
function FP:PaintMinimizeMark()
  if not (frame and frame.minimizeButton) then return end
  local icon, _, tip = minimizeFace()
  NS.Browser:PaintMark(frame.minimizeButton, icon, tip)
end

--- Flip minimized (the `-` / `+` mark and a title-bar double-click); the state persists (§4.5).
function FP:ToggleMinimized()
  local p = panelState()
  p.minimized = (not p.minimized) or nil
  debug("farm panel %s", p.minimized and "minimized" or "expanded")
  self:PaintMinimizeMark()
  self:Refresh()
end

-- ── show, hide, visibility ───────────────────────────────────────────────────────────────────

-- Hide the frame and its ticker together: the client's OnHide clears the OnUpdate too, but a hide
-- path must not depend on the script running (a hidden frame's OnUpdate is the §7 cost).
local function takeDown()
  frame:Hide()
  frame:SetScript("OnUpdate", nil)
  if sessions then sessions:Hide() end
end

local function reveal()
  local f = ensureFrame()
  f:Show()
  FP:Refresh()
  debug("farm panel shown")
end

--- Show the panel. Refused silently while stood down (the verb gate already spoke), and with a line
--- while General visibility hides it -- which also marks it to come back on the next allowing edge.
function FP:Show()
  if NS.IsStoodDown() then
    debug("farm panel refused: stood down")
    return
  end
  if not NS.Browser:VisibilityAllows() then
    self._hiddenByVisibility = true
    debug("farm panel refused: visibility")
    NS.Print("the farm panel is hidden by the General visibility setting.")
    return
  end
  self._hiddenByVisibility = nil
  reveal()
end

--- Hide the panel (its close mark, the verb, the stand-down). Forgets a pending visibility re-show.
function FP:Hide()
  self._hiddenByVisibility = nil
  if frame then takeDown() end
end

function FP:Toggle()
  if self:IsShown() then return self:Hide() end
  return self:Show()
end

function FP:IsShown() return frame ~= nil and frame:IsShown() end

--- F9: hide a panel the visibility setting no longer allows (remembering it), and bring back one it
--- hid once the setting allows it again. `inCombat` is the combat edge, as B:VisibilityAllows takes.
function FP:ApplyVisibility(inCombat)
  local allows = NS.Browser:VisibilityAllows(inCombat)
  if frame and frame:IsShown() and not allows then
    takeDown()
    self._hiddenByVisibility = true
    debug("farm panel hidden by visibility")
  elseif self._hiddenByVisibility and allows then
    self._hiddenByVisibility = nil
    reveal()
  end
end

--- The master rows moved (B:OnSettingsChanged): chrome, the lock mark, visibility.
function FP:OnChromeChanged()
  if frame then NS.Browser:ApplyChrome(frame) end
  if sessions then NS.Browser:ApplyChrome(sessions) end
  self:PaintLockMark()
  self:ApplyVisibility()
end

--- The profile adopt path (B:AdoptProfile): the new profile's position, minimized state, lock,
--- chrome and visibility. A panel never built has nothing to re-read.
function FP:AdoptProfile()
  if not frame then return end
  restorePosition()
  NS.Browser:ApplyChrome(frame)
  if sessions then NS.Browser:ApplyChrome(sessions) end
  self:PaintLockMark()
  self:PaintMinimizeMark()
  if frame:IsShown() then self:Refresh() end
  self:ApplyVisibility()
end

--- The panel frame, or nil before its first show (a test seam).
function FP:Window() return frame end

-- ── the other farm windows (M4.3, M4.4) ──────────────────────────────────────────────────────

--- Details opens the open session's record (modules/FarmDetails.lua, M4.3).
function FP:OpenDetails()
  if NS.FarmDetails and NS.FarmDetails.Open then NS.FarmDetails:Open(nil) end
end

-- ── the sessions list (§7.2, M4.4) ───────────────────────────────────────────────────────────

local SESSIONS_W, SESSIONS_H = 360, 320
local SESSION_KEYS = { "date", "zone", "active", "total", "rate", "star" }
local SESSION_WIDTHS = { 52, nil, 44, 72, 64, 22 }

local function sessionsBar(f)
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", -1, -1)
  bar:SetHeight(TITLE_H)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  -- Docked: a drag on its title moves the panel it hangs from, under the same lock.
  bar:SetScript("OnDragStart", function()
    if NS.Browser:IsLocked() then return end
    frame:StartMoving()
  end)
  bar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    savePosition()
  end)
  f.titleBar = bar
  local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("CENTER")
  title:SetText(L["Farm sessions"])
  f.title = title
  NS.Skin.TitleBar(bar)
  -- A companion: close alone.
  local marks = NS.Browser:MakeTitleMarks(bar, f, function() FP:HideSessions() end, true, nil)
  NS.Skin.Header(f, { title = title, right = marks, bars = { bar } })
end

--- Place the list under the title (and a mode strip, while one shows).
function FP:LayoutSessions()
  local f = sessions
  if not f then return end
  local top = TITLE_H + 4
  for _, strip in ipairs({ f.simStrip, f.testStrip }) do
    if strip and strip:IsShown() and strip.BodyOffset then top = top + (strip:BodyOffset() or 0) end
  end
  f.host:ClearAllPoints()
  f.host:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -top)
  f.host:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
  if f.list then f.list:Relayout() end
end

local function tooltipGroup()
  local Tip = LibStub and LibStub("LibKa0s-Tooltip-1.0", true)
  if Tip and Tip.SetGroup then Tip.SetGroup(frame, function() return { sessions } end) end
end

local function ensureSessions()
  if sessions then return sessions end
  local FT = NS.FarmTab
  -- Parented to UIParent, not the panel, so the master scale applies once (B:ApplyChrome on each).
  local f = CreateFrame("Frame", "LootHistoryFarmSessions", UIParent, "BackdropTemplate")
  sessions = f
  f:SetSize(SESSIONS_W, SESSIONS_H)
  -- The read tier (frame-layering-§1 T4 WINDOW, HIGH), one above the panel it docks to (§11.3).
  f:SetFrameStrata(C.LAYERS.STRATA.WINDOW)
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0)
  sessionsBar(f)
  f.simStrip = NS.Browser.MakeSimStrip(f, function() FP:LayoutSessions() end)
  f.testStrip = NS.Browser.MakeTestModeStrip and NS.Browser.MakeTestModeStrip(f, function() FP:LayoutSessions() end)
  f.host = CreateFrame("Frame", nil, f)
  f:HookScript("OnHide", function() debug("farm sessions hidden") end)
  NS.Browser:ApplySkin(f, nil, { noTopBar = true })
  NS.Browser:ApplyChrome(f)
  FP:LayoutSessions()
  f.list = NS.FarmList.New(f.host, {
    columns = FT.Columns(SESSION_KEYS, SESSION_WIDTHS, { rate = "/h" }),
    sortKey = "date", sortAsc = false,
    empty = L["No saved farm sessions yet."],
    onClick = FT.RowClick, onDoubleClick = FT.RowDoubleClick, onEnter = FT.RowEnter,
  })
  f:Hide()
  tooltipGroup()
  return f
end

--- This character's saved sessions in Farm:ActiveStore(), as list entries at the headline value.
function FP.SessionEntries()
  local FT = NS.FarmTab
  local kind, char = FT.StoreKind(), NS.Util.PlayerKey()
  local mine = NS.Farm:ActiveStore()[char]
  local measure = farmSettings().headlineValue or "ah"
  local out = {}
  for _, s in ipairs(mine and mine.sessions or {}) do out[#out + 1] = FT.Entry(s, kind, char, measure) end
  return FT.MarkBest(out, measure)
end

--- Repaint the sessions list: its strips and its rows.
function FP:RefreshSessions()
  local f = sessions
  if not f then return end
  local kind = NS.FarmTab.StoreKind()
  if f.simStrip then f.simStrip:SetShown(kind == "sim") end
  if f.testStrip then f.testStrip:SetShown(kind == "test") end
  self:LayoutSessions()
  f.list:SetData(FP.SessionEntries())
end

--- Show the sessions list beside the panel (the panel must be up; it closes with it).
function FP:ShowSessions()
  if not self:IsShown() then return end
  ensureSessions():Show()
  self:RefreshSessions()
  debug("farm sessions shown")
end

function FP:HideSessions()
  if sessions then sessions:Hide() end
end

function FP:SessionsShown() return sessions ~= nil and sessions:IsShown() end

--- The panel's Sessions button.
function FP:ToggleSessions()
  if self:SessionsShown() then return self:HideSessions() end
  return self:ShowSessions()
end

--- The sessions list frame (a test seam), nil before its first show.
function FP:SessionsWindow() return sessions end

-- ── the bus (lifecycle steps, core/LifecycleSetup.lua) ───────────────────────────────────────

local function onChanged()
  if frame and frame:IsShown() and FP._refresh then FP._refresh() end
  if sessions and sessions:IsShown() and FP._refreshSessions then FP._refreshSessions() end
end

--- Stand-up: the panel's own bus target, FARM_CHANGED and SETTINGS_CHANGED, both coalesced.
function FP:Enable()
  if self.__ev or not NS.bus then return end
  self._refresh = NS.Coalesce(function() FP:Refresh() end, COALESCE)
  self._refreshSessions = NS.Coalesce(function() FP:RefreshSessions() end, COALESCE)
  self.__ev = NS.NewBusTarget()
  self.__ev:RegisterMessage(NS.MSG.FARM_CHANGED, onChanged)
  self.__ev:RegisterMessage(NS.MSG.SETTINGS_CHANGED, onChanged)
end

--- Stand-down: the bus target goes (the panel itself goes in the Hide step).
function FP:Disable()
  if not self.__ev then return end
  self.__ev:UnregisterAllMessages()
  self.__ev = nil
  self._refresh, self._refreshSessions = nil, nil
end
