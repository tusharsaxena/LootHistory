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
-- The HOST supplies what is genuinely its own: its folder name, its logo, how its settings panel
-- opens, and the accessor-and-toggle pairs for the states it has (enabled, locked, test mode, its
-- primary window). The library owns the rest: since minor 4 the left button opens the settings
-- panel on every addon and the right button opens one context menu of those toggles (launcher-§2).
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

local MAJOR, MINOR = "LibKa0s-Launcher-1.0", 4
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
  -- Minor 4 (launcher-§2, v2.67.0): the hints are fixed. `TOOLTIP_LEFT_DEFAULT`,
  -- `TOOLTIP_DISABLED_HINT` and `TOOLTIP_DISABLED_BARE` described the retired left-click rungs and
  -- are gone; a host `d.L` still carrying them is read by nothing.
  TOOLTIP_OPTIONS_MENU  = "Options menu",

  -- The right-click options menu (minor 4, launcher-§2). The title is the plain-text label, so it
  -- has no key. A grayed entry reads `<entry> (<note>)`, the note in its label rather than in a
  -- tooltip, because the client does not run a disabled button's motion scripts by default and a
  -- note in a tooltip nobody can raise is no note.
  MENU_ENABLED          = "Enabled",
  MENU_LOCKED           = "Locked",
  MENU_TEST_MODE        = "Test mode",
  MENU_SHOW_WINDOW      = "Show window",
  MENU_NEEDS_ENABLE     = "enable the addon first",
  MENU_GRAYED           = "%s (%s)",
  MENU_FAILED           = "%s: the launcher menu's %s entry raised: %s",
}

-- The status values' two colors, and the only color the tooltip draws (launcher-§1).
local GREEN, RED, RESET = "|cFF00FF00", "|cFFFF0000", "|r"

