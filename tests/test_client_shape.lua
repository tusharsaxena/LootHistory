-- tests/test_client_shape.lua — the Retail · Forever shape (clients-§2, §4, §6; toc-file-§3).
--
-- WHAT IT PROVES. Loot History ships on Retail and WoW Forever from one codebase (the WoW Forever
-- port, Ka0sAddonsCommonTasks docs/2026-11-22-LOOTHISTORY_BANKLEDGER_FOREVER_PORT, item LH-14). Its
-- shape is spread over files nothing else ties together: the TOC's Interface line, the README's
-- badge and supported-clients sentence, the CLAUDE.md gate, DEPENDENCIES.md, the per-client feature
-- table in docs/ARCHITECTURE.md and docs/forever-quirks.md. Each case here pins one of them, and the
-- last two check, on whichever kit profile runs, that every declared feature is present where it is
-- declared and absent where it is not (clients-§6). DropWatcher's tests/test_harness.lua is the
-- precedent for the TOC and README cases.
--
-- It reads the checkout from disk, and fails rather than passes when a file cannot be opened.

local T = _G.LH_TEST
local NS = T.NS
local test, fail, assertEqual, assertTrue = T.test, T.fail, T.assertEqual, T.assertTrue
local ROOT = T.root or "."
local C = NS.Constants

--- A file's contents with line endings normalized, or a failure.
local function read(rel)
  local fh = io.open(ROOT .. "/" .. rel, "rb")
  if not fh then fail("client shape: " .. rel .. " could not be opened", 2) end
  local body = fh:read("*a") or ""
  fh:close()
  return (body:gsub("\r\n", "\n"))
end

--- The TOC's `## Key: value` fields, by key.
local function tocFields()
  local out = {}
  for line in (read("LootHistory.toc") .. "\n"):gmatch("([^\n]*)\n") do
    local k, v = line:match("^##%s*([%w%-]+)%s*:%s*(.-)%s*$")
    if k then out[k] = v end
  end
  return out
end

--- Every client token a feature's declaration names, as a set.
local function serves(clients)
  local set = {}
  for _, c in ipairs(clients or {}) do set[c] = true end
  return set
end

local CLIENT = T.forever and "forever" or "retail"

-- ── The TOC ──────────────────────────────────────────────────────────────────────────────────

test("Client shape: the TOC carries the Retail and WoW Forever numbers and no load-gating line", function()
  -- Retail · Forever (clients-§2, toc-file-§3): one unsuffixed TOC with both numbers, no gate.
  -- red under: the Retail number alone, or an AllowLoadGameType / ExcludeLoadGameType line
  local f = tocFields()
  assertEqual(f.Interface, "120105, 16001")
  assertTrue(f.AllowLoadGameType == nil and f.ExcludeLoadGameType == nil,
    "no load-gating line on a Retail · Forever addon")
end)

test("Client shape: the Forever number arms the kit's missing-globals scan for both clients", function()
  local CG = dofile(ROOT .. "/tests/_kit/client_globals.lua")
  -- red under: `## Interface: 120105` alone (the scan then checks the live set only)
  assertEqual(table.concat(CG.clientsFromToc(read("LootHistory.toc")), ","), "live,forever")
end)

-- ── The root docs ────────────────────────────────────────────────────────────────────────────

test("Client shape: the README opens on the dual-client WoW badge and the supported-clients sentence", function()
  local readme = read("README.md")
  -- documentation-§1: both clients and both numbers on the badge, then one plain sentence at the
  -- start of the description. red under: the Midnight-only badge or the port-pending sentence
  assertTrue(readme:find("![WoW](https://img.shields.io/badge/WoW-Midnight_12.1.5_and_Forever_1.60.1-purple)",
    1, true) ~= nil, "the dual-client badge")
  local body = readme:match("\n\n([^!#\n][^\n]*)")
  assertTrue(body ~= nil and body:find("^Supports Retail and WoW Forever%. ") ~= nil, tostring(body))
  assertTrue(readme:find("support is planned", 1, true) == nil, "no port-pending sentence left")
end)

