-- 0.5.2: the performance, code and security audit. One test for each thing found.
local SL = NS
local L = SL.L
local Book, Rules, Cat = SL.LootBook, SL.Rules, SL.Catalog
local index = Cat.index
_G.SafeLootWelcome:Hide()

local function settle()
  for _ = 1, 8 do
    if #SIM.timers == 0 then return end
    SIM.RunTimers()
  end
end

local function clearToasts()
  SL.Alert.queue = {}
  _G.SafeLootToast:Hide()
end

local function joinGroup()
  SIM.inGroup, SIM.groupSize = true, 4
  SIM.units.party1 = { first = "Krag", second = "Hierro", class = "WARRIOR" }
  SIM.units.party2 = { first = "Zarn", second = "Brasa", class = "MAGE" }
  SIM.units.party3 = { first = "Lia", second = "Sombra", class = "ROGUE" }
  SIM.leaderUnit, SIM.lootMethod = "party1", 3
  SIM.Fire("GROUP_ROSTER_UPDATE")
  settle()
end

local MC, LUCIFRON, STRAT = 409, 663, 329

-- Loot book: what others say ---------------------------------------------------------------------------------------------
test("what you only heard is never shared again, so a false report cannot travel", function()
  local book = {}
  Book.Learn(book, index, MC, LUCIFRON, 16800, 100)
  Book.Learn(book, index, MC, LUCIFRON, 99001, 100, true)
  local text = table.concat(Book.Encode(book, MC), " ")
  ok(contains(text, "16800"), "what you saw")
  ok(not contains(text, "99001"), "not what you heard")
end)

test("what you only heard is marked as such, until you see it or the data pack backs it up", function()
  local book = {}
  Book.Learn(book, index, MC, LUCIFRON, 99001, 100, true)
  local function rumor()
    for _, entry in ipairs(Book.Known(book, index, MC, LUCIFRON)) do
      if entry.id == 99001 then return entry end
    end
  end
  local e = rumor()
  eq(e.seen, false)
  eq(e.heard, true)
  ok(Book.Learn(book, index, MC, LUCIFRON, 99001, 200), "seeing it counts as news")
  e = rumor()
  eq(e.seen, true)
  eq(e.heard, nil)
  -- in the pack: plausible, so one report is enough
  local key, id
  for k, items in pairs(index.pack[STRAT]) do
    if k ~= Book.OTHER then key, id = k, next(items) end
  end
  Book.Learn(book, index, STRAT, key, id, 100, true)
  for _, entry in ipairs(Book.Known(book, index, STRAT, key)) do
    if entry.id == id then eq(entry.seen, true) end
  end
  local _, seen = Book.Totals(book, index, STRAT)
  eq(seen, 1)
end)

