-- LibKa0s-Options-1.0 — the Master controls composer: O.MasterControls, the canonical first tab
-- (options-ui-§15), and the button pair that closes it.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF OptionsCompose.lua ───────────────────────────
--
-- Because of `layout-§1`. LibKa0s#97's skin companions took OptionsCompose.lua to 1217 lines, past
-- the 1150-line trigger its census entry set, and the owner ruled the band files peeled (FU-LK-COMPOSE
-- of Ka0sAddonsCommonTasks docs/2026-11-21-SYNC_FOLLOWUPS). The Master controls block, the seam that
-- entry named, moved here at compose minor 21, unchanged: the Lock frame and Sim mode words, the
-- notes, THE SIM ROW (`simHooks`, `emitSim`, `armSimShow`), `masterTail`, `masterRows`,
-- `masterButtons` and `O.MasterControls` itself, the same member with the same spec. Its history is
-- OptionsCompose.lua's header. It is NOT a major of its own: it is part of `LibKa0s-Options-1.0`,
-- paired on the Options shell's minor as every secondary file of the major is, so a block from one
-- vendored copy never pairs with a shell from another without saying so.
--
-- WHAT CROSSES THE CUT. OptionsCompose.lua loads first and publishes `lib.__composeKit` (the row
-- emitter and the extra rows, the read-only EMPTY, `shallow`, the Reset all settings wording and the
-- three Master controls constants, which the instance also publishes); its `lib.__AttachCompose`
-- calls `lib.__AttachComposeMaster(O, desc)` last, so the shell's attach list does not change. A
-- payload without this file has every other composer and no O.MasterControls.
--
-- Depends on LibStub, on the Options shell and on OptionsCompose.lua.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib or type(lib.__composeKit) ~= "table" then return end

local MASTER_MINOR = 1
-- Minor 1: the Master controls block of compose minor 20, moved unchanged (compose minor 21).
-- Paired on the SHELL's minor as well as this file's own, as OptionsCompose.lua is.
if lib.__masterMinor and lib.__masterMinor >= MASTER_MINOR
  and lib.__masterShellMinor == lib.MINOR then return end
lib.__masterMinor      = MASTER_MINOR
lib.__masterShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsComposeMaster = MASTER_MINOR

local kit = lib.__composeKit
local EMPTY, shallow, emit, appendExtra = kit.EMPTY, kit.shallow, kit.emit, kit.appendExtra
local resetAllTooltip, MASTER_GROUP = kit.resetAllTooltip, kit.MASTER_GROUP
local VISIBILITY_VALUES, VISIBILITY_SORT = kit.VISIBILITY_VALUES, kit.VISIBILITY_SORT

-- The Lock frame tooltip for an addon whose unlocked view IS its test mode (compose minor 9,
-- options-ui-§15). The standard quotes this sentence, so it is written once, here, and a host
-- passes `lockIsPreview` rather than a copy of it.
local LOCK_PREVIEW_TIP = "Stop the frame being dragged. While it is unlocked the display shows placeholder content, so it can be seen and placed; this is the addon's test mode."

--- `text` with the host's one-sentence note after it, or `text` alone when the note is not a
--- non-empty string. The note never replaces the canonical words; it only follows them.
local function withNote(text, note)
  if type(note) == "string" and note ~= "" then return text .. " " .. note end
  return text
end

--- Emit one canonical Master controls row and append the host's note for that LEAF -- the canonical
--- name, never the `keys` rename. An omitted row takes no note.
local function emitNoted(ms, rows, notes, leaf, row)
  local out = emit(ms, rows, leaf, row)
  if out then out.tooltip = withNote(out.tooltip, notes[leaf]) end
  return out
end

