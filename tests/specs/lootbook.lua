-- 0.4.0: destination, loot by boss, picking items and people instead of typing, sharing, real link format.
local SL = NS
local L = SL.L
local Book, Rules = SL.LootBook, SL.Rules

local function settle()
  for _ = 1, 8 do
    if #SIM.timers == 0 then
      return
    end
    SIM.RunTimers()
  end
end

local function addItem(id, name, quality)
  -- the named colour is the format of the real Forever client (seen in saved data): "|cnIQ3:|Hitem:..."
  local link = "|cnIQ" .. (quality or 3) .. ":|Hitem:" .. id .. "::::::::60:1488::11:::::::|h[" .. name .. "]|h|r"
  SIM.items[link] = { itemID = id, equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 7, name = name, quality = quality or 3, bindType = 1 }
  return link
end

local MC, LUCIFRON, RAGNAROS = 409, 663, 672
local index = SL.Catalog.index
_G.SafeLootWelcome:Hide()

-- Data ---------------------------------------------------------------------------------------------------------------
test("instances and bosses come from the game data, in the addon's language", function()
  ok(#index.list >= 30, "instances: " .. #index.list)
  local mc = index.byMap[MC]
  ok(mc and mc.raid and mc.size == 40, "Molten Core raid")
  eq(mc.name, "Núcleo de Magma", "Spanish name")
  eq(mc.bosses[1].name, "Lucifron")
  local en = Book.Index(SL.InstanceData, "enUS")
  eq(en.byMap[MC].name, "Molten Core")
  ok(index.byMap[2974] and index.byMap[2974].live, "new Forever dungeon: Blackmaw Hold")
  for _, leftover in ipairs({ 2875, 2856, 2784, 2789, 2791, 2804, 2832 }) do
    eq(index.byMap[leftover], nil, "Season of Discovery leftovers are not in Forever: " .. leftover)
  end
  ok(not mc.live, "Molten Core is in the data but not open in Forever")
  for _, inst in ipairs(index.list) do
    ok(type(inst.name) == "string" and #inst.name > 0 and #inst.bosses > 0, "complete: " .. tostring(inst.id))
  end
  local seen = {}
  for _, inst in ipairs(index.list) do
    for _, boss in ipairs(inst.bosses) do
      for _, id in ipairs(boss.ids) do
        ok(not seen[id], "encounter ID used once: " .. id)
        seen[id] = true
      end
    end
  end
end)

test("dungeons first, then raids, each by level", function()
  local lastRaid, lastMin = false, 0
  for _, inst in ipairs(index.list) do
    if inst.raid ~= lastRaid then
      ok(inst.raid, "raids after dungeons")
      lastRaid, lastMin = inst.raid, 0
    end
    ok(lastMin <= inst.min, lastMin .. " <= " .. inst.min)
    lastMin = inst.min
  end
end)

-- Loot book (pure) ---------------------------------------------------------------------------------------------------
test("loot book: refuses junk, moves 'other' to its boss, caps each boss", function()
  local book = {}
  ok(not Book.Learn(book, index, 999999, 0, 100, 1), "unknown instance")
  ok(not Book.Learn(book, index, MC, 12345678, 100, 1), "unknown boss")
  ok(not Book.Learn(book, index, MC, LUCIFRON, -3, 1), "bad ID")
  ok(not Book.Learn(book, index, MC, LUCIFRON, 1.5, 1), "bad ID")
  ok(not Book.Learn(book, index, MC, LUCIFRON, "16800", 1), "text ID")
  ok(Book.Learn(book, index, MC, Book.OTHER, 16800, 1), "other")
  ok(Book.Learn(book, index, MC, LUCIFRON, 16800, 2), "then under its boss")
  eq(#Book.Items(book, MC, Book.OTHER), 0, "no longer in 'other'")
  ok(not Book.Learn(book, index, MC, Book.OTHER, 16800, 3), "already known under its boss")
  for i = 1, Book.MAX_PER_BOSS + 10 do
    Book.Learn(book, index, MC, LUCIFRON, 20000 + i, 10 + i)
  end
  eq(#Book.Items(book, MC, LUCIFRON), Book.MAX_PER_BOSS, "capped")
  ok(not book[MC][LUCIFRON][16800], "the oldest went out")
  ok(not Book.Learn(book, index, MC, LUCIFRON, 99999, 999, true), "a shared item never pushes out yours")
end)

test("loot book: encode / decode round trip, every message fits", function()
  local book = {}
  for i = 1, 48 do
    Book.Learn(book, index, MC, LUCIFRON, 200000 + i, 1)
    Book.Learn(book, index, MC, RAGNAROS, 300000 + i, 1)
  end
  Book.Learn(book, index, MC, Book.OTHER, 77777, 1)
  local copy, messages = {}, Book.Encode(book, MC)
  ok(#messages > 1, "several messages")
  for _, message in ipairs(messages) do
    ok(#message <= 255, "fits: " .. #message)
    local mapID, entries = Book.Decode(index, message)
    eq(mapID, MC)
    for _, e in ipairs(entries) do
      Book.Learn(copy, index, mapID, e[1], e[2], 1, true)
    end
  end
  eq(Book.Count(copy, MC), 97, "nothing lost")
end)

test("loot book: hostile or broken messages are ignored", function()
  for _, bad in ipairs({ "1|LB|409|", "1|LB|1|663:5", "1|LB|409|663:x", "1|LB|409|663:5|Hjunk", "2|LB|409|663:5", "",
    "1|LB|409|" .. string.rep("9", 300) }) do
    local mapID, entries = Book.Decode(index, bad)
    ok(mapID == nil or #entries == 0, bad:sub(1, 30))
  end
  local _, entries = Book.Decode(index, "1|LB|409|663:0,99999999999,16800;424242:5")
  eq(#entries, 1, "only the valid ID of a real boss")
  eq(Book.ParseQuery(index, "1|LQ|409"), MC)
  eq(Book.ParseQuery(index, "1|LQ|1"), nil)
end)

test("loot book: damaged saved data is cleaned, not crashed on", function()
  local book = { [MC] = { [LUCIFRON] = { [16800] = 5, x = 1, [5] = "no" }, [1] = { [5] = 1 } }, junk = 1, [7] = {} }
  Book.Validate(book, index)
  eq(Book.Count(book, MC), 1)
  eq(book.junk, nil)
  eq(book[7], nil)
  eq(type(Book.Validate("broken", index)), "table")
end)

-- Learning in game ---------------------------------------------------------------------------------------------------
test("drops of the roll history are learned under their boss, even with the detector off", function()
  SafeLootDB.settings.detector = false
  local link = addItem(16800, "Botas Arcanista", 4)
  SIM.lootDrops[LUCIFRON .. ":1"] = { itemHyperlink = link, rollInfos = {} }
  SIM.Fire("LOOT_HISTORY_UPDATE_DROP", LUCIFRON, 1)
  settle()
  ok(SafeLootDB.loot[MC][LUCIFRON][16800], "learned")
  SafeLootDB.settings.detector = true
end)

test("an unknown encounter ID falls back to the encounter's name, then to 'other'", function()
  SIM.inGroup, SIM.groupSize, SIM.inInstance, SIM.instanceType, SIM.instanceMapID = true, 4, true, "raid", MC
  SIM.encounterNames = { [987654] = "Ragnaros" }
  local a, b = addItem(17204, "Ojo de Sulfuras", 5), addItem(18251, "Cuero del Núcleo", 3)
  SIM.lootDrops["987654:1"] = { itemHyperlink = a, rollInfos = {} }
  SIM.lootDrops["987655:1"] = { itemHyperlink = b, rollInfos = {} }
  SIM.Fire("LOOT_HISTORY_UPDATE_DROP", 987654, 1)
  SIM.Fire("LOOT_HISTORY_UPDATE_DROP", 987655, 1)
  settle()
  ok(SafeLootDB.loot[MC][RAGNAROS][17204], "by name")
  ok(SafeLootDB.loot[MC][Book.OTHER][18251], "other")
end)

test("looting a boss corpse learns it; trash, players and grey items do not", function()
  local c, grey = addItem(16901, "Guardapiernas de Tormenta", 4), addItem(7073, "Colmillo roto", 0)
  SIM.lootWindow = { { link = c, quality = 4 }, { link = grey, quality = 0 } }
  SIM.target = { name = "Perro del Núcleo", dead = true }
  SIM.Fire("LOOT_OPENED")
  ok(not SafeLootDB.loot[MC][RAGNAROS][16901], "trash corpse: nothing")
  SIM.target = { name = "Ragnaros", dead = true }
  SIM.Fire("LOOT_OPENED")
  ok(SafeLootDB.loot[MC][RAGNAROS][16901], "boss corpse")
  ok(not SafeLootDB.loot[MC][RAGNAROS][7073], "no grey items")
  SIM.target, SIM.lootWindow = nil, nil
end)

test("secret values from the game are never used as keys", function()
  SIM.secrets[555001] = true
  SIM.Fire("LOOT_HISTORY_UPDATE_DROP", 555001, 1)
  SIM.secrets[555001] = nil
  eq(#(SafeLootDB.errors or {}), 0)
end)

-- Destination --------------------------------------------------------------------------------------------------------
test("entering a dungeon with a group sets the destination; choosing one never unpublishes the rules", function()
  SIM.units.party1 = { first = "Krag", second = "Hierro", class = "WARRIOR" }
  SIM.units.party2 = { first = "Zarn", second = "Brasa", class = "MAGE" }
  SIM.leaderUnit, SIM.lootMethod = "party1", 3
  SIM.Fire("GROUP_ROSTER_UPDATE")
  settle()
  SIM.Fire("ZONE_CHANGED_NEW_AREA")
  settle()
  eq(SL.Contract:Get().instance, MC)
  SIM.now = SIM.now + 10
  SL.Contract:Publish()
  local at = SL.Contract:Get().publishedAt
  ok(at, "published")
  SL.Contract:SetDestination(2974)
  eq(SL.Contract:Get().publishedAt, at, "still published")
  SL.Contract:SetDestination(2974)
  eq(SL.Contract:Get().publishedAt, at, "choosing the same one again changes nothing")
  SL.Contract:SetDestination(MC)
end)

test("rules prepared alone are kept when the group forms, with the game's real loot method", function()
  SIM.inInstance, SIM.inGroup, SIM.groupSize = false, false, 1
  SIM.Fire("GROUP_LEFT")
  SIM.Fire("GROUP_ROSTER_UPDATE")
  settle()
  eq(SL.Contract:Get(), nil, "alone, nothing agreed")
  SL.Contract:SetDestination(MC)
  SL.Contract:Edit(function(c)
    Rules.Apply(c, { reserves = { { item = "Ojo de Sulfuras", itemID = 17204, owner = "Ana Paciente", kind = "hard" } } })
  end)
  SIM.inGroup, SIM.groupSize, SIM.lootMethod = true, 4, 4
  SIM.Fire("GROUP_ROSTER_UPDATE")
  settle()
  local c = SL.Contract:Get()
  eq(c.instance, MC, "destination kept")
  eq(#c.reserves, 1, "reserve kept")
  eq(c.method, 4, "method of the real group")
end)

test("the leader's own change keeps the destination", function()
  SL.Contract:Reset(Rules.FromState(SL.API.LootState(), SIM.now))
  SL.Contract:SetDestination(MC)
  SIM.leaderUnit, SIM.lootMethod = "player", 3
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  eq(SL.Contract:Get().method, 3)
  eq(SL.Contract:Get().instance, MC)
  SIM.leaderUnit = "party1"
  SL.Contract:SyncGame()
end)

-- Picker -------------------------------------------------------------------------------------------------------------
local function rows()
  return SL.LootPicker.frame.List.provider.items
end

test("picker: dungeons and raids listed, choosing one shows its bosses with their items", function()
  SL.MainFrame:Open("contract")
  SL.MainFrame.pages.contract.Dest:Click()
  ok(_G.SafeLootLootPicker:IsShown(), "open")
  local heads, instances, target = 0, 0, nil
  for _, row in ipairs(rows()) do
    if row.kind == "head" then heads = heads + 1 end
    if row.kind == "instance" then
      instances = instances + 1
      if row.inst.id == MC then target = row end
    end
  end
  eq(heads, 2)
  local live = 0
  for _, inst in ipairs(index.list) do
    if inst.live then live = live + 1 end
  end
  eq(instances, live + 1, "what is open in Forever, plus the chosen one")
  ok(target.dest, "the chosen one is marked")
  ok(target.known >= 3, "known items counted")
  SL.LootPicker:OnRowClick(target, "LeftButton")
  local bosses, items = 0, {}
  for _, row in ipairs(rows()) do
    if row.kind == "boss" then bosses = bosses + 1 end
    if row.kind == "item" then items[row.id] = row end
  end
  eq(bosses, #index.byMap[MC].bosses, "every boss")
  ok(items[16800] and items[17204] and items[16901] and items[18251], "learned items")
  eq(SL.MainFrame.pages.contract.Dest:GetText(), string.format(L.DEST_FMT, "Núcleo de Magma"))
end)

test("picker: search by item or by boss, accents ignored", function()
  local f = _G.SafeLootLootPicker
  f.Search:SetText("SULFURAS")
  f.Search:Fire("OnTextChanged")
  local items = 0
  for _, row in ipairs(rows()) do
    if row.kind == "item" then
      items = items + 1
      eq(row.id, 17204)
    end
  end
  eq(items, 1)
  f.Search:SetText("ragnaros")
  f.Search:Fire("OnTextChanged")
  local bossRows, itemCount = 0, 0
  for _, row in ipairs(rows()) do
    if row.kind == "boss" then bossRows = bossRows + 1 end
    if row.kind == "item" then itemCount = itemCount + 1 end
  end
  eq(bossRows, 1)
  eq(itemCount, 2, "all of that boss's items")
  f.Search:SetText("zzzz")
  f.Search:Fire("OnTextChanged")
  eq(rows()[1].text, L.PICKER_NO_MATCH)
  f.Search:SetText("")
  f.Search:Fire("OnTextChanged")
end)

test("picker: every row draws without errors, and items show the game's tooltip and modified clicks", function()
  for _, view in ipairs({ "loot", "instances" }) do
    if view == "instances" then SL.LootPicker:ShowInstances() end
    for _, data in ipairs(rows()) do
      local row = SIM.newWidget("Button")
      SL.LootPicker.frame.List.view.init(row, data)
      ok(type(row.Text:GetText()) == "string" and #row.Text:GetText() > 0, data.kind)
      row:Fire("OnEnter")
      row:Fire("OnLeave")
    end
  end
  SL.LootPicker:ShowLoot(MC)
  local itemRow
  for _, data in ipairs(rows()) do
    if data.id == 17204 then itemRow = data end
  end
  SIM.modifiedClick = true
  SL.LootPicker:OnRowClick(itemRow, "LeftButton")
  SIM.modifiedClick = false
  ok(contains(SIM.modifiedLinks[#SIM.modifiedLinks], "17204"), "Shift/Ctrl-click goes to the game")
  ok(_G.SafeLootLootPicker:IsShown(), "and does not pick")
end)

test("picking an item, its owner from the group menu and HR/SR, without typing anything", function()
  local page = SL.MainFrame.pages.contract
  SL.Contract:Edit(function(c) c.reserves = {} end)
  page.LootButton:Click()
  local itemRow
  for _, data in ipairs(rows()) do
    if data.id == 17204 then itemRow = data end
  end
  SL.LootPicker:OnRowClick(itemRow, "LeftButton")
  eq(page.ItemBox:GetText(), "Ojo de Sulfuras")
  ok(not _G.SafeLootLootPicker:IsShown(), "closes after picking")
  page.OwnerButton:Click()
  local names = {}
  for _, entry in ipairs(SIM.lastMenu.entries) do
    names[#names + 1] = entry.text
  end
  ok(contains(table.concat(names, " "), "Krag Hierro"), "your group is listed: " .. table.concat(names, ", "))
  for _, entry in ipairs(SIM.lastMenu.entries) do
    if contains(entry.text, "Krag Hierro") then entry.fn() end
  end
  page.Kind:Click()
  page.AddButton:Click()
  local r = SL.Contract:Get().reserves[1]
  eq(r.item, "Ojo de Sulfuras")
  eq(r.itemID, 17204)
  eq(r.owner, "Krag Hierro")
  eq(r.kind, "soft")
  eq(page.ItemBox:GetText(), "", "box cleared")
  page.Kind:Click()
end)

test("the list shows the reserve as a clickable link and each one can be removed", function()
  local page = SL.MainFrame.pages.contract
  eq(#page.ReserveList.provider.items, 1)
  local row = SIM.newWidget("Button")
  page.ReserveList.view.init(row, page.ReserveList.provider.items[1])
  ok(contains(row.Text:GetText(), "|Hitem:17204"), "real link: " .. row.Text:GetText())
  ok(contains(row.Text:GetText(), "Krag Hierro"), "owner")
  row.Remove:Click()
  eq(#SL.Contract:Get().reserves, 0, "removed")
  eq(page.Reserves:GetText() ~= "", true, "empty state back")
end)

test("typing the name still works and finds the item ID when it is known", function()
  local page = SL.MainFrame.pages.contract
  page.ItemBox:SetText("botas arcanista")
  page.AddButton:Click()
  eq(SL.Contract:Get().reserves[1].itemID, 16800)
  page.ItemBox:SetText("Algo que no existe")
  page.AddButton:Click()
  eq(SL.Contract:Get().reserves[2].itemID, nil)
  page.ItemBox:SetText("")
  page.AddButton:Click()
  eq(#SL.Contract:Get().reserves, 2, "an empty box adds nothing")
end)

test("BUG: Shift-click never reached the box (Forever calls ChatFrameUtil.InsertLink)", function()
  local page = SL.MainFrame.pages.contract
  local hook = SIM.tableHooks and SIM.tableHooks.InsertLink
  ok(hook, "hooked where the game really calls")
  local link = addItem(11684, "Ironfoe", 4)
  page.ItemBox:SetText("")
  page.ItemBox:Fire("OnEditFocusGained")
  page.ItemBox.HasFocus = function() return false end
  hook(link)
  eq(page.ItemBox:GetText(), "", "nothing without the cursor in the box")
  page.ItemBox.HasFocus = function() return true end
  hook(link)
  eq(page.ItemBox:GetText(), "Ironfoe")
  eq(page.picked.id, 11684)
  page.ItemBox.HasFocus = function() return false end
  page.ItemBox:SetText("Ironfoe y algo más")
  page.ItemBox:Fire("OnTextChanged")
  eq(page.picked, nil, "editing the text forgets the picked item")
  page.ItemBox:SetText("")
end)

test("an owner who leaves the group is not kept for the next reserve", function()
  local page = SL.MainFrame.pages.contract
  page.owner = "Zarn Brasa"
  SL.MainFrame:Refresh()
  eq(page.owner, "Zarn Brasa")
  local saved = SIM.units.party2
  SIM.units.party2 = nil
  SL.MainFrame:Refresh()
  eq(page.owner, SL.Names.Me())
  SIM.units.party2 = saved
end)

-- Chat line with real links --------------------------------------------------------------------------------------
test("the published line carries real item links and never exceeds 255 bytes", function()
  SL.Contract:Edit(function(c)
    c.reserves = {}
    Rules.Apply(c, { reserves = { { item = "Ironfoe", itemID = 11684, owner = "Krag Hierro", kind = "hard" } } })
  end)
  SIM.now = SIM.now + 10
  SL.Contract:Publish()
  local line = SIM.sent[#SIM.sent].text
  ok(contains(line, "|Hitem:11684"), "link in the chat: " .. line)
  ok(#line <= 255)
  SL.Contract:Edit(function(c)
    for i = 1, 8 do
      local id = 30000 + i
      addItem(id, "Objeto larguísimo número " .. i, 4)
      Rules.Apply(c, { reserves = { { item = "Objeto larguísimo número " .. i, itemID = id, owner = "Krag Hierro", kind = "hard" } } })
    end
  end)
  SIM.now = SIM.now + 10
  SL.Contract:Publish()
  local long = SIM.sent[#SIM.sent].text
  ok(#long <= 255, "fits: " .. #long)
  local opened = select(2, long:gsub("|H", ""))
  local closed = select(2, long:gsub("|h|r", ""))
  eq(opened, closed, "no link cut in half")
end)

test("BUG: the client's '|cnIQ3:' colours left junk in cleaned text", function()
  local link = "|cnIQ3:|Hitem:13246::::::::60:1488::11:::::::|h[Argent Avenger]|h|r"
  eq(Rules.Clean("HR " .. link, 80), "HR [Argent Avenger]")
  eq(Rules.Normalize("|cnIQ3:Hola|r"), "hola")
  eq(Rules.CleanChat("HR " .. link .. " |TInterface:1|t|Hplayer:x|h[x]|h", 255), "HR " .. link .. " [x]")
  local parsed = Rules.Parse("HR " .. link .. ", MS>OS", "Krag Hierro")
  eq(parsed.reserves[1].item, "Argent Avenger")
  eq(parsed.reserves[1].itemID, 13246)
  eq(parsed.needRule, "msos")
end)

test("the same item for the same person is one reserve (the newest HR/SR wins)", function()
  local c = Rules.New("proposed", 1)
  Rules.Apply(c, { reserves = { { item = "Ironfoe", itemID = 11684, owner = "Krag Hierro", kind = "hard" } } })
  Rules.Apply(c, { reserves = { { item = "ironfoe", owner = "Krag Hierro", kind = "soft" } } })
  Rules.Apply(c, { reserves = { { item = "Ironfoe", itemID = 11684, owner = "Zarn Brasa", kind = "soft" } } })
  eq(#c.reserves, 2)
  eq(c.reserves[1].kind, "soft")
  eq(#Rules.ReservesFor(c, "otro nombre", 11684), 2, "found by ID")
  eq(#Rules.ReservesFor(c, "IRONFOE", nil), 2, "found by name")
end)

-- Items still loading --------------------------------------------------------------------------------------------
test("items the game has not loaded yet are requested once and filled in when they arrive", function()
  SafeLootDB.loot[MC][LUCIFRON][55555] = SIM.now
  local link = addItem(55555, "Objeto lento", 3)
  SIM.items[link].unloaded = true
  SIM.itemRequests = {}
  SL.MainFrame:Open("contract")
  SL.LootPicker:Open(MC)
  SL.LootPicker:Refresh()
  local n = 0
  for _, id in ipairs(SIM.itemRequests) do
    if id == 55555 then n = n + 1 end
  end
  eq(n, 1, "requested once")
  SIM.items[link].unloaded = nil
  SIM.Fire("ITEM_DATA_LOAD_RESULT", 55555, true) -- the event RequestLoadItemDataByID really uses
  settle()
  local name
  for _, row in ipairs(rows()) do
    if row.id == 55555 then name = row.info.name end
  end
  eq(name, "Objeto lento")
end)

-- Sharing ------------------------------------------------------------------------------------------------------------
test("sharing: asks the group once, answers others, learns what it receives", function()
  SL.Contract:SetDestination(nil)
  SIM.addonSent = {}
  SIM.now = SIM.now + 1000
  SL.Contract:SetDestination(MC)
  eq(SIM.addonSent[#SIM.addonSent].message, "1|LQ|409")
  local n = #SIM.addonSent
  SL.Catalog:Ask(MC)
  eq(#SIM.addonSent, n, "not repeated")
  SIM.Fire("CHAT_MSG_ADDON", "SafeLoot", "1|LQ|409", "PARTY", "Zarn-Brasa")
  settle()
  ok(contains(SIM.addonSent[#SIM.addonSent].message, "1|LB|409|"), "answered")
  SIM.Fire("CHAT_MSG_ADDON", "SafeLoot", "1|LB|409|664:17109", "PARTY", "Zarn-Brasa")
  ok(SafeLootDB.loot[MC][664][17109], "learned from the group")
  SIM.Fire("CHAT_MSG_ADDON", "SafeLoot", "1|LB|409|664:17110", "WHISPER", "Desconocido-Raro")
  ok(not SafeLootDB.loot[MC][664][17110], "strangers outside the group are ignored")
  SafeLootDB.settings.shareLoot = false
  SIM.Fire("CHAT_MSG_ADDON", "SafeLoot", "1|LB|409|664:17111", "PARTY", "Zarn-Brasa")
  ok(not SafeLootDB.loot[MC][664][17111], "the option turns it off")
  SIM.now = SIM.now + 1000
  local before = #SIM.addonSent
  SL.Catalog:Ask(MC)
  eq(#SIM.addonSent, before, "and nothing is sent")
  SafeLootDB.settings.shareLoot = true
end)

test("closing the main window closes the picker; diagnostics report the loot book", function()
  SL.LootPicker:Open(MC)
  _G.SafeLootMainFrame:Hide()
  ok(not _G.SafeLootLootPicker:IsShown())
  local stats = SL.Catalog:Stats()
  ok(stats.items > 3 and stats.maps == 1)
  SL:HandleSlash("test")
  ok(SafeLootDB.diagnostics.report.lootBook.items > 3)
  ok(SafeLootDB.diagnostics.report.functions["ChatFrameUtil.InsertLink"])
  eq(#(SafeLootDB.errors or {}), 0, "no internal errors")
end)
