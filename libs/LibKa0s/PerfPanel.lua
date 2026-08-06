-- LibKa0s-Perf-1.0 — the clickable step panel for a perf run.
--
-- Part of the Perf module rather than a major of its own: it is the same feature, and splitting it
-- across LibStub majors would let a host end up with a panel from one copy and a probe from another.
-- The guard below is the standard multi-file idiom — if an older copy of Perf.lua won the LibStub
-- race, or a newer panel is already attached, this file is a no-op.

local lib = LibStub and LibStub("LibKa0s-Perf-1.0", true)
if not lib then return end
-- Core is guaranteed present here: Perf.lua refuses to register without it, so reaching this line
-- at all means the lookup above already succeeded on a Core-backed probe.
local core = LibStub("LibKa0s-Core-1.0", true)
local PANEL_MINOR = 3
-- Paired on the PROBE's minor as well as the panel's own. The panel counter alone is not enough:
-- two vendored copies can ship the same panel minor over different Perf.lua minors, and then the
-- higher probe wins the LibStub race while the first-loaded copy's panel stays attached to it —
-- exactly the mismatched pairing the single-major design is supposed to make impossible. Recording
-- which probe the attached panel was built against makes a copy re-attach whenever the probe
-- underneath it changed.
if lib.__panelMinor and lib.__panelMinor >= PANEL_MINOR
  and lib.__panelProbeMinor == lib.MINOR then return end
lib.__panelMinor = PANEL_MINOR
lib.__panelProbeMinor = lib.MINOR

-- Publish the live panel version next to the probe's (Perf.lua's MODULES table). The dunder fields
-- above are the guard's own bookkeeping; this is the readable answer to "what am I running?".
lib.MODULES = lib.MODULES or {}
lib.MODULES.PerfPanel = PANEL_MINOR

-- Three columns: status dot, step, slash command. The command column is the point — it teaches the
-- typed form while you click, so the panel is a crutch you can stop needing.
local ROW_W, ROW_H, GAP = 360, 22, 4
local DOT_X, DOT = 8, 8        -- column 1: status dot
local LABEL_X   = 26           -- column 2: step name
local CMD_PAD   = 10           -- column 3: slash command, right-aligned
local TITLE_H = 24
local PAD = 8

-- Per-state color, used for both the row's text and its status dot. `busy` deliberately shares the
-- gold of an interactive control: the step IS happening, and graying it out would read as "nothing
-- is going on" during the one phase where the user most needs to know the addon is recording.
local COLORS = {
    done   = { 0.30, 0.85, 0.30 },
    -- Same green as `done`: it has been run. Still clickable, because re-reading a report costs
    -- nothing and is regularly wanted twice.
    used   = { 0.30, 0.85, 0.30 },
    ready  = { 0.90, 0.90, 0.92 },
    busy   = { 1.00, 0.82, 0.00 },
    locked = { 0.40, 0.40, 0.42 },
    -- Muted red rather than a warning red: cancel is always available, so a shade that shouts would
    -- shout on every frame of every run.
    cancel = { 0.80, 0.32, 0.32 },
}

-- Command column, dimmer than its row so it reads as reference rather than as another control.
local CMD_COLOR = { 0.45, 0.45, 0.48 }

-- Ordered, and the order IS the workflow. `key` matches a field of Progress(); `command` is the
-- sub-verb the host's slash handler will be given.
local STEPS = {
  { key = "start",    string = "STEP_START",     command = "perf start"     },
  { key = "measureA", string = "STEP_MEASURE_A", command = "perf measure a" },
  { key = "measureB", string = "STEP_MEASURE_B", command = "perf measure b" },
  { key = "finish",   string = "STEP_FINISH",    command = "perf finish"    },
  { key = "report",   string = "STEP_REPORT",    command = "perf report"    },
  { key = "dump",     string = "STEP_DUMP",      command = "perf dump"      },
  -- Outside the linear progression: clickable for as long as there is a run to abandon, and
  -- doubles as nothing once there is not — an live-looking button that discards nothing is just a
  -- way to worry someone.
  { key = "cancel",   string = "STEP_CANCEL",    command = "perf cancel"    },
}

