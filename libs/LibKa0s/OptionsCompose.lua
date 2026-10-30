-- LibKa0s-Options-1.0 — the schema composers: one declaration expands into the canonical block.
--
-- Nine addons were about to hand-write the same six font rows, the same four border rows, the same
-- four bar rows and the same eight master controls, and each copy would have been defensible on its
-- own. The SET of them is the drift this library was extracted to end: color before flags here, no
-- shadow there, "Font Outline" in one addon and "Font flags" in the next, thickness in px on one
-- page and unlabeled on another. options-ui-§15, §16 and §17 say what the blocks are; this file is
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

local COMPOSE_MINOR = 14
-- Minor 8: O.StrataTooltip(values[, strings]), the one tooltip every player strata row carries
-- (frame-layering-§1, options-ui-§16).
-- Minor 9: MasterControls takes `notes`, `resetPositionTooltip` and `lockIsPreview`, the only ways a
-- host extends the composed words; the alpha row reads Master opacity (stored leaf unchanged); and
-- with Lock frame omitted, Minimap button packs beside Debug console (options-ui-§15, v2.88.0).
-- Minor 10: the group composers take `tooltips` beside `labels`, replacing a leaf's tooltip where the
-- canonical words misdescribe the host's wiring; a swatch keeps its class-color sentence after it,
-- and MasterControls ignores the field (options-ui-§16, v2.88.0).
-- Minor 11: O.ResetAllTooltip(tail), the Reset all settings tooltip for the General page's header
-- Defaults, read from the descriptor exactly as the button reads it (options-ui-§12, U-04).
-- Minor 12: FontGroup, BorderGroup and BarGroup take an opt-in `fromSkin = true`, which adds one
-- companion bool `<key>FromSkin` ("Use the skin's font / border / texture", default false) after the
-- canonical rows. While it is set the media picker is disabled and shows the skin's value, read at
-- call time (LK-07 of the skinning run, the owner's ruling R3). No sentinel enters a media list.
-- Minor 13: BorderGroup takes `fromSkin = "icon"` (LK-04 of Ka0sAddonsCommonTasks
-- docs/2026-10-29-SKINNING_ROLLOUT, gap DW-G14): the same companion, following the skin's icon
-- border family (`icon.borderStyle`, `icon.borderSize`, SkinDefs minor 15) rather than the bar's,
-- and governing the thickness slider as well as the style picker. `fromSkin = true` is unchanged.
-- Minor 14 (LK-04 of Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK, the owner's ruling
-- D-07): FontGroup takes `flagsFromSkin = true`, which leads the Font flags row with "From skin" (the
-- Skin major's FROM_SKIN, "@skin") and makes it the row's default; the host draws with
-- `S.FontFlags(stored)` (LibKa0s-Skin-1.0 SkinPaintExtras minor 7), which resolves it through the
-- owner's Font outline and lets a picked flag win. A flags value is a CLI value, not a media path, so
-- the sentinel is honest here. `fromSkin = true, flagsFromSkin = true` is the minimum font setting
-- D-07 asks of every element: face (with "Use the skin's font"), size, color with its class-color
-- companion, flags with From skin, and shadow. Without `flagsFromSkin` the block is minor 13's.
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

-- What a player strata row's tooltip says, in three parts (frame-layering-§1, player-chosen
-- strata). Written once here so no host restates the tiers: BASE always, DIALOG when the row offers
-- Dialog or above, POPUP when it offers Fullscreen Dialog or Tooltip. ASCII only, and US English.
local STRATA_TEXT = {
  BASE   = "The layer this frame draws in. Background and Low draw under most of the interface, Medium is the default for displays, and High draws over other windows, in the same layer as the game's Settings window.",
  DIALOG = " Dialog and above also cover confirmation dialogs, this addon's debug console and the Settings window, so a frame placed there can hide them.",
  POPUP  = " Fullscreen Dialog and Tooltip can also cover dropdown menus and tooltips.",
}

-- The offered strata that earn each appended part. DIALOG and above for the DIALOG sentence; the
-- two that also cover dropdown menus and tooltips for the POPUP one.
local STRATA_DIALOG_UP = { DIALOG = true, FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }
local STRATA_POPUP_UP  = { FULLSCREEN_DIALOG = true, TOOLTIP = true }

--- The strata keys a row offers: the strings of an array, or the keys of a map such as a dropdown's
--- `{ DIALOG = "Dialog", ... }`. A non-table offers none.
local function offeredStrata(values)
  local offered = {}
  if type(values) ~= "table" then return offered end
  for k, v in pairs(values) do
    if type(k) == "number" then
      if type(v) == "string" then offered[v] = true end
    else
      offered[k] = true
    end
  end
  return offered
end

--- True when any key of `set` is in `offered`.
local function offersAny(offered, set)
  for key in pairs(set) do
    if offered[key] then return true end
  end
  return false
end

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

-- The same list led by "From skin" (minor 14, `flagsFromSkin`): the Skin major's FROM_SKIN, which
-- `S.FontFlags` resolves through the owner's Font outline. Private, as copies, so no host's list and
-- no instance member changes shape.
local FLAGS_FROM_SKIN = "@skin"
local FONT_FLAGS_SKIN = { [FLAGS_FROM_SKIN] = "From skin" }
for k, v in pairs(FONT_FLAGS) do FONT_FLAGS_SKIN[k] = v end
local FONT_FLAGS_SKIN_SORT = { FLAGS_FROM_SKIN }
for _, k in ipairs(FONT_FLAGS_SORT) do FONT_FLAGS_SKIN_SORT[#FONT_FLAGS_SKIN_SORT + 1] = k end
local FLAGS_SKIN_TIP = "Outline and monochrome rendering. From skin follows the Font outline setting on "
  .. "this addon's Skin tab; any other choice is drawn as picked."

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

-- ── THE RECORD-BACKED ARM (compose minor 4) ─────────────────────────────────────────────────────
--
-- Every composer takes `spec.bind` as an alternative to settings paths, for a page that edits
-- REGISTRY RECORDS -- PanelMaster's panel editor, whose three options-ui-§16 groups could not
-- compose while every row came out path-keyed (PanelMaster#48, PANELMASTER-A-03).
--
--   spec.bind = {
--     set    = function(field, value, row) end,   -- required: the record's single write seam
--     get    = function(field, row) return v end, -- read the LIVE record
--     record = function() return rec end,         -- or this, and get becomes record()[field]
--   }
--
-- A bound row carries NO `path`. It carries `field` -- exactly what its path would have been, so
-- `prefix` and `keys` rename a record field the way they rename a leaf -- and `get` / `set`
-- closures, which the flow engine uses for any row without a path (OptionsWidgets minor 15).
-- Everything else is the composer's, unchanged: the rows, their order, their labels and defaults,
-- `startsLine`, the class-color stamps. The arm changes where a value lives, never which controls
-- a block has.
--
-- Bound rows are for DIRECT rendering -- `O.RenderField` into the host's own container, or
-- `O.RenderRows` over the returned list. They are not settings: they have no path for the CLI to
-- address or for RestoreDefaults to reset, so they must never be put in the host's schema. A
-- record's reset is the host's, as it always was.
--
-- A spec with no `bind` never reaches any of this, and emits byte-for-byte what minor 3 emitted
-- (tests/fixture_compose_golden.lua holds the record that proves it).

--- The reader a bind supplies, refusing a bind that cannot both read and write. A bound control
--- with nowhere to write is a dead control that looks alive; refusing it at compose time names the
--- host instead of shipping it.
local function bindReader(bind)
  if type(bind.set) ~= "function" then
    error("LibKa0s-Options: spec.bind needs set(field, value, row) -- a bound row must be able to write", 5)
  end
  if type(bind.get) == "function" then return bind.get end
  if type(bind.record) == "function" then
    return function(field)
      local rec = bind.record()
      return rec and rec[field]
    end
  end
  error("LibKa0s-Options: spec.bind needs get(field, row) or record() -- a bound row must be able to read", 5)
end

--- Bind `row` to the record field `field`: no path, and get/set closures over the bind.
---
--- `row.get(key)` with an argument reads ANOTHER field of the same record -- which is how the flow
--- engine resolves a bound row's `disabledIf`, a record field rather than a settings path.
local function bindRow(bind, row, field)
  local read = bindReader(bind)
  row.path, row.field = nil, field
  row.get = function(key) return read(key or field, row) end
  row.set = function(value) return bind.set(field, value, row) end
  return row
end

--- Replace `row`'s tooltip with the host's own words (compose minor 10, options-ui-§16), for a
--- composed group whose canonical tooltip misdescribes the host's wiring -- a *Bar opacity* applied
--- to the whole frame rather than the fill. Only a non-empty string does anything. A color swatch
--- keeps CLASS_COLOR_NOTE after the host's words, because that sentence is options-ui-§17's and
--- describes the pair, not the wiring; its companion takes the words as given. The label is not
--- touched: a host that needs other words for the label passes `labels`, as before.
local function withTooltip(row, tip)
  if type(tip) ~= "string" or tip == "" then return end
  if row.type == "color" then tip = tip .. " " .. CLASS_COLOR_NOTE end
  row.tooltip = tip
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
---
--- Under `spec.bind` the same key becomes the row's record `field` instead of its path (see the arm
--- above); nothing else in this function looks at the bind.
---
--- `spec.tooltips` (compose minor 10, options-ui-§16) is read here too, keyed by the canonical LEAF
--- exactly as `labels` is, never by a `keys` rename: see withTooltip below for what it does.
local function emit(spec, rows, leaf, row)
  local omit = spec.omit or EMPTY
  if omit[leaf] then return nil end

  local keys     = spec.keys or EMPTY
  local labels   = spec.labels or EMPTY
  local tooltips = spec.tooltips or EMPTY
  local defaults = spec.defaults or EMPTY

  local key = row.path or ((spec.prefix or "") .. (keys[leaf] or leaf))
  if spec.bind then bindRow(spec.bind, row, key) else row.path = key end
  row.page     = spec.page
  row.group    = spec.group
  row.subgroup = spec.subgroup
  row.order    = (tonumber(spec.order) or 0) + (#rows * ORDER_STEP)
  if labels[leaf]   ~= nil then row.label   = labels[leaf]   end
  if defaults[leaf] ~= nil then row.default = defaults[leaf] end
  withTooltip(row, tooltips[leaf])

  rows[#rows + 1] = row
  return row
end

--- Append the caller's own rows AFTER the mandated block, order continuing.
---
--- A legitimate extra — a border offset, a fill direction, a bar spacing — belongs to the same
--- block and takes the block's page, group and subgroup; it is NEVER interleaved with the mandated
--- rows (options-ui-§16). It declares its own `path` in full, because an extra is a hand-written
--- row rather than a canonical leaf and there is no leaf name to prefix.
---
--- Under `spec.bind` an extra declares its record `field` in full instead, and is bound like a
--- canonical row. One that declares a `path`, or brings its own get/set, is left exactly as given.
local function appendExtra(spec, rows)
  for _, row in ipairs(spec.extra or EMPTY) do
    local copy = shallow(row)
    if spec.bind and copy.path == nil and copy.field ~= nil and copy.get == nil then
      bindRow(spec.bind, copy, copy.field)
    end
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

-- ── FOLLOWING THE SKIN (compose minor 12) ───────────────────────────────────────────────────
--
-- A HUD setting can follow the owner's skin instead of a stored pick (the owner's ruling R3). A
-- SENTINEL value in the picker cannot say so: an LSM30 picker shows its list's KEY as the label and
-- uses the list's value as the media path, and the same list is the CLI's allowed values, so a
-- "From skin" entry would draw no preview and be a value the CLI accepts and nothing can render. A
-- companion bool says it instead, beside the picker it governs: `<key>FromSkin`, emitted only when
-- the spec opts in. While it is true the picker is disabled (`disabledIf`, the companion's own key,
-- so a record-backed row reads its record) and shows the skin's value (`skinValue`, the row field the
-- flow engine reads before the stored one, OptionsWidgets minor 35); the host draws with
-- `S.Resolve(token, stored, fromSkin)`, which answers the skin's value while the companion is set.
-- `Skin.ResetToSkin` sets the companions to true. Without `fromSkin` a composer emits exactly what
-- minor 11 emitted.

-- The three media pickers that can follow the skin, by canonical leaf: the token the skin answers
-- with and the companion's words.
local FROM_SKIN = {
  font = { token = "hud.font", label = "Use the skin's font",
    tooltip = "Draw this text in the skin's font. The font picker is not read while this is on." },
  borderStyle = { token = "bar.borderStyle", label = "Use the skin's border",
    tooltip = "Draw this border in the skin's border style. The border picker is not read while this is on." },
  barTexture = { token = "bar.texture", label = "Use the skin's texture",
    tooltip = "Draw this bar in the skin's texture. The texture picker is not read while this is on." },
}

-- The other families a picker can follow, by `spec.fromSkin` value (minor 13); `true`, and any value
-- not named here, is FROM_SKIN's. `sizeToken` makes the companion govern the group's thickness row
-- too (`disabledIf` it, showing that token while it is set).
local FROM_SKIN_FAMILY = {
  icon = {
    borderStyle = { token = "icon.borderStyle", sizeToken = "icon.borderSize", label = "Use the skin's border",
      tooltip = "Draw this border in the skin's icon border style and thickness. The border style and "
        .. "thickness pickers are not read while this is on." },
  },
}

--- Attach the composers to one instance, beside the widget makers and the flow engine.
---
--- Takes no descriptor: a composer reads no state and writes none, so there is nothing of the
--- host's for it to close over. It takes `O` because the media-backed rows call O.LSMValues, which
--- is the instance's deferred reader.
---
--- CONTRACT, for a host that supplies its own `O.LSMValues`: it MUST RETURN A FUNCTION, the way
--- Options.lua's does. The three media rows below read that member ONCE, at row-declaration time,
--- and assign what comes back straight into `values` -- because enumList (OptionsWidgets.lua:78-79)
--- unwraps a row's `values` exactly once, so anything wrapped twice reaches it as a function and
--- comes back as an empty dropdown with no report. A host handing back a TABLE therefore does not
--- error: it freezes its own media list at whatever was registered when this file loaded, which is
--- precisely the failure Options.lua:759-763 says the deferral exists to prevent. Pass the deferred
--- reader itself, never a caller of it.
-- The "Reset all settings" tooltip, chosen by what the reset IS on this host (compose minor 5).
-- Through minor 4 it was one literal, "Restore every setting in this addon to its default", and a
-- host could not change it without keeping a second copy of the button in its own source. But a
-- host that supplies `resetProfile` resets the CURRENT PROFILE (options-ui-§12), and "every setting
-- in this addon" overstates it -- other profiles survive. So the descriptor picks the wording:
-- no `resetProfile`, the minor-4 text byte for byte; `resetProfile`, the profile wording; and
-- `profilesPage` as well, the equivalence §12 asks the tooltip to name. Read at call time, from
-- lib.STRINGS, so the three wordings live beside the shell's other user-visible text.
local function resetAllTooltip(desc)
  local S = lib.STRINGS
  if type(desc.resetProfile) ~= "function" then return S.RESET_ALL_TIP end
  if desc.profilesPage then return S.RESET_ALL_TIP_PROFILES_PAGE end
  return S.RESET_ALL_TIP_PROFILE
end

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
  emitNoted(ms, rows, notes, "locked", {
    type = "bool", label = "Lock frame",
    tooltip = spec.lockIsPreview and LOCK_PREVIEW_TIP or "Stop the frame being dragged.",
    default = false, startsLine = true,
  })
  local consoleRow = emitNoted(ms, rows, notes, "debugConsole", {
    path = spec.debugConsolePath or "state.debugConsole",
    type = "bool", label = "Debug console", tooltip = "Show this session's developer log window.",
    -- Session state, never persisted: a console left open is not a setting the next character
    -- inherits.
    sessionOnly = true,
  })
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
      -- row was emitted; otherwise the first column of its own line, as at minor 7.
      startsLine = not (ms.omit.locked and consoleRow) or nil,
    })
  end
  -- The test mode, for an addon whose preview has a switch of its own (options-ui-§15, compose
  -- minor 6). Session state like the console row, and absent unless the host names its path: a
  -- checkbox shows whether the mode is on, which a button beside the resets could not.
  if spec.testModePath then
    emitNoted(ms, rows, notes, "testMode", {
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

--- `d` is the instance's descriptor, handed through by lib:New since Options minor 18. A shell
--- older than that passes none, and every descriptor read below then answers as absent.
function lib.__AttachCompose(O, d)
  local desc = type(d) == "table" and d or EMPTY

  --- The skin's value of `token` for this instance's owner (the descriptor's `addonName`; an
  --- unregistered one reads Ka0s Default), or nil with no Skin major or no owner.
  local function skinValue(token)
    local Skin = LibStub and LibStub("LibKa0s-Skin-1.0", true)
    local owner = desc.addonName
    if not (Skin and type(Skin.For) == "function" and type(owner) == "string" and owner ~= "") then return nil end
    local S = Skin:For(owner)
    return type(S.Resolve) == "function" and S.Resolve(token, nil, true) or nil
  end

  --- Put row `r` under `companion`: disabled while it is set, showing the skin's `token` meanwhile.
  local function governed(r, companion, token)
    r.disabledIf = companion
    r.skinValue = function(row)
      local on
      if row.path == nil and type(row.get) == "function" then
        on = row.get(companion)
      elseif type(desc.get) == "function" then
        on = desc.get(companion)
      end
      if on ~= true then return nil end
      return skinValue(token)
    end
  end

  --- The `<key>FromSkin` companion of `picker` (the row emit returned for canonical `leaf`), when
  --- `spec.fromSkin` asks for it and the caller did not omit either row. Appended after the
  --- canonical rows, on a line of its own, so the block's pairs stay as they are. `size` is the
  --- group's thickness row, governed too when the family names a size token (minor 13).
  local function fromSkinRow(spec, rows, picker, leaf, size)
    local family = FROM_SKIN_FAMILY[spec.fromSkin]
    local f = family and family[leaf] or FROM_SKIN[leaf]
    if not (spec.fromSkin and picker and f) then return end
    local companion = (picker.path or picker.field) .. "FromSkin"
    local row = emit(spec, rows, leaf .. "FromSkin", {
      path = companion, type = "bool", label = f.label, tooltip = f.tooltip, default = false,
      startsLine = true,
    })
    if not row then return end
    governed(picker, companion, f.token)
    if size and f.sizeToken then governed(size, companion, f.sizeToken) end
  end
  -- Published on the INSTANCE, not on the lib table, for the reason Options.lua's layout block
  -- gives: a lib-level table is shared by every instance, so handing it out lets one host's
  -- mutation retune every other host's dropdowns.
  O.FONT_FLAGS         = FONT_FLAGS
  O.FONT_FLAGS_SORT    = FONT_FLAGS_SORT
  O.VISIBILITY_VALUES  = VISIBILITY_VALUES
  O.VISIBILITY_SORT    = VISIBILITY_SORT
  O.MASTER_GROUP       = MASTER_GROUP
  O.CLASS_COLOR_NOTE   = CLASS_COLOR_NOTE

  --- The one tooltip a player strata row carries (frame-layering-§1, player-chosen strata: a MUST
  --- for every such row; options-ui-§16). Since compose minor 8.
  ---
  --- `values` is the row's own value table: an array of strata keys, or the dropdown's map keyed by
  --- strata key. Returns one string: BASE always; DIALOG appended when the row offers DIALOG,
  --- FULLSCREEN, FULLSCREEN_DIALOG or TOOLTIP; POPUP appended when it offers FULLSCREEN_DIALOG or
  --- TOOLTIP. A non-table offers nothing and answers BASE alone.
  ---
  --- `strings` (optional `{ BASE =, DIALOG =, POPUP = }`) overrides each part. The library carries
  --- no locale, so a host with one passes its own L's three strings through here. No value set is
  --- published: each knob keeps the values it stores, because changing a stored value set is a
  --- migration, not a tooltip.
  function O.StrataTooltip(values, strings)
    local S = type(strings) == "table" and strings or EMPTY
    local offered = offeredStrata(values)
    local text = S.BASE or STRATA_TEXT.BASE
    if offersAny(offered, STRATA_DIALOG_UP) then
      text = text .. (S.DIALOG or STRATA_TEXT.DIALOG)
    end
    if offersAny(offered, STRATA_POPUP_UP) then
      text = text .. (S.POPUP or STRATA_TEXT.POPUP)
    end
    return text
  end

  --- The tooltip *Reset all settings* carries, for the General page's header Defaults where that
  --- button is the global reset (options-ui-§12, U-04). Since compose minor 11.
  ---
  --- Reads the descriptor at call time through the same resetAllTooltip MasterControls uses, so the
  --- two controls for one act can never describe it two ways. `tail` (optional) follows after one
  --- space when it is a non-empty string; an addon with key bindings passes O.KEYBINDS_UNCHANGED
  --- (options-ui-§20). MasterControls' `notes.resetAll` is that button's own and never appears here.
  function O.ResetAllTooltip(tail)
    local text = resetAllTooltip(desc)
    if type(tail) == "string" and tail ~= "" then text = text .. " " .. tail end
    return text
  end

  --- A color swatch and its "use class color" companion, as exactly two adjacent rows
  --- (options-ui-§17). The primitive the three group composers below are built out of, and the one
  --- a host calls directly for a standalone swatch.
  ---
  --- `spec` takes the common fields (prefix, page, group, subgroup, order, keys, labels, tooltips,
  --- defaults, omit, classColor, extra; `tooltips` since compose minor 10, a swatch's override keeping
  --- the class-color sentence after it) plus:
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
  ---
  --- `spec.flagsFromSkin = true` (compose minor 14) leads Font flags with "From skin" ("@skin") and
  --- makes it the default; the host draws with `S.FontFlags(stored)`. With `fromSkin = true` too it
  --- is the minimum font setting every element carries (D-07).
  function O.FontGroup(spec)
    spec = spec or EMPTY
    local rows = {}
    local skinFlags = spec.flagsFromSkin == true

    local picker = emit(spec, rows, "font", {
      type = "string", label = "Font", tooltip = "The face this text is drawn in.",
      dialogControl = "LSM30_Font", default = "Friz Quadrata TT", startsLine = true,
      values = O.LSMValues("font"),
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
      type = "string", label = "Font flags",
      tooltip = skinFlags and FLAGS_SKIN_TIP or "Outline and monochrome rendering.",
      values = skinFlags and FONT_FLAGS_SKIN or FONT_FLAGS,
      sorting = skinFlags and FONT_FLAGS_SKIN_SORT or FONT_FLAGS_SORT,
      default = skinFlags and FLAGS_FROM_SKIN or "OUTLINE",
    })
    emit(spec, rows, "fontShadow", {
      type = "bool", label = "Font shadow",
      tooltip = "Draw a soft shadow behind the text, for legibility over bright art.",
      default = false,
    })
    fromSkinRow(spec, rows, picker, "font")
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
    local picker = emit(spec, rows, "borderStyle", {
      type = "string", label = "Border style", tooltip = "The border texture.",
      dialogControl = "LSM30_Border", default = "None", startsLine = true,
      values = O.LSMValues("border"),
    })
    local size = emit(spec, rows, "borderSize", {
      type = "number", label = "Border thickness (px)", tooltip = "Border edge width, in pixels.",
      min = 0, max = 16, step = 1, default = 1,
    })
    emit(spec, rows, "borderColor",
      swatchRow(spec, "Border color", "The color the border is drawn in.", spec.hasAlpha))
    emit(spec, rows, "useClassColorBorder",
      companionRow(spec, "Draw this border in the class color instead of the swatch beside it."))
    fromSkinRow(spec, rows, picker, "borderStyle", size)
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

    local picker = emit(spec, rows, "barTexture", {
      type = "string", label = "Bar texture", tooltip = "The bar's fill texture.",
      dialogControl = "LSM30_Statusbar", default = "Blizzard", startsLine = true,
      values = O.LSMValues("statusbar"),
    })
    emit(spec, rows, "barAlpha", {
      type = "number", label = "Bar opacity", tooltip = "How opaque the bar's fill is.",
      isPercent = true, min = 0, max = 1, step = 0.05, default = 1,
    })
    emit(spec, rows, "barColor",
      swatchRow(spec, "Bar color", "The color the bar's fill is drawn in.", spec.hasAlpha))
    emit(spec, rows, "useClassColorBar",
      companionRow(spec, "Draw this bar in the class color instead of the swatch beside it."))
    fromSkinRow(spec, rows, picker, "barTexture")
    return appendExtra(spec, rows)
  end

  --- The canonical MASTER CONTROLS block (options-ui-§15), and the button pair that closes it.
  ---
  ---   [Enable <AddonName>]   [General visibility]
  ---   [Master scale]         [Master opacity]
  ---   [Lock frame]           [Debug console]
  ---   [Minimap button]       [Test mode]
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
  ---   leadButton       table     { text, tooltip, onClick } — ONE act of the host's own, closing
  ---                              the tab beside the resets. Since compose minor 2.
  ---   notes            table     since compose minor 9: { <leaf> = "One sentence." }, appended after
  ---                              the canonical tooltip of that row or button, with one space. The
  ---                              leaves are enabled, visibility, scale, alpha, locked, debugConsole,
  ---                              minimap and testMode, and the buttons resetPosition and resetAll.
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
  ---                         [Test mode]
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
    return rows, function(ctx)
      if lead and not resetPosition then
        return O.InlineButtonPair(ctx, lead, resetAll)
      end
      if lead then O.InlineButtonPair(ctx, lead, nil) end
      O.InlineButtonPair(ctx, resetPosition or resetAll, resetPosition and resetAll or nil)
    end
  end
end