-- THE SIM ROW (compose minor 19, options-ui-§15). An addon with a simulation shows a Sim mode checkbox
-- beside Test mode. The host hands in the pair its launcher already carries (Launcher minor 7):
-- `isSimMode()`, whether the sim runs, and `toggleSim()`, the act of its `/<slash> sim` verb, so the
-- box, the launcher's Sim mode entry and the slash verb are one act. The row is a SESSION row with
-- the host's hooks as its own get / set: nothing is stored, and a reload ends the sim as it always
-- did. Its set takes a VALUE, never a bare toggle: Reset all settings walks the session rows and
-- writes each one's default, so a set that toggled unconditionally would START a sim on a reset.
-- set(v) calls toggleSim() only when v differs from isSimMode(), and the flow engine's write then
-- re-reads the row (`set` -> RefreshScalars), so a start the host refused -- in combat, or a prepare
-- step that failed -- leaves the box unticked rather than echoing the click.
local SIM_TIP = "Run the addon's simulation, the same as its sim slash command, so the display plays scripted data. Untick it to stop the simulation. Session state: a reload ends it."

--- The host's two sim hooks, or nil unless BOTH are functions: a box that could tick but not read,
--- or read but not act, is a dead control that looks alive.
local function simHooks(spec)
  if type(spec.isSimMode) == "function" and type(spec.toggleSim) == "function" then
    return spec.isSimMode, spec.toggleSim
  end
end

--- Emit the Sim mode row when the host passed its hooks, at `startsLine` (true or nil). The get / set
--- are attached AFTER emit, so a `bind` spec cannot turn them into a record field's.
local function emitSim(ms, rows, notes, spec, startsLine)
  local isSim, toggle = simHooks(spec)
  if not isSim then return nil end
  local row = emitNoted(ms, rows, notes, "simMode", {
    path = spec.simPath or "state.sim",
    type = "bool", label = "Sim mode", tooltip = SIM_TIP,
    sessionOnly = true, default = false, startsLine = startsLine,
  })
  if not row then return nil end
  local function get() return isSim() and true or false end
  row.get = get
  row.set = function(value)
    if (value and true or false) ~= get() then toggle() end
  end
  return row
end

--- Arm `ctx`'s panel to refresh its widgets in place on every show, once per ctx (THE SIM ROW). A
--- ctx with no hookable panel, the button recorder's `{}` among them, is left alone.
local function armSimShow(O, ctx)
  local panel = type(ctx) == "table" and rawget(ctx, "panel") or nil
  if not (panel and panel.HookScript) or rawget(ctx, "__simShowArmed") then return end
  rawset(ctx, "__simShowArmed", true)
  panel:HookScript("OnShow", function()
    if O.RefreshPanel then pcall(O.RefreshPanel, ctx, false) end
  end)
end