test("Client shape: the CLAUDE.md gate and DEPENDENCIES.md name both suite runs", function()
  -- clients-§6: a dual-client addon's suite runs under both kit profiles, so the gate names both.
  for _, rel in ipairs({ "CLAUDE.md", "DEPENDENCIES.md", "docs/testing.md" }) do
    local body = read(rel)
    assertTrue(body:find("`lua tests/run.lua`", 1, true) ~= nil or body:find("\nlua tests/run.lua ", 1, true) ~= nil,
      rel .. " names the Retail run")
    assertTrue(body:find("KA0S_KIT_CLIENT=forever lua tests/run.lua", 1, true) ~= nil,
      rel .. " names the WoW Forever run")
  end
  assertTrue(read("DEPENDENCIES.md"):find("## Interface: 120105, 16001", 1, true) ~= nil,
    "DEPENDENCIES.md quotes the TOC's two numbers")
end)

-- ── The Forever docs ─────────────────────────────────────────────────────────────────────────

test("Client shape: docs/forever-quirks.md carries the vendored Forever catalog, then its own section", function()
  -- forever-quirks-§1: every addon whose Clients include Forever carries the file, the vendored
  -- block first and the addon's own section after it. red under: no file, or the block missing
  local body = read("docs/forever-quirks.md")
  local open = body:find("<!%-%- BEGIN VENDORED: forever quirks catalog v%d+%.%d+%.%d+ %(source: WowAddonStandards%) %-%->")
  local close = body:find("<!-- END VENDORED -->", 1, true)
  assertTrue(open ~= nil and close ~= nil and open < close, "the vendored block's two markers, in order")
  local own = body:find("\n## LootHistory%-specific quirks\n")
  assertTrue(own ~= nil and own > close, "the addon's own section follows the block")
  local arch = read("docs/ARCHITECTURE.md")
  assertTrue(arch:find("| `forever-quirks.md` | Present |", 1, true) ~= nil,
    "the documentation map lists forever-quirks.md as Present")
  assertTrue(arch:find("| `midnight-quirks.md` | Present |", 1, true) ~= nil,
    "a Retail · Forever addon keeps the Retail catalog too")
end)

test("Client shape: the ARCHITECTURE per-client table names every declared feature and source", function()
  -- clients-§4: one row per declared feature, its client and the file that gates it. A feature
  -- declared in core/Constants.lua and missing from the table is a declaration nobody can find.
  local arch = read("docs/ARCHITECTURE.md")
  local section = arch:match("\n### Per%-client features %(clients%-§4%)\n(.-)\n## ")
  assertTrue(section ~= nil, "docs/ARCHITECTURE.md has a `### Per-client features (clients-§4)` section")
  for name in pairs(C.FEATURE_CLIENTS) do
    assertTrue(section:find("`" .. name .. "`", 1, true) ~= nil, "the table names the feature " .. name)
  end
  for s in pairs(C.SOURCE_CLIENTS) do
    assertTrue(section:find("`" .. s .. "`", 1, true) ~= nil, "the table names the source " .. s)
  end
  local rows = 0
  for client in section:gmatch("\n| [^\n]-| `(%a+)` | [^\n]-|") do
    rows = rows + 1
    assertTrue(client == "retail" or client == "forever" or client == "both",
      "a Client cell takes the standard's tokens alone, not " .. client)
  end
  assertTrue(rows >= 10, "the table carries its rows (" .. rows .. ")")
end)

-- ── Present where declared, absent where not (clients-§6) ────────────────────────────────────

test("Client shape: each declared feature's answer is the running client's", function()
  -- red under: a WoW Forever build that answers a Retail-only feature present, or the reverse
  for name, clients in pairs(C.FEATURE_CLIENTS) do
    local set = serves(clients)
    assertEqual(C.FEATURE[name], set[CLIENT] == true or set.both == true, name .. " on " .. CLIENT)
  end
  local inOrder = {}
  for _, s in ipairs(C.SourceOrder) do inOrder[s] = true end
  for s, clients in pairs(C.SOURCE_CLIENTS) do
    local here = serves(clients)[CLIENT] == true
    assertEqual(C.SOURCE_ABSENT[s] == true, not here, s .. " absent on " .. CLIENT)
    assertEqual(inOrder[s] == true, here, s .. " in SourceOrder on " .. CLIENT)
    assertEqual(C.SourceType[s], s, s .. " stays a SourceType member on every client (the export contract)")
  end
end)

-- The event rows each Retail-only feature registers, by the module that owns them.
local FEATURE_EVENTS = {
  mythicPlus = { owner = "Attribution", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED",
                 "CHALLENGE_MODE_RESET", "ZONE_CHANGED_NEW_AREA" },
  warbandBank = { owner = "Reconciler", "ACCOUNT_MONEY", "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" },
}

