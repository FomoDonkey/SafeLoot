-- 0.5.3: notes say only what you wrote. Seen in the real client (2026-11-28): every note on the card came as
-- 'Note · <zone> · "text" (date time)', and the note itself was cut off.
local SL = NS
local L = SL.L
local M, MH = SL.Memory, SL.MemoryHooks
_G.SafeLootWelcome:Hide()

local DAY = 86400
local db = SafeLootDB.players
local function add(name, kind, daysAgo, extra)
  local e = { kind = kind, t = SIM.now - (daysAgo or 0) * DAY }
  for k, v in pairs(extra or {}) do e[k] = v end
  M.Add(db, name, e)
end
local NOTE = "buen tanque, nos ayudo media hora con una mision"
local MARK = string.format(L.EVENT_YOUR_MARK, L.EVENT_TAG_TRUSTED)

-- as saved by 0.5.3 and before: notes and marks carry the zone
add("Jota Clara", "note", 0, { note = NOTE, place = "Bosque del Ocaso" })
add("Jota Clara", "tag_trusted", 0, { place = "Bosque del Ocaso" })
add("Jota Clara", "need_impossible", 1, { item = "Gran espada", place = "Stratholme" })
add("Solo Marca", "tag_ninja", 2, { place = "Bosque del Ocaso" })

local function page() return SL.MainFrame.pages.players end
local function card(name)
  SL.MainFrame:Open("players")
  page().selected = name
  SL.MainFrame:Refresh()
  local byKind = {}
  for _, item in ipairs(page().Notes.provider.items) do
    byKind[item.event.kind] = item
  end
  return page().Notes.provider.items, byKind
end

test("on the card a note is only what you wrote, and when in grey: no zone, no time, no 'Note'", function()
  local items, by = card("Jota Clara")
  eq(#items, 3)
  eq(by.note.text, NOTE, "the note, whole and alone")
  eq(by.note.when, L.AGO_TODAY)
  local row = SIM.newWidget("Button")
  page().Notes.view.init(row, by.note)
  eq(row.Text:GetText(), NOTE)
  ok(contains(row.When:GetText(), L.AGO_TODAY), "when, under it")
  ok(not contains(row.Text:GetText() .. row.When:GetText(), "Bosque"), "no zone")
  ok(not contains(row.When:GetText(), ":"), "no clock time")
end)

test("your mark says it is your opinion, without the zone", function()
  local _, by = card("Jota Clara")
  ok(contains(by.tag_trusted.text, MARK), by.tag_trusted.text)
  ok(not contains(by.tag_trusted.text .. by.tag_trusted.when, "Bosque"), "no zone")
end)

test("what the addon saw keeps where it happened", function()
  local _, by = card("Jota Clara")
  ok(contains(by.need_impossible.text, L.EVENT_NEED_IMPOSSIBLE) and contains(by.need_impossible.text, "Gran espada"))
  ok(contains(by.need_impossible.when, "Stratholme") and contains(by.need_impossible.when, L.AGO_YESTERDAY))
end)

test("hovering a row shows it whole, with the exact date and the place", function()
  local _, by = card("Jota Clara")
  local row = SIM.newWidget("Button")
  page().Notes.view.init(row, by.note)
  GameTooltip._lines = {}
  row:Fire("OnEnter")
  eq(GameTooltip:GetText(), L.EVENT_NOTE)
  local lines = table.concat(GameTooltip._lines, "\n")
  ok(contains(lines, NOTE), "the whole note")
  ok(contains(lines, "Bosque del Ocaso"), "the zone is one hover away")
  ok(contains(lines, SL.UI.FormatDate(SIM.now)), "and the exact date")
end)

test("the player tooltip shows your note and what the addon saw, not the zone or your mark again", function()
  local tip = table.concat(MH:TooltipLines("Jota Clara"), "\n")
  ok(contains(tip, "\"" .. NOTE .. "\""), "your note")
  ok(contains(tip, "Gran espada") and contains(tip, "Stratholme"), "what the addon saw, with where")
  ok(not contains(tip, "Bosque"), "no zone on your note or mark")
  ok(not contains(tip, MARK), "your mark is already the big word")
  ok(contains(tip, M.Upper(L.CAT_TRUSTED)), "the big word")
end)

test("a notice about someone with only a mark says the mark and when", function()
  local record = db["Solo Marca"]
  local body = MH.NoticeBody(record, M.Summary(record, SIM.now, SL.settings.memoryDays))
  ok(contains(body, string.format(L.EVENT_YOUR_MARK, L.EVENT_TAG_NINJA)), body)
  ok(contains(body, string.format(L.AGO_DAYS, 2)))
  ok(not contains(body, "Bosque"), "no zone")
end)

test("a removed note leaves the card at once", function()
  local _, by = card("Jota Clara")
  local row = SIM.newWidget("Button")
  page().Notes.view.init(row, by.note)
  row.Remove:Click()
  SL.MainFrame:Refresh()
  local items = card("Jota Clara")
  eq(#items, 2)
  for _, item in ipairs(items) do
    ok(item.event.kind ~= "note", "the note is gone")
  end
end)

test("when your mark is the newest thing, the tooltip still does not repeat it", function()
  add("Marca Nueva", "need_doubtful", 3, { item = "Anillo", place = "Stratholme" })
  add("Marca Nueva", "tag_ninja", 0, { place = "Bosque del Ocaso" })
  local tip = table.concat(MH:TooltipLines("Marca Nueva"), "\n")
  ok(not contains(tip, string.format(L.EVENT_YOUR_MARK, L.EVENT_TAG_NINJA)), tip)
  ok(contains(tip, "Anillo"), "what the addon saw before your mark")
  local only = table.concat(MH:TooltipLines("Solo Marca"), "\n")
  ok(not contains(only, string.format(L.EVENT_YOUR_MARK, L.EVENT_TAG_NINJA)), only)
  ok(contains(only, M.Upper(L.CAT_NINJA)), "the big word")
end)
