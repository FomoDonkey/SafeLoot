-- Minimal simulation of the WoW: Forever client API used by SafeLoot. Not a full emulator: enough to load
-- every file, fire events and observe what the addon does (alarms, chat lines, toasts, memory).
-- SIM holds the scenario state and records every observable output.
SIM = {
  locale = "esES",
  inGroup = false, inRaid = false, inInstance = false, instanceType = "none", combat = false,
  lootMethod = 3, masterPartyID = nil, leaderUnit = "party1", groupSize = 1,
  units = { player = { first = "Ana", second = "Paciente", class = "PRIEST" } },
  secrets = {},             -- values that issecretvalue() reports as secret
  sent = {},                -- chat lines sent { text, chatType }
  addonSent = {},           -- addon messages
  warnings = {},            -- centre warnings
  sounds = {},              -- PlaySound kits
  spoken = {},              -- text to speech
  timers = {},
  lootDrops = {},           -- [encounterID..":"..key] = EncounterLootDropInfo
  items = {},               -- [link] = { itemID, equipLoc, classID, subClassID, name, quality, bindType, stats }
  now = 1800000000,
  frames = {},
  hooks = {},
  tooltipPostCalls = {},
  settingsRegistered = {},
}

local function noop() end

-- Generic widget ---------------------------------------------------------------------------------------------
local Widget = {}
-- Unknown METHODS (verb-named: SetFoo, GetBar, EnableMouse...) are accepted and do nothing. Unknown FIELDS
-- (Text, Icon, fadeIn...) are nil, exactly like the real client, so "if not frame.Text then create it" works.
local VERBS = { "Set", "Get", "Is", "Has", "Enable", "Disable", "Register", "Unregister", "Start", "Stop", "Clear",
  "Highlight", "Hook", "Play", "Add", "Create", "Lock", "Unlock", "Raise", "Lower", "Apply", "Insert" }
