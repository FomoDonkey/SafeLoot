-- The Detector: flags Need rolls a class can never use, and rolls that break the agreed rules
-- (docs/PROMPT_MAESTRO.md §4.2). Source: C_LootHistory (roll state per player). Never accuses on its own:
-- it shows a mark and offers a button; nothing is sent to chat without a click.
local _, SL = ...
local LW = SL:NewModule("LootWatch")
SL.LootWatch = LW
local API, Judge, Names, T, L = SL.API, SL.Judge, SL.Names, SL.Theme, SL.L

LW.judged = {}

local function reasonText(verdict, roll, item)
  local class = API.LocalizedClass(roll.playerClass) or roll.playerClass or "?"
  local key = "REASON_" .. string.upper(verdict.reason)
  local template = L[key] or L.REASON_GENERIC
  return string.format(template, class)
end

function LW:Mark(roll, item, verdict)
  local who = Names.Short(roll.playerName) or roll.playerName or "?"
  local link = item.link or item.name or "?"
  local title = verdict.level == Judge.IMPOSSIBLE and L.MARK_IMPOSSIBLE or L.MARK_DOUBTFUL
  local because = reasonText(verdict, roll, item)
  local tone = verdict.level == Judge.IMPOSSIBLE and "bad" or "warn"
  SL.Run:Log("mark", {
    text = "|T" .. (tone == "bad" and T.tex.bad or T.tex.alert) .. ":14:14|t " .. string.format(L.MARK_LINE, who, link, because),
    who = who, item = item.name, level = verdict.level, reason = verdict.reason,
  })
  if verdict.level == Judge.IMPOSSIBLE and SL.settings.memory then
    SL.Memory.Add(SL.db.players, who, {
      kind = "need_impossible", t = API.Now(), place = API.PlaceName(), item = item.name, link = item.link,
      class = roll.playerClass,
    })
    SL:Fire("MEMORY_CHANGED", who)
  end
  SL.Alert:Toast({
    tone = tone,
    title = title,
    body = string.format(L.MARK_LINE, who, link, because),
    seconds = 15,
    action = { label = L.ACTION_TELL_GROUP, fn = function()
      API.SendGroupChat(string.format(L.CHAT_MARK, who, item.name or "?", because))
    end },
    -- class-based marks can be wrong if Forever changed a proficiency: one click teaches the detector
    action2 = verdict.reason and verdict.reason:find("^class_") and { label = L.ACTION_MISTAKE, fn = function()
      LW:Mistake(roll, item)
    end } or nil,
  })
end

-- The player says a class-based mark was wrong: never flag that class with that item type again, and take the
-- automatic note back from the memory.
function LW:Mistake(roll, item)
  local class = roll.playerClass
  if not class or not item.classID or not item.subClassID then
    return
  end
  SL.settings.exceptions = SL.settings.exceptions or {}
  SL.settings.exceptions[class .. ":" .. tostring(item.classID) .. ":" .. tostring(item.subClassID)] = true
  local record = SL.Memory.Get(SL.db.players, roll.playerName)
  if record then
    for i = #record.events, 1, -1 do
      local event = record.events[i]
      if event.kind == "need_impossible" and event.item == item.name then
        table.remove(record.events, i)
        break
      end
    end
  end
  SL.Run:Log("note", { text = string.format(L.MISTAKE_DONE, API.LocalizedClass(class) or class) })
  SL:Print(string.format(L.MISTAKE_DONE, API.LocalizedClass(class) or class))
  SL:Fire("MEMORY_CHANGED", roll.playerName)
end

function LW:ResetExceptions()
  SL.settings.exceptions = {}
  SL:Print(L.EXCEPTIONS_RESET)
end

