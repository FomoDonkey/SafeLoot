-- Options > AddOns > SafeLoot, with the game's own Settings API (verified in Blizzard_Settings_Shared for
-- Forever). Also the demo commands that let the player SEE every screen without waiting for a real run.
local _, SL = ...
local SP = SL:NewModule("SettingsPanel")
SL.SettingsPanel = SP
local API, UI, T, L = SL.API, SL.UI, SL.Theme, SL.L

local BOOL = (Settings and Settings.VarType and Settings.VarType.Boolean) or "boolean"
local NUMBER = (Settings and Settings.VarType and Settings.VarType.Number) or "number"
local STRING = (Settings and Settings.VarType and Settings.VarType.String) or "string"

local OPTIONS = {
  { section = "SECTION_GENERAL" },
  { key = "language", kind = "language" },
  { key = "showIndicator" },
  { section = "SECTION_ALARM" },
  { key = "alarmCenter" }, { key = "alarmSound" }, { key = "alarmVoice" }, { key = "alarmPanel" }, { key = "panelInCombat" },
  { section = "SECTION_DETECT" },
  { key = "detector" }, { key = "suggestRules" }, { key = "summaryAlways" }, { key = "shareLoot" },
  { section = "SECTION_MEMORY" },
  { key = "memory" }, { key = "showTooltip" }, { key = "showFinder" }, { key = "showInvite" }, { key = "showGroupJoin" },
  { key = "memoryDays", min = 30, max = 365, step = 15 },
  { section = "SECTION_ACCESS" },
  { key = "largeText" }, { key = "reduceMotion" }, { key = "sounds" },
  { key = "scale", min = 0.8, max = 1.3, step = 0.05 },
}

local function onChanged(key, value)
  if key == "largeText" then
    UI.RefreshFonts()
  elseif key == "scale" and SL.MainFrame and SL.MainFrame.frame then
    SL.MainFrame.frame:SetScale(value)
  end
  SL:Fire("SETTING_CHANGED", key, value)
end

function SP:OnInitialize()
  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting
    and Settings.RegisterAddOnCategory) then
    SL:ReportError("Settings", "Settings API missing")
    return
  end
  local category, layout = Settings.RegisterVerticalLayoutCategory(L.ADDON_NAME)
  if not layout and SettingsPanel and SettingsPanel.GetLayout then
    layout = SettingsPanel:GetLayout(category)
  end
  for _, option in ipairs(OPTIONS) do
    if option.section then
      if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L[option.section]))
      end
    elseif option.kind == "language" then
      SP:AddLanguage(category)
    else
      local key = option.key
      local default = SL.settings[key]
      local name = L["OPT_" .. key] or key
      local tooltip = L["OPT_" .. key .. "_TIP"]
      local isNumber = type(default) == "number"
      local ok, setting = pcall(Settings.RegisterAddOnSetting, category, "SafeLoot_" .. key, key, SL.settings,
        isNumber and NUMBER or BOOL, name, default)
      if ok and setting then
        if isNumber and Settings.CreateSliderOptions and Settings.CreateSlider then
          local options = Settings.CreateSliderOptions(option.min, option.max, option.step)
          if options.SetLabelFormatter and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
              if key == "scale" then
                return string.format("%d%%", value * 100 + 0.5)
              end
              return string.format(L.DAYS, value)
            end)
          end
          Settings.CreateSlider(category, setting, options, tooltip)
        elseif Settings.CreateCheckbox then
          Settings.CreateCheckbox(category, setting, tooltip)
        end
        if setting.SetValueChangedCallback then
          setting:SetValueChangedCallback(function(_, value)
            onChanged(key, value)
          end)
        elseif Settings.SetOnValueChangedCallback then
          Settings.SetOnValueChangedCallback("SafeLoot_" .. key, function(_, _, value)
            onChanged(key, value)
          end)
        end
      else
        SL:ReportError("Settings", "could not register " .. key)
      end
    end
  end
  if layout and CreateSettingsButtonInitializer then
    layout:AddInitializer(CreateSettingsButtonInitializer(L.DEMO_ALARM, L.DEMO_BUTTON, function()
      SP:DemoAlarm()
    end, L.DEMO_ALARM_TIP, true))
    layout:AddInitializer(CreateSettingsButtonInitializer(L.DIAG_TITLE, L.DIAG_BUTTON, function()
      SL.Diagnostics:Run()
    end, L.DIAG_SUB, true))
    layout:AddInitializer(CreateSettingsButtonInitializer(L.RESET_EXCEPTIONS, L.RESET_BUTTON, function()
      SL.LootWatch:ResetExceptions()
    end, L.RESET_EXCEPTIONS_TIP, true))
  end
  Settings.RegisterAddOnCategory(category)
  self.category = category
end

