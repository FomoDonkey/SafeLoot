-- SavedVariables damaged by hand: wrong types everywhere. The addon must start and clean them.
local SL = NS
test("damaged saved data is cleaned, the addon starts", function()
  ok(SL.settings, "settings exist")
  eq(type(SafeLootDB.players), "table")
  eq(SafeLootDB.players["Bad Record"], nil, "non-table record dropped")
  eq(#SafeLootDB.players["Half Ok"].events, 1, "invalid events dropped")
  eq(SafeLootDB.settings.alarmSound, true, "wrong type reset to default")
  eq(#SafeLootDB.runs, 0, "broken runs dropped")
end)
test("alarm still works after cleaning", function()
  SL:HandleSlash("alarm")
  ok(_G.SafeLootAlarmPanel:IsShown(), "panel")
end)
