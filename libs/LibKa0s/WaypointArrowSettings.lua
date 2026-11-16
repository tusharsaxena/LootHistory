-- LibKa0s-WaypointArrow-1.0 — WaypointArrowSettings.lua: the settings rows a consumer drops into its own schema.
--
-- ── WHAT IT IS ───────────────────────────────────────────────────────────────────────────────
--
-- The arrow's Style, "Use the skin's colors", Far color, Near color and Scale, as ordinary schema
-- rows (the owner's decisions of 2026-11-14, Skill Master
-- docs/superpowers/plans/2026-11-14-feedback-round8.md, row L1). A file of the WaypointArrow major,
-- paired on WaypointArrow.lua's minor the way CalloutSettings.lua is on Callout's, so rows from one
-- vendored copy never pair with an arrow from another without saying so. A payload without this
-- file loads whole and has no SettingsRows.
--
-- ── WHY ROWS WITH THE HOST'S PATHS ───────────────────────────────────────────────────────────
--
-- The Callout's section reads and writes through its instance, because the instance owns its
-- settings table. The arrow owns none: a host keeps the five values at its own paths, in its own
-- profile, beside the rest of its page, so a profile switch, copy or reset reaches them the way it
-- reaches every other row. `SettingsRows(opts)` therefore answers PATH rows (`path`, `type`,
-- `default`, `label`, `desc`, `values`, `min`, `max`, `step`, `disabledIf`, `onChange`) that a host
-- registers in its schema like its own; each row also carries `key`, the arrow setting it holds.
-- The two color rows are `disabledIf` the "Use the skin's colors" path, so they gray out while the
-- skin's colors are drawn. A row's `onChange(value)` hands the value to `opts.arrow:Configure` (when
-- an instance is given), then calls `opts.onChange(key, value)`.
--
-- ── THE TEXT BLOCK (minor 2) ─────────────────────────────────────────────────────────────────
--
-- The distance text's settings are options-ui-§16's canonical Font block: Font, Font size, Font
-- color, Use class color, Font flags (led by From skin), Font shadow, then "Use the skin's font",
-- the companion at the font path plus "FromSkin" (OptionsCompose's FontGroup with `fromSkin` and
-- `flagsFromSkin`). Given `opts.options`, the host's Options instance, the six rows and the
-- companion ARE `O.FontGroup`'s, so they carry the composer's shape, words and media picker; without
-- one this file emits the same leaves in the same order with the same words. The block's own
-- extras follow it: Text position, Show the label and Distance units.
--
-- ── WORDS ────────────────────────────────────────────────────────────────────────────────────
--
-- Every word is `lib.SETTINGS_STRINGS`, US English; a host passes `opts.L` keyed to it (read with
-- rawget, because a Ka0s locale table answers an unknown key with the key). The Font block's words
-- are the composer's own, which `opts.L` overrides leaf by leaf through the same keys; the flags
-- row's choices (`FLAGS_*`) and the swatch's class-color sentence (`CLASS_COLOR_NOTE`), which the
-- composer writes in English, are put back in `opts.L`'s words after composing.

local lib = LibStub and LibStub("LibKa0s-WaypointArrow-1.0", true)
if not lib or type(lib.__methods) ~= "table" then return end

-- Minor 1: the rows (plan row L1).
-- Minor 2 (Skill Master docs/superpowers/plans/2026-11-14-feedback-round9.md, rows L1 to L4): paired
-- on WaypointArrow minor 2 (the larger art); the Text and Position blocks and the Lock toggle.
local SETTINGS_MINOR = 2
if lib.__settingsMinor and lib.__settingsMinor >= SETTINGS_MINOR
  and lib.__settingsShellMinor == lib.MINOR then return end
lib.__settingsMinor      = SETTINGS_MINOR
lib.__settingsShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.WaypointArrowSettings = SETTINGS_MINOR

