-- SafeLoot: namespace, event bus, internal messages, modules, combat queue, errors, slash command.
-- Rules: docs/PROMPT_MAESTRO.md. Every handler runs inside xpcall so a bug in one module never breaks another
-- and never shows a Lua error to the player.
local ADDON, SL = ...
SL.name = ADDON
SL.L = {}        -- the active strings (English base, overridden by the chosen language)
SL.Locales = {}  -- other languages: SL.Locales.esES = { KEY = "..." }
SL.modules = {}

local moduleOrder = {}
local handlers = {} -- event -> { {owner, fn}, ... }
local listeners = {} -- internal message -> { {owner, fn}, ... }
local afterCombat = {}

local frame = CreateFrame("Frame")
SL.eventFrame = frame

local function metadata(field)
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(ADDON, field)
  elseif GetAddOnMetadata then
    return GetAddOnMetadata(ADDON, field)
  end
end
SL.version = metadata("Version") or "dev"

-- Errors -----------------------------------------------------------------------------------------
local function errorHandler(err)
  local trace = debugstack and debugstack(2, 6, 0) or ""
  return tostring(err) .. "\n" .. trace
end

function SL:ReportError(where, err)
  local db = SafeLootDB
  local text = tostring(where) .. ": " .. tostring(err)
  if db then
    db.errors = db.errors or {}
    local last = db.errors[#db.errors]
    if last and last.text == text then
      last.count = (last.count or 1) + 1
      last.t = time and time() or 0
    else
      table.insert(db.errors, { text = text, t = time and time() or 0, count = 1, v = SL.version })
      while #db.errors > 30 do
        table.remove(db.errors, 1)
      end
    end
  end
  if SL.debug then
    SL:Print("|cffff5555error|r " .. text)
  end
end

-- Portable: plain Lua 5.1 xpcall drops extra arguments, so they travel in a closure (keeps the traceback).
local unpackArgs = unpack or table.unpack
local function safeCall(where, fn, ...)
  local n, args = select("#", ...), { ... }
  local ok, err = xpcall(function()
    return fn(unpackArgs(args, 1, n))
  end, errorHandler)
  if not ok then
    SL:ReportError(where, err)
  end
  return ok
end
SL.SafeCall = safeCall

-- Game events --------------------------------------------------------------------------------------
function SL:RegisterEvent(event, owner, fn)
  local list = handlers[event]
  if not list then
    list = {}
    handlers[event] = list
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then
      SL:ReportError("RegisterEvent", "unknown event " .. tostring(event))
      handlers[event] = nil
      return false
    end
  end
  table.insert(list, { owner = owner, fn = fn })
  return true
end

function SL:UnregisterEvent(event, owner)
  local list = handlers[event]
  if not list then
    return
  end
  for i = #list, 1, -1 do
    if list[i].owner == owner then
      table.remove(list, i)
    end
  end
  if #list == 0 then
    handlers[event] = nil
    frame:UnregisterEvent(event)
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then
    return
  end
  for i = 1, #list do
    local h = list[i]
    if h then
      safeCall(event, h.fn, h.owner, event, ...)
    end
  end
end)

-- Internal messages ----------------------------------------------------------------------------------
function SL:On(message, owner, fn)
  listeners[message] = listeners[message] or {}
  table.insert(listeners[message], { owner = owner, fn = fn })
end

function SL:Fire(message, ...)
  local list = listeners[message]
  if not list then
    return
  end
  for i = 1, #list do
    local h = list[i]
    safeCall(message, h.fn, h.owner, ...)
  end
end

-- Modules --------------------------------------------------------------------------------------------
function SL:NewModule(name)
  local module = { name = name }
  SL.modules[name] = module
  table.insert(moduleOrder, module)
  return module
end

-- Combat ---------------------------------------------------------------------------------------------
function SL:InCombat()
  return (InCombatLockdown and InCombatLockdown()) and true or false
end

-- Runs fn now, or as soon as combat ends. Forever blocks some calls in combat (BlazonGuild 0.29.4: the
-- guild message of the day raised ADDON_ACTION_BLOCKED in combat), so anything not needed mid-fight waits.
function SL:AfterCombat(key, fn)
  if not SL:InCombat() then
    safeCall(key, fn)
    return
  end
  afterCombat[key] = fn
end

-- Debounce: many calls in a short burst run fn once, `delay` seconds after the first one. Used for
-- GROUP_ROSTER_UPDATE, which fires dozens of times in a row in a 40-player raid.
local pending = {}
function SL:Debounce(key, delay, fn)
  if pending[key] then
    pending[key] = fn
    return
  end
  pending[key] = fn
  local function run()
    local latest = pending[key]
    pending[key] = nil
    if latest then
      safeCall(key, latest)
    end
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(delay, run)
  else
    run()
  end
end

-- Cooldown: true at most once every `seconds` per key (anti-spam for anything sent to chat).
local lastUse = {}
function SL:Cooldown(key, seconds)
  local now = GetTime and GetTime() or 0
  if lastUse[key] and now - lastUse[key] < seconds then
    return false
  end
  lastUse[key] = now
  return true
end

