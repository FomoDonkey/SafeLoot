-- Alarms and notices (docs/PROMPT_MAESTRO.md §4.1, §7):
--   * Alert:Alarm{...}  native centre warning (RaidWarning frame) + RAID_WARNING sound + optional voice, and an
--     action panel that never closes on its own. During combat only the warning is shown; the panel waits.
--   * Alert:Toast{...}  a small card for marks and memory notices; it stays while the mouse is over it.
-- Frames are built once outside combat and only shown/updated afterwards.
local _, SL = ...
local Alert = SL:NewModule("Alert")
SL.Alert = Alert
local UI, T, L = SL.UI, SL.Theme, SL.L

local PANEL_W, PANEL_H = 420, 150
local TOAST_W, TOAST_H = 320, 86

local function buildPanel()
  local panel = UI.Card(UIParent, PANEL_W, PANEL_H, "SafeLootAlarmPanel")
  panel:SetFrameStrata("DIALOG")
  panel:Hide()
  UI.Movable(panel, "alarm", { "TOP", UIParent, "TOP", 0, -190 })

  panel.Icon = UI.Icon(panel, 36, T.tex.alert, "OVERLAY")
  panel.Icon:SetPoint("TOPLEFT", 18, -18)
  panel.Title = UI.Text(panel, "alert", "", "LEFT")
  panel.Title:SetPoint("TOPLEFT", panel.Icon, "TOPRIGHT", 10, -2)
  panel.Title:SetPoint("RIGHT", -36, 0)
  panel.Body = UI.Text(panel, "body", "", "LEFT")
  panel.Body:SetPoint("TOPLEFT", panel.Title, "BOTTOMLEFT", 0, -6)
  panel.Body:SetPoint("RIGHT", -20, 0)
  panel.Body:SetSpacing(2)

  local close = UI.Create("Button", panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function()
    Alert:HidePanel()
  end)

  panel.buttons = {}
  for i = 1, 3 do
    local button = UI.Button(panel, "", 124, function(self)
      if self.action then
        self.action()
      end
      if not self.keepOpen then
        Alert:HidePanel()
      end
    end)
    button:SetPoint("BOTTOMLEFT", 18 + (i - 1) * 130, 16)
    button:Hide()
    panel.buttons[i] = button
  end

  -- Escape closes it like any game window. (No keyboard capture: SetPropagateKeyboardInput is restricted in
  -- combat on modern clients, and a blocked action would show the game's "interface action failed" error.)
  if UISpecialFrames then
    table.insert(UISpecialFrames, "SafeLootAlarmPanel")
  end
  return panel
end

local function buildToast()
  local toast = UI.Card(UIParent, TOAST_W, TOAST_H, "SafeLootToast")
  toast:SetFrameStrata("HIGH")
  toast:Hide()
  UI.Movable(toast, "toast", { "RIGHT", UIParent, "RIGHT", -40, 120 })
  toast.Icon = UI.Icon(toast, 24, T.tex.alert, "OVERLAY")
  toast.Icon:SetPoint("TOPLEFT", 16, -16)
  toast.Title = UI.Text(toast, "header", "", "LEFT")
  toast.Title:SetPoint("TOPLEFT", toast.Icon, "TOPRIGHT", 8, -2)
  toast.Title:SetPoint("RIGHT", -16, 0)
  toast.Body = UI.Text(toast, "small", "", "LEFT")
  toast.Body:SetPoint("TOPLEFT", toast.Title, "BOTTOMLEFT", 0, -4)
  toast.Body:SetPoint("RIGHT", -16, 0)
  toast.Action = UI.Button(toast, "", 120, function(self)
    if self.action then
      self.action()
    end
    toast:Hide()
  end)
  toast.Action:SetPoint("BOTTOMRIGHT", -14, 12)
  toast.Action:Hide()
  toast.Action2 = UI.Button(toast, "", 110, function(self)
    if self.action then
      self.action()
    end
    toast:Hide()
  end)
  toast.Action2:SetPoint("RIGHT", toast.Action, "LEFT", -6, 0)
  toast.Action2:Hide()
  toast:SetScript("OnUpdate", function(self, elapsed)
    if self:IsMouseOver() then
      return
    end
    self.remaining = (self.remaining or 0) - elapsed
    if self.remaining <= 0 then
      self:Hide()
    end
  end)
  toast:SetScript("OnHide", function()
    Alert:NextToast()
  end)
  return toast
end

function Alert:OnInitialize()
  self.panel = buildPanel()
  self.toast = buildToast()
end

-- spec = { severity = 1..3, title, body, voice, actions = { {label, fn, keepOpen}, ... } }
function Alert:Alarm(spec)
  local s = SL.settings or {}
  local color = spec.severity == 3 and T.color.red or (spec.severity == 2 and T.color.orange or T.color.gold)
  if s.alarmCenter ~= false then
    local ok = SL.API.CenterWarning(spec.title, color, 8)
    if SL.Diagnostics then
      SL.Diagnostics:Observe("center_warning", { ok = ok })
    end
  end
  if s.alarmSound ~= false and (spec.severity or 0) >= 2 then
    T.Play("alarm")
  end
  if s.alarmVoice and spec.voice then
    SL.API.Speak(spec.voice)
  end
  SL:Print(T.Paint(spec.title, color) .. (spec.body and (" — " .. spec.body) or ""))
  if s.alarmPanel ~= false then
    if SL:InCombat() and not s.panelInCombat then
      SL:AfterCombat("alarm-panel", function()
        Alert:ShowPanel(spec)
      end)
    else
      self:ShowPanel(spec)
    end
  end
end

function Alert:ShowPanel(spec)
  local panel = self.panel
  if not panel then
    return
  end
  panel.Icon:SetTexture(spec.severity == 3 and T.tex.bad or T.tex.alert)
  panel.Title:SetText(spec.title or "")
  panel.Body:SetText(spec.body or "")
  local height = 70 + (panel.Title:GetStringHeight() or 20) + (panel.Body:GetStringHeight() or 20)
  panel:SetHeight(math.max(PANEL_H, height + 40))
  for i, button in ipairs(panel.buttons) do
    local action = spec.actions and spec.actions[i]
    if action then
      button:SetText(action.label)
      button.action = action.fn
      button.keepOpen = action.keepOpen
      button:Show()
    else
      button:Hide()
    end
  end
  UI.FadeIn(panel)
end

function Alert:HidePanel()
  if self.panel then
    self.panel:Hide()
  end
end

-- spec = { tone = "bad"|"warn"|"good"|"neutral", title, body, seconds, action = {label, fn} }
-- While a toast is on screen, new ones wait in a short queue (max 4) instead of replacing it.
function Alert:Toast(spec)
  local toast = self.toast
  if not toast then
    return
  end
  if toast:IsShown() and (toast.remaining or 0) > 1 then
    self.queue = self.queue or {}
    if #self.queue < 4 then
      table.insert(self.queue, spec)
    end
    return
  end
  self:ShowToast(spec)
end

function Alert:NextToast()
  local spec = self.queue and table.remove(self.queue, 1)
  if spec then
    self:ShowToast(spec)
  end
end

function Alert:ShowToast(spec)
  local toast = self.toast
  local info = T.tone[spec.tone] or T.tone.neutral
  toast.Icon:SetTexture(info.icon)
  toast.Title:SetText(spec.title or "")
  toast.Body:SetText(spec.body or "")
  if spec.action then
    toast.Action:SetText(spec.action.label)
    toast.Action.action = spec.action.fn
    toast.Action:Show()
    toast:SetHeight(TOAST_H + 22)
  else
    toast.Action:Hide()
    toast:SetHeight(TOAST_H)
  end
  if spec.action and spec.action2 then
    toast.Action2:SetText(spec.action2.label)
    toast.Action2.action = spec.action2.fn
    toast.Action2:Show()
  else
    toast.Action2:Hide()
  end
  toast.remaining = spec.seconds or 12
  T.Play("toast")
  UI.FadeIn(toast)
end
