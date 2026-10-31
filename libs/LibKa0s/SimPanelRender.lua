-- LibKa0s-Sim-1.0 — the step panel's renderer: the window, its rows and their chrome, with no
-- semantics of its own. SimPanel.lua is the adapter that puts Sim's on it.
--
-- Peeled out of SimPanel.lua at its minor 9, unchanged (LK-M2-PEEL of Ka0sAddonsCommonTasks
-- docs/2026-10-31-FINDINGS_REMEDIATION), on the seam CLAUDE.md's band census named for that file. The
-- history is SimPanel.lua's header, and so is why the renderer is private (LK-11 outcome B).
--
-- WHAT CROSSES THE CUT. SimPanel.lua loads first and publishes `lib.__panelKit`, the six locals the
-- adapter and the renderer share (it sizes its picker from them at file load); this file publishes
-- the renderer, `lib.__StepPanel`, which the adapter reads on the first Show. A copy without this
-- file has no panel: `lib.__AttachPanel` attaches nothing and the shell's fallbacks answer.
--
-- A file of `LibKa0s-Sim-1.0`, paired on the shell's minor, with the same attach floor as
-- SimPanel.lua: Core 9 or newer and Widgets present.

local lib = LibStub and LibStub("LibKa0s-Sim-1.0", true)
if not lib then return end

local core = LibStub("LibKa0s-Core-1.0", true)
local W = LibStub("LibKa0s-Widgets-1.0", true)
local NEEDS_CORE = 9
if not core or (core.MINOR or 0) < NEEDS_CORE or not W or not lib.__panelKit then return end

-- Minor 1: the renderer section, moved here unchanged from SimPanel.lua (its minor 9).
local RENDER_MINOR = 1

-- Read at call time and guarded: an older Core without RaiseStaticPopups raises nothing.
local function raisePopups()
  if type(core.RaiseStaticPopups) == "function" then core.RaiseStaticPopups() end
end

-- Paired on the SHELL's minor as well as this file's own, as SimTimeline.lua is.
if lib.__renderMinor and lib.__renderMinor >= RENDER_MINOR
  and lib.__renderShellMinor == lib.MINOR then return end
lib.__renderMinor      = RENDER_MINOR
lib.__renderShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.SimPanelRender = RENDER_MINOR

local type, tostring, ipairs = type, tostring, ipairs

local kit = lib.__panelKit
local ROW_W, PAD, DEFAULT, setColor = kit.ROW_W, kit.PAD, kit.DEFAULT, kit.setColor
local closeMenu, hoverWhileDisabled = kit.closeMenu, kit.hoverWhileDisabled

-- ════════════════════════════════════════════════════════════════════════════════════════════
-- THE RENDERER (`lib.__StepPanel` is its internal test seam)
-- ════════════════════════════════════════════════════════════════════════════════════════════
--
-- Render-only: it owns the shape and none of the semantics. A row arrives as data,
-- `{ key?, label, command, state, actionable, tip? }`, from `d.rows()`; `actionable` is the
-- caller's answer and never derived from `state` here. A click re-reads `rows()` and re-checks
-- `actionable` at the clicked index before `d.onClick(row, index)`. No state logic, no slash
-- knowledge, no saved position: the panel sits at CENTER -320 at build, and SimPanel.lua's adapter
-- positions it. Resizing is width-only through Core.MakeResizable (guarded), and because that is
-- call-once and pins a widthOnly frame's height bounds at the height it had then, every Refresh
-- where the row count moved re-pins them (OWNER_SCOPE C.5), guarded the way Core's setBounds is.
--
-- Perf's geometry, palette and command color, copied from PerfPanel.lua on purpose.
local ROW_H, GAP = 22, 4
local DOT_X, DOT = 8, 8        -- column 1: status dot
local LABEL_X   = 26           -- column 2: step name
local CMD_PAD   = 10           -- column 3: slash command, right-aligned
local LABEL_GAP = 8            -- the label stops this far short of the command column
local TITLE_H = 24

local LOCKED_DOT_ALPHA = 0.35
local CHECK = 12                                   -- the done mark, centered over the dot
local CENTER_X = -320                              -- Perf's spot, set once at build

