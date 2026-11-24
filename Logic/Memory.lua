-- PURE (no game API). Private memory of players (docs/PROMPT_MAESTRO.md §4.3). Operates on a table passed in
-- (SafeLootDB.players in game, a plain table in tests). Keys are "First Surname" (SL.Names.Short).
local _, SL = ...
local M = {}
SL.Memory = M

M.MAX_EVENTS = 20
M.DAY = 86400

-- Event kinds. "auto" kinds are recorded by the addon; manual tags come from the player.
M.KINDS = {
  need_impossible = { tone = "bad", auto = true },
  need_doubtful = { tone = "warn", auto = true },
  rules_changed = { tone = "bad", auto = true },
  contract_broken = { tone = "bad", auto = true },
  grouped = { tone = "neutral", auto = true },
  tag_ninja = { tone = "bad" },
  tag_extortion = { tone = "bad" },
  tag_quitter = { tone = "warn" },
  tag_rude = { tone = "warn" },
  tag_trusted = { tone = "good" },
  tag_goodleader = { tone = "good" },
  note = { tone = "neutral" },
}

local function key(name)
  if SL.Names and SL.Names.Short then
    return SL.Names.Short(name)
  end
  return name
end
M.Key = key

function M.Get(players, name)
  local k = key(name)
  return k and players[k] or nil, k
end

-- event = { kind, t, place, item, note, class }
function M.Add(players, name, event)
  local k = key(name)
  if not k or type(event) ~= "table" or not M.KINDS[event.kind] then
    return nil
  end
  local record = players[k]
  if not record then
    record = { events = {}, first = event.t }
    players[k] = record
  end
  if event.class then
    record.class = event.class
  end
  record.last = event.t
  if event.kind == "grouped" then
    -- grouped events only refresh "seen", they never pile up
    record.seen = (record.seen or 0) + 1
    return record
  end
  table.insert(record.events, event)
  while #record.events > M.MAX_EVENTS do
    table.remove(record.events, 1)
  end
  return record
end

function M.Forget(players, name)
  local k = key(name)
  if k then
    players[k] = nil
  end
end

local function alive(event, now, days)
  return not days or not event.t or (now - event.t) <= days * M.DAY
end

-- Returns { tone = "bad" | "warn" | "good" | "mixed" | nil, bad, warn, good, latest, count } over live events.
function M.Summary(record, now, days)
  local result = { bad = 0, warn = 0, good = 0, count = 0 }
  if not record then
    return result
  end
  for _, event in ipairs(record.events or {}) do
    if alive(event, now, days) then
      local info = M.KINDS[event.kind]
      local tone = info and info.tone
      if tone == "bad" or tone == "warn" or tone == "good" then
        result[tone] = result[tone] + 1
        result.count = result.count + 1
        if not result.latest or (event.t or 0) >= (result.latest.t or 0) then
          result.latest = event
        end
      end
    end
  end
  if result.bad > 0 and result.good > 0 then
    result.tone = "mixed"
  elseif result.bad > 0 then
    result.tone = "bad"
  elseif result.warn > 0 then
    result.tone = "warn"
  elseif result.good > 0 then
    result.tone = "good"
  end
  return result
end

-- Drop expired events, empty records and the oldest players beyond maxPlayers.
function M.Prune(players, now, days, maxPlayers)
  if type(players) ~= "table" then
    return 0
  end
  local removed = 0
  local list = {}
  for name, record in pairs(players) do
    local kept = {}
    for _, event in ipairs(record.events or {}) do
      if alive(event, now, days) then
        kept[#kept + 1] = event
      end
    end
    record.events = kept
    local seenRecently = record.last and alive({ t = record.last }, now, days)
    if #kept == 0 and not seenRecently then
      players[name] = nil
      removed = removed + 1
    else
      list[#list + 1] = { name = name, last = record.last or 0 }
    end
  end
  if maxPlayers and #list > maxPlayers then
    table.sort(list, function(a, b) return a.last < b.last end)
    for i = 1, #list - maxPlayers do
      players[list[i].name] = nil
      removed = removed + 1
    end
  end
  return removed
end

-- Sorted list for the Players tab: { name, record, summary }, newest first, optional text filter.
function M.List(players, now, days, filter)
  local list = {}
  local f = filter and filter ~= "" and filter:lower() or nil
  for name, record in pairs(players or {}) do
    if not f or name:lower():find(f, 1, true) then
      list[#list + 1] = { name = name, record = record, summary = M.Summary(record, now, days) }
    end
  end
  table.sort(list, function(a, b)
    return (a.record.last or 0) > (b.record.last or 0)
  end)
  return list
end
