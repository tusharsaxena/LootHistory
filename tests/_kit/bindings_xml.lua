-- testkit/bindings_xml.lua — Kit.assertBindingsXml, the shared Bindings.xml shape check (kit
-- revision 42).
--
-- WHY. launcher-§6 rules how an addon's key bindings are declared: every Binding in the addon's own
-- category (never the client's ADDONS bucket), no header= (the category carries the heading), no
-- default= (an addon never claims a player's key), one BINDING_NAME_ label per command, and the
-- category global reading the addon's brand. Its re-check paragraph deferred a vendored check until
-- an addon shipped more than one binding; DpsRace and QuickComms do, so the kit ships the one form.
--
-- SURFACE, on the kit table and published by `Kit.expose`:
--
--   Kit.assertBindingsXml(path, opts) -> { { name =, category = }, ... }
--
--     path            the addon's Bindings.xml, relative to the run's working directory
--     opts.category   required string: the category every Binding names (BINDING_HEADER_<X>)
--     opts.commands   required array, in file order: command strings, or the addon's NS.BINDINGS
--                     records ({ command = ... }); both are accepted, and may be mixed
--     opts.brand      required string: what globals[opts.category] must read
--     opts.globals    where the BINDING_NAME_ and category globals live (default _G); a harness
--                     whose addon globals land elsewhere, such as the mock, passes that table
--     opts.labels     optional map command -> the label its BINDING_NAME_ global must read
--
-- PARSING. XML comments (`<!-- ... -->`) are stripped first, so a commented-out Binding is not a
-- binding. Every `<Binding .../>` and `<Binding ...>` element's attributes are read, double- or
-- single-quoted. It is a shape check over a small, flat file, not an XML parser.
--
-- FAILURE. Through Kit.fail at the caller's line, naming the file and launcher-§6: a missing or
-- unreadable file, no Binding at all, a category other than opts.category, a header= or default=
-- attribute, names not equal to the commands in order (count first), an absent or empty
-- BINDING_NAME_ global, a label that differs from opts.labels, or a category global that is not
-- the brand.
--
-- AND THE TAB'S DRIVER (kit revision 42, with LibKa0s's OptionsKeybinds minor 2):
--
--   Kit.keybindThroughTab(row, slot, key, mods) -> the row's outcome line
--
--     row    a row record O.KeybindRows answered ({ command, slots = { w1, w2 }, status, ... })
--     slot   1 or 2 (default 1)
--     key    the key press, as the client's OnKeyDown hands it ("K", "F5", "ESCAPE", ...)
--     mods   optional { alt =, ctrl =, shift =, meta = }, set through the binding mock's
--            M.setModifiers for the press and put back to what they were after it
--
--   It does what a player does on the tab: a left click on the slot (the slot widget's OnClick
--   callback, fired through the AceGUI fake's __fire with "LeftButton"), then the key, run through
--   the OnKeyDown script of the library's one capture listener (lib.__keybindListener, the
--   library resolved through LibStub("LibKa0s-Options-1.0")). It answers the text of the row's
--   outcome line, so a suite asserts KEY_BOUND, or reads GetBindingKey, without knowing how the
--   tab is wired. The mock is the one the harness handed Kit.expose (`mocks` or `mock`), else _G.
--   It fails naming options-ui-§20 when the row, the slot, the listener or its script is missing,
--   or `mods` is given with no M.setModifiers (install tests/_kit/mock_bindings.lua first).
--
-- SHAPE. Returns `function(Kit)`, which installs the members on the kit table it is handed.
-- `framework.lua` loads it once, from its own folder, beside `latch.lua`; it is not a module a
-- suite loads on its own.

return function(Kit)
  local fail = Kit.fail

  local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local body = f:read("*a")
    f:close()
    return body
  end

  local function parseAttrs(s)
    local attrs = {}
    for k, _, v in s:gmatch("([%w_:%-]+)%s*=%s*([\"'])(.-)%2") do attrs[k] = v end
    return attrs
  end

  --- Every Binding element's attribute table, in file order, comments stripped.
  local function elements(text)
    text = text:gsub("<!%-%-.-%-%->", "")
    local out = {}
    for rest in text:gmatch("<Binding([^>]*)>") do
      local c = rest:sub(1, 1)
      if c == "" or c == "/" or c:match("%s") then out[#out + 1] = parseAttrs(rest) end
    end
    return out
  end

  local function commandNames(commands)
    local names = {}
    for i, c in ipairs(commands) do
      names[i] = type(c) == "table" and c.command or c
    end
    return names
  end

  --- The attribute half: nil and the list when every element conforms; otherwise the problem.
  local function checkElements(els, opts)
    local list = {}
    for i, a in ipairs(els) do
      local name = a.name or ("#" .. i)
      if a.category ~= opts.category then
        return ("Binding %s has category %q, expected %q"):format(name, tostring(a.category), opts.category)
      end
      if a.header ~= nil then return ("Binding %s carries header=; the category is the heading"):format(name) end
      if a.default ~= nil then return ("Binding %s carries default=; an addon never claims a key"):format(name) end
      list[i] = { name = a.name, category = a.category }
    end
    return nil, list
  end

  --- The names half: nil when the names follow the commands and every label and the category
  --- global read as they must; otherwise the problem.
  local function checkNames(list, opts)
    local want = commandNames(opts.commands)
    if #want ~= #list then
      return ("Binding count %d does not match the %d commands"):format(#list, #want)
    end
    local g = opts.globals or _G
    for i, b in ipairs(list) do
      if b.name ~= want[i] then
        return ("Binding %d is %s, expected %s (the commands' order)"):format(i, tostring(b.name), tostring(want[i]))
      end
      local key = "BINDING_NAME_" .. b.name
      local label = g[key]
      if type(label) ~= "string" or label == "" then
        return ("%s is not a non-empty string"):format(key)
      end
      local expected = opts.labels and opts.labels[b.name]
      if expected ~= nil and label ~= expected then
        return ("%s reads %q, expected %q"):format(key, label, expected)
      end
    end
    if g[opts.category] ~= opts.brand then
      return ("%s reads %q, expected the brand %q"):format(opts.category, tostring(g[opts.category]),
        tostring(opts.brand))
    end
    return nil
  end

  --- nil and the list when the file conforms; otherwise the problem, as a sentence. Two halves, so
  --- neither passes automated-tests-§3's CCN 15 ceiling.
  local function check(path, opts)
    local text = readAll(path)
    if not text then return "cannot read the file" end
    local els = elements(text)
    if #els == 0 then return "no <Binding> element" end
    local problem, list = checkElements(els, opts)
    if problem then return problem end
    problem = checkNames(list, opts)
    if problem then return problem end
    return nil, list
  end

  function Kit.assertBindingsXml(path, opts)
    opts = opts or {}
    local prefix = "assertBindingsXml: " .. tostring(path) .. ": "
    if type(opts.category) ~= "string" then fail(prefix .. "opts.category must be a string (launcher-§6)", 2) end
    if type(opts.commands) ~= "table" then fail(prefix .. "opts.commands must be an array (launcher-§6)", 2) end
    if opts.brand == nil then fail(prefix .. "opts.brand is required (launcher-§6)", 2) end
    local problem, list = check(path, opts)
    if problem then fail(prefix .. problem .. " (launcher-§6)", 2) end
    return list
  end

  -- ── Kit.keybindThroughTab ──────────────────────────────────────────────────────────────────

  local function env()
    local m = rawget(Kit, "__exposedMock")
    if type(m) == "table" then return m end
    return _G
  end

  local function statusText(row)
    local s = row.status
    if type(s) ~= "table" then return nil end
    if s.text ~= nil then return s.text end
    if type(s.label) == "table" and s.label.GetText then return s.label:GetText() end
    return nil
  end

  --- The slot widget to click, or nil and the problem.
  local function slotWidget(row, slot)
    if type(row) ~= "table" or type(row.slots) ~= "table" then
      return nil, "no row record from O.KeybindRows (options-ui-§20)"
    end
    local w = row.slots[slot]
    if type(w) ~= "table" or type(w.__fire) ~= "function" then
      return nil, "the row has no slot " .. tostring(slot) .. " widget to click (options-ui-§20)"
    end
    return w
  end

  --- The Options library, resolved through the mock's LibStub (or the global one), or nil.
  local function optionsLib(M)
    local ls = M.LibStub or rawget(_G, "LibStub")
    -- LibStub is a callable table in the client and in the kit's mock, not a function.
    local callable = type(ls) == "function" or type(ls) == "table"
    return callable and ls("LibKa0s-Options-1.0", true) or nil
  end

  --- The capture listener and its OnKeyDown script, or nil when either is missing.
  local function listenerScript(lib)
    local f = lib and lib.__keybindListener
    local onKey = f and f.GetScript and f:GetScript("OnKeyDown")
    if type(onKey) ~= "function" then return nil end
    return f, onKey
  end

  function Kit.keybindThroughTab(row, slot, key, mods)
    local prefix = "keybindThroughTab: "
    slot = slot or 1
    local w, problem = slotWidget(row, slot)
    if not w then fail(prefix .. problem, 2) end
    local M = env()
    local lib = optionsLib(M)
    w:__fire("OnClick", "LeftButton")
    local f, onKey = listenerScript(lib)
    if not f then
      fail(prefix .. "no lib.__keybindListener OnKeyDown to press the key into (options-ui-§20)", 2)
    end
    local prev
    if mods ~= nil then
      if type(M.setModifiers) ~= "function" then
        fail(prefix .. "mods given but no setModifiers: install tests/_kit/mock_bindings.lua (options-ui-§20)", 2)
      end
      prev = M.__modifiers
      M.setModifiers(mods)
    end
    local ok, err = pcall(onKey, f, key)
    if mods ~= nil then M.setModifiers(prev) end
    if not ok then error(err, 0) end
    return statusText(row)
  end
end
