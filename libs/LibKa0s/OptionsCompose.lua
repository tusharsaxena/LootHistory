-- LibKa0s-Options-1.0 — the schema composers: one declaration expands into the canonical block.
--
-- Nine addons were about to hand-write the same six font rows, the same four border rows, the same
-- four bar rows and the same eight master controls, and each copy would have been defensible on its
-- own. The SET of them is the drift this library was extracted to end: color before flags here, no
-- shadow there, "Font Outline" in one addon and "Font flags" in the next, thickness in px on one
-- page and unlabelled on another. options-ui-§15, §16 and §17 say what the blocks are; this file is
-- what makes nine copies of them identical without nine people agreeing to be careful.
--
-- ── EVERY COMPOSER IS A PURE FUNCTION RETURNING AN ARRAY OF ORDINARY SCHEMA ROWS ───────────────
--
-- It creates no widget, touches no AceGUI and reads no state. That is the whole design: what comes
-- out is indistinguishable from hand-written rows, so `rowsForPage`, `applyDefault`,
-- `RestoreDefaults`, the CLI and the reset sweep all keep working with nothing added to them -- and
-- the composers themselves are testable with no mock at all. A composer that RENDERED would have
-- had to take a ctx, and every one of those seams would have needed a second implementation.
--
-- It also never mutates what it is handed. A host hoists its spec (and its `extra` rows) to a file
-- constant and re-renders freely, which is the same promise `afterGroup` and `pairWith` make in
-- OptionsWidgets.lua and for the same reason.
--
-- Part of the Options major rather than a major of its own, and guarded with the same multi-file
-- idiom as OptionsWidgets.lua and OptionsScroll.lua: composers from one vendored copy paired with a
-- flow engine from another would emit row fields the engine does not read, and nothing would say so.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

local COMPOSE_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own — see OptionsScroll.lua for why the
-- file's own counter is not enough.
if lib.__composeMinor and lib.__composeMinor >= COMPOSE_MINOR
  and lib.__composeShellMinor == lib.MINOR then return end
lib.__composeMinor      = COMPOSE_MINOR
lib.__composeShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsCompose = COMPOSE_MINOR

-- Read-only stand-in for an absent optional table, so the readers below index one shape rather than
-- branching on nil at every lookup.
local EMPTY = {}

-- The gap between two consecutive rows of a composed block. Ten, so a host can splice a row of its
-- own between two canonical ones without renumbering either.
local ORDER_STEP = 10

-- The tab every addon's General page opens on (options-ui-§15). A literal, and the same literal the
-- host uses as its `afterGroup` key, because the group name IS the hook key.
local MASTER_GROUP = "Master controls"

