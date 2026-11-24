-- The minimap button: one click opens or closes SafeLoot, right click gives a quick menu, drag moves it around the
-- edge. It shows a warning mark while the loot rules of your group are not the agreed ones.
-- Textures and placement verified in the real Forever client through Edgar's BlazonGuild. No libraries.
local _, SL = ...
local MB = SL:NewModule("MinimapButton")
SL.MinimapButton = MB
local API, UI, T, L = SL.API, SL.UI, SL.Theme, SL.L

local SIZE = 31

-- Round and square minimaps (other add-ons announce the shape through the GetMinimapShape convention).
-- Each shape: which quarters are round { bottom right, bottom left, top right, top left }.
local ROUND = { true, true, true, true }
local SHAPES = {
  ROUND = ROUND,
  SQUARE = { false, false, false, false },
  ["CORNER-TOPLEFT"] = { false, false, false, true },
  ["CORNER-TOPRIGHT"] = { false, false, true, false },
  ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
  ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
  ["SIDE-LEFT"] = { false, true, false, true },
  ["SIDE-RIGHT"] = { true, false, true, false },
  ["SIDE-TOP"] = { false, false, true, true },
  ["SIDE-BOTTOM"] = { true, true, false, false },
  ["TRICORNER-TOPLEFT"] = { false, true, true, true },
  ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
  ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
  ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

-- Offset from the centre of the minimap for an angle (degrees). Pure, used by the tests.
function MB.Offset(angle, width, height, shape)
  local a = math.rad(angle)
  local x, y = math.cos(a), math.sin(a)
  local quarter = 1
  if x < 0 then
    quarter = quarter + 1
  end
  if y > 0 then
    quarter = quarter + 2
  end
  local w, h = width / 2 + 10, height / 2 + 10
  if (SHAPES[shape or "ROUND"] or ROUND)[quarter] then
    return x * w, y * h
  end
  -- straight side: slide along the edge of the square
  local dw, dh = math.sqrt(2 * w * w) - 10, math.sqrt(2 * h * h) - 10
  return math.max(-w, math.min(x * dw, w)), math.max(-h, math.min(y * dh, h))
end

function MB:Place()
  local b = self.button
  if not b or not Minimap then
    return
  end
  local shape
  if type(GetMinimapShape) == "function" then
    local ok, value = pcall(GetMinimapShape)
    shape = ok and value or nil
  end
  local x, y = MB.Offset(SL.settings.minimapAngle or 182, Minimap:GetWidth() or 140, Minimap:GetHeight() or 140, shape)
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Follow the cursor around the edge while dragging.
function MB:Follow()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale() or 1
  if mx and px and scale > 0 then
    SL.settings.minimapAngle = math.floor(math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360 + 0.5)
    self:Place()
  end
end

function MB:Menu(button)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    if SL.SettingsPanel then
      SL.SettingsPanel:Open()
    end
    return
  end
  pcall(MenuUtil.CreateContextMenu, button, function(_, root)
    root:CreateTitle(L.ADDON_NAME)
    for _, tab in ipairs({ "contract", "journal", "players", "help" }) do
      root:CreateButton(L["TAB_" .. string.upper(tab)], function()
        SL.MainFrame:Open(tab)
      end)
    end
    root:CreateButton(L.PICKER_TITLE, function()
      SL.MainFrame:Open("contract")
      SL.LootPicker:Open(SL.Catalog:Destination())
    end)
    root:CreateButton(L.SETTINGS, function()
      SL.SettingsPanel:Open()
    end)
    root:CreateButton(T.Paint(L.MINIMAP_HIDE, T.color.gray), function()
      MB:SetVisible(false)
    end)
  end)
end

function MB:SetVisible(visible)
  SL.settings.showMinimap = visible and true or false
  self:Update()
  SL:Print(visible and L.MINIMAP_SHOWN or L.MINIMAP_HIDDEN)
end

function MB:ShowTooltip(owner)
  if not GameTooltip then
    return
  end
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  GameTooltip:SetText(L.ADDON_NAME, T.color.gold.r, T.color.gold.g, T.color.gold.b)
  if API.InGroup() then
    GameTooltip:AddLine(SL.Contract:ShortSummary(SL.Contract:Get()), 1, 1, 1, true)
    if SL.Indicator and (SL.Indicator.deviation or 0) >= 2 then
      GameTooltip:AddLine(L.IND_CHANGED, T.color.red.r, T.color.red.g, T.color.red.b, true)
    end
  end
  local g = T.color.gray
  GameTooltip:AddLine(L.MINIMAP_LEFT, g.r, g.g, g.b, true)
  GameTooltip:AddLine(L.MINIMAP_RIGHT, g.r, g.g, g.b, true)
  GameTooltip:AddLine(L.MINIMAP_DRAG, g.r, g.g, g.b, true)
  GameTooltip:Show()
end

function MB:Build()
  local b = CreateFrame("Button", "SafeLootMinimapButton", Minimap)
  b:SetSize(SIZE, SIZE)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local back = b:CreateTexture(nil, "BACKGROUND")
  back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  back:SetSize(22, 22)
  back:SetPoint("TOPLEFT", 5, -4)
  b.Icon = b:CreateTexture(nil, "ARTWORK")
  b.Icon:SetTexture(T.tex.minimap)
  b.Icon:SetSize(20, 20)
  b.Icon:SetPoint("TOPLEFT", 6, -5)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  -- an icon, not only a colour: the rules are not the agreed ones
  b.Alert = b:CreateTexture(nil, "OVERLAY", nil, 2)
  b.Alert:SetTexture(T.tex.alert)
  b.Alert:SetSize(18, 18)
  b.Alert:SetPoint("BOTTOMRIGHT", 3, -3)
  b.Alert:Hide()

  b:SetScript("OnClick", function(self, mouse)
    if self.dragging then
      return
    end
    if mouse == "RightButton" then
      SL.SafeCall("minimap menu", MB.Menu, MB, self)
    else
      SL.SafeCall("minimap click", SL.MainFrame.Toggle, SL.MainFrame)
    end
  end)
  b:SetScript("OnMouseDown", function(self)
    self.Icon:SetPoint("TOPLEFT", 7, -6)
  end)
  b:SetScript("OnMouseUp", function(self)
    self.Icon:SetPoint("TOPLEFT", 6, -5)
  end)
  b:SetScript("OnDragStart", function(self)
    self.dragging = true
    if GameTooltip then
      GameTooltip:Hide()
    end
    self:SetScript("OnUpdate", function()
      MB:Follow()
    end)
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    self.Icon:SetPoint("TOPLEFT", 6, -5)
    -- the release of a drag must not count as a click
    if C_Timer and C_Timer.After then
      C_Timer.After(0.1, function()
        self.dragging = false
      end)
    else
      self.dragging = false
    end
  end)
  b:SetScript("OnEnter", function(self)
    if not self.dragging then
      SL.SafeCall("minimap tooltip", MB.ShowTooltip, MB, self)
    end
  end)
  b:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  self.button = b
end

function MB:Update()
  if not Minimap then
    return
  end
  if not SL.settings.showMinimap then
    if self.button then
      self.button:Hide()
    end
    return
  end
  if not self.button then
    self:Build()
  end
  self:Place()
  self.button:Show()
  self.button.Alert:SetShown(API.InGroup() and SL.Indicator ~= nil and (SL.Indicator.deviation or 0) >= 2)
end

function MB:OnEnable()
  self:Update()
  local function update()
    MB:Update()
  end
  -- after the indicator has worked out the state (it registers first)
  SL:On("RULES_STATUS", self, update)
  SL:On("CONTRACT_CHANGED", self, update)
  SL:On("SETTING_CHANGED", self, function(_, key)
    if key == "showMinimap" then
      MB:Update()
    end
  end)
  SL:RegisterEvent("GROUP_ROSTER_UPDATE", self, function()
    SL:Debounce("minimap-roster", 0.8, update)
  end)
  -- other add-ons may reshape or resize the minimap while the world loads
  SL:RegisterEvent("PLAYER_ENTERING_WORLD", self, function()
    SL:Debounce("minimap-place", 2, update)
  end)
  SL:RegisterCommand("minimap", function()
    MB:SetVisible(not SL.settings.showMinimap)
  end, L.CMD_MINIMAP, { "minimapa" })
end
