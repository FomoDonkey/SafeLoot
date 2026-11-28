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
    -- the oldest automatic event goes first; what the player wrote or decided is the last thing to lose
    local drop
    for i, old in ipairs(record.events) do
      if not M.PERMANENT[old.kind] then
        drop = i
        break
      end
    end
    for i, old in ipairs(record.events) do
      if not drop and old.kind == "note" then
        drop = i
      end
    end
    table.remove(record.events, drop or 1)
  end
  return record
end

-- Manual tags are the player's opinion: one per player. A new tag replaces the previous one and clicking the
-- active tag again removes it (seen in the real client: repeated clicks piled up and produced "Mixed").
M.MANUAL = { tag_trusted = true, tag_goodleader = true, tag_ninja = true, tag_extortion = true, tag_quitter = true,
  tag_rude = true }

-- What the player decided or wrote never expires (0.5.0: marks used to vanish after 90 days). Automatic events do.
M.PERMANENT = { note = true }
for kind in pairs(M.MANUAL) do
  M.PERMANENT[kind] = true
end

-- Categories of the Players tab.
M.TAG_CATEGORY = { tag_ninja = "ninja", tag_extortion = "extortion", tag_quitter = "quitter", tag_rude = "warned",
  tag_trusted = "trusted", tag_goodleader = "trusted" }

function M.ActiveTag(record)
  if type(record) ~= "table" then
    return nil
  end
  for i = #(record.events or {}), 1, -1 do
    local kind = record.events[i].kind
    if M.MANUAL[kind] then
      return kind
    end
  end
  return nil
end

-- Returns the active tag after the change (nil when it was removed).
function M.SetTag(players, name, kind, t, place)
  local k = key(name)
  if not k or not M.MANUAL[kind] then
    return nil
  end
  local record = players[k]
  local wasActive = record and M.ActiveTag(record) == kind
  if record then
    for i = #record.events, 1, -1 do
      if M.MANUAL[record.events[i].kind] then
        table.remove(record.events, i)
      end
    end
  end
  if wasActive then
    return nil
  end
  M.Add(players, k, { kind = kind, t = t, place = place })
  return kind
end

function M.Forget(players, name)
  local k = key(name)
  if k then
    players[k] = nil
  end
end

local function alive(event, now, days)
  return M.PERMANENT[event.kind] or not days or not event.t or (now - event.t) <= days * M.DAY
end
M.Alive = alive

-- One category per player: your opinion first; then what the addon saw; then written notes; else just "seen".
function M.Category(record, now, days)
  local tag = M.ActiveTag(record)
  if tag then
    return M.TAG_CATEGORY[tag] or "seen"
  end
  local noted = false
  for _, event in ipairs(type(record) == "table" and record.events or {}) do
    local info = M.KINDS[event.kind]
    if info and info.auto and (info.tone == "bad" or info.tone == "warn") and alive(event, now or 0, days) then
      return "warned"
    end
    noted = noted or event.kind == "note"
  end
  return noted and "noted" or "seen"
end

-- Capital letters for labels, accents included (string.upper depends on the locale).
function M.Upper(text)
  return (text:gsub("[a-z]", function(c)
    return string.char(c:byte() - 32)
  end):gsub("\195([\160-\182\184-\190])", function(c)
    return "\195" .. string.char(c:byte() - 32)
  end))
end

-- Removes one event (a note, a mark, an automatic event) if it is still the one shown.
function M.RemoveEvent(players, name, index, event)
  local record = M.Get(players, name)
  if not record or record.events[index] == nil or (event and record.events[index] ~= event) then
    return false
  end
  table.remove(record.events, index)
  return true
end

-- Returns { tone = "bad" | "warn" | "good" | "mixed" | nil, bad, warn, good, latest, latestAny, count } over live
-- events. latest = newest event with a tone; latestAny = newest event of any kind (notes included).
function M.Summary(record, now, days)
  local result = { bad = 0, warn = 0, good = 0, count = 0 }
  if not record then
    return result
  end
  for _, event in ipairs(record.events or {}) do
    if alive(event, now, days) then
      if not result.latestAny or (event.t or 0) >= (result.latestAny.t or 0) then
        result.latestAny = event -- includes notes, which have no tone
      end
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
      local kept_forever = false
      for _, event in ipairs(kept) do
        kept_forever = kept_forever or M.PERMANENT[event.kind] or false
      end
      list[#list + 1] = { name = name, last = record.last or 0, keep = kept_forever }
    end
  end
  if maxPlayers and #list > maxPlayers then
    table.sort(list, function(a, b)
      if a.keep ~= b.keep then
        return b.keep -- players with your marks or notes are the last to go
      end
      return a.last < b.last
    end)
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
  -- accent- and case-insensitive ("pena" finds "Peña"), without string.lower (locale-dependent on UTF-8)
  local norm = (SL.Rules and SL.Rules.Normalize) or function(s) return s end
  local f = filter and filter ~= "" and norm(filter) or nil
  for name, record in pairs(players or {}) do
    if not f or norm(name):find(f, 1, true) then
      list[#list + 1] = { name = name, record = record, summary = M.Summary(record, now, days) }
    end
  end
  table.sort(list, function(a, b)
    return (a.record.last or 0) > (b.record.last or 0)
  end)
  return list
end
