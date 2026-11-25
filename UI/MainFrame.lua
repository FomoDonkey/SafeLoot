-- Main window (docs/PROMPT_MAESTRO.md §5, §6.6): the game's PortraitFrameTemplate with bottom tabs, like the
-- classic Character window. Tabs: Contract · Journal · Players. Built on first open (never in combat).
local _, SL = ...
local MF = SL:NewModule("MainFrame")
SL.MainFrame = MF
local API, Rules, Names, UI, T, L = SL.API, SL.Rules, SL.Names, SL.UI, SL.Theme, SL.L

local WIDTH, HEIGHT = 640, 520 -- (wider in 0.5.0: the three panes of the Players tab)
local TABS = { "contract", "journal", "players", "help" }

-- Lists: UI.List (WowScrollBoxList + MinimalScrollBar), one text line per element --------------------------
local function makeList(parent, rowHeight, onInit, onClick, opts)
  return UI.List(parent, rowHeight, onInit, onClick and function(data)
    onClick(data)
  end, opts)
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

  local game = UI.Text(page, "small", "", "LEFT")
  game:SetPoint("TOPLEFT", source, "BOTTOMLEFT", 0, -6)
  game:SetPoint("RIGHT", -16, 0)
  page.Game = game

  local accepted = UI.Text(page, "small", "", "LEFT")
  accepted:SetPoint("TOPLEFT", game, "BOTTOMLEFT", 0, -4)
  accepted:SetPoint("RIGHT", -16, 0)
  page.Accepted = accepted
  -- one line each: a long summary or a whole raid of names never pushes into the rules below
  for _, fs in ipairs({ status, source, game, accepted }) do
    fs:SetWordWrap(false)
  end

  local header = UI.Text(page, "header", L.CONTRACT_EDIT, "LEFT")
  header:SetPoint("TOPLEFT", 16, -84)

  -- Need rule: three exclusive choices (check buttons acting as radio buttons)
  page.rules = {}
  local choices = { { "msos", L.NEED_msos }, { "greed", L.NEED_greed }, { "free", L.NEED_free } }
  for i, choice in ipairs(choices) do
    local check = UI.Check(page, choice[2], function()
      local c = SL.Contract:Get()
      return c and c.needRule == choice[1]
    end, function(value)
      SL.Contract:Edit(function(c)
        c.needRule = value and choice[1] or nil
      end)
    end, L["NEED_TIP_" .. choice[1]])
    check:SetPoint("TOPLEFT", 14, -102 - (i - 1) * 24)
    page.rules[#page.rules + 1] = check
  end
  local boe = UI.Check(page, L.BOE_GREED, function()
    local c = SL.Contract:Get()
    return c and c.boe == "greed"
  end, function(value)
    SL.Contract:Edit(function(c)
      c.boe = value and "greed" or nil
    end)
  end, L.BOE_TIP)
  boe:SetPoint("TOPLEFT", 14, -102 - 3 * 24) -- its own row (beside the long first label it overlapped it)
  page.rules[#page.rules + 1] = boe

  -- Reserves: where the group goes, then [HR/SR] [item] [Loot...] [-> who] [+], then the list ------------------
  local resHeader = UI.Text(page, "header", L.RESERVES_HEADER, "LEFT")
  resHeader:SetPoint("TOPLEFT", 16, -206)
  local dest = UI.Button(page, L.DEST_NONE, 250, function()
    SL.LootPicker:Open(nil)
  end, L.DEST_TITLE, L.DEST_TIP)
  dest:SetPoint("TOPRIGHT", -14, -200)
  page.Dest = dest

  page.kind = "hard"
  local kind = UI.Button(page, "HR", 40, function()
    page.kind = page.kind == "hard" and "soft" or "hard"
    T.Play(page.kind == "soft" and "checkOn" or "checkOff")
    MF:Refresh()
  end, L.KIND_TITLE, function()
    return (page.kind == "soft" and L.GLOSS_SR or L.GLOSS_HR) .. "\n\n" .. L.KIND_SWITCH
  end)
  kind:SetPoint("TOPLEFT", 14, -228)
  page.Kind = kind

  local item = UI.Input(page, 266, L.RESERVE_ITEM, 60)
  item.holder:SetPoint("LEFT", kind, "RIGHT", 6, 0)
  page.ItemBox = item
  item:HookScript("OnTextChanged", function(self)
    -- typing by hand forgets the item picked from the list once the text no longer is its name
    if page.picked and self:GetText() ~= page.picked.name then
      page.picked = nil
    end
  end)
  item:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    MF:AddReserve()
  end)
  -- Shift-click an item link into the box (see MF:OnEnable)
  item:HookScript("OnEditFocusGained", function()
    MF.linkTarget = item
  end)

  local lootButton = UI.Button(page, L.LOOT_BUTTON, 82, function()
    SL.LootPicker:Open(SL.Catalog:Destination())
  end, L.LOOT_BUTTON, L.LOOT_BUTTON_TIP)
  lootButton:SetPoint("LEFT", item.holder, "RIGHT", 6, 0)
  page.LootButton = lootButton

  page.owner = Names.Me() -- who the reserve is for (yourself unless you choose someone)
  local owner = UI.Button(page, "", 128, function(self)
    MF:ChooseOwner(self)
  end, L.RESERVE_FOR, L.OWNER_TIP)
  owner:SetPoint("LEFT", lootButton, "RIGHT", 6, 0)
  page.OwnerButton = owner

  local add = UI.Button(page, "+", 52, function()
    MF:AddReserve()
  end, L.RESERVE_ADD_TIP, L.RESERVE_ADD_BODY)
  add:SetPoint("LEFT", owner, "RIGHT", 6, 0)
  page.AddButton = add

  local resInset = UI.Create("Frame", page, "InsetFrameTemplate")
  resInset:SetPoint("TOPLEFT", 10, -258)
  resInset:SetPoint("TOPRIGHT", -10, -258)
  resInset:SetHeight(92)
  page.ReserveList = makeList(resInset, 18, function(row, data)
    local link = data.reserve.itemID and SL.Catalog:ItemInfo(data.reserve.itemID)
    local shown = link and link.link or T.Paint(data.reserve.item, T.color.white)
    local who = data.reserve.owner and ("  > " .. MF:ColoredName(data.reserve.owner)) or ""
    row.Text:SetText(T.Paint(data.reserve.kind == "soft" and "SR" or "HR", T.color.gold) .. "  " .. shown .. who)
  end, nil, {
    build = function(row)
      local remove = CreateFrame("Button", nil, row)
      remove:SetSize(16, 16)
      remove:SetPoint("RIGHT", -4, 0)
      remove:SetNormalTexture(T.tex.remove)
      remove:SetPushedTexture(T.tex.removeDown)
      remove:SetHighlightTexture(T.tex.removeHighlight, "ADD")
      remove:SetScript("OnClick", function()
        if row.data then
          MF:RemoveReserve(row.data.index)
        end
      end)
      UI.Tooltip(remove, L.RESERVE_REMOVE)
      row.Remove = remove
      row.Text:SetPoint("RIGHT", -26, 0)
    end,
    onEnter = function(row, data)
      if data.reserve.itemID then
        UI.ItemTooltip(row, data.reserve.itemID)
      end
    end,
  })
  page.Reserves = UI.Text(resInset, "small", "", "LEFT") -- empty state
  page.Reserves:SetPoint("TOPLEFT", 10, -8)
  page.Reserves:SetPoint("RIGHT", -10, 0)

  -- Preview of the chat line everyone will read
  local previewHeader = UI.Text(page, "header", L.PREVIEW_HEADER, "LEFT")
  previewHeader:SetPoint("TOPLEFT", 16, -358)
  -- in its own mouse-enabled frame so the items in the line can be hovered and clicked, as in the chat
  local previewFrame = CreateFrame("Frame", nil, page)
  previewFrame:SetPoint("TOPLEFT", 16, -374)
  previewFrame:SetPoint("TOPRIGHT", -16, -374)
  previewFrame:SetHeight(42)
  previewFrame:EnableMouse(true)
  UI.EnableLinks(previewFrame)
  local preview = UI.Text(previewFrame, "small", "", "LEFT")
  preview:SetAllPoints()
  preview:SetJustifyV("TOP")
  if preview.SetMaxLines then
    preview:SetMaxLines(3)
  end
  page.Preview = preview
  page.PreviewFrame = previewFrame

  local publish = UI.Button(page, L.PUBLISH, 180, function()
    SL.Contract:Publish()
    MF:Refresh()
  end, L.PUBLISH, L.PUBLISH_TIP .. "\n\n" .. L.CONTRACT_TIP)
  publish:SetPoint("BOTTOMLEFT", 14, 14)
  page.Publish = publish
  local clear = UI.Button(page, L.CLEAR_RESERVES, 140, function()
    SL.Contract:Edit(function(c)
      c.reserves = {}
    end)
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
end

local SOURCE_TEXT = { auto = "SOURCE_AUTO", copied = "SOURCE_COPIED", proposed = "SOURCE_PROPOSED", received = "SOURCE_RECEIVED" }

local function refreshContractTab(page)
  local c = SL.Contract:Get()
  page.Status:SetText("|T" .. (c and T.tex.ok or T.tex.wait) .. ":16:16|t " .. L.CONTRACT_CURRENT .. " " .. SL.Contract:ShortSummary(c))
  local sourceKey = c and (c.source == "proposed" and not c.publishedAt and "SOURCE_DRAFT" or SOURCE_TEXT[c.source]) or nil
  page.Source:SetText(c and (L[sourceKey or "SOURCE_AUTO"] .. " · " .. UI.FormatDate(c.publishedAt or c.createdAt)) or L.CONTRACT_NONE_HINT)
  page.Game:SetText(API.InGroup() and (T.Paint(L.GAME_NOW, T.color.gold) .. " " .. SL.Contract:GameStateLine()) or "")
  local names = {}
  if c and c.accepted then
    for name, t in pairs(c.accepted) do
      names[#names + 1] = "|T" .. T.tex.ok .. ":12:12|t " .. name .. " " .. (date and date("%H:%M", t) or "")
    end
    table.sort(names) -- same order every time the tab refreshes
  end
  if c and c.publishedAt then
    page.Accepted:SetText(#names > 0 and (L.ACCEPTED_BY .. " " .. table.concat(names, "   ")) or L.ACCEPTED_NONE)
  else
    page.Accepted:SetText("")
  end
  local rows = {}
  for i, reserve in ipairs(c and c.reserves or {}) do
    rows[#rows + 1] = { reserve = reserve, index = i }
  end
  page.ReserveList:Set(rows)
  page.Reserves:SetText(#rows == 0 and T.Paint(L.RESERVES_NONE, T.color.gray) or "")
  local inst = SL.Catalog:Instance(SL.Catalog:Destination())
  page.Dest:SetText(inst and string.format(L.DEST_FMT, inst.name) or L.DEST_NONE)
  if page.owner and not Names.IsMe(page.owner) then
    local present = false
    for _, member in ipairs(API.GroupMembers()) do
      present = present or Names.Same(member.name, page.owner)
    end
    if not present then
      page.owner = Names.Me() -- that player left the group
    end
  end
  page.Kind:SetText(page.kind == "soft" and "SR" or "HR")
  page.OwnerButton:SetText("> " .. (page.owner or L.OWNER_NOBODY))
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

-- Reserve editing -------------------------------------------------------------------------------------------------
function MF:ColoredName(name)
  for _, member in ipairs(API.GroupMembers()) do
    if Names.Same(member.name, name) then
      local color = API.ClassColor(member.class)
      if color then
        return "|c" .. (color.colorStr or T.Hex(color)) .. name .. "|r"
      end
    end
  end
  return T.Paint(name, T.color.white)
end

-- An item chosen in the loot picker or shift-clicked: its name goes in the box and its ID is remembered.
function MF:PickItem(picked)
  if not self.frame or type(picked) ~= "table" or type(picked.name) ~= "string" then
    return
  end
  local page = self.pages.contract
  page.picked = picked
  page.ItemBox:SetText(picked.name)
  page.ItemBox.Refresh()
  if self.tab ~= "contract" or not self.frame:IsShown() then
    self:Open("contract")
  end
  self:Refresh()
end

function MF:AddReserve()
  local page = self.pages.contract
  local text = Rules.Clean(page.ItemBox:GetText() or "", 80)
  if not text then
    return
  end
  local name = text:match("^%[(.-)%]$") or text
  local picked = page.picked
  local itemID = picked and picked.name == name and picked.id or SL.Catalog:FindItemID(SL.Catalog:Destination(), name)
  local reserve = { item = name, itemID = itemID, owner = page.owner and Names.Short(page.owner) or nil, kind = page.kind }
  SL.Contract:Edit(function(c)
    Rules.Apply(c, { reserves = { reserve } })
  end)
  page.picked = nil
  page.ItemBox:SetText("")
  page.ItemBox.Refresh()
  T.Play("checkOn")
end

function MF:RemoveReserve(index)
  local c = SL.Contract:Get()
  if not c or not c.reserves or not c.reserves[index] then
    return
  end
  SL.Contract:Edit(function(contract)
    table.remove(contract.reserves, index)
  end)
  T.Play("checkOff")
end

-- Who the reserve is for: a menu with your group (the game's own menu); without it, each click picks the next one.
function MF:OwnerChoices()
  local list = {}
  for _, member in ipairs(API.GroupMembers()) do
    list[#list + 1] = member.name
  end
  if #list == 0 then
    list[1] = Names.Me()
  end
  return list
end

function MF:ChooseOwner(button)
  local page = self.pages.contract
  local choices = self:OwnerChoices()
  local function choose(name)
    page.owner = name
    MF:Refresh()
  end
  if MenuUtil and MenuUtil.CreateContextMenu then
    local ok = pcall(MenuUtil.CreateContextMenu, button, function(_, root)
      root:CreateTitle(L.RESERVE_FOR)
      for _, name in ipairs(choices) do
        root:CreateButton(MF:ColoredName(name), function()
          choose(name)
        end)
      end
      root:CreateButton(T.Paint(L.OWNER_NOBODY, T.color.gray), function()
        choose(nil)
      end)
      if #choices > 20 and root.SetScrollMode then
        root:SetScrollMode(420)
      end
    end)
    if ok then
      return
    end
  end
  local nextIndex = 1
  for i, name in ipairs(choices) do
    if page.owner and Names.Same(name, page.owner) then
      nextIndex = i + 1
    end
  end
  choose(choices[nextIndex]) -- past the last one: nobody
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
    for _, drop in ipairs(SL.Run.SortedDrops(run)) do
      items[#items + 1] = { text = "   " .. (date and drop.t and (date("%H:%M", drop.t) .. "  ") or "") .. string.format(L.SUMMARY_DROP, drop.item or "?", drop.winner) }
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

-- Tab 3: Players -> UI/PlayersTab.lua
MF.PlayerList = function(filter)
  return (SL.PlayersTab.List("all", filter))
end

-- Opens the card of a player (from a menu, a toast...).
function MF:OpenPlayer(name)
  local short = Names.Short(name)
  self:Open("players")
  if not short or not self.frame then
    return
  end
  local page = self.pages.players
  page.category = "all"
  page.Search:SetText(SL.db.players[short] and "" or short)
  page.Search.Refresh()
  page.selected = SL.db.players[short] and short or nil
  for _, entry in ipairs(SL.PlayersTab.All()) do
    if entry.name == short then
      page.Search:SetText("")
      page.Search.Refresh()
      page.selected = short
    end
  end
  self:Refresh()
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
    { "settings", L.CMD_SETTINGS }, { "minimap", L.CMD_MINIMAP }, { "reset", L.CMD_RESET }, { "exceptions", L.CMD_RESET_EXCEPTIONS } }) do
    line(T.Paint("/safeloot " .. cmd[1], T.color.white) .. " — " .. cmd[2])
  end
  head(L.HELP_LOOT_TITLE)
  line(L.HELP_LOOT)
  if SL.Catalog.index.credit then
    line(T.Paint(string.format(L.LOOT_CREDIT, SL.Catalog.index.credit), T.color.gray))
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
    if SL.LootPicker then
      SL.LootPicker:Hide()
    end
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
    if i == 1 then
      -- seen in the real client: without this anchor no tab is drawn (Blizzard only chains tabs 2..n)
      tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
    end
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
  SL.PlayersTab.Build(self.pages.players)
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
  self.fresh = true -- a tab just opened starts at the top; a refresh stays where it was
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
    self.pages.journal.List:Set(journalItems(), self.fresh)
  elseif self.tab == "players" then
    SL.PlayersTab.Refresh(self.pages.players)
  elseif self.tab == "help" then
    self.pages.help.List:Set(helpItems(), self.fresh)
  end
  self.fresh = nil
end

function MF:OnEnable()
  -- each message only redraws the tab that shows it (while items load, CATALOG_CHANGED comes three times a second)
  local function refreshIf(...)
    local tabs = {}
    for _, key in ipairs({ ... }) do
      tabs[key] = true
    end
    return function()
      if tabs[MF.tab] then
        MF:Refresh()
      end
    end
  end
  SL:On("CONTRACT_CHANGED", self, refreshIf("contract", "journal"))
  SL:On("MEMORY_CHANGED", self, refreshIf("players"))
  SL:On("RUN_FINISHED", self, refreshIf("journal", "players"))
  SL:On("CATALOG_CHANGED", self, refreshIf("contract"))
  -- Shift-click an item into the reserve box while it has the focus
  API.HookInsertLink(function(link)
    local box = MF.linkTarget
    if not box or not box:HasFocus() or type(link) ~= "string" or API.IsSecret(link) then
      return
    end
    local name = link:match("|h%[(.-)%]|h") or link:match("%[(.-)%]")
    if SL.Diagnostics then
      SL.Diagnostics:Observe("insert_link", { item = API.ItemIDFromLink(link) ~= nil })
    end
    if name then
      MF:PickItem({ id = API.ItemIDFromLink(link), name = name, link = link })
    end
  end)
  SL:RegisterCommand("rules", function()
    MF:Open("contract")
  end, L.CMD_CONTRACT, { "reglas", "contrato" })
  SL:RegisterCommand("players", function()
    MF:Open("players")
  end, L.CMD_PLAYERS, { "jugadores" })
  SL:RegisterCommand("journal", function()
    MF:Open("journal")
  end, L.CMD_JOURNAL, { "diario" })
  SL:RegisterCommand("reset", function()
    UI.ResetPositions()
    SL:Print(L.POSITIONS_RESET)
  end, L.CMD_RESET, { "colocar" })
  SL:RegisterCommand("help", function()
    MF:Open("help")
  end, L.CMD_HELP, { "ayuda" })
end
