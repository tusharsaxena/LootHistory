-- LibKa0s-Launcher-1.0 — the minimap button and the broker plugin, as ONE object registered twice.
--
-- ── WHY THIS EXISTS ──────────────────────────────────────────────────────────────────────────
--
-- `launcher-§1` makes a launcher mandatory for every Ka0s addon, and it is the surface on which
-- the collection is most visibly one collection: eleven buttons around one minimap, each wearing
-- its own logo, each answering a click the same way. The wiring underneath is identical in all
-- eleven — one LibDataBroker-1.1 object of `type = "launcher"`, handed to LibDBIcon-1.0, one
-- OnClick, one `minimap` table in the global store — and every line of it is the kind of thing
-- that gets written eleven times in eleven spellings and then drifts on the first behavior change.
-- That is anti-pattern #81, and it is what this module exists to make impossible.
--
-- The HOST supplies what is genuinely its own: its folder name, its logo, what its left button
-- does, and how its settings panel opens. The library owns the rest.
--
-- ── WHAT IT DELIBERATELY DOES NOT OWN ────────────────────────────────────────────────────────
--
-- **The inversion.** `launcher-§3` stores the button's visibility as LibDBIcon's OWN `hide`
-- boolean, and the Master-controls row says *shown*. The row is emitted by
-- `LibKa0s-Options-1.0`'s `MasterControls` composer (`minimapPath`, compose minor 7) and its
-- get/set invert at the HOST's single write seam (options-ui-§1), which is the same seam every
-- other row writes through. This module offers `SetShown` / `IsShown` for that seam to call; it
-- never reaches into a settings store and never registers a row.
--
-- **The scope.** The `minimap` table is `db.global.minimap` and the standard fixes it there for
-- two stated reasons — a profile switch must not move a player's buttons, and options-ui-§12's
-- *Reset all settings*, a profile reset by definition, must not un-hide a button the player hid.
-- The host hands the table in; this module does not know what a profile is.
--
-- ── NEITHER BROKER LIBRARY IS A DEPENDENCY ───────────────────────────────────────────────────
--
-- LibDataBroker-1.1 and LibDBIcon-1.0 are resolved with `LibStub(..., true)` at REGISTER time, not
-- at load, and a host that has neither gets a launcher that reports itself absent rather than one
-- that raises. That is the same bargain LibSharedMedia strikes in `Media.lua` and AceGUI-3.0 in
-- `Options.lua`: the library is vendored into eleven addons whose `libs/` folders are not
-- identical, and a hard dependency here would take the whole module out — or worse, take the host
-- out — over a library that is genuinely optional to everything but the button itself.
--
-- Call time rather than load time is deliberate too. `LibKa0s.xml` is one entry in a TOC's
-- `# Libraries` block and the broker libraries are others; nothing fixes their relative order, and
-- a lookup taken at load would answer `nil` for a host that happens to list LibKa0s first.
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on no addon framework. No Core member is called —
-- the gate is there so that a host holding a partial payload gets every module absent rather than
-- a working half, and "is LibKa0s here?" stays one question.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Launcher-1.0", 3
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

-- Which version of each FILE in this major is actually live, so version skew is discoverable at
-- runtime rather than by reading source. See docs/releasing.md.
lib.MODULES = lib.MODULES or {}
lib.MODULES.Launcher = MINOR

-- The two libraries the launcher sits on, by their LibStub majors. Named here rather than inline
-- so the one place a reader has to look to answer "what does this need?" is the top of the file.
local LDB_MAJOR  = "LibDataBroker-1.1"
local ICON_MAJOR = "LibDBIcon-1.0"

