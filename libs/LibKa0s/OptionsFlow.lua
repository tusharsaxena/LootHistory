-- LibKa0s-Options-1.0 -- the two-column flow engine: O.RenderRows, O.RenderSchema, O.RenderGrid and
-- the untabbed O.RenderTabbedSchema, which turn a page's rows into 50/50 Flow lines under their
-- headings.
--
-- Peeled out of OptionsWidgets.lua at its minor 39, unchanged (LK-M2-PEEL of Ka0sAddonsCommonTasks
-- docs/2026-10-31-FINDINGS_REMEDIATION), on the seam CLAUDE.md's band census named for that file. The
-- history is that file's header.
--
-- WHO CALLS IN. lib.__AttachWidgets calls lib.__AttachFlow once per instance, at the end of its
-- body, handing over the shell's sink and its two reads. `lib.__widgetsKit` is the helpers the two
-- files share. Nothing else crosses the cut.
-- OptionsTabs.lua's attach, later, replaces the untabbed O.RenderTabbedSchema with the real one.
--
-- A file of the Options major, paired on the shell's minor with the same multi-file idiom as
-- OptionsIds.lua.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib or not lib.__widgetsKit then return end

-- Minor 1: the flow engine, moved here unchanged from OptionsWidgets.lua (its minor 39).
-- Minor 2 (LibKa0s#59, ruling U-14): RenderRows' `opts.beforeGroup` and `opts.afterSubgroup`, which
-- RenderSchema now takes too, and the schema `note` row, drawn by O.__renderNote.
local FLOW_MINOR = 2
-- Paired on the SHELL's minor as well as this file's own: see OptionsScroll.lua.
if lib.__flowMinor and lib.__flowMinor >= FLOW_MINOR
  and lib.__flowShellMinor == lib.MINOR then return end
lib.__flowMinor      = FLOW_MINOR
lib.__flowShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsFlow = FLOW_MINOR

local L = lib.LAYOUT
local startRow, renderRowGuarded = lib.__widgetsKit.startRow, lib.__widgetsKit.renderRowGuarded
local applyLabelFont = lib.__widgetsKit.applyLabelFont

-- The two-column split. Not BUTTON_PAIR_REL: a schema widget's label sits above its control, so it
-- has no border to be clipped and takes the honest half.
local HALF = 0.5

-- Read-only stand-in for a call with no `opts`.
local NO_OPTS = {}

-- What a note row's text is drawn in: the dim small face, and the owner's muted role off Ka0s Default.
local NOTE_FONT = "GameFontDisableSmall"

--- RenderGrid's spacer height (minor 34): absent, the row gap every page has; false or 0, none.
local function gridGap(opts)
  local gap = type(opts) == "table" and opts.gap
  if gap == nil or type(opts) ~= "table" then return L.ROW_VSPACER end
  return gap ~= false and gap ~= 0 and gap or nil
end

--- Claim a host hook for `key`, or nil if there is none or it has already run this render.
---
--- The lookup and the marking are ONE step on purpose. RenderRows honors its hook tables as "fire at
--- most once per render, and only if it actually fired"; splitting the two halves is how a caller
--- ends up marking a hook it never ran, or running one it already marked. `fired` is the LIBRARY's
--- call-local ledger, never the host's table: see the note in O.RenderRows for why consuming the
--- host's entries silently breaks a second render.
local function takeOnce(hooks, fired, key)
  if not (hooks and key) then return nil end
  local hook = hooks[key]
  if not hook or fired[key] then return nil end
  fired[key] = true
  return hook
end

--- Emit a section heading when `row` opens a group the page has not drawn yet, and advance the
--- tracker. The previous group's tail row is flushed FIRST, or the heading lands above a widget
--- that belongs above IT.
---
--- `noHeadings` skips the O.Section call for a page whose sections are drawn as tabs instead
--- (options-ui-§13) -- but the flush and the tracker advance happen either way, or a later
--- group would be treated as a continuation of this one and the boundary flush between them
--- would never happen.
---
--- `seams.beforeGroup[group]` (minor 2) runs between the flush and the heading, under `noHeadings`
--- too, where it is the top of the tab: what it draws lands above the group and under the last one.
local function startGroup(O, ctx, row, flushRow, seams, firedBefore)
  if not (row.group and row.group ~= ctx.lastGroup) then return end
  flushRow()
  local before = takeOnce(seams.beforeGroup, firedBefore, row.group)
  if before then before(ctx) end
  if not seams.noHeadings then O.Section(ctx, row.group) end
  ctx.lastGroup = row.group
  -- A subgroup belongs to ONE group. Leaving the tracker set across a group boundary would swallow
  -- the first subsection heading of the next group whenever the two happened to share a name --
  -- "Border" under Bars and "Border" under Tooltip is the shape the collection is about to be full
  -- of (options-ui-§16).
  ctx.lastSubgroup = nil
end

--- Emit a SUBSECTION heading when `row` opens a subgroup its group has not drawn yet, and advance
--- the tracker. The pending line is flushed FIRST, exactly as it is for a group heading, or the
--- heading lands packed beside a widget that belongs above it.
---
--- The sibling of startGroup, and deliberately NOT suppressed by `noHeadings`. That flag exists
--- because on a tabbed page the TAB is the group's heading -- but a tab that mixes control types
--- (a bar block, a background block and a border block, all under one label) has to say where one
--- stops and the next starts, and there is no tab left to name them with (options-ui-§7). So
--- `group` is what the strip partitions on and `subgroup` is what breaks a tab up inside itself;
--- a page uses either, both, or neither, and the tab list stays derivable from `group` alone.
---
--- ONE HEADING WIDGET IN THE COLLECTION: O.Section, the same AceGUI Heading every other header
--- uses. A hand-rolled colored label standing in for it is anti-patterns #71.
local function startSubgroup(O, ctx, row, flushRow)
  if not (row.subgroup and row.subgroup ~= ctx.lastSubgroup) then return end
  flushRow()
  O.Section(ctx, row.subgroup)
  ctx.lastSubgroup = row.subgroup
end

--- Does `row` have to start a fresh line?
---
--- Three fields, one question, hoisted out of the loop so the loop reads as the decision rather
--- than as the disjunction. They differ only in what happens AFTER the line opens -- see the field
--- list on O.RenderRows.
local function opensLine(row)
  return row.solo or row.wide or row.type == "note" or row.startsLine
end

--- A row across both columns, alone on its line: `wide`, or a note (minor 2), which is never half a
--- line.
local function isWide(row)
  return row.wide or row.type == "note"
end

--- Draw one row across BOTH columns, alone on its line. `nil` relative width is what applyWidth
--- turns into SetFullWidth, so no maker knows this case exists.
local function drawWide(O, ctx, row, pendingRow, printer)
  if not pendingRow then pendingRow = startRow(O) end
  renderRowGuarded(printer, row.path, O.RenderField, ctx, row, pendingRow, nil)
  return pendingRow
end

--- Draw one schema row into the pending Flow line, then attach its pairWith partner if it has one.
--- Returns the line and its widget count, because both advance and the caller decides on them.
---
--- The partner attaches only while the row is the LONE widget on its line: attaching to a line that
--- already holds two would make it three-wide and break the 50/50 split for the rest of the page.
--- A row whose render RAISED never counted, so it cannot pull a partner onto the line either.
local function drawRow(O, ctx, row, pendingRow, pendingCount, pairWith, firedPair, printer)
  if not pendingRow then pendingRow = startRow(O) end
  if renderRowGuarded(printer, row.path, O.RenderField, ctx, row, pendingRow, HALF) then
    pendingCount = pendingCount + 1
  end
  if pendingCount == 1 then
    -- A bound row (OptionsCompose's `spec.bind`) has no path, so it is keyed by its record field.
    local pair = takeOnce(pairWith, firedPair, row.path or row.field)
    if pair then
      pair(ctx, pendingRow)
      pendingCount = pendingCount + 1
    end
  end
  return pendingRow, pendingCount
end

--- Close out a group on its LAST row — the next row opens a different group, or there is no next
--- row — by running the host's afterGroup hook for it. The counterpart to startGroup, and the loop
--- reads as the pair: open the group, draw the row, close the group.
---
--- The pending line is flushed FIRST. afterGroup draws buttons, and they belong on a fresh line
--- rather than packed into the empty half of the group's tail row.
local function endGroup(ctx, afterGroup, firedAfter, row, nextRow, flushRow)
  if not (row.group and (not nextRow or nextRow.group ~= row.group)) then return end
  local after = takeOnce(afterGroup, firedAfter, row.group)
  if not after then return end
  flushRow()
  after(ctx)
end

--- Close out a subgroup on its LAST row (minor 2): the next row is in another block, or there is
--- none. The flush comes first, as endGroup's, and this runs before endGroup, since the block ends
--- inside its group.
---
--- The ledger is keyed by group AND name, where endGroup's is by name alone. One subgroup name under
--- two groups is the shape startGroup's note describes, and a name-keyed ledger would close the first
--- "Border" and lose the second in silence; the hook is handed the group so it can tell them apart. A
--- block that recurs inside one group closes once, as a recurring group does.
local function endSubgroup(ctx, seams, fired, row, nextRow, flushRow)
  local name, group = row.subgroup, row.group
  if not (name and seams.afterSubgroup) then return end
  if nextRow and nextRow.subgroup == name and nextRow.group == group then return end
  local hook = seams.afterSubgroup[name]
  local key = tostring(group) .. "\0" .. name
  if not hook or fired[key] then return end
  fired[key] = true
  flushRow()
  hook(ctx, group)
end

--- The flow engine for instance `O`, descriptor `d`: `h` carries what OptionsWidgets.lua shares.
function lib.__AttachFlow(O, d, h)
  local print, read, readKey = h.print, h.read, h.readKey

  --- The `note` row's maker (minor 2), which O.RenderField dispatches to: text, not a setting. It
  --- lives here rather than among the makers because it has no value, no refresher and no path.
  function O.__renderNote(_ctx, row, parent, relativeWidth)
    local w = O.AceGUI:Create("Label")
    if relativeWidth then w:SetRelativeWidth(relativeWidth) else w:SetFullWidth(true) end
    w:SetText(row.text or "")
    applyLabelFont(w, NOTE_FONT)
    if w.label and w.label.SetJustifyH then w.label:SetJustifyH("LEFT") end
    local Sk = O.__chromeAway and O.__chromeAway()
    local r, g, b
    if Sk then r, g, b = Sk.Color("text.muted") end
    if r and w.SetColor then w:SetColor(r, g, b) end
    parent:AddChild(w)
    return w
  end

  -- ── the two-column flow engine ───────────────────────────────────────────────────────────
  --
  -- Widgets are paired into 50/50 Flow rows, each row wrapped in a full-width SimpleGroup so
  -- AceGUI's layout pass gives both children exactly half the panel width and breaks them onto the
  -- same line. Section headings span the full width, and every row is followed by a small vertical
  -- spacer.
  --
  --   solo        render this row alone in the left half of its own line. For visual pivots.
  --   wide        render this row alone at FULL width, spanning both columns. NOT what `solo`
  --               does -- solo renders alone in the LEFT HALF -- and named to match RenderGrid's
  --               field of the same meaning rather than redefining solo, which would silently
  --               widen every solo row in nine shipped addons.
  --   startsLine  flush the pending line BEFORE this row, so a declared pair -- a color swatch and
  --               its "use class color" companion (options-ui-§17), the first row of a composed
  --               group -- is guaranteed to land as [left][right] and can never be split across
  --               two lines by an odd number of widgets above it. Without it the parity of every
  --               pair is a property of how many rows happen to precede it, which is a thing every
  --               author was counting by hand.
  --   subgroup    a heading drawn INSIDE a group (options-ui-§7). `group` is what a tabbed page
  --               partitions its strip on; `subgroup` is what breaks one tab into named blocks
  --               when it mixes control types. Drawn even under `noHeadings`, which suppresses the
  --               GROUP heading only.
  --   note        (`type = "note"`, minor 2) `text` drawn dim at full width on a line of its own. No
  --               path and no value: /list and both reset walks skip it, and the row's `group`,
  --               `subgroup`, `shownWhen` and `skipRender` read as on any other row.
  --   skipRender  keep the row in the schema (so resets and the CLI still see it) but let the host
  --               draw it bespoke — a header checkbox, say.
  --   afterGroup  { [groupName] = fn(ctx) } fired once PER RENDER, after that group's last row is
  --               flushed, so inline action buttons always start on a fresh line. The table is
  --               read-only to the library: hoist it to a constant and re-render freely.
  --   pairWith    { [path] = maker(ctx, rowGroup) } attaches a non-schema widget as the RIGHT half
  --               of a named path's row. Once per render (and, like afterGroup, never mutated),
  --               and only when that path is currently the lone
  --               widget on its row — attaching to a row that already has two would make it
  --               three-wide and break the 50/50 split for the rest of the page.
  --   opts        { noHeadings = true } suppresses the automatic Section heading, for a page
  --               whose sections are drawn as tabs instead (options-ui-§13). Omitted by every
  --               untabbed caller, which is why it is a fifth argument rather than a field on
  --               the ctx: a page's tabbedness is a property of THIS render, and a ctx flag
  --               would leak it into the next one.
  --               { beforeGroup = { [group] = fn(ctx) } } (minor 2) fires once per render as a group
  --               opens, after the last group's tail row and before this one's heading, for a line
  --               that introduces the group. Fires under `noHeadings` too.
  --               { afterSubgroup = { [subgroup] = fn(ctx, group) } } (minor 2) fires after a
  --               subgroup's last row is flushed, once per render per group holding that name, and
  --               before any afterGroup for the same row. Both tables are read-only to the library.
  --               { disabled = true } (minor 16) draws every widget of the call disabled -- the
  --               rows, and the buttons an afterGroup or pairWith hook draws -- for a page whose
  --               subject does not apply (a Bars page over an icons container). It rides on
  --               `ctx.__renderDisabled` for the call's duration only, for the reason just given.
  --   disabledIf  (a row field) a settings path, or from minor 16 a predicate function(row) ->
  --               bool, whose truth draws the row disabled. Honored by every maker (only the
  --               color picker read it before minor 16) and re-evaluated on every refresh.

  --- Render an EXPLICIT list of rows. Taking a list rather than a page key is what lets a host
  --- render a filtered subset (a mirrored unit's partition) through the same engine.
  --- Lay out arbitrary widgets two per row, in the order given.
  ---
  --- The sibling of RenderRows, and deliberately not the same function. RenderRows is
  --- SCHEMA-driven: it walks declared rows, emits a Section when `group` changes, and pairs them
  --- automatically. This one is CALLER-driven — the caller decides what goes in each cell and in
  --- what order, and a cell may be a schema row or a bespoke widget.
  ---
  --- That distinction is what a host needs for a list whose LENGTH is not known from the schema:
  --- one checkbox per macro, per unit, per spell. Every such list was previously a hand-rolled
  --- copy of this loop in the host, which is exactly the duplication this library exists to end.
  ---
  --- Each item is either a schema row, or `{ make = function(ctx, parent, relativeWidth) end }`
  --- for a bespoke widget. `wide = true` breaks the item onto its own full-width row.
  --- Minor 34: `parent` replaces the page scroll as the container; `opts.gap` is the spacer after
  --- each row (absent `L.ROW_VSPACER`; `false` or `0` none, for a fixed-stride ReorderList); and an
  --- item that raised, or whose `make` answered exactly `false`, takes no cell, a wide one no row
  --- and no gap (its row is released). A `make` answering nil still counts as drawn.
  --- IT DOES NOT LAY OUT, deliberately: hosts render several grids and lay out once. Call
  --- `container:DoLayout()` after the last render, as RenderRows does for you.
  function O.RenderGrid(ctx, items, parent, opts)
    local scroll = parent or O.EnsureScroll(ctx)
    if not scroll then return end
    local gap = gridGap(opts)
    local pendingRow, pendingCount = nil, 0

    local function addRow(r)
      scroll:AddChild(r)
      if gap then O.AddSpacer(scroll, gap) end
    end

    local function flushRow()
      if pendingRow then
        addRow(pendingRow)
        pendingRow, pendingCount = nil, 0
      end
    end

    -- Guarded per item, for the same reason RenderRows guards per row: a bespoke `make` reaches
    -- into live addon state, and a raise inside AceGUI's layout pass would cost every item after
    -- it. True when the item drew.
    local function renderInto(item, into, relativeWidth)
      if type(item.make) ~= "function" then
        return renderRowGuarded(print, item.path, O.RenderField, ctx, item, into, relativeWidth)
      end
      local answer
      local ok = renderRowGuarded(print, item.path, function()
        answer = item.make(ctx, into, relativeWidth)
      end)
      return ok and answer ~= false
    end

    for _, item in ipairs(items) do
      if isWide(item) then
        flushRow()
        local r = startRow(O)
        if renderInto(item, r, nil) then addRow(r) else r:Release() end
      else
        if not pendingRow then pendingRow = startRow(O) end
        if renderInto(item, pendingRow, HALF) then
          pendingCount = pendingCount + 1
        end
        if pendingCount >= 2 then flushRow() end
      end
    end
    flushRow()
  end

  -- ── switched sections: `shownWhen` (minor 22) ─────────────────────────────────────────────
  --
  -- A row carrying `shownWhen` is dropped from the render while its selector says so, and the page
  -- re-renders once when the selector changes. Peeled out to OptionsSwitch.lua at minor 37 (LK-10
  -- of Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK, with the OR form `any`), which
  -- is handed this instance's two reads. A copy without that file draws every row: no row is lost.
  local switch = lib.__AttachSwitch and lib.__AttachSwitch(O, { read = read, readKey = readKey })
  local switchedRows = switch and switch.switchedRows or function(rows) return rows, nil end
  local selectorKey = switch and switch.selectorKey
  local watchSelector = switch and switch.watchSelector

  --- The flow engine's loop, under the disable flag RenderRows holds for it.
  local function flowRows(ctx, scroll, allRows, afterGroup, pairWith, seams)
    local pendingRow, pendingCount = nil, 0
    local rows, selectors = switchedRows(allRows)

    -- The one-shot bookkeeping below is the LIBRARY's, and it lives in these call-local sets
    -- rather than in the caller's tables. Consuming the caller's entries would make a second render
    -- of the same page \226\128\148 a unit switch, a ClearScroll + re-render \226\128\148 silently drop every inline
    -- button and every paired widget, for any host that hoisted its table to a file-level constant.
    local firedAfter, firedPair, firedBefore, firedSub = {}, {}, {}, {}

    local function flushRow()
      if pendingRow then
        scroll:AddChild(pendingRow)
        O.AddSpacer(scroll, L.ROW_VSPACER)
        pendingRow, pendingCount = nil, 0
      end
    end

    for i, row in ipairs(rows) do
      startGroup(O, ctx, row, flushRow, seams, firedBefore)
      startSubgroup(O, ctx, row, flushRow)

      if not row.skipRender then
        if opensLine(row) and pendingCount > 0 then flushRow() end

        if isWide(row) then
          pendingRow = drawWide(O, ctx, row, pendingRow, print)
          flushRow()
        else
          pendingRow, pendingCount =
            drawRow(O, ctx, row, pendingRow, pendingCount, pairWith, firedPair, print)
          if row.solo or pendingCount >= 2 then flushRow() end
        end
        if selectors and selectors[selectorKey(row)] then watchSelector(ctx, row) end
      end

      endSubgroup(ctx, seams, firedSub, row, rows[i + 1], flushRow)
      endGroup(ctx, afterGroup, firedAfter, row, rows[i + 1], flushRow)
    end
    flushRow()
    if scroll.DoLayout then scroll:DoLayout() end
  end

  function O.RenderRows(ctx, rows, afterGroup, pairWith, opts)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end
    -- `opts.disabled` (minor 16) holds `ctx.__renderDisabled` for exactly this call: every maker
    -- snapshots it at build, and InlineButtonPair / SessionCheckbox read it, so a widget an
    -- afterGroup or pairWith hook draws is disabled with the page. A nested call with no opts of
    -- its own INHERITS the outer flag, since its widgets are part of the same disabled page, and
    -- the outer value is restored on the way out -- a raise included, or the flag would be
    -- stranded on the ctx and dim the next render. The raise still propagates, as it always has.
    local outer = ctx.__renderDisabled
    ctx.__renderDisabled = ((opts and opts.disabled) or outer) and true or nil
    local ok, err = pcall(flowRows, ctx, scroll, rows, afterGroup, pairWith, opts or NO_OPTS)
    ctx.__renderDisabled = outer
    if not ok then error(err, 0) end
  end

  --- The per-page wrapper. `ctx.unit` is passed through as the host's filter argument, which is
  --- how a per-unit page renders only the selected unit's rows. `opts` (OptionsFlow minor 2) is
  --- RenderRows' own.
  function O.RenderSchema(ctx, pageKey, afterGroup, pairWith, opts)
    O.RenderRows(ctx, d.rowsForPage(pageKey, ctx.unit) or {}, afterGroup, pairWith, opts)
  end

  --- The UNTABBED fallback for a page meant to render tabbed. OptionsTabs.lua's attach replaces it
  --- with the real one (OptionsTabs minor 4 took it there, with its fifth `opts` argument); it
  --- stays only for a partial copy without that file, where every row renders with its headings
  --- and `opts` is ignored. Returns the group names, as the real one does.
  function O.RenderTabbedSchema(ctx, pageKey, afterGroup, pairWith)
    local rows, groups, seen = d.rowsForPage(pageKey, ctx.unit) or {}, {}, {}
    for _, row in ipairs(rows) do
      if row.group and not seen[row.group] then seen[row.group] = true; groups[#groups + 1] = row.group end
    end
    if not O.AceGUI then return {} end
    O.RenderRows(ctx, rows, afterGroup, pairWith)
    return groups
  end
end
