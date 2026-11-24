-- The ONLY layer that talks to the game API (docs/PROMPT_MAESTRO.md §0.3). Every function:
--   * checks the function exists before calling it (Forever lacks some globals, e.g. GetItemInfo);
--   * returns nil instead of failing;
--   * drops secret values (issecretvalue) instead of comparing or concatenating them.
local _, SL = ...
local API = {}
SL.API = API

local function secret(v)
  return issecretvalue ~= nil and issecretvalue(v) == true
end
API.IsSecret = secret

local function try(fn, ...)
  if type(fn) ~= "function" then
    return false
  end
  return pcall(fn, ...)
end
API.Try = try

function API.Now()
  return time and time() or 0
end

function API.Clock()
  return GetTime and GetTime() or 0
end

-- Group and place -----------------------------------------------------------------------------------
function API.InGroup()
  return (IsInGroup and IsInGroup()) and true or false
end

function API.InRaid()
  return (IsInRaid and IsInRaid()) and true or false
end

function API.GroupSize()
  return GetNumGroupMembers and GetNumGroupMembers() or 0
end

function API.InInstance()
  if not IsInInstance then
    return false, nil
  end
  local ok, inInstance, kind = pcall(IsInInstance)
  if not ok then
    return false, nil
  end
  return inInstance and true or false, kind
end

function API.PlaceName()
  -- outside instances GetInstanceInfo returns the continent ("Reinos del Este", seen in the real saved data):
  -- use the zone there
  if not API.InInstance() then
    for _, getter in ipairs({ GetRealZoneText, GetZoneText }) do
      if type(getter) == "function" then
        local ok, zone = pcall(getter)
        if ok and type(zone) == "string" and zone ~= "" and not secret(zone) then
          return zone
        end
      end
    end
  end
  if GetInstanceInfo then
    local ok, name = pcall(GetInstanceInfo)
    if ok and type(name) == "string" and not secret(name) and name ~= "" then
      return name
    end
  end
  if GetRealZoneText then
    local ok, zone = pcall(GetRealZoneText)
    if ok and type(zone) == "string" and not secret(zone) then
      return zone
    end
  end
  return nil
end