-- Every user-visible string this module can emit. A literal table, as every other major's is: the
-- library carries no locale, and a host that wants its own words passes `d.L` keyed to these.
--
-- UNTAGGED since minor 2. Every line goes out through the host's printer (makeEmit), which carries
-- the host's own tag, so a library tag here read as two tags in chat. The `%s` is still the addon's
-- folder name, so the chat-frame fallback still says whose launcher it is. The keys are unchanged,
-- so a host's `d.L` override keeps working.
lib.STRINGS = {
  NO_BROKER    = "%s: LibDataBroker-1.1 is missing, so there is no launcher.",
  NO_ICON      = "%s: LibDBIcon-1.0 is missing, so there is no minimap button. "
              .. "A broker display will still show the plugin.",
  NO_MINIMAP   = "%s: the launcher descriptor's `minimap` did not answer a table, so "
              .. "LibDBIcon has nowhere to keep the button's position.",
  CLICK_FAILED = "%s: the launcher's %s-click raised: %s",

  -- The status tooltip (minor 3, launcher-§1). Every word of it is here so a host's `d.L` can
  -- reach it; the only color is the green/red the code wraps a status value in, never a string.
  TOOLTIP_TITLE_VERSION = "%s  v%s",
  TOOLTIP_ENABLED       = "Enabled: %s",
  TOOLTIP_LOCKED        = "Locked: %s",
  TOOLTIP_TEST_MODE     = "Test mode: %s",
  TOOLTIP_YES           = "Yes",
  TOOLTIP_NO            = "No",
  TOOLTIP_ON            = "On",
  TOOLTIP_OFF           = "Off",
  TOOLTIP_LEFT          = "Left-click: %s",
  TOOLTIP_RIGHT         = "Right-click: %s",
  TOOLTIP_OPEN_SETTINGS = "Open settings",
  TOOLTIP_LEFT_DEFAULT  = "Toggle",
  TOOLTIP_DISABLED_HINT = "disabled \226\128\148 %s enable",
  TOOLTIP_DISABLED_BARE = "disabled",
}

-- The status values' two colors, and the only color the tooltip draws (launcher-§1).
local GREEN, RED, RESET = "|cFF00FF00", "|cFFFF0000", "|r"

--- The host's own printer, or the chat frame. Same shape every other major uses.
local function makeEmit(d)
  if type(d.print) == "function" then return d.print end
  return function(line)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) end
  end
end

--- Resolve `d.minimap`, which may be the table itself or a function answering it.
---
--- A FUNCTION is the shape a host normally passes, and the reason is ordering: `db.global.minimap`
--- does not exist when the host builds its descriptor at file load, and a table captured then is a
--- table AceDB later replaces. Reading it at Register time through a closure is what keeps the
--- object LibDBIcon holds and the table the settings row writes the same table.
local function minimapTable(d)
  local t = d.minimap
  if type(t) == "function" then t = t() end
  return type(t) == "table" and t or nil
end