--- The Master controls tab's last rows, Minimap button, Test mode and Sim mode beside Test mode,
--- appended to `rows` (a split of `masterRows`, v1.85.0's `R6-REL2` re-cut, to keep it at CCN 15;
--- no behavior change). `consoleRow` and `simBesideLock` are the rows `masterRows` emitted.
local function masterTail(ms, rows, notes, spec, consoleRow, simBesideLock)
  -- THE FOURTH LINE OF THE CANONICAL SET: [Minimap button] [Test mode] (options-ui-§15, compose
  -- minor 7). Which of the two opens the line is not a preference and not a tidy-up: EVERY addon
  -- has a minimap button and only SOME have a test mode, so the always-present row takes column 1
  -- and the optional one pairs beside it. Put the other way round, an addon with no test mode
  -- draws a hole in the first column with a lone control to its right.
  --
  -- Both are opt-in HERE even so, because this composer cannot know whether the host has adopted
  -- the launcher yet (launcher-§5) -- and either row alone must still open its own line, which is
  -- what `startsLine` below is computed from rather than declared.
  local minimapRow
  if spec.minimapPath then
    -- STORED, not session: `sessionOnly` is deliberately absent. The console and the test mode are
    -- both things a reload ends; a hidden minimap button is furniture the player arranged, and
    -- launcher-§3 puts it in the GLOBAL store precisely so it survives a profile switch and
    -- options-ui-§12's reset. The default is the row's own sense -- SHOWN -- and the host inverts
    -- onto LibDBIcon's `hide` at its write seam.
    minimapRow = emitNoted(ms, rows, notes, "minimap", {
      path = spec.minimapPath,
      type = "bool", label = "Minimap button",
      tooltip = "Show this addon's button on the minimap.",
      default = true,
      -- The frameless packing: beside Debug console when Lock frame is omitted and the console
      -- row was emitted; otherwise the first column of its own line, as at minor 7. Sim mode beside
      -- Lock frame moves the console to the first column, so Minimap button packs beside it too.
      startsLine = not ((ms.omit.locked or simBesideLock) and consoleRow) or nil,
    })
  end
  -- The test mode, for an addon whose preview has a switch of its own (options-ui-§15, compose
  -- minor 6). Session state like the console row, and absent unless the host names its path: a
  -- checkbox shows whether the mode is on, which a button beside the resets could not.
  local testRow
  if spec.testModePath then
    testRow = emitNoted(ms, rows, notes, "testMode", {
      path = spec.testModePath,
      type = "bool", label = "Test mode",
      tooltip = "Show placeholder content, so the display can be seen and placed without waiting for the real thing.",
      -- `or nil` rather than `false`: a row that pairs beside Minimap button carries no
      -- `startsLine` key at all, which is the shape every other second-column row in this file
      -- has, and the shape the flow engine's `opensLine` reads. It opens its own line when there
      -- is no minimap row, or when the minimap row has packed beside the console.
      sessionOnly = true, startsLine = (not minimapRow or not minimapRow.startsLine) or nil,
    })
  end
  -- Sim mode BESIDE TEST MODE (compose minor 19): straight after it, pairing when Test mode opened
  -- its own line and opening the next one when Test mode sits in the second column. With no Test
  -- mode row and no Lock frame to pair with, it takes Test mode's slot, by Test mode's own rule.
  if not simBesideLock then
    local opens
    if testRow then opens = not testRow.startsLine or nil
    else opens = (not minimapRow or not minimapRow.startsLine) or nil end
    emitSim(ms, rows, notes, spec, opens)
  end
end

--- The canonical rows of the Master controls tab, in order, then the host's extras.
---
--- THE FRAMELESS PACKING (compose minor 9, options-ui-§15, U-09c). With Lock frame omitted -- the
--- frameless set, or a host that omits it -- Minimap button leaves the first column and sits beside
--- Debug console, so no line holds a lone control; Test mode then opens a line of its own. With Lock
--- frame present, minor 7's shape stands: Minimap button opens the line and Test mode pairs beside
--- it. The composer lays out the rows the spec asks for and does not police which ones it asks for.
local function masterRows(ms, spec, notes)
  local rows = {}
  emitNoted(ms, rows, notes, "enabled", {
    type = "bool", label = "Enable " .. tostring(spec.addonName or "this addon"),
    tooltip = "Turn the addon off without unloading it.", default = true, startsLine = true,
  })
  emitNoted(ms, rows, notes, "visibility", {
    type = "string", label = "General visibility",
    tooltip = "When this addon's display is shown at all.",
    values = VISIBILITY_VALUES, sorting = VISIBILITY_SORT, default = "always",
  })
  emitNoted(ms, rows, notes, "scale", {
    type = "number", label = "Master scale", tooltip = "Scales the whole addon's display.",
    min = 0.5, max = 2, step = 0.05, default = 1, startsLine = true,
  })
  -- Labeled Master opacity since compose minor 9 (owner call CALL-02, options-ui-§21): only the
  -- label moved, so the stored leaf is still `alpha` and nothing migrates.
  emitNoted(ms, rows, notes, "alpha", {
    type = "number", label = "Master opacity", tooltip = "Opacity of the whole addon's display.",
    isPercent = true, min = 0, max = 1, step = 0.05, default = 1,
  })
  local lockRow = emitNoted(ms, rows, notes, "locked", {
    type = "bool", label = "Lock frame",
    tooltip = spec.lockIsPreview and LOCK_PREVIEW_TIP or "Stop the frame being dragged.",
    default = false, startsLine = true,
  })
  -- Sim mode BESIDE LOCK FRAME (compose minor 19): a host with a sim and no Test mode row -- most
  -- often one whose unlocked view is its preview, `lockIsPreview` -- has Lock frame as the switch
  -- nearest a test mode, so the sim pairs there and Debug console opens the next line, Minimap
  -- button beside it. With a Test mode row it sits beside Test mode instead (below).
  local simBesideLock = (lockRow and not spec.testModePath) and emitSim(ms, rows, notes, spec, nil) or nil
  local consoleRow = emitNoted(ms, rows, notes, "debugConsole", {
    path = spec.debugConsolePath or "state.debugConsole",
    type = "bool", label = "Debug console", tooltip = "Show this session's developer log window.",
    -- Session state, never persisted: a console left open is not a setting the next character
    -- inherits.
    sessionOnly = true,
    startsLine = simBesideLock and true or nil,
  })
  masterTail(ms, rows, notes, spec, consoleRow, simBesideLock)
  return appendExtra(ms, rows)