function LW:OnDrop(_, encounterID, lootListKey)
  if not SL.settings.detector then
    return
  end
  local info = API.LootDrop(encounterID, lootListKey)
  if SL.Diagnostics then
    SL.Diagnostics:Observe("loot_history_drop", {
      ok = info ~= nil, rolls = info and info.rollInfos and #info.rollInfos or 0,
      hasClass = info and info.rollInfos and info.rollInfos[1] and type(info.rollInfos[1].playerClass) == "string" or false,
    })
  end
  if not info or type(info.rollInfos) ~= "table" then
    return
  end
  local item = API.ItemFacts(info.itemHyperlink)
  if not item then
    return
  end
  local contract = SL.Contract:Get()
  for _, roll in ipairs(info.rollInfos) do
    -- inside instances the game may hide identity as "secret" values: such rolls are skipped, never compared
    if type(roll) == "table" and not API.IsSecret(roll.isSelf) and not roll.isSelf
      and not API.IsSecret(roll.playerName) and not API.IsSecret(roll.playerClass) and not API.IsSecret(roll.state) then
      local key = tostring(encounterID) .. ":" .. tostring(lootListKey) .. ":" .. tostring(roll.playerName) .. ":" .. tostring(roll.state)
      if not self.judged[key] then
        self:Remember(key)
        local verdict = Judge.Evaluate(roll, item, contract, { exceptions = SL.settings.exceptions })
        -- the chat fallback must not flag the same roll again
        self:Remember("chat:" .. tostring(Names.Short(roll.playerName)) .. ":" .. tostring(item.name) .. ":"
          .. math.floor(API.Now() / 60))
        if verdict then
          self:Mark(roll, item, verdict)
        end
      end
    end
  end
  if info.winner and type(info.winner) == "table" and not API.IsSecret(info.winner.playerName) then
    -- never store a secret value in SavedVariables
    local winnerClass = not API.IsSecret(info.winner.playerClass) and info.winner.playerClass or nil
    SL.Run:LogDrop(tostring(encounterID) .. ":" .. tostring(lootListKey), item.link or item.name,
      Names.Short(info.winner.playerName), winnerClass)
  end
end

-- Bounded set of rolls already judged (also shared with the chat fallback so nothing is flagged twice).
function LW:Remember(key)
  self.judgedCount = (self.judgedCount or 0) + 1
  if self.judgedCount > 500 then
    self.judged, self.judgedCount = {}, 1
  end
  self.judged[key] = true
end

-- Fallback: the group-loot chat line "X has selected Need for: [item]" (game string LOOT_ROLL_NEED). Only used
-- when the game gives that string; lines hidden by the game (secret) are skipped. Dedupe with the history by
-- player + item within 60 s.
local needPattern
local function buildNeedPattern()
  if needPattern ~= nil then
    return needPattern
  end
  needPattern = false
  local template = type(LOOT_ROLL_NEED) == "string" and LOOT_ROLL_NEED or nil
  if template and select(2, template:gsub("%%s", "")) == 2 then
    local escaped = template:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)")
    needPattern = "^" .. escaped .. "$"
  end
  return needPattern
end

function LW:OnLootChat(_, text)
  if not SL.settings.detector or API.IsSecret(text) or type(text) ~= "string" then
    return
  end
  local pattern = buildNeedPattern()
  if not pattern then
    return
  end
  local who, link = text:match(pattern)
  if not who or not link then
    return
  end
  if SL.Diagnostics then
    SL.Diagnostics:Observe("chat_loot_need")
  end
  if Names.IsMe(who) then
    return
  end
  local item = API.ItemFacts(link)
  if not item then
    return
  end
  local class
  for _, member in ipairs(API.GroupMembers()) do
    if Names.Same(member.name, who) then
      class = member.class
    end
  end
  local key = "chat:" .. tostring(Names.Short(who)) .. ":" .. tostring(item.name) .. ":" .. math.floor(API.Now() / 60)
  if self.judged[key] or not class then
    return
  end
  self:Remember(key)
  local roll = { playerName = who, playerClass = class, state = Judge.NEED_MAIN }
  local verdict = Judge.Evaluate(roll, item, SL.Contract:Get(), { exceptions = SL.settings.exceptions })
  if verdict then
    self:Mark(roll, item, verdict)
  end
end

function LW:OnEnable()
  SL:RegisterCommand("exceptions", function()
    LW:ResetExceptions()
  end, L.CMD_RESET_EXCEPTIONS, { "excepciones" })
  SL:RegisterEvent("LOOT_HISTORY_UPDATE_DROP", self, self.OnDrop)
  SL:RegisterEvent("CHAT_MSG_LOOT", self, self.OnLootChat)
  SL:On("RUN_STARTED", self, function()
    LW.judged = {}
  end)
end