--- The descriptor documented, then checked.
---
---   name           string    REQUIRED. The addon's FOLDER name, used for BOTH registrations.
---                            Not cosmetic: LibDBIcon keys the button's saved position by it, so
---                            a second spelling loses the angle the player dragged the button to
---                            and labels the broker plugin with the other name (launcher-§1).
---   icon           string    REQUIRED. The addon's own logo — the same file the TOC's
---                            `## IconTexture` names, `media/logos/<addon>.logo.128.tga`
---                            (launcher-§4). Never a Blizzard path and never a numeric file id.
---   label          string    optional. What a broker display labels the plugin. Defaults to
---                            `name`.
---   minimap        table|fn  REQUIRED. LibDBIcon's own table, `db.global.minimap`
---                            (launcher-§3), or a function answering it. A function is the usual
---                            shape — see minimapTable above.
---   openSettings   function  REQUIRED. Opens the addon's settings panel. RIGHT-click always
---                            calls it, on every addon, whatever rung its left click sits on; so
---                            does left-click on rung (c).
---   onClick        function  optional. The LEFT click's action, and which rung the addon is on
---                            (launcher-§2): pass the primary window's toggle for rung (a), the
---                            preview switch's toggle for rung (b), and pass NOTHING for rung
---                            (c), where left-click opens the settings panel too. It is handed
---                            the button name, so a host needing it does not have to re-read it.
---   isEnabled      function  optional, since minor 2. Whether the addon is enabled. Where it
---                            answers false (or nil) and `onClick` is present, a LEFT click is
---                            refused: `disabledLine` is printed and `onClick` is not called
---                            (launcher-§2's disabled rung (a)/(b)). Right-click and rung (c) are
---                            never gated, because the settings panel is where the addon is
---                            re-enabled. Asked on every click, never cached.
---   disabledLine   function  REQUIRED when `isEnabled` is given, since minor 2. Answers the line
---                            the refusal prints — the host's Slash dispatcher's own disabled line,
---                            so the minimap and `/<slash>` refuse in the same words.
---   onTooltipShow  function  optional. Since minor 3 it is NOT the LDB object's hook: the
---                            library always draws the status tooltip and calls this once per
---                            show, handed the tooltip, to APPEND the addon's own lines between
---                            the status block and the click hints. It draws no title, version,
---                            status line or click hint of its own (launcher-§1).
---   version        str|fn    optional, since minor 3. The addon's version, drawn after the
---                            label in the tooltip's title. A leading `v` is not doubled.
---   isLocked       function  optional, since minor 3. Where the addon has a lock: answers
---                            whether it is locked, and the tooltip draws `Locked: Yes|No`.
---   isTestMode     function  optional, since minor 3. Where the addon has a test mode: answers
---                            whether it is on, and the tooltip draws `Test mode: On|Off`.
---   leftClickLabel str|fn    optional, since minor 3. What the left click does on rungs (a)/(b)
---                            (`Toggle window`), drawn as `Left-click: <label>`. Ignored on rung
---                            (c), which reads `Open settings`.
---   slash          string    optional, since minor 3. The slash command (`/th` or `th`) the
---                            disabled hint names. Without it the command is read out of
---                            `disabledLine()`, which already names `/<slash> enable`.
---   print          function  optional. Where this module's own reports go. Defaults to the chat
---                            frame.
---   debug          function  optional. debug(tag, message) — the host's log seam, called with
---                            the tag "Launcher".
---   L              table     optional. Locale override, keyed to lib.STRINGS.
---
--- @return table  the launcher instance
function lib:New(d)
  d = type(d) == "table" and d or {}
  if type(d.name) ~= "string" or d.name == "" then
    error(MAJOR .. ":New requires descriptor.name — the addon's FOLDER name, e.g. \"BankLedger\"", 2)
  end
  if type(d.icon) ~= "string" or d.icon == "" then
    error(MAJOR .. ":New requires descriptor.icon — the addon's own logo path", 2)
  end
  if type(d.openSettings) ~= "function" then
    error(MAJOR .. ":New requires descriptor.openSettings — right-click ALWAYS opens the panel", 2)
  end
  if type(d.isEnabled) == "function" and type(d.disabledLine) ~= "function" then
    error(MAJOR .. ":New requires descriptor.disabledLine with isEnabled — a refusal must say why", 2)
  end

  local strings = type(d.L) == "table" and d.L or nil
  local emit    = makeEmit(d)
  local name    = d.name

  local Lb = {}
  local object          -- the ONE LibDataBroker object, or nil until Register succeeds
  local iconLib         -- LibDBIcon-1.0, once resolved
  local minimap         -- the table LibDBIcon was handed, so IsShown reads what it writes

  --- One user-visible string, host override first.
  ---
  --- rawget, NOT a plain index: every Ka0s host's locale table answers an unknown key WITH THE
  --- KEY (anti-patterns #2), so a plain index would accept that synthesized string for every key
  --- and these strings would become unreachable. The same guard DebugLog.lua and Slash.lua carry,
  --- and for the same shipped defect.
  local function text(key)
    local v = strings and rawget(strings, key)
    if type(v) == "string" then return v end
    return lib.STRINGS[key]
  end

  local function log(message)
    if type(d.debug) == "function" then d.debug("Launcher", message) end
  end

  --- A missing-library notice, printed ONCE per instance. Register is callable from OnInitialize
  --- and again from login, and a Register that fails reaches its notice again each time; one
  --- missing library is one line in chat, not one per call. The debug log still hears every call.
  local noticed = {}
  local function notice(key)
    if noticed[key] then return end
    noticed[key] = true
    emit(text(key):format(name))
  end

  --- One descriptor accessor, asked on this show and never cached, and never allowed to raise into
  --- the client's hover dispatch. A raise is heard by the debug seam and answers nil; nothing goes
  --- to chat, because a hover repeats and a chat line per hover is noise.
  local function ask(fn, what)
    if type(fn) ~= "function" then return fn end
    local ok, v = pcall(fn)
    if ok then return v end
    log("tooltip: " .. what .. " raised: " .. tostring(v))
    return nil
  end

  --- A status value, green when true and red when false.
  local function status(flag, yes, no)
    return (flag and GREEN or RED) .. text(flag and yes or no) .. RESET
  end

  --- `<label>  v<version>`, or the label alone where no version answers.
  local function titleLine()
    local label = d.label or name
    local v = ask(d.version, "version")
    if v == nil or v == "" then return label end
    return text("TOOLTIP_TITLE_VERSION"):format(label, (tostring(v):gsub("^[vV]", "")))
  end

  --- The command the disabled hint names: `d.slash`, else the one `disabledLine()` names.
  local function slashCommand()
    local s = d.slash
    if type(s) == "string" and s ~= "" then
      return s:sub(1, 1) == "/" and s or "/" .. s
    end
    local line = ask(d.disabledLine, "disabledLine")
    return type(line) == "string" and line:match("(/[^%s|]+) enable") or nil
  end

  --- What `Left-click:` says: the rung, stated (launcher-§2), or the refusal's pointer.
  local function leftHint(enabled)
    if type(d.onClick) ~= "function" then return text("TOOLTIP_OPEN_SETTINGS") end
    if not enabled then
      local slash = slashCommand()
      return slash and text("TOOLTIP_DISABLED_HINT"):format(slash) or text("TOOLTIP_DISABLED_BARE")
    end
    local label = ask(d.leftClickLabel, "leftClickLabel")
    return (type(label) == "string" and label ~= "") and label or text("TOOLTIP_LEFT_DEFAULT")
  end

  --- THE TOOLTIP (minor 3, launcher-§1). Always the LDB object's `OnTooltipShow`, on every host,
  --- in one shape: title, Enabled, Locked and Test mode where the host has them, the host's own
  --- lines, then the two click hints. Every state is read on this show, so the tooltip cannot
  --- disagree with the panel, and it draws while the addon is disabled, which is when a player
  --- most needs to ask. A host with no `isEnabled` is always enabled, as its clicks are.
  local function drawTooltip(tt)
    if type(tt) ~= "table" or type(tt.AddLine) ~= "function" then return end
    local enabled = true
    if type(d.isEnabled) == "function" then enabled = ask(d.isEnabled, "isEnabled") and true or false end
    tt:AddLine(titleLine())
    tt:AddLine(text("TOOLTIP_ENABLED"):format(status(enabled, "TOOLTIP_YES", "TOOLTIP_NO")))
    if type(d.isLocked) == "function" then
      tt:AddLine(text("TOOLTIP_LOCKED"):format(status(ask(d.isLocked, "isLocked"), "TOOLTIP_YES", "TOOLTIP_NO")))
    end
    if type(d.isTestMode) == "function" then
      tt:AddLine(text("TOOLTIP_TEST_MODE"):format(status(ask(d.isTestMode, "isTestMode"), "TOOLTIP_ON", "TOOLTIP_OFF")))
    end
    if type(d.onTooltipShow) == "function" then
      local ok, err = pcall(d.onTooltipShow, tt)
      if not ok then log("tooltip: onTooltipShow raised: " .. tostring(err)) end
    end
    tt:AddLine(text("TOOLTIP_LEFT"):format(leftHint(enabled)))
    tt:AddLine(text("TOOLTIP_RIGHT"):format(text("TOOLTIP_OPEN_SETTINGS")))
  end

  --- The LEFT click on rungs (a)/(b), behind the optional disabled gate (minor 2). A disabled
  --- addon's left click prints the host's refusal line and runs nothing, which is launcher-§2's
  --- rule written once here instead of inside every host's onClick.
  local function leftAction(button)
    if type(d.isEnabled) == "function" and not d.isEnabled() then
      local line = d.disabledLine()
      if type(line) == "string" then emit(line) end
      return
    end
    return d.onClick(button)
  end

  --- THE ONE CLICK IMPLEMENTATION (launcher-§1/§2). Both surfaces dispatch into it, so the rung
  --- rule is satisfied on the minimap and in a broker display by construction rather than by two
  --- implementations agreeing.
  ---
  --- RIGHT-click always opens the settings panel, which is what lets rungs (a) and (b) spend the
  --- left button on something better. LEFT-click takes the host's action where it supplied one,
  --- and otherwise opens the panel as well — that is rung (c), and it is expressed by the ABSENCE
  --- of `onClick` rather than by a flag, so a host cannot declare a rung it did not implement.
  ---
  --- A host that passes `isEnabled` has its LEFT click on rungs (a)/(b) gated by it (leftAction);
  --- the right button and rung (c) both open the panel, where the addon is re-enabled, and are
  --- never gated.
  ---
  --- pcall'd, because this runs inside the client's click dispatch: a raising handler there is a
  --- red error box over the player's minimap with nothing saying which addon caused it. One line
  --- names the addon and the button instead, and the launcher keeps working.
  local function click(_, button)
    local right = button == "RightButton"
    local fn = (not right) and type(d.onClick) == "function" and leftAction or d.openSettings
    local ok, err = pcall(fn, button)
    if not ok then
      emit(text("CLICK_FAILED"):format(name, right and "right" or "left", tostring(err)))
    end
  end

  --- Build the object and register it, once.
  ---
  --- Idempotent by design rather than by accident: a host may call this from `OnInitialize` and
  --- again from a login handler, and LibDBIcon's `:Register` on a name it already holds would
  --- otherwise build a second button over the first.
  ---
  --- @return boolean  whether the launcher is FULLY wired — the broker object exists AND the
  ---                  minimap button is registered. A host with LibDataBroker but no LibDBIcon
  ---                  still gets the broker plugin and `false` here, which is the honest answer:
  ---                  the section's headline surface, the button, is not there.
  function Lb:Register()
    if object and iconLib then return true end

    local LDB = LibStub and LibStub(LDB_MAJOR, true)
    if not LDB then
      log("LibDataBroker-1.1 absent; no launcher")
      notice("NO_BROKER")
      return false
    end

    -- ONE object, and `type = "launcher"` is the reason rather than a label: a broker display
    -- reads `type` to decide what to draw, and `"data source"` promises a `text` value that
    -- updates, which this object does not have. A display handed the wrong type draws an empty
    -- value cell beside the icon forever (launcher-§1).
    object = object or LDB:NewDataObject(name, {
      type  = "launcher",
      label = d.label or name,
      icon  = d.icon,
      OnClick = click,
      OnTooltipShow = drawTooltip,   -- always the library's (minor 3); the host's lines go inside
    })
    if not object then
      -- NewDataObject answers nil for a name already taken. Take the existing object rather than
      -- leaving the host with none: a second launcher under one addon's name is not a state this
      -- module can improve on, and the one already registered is the one the displays hold.
      object = LDB:GetDataObjectByName(name)
    end

    local icons = LibStub and LibStub(ICON_MAJOR, true)
    if not icons then
      log("LibDBIcon-1.0 absent; broker plugin only")
      notice("NO_ICON")
      return false
    end

    minimap = minimapTable(d)
    if not minimap then
      log("descriptor.minimap answered no table; no minimap button")
      notice("NO_MINIMAP")
      return false
    end

    -- The SAME table the settings row writes, handed straight in. LibDBIcon writes `minimapPos`
    -- into it when the player drags the button and `hide` when they use its own menu, so a copy
    -- here would be two records of one state and they would disagree the first time either was
    -- used (launcher-§3, anti-pattern #81).
    iconLib = icons
    icons:Register(name, object, minimap)
    log("registered")
    return true
  end

  --- Whether Register has fully wired the launcher.
  function Lb:IsRegistered()
    return (object and iconLib) and true or false
  end

  --- The one LibDataBroker object, or nil before Register (or where LibDataBroker is absent).
  ---
  --- Published because a host with a live value to show — a count, a state — updates the object's
  --- own fields, and because there is no other honest way for a suite to drive the click that
  --- both surfaces share. It is NOT an invitation to register a second one.
  function Lb:Object()
    return object
  end

  --- Whether the minimap button is shown. Reads LibDBIcon's OWN `hide` key and inverts it, which
  --- is the whole of launcher-§3's storage rule: there is one boolean, the library writes it too,
  --- and a second key beside it would be a copy free to disagree.
  ---
  --- Answers from the STORE rather than from the button, so it is still the right answer on a
  --- host where LibDBIcon never loaded — the Master-controls checkbox then reflects what the
  --- player chose rather than reading `true` because nothing contradicted it.
  function Lb:IsShown()
    local t = minimap or minimapTable(d)
    if not t then return true end
    return not t.hide
  end

  --- Show or hide the minimap button, and record it.
  ---
  --- The Master-controls row's `set` calls this from the host's single write seam, AFTER its own
  --- write of the inverted value — so `hide` is written twice with the same value, which is
  --- deliberate: a host that drives the button from somewhere else (a slash verb, a migration)
  --- gets the store updated without having to remember the inversion a second time.
  ---
  --- @return boolean  whether the button itself could be moved. `false` means the store was still
  ---                  updated and LibDBIcon simply is not there to act on it.
  function Lb:SetShown(shown)
    local t = minimap or minimapTable(d)
    if t then t.hide = not shown end
    if not (iconLib and object) then return false end
    if shown then iconLib:Show(name) else iconLib:Hide(name) end
    log(shown and "shown" or "hidden")
    return true
  end

  return Lb
end
