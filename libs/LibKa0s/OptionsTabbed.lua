-- LibKa0s-Options-1.0 -- the tabbed page: O.RenderTabbedSchema and its helpers, which partition a
-- page's rows into the tabs of a strip and draw the selected one through the flow engine.
--
-- Peeled out of OptionsTabs.lua at its minor 12, unchanged (LK-M2-PEEL of Ka0sAddonsCommonTasks
-- docs/2026-10-31-FINDINGS_REMEDIATION), on the seam CLAUDE.md's band census named for that file. The
-- history is that file's header (minors 4 and 8).
--
-- WHO CALLS IN. lib.__AttachTabs calls lib.__AttachTabbed once per instance, at the end of its body,
-- handing over the shell's sink. Nothing else crosses the cut. A copy without this file keeps the
-- flow engine's untabbed fallback, every row under its heading.
--
-- A file of the Options major, paired on the shell's minor with the same multi-file idiom as
-- OptionsIds.lua.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- Minor 1: the tabbed page, moved here unchanged from OptionsTabs.lua (its minor 12).
-- Minor 2 (LibKa0s#59): `opts.beforeGroup` and `opts.afterSubgroup`, handed to the flow.
local TABBED_MINOR = 2
-- Paired on the SHELL's minor as well as this file's own: see OptionsScroll.lua.
if lib.__tabbedMinor and lib.__tabbedMinor >= TABBED_MINOR
  and lib.__tabbedShellMinor == lib.MINOR then return end
lib.__tabbedMinor      = TABBED_MINOR
lib.__tabbedShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsTabbed = TABBED_MINOR

local L = lib.LAYOUT

--- The tabbed page for instance `O`, descriptor `d`. `h.print` is the shell's sink.
function lib.__AttachTabbed(O, d, h)
  local print = h.print

  -- ── the tabbed page (minor 4) ─────────────────────────────────
  -- Only over a flow engine: the widget half attaches first and leaves an untabbed fallback, which
  -- this replaces. Without that half, one that raised on its first O.RenderRows is worse than none.
  if not (d and O.RenderRows) then return end

  local NO_OPTS = {}

  --- The page's groups in declaration order, each group's rows, and (minor 8) which groups hold a
  --- row the flow engine draws, i.e. one that is not skipRender.
  local function partition(rows)
    local groups, byGroup, drawable = {}, {}, {}
    for _, row in ipairs(rows) do
      local g = row.group
      if g ~= nil then
        if not byGroup[g] then byGroup[g], groups[#groups + 1] = {}, g end
        byGroup[g][#byGroup[g] + 1] = row
        if not row.skipRender then drawable[g] = true end
      end
    end
    return groups, byGroup, drawable
  end

  --- A host tab entry the strip honors: keyed, with a render function.
  local function isHostTab(t)
    return type(t) == "table" and t.key ~= nil and type(t.render) == "function"
  end

  --- The groups `opts.untabbedSkipRender` (minor 8) keeps off the strip: every row skipRender, and
  --- neither a host tab nor an afterGroup hook keyed by the group, either of which draws it. The
  --- rows stay in their bucket, so a mixed group's skipRender row is skipped as before.
  local function untabbedGroups(opts, groups, drawable, afterGroup)
    if not opts.untabbedSkipRender then return NO_OPTS end
    local claimed = {}
    for _, t in ipairs(type(opts.tabs) == "table" and opts.tabs or NO_OPTS) do
      if isHostTab(t) then claimed[t.key] = true end
    end
    if type(afterGroup) == "table" then
      for g in pairs(afterGroup) do claimed[g] = true end
    end
    local skip = {}
    for _, g in ipairs(groups) do
      if not (drawable[g] or claimed[g]) then skip[g] = true end
    end
    return skip
  end

  --- Put a host tab ahead of the tab `before` names, or last when this render draws no such tab.
  local function placeTab(tabs, entry, before)
    for i, t in ipairs(tabs) do
      if before ~= nil and t.key == before then return table.insert(tabs, i, entry) end
    end
    tabs[#tabs + 1] = entry
  end

  --- The strip: one tab per group, then the host's tabs. A host tab keyed by a group takes that
  --- group's place (and may relabel it) rather than adding a second tab. An entry with no key or
  --- no render function is not a tab.
  local function collectTabs(groups, byGroup, hostTabs, skip)
    local tabs, index, bespoke = {}, {}, {}
    for _, name in ipairs(groups) do
      if not skip[name] then
        tabs[#tabs + 1] = { key = name, label = name }
        index[name] = tabs[#tabs]
      end
    end
    for _, t in ipairs(type(hostTabs) == "table" and hostTabs or NO_OPTS) do
      if isHostTab(t) then
        bespoke[t.key] = t
        local own = index[t.key]
        if own then
          own.label, own.tooltip = t.label or own.label, t.tooltip
        elseif not byGroup[t.key] then
          local entry = { key = t.key, label = t.label or tostring(t.key), tooltip = t.tooltip }
          index[t.key] = entry
          placeTab(tabs, entry, t.before)
        end
      end
    end
    return tabs, bespoke
  end

  --- Keep the active tab when this render draws it, else heal to the first. A pointer at a tab
  --- the page no longer has would render an empty page under a strip.
  local function settleActiveTab(ctx, tabs)
    for _, t in ipairs(tabs) do if t.key == ctx.activeTab then return end end
    ctx.activeTab = tabs[1].key
  end

  --- `disabledFor(cfg)`, guarded: a raising predicate reads as enabled, as a row's disabledIf does.
  local function pageDisabled(opts)
    if type(opts.disabledFor) ~= "function" then return false end
    local ok, answer = pcall(opts.disabledFor, opts.cfg)
    return (ok and answer) and true or false
  end

  --- The notice over a page drawn disabled, and a row gap under it. A string, or a function of
  --- `opts.cfg` answering one; the host colors it with an escape sequence if it wants a color.
  local function drawDisabledNotice(ctx, opts)
    local notice = opts.disabledNotice
    if type(notice) == "function" then
      local ok, text = pcall(notice, opts.cfg)
      notice = ok and text or nil
    end
    if type(notice) ~= "string" or notice == "" or not O.TextRow then return end
    O.TextRow(ctx, notice, { fontObject = opts.disabledNoticeFont or "GameFontHighlightSmall" })
    local scroll = O.EnsureScroll(ctx)
    if scroll and O.AddSpacer then O.AddSpacer(scroll, L.ROW_VSPACER) end
  end

  --- A host tab's render under the page's disable, as RenderRows' `opts.disabled` holds it: every
  --- maker reads `ctx.__renderDisabled`, restored on the way out, a raise included.
  local function renderHostTab(ctx, tab, rows, disabled)
    local outer = ctx.__renderDisabled
    ctx.__renderDisabled = (disabled or outer) and true or nil
    local ok, err = pcall(tab.render, ctx, rows)
    ctx.__renderDisabled = outer
    if not ok then error(err, 0) end
    local scroll = O.EnsureScroll(ctx)
    if scroll and scroll.DoLayout then scroll:DoLayout() end
  end

  --- Everything under the strip: `chrome`, the disabled notice, then the tab's content.
  local function renderBody(ctx, opts, tab, rows, flow)
    local disabled = pageDisabled(opts)
    if type(opts.chrome) == "function" then opts.chrome(ctx) end
    if disabled then drawDisabledNotice(ctx, opts) end
    if disabled and opts.disabledReplaces then return end
    if tab then
      renderHostTab(ctx, tab, rows, disabled)
    elseif rows then
      O.RenderRows(ctx, rows, flow.afterGroup, flow.pairWith,
        { noHeadings = flow.noHeadings, disabled = disabled, beforeGroup = opts.beforeGroup,
          afterSubgroup = opts.afterSubgroup })
    end
  end

  --- A tab click: the host's `rerender` when it passed one (minor 8), else ClearScroll and a render
  --- with the same arguments.
  local function selectTab(ctx, key, pageKey, afterGroup, pairWith, opts)
    if key == ctx.activeTab then return end
    ctx.activeTab = key
    -- The re-render a change of subject takes. In combat the tab button refuses the click.
    if type(opts.rerender) == "function" then
      local ok, err = pcall(opts.rerender, ctx)
      if not ok then print(lib.STRINGS.RENDER_FAILED:format(tostring(pageKey), tostring(err))) end
      return
    end
    O.ClearScroll(ctx)
    O.RenderTabbedSchema(ctx, pageKey, afterGroup, pairWith, opts)
  end

  --- Render one page as a tab strip over its sections (options-ui-§13). The partition is by
  --- `group`, IN DECLARATION ORDER, one tab per group, and no second field names a tab: a tab list
  --- declared apart from the rows goes stale the first time a section is renamed (options-ui-§1).
  --- Returns the group names in tab order and (minor 4) every drawn tab's key in strip order.
  ---
  --- A ONE-GROUP PAGE DRAWS ITS STRIP TOO (OptionsWidgets minor 13): a page that lost its strip is
  --- the one that looks broken, and the tab is the only thing naming the group once `noHeadings`
  --- has suppressed the heading. No opt-out flag. A page with NO groups and no host tabs has nothing
  --- to name a tab with: an authoring defect (anti-patterns #69), REPORTED and rendered untabbed.
  --- With no AceGUI it reports an empty tab list and draws nothing.
  ---
  --- `opts` (minor 4, every field optional), for the pages five hosts hand-built around this:
  ---   tabs            { { key, label, tooltip, before, render = function(ctx, rows) } } host
  ---                   tabs drawn by their own callback. One keyed by a group takes that group's
  ---                   place in the strip and is handed the group's rows; any other is placed
  ---                   ahead of the tab `before` names, or last, and is handed nil.
  ---   cfg             the subject this render edits, handed to `disabledFor` and `disabledNotice`.
  ---   disabledFor     function(cfg) answering true to draw the page disabled: `disabledNotice`
  ---                   above the rows, and every row (a host tab's widgets through
  ---                   `ctx.__renderDisabled`) disabled. The rows are still drawn, unless
  ---                   `disabledReplaces`.
  ---   disabledNotice  a string, or function(cfg) answering one, drawn in the small font unless
  ---                   `disabledNoticeFont` names another.
  ---   chrome          function(ctx), called once per render after the strip and before the
  ---                   notice and the rows: a line that belongs above every tab. A banner is not
  ---                   chrome here -- draw it before calling this, as PageBanner says.
  ---   untabbedSkipRender  (minor 8) a group whose rows are ALL skipRender is no tab, unless a host
  ---                   tab or an afterGroup hook is keyed by it. Its rows stay in the page. The
  ---                   returned groups still name it.
  ---   disabledReplaces  (minor 8) a disabled page draws the notice and nothing under it: no rows
  ---                   and no host tab.
  ---   disabledNoticeFont  (minor 8) the notice's font object, by name; default
  ---                   "GameFontHighlightSmall".
  ---   beforeGroup, afterSubgroup  (OptionsTabbed minor 2) RenderRows' two seams, handed to the
  ---                   flow unchanged. A host tab draws its own content, so neither reaches one.
  ---   rerender        (minor 8) function(ctx): a tab click sets `ctx.activeTab` and calls this
  ---                   instead of ClearScroll and a render of its own, so the host's whole redraw
  ---                   (its chrome above, its refreshers after) runs. A raise is reported.
  --- Otherwise a tab click re-renders with the same `opts`. All four are off by default.
  function O.RenderTabbedSchema(ctx, pageKey, afterGroup, pairWith, opts)
    opts = type(opts) == "table" and opts or NO_OPTS
    local rows = d.rowsForPage(pageKey, ctx.unit) or {}
    local groups, byGroup, drawable = partition(rows)
    if not O.AceGUI then return {}, {} end

    local skip = untabbedGroups(opts, groups, drawable, afterGroup)
    local tabs, bespoke = collectTabs(groups, byGroup, opts.tabs, skip)
    if #tabs == 0 then
      -- Reported only when the page has no group at all: one whose groups are all kept off the
      -- strip by untabbedSkipRender is not an authoring defect.
      if #groups == 0 then print(lib.STRINGS.NO_GROUPS:format(tostring(pageKey))) end
      renderBody(ctx, opts, nil, rows, { afterGroup = afterGroup, pairWith = pairWith })
      return groups, {}
    end
    settleActiveTab(ctx, tabs)

    O.TabStrip(ctx, {
      tabs  = tabs,
      value = ctx.activeTab,
      onSelect = function(key) selectTab(ctx, key, pageKey, afterGroup, pairWith, opts) end,
    })

    local active = ctx.activeTab
    renderBody(ctx, opts, bespoke[active], byGroup[active],
      { afterGroup = afterGroup, pairWith = pairWith, noHeadings = true })

    local keys = {}
    for i, t in ipairs(tabs) do keys[i] = t.key end
    return groups, keys
  end
end
