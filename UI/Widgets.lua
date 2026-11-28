-- Small builders over the game's own templates (verified in the Forever source, docs/PROMPT_MAESTRO.md §6.1).
-- Every template is checked first (C_XMLUtil.GetTemplateInfo); if one is missing we fall back instead of failing.
local _, SL = ...
local UI = {}
SL.UI = UI
local T = SL.Theme

function UI.Create(kind, parent, template, name)
  if template and not SL.API.TemplateExists(template) then
    SL:ReportError("UI.Create", "missing template " .. template)
    template = nil
  end
  local ok, frame = pcall(CreateFrame, kind, name, parent, template)
  if ok and frame then
    return frame
  end
  return CreateFrame(kind, name, parent)
end

function UI.Text(parent, role, text, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", T.Font(role or "body"))
  fs.role = role or "body"
  if justify then
    fs:SetJustifyH(justify)
  end
  if text then
    fs:SetText(text)
  end
  UI.fonts = UI.fonts or {}
  UI.fonts[#UI.fonts + 1] = fs
  return fs
end

-- Re-apply fonts after the "large text" option changes.
function UI.RefreshFonts()
  for _, fs in ipairs(UI.fonts or {}) do
    if fs.role and fs.SetFontObject then
      fs:SetFontObject(T.Font(fs.role))
    end
  end
end

function UI.Icon(parent, size, texture, layer)
  local icon = parent:CreateTexture(nil, layer or "ARTWORK")
  icon:SetSize(size, size)
  if texture then
    icon:SetTexture(texture)
  end
  return icon
end

-- Tooltip with a title and optional body lines on any frame.
function UI.Tooltip(frame, title, body)
  frame:HookScript("OnEnter", function(self)
    if not GameTooltip then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(type(title) == "function" and title() or title, T.color.gold.r, T.color.gold.g, T.color.gold.b)
    local text = type(body) == "function" and body() or body
    if text and text ~= "" then
      GameTooltip:AddLine(text, 1, 1, 1, true)
    end
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
end

function UI.Button(parent, text, width, onClick, tipTitle, tipBody)
  local button = UI.Create("Button", parent, "UIPanelButtonTemplate")
  button:SetSize(width or 140, 24)
  button:SetText(text)
  UI.FitText(button, (width or 140) - 14)
  button:SetScript("OnClick", function(self, mouse)
    SL.SafeCall("button " .. tostring(text), onClick, self, mouse)
  end)
  if tipTitle then
    UI.Tooltip(button, tipTitle, tipBody)
  end
  return button
end

function UI.Check(parent, label, getValue, setValue, tipBody)
  local check = UI.Create("CheckButton", parent, "UICheckButtonTemplate")
  check:SetSize(26, 26)
  local fs = check.Text
  if not fs then
    fs = UI.Text(check, "body")
    fs:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check.Text = fs
  else
    fs:SetFontObject(T.Font("body"))
  end
  fs:SetText(label)
  check:SetChecked(getValue() and true or false)
  check:SetScript("OnClick", function(self)
    local value = self:GetChecked() and true or false
    T.Play(value and "checkOn" or "checkOff")
    SL.SafeCall("check " .. tostring(label), setValue, value)
  end)
  if tipBody then
    UI.Tooltip(check, label, tipBody)
  end
  check.Refresh = function(self)
    self:SetChecked(getValue() and true or false)
  end
  return check
end

-- Text input. Seen in the real client (2026-11-24): SharedEditBoxTemplate draws its art at a fixed size and
-- spills outside small boxes, and SetInstructions is missing. So, like BlazonGuild's own input: a classic
-- tooltip-border box with a dark background, the game's font, and a grey hint shown while the box is empty.
function UI.Input(parent, width, placeholder, maxLetters)
  local holder = UI.Create("Frame", parent, "BackdropTemplate")
  holder:SetSize(width, 26)
  if holder.SetBackdrop then
    holder:SetBackdrop({
      bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    holder:SetBackdropColor(0, 0, 0, 0.55)
    holder:SetBackdropBorderColor(0.65, 0.65, 0.65, 0.9)
  end
  local box = CreateFrame("EditBox", nil, holder)
  box:SetPoint("TOPLEFT", 8, -3)
  box:SetPoint("BOTTOMRIGHT", -8, 3)
  box:SetFontObject(T.Font("body"))
  box:SetAutoFocus(false)
  box:SetMaxLetters(maxLetters or 120)
  box.holder = holder
  local hint = UI.Text(holder, "muted", placeholder or "", "LEFT")
  hint:SetPoint("LEFT", 9, 0)
  hint:SetPoint("RIGHT", -8, 0)
  hint:SetWordWrap(false)
  box.Hint = hint
  local function update()
    hint:SetShown((box:GetText() or "") == "" and not box:HasFocus())
  end
  box:SetScript("OnEditFocusGained", update)
  box:SetScript("OnEditFocusLost", update)
  box:SetScript("OnTextChanged", update)
  box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  box:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
  end)
  holder:EnableMouse(true)
  holder:SetScript("OnMouseDown", function()
    box:SetFocus()
  end)
  box.Refresh = update
  update()
  return box
end

-- Item links in our texts behave like links in chat: hover shows the item, click opens it (shift-click puts it in
-- the chat box, ctrl-click previews it), through the game's own SetItemRef. Seen in the real client: without
-- this, the links in the journal, toasts and summary were dead text.
function UI.EnableLinks(frame)
  if frame.SetHyperlinksEnabled then
    frame:SetHyperlinksEnabled(true)
  end
  frame:SetScript("OnHyperlinkEnter", function(self, link)
    if not GameTooltip or type(link) ~= "string" then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
      GameTooltip:Show()
    else
      GameTooltip:Hide()
    end
  end)
  frame:SetScript("OnHyperlinkLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  frame:SetScript("OnHyperlinkClick", function(self, link, text, button)
    if SetItemRef then
      pcall(SetItemRef, link, text, button, self)
    end
  end)
end

-- A card with the game's "Dialog" frame (diamond metal border, as StaticPopup) over a dark dialog background.
function UI.Card(parent, width, height, name)
  local card = UI.Create("Frame", parent or UIParent, nil, name)
  card:SetSize(width, height)
  local bg = card:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(T.tex.dialogBg)
  bg:SetPoint("TOPLEFT", 6, -6)
  bg:SetPoint("BOTTOMRIGHT", -6, 6)
  bg:SetAlpha(0.92)
  card.Bg = bg
  local border = UI.Create("Frame", card, "NineSlicePanelTemplate")
  border:SetAllPoints()
  border:SetFrameLevel(card:GetFrameLevel() + 1)
  if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
    pcall(NineSliceUtil.ApplyLayoutByName, border, "Dialog")
  end
  card.Border = border
  card:EnableMouse(true)
  return card
end

-- Smooth appearance (0.2 s alpha + slight rise) unless "reduce motion" is on.
function UI.FadeIn(frame)
  if SL.settings and SL.settings.reduceMotion then
    frame:SetAlpha(1)
    frame:Show()
    return
  end
  if not frame.fadeIn then
    local group = frame:CreateAnimationGroup()
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.2)
    local move = group:CreateAnimation("Translation")
    move:SetOffset(0, 6)
    move:SetDuration(0.2)
    group:SetScript("OnFinished", function()
      frame:SetAlpha(1)
    end)
    frame.fadeIn = group
  end
  frame:SetAlpha(0)
  frame:Show()
  frame.fadeIn:Play()
end

-- Draggable frame that remembers where the player left it (per character).
-- Drag it anywhere (title bar or any empty part); the place is remembered for each character.
-- (EnableMouse is needed: without it the game never reports the drag, and clicks go through the window to the world.
-- The main window could not be moved until 0.5.0.)
UI.movables = {}
function UI.Movable(frame, key, defaultPoint)
  UI.movables[#UI.movables + 1] = frame
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if self.SetUserPlaced then
      self:SetUserPlaced(false) -- we remember the place; the game's own layout cache must not fight with it
    end
    local point, _, relPoint, x, y = self:GetPoint(1)
    if SL.char then
      SL.char.positions[key] = { point, relPoint, x, y }
    end
  end)
  frame.RestorePosition = function(self)
    self:ClearAllPoints()
    local saved = SL.char and SL.char.positions[key]
    if saved and not pcall(self.SetPoint, self, saved[1], UIParent, saved[2], saved[3], saved[4]) then
      self:ClearAllPoints()
      saved = nil -- an anchor the game does not know (damaged saved data): back to the first place
    elseif saved then
      return
    end
    if type(defaultPoint) == "function" then
      defaultPoint(self)
    else
      self:SetPoint(unpack(defaultPoint))
    end
  end
  frame:RestorePosition()
end

-- Icon + coloured word for a memory tone (never colour alone).
-- Every window back to its first place (/safeloot reset): for one lost off the screen or behind something.
function UI.ResetPositions()
  if SL.char then
    SL.char.positions = {}
  end
  for _, frame in ipairs(UI.movables) do
    frame:RestorePosition()
  end
end

function UI.ToneLine(tone)
  local info = T.tone[tone] or T.tone.neutral
  local word = SL.L["TONE_" .. string.upper(tone or "neutral")] or ""
  return "|T" .. info.icon .. ":14:14|t " .. T.Paint(word, info.color), info
end

function UI.FormatDate(t)
  if not t or t == 0 then
    return ""
  end
  return date and date("%d-%m %H:%M", t) or tostring(t)
end

-- "today", "yesterday", "3 days ago": how long ago, in words.
function UI.Ago(t)
  if type(t) ~= "number" or t == 0 then
    return ""
  end
  local L = SL.L
  local days = math.floor((SL.API.Now() - t) / 86400)
  if days <= 0 then
    return L.AGO_TODAY
  elseif days == 1 then
    return L.AGO_YESTERDAY
  end
  return string.format(L.AGO_DAYS, days)
end

-- Scrolling list: WowScrollBoxList + MinimalScrollBar (verified templates), one Button row per element.
-- onInit(row, data) fills a row; onClick(data, mouseButton, row); opts.build(row) adds widgets to a new row;
-- opts.onEnter / opts.onLeave (row, data) for tooltips.
function UI.List(parent, rowHeight, onInit, onClick, opts)
  opts = opts or {}
  local box = UI.Create("Frame", parent, "WowScrollBoxList")
  local bar = UI.Create("EventFrame", parent, "MinimalScrollBar")
  box:SetPoint("TOPLEFT", 4, -4)
  box:SetPoint("BOTTOMRIGHT", -20, 4)
  bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
  bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
  local list = { box = box, bar = bar }
  if CreateScrollBoxListLinearView and ScrollUtil and ScrollUtil.InitScrollBoxListWithScrollBar and CreateDataProvider then
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(rowHeight)
    view:SetElementInitializer("Button", function(row, data)
      if not row.Text then
        row.Highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.Highlight:SetAllPoints()
        row.Highlight:SetColorTexture(1, 0.82, 0, 0.08)
        row.Text = UI.Text(row, "small", "", "LEFT")
        row.Text:SetPoint("LEFT", 6, 0)
        row.Text:SetPoint("RIGHT", -6, 0)
        row.Text:SetWordWrap(false)
        UI.EnableLinks(row)
        if row.RegisterForClicks then
          row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
        row:SetScript("OnClick", function(self, mouse)
          if onClick and self.data then
            SL.SafeCall("list click", onClick, self.data, mouse, self)
          end
        end)
        row:SetScript("OnEnter", function(self)
          if opts.onEnter and self.data then
            SL.SafeCall("list enter", opts.onEnter, self, self.data)
          end
        end)
        row:SetScript("OnLeave", function(self)
          if opts.onLeave then
            SL.SafeCall("list leave", opts.onLeave, self, self.data)
          elseif GameTooltip then
            GameTooltip:Hide()
          end
        end)
        if opts.build then
          opts.build(row)
        end
      end
      row.data = data
      onInit(row, data)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    list.provider = CreateDataProvider()
    box:SetDataProvider(list.provider)
    list.view = view
  end
  -- A new provider with everything at once: inserting line by line makes the game lay the whole list out again for every
  -- line (OnSizeChanged -> FullUpdate, Forever UI source). The scroll stays where it was unless top is true.
  list.Set = function(self, items, top)
    if self.provider then
      self.provider = CreateDataProvider(items)
      self.box:SetDataProvider(self.provider, not top)
    end
  end
  return list
end

-- Item tooltip for a row (by item ID, or by link when only the link is known).
function UI.ItemTooltip(owner, itemID, link)
  if not GameTooltip then
    return
  end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local ok = false
  if itemID and GameTooltip.SetItemByID then
    ok = pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
  end
  if not ok and type(link) == "string" then
    ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
  end
  if ok then
    GameTooltip:Show()
  else
    GameTooltip:Hide()
  end
end

-- A button whose label never spills out of it: one line, cut with "..." by the game when too long.
function UI.FitText(button, width)
  local fs = button.GetFontString and button:GetFontString()
  if fs then
    fs:SetWidth(width)
    fs:SetWordWrap(false)
  end
end
