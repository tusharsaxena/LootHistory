-- LibKa0s-Sim-1.0 — the step panel: a docked window listing the session's steps as clickable rows,
-- each with the slash command that does the same thing, the scenario picker under them while no
-- simulation runs, and the run controls while one does.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF Sim.lua ──────────────────────────────────────
--
-- A host that only scripts a simulation (the seam, the session and the step machine) needs no
-- frame, so the panel is a secondary file of `LibKa0s-Sim-1.0` paired on the shell's minor (Perf's
-- multi-file idiom), with an attach-file floor of its own: Core 9 or newer and Widgets present (the
-- picker's `W.Dropdown`). With the floor unmet this file returns before `lib.__AttachPanel` exists,
-- the shell's panel fallbacks answer (`ShowPanel` false, `PanelRows` {}), and a headless Sim is
-- never lost to a missing panel.
--
-- ── THE RENDERER IS PRIVATE (LK-11 OUTCOME B, LibKa0s#53) ────────────────────────────────────
--
-- The owner's scope made the step panel a public widget only if Perf's panel could be rebuilt on
-- it with every Perf suite passing unedited (OWNER_SCOPE C.6). It could not, so the renderer is a
-- FILE-LOCAL section of this file, library-internal with no public contract. It is a deliberate
-- duplicate of PerfPanel.lua's renderer (same geometry, palette and chrome); PerfPanel.lua's header
-- names the same duplication from its side. The suites reach it through `lib.__StepPanel`, an
-- internal test seam (library-stack-§7's `__` clause): no host reads it, and the members manifest
-- leaves it out.
--
-- ── WHAT THE ADAPTER OWNS ────────────────────────────────────────────────────────────────────
--
-- Rows: Start, one per timeline step, Stop, addressed by index (keys repeat). States are Perf's set
-- and no other (design D8): a step before pos is done; the step at pos is busy while the run plays
-- or the gate holds; pos+1 is ready; further ahead is locked AND actionable (a click there runs
-- every step up to it through the internal click-ahead); every step is locked and inert while idle
-- or before the session's ready(). Start is ready while idle, busy until ready, then done; Stop is
-- cancel while running, the only time it acts. A click re-composes from the live model and
-- re-checks the clicked index, so a stale row never acts, and every action is `RunVerb` or the
-- click-ahead: the click path is the typed path.
--
-- Idle, the rows preview the picked scenario's `timeline(def, opts)` at pos 0, all locked.
--
-- The picked scenario is read at use (minor 2): `chosen(P)` answers the picker's choice while its
-- def resolves, else the first name `d.scenarios.names` lists NOW, so a host that fills its
-- scenarios after `Sim:New` (legal since Sim minor 2) gets a working Start row and picker. With no
-- scenario listed at all the Start row is locked and the picker's Start disabled.
--
-- Placement: a point dragged THIS SESSION wins, held in this instance's memory only (OWNER_SCOPE
-- C.11: the panel position is session-only and nothing is written to SavedVariables). Otherwise it
-- docks right of `d.panel.anchorTo()`, or left of it when the right has no room, or floats at
-- CENTER +420 when neither side fits or there is no anchor. It redocks on every Show with no
-- dragged point, and `ResetPanelPosition()` forgets the point. The library draws its own minimal
-- button and uses GameTooltip: there is no `d.panel.button` or `d.panel.tooltip` (C.7).

local lib = LibStub and LibStub("LibKa0s-Sim-1.0", true)
if not lib then return end

-- The attach-file floor: MakeResizable arrived at Core minor 9, and the picker is W.Dropdown.
local core = LibStub("LibKa0s-Core-1.0", true)
local W = LibStub("LibKa0s-Widgets-1.0", true)
local NEEDS_CORE = 9
if not core or (core.MINOR or 0) < NEEDS_CORE or not W then return end

local SIM_PANEL_MINOR = 3

--- Close Widgets' shared dropdown menu. The picker's dropdowns drop that process-wide popup, which
--- no owner's Hide reaches (Widgets.lua's CloseMenu contract), so every non-click way the picker
--- leaves the screen calls this: HidePanel, the frame's OnHide (Escape through UISpecialFrames
--- never goes through HidePanel), and the footer swapping the picker out for the controls.
local function closeMenu()
  if type(W.CloseMenu) == "function" then W.CloseMenu() end
end
-- Paired on the SHELL's minor as well as this file's own, as SimTimeline.lua is.
if lib.__panelMinor and lib.__panelMinor >= SIM_PANEL_MINOR
  and lib.__panelShellMinor == lib.MINOR then return end