-- Languages --------------------------------------------------------------------------------------------
-- English is the base. The "language" setting is "auto" (the game's language) or a code; changing it needs a
-- /reload, because texts are placed when the windows are built.
SL.LANGUAGES = { "enUS", "esES", "deDE", "frFR", "ptBR" }
local CLIENT_TO_LANGUAGE = { esES = "esES", esMX = "esES", deDE = "deDE", frFR = "frFR", ptBR = "ptBR", ptPT = "ptBR" }

function SL:ResolveLanguage(choice)
  if choice and choice ~= "auto" then
    return choice
  end
  local client = GetLocale and GetLocale() or "enUS"
  return CLIENT_TO_LANGUAGE[client] or "enUS"
end

function SL:ApplyLocale()
  local choice = SL.settings and SL.settings.language or "auto"
  local code = SL:ResolveLanguage(choice)
  local strings = SL.Locales[code]
  if code ~= "enUS" and strings then
    for key, value in pairs(strings) do
      SL.L[key] = value
    end
  end
  SL.language = strings and code or "enUS"
  BINDING_HEADER_SAFELOOT = SL.L.BINDING_HEADER
  BINDING_NAME_SAFELOOT_TOGGLE = SL.L.BINDING_TOGGLE
end

-- Output ---------------------------------------------------------------------------------------------
function SL:Print(message)
  local chat = DEFAULT_CHAT_FRAME
  if chat and chat.AddMessage then
    chat:AddMessage("|cffd4a017" .. (SL.L.ADDON_NAME or "SafeLoot") .. "|r · " .. tostring(message))
  end
end

-- Lifecycle ------------------------------------------------------------------------------------------
local lifecycle = {}

function lifecycle:ADDON_LOADED(_, name)
  if name ~= ADDON then
    return
  end
  SL:UnregisterEvent("ADDON_LOADED", lifecycle)
  -- each step on its own: a damaged SavedVariables file must never leave the addon without settings
  if not safeCall("Store.Init", SL.Store.Init, SL.Store) then
    SL.Store:Fallback()
  end
  safeCall("ApplyLocale", SL.ApplyLocale, SL)
  for _, module in ipairs(moduleOrder) do
    if module.OnInitialize then
      safeCall(module.name .. ".OnInitialize", module.OnInitialize, module)
    end
  end
end

function lifecycle:PLAYER_LOGIN()
  for _, module in ipairs(moduleOrder) do
    if module.OnEnable then
      safeCall(module.name .. ".OnEnable", module.OnEnable, module)
    end
  end
  SL.enabled = true
  SL:Fire("ENABLED")
end

function lifecycle:PLAYER_REGEN_ENABLED()
  local queued = afterCombat
  afterCombat = {}
  for key, fn in pairs(queued) do
    safeCall(key, fn)
  end
  SL:Fire("COMBAT_ENDED")
end

SL:RegisterEvent("ADDON_LOADED", lifecycle, lifecycle.ADDON_LOADED)
SL:RegisterEvent("PLAYER_LOGIN", lifecycle, lifecycle.PLAYER_LOGIN)
SL:RegisterEvent("PLAYER_REGEN_ENABLED", lifecycle, lifecycle.PLAYER_REGEN_ENABLED)

-- Slash command --------------------------------------------------------------------------------------
local commands = {}

-- word: English command; aliases: other spellings (e.g. Spanish) that do the same and are not listed in help.
function SL:RegisterCommand(word, fn, help, aliases)
  commands[word] = { fn = fn, help = help }
  for _, alias in ipairs(aliases or {}) do
    commands[alias] = { fn = fn, help = help, alias = true }
  end
end

function SL:HandleSlash(input)
  input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local word, rest = input:match("^(%S+)%s*(.-)$")
  word = word and word:lower() or ""
  local command = commands[word]
  if command then
    safeCall("/safeloot " .. word, command.fn, rest)
  elseif word == "" then
    if SL.MainFrame then
      SL.MainFrame:Toggle()
    end
  else
    SL:Print(SL.L.HELP_HEADER or "Commands:")
    local names = {}
    for name, info in pairs(commands) do
      if not info.alias then
        names[#names + 1] = name
      end
    end
    table.sort(names)
    for _, name in ipairs(names) do
      SL:Print("/safeloot " .. name .. " — " .. (commands[name].help or ""))
    end
  end
end

SLASH_SAFELOOT1 = "/safeloot"
SLASH_SAFELOOT2 = "/sl"
SlashCmdList.SAFELOOT = function(input)
  SL:HandleSlash(input)
end

SL:RegisterCommand("debug", function()
  SL.debug = not SL.debug
  SL:Print("debug " .. (SL.debug and "ON" or "OFF"))
end, "debug mode")

-- Globals required by the TOC (addon compartment) and Bindings.xml.
function SafeLoot_Toggle()
  if SL.MainFrame then
    SL.MainFrame:Toggle()
  end
end

function SafeLoot_OnAddonCompartmentClick(_, button)
  if button == "RightButton" and SL.SettingsPanel then
    SL.SettingsPanel:Open()
  else
    SafeLoot_Toggle()
  end
end

function SafeLoot_OnAddonCompartmentEnter(_, menuButton)
  if not GameTooltip then
    return
  end
  GameTooltip:SetOwner(menuButton or UIParent, "ANCHOR_LEFT")
  GameTooltip:SetText(SL.L.ADDON_NAME or "SafeLoot", 1, 0.82, 0)
  GameTooltip:AddLine(SL.L.COMPARTMENT_LEFT or "Left click: open", 1, 1, 1)
  GameTooltip:AddLine(SL.L.COMPARTMENT_RIGHT or "Right click: settings", 1, 1, 1)
  GameTooltip:Show()
end

function SafeLoot_OnAddonCompartmentLeave()
  if GameTooltip then
    GameTooltip:Hide()
  end
end