test("Client shape: a Retail-only feature's event rows exist on Retail and are absent on WoW Forever", function()
  -- clients-§4: gated at registration, never registered and then ignored. red under: an event row
  -- of a Retail-only feature left in NS.EVENT_ROWS on WoW Forever
  for name, events in pairs(FEATURE_EVENTS) do
    assertTrue(C.FEATURE_CLIENTS[name] ~= nil, name .. " is declared")
    local have = {}
    for _, row in ipairs(NS.EVENT_ROWS) do
      if row.owner == events.owner then have[row.event] = true end
    end
    for _, e in ipairs(events) do
      assertEqual(have[e] == true, C.FEATURE[name], events.owner .. " " .. e .. " (" .. name .. ") on " .. CLIENT)
    end
  end
end)

-- ── The smoke file (clients-§6) ──────────────────────────────────────────────────────────────

-- The word each Retail-only feature's absence check must name in the WoW Forever theme. A feature
-- declared in core/Constants.lua with no word here fails the case below until its smoke check exists.
local FEATURE_WORD = { warbandBank = "Warband", mythicPlus = "keystone", appearances = "appearance" }

test("Client shape: docs/smoke-tests.md names each check's client and carries the WoW Forever theme", function()
  -- clients-§6: every check names the client it runs on; a feature absent on a client gets a check
  -- that it is not there, and one that it still works on the other. red under: no Client column in
  -- the Index, no WoW Forever theme, a FOREVER check with no Client tag, an absent source or feature
  -- the absence checks forget, or no Retail regression check for an R8 fix
  local body = read("docs/smoke-tests.md")
  local index = body:match("\n## Index\n(.-)\n## ")
  assertTrue(index ~= nil, "docs/smoke-tests.md has its Index")
  assertTrue(index:find("\n| ID range | Theme | Client | What it covers |\n", 1, true) ~= nil,
    "the Index carries a Client column")
  local rows = 0
  for line in index:gmatch("\n(|[^\n]*)") do
    if not line:find("^| ID range") and not line:find("^|%-") then
      rows = rows + 1
      local client = line:match("^| [^|]-| [^|]-| ([^|]-) |")
      assertTrue(client == "both" or client == "Retail" or client == "WoW Forever",
        "an Index row's Client cell is both, Retail or WoW Forever, not " .. tostring(client) ..
        " (" .. line:sub(1, 40) .. ")")
    end
  end
  assertTrue(rows >= 25, "the Index carries its theme rows (" .. rows .. ")")
  assertTrue(index:find("| [WoW Forever](#wow-forever) |", 1, true) ~= nil, "the Index lists the WoW Forever theme")

  local forever = body:match("\n## WoW Forever\n(.-)\n## Pending sign%-off\n")
  assertTrue(forever ~= nil, "a `## WoW Forever` theme just before Pending sign-off")
  local tagged, n = 0, 0
  for _ in forever:gmatch("\n%*%*FOREVER%-%d+%.") do n = n + 1 end
  for id, client in forever:gmatch("\n%*%*FOREVER%-(%d+)%.[^\n]-%*%* Client: ([%a ]-)%.") do
    tagged = tagged + 1
    assertEqual(tonumber(id), tagged, "FOREVER checks are numbered in order")
    assertTrue(client == "both" or client == "Retail" or client == "WoW Forever",
      "FOREVER-" .. id .. " names its client, not " .. client)
  end
  assertTrue(n >= 10 and tagged == n, "every FOREVER check names its client (" .. tagged .. " of " .. n .. ")")
  for name in pairs(C.FEATURE_CLIENTS) do
    local word = FEATURE_WORD[name]
    assertTrue(word ~= nil and forever:find(word, 1, true) ~= nil,
      "the WoW Forever theme has an absence check for the feature " .. name)
  end
  for s in pairs(C.SOURCE_CLIENTS) do
    assertTrue(forever:find(C.SourceLabel[s], 1, true) ~= nil,
      "the WoW Forever theme's absence checks name the source " .. C.SourceLabel[s])
  end
  local r8 = forever:match("\n### Retail regression checks %(ruling R8%)\n(.*)$")
  assertTrue(r8 ~= nil, "a `### Retail regression checks (ruling R8)` subsection closes the theme")
  assertTrue(r8:find("%*%* Client: Retail%.") ~= nil, "the R8 subsection holds Retail checks")
  for _, fix in ipairs({ "CharacterBanker", "CanViewBank", "GetCoinTextureString" }) do
    assertTrue(r8:find(fix, 1, true) ~= nil, "the R8 subsection checks " .. fix .. " on Retail")
  end
end)