lib.__panelMinor      = SIM_PANEL_MINOR
lib.__panelShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.SimPanel = SIM_PANEL_MINOR

local type, tostring, tonumber, pcall, ipairs, floor = type, tostring, tonumber, pcall, ipairs, math.floor

--- Keep a button's OnEnter and OnLeave running while it is disabled. The client runs neither on a
--- disabled Button by default, and the panel disables every row it will not act on (a played step,
--- the started Start row) and every control with nothing to do, each of which still has a tip.
local function hoverWhileDisabled(b)
  if type(b.SetMotionScriptsWhileDisabled) == "function" then b:SetMotionScriptsWhileDisabled(true) end
end

lib.STRINGS = lib.STRINGS or {}
for key, line in pairs({
  PANEL_START = "Start: %s",
  START       = "Start",
  PANEL_STOP  = "Stop simulation",
  RUN_ALL     = "Run all",
  PAUSE       = "Pause",
  RESUME      = "Resume",
  RESTART     = "Restart",
  STOP        = "Stop",
  RANDOM      = "Random",
  RAN_AGO     = "Ran %s ago",
}) do lib.STRINGS[key] = line end

-- ════════════════════════════════════════════════════════════════════════════════════════════
-- THE RENDERER (file-local; `lib.__StepPanel` is its internal test seam)
-- ════════════════════════════════════════════════════════════════════════════════════════════
--
-- Render-only: it owns the shape and none of the semantics. A row arrives as data,
-- `{ key?, label, command, state, actionable, tip? }`, from `d.rows()`; `actionable` is the
-- caller's answer and never derived from `state` here. A click re-reads `rows()` and re-checks
-- `actionable` at the clicked index before `d.onClick(row, index)`. No state logic, no slash
-- knowledge, no saved position: the panel sits at CENTER -320 at build, and the adapter below
-- positions it. Resizing is width-only through Core.MakeResizable (guarded), and because that is
-- call-once and pins a widthOnly frame's height bounds at the height it had then, every Refresh
-- where the row count moved re-pins them (OWNER_SCOPE C.5), guarded the way Core's setBounds is.
--
-- Perf's geometry, palette and command color, copied from PerfPanel.lua on purpose.
local ROW_W, ROW_H, GAP = 360, 22, 4
local DOT_X, DOT = 8, 8        -- column 1: status dot
local LABEL_X   = 26           -- column 2: step name
local CMD_PAD   = 10           -- column 3: slash command, right-aligned
local TITLE_H = 24
local PAD = 8

local COLORS = {
  done   = { 0.30, 0.85, 0.30 },
  used   = { 0.30, 0.85, 0.30 },
  ready  = { 0.90, 0.90, 0.92 },
  busy   = { 1.00, 0.82, 0.00 },
  locked = { 0.40, 0.40, 0.42 },
  cancel = { 0.80, 0.32, 0.32 },
}
local CMD_COLOR = { 0.45, 0.45, 0.48 }

local LOCKED_DOT_ALPHA = 0.35
local CHECK = 12                                   -- the done mark, centered over the dot
local HOVER_GOLD   = { 1, 0.82, 0 }
local HOVER_CANCEL = { 1.00, 0.45, 0.45 }
local CENTER_X = -320                              -- Perf's spot, set once at build

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end
local function colorOf(state) return COLORS[state] or COLORS.locked end

local function required(d, field, kind)
  if type(d[field]) ~= kind then
    error(("LibKa0s-Sim-1.0: StepPanel requires d.%s (a %s)"):format(field, kind), 3)
  end
end

local function checkDescriptor(d)
  if type(d) ~= "table" then
    error("LibKa0s-Sim-1.0: StepPanel requires a descriptor table", 3)
  end
  required(d, "name", "string")
  required(d, "addonName", "string")
  required(d, "rows", "function")
  required(d, "onClick", "function")
end

local function readRows(d)
  local list = d.rows()
  if type(list) ~= "table" then return {} end
  return list
end

local function readTitle(d)
  local t = d.title
  if type(t) == "function" then t = t() end
  return t ~= nil and tostring(t) or ""
end

--- The footer, when the descriptor carries a usable one: a number height and two functions.
local function footerOf(d)
  local f = d.footer
  if type(f) ~= "table" or type(f.build) ~= "function" or type(f.paint) ~= "function" then return nil end
  if type(f.height) ~= "number" or f.height < 0 then return nil end
  return f
end

