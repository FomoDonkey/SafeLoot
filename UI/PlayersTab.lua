-- Players tab (0.5.0): an address book in three panes. Left: categories with icon and number. Middle: the players of
-- the category, two lines each. Right: the card of the chosen one (opinion, notes). Searching looks in all categories.
local _, SL = ...
local PT = {}
SL.PlayersTab = PT
local API, Rules, Memory, Names, UI, T, L = SL.API, SL.Rules, SL.Memory, SL.Names, SL.UI, SL.Theme, SL.L

local SIDEBAR = { "all", "group", "ninja", "extortion", "quitter", "warned", "trusted", "noted", "seen" }
local SORTS = { "recent", "name", "times" }

-- Data ---------------------------------------------------------------------------------------------------------------
-- Everyone you grouped with recently (your current group included), with or without notes.
local function recentPlayers()
  local recent = {}
  local function add(name, class, inGroup, last)
    local short = Names.Short(name)
    if not short or Names.IsMe(short) then
      return
    end
    local entry = recent[short] or { last = 0 }
    entry.class = entry.class or (type(class) == "string" and class or nil)
    entry.inGroup = entry.inGroup or inGroup or false
    entry.last = math.max(entry.last, last or 0)
    recent[short] = entry
  end
  for _, member in ipairs(API.GroupMembers()) do
    add(member.name, member.class, true, API.Now())
  end
  local current = SL.Run:Current()
  if current then
    for name, class in pairs(current.members or {}) do
      add(name, class, false, current.startedAt)
    end
  end
  for i = #SL.db.runs, math.max(1, #SL.db.runs - 15), -1 do
    local run = SL.db.runs[i]
    for name, class in pairs(run.members or {}) do
      add(name, class, false, run.endedAt or run.startedAt)
    end
  end
  return recent
end

-- Names without accents or capitals, for searching and sorting: worked out once per name (with 2000 players, sorting
-- A-Z used to work it out 40000 times).
local folded, foldedCount = {}, 0
local function fold(name)
  local f = folded[name]
  if not f then
    if foldedCount >= 5000 then
      folded, foldedCount = {}, 0
    end
    f = Rules.Normalize(name)
    folded[name] = f
    foldedCount = foldedCount + 1
  end
  return f
end

local NOTHING = Memory.Summary(nil)

