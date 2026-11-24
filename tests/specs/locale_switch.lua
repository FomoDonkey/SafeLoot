-- English client, language "auto": English texts, English commands.
local SL = NS
test("English client gets English", function()
  eq(SL.language, "enUS")
  eq(SL.L.ALARM_ML_TITLE, "The leader switched to MASTER LOOT!")
  eq(BINDING_NAME_SAFELOOT_TOGGLE, "Open / close SafeLoot")
end)
test("English command opens the demo alarm", function()
  SL:HandleSlash("alarm")
  ok(_G.SafeLootAlarmPanel:IsShown(), "panel")
  eq(SIM.warnings[1], "The leader switched to MASTER LOOT!")
end)
test("help lists English commands only once (aliases hidden)", function()
  SIM.chatOutput = {}
  SL:HandleSlash("help-unknown")
  local text = table.concat(SIM.chatOutput, "\n")
  ok(contains(text, "/safeloot alarm"), "alarm listed")
  ok(not contains(text, "/safeloot alarma"), "alias hidden")
end)