-- Unit tokens of everyone in the group (including "player").
function API.GroupUnits()
  local units = { "player" }
  if API.InRaid() then
    units = {}
    for i = 1, 40 do
      units[#units + 1] = "raid" .. i
    end
  elseif API.InGroup() then
    for i = 1, 4 do
      units[#units + 1] = "party" .. i
    end
  end
  return units
end

function API.UnitExists(unit)
  return (UnitExists and UnitExists(unit)) and true or false
end

function API.UnitClass(unit)
  if not UnitClass then
    return nil
  end
  local ok, _, classFile = pcall(UnitClass, unit)
  if ok and type(classFile) == "string" and not secret(classFile) then
    return classFile
  end
  return nil
end

function API.IsLeader(unit)
  if not UnitIsGroupLeader then
    return false
  end
  local ok, leader = pcall(UnitIsGroupLeader, unit)
  return ok and leader == true
end

function API.LeaderName()
  for _, unit in ipairs(API.GroupUnits()) do
    if API.UnitExists(unit) and API.IsLeader(unit) then
      return SL.Names.Unit(unit)
    end
  end
  return nil
end

-- Members as { name = "First Surname", class = "MAGE", unit = "party1" }.
function API.GroupMembers()
  local members = {}
  for _, unit in ipairs(API.GroupUnits()) do
    if API.UnitExists(unit) then
      local name = SL.Names.Unit(unit)
      if name then
        members[#members + 1] = { name = name, class = API.UnitClass(unit), unit = unit }
      end
    end
  end
  return members
end

-- Loot rules ----------------------------------------------------------------------------------------
-- Enum.LootMethod in Forever: Freeforall=0, Roundrobin=1, Masterlooter=2, Group=3, Needbeforegreed=4, Personal=5.
local LEGACY_METHODS = {
  freeforall = 0, roundrobin = 1, master = 2, group = 3, needbeforegreed = 4, personalloot = 5,
}

local function unitForLooter(partyID, raidID)
  if type(raidID) == "number" and raidID > 0 then
    return "raid" .. raidID
  end
  if partyID == 0 then
    return "player"
  end
  if type(partyID) == "number" and partyID > 0 then
    return "party" .. partyID
  end
  return nil
end

-- Returns method (number), masterLooterName (string|nil), or nil if the game hides it.
function API.LootMethod()
  local method, partyID, raidID
  if C_PartyInfo and C_PartyInfo.GetLootMethod then
    local ok, m, p, r = pcall(C_PartyInfo.GetLootMethod)
    if not ok or secret(m) then
      return nil
    end
    method, partyID, raidID = m, p, r
  elseif GetLootMethod then
    local ok, m, p, r = pcall(GetLootMethod)
    if not ok or secret(m) then
      return nil
    end
    method = type(m) == "string" and LEGACY_METHODS[m] or m
    partyID, raidID = p, r
  else
    return nil
  end
  if type(method) ~= "number" then
    return nil
  end
  local looter
  if method == 2 and not secret(partyID) and not secret(raidID) then
    local unit = unitForLooter(partyID, raidID)
    looter = unit and SL.Names.Unit(unit) or nil
  end
  return method, looter
end

function API.LootThreshold()
  if not GetLootThreshold then
    return nil
  end
  local ok, threshold = pcall(GetLootThreshold)
  if ok and type(threshold) == "number" and not secret(threshold) then
    return threshold
  end
  return nil
end

-- Snapshot of the current loot rules, as Logic/Rules expects.
function API.LootState()
  local method, looter = API.LootMethod()
  if method == nil then
    return nil
  end
  return {
    method = method,
    masterLooter = looter,
    threshold = API.LootThreshold(),
    leader = API.LeaderName(),
  }
end

-- Loot history ---------------------------------------------------------------------------------------
-- C_LootHistory.GetSortedInfoForDrop(encounterID, lootListKey) -> EncounterLootDropInfo
-- { itemHyperlink, rollInfos = { {playerName, playerGUID, playerClass, isSelf, state, isWinner, roll} }, winner, ... }
function API.LootDrop(encounterID, lootListKey)
  if not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then
    return nil
  end
  local ok, info = pcall(C_LootHistory.GetSortedInfoForDrop, encounterID, lootListKey)
  if not ok or type(info) ~= "table" or secret(info) then
    return nil
  end
  return info
end

-- Items ----------------------------------------------------------------------------------------------
-- Forever has no global GetItemInfo (BlazonGuild probe): always C_Item. Facts are cached per link (a drop fires
-- LOOT_HISTORY_UPDATE_DROP many times while people roll); the cache is small and only keeps complete answers.
local itemCache, itemCacheSize = {}, 0
function API.ItemFacts(link)
  if type(link) ~= "string" or secret(link) then
    return nil
  end
  if itemCache[link] then
    return itemCache[link]
  end
  local facts = { link = link }
  if C_Item and C_Item.GetItemInfoInstant then
    local ok, itemID, _, _, equipLoc, icon, classID, subClassID = pcall(C_Item.GetItemInfoInstant, link)
    if ok and itemID then
      facts.itemID, facts.equipLoc, facts.icon = itemID, equipLoc, icon
      facts.classID, facts.subClassID = classID, subClassID
    end
  end
  if C_Item and C_Item.GetItemInfo then
    local ok, name, _, quality, _, _, _, _, _, _, _, _, _, _, bindType = pcall(C_Item.GetItemInfo, link)
    if ok and name then
      facts.name, facts.quality, facts.bindType = name, quality, bindType
    end
  end
  local complete = facts.name ~= nil
  if not facts.name then
    facts.name = link:match("%[(.-)%]")
  end
  if C_Item and C_Item.GetItemStats then
    local ok, stats = pcall(C_Item.GetItemStats, link)
    if ok and type(stats) == "table" then
      facts.stats = stats
    end
  end
  if complete then
    if itemCacheSize >= 200 then
      itemCache, itemCacheSize = {}, 0
    end
    itemCache[link] = facts
    itemCacheSize = itemCacheSize + 1
  end
  return facts
end

function API.LFGResult(resultID)
  if not (C_LFGList and C_LFGList.GetSearchResultInfo) or not resultID then
    return nil
  end
  local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
  if ok and type(info) == "table" then
    return info
  end
  return nil
end

function API.UnitIsPlayer(unit)
  if not UnitIsPlayer then
    return false
  end
  local ok, isPlayer = pcall(UnitIsPlayer, unit)
  return ok and isPlayer == true
end

function API.UnitIsDead()
  if UnitIsDeadOrGhost then
    local ok, dead = pcall(UnitIsDeadOrGhost, "player")
    return ok and dead == true
  end
  return false
end

-- Chat and addon messages ----------------------------------------------------------------------------
function API.GroupChatType()
  if API.InRaid() then
    return "RAID"
  end
  local inInstance, kind = API.InInstance()
  if inInstance and IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
    return "INSTANCE_CHAT"
  end
  return "PARTY"
end

-- Only ever called from a click (hardware event). Never SAY/YELL/EMOTE. The text is cleaned (no "|" escapes,
-- valid UTF-8, <= 255 bytes) and there is a short cooldown so repeated clicks never flood the group chat.
function API.SendGroupChat(text)
  if type(text) ~= "string" or text == "" or not API.InGroup() then
    return false
  end
  -- keeps real item links (everyone can hover the reserved item); any other "|" code is removed
  local clean = SL.Rules.CleanChat(text, 255)
  if not clean then
    return false
  end
  if not SL:Cooldown("group-chat", 4) then
    SL:Print(SL.L.CHAT_COOLDOWN)
    return false
  end
  local chatType = API.GroupChatType()
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  local ok = try(send, clean, chatType)
  return ok
end

function API.RegisterPrefix(prefix)
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
    return ok, result
  end
  return false
end

function API.SendAddon(prefix, message, chatType, target)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
    return false, "missing"
  end
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, prefix, message, chatType, target)
  if not ok then
    return false, "error"
  end
  return result == 0 or result == true or result == nil, result
end

function API.ChatLocked()
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    return ok and locked == true
  end
  return false
end

-- Output: sound, voice, centre warning ---------------------------------------------------------------
function API.PlaySound(kit)
  if PlaySound and kit then
    pcall(PlaySound, kit, "Master")
  end
end

function API.Speak(text)
  if not (C_VoiceChat and C_VoiceChat.SpeakText and C_VoiceChat.GetTtsVoices) or type(text) ~= "string" then
    return false
  end
  local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
  if not ok or type(voices) ~= "table" or not voices[1] then
    return false
  end
  local voiceID = voices[1].voiceID
  -- Forever signature (VoiceChatDocumentation): SpeakText(voiceID, text, rate, volume, overlap)
  return (pcall(C_VoiceChat.SpeakText, voiceID, text, 0, 100, false))
end

function API.CenterWarning(text, color, seconds)
  color = color or { r = 1, g = 0.1, b = 0.1 }
  if RaidWarningUtil and RaidWarningUtil.AddMessage then
    if pcall(RaidWarningUtil.AddMessage, text, color, seconds) then
      return true
    end
  end
  if RaidWarningFrame and RaidWarningFrame.AddMessage then
    return (pcall(RaidWarningFrame.AddMessage, RaidWarningFrame, text, color, seconds))
  end
  return false
end

-- UI helpers -----------------------------------------------------------------------------------------
function API.TemplateExists(template)
  if not template then
    return true
  end
  if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
    local ok, info = pcall(C_XMLUtil.GetTemplateInfo, template)
    return ok and info ~= nil
  end
  return true -- cannot check; assume it exists
end

function API.ClassColor(classFile)
  if not classFile then
    return nil
  end
  if C_ClassColor and C_ClassColor.GetClassColor then
    local ok, color = pcall(C_ClassColor.GetClassColor, classFile)
    if ok and color then
      return color
    end
  end
  return RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] or nil
end

function API.LocalizedClass(classFile)
  if LOCALIZED_CLASS_NAMES_MALE and classFile then
    return LOCALIZED_CLASS_NAMES_MALE[classFile] or classFile
  end
  return classFile
end

function API.GameBuild()
  if not GetBuildInfo then
    return nil
  end
  local version, build, _, interface = GetBuildInfo()
  return tostring(version) .. "." .. tostring(build), interface
end

-- Instances, items and loot (0.4.0) ----------------------------------------------------------------------------
-- The game's map ID of the instance you are in (8th value of GetInstanceInfo); nil outside instances.
function API.InstanceMapID()
  if not API.InInstance() or not GetInstanceInfo then
    return nil
  end
  local ok, _, _, _, _, _, _, _, mapID = pcall(GetInstanceInfo)
  if ok and type(mapID) == "number" and not secret(mapID) then
    return mapID
  end
  return nil
end

function API.ItemIDFromLink(link)
  if type(link) ~= "string" or secret(link) then
    return nil
  end
  return tonumber(link:match("|Hitem:(%d+)") or link:match("^item:(%d+)"))
end

-- { id, name, link, quality, icon }. name is nil while the game is still loading the item (see RequestItem).
function API.ItemByID(itemID)
  if type(itemID) ~= "number" then
    return nil
  end
  local info = { id = itemID }
  if C_Item and C_Item.GetItemInfo then
    local ok, name, link, quality, _, _, _, _, _, _, icon = pcall(C_Item.GetItemInfo, itemID)
    if ok and type(name) == "string" and not secret(name) then
      info.name, info.link, info.quality, info.icon = name, link, quality, icon
    end
  end
  if not info.icon and C_Item and C_Item.GetItemIconByID then
    local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
    if ok and not secret(icon) then
      info.icon = icon
    end
  end
  return info
end

-- Ask the game to load an item; ITEM_DATA_LOAD_RESULT fires when it is ready.
function API.RequestItem(itemID)
  if C_Item and C_Item.RequestLoadItemDataByID then
    pcall(C_Item.RequestLoadItemDataByID, itemID)
  end
end

function API.EncounterName(encounterID)
  if type(encounterID) ~= "number" or secret(encounterID) or not (C_LootHistory and C_LootHistory.GetInfoForEncounter) then
    return nil
  end
  local ok, info = pcall(C_LootHistory.GetInfoForEncounter, encounterID)
  local name = ok and type(info) == "table" and info.encounterName
  if type(name) == "string" and not secret(name) then
    return name
  end
  return nil
end

-- Name of the dead creature you target (the corpse you are looting); nil for players and secret values.
function API.TargetCorpseName()
  if not (UnitExists and UnitIsDead and UnitName) then
    return nil
  end
  local ok, exists = pcall(UnitExists, "target")
  if not ok or secret(exists) or not exists then
    return nil
  end
  local okDead, dead = pcall(UnitIsDead, "target")
  if not okDead or secret(dead) or not dead or API.UnitIsPlayer("target") then
    return nil
  end
  local okName, name = pcall(UnitName, "target")
  if okName and type(name) == "string" and not secret(name) then
    return name
  end
  return nil
end

-- Items in the open loot window: { { link, quality } }.
function API.LootSlots()
  local slots = {}
  if not (GetNumLootItems and GetLootSlotLink) then
    return slots
  end
  local ok, n = pcall(GetNumLootItems)
  if not ok or type(n) ~= "number" or secret(n) then
    return slots
  end
  for i = 1, math.min(n, 40) do
    local okLink, link = pcall(GetLootSlotLink, i)
    if okLink and type(link) == "string" and not secret(link) then
      local quality
      if GetLootSlotInfo then
        local okInfo, _, _, _, _, q = pcall(GetLootSlotInfo, i)
        if okInfo and type(q) == "number" and not secret(q) then
          quality = q
        end
      end
      slots[#slots + 1] = { link = link, quality = quality }
    end
  end
  return slots
end

-- Shift-click on an item. Forever's own code calls ChatFrameUtil.InsertLink; ChatEdit_InsertLink is only a
-- deprecated alias that Blizzard no longer calls (verified in the Forever UI source, build 71037). Both are hooked
-- (hooksecurefunc: nothing is replaced), each path fires once.
function API.HookInsertLink(fn)
  local hooked = false
  if ChatFrameUtil and type(ChatFrameUtil.InsertLink) == "function" then
    hooksecurefunc(ChatFrameUtil, "InsertLink", fn)
    hooked = true
  end
  if type(ChatEdit_InsertLink) == "function" then
    hooksecurefunc("ChatEdit_InsertLink", fn)
    hooked = true
  end
  return hooked
end