--- The 10.0+ half of pinHeight: keep the width bounds MakeResizable set, pin the height to `h`.
local function pinHeightBounds(frame, minW, h)
  local curMinW, _, curMaxW
  if type(frame.GetResizeBounds) == "function" then curMinW, _, curMaxW = frame:GetResizeBounds() end
  local loW = (type(curMinW) == "number" and curMinW > 0) and curMinW or minW
  local hiW = (type(curMaxW) == "number" and curMaxW >= loW) and curMaxW or loW
  frame:SetResizeBounds(loW, h, hiW, h)
end

--- The pre-10.0 half: the SetMinResize / SetMaxResize pair, the maximum width the screen's.
local function pinHeightLegacy(frame, minW, h)
  if type(frame.SetMinResize) == "function" then frame:SetMinResize(minW, h) end
  if type(frame.SetMaxResize) == "function" then
    local sw = type(UIParent) == "table" and type(UIParent.GetWidth) == "function" and UIParent:GetWidth()
    frame:SetMaxResize((type(sw) == "number" and sw > minW) and sw or minW, h)
  end
end

--- Re-pin the height bounds to `h`, keeping the width bounds MakeResizable set. Guarded like
--- Core's setBounds, because SetResizeBounds replaced the SetMinResize / SetMaxResize pair in 10.0.
--- Split in two so neither half passes CCN 15 (automated-tests-§3's release gate).
local function pinHeight(frame, minW, h)
  if type(frame.SetResizeBounds) == "function" then return pinHeightBounds(frame, minW, h) end
  pinHeightLegacy(frame, minW, h)
end

--- The frame chrome: Perf's backdrop, strata, drag, title and close mark.
local function buildChrome(frame, d, panel, showClose)
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() frame:StartMoving() end)
  frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.title:SetPoint("TOP", frame, "TOP", 0, -6)
  frame.title:SetText(readTitle(d))
  if not showClose then return end
  -- The third argument is the addon FOLDER the close icon's path is built from; without it
  -- MakeCloseButton falls back to the multiplication sign (Perf panel minor 3's bug).
  local close = core.MakeCloseButton(frame, panel.Hide, d.addonName)
  if close then
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -(TITLE_H - 18) / 2)
    frame.closeButton = close
  end
end