--- Attach the panel closures to one instance. Called at the end of lib:New, so every host gets its
--- own frame — created lazily, on first show, under that host's ownership.
function lib.__AttachPanel(P, d, tr, runCommand)
  local frame
  local decorate = type(d.decorate) == "function" and d.decorate or nil

  -- `string` travels with the step and `label` is re-resolved on every repaint. A host on the Ka0s
  -- standard populates its locale table from a separate file, which may well load after :New() runs
  -- — resolving once here froze every row to the built-in English.
  P.STEPS = {}
  for i, s in ipairs(STEPS) do
    P.STEPS[i] = { key = s.key, string = s.string, label = tr(s.string), command = s.command }
  end

  local function setColor(fs, state)
    local c = COLORS[state] or COLORS.locked
    fs:SetTextColor(c[1], c[2], c[3])
  end

  --- Current state of one step, straight from the probe. Nil-safe so the panel can exist before a
  --- run.
  function P.PanelStateOf(key)
    if not P.Progress then return "locked" end
    return P.Progress()[key] or "locked"
  end

  --- Can this row be clicked? `ready` is the one legal next step, `cancel` is available for as long
  --- as there is a run to abandon, and `used` is a review action that stays repeatable.
  function P.PanelIsActionable(key)
    local state = P.PanelStateOf(key)
    return state == "ready" or state == "cancel" or state == "used"
  end

  --- Build one step row. The click handler re-checks PanelIsActionable rather than trusting the
  --- button's enabled state: the mock (and a sufficiently determined user) can fire a script
  --- directly, and a step that runs out of order corrupts the run it was meant to protect.
  local function makeStepButton(parent, step, index)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ROW_W, ROW_H)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -(TITLE_H + PAD + (index - 1) * (ROW_H + GAP)))

    -- Status dot drawn with SetColorTexture rather than a glyph or an art file. A text tick (U+2713)
    -- rendered as tofu in the default font, and any Interface\\... path is a guess that fails
    -- silently as a green box. A solid color texture has no dependency and cannot not render.
    local dot = b:CreateTexture(nil, "ARTWORK")
    dot:SetSize(DOT, DOT)
    dot:SetPoint("LEFT", b, "LEFT", DOT_X, 0)
    b.dot = dot

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", b, "LEFT", LABEL_X, 0)
    fs:SetJustifyH("LEFT")
    b.text = fs

    local cmd = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cmd:SetPoint("RIGHT", b, "RIGHT", -CMD_PAD, 0)
    cmd:SetJustifyH("RIGHT")
    cmd:SetText(P.slash .. " " .. step.command)
    cmd:SetTextColor(CMD_COLOR[1], CMD_COLOR[2], CMD_COLOR[3])
    b.cmd = cmd

    b.step = step

    b:SetScript("OnEnter", function()
        local state = P.PanelStateOf(step.key)
        if state == "cancel" then fs:SetTextColor(1.00, 0.45, 0.45)
        elseif state == "ready" or state == "used" then fs:SetTextColor(1, 0.82, 0) end
    end)
    b:SetScript("OnLeave", function() setColor(fs, P.PanelStateOf(step.key)) end)
    b:SetScript("OnClick", function()
        if not P.PanelIsActionable(step.key) then return end
        runCommand(step.command)
        P.RefreshPanel()
    end)
    return b
  end

  local function EnsureFrame()
    if frame then return frame end
    if type(CreateFrame) ~= "function" then return nil end

    local name = d.name .. "PerfPanel"
    local height = TITLE_H + PAD * 2 + #P.STEPS * (ROW_H + GAP)
    frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(ROW_W + PAD * 2, height)
    frame:SetPoint("CENTER", -320, 0)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOP", 0, -6)
    title:SetText(P.title .. tr("PANEL_TITLE_SUFFIX"))
    frame.title = title

    -- A host that draws its own chrome keeps drawing it: `decorate` gets the frame plus a small API
    -- to wire a close control to, and takes precedence. A host that passes none now gets Core's
    -- close button rather than nothing — the same × the debug console wears, from the same factory,
    -- so the two windows cannot drift. The two paths are exclusive: running both would leave a host
    -- with its own close button and ours stacked on the same corner.
    if decorate then
      decorate(frame, {
        Show = P.ShowPanel, Hide = P.HidePanel, Toggle = P.TogglePanel,
        TITLE_H = TITLE_H, PAD = PAD, ROW_W = ROW_W,
      })
    else
      local close = core.MakeCloseButton(frame, P.HidePanel)
      if close then
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -(TITLE_H - 18) / 2)
        frame.closeButton = close
      end
    end

    frame.buttons = {}
    for i, step in ipairs(P.STEPS) do
      frame.buttons[step.key] = makeStepButton(frame, step, i)
    end

    core.ApplySkin(frame)

    frame:Hide()
    -- Esc closes it, like a debug console. Hiding is non-destructive, so this is safe to wire.
    if type(UISpecialFrames) == "table" then
      table.insert(UISpecialFrames, name)
    end
    return frame
  end

  --- Repaint every row from the probe's current state. Cheap and idempotent, so it is safe to call
  --- on every transition rather than trying to work out which row changed.
  function P.RefreshPanel()
    if not frame then return end
    for _, step in ipairs(P.STEPS) do
      local b = frame.buttons[step.key]
      if b then
        local state = P.PanelStateOf(step.key)
        step.label = tr(step.string)
        b.text:SetText(step.label)
        setColor(b.text, state)
        -- The dot carries the state at a glance: green behind you, gold on the step that is
        -- actually happening, gray ahead. Dimmed while locked so the eye skips it.
        local c = COLORS[state] or COLORS.locked
        if b.dot.SetColorTexture then
          b.dot:SetColorTexture(c[1], c[2], c[3], state == "locked" and 0.35 or 1)
        end
        if P.PanelIsActionable(step.key) then b:Enable() else b:Disable() end
        -- What was actually rendered, for the headless suite. The mock's FontString stub cannot be
        -- asked (it returns the parent frame, and defining SetText on it would break the other
        -- suites' SetText spies — see the note in tests/wow_mock.lua).
        b.__label, b.__state, b.__command = step.label, state, P.slash .. " " .. step.command
      end
    end
  end

  function P.ShowPanel()
    local f = EnsureFrame()
    if not f then return end
    P.RefreshPanel()
    f:Show()
  end

  function P.HidePanel() if frame then frame:Hide() end end
  function P.IsPanelShown() return (frame and frame:IsShown()) and true or false end

  function P.TogglePanel()
    if P.IsPanelShown() then P.HidePanel() else P.ShowPanel() end
  end

  -- Test seam: reach the buttons without a live client.
  function P.__panel() return frame end
end
