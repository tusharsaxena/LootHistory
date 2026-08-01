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

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

local WIDGETS_MINOR = 5
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
-- Live-slider commits reuse the colour picker's throttle: a 60 Hz drag would otherwise fan a
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

-- Both enum shapes the collection actually declares, normalised to one ordered list of
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

--- Attach the widget makers and the flow engine to one instance. Called at the end of lib:New, so
--- every host gets its own closures over its own descriptor.
function lib.__AttachWidgets(O, d)
  local print = d.print or function() end

  local function get(path) return d.get(path) end

  -- Write a row's value through the host's single write seam, then re-sync every widget on every
  -- panel. That is what makes paired controls just work: a "Use Class Color" toggle flips and its
  -- matching swatch grays out on the same frame. AceGUI's SetValue does not fire OnValueChanged,
  -- so this cannot recurse.
  --
  -- SCALARS, not the structural tier. Writing a value does not change which rows exist, and a
  -- rebuild on every checkbox click would tear down and recreate every widget on the page — which
  -- is exactly what the two-tier split exists to avoid.
  local function set(row, value)
    d.set(row.path, value)
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
      local btn = O.AceGUI:Create("Button")
      btn:SetText(spec.text or "")
      btn:SetRelativeWidth(L.BUTTON_PAIR_REL)
      btn:SetCallback("OnClick", function()
        if not spec.onClick then return end
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

    local function readValue() return get(row.path) and true or false end

    cb:SetValue(readValue())
    local function refresh() cb:SetValue(readValue()) end

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

    local function refresh()
      local v = get(row.path)
      -- A corrupt SavedVariable would otherwise hand AceGUI a nil or a string and blow up the
      -- layout pass, taking the whole page with it.
      if type(v) ~= "number" then v = row.default or row.min or 0 end
      s:SetValue(v)
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
    -- Throttled through the same re-armed single timer the colour picker uses, rather than the
    -- per-frame write a host would write by hand. Live commits snap to the row's step exactly as
    -- the release commit does, or the release would silently correct what the drag stored.
    local liveCommit = row.commitOn or d.sliderCommit
    if liveCommit == "change" then
      local pendingValue, dragTimer
      s:SetCallback("OnValueChanged", function(_, _, value)
        if type(d.scheduleTimer) ~= "function" then return commitSlider(value) end
        pendingValue = value
        if dragTimer then return end
        dragTimer = d.scheduleTimer(function()
          dragTimer = nil
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

    local function applyList()
      local items, order = {}, {}
      for i, item in ipairs(enumList(row)) do
        items[item.value] = item.text
        order[i] = item.value
      end
      dd:SetList(items, order)
    end
    applyList()
    dd:SetValue(get(row.path))

    local function refresh()
      applyList()                            -- media lists grow as other addons register into them
      dd:SetValue(get(row.path))
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
    eb:SetText(get(row.path) or "")

    local function refresh() eb:SetText(get(row.path) or "") end

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
    -- colour it stores (`a or 1` on write, `c.a or 1` on read). Suppressing the slider by default
    -- contradicted the codec: a stored alpha the user could never reach. A host that wants the
    -- old behaviour now writes `hasAlpha = false`, which it can say for the first time.
    cp:SetHasAlpha(row.hasAlpha ~= false)
    applyWidth(cp, relativeWidth)

    local function readColor() return decodeColor(get(row.path)) end

    cp:SetColor(readColor())

    local function applyDisabled()
      if row.disabledIf then
        cp:SetDisabled(get(row.disabledIf) and true or false)
      end
    end
    applyDisabled()

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
      d.set(row.path, encodeColor(r, g, b, a))
    end

    -- A single re-armed timer over a reused args table, so a 60 Hz drag produces O(1) garbage
    -- rather than sixty closures and sixty tables a second. The timer is the host's (the
    -- descriptor's scheduleTimer), because embedding AceTimer here would be this library's second
    -- dependency-budget breach.
    local pendingArgs
    local timer
    local function throttledCommit(r, g, b, a)
      if type(d.scheduleTimer) ~= "function" then return commit(r, g, b, a) end
      pendingArgs = pendingArgs or {}
      pendingArgs[1], pendingArgs[2], pendingArgs[3], pendingArgs[4] = r, g, b, a
      if timer then return end
      timer = d.scheduleTimer(function()
        timer = nil
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
      -- empty falls through to the slider, which is exactly the old behaviour.
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
    local function refresh() cb:SetValue(spec.get() and true or false) end

    cb:SetCallback("OnValueChanged", function(_, _, value)
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

    local function startRow()
      local r = O.AceGUI:Create("SimpleGroup")
      r:SetLayout("Flow")
      r:SetFullWidth(true)
      return r
    end
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
      local ok, err
      if type(item.make) == "function" then
        ok, err = pcall(item.make, ctx, parent, relativeWidth)
      else
        ok, err = pcall(O.RenderField, ctx, item, parent, relativeWidth)
      end
      if not ok then
        print(lib.STRINGS.ROW_FAILED:format(tostring(item.path or "?"), tostring(err)))
      end
      return ok
    end

    for _, item in ipairs(items) do
      if item.wide then
        flushRow()
        local r = startRow()
        renderInto(item, r, nil)
        scroll:AddChild(r)
        O.AddSpacer(scroll, L.ROW_VSPACER)
      else
        if not pendingRow then pendingRow = startRow() end
        if renderInto(item, pendingRow, HALF) then
          pendingCount = pendingCount + 1
        end
        if pendingCount >= 2 then flushRow() end
      end
    end
    flushRow()
  end

  function O.RenderRows(ctx, rows, afterGroup, pairWith)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end
    local pendingRow, pendingCount = nil, 0

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

    local function startRow()
      local r = O.AceGUI:Create("SimpleGroup")
      r:SetLayout("Flow")
      r:SetFullWidth(true)
      return r
    end

    for i, row in ipairs(rows) do
      if row.group and row.group ~= ctx.lastGroup then
        flushRow()                 -- the previous group's tail row
        O.Section(ctx, row.group)
        ctx.lastGroup = row.group
      end

      if not row.skipRender then
        if row.solo and pendingCount > 0 then
          flushRow()
        end

        if not pendingRow then pendingRow = startRow() end
        -- Each ROW is guarded, not just the page. One corrupt saved value, or one `values`
        -- function that raises because the media library it queries is half-loaded, used to take
        -- the whole page down from inside AceGUI's layout pass — every row after it never drew,
        -- and the user saw a panel that simply stopped mid-way with no error naming the row.
        -- The page-level guard added in Options minor 3 catches a raising BUILDER; this catches a
        -- raising ROW, which is the more common failure and the one a host cannot pre-empt.
        local ok, err = pcall(O.RenderField, ctx, row, pendingRow, HALF)
        if ok then
          pendingCount = pendingCount + 1
        else
          print(lib.STRINGS.ROW_FAILED:format(tostring(row.path or "?"), tostring(err)))
        end
        if pairWith and row.path and pairWith[row.path] and not firedPair[row.path]
           and pendingCount == 1 then
          pairWith[row.path](ctx, pendingRow)
          firedPair[row.path] = true     -- one-shot, per RenderRows call
          pendingCount = pendingCount + 1
        end
        if row.solo or pendingCount >= 2 then flushRow() end
      end

      local nextRow = rows[i + 1]
      if afterGroup and row.group
         and (not nextRow or nextRow.group ~= row.group)
         and afterGroup[row.group] and not firedAfter[row.group] then
        flushRow()                 -- afterGroup buttons start on a fresh line
        afterGroup[row.group](ctx)
        firedAfter[row.group] = true -- one-shot, per RenderRows call
      end
    end
    flushRow()
    if scroll.DoLayout then scroll:DoLayout() end
  end

  --- The per-page wrapper. `ctx.unit` is passed through as the host's filter argument, which is
  --- how a per-unit page renders only the selected unit's rows.
  function O.RenderSchema(ctx, pageKey, afterGroup, pairWith)
    O.RenderRows(ctx, d.rowsForPage(pageKey, ctx.unit) or {}, afterGroup, pairWith)
  end
end
