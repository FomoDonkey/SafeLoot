-- The run journal and the end-of-run summary (docs/PROMPT_MAESTRO.md §4.5).
-- A session starts when you join a group (in the world or in an instance) and ends when you leave the group.
-- Entering an instance turns the session into that instance's run; leaving the instance for good (10 minutes
-- outside, or another instance) ends it. Everything the other modules notice is logged here.
local _, SL = ...
local Run = SL:NewModule("Run")
SL.Run = Run
local API, UI, T, L = SL.API, SL.UI, SL.Theme, SL.L

function Run:Current()
  return SL.char and SL.char.run or nil
end

function Run:Start(place, isInstance)
  local run = {
    instance = isInstance and true or false,
    id = tostring(API.Now()) .. "-" .. math.random(1000, 9999),
    startedAt = API.Now(),
    place = place or API.PlaceName() or "?",
    members = {},
    events = {},
    drops = {},
  }
  SL.char.run = run
  self:UpdateMembers()
  SL:Fire("RUN_STARTED", run)
  return run
end

function Run:UpdateMembers()
  local run = self:Current()
  if not run then
    return
  end
  for _, member in ipairs(API.GroupMembers()) do
    if not SL.Names.IsMe(member.name) then
      run.members[member.name] = member.class or run.members[member.name] or true
    end
  end
end

-- kind: "rules_changed" | "mark" | "contract" | "agreed" | "note"
function Run:Log(kind, data)
  local run = self:Current()
  if not run then
    return
  end
  data = data or {}
  data.kind, data.t = kind, API.Now()
  table.insert(run.events, data)
  while #run.events > 200 do
    table.remove(run.events, 1)
  end
end

function Run:LogDrop(key, item, winner, winnerClass)
  local run = self:Current()
  if not run then
    return
  end
  run.drops[key] = { item = item, winner = winner, class = winnerClass, t = API.Now() }
end

function Run:Finish()
  local run = self:Current()
  if not run then
    return
  end
  SL.char.run = nil
  run.endedAt = API.Now()
  -- everyone you played with is "seen" in your memory (no judgement, just "met before"), even in a quiet group:
  -- that is how the Players tab can list the people you grouped with
  if SL.settings.memory then
    for name, class in pairs(run.members) do
      SL.Memory.Add(SL.db.players, name, { kind = "grouped", t = run.endedAt, class = type(class) == "string" and class or nil })
    end
  end
  local hasContent = #run.events > 0 or next(run.drops) ~= nil
  if not hasContent then
    return
  end
  table.insert(SL.db.runs, run)
  while #SL.db.runs > 50 do
    table.remove(SL.db.runs, 1)
  end
  SL:Fire("RUN_FINISHED", run)
  if not SL.settings.summaryAlways and not Run:HasIssues(run) then
    return -- saved in the journal; the summary only pops up when something happened
  end
  SL:AfterCombat("run-summary", function()
    Run:ShowSummary(run)
  end)
end

function Run:HasIssues(run)
  for _, event in ipairs(run.events or {}) do
    if event.kind == "mark" or (event.kind == "rules_changed" and (event.severity or 0) >= 2) then
      return true
    end
  end
  return false
end