--- Build one step panel. Answers { Frame, Show, Hide, Toggle, IsShown, Refresh, Buttons }.
local function StepPanel(d)
  checkDescriptor(d)
  local footer = footerOf(d)
  local showClose = d.close ~= false
  local panel = {}
  local frame
  local buttons, shown, pinnedCount = {}, 0, nil
  local minW = ROW_W + PAD * 2

  local function heightFor(n)
    local h = TITLE_H + PAD * 2 + n * (ROW_H + GAP)
    if footer then h = h + footer.height + PAD end
    return h
  end

  local function rowWidth()
    local w = frame:GetWidth()
    if type(w) == "number" and w > PAD * 2 then return w - PAD * 2 end
    return ROW_W
  end

  local function stretchRows(w)
    if type(w) ~= "number" or w <= 0 then w = frame:GetWidth() end
    if type(w) ~= "number" or w <= 0 then return end
    for _, b in ipairs(buttons) do b:SetWidth(w - PAD * 2) end
  end

  local function onEnter(b)
    local row = b.__row
    if not row then return end
    -- Hover marks what a click would do, so only an actionable row lights up; a tip is for any row
    -- (a done step's tip says when it ran).
    if row.actionable then setColor(b.text, row.state == "cancel" and HOVER_CANCEL or HOVER_GOLD) end
    if row.tip ~= nil and type(d.tooltip) == "function" then
      b.__tipShown = true
      d.tooltip(b, row)
    end
  end

  local function onLeave(b)
    if b.__row then setColor(b.text, colorOf(b.__row.state)) end
    if b.__tipShown then
      b.__tipShown = nil
      if type(GameTooltip) == "table" and GameTooltip.Hide then GameTooltip:Hide() end
    end
  end

  local function onClick(b)
    local index = b.__index
    local row = readRows(d)[index]
    if row and row.actionable then d.onClick(row, index) end
    panel.Refresh()
  end

  local function makeRow(index)
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(rowWidth(), ROW_H)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TITLE_H + PAD + (index - 1) * (ROW_H + GAP)))
    -- A solid color texture, not a glyph or an art path: PerfPanel.lua's note on the dot.
    b.dot = b:CreateTexture(nil, "ARTWORK")
    b.dot:SetSize(DOT, DOT)
    b.dot:SetPoint("LEFT", b, "LEFT", DOT_X, 0)
    if type(d.check) == "string" or type(d.check) == "number" then
      b.check = b:CreateTexture(nil, "OVERLAY")
      b.check:SetSize(CHECK, CHECK)
      b.check:SetPoint("CENTER", b.dot, "CENTER", 0, 0)
      b.check:SetTexture(d.check)
      b.check:Hide()
    end
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("LEFT", b, "LEFT", LABEL_X, 0)
    b.text:SetJustifyH("LEFT")
    b.cmd = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.cmd:SetPoint("RIGHT", b, "RIGHT", -CMD_PAD, 0)
    b.cmd:SetJustifyH("RIGHT")
    setColor(b.cmd, CMD_COLOR)
    b.__index = index
    hoverWhileDisabled(b)
    b:SetScript("OnEnter", onEnter)
    b:SetScript("OnLeave", onLeave)
    b:SetScript("OnClick", onClick)
    return b
  end

  local function paintRow(b, row)
    b.__row = row
    local c = colorOf(row.state)
    b.text:SetText(row.label)
    b.cmd:SetText(row.command)
    setColor(b.text, c)
    if b.dot.SetColorTexture then
      b.dot:SetColorTexture(c[1], c[2], c[3], row.state == "locked" and LOCKED_DOT_ALPHA or 1)
    end
    local done = b.check ~= nil and row.state == "done"
    if b.check then
      b.check:SetVertexColor(c[1], c[2], c[3])
      b.check:SetShown(done)
    end
    b.dot:SetShown(not done)
    if row.actionable then b:Enable() else b:Disable() end
    -- What was rendered, for the headless suites (PerfPanel.lua records the same three).
    b.__label, b.__state, b.__command = row.label, row.state, row.command
    b:Show()
  end

  local function build()
    local n = #readRows(d)
    frame = CreateFrame("Frame", d.name, UIParent, "BackdropTemplate")
    frame:SetSize(minW, heightFor(n))
    frame:SetPoint("CENTER", CENTER_X, 0)
    frame.__rowButtons = buttons                   -- the test record: the row buttons, by index
    buildChrome(frame, d, panel, showClose)
    if footer then
      footer.build(frame, {
        Show = panel.Show, Hide = panel.Hide, Toggle = panel.Toggle, IsShown = panel.IsShown,
        Refresh = panel.Refresh, Buttons = panel.Buttons,
        TITLE_H = TITLE_H, PAD = PAD, ROW_W = ROW_W,
      })
    end
    core.ApplySkin(frame)
    frame:Hide()
    -- Escape hides the frame directly (CloseSpecialWindows), never through HidePanel.
    if type(frame.HookScript) == "function" then frame:HookScript("OnHide", closeMenu) end
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, d.name) end
    -- Guarded: the no-MakeResizable fixture (tests/test_resize_windows.lua) is today's fixed panel.
    if type(core.MakeResizable) == "function" then
      core.MakeResizable(frame, {
        minWidth = minW, minHeight = heightFor(n), widthOnly = true, onResize = stretchRows,
      })
    end
    pinnedCount = n
  end

  function panel.Frame()
    if frame then return frame end
    if type(CreateFrame) ~= "function" then return nil end
    build()
    return frame
  end

  --- Repaint from `rows()` and the title. Cheap and idempotent: safe on every host transition.
  function panel.Refresh()
    if not frame then return end
    frame.title:SetText(readTitle(d))
    local list = readRows(d)
    for i, row in ipairs(list) do
      buttons[i] = buttons[i] or makeRow(i)
      paintRow(buttons[i], row)
    end
    shown = #list
    for i = shown + 1, #buttons do
      buttons[i].__row = nil
      buttons[i]:Hide()
    end
    local h = heightFor(shown)
    frame:SetHeight(h)
    if shown ~= pinnedCount then
      pinHeight(frame, minW, h)
      pinnedCount = shown
    end
    if footer then footer.paint(frame) end
  end

  function panel.Show()
    local f = panel.Frame()
    if not f then return end
    panel.Refresh()
    f:Show()
  end

  function panel.Hide() if frame then frame:Hide() end end
  function panel.IsShown() return (frame and frame:IsShown()) and true or false end
  function panel.Toggle()
    if panel.IsShown() then panel.Hide() else panel.Show() end
  end

  --- The row buttons of the last paint, by index. A fresh table: writing to it moves nothing.
  function panel.Buttons()
    local out = {}
    for i = 1, shown do out[i] = buttons[i] end
    return out
  end

  return panel
end

lib.__StepPanel = StepPanel

-- ════════════════════════════════════════════════════════════════════════════════════════════
-- THE ADAPTER: Sim's semantics on the renderer (P is one instance's panel state)
-- ════════════════════════════════════════════════════════════════════════════════════════════

