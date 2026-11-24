-- Phase 0 (docs/PROMPT_MAESTRO.md §9.4). Two parts:
--   1. Diagnostics:Observe(key, detail): every module reports what it actually sees in the live game (events
--      fired, values secret or not, in combat or in an instance). Stored in SafeLootDB.diagnostics.observed,
--      so the developer can read the real client's behaviour from SavedVariables after a session.
--   2. /safeloot test: an immediate capability check (APIs, templates, addon message echo) shown in a window and
--      saved to SafeLootDB.diagnostics.report.
local _, SL = ...
local D = SL:NewModule("Diagnostics")
SL.Diagnostics = D
local API, UI, T, L = SL.API, SL.UI, SL.Theme, SL.L

local function context()
  local inInstance, kind = API.InInstance()
  return {
    combat = SL:InCombat(),
    instance = inInstance and (kind or true) or false,
    group = API.InGroup() and API.GroupSize() or 0,
    chatLocked = API.ChatLocked(),
  }
end

function D:Observe(key, detail)
  local db = SL.db
  if not db then
    return
  end
  local observed = db.diagnostics.observed
  local entry = observed[key]
  if not entry then
    entry = { count = 0, first = API.Now() }
    observed[key] = entry
  end
  entry.count = entry.count + 1
  -- The full context (a few API calls) is only taken for the first 30 observations and then every 25th:
  -- enough to answer P1-P5, and nearly free on hot paths such as player tooltips.
  if entry.count > 30 and entry.count % 25 ~= 0 then
    return
  end
  entry.last = API.Now()
  entry.context = context()
  if detail ~= nil then
    entry.detail = detail
  end
  -- separate tallies inside/outside instances and combat: the answers to P1-P3
  local ctx = entry.context
  local bucket = (ctx.instance and "inInstance" or "outside") .. (ctx.combat and "_combat" or "")
  entry[bucket] = (entry[bucket] or 0) + 1
end

-- Capability checks -----------------------------------------------------------------------------------
local TEMPLATES = {
  "PortraitFrameTemplate", "ButtonFrameTemplate", "InsetFrameTemplate", "PanelTabButtonTemplate",
  "UIPanelButtonTemplate", "UIPanelCloseButton", "UICheckButtonTemplate", "SharedEditBoxTemplate",
  "WowScrollBoxList", "MinimalScrollBar", "NineSlicePanelTemplate", "BackdropTemplate", "UIPanelScrollFrameTemplate",
}

local function exists(path)
  local value = _G
  for part in path:gmatch("[^%.]+") do
    if type(value) ~= "table" then
      return false
    end
    value = value[part]
  end
  return value ~= nil
end

local FUNCTIONS = {
  "C_PartyInfo.GetLootMethod", "C_LootHistory.GetSortedInfoForDrop", "C_LootHistory.GetAllEncounterInfos",
  "C_ChatInfo.SendAddonMessage", "C_ChatInfo.RegisterAddonMessagePrefix", "C_ChatInfo.SendChatMessage",
  "C_ChatInfo.InChatMessagingLockdown", "C_LFGList.GetSearchResultInfo", "TooltipDataProcessor.AddTooltipPostCall",
  "RaidWarningUtil.AddMessage", "Settings.RegisterVerticalLayoutCategory", "Settings.RegisterAddOnSetting",
  "C_VoiceChat.SpeakText", "C_VoiceChat.GetTtsVoices", "C_Item.GetItemInfoInstant", "C_Item.GetItemInfo",
  "C_Item.GetItemStats", "C_XMLUtil.GetTemplateInfo", "issecretvalue", "UnitFullName", "GetLootThreshold",
  "IsInInstance", "GetInstanceInfo", "StaticPopup_FindVisible", "NineSliceUtil.ApplyLayoutByName",
  "ScrollUtil.InitScrollBoxListWithScrollBar", "CreateScrollBoxListLinearView", "SendChatMessage",
}

local function canRegister(event)
  local f = CreateFrame("Frame")
  local ok = pcall(f.RegisterEvent, f, event)
  if ok then
    f:UnregisterEvent(event)
  end
  return ok
end