Widget.__index = function(self, key)
  local method = Widget[key]
  if method ~= nil then
    return method
  end
  if type(key) == "string" then
    for _, verb in ipairs(VERBS) do
      if key:sub(1, #verb) == verb and (#key == #verb or key:sub(#verb + 1, #verb + 1):match("%u")) then
        return noop
      end
    end
  end
  return nil
end

local function newWidget(kind, name, parent)
  local w = setmetatable({ _kind = kind, _name = name, _parent = parent, _shown = kind ~= "Frame" or true,
    _scripts = {}, _text = "", _points = {}, _checked = false, _alpha = 1, _width = 100, _height = 20 }, Widget)
  w._shown = true
  table.insert(SIM.frames, w)
  if name then
    _G[name] = w
  end
  return w
end
SIM.newWidget = newWidget

function Widget:SetScript(event, fn) self._scripts[event] = fn end
function Widget:GetScript(event) return self._scripts[event] end
function Widget:HookScript(event, fn)
  local old = self._scripts[event]
  self._scripts[event] = function(...)
    if old then old(...) end
    fn(...)
  end
end
function Widget:Fire(event, ...)
  local fn = self._scripts[event]
  if fn then return fn(self, ...) end
end
function Widget:Show() self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end end
function Widget:Hide() local was = self._shown; self._shown = false; if was and self._scripts.OnHide then self._scripts.OnHide(self) end end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self._shown end
function Widget:IsVisible() return self._shown end
function Widget:SetText(t) self._text = t end
function Widget:GetText() return self._text end
function Widget:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
function Widget:GetStringHeight() return 14 end
function Widget:GetStringWidth() return 80 end
function Widget:GetWidth() return self._width end
function Widget:GetHeight() return self._height end
function Widget:SetSize(w, h) self._width, self._height = w, h end
function Widget:SetWidth(w) self._width = w end
function Widget:SetHeight(h) self._height = h end
function Widget:SetChecked(v) self._checked = v and true or false end
function Widget:GetChecked() return self._checked end
function Widget:SetAlpha(a) self._alpha = a end
function Widget:GetAlpha() return self._alpha end
function Widget:SetPoint(...) table.insert(self._points, { ... }) end
function Widget:ClearAllPoints() self._points = {} end
function Widget:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Widget:GetFrameLevel() return 1 end
function Widget:GetParent() return self._parent end
function Widget:GetName() return self._name end
function Widget:IsMouseOver() return false end
function Widget:HasFocus() return false end
function Widget:GetID() return self._id or 0 end
function Widget:SetID(id) self._id = id end
function Widget:Click() if self._scripts.OnClick then self._scripts.OnClick(self, "LeftButton") end end
function Widget:CreateFontString() return newWidget("FontString", nil, self) end
function Widget:CreateTexture() return newWidget("Texture", nil, self) end
function Widget:CreateAnimationGroup() return newWidget("AnimationGroup", nil, self) end
function Widget:CreateAnimation() return newWidget("Animation", nil, self) end
function Widget:RegisterEvent(event)
  if SIM.unknownEvents and SIM.unknownEvents[event] then
    error("Attempt to register unknown event " .. event)
  end
  self._events = self._events or {}
  self._events[event] = true
  SIM.eventFrames = SIM.eventFrames or {}
  SIM.eventFrames[self] = true
end
function Widget:UnregisterEvent(event) if self._events then self._events[event] = nil end end
function Widget:SetTitle(t) self._title = t end
function Widget:Enable() self._enabled = true end
function Widget:Disable() self._enabled = false end
function Widget:Play() end

function CreateFrame(kind, name, parent, template)
  if template and SIM.missingTemplates and SIM.missingTemplates[template] then
    error("missing template " .. template)
  end
  local w = newWidget(kind, name, parent)
  w._template = template
  if template == "UICheckButtonTemplate" then
    w.Text = newWidget("FontString", nil, w)
  end
  if template == "PanelTabButtonTemplate" and parent then
    parent.Tabs = parent.Tabs or {}
    table.insert(parent.Tabs, w)
  end
  return w
end

UIParent = newWidget("Frame", "UIParent")
DEFAULT_CHAT_FRAME = newWidget("Frame", "DEFAULT_CHAT_FRAME")
SIM.chatOutput = {}
function DEFAULT_CHAT_FRAME:AddMessage(text) table.insert(SIM.chatOutput, text) end
GameTooltip = newWidget("GameTooltip", "GameTooltip")
GameTooltip._lines = {}
function GameTooltip:AddLine(text) table.insert(self._lines, text) end
function GameTooltip:GetUnit() return SIM.tooltipUnitName, SIM.tooltipUnit end
UISpecialFrames = {}
SlashCmdList = {}

-- Fire a game event to every frame registered for it.
function SIM.Fire(event, ...)
  for frame in pairs(SIM.eventFrames or {}) do
    if frame._events and frame._events[event] and frame._scripts.OnEvent then
      frame._scripts.OnEvent(frame, event, ...)
    end
  end
end

function SIM.RunTimers()
  local timers = SIM.timers
  SIM.timers = {}
  for _, fn in ipairs(timers) do fn() end
end

-- Environment ------------------------------------------------------------------------------------------------
function GetLocale() return SIM.locale end
function time() return SIM.now end
function date(fmt, t) return os.date(fmt, t or SIM.now) end
function GetTime() return SIM.now end
function debugstack() return "" end
function GetBuildInfo() return "1.60.1", "71037", "Nov 20 2026", 16001 end
function issecretvalue(v) return SIM.secrets[v] == true end
function InCombatLockdown() return SIM.combat end
function GetNormalizedRealmName() return "" end
function PlaySound(kit) table.insert(SIM.sounds, kit) end
function hooksecurefunc(a, b, c)
  if type(a) == "string" then SIM.hooks[a] = b else SIM.hooks[b] = c end
end
function IsInGroup() return SIM.inGroup end
function IsInRaid() return SIM.inRaid end
function GetNumGroupMembers() return SIM.inGroup and SIM.groupSize or 0 end
function IsInInstance() return SIM.inInstance, SIM.instanceType end
function GetInstanceInfo() return SIM.inInstance and "Cumbre de Roca Negra" or "Ventormenta" end
function GetRealZoneText() return "Ventormenta" end
function UnitExists(unit) return SIM.units[unit] ~= nil end
function UnitFullName(unit)
  local u = SIM.units[unit]
  if not u then return nil end
  return u.first, u.second
end
function UnitName(unit) local u = SIM.units[unit]; return u and u.first or nil end
function UnitClass(unit) local u = SIM.units[unit]; if not u then return nil end return u.class, u.class end
function UnitIsGroupLeader(unit) return unit == SIM.leaderUnit end
function UnitIsPlayer(unit) return SIM.units[unit] ~= nil end
LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mago", PRIEST = "Sacerdote", WARRIOR = "Guerrero", ROGUE = "Pícaro" }
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92, colorStr = "ff3fc7eb" } }