-- What a color swatch's tooltip says about its companion. IN WORDS, because the swatch is never
-- disabled: it is still read for its ALPHA under class color, so graying it would tell the player
-- something untrue (options-ui-§17, anti-patterns #74).
local CLASS_COLOR_NOTE =
  "Not read while Use class color is on, except for its opacity, which always applies."

-- The font flag combinations the client accepts, and the order they are offered in. A key map plus
-- an explicit `sorting`, which is the shape the flow engine and the CLI parser both already read;
-- the empty string is a real stored value, and "None" is the only honest label for it.
local FONT_FLAGS = {
  [""]                    = "None",
  OUTLINE                 = "Outline",
  THICKOUTLINE            = "Thick outline",
  MONOCHROME              = "Monochrome",
  ["OUTLINE, MONOCHROME"] = "Monochrome outline",
}
local FONT_FLAGS_SORT = { "", "OUTLINE", "THICKOUTLINE", "MONOCHROME", "OUTLINE, MONOCHROME" }

-- General visibility is a DROPDOWN and not a boolean (options-ui-§15): a boolean can only ever
-- answer two of the four, which is why every addon that shipped a "show only in combat" checkbox
-- migrates it rather than keeping it.
local VISIBILITY_VALUES = {
  always       = "Always",
  inCombat     = "Only in combat",
  outOfCombat  = "Only out of combat",
  never        = "Never",
}
local VISIBILITY_SORT = { "always", "inCombat", "outOfCombat", "never" }

--- A flat copy, so nothing a caller handed in is written to.
local function shallow(t)
  local out = {}
  for k, v in pairs(t or EMPTY) do out[k] = v end
  return out
end

--- Append one canonical row to `rows`, unless the caller omitted that leaf.
---
--- Everything a caller can override is applied HERE and nowhere else — the path leaf, the label, the
--- default — so each composer body below reads as the canonical row list and nothing else. A row
--- that already carries a `path` keeps it verbatim: the debug-console toggle is stored outside the
--- block's own prefix, and it is the only such row.
---
--- `order` counts EMITTED rows, so an omitted row leaves no hole. The relative order of the
--- survivors is what matters and it is unchanged either way.
local function emit(spec, rows, leaf, row)
  local omit = spec.omit or EMPTY
  if omit[leaf] then return nil end

  local keys     = spec.keys or EMPTY
  local labels   = spec.labels or EMPTY
  local defaults = spec.defaults or EMPTY

  row.path     = row.path or ((spec.prefix or "") .. (keys[leaf] or leaf))
  row.page     = spec.page
  row.group    = spec.group
  row.subgroup = spec.subgroup
  row.order    = (tonumber(spec.order) or 0) + (#rows * ORDER_STEP)
  if labels[leaf]   ~= nil then row.label   = labels[leaf]   end
  if defaults[leaf] ~= nil then row.default = defaults[leaf] end

  rows[#rows + 1] = row
  return row
end

--- Append the caller's own rows AFTER the mandated block, order continuing.
---
--- A legitimate extra — a border offset, a fill direction, a bar spacing — belongs to the same
--- block and takes the block's page, group and subgroup; it is NEVER interleaved with the mandated
--- rows (options-ui-§16). It declares its own `path` in full, because an extra is a hand-written
--- row rather than a canonical leaf and there is no leaf name to prefix.
local function appendExtra(spec, rows)
  for _, row in ipairs(spec.extra or EMPTY) do
    local copy = shallow(row)
    copy.page     = spec.page
    copy.group    = spec.group
    copy.subgroup = spec.subgroup
    copy.order    = (tonumber(spec.order) or 0) + (#rows * ORDER_STEP)
    rows[#rows + 1] = copy
  end
  return rows
end

--- The class-color declaration both halves of a pair carry.
---
--- WHICH CLASS is the host's call and it is DECLARED rather than inferred (options-ui-§17): the
--- color resolves to the class of the unit the surface DESCRIBES, and a path prefix cannot be
--- trusted to say which that is — a control stored under `units.<unit>.` that draws the player's
--- own cooldowns is player-scoped. So both rows are stamped, and that stamp is what an audit reads.
local function classSource(spec)
  local cc = spec.classColor or EMPTY
  return cc.source or "player", cc.unit
end

--- The swatch half of a color pair.
local function swatchRow(spec, label, tooltip, hasAlpha)
  local source, unit = classSource(spec)
  return {
    type             = "color",
    label            = label,
    tooltip          = tooltip .. " " .. CLASS_COLOR_NOTE,
    hasAlpha         = hasAlpha ~= false,
    -- The pair can never be split across two lines by an odd number of widgets above it, which is
    -- what "immediately to its right" requires and what every author was counting by hand.
    startsLine       = true,
    classColorSource = source,
    classColorUnit   = unit,
  }
end

--- The companion half. NO `disabledIf`, on either row, ever — see CLASS_COLOR_NOTE.
local function companionRow(spec, tooltip)
  local source, unit = classSource(spec)
  local cc = spec.classColor or EMPTY
  return {
    type             = "bool",
    label            = "Use class color",
    tooltip          = tooltip,
    default          = cc.default or false,
    classColorSource = source,
    classColorUnit   = unit,
  }
end

--- Attach the composers to one instance, beside the widget makers and the flow engine.
---
--- Takes no descriptor: a composer reads no state and writes none, so there is nothing of the
--- host's for it to close over. It takes `O` because the media-backed rows call O.LSMValues, which
--- is the instance's deferred reader.
function lib.__AttachCompose(O)
  -- Published on the INSTANCE, not on the lib table, for the reason Options.lua's layout block
  -- gives: a lib-level table is shared by every instance, so handing it out lets one host's
  -- mutation retune every other host's dropdowns.
  O.FONT_FLAGS         = FONT_FLAGS
  O.FONT_FLAGS_SORT    = FONT_FLAGS_SORT
  O.VISIBILITY_VALUES  = VISIBILITY_VALUES
  O.VISIBILITY_SORT    = VISIBILITY_SORT
  O.MASTER_GROUP       = MASTER_GROUP
  O.CLASS_COLOR_NOTE   = CLASS_COLOR_NOTE

  --- A color swatch and its "use class color" companion, as exactly two adjacent rows
  --- (options-ui-§17). The primitive the three group composers below are built out of, and the one
  --- a host calls directly for a standalone swatch.
  ---
  --- `spec` takes the common fields (prefix, page, group, subgroup, order, keys, labels, defaults,
  --- omit, classColor, extra) plus:
  ---   key           string   the swatch's leaf. Defaults to "color".
  ---   companionKey  string   the companion's leaf. Defaults to "useClassColor<Key>".
  ---   label         string   the swatch's label. Defaults to "Color".
  ---   hasAlpha      boolean  defaults true, exactly as the color maker's own default does.
  function O.ColorPair(spec)
    spec = spec or EMPTY
    local rows = {}
    local key   = spec.key or "color"
    local label = spec.label or "Color"
    local companion = spec.companionKey
      or ("useClassColor" .. key:sub(1, 1):upper() .. key:sub(2))

    emit(spec, rows, key, swatchRow(spec, label, "The " .. label:lower() .. ".", spec.hasAlpha))
    emit(spec, rows, companion,
      companionRow(spec, "Take this color from the class color instead of the swatch beside it."))
    return appendExtra(spec, rows)
  end

  --- The canonical FONT block (options-ui-§16): six rows, which land as three lines.
  ---
  ---   [Font]        [Font size]
  ---   [Font color]  [Use class color]
  ---   [Font flags]  [Font shadow]
  ---
  --- An even row count plus `startsLine` on rows 1 and 3 is what makes that layout parity-proof
  --- rather than a property of how many rows happen to precede the block.
  function O.FontGroup(spec)
    spec = spec or EMPTY
    local rows = {}

    emit(spec, rows, "font", {
      type = "string", label = "Font", tooltip = "The face this text is drawn in.",
      dialogControl = "LSM30_Font", default = "Friz Quadrata TT", startsLine = true,
      values = function() return O.LSMValues("font") end,
    })
    emit(spec, rows, "fontSize", {
      type = "number", label = "Font size", tooltip = "Height of the text, in points.",
      min = 6, max = 32, step = 1, default = 12,
    })
    emit(spec, rows, "fontColor",
      swatchRow(spec, "Font color", "The color the text is drawn in.", spec.hasAlpha))
    emit(spec, rows, "useClassColorFont",
      companionRow(spec, "Draw this text in the class color instead of the swatch beside it."))
    emit(spec, rows, "fontFlags", {
      type = "string", label = "Font flags", tooltip = "Outline and monochrome rendering.",
      values = FONT_FLAGS, sorting = FONT_FLAGS_SORT, default = "OUTLINE",
    })
    emit(spec, rows, "fontShadow", {
      type = "bool", label = "Font shadow",
      tooltip = "Draw a soft shadow behind the text, for legibility over bright art.",
      default = false,
    })
    return appendExtra(spec, rows)
  end

  --- The canonical BORDER block (options-ui-§16): four rows, optionally preceded by the group's own
  --- "Show border" toggle where the addon has one.
  ---
  ---   [Border style]  [Border thickness (px)]
  ---   [Border color]  [Use class color]
  ---
  --- `spec.show = true` prepends the toggle, which then leads the block and is the only thing that
  --- may. Anything else the addon legitimately has — a border offset — goes in `spec.extra` and is
  --- appended AFTER the mandated four, never interleaved.
  function O.BorderGroup(spec)
    spec = spec or EMPTY
    local rows = {}

    if spec.show then
      emit(spec, rows, "borderShow", {
        type = "bool", label = "Show border", tooltip = "Draw a border around this element.",
        default = true, startsLine = true,
      })
    end
    emit(spec, rows, "borderStyle", {
      type = "string", label = "Border style", tooltip = "The border texture.",
      dialogControl = "LSM30_Border", default = "None", startsLine = true,
      values = function() return O.LSMValues("border") end,
    })
    emit(spec, rows, "borderSize", {
      type = "number", label = "Border thickness (px)", tooltip = "Border edge width, in pixels.",
      min = 0, max = 16, step = 1, default = 1,
    })
    emit(spec, rows, "borderColor",
      swatchRow(spec, "Border color", "The color the border is drawn in.", spec.hasAlpha))
    emit(spec, rows, "useClassColorBorder",
      companionRow(spec, "Draw this border in the class color instead of the swatch beside it."))
    return appendExtra(spec, rows)
  end

  --- The canonical BAR block (options-ui-§16): four rows over a STATUS BAR, a thing with a fill
  --- texture.
  ---
  ---   [Bar texture]  [Bar opacity]
  ---   [Bar color]    [Use class color]
  ---
  --- A group over a BACKGROUND is not a bar group. A container with a backdrop and no fill texture
  --- takes the swatch and its companion (O.ColorPair) and nothing else; inventing a texture picker
  --- for a surface that has no texture is a control wired to nothing.
  function O.BarGroup(spec)
    spec = spec or EMPTY
    local rows = {}

    emit(spec, rows, "barTexture", {
      type = "string", label = "Bar texture", tooltip = "The bar's fill texture.",
      dialogControl = "LSM30_Statusbar", default = "Blizzard", startsLine = true,
      values = function() return O.LSMValues("statusbar") end,
    })
    emit(spec, rows, "barAlpha", {
      type = "number", label = "Bar opacity", tooltip = "How opaque the bar's fill is.",
      isPercent = true, min = 0, max = 1, step = 0.05, default = 1,
    })
    emit(spec, rows, "barColor",
      swatchRow(spec, "Bar color", "The color the bar's fill is drawn in.", spec.hasAlpha))
    emit(spec, rows, "useClassColorBar",
      companionRow(spec, "Draw this bar in the class color instead of the swatch beside it."))
    return appendExtra(spec, rows)
  end

  --- The canonical MASTER CONTROLS block (options-ui-§15), and the button pair that closes it.
  ---
  ---   [Enable <AddonName>]   [General visibility]
  ---   [Master scale]         [Master alpha]
  ---   [Lock frame]           [Debug console]
  ---   [Reset position]       [Reset all settings]
  ---
  --- `spec` additionally takes:
  ---   addonName        string    for the Enable row's label. Required in practice.
  ---   frameless        boolean   the addon draws no positionable frame at all, so it omits EXACTLY
  ---                              master scale, master alpha, lock frame and reset position — and
  ---                              nothing else. It MUST NOT invent a movable frame to fill the tab.
  ---   debugConsolePath string    the console toggle's stored path, VERBATIM and unprefixed:
  ---                              session state lives outside the block's own prefix. Defaults to
  ---                              "state.debugConsole".
  ---   onResetPosition  function  the button's click handler. Omitted when frameless.
  ---   onResetAll       function  options-ui-§12's global reset, verbatim.
  ---
  --- @return table rows          the schema rows, in canonical order
  --- @return function afterGroup the hook for this group, drawing the closing button pair
  function O.MasterControls(spec)
    spec = spec or EMPTY

    -- The frame-only rows are dropped through the SAME `omit` table a caller uses, so there is one
    -- code path rather than a `frameless` branch per row.
    local omit = shallow(spec.omit)
    if spec.frameless then
      omit.scale, omit.alpha, omit.locked = true, true, true
    end
    -- The group defaults to the canonical literal without writing to the caller's table. `__index`
    -- rather than a copy so that every other field is read straight off the spec.
    local ms = setmetatable({ group = spec.group or MASTER_GROUP, omit = omit }, { __index = spec })

    local rows = {}
    emit(ms, rows, "enabled", {
      type = "bool", label = "Enable " .. tostring(spec.addonName or "this addon"),
      tooltip = "Turn the addon off without unloading it.", default = true, startsLine = true,
    })
    emit(ms, rows, "visibility", {
      type = "string", label = "General visibility",
      tooltip = "When this addon's display is shown at all.",
      values = VISIBILITY_VALUES, sorting = VISIBILITY_SORT, default = "always",
    })
    emit(ms, rows, "scale", {
      type = "number", label = "Master scale", tooltip = "Scales the whole addon's display.",
      min = 0.5, max = 2, step = 0.05, default = 1, startsLine = true,
    })
    emit(ms, rows, "alpha", {
      type = "number", label = "Master alpha", tooltip = "Opacity of the whole addon's display.",
      isPercent = true, min = 0, max = 1, step = 0.05, default = 1,
    })
    emit(ms, rows, "locked", {
      type = "bool", label = "Lock frame", tooltip = "Stop the frame being dragged.",
      default = false, startsLine = true,
    })
    emit(ms, rows, "debugConsole", {
      path = spec.debugConsolePath or "state.debugConsole",
      type = "bool", label = "Debug console", tooltip = "Show this session's developer log window.",
      -- Session state, never persisted: a console left open is not a setting the next character
      -- inherits.
      sessionOnly = true,
    })
    appendExtra(ms, rows)

    -- The two resets are the tab's closing BUTTON PAIR (options-ui-§8), not schema rows: they are
    -- acts rather than settings. A frameless addon draws "Reset all settings" alone, which is the
    -- one shape InlineButtonPair's nil right-hand spec exists for.
    local resetAll = {
      text    = "Reset all settings",
      tooltip = "Restore every setting in this addon to its default.",
      onClick = spec.onResetAll,
    }
    local resetPosition = not spec.frameless and {
      text    = "Reset position",
      tooltip = "Move the frame back to where it started.",
      onClick = spec.onResetPosition,
    } or nil

    return rows, function(ctx)
      O.InlineButtonPair(ctx, resetPosition or resetAll, resetPosition and resetAll or nil)
    end
  end
end
