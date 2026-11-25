-- Loot picker: choose the dungeon or raid, then the item from each boss's loot, instead of typing its name.
-- Opens beside the main window (the side with room). Built on first use, never in combat.
local _, SL = ...
local LP = SL:NewModule("LootPicker")
SL.LootPicker = LP
local Book, Rules, UI, T, L = SL.LootBook, SL.Rules, SL.UI, SL.Theme, SL.L

local WIDTH, HEIGHT = 340, 520
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

local function matches(text, filter)
  return not filter or (type(text) == "string" and Rules.Normalize(text):find(filter, 1, true) ~= nil)
end

-- Instances view -------------------------------------------------------------------------------------------------
local function instanceRows(filter)
  local rows = {}
  local here, dest = SL.Catalog:Here(), SL.Catalog:Destination()
  local section
  for _, inst in ipairs(SL.Catalog:Instances()) do
    local total, seen = SL.Catalog:Totals(inst.id)
    -- content that is in the game data but not open in Forever is only listed when it concerns you
    local shown = inst.live or inst.id == here or inst.id == dest or seen > 0
    if shown and matches(inst.name, filter) then
      local wanted = inst.raid and "raid" or "dungeon"
      if section ~= wanted then
        section = wanted
        rows[#rows + 1] = { kind = "head", text = inst.raid and L.PICKER_RAIDS or L.PICKER_DUNGEONS }
      end
      rows[#rows + 1] = { kind = "instance", inst = inst, here = inst.id == here, dest = inst.id == dest,
        known = total }
    end
  end
  return rows
end

-- Loot view: every boss in order with the items known for it ----------------------------------------------------
local QUALITY_ORDER = function(a, b)
  if a.seen ~= b.seen then
    return a.seen -- what really dropped in Forever first
  end
  local qa, qb = a.info and a.info.quality or -1, b.info and b.info.quality or -1
  if qa ~= qb then
    return qa > qb
  end
  local na, nb = a.info and a.info.name or "~", b.info and b.info.name or "~"
  if na ~= nb then
    return Rules.Normalize(na) < Rules.Normalize(nb)
  end
  return a.id < b.id
end

local function itemRows(mapID, bossKey, filter)
  local rows = {}
  for _, entry in ipairs(SL.Catalog:Items(mapID, bossKey)) do
    if not filter or (entry.info and matches(entry.info.name, filter)) then
      rows[#rows + 1] = { kind = "item", id = entry.id, info = entry.info, seen = entry.seen }
    end
  end
  table.sort(rows, QUALITY_ORDER)
  return rows
end

local function lootRows(mapID, filter)
  local rows = {}
  local inst = SL.Catalog:Instance(mapID)
  if not inst then
    return rows
  end
  for _, boss in ipairs(inst.bosses) do
    local bossMatch = filter and matches(boss.name, filter)
    local items = itemRows(mapID, boss.key, (not bossMatch) and filter or nil)
    if not filter or bossMatch or #items > 0 then
      rows[#rows + 1] = { kind = "boss", boss = boss }
      if #items == 0 then
        rows[#rows + 1] = { kind = "empty" }
      end
      for _, row in ipairs(items) do
        rows[#rows + 1] = row
      end
    end
  end
  local other = itemRows(mapID, Book.OTHER, filter)
  if #other > 0 then
    rows[#rows + 1] = { kind = "head", text = L.PICKER_OTHER }
    for _, row in ipairs(other) do
      rows[#rows + 1] = row
    end
  end
  if #rows == 0 then
    rows[1] = { kind = "empty", text = L.PICKER_NO_MATCH }
  end
  return rows
end

-- Rows -------------------------------------------------------------------------------------------------------------
function LP:InitRow(row, data)
  local text
  if data.kind == "head" then
    text = T.Paint(data.text, T.color.gold)
  elseif data.kind == "instance" then
    local inst = data.inst
    local size = ""
    if inst.raid and (inst.size or 0) > 0 then
      size = T.Paint(" (" .. inst.size .. ")", T.color.gray)
    elseif (inst.min or 0) > 0 then
      size = T.Paint(" " .. (inst.min == inst.max and inst.min or (inst.min .. "-" .. inst.max)), T.color.gray)
    end
    local flags = ""
    if data.here then
      flags = flags .. "  " .. T.Paint(L.PICKER_HERE, T.color.green)
    end
    if data.dest then
      flags = flags .. "  " .. T.Paint(L.PICKER_DEST, T.color.gold)
    end
    local known = data.known > 0 and T.Paint("  · " .. string.format(L.PICKER_KNOWN, data.known), T.color.gray) or ""
    text = (data.dest and T.Paint("» ", T.color.gold) or "   ") .. T.Paint(inst.name, T.color.white) .. size .. flags .. known
  elseif data.kind == "boss" then
    text = "|T" .. SKULL .. ":14:14|t " .. T.Paint(data.boss.name, T.color.gold)
  elseif data.kind == "item" then
    local info = data.info
    if info and info.name then
      text = "      |T" .. (info.icon or QUESTION) .. ":16:16|t " .. (info.link or info.name)
        .. (data.seen and "" or ("  " .. T.Paint(L.PICKER_UNSEEN, T.color.gray)))
    else
      text = "      |T" .. ((info and info.icon) or QUESTION) .. ":16:16|t " .. T.Paint(L.PICKER_LOADING, T.color.gray)
    end
  else
    text = "      " .. T.Paint(data.text or L.PICKER_BOSS_EMPTY, T.color.gray)
  end
  row.Text:SetText(text)
end

function LP:OnRowClick(data, mouse)
  if data.kind == "instance" then
    T.Play("tab")
    SL.Contract:SetDestination(data.inst.id)
    self:ShowLoot(data.inst.id)
  elseif data.kind == "item" then
    local info = data.info or SL.Catalog:ItemInfo(data.id)
    local link = info and info.link
    -- the game's own modified clicks keep working: Shift = link in chat, Ctrl = dressing room
    if link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
      if pcall(HandleModifiedItemClick, link) then
        return
      end
    end
    if not (info and info.name) then
      return -- still loading: nothing to put in the box yet
    end
    T.Play("checkOn")
    SL.MainFrame:PickItem({ id = data.id, name = info.name, link = link })
    self:Hide()
  end
end

function LP:OnRowEnter(row, data)
  if data.kind == "item" then
    UI.ItemTooltip(row, data.id, data.info and data.info.link)
    if not data.seen and GameTooltip and GameTooltip.AddLine then
      GameTooltip:AddLine(L.PICKER_UNSEEN_TIP, T.color.gray.r, T.color.gray.g, T.color.gray.b, true)
      GameTooltip:Show()
    end
  elseif data.kind == "instance" and GameTooltip then
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(data.inst.name, T.color.gold.r, T.color.gold.g, T.color.gold.b)
    GameTooltip:AddLine(string.format(L.PICKER_BOSSES, #data.inst.bosses), 1, 1, 1)
    GameTooltip:AddLine(data.known > 0 and string.format(L.PICKER_KNOWN, data.known) or L.PICKER_NONE_YET,
      T.color.gray.r, T.color.gray.g, T.color.gray.b, true)
    GameTooltip:Show()
  end
end

-- Window -----------------------------------------------------------------------------------------------------------
function LP:Build()
  local f = UI.Card(UIParent, WIDTH, HEIGHT, "SafeLootLootPicker")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetScale(SL.settings.scale or 1)
  f:Hide()
  if UISpecialFrames then
    table.insert(UISpecialFrames, "SafeLootLootPicker")
  end
  f.Title = UI.Text(f, "header", L.PICKER_TITLE, "LEFT")
  f.Title:SetPoint("TOPLEFT", 20, -20)
  f.Title:SetPoint("TOPRIGHT", -36, -20)
  f.Title:SetWordWrap(false)
  local close = UI.Create("Button", f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)
  f.Close = close

  f.Back = UI.Button(f, "< " .. L.PICKER_BACK, 92, function()
    T.Play("tab")
    LP:ShowInstances()
  end, L.PICKER_BACK, L.PICKER_BACK_TIP)
  f.Back:SetPoint("TOPLEFT", 16, -44)

  f.Search = UI.Input(f, 200, L.PICKER_SEARCH, 40)
  f.Search.holder:SetPoint("TOPRIGHT", -16, -43)
  f.Search:HookScript("OnTextChanged", function()
    LP:Refresh()
  end)

  local inset = UI.Create("Frame", f, "InsetFrameTemplate")
  inset:SetPoint("TOPLEFT", 12, -74)
  inset:SetPoint("BOTTOMRIGHT", -12, 76)
  f.List = UI.List(inset, 20, function(row, data)
    LP:InitRow(row, data)
  end, function(data, mouse)
    LP:OnRowClick(data, mouse)
  end, {
    onEnter = function(row, data)
      LP:OnRowEnter(row, data)
    end,
  })

  f.Hint = UI.Text(f, "muted", L.PICKER_HINT, "LEFT")
  f.Hint:SetPoint("BOTTOMLEFT", 18, 16)
  f.Hint:SetPoint("BOTTOMRIGHT", -18, 16)
  f.Hint:SetHeight(56)
  f.Hint:SetJustifyV("TOP")
  self.frame = f
  UI.Movable(f, "picker", LP.Beside)
end

-- Beside the main window, on the side with room.
function LP:Place()
  self.frame:RestorePosition() -- where you left it, or beside the main window
end

local function beside(f)
  local main = SL.MainFrame.frame
  if not (main and main:IsShown()) then
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    return
  end
  local right = main:GetRight()
  local screen = UIParent:GetRight()
  local scale = (main:GetEffectiveScale() or 1)
  local fits = not (right and screen) or (right * scale + WIDTH * (f:GetEffectiveScale() or 1)) <= screen * (UIParent:GetEffectiveScale() or 1)
  if fits then
    f:SetPoint("TOPLEFT", main, "TOPRIGHT", 2, 0)
  else
    f:SetPoint("TOPRIGHT", main, "TOPLEFT", -2, 0)
  end
end
LP.Beside = beside

function LP:Open(mapID)
  if SL:InCombat() and not self.frame then
    SL:AfterCombat("lootpicker-open", function()
      LP:Open(mapID)
    end)
    return
  end
  if not self.frame then
    self:Build()
  end
  self:Place()
  self.frame.Search:SetText("")
  if mapID and SL.Catalog:Instance(mapID) then
    self:ShowLoot(mapID)
  else
    self:ShowInstances()
  end
  if not self.frame:IsShown() then
    T.Play("open")
  end
  self.frame:Show()
end

function LP:Hide()
  if self.frame then
    self.frame:Hide()
  end
end

function LP:ShowInstances()
  self.view, self.mapID = "instances", nil
  local f = self.frame
  f.Back:Hide()
  f.Title:SetText(L.PICKER_INSTANCES)
  f.Hint:SetText(L.PICKER_HINT)
  f.Search.Hint:SetText(L.PICKER_SEARCH_INST)
  f.Search:SetText("")
  f.Search.Refresh()
  self:Refresh()
end

function LP:ShowLoot(mapID)
  local inst = SL.Catalog:Instance(mapID)
  if not inst then
    return self:ShowInstances()
  end
  self.view, self.mapID = "loot", mapID
  local f = self.frame
  f.Back:Show()
  f.Title:SetText(inst.name)
  f.Search.Hint:SetText(L.PICKER_SEARCH)
  f.Search:SetText("")
  f.Search.Refresh()
  local total, seen = SL.Catalog:Totals(mapID)
  f.Hint:SetText(total > seen and L.PICKER_HINT_UNSEEN or L.PICKER_HINT)
  SL.Catalog:Ask(mapID)
  self:Refresh()
end

function LP:Refresh()
  local f = self.frame
  if not f then
    return
  end
  local typed = f.Search:GetText() or ""
  local filter = typed ~= "" and Rules.Normalize(typed) or nil
  if self.view == "loot" and self.mapID then
    f.List:Set(lootRows(self.mapID, filter))
  else
    f.List:Set(instanceRows(filter))
  end
end

function LP:OnEnable()
  local function refresh()
    if LP.frame and LP.frame:IsShown() then
      LP:Refresh()
    end
  end
  SL:On("CATALOG_CHANGED", self, refresh)
  SL:On("CONTRACT_CHANGED", self, refresh)
  SL:On("SETTING_CHANGED", self, function(_, key)
    if key == "scale" and LP.frame then
      LP.frame:SetScale(SL.settings.scale or 1)
    end
  end)
end