lib.SETTINGS_STRINGS = {
  STYLE = "Arrow style",
  STYLE_TIP = "How the arrow is drawn. Raised floats over the world on a soft shadow; On the ground lies flat, tilted toward you.",
  STYLE_FLAT = "Flat", STYLE_RIDGE = "Ridge", STYLE_RAISED = "Raised", STYLE_FACETED = "Faceted",
  STYLE_GROUND = "On the ground",
  USE_SKIN = "Use the skin's colors",
  USE_SKIN_TIP = "The arrow fades from the skin's accent color, far away, to its good color as you arrive. Off: your own two colors.",
  FAR = "Far color", FAR_TIP = "The arrow's color 300 yards away or more. Not read while Use the skin's colors is on.",
  NEAR = "Near color", NEAR_TIP = "The arrow's color 30 yards away or closer. Not read while Use the skin's colors is on.",
  SCALE = "Arrow scale", SCALE_TIP = "The size of the arrow and its distance, 0.5 to 2.",
  -- Minor 2: the Text block (the Font block's words are OptionsCompose's FontGroup's).
  FONT = "Font", FONT_TIP = "The face this text is drawn in.",
  FONT_SIZE = "Font size", FONT_SIZE_TIP = "Height of the text, in points.",
  FONT_COLOR = "Font color", FONT_COLOR_TIP = "The color the text is drawn in.",
  CLASS_COLOR = "Use class color",
  CLASS_COLOR_TIP = "Draw this text in the class color instead of the swatch beside it.",
  CLASS_COLOR_NOTE = "Not read while Use class color is on, except for its opacity, which always applies.",
  FONT_FLAGS = "Font flags",
  FONT_FLAGS_TIP = "Outline and monochrome rendering. From skin follows the Font outline setting on this addon's Skin tab; any other choice is drawn as picked.",
  FLAGS_SKIN = "From skin", FLAGS_NONE = "None", FLAGS_OUTLINE = "Outline", FLAGS_THICK = "Thick outline",
  FLAGS_MONO = "Monochrome", FLAGS_MONO_OUTLINE = "Monochrome outline",
  FONT_SHADOW = "Font shadow",
  FONT_SHADOW_TIP = "Draw a soft shadow behind the text, for legibility over bright art.",
  FONT_SKIN = "Use the skin's font",
  FONT_SKIN_TIP = "Draw this text in the skin's font. The font picker is not read while this is on.",
  TEXT_POSITION = "Text position",
  TEXT_POSITION_TIP = "Where the distance sits beside the arrow, or Hidden for the arrow alone.",
  POS_BELOW = "Below", POS_ABOVE = "Above", POS_LEFT = "Left", POS_RIGHT = "Right", POS_HIDDEN = "Hidden",
  SHOW_LABEL = "Show the target's name",
  SHOW_LABEL_TIP = "A second line under the distance with the name of what the arrow points to.",
  UNITS = "Distance units",
  UNITS_TIP = "Yards, or compact: thousands of yards shortened, as 4.2k yd.",
  UNITS_YARDS = "Yards", UNITS_COMPACT = "Compact (4.2k yd)",
  -- Minor 2: the Position block and the arrow's own lock.
  POSITION = "Position",
  X_OFFSET = "X offset", X_TIP = "How far right of the screen's center the arrow sits; the Arrow scale does not move it. Dragging the arrow sets it.",
  Y_OFFSET = "Y offset", Y_TIP = "How far above the screen's center the arrow sits; the Arrow scale does not move it. Dragging the arrow sets it.",
  LOCK = "Lock the arrow", LOCK_TIP = "While on, the arrow cannot be dragged. Its right-click menu still opens.",
  RESET_POSITION = "Reset position", RESET_POSITION_TIP = "Put the arrow back at its default position.",
}

local STYLE_WORD = { flat = "STYLE_FLAT", ridge = "STYLE_RIDGE", raised = "STYLE_RAISED",
  faceted = "STYLE_FACETED", ground = "STYLE_GROUND" }
lib.SCALE_STEP = 0.05

local function word(L, key)
  local v = type(L) == "table" and rawget(L, key)
  if type(v) == "string" then return v end
  return lib.SETTINGS_STRINGS[key]
end

--- `list`'s choices as `{ value, text }`, each word `words[value]` through `word`.
local function choices(L, list, words)
  local out = {}
  for i, v in ipairs(list) do out[i] = { value = v, text = word(L, words[v]) } end
  return out
end

--- The style row's choices, in STYLES order: `{ value, text }` each.
function lib.StyleValues(L) return choices(L, lib.STYLES, STYLE_WORD) end

local POSITION_WORD = { BELOW = "POS_BELOW", ABOVE = "POS_ABOVE", LEFT = "POS_LEFT", RIGHT = "POS_RIGHT",
  HIDDEN = "POS_HIDDEN" }
local UNITS_WORD = { yards = "UNITS_YARDS", compact = "UNITS_COMPACT" }
local FLAGS_WORD = { ["@skin"] = "FLAGS_SKIN", [""] = "FLAGS_NONE", OUTLINE = "FLAGS_OUTLINE",
  THICKOUTLINE = "FLAGS_THICK", MONOCHROME = "FLAGS_MONO", ["OUTLINE, MONOCHROME"] = "FLAGS_MONO_OUTLINE" }

--- Minor 2: the Text position and Distance units rows' choices, in TEXT_POSITIONS and
--- DISTANCE_UNITS order.
function lib.TextPositionValues(L) return choices(L, lib.TEXT_POSITIONS, POSITION_WORD) end
function lib.DistanceUnitsValues(L) return choices(L, lib.DISTANCE_UNITS, UNITS_WORD) end

local function colorDefault(opts, c)
  if type(opts.encodeColor) == "function" then return opts.encodeColor(c[1], c[2], c[3], c[4] or 1) end
  return { c[1], c[2], c[3], c[4] or 1 }
end

local function onChangeFor(opts, key)
  local arrow, notify = opts.arrow, opts.onChange
  return function(value)
    if type(arrow) == "table" and type(arrow.Configure) == "function" then arrow:Configure({ [key] = value }) end
    if type(notify) == "function" then notify(key, value) end
  end
end

-- One row per setting, in this order; `make(opts, L)` answers the row's own fields.
local ROWS = {
  { key = "style", make = function(_, L)
      return { type = "string", label = word(L, "STYLE"), desc = word(L, "STYLE_TIP"),
        values = lib.StyleValues(L), default = lib.DEFAULTS.style }
    end },
  { key = "useSkinColors", make = function(_, L)
      return { type = "bool", label = word(L, "USE_SKIN"), desc = word(L, "USE_SKIN_TIP"),
        default = lib.DEFAULTS.useSkinColors }
    end },
  { key = "farColor", color = true, make = function(opts, L)
      return { type = "color", hasAlpha = false, label = word(L, "FAR"), desc = word(L, "FAR_TIP"),
        default = colorDefault(opts, lib.DEFAULTS.farColor) }
    end },
  { key = "nearColor", color = true, make = function(opts, L)
      return { type = "color", hasAlpha = false, label = word(L, "NEAR"), desc = word(L, "NEAR_TIP"),
        default = colorDefault(opts, lib.DEFAULTS.nearColor) }
    end },
  { key = "scale", make = function(_, L)
      return { type = "number", label = word(L, "SCALE"), desc = word(L, "SCALE_TIP"),
        min = lib.SCALE_MIN, max = lib.SCALE_MAX, step = lib.SCALE_STEP, commitOn = "change",
        default = lib.DEFAULTS.scale }
    end },
}

-- ── the Text block (minor 2) ─────────────────────────────────────────────────────────────────

-- The Font block's leaves in the canonical order, each with its words' keys.
local FONT_LEAVES = {
  { key = "font", label = "FONT", tip = "FONT_TIP" },
  { key = "fontSize", label = "FONT_SIZE", tip = "FONT_SIZE_TIP" },
  { key = "fontColor", label = "FONT_COLOR", tip = "FONT_COLOR_TIP" },
  { key = "useClassColorFont", label = "CLASS_COLOR", tip = "CLASS_COLOR_TIP" },
  { key = "fontFlags", label = "FONT_FLAGS", tip = "FONT_FLAGS_TIP" },
  { key = "fontShadow", label = "FONT_SHADOW", tip = "FONT_SHADOW_TIP" },
  { key = "fontFromSkin", label = "FONT_SKIN", tip = "FONT_SKIN_TIP" },
}

--- The font row's choices without an Options instance: LibSharedMedia's faces, else the default's.
local function fontValues()
  return function()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local ok, list = false, nil
    if LSM and type(LSM.HashTable) == "function" then ok, list = pcall(LSM.HashTable, LSM, "font") end
    local out, any = {}, false
    for k in pairs(ok and type(list) == "table" and list or {}) do out[k], any = k, true end
    if not any then out[lib.FONT_DEFAULT] = lib.FONT_DEFAULT end
    return out
  end
end

local function flagValues(L)
  local values = {}
  for _, f in ipairs(lib.FONT_FLAGS) do values[f] = word(L, FLAGS_WORD[f]) end
  return values
end

--- The Font block's rows, built here (no Options instance): FontGroup's leaves, order, types,
--- defaults and words, `startsLine` on Font, Font color and the companion. `paths` has the
--- companion's path already.
local function ownFontRows(opts, L, paths)
  local D, out = lib.DEFAULTS, {}
  local made = {
    font = { type = "string", dialogControl = "Ka0sMedia_Font", values = fontValues(), startsLine = true,
      disabledIf = paths.fontFromSkin },
    fontSize = { type = "number", min = lib.FONT_SIZE_MIN, max = lib.FONT_SIZE_MAX, step = 1 },
    fontColor = { type = "color", hasAlpha = true, startsLine = true, classColorSource = "player" },
    useClassColorFont = { type = "bool", classColorSource = "player" },
    fontFlags = { type = "string", values = flagValues(L), sorting = lib.FONT_FLAGS },
    fontShadow = { type = "bool" },
    fontFromSkin = { type = "bool", startsLine = true },
  }
  for _, leaf in ipairs(FONT_LEAVES) do
    local row, path = made[leaf.key], paths[leaf.key]
    if path then
      row.key, row.path, row.label, row.tooltip = leaf.key, path, word(L, leaf.label), word(L, leaf.tip)
      if leaf.key == "fontColor" then row.tooltip = row.tooltip .. " " .. word(L, "CLASS_COLOR_NOTE") end
      local v = D[leaf.key]
      row.default = leaf.key == "fontColor" and colorDefault(opts, v) or v
      out[#out + 1] = row
    end
  end
  return out
end

--- A word `L` overrides, or nil: the composer keeps its own words for the rest.
local function override(L, key)
  local v = type(L) == "table" and rawget(L, key)
  return type(v) == "string" and v or nil
end

--- Whether `L` overrides any of `keys`.
local function overridesAny(L, keys)
  for _, key in ipairs(keys) do if override(L, key) then return true end end
  return false
end

local FLAG_KEYS = { "FLAGS_SKIN", "FLAGS_NONE", "FLAGS_OUTLINE", "FLAGS_THICK", "FLAGS_MONO", "FLAGS_MONO_OUTLINE" }

--- A composed Font row in `L`'s words where the composer wrote its own English: the flags row's
--- choices (a fresh table, never the composer's shared one) and the swatch's tooltip, rebuilt as
--- FONT_COLOR_TIP plus CLASS_COLOR_NOTE when `L` overrides either.
local function localizeComposed(L, row)
  if row.key == "fontFlags" and overridesAny(L, FLAG_KEYS) then
    row.values = flagValues(L)
  elseif row.key == "fontColor" and overridesAny(L, { "FONT_COLOR_TIP", "CLASS_COLOR_NOTE" }) then
    row.tooltip = word(L, "FONT_COLOR_TIP") .. " " .. word(L, "CLASS_COLOR_NOTE")
  end
  return row
end

--- The Font block's rows from the host's Options instance `O` (`O.FontGroup`, fromSkin and
--- flagsFromSkin), each given its arrow `key`. A leaf with no path is omitted.
local function composedFontRows(O, opts, L, paths, subgroup)
  local keys, omit, labels, tooltips, byPath = {}, {}, {}, {}, {}
  for _, leaf in ipairs(FONT_LEAVES) do
    local path = paths[leaf.key]
    if path then byPath[path] = leaf.key else omit[leaf.key] = true end
    if leaf.key ~= "fontFromSkin" then keys[leaf.key] = path end
    labels[leaf.key], tooltips[leaf.key] = override(L, leaf.label), override(L, leaf.tip)
  end
  local D = lib.DEFAULTS
  local rows = O.FontGroup({ prefix = "", keys = keys, omit = omit, labels = labels, tooltips = tooltips,
    page = opts.page, group = opts.group, subgroup = subgroup, fromSkin = true, flagsFromSkin = true,
    defaults = { font = D.font, fontSize = D.fontSize, fontColor = colorDefault(opts, D.fontColor),
      fontShadow = D.fontShadow } })
  local out = {}
  for _, row in ipairs(type(rows) == "table" and rows or {}) do
    row.key = byPath[row.path]
    if row.key then out[#out + 1] = localizeComposed(L, row) end
  end
  return out
end

--- The block's extras, after the Font rows: Text position, Show the label, Distance units.
local EXTRA_ROWS = {
  { key = "textPosition", make = function(L)
      return { type = "string", label = word(L, "TEXT_POSITION"), tooltip = word(L, "TEXT_POSITION_TIP"),
        values = lib.TextPositionValues(L), startsLine = true }
    end },
  { key = "showLabel", make = function(L)
      return { type = "bool", label = word(L, "SHOW_LABEL"), tooltip = word(L, "SHOW_LABEL_TIP") }
    end },
  { key = "distanceUnits", make = function(L)
      return { type = "string", label = word(L, "UNITS"), tooltip = word(L, "UNITS_TIP"),
        values = lib.DistanceUnitsValues(L) }
    end },
}

-- ── the Position block (minor 2) ─────────────────────────────────────────────────────────────

local function lockRow(L, path)
  return { key = "lock", path = path, type = "bool", label = word(L, "LOCK"), tooltip = word(L, "LOCK_TIP"),
    default = lib.DEFAULTS.lock, startsLine = true }
end

--- The Reset position button's handler: the instance's ResetPosition, then `opts.onResetPosition`;
--- nil with neither, and then there is no button.
local function resetHandler(opts)
  local arrow, after = opts.arrow, opts.onResetPosition
  local hasArrow = type(arrow) == "table" and type(arrow.ResetPosition) == "function"
  if not hasArrow and type(after) ~= "function" then return nil end
  return function()
    if hasArrow then arrow:ResetPosition() end
    if type(after) == "function" then after() end
  end
end

--- X offset and Y offset as PositionBlock draws them, built here (no Options instance).
local function ownPositionRows(L, paths)
  local out = {}
  for _, a in ipairs({ { "x", "X_OFFSET", "X_TIP" }, { "y", "Y_OFFSET", "Y_TIP" } }) do
    if paths[a[1]] then
      out[#out + 1] = { key = a[1], path = paths[a[1]], type = "number", label = word(L, a[2]),
        tooltip = word(L, a[3]), default = lib.DEFAULTS[a[1]], min = lib.POSITION_MIN,
        max = lib.POSITION_MAX, step = 1, startsLine = a[1] == "x" or nil }
    end
  end
  if paths.lock then out[#out + 1] = lockRow(L, paths.lock) end
  return out
end

--- The Position block from the host's Options instance (`O.PositionBlock`): its X and Y offset
--- rows, the Lock row as its extra, and its Reset position hook.
local function composedPositionRows(O, opts, L, paths, subgroup)
  local omit = { x = not paths.x or nil, y = not paths.y or nil }
  local rows, hook = O.PositionBlock({ prefix = "", keys = { x = paths.x, y = paths.y }, omit = omit,
    labels = { x = override(L, "X_OFFSET"), y = override(L, "Y_OFFSET") },
    tooltips = { x = word(L, "X_TIP"), y = word(L, "Y_TIP") },
    defaults = { x = lib.DEFAULTS.x, y = lib.DEFAULTS.y }, min = lib.POSITION_MIN, max = lib.POSITION_MAX,
    page = opts.page, group = opts.group, subgroup = subgroup, onReset = resetHandler(opts),
    resetText = word(L, "RESET_POSITION"), resetTooltip = word(L, "RESET_POSITION_TIP"),
    extra = paths.lock and { lockRow(L, paths.lock) } or nil })
  local byPath, out = { [paths.x or ""] = "x", [paths.y or ""] = "y", [paths.lock or ""] = "lock" }, {}
  for _, row in ipairs(type(rows) == "table" and rows or {}) do
    row.key = byPath[row.path]
    if row.key then out[#out + 1] = row end
  end
  return out, hook
end

--- The Position block on `subgroup`: composed with a Reset position hook, or built here without.
local function positionRows(opts, L, paths, subgroup)
  local O = opts.options
  if type(O) == "table" and type(O.PositionBlock) == "function" and (paths.x or paths.y) then
    return composedPositionRows(O, opts, L, paths, subgroup)
  end
  return ownPositionRows(L, paths), nil
end

--- The host's paths with the companion's filled in (the font path plus "FromSkin").
local function withCompanion(paths)
  local out = {}
  for k, v in pairs(paths) do if type(v) == "string" and v ~= "" then out[k] = v end end
  out.fontFromSkin = lib.__pathOf(paths, "fontFromSkin")
  return out
end

--- The Text block: the Font rows (composed, or built here), then the extras, on `subgroup`.
local function textRows(opts, L, paths, subgroup)
  local O = opts.options
  local font
  if type(O) == "table" and type(O.FontGroup) == "function" then
    font = composedFontRows(O, opts, L, paths, subgroup)
  else
    font = ownFontRows(opts, L, paths)
  end
  for _, spec in ipairs(EXTRA_ROWS) do
    if paths[spec.key] then
      local row = spec.make(L)
      row.key, row.path, row.default = spec.key, paths[spec.key], lib.DEFAULTS[spec.key]
      font[#font + 1] = row
    end
  end
  return font
end

--- Stamp the host's placement and the change route on `row`.
local function place(opts, row, subgroup)
  row.page, row.group, row.subgroup = opts.page, opts.group, subgroup
  row.onChange = onChangeFor(opts, row.key)
  return row
end

--- The look's rows (minor 1's five), into `out`.
local function lookRows(opts, L, paths, out)
  for _, spec in ipairs(ROWS) do
    local path = paths[spec.key]
    if path then
      local row = spec.make(opts, L)
      row.path, row.key = path, spec.key
      if spec.color and paths.useSkinColors then row.disabledIf = paths.useSkinColors end
      out[#out + 1] = place(opts, row, opts.subgroup)
    end
  end
end

--- The arrow's settings rows, for the host's schema. `opts.paths` names the host's path for each
--- setting (`style`, `useSkinColors`, `farColor`, `nearColor`, `scale`; from minor 2 the Text
--- block's `font`, `fontSize`, `fontColor`, `useClassColorFont`, `fontFlags`, `fontShadow`,
--- `textPosition`, `showLabel`, `distanceUnits`; "Use the skin's font" sits at the font path plus
--- "FromSkin"; and the Position block's `x`, `y` and `lock`); a setting with no path has no row.
--- `opts.page`, `opts.group` and `opts.subgroup` are copied onto every row (minor 2:
--- `opts.textSubgroup` for the Text block's, falling back to `opts.subgroup`; `opts.positionSubgroup`
--- for the Position block's, which is its own "Position" (the `POSITION` word, PositionBlock's
--- canonical heading) when it is not given, never `opts.subgroup`); `opts.L`
--- overrides the words; `opts.encodeColor(r, g, b, a)` shapes the color rows' defaults the way the
--- host stores colors (`{ r, g, b, a }` without it); `opts.options` (an Options instance, minor 2)
--- composes the Font and Position rows; `opts.arrow` (an instance) is configured on every change,
--- then `opts.onChange(key, value)` is called. Answers a fresh list, and (minor 2) a table of
--- `afterSubgroup` hooks keyed by subgroup for RenderRows (empty when there are none): with
--- `opts.options`, the Position block's Reset position button, which calls `opts.arrow`'s
--- ResetPosition and then `opts.onResetPosition()` (no button with neither). Reset position NEEDS
--- `opts.options`: the button is PositionBlock's, and without an Options instance the block is the
--- X, Y and Lock rows alone, so such a host draws its own reset and calls the instance's
--- ResetPosition (or the right-click menu's Reset position serves).
function lib.SettingsRows(opts)
  opts = type(opts) == "table" and opts or {}
  local paths = withCompanion(type(opts.paths) == "table" and opts.paths or {})
  local L, out = opts.L, {}
  lookRows(opts, L, paths, out)
  local textSub = opts.textSubgroup or opts.subgroup
  for _, row in ipairs(textRows(opts, L, paths, textSub)) do out[#out + 1] = place(opts, row, textSub) end
  local posSub = opts.positionSubgroup or word(L, "POSITION")
  local posRows, hook = positionRows(opts, L, paths, posSub)
  for _, row in ipairs(posRows) do out[#out + 1] = place(opts, row, posSub) end
  return out, hook and { [posSub] = hook } or {}
end

--- The same rows from an instance: `opts.arrow` is this one.
function lib.__methods:SettingsRows(opts)
  local o = {}
  for k, v in pairs(type(opts) == "table" and opts or {}) do o[k] = v end
  o.arrow = self
  return lib.SettingsRows(o)
end
