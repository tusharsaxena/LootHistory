local _, NS = ...

-- modules/SimPanel.lua: the simulation step panel's LootHistory half (LootHistory#37, LibKa0s#53
-- #54; req-lh-sim.md §6). The panel itself (its rows, states, colors, run controls, scenario
-- picker, click-ahead, placement and stand-down refusal) is LibKa0s-Sim-1.0's
-- (libs/LibKa0s/SimPanel.lua); this file says what LootHistory's steps are called and what their
-- tooltips say, and keeps the History window's simulation marker in step with the session.
--
-- NS.SimHost.PANEL is the Sim:New descriptor's `panel` (modules/Sim.lua creates the table and
-- passes it; this file fills it in place at load, the way modules/SimScenario.lua fills the
-- scenarios; the library reads each field when it draws, so nothing is captured early):
--   title      `Ka0s Loot History - Simulation`
--   stepLabel  the step's own label (`Kill: Rookery Bat`, `Merchant: sell 3`), which the library
--              also prints in its `Simulation step 2 of 7: ...` line
--   stepTip    what the step injects, and once it has run, the rows it recorded
--   startTip, stopTip   what Start and Stop do
--   anchorTo   the History window while it is shown (the panel docks beside it), else nil
--   check      the catalog's `confirm` tick, the done mark (declared on the CLAUDE.md icons line)
-- No `button`, no `tooltip` (the library's own, OWNER_SCOPE C.7) and no `store`: the panel's
-- position is session-only (C.11), held in the library instance's memory, so a simulation writes
-- nothing to SavedVariables.
--
-- The marker (preview-mode, H8): a Sim listener repaints the History window's title badge, strip
-- and footer on every transition (start, ready, step, run, pause, stop), so `SIMULATION` shows
-- from the start to the stop and goes with it (modules/Browser.lua, B:UpdateTestStrip and
-- B:UpdateFooter).

NS.SimHost = NS.SimHost or {}
local Host = NS.SimHost
local L = NS.L

Host.PANEL = Host.PANEL or {}
local F = Host.PANEL

-- The most rows a done step's tooltip names one by one; the rest are counted.
local TIP_ROWS = 4

local START_TIP = {
  { L["Builds"], L["an invented world: bags, bank, mail, auctions"] },
  { L["Records"], L["into this session only: nothing is saved"] },
  { L["Refused"], L["in combat, an instance, a group or test mode"] },
}
local STOP_TIP = {
  { L["Ends"], L["the simulation and its session rows"] },
  { L["Then"], L["a real rescan: what changed meanwhile is untracked"] },
}

-- The rows a step recorded: from the history index its play began at (Host.Play's wrapper in
-- modules/Sim.lua stamps `lhFrom`) up to where the next step began, or to now for the last one
-- played. The gate holds the next step until the ledger settles, so every row of a step lands
-- before the next one starts. A `/lh sim loot` verb closes the window first (`lhTo`, stamped by
-- runLoot in modules/Sim.lua), so the verb's ad hoc rows are never counted as the step's.
local function recorded(step, i)
  local from = step.lhFrom
  if type(from) ~= "number" then return nil end
  local history = NS.Database:History()
  local to = step.lhTo
  if type(to) ~= "number" then
    local nextStep = NS.Sim:Steps()[i + 1]
    to = (type(nextStep) == "table" and type(nextStep.lhFrom) == "number") and nextStep.lhFrom or #history
  end
  local rows = {}
  for k = from + 1, to do rows[#rows + 1] = history[k] end
  return rows
end

local function describe(r)
  local name = r.itemName or r.currencyName or NS.Util.RowKind(r)
  local label = NS.Constants.SourceLabel[r.source] or tostring(r.source)
  return ("%s %s x%d (%s)"):format(NS.Util.RowDir(r) == "OUT" and "-" or "+", tostring(name), r.quantity or 1, label)
end

--- A timeline step's name (the descriptor's `panel.stepLabel`).
--- @param step table { kind, label }
--- @return string
function Host.StepLabel(step)
  return step.label or step.kind
end

--- A timeline step's tooltip lines (the descriptor's `panel.stepTip`): what it injects, then, once
--- it has run, how many rows it recorded and the first few of them.
--- @param step table
--- @param i number
--- @return table lines
function Host.StepTip(step, i)
  local lines = {}
  for j, line in ipairs(step.tip or {}) do lines[#lines + 1] = { j == 1 and L["Injects"] or " ", line } end
  local rows = step.ranAt and recorded(step, i)
  if rows then
    lines[#lines + 1] = { L["Recorded"], L["%d rows"]:format(#rows) }
    for k = 1, math.min(#rows, TIP_ROWS) do lines[#lines + 1] = describe(rows[k]) end
    if #rows > TIP_ROWS then lines[#lines + 1] = L["and %d more"]:format(#rows - TIP_ROWS) end
  end
  return lines
end

F.title = function() return L["%s - Simulation"]:format(NS.BRAND) end
F.stepLabel = Host.StepLabel
F.stepTip = Host.StepTip
F.startTip = START_TIP
F.stopTip = STOP_TIP
-- The window while it is shown, so the panel docks beside it and never beside a hidden frame.
F.anchorTo = function()
  local w = NS.Browser and NS.Browser:GetWindow()
  if w and w:IsShown() then return w end
  return nil
end
F.check = NS.Icon("confirm")

-- The marker follows the session: every transition repaints the badge, the strip and the footer.
NS.Sim:AddListener(function()
  local B = NS.Browser
  if not B then return end
  B:UpdateTestStrip()
  B:UpdateFooter()
end)
