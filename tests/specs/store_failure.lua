-- 0.5.2: if reading the saved data fails, the session starts empty but what was saved is NOT replaced.
local SL = NS
test("a failure reading the saved data never erases it", function()
  ok(SL.Store.failed, "the failure happened")
  ok(SafeLootDB.players["Krag Hierro"], "the marks are still in the file that is saved at logout")
  eq(SafeLootDB.players["Krag Hierro"].events[1].kind, "tag_ninja")
  ok(SL.db ~= SafeLootDB, "the session works on a copy")
  ok(SL.settings.alarmSound, "with the defaults")
  SL.Memory.Add(SL.db.players, "Zarn Brasa", { kind = "tag_trusted", t = SIM.now })
  eq(SafeLootDB.players["Zarn Brasa"], nil, "nothing is mixed into the saved data")
end)
test("the player is told, and the alarm works", function()
  local told = false
  for _, line in ipairs(SIM.chatOutput) do
    told = told or contains(line, SL.L.STORE_FALLBACK)
  end
  ok(told, "message")
  SL:HandleSlash("alarm")
  ok(_G.SafeLootAlarmPanel:IsShown(), "panel")
  SafeLootDB.errors = {} -- (the failure itself is recorded: expected here)
end)
