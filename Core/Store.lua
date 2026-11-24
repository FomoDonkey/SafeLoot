-- SavedVariables: defaults, schema version, migrations, pruning (docs/PROMPT_MAESTRO.md §8).
local _, SL = ...
local Store = {}
SL.Store = Store

Store.SCHEMA = 1

local DEFAULTS = {
  schema = 1,
  settings = {
    language = "auto",      -- "auto" (game language) | "enUS" | "esES" | "deDE" | "frFR" | "ptBR"
    alarmCenter = true,     -- native centre warning (RaidWarning frame)
    alarmSound = true,      -- SOUNDKIT.RAID_WARNING
    alarmVoice = false,     -- text to speech
    alarmPanel = true,      -- action panel with buttons
    panelInCombat = false,  -- show the panel during combat (the warning is always immediate)
    summaryAlways = false,  -- end-of-run summary: false = only when something happened
    showIndicator = true,   -- the small rules bar while in a group
    exceptions = {},        -- detector false positives the player reported: ["MAGE:4:3"] = true
    detector = true,
    memory = true,
    memoryDays = 90,
    showTooltip = true,
    showFinder = true,
    showInvite = true,
    showGroupJoin = true,
    suggestRules = true,
    sounds = true,
    largeText = false,
    reduceMotion = false,
    scale = 1.0,
    onboarded = false,
    shareLoot = true,       -- exchange the loot book (item IDs per boss) with SafeLoot users in your group
  },
  players = {},
  runs = {},
  loot = {},                -- loot book: [mapID][bossKey][itemID] = last seen (Logic/LootBook.lua)
  diagnostics = { observed = {}, report = nil },
  errors = {},
}

local CHAR_DEFAULTS = {
  positions = {},
  run = nil,
}

local function merge(target, defaults)
  for key, value in pairs(defaults) do
    if type(value) == "table" then
      if type(target[key]) ~= "table" then
        target[key] = {}
      end
      merge(target[key], value)
    elseif target[key] == nil then
      target[key] = value
    end
  end
  return target
end
Store.Merge = merge

local MIGRATIONS = {
  -- [2] = function(db) ... end,
}

function Store:Init()
  SafeLootDB = type(SafeLootDB) == "table" and SafeLootDB or {}
  SafeLootCharDB = type(SafeLootCharDB) == "table" and SafeLootCharDB or {}
  local db = SafeLootDB
  local from = tonumber(db.schema) or Store.SCHEMA
  for version = from + 1, Store.SCHEMA do
    if MIGRATIONS[version] then
      SL.SafeCall("migration " .. version, MIGRATIONS[version], db)
    end
  end
  merge(db, DEFAULTS)
  Store.Validate(db)
  db.schema = Store.SCHEMA
  merge(SafeLootCharDB, CHAR_DEFAULTS)
  SL.db = db
  SL.char = SafeLootCharDB
  SL.settings = db.settings
  if SL.Memory and SL.Memory.Prune then
    pcall(SL.Memory.Prune, db.players, SL.API.Now(), tonumber(db.settings.memoryDays) or 90, 2000)
  end
  while #db.runs > 50 do
    table.remove(db.runs, 1)
  end
end

-- SavedVariables can be edited by hand or damaged: drop anything with the wrong shape instead of failing later.
function Store.Validate(db)
  for name, record in pairs(db.players) do
    if type(name) ~= "string" or type(record) ~= "table" then
      db.players[name] = nil
    else
      if type(record.events) ~= "table" then
        record.events = {}
      end
      for i = #record.events, 1, -1 do
        local event = record.events[i]
        if type(event) ~= "table" or type(event.kind) ~= "string" then
          table.remove(record.events, i)
        end
      end
    end
  end
  for i = #db.runs, 1, -1 do
    local run = db.runs[i]
    if type(run) ~= "table" or type(run.events) ~= "table" or type(run.drops) ~= "table" then
      table.remove(db.runs, i)
    end
  end
  for key, value in pairs(DEFAULTS.settings) do
    if type(db.settings[key]) ~= type(value) then
      db.settings[key] = value
    end
  end
end

-- Last resort if Init failed: in-memory defaults so every module still works this session.
function Store:Fallback()
  SafeLootDB = merge({}, DEFAULTS)
  SafeLootCharDB = merge({}, CHAR_DEFAULTS)
  SL.db, SL.char, SL.settings = SafeLootDB, SafeLootCharDB, SafeLootDB.settings
end

function Store:Setting(key)
  return SL.settings and SL.settings[key]
end

function Store:SetSetting(key, value)
  if SL.settings then
    SL.settings[key] = value
    SL:Fire("SETTING_CHANGED", key, value)
  end
end
