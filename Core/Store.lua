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
    showTarget = true,      -- badge under the target's portrait
    showWhisper = true,     -- notice when someone you marked badly whispers you
    showUnitMenu = true,    -- SafeLoot in the right-click menu of a player
    playerSort = "recent",  -- "recent" | "name" | "times"
    suggestRules = true,
    sounds = true,
    largeText = false,
    reduceMotion = false,
    scale = 1.0,
    onboarded = false,
    showMinimap = true,     -- the button on the edge of the minimap
    minimapAngle = 182,     -- where it is (degrees, 0 = right)
    shareLoot = true,       -- exchange the loot book (item IDs per boss) with SafeLoot users in your group
  },
  players = {},
  runs = {},
  loot = {},                -- loot book: [mapID][bossKey][itemID] = last seen (Logic/LootBook.lua)
  diagnostics = { observed = {}, report = nil },
  errors = {},
}
Store.DEFAULTS = DEFAULTS

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
  Store.ValidateChar(SafeLootCharDB)
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
local function keep(record, field, kind)
  local value = record[field]
  if value ~= nil and (type(value) ~= kind or value ~= value) then
    record[field] = nil -- (value ~= value: not a number)
  end
end

local function cleanEvents(events)
  for i = #events, 1, -1 do
    local event = events[i]
    if type(event) ~= "table" or type(event.kind) ~= "string" then
      table.remove(events, i)
    else
      for _, field in ipairs({ "note", "place", "item", "link", "text", "who" }) do
        keep(event, field, "string")
      end
      keep(event, "t", "number")
      keep(event, "severity", "number")
    end
  end
end

-- A run of the journal (saved ones and the one in progress). False when it cannot be used.
local function cleanRun(run)
  if type(run) ~= "table" or type(run.events) ~= "table" or type(run.drops) ~= "table" then
    return false
  end
  if type(run.members) ~= "table" then
    run.members = {}
  end
  for _, field in ipairs({ "startedAt", "endedAt", "outsideSince" }) do
    keep(run, field, "number")
  end
  keep(run, "place", "string")
  cleanEvents(run.events)
  for key, drop in pairs(run.drops) do
    if type(drop) ~= "table" then
      run.drops[key] = nil
    else
      keep(drop, "item", "string")
      keep(drop, "winner", "string")
      keep(drop, "t", "number")
    end
  end
  return true
end

local RANGES = { scale = { 0.8, 1.3 }, memoryDays = { 30, 365 }, minimapAngle = { 0, 360 } }
local CHOICES = { playerSort = { recent = true, name = true, times = true } }

function Store.Validate(db)
  for name, record in pairs(db.players) do
    if type(name) ~= "string" or type(record) ~= "table" then
      db.players[name] = nil
    else
      if type(record.events) ~= "table" then
        record.events = {}
      end
      cleanEvents(record.events)
      for _, field in ipairs({ "first", "last", "seen" }) do
        keep(record, field, "number")
      end
      keep(record, "class", "string")
    end
  end
  for i = #db.runs, 1, -1 do
    if not cleanRun(db.runs[i]) then
      table.remove(db.runs, i)
    end
  end
  for key, value in pairs(DEFAULTS.settings) do
    local current = db.settings[key]
    local range = RANGES[key]
    if type(current) ~= type(value) or current ~= current or (CHOICES[key] and not CHOICES[key][current]) then
      db.settings[key] = type(value) == "table" and {} or value
    elseif range then
      db.settings[key] = math.max(range[1], math.min(range[2], current))
    end
  end
  local code = db.settings.language
  if code ~= "auto" and code ~= "enUS" and not (SL.Locales and SL.Locales[code]) then
    db.settings.language = "auto"
  end
  for i = #db.errors, 1, -1 do
    if type(db.errors[i]) ~= "table" or type(db.errors[i].text) ~= "string" then
      table.remove(db.errors, i)
    end
  end
  for key, entry in pairs(db.diagnostics.observed) do
    if type(entry) ~= "table" or type(entry.count) ~= "number" then
      db.diagnostics.observed[key] = nil
    end
  end
  if type(db.diagnostics.report) ~= "table" then
    db.diagnostics.report = nil
  end
end

function Store.ValidateChar(char)
  for key, p in pairs(char.positions) do
    if type(p) ~= "table" or type(p[1]) ~= "string" or type(p[2]) ~= "string" or type(p[3]) ~= "number" or type(p[4]) ~= "number"
      or p[3] ~= p[3] or p[4] ~= p[4] then
      char.positions[key] = nil
    end
  end
  if char.run ~= nil and not cleanRun(char.run) then
    char.run = nil
  end
end

-- Last resort if Init failed: in-memory defaults so every module still works this session. What was saved is NOT
-- replaced: until 0.5.1 it was, and a failure here would have erased every mark and note at logout.
function Store:Fallback()
  self.failed = true
  SL.db, SL.char = merge({}, DEFAULTS), merge({}, CHAR_DEFAULTS)
  SL.settings = SL.db.settings
  if type(SafeLootDB) ~= "table" then
    SafeLootDB = SL.db
  end
  if type(SafeLootCharDB) ~= "table" then
    SafeLootCharDB = SL.char
  end
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
