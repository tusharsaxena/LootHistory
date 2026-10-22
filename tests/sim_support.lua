-- tests/sim_support.lua: shared helpers for the simulator's end-to-end suites
-- (tests/test_sim_e2e.lua, tests/test_sim_store.lua; LootHistory#37, req-lh-sim.md §11).
--
-- Loaded with dofile by those suites (it registers no case of its own). It owns three things:
--
--   * THE CLIENT'S ITEM AND CURRENCY ANSWERS. The kit mock answers every item with one id (211296)
--     and quality 4, which no real client does. The simulator reads items live -- the simulated
--     player is the real player -- so these suites make the mock answer the way the client would
--     for the fixture's own items: the id out of the link, the name and quality by id, the one
--     uncached item answering nothing (so its rows take the link's own name and color). The
--     situation reads (group, instance, combat, the loot window) stay the mock's solo answers: only
--     the seam's providers may answer those during a session, which is the DW-90 regression.
--   * THE CLOCK. Every timer in the kit's queue is given a due time when first seen, and `advance`
--     moves M.__now and runs what is due, in due order, so the Reconciler's 0.35 s debounce, its
--     1.5 s claim wait and its 6 s hold, and the library's Run ticks and gate polls, all run in the
--     order and at the times they would in the client.
--   * A SESSION. `run(name, mode)` starts a scenario from a clean world, plays it by `step` or by
--     `run`, waits for the ledger to settle, and hands the session's rows back before it stops.

local S = {}

function S.new(T)
  local NS, M = T.NS, T.mocks
  local Host, R, A = NS.SimHost, NS.Reconciler, NS.Attribution
  local World = Host.World
  local H = {}

  -- ── the client's item and currency answers ──────────────────────────────────────────────────

  local function itemSpecs()
    local by = {}
    for _, src in ipairs({ World.ITEMS, Host.SCENARIO_ITEMS or {} }) do
      for _, spec in pairs(src) do by[spec.id] = spec end
    end
    return by
  end

  local CLASS = { [211880] = 0 }   -- the potion is a consumable; every other fixture item is not

  local function linkID(link)
    return tonumber(type(link) == "string" and (link:match("item:(%d+)")) or link)
  end

  --- Swap the mock's item and currency answers for the client's own, run body, restore.
  function H.withClient(body)
    local CI, CC = M.C_Item, M.C_CurrencyInfo
    local saved = { CI.GetItemInfoInstant, CI.GetItemInfo, M.__currencyNames, _G.AUCTION_HOUSE }
    -- The auction house mail's sender, a client global the kit mock does not carry.
    _G.AUCTION_HOUSE = "Auction House"
    local specs = itemSpecs()
    CI.GetItemInfoInstant = function(link)
      local id = linkID(link)
      if not id then return nil end
      return id, nil, nil, nil, nil, CLASS[id] or 15
    end
    CI.GetItemInfo = function(link)
      local spec = specs[linkID(link)]
      if not spec or spec.uncached then return nil end
      return spec.name, link, spec.quality
    end
    local names = {}
    for k, v in pairs(M.__currencyNames) do names[k] = v end
    names[3444], names[3316] = "Champion Mistcrest", "Voidlight Marl"
    M.__currencyNames = names
    local ok, err = pcall(body)
    CI.GetItemInfoInstant, CI.GetItemInfo, M.__currencyNames, _G.AUCTION_HOUSE = saved[1], saved[2], saved[3],
      saved[4]
    if not ok then error(err, 0) end
    return CC
  end

  -- ── the clock ───────────────────────────────────────────────────────────────────────────────

  local function stamp()
    for _, t in ipairs(M.__timers) do
      if t.__due == nil then t.__due = M.__now + (tonumber(t.delay) or 0) end
    end
  end

  local function cancelled(t) return t.cancelled or (t.timer and t.timer.cancelled) end

  --- Move the clock `dt` seconds, running every timer that falls due, earliest first (a timer set
  --- while running is due from the moment it was set).
  function H.advance(dt)
    stamp()
    local target = M.__now + dt
    while true do
      stamp()
      local best, at
      for i, t in ipairs(M.__timers) do
        if t.__due <= target and (best == nil or t.__due < best.__due) then best, at = t, i end
      end
      if not best then break end
      table.remove(M.__timers, at)
      if best.__due > M.__now then M.__now = best.__due end
      if not cancelled(best) then best.fn() end
    end
    M.__now = target
  end

  --- Park every timer an earlier suite left queued, run body on an empty queue, put them back.
  function H.withQueue(body)
    local parked = {}
    while #M.__timers > 0 do parked[#parked + 1] = table.remove(M.__timers, 1) end
    local ok, err = pcall(body)
    while #M.__timers > 0 do table.remove(M.__timers) end
    for _, t in ipairs(parked) do M.__timers[#M.__timers + 1] = t end
    if not ok then error(err, 0) end
  end

  -- ── a session ───────────────────────────────────────────────────────────────────────────────

  --- A clean world to start in: login settled, no ledger in flight, nothing open, solo, out of
  --- combat. Every situation read answers the mock's own solo value.
  function H.settle()
    NS.State.cleanupDone, NS.State.loginSettled = true, true
    R:ResetState()
    A:ResetContexts()
    M.__inCombat = false
    M.__context.inGroup, M.__context.inInstance = false, false
  end

  --- The ledger has nothing in flight.
  function H.settled()
    return not (R._pending or R._holdSince or R.deferred)
  end

  -- Play a started session to its end by repeated `step`, letting the clock run while the gate
  -- holds the next one. Answers the list of codes Step answered.
  -- `afterStep(i, step)` runs after each step that played.
  local function playByStep(sim, limit, afterStep)
    local codes = {}
    for _ = 1, limit do
      local st = sim:Status()
      if st.total > 0 and st.pos >= st.total then break end
      local played, code = sim:Step()
      codes[#codes + 1] = played and "step" or code
      if played and afterStep then afterStep(played.index, played) end
      if not played and code ~= "settling" then break end
      H.advance(0.25)
    end
    return codes
  end

  local function playByRun(sim, limit)
    assert(sim:Run(), "run starts")
    for _ = 1, limit do
      local st = sim:Status()
      if st.pos >= st.total and not st.playing then break end
      H.advance(0.25)
    end
  end

  --- Start scenario `name`, play it to the end by `mode` ("step" or "run"), let the ledger settle,
  --- and call inspect(rows, session) before the stop. Answers what inspect answered.
  function H.run(name, mode, inspect, opts)
    opts = opts or {}
    local sim = NS.Sim
    local result
    H.withClient(function()
      H.withQueue(function()
        H.settle()
        M.__resetPrinted()
        local ok, line = sim:Start({ scenario = name, seed = opts.seed or 7 })
        assert(ok, "scenario " .. name .. " starts: " .. tostring(line))
        local body = function()
          if mode == "run" then playByRun(sim, 2000) else H.codes = playByStep(sim, 2000, opts.afterStep) end
          local st = sim:Status()
          assert(st.total > 0 and st.pos == st.total, ("%s by %s played %d of %d steps"):format(name, mode,
            st.pos, st.total))
          for _ = 1, 200 do
            if H.settled() then break end
            H.advance(0.25)
          end
          result = inspect(NS.Database:History(), sim:Session())
        end
        local okb, err = pcall(body)
        sim:Stop("stop")
        H.settle()
        if not okb then error(err, 0) end
      end)
    end)
    return result
  end

  -- ── rows ────────────────────────────────────────────────────────────────────────────────────

  -- A holder key as the expectations write it: `me`, `alt` (the session's own alt) or `§warband`.
  local function who(key)
    if key == nil then return "nil" end
    local me, alt = NS.Util.PlayerKey(), Host.alt or ("Simalt-" .. (NS.Util.PlayerKey():match("%-(.+)$") or ""))
    local function lit(x) return (x:gsub("%p", "%%%0")) end
    return (tostring(key):gsub(lit(me), "me"):gsub(lit(alt), "alt"))
  end

  --- One row as "<DIR> <KIND>[:<id>] x<qty> <reason> @<holder>[ <from>><to>]".
  function H.describe(r)
    local U = NS.Util
    local kind = U.RowKind(r)
    local id = kind == "ITEM" and r.itemID or kind == "CURRENCY" and r.currencyID or nil
    local route = (r.from or r.to) and (" " .. who(r.from) .. ">" .. who(r.to)) or ""
    return ("%s %s%s x%d %s @%s%s"):format(U.RowDir(r), kind, id and (":" .. id) or "", r.quantity or 0,
      tostring(r.source), who(U.RowHolder(r)), route)
  end

  function H.describeAll(rows)
    local out = {}
    for i, r in ipairs(rows) do out[i] = H.describe(r) end
    table.sort(out)
    return out
  end

  -- ── serialization (the saved-data invariant) ────────────────────────────────────────────────

  local function ser(v, out)
    local t = type(v)
    if t == "table" then
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) < type(b)
      end)
      out[#out + 1] = "{"
      for _, k in ipairs(keys) do
        out[#out + 1] = "[" .. (type(k) == "string" and ("%q"):format(k) or tostring(k)) .. "]="
        ser(v[k], out)
        out[#out + 1] = ","
      end
      out[#out + 1] = "}"
    elseif t == "string" then
      out[#out + 1] = ("%q"):format(v)
    else
      out[#out + 1] = tostring(v)
    end
  end

  --- A table as one deterministic string: keys sorted, every level.
  function H.serialize(v)
    local out = {}
    ser(v, out)
    return table.concat(out)
  end

  return H
end

return S
