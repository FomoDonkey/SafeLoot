-- PURE (no game API). The loot book: which items each boss of each dungeon or raid drops.
-- The dungeons, raids and bosses come from the Forever client data (Data/Instances.lua, generated). Forever has no
-- Encounter Journal, so nothing in the game says what a boss drops: the items are LEARNED from real drops (yours
-- and those of other SafeLoot users in your group) and kept in SafeLootDB.loot:
--   loot = { [mapID] = { [bossKey] = { [itemID] = lastSeen } } }   lastSeen > 0: you saw it drop; < 0: only heard
--   from a SafeLoot user of your group (never shared again: a wrong report cannot travel from player to player).
--   bossKey = the boss's first encounter ID, or
--   OTHER (0) for items seen in the instance that no boss could be matched to. Negative keys are bosses the client's
--   encounter list does not have (rares): they come from the optional data pack (SafeLoot_LootData).
local _, SL = ...
local B = {}
SL.LootBook = B

B.OTHER = 0
B.MAX_PER_BOSS = 48
B.MAX_BYTES = 240        -- one addon message (the game's limit is 255)
B.MAX_PER_MESSAGE = 120  -- item IDs accepted from one received message

local LOCALE_INDEX = { enUS = 1, enGB = 1, esES = 2, esMX = 2, deDE = 3, frFR = 4, ptBR = 5, ptPT = 5 }

local function pick(name, i)
  if type(name) == "table" then
    return name[i] or name[1]
  end
  return name
end

local function norm(text)
  return SL.Rules and SL.Rules.Normalize(text) or text
end

local function isID(value)
  return type(value) == "number" and value >= 1 and value < 10000000 and value == math.floor(value)
end
B.IsID = isID

-- index = { list (dungeons A-Z, then raids A-Z), byMap[mapID], byEncounter[encounterID] = { map, boss } }
-- instance = { id, raid, size, name, names, bosses = { { key, ids, name, names, order } } }
function B.Index(data, lang)
  local index = { list = {}, byMap = {}, byEncounter = {} }
  if type(data) ~= "table" or type(data.list) ~= "table" then
    return index
  end
  local li = LOCALE_INDEX[lang] or 1
  for _, raw in ipairs(data.list) do
    local inst = { id = raw.id, raid = raw.raid and true or false, live = raw.live ~= false, size = raw.size or 0,
      min = raw.min or 0, max = raw.max or 0, name = pick(raw.name, li), names = raw.name, bosses = {} }
    for order, rawBoss in ipairs(raw.bosses or {}) do
      local boss = { key = rawBoss.ids[1], ids = rawBoss.ids, name = pick(rawBoss.name, li), names = rawBoss.name,
        order = order }
      inst.bosses[#inst.bosses + 1] = boss
      for _, id in ipairs(rawBoss.ids) do
        index.byEncounter[id] = { map = raw.id, boss = boss }
      end
    end
    index.list[#index.list + 1] = inst
    index.byMap[raw.id] = inst
  end
  table.sort(index.list, function(a, b)
    if a.raid ~= b.raid then
      return not a.raid
    end
    if a.min ~= b.min then
      return a.min < b.min
    end
    if a.max ~= b.max then
      return a.max < b.max
    end
    return norm(a.name) < norm(b.name)
  end)
  return index
end

-- Optional data pack: { credit, loot = { [mapID] = { [bossKey] = { ids } } }, extra = { [mapID] = { [-npcID] = name } } }
-- It is a starting point, never proof: B.Items marks what has really been seen. Returns the number of items used.
function B.AddPack(index, pack)
  if type(pack) ~= "table" or type(pack.loot) ~= "table" then
    return 0
  end
  index.pack, index.packIDs, index.credit = {}, {}, type(pack.credit) == "string" and pack.credit or nil
  local used = 0
  for mapID, byBoss in pairs(pack.loot) do
    local inst = index.byMap[mapID]
    if inst and type(byBoss) == "table" then
      local extras = type(pack.extra) == "table" and type(pack.extra[mapID]) == "table" and pack.extra[mapID] or {}
      local added = {}
      for key, name in pairs(extras) do
        if type(key) == "number" and key < 0 and type(name) == "string" then
          added[#added + 1] = { key = key, ids = {}, name = name, names = name, extra = true }
        end
      end
      table.sort(added, function(a, b)
        return a.name < b.name
      end)
      for _, boss in ipairs(added) do
        boss.order = #inst.bosses + 1
        inst.bosses[#inst.bosses + 1] = boss
      end
      local known, all = {}, {}
      for key, ids in pairs(byBoss) do
        if type(ids) == "table" and (key == B.OTHER or B.Boss(index, mapID, key)) then
          known[key] = {}
          for _, id in ipairs(ids) do
            if isID(id) then
              known[key][id] = true
              all[id] = true
              used = used + 1
            end
          end
        end
      end
      index.pack[mapID], index.packIDs[mapID] = known, all
    end
  end
  return used
end

-- Really seen: you saw it, or someone in your group did and the data pack says it belongs to that instance.
-- Something only heard, that nothing else backs up, is not proof of anything.
local function proven(index, mapID, id, lastSeen)
  if lastSeen >= 0 then
    return true
  end
  local pack = index.packIDs and index.packIDs[mapID]
  return pack ~= nil and pack[id] == true
end

-- Everything known for a boss: { { id, seen, heard } }. seen = it really dropped in Forever; heard = only a SafeLoot
-- user of your group says so; neither = it only comes from the data pack.
function B.Known(book, index, mapID, bossKey)
  local list, done = {}, {}
  for _, id in ipairs(B.Items(book, mapID, bossKey)) do
    local seen = proven(index, mapID, id, book[mapID][bossKey][id])
    list[#list + 1] = { id = id, seen = seen, heard = not seen or nil }
    done[id] = true
  end
  local pack = index.pack and index.pack[mapID] and index.pack[mapID][bossKey]
  for id in pairs(pack or {}) do
    if not done[id] then
      list[#list + 1] = { id = id, seen = false }
    end
  end
  table.sort(list, function(a, b)
    return a.id < b.id
  end)
  return list
end

-- Different items known in an instance, and how many of them were really seen.
function B.Totals(book, index, mapID)
  local ids, total, seen = {}, 0, 0
  for _, items in pairs(book and book[mapID] or {}) do
    for id, lastSeen in pairs(items) do
      if not ids[id] then
        ids[id] = true
        total = total + 1
        seen = seen + (proven(index, mapID, id, lastSeen) and 1 or 0)
      end
    end
  end
  for _, items in pairs(index.pack and index.pack[mapID] or {}) do
    for id in pairs(items) do
      if not ids[id] then
        ids[id] = true
        total = total + 1
      end
    end
  end
  return total, seen
end

function B.Boss(index, mapID, bossKey)
  local inst = index.byMap[mapID]
  if not inst then
    return nil
  end
  for _, boss in ipairs(inst.bosses) do
    if boss.key == bossKey then
      return boss
    end
  end
  return nil
end

-- A boss of the instance by any of its names in any language (e.g. the corpse you are looting).
function B.BossByName(index, mapID, name)
  local inst = index.byMap[mapID]
  if not inst or type(name) ~= "string" or name == "" then
    return nil
  end
  local target = norm(name)
  for _, boss in ipairs(inst.bosses) do
    local names = type(boss.names) == "table" and boss.names or { boss.names }
    for _, candidate in ipairs(names) do
      if norm(candidate) == target then
        return boss
      end
    end
  end
  return nil
end

-- Where a drop goes: the boss of its encounter ID, else "other" of the instance you are in. Returns map, bossKey.
function B.Place(index, encounterID, mapID)
  local hit = type(encounterID) == "number" and index.byEncounter[encounterID]
  if hit then
    return hit.map, hit.boss.key
  end
  if mapID and index.byMap[mapID] then
    return mapID, B.OTHER
  end
  return nil, nil
end

local function count(items)
  local n = 0
  for _ in pairs(items) do
    n = n + 1
  end
  return n
end

-- Returns true when the item is new for that boss (or now seen by you). Unknown instances / bosses and bad IDs are
-- refused. shared = it comes from another player: it only fills free room, never pushes out or moves what you saw
-- yourself, and gives its place up to it.
function B.Learn(book, index, mapID, bossKey, itemID, t, shared)
  if type(book) ~= "table" or not isID(itemID) or not index.byMap[mapID] then
    return false
  end
  if bossKey ~= B.OTHER and not B.Boss(index, mapID, bossKey) then
    return false
  end
  local byBoss = book[mapID] or {}
  book[mapID] = byBoss
  if bossKey == B.OTHER then
    for key, items in pairs(byBoss) do
      if key ~= B.OTHER and items[itemID] and (shared or items[itemID] >= 0) then
        return false -- already known under its boss
      end
    end
  elseif byBoss[B.OTHER] and byBoss[B.OTHER][itemID] then
    if shared and byBoss[B.OTHER][itemID] >= 0 then
      return false -- what you saw stays where you saw it
    end
    byBoss[B.OTHER][itemID] = nil -- now we know which boss drops it
  end
  local items = byBoss[bossKey] or {}
  byBoss[bossKey] = items
  local old = items[itemID]
  if old == nil and count(items) >= B.MAX_PER_BOSS then
    if shared then
      return false
    end
    -- what was only heard goes first, then the oldest
    local outID, outMine, outAge
    for id, seen in pairs(items) do
      local mine, age = seen >= 0, math.abs(seen)
      if not outID or (outMine and not mine) or (mine == outMine and age < outAge) then
        outID, outMine, outAge = id, mine, age
      end
    end
    items[outID] = nil
  end
  if shared then
    if old == nil then
      items[itemID] = -math.max(math.abs(t or 0), 1)
    end
    return old == nil
  end
  items[itemID] = math.abs(t or old or 0)
  return old == nil or old < 0
end

-- Item IDs known for a boss (ascending ID; the UI sorts by name once the names are loaded).
function B.Items(book, mapID, bossKey)
  local list = {}
  local items = book and book[mapID] and book[mapID][bossKey]
  for id in pairs(items or {}) do
    list[#list + 1] = id
  end
  table.sort(list)
  return list
end

function B.Count(book, mapID)
  local n = 0
  for _, items in pairs(book and book[mapID] or {}) do
    n = n + count(items)
  end
  return n
end

-- Saved data is untrusted after a crash or a manual edit: keep only known instances, bosses and valid IDs.
function B.Validate(book, index)
  if type(book) ~= "table" then
    return {}
  end
  local orphans = {}
  for mapID, byBoss in pairs(book) do
    if not index.byMap[mapID] or type(byBoss) ~= "table" then
      book[mapID] = nil
    else
      for bossKey, items in pairs(byBoss) do
        if type(items) ~= "table" then
          byBoss[bossKey] = nil
        elseif bossKey ~= B.OTHER and not B.Boss(index, mapID, bossKey) then
          byBoss[bossKey] = nil
          if type(bossKey) == "number" and bossKey < 0 then
            orphans[#orphans + 1] = { mapID, items } -- a rare of a data pack that is no longer installed
          end
        else
          for id, seen in pairs(items) do
            if not isID(id) or type(seen) ~= "number" or seen ~= seen then
              items[id] = nil
            end
          end
        end
      end
    end
  end
  for _, orphan in ipairs(orphans) do
    for id, seen in pairs(orphan[2]) do
      if isID(id) and type(seen) == "number" and seen == seen then
        B.Learn(book, index, orphan[1], B.OTHER, id, seen, seen < 0)
      end
    end
  end
  return book
end

-- Sharing with other SafeLoot users in the group (addon messages, never chat) -----------------------------------
-- query:  "1|LQ|<mapID>"
-- answer: "1|LB|<mapID>|<bossKey>:<id>,<id>;<bossKey>:<id>"  (several messages if needed; only what you saw yourself)
function B.Query(mapID)
  return "1|LQ|" .. tostring(mapID)
end

function B.ParseQuery(index, message)
  local mapID = type(message) == "string" and tonumber(message:match("^1|LQ|(%d+)$"))
  return mapID and index.byMap[mapID] and mapID or nil
end

function B.Encode(book, mapID)
  local messages = {}
  local byBoss = book and book[mapID]
  if not byBoss then
    return messages
  end
  local keys = {}
  for key in pairs(byBoss) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  local prefix = "1|LB|" .. tostring(mapID) .. "|"
  local text, openKey = prefix, nil
  local function flush()
    if text ~= prefix then
      messages[#messages + 1] = text
    end
    text, openKey = prefix, nil
  end
  for _, key in ipairs(keys) do
    for _, id in ipairs(B.Items(book, mapID, key)) do
      if byBoss[key][id] >= 0 then
        local piece
        if openKey == key then
          piece = "," .. id
        else
          piece = (text ~= prefix and ";" or "") .. key .. ":" .. id
        end
        if #text + #piece > B.MAX_BYTES then
          flush()
          piece = key .. ":" .. id
        end
        text, openKey = text .. piece, key
      end
    end
  end
  flush()
  return messages
end

-- Returns mapID and { { bossKey, itemID } } with everything validated, or nil.
function B.Decode(index, message)
  if type(message) ~= "string" or #message > 255 then
    return nil
  end
  local mapID, body = message:match("^1|LB|(%d+)|([%-%d:,;]+)$")
  mapID = tonumber(mapID)
  if not mapID or not index.byMap[mapID] then
    return nil
  end
  local entries = {}
  for group in body:gmatch("[^;]+") do
    local key, ids = group:match("^(%-?%d+):([%d,]+)$")
    key = tonumber(key)
    if key and (key == B.OTHER or B.Boss(index, mapID, key)) then
      for id in ids:gmatch("%d+") do
        id = tonumber(id)
        if isID(id) and #entries < B.MAX_PER_MESSAGE then
          entries[#entries + 1] = { key, id }
        end
      end
    end
  end
  return mapID, entries
end
