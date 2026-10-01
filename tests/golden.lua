-- tests/golden.lua — golden-master snapshots for the characterization suites.
--
-- A golden file is plain text, one section per snapshot, each opened by a `== <name> ==` line. CR
-- is stripped on read because the working tree is CRLF (.gitattributes). Plain text rather than a
-- Lua module so a long snapshot never meets layout-§1's 1500-line cap for a .lua file.
--
-- A golden file is generated once, from the code it characterizes, and never regenerated to make a
-- refactor pass. A deliberate output change regenerates it in its own commit and says so: run
-- `LH_WRITE_GOLDEN=1 lua tests/run.lua` and every check prints its snapshot, between
-- `-- GOLDEN BEGIN <path>` and `-- GOLDEN END`, instead of comparing.

local G = {}

G.WRITE = os.getenv("LH_WRITE_GOLDEN") == "1"

--- The sections of the golden file at `path`, name -> text; empty when the file is absent.
function G.read(path)
  local f = io.open(path, "rb")
  if not f then return {} end
  local body = f:read("*a"):gsub("\r", "")
  f:close()
  local out, name, lines = {}, nil, nil
  for line in (body .. "\n"):gmatch("(.-)\n") do
    local header = line:match("^== (.-) ==$")
    if header then
      if name then out[name] = table.concat(lines, "\n") end
      name, lines = header, {}
    elseif name then
      lines[#lines + 1] = line
    end
  end
  if name then
    while lines[#lines] == "" do lines[#lines] = nil end
    out[name] = table.concat(lines, "\n")
  end
  return out
end

local function firstDiff(a, b)
  local la, lb = {}, {}
  for line in (a .. "\n"):gmatch("(.-)\n") do la[#la + 1] = line end
  for line in (b .. "\n"):gmatch("(.-)\n") do lb[#lb + 1] = line end
  for i = 1, math.max(#la, #lb) do
    if la[i] ~= lb[i] then
      return ("line %d:\n  want: %s\n  got:  %s"):format(i, tostring(la[i]), tostring(lb[i]))
    end
  end
  return "no difference"
end

--- A checker bound to one golden file: `check(name, got)` asserts `got` equals that section.
function G.file(path)
  local golden = G.read(path)
  return function(name, got)
    if G.WRITE then
      print(("-- GOLDEN BEGIN %s\n== %s ==\n%s\n-- GOLDEN END"):format(path, name, got))
      return
    end
    local want = golden[name]
    local T = _G.LH_TEST
    T.assertTrue(want ~= nil, "no golden snapshot named " .. name .. " in " .. path)
    T.assertTrue(want == got, name .. " differs from " .. path .. " at " .. firstDiff(want, got))
  end
end

return G