test("a boss full of things you heard still has room for what you see", function()
  local book = {}
  Book.Learn(book, index, MC, LUCIFRON, 16800, 1) -- yours, and the oldest
  for i = 1, 100 do
    Book.Learn(book, index, MC, LUCIFRON, 90000 + i, 5000 + i, true)
  end
  eq(#Book.Items(book, MC, LUCIFRON), Book.MAX_PER_BOSS)
  for i = 1, 20 do
    ok(Book.Learn(book, index, MC, LUCIFRON, 70000 + i, 100 + i), "room for yours")
  end
  ok(book[MC][LUCIFRON][16800], "your oldest one is still there")
  for i = 1, 20 do
    ok(book[MC][LUCIFRON][70000 + i], "and the new ones")
  end
  eq(#Book.Items(book, MC, LUCIFRON), Book.MAX_PER_BOSS)
end)

test("nobody can move or refresh what you saw", function()
  local book = {}
  Book.Learn(book, index, MC, Book.OTHER, 16800, 50)
  ok(not Book.Learn(book, index, MC, LUCIFRON, 16800, 99, true), "refused")
  eq(book[MC][Book.OTHER][16800], 50, "still where you saw it")
  Book.Learn(book, index, MC, LUCIFRON, 16801, 50)
  Book.Learn(book, index, MC, LUCIFRON, 16801, 99, true)
  eq(book[MC][LUCIFRON][16801], 50)
  -- and something heard under a boss never hides what you see elsewhere in the same place
  Book.Learn(book, index, MC, LUCIFRON, 16802, 99, true)
  ok(Book.Learn(book, index, MC, Book.OTHER, 16802, 60), "yours is kept")
end)

test("damaged times in the book are dropped", function()
  local book = { [MC] = { [LUCIFRON] = { [16800] = 0 / 0, [16801] = -5, [16802] = 5 } } }
  Book.Validate(book, index)
  eq(book[MC][LUCIFRON][16800], nil)
  eq(#Book.Items(book, MC, LUCIFRON), 2)
end)

test("reports are only taken about where you are going, and not without limit from one player", function()
  joinGroup()
  SL.Contract:SetDestination(MC)
  SL.db.loot = {}
  SIM.Fire("CHAT_MSG_ADDON", "SafeLoot", "1|LB|329|472:13335", "PARTY", "Zarn-Brasa")
  eq(Book.Count(SL.db.loot, STRAT), 0, "another place")
  SIM.Fire("CHAT_MSG_ADDON", "SafeLoot", "1|LB|409|663:99001", "PARTY", "Zarn-Brasa")
  eq(Book.Count(SL.db.loot, MC), 1, "the destination")
  ok(SL.db.loot[MC][LUCIFRON][99001] < 0, "as something heard")
  for m = 1, 40 do
    local ids = {}
    for i = 1, 30 do ids[i] = tostring(100000 + m * 100 + i) end
    SIM.Fire("CHAT_MSG_ADDON", "SafeLoot", "1|LB|409|663:" .. table.concat(ids, ","), "PARTY", "Lia-Sombra")
  end
  eq(Cat.received["Lia Sombra"], 600, "stopped listening to them")
end)

test("asking over and over does not make you flood the group", function()
  SL.db.loot = {}
  for _, map in ipairs({ MC, STRAT, 230, 229 }) do
    local boss = index.byMap[map].bosses[1]
    Book.Learn(SL.db.loot, index, map, boss.key, 16800 + map, SIM.now)
  end
  SIM.now = SIM.now + 1000
  settle()
  SIM.addonSent = {}
  for _ = 1, 50 do
    for _, map in ipairs({ MC, STRAT, 230, 229 }) do
      SIM.Fire("CHAT_MSG_ADDON", "SafeLoot", "1|LQ|" .. map, "PARTY", "Zarn-Brasa")
    end
  end
  ok(#SIM.timers <= 4, "one answer waiting per question: " .. #SIM.timers)
  settle()
  local answers = 0
  for _, m in ipairs(SIM.addonSent) do
    if contains(m.message, "|LB|") then answers = answers + 1 end
  end
  eq(answers, 1, "one answer at a time")
end)

test("the picker says what is only heard", function()
  SL.db.loot = {}
  local link = "|cnIQ3:|Hitem:99001::::|h[Rumor]|h|r"
  SIM.items[link] = { itemID = 99001, equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 7, name = "Rumor", quality = 3, bindType = 1 }
  Book.Learn(SL.db.loot, index, MC, LUCIFRON, 99001, SIM.now, true)
  local row = SIM.newWidget("Button")
  SL.LootPicker:Open(MC)
  local found
  for _, data in ipairs(SL.LootPicker.frame.List.provider.items) do
    if data.id == 99001 then found = data end
  end
  ok(found and found.heard, "listed as heard")
  SL.LootPicker.frame.List.view.init(row, found)
  ok(contains(row.Text:GetText(), L.PICKER_HEARD), row.Text:GetText())
  SL.LootPicker:Hide()
end)

-- The game's noise ---------------------------------------------------------------------------------------------------------
test("items loaded by the game for others are only listened to while we wait for one", function()
  local events = SL.eventFrame._events
  for id = 880001, 880003 do
    Cat:ItemInfo(id)
  end
  ok(events.ITEM_DATA_LOAD_RESULT and events.GET_ITEM_INFO_RECEIVED, "listening")
  for _, id in ipairs(SIM.itemRequests) do -- every answer, the ones other tests left waiting included
    SIM.Fire("ITEM_DATA_LOAD_RESULT", id, false)
  end
  SIM.now = SIM.now + 100
  Cat:ItemInfo(880010)
  SIM.Fire("ITEM_DATA_LOAD_RESULT", 880010, false)
  ok(not events.ITEM_DATA_LOAD_RESULT and not events.GET_ITEM_INFO_RECEIVED, "not any more")
end)

test("a drop is read from the game once per event and learned once", function()
  SIM.inInstance, SIM.instanceType, SIM.instanceMapID = true, "raid", MC
  local link = "|cnIQ4:|Hitem:16899::::|h[Guantes]|h|r"
  SIM.items[link] = { itemID = 16899, equipLoc = "INVTYPE_HAND", classID = 4, subClassID = 2, name = "Guantes", quality = 4, bindType = 1 }
  SIM.lootDrops[LUCIFRON .. ":9"] = { itemHyperlink = link, rollInfos = {} }
  local reads, real = 0, SL.API.LootDrop
  SL.API.LootDrop = function(...) reads = reads + 1; return real(...) end
  local learns, realLearn = 0, Cat.Learn
  Cat.Learn = function(...) learns = learns + 1; return realLearn(...) end
  for _ = 1, 40 do
    SIM.Fire("LOOT_HISTORY_UPDATE_DROP", LUCIFRON, 9)
  end
  SL.API.LootDrop, Cat.Learn = real, realLearn
  eq(reads, 40, "once per event, not twice")
  eq(learns, 1)
  ok(SL.db.loot[MC][LUCIFRON][16899] > 0, "yours")
  SIM.inInstance, SIM.instanceType, SIM.instanceMapID = false, "none", nil
end)

test("a handler that unregisters itself does not make the next one miss the event", function()
  local a, b, calls = {}, {}, {}
  SL:RegisterEvent("PLAYER_STARTED_MOVING", a, function()
    calls[#calls + 1] = "a"
    SL:UnregisterEvent("PLAYER_STARTED_MOVING", a)
  end)
  SL:RegisterEvent("PLAYER_STARTED_MOVING", b, function() calls[#calls + 1] = "b" end)
  SIM.Fire("PLAYER_STARTED_MOVING")
  SIM.Fire("PLAYER_STARTED_MOVING")
  eq(table.concat(calls), "abb")
  SL:UnregisterEvent("PLAYER_STARTED_MOVING", b)
end)

-- Lists --------------------------------------------------------------------------------------------------------------------
test("a list is drawn once, whatever its length, and stays where you were reading", function()
  for i = 1, 300 do
    SL.db.players["Prueba" .. i .. " Larga"] = { events = {}, last = SIM.now - i, seen = 1 }
  end
  SL.MainFrame:Open("players")
  local page = SL.MainFrame.pages.players
  local sets, kept = 0, nil
  page.List.box.SetDataProvider = function(_, _, keep) sets, kept = sets + 1, keep end
  page.Search:SetText("")
  SL.MainFrame:Refresh()
  SIM.providers, sets = 0, 0
  page.selected = "Prueba7 Larga"
  SL.MainFrame:Refresh()
  eq(sets, 1, "one assignment for 300 players")
  eq(kept, true, "choosing a player does not move the list")
  page.category = "ninja"
  SL.MainFrame:Refresh()
  eq(kept, false, "another category starts at the top")
  page.category = "all"
  SL.MainFrame:Refresh()
  for i = 1, 300 do
    SL.db.players["Prueba" .. i .. " Larga"] = nil
  end
end)

test("while items load, only the tab that shows them is drawn again", function()
  SL.MainFrame:Open("journal")
  local n, real = 0, SL.MainFrame.Refresh
  SL.MainFrame.Refresh = function(...) n = n + 1; return real(...) end
  SL:Fire("CATALOG_CHANGED")
  eq(n, 0, "journal")
  SL.MainFrame:Open("contract")
  n = 0
  SL:Fire("CATALOG_CHANGED")
  eq(n, 1, "rules")
  SL.MainFrame.Refresh = real
end)

test("players are sorted A-Z without accents or capitals", function()
  for _, name in ipairs({ "Ñu Azul", "nadia Verde", "Óscar Rojo", "oca Gris" }) do
    SL.db.players[name] = { events = {}, last = SIM.now, seen = 1 }
  end
  SL.settings.playerSort = "name"
  local order = {}
  for _, e in ipairs((SL.PlayersTab.List("seen", ""))) do
    order[#order + 1] = e.name
  end
  local text = table.concat(order, ",")
  ok(text:find("nadia Verde", 1, true) < text:find("Ñu Azul", 1, true), text)
  ok(text:find("oca Gris", 1, true) < text:find("Óscar Rojo", 1, true), text)
  SL.settings.playerSort = "recent"
  for _, name in ipairs({ "Ñu Azul", "nadia Verde", "Óscar Rojo", "oca Gris" }) do
    SL.db.players[name] = nil
  end
end)

-- Notices ------------------------------------------------------------------------------------------------------------------
test("switching the loot method over and over warns every time but does not scream every time", function()
  joinGroup()
  SIM.now = SIM.now + 100
  SIM.sounds, SIM.warnings = {}, {}
  local alarm = SL.Theme.sound.alarm
  for i = 1, 20 do
    SIM.lootMethod = i % 2 == 1 and 0 or 2
    SIM.masterPartyID = 1
    SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  end
  local noise = 0
  for _, kit in ipairs(SIM.sounds) do
    if (type(kit) == "table" and kit[1] or kit) == alarm then noise = noise + 1 end
  end
  ok(#SIM.warnings >= 20, "warnings: " .. #SIM.warnings)
  eq(noise, 1, "sounds")
  SIM.lootMethod, SIM.masterPartyID = 3, nil
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  clearToasts()
end)

test("a leader writing line after line never fills the queue of notices, and a bad one always gets in", function()
  clearToasts()
  SL.Alert:Toast({ tone = "neutral", title = "shown", seconds = 10 })
  for i = 1, 30 do
    SIM.Fire("CHAT_MSG_PARTY_LEADER", "HR Objeto" .. i, "Krag-Hierro")
  end
  eq(#SL.Alert.queue, 1, "one suggestion waiting")
  ok(contains(SL.Alert.queue[1].title, L.SUGGEST_TITLE))
  for i = 1, 10 do
    SL.Alert:Toast({ tone = "neutral", title = "filler" .. i, seconds = 10 })
  end
  eq(#SL.Alert.queue, 4)
  SL.Alert:Toast({ tone = "bad", title = "ninja", seconds = 10 })
  eq(#SL.Alert.queue, 4)
  eq(SL.Alert.queue[4].title, "ninja")
  clearToasts()
end)

-- Rules --------------------------------------------------------------------------------------------------------------------
test("adopting other rules forgets the answers to the old ones", function()
  SIM.now = SIM.now + 100
  SL.Contract:Edit(function(c) c.needRule = "msos" end)
  ok(SL.Contract:Publish(), "published")
  SIM.Fire("CHAT_MSG_PARTY", "ok", "Zarn-Brasa")
  ok(next(SL.Contract:Get().accepted), "one ok")
  SL.Contract:Adopt({ needRule = "greed" }, "copied")
  local c = SL.Contract:Get()
  eq(c.publishedAt, nil)
  eq(next(c.accepted), nil)
  ok(not SL.Contract:Awaiting(), "a later ok is not an answer to these")
end)

test("saved rules are only trusted field by field", function()
  local c = SL.Contract.Sane({ method = {}, needRule = 7, leader = 5, accepted = { [1] = 2, ["Krag Hierro"] = "x", ["Zarn Brasa"] = 9 },
    reserves = { "junk", { item = "Yelmo", owner = {}, kind = {} }, { item = 4 } }, instance = "x" })
  eq(c.method, nil)
  eq(c.needRule, nil)
  eq(c.leader, nil)
  eq(c.instance, nil)
  eq(c.accepted["Krag Hierro"], nil)
  eq(c.accepted["Zarn Brasa"], 9)
  eq(#c.reserves, 1)
  eq(c.reserves[1].owner, nil)
  eq(c.reserves[1].kind, "hard")
  ok(type(SL.Contract:ShortSummary(c)) == "string")
end)

test("the check that was waiting does nothing when the group is already over", function()
  SIM.inGroup = false
  SL.Contract:Reset(nil)
  SL.Watcher.lastState = nil
  SL.Watcher:Check("join")
  eq(SL.Contract:Get(), nil)
  joinGroup()
end)

-- Journal ------------------------------------------------------------------------------------------------------------------
test("a session of a whole day keeps a limited number of drops, the newest", function()
  local run = SL.Run:Current() or SL.Run:Start("Prueba", false)
  run.drops = {}
  for i = 1, SL.Run.MAX_DROPS + 50 do
    SIM.now = SIM.now + 1
    SL.Run:LogDrop("k" .. i, "[Objeto]", "Zarn Brasa", "MAGE")
  end
  local n = 0
  for _ in pairs(run.drops) do n = n + 1 end
  eq(n, SL.Run.MAX_DROPS)
  ok(run.drops["k" .. (SL.Run.MAX_DROPS + 50)], "the newest")
  eq(run.drops.k1, nil)
end)

test("a loading screen with no place name does not end the run", function()
  SIM.inInstance, SIM.instanceType, SIM.instanceMapID = true, "party", STRAT
  SL.Run:Check()
  local id = SL.Run:Current().id
  local real = SL.API.PlaceName
  SL.API.PlaceName = function() return nil end
  SL.Run:Check()
  SL.API.PlaceName = real
  eq(SL.Run:Current().id, id)
  SIM.inInstance, SIM.instanceType, SIM.instanceMapID = false, "none", nil
end)

-- Settings and report --------------------------------------------------------------------------------------------------------
test("'Defaults' in the options restores the real defaults", function()
  for _, key in ipairs({ "alarmVoice", "memoryDays", "scale", "reduceMotion", "showMinimap" }) do
    eq(SIM.settingsRegistered[key].default, SL.Store.DEFAULTS.settings[key], key)
  end
end)

test("the report can be copied, without the character's name", function()
  SL:HandleSlash("test")
  local window = _G.SafeLootDiagnostics
  ok(window.Copy, "button")
  window.Copy:Click()
  local text = SL.Run.copyBox.Edit:GetText()
  ok(contains(text, "SafeLoot " .. SL.version), text:sub(1, 80))
  ok(not contains(text, "Paciente"), "no name")
  ok(not text:find("|T") and not text:find("|c"), "plain text")
  ok(contains(text, "[OK]"), "what works is said in words")
  _G.SafeLootCopy:Hide()
  window:Hide()
end)

test("only our own echo counts, and nothing about who sent it is saved", function()
  local report = SL.db.diagnostics.report
  report.addonEcho = nil
  SIM.Fire("CHAT_MSG_ADDON", "SafeLoot", "1|PING|" .. SL.Diagnostics.pingToken, "PARTY", "Zarn-Brasa")
  eq(report.addonEcho, nil, "someone else")
  SIM.Fire("CHAT_MSG_ADDON", "SafeLoot", "1|PING|" .. SL.Diagnostics.pingToken, "PARTY", "Ana Paciente")
  ok(report.addonEcho.PARTY.ms, "ours")
  eq(report.addonEcho.PARTY.sender, nil)
end)

-- Saved data -----------------------------------------------------------------------------------------------------------------
test("a damaged file is cleaned down to the last field", function()
  local db = { players = { ["Krag Hierro"] = { events = { { kind = "note", note = {}, t = "x", place = 5 } }, last = "ayer", seen = {}, class = 3 } },
    runs = { { events = { "x", { kind = "note", text = {} } }, drops = { a = 1, b = { item = {}, winner = 4 } } } },
    settings = { scale = 99, memoryDays = 0 / 0, minimapAngle = -50, playerSort = "x", language = "xx", exceptions = 4 },
    errors = { "x", { text = "bien" } }, diagnostics = { observed = { a = 4, b = { count = 2 } }, report = 5 } }
  SL.Store.Merge(db, SL.Store.DEFAULTS)
  SL.Store.Validate(db)
  local r = db.players["Krag Hierro"]
  eq(r.last, nil)
  eq(r.seen, nil)
  eq(r.class, nil)
  eq(r.events[1].note, nil)
  eq(r.events[1].place, nil)
  eq(#db.runs[1].events, 1)
  eq(db.runs[1].events[1].text, nil)
  eq(db.runs[1].drops.a, nil)
  eq(db.runs[1].drops.b.winner, nil)
  eq(db.settings.scale, 1.3)
  eq(db.settings.memoryDays, 90)
  eq(db.settings.minimapAngle, 0)
  eq(db.settings.playerSort, "recent")
  eq(db.settings.language, "auto")
  eq(type(db.settings.exceptions), "table")
  eq(#db.errors, 1)
  eq(db.diagnostics.observed.a, nil)
  eq(db.diagnostics.observed.b.count, 2)
  eq(db.diagnostics.report, nil)
  local char = { positions = { main = "x", alarm = { "CENTER", "CENTER", 1, 2 }, toast = { "CENTER", "CENTER", 0 / 0, 2 } }, run = { events = 4 } }
  SL.Store.ValidateChar(char)
  eq(char.positions.main, nil)
  eq(char.positions.toast, nil)
  ok(char.positions.alarm)
  eq(char.run, nil)
end)

test("a damaged error list never breaks the error handler", function()
  local real = SafeLootDB.errors
  SafeLootDB.errors = "x"
  SL:ReportError("test", "boom")
  eq(SafeLootDB.errors[1].text, "test: boom")
  SafeLootDB.errors = { "x" }
  SL:ReportError("test", "boom")
  eq(#SafeLootDB.errors, 2)
  SafeLootDB.errors = real
end)

test("observations with a damaged entry start again", function()
  SL.db.diagnostics.observed.unit_tooltip = 5
  SL.Diagnostics:Observe("unit_tooltip")
  eq(SL.db.diagnostics.observed.unit_tooltip.count, 1)
end)

test("group units: fixed lists, yourself included once", function()
  SIM.inRaid = true
  eq(#SL.API.GroupUnits(), 40)
  eq(SL.API.GroupUnits(), SL.API.GroupUnits(), "no new table each time")
  SIM.inRaid = false
  eq(table.concat(SL.API.GroupUnits(), ","), "player,party1,party2,party3,party4")
  SIM.inGroup = false
  eq(#SL.API.GroupUnits(), 1)
  SIM.inGroup = true
end)

test("rules saved in a damaged file are cleaned when they come back after a reload", function()
  local saved = { source = "proposed", method = {}, leader = "Krag Hierro", needRule = "msos", reserves = { "junk", { item = "Yelmo" } }, accepted = "x" }
  SL.char.contract = { contract = saved, leader = "Krag Hierro", t = SIM.now }
  ok(SL.Contract:Restore(), "restored")
  local c = SL.Contract:Get()
  eq(c.method, nil)
  eq(#c.reserves, 1)
  eq(type(c.accepted), "table")
  eq(c.needRule, "msos", "what is right is kept")
end)

test("a drop whose encounter the game hides is not even read", function()
  local reads, real = 0, SL.API.LootDrop
  SL.API.LootDrop = function(...) reads = reads + 1; return real(...) end
  SIM.secrets[555002] = true
  SIM.Fire("LOOT_HISTORY_UPDATE_DROP", 555002, 1)
  SIM.Fire("LOOT_HISTORY_UPDATE_DROP", 1, 555002)
  SIM.secrets[555002] = nil
  SL.API.LootDrop = real
  eq(reads, 0)
end)