local DOCK_GAP = 8
local FLOAT_X = 420
local BAR_H = 22                   -- the picker, or the controls, under the rows
local BUTTON_W, BUTTON_GAP = 84, 6
local SCENARIO_W, SIZE_W = 140, 120
local WIDTH = ROW_W + PAD * 2

-- What an internal click-ahead's failure code prints (the verbs' WHY lines, SimTimeline.lua).
local WHY = { notRunning = "NOT_RUNNING", building = "BUILDING", playing = "PLAYING", done = "DONE" }

local function panelField(P, key)
  local panel = P.ctx.d.panel
  return type(panel) == "table" and panel[key] or nil
end

--- A presentation callback's answer under pcall, or nil when it is absent or raises.
local function ask(P, key, ...)
  local fn = panelField(P, key)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if not ok then
    P.ctx.debug("panel.%s failed: %s", key, tostring(v))
    return nil
  end
  return v
end

--- A tip line list: the field's table, or the function's answer.
local function tipList(P, key, ...)
  local v = panelField(P, key)
  if type(v) == "function" then v = ask(P, key, ...) end
  return type(v) == "table" and v or nil
end

--- A fresh copy of a tip list, so a RAN_AGO line never lands in the host's own table.
local function copyTip(list)
  local out = {}
  for i, line in ipairs(list or {}) do out[i] = line end
  return out
end

--- "12s", "3m", "2h": how long ago `at` (a time() stamp) was.
local function agoText(at)
  local s = floor((time() or 0) - (tonumber(at) or 0))
  if s < 0 then s = 0 end
  if s < 60 then return s .. "s" end
  if s < 3600 then return floor(s / 60) .. "m" end
  return floor(s / 3600) .. "h"
end

local function ranLine(P, at)
  return { P.ctx.tr("RAN_AGO"):format(agoText(at)) }
end

local function slashOf(P, rest) return tostring(P.ctx.d.slash) .. " " .. rest end

--- The scenario def `name` names, read from d.scenarios now, or nil (a non-table entry included).
local function defOf(P, name)
  if name == nil then return nil end
  local def = P.ctx.d.scenarios.defs[name]
  return type(def) == "table" and def or nil
end

--- The scenario the picker means, read at use (minor 2): its choice while that def resolves, else
--- the first name d.scenarios.names lists now, else nil (nothing listed yet).
local function chosen(P)
  local name = P.choice.scenario
  if defOf(P, name) then return name end
  return P.ctx.d.scenarios.names[1]
end

--- The size the picker sends with `name`: its chosen size when the def has sizes, else nil.
local function sizeFor(P, name)
  local def = defOf(P, name)
  if not (def and def.sizes) then return nil end
  return tonumber(P.choice.size) or 0
end

--- The verb line that starts `name` at `size` (0 or nil: no size argument). No name: the bare verb.
local function startLine(name, size)
  if name == nil then return "start" end
  local n = tonumber(size)
  if n and n > 0 then return ("start %s %d"):format(tostring(name), n) end
  return "start " .. tostring(name)
end

--- The picked scenario's pure timeline at pos 0: the idle preview. A raising timeline is empty.
local function previewSteps(P, name, size, seed)
  local def = defOf(P, name)
  if not def then return {} end
  local ok, steps = pcall(def.timeline, def, { scenario = name, size = size, seed = seed or 0 })
  if ok and type(steps) == "table" then return steps end
  P.ctx.debug("preview timeline %s failed: %s", tostring(name), tostring(steps))
  return {}
end

--- The model the rows are composed from: idle (the picker's preview), stopping, or running.
local function model(P)
  local ctx, sim = P.ctx, P.sim
  local session = ctx.session()
  if not session then
    local name = chosen(P)
    local size = sizeFor(P, name)
    return { mode = "idle", scenario = name, size = size, steps = previewSteps(P, name, size), pos = 0 }
  end
  if ctx.stopping() then
    return { mode = "stopping", scenario = session.scenario, size = session.size,
      steps = previewSteps(P, session.scenario, session.size, session.seed), pos = 0 }
  end
  local st = sim:Status()
  return { mode = "running", scenario = session.scenario, size = session.size, session = session,
    steps = sim:Steps(), pos = st.pos or 0, ready = st.ready, busy = st.playing or st.settling }
end

local function stepLabel(P, step, i, steps)
  local text = ask(P, "stepLabel", step, i, steps)
  if text ~= nil then return tostring(text) end
  return tostring(step.label or step.kind)
end

--- A timeline row's state and whether it acts (the header's table).
local function stepState(m, i)
  if m.mode ~= "running" or not m.ready then return "locked", false end
  if i < m.pos then return "done", false end
  if i == m.pos then return (m.busy and "busy" or "done"), false end
  if i == m.pos + 1 then return "ready", true end
  return "locked", true                           -- ahead: a click-ahead target
