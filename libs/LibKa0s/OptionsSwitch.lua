-- LibKa0s-Options-1.0 -- the switched sections: a row carrying `shownWhen` is drawn only while the
-- setting (or settings) that choose it say so, and the page re-renders once, on the next frame, when
-- one of them changes. The flow engine (OptionsWidgets.lua's flowRows) asks this file which rows of a
-- render are drawn and which of them are selectors to watch.
--
-- Peeled out of OptionsWidgets.lua at its minor 37 (LK-10 of Ka0sAddonsCommonTasks
-- docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK, decision D-17), on the seam CLAUDE.md's band census named
-- for that file, because the OR form below took it past its 1450-line re-check trigger. The
-- single-path form moved unchanged (OptionsWidgets minor 22 to 36); the `any` form is new here.
--
-- WHO CALLS IN. lib.__AttachWidgets calls lib.__AttachSwitch at the point these helpers used to be
-- defined, handing over the instance's two reads (`read`, the row's own value; `readKey`, another
-- key read on a row's behalf), and keeps the three functions it answers. Nothing else crosses the
-- cut. A copy without this file draws every row and watches nothing: no row is ever lost.
--
-- A fifteenth file of the Options major rather than a major of its own, guarded with the same
-- multi-file idiom as OptionsIds.lua: a switch from one vendored copy paired with a shell from
-- another would be handed reads it does not expect, and nothing would say so.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- Minor 1: the switched sections, moved here from OptionsWidgets.lua (its minor 37), and the OR
-- form `shownWhen = { any = { { path, equals }, ... } }` (LK-10, D-17).
local SWITCH_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own -- see OptionsScroll.lua for why the
-- file's own counter is not enough.
if lib.__switchMinor and lib.__switchMinor >= SWITCH_MINOR
  and lib.__switchShellMinor == lib.MINOR then return end
lib.__switchMinor      = SWITCH_MINOR
lib.__switchShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsSwitch = SWITCH_MINOR

-- ── the two forms ────────────────────────────────────────────────────────────────────────────
--
-- A subsection chosen by a dropdown -- a tab strip whose selector is a stored setting -- is drawn
-- only while that setting says so. A row carrying
--   shownWhen = { path = "<selector path>", equals = <value> | { <value>, ... } }
-- is DROPPED from the render (heading included, no space reserved) while the selector holds any
-- other value, and the page re-renders once, on the next frame, when the selector changes. The
-- row stays in the schema -- /<slash> list, get, set, the resets and Defaults all still reach it
-- (options-ui-§6); only the flow engine skips it. Opt-in: a row list with no `shownWhen` in
-- it renders exactly as before minor 22 -- the list is not copied and no refresher is added.
--
-- THE OR FORM (minor 1, D-17). A section that either of two dropdowns can choose -- DropWatcher's
-- Pixel border section, shown when the main OR the off-spec glow style is Pixel -- carries
--   shownWhen = { any = { { path = p1, equals = ... }, { path = p2, equals = ... }, ... } }
-- and is drawn while ANY clause holds. Every clause's path is a selector, watched as the single
-- form's is, so a change to any of them re-renders the page once (coalesced per page, so two in
-- one frame still cost one). A clause that is not a table or names no path holds for nothing and
-- is never watched; an `any` with no well-formed clause switches nothing, so its row is always
-- drawn. With `any` present, a top-level `path` is ignored.

--- The clauses a `shownWhen` names: its `any` list, or the single form as a list of one; nil for a
--- row with no switch.
local function clausesOf(sw)
  if type(sw) ~= "table" then return nil end
  if type(sw.any) == "table" then return sw.any end
  if sw.path ~= nil then return { sw } end
  return nil
end

--- Attach the switched sections to one instance. `w.read(row)` reads a row's own value and
--- `w.readKey(row, key)` another key on its behalf. Answers { switchedRows, selectorKey,
--- watchSelector } for the flow engine.
function lib.__AttachSwitch(O, w)
  local read, readKey = w.read, w.readKey

  --- Whether one clause holds for `row`. The selector is read the way `disabledIf` reads a path
  --- (readKey), so a record-backed row reads its own record. A read that raises reads as shown:
  --- a broken selector never loses a section.
  local function clauseHolds(row, clause)
    if type(clause) ~= "table" or clause.path == nil then return false end
    local ok, value = pcall(readKey, row, clause.path)
    if not ok then return true end
    local want = clause.equals
    if type(want) ~= "table" then return value == want end
    for _, v in ipairs(want) do
      if value == v then return true end
    end
    return false
  end

  --- Whether `row` is drawn under its `shownWhen` (none: always): any clause holding. An `any`
  --- with no well-formed clause is no switch at all, as a single form with no path is.
  local function shownNow(row)
    local clauses = clausesOf(row.shownWhen)
    if not clauses then return true end
    local formed = false
    for _, clause in ipairs(clauses) do
      if clauseHolds(row, clause) then return true end
      formed = formed or (type(clause) == "table" and clause.path ~= nil)
    end
    return not formed
  end

  --- The rows of one render that are drawn, and the set of selector paths their `shownWhen` names --
  --- or `rows` itself and nil when none carries one, which is what keeps an opted-out host's render
  --- byte-for-byte unchanged.
  local function switchedRows(rows)
    local selectors
    for _, row in ipairs(rows) do
      for _, clause in ipairs(clausesOf(row.shownWhen) or {}) do
        if type(clause) == "table" and clause.path ~= nil then
          selectors = selectors or {}
          selectors[clause.path] = true
        end
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

  --- The key a `shownWhen` clause's path names this row by: its settings path, or -- for a
  --- path-less, record-backed row (OptionsCompose's `spec.bind`) -- its record field, which is the
  --- key readKey hands that row's `get` when another row of the same record names it as a
  --- selector. The same key drawRow pairs a bound row by.
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

  return { switchedRows = switchedRows, selectorKey = selectorKey, watchSelector = watchSelector }
end