local EVENTS = {
  "PARTY_LOOT_METHOD_CHANGED", "LOOT_HISTORY_UPDATE_DROP", "LOOT_HISTORY_UPDATE_ENCOUNTER", "PARTY_INVITE_REQUEST",
  "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_LOOT",
  "CHAT_MSG_ADDON",
}

local PREFIX = "SafeLoot"

function D:Run()
  local report = { t = API.Now(), version = SL.version, context = context(), functions = {}, templates = {}, events = {} }
  report.build, report.interface = API.GameBuild()
  for _, name in ipairs(FUNCTIONS) do
    report.functions[name] = exists(name)
  end
  for _, name in ipairs(TEMPLATES) do
    report.templates[name] = API.TemplateExists(name)
  end
  for _, name in ipairs(EVENTS) do
    report.events[name] = canRegister(name)
  end
  -- live values
  local method, looter = API.LootMethod()
  report.lootMethod = method
  report.masterLooter = looter
  report.lootThreshold = API.LootThreshold()
  report.me = SL.Names.Me()
  report.place = API.PlaceName()
  -- addon message echo: whisper ourselves (works without a group); the reply arrives in CHAT_MSG_ADDON
  local ok, result = API.SendAddon(PREFIX, "1|PING|" .. report.t, "WHISPER", report.me)
  report.addonSend = { ok = ok, result = tostring(result) }
  D.pingAt = API.Clock()
  D.pingToken = tostring(report.t)
  if API.InGroup() then
    local okGroup, resultGroup = API.SendAddon(PREFIX, "1|PING|" .. report.t, API.InRaid() and "RAID" or "PARTY")
    report.addonSendGroup = { ok = okGroup, result = tostring(resultGroup) }
  end
  -- voices for text to speech
  if C_VoiceChat and C_VoiceChat.GetTtsVoices then
    local okVoices, voices = pcall(C_VoiceChat.GetTtsVoices)
    report.ttsVoices = okVoices and type(voices) == "table" and #voices or 0
  end
  SL.db.diagnostics.report = report
  self:ShowReport(report)
  return report
end

function D:OnAddonMessage(_, prefix, message, channel, sender)
  if prefix ~= PREFIX or API.IsSecret(message) then
    return
  end
  local token = type(message) == "string" and message:match("^1|PING|(%d+)")
  if token and token == D.pingToken and SL.db.diagnostics.report then
    local report = SL.db.diagnostics.report
    report.addonEcho = report.addonEcho or {}
    report.addonEcho[channel or "?"] = { ms = math.floor((API.Clock() - (D.pingAt or 0)) * 1000), sender = sender }
    if self.window and self.window:IsShown() then
      self:ShowReport(report)
    end
  end
end

-- Report window ------------------------------------------------------------------------------------------
local function mark(ok)
  return "|T" .. (ok and T.tex.ok or T.tex.bad) .. ":14:14|t "
end