--- The options menu's entries (minor 4, launcher-§2), in the one order the standard allows. Each
--- is drawn only where the descriptor passes BOTH its accessor (`get`) and its toggle (`set`).
--- `gated` entries drive features, which refuse while the addon is disabled (slash-commands-§7),
--- so they are grayed then; Enabled is the off switch and must work in the off state.
local ENTRIES = {
  { key = "MENU_ENABLED",     get = "isEnabled",     set = "setEnabled",     gated = false },
  { key = "MENU_LOCKED",      get = "isLocked",      set = "toggleLock",     gated = true  },
  { key = "MENU_TEST_MODE",   get = "isTestMode",    set = "toggleTestMode", gated = true  },
  { key = "MENU_SHOW_WINDOW", get = "isWindowShown", set = "toggleWindow",   gated = true  },
}

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
---   label          string    optional. What a broker display labels the plugin, the tooltip's
---                            title and the options menu's title. Defaults to `name`.
---   minimap        table|fn  REQUIRED. LibDBIcon's own table, `db.global.minimap`
---                            (launcher-§3), or a function answering it. A function is the usual
---                            shape — see minimapTable above.
---   openSettings   function  REQUIRED. Opens the addon's settings panel. Since minor 4 the LEFT
---                            click calls it, on every addon and in either state (launcher-§2); so
---                            does the right click on a client with no context-menu API.
---   isEnabled      function  optional, since minor 2. Whether the addon is enabled. The tooltip's
---                            Enabled line (minor 3), the menu's Enabled checkbox with
---                            `setEnabled`, and, while it answers false, the menu's other entries
---                            are grayed (minor 4). Asked on every show and every open, never
---                            cached. A host without it is always enabled.
---   setEnabled     function  optional, since minor 4. setEnabled(bool) — the addon's own
---                            enable/disable path, the one `/<slash> enable|disable` writes. With
---                            `isEnabled`, the menu draws the Enabled entry.
---   isLocked       function  optional, since minor 3. Where the addon has a lock: answers whether
---                            it is locked. Draws `Locked: Yes|No` in the tooltip, and with
---                            `toggleLock` the menu's Locked entry (minor 4).
---   toggleLock     function  optional, since minor 4. The addon's own lock/unlock toggle.
---   isTestMode     function  optional, since minor 3. Where the addon has a test mode: answers
---                            whether it is on. Draws `Test mode: On|Off` in the tooltip, and with
---                            `toggleTestMode` the menu's Test mode entry (minor 4).
---   toggleTestMode function  optional, since minor 4. The addon's own test-mode toggle.
---   isWindowShown  function  optional, since minor 4. Where the addon has a primary window:
---                            answers whether it is shown. With `toggleWindow`, the menu's Show
---                            window entry.
---   toggleWindow   function  optional, since minor 4. The primary window's own toggle.
---   onTooltipShow  function  optional. Since minor 3 it is NOT the LDB object's hook: the
---                            library always draws the status tooltip and calls this once per
---                            show, handed the tooltip, to APPEND the addon's own lines between
---                            the status block and the click hints. It draws no title, version,
---                            status line or click hint of its own (launcher-§1).
---   version        str|fn    optional, since minor 3. The addon's version, drawn after the
---                            label in the tooltip's title. A leading `v` is not doubled.
---   print          function  optional. Where this module's own reports go. Defaults to the chat
---                            frame.
---   debug          function  optional. debug(tag, message) — the host's log seam, called with
---                            the tag "Launcher".
---   L              table     optional. Locale override, keyed to lib.STRINGS.
---
--- RETIRED at minor 4, with launcher-§2's left-click rungs, and ignored if passed (no error):
--- `onClick` and `leftClickLabel` (the left button opens the settings panel now), and
--- `disabledLine` and `slash`, which served only the retired disabled left-click refusal and its
--- tooltip hint. Minor 2's rule that `isEnabled` needs a `disabledLine` goes with them.
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
    error(MAJOR .. ":New requires descriptor.openSettings — left-click ALWAYS opens the panel", 2)
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

  --- One descriptor accessor, asked now and never cached, and never allowed to raise into the
  --- client's hover or menu dispatch. A raise is heard by the debug seam and answers nil; nothing
  --- goes to chat, because a hover repeats and a chat line per hover is noise.
  local function ask(fn, what)
    if type(fn) ~= "function" then return fn end
    local ok, v = pcall(fn)
    if ok then return v end
    log(what .. " raised: " .. tostring(v))
    return nil
  end

  --- Whether the addon is enabled, read now. A host with no `isEnabled` is always enabled.
  local function enabledNow(what)
    if type(d.isEnabled) ~= "function" then return true end
    return ask(d.isEnabled, what) and true or false
  end

  --- A status value, green when true and red when false.
  local function status(flag, yes, no)
    return (flag and GREEN or RED) .. text(flag and yes or no) .. RESET
  end

  --- `<label>  v<version>`, or the label alone where no version answers.
  local function titleLine()
    local label = d.label or name
    local v = ask(d.version, "tooltip: version")
    if v == nil or v == "" then return label end
    return text("TOOLTIP_TITLE_VERSION"):format(label, (tostring(v):gsub("^[vV]", "")))
  end

  --- THE TOOLTIP (minor 3, launcher-§1). Always the LDB object's `OnTooltipShow`, on every host,
  --- in one shape: title, Enabled, Locked and Test mode where the host has them, the host's own
  --- lines, then the two click hints. Every state is read on this show, so the tooltip cannot
  --- disagree with the panel, and it draws while the addon is disabled, which is when a player
  --- most needs to ask. Since minor 4 the hints are fixed: the left button opens the settings
  --- panel and the right one the options menu, in either state (launcher-§2).
  local function drawTooltip(tt)
    if type(tt) ~= "table" or type(tt.AddLine) ~= "function" then return end
    local enabled = enabledNow("tooltip: isEnabled")
    tt:AddLine(titleLine())
    tt:AddLine(text("TOOLTIP_ENABLED"):format(status(enabled, "TOOLTIP_YES", "TOOLTIP_NO")))
    if type(d.isLocked) == "function" then
      tt:AddLine(text("TOOLTIP_LOCKED"):format(status(ask(d.isLocked, "tooltip: isLocked"), "TOOLTIP_YES", "TOOLTIP_NO")))
    end
    if type(d.isTestMode) == "function" then
      tt:AddLine(text("TOOLTIP_TEST_MODE"):format(status(ask(d.isTestMode, "tooltip: isTestMode"), "TOOLTIP_ON", "TOOLTIP_OFF")))
    end
    if type(d.onTooltipShow) == "function" then
      local ok, err = pcall(d.onTooltipShow, tt)
      if not ok then log("tooltip: onTooltipShow raised: " .. tostring(err)) end
    end
    tt:AddLine(text("TOOLTIP_LEFT"):format(text("TOOLTIP_OPEN_SETTINGS")))
    tt:AddLine(text("TOOLTIP_RIGHT"):format(text("TOOLTIP_OPTIONS_MENU")))
  end

  --- The menu's response to a click: close. The next open reads every state afresh, which is
  --- simpler to trust than a refresh that re-reads checkmarks but not which entries are grayed.
  --- `MenuResponse` is the client's; where it is absent the menu takes its own default.
  local function closeMenu()
    local R = MenuResponse
    return type(R) == "table" and R.Close or nil
  end

  --- One entry clicked. Toggles through the HOST's own handler, once, so its refusals, combat
  --- rules and messages are the addon's (launcher-§2). A gated entry clicked while disabled (a
  --- client that ran the click despite the gray) calls nothing and writes nothing. pcall'd: this
  --- runs in the client's menu dispatch, where a raise is a red error box naming no addon.
  local function choose(entry)
    if entry.gated and not enabledNow("menu: isEnabled") then
      log("menu: " .. entry.set .. " refused while disabled")
      return closeMenu()
    end
    local ok, err
    if entry.set == "setEnabled" then
      ok, err = pcall(d.setEnabled, not enabledNow("menu: isEnabled"))
    else
      ok, err = pcall(d[entry.set])
    end
    if not ok then emit(text("MENU_FAILED"):format(name, text(entry.key), tostring(err))) end
    return closeMenu()
  end

  --- The entries this host supplies, in ENTRIES order: each needs both halves, the accessor and
  --- the toggle, since an entry for a state the addon does not have is as wrong as a missing one.
  local function suppliedEntries()
    local out = {}
    for _, entry in ipairs(ENTRIES) do
      if type(d[entry.get]) == "function" and type(d[entry.set]) == "function" then
        out[#out + 1] = entry
      end
    end
    return out
  end

  --- THE OPTIONS MENU (minor 4, launcher-§2), as a Blizzard menu generator: the title, then one
  --- checkbox per supplied entry. Every state is read HERE, when the menu opens, never cached;
  --- while the addon is disabled the entries past Enabled are grayed with the note in the label.
  local function buildMenu(_, root, entries)
    if type(root) ~= "table" then return end
    if type(root.CreateTitle) == "function" then root:CreateTitle(d.label or name) end
    local enabled = enabledNow("menu: isEnabled")
    for _, entry in ipairs(entries) do
      local checked = ask(d[entry.get], "menu: " .. entry.get) and true or false
      local grayed = entry.gated and not enabled
      local label = text(entry.key)
      if grayed then label = text("MENU_GRAYED"):format(label, text("MENU_NEEDS_ENABLE")) end
      local box = root:CreateCheckbox(label,
        function() return checked end,
        function() return choose(entry) end)
      if grayed and type(box) == "table" and type(box.SetEnabled) == "function" then
        box:SetEnabled(false)
      end
    end
  end

  --- The RIGHT click: the client's own context menu (`MenuUtil.CreateContextMenu`, 11.0+),
  --- resolved at call time so a client without it — or a host supplying no toggle at all —
  --- degrades to the settings panel rather than to a silent button.
  local function openMenu(owner)
    local MU = MenuUtil
    if type(MU) ~= "table" or type(MU.CreateContextMenu) ~= "function" then
      log("menu: MenuUtil.CreateContextMenu absent; right-click opens settings")
      return d.openSettings("RightButton")
    end
    local entries = suppliedEntries()
    if #entries == 0 then
      log("menu: the descriptor supplies no toggle; right-click opens settings")
      return d.openSettings("RightButton")
    end
    MU.CreateContextMenu(owner or UIParent, function(o, root) buildMenu(o, root, entries) end)
  end

  --- THE ONE CLICK IMPLEMENTATION (launcher-§1/§2). Both surfaces dispatch into it, so the rule is
  --- satisfied on the minimap and in a broker display by construction rather than by two
  --- implementations agreeing.
  ---
  --- Since minor 4 the buttons mean the same thing on every addon: LEFT opens the settings panel,
  --- in either state — the panel is setup, not a feature, and is where a disabled addon is
  --- re-enabled — and RIGHT opens the options menu. There is no rung and no refusal.
  ---
  --- pcall'd, because this runs inside the client's click dispatch: a raising handler there is a
  --- red error box over the player's minimap with nothing saying which addon caused it. One line
  --- names the addon and the button instead, and the launcher keeps working.
  local function click(owner, button)
    local right = button == "RightButton"
    local ok, err
    if right then ok, err = pcall(openMenu, owner) else ok, err = pcall(d.openSettings, button) end
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
