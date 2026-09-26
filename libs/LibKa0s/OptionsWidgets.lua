-- LibKa0s-Options-1.0 — the schema-row -> AceGUI translation and the two-column flow engine.
--
-- Each maker reads through the descriptor's `get`, writes through its `set`, registers a refresher
-- closure so an external write re-syncs the widget, and adds itself to the container it was given.
-- RenderField dispatches by row.type; RenderRows lays an explicit row list into 50/50 flow rows
-- with section headings and spacers; RenderSchema is the thin per-page wrapper.
--
-- Part of the Options major rather than a major of its own, and guarded with the same multi-file
-- idiom as OptionsScroll.lua: a flow engine paired with a shell from a different vendored copy
-- would lay pages out wrong with nothing to notice it.
--
-- THE PAGE'S CHROME IS NOT HERE. The tab strip, the page banner, the header block, the secondary
-- strip and the client art all four are drawn from moved to OptionsTabs.lua at v1.39.0 (issue
-- #16), on the seam this file was already built along: the two halves never reached into each
-- other's module-scope locals. What is left is what a schema ROW becomes. `O.RenderTabbedSchema`
-- moved to OptionsTabs.lua at OptionsTabs minor 4 (a first peel toward the census row on this
-- file); what stays below is its untabbed fallback for a partial copy without that file.
--
-- NOR IS THE ID SURFACE. O.ResolveId, O.UnnamedCandidates, O.ID_NAME_HINT and O.IdInput moved to
-- OptionsIds.lua, and O.IdList to OptionsIdList.lua, at OptionsWidgets minor 32 (issue #32): the
-- module-scope id resolution and suggestion blocks never reached the makers or the flow engine, and
-- the members reached this file only through the sink, the combat refusal, startRow and
-- renderRowGuarded, which lib.__AttachWidgets hands them when it calls them in.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- Minor 14 takes the tab strip's buttons and the page's content panel from LibKa0s-Pool-1.0
-- instead of building them on every click, so the pool is a hard FLOOR here and not a nicety.
-- Absent or too old, this file is absent rather than half-wired: the alternative -- falling back
-- to allocating per click -- is precisely the leak this minor exists to end, and it would fall
-- back in silence. Both files ship in one payload and whole-folder vendoring is mandatory, so a
-- host that trips this floor has a broken copy rather than an unlucky one. The floor is also
-- unreachable in a well-formed tree: Pool.lua and Options.lua both gate on LibKa0s-Core-1.0 and
-- Pool.lua loads first in LibKa0s.xml, so a payload with no pool has no Options major to attach
-- to either and `lib` above is already nil.
local Pool = LibStub and LibStub("LibKa0s-Pool-1.0", true)
local NEEDS_POOL = 1
if not Pool or (Pool.MINOR or 0) < NEEDS_POOL then return end

-- Minor 32: the id surface moved out to OptionsIds.lua and OptionsIdList.lua (issue #32), attached
-- from lib.__AttachWidgets where it used to be defined; no change in behavior.
local WIDGETS_MINOR = 32
-- Paired on the SHELL's minor as well as this file's own — see OptionsScroll.lua for why the
-- file's own counter is not enough.
if lib.__widgetsMinor and lib.__widgetsMinor >= WIDGETS_MINOR
  and lib.__widgetsShellMinor == lib.MINOR then return end
lib.__widgetsMinor      = WIDGETS_MINOR
lib.__widgetsShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsWidgets = WIDGETS_MINOR

local L = lib.LAYOUT

-- Live-preview color drags fire at up to 60 Hz. 50 ms is slow enough that a sustained drag costs
-- a handful of writes a second rather than sixty, and fast enough that the preview still tracks
-- the cursor.
local COLOR_THROTTLE = 0.05
-- Live-slider commits reuse the color picker's throttle: a 60 Hz drag would otherwise fan a
-- refresh pass out across every registered panel sixty times a second.
local DRAG_THROTTLE  = COLOR_THROTTLE

-- The tooltip BODY. `tooltip` is the name every Ka0s host's schema declares; `desc` is the one
-- this library invented, and it is kept because two shipped hosts use it. Reading only `desc`
-- blanked the body on every widget of any host on the standard's own shape — the label still
-- renders, so it failed silently and only in game.
local function tooltipBody(row)
  return row.tooltip or row.desc
end

-- The two-column split. Not BUTTON_PAIR_REL: a schema widget's label sits above its control, so it
-- has no border to be clipped and takes the honest half.
local HALF = 0.5

local function applyWidth(widget, relativeWidth)
  if relativeWidth then
    widget:SetRelativeWidth(relativeWidth)
  else
    widget:SetFullWidth(true)
  end
end

-- Both enum shapes the collection actually declares, normalized to one ordered list of
-- { value =, text = }.
--
--   ordered array   { { value = "SHORT", text = "Short" }, ... }   the Ka0s options schema
--   key map         { SHORT = "Short", LONG = "Long" }             AceGUI's own SetList shape
--   key set         { SHORT = true, LONG = true }                  the degenerate key map
--
-- The array is identified by its FIRST element being a table carrying `value`; nothing else in
-- play can look like that, so the two are distinguishable without a declared discriminator.
-- Array POSITION is the order — that is the entire point of the shape — so `sorting` is ignored
-- there. A key map keeps the existing rule: `sorting` if the row declares one, else sorted keys.
--
-- Evaluated at call time, not at load: a host's media list is populated by another addon and is
-- not knowable when the schema row is declared.
--
-- Duplicated verbatim in Slash.lua and OptionsWidgets.lua rather than hoisted into Core. The two
-- readers MUST agree — a CLI that accepts a value the dropdown cannot display is worse than
-- either being wrong alone — but hoisting would raise NEEDS_CORE in two majors, and
-- docs/releasing.md is explicit that a floor raise is a breaking change to the VENDORING: every
-- consumer carrying a stale Core.lua would lose both majors outright. The agreement is pinned by
-- a cross-major parity case instead, which is the cheaper guarantee.
local function enumList(row)
  local v = type(row.values) == "function" and row.values() or row.values
  if type(v) ~= "table" then return {} end

  if type(v[1]) == "table" and v[1].value ~= nil then
    local out = {}
    for i, item in ipairs(v) do
      out[i] = { value = item.value, text = item.text or tostring(item.value) }
    end
    return out
  end

  local keys = {}
  if type(row.sorting) == "table" then
    for i, k in ipairs(row.sorting) do keys[i] = k end
  else
    for k in pairs(v) do keys[#keys + 1] = k end
    -- Mixed key types would raise on a bare `<`. Homogeneous string keys sort exactly as before.
    table.sort(keys, function(a, b)
      if type(a) == type(b) then return a < b end
      return tostring(a) < tostring(b)
    end)
  end
  local out = {}
  for i, k in ipairs(keys) do
    -- `true` is the SET shape, and rendering it as the label is how a key set becomes a dropdown
    -- of entries all reading "true". The key is the only honest label such a row has.
    local text = v[k]
    out[i] = { value = k, text = type(text) == "string" and text or tostring(k) }
  end
  return out
end

local function snapToStep(value, mn, step)
  if not (step and step > 0) then return value end
  return math.floor((value - mn) / step + 0.5) * step + mn
end

-- ── the shared row plumbing ──────────────────────────────────────────────────────────────────
--
-- File-locals rather than closures inside the makers: they are created once at load and take the
-- instance as an argument, so nothing is allocated per render.

--- Apply a _G font-object NAME to an AceGUI text widget's FontString.
---
--- Guarded three ways because all three misses are real: AceGUI's Label only grows its `.label`
--- once it has been laid out, a widget mock may have neither, and a font object a client does not
--- ship resolves to nil. None of them may cost the page. The NAME is taken rather than the object
--- because a host declares its landing spec at file scope, where the font globals may not exist yet.
local function applyLabelFont(widget, fontName)
  if not fontName then return end
  local fs = widget.label
  if fs and fs.SetFontObject and _G[fontName] then
    fs:SetFontObject(_G[fontName])
  end
end

--- One full-width Flow row — the container the two-column engine packs a pair of widgets into.
--- Byte-identical in RenderGrid and RenderRows before it was hoisted here.
local function startRow(O)
  local r = O.AceGUI:Create("SimpleGroup")
  r:SetLayout("Flow")
  r:SetFullWidth(true)
  return r
end

--- Render one row (or one bespoke item) through `fn`, absorbing a raise and reporting it against
--- the row's path. Vararg because the two callers pass different argument shapes: a schema row goes
--- through O.RenderField(ctx, row, parent, relW), a bespoke item through its own
--- make(ctx, parent, relW).
---
--- Each ROW is guarded, not just the page. One corrupt saved value, or one `values` function that
--- raises because the media library it queries is half-loaded, used to take the whole page down
--- from inside AceGUI's layout pass — every row after it never drew, and the user saw a panel that
--- simply stopped mid-way with no error naming the row. The page-level guard added in Options minor
--- 3 catches a raising BUILDER; this catches a raising ROW, which is the more common failure and
--- the one a host cannot pre-empt.
local function renderRowGuarded(printer, path, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    printer(lib.STRINGS.ROW_FAILED:format(tostring(path or "?"), tostring(err)))
  end
  return ok
end

--- Emit a section heading when `row` opens a group the page has not drawn yet, and advance the
--- tracker. The previous group's tail row is flushed FIRST, or the heading lands above a widget
--- that belongs above IT.
---
--- `noHeadings` skips the O.Section call for a page whose sections are drawn as tabs instead
--- (options-ui-§13) -- but the flush and the tracker advance happen either way, or a later
--- group would be treated as a continuation of this one and the boundary flush between them
--- would never happen.
local function startGroup(O, ctx, row, flushRow, noHeadings)
  if not (row.group and row.group ~= ctx.lastGroup) then return end
  flushRow()
  if not noHeadings then O.Section(ctx, row.group) end
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
  return row.solo or row.wide or row.startsLine
end

--- Draw one row across BOTH columns, alone on its line. `nil` relative width is what applyWidth
--- turns into SetFullWidth, so no maker knows this case exists.
local function drawWide(O, ctx, row, pendingRow, printer)
  if not pendingRow then pendingRow = startRow(O) end
  renderRowGuarded(printer, row.path, O.RenderField, ctx, row, pendingRow, nil)
  return pendingRow
end

--- Claim a host hook for `key`, or nil if there is none or it has already run this render.
---
--- The lookup and the marking are ONE step on purpose. RenderRows honors two hook tables — pairWith
--- and afterGroup — and both are "fire at most once per render, and only if it actually fired";
--- splitting the two halves is how a caller ends up marking a hook it never ran, or running one it
--- already marked. `fired` is the LIBRARY's call-local ledger, never the host's table: see the note
--- in O.RenderRows for why consuming the host's entries silently breaks a second render.
local function takeOnce(hooks, fired, key)
  if not (hooks and key) then return nil end
  local hook = hooks[key]
  if not hook or fired[key] then return nil end
  fired[key] = true
  return hook
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

-- ── the landing page ─────────────────────────────────────────────────────────────────────────
--
-- Three blocks, one file-local each, assembled by O.BuildLandingPage. Promoted out of three hosts
-- that each carried a function literally named Helpers.BuildMainContent rendering the same page
-- with the same four constants; the only differences were the logo path and where the one-liner
-- came from, which is why both are spec DATA here.

--- The logo block. A full-width SimpleGroup with its layout suppressed, holding a texture anchored
--- TOPLEFT at its native size, so the art renders pixel-exact and left-aligned regardless of how
--- wide the panel is.
---
--- The `.frame` handle and the texture it hands back are both guarded, for the same reason every
--- other widget touch in this file is: an AceGUI widget mock has no backing frame, and a
--- CreateTexture that answers nil is the shape a stubbed one takes. It matters MORE here than
--- elsewhere — BuildLandingPage runs under the renderer's pcall, so one raise on the logo prints
--- RENDER_FAILED and costs the notes and every section too, i.e. the whole page for the sake of a
--- picture. The group and its spacer are added either way, so a missing texture leaves a gap where
--- the art goes rather than re-flowing everything under it.
---
--- A TEXTURE OUTLIVES THE WIDGET THAT DREW IT, and that is the whole reason this is not three
--- lines. AceGUI POOLS its widget frames: Release hides a frame and hands the same one back on the
--- next Create. A texture created on it is not a widget, so nothing releases it and nothing hides
--- it — it rides the frame into the pool and reappears the next time that frame is handed out. So
--- a host with a logo grew a SECOND logo partway down its own landing page, intermittently,
--- depending only on pool order: the stale texture belonged to a SimpleGroup being used for
--- something else entirely. BuildLandingPage's ClearScroll cannot help, because there is no widget
--- there to clear.
---
--- Two halves, and both are needed. The texture is kept ON the frame and reused, so a frame that
--- comes back for another logo cannot accumulate a second one; and it is hidden when the widget is
--- released, so a frame that comes back for anything else does not show it. `SetCallback` is safe
--- here because AceGUI fires "OnRelease" BEFORE it clears a widget's callbacks, and this one is set
--- fresh on every acquisition.
local function landingLogo(O, scroll, spec)
  if not spec.logo then return end

  local size  = spec.logoSize or L.LANDING_LOGO
  local group = O.AceGUI:Create("SimpleGroup")
  group:SetLayout(nil)
  group:SetFullWidth(true)
  group:SetHeight(size)

  local frame = group.frame
  local tex   = frame and frame.__ka0sLandingLogo
  if not tex and frame and frame.CreateTexture then
    tex = frame:CreateTexture(nil, "ARTWORK")
    frame.__ka0sLandingLogo = tex
  end
  if tex then
    tex:SetTexture(spec.logo)
    tex:SetSize(size, size)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    tex:Show()
    group:SetCallback("OnRelease", function() tex:Hide() end)
  end
  scroll:AddChild(group)

  O.AddSpacer(scroll, L.LANDING_GAP_LOGO)
end

--- The one-liner under the logo.
---
--- Resolved at RENDER time when it is a function, because the usual source is the TOC's Notes field
--- and a host that declares its spec at file scope cannot read that yet. An empty or absent
--- one-liner skips the Label AND its spacer together — a lone gap under the logo reads as a broken
--- margin rather than as a missing sentence.
local function landingNotes(O, ctx, scroll, spec)
  local notes = spec.notes
  if type(notes) == "function" then notes = notes() end
  if type(notes) ~= "string" or notes == "" then return end

  O.TextRow(ctx, notes, { fontObject = "GameFontHighlight" })
  O.AddSpacer(scroll, L.LANDING_GAP_DESC)
end

--- One heading plus its rows, per section.
---
--- `rows` is a FUNCTION, not an array, so a re-render picks up a command registered since the spec
--- was declared: the list a host passes here is generated from its command table, which grows as
--- other files load.
---
--- The heading goes through O.Section, which already emits SECTION_BOTTOM_SPACER under it — the
--- same 6 the three hosts spelled MAIN_GAP_BELOW_HEAD, and what LANDING_GAP_HEAD names. A second
--- spacer here would double that gap. ctx.lastGroup is advanced for the same reason RenderRows
--- advances it: it is what puts SECTION_TOP_SPACER above the SECOND heading and not above the first.
local function landingSections(O, ctx, spec)
  for _, section in ipairs(spec.sections or {}) do
    O.Section(ctx, section.heading)
    ctx.lastGroup = section.heading
    for _, line in ipairs(section.rows and section.rows() or {}) do
      O.TextRow(ctx, line)
    end
  end
end

--- Attach the widget makers and the flow engine to one instance. Called at the end of lib:New, so
--- every host gets its own closures over its own descriptor.
function lib.__AttachWidgets(O, d)
  -- The SHELL's sink (`O.__print`), not a second one built from the same descriptor. What stood
  -- here was `d.print or function() end`, which discarded every diagnostic in this file for any
  -- host that passed no printer — that is, for every host relying on the library's own
  -- chat-frame fallback, which is the fallback that exists precisely so these lines stay visible.
  -- The `or` arms survive for composition order alone: this is called from the end of lib:New, so
  -- `O.__print` is always there, and a caller that attached the maker set to some other table
  -- should fall silent rather than raise.
  local print = O.__print or d.print or function() end

  -- A ROW WITH NO PATH IS READ AND WRITTEN THROUGH ITS OWN get / set (minor 15). That is the flow
  -- engine's half of OptionsCompose.lua's record-backed arm: a composed block bound to a registry
  -- record rather than to settings carries `get()` and `set(value)` closures and no `path`. The
  -- gate is `path == nil`, not "has a get": a row WITH a path goes through the descriptor exactly as
  -- it always has, whatever other fields a host's schema happens to give it, so no path-keyed row
  -- anywhere in the collection can change behavior because of this.
  local function read(row)
    if row.path == nil and type(row.get) == "function" then return row.get() end
    return d.get(row.path)
  end
  -- Another key read on a row's behalf -- `disabledIf`. A path-less row resolves it through its own
  -- `get(key)`, which reads that field of the same record; a path row reads the settings path.
  local function readKey(row, key)
    if row.path == nil and type(row.get) == "function" then return row.get(key) end
    return d.get(key)
  end
  -- THE COMBAT LOCK's seam in this file (minor 23, options-ui-§2): the shell's refusal, asked by
  -- every control that would reach the host -- a write, a button, a session toggle, an id list's
  -- add or remove. It prints the gray notice once per combat. A refused control is put back, by
  -- the refresh its caller already runs or by an explicit reset where the caller runs none.
  local function refused()
    return O.__combatRefused ~= nil and O.__combatRefused()
  end

  local function write(row, value)
    if refused() then return end
    if row.path == nil and type(row.set) == "function" then return row.set(value) end
    return d.set(row.path, value)
  end

  -- Is `row` drawn disabled? `pageDisabled` is RenderRows' `opts.disabled`, snapshotted by the
  -- maker at BUILD time and never re-read from the ctx: the flag is cleared when that render
  -- returns, so a refresher reading it live would lift a disabled page's dimming on the first
  -- write anywhere, and a later render's flag could reach an earlier page's widgets.
  --
  -- `disabledIf` is a settings path (read through readKey, so a composed row reads its record) or,
  -- from minor 16, a predicate `function(row) -> bool`. A predicate that raises reads as enabled:
  -- the refresher is pcall'd by the sweep anyway, and a raise at build would cost the whole row
  -- for the sake of its dimming.
  local function isDisabled(row, pageDisabled)
    if pageDisabled then return true end
    local cond = row.disabledIf
    if type(cond) == "function" then
      local ok, v = pcall(cond, row)
      return (ok and v) and true or false
    end
    return readKey(row, cond) and true or false
  end

  local function noop() end

  --- Apply `row`'s disabled state to `widget` now, and hand back the function its refresher calls
  --- to re-apply it (minor 16; the color picker's private copy of this was the only one before).
  ---
  --- A row with no `disabledIf`, drawn outside a disabled render, is NEVER touched: it gets a no-op.
  --- Calling SetDisabled(false) on it would re-enable, on the next write anywhere, a widget the
  --- host disabled itself -- five hosts call SetDisabled on their own widgets.
  local function bindDisabled(ctx, row, widget)
    local pageDisabled = ctx.__renderDisabled and true or false
    if row.disabledIf == nil and not pageDisabled then return noop end
    if type(widget.SetDisabled) ~= "function" then return noop end
    local function apply() widget:SetDisabled(isDisabled(row, pageDisabled)) end
    apply()
    return apply
  end

  -- Write a row's value through the host's single write seam, then re-sync every widget on every
  -- panel. That is what makes paired controls just work: a "Use Class Color" toggle flips and its
  -- matching swatch grays out on the same frame. AceGUI's SetValue does not fire OnValueChanged,
  -- so this cannot recurse.
  --
  -- SCALARS, not the structural tier. Writing a value does not change which rows exist, and a
  -- rebuild on every checkbox click would tear down and recreate every widget on the page — which
  -- is exactly what the two-tier split exists to avoid. The same refresh puts a widget back when
  -- `write` refused it in combat.
  local function set(row, value)
    write(row, value)
    O.RefreshScalars()
  end

  -- Color storage is the HOST's shape, not the library's. AbsorbTracker stores {r=,g=,b=,a=};
  -- KickCD stores arrays. Picking a winner would force one of them to translate at every read site
  -- in the addon, so the codec is a descriptor option with the named-key form as the default.
  local function decodeColor(c)
    if type(d.colorDecode) == "function" then return d.colorDecode(c) end
    if type(c) ~= "table" then c = {} end
    return c.r or 1, c.g or 1, c.b or 1, c.a or 1
  end
  local function encodeColor(r, g, b, a)
    if type(d.colorEncode) == "function" then return d.colorEncode(r, g, b, a) end
    return { r = r, g = g, b = b, a = a or 1 }
  end

  -- ── tooltips and spacers ─────────────────────────────────────────────────────────────────

  --- Works on AceGUI widgets (via SetCallback) and on plain Blizzard frames (via HookScript),
  --- anchoring on widget.frame when the target is an AceGUI widget.
  function O.AttachTooltip(widget, label, tooltip)
    if not widget then return end
    local anchor = widget.frame or widget
    if not anchor then return end

    local function show()
      if not GameTooltip then return end
      GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
      if label and label ~= "" then
        GameTooltip:SetText(label, 1, 1, 1)
      end
      if tooltip and tooltip ~= "" then
        GameTooltip:AddLine(tooltip, nil, nil, nil, true)
      end
      GameTooltip:Show()
    end
    local function hide() if GameTooltip then GameTooltip:Hide() end end

    if widget.SetCallback then
      widget:SetCallback("OnEnter", show)
      widget:SetCallback("OnLeave", hide)
    elseif widget.HookScript then
      widget:HookScript("OnEnter", show)
      widget:HookScript("OnLeave", hide)
    end
  end

  --- An invisible full-width row. Used between sections, between widget rows, and between blocks
  --- on a host's landing page.
  function O.AddSpacer(scroll, height)
    local sp = O.AceGUI:Create("SimpleGroup")
    sp:SetLayout(nil)
    sp:SetFullWidth(true)
    sp:SetHeight(height)
    scroll:AddChild(sp)
    return sp
  end

  --- A section heading: an AceGUI Heading, which renders as a label flanked by side dividers, so
  --- one widget delivers both the separator and the title.
  function O.Section(ctx, label)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end

    -- Only between sections, never above the first: a leading gap reads as a broken top margin.
    if ctx.lastGroup ~= nil then
      O.AddSpacer(scroll, L.SECTION_TOP_SPACER)
    end

    local h = O.AceGUI:Create("Heading")
    h:SetText(label)
    h:SetFullWidth(true)
    h:SetHeight(L.SECTION_HEADING_H)
    if h.label and h.label.SetFontObject and _G.GameFontNormalLarge then
      h.label:SetFontObject(_G.GameFontNormalLarge)
    end
    scroll:AddChild(h)

    O.AddSpacer(scroll, L.SECTION_BOTTOM_SPACER)
    return h
  end

  --- A full-width line of text: one AceGUI Label added to the page's scroll, left-justified.
  ---
  --- `opts` is optional: `opts.fontObject` is a _G font-object NAME ("GameFontHighlight"), applied
  --- only when both the FontString and the global exist; `opts.justify` defaults to "LEFT".
  --- Returns nil, having drawn nothing, when AceGUI or the scroll is absent.
  ---
  --- This owns the `if w.label and w.label.SetJustifyH` / SetFontObject guard pair ONCE. That pair
  --- was written out per text widget per host — 28 times across six repos — and every copy is a
  --- place for one of the two halves to be forgotten, which fails silently and only in game.
  function O.TextRow(ctx, text, opts)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end

    opts = opts or {}
    local w = O.AceGUI:Create("Label")
    w:SetFullWidth(true)
    w:SetText(text)
    applyLabelFont(w, opts.fontObject)
    if w.label and w.label.SetJustifyH then
      w.label:SetJustifyH(opts.justify or "LEFT")
    end
    scroll:AddChild(w)
    return w
  end

  --- Render a whole landing-page body: logo, one-liner, then a heading and its rows per section.
  ---
  --- `spec`:
  ---   logo      string             texture path. Omitted = no logo block.
  ---   logoSize  number             defaults to LAYOUT.LANDING_LOGO.
  ---   notes     string|function()  the one-liner; a function is called at RENDER time.
  ---   sections  array of { heading = string, rows = function() -> array of string }
  ---
  --- The last host-side copy in a stack this major already owns end to end: EnsureScroll,
  --- ClearScroll, AddSpacer and Section are all here, the rows come from LibKa0s-Slash-1.0's one
  --- command-row formatter, and buildMain(ctx) is already the descriptor seam the page hangs off.
  --- Three hosts kept a private body over it and drifted, which is the same class of drift — one
  --- level up — that the shared row formatter exists to end.
  function O.BuildLandingPage(ctx, spec)
    -- The renderer owns the clear, not the registry: a landing page is re-rendered on every
    -- re-show, and stacking a second copy of the logo under the first is what happens without it.
    O.ClearScroll(ctx)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end

    spec = spec or {}
    landingLogo(O, scroll, spec)
    landingNotes(O, ctx, scroll, spec)
    landingSections(O, ctx, spec)
  end

  --- Two side-by-side action buttons (not settings) sharing one Flow row, each inset to
  --- BUTTON_PAIR_REL so the right one clears the ScrollFrame's clip rectangle (options-ui-§8).
  --- Each spec is { text, tooltip, onClick }.
  function O.InlineButtonPair(ctx, leftSpec, rightSpec)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end

    local row = O.AceGUI:Create("SimpleGroup")
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    row:SetHeight(28)

    local function makeBtn(spec)
      if not spec then return end

      -- AT BUILD TIME, and once. OptionsCompose emits the master group's two resets whether or
      -- not the host spec carried onResetAll/onResetPosition, so a spec that forgot one hands
      -- the player a button that looks live and swallows the click below. Saying so on the
      -- click instead would only tell the one person who pressed it, and tell them again every
      -- press; said here it lands once, in the log of whoever opened the panel, which is the
      -- author. Report and render, exactly as EMPTY_DROPDOWN does further down: dropping the
      -- button would leave a half-empty pair that reads as an intended layout.
      if type(spec.onClick) ~= "function" then
        print(lib.STRINGS.DEAD_BUTTON:format(tostring(spec.text or "")))
      end

      local btn = O.AceGUI:Create("Button")
      btn:SetText(spec.text or "")
      btn:SetRelativeWidth(L.BUTTON_PAIR_REL)
      -- Inside a RenderRows call carrying `opts.disabled` (minor 16) -- an afterGroup hook on a
      -- page drawn disabled -- the buttons are part of that page and are disabled with it.
      if ctx.__renderDisabled then btn:SetDisabled(true) end
      btn:SetCallback("OnClick", function()
        if not spec.onClick then return end
        -- Refused in combat (minor 23): "Reset all settings" is one of these buttons.
        if refused() then return end
        -- pcall'd and REPORTED. A host's button body reaches into live addon state, and a raise
        -- here would propagate into AceGUI's own dispatch and take the click handling of every
        -- widget on the frame down with it.
        local ok, err = pcall(spec.onClick)
        if not ok then
          print(lib.STRINGS.BUTTON_FAILED:format(tostring(err)))
        end
      end)
      O.AttachTooltip(btn, spec.text, spec.tooltip)
      row:AddChild(btn)
    end

    makeBtn(leftSpec)
    makeBtn(rightSpec)
    scroll:AddChild(row)
    O.AddSpacer(scroll, L.ROW_VSPACER)
    return row
  end

  -- ── the five makers ──────────────────────────────────────────────────────────────────────

  local function makeCheckbox(ctx, row, parent, relativeWidth)
    parent = parent or O.EnsureScroll(ctx)
    local cb = O.AceGUI:Create("CheckBox")
    cb:SetLabel(row.label or row.path)
    applyWidth(cb, relativeWidth)

    local function readValue() return read(row) and true or false end

    cb:SetValue(readValue())
    local applyDisabled = bindDisabled(ctx, row, cb)
    local function refresh()
      cb:SetValue(readValue())
      applyDisabled()
    end

    cb:SetCallback("OnValueChanged", function(_, _, value)
      set(row, value and true or false)
    end)

    O.AttachTooltip(cb, row.label, tooltipBody(row))
    parent:AddChild(cb)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return cb
  end

  local function makeSlider(ctx, row, parent, relativeWidth)
    parent = parent or O.EnsureScroll(ctx)
    local s = O.AceGUI:Create("Slider")
    s:SetLabel(row.label or row.path)
    s:SetSliderValues(row.min or 0, row.max or 1, row.step or 1)
    -- Read from the row rather than hardcoded: a 0-1 ratio row renders as a percentage, which is
    -- the whole reason the field exists in the schema.
    s:SetIsPercent(row.isPercent and true or false)
    applyWidth(s, relativeWidth)

    local applyDisabled = bindDisabled(ctx, row, s)
    local function refresh()
      local v = read(row)
      -- A corrupt SavedVariable would otherwise hand AceGUI a nil or a string and blow up the
      -- layout pass, taking the whole page with it.
      if type(v) ~= "number" then v = row.default or row.min or 0 end
      s:SetValue(v)
      applyDisabled()
    end

    local function commitSlider(value)
      -- Snapped relative to `min`, not to zero: a step that does not divide min evenly would
      -- otherwise commit values the slider can never reach by dragging.
      set(row, snapToStep(value, row.min or 0, row.step or 0))
    end

    s:SetCallback("OnMouseUp", function(_, _, value) commitSlider(value) end)

    -- Opt-in live commit, per descriptor or per row. A page whose number rows drive something the
    -- user can see while dragging — a bar's width, a button's scale — has no preview without it,
    -- and there was no hook to ask for one. The default stays release-only, so an unchanged host
    -- is untouched.
    --
    -- Throttled through the same re-armed single timer the color picker uses, rather than the
    -- per-frame write a host would write by hand. Live commits snap to the row's step exactly as
    -- the release commit does, or the release would silently correct what the drag stored.
    local liveCommit = row.commitOn or d.sliderCommit
    if liveCommit == "change" then
      -- `armed` is the library's own flag, never the host's return value (minor 31): the
      -- descriptor asks for no handle, and a C_Timer.After wrapper answers nil, which read as
      -- "not armed" on every frame and defeated the throttle.
      local pendingValue, armed
      s:SetCallback("OnValueChanged", function(_, _, value)
        if type(d.scheduleTimer) ~= "function" then return commitSlider(value) end
        pendingValue = value
        if armed then return end
        armed = true
        d.scheduleTimer(function()
          armed = false
          local v = pendingValue
          pendingValue = nil
          if v ~= nil then commitSlider(v) end
        end, DRAG_THROTTLE)
      end)
    end

    O.AttachTooltip(s, row.label, tooltipBody(row))
    parent:AddChild(s)
    refresh()
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return s
  end

  local function makeDropdown(ctx, row, parent, relativeWidth)
    parent = parent or O.EnsureScroll(ctx)
    -- A row may ask for an in-tree widget (LSM30_* for a media swatch or font preview). Fall back
    -- to the stock Dropdown when it is not registered — AceGUI-3.0-SharedMediaWidgets is optional,
    -- and the option must still render (no swatch, but usable) rather than erroring on an unknown
    -- type. Both share enough interface that the rest of this function is unchanged either way.
    local widgetType = row.dialogControl or "Dropdown"
    if widgetType ~= "Dropdown" and not O.AceGUI:GetWidgetVersion(widgetType) then
      widgetType = "Dropdown"
    end
    local dd = O.AceGUI:Create(widgetType)
    dd:SetLabel(row.label or row.path)
    applyWidth(dd, relativeWidth)

    -- A `type = "string"` row with no `values` AND no `dialogControl` is a free-text field that
    -- forgot to say so: the dispatch below sends it here and the player gets a dropdown that opens
    -- on nothing. Opting in with `dialogControl = "EditBox"` stays the rule -- see makeEditBox for
    -- why free text is not inferred from a missing list -- and this line is what makes forgetting
    -- it visible instead of silent.
    --
    -- ONLY when `row.values` is nil. An LSM-backed closure that legitimately answers empty before
    -- the media library has registered anything must NOT warn; that deferred case is the whole
    -- reason the opt-in exists.
    if row.values == nil and #enumList(row) == 0 then
      print(lib.STRINGS.EMPTY_DROPDOWN:format(tostring(row.path or row.field)))
    end

    local function applyList()
      local items, order = {}, {}
      for i, item in ipairs(enumList(row)) do
        items[item.value] = item.text
        order[i] = item.value
      end
      dd:SetList(items, order)
    end
    applyList()
    dd:SetValue(read(row))

    local applyDisabled = bindDisabled(ctx, row, dd)
    local function refresh()
      applyList()                            -- media lists grow as other addons register into them
      dd:SetValue(read(row))
      applyDisabled()
    end

    dd:SetCallback("OnValueChanged", function(_, _, value) set(row, value) end)

    O.AttachTooltip(dd, row.label, tooltipBody(row))
    parent:AddChild(dd)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return dd
  end

  -- The fifth type. Ships in -1.0 because adding a widget TYPE later is additive, but retrofitting
  -- one into a dispatch table already frozen by the major is not. Opted into with
  -- `dialogControl = "EditBox"` rather than inferred from a missing `values` list: inference would
  -- silently turn a row whose values function returned empty into a free-text field.
  local function makeEditBox(ctx, row, parent, relativeWidth)
    parent = parent or O.EnsureScroll(ctx)
    local eb = O.AceGUI:Create("EditBox")
    eb:SetLabel(row.label or row.path)
    applyWidth(eb, relativeWidth)
    if row.maxLetters then eb:SetMaxLetters(row.maxLetters) end
    eb:SetText(read(row) or "")

    local applyDisabled = bindDisabled(ctx, row, eb)
    local function refresh()
      eb:SetText(read(row) or "")
      applyDisabled()
    end

    -- OnEnterPressed only, never OnTextChanged: committing per keystroke would fire the row's
    -- onChange on every letter typed.
    eb:SetCallback("OnEnterPressed", function(_, _, text) set(row, text) end)

    O.AttachTooltip(eb, row.label, tooltipBody(row))
    parent:AddChild(eb)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return eb
  end

  local function makeColorPicker(ctx, row, parent, relativeWidth)
    parent = parent or O.EnsureScroll(ctx)
    local cp = O.AceGUI:Create("ColorPicker")
    cp:SetLabel(row.label or row.path)
    -- Default TRUE. The old `row.hasAlpha and true or false` made a declared `false`
    -- indistinguishable from an absent field, so no host could express "no alpha" even
    -- deliberately — while the codec below models alpha as a first-class component of every
    -- color it stores (`a or 1` on write, `c.a or 1` on read). Suppressing the slider by default
    -- contradicted the codec: a stored alpha the user could never reach. A host that wants the
    -- old behavior now writes `hasAlpha = false`, which it can say for the first time.
    cp:SetHasAlpha(row.hasAlpha ~= false)
    applyWidth(cp, relativeWidth)

    local function readColor() return decodeColor(read(row)) end

    cp:SetColor(readColor())

    local applyDisabled = bindDisabled(ctx, row, cp)

    local function refresh()
      cp:SetColor(readColor())
      applyDisabled()
    end

    -- AceGUI's ColorPicker fires OnValueChanged during a drag (live preview) and OnValueConfirmed
    -- on confirm or cancel (with the original color). The drag is throttled so a sustained one
    -- does not repaint at 60 Hz; the confirm commits immediately, so a cancel snaps back to the
    -- pre-drag color without waiting on the throttle window.
    --
    -- Deliberately does NOT call RefreshAllPanels: a sustained drag would re-traverse every widget
    -- on every panel every 50 ms. This is the one maker that declines the refresh.
    local function commit(r, g, b, a)
      -- Refused in combat (minor 23), and the swatch put back: this maker runs no refresh.
      if refused() then return refresh() end
      write(row, encodeColor(r, g, b, a))
    end

    -- A single re-armed timer over a reused args table, so a 60 Hz drag produces O(1) garbage
    -- rather than sixty closures and sixty tables a second. The timer is the host's (the
    -- descriptor's scheduleTimer), because embedding AceTimer here would be this library's second
    -- dependency-budget breach. `armed` is the library's own flag rather than whatever
    -- scheduleTimer returns (minor 31): a host's C_Timer.After wrapper answers nil.
    local pendingArgs
    local armed = false
    local function throttledCommit(r, g, b, a)
      if type(d.scheduleTimer) ~= "function" then return commit(r, g, b, a) end
      pendingArgs = pendingArgs or {}
      pendingArgs[1], pendingArgs[2], pendingArgs[3], pendingArgs[4] = r, g, b, a
      if armed then return end
      armed = true
      d.scheduleTimer(function()
        armed = false
        local p = pendingArgs
        pendingArgs = nil
        if p then commit(p[1], p[2], p[3], p[4]) end
      end, COLOR_THROTTLE)
    end

    cp:SetCallback("OnValueChanged",   function(_, _, r, g, b, a) throttledCommit(r, g, b, a) end)
    cp:SetCallback("OnValueConfirmed", function(_, _, r, g, b, a) commit(r, g, b, a) end)

    O.AttachTooltip(cp, row.label, tooltipBody(row))
    parent:AddChild(cp)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return cp
  end

  --- Dispatch by row.type. Returns nil for a type it does not know, rather than erroring: a
  --- misspelled type in a host's schema must cost that one row, not the whole page.
  function O.RenderField(ctx, row, parent, relativeWidth)
    if row.type == "bool"   then return makeCheckbox(ctx, row, parent, relativeWidth)    end
    if row.type == "number" then
      -- A number carrying a `values` list is an ENUM, not a range, and Slash.lua has said so
      -- since -1.0: its parseNumber refuses a value outside the list rather than clamping, and
      -- its comment calls the shape "a NUMERIC dropdown" and warns that clamping "lands BETWEEN
      -- two entries, and the renderer then has no label for what is stored". That renderer did
      -- not exist — this line is it. Until now the two majors read one row as two different
      -- things, and a host with such a row got a CLI that validated an enum and a panel that drew
      -- a slider over it.
      --
      -- INFERRED from `values`, not opted into with a `dialogControl`, because Slash infers too
      -- and an opt-in would leave the two disagreeing for every row that declares `values` and
      -- nothing else. The enumList duplication comment above states the requirement outright: the
      -- two readers MUST agree. Safe in the failure direction — a values function that answers
      -- empty falls through to the slider, which is exactly the old behavior.
      if #enumList(row) > 0 then return makeDropdown(ctx, row, parent, relativeWidth) end
      return makeSlider(ctx, row, parent, relativeWidth)
    end
    if row.type == "string" then
      if row.dialogControl == "EditBox" then
        return makeEditBox(ctx, row, parent, relativeWidth)
      end
      return makeDropdown(ctx, row, parent, relativeWidth)
    end
    if row.type == "color"  then return makeColorPicker(ctx, row, parent, relativeWidth) end
  end

  --- A non-schema checkbox wired to caller-supplied get/set instead of a settings path. For
  --- runtime-only, never-persisted toggles (a debug console's show/hide) that must NOT become
  --- saved settings — so they cannot go through makeCheckbox, which reads and writes a stored
  --- path. Registers a refresher so RefreshAllPanels re-reads live state when the thing it mirrors
  --- is changed elsewhere. spec = { label, tooltip, get, set }.
  function O.SessionCheckbox(ctx, parent, relativeWidth, spec)
    parent = parent or O.EnsureScroll(ctx)
    local cb = O.AceGUI:Create("CheckBox")
    cb:SetLabel(spec.label)
    applyWidth(cb, relativeWidth)

    cb:SetValue(spec.get() and true or false)
    -- Part of a page drawn disabled when drawn from inside it (minor 16), like InlineButtonPair.
    if ctx.__renderDisabled then cb:SetDisabled(true) end
    local function refresh() cb:SetValue(spec.get() and true or false) end

    cb:SetCallback("OnValueChanged", function(_, _, value)
      if refused() then return refresh() end        -- minor 23; the box reads live state again
      spec.set(value and true or false)
    end)

    O.AttachTooltip(cb, spec.label, spec.tooltip)
    parent:AddChild(cb)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return cb
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
  function O.RenderGrid(ctx, items)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end
    local pendingRow, pendingCount = nil, 0

    local function flushRow()
      if pendingRow then
        scroll:AddChild(pendingRow)
        O.AddSpacer(scroll, L.ROW_VSPACER)
        pendingRow, pendingCount = nil, 0
      end
    end

    -- Guarded per item, for the same reason RenderRows guards per row: a bespoke `make` reaches
    -- into live addon state, and a raise inside AceGUI's layout pass would cost every item after
    -- it.
    local function renderInto(item, parent, relativeWidth)
      if type(item.make) == "function" then
        return renderRowGuarded(print, item.path, item.make, ctx, parent, relativeWidth)
      end
      return renderRowGuarded(print, item.path, O.RenderField, ctx, item, parent, relativeWidth)
    end

    for _, item in ipairs(items) do
      if item.wide then
        flushRow()
        local r = startRow(O)
        renderInto(item, r, nil)
        scroll:AddChild(r)
        O.AddSpacer(scroll, L.ROW_VSPACER)
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

  -- ── the choice grid (minor 16) ───────────────────────────────────────────────────────────
  --
  -- One choice cell per column, then the row's label across what is left of the line. The label
  -- gives back CHOICE_CLIP_INSET for the reason BUTTON_PAIR_REL sits under half: the widget that
  -- ends at the right edge is clipped by the ScrollFrame's clip rectangle (options-ui-§8), and a
  -- line summing to exactly 1 can wrap its last cell on a float rounding.
  local CHOICE_CELL_REL   = 0.12
  local CHOICE_CLIP_INSET = 0.02
  -- The optional extra link column's width (K-2): a host's "See spells" after the row's label,
  -- opening another settings page at that row's list. The label column gives this back, the same
  -- way it gives back CHOICE_CLIP_INSET, so the line still fits one Flow row.
  local CHOICE_EXTRA_REL  = 0.18
  -- The label column's heading when the host names none. A literal, as lib.STRINGS' own are: the
  -- library carries no locale, and a host that has one passes `labelHeader`.
  local CHOICE_LABEL_HEADER = "Category"

  -- `hasExtra` is a boolean, not the extraColumn table itself: callers pass `extra ~= nil` so a
  -- spec with no extraColumn takes exactly the path it always did, and the label column's width is
  -- byte-for-byte what it was before K-2.
  local function choiceLabelRel(columnCount, hasExtra)
    local taken = columnCount * CHOICE_CELL_REL + (hasExtra and CHOICE_EXTRA_REL or 0)
    return math.max(1 - taken - CHOICE_CLIP_INSET, CHOICE_CELL_REL)
  end

  --- The header line: each column's label over its cells, then the label column's heading, then
  --- `extra.header` when the host asked for a link column (K-2).
  local function choiceHeader(scroll, columns, labelHeader, extra)
    local line = startRow(O)
    for _, col in ipairs(columns) do
      local lbl = O.AceGUI:Create("Label")
      lbl:SetText(col.label or tostring(col.value))
      lbl:SetRelativeWidth(CHOICE_CELL_REL)
      line:AddChild(lbl)
    end
    local lbl = O.AceGUI:Create("Label")
    lbl:SetText(labelHeader or CHOICE_LABEL_HEADER)
    lbl:SetRelativeWidth(choiceLabelRel(#columns, extra ~= nil))
    line:AddChild(lbl)
    if extra then
      local x = O.AceGUI:Create("Label")
      x:SetText(extra.header or "")
      x:SetRelativeWidth(CHOICE_EXTRA_REL)
      line:AddChild(x)
    end
    scroll:AddChild(line)
  end

  --- One choice cell: lit while the row holds this column's value, writing it on a click.
  ---
  --- AceGUI toggles a CheckBox on every click, so a click on the lit cell arrives as `false`.
  --- That is not a choice -- one choice per row cannot be clicked off -- so it re-lights the cell
  --- and writes nothing, rather than sweeping every panel for a no-op write. Drawn as an ordinary
  --- AceGUI checkbox check, the same as the "Only these categories" checkbox on the same panel
  --- (owner feedback, 2026-09-15: the earlier solid-fill treatment read as awkward). The exclusive
  --- one-choice-per-row behavior is this function's, never the widget's -- the widget stays a
  --- plain, unpainted CheckBox.
  local function choiceCell(ctx, row, col, line)
    local cb = O.AceGUI:Create("CheckBox")
    cb:SetLabel("")
    cb:SetRelativeWidth(CHOICE_CELL_REL)

    local function lit() return read(row) == col.value end
    cb:SetValue(lit())
    local applyDisabled = bindDisabled(ctx, row, cb)
    ctx.refreshers[#ctx.refreshers + 1] = function()
      cb:SetValue(lit())
      applyDisabled()
    end

    cb:SetCallback("OnValueChanged", function()
      if lit() then cb:SetValue(true) return end
      set(row, col.value)
    end)
    O.AttachTooltip(cb, row.label, col.label)
    line:AddChild(cb)
  end

  --- Draw the extra link column's cell for `row`, blank when `extra.cell` returns nil. Guarded on
  --- its own -- `extra.cell` is host code and may raise -- so a raise costs this one cell, not the
  --- line and not the grid, the same shape renderRowGuarded holds for a whole row.
  local function choiceExtraCell(extra, row, line)
    local ok, cell = pcall(extra.cell, row)
    local x = O.AceGUI:Create((ok and cell) and "InteractiveLabel" or "Label")
    x:SetRelativeWidth(CHOICE_EXTRA_REL)
    if ok and cell then
      x:SetText(cell.text or "")
      if type(cell.onClick) == "function" then
        x:SetCallback("OnClick", function()
          if refused() then return end                -- minor 23
          cell.onClick()
        end)
      end
      if cell.tooltip then O.AttachTooltip(x, cell.text or "", cell.tooltip) end
    else
      x:SetText("")
    end
    line:AddChild(x)
  end

  --- Fill one row's line: its cells, then its label carrying the row's tooltip, then the extra
  --- link column's cell when the host asked for one (K-2). The label dims with the cells, so a
  --- disabled row reads as disabled across the whole line.
  local function choiceLine(ctx, row, columns, line, extra)
    for _, col in ipairs(columns) do choiceCell(ctx, row, col, line) end
    local lbl = O.AceGUI:Create("InteractiveLabel")
    lbl:SetText(row.label or row.path)
    lbl:SetRelativeWidth(choiceLabelRel(#columns, extra ~= nil))
    local applyDisabled = bindDisabled(ctx, row, lbl)
    if applyDisabled ~= noop then ctx.refreshers[#ctx.refreshers + 1] = applyDisabled end
    O.AttachTooltip(lbl, row.label, tooltipBody(row))
    line:AddChild(lbl)
    if extra then choiceExtraCell(extra, row, line) end
  end

  --- The grid's body, under the disable flag O.ChoiceGrid holds for it.
  local function drawChoiceGrid(ctx, scroll, spec)
    local columns = spec.columns or {}
    local extra = spec.extraColumn
    if spec.heading then
      O.Section(ctx, spec.heading)
      ctx.lastGroup = spec.heading
    end
    choiceHeader(scroll, columns, spec.labelHeader, extra)

    -- Guarded per line, as RenderRows guards per row: a row whose `get` raises costs that line
    -- and is reported, and every line after it still draws. A half-built line is not added.
    local lines = {}
    for _, row in ipairs(spec.rows or {}) do
      local line = startRow(O)
      if renderRowGuarded(print, row.path or row.label, choiceLine, ctx, row, columns, line, extra) then
        scroll:AddChild(line)
        lines[#lines + 1] = line
      end
    end
    O.AddSpacer(scroll, L.ROW_VSPACER)
    if scroll.DoLayout then scroll:DoLayout() end
    return lines
  end

  --- A matrix of one-choice-per-row checkbox cells over rows that share one value list (minor
  --- 16): a header line of column labels, then one line per row -- a checkbox per column, lit
  --- with a yellow fill rather than an AceGUI radio dot, then the row's label with its tooltip.
  --- A category that is Default, Whitelist or Blacklist is the shape it exists for.
  ---
  --- spec = {
  ---   rows        = schema rows: `path` (or a path-less `get`/`set`), `label`, `tooltip`/`desc`,
  ---                 `disabledIf`. Read and written through the same seam as every maker, so a
  ---                 click runs RefreshScalars and every cell re-syncs. The rows should carry
  ---                 `skipRender` so the flow engine leaves them to the grid; the grid draws them
  ---                 regardless, and they stay in the schema for the CLI and the resets.
  ---   columns     = ordered { { value =, label = }, ... }. A stored value no column carries
  ---                 lights no cell: guessing a column would hide the stale value behind a choice.
  ---   heading     = optional section heading, drawn with O.Section.
  ---   labelHeader = optional heading for the label column ("Category" when absent).
  ---   disabled    = optional; draws every cell disabled, as RenderRows' `opts.disabled` does. A
  ---                 grid drawn inside a disabled render inherits that render's flag either way.
  ---   extraColumn = optional (K-2), a link column after the row label: { header = <string>,
  ---                 cell = function(row) -> { text =, onClick =, tooltip = } | nil }. The label
  ---                 column gives back this column's width, so the line still fits one Flow row.
  ---                 `cell` is host code and may raise; a raise costs only that row's cell, drawn
  ---                 as a blank Label, same as a `nil` return -- rows stay aligned either way.
  --- }
  ---
  --- Returns the row lines (full-width Flow SimpleGroups) in row order; a row that failed to draw
  --- has no line. Nil, drawing nothing, with no AceGUI.
  function O.ChoiceGrid(ctx, spec)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end
    spec = spec or {}
    local outer = ctx.__renderDisabled
    ctx.__renderDisabled = (spec.disabled or outer) and true or nil
    local ok, res = pcall(drawChoiceGrid, ctx, scroll, spec)
    ctx.__renderDisabled = outer
    if not ok then error(res, 0) end
    return res
  end

  -- ── the id input and the id list (minor 16): OptionsIds.lua and OptionsIdList.lua ──────────
  --
  -- Moved out at OptionsWidgets minor 32 (issue #32), and attached from here, where they were
  -- defined, so an instance gets its members in the same order as before. What the two files share
  -- with this one is handed over rather than restated: the sink, the combat refusal, and the row
  -- helpers. A copy without the files draws no id widget.
  local ids = lib.__AttachIds and lib.__AttachIds(O, {
    print = print, refused = refused, startRow = startRow, renderRowGuarded = renderRowGuarded,
  })
  if ids and lib.__AttachIdList then lib.__AttachIdList(O, d, ids) end

  -- ── switched sections: `shownWhen` (minor 22) ─────────────────────────────────────────────
  --
  -- A subsection chosen by a dropdown -- a tab strip whose selector is a stored setting -- is drawn
  -- only while that setting says so. A row carrying
  --   shownWhen = { path = "<selector path>", equals = <value> | { <value>, ... } }
  -- is DROPPED from the render (heading included, no space reserved) while the selector holds any
  -- other value, and the page re-renders once, on the next frame, when the selector changes. The
  -- row stays in the schema -- /<slash> list, get, set, the resets and Defaults all still reach it
  -- (options-ui-§6); only the flow engine skips it. Opt-in: a row list with no `shownWhen` in
  -- it renders exactly as before minor 22 -- the list is not copied and no refresher is added.

  --- Whether `row` is drawn under its `shownWhen` (none: always). The selector is read the way
  --- `disabledIf` reads a path (readKey), so a record-backed row reads its own record. A read that
  --- raises reads as shown: a broken selector never loses a section.
  local function shownNow(row)
    local sw = row.shownWhen
    if type(sw) ~= "table" or sw.path == nil then return true end
    local ok, value = pcall(readKey, row, sw.path)
    if not ok then return true end
    local want = sw.equals
    if type(want) ~= "table" then return value == want end
    for _, w in ipairs(want) do
      if value == w then return true end
    end
    return false
  end

  --- The rows of one render that are drawn, and the set of selector paths their `shownWhen` names --
  --- or `rows` itself and nil when none carries one, which is what keeps an opted-out host's render
  --- byte-for-byte unchanged.
  local function switchedRows(rows)
    local selectors
    for _, row in ipairs(rows) do
      local sw = row.shownWhen
      if type(sw) == "table" and sw.path ~= nil then
        selectors = selectors or {}
        selectors[sw.path] = true
      end
    end
    if not selectors then return rows, nil end
    local drawn = {}
    for _, row in ipairs(rows) do
      if shownNow(row) then
        drawn[#drawn + 1] = row
      end
    end
    return drawn, selectors
  end

  --- ONE structural re-render of `ctx`'s page, on the next frame: never inside the callback of the
  --- widget that changed the selector (the re-render releases it, an open pullout included --
  --- options-ui-§11). Coalesced per ctx; O.RefreshPanel scopes it to a page on screen and marks
  --- a hidden one dirty. Immediate where the client has no C_Timer.
  local function requestSwitch(ctx)
    if ctx.__switchQueued then return end
    ctx.__switchQueued = true
    local function run()
      ctx.__switchQueued = nil
      O.RefreshPanel(ctx, true)
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
  end

  --- The key a `shownWhen.path` names this row by: its settings path, or -- for a path-less,
  --- record-backed row (OptionsCompose's `spec.bind`) -- its record field, which is the key
  --- readKey hands that row's `get` when another row of the same record names it as a selector.
  --- The same key drawRow pairs a bound row by.
  local function selectorKey(row)
    if row.path ~= nil then return row.path end
    return row.field
  end

  --- For a selector row this render drew: a refresher that re-renders the page once its value differs
  --- from the one this render drew with -- the widget's own change, a /<slash> set, a Defaults press
  --- alike, since every one of them runs the refreshers. It re-arms on the new value, so a page with
  --- no renderer (refreshed by refreshers alone) asks once per change, never on every refresh. A
  --- selector that cannot be read gets no watcher (the sweep pcalls a refresher anyway).
  local function watchSelector(ctx, row)
    local ok, drawnWith = pcall(read, row)
    if not ok then return end
    local function refresh()
      local now = read(row)
      if now == drawnWith then return end
      drawnWith = now
      requestSwitch(ctx)
    end
    ctx.refreshers[#ctx.refreshers + 1] = refresh
  end

  --- The flow engine's loop, under the disable flag RenderRows holds for it.
  local function flowRows(ctx, scroll, allRows, afterGroup, pairWith, opts)
    local pendingRow, pendingCount = nil, 0
    local rows, selectors = switchedRows(allRows)

    -- The one-shot bookkeeping below is the LIBRARY's, and it lives in these two call-local sets
    -- rather than in the caller's tables. Consuming the caller's entries would make a second render
    -- of the same page \226\128\148 a unit switch, a ClearScroll + re-render \226\128\148 silently drop every inline
    -- button and every paired widget, for any host that hoisted its table to a file-level constant.
    local firedAfter, firedPair = {}, {}

    local function flushRow()
      if pendingRow then
        scroll:AddChild(pendingRow)
        O.AddSpacer(scroll, L.ROW_VSPACER)
        pendingRow, pendingCount = nil, 0
      end
    end

    for i, row in ipairs(rows) do
      startGroup(O, ctx, row, flushRow, opts and opts.noHeadings)
      startSubgroup(O, ctx, row, flushRow)

      if not row.skipRender then
        if opensLine(row) and pendingCount > 0 then flushRow() end

        if row.wide then
          pendingRow = drawWide(O, ctx, row, pendingRow, print)
          flushRow()
        else
          pendingRow, pendingCount =
            drawRow(O, ctx, row, pendingRow, pendingCount, pairWith, firedPair, print)
          if row.solo or pendingCount >= 2 then flushRow() end
        end
        if selectors and selectors[selectorKey(row)] then watchSelector(ctx, row) end
      end

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
    local ok, err = pcall(flowRows, ctx, scroll, rows, afterGroup, pairWith, opts)
    ctx.__renderDisabled = outer
    if not ok then error(err, 0) end
  end

  --- The per-page wrapper. `ctx.unit` is passed through as the host's filter argument, which is
  --- how a per-unit page renders only the selected unit's rows.
  function O.RenderSchema(ctx, pageKey, afterGroup, pairWith)
    O.RenderRows(ctx, d.rowsForPage(pageKey, ctx.unit) or {}, afterGroup, pairWith)
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