C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return "0.1.0-test" end end }
C_Timer = { After = function(_, fn) table.insert(SIM.timers, fn) end }
C_PartyInfo = {
  GetLootMethod = function()
    if SIM.lootMethodSecret then return SIM.secretToken end
    return SIM.lootMethod, SIM.masterPartyID, nil
  end,
}
C_LootHistory = {
  GetSortedInfoForDrop = function(encounterID, key) return SIM.lootDrops[tostring(encounterID) .. ":" .. tostring(key)] end,
}
C_Item = {
  GetItemInfoInstant = function(link)
    local i = SIM.items[link]
    if not i then return nil end
    return i.itemID, "", "", i.equipLoc, 0, i.classID, i.subClassID
  end,
  GetItemInfo = function(link)
    local i = SIM.items[link]
    if not i then return nil end
    return i.name, link, i.quality, 60, 55, "", "", 1, i.equipLoc, 0, 0, i.classID, i.subClassID, i.bindType
  end,
  GetItemStats = function(link) local i = SIM.items[link]; return i and i.stats or nil end,
}
C_ChatInfo = {
  SendChatMessage = function(text, chatType) table.insert(SIM.sent, { text = text, chatType = chatType }) end,
  SendAddonMessage = function(prefix, message, chatType, target)
    table.insert(SIM.addonSent, { prefix = prefix, message = message, chatType = chatType, target = target })
    return 0
  end,
  RegisterAddonMessagePrefix = function() return 0 end,
  InChatMessagingLockdown = function() return false end,
}
C_LFGList = { GetSearchResultInfo = function(id) return SIM.lfgResults and SIM.lfgResults[id] end }
C_XMLUtil = { GetTemplateInfo = function(t) if SIM.missingTemplates and SIM.missingTemplates[t] then return nil end return {} end }
C_VoiceChat = {
  GetTtsVoices = function() return { { voiceID = 1, name = "Test" } } end,
  SpeakText = function(voiceID, text) table.insert(SIM.spoken, text) end,
}
C_ClassColor = { GetClassColor = function(c) return RAID_CLASS_COLORS[c] end }
RaidWarningUtil = { AddMessage = function(text, color, seconds) table.insert(SIM.warnings, text) end }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) table.insert(SIM.tooltipPostCalls, { kind = kind, fn = fn }) end }
NineSliceUtil = { ApplyLayoutByName = noop }
Enum = {
  TooltipDataType = { Item = 0, Spell = 1, Unit = 2 },
  LootMethod = { Freeforall = 0, Roundrobin = 1, Masterlooter = 2, Group = 3, Needbeforegreed = 4, Personal = 5 },
}
SOUNDKIT = { RAID_WARNING = 8959, READY_CHECK = 8960, IG_MAINMENU_OPEN = 850, IG_MAINMENU_CLOSE = 851,
  IG_CHARACTER_INFO_TAB = 841, IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857, TELL_MESSAGE = 3081 }
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
GameFontNormal, GameFontHighlight, GameFontNormalLarge, GameFontHighlightSmall, GameFontDisableSmall = {}, {}, {}, {}, {}
OKAY, CLOSE, ADD = "Aceptar", "Cerrar", "Añadir"

-- ScrollBox / data provider
function CreateScrollBoxListLinearView()
  local view = {}
  function view:SetElementExtent() end
  function view:SetElementInitializer(_, fn) self.init = fn end
  SIM.lastView = view
  return view
end
ScrollUtil = { InitScrollBoxListWithScrollBar = function(box, bar, view) box._view = view end }
function CreateDataProvider()
  local p = { items = {} }
  function p:Flush() self.items = {} end
  function p:Insert(item) table.insert(self.items, item) end
  return p
end
function PanelTemplates_SetNumTabs() end
function PanelTemplates_SetTab(frame, id) frame._selectedTab = id end
function PanelTemplates_TabResize() end

-- Settings API
Settings = {
  VarType = { Boolean = "boolean", Number = "number" },
  RegisterVerticalLayoutCategory = function(name)
    local layout = { inits = {} }
    function layout:AddInitializer(i) table.insert(self.inits, i) end
    local category = { name = name, ID = 77 }
    function category:GetID() return self.ID end
    return category, layout
  end,
  RegisterAddOnSetting = function(category, variable, key, tbl, varType, name, default)
    local setting = { variable = variable, key = key, tbl = tbl, default = default }
    function setting:SetValueChangedCallback(fn) self.cb = fn end
    SIM.settingsRegistered[key] = setting
    return setting
  end,
  CreateCheckbox = noop,
  CreateSlider = noop,
  CreateSliderOptions = function() return { SetLabelFormatter = noop } end,
  RegisterAddOnCategory = function(c) SIM.settingsCategory = c end,
  OpenToCategory = function(id) SIM.openedSettings = id end,
}
Settings.CreateDropdown = function(category, setting, options) SIM.languageOptions = options() end
Settings.CreateControlTextContainer = function()
  local c = { data = {} }
  function c:Add(value, label) table.insert(self.data, { value = value, label = label }) end
  function c:GetData() return self.data end
  return c
end
C_UI = { Reload = function() SIM.reloaded = true end }
-- Group Finder functions (Blizzard_GroupFinder_VanillaStyle) so the addon can hook them
function LFGBrowseSearchEntry_Update() end
function LFGBrowseSearchEntryTooltip_UpdateAndShow() end
function ChatEdit_InsertLink() end
function CreateSettingsListSectionHeaderInitializer(t) return { header = t } end
function CreateSettingsButtonInitializer(name, text, fn) return { button = name, fn = fn } end