-- Every known player: { name, record, summary, category, inGroup }, unsorted.
function PT.All()
  local now, days = API.Now(), SL.settings.memoryDays
  local list, byName = {}, {}
  for name, record in pairs(SL.db.players) do
    local entry = { name = name, record = record, summary = record.events[1] and Memory.Summary(record, now, days) or NOTHING }
    list[#list + 1] = entry
    byName[name] = entry
  end
  for name, info in pairs(recentPlayers()) do
    local entry = byName[name]
    if entry then
      entry.inGroup = info.inGroup
      entry.record.class = entry.record.class or info.class
    else
      list[#list + 1] = {
        name = name, record = { class = info.class, events = {}, last = info.last }, summary = NOTHING,
        recent = true, inGroup = info.inGroup,
      }
    end
  end
  for _, entry in ipairs(list) do
    entry.category = Memory.Category(entry.record, now, days)
  end
  return list
end

local SORT = {
  recent = function(a, b)
    return (a.record.last or 0) > (b.record.last or 0)
  end,
  name = function(a, b)
    return fold(a.name) < fold(b.name)
  end,
  times = function(a, b)
    if (a.record.seen or 0) ~= (b.record.seen or 0) then
      return (a.record.seen or 0) > (b.record.seen or 0)
    end
    return (a.record.last or 0) > (b.record.last or 0)
  end,
}

-- list for a category and a search text (a search looks everywhere), plus the number of players of each category.
function PT.List(category, filter)
  local all = PT.All()
  local counts = { all = #all, group = 0 }
  local f = filter and filter ~= "" and Rules.Normalize(filter) or nil
  local list = {}
  for _, entry in ipairs(all) do
    counts[entry.category] = (counts[entry.category] or 0) + 1
    if entry.inGroup then
      counts.group = counts.group + 1
    end
    local wanted
    if f then
      wanted = fold(entry.name):find(f, 1, true) ~= nil
    else
      wanted = category == nil or category == "all" or (category == "group" and entry.inGroup) or entry.category == category
    end
    if wanted then
      list[#list + 1] = entry
    end
  end
  local compare = SORT[SL.settings.playerSort] or SORT.recent
  table.sort(list, function(a, b)
    local ga, gb = a.inGroup and 1 or 0, b.inGroup and 1 or 0
    if ga ~= gb then
      return ga > gb -- your group first, always
    end
    return compare(a, b)
  end)
  return list, counts
end

-- Pieces --------------------------------------------------------------------------------------------------------------
local function classText(class, size)
  if type(class) ~= "string" or not class:match("^%u+$") then
    return ""
  end
  local atlas = "classicon-" .. class:lower()
  if C_Texture and C_Texture.GetAtlasInfo then
    local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
    if not ok or not info then
      return ""
    end
  end
  return "|A:" .. atlas .. ":" .. size .. ":" .. size .. "|a "
end

local function coloredName(name, class)
  local color = API.ClassColor(class)
  return color and ("|c" .. (color.colorStr or T.Hex(color)) .. name .. "|r") or T.Paint(name, T.color.white)
end

local ago = UI.Ago

local function togetherText(record)
  local n = record.seen or 0
  if n == 0 then
    return nil
  end
  return n == 1 and L.TOGETHER_ONE or string.format(L.TOGETHER_N, n)
end

-- One category of the sidebar: icon, word and number; the chosen one is lit and marked.
local function sideButton(parent, page, key, y)
  local b = CreateFrame("Button", nil, parent)
  b:SetPoint("TOPLEFT", 6, y)
  b:SetPoint("TOPRIGHT", -6, y)
  b:SetHeight(26)
  b.Lit = b:CreateTexture(nil, "BACKGROUND")
  b.Lit:SetAllPoints()
  b.Lit:SetColorTexture(1, 0.82, 0, 0.16)
  b.Mark = b:CreateTexture(nil, "ARTWORK")
  b.Mark:SetPoint("TOPLEFT", 0, 0)
  b.Mark:SetPoint("BOTTOMLEFT", 0, 0)
  b.Mark:SetWidth(3)
  b.Mark:SetColorTexture(1, 0.82, 0, 1)
  b.Over = b:CreateTexture(nil, "HIGHLIGHT")
  b.Over:SetAllPoints()
  b.Over:SetColorTexture(1, 1, 1, 0.07)
  b.Count = UI.Text(b, "small", "", "RIGHT")
  b.Count:SetPoint("RIGHT", -6, 0)
  b.Text = UI.Text(b, "small", "", "LEFT")
  b.Text:SetPoint("LEFT", 8, 0)
  b.Text:SetPoint("RIGHT", b.Count, "LEFT", -4, 0)
  b.Text:SetWordWrap(false)
  b:SetScript("OnClick", function()
    T.Play("tab")
    page.category = key
    page.Search:SetText("")
    page.Search.Refresh()
    SL.MainFrame:Refresh()
  end)
  UI.Tooltip(b, L["CAT_" .. string.upper(key)], L["CAT_TIP_" .. string.upper(key)])
  b.key = key
  return b
end

function PT.Build(page)
  page.category = "all"

  -- left: categories
  local side = UI.Create("Frame", page, "InsetFrameTemplate")
  side:SetPoint("TOPLEFT", 8, -10)
  side:SetPoint("BOTTOMLEFT", 8, 10)
  side:SetWidth(142)
  page.side = {}
  local y = -6
  for i, key in ipairs(SIDEBAR) do
    page.side[key] = sideButton(side, page, key, y)
    y = y - 27
    if i == 2 or key == "warned" then
      local line = side:CreateTexture(nil, "ARTWORK")
      line:SetPoint("TOPLEFT", 10, y - 2)
      line:SetPoint("TOPRIGHT", -10, y - 2)
      line:SetHeight(1)
      line:SetColorTexture(1, 0.82, 0, 0.25)
      y = y - 6
    end
  end

  -- middle: search, order, list
  local search = UI.Input(page, 162, L.SEARCH, 48)
  search.holder:SetPoint("TOPLEFT", 158, -12)
  search:HookScript("OnTextChanged", function()
    -- typing decides who the buttons act on: that player if known, otherwise the typed name (never the player
    -- that happened to be selected before: that was the real-client bug)
    local typed = Rules.Clean(search:GetText() or "", 48)
    local short = typed and Names.Short(typed)
    page.selected = (short and SL.db.players[short]) and short or nil
    SL.MainFrame:Refresh()
  end)
  page.Search = search
  page.Sort = UI.Button(page, L.SORT_RECENT, 86, function()
    local current = 1
    for i, key in ipairs(SORTS) do
      if key == SL.settings.playerSort then
        current = i
      end
    end
    SL.settings.playerSort = SORTS[current % #SORTS + 1]
    SL.MainFrame:Refresh()
  end, L.SORT_TITLE, L.SORT_TIP)
  page.Sort:SetPoint("LEFT", search.holder, "RIGHT", 6, 0)

  local inset = UI.Create("Frame", page, "InsetFrameTemplate")
  inset:SetPoint("TOPLEFT", 156, -44)
  inset:SetPoint("BOTTOMLEFT", 156, 10)
  inset:SetWidth(262)
  page.List = UI.List(inset, 40, function(row, data)
    local c = T.category[data.category] or T.category.seen
    row.Bar:SetColorTexture(c.color.r, c.color.g, c.color.b, data.category == "seen" and 0.25 or 1)
    row.Lit:SetShown(page.selected == data.name)
    row.Text:SetText(classText(data.record.class, 16) .. coloredName(data.name, data.record.class))
    row.Tag:SetText(data.category ~= "seen" and SL.Players:Label(data.category, 13) or "")
    local latest = data.summary.latest or data.summary.latestAny
    local sub = {}
    if data.inGroup then
      sub[#sub + 1] = T.Paint(L.IN_GROUP_NOW, T.color.green)
    end
    if latest then
      sub[#sub + 1] = SL.MemoryHooks.ShortEvent(latest)
    else
      sub[#sub + 1] = togetherText(data.record)
    end
    if not data.inGroup then
      sub[#sub + 1] = ago(data.record.last)
    end
    row.Sub:SetText(T.Paint(table.concat(sub, " · "), T.color.gray))
  end, function(data, mouse, row)
    page.selected = data.name
    if mouse == "RightButton" and MenuUtil and MenuUtil.CreateContextMenu then
      pcall(MenuUtil.CreateContextMenu, row, function(_, root)
        root:CreateTitle(data.name)
        SL.Players:FillMenu(root, data.name)
      end)
    end
    SL.MainFrame:Refresh()
  end, {
    build = function(row)
      row.Lit = row:CreateTexture(nil, "BACKGROUND")
      row.Lit:SetAllPoints()
      row.Lit:SetColorTexture(1, 0.82, 0, 0.14)
      row.Bar = row:CreateTexture(nil, "ARTWORK")
      row.Bar:SetPoint("TOPLEFT", 0, -2)
      row.Bar:SetPoint("BOTTOMLEFT", 0, 2)
      row.Bar:SetWidth(4)
      row.Tag = UI.Text(row, "small", "", "RIGHT")
      row.Tag:SetPoint("TOPRIGHT", -6, -5)
      row.Text:ClearAllPoints()
      row.Text:SetPoint("TOPLEFT", 10, -4)
      row.Text:SetPoint("RIGHT", row.Tag, "LEFT", -4, 0)
      row.Sub = UI.Text(row, "small", "", "LEFT")
      row.Sub:SetPoint("BOTTOMLEFT", 10, 5)
      row.Sub:SetPoint("BOTTOMRIGHT", -6, 5)
      row.Sub:SetWordWrap(false)
    end,
  })
  page.Empty = UI.Text(inset, "small", "", "CENTER")
  page.Empty:SetPoint("TOPLEFT", 16, -24)
  page.Empty:SetPoint("TOPRIGHT", -24, -24)

  -- right: the card
  local card = UI.Create("Frame", page, "InsetFrameTemplate")
  card:SetPoint("TOPLEFT", 424, -10)
  card:SetPoint("BOTTOMRIGHT", -8, 10)
  page.Card = card
  page.Name = UI.Text(card, "title", "", "LEFT")
  page.Name:SetPoint("TOPLEFT", 10, -10)
  page.Name:SetPoint("TOPRIGHT", -8, -10)
  page.Name:SetWordWrap(false)
  page.Badge = UI.Text(card, "header", "", "LEFT")
  page.Badge:SetPoint("TOPLEFT", 10, -32)
  page.Badge:SetPoint("TOPRIGHT", -8, -32)
  page.Badge:SetWordWrap(false)
  page.Detail = UI.Text(card, "small", "", "LEFT")
  page.Detail:SetPoint("TOPLEFT", 10, -50)
  page.Detail:SetPoint("TOPRIGHT", -8, -50)
  page.Detail:SetJustifyV("TOP")
  if page.Detail.SetMaxLines then
    page.Detail:SetMaxLines(3)
  end

  local function target()
    if page.selected then
      return page.selected
    end
    local typed = Rules.Clean(page.Search:GetText() or "", 48)
    return typed and Names.Short(typed) or nil
  end
  page.Target = target

  page.Opinion = UI.Text(card, "header", L.OPINION, "LEFT")
  page.Opinion:SetPoint("TOPLEFT", 10, -84)
  page.tagButtons = {}
  for i, kind in ipairs(SL.Players.TAGS) do
    local b = UI.Button(card, "", 92, function()
      local name = target()
      if name then
        SL.Players:Tag(name, kind, true)
        page.selected = Names.Short(name)
        SL.MainFrame:Refresh()
      end
    end, L["CAT_" .. string.upper(Memory.TAG_CATEGORY[kind])], L.TAG_TIP)
    b:SetPoint("TOPLEFT", 8 + ((i - 1) % 2) * 94, -100 - math.floor((i - 1) / 2) * 27)
    if b.SetNormalFontObject and GameFontNormalSmall then
      b:SetNormalFontObject("GameFontNormalSmall")
      b:SetHighlightFontObject("GameFontHighlightSmall")
      b:SetDisabledFontObject("GameFontDisableSmall")
    end
    b.kind = kind
    page.tagButtons[i] = b
  end

  page.NotesTitle = UI.Text(card, "header", L.NOTES_TITLE, "LEFT")
  page.NotesTitle:SetPoint("TOPLEFT", 10, -160)
  local notes = UI.Create("Frame", card, "InsetFrameTemplate")
  notes:SetPoint("TOPLEFT", 6, -176)
  notes:SetPoint("BOTTOMRIGHT", -6, 72)
  -- Each row: what you wrote (or your mark, or what the addon saw) on up to two lines, and when in grey under it.
  -- Hovering shows it whole, with the exact date and the place.
  page.Notes = UI.List(notes, (SL.settings and SL.settings.largeText) and 56 or 46, function(row, data)
    row.Text:SetText(data.text)
    row.When:SetText(data.when and data.when ~= "" and T.Paint(data.when, T.color.gray) or "")
    row.Remove:SetShown(data.index ~= nil)
  end, nil, {
    build = function(row)
      row.Text:ClearAllPoints()
      row.Text:SetPoint("TOPLEFT", 4, -4)
      row.Text:SetPoint("TOPRIGHT", -20, -4)
      row.Text:SetWordWrap(true)
      row.Text:SetJustifyV("TOP")
      if row.Text.SetMaxLines then
        row.Text:SetMaxLines(2)
      end
      row.When = UI.Text(row, "small", "", "LEFT")
      row.When:SetPoint("TOPLEFT", row.Text, "BOTTOMLEFT", 0, -2)
      row.When:SetPoint("TOPRIGHT", row.Text, "BOTTOMRIGHT", 0, -2)
      row.When:SetWordWrap(false)
      local remove = CreateFrame("Button", nil, row)
      remove:SetSize(14, 14)
      remove:SetPoint("TOPRIGHT", -2, -4)
      remove:SetNormalTexture(T.tex.remove)
      remove:SetPushedTexture(T.tex.removeDown)
      remove:SetHighlightTexture(T.tex.removeHighlight, "ADD")
      remove:SetScript("OnClick", function()
        local name = target()
        if row.data and row.data.index and name and Memory.RemoveEvent(SL.db.players, name, row.data.index, row.data.event) then
          T.Play("checkOff")
          SL:Fire("MEMORY_CHANGED", name)
        end
      end)
      UI.Tooltip(remove, L.NOTE_REMOVE)
      row.Remove = remove
    end,
    onEnter = function(row, data)
      if not data.event or not GameTooltip then
        return
      end
      local title, text, stamp = SL.MemoryHooks.EventDetail(data.event)
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
      GameTooltip:SetText(title, T.color.gold.r, T.color.gold.g, T.color.gold.b)
      GameTooltip:AddLine(text, 1, 1, 1, true)
      if stamp ~= "" then
        GameTooltip:AddLine(stamp, T.color.gray.r, T.color.gray.g, T.color.gray.b, true)
      end
      GameTooltip:Show()
    end,
  })

  local note = UI.Input(card, 152, L.NOTE_PLACEHOLDER, 200)
  note.holder:SetPoint("BOTTOMLEFT", 6, 40)
  page.Note = note
  local function addNote()
    local name = target()
    local text = Rules.Clean(note:GetText() or "", 200)
    if name and text then
      Memory.Add(SL.db.players, name, { kind = "note", t = API.Now(), note = text, place = API.PlaceName() })
      page.selected = Names.Short(name)
      note:SetText("")
      note:ClearFocus()
      note.Refresh()
      SL:Fire("MEMORY_CHANGED", name)
      SL.MainFrame:Refresh()
    end
  end
  note:SetScript("OnEnterPressed", addNote)
  page.NoteButton = UI.Button(card, "+", 32, addNote, L.NOTE_ADD, L.NOTE_TIP)
  page.NoteButton:SetPoint("LEFT", note.holder, "RIGHT", 2, 0)

  -- deleting everything about someone asks twice
  page.Forget = UI.Button(card, L.FORGET, 186, function(self)
    local name = target()
    if not name or not SL.db.players[name] then
      return
    end
    if page.forgetArmed ~= name then
      page.forgetArmed = name
      self:SetText(L.FORGET_SURE)
      if C_Timer and C_Timer.After then
        C_Timer.After(4, function()
          page.forgetArmed = nil
          self:SetText(L.FORGET)
        end)
      end
      return
    end
    page.forgetArmed = nil
    Memory.Forget(SL.db.players, name)
    page.selected = nil
    SL:Fire("MEMORY_CHANGED", name)
    SL.MainFrame:Refresh()
  end, L.FORGET, L.FORGET_TIP)
  page.Forget:SetPoint("BOTTOMLEFT", 8, 10)
end

-- Refresh --------------------------------------------------------------------------------------------------------------
function PT.Refresh(page)
  local typed = page.Search:GetText() or ""
  local list, counts = PT.List(page.category, typed)
  local shown = typed ~= "" and "all" or page.category
  for key, b in pairs(page.side) do
    local c = T.category[key]
    local n = counts[key] or 0
    b.Text:SetText("|T" .. c.icon .. ":16:16|t " .. T.Paint(L["CAT_" .. string.upper(key)], n > 0 and c.color or T.color.gray))
    b.Count:SetText(T.Paint(tostring(n), n > 0 and T.color.white or T.color.gray))
    b.Lit:SetShown(key == shown)
    b.Mark:SetShown(key == shown)
  end
  page.Sort:SetText(L["SORT_" .. string.upper(SORT[SL.settings.playerSort] and SL.settings.playerSort or "recent")])
  -- back to the top only when what is listed is something else; choosing a player must not move the list
  local view = shown .. "|" .. typed .. "|" .. tostring(SL.settings.playerSort)
  page.List:Set(list, page.view ~= view)
  page.view = view
  page.Empty:SetText(#list == 0 and T.Paint(counts.all == 0 and L.PLAYERS_EMPTY or (typed ~= "" and L.PLAYERS_NO_MATCH or L.CAT_EMPTY), T.color.gray) or "")

  local name = page.Target()
  local record = name and SL.db.players[name]
  local entry
  for _, e in ipairs(list) do
    if e.name == name then
      entry = e
    end
  end
  local shape = record or (entry and entry.record)
  page.Name:SetText(name and (classText(shape and shape.class, 20) .. coloredName(name, shape and shape.class)) or "")
  local notes = {}
  if name then
    local category = shape and Memory.Category(shape, API.Now(), SL.settings.memoryDays) or "seen"
    page.Badge:SetText(shape and SL.Players:Label(category, 16, true) or "")
    local info = {}
    if entry and entry.inGroup then
      info[#info + 1] = T.Paint(L.IN_GROUP_NOW, T.color.green)
    end
    info[#info + 1] = shape and togetherText(shape)
    if shape and shape.last then
      info[#info + 1] = T.Paint(ago(shape.last), T.color.gray)
    end
    if record then
      page.Detail:SetText(table.concat(info, " · "))
    else
      page.Detail:SetText(T.Paint(string.format(entry and L.PLAYER_NO_NOTES or L.NEW_PLAYER_HINT, name), T.color.gray))
    end
    for i = record and #record.events or 0, 1, -1 do
      local event = record.events[i]
      local text, when = SL.MemoryHooks.EventParts(event)
      notes[#notes + 1] = { text = text, when = when, index = i, event = event }
    end
    if #notes == 0 then
      notes[1] = { text = T.Paint(L.NO_NOTES, T.color.gray) }
    end
  else
    page.Badge:SetText("")
    page.Detail:SetText(T.Paint(#list == 0 and L.PLAYERS_EMPTY or L.PLAYERS_PICK, T.color.gray))
  end
  page.Notes:Set(notes)

  local active = record and Memory.ActiveTag(record)
  for _, b in ipairs(page.tagButtons) do
    local category = Memory.TAG_CATEGORY[b.kind]
    -- plain text: red or orange words cannot be read on the game's red buttons (seen in the real client)
    b:SetText("|T" .. T.category[category].icon .. ":13:13|t " .. L["CAT_" .. string.upper(category)])
    if name then
      b:Enable()
    else
      b:Disable()
    end
    if active == b.kind then
      b:LockHighlight()
    else
      b:UnlockHighlight()
    end
  end
  for _, b in ipairs({ page.NoteButton, page.Forget }) do
    if (b == page.Forget and record) or (b ~= page.Forget and name) then
      b:Enable()
    else
      b:Disable()
    end
  end
  if page.forgetArmed and page.forgetArmed ~= name then
    page.forgetArmed = nil
    page.Forget:SetText(L.FORGET)
  end
end
