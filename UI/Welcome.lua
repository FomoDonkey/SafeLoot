-- First-use card (docs/PROMPT_MAESTRO.md §5.1): three steps, one line each, shown once a few seconds after the
-- first login (never in combat). /safeloot welcome shows it again.
local _, SL = ...
local W = SL:NewModule("Welcome")
SL.Welcome = W
local UI, T, L = SL.UI, SL.Theme, SL.L

local STEPS = {
  { icon = T.tex.alert, title = "WELCOME_1_TITLE", body = "WELCOME_1_BODY" },
  { icon = T.tex.bad, title = "WELCOME_2_TITLE", body = "WELCOME_2_BODY" },
  { icon = T.tex.ok, title = "WELCOME_3_TITLE", body = "WELCOME_3_BODY" },
}

function W:Build()
  local card = UI.Card(UIParent, 440, 300, "SafeLootWelcome")
  card:SetFrameStrata("DIALOG")
  card:SetPoint("CENTER", 0, 60)
  local portrait = UI.Icon(card, 40, T.tex.portrait, "OVERLAY")
  portrait:SetPoint("TOPLEFT", 20, -20)
  local title = UI.Text(card, "title", L.WELCOME_TITLE, "LEFT")
  title:SetPoint("LEFT", portrait, "RIGHT", 12, 0)
  title:SetPoint("RIGHT", -36, 0)
  local close = UI.Create("Button", card, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)
  local anchor = portrait
  for i, step in ipairs(STEPS) do
    local icon = UI.Icon(card, 24, step.icon, "OVERLAY")
    icon:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", i == 1 and 8 or 0, i == 1 and -18 or -22)
    local head = UI.Text(card, "header", L[step.title], "LEFT")
    head:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 2)
    head:SetPoint("RIGHT", -24, 0)
    local body = UI.Text(card, "small", L[step.body], "LEFT")
    body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -3)
    body:SetPoint("RIGHT", -24, 0)
    anchor = icon
  end
  local ok = UI.Button(card, L.WELCOME_OK, 120, function()
    card:Hide()
  end)
  ok:SetPoint("BOTTOMRIGHT", -18, 16)
  local try = UI.Button(card, L.WELCOME_TRY, 140, function()
    card:Hide()
    SL.SettingsPanel:DemoAlarm()
  end)
  try:SetPoint("BOTTOMLEFT", 18, 16)
  local settings = UI.Button(card, L.SETTINGS, 110, function()
    card:Hide()
    SL.SettingsPanel:Open()
  end)
  settings:SetPoint("LEFT", try, "RIGHT", 8, 0)
  if UISpecialFrames then
    table.insert(UISpecialFrames, "SafeLootWelcome")
  end
  card:Hide()
  self.card = card
end

function W:Show()
  if not self.card then
    self:Build()
  end
  UI.FadeIn(self.card)
end

function W:OnEnable()
  SL:RegisterCommand("welcome", function()
    W:Show()
  end, L.CMD_WELCOME, { "bienvenida" })
  if SL.settings.onboarded then
    return
  end
  SL.settings.onboarded = true
  local function show()
    SL:AfterCombat("welcome", function()
      W:Show()
    end)
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(4, show)
  else
    show()
  end
end