end

--- The two closing buttons' specs. Reset position is nil for a frameless addon.
---
--- BOTH ARE BUILT UNCONDITIONALLY, handler or no handler. That is deliberate -- the pair is the
--- canonical shape §15 fixes, and a composer that silently dropped a reset because the host forgot
--- to pass its callback would make the gap look like a layout decision. The gap is named instead:
--- InlineButtonPair reports lib.STRINGS.DEAD_BUTTON at build time for a spec with no onClick, and
--- draws the button anyway.
local function masterButtons(spec, notes, desc)
  local resetAll = {
    text    = "Reset all settings",
    tooltip = withNote(resetAllTooltip(desc), notes.resetAll),
    onClick = spec.onResetAll,
  }
  if spec.frameless then return resetAll, nil end
  -- The one canonical text that has to name the addon's own frames, so the host may replace it
  -- (compose minor 9, options-ui-§15); a note then follows the replacement.
  local own = spec.resetPositionTooltip
  local tip = (type(own) == "string" and own ~= "") and own or "Move the frame back to where it started."
  return resetAll, {
    text    = "Reset position",
    tooltip = withNote(tip, notes.resetPosition),
    onClick = spec.onResetPosition,
  }
end

--- Attach O.MasterControls to the instance `O`; `desc` is its descriptor, as lib.__AttachCompose
--- hands it on.
function lib.__AttachComposeMaster(O, desc)
  --- The canonical MASTER CONTROLS block (options-ui-§15), and the button pair that closes it.
  ---
  ---   [Enable <AddonName>]   [General visibility]
  ---   [Master scale]         [Master opacity]
  ---   [Lock frame]           [Debug console]
  ---   [Minimap button]       [Test mode]
  ---   [Sim mode]
  ---   [Reset position]       [Reset all settings]
  ---
  --- `spec` additionally takes:
  ---   addonName        string    for the Enable row's label. Required in practice.
  ---   frameless        boolean   the addon draws no positionable frame at all, so it omits EXACTLY
  ---                              master scale, master opacity, lock frame and reset position — and
  ---                              nothing else. It MUST NOT invent a movable frame to fill the tab.
  ---   debugConsolePath string    the console toggle's stored path, VERBATIM and unprefixed:
  ---                              session state lives outside the block's own prefix. Defaults to
  ---                              "state.debugConsole".
  ---   onResetPosition  function  the button's click handler. Omitted when frameless.
  ---   onResetAll       function  options-ui-§12's global reset, verbatim. The button's tooltip
  ---                              is not the spec's: since compose minor 5 it follows the Options
  ---                              descriptor's `resetProfile` and `profilesPage` (resetAllTooltip).
  ---   minimapPath      string    since compose minor 7: the minimap button's visibility, as a
  ---                              "Minimap button" checkbox in the FIRST column of the line below
  ---                              Lock frame / Debug console (options-ui-§15, launcher-§3). Taken
  ---                              VERBATIM, like the console path, because LibDBIcon's own table
  ---                              lives in the GLOBAL store and not under the block's profile
  ---                              prefix. STORED state, never session-only: a button the player
  ---                              hid stays hidden across a reload. The row's boolean says SHOWN
  ---                              while LibDBIcon's key says hidden, so the host's get/set invert
  ---                              at its single write seam and call LibDBIcon's Show / Hide there;
  ---                              the library owns the row, not the inversion.
  ---   testModePath     string    since compose minor 6: the addon's test mode, as a session-only
  ---                              "Test mode" checkbox, pairing BESIDE Minimap button on that same
  ---                              line -- or opening a line of its own where the host passes no
  ---                              minimapPath (options-ui-§15). Taken VERBATIM, like the console path.
  ---                              Omit it when the addon has no test mode: most have none, and a
  ---                              one-shot test action is not one. The host binds get/set.
  ---   isSimMode        function  since compose minor 19, with `toggleSim`: the addon's simulation,
  ---   toggleSim        function  as a session-only "Sim mode" checkbox. The SAME pair the launcher
  ---                              descriptor takes (Launcher minor 7): isSimMode() answers whether
  ---                              the sim runs, toggleSim() is the act of `/<slash> sim`. The row's
  ---                              get / set are these hooks, so the host binds nothing; its
  ---                              descriptor's get / set must answer a row's own get / set, as
  ---                              LibKa0s-Schema's S.Get / S.Set do. Ticking starts the sim,
  ---                              unticking stops it, a refused start re-reads as unticked, and
  ---                              Reset all settings stops a running sim (default false). Without
  ---                              both functions there is no row and nothing else moves. Placed
  ---                              straight after Test mode (pairing beside it, or opening the next
  ---                              line when Test mode is in the second column), or beside Lock
  ---                              frame when there is no testModePath; with neither, in Test
  ---                              mode's slot. The box re-reads the sim on every RefreshScalars, so
  ---                              the host calls O.RefreshScalars() from its sim's listener
  ---                              (Sim:AddListener), and on each show of the panel the tail is
  ---                              drawn on. Leaf `simMode` (omit, notes).
  ---   simPath          string    since compose minor 19: the Sim mode row's path, VERBATIM, like the
  ---                              console path. Defaults to "state.sim". Nothing is stored there.
  ---   leadButton       table     { text, tooltip, onClick } — ONE act of the host's own, closing
  ---                              the tab beside the resets. Since compose minor 2.
  ---   notes            table     since compose minor 9: { <leaf> = "One sentence." }, appended after
  ---                              the canonical tooltip of that row or button, with one space. The
  ---                              leaves are enabled, visibility, scale, alpha, locked, debugConsole,
  ---                              minimap, testMode and simMode (minor 19), and the buttons
  ---                              resetPosition and resetAll.
  ---                              Keyed by the CANONICAL leaf, so a `keys` rename keeps its note. A
  ---                              note for an omitted row, or one that is not a non-empty string,
  ---                              does nothing; `extra` rows are the host's and take none. This is
  ---                              the only way a host extends the composed words (options-ui-§15).
  ---                              The group composers' `tooltips` (compose minor 10) is not read
  ---                              here; `labels` keeps its behavior.
  ---   resetPositionTooltip string since compose minor 9: replaces the Reset position tooltip, the
  ---                              one canonical text that has to name the addon's own frames.
  ---                              notes.resetPosition then follows it. No effect when frameless.
  ---   lockIsPreview    boolean   since compose minor 9: the addon's unlocked view IS its test mode,
  ---                              so Lock frame's tooltip becomes the library's one sentence for it
  ---                              (LOCK_PREVIEW_TIP), notes.locked after it. Such an addon has no
  ---                              Test mode row, so passing testModePath as well is an error. A
  ---                              frameless spec emits no Lock frame row and ignores the field.
  ---
  --- THE FRAMELESS PACKING (compose minor 9, U-09c): with Lock frame omitted, Minimap button sits
  --- beside Debug console and Test mode, when there is one, opens its own line:
  ---
  ---   frameless:            [Enable <AddonName>] [General visibility]
  ---                         [Debug console]      [Minimap button]
  ---                         [Reset all settings]
  ---   framed, omit.locked:  ... [Debug console] [Minimap button]
  ---                         [Test mode]          [Sim mode]
  ---   no Test mode, a sim:  ... [Lock frame]    [Sim mode]
  ---                         [Debug console]      [Minimap button]
  ---
  --- `leadButton` exists because §15 fixes the reset buttons' WORDING. An addon with a verb of its
  --- own to put beside them could not draw the pair itself without keeping a second copy of "Reset
  --- all settings" in its own source, which is the drift this composer exists to end — so the verb
  --- is handed IN and the composer stays the only writer of that text. It is one button, not a
  --- list: the tab closes with the resets, and a row of host verbs before them is a different
  --- design that §15 does not describe.
  ---
  --- @return table rows          the schema rows, in canonical order
  --- @return function afterGroup the hook for this group, drawing the closing button pair
  function O.MasterControls(spec)
    spec = spec or EMPTY
    if spec.lockIsPreview and spec.testModePath then
      error("LibKa0s-Options: MasterControls lockIsPreview is for an addon whose unlocked view is its test mode, so it takes no testModePath (options-ui section 15)", 2)
    end

    -- The frame-only rows are dropped through the SAME `omit` table a caller uses, so there is one
    -- code path rather than a `frameless` branch per row.
    local omit = shallow(spec.omit)
    if spec.frameless then
      omit.scale, omit.alpha, omit.locked = true, true, true
    end
    -- The group defaults to the canonical literal without writing to the caller's table. `__index`
    -- rather than a copy so that every other field is read straight off the spec.
    -- `tooltips = EMPTY` shadows the spec's own: the group composers' tooltip override never reaches
    -- this tab, whose only route to its words is `notes` (options-ui-§15, compose minor 10).
    local ms = setmetatable({ group = spec.group or MASTER_GROUP, omit = omit, tooltips = EMPTY },
      { __index = spec })
    local notes = type(spec.notes) == "table" and spec.notes or EMPTY

    local rows = masterRows(ms, spec, notes)

    -- The two resets are the tab's closing BUTTON PAIR (options-ui-§8), not schema rows: they are
    -- acts rather than settings. A frameless addon draws "Reset all settings" alone, which is the
    -- one shape InlineButtonPair's nil right-hand spec exists for.
    local resetAll, resetPosition = masterButtons(spec, notes, desc)

    -- WHERE THE HOST'S VERB GOES, and the two cases are not a preference. A frameless addon's pair
    -- has ONE empty cell — the right half §15 leaves when there is no Reset position — so the verb
    -- leads and the reset still closes the tab. A framed addon's pair is already full, and §15
    -- forbids splitting or reordering the canonical two, so there the verb takes its own row ABOVE
    -- rather than displacing a reset. Nothing here invents a third button on one line.
    local lead = spec.leadButton
    -- The Sim mode box re-reads the sim on each show of its panel (compose minor 19): a sim started
    -- or ended while the page was hidden, with no host signal, would otherwise show stale until the
    -- next write. Armed once per ctx, however often the page renders.
    local simShown = simHooks(spec) ~= nil and not omit.simMode
    return rows, function(ctx)
      if simShown then armSimShow(O, ctx) end
      if lead and not resetPosition then
        return O.InlineButtonPair(ctx, lead, resetAll)
      end
      if lead then O.InlineButtonPair(ctx, lead, nil) end
      O.InlineButtonPair(ctx, resetPosition or resetAll, resetPosition and resetAll or nil)
    end
  end
end