-- Summary text (also used by "Copy summary").
function Run:SummaryLines(run)
  local lines = {}
  local broken = false
  for _, event in ipairs(run.events) do
    if event.kind == "rules_changed" and (event.severity or 0) >= 2 then
      broken = true -- same threshold that makes the summary pop up
    end
  end
  lines[#lines + 1] = string.format(L.SUMMARY_HEADER, run.place or "?", UI.FormatDate(run.startedAt))
  if broken then
    lines[#lines + 1] = "|T" .. T.tex.bad .. ":14:14|t " .. T.Paint(L.SUMMARY_BROKEN, T.color.red)
  else
    lines[#lines + 1] = "|T" .. T.tex.ok .. ":14:14|t " .. T.Paint(L.SUMMARY_KEPT, T.color.green)
  end
  for _, event in ipairs(run.events) do
    if event.text then
      lines[#lines + 1] = UI.FormatDate(event.t):sub(7) .. "  " .. event.text
    end
  end
  for _, drop in pairs(run.drops) do
    if drop.winner then
      lines[#lines + 1] = string.format(L.SUMMARY_DROP, drop.item or "?", drop.winner)
    end
  end
  return lines
end

local function stripCodes(text)
  return (text:gsub("|T.-|t", ""):gsub("|cn[%w_]+:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", ""))
end

function Run:ShowSummary(run)
  if not self.summary then
    local card = UI.Card(UIParent, 440, 300, "SafeLootSummary")
    card:SetFrameStrata("DIALOG")
    UI.Movable(card, "summary", { "CENTER", UIParent, "CENTER", 0, 80 })
    card.Title = UI.Text(card, "title", L.SUMMARY_TITLE, "LEFT")
    card.Title:SetPoint("TOPLEFT", 20, -20)
    card.Body = UI.Text(card, "small", "", "LEFT")
    card.Body:SetPoint("TOPLEFT", card.Title, "BOTTOMLEFT", 0, -10)
    card.Body:SetPoint("RIGHT", -20, 0)
    card.Body:SetJustifyV("TOP")
    card.Body:SetSpacing(3)
    UI.EnableLinks(card)
    local close = UI.Create("Button", card, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    card.Copy = UI.Button(card, L.SUMMARY_COPY, 130, function()
      Run:ShowCopyBox(card.text or "")
    end, L.SUMMARY_COPY, L.SUMMARY_COPY_TIP)
    card.Copy:SetPoint("BOTTOMLEFT", 18, 16)
    card.Open = UI.Button(card, L.SUMMARY_OPEN, 130, function()
      if SL.MainFrame then
        SL.MainFrame:Open("journal")
      end
      card:Hide()
    end)
    card.Open:SetPoint("LEFT", card.Copy, "RIGHT", 8, 0)
    card.Ok = UI.Button(card, OKAY or "OK", 90, function()
      card:Hide()
    end)
    card.Ok:SetPoint("BOTTOMRIGHT", -18, 16)
    if UISpecialFrames then
      table.insert(UISpecialFrames, "SafeLootSummary")
    end
    self.summary = card
  end
  local lines = self:SummaryLines(run)
  local shown = {}
  for i = 1, math.min(#lines, 12) do
    shown[i] = lines[i]
  end
  if #lines > 12 then
    shown[#shown + 1] = string.format(L.SUMMARY_MORE, #lines - 12)
  end
  self.summary.Body:SetText(table.concat(shown, "\n"))
  local plain = {}
  for i, line in ipairs(lines) do
    plain[i] = stripCodes(line)
  end
  self.summary.text = table.concat(plain, "\n")
  self.summary:SetHeight(math.max(200, (self.summary.Body:GetStringHeight() or 120) + 110))
  UI.FadeIn(self.summary)
end

function Run:ShowCopyBox(text)
  if not self.copyBox then
    local card = UI.Card(UIParent, 460, 220, "SafeLootCopy")
    card:SetFrameStrata("FULLSCREEN_DIALOG")
    card:SetPoint("CENTER")
    local title = UI.Text(card, "header", L.COPY_HINT, "LEFT")
    title:SetPoint("TOPLEFT", 20, -18)
    local scroll = UI.Create("ScrollFrame", card, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -42)
    scroll:SetPoint("BOTTOMRIGHT", -40, 50)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(true)
    edit:SetFontObject(T.Font("small"))
    edit:SetWidth(390)
    edit:SetScript("OnEscapePressed", function()
      card:Hide()
    end)
    scroll:SetScrollChild(edit)
    card.Edit = edit
    local ok = UI.Button(card, CLOSE or "Close", 100, function()
      card:Hide()
    end)
    ok:SetPoint("BOTTOMRIGHT", -18, 14)
    if UISpecialFrames then
      table.insert(UISpecialFrames, "SafeLootCopy")
    end
    self.copyBox = card
  end
  self.copyBox.Edit:SetText(text)
  self.copyBox.Edit:HighlightText()
  self.copyBox:Show()
  self.copyBox.Edit:SetFocus()
end

-- Lifecycle -------------------------------------------------------------------------------------------
Run.OUTSIDE_GRACE = 600 -- seconds outside the instance (still grouped) before the run counts as finished

function Run:Check()
  local inInstance = API.InInstance()
  local inGroup = API.InGroup()
  local run = self:Current()
  if not inGroup then
    if run then
      self:Finish()
    end
    return
  end
  local place = API.PlaceName()
  if inInstance then
    if run and run.instance and run.place ~= place then
      self:Finish() -- a different instance: the previous run is over
      run = nil
    end
    if run and not run.instance then
      -- the group session becomes this instance's run (rules agreed at the meeting stone stay with it)
      run.instance, run.place, run.outsideSince = true, place or run.place, nil
      self:UpdateMembers()
    elseif not run then
      self:Start(place, true)
    else
      run.outsideSince = nil
      self:UpdateMembers()
    end
  elseif not run then
    self:Start(place, false) -- a group in the open world
  elseif not run.instance then
    self:UpdateMembers()
  elseif run then
    -- released as a ghost, went out to repair or to summon: the run goes on for a while
    run.outsideSince = run.outsideSince or API.Now()
    if API.Now() - run.outsideSince >= Run.OUTSIDE_GRACE then
      self:Finish()
    elseif C_Timer and C_Timer.After and not self.graceTimer then
      self.graceTimer = true
      C_Timer.After(Run.OUTSIDE_GRACE + 1, function()
        Run.graceTimer = nil
        SL.SafeCall("Run.grace", Run.Check, Run)
      end)
    end
  end
end

function Run:OnEnable()
  local function check()
    SL:Debounce("run-check", 0.5, function()
      Run:Check()
    end)
  end
  SL:RegisterEvent("PLAYER_ENTERING_WORLD", self, function()
    Run:Check() -- immediate: a loading screen is a real change of place
  end)
  SL:RegisterEvent("GROUP_ROSTER_UPDATE", self, check)
  SL:RegisterEvent("GROUP_LEFT", self, function()
    Run:Check()
  end)
  self:Check()
end
