-- The loot catalog: dungeons and raids with their bosses (from the Forever client data) and the items each boss
-- drops, learned in play (Logic/LootBook.lua). Forever has no Encounter Journal, so the items come from:
--   1. the group loot history (each drop carries the boss's encounter ID);
--   2. the loot window when you loot a boss corpse yourself (the corpse's name is matched with the boss names);
--   3. other SafeLoot users in your group (addon messages with item IDs only: no names, no players, no chat);
--   4. the optional add-on SafeLoot_LootData (tables from AtlasLoot Classic Forever, GPL): a starting point, shown as
--      "not seen yet" until the item is really seen dropping.
local _, SL = ...
local Cat = SL:NewModule("Catalog")
SL.Catalog = Cat
local API, Book, Names = SL.API, SL.LootBook, SL.Names

local PREFIX = "SafeLoot"
local MAX_INFO = 1500
local MAX_PENDING = 60   -- items asked to the server at the same time
local RETRY = 15         -- seconds before asking again for an item that did not answer
local infoCache, infoCount, pending, failed = {}, 0, {}, {}

local function observe(key, detail)
  if SL.Diagnostics then
    SL.Diagnostics:Observe(key, detail)
  end
end

function Cat:OnInitialize()
  self.index = Book.Index(SL.InstanceData, SL.language)
  if type(SL.db.loot) ~= "table" then
    SL.db.loot = {}
  end
end

-- SafeLoot_LootData loads after SafeLoot (it depends on it) and leaves its table in SafeLootDataPack.
function Cat:LoadPack()
  local pack = type(SafeLootDataPack) == "table" and SafeLootDataPack or nil
  self.packItems = pack and Book.AddPack(self.index, pack) or 0
  SafeLootDataPack = nil -- copied: free the source table
  SL.db.loot = Book.Validate(SL.db.loot, self.index)
end

-- Items of a boss to show: { { id, seen, info } }. Without the ones the server does not know, and without grey and
-- white ones that only come from the data pack.
function Cat:Items(mapID, bossKey)
  local list = {}
  for _, entry in ipairs(Book.Known(SL.db.loot, self.index, mapID, bossKey)) do
    local info = self:ItemInfo(entry.id)
    local hidden = failed[entry.id] or (not entry.seen and info and info.quality and info.quality < 2)
    if not hidden then
      entry.info = info
      list[#list + 1] = entry
    end
  end
  return list
end

function Cat:Totals(mapID)
  return Book.Totals(SL.db.loot, self.index, mapID)
end

function Cat:Instances()
  return self.index.list
end

function Cat:Instance(mapID)
  return mapID and self.index.byMap[mapID] or nil
end

-- The known instance you are in right now, or nil.
function Cat:Here()
  local mapID = API.InstanceMapID()
  return mapID and self.index.byMap[mapID] and mapID or nil
end

-- Where the group is going: the one chosen in the Rules tab, otherwise the instance you are in.
function Cat:Destination()
  local c = SL.Contract and SL.Contract:Get()
  if c and c.instance and self.index.byMap[c.instance] then
    return c.instance
  end
  return self:Here()
end

function Cat:Stats()
  local maps, items = 0, 0
  for mapID in pairs(SL.db.loot or {}) do
    local n = Book.Count(SL.db.loot, mapID)
    if n > 0 then
      maps, items = maps + 1, items + n
    end
  end
  return { maps = maps, items = items, pack = self.packItems or 0 }
end

function Cat:Learn(mapID, bossKey, itemID, shared)
  local isNew = Book.Learn(SL.db.loot, self.index, mapID, bossKey, itemID, API.Now(), shared)
  if isNew then
    SL:Debounce("catalog-changed", 0.5, function()
      SL:Fire("CATALOG_CHANGED", mapID)
    end)
  end
  return isNew
end

-- 1. Group loot history ------------------------------------------------------------------------------------------
function Cat:OnDrop(_, encounterID, lootListKey)
  if API.IsSecret(encounterID) or API.IsSecret(lootListKey) then
    return
  end
  local info = API.LootDrop(encounterID, lootListKey)
  if type(info) == "table" then
    self:LearnDrop(encounterID, info.itemHyperlink)
  end
end

function Cat:LearnDrop(encounterID, link)
  local itemID = API.ItemIDFromLink(link)
  if not itemID then
    return
  end
  local here = API.InstanceMapID()
  local mapID, bossKey = Book.Place(self.index, encounterID, here)
  if mapID and bossKey == Book.OTHER then
    -- an ID the shipped data does not have: the encounter's name (same client language) may still match a boss
    local boss = Book.BossByName(self.index, mapID, API.EncounterName(encounterID))
    if boss then
      bossKey = boss.key
    end
  end
  observe("loot_book_drop", { encounter = encounterID, map = here, boss = bossKey ~= nil and bossKey ~= Book.OTHER })
  if mapID then
    self:Learn(mapID, bossKey, itemID)
  end
end

-- 2. Looting a boss corpse yourself -------------------------------------------------------------------------------
function Cat:OnLootOpened()
  local mapID = self:Here()
  if not mapID then
    return
  end
  local boss = Book.BossByName(self.index, mapID, API.TargetCorpseName())
  observe("loot_book_corpse", { boss = boss ~= nil, map = mapID })
  if not boss then
    return -- trash or a chest: nothing to put under a boss
  end
  for _, slot in ipairs(API.LootSlots()) do
    if (slot.quality or 0) >= 2 then -- uncommon and better: what people reserve
      self:Learn(mapID, boss.key, API.ItemIDFromLink(slot.link))
    end
  end
end

-- Item names, links and icons (the game loads them on demand) -----------------------------------------------------
function Cat:ItemInfo(itemID)
  if type(itemID) ~= "number" then
    return nil
  end
  local cached = infoCache[itemID]
  if cached then
    return cached
  end
  local info = API.ItemByID(itemID)
  if info and info.name then
    if infoCount >= MAX_INFO then
      infoCache, infoCount = {}, 0
    end
    infoCache[itemID] = info
    infoCount = infoCount + 1
    return info
  end
  if not failed[itemID] then
    local now, waiting = API.Clock(), 0
    for _, asked in pairs(pending) do
      if now - asked < RETRY then
        waiting = waiting + 1
      end
    end
    local asked = pending[itemID]
    -- a few at a time: a whole raid at once would flood the server. The rest is asked as answers arrive.
    if (not asked or now - asked >= RETRY) and waiting < MAX_PENDING then
      pending[itemID] = now
      API.RequestItem(itemID)
    end
  end
  return info
end

function Cat:OnItemInfo(_, itemID, success)
  if type(itemID) == "number" and not API.IsSecret(itemID) and pending[itemID] then
    pending[itemID] = nil
    if not API.IsSecret(success) and success == false then
      failed[itemID] = true -- the server does not have this item: not asked again, not shown
    end
    SL:Debounce("catalog-items", 0.3, function()
      SL:Fire("CATALOG_CHANGED")
    end)
  end
end

-- A typed name that matches a known item of the instance (so a typed reserve still gets its item ID).
function Cat:FindItemID(mapID, name)
  if not mapID or type(name) ~= "string" then
    return nil
  end
  local target = SL.Rules.Normalize(name)
  local inst = self.index.byMap[mapID]
  local keys = { Book.OTHER }
  for _, boss in ipairs(inst and inst.bosses or {}) do
    keys[#keys + 1] = boss.key
  end
  for _, key in ipairs(keys) do
    for _, entry in ipairs(Book.Known(SL.db.loot, self.index, mapID, key)) do
      local info = self:ItemInfo(entry.id)
      if info and info.name and SL.Rules.Normalize(info.name) == target then
        return entry.id
      end
    end
  end
  return nil
end

-- 3. Sharing with SafeLoot users in the group -------------------------------------------------------------------
function Cat:Ask(mapID)
  if not SL.settings.shareLoot or not self.index.byMap[mapID] or not API.InGroup() or API.ChatLocked() then
    return false
  end
  if not SL:Cooldown("loot-ask-" .. mapID, 300) then
    return false
  end
  local ok = API.SendAddon(PREFIX, Book.Query(mapID), API.GroupChatType())
  observe("loot_book_sync", { asked = mapID, ok = ok })
  return ok
end

function Cat:Answer(mapID)
  if not SL.settings.shareLoot or not API.InGroup() or API.ChatLocked() then
    return
  end
  local messages = Book.Encode(SL.db.loot, mapID)
  if #messages == 0 or not SL:Cooldown("loot-answer-" .. mapID, 60) then
    return
  end
  local chatType = API.GroupChatType()
  for i = 1, math.min(#messages, 10) do
    local message = messages[i]
    -- spaced out: the game throttles bursts of addon messages
    if C_Timer and C_Timer.After then
      C_Timer.After(0.4 * i, function()
        API.SendAddon(PREFIX, message, chatType)
      end)
    else
      API.SendAddon(PREFIX, message, chatType)
    end
  end
end

local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

function Cat:OnAddonMessage(_, prefix, message, channel, sender)
  if prefix ~= PREFIX or API.IsSecret(message) or API.IsSecret(sender) or API.IsSecret(channel) then
    return
  end
  if type(message) ~= "string" or not GROUP_CHANNELS[channel] or not SL.settings.shareLoot or Names.IsMe(sender) then
    return
  end
  local asked = Book.ParseQuery(self.index, message)
  if asked then
    -- a short random wait so that not everybody answers at the same moment
    local wait = 0.5 + math.random() * 1.5
    if C_Timer and C_Timer.After then
      C_Timer.After(wait, function()
        SL.SafeCall("loot answer", Cat.Answer, Cat, asked)
      end)
    else
      self:Answer(asked)
    end
    return
  end
  local mapID, entries = Book.Decode(self.index, message)
  if mapID then
    local learned = 0
    for _, entry in ipairs(entries) do
      -- shared knowledge only fills free room: it never pushes out what you saw yourself
      if self:Learn(mapID, entry[1], entry[2], true) then
        learned = learned + 1
      end
    end
    observe("loot_book_sync", { received = #entries, learned = learned })
  end
end

-- Entering a dungeon sets it as the destination ------------------------------------------------------------------
function Cat:OnZone()
  if not API.InInstance() then
    return
  end
  local mapID = API.InstanceMapID()
  local here = mapID and self.index.byMap[mapID] and mapID or nil
  observe("instance_map", { map = mapID, known = here ~= nil })
  if here and API.InGroup() then
    SL.Contract:SetDestination(here)
  end
end

function Cat:OnEnable()
  self:LoadPack()
  API.RegisterPrefix(PREFIX)
  SL:RegisterEvent("LOOT_HISTORY_UPDATE_DROP", self, self.OnDrop)
  SL:RegisterEvent("LOOT_OPENED", self, self.OnLootOpened)
  -- GetItemInfo answers through the first event, RequestLoadItemDataByID through the second (Forever UI source)
  SL:RegisterEvent("GET_ITEM_INFO_RECEIVED", self, self.OnItemInfo)
  SL:RegisterEvent("ITEM_DATA_LOAD_RESULT", self, self.OnItemInfo)
  SL:RegisterEvent("CHAT_MSG_ADDON", self, self.OnAddonMessage)
  local function zone()
    SL:Debounce("catalog-zone", 1, function()
      Cat:OnZone()
    end)
  end
  SL:RegisterEvent("PLAYER_ENTERING_WORLD", self, zone)
  SL:RegisterEvent("ZONE_CHANGED_NEW_AREA", self, zone)
  -- someone new in the group may know more of the destination's loot
  SL:RegisterEvent("GROUP_ROSTER_UPDATE", self, function()
    SL:Debounce("catalog-roster", 2, function()
      local dest = Cat:Destination()
      if dest then
        Cat:Ask(dest)
      end
    end)
  end)
end
