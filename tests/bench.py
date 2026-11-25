"""SafeLoot offline benchmark: time and garbage of the hot paths with big data, in real Lua 5.1 (lupa).

    uv run --with lupa python tests/bench.py

Numbers are for comparing two versions on the same computer. The game runs the same Lua 5.1 with its own API cost, so
this does NOT say how long anything takes inside the client.
"""
import os
import sys

try:
    from lupa import lua51
except ImportError:
    print("lupa is missing. Run: uv run --with lupa python tests/bench.py")
    sys.exit(2)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute(read("tests/wow_mock.lua"))
lua.execute("NS = {}")
runner = lua.eval("function(src, name) local f = assert(loadstring(src, '@' .. name)); f('SafeLoot', NS) end")
for line in read("SafeLoot.toc").splitlines():
    line = line.strip().replace("\\", "/")
    if line and not line.startswith("#") and line.endswith(".lua"):
        runner(read(line), line)
lua.execute("SIM.Fire('ADDON_LOADED', 'SafeLoot')")
lua.execute(read("SafeLoot_LootData/Data.lua"))
lua.execute("SIM.Fire('PLAYER_LOGIN'); SIM.RunTimers()")

lua.execute(r"""
local SL = NS
local clock = os.clock
function BENCH(name, n, fn)
  fn() -- warm up
  collectgarbage("collect"); collectgarbage("collect"); collectgarbage("stop")
  local m0, t0 = collectgarbage("count"), clock()
  for i = 1, n do fn(i) end
  local t, m = clock() - t0, collectgarbage("count") - m0
  collectgarbage("restart"); collectgarbage("collect")
  print(string.format("%-46s %9.3f ms  %9.2f KB garbage", name, t * 1000 / n, m / n))
end

-- 2000 remembered players, some with events; 50 runs
local now = SIM.now
for i = 1, 2000 do
  local name = "Jugador" .. i .. " Ñandú" .. (i % 37)
  SL.db.players[name] = { events = {}, seen = i % 9, last = now - i * 60, class = "MAGE" }
  if i % 4 == 0 then
    SL.Memory.Add(SL.db.players, name, { kind = "tag_ninja", t = now - i * 60, place = "Stratholme" })
    SL.Memory.Add(SL.db.players, name, { kind = "note", t = now - i * 60, note = "una nota" })
  end
end
for r = 1, 50 do
  local run = { id = "r" .. r, place = "Stratholme", startedAt = now - r * 9000, endedAt = now - r * 8000, instance = true, members = {}, events = {}, drops = {} }
  for e = 1, 30 do
    run.events[e] = { kind = "note", t = now - r * 9000 + e, text = "evento " .. e }
    run.drops["d" .. e] = { item = "[Objeto " .. e .. "]", winner = "Jugador" .. e .. " X", t = now - r * 9000 + e }
  end
  SL.db.runs[r] = run
end

BENCH("event that nobody cares about (CHAT_MSG_ADDON)", 20000, function() SIM.Fire("CHAT_MSG_ADDON", "OtherAddon", "x", "PARTY", "Someone Else") end)
BENCH("item loaded by the game (ITEM_DATA_LOAD_RESULT)", 20000, function() SIM.Fire("ITEM_DATA_LOAD_RESULT", 12345, true) end)
BENCH("target change on a stranger", 5000, function() SIM.Fire("PLAYER_TARGET_CHANGED") end)

SL.MainFrame:Open("players")
BENCH("players tab: refresh", 10, function() SL.MainFrame:Refresh() end)
local page = SL.MainFrame.pages.players
BENCH("players tab: one letter typed", 10, function(i) page.Search:SetText("juga" .. ((i or 0) % 9)); SL.MainFrame:Refresh() end)
page.Search:SetText("")
SL.settings.playerSort = "name"
BENCH("players tab: refresh, A-Z", 5, function() SL.MainFrame:Refresh() end)
SL.settings.playerSort = "recent"
SL.MainFrame:Open("journal")
BENCH("journal tab: refresh", 10, function() SL.MainFrame:Refresh() end)
BENCH("journal tab: items loading (CATALOG_CHANGED)", 10, function() SL:Fire("CATALOG_CHANGED") end)

SL.LootPicker:Open(nil)
BENCH("loot picker: list of dungeons", 20, function() SL.LootPicker:Refresh() end)
SL.LootPicker:Open(329)
BENCH("loot picker: Stratholme", 20, function() SL.LootPicker:Refresh() end)
SL.MainFrame.frame:Hide()

-- a raid of 40
SIM.inGroup, SIM.inRaid, SIM.groupSize = true, true, 40
for i = 1, 40 do
  SIM.units["raid" .. i] = { first = "Banda" .. i, second = "Cuarenta", class = "WARRIOR" }
end
SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.RunTimers()
BENCH("raid of 40: roster change, all modules", 50, function() SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.RunTimers() end)
local link = "|cff0070dd|Hitem:13346::::::::60:::::|h[Robes of the Exalted]|h|r"
SIM.items[link] = { itemID = 13346, equipLoc = "INVTYPE_ROBE", classID = 4, subClassID = 1, name = "Robes of the Exalted", quality = 3, bindType = 1 }
local rolls = {}
for i = 1, 40 do
  rolls[i] = { playerName = "Banda" .. i .. " Cuarenta", playerClass = "WARRIOR", state = i % 3 == 0 and 0 or 3, isSelf = false }
end
SIM.lootDrops["100:1"] = { itemHyperlink = link, rollInfos = rolls }
BENCH("raid of 40: one update of a roll", 200, function() SIM.Fire("LOOT_HISTORY_UPDATE_DROP", 100, 1) end)
BENCH("group chat line (not the leader)", 2000, function(i) SIM.Fire("CHAT_MSG_RAID", "vamos a por el siguiente jefe " .. (i or 0), "Banda7 Cuarenta") end)
BENCH("group chat line (the leader)", 2000, function(i) SIM.Fire("CHAT_MSG_RAID_LEADER", "vamos a por el siguiente jefe " .. (i or 0), "Banda1 Cuarenta") end)
print("internal errors: " .. #(SafeLootDB.errors or {}))
for _, e in ipairs(SafeLootDB.errors or {}) do print("  " .. e.text:sub(1, 300)) end
""")