-- Language dropdown (Automatic + the five languages); a change asks to reload.
function SP:AddLanguage(category)
  if not (Settings.CreateDropdown and Settings.CreateControlTextContainer) then
    return
  end
  local ok, setting = pcall(Settings.RegisterAddOnSetting, category, "SafeLoot_language", "language", SL.settings,
    STRING, L.OPT_language, "auto")
  if not ok or not setting then
    SL:ReportError("Settings", "could not register language")
    return
  end
  local function options()
    local container = Settings.CreateControlTextContainer()
    container:Add("auto", L.LANG_auto)
    for _, code in ipairs(SL.LANGUAGES) do
      container:Add(code, L["LANG_" .. code])
    end
    return container:GetData()
  end
  Settings.CreateDropdown(category, setting, options, L.OPT_language_TIP)
  local function changed()
    if SL:ResolveLanguage(SL.settings.language) ~= SL.language then
      SP:AskReload()
    end
  end
  if setting.SetValueChangedCallback then
    setting:SetValueChangedCallback(changed)
  elseif Settings.SetOnValueChangedCallback then
    Settings.SetOnValueChangedCallback("SafeLoot_language", changed)
  end
end

function SP:AskReload()
  if not self.reload then
    local card = UI.Card(UIParent, 360, 130, "SafeLootReload")
    card:SetFrameStrata("FULLSCREEN_DIALOG")
    card:SetPoint("CENTER", 0, 120)
    local title = UI.Text(card, "header", L.RELOAD_TITLE, "LEFT")
    title:SetPoint("TOPLEFT", 20, -18)
    local body = UI.Text(card, "small", L.RELOAD_BODY, "LEFT")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    body:SetPoint("RIGHT", -20, 0)
    local now = UI.Button(card, L.RELOAD_NOW, 140, function()
      local reload = (C_UI and C_UI.Reload) or ReloadUI
      if reload then
        reload()
      end
    end)
    now:SetPoint("BOTTOMLEFT", 18, 16)
    local later = UI.Button(card, L.RELOAD_LATER, 110, function()
      card:Hide()
    end)
    later:SetPoint("BOTTOMRIGHT", -18, 16)
    self.reload = card
  end
  self.reload:Show()
end

function SP:Open()
  if self.category and Settings and Settings.OpenToCategory then
    local id = self.category.GetID and self.category:GetID() or self.category.ID
    pcall(Settings.OpenToCategory, id)
  end
end

-- Demos: see the screens without waiting for a real run ------------------------------------------------------
function SP:DemoAlarm()
  SL.Alert:Alarm({
    severity = 3,
    title = L.ALARM_ML_TITLE,
    body = string.format(L.ALARM_ML_BODY, date and date("%H:%M") or "", "Krag Hierro", L.METHOD_3) .. "\n" .. T.Paint(L.DEMO_NOTE, T.color.gray),
    voice = L.VOICE_ML,
    actions = {
      { label = L.ACTION_ASK, fn = function() SL:Print(L.DEMO_NOTHING_SENT) end },
      { label = L.ACTION_SAVE, fn = function() SL:Print(L.DEMO_NOTHING_SENT) end },
      { label = L.ACTION_OK, fn = function() end },
    },
  })
end

function SP:DemoMark()
  SL.Alert:Toast({
    tone = "bad",
    title = L.MARK_IMPOSSIBLE,
    body = string.format(L.MARK_LINE, "Zarn Brasa", "[Coraza de malla]", string.format(L.REASON_CLASS_ARMOR, API.LocalizedClass("MAGE") or "Mage")),
    seconds = 15,
    action = { label = L.ACTION_TELL_GROUP, fn = function() SL:Print(L.DEMO_NOTHING_SENT) end },
  })
end

function SP:DemoSummary()
  SL.Run:ShowSummary({
    place = "Cumbre de Roca Negra", startedAt = API.Now() - 3600,
    events = {
      { kind = "contract", t = API.Now() - 3500, text = T.Paint(L.CONTRACT_PUBLISHED, T.color.gold) .. " " .. L.METHOD_3 .. " · " .. L.NEED_msos },
      { kind = "agreed", t = API.Now() - 3490, text = string.format(L.CONTRACT_AGREED, "Krag Hierro", "21:04") },
      { kind = "mark", t = API.Now() - 1800, text = "|T" .. T.tex.bad .. ":14:14|t " .. string.format(L.MARK_LINE, "Zarn Brasa", "[Coraza de malla]", string.format(L.REASON_CLASS_ARMOR, API.LocalizedClass("MAGE") or "Mage")) },
      { kind = "rules_changed", t = API.Now() - 600, severity = 3, text = T.Paint(L.ALARM_ML_TITLE, T.color.red) },
    },
    drops = { a = { item = "[Mano de Dal'Rend]", winner = "Krag Hierro" } },
  })
end

function SP:OnEnable()
  SL:RegisterCommand("alarm", function() SP:DemoAlarm() end, L.CMD_DEMO_ALARM, { "alarma" })
  SL:RegisterCommand("mark", function() SP:DemoMark() end, L.CMD_DEMO_MARK, { "marca" })
  SL:RegisterCommand("summary", function() SP:DemoSummary() end, L.CMD_DEMO_SUMMARY, { "resumen" })
  SL:RegisterCommand("settings", function() SP:Open() end, L.CMD_SETTINGS, { "ajustes", "options" })
end