function D:ReportLines(report)
  local lines = {}
  local function add(ok, text)
    lines[#lines + 1] = mark(ok) .. text
  end
  local missingF, missingT, missingE = {}, {}, {}
  for name, ok in pairs(report.functions) do
    if not ok then missingF[#missingF + 1] = name end
  end
  for name, ok in pairs(report.templates) do
    if not ok then missingT[#missingT + 1] = name end
  end
  for name, ok in pairs(report.events) do
    if not ok then missingE[#missingE + 1] = name end
  end
  table.sort(missingF)
  table.sort(missingT)
  table.sort(missingE)
  lines[#lines + 1] = T.Paint(string.format(L.DIAG_BUILD, tostring(report.build), tostring(report.interface)), T.color.gray)
  add(#missingF == 0, string.format(L.DIAG_FUNCTIONS, #FUNCTIONS - #missingF, #FUNCTIONS)
    .. (#missingF > 0 and (" — " .. table.concat(missingF, ", ")) or ""))
  add(#missingT == 0, string.format(L.DIAG_TEMPLATES, #TEMPLATES - #missingT, #TEMPLATES)
    .. (#missingT > 0 and (" — " .. table.concat(missingT, ", ")) or ""))
  add(#missingE == 0, string.format(L.DIAG_EVENTS, #EVENTS - #missingE, #EVENTS)
    .. (#missingE > 0 and (" — " .. table.concat(missingE, ", ")) or ""))
  add(report.lootMethod ~= nil, string.format(L.DIAG_LOOTMETHOD, report.lootMethod ~= nil and (L["METHOD_" .. report.lootMethod] or tostring(report.lootMethod)) or L.DIAG_NOVALUE))
  add(report.me ~= nil and SL.Names.HasSurname(report.me), string.format(L.DIAG_NAME, tostring(report.me)))
  add(report.addonSend and report.addonSend.ok, string.format(L.DIAG_ADDON_SEND, report.addonSend and report.addonSend.result or "?"))
  local echo = report.addonEcho and (report.addonEcho.WHISPER or next(report.addonEcho) and select(2, next(report.addonEcho)))
  add(echo ~= nil, echo and string.format(L.DIAG_ADDON_ECHO, echo.ms) or L.DIAG_ADDON_WAIT)
  add((report.ttsVoices or 0) > 0, string.format(L.DIAG_TTS, report.ttsVoices or 0))
  -- what has been observed in real play so far
  local observed = SL.db.diagnostics.observed
  lines[#lines + 1] = " "
  lines[#lines + 1] = T.Paint(L.DIAG_OBSERVED, T.color.gold)
  local keys = { "loot_method_event", "loot_method_read", "loot_history_drop", "finder_row_hook", "finder_tooltip_hook",
    "unit_tooltip", "invite_event", "chat_group_secret", "chat_group_plain", "chat_loot_need", "center_warning" }
  for _, key in ipairs(keys) do
    local entry = observed[key]
    local count = entry and entry.count or 0
    local where = entry and string.format(" (%s %d · %s %d)", L.DIAG_IN_INSTANCE, entry.inInstance or 0,
      L.DIAG_OUTSIDE, entry.outside or 0) or ""
    lines[#lines + 1] = (count > 0 and mark(true) or "|T" .. T.tex.wait .. ":14:14|t ")
      .. (L["OBS_" .. key] or key) .. ": " .. count .. where
  end
  return lines
end

function D:ShowReport(report)
  if not self.window then
    local card = UI.Card(UIParent, 520, 420, "SafeLootDiagnostics")
    card:SetFrameStrata("DIALOG")
    UI.Movable(card, "diagnostics", { "CENTER", UIParent, "CENTER", 0, 40 })
    card.Title = UI.Text(card, "title", L.DIAG_TITLE, "LEFT")
    card.Title:SetPoint("TOPLEFT", 20, -20)
    card.Sub = UI.Text(card, "muted", L.DIAG_SUB, "LEFT")
    card.Sub:SetPoint("TOPLEFT", card.Title, "BOTTOMLEFT", 0, -4)
    card.Sub:SetPoint("RIGHT", -20, 0)
    card.Body = UI.Text(card, "small", "", "LEFT")
    card.Body:SetPoint("TOPLEFT", card.Sub, "BOTTOMLEFT", 0, -10)
    card.Body:SetPoint("RIGHT", -20, 0)
    card.Body:SetJustifyV("TOP")
    card.Body:SetSpacing(3)
    local close = UI.Create("Button", card, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    local again = UI.Button(card, L.DIAG_AGAIN, 130, function()
      D:Run()
    end)
    again:SetPoint("BOTTOMLEFT", 18, 16)
    local ok = UI.Button(card, OKAY or "OK", 90, function()
      card:Hide()
    end)
    ok:SetPoint("BOTTOMRIGHT", -18, 16)
    if UISpecialFrames then
      table.insert(UISpecialFrames, "SafeLootDiagnostics")
    end
    self.window = card
  end
  self.window.Body:SetText(table.concat(self:ReportLines(report), "\n"))
  self.window:SetHeight(math.max(260, (self.window.Body:GetStringHeight() or 200) + 120))
  self.window:Show()
end

function D:OnEnable()
  API.RegisterPrefix(PREFIX)
  SL:RegisterEvent("CHAT_MSG_ADDON", self, self.OnAddonMessage)
  SL:RegisterCommand("test", function()
    D:Run()
  end, L.CMD_TEST, { "prueba" })
end
