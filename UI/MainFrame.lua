-- Main window (docs/PROMPT_MAESTRO.md §5, §6.6): the game's PortraitFrameTemplate with bottom tabs, like the
-- classic Character window. Tabs: Contract · Journal · Players. Built on first open (never in combat).
local _, SL = ...
local MF = SL:NewModule("MainFrame")
SL.MainFrame = MF
local API, Rules, Memory, Names, UI, T, L = SL.API, SL.Rules, SL.Memory, SL.Names, SL.UI, SL.Theme, SL.L

local WIDTH, HEIGHT = 560, 470
local TABS = { "contract", "journal", "players", "help" }

-- Lists: WowScrollBoxList + MinimalScrollBar (verified templates), one text line per element ----------------
local function makeList(parent, rowHeight, onInit, onClick)
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
        row:SetScript("OnClick", function(self)
          if onClick and self.data then
            SL.SafeCall("list click", onClick, self.data)
          end
        end)
      end
      row.data = data
      onInit(row, data)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    list.provider = CreateDataProvider()
    box:SetDataProvider(list.provider)
  end
  list.Set = function(self, items)
    if self.provider then
      self.provider:Flush()
      for _, item in ipairs(items) do
        self.provider:Insert(item)
      end
    end
  end
  return list
end

-- Tab 1: Contract ---------------------------------------------------------------------------------------------
local function buildContractTab(page)
  local status = UI.Text(page, "header", "", "LEFT")
  status:SetPoint("TOPLEFT", 16, -14)
  status:SetPoint("RIGHT", -16, 0)
  page.Status = status

  local source = UI.Text(page, "muted", "", "LEFT")
  source:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -4)
  source:SetPoint("RIGHT", -16, 0)
  page.Source = source

  local accepted = UI.Text(page, "small", "", "LEFT")
  accepted:SetPoint("TOPLEFT", source, "BOTTOMLEFT", 0, -6)
  accepted:SetPoint("RIGHT", -16, 0)
  page.Accepted = accepted

  local header = UI.Text(page, "header", L.CONTRACT_EDIT, "LEFT")
  header:SetPoint("TOPLEFT", 16, -96)

  -- Need rule: three exclusive choices (check buttons acting as radio buttons)
  page.rules = {}
  local choices = { { "msos", L.NEED_msos }, { "greed", L.NEED_greed }, { "free", L.NEED_free } }
  for i, choice in ipairs(choices) do
    local check = UI.Check(page, choice[2], function()
      local c = SL.Contract:Get()
      return c and c.needRule == choice[1]
    end, function(value)
      local c = SL.Contract:Get() or Rules.New("proposed", API.Now())
      c.needRule = value and choice[1] or nil
      SL.Contract.current = c
      MF:Refresh()
    end, L["NEED_TIP_" .. choice[1]])
    check:SetPoint("TOPLEFT", 14, -114 - (i - 1) * 26)
    page.rules[#page.rules + 1] = check
  end
  local boe = UI.Check(page, L.BOE_GREED, function()
    local c = SL.Contract:Get()
    return c and c.boe == "greed"
  end, function(value)
    local c = SL.Contract:Get() or Rules.New("proposed", API.Now())
    c.boe = value and "greed" or nil
    SL.Contract.current = c
    MF:Refresh()
  end, L.BOE_TIP)
  boe:SetPoint("TOPLEFT", 280, -114)
  page.rules[#page.rules + 1] = boe

  -- Reserves: item + owner + add
  local resHeader = UI.Text(page, "header", L.RESERVES_HEADER, "LEFT")
  resHeader:SetPoint("TOPLEFT", 16, -204)
  local item = UI.Create("EditBox", page, "SharedEditBoxTemplate")
  item:SetSize(230, 32)
  item:SetPoint("TOPLEFT", 14, -222)
  item:SetAutoFocus(false)
  if item.SetInstructions then
    pcall(item.SetInstructions, item, L.RESERVE_ITEM)
  end
  page.ItemBox = item
  local owner = UI.Create("EditBox", page, "SharedEditBoxTemplate")
  owner:SetSize(150, 32)
  owner:SetPoint("LEFT", item, "RIGHT", 8, 0)
  owner:SetAutoFocus(false)
  if owner.SetInstructions then
    pcall(owner.SetInstructions, owner, L.RESERVE_OWNER)
  end
  page.OwnerBox = owner
  local add = UI.Button(page, ADD or "+", 70, function()
    local itemName = item:GetText()
    if not itemName or itemName:gsub("%s", "") == "" then
      return
    end
    local c = SL.Contract:Get() or Rules.New("proposed", API.Now())
    local partialItem = itemName:match("%[(.-)%]") or itemName
    local ownerName = owner:GetText() ~= "" and owner:GetText() or nil
    Rules.Apply(c, { reserves = { { item = partialItem, owner = ownerName, kind = "hard" } } })
    SL.Contract.current = c
    item:SetText("")
    owner:SetText("")
    MF:Refresh()
  end, L.RESERVE_ADD_TIP, L.RESERVE_ADD_BODY)
  add:SetPoint("LEFT", owner, "RIGHT", 8, 0)
  -- shift-click an item link into the box
  item:SetScript("OnEditFocusGained", function()
    MF.linkTarget = item
  end)

  local reserves = UI.Text(page, "small", "", "LEFT")
  reserves:SetPoint("TOPLEFT", 16, -262)
  reserves:SetPoint("RIGHT", -16, 0)
  reserves:SetSpacing(2)
  page.Reserves = reserves

  -- Preview of the chat line everyone will read
  local previewHeader = UI.Text(page, "header", L.PREVIEW_HEADER, "LEFT")
  previewHeader:SetPoint("TOPLEFT", 16, -312)
  local preview = UI.Text(page, "small", "", "LEFT")
  preview:SetPoint("TOPLEFT", previewHeader, "BOTTOMLEFT", 0, -4)
  preview:SetPoint("RIGHT", -16, 0)
  page.Preview = preview

  local publish = UI.Button(page, L.PUBLISH, 180, function()
    SL.Contract:Publish()
    MF:Refresh()
  end, L.PUBLISH, L.PUBLISH_TIP)
  publish:SetPoint("BOTTOMLEFT", 14, 14)
  page.Publish = publish
  local clear = UI.Button(page, L.CLEAR_RESERVES, 140, function()
    local c = SL.Contract:Get()
    if c then
      c.reserves = {}
    end
    MF:Refresh()
  end)
  clear:SetPoint("LEFT", publish, "RIGHT", 8, 0)
  local fromGame = UI.Button(page, L.USE_GAME_RULES, 170, function()
    local state = API.LootState()
    if state then
      SL.Contract:Reset(Rules.FromState(state, API.Now()))
    end
    MF:Refresh()
  end, L.USE_GAME_RULES, L.USE_GAME_RULES_TIP)
  fromGame:SetPoint("LEFT", clear, "RIGHT", 8, 0)

  local tip = UI.Text(page, "muted", L.CONTRACT_TIP, "LEFT")
  tip:SetPoint("BOTTOMLEFT", publish, "TOPLEFT", 2, 8)
  tip:SetPoint("RIGHT", -16, 0)
end

local SOURCE_TEXT = { auto = "SOURCE_AUTO", copied = "SOURCE_COPIED", proposed = "SOURCE_PROPOSED", received = "SOURCE_RECEIVED" }

local function refreshContractTab(page)
  local c = SL.Contract:Get()
  page.Status:SetText("|T" .. (c and T.tex.ok or T.tex.wait) .. ":16:16|t " .. L.CONTRACT_CURRENT .. " " .. SL.Contract:Summary(c))
  page.Source:SetText(c and (L[SOURCE_TEXT[c.source] or "SOURCE_AUTO"] .. " · " .. UI.FormatDate(c.createdAt)) or L.CONTRACT_NONE_HINT)
  local names = {}
  if c and c.accepted then
    for name, t in pairs(c.accepted) do
      names[#names + 1] = "|T" .. T.tex.ok .. ":12:12|t " .. name .. " " .. (date and date("%H:%M", t) or "")
    end
  end
  if c and c.publishedAt then
    page.Accepted:SetText(#names > 0 and (L.ACCEPTED_BY .. " " .. table.concat(names, "   ")) or L.ACCEPTED_NONE)
  else
    page.Accepted:SetText("")
  end
  local lines = {}
  for _, reserve in ipairs(c and c.reserves or {}) do
    lines[#lines + 1] = "• " .. (reserve.kind == "soft" and "SR " or "HR ") .. reserve.item
      .. (reserve.owner and (" → " .. reserve.owner) or "")
  end
  page.Reserves:SetText(#lines > 0 and table.concat(lines, "\n") or T.Paint(L.RESERVES_NONE, T.color.gray))
  page.Preview:SetText(T.Paint(SL.Contract:ChatLine(c), T.color.white))
  for _, check in ipairs(page.rules) do
    check:Refresh()
  end
  if API.InGroup() then
    page.Publish:Enable()
  else
    page.Publish:Disable()
  end
end

-- Tab 2: Journal ------------------------------------------------------------------------------------------------
local function buildJournalTab(page)
  local inset = UI.Create("Frame", page, "InsetFrameTemplate")
  inset:SetPoint("TOPLEFT", 10, -10)
  inset:SetPoint("BOTTOMRIGHT", -10, 10)
  page.List = makeList(inset, 20, function(row, data)
    row.Text:SetText(data.text or "")
  end)
end

local function journalItems()
  local items = {}
  local function addRun(run, current)
    items[#items + 1] = { text = T.Paint((current and L.JOURNAL_CURRENT or "") .. (run.place or "?") .. " · " .. UI.FormatDate(run.startedAt), T.color.gold) }
    for _, event in ipairs(run.events or {}) do
      if event.text then
        items[#items + 1] = { text = "   " .. (date and date("%H:%M", event.t) or "") .. "  " .. event.text }
      end
    end
    for _, drop in pairs(run.drops or {}) do
      if drop.winner then
        items[#items + 1] = { text = "   " .. string.format(L.SUMMARY_DROP, drop.item or "?", drop.winner) }
      end
    end
  end
  local current = SL.Run:Current()
  if current then
    addRun(current, true)
  end
  for i = #SL.db.runs, math.max(1, #SL.db.runs - 20), -1 do
    addRun(SL.db.runs[i], false)
  end
  if #items == 0 then
    items[1] = { text = T.Paint(L.JOURNAL_EMPTY, T.color.gray) }
  end
  return items
end

-- Tab 3: Players ------------------------------------------------------------------------------------------------
local function buildPlayersTab(page)
  local search = UI.Create("EditBox", page, "SharedEditBoxTemplate")
  search:SetSize(220, 32)
  search:SetPoint("TOPLEFT", 14, -10)
  search:SetAutoFocus(false)
  if search.SetInstructions then
    pcall(search.SetInstructions, search, L.SEARCH)
  end
  search:SetScript("OnTextChanged", function()
    MF:Refresh()
  end)
  page.Search = search

  local inset = UI.Create("Frame", page, "InsetFrameTemplate")
  inset:SetPoint("TOPLEFT", 10, -48)
  inset:SetPoint("BOTTOMRIGHT", -10, 150)
  page.List = makeList(inset, 22, function(row, data)
    local color = API.ClassColor(data.record.class)
    local name = color and ("|c" .. (color.colorStr or T.Hex(color)) .. data.name .. "|r") or data.name
    local tone = data.summary.tone and UI.ToneLine(data.summary.tone) or ("|T" .. T.tex.wait .. ":14:14|t")
    row.Text:SetText(tone .. "  " .. name .. "   " .. T.Paint(SL.MemoryHooks.EventText(data.summary.latest), T.color.gray))
  end, function(data)
    page.selected = data.name
    MF:Refresh()
  end)

  local detail = UI.Text(page, "small", "", "LEFT")
  detail:SetPoint("TOPLEFT", inset, "BOTTOMLEFT", 6, -8)
  detail:SetPoint("RIGHT", -16, 0)
  page.Detail = detail

  -- The buttons act on the selected player, or on the name typed in the search box when nobody matches it
  -- (so you can note someone who wronged you before you had the addon).
  local function target()
    if page.selected then
      return page.selected
    end
    local typed = SL.Rules.Clean(page.Search:GetText() or "", 48)
    return typed and SL.Names.Short(typed) or nil
  end
  page.Target = target
  local function tag(kind)
    return function()
      local name = target()
      if name then
        Memory.Add(SL.db.players, name, { kind = kind, t = API.Now(), place = API.PlaceName() })
        page.selected = SL.Names.Short(name)
        MF:Refresh()
      end
    end
  end

  local note = UI.Create("EditBox", page, "SharedEditBoxTemplate")
  note:SetSize(400, 32)
  note:SetPoint("BOTTOMLEFT", 14, 44)
  note:SetAutoFocus(false)
  note:SetMaxLetters(200)
  if note.SetInstructions then
    pcall(note.SetInstructions, note, L.NOTE_PLACEHOLDER)
  end
  page.Note = note
  local function addNote()
    local name = target()
    local text = SL.Rules.Clean(note:GetText() or "", 200)
    if name and text then
      Memory.Add(SL.db.players, name, { kind = "note", t = API.Now(), note = text, place = API.PlaceName() })
      page.selected = SL.Names.Short(name)
      note:SetText("")
      note:ClearFocus()
      MF:Refresh()
    end
  end
  note:SetScript("OnEnterPressed", addNote)
  note:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  page.NoteButton = UI.Button(page, L.NOTE_ADD, 110, addNote, L.NOTE_ADD, L.NOTE_TIP)
  page.NoteButton:SetPoint("LEFT", note, "RIGHT", 8, 0)
  local buttons = {
    { L.TAG_TRUSTED, tag("tag_trusted") }, { L.TAG_NINJA, tag("tag_ninja") }, { L.TAG_EXTORTION, tag("tag_extortion") },
    { L.FORGET, function()
      if page.selected then
        Memory.Forget(SL.db.players, page.selected)
        page.selected = nil
        MF:Refresh()
      end
    end },
  }
  page.tagButtons = {}
  for i, spec in ipairs(buttons) do
    local b = UI.Button(page, spec[1], 122, spec[2])
    b:SetPoint("BOTTOMLEFT", 14 + (i - 1) * 128, 14)
    page.tagButtons[i] = b
  end
end

local function refreshPlayersTab(page)
  local filter = page.Search:GetText()
  local list = Memory.List(SL.db.players, API.Now(), SL.settings.memoryDays, filter)
  if #list == 0 then
    page.Detail:SetText(T.Paint(L.PLAYERS_EMPTY, T.color.gray))
  end
  page.List:Set(list)
  local record = page.selected and SL.db.players[page.selected]
  if record then
    local lines = { T.Paint(page.selected, T.color.gold) .. "  " .. (API.LocalizedClass(record.class) or "") }
    for i = #record.events, math.max(1, #record.events - 2), -1 do
      lines[#lines + 1] = "• " .. SL.MemoryHooks.EventText(record.events[i])
    end
    page.Detail:SetText(table.concat(lines, "\n"))
  elseif #list > 0 then
    page.Detail:SetText(T.Paint(L.PLAYERS_PICK, T.color.gray))
  end
  local name = page.Target()
  if not record and name and #list == 0 then
    page.Detail:SetText(T.Paint(string.format(L.NEW_PLAYER_HINT, name), T.color.gray))
  end
  for i, b in ipairs(page.tagButtons) do
    local enabled = name ~= nil and (i < #page.tagButtons or record ~= nil) -- "Forget" needs an existing record
    if enabled then b:Enable() else b:Disable() end
  end
  if name then page.NoteButton:Enable() else page.NoteButton:Disable() end
end

-- Tab 4: Help ---------------------------------------------------------------------------------------------------
local function helpItems()
  local items = {}
  local function head(text)
    items[#items + 1] = { text = T.Paint(text, T.color.gold), head = true }
  end
  local function line(text)
    items[#items + 1] = { text = text }
  end
  head(L.HELP_ABOUT_TITLE)
  line(L.HELP_ABOUT)
  head(L.HELP_GLOSSARY_TITLE)
  for _, key in ipairs({ "GLOSS_NEED", "GLOSS_GREED", "GLOSS_ML", "GLOSS_GROUP", "GLOSS_HR", "GLOSS_SR", "GLOSS_MSOS",
    "GLOSS_BOE", "GLOSS_PUG" }) do
    line(L[key])
  end
  head(L.HELP_COMMANDS_TITLE)
  for _, cmd in ipairs({ { "", L.CMD_OPEN }, { "test", L.CMD_TEST }, { "alarm", L.CMD_DEMO_ALARM },
    { "mark", L.CMD_DEMO_MARK }, { "summary", L.CMD_DEMO_SUMMARY }, { "welcome", L.CMD_WELCOME },
    { "settings", L.CMD_SETTINGS }, { "exceptions", L.CMD_RESET_EXCEPTIONS } }) do
    line(T.Paint("/safeloot " .. cmd[1], T.color.white) .. " — " .. cmd[2])
  end
  head(L.HELP_PRIVACY_TITLE)
  line(L.HELP_PRIVACY)
  return items
end

local function buildHelpTab(page)
  local inset = UI.Create("Frame", page, "InsetFrameTemplate")
  inset:SetPoint("TOPLEFT", 10, -10)
  inset:SetPoint("BOTTOMRIGHT", -10, 10)
  page.List = makeList(inset, 34, function(row, data)
    row.Text:SetWordWrap(true)
    row.Text:SetText(data.text or "")
  end)
end

-- Window -------------------------------------------------------------------------------------------------------
function MF:Build()
  local frame = UI.Create("Frame", UIParent, "PortraitFrameTemplate", "SafeLootMainFrame")
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:Hide()
  UI.Movable(frame, "main", { "CENTER", UIParent, "CENTER", 0, 0 })
  frame:SetScale(SL.settings.scale or 1)
  if frame.SetTitle then
    frame:SetTitle(L.ADDON_NAME)
  end
  if frame.SetPortraitToAsset then
    pcall(frame.SetPortraitToAsset, frame, T.tex.portrait)
  end
  if UISpecialFrames then
    table.insert(UISpecialFrames, "SafeLootMainFrame")
  end
  frame:SetScript("OnShow", function()
    T.Play("open")
    MF:Refresh()
  end)
  frame:SetScript("OnHide", function()
    T.Play("close")
  end)

  local settings = UI.Button(frame, L.SETTINGS, 90, function()
    if SL.SettingsPanel then
      SL.SettingsPanel:Open()
    end
  end, L.SETTINGS, L.SETTINGS_TIP)
  settings:SetPoint("TOPRIGHT", -30, -30)

  self.pages = {}
  for i, key in ipairs(TABS) do
    local page = CreateFrame("Frame", nil, frame)
    page:SetPoint("TOPLEFT", 6, -58)
    page:SetPoint("BOTTOMRIGHT", -6, 6)
    page:Hide()
    self.pages[key] = page
    local tab = UI.Create("Button", frame, "PanelTabButtonTemplate", "SafeLootMainFrameTab" .. i)
    tab:SetID(i)
    tab:SetText(L["TAB_" .. string.upper(key)])
    tab:HookScript("OnClick", function()
      T.Play("tab")
      MF:Open(key)
    end)
    if PanelTemplates_TabResize then
      pcall(PanelTemplates_TabResize, tab, 0)
    end
  end
  if PanelTemplates_SetNumTabs then
    pcall(PanelTemplates_SetNumTabs, frame, #TABS)
  end
  buildContractTab(self.pages.contract)
  buildJournalTab(self.pages.journal)
  buildPlayersTab(self.pages.players)
  buildHelpTab(self.pages.help)
  self.frame = frame
  self:Open("contract", true)
end

function MF:Open(key, silent)
  if not self.frame then
    if SL:InCombat() then
      SL:AfterCombat("mainframe-open", function()
        MF:Open(key)
      end)
      return
    end
    self:Build()
  end
  self.tab = key or self.tab or "contract"
  for i, name in ipairs(TABS) do
    self.pages[name]:SetShown(name == self.tab)
    if name == self.tab and PanelTemplates_SetTab then
      pcall(PanelTemplates_SetTab, self.frame, i)
    end
  end
  if not silent then
    self.frame:Show()
  end
  self:Refresh()
end

function MF:Toggle()
  if self.frame and self.frame:IsShown() then
    self.frame:Hide()
  else
    self:Open(self.tab)
  end
end

function MF:Refresh()
  if not self.frame or not self.frame:IsShown() then
    return
  end
  if self.tab == "contract" then
    refreshContractTab(self.pages.contract)
  elseif self.tab == "journal" then
    self.pages.journal.List:Set(journalItems())
  elseif self.tab == "players" then
    refreshPlayersTab(self.pages.players)
  elseif self.tab == "help" then
    self.pages.help.List:Set(helpItems())
  end
end

function MF:OnEnable()
  SL:On("CONTRACT_CHANGED", self, function()
    MF:Refresh()
  end)
  SL:On("MEMORY_CHANGED", self, function()
    MF:Refresh()
  end)
  SL:On("RUN_FINISHED", self, function()
    MF:Refresh()
  end)
  -- shift-click an item into the reserve box
  if type(ChatEdit_InsertLink) == "function" then
    hooksecurefunc("ChatEdit_InsertLink", function(link)
      local box = MF.linkTarget
      if box and box:HasFocus() and type(link) == "string" then
        box:SetText(link:match("%[(.-)%]") or link)
      end
    end)
  end
  SL:RegisterCommand("rules", function()
    MF:Open("contract")
  end, L.CMD_CONTRACT, { "reglas", "contrato" })
  SL:RegisterCommand("players", function()
    MF:Open("players")
  end, L.CMD_PLAYERS, { "jugadores" })
  SL:RegisterCommand("journal", function()
    MF:Open("journal")
  end, L.CMD_JOURNAL, { "diario" })
  SL:RegisterCommand("help", function()
    MF:Open("help")
  end, L.CMD_HELP, { "ayuda" })
end