-- THE SKIN OWNER (minor 7): the renderer's `addonName` (the adapter's `name`, the close mark's
-- folder) once it is a registered LibKa0s-Skin-1.0 owner (Core's `__SkinFacade`, at build). Its
-- window paints through `Core.ApplySkin(frame, nil, owner)`, each button box through `S.Shell` (no
-- top bar), and every color below from its tokens (`pal`, the frame's `__pal`), refilled on each
-- switch. Any other panel draws the constants, call for call; Ka0s Default's tokens equal them.
local TOKENS = { done = "sem.on", used = "sem.on", ready = "sem.stepReady", busy = "sem.stepBusy",
  locked = "sem.stepLocked", cancel = "sem.stepCancel", cmd = "text.faint", hover = "text.accent",
  hoverCancel = "sem.stepCancelHot", rest = "sem.stepReady", hot = "text.accent", off = "text.faint",
  tipKey = "gtip.title", tipValue = "gtip.value" }
local function fillPalette(pal, S)
  for name, token in pairs(TOKENS) do pal[name] = S.Token(token) or DEFAULT[name] end
  return pal
end

local function facadeOf(owner)
  return type(core.__SkinFacade) == "function" and core.__SkinFacade(owner) or nil
end

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
  frame:SetToplevel(true)
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", raisePopups) end
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
  local pal = DEFAULT
  local function colorOf(state) return pal[state] or pal.locked end

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
    if row.actionable then setColor(b.text, row.state == "cancel" and pal.hoverCancel or pal.hover) end
    if row.tip ~= nil and type(d.tooltip) == "function" then
      b.__tipShown = true
      d.tooltip(b, row, pal)
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
    b.cmd = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if frame.__skin then frame.__skin.Font(b.cmd) end   -- minor 8: the skin's body face, recorded
    b.cmd:SetPoint("RIGHT", b, "RIGHT", -CMD_PAD, 0)
    b.cmd:SetJustifyH("RIGHT")
    setColor(b.cmd, pal.cmd)
    -- One line, bounded on both sides (LK-91), so a long label truncates with an ellipsis instead
    -- of running under the command; the right bound is set by paintRow (anchorLabel).
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if frame.__skin then frame.__skin.Font(b.text) end
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b.__index = index
    hoverWhileDisabled(b)
    b:SetScript("OnEnter", onEnter)
    b:SetScript("OnLeave", onLeave)
    b:SetScript("OnClick", onClick)
    return b
  end

  --- Bound the label: LEFT at LABEL_X, RIGHT LABEL_GAP short of the command's natural-width left
  --- edge, or at the row's right inset when the row has no command. Anchors rather than a width, so
  --- a resize moves the bound with the row. Re-anchored only when the command appears or goes.
  local function anchorLabel(b, command)
    local toCmd = command ~= nil and command ~= ""
    if b.__labelToCmd == toCmd then return end
    b.__labelToCmd = toCmd
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", b, "LEFT", LABEL_X, 0)
    if toCmd then
      b.text:SetPoint("RIGHT", b.cmd, "LEFT", -LABEL_GAP, 0)
    else
      b.text:SetPoint("RIGHT", b, "RIGHT", -CMD_PAD, 0)
    end
  end

  local function paintRow(b, row)
    b.__row = row
    local c = colorOf(row.state)
    anchorLabel(b, row.command)
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

  --- An owned panel: the window through the facade; each switch refills, recolors and repaints.
  local function adopt(S)
    core.ApplySkin(frame, nil, d.addonName)
    S.OnLooksChanged(function()
      fillPalette(pal, S)
      for _, b in ipairs(buttons) do setColor(b.cmd, pal.cmd) end
      panel.Refresh()
    end)
  end

  local function build()
    local n = #readRows(d)
    local S = facadeOf(d.addonName)
    if S then pal = fillPalette({}, S) end
    frame = CreateFrame("Frame", d.name, UIParent, "BackdropTemplate")
    frame.__pal, frame.__skin = pal, S
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
    if S then adopt(S) else core.ApplySkin(frame) end
    frame:Hide()
    -- Escape hides the frame directly (CloseSpecialWindows), never through HidePanel.
    if type(frame.HookScript) == "function" then frame:HookScript("OnHide", closeMenu) end
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, d.name) end
    -- Guarded: the no-MakeResizable fixture (tests/test_resize_windows.lua) is today's fixed panel.
    if type(core.MakeResizable) == "function" then
      core.MakeResizable(frame, {
        minWidth = minW, minHeight = heightFor(n), widthOnly = true, onResize = stretchRows,
        owner = S and d.addonName or nil,   -- minor 8: the grip wears the skin (Core minor 14)
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
