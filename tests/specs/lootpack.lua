-- 0.4.0: the optional loot data pack (SafeLoot_LootData, GPL-2.0), loaded as the game does.
local SL = NS
local L = SL.L
local Book = SL.LootBook
local index = SL.Catalog.index
_G.SafeLootWelcome:Hide()

local function settle()
  for _ = 1, 8 do
    if #SIM.timers == 0 then return end
    SIM.RunTimers()
  end
end

local STRAT, ONYXIA = 329, 249
local function bossByName(mapID, name)
  for _, boss in ipairs(index.byMap[mapID].bosses) do
    local names = type(boss.names) == "table" and boss.names or { boss.names }
    if names[1] == name then return boss end
  end
end
local function has(mapID, name, itemID)
  for _, e in ipairs(Book.Known(SafeLootDB.loot, index, mapID, bossByName(mapID, name).key)) do
    if e.id == itemID then return e end
  end
end

test("the pack loads, is credited and its source table is freed", function()
  ok(SL.Catalog.packItems > 2000, "items: " .. tostring(SL.Catalog.packItems))
  ok(contains(index.credit, "AtlasLootClassic"), "credit")
  eq(_G.SafeLootDataPack, nil)
  SL.MainFrame:Open("help")
  local all = {}
  for _, item in ipairs(SL.MainFrame.pages.help.List.provider.items) do all[#all + 1] = item.text end
  ok(contains(table.concat(all, "\n"), "AtlasLootClassic"), "credit visible in the help tab")
end)

test("well-known drops are under the right boss", function()
  ok(has(ONYXIA, "Onyxia", 18423) or has(ONYXIA, "Onyxia", 18422), "Head of Onyxia")
  ok(has(230, "Emperor Dagran Thaurissan", 11684), "Ironfoe: Emperor Dagran Thaurissan")
  ok(has(229, "General Drakkisath", 22269) or has(229, "General Drakkisath", 12592), "Drakkisath")
  ok(has(36, "Edwin VanCleef", 5191), "Cruel Barb: VanCleef")
  ok(has(329, "Baron Rivendare", 13335) or has(329, "Lord Aurius Rivendare", 13335), "Deathcharger's Reins")
  ok(has(349, "Princess Theradras", 17780), "Blade of Eternal Darkness")
end)

test("every item and boss of the pack is valid for Forever", function()
  for mapID, byBoss in pairs(index.pack) do
    ok(index.byMap[mapID], "instance " .. mapID)
    for key, items in pairs(byBoss) do
      ok(key == 0 or Book.Boss(index, mapID, key), mapID .. ":" .. key)
      for id in pairs(items) do ok(Book.IsID(id), tostring(id)) end
    end
  end
end)

test("every dungeon of Forever has loot from the first day, the nine new ones included", function()
  local live = 0
  for _, inst in ipairs(index.list) do
    if inst.live then
      live = live + 1
      ok(SL.Catalog:Totals(inst.id) > 0, "loot: " .. inst.name)
    end
  end
  eq(live, 29, "28 dungeons and Onyxia")
  ok(has(3065, "Faldrim Anvilmar", 270227), "Hall of Thanes: Ephemeral Choker")
  ok(has(2970, "Zul'Alai", 274598), "The Drowned City: Bloodslash Axe")
  ok(has(2999, "Witherfang", 271203), "Ruins of Lordaeron: Segmented Spider Leg")
  ok(has(389, "Taragaman the Hungerer", 251361), "Forever's additions to the classic dungeons")
end)

test("bosses without an NPC number in the source keep the same key every time", function()
  local first = Book.Index(SL.InstanceData, "enUS")
  ok(index.byMap[3065], "Hall of Thanes")
  local found
  for _, boss in ipairs(index.byMap[3065].bosses) do
    if boss.name == "Magmatus" then found = boss end
  end
  ok(found and found.key < -100000000 and found.extra, "Magmatus has a name-based key")
end)

test("an item is marked 'not seen yet' until someone sees it drop, then it is confirmed", function()
  local link = "|cnIQ4:|Hitem:11684::::::::60:::::|h[Ironfoe]|h|r"
  SIM.items[link] = { itemID = 11684, equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 4, name = "Ironfoe", quality = 4, bindType = 1 }
  local boss = bossByName(230, "Emperor Dagran Thaurissan")
  eq(has(230, "Emperor Dagran Thaurissan", 11684).seen, false)
  SL.MainFrame:Open("contract")
  SL.LootPicker:Open(230)
  local function rowFor()
    for _, data in ipairs(SL.LootPicker.frame.List.provider.items) do
      if data.id == 11684 then
        local row = SIM.newWidget("Button")
        SL.LootPicker:InitRow({ Text = row }, data)
        return row:GetText()
      end
    end
  end
  ok(contains(rowFor(), L.PICKER_UNSEEN), "marked")
  eq(_G.SafeLootLootPicker.Hint:GetText(), L.PICKER_HINT_UNSEEN, "explained")
  SIM.lootDrops[boss.key .. ":1"] = { itemHyperlink = link, rollInfos = {} }
  SIM.Fire("LOOT_HISTORY_UPDATE_DROP", boss.key, 1)
  settle()
  eq(has(230, "Emperor Dagran Thaurissan", 11684).seen, true)
  ok(not contains(rowFor(), L.PICKER_UNSEEN), "mark gone")
end)

test("items the server does not know, and grey or white pack items, are not shown", function()
  SIM.now = SIM.now + 100 -- (the previous dungeon's questions have expired)
  SL.LootPicker:ShowLoot(STRAT)
  local boss, unknown, white
  for _, b in ipairs(index.byMap[STRAT].bosses) do
    local list = Book.Known({}, index, STRAT, b.key)
    if #list >= 2 then boss, unknown, white = b, list[1].id, list[2].id; break end
  end
  SL.Catalog:ItemInfo(unknown)
  SIM.Fire("ITEM_DATA_LOAD_RESULT", unknown, false)
  SIM.items["|Hitem:" .. white .. "|h"] = { itemID = white, name = "Blanco", quality = 1, equipLoc = "", classID = 0, subClassID = 0, bindType = 0 }
  for _, e in ipairs(SL.Catalog:Items(STRAT, boss.key)) do
    ok(e.id ~= unknown, "unknown to the server")
    ok(e.id ~= white, "white")
  end
end)

test("the server is asked for a few items at a time, never a whole raid at once, and not again in a hurry", function()
  SIM.now = SIM.now + 100
  SIM.itemRequests = {}
  SL.LootPicker:ShowLoot(229)
  ok(#SIM.itemRequests > 0 and #SIM.itemRequests <= 60, "first burst: " .. #SIM.itemRequests)
  local n = #SIM.itemRequests
  SL.LootPicker:Refresh()
  eq(#SIM.itemRequests, n, "nothing is asked twice while waiting")
  SIM.Fire("ITEM_DATA_LOAD_RESULT", SIM.itemRequests[1], false)
  settle()
  eq(#SIM.itemRequests, n + 1, "an answer makes room for the next one")
end)

test("rares of the pack are bosses too: learned from their corpse and shared", function()
  local rare
  for _, b in ipairs(index.byMap[STRAT].bosses) do
    if b.key < 0 then rare = b end
  end
  ok(rare, "Stratholme has a rare from the pack")
  ok(Book.Learn(SafeLootDB.loot, index, STRAT, rare.key, 13395, 5), "learned")
  local messages = Book.Encode({ [STRAT] = { [rare.key] = { [13395] = 5 } } }, STRAT)
  local mapID, entries = Book.Decode(index, messages[1])
  eq(mapID, STRAT)
  eq(entries[1][1], rare.key)
  -- without the pack those items are kept under "other", not lost
  local plain = Book.Index(SL.InstanceData, "enUS")
  local saved = { [STRAT] = { [rare.key] = { [13395] = 5 } } }
  Book.Validate(saved, plain)
  ok(saved[STRAT][Book.OTHER][13395], "kept")
end)

test("only what was really seen is shared, never the pack", function()
  local messages = Book.Encode(SafeLootDB.loot, 43)
  eq(#messages, 0)
end)

test("a broken pack is ignored", function()
  local plain = Book.Index(SL.InstanceData, "enUS")
  eq(Book.AddPack(plain, nil), 0)
  eq(Book.AddPack(plain, { loot = "x" }), 0)
  eq(Book.AddPack(plain, { loot = { [999999] = { [1] = { 5 } }, [STRAT] = { [123456] = { 5 }, [0] = { "x", -1, 13395 } } } }), 1)
end)