end

local function startState(m)
  if m.mode == "idle" then
    if m.scenario == nil then return "locked", false end   -- nothing listed yet: nothing to start
    return "ready", true
  end
  if m.mode == "running" and m.ready then return "done", false end
  return "busy", false
end

local function startRow(P, m)
  local def = defOf(P, m.scenario)
  local state, act = startState(m)
  local tip = copyTip(tipList(P, "startTip"))
  if state == "done" and m.session then tip[#tip + 1] = ranLine(P, m.session.startedAt) end
  return { key = "start", index = 0, state = state, actionable = act, tip = tip,
    label = P.ctx.tr("PANEL_START"):format(m.scenario == nil and "" or tostring(def and def.label or m.scenario)),
    command = slashOf(P, startLine(m.scenario, m.size)) }
end

local function timelineRow(P, m, i, step)
  local state, act = stepState(m, i)
  local tip = copyTip(type(step) == "table" and tipList(P, "stepTip", step, i) or nil)
  if state == "done" and step.ranAt then tip[#tip + 1] = ranLine(P, step.ranAt) end
  return { key = "step", index = i, state = state, actionable = act, tip = tip,
    label = stepLabel(P, step, i, m.steps), command = slashOf(P, "step") }
end

local function stopRow(P, m, index)
  local running = m.mode == "running"
  return { key = "stop", index = index, state = running and "cancel" or "locked", actionable = running,
    tip = copyTip(tipList(P, "stopTip")), label = P.ctx.tr("PANEL_STOP"), command = slashOf(P, "stop") }
end

--- The panel's rows (pure): Start, one per step, Stop. A fresh list of fresh tables each call.
local function compose(P)
  local m = model(P)
  local rows = { startRow(P, m) }
  for i, step in ipairs(m.steps) do rows[#rows + 1] = timelineRow(P, m, i, step) end
  rows[#rows + 1] = stopRow(P, m, #m.steps + 1)
  return rows
end

--- A clicked row, already re-checked by the renderer against a fresh compose: Start and Stop are
--- the typed verbs; the ready row is the typed `step`; a row ahead is the internal click-ahead.
local function act(P, row)
  local sim, ctx = P.sim, P.ctx
  if row.key == "start" then
    local name = chosen(P)
    return sim:RunVerb(startLine(name, sizeFor(P, name)))
  end
  if row.key == "stop" then return sim:RunVerb("stop") end
  if row.index == (sim:Status().pos or 0) + 1 then return sim:RunVerb("step") end
  if type(ctx.runTo) ~= "function" then return false end
  local ok, code = ctx.runTo(row.index)
  if not ok and WHY[code] then ctx.print(ctx.tr(WHY[code])) end
  return ok
end

--- GameTooltip: the row's label, then each tip line ({left, right?} or a string).
local function showTip(owner, row)
  local tip = GameTooltip
  if type(tip) ~= "table" then return end
  tip:SetOwner(owner, "ANCHOR_RIGHT")
  tip:SetText(tostring(row.label))
  for _, line in ipairs(row.tip or {}) do
    if type(line) ~= "table" then
      tip:AddLine(tostring(line), 1, 1, 1)
    elseif line[2] ~= nil then
      tip:AddDoubleLine(tostring(line[1]), tostring(line[2]), 0.9, 0.82, 0.5, 1, 1, 1)
    else
      tip:AddLine(tostring(line[1]), 1, 1, 1)
    end
  end
  tip:Show()
end

-- ── the picker and the controls ─────────────────────────────────────────────────────────────

local REST, HOT, OFF = { 0.9, 0.9, 0.92 }, { 1, 0.82, 0 }, { 0.45, 0.45, 0.48 }

--- The library's minimal button: a Core-skinned box with a centered label, gold under the pointer,
--- and a GameTooltip naming the typed command (`typed()`). There is no d.panel.button (C.7).
local function makeButton(parent, width, text, onClick, typed)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width, BAR_H)
  core.ApplySkin(b)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.label:SetText(text)
  setColor(b.label, REST)
  b.__label = text
  hoverWhileDisabled(b)
  b:SetScript("OnEnter", function()
    if b:IsEnabled() then setColor(b.label, HOT) end
    showTip(b, { label = b.__label, tip = { { typed() } } })
  end)
  b:SetScript("OnLeave", function()
    setColor(b.label, b:IsEnabled() and REST or OFF)
    if type(GameTooltip) == "table" and GameTooltip.Hide then GameTooltip:Hide() end
  end)
  b:SetScript("OnClick", function() if b:IsEnabled() then onClick() end end)
  return b
end

local function setLabel(b, text)
  b.__label = text
  b.label:SetText(text)
end

local function setEnabled(b, on)
  if on then b:Enable() else b:Disable() end
  setColor(b.label, on and REST or OFF)
end

local function scenarioOptions(P)
  local out = {}
  for _, name in ipairs(P.ctx.d.scenarios.names) do
    local def = defOf(P, name)
    out[#out + 1] = { value = name, label = tostring(def and def.label or name) }
  end
  return out
end

local function sizeOptions(P, def)
  local out = { { value = 0, label = P.ctx.tr("RANDOM") } }
  local sizes = def and def.sizes
  for _, n in ipairs(type(sizes) == "table" and sizes or {}) do out[#out + 1] = { value = n, label = tostring(n) } end
  return out
end

local function bar(f)
  local b = CreateFrame("Frame", nil, f)
  b:SetSize(ROW_W, BAR_H)
  b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
  return b
end

local function buildPicker(P, f)
  local pk = bar(f)
  pk.scenario = W.Dropdown(pk, SCENARIO_W)
  pk.scenario:SetPoint("LEFT", pk, "LEFT", 0, 0)
  pk.scenario.onSelect = function(v)
    if defOf(P, v) then P.choice.scenario = v end
    P.refresh()
  end
  pk.size = W.Dropdown(pk, SIZE_W)
  pk.size:SetPoint("LEFT", pk, "LEFT", SCENARIO_W + BUTTON_GAP, 0)
  pk.size.onSelect = function(v)
    P.choice.size = tonumber(v) or 0
    P.refresh()
  end
  local function line()
    local name = chosen(P)
    return startLine(name, sizeFor(P, name))
  end
  pk.start = makeButton(pk, BUTTON_W, P.ctx.tr("START"),
    function() P.sim:RunVerb(line()) end, function() return slashOf(P, line()) end)
  pk.start:SetPoint("RIGHT", pk, "RIGHT", 0, 0)
  f.picker = pk
end

local function buildControls(P, f)
  local c = bar(f)
  local function verbOf(key)
    if key == "pause" then return c.pause.__verb or "pause" end
    return key
  end
  local list = { { "run", "RUN_ALL" }, { "pause", "PAUSE" }, { "restart", "RESTART" }, { "stop", "STOP" } }
  for i, spec in ipairs(list) do
    local key = spec[1]
    local b = makeButton(c, BUTTON_W, P.ctx.tr(spec[2]), function() P.sim:RunVerb(verbOf(key)) end,
      function() return slashOf(P, verbOf(key)) end)
    b:SetPoint("LEFT", c, "LEFT", (i - 1) * (BUTTON_W + BUTTON_GAP), 0)
    c[key] = b
  end
  f.controls = c
end

local function paintPicker(P, f)
  local pk = f.picker
  local name = chosen(P)
  local def = defOf(P, name)
  pk.scenario:SetOptions(scenarioOptions(P))
  if name == nil then pk.scenario:SetValue(nil, "") else pk.scenario:SelectValue(name) end
  pk.size:SetOptions(sizeOptions(P, def))
  pk.size:SelectValue(tonumber(P.choice.size) or 0)
  pk.size:SetShown(def ~= nil and def.sizes ~= nil)
  setEnabled(pk.start, name ~= nil)
end

local function paintControls(P, f)
  local c, st = f.controls, P.sim:Status()
  local left = st.ready and (st.pos or 0) < (st.total or 0)
  setEnabled(c.run, left and not st.playing)
  if st.paused then
    c.pause.__verb = "resume"
    setLabel(c.pause, P.ctx.tr("RESUME"))
    setEnabled(c.pause, left)
  else
    c.pause.__verb = "pause"
    setLabel(c.pause, P.ctx.tr("PAUSE"))
    setEnabled(c.pause, st.playing)
  end
  setEnabled(c.restart, true)
  setEnabled(c.stop, true)
end

--- The footer: the picker while idle, the controls while a session runs.
local function footer(P)
  return {
    height = BAR_H,
    build = function(f)
      buildPicker(P, f)
      buildControls(P, f)
    end,
    paint = function(f)
      local running = P.ctx.session() ~= nil and not P.ctx.stopping()
      -- A typed start swaps the picker out with no mouse press: its open menu would stay behind.
      if running and f.picker:IsShown() then closeMenu() end
      f.picker:SetShown(not running)
      f.controls:SetShown(running)
      if running then paintControls(P, f) else paintPicker(P, f) end
    end,
  }
end

-- ── placement (session-only: never written anywhere but this instance's memory) ──────────────

local function num(v) return type(v) == "number" and v or nil end

--- right, left or float for a panel `width` wide beside an anchor at left..right on a screen
--- `screen` wide. Unmeasurable geometry docks right.
local function dockSide(left, right, width, screen)
  left, right, screen = num(left), num(right), num(screen)
  if not (left and right and screen and screen > 0) then return "right" end
  if right + DOCK_GAP + width <= screen then return "right" end
  if left - DOCK_GAP - width >= 0 then return "left" end
  return "float"
end

local function screenWidth()
  return type(UIParent) == "table" and type(UIParent.GetWidth) == "function" and UIParent:GetWidth() or nil
end

local function edge(f, method)
  return type(f[method]) == "function" and num(f[method](f)) or nil
end

local function place(P, frame)
  frame:ClearAllPoints()
  local pt = P.point
  if pt then
    frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
    frame.__dock = "dragged"
    return
  end
  local anchor = ask(P, "anchorTo")
  local side = type(anchor) == "table"
    and dockSide(edge(anchor, "GetLeft"), edge(anchor, "GetRight"), WIDTH, screenWidth()) or "float"
  if side == "right" then
    frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", DOCK_GAP, 0)
  elseif side == "left" then
    frame:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -DOCK_GAP, 0)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", FLOAT_X, 0)
  end
  frame.__dock = side
end

--- On drag stop: remember where the player put it, for this session only.
local function remember(P, frame)
  local point, _, relPoint, x, y = frame:GetPoint(1)
  if type(point) ~= "string" then return end
  P.point = { point, type(relPoint) == "string" and relPoint or point, num(x) or 0, num(y) or 0 }
  frame.__dock = "dragged"
end

-- ── the members ──────────────────────────────────────────────────────────────────────────────

local function title(P)
  local t = panelField(P, "title")
  if type(t) == "function" then t = ask(P, "title") end
  if t ~= nil then return tostring(t) end
  return tostring(P.ctx.d.name) .. " - Simulation"
end

--- The renderer for one instance, built on the first Show.
local function renderer(P)
  if P.panel then return P.panel end
  local d = P.ctx.d
  P.panel = StepPanel({
    name = tostring(d.name) .. "SimPanel", addonName = tostring(d.name),
    title = function() return title(P) end,
    rows = function() return compose(P) end,
    onClick = function(row) act(P, row) end,
    check = panelField(P, "check"),
    tooltip = showTip,
    footer = footer(P),
  })
  return P.panel
end

local function hookDrag(P, frame)
  if P.hooked or type(frame.HookScript) ~= "function" then return end
  P.hooked = true
  frame:HookScript("OnDragStop", function() remember(P, frame) end)
end

local function installMembers(sim, P)
  function sim.ShowPanel()
    if P.ctx.d.isStoodDown() then return false end
    local panel = renderer(P)
    local frame = panel.Frame()
    if not frame then return false end
    hookDrag(P, frame)
    place(P, frame)
    panel.Show()
    return true
  end

  function sim.HidePanel()
    if not P.panel then return end
    P.panel.Hide()
    closeMenu()                                    -- no orphaned dropdown menu
  end

  function sim.IsPanelShown() return P.panel ~= nil and P.panel.IsShown() end

  function sim.TogglePanel()
    if sim:IsPanelShown() then
      sim:HidePanel()
      return false
    end
    return sim:ShowPanel()
  end

  function sim.RefreshPanel() P.refresh() end

  function sim.ResetPanelPosition()
    P.point = nil
    local frame = P.panel and P.panel.Frame()
    if frame and P.panel.IsShown() then place(P, frame) end
  end

  function sim.PanelRows() return compose(P) end
end

--- Attach the panel to one instance. Called by Sim:New with the instance and the handshake's
--- internal ctx (Sim.lua); overwrites the shell's panel fallbacks.
--- `first` only seeds the choice and may be nil (scenarios filled after New); every read of the
--- choice goes through chosen(P), which falls back to the live first name (minor 2).
function lib.__AttachPanel(sim, ctx)
  local first = ctx.d.scenarios.names[1]
  local P = { sim = sim, ctx = ctx, choice = { scenario = first, size = 0 }, point = nil }
  -- Repaint a shown panel. While a session runs the picker follows its scenario, so the preview
  -- after a stop is the scenario that just ran.
  function P.refresh()
    local session = ctx.session()
    if session and defOf(P, session.scenario) then P.choice.scenario = session.scenario end
    if P.panel and P.panel.IsShown() then P.panel.Refresh() end
  end
  installMembers(sim, P)
  sim:AddListener(function() P.refresh() end)
end
