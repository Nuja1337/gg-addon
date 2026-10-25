-- The stubs in wow.lua: what a test can set, and what the addon sees.

T.test("the clock stands still until the test advances it", function()
  local t0, s0 = GetTime(), GetServerTime()
  T.eq(GetTime(), t0)
  T.eq(time(), s0)
  T.eq(os.time(), s0)
  WOW.advance(90)
  T.eq(GetTime(), t0 + 90)
  T.eq(GetServerTime(), s0 + 90)
  T.eq(debugprofilestop(), (t0 + 90) * 1000)
  WOW.reset({ time = 1000, uptime = 50 })
  T.eq(GetServerTime(), 1000)
  T.eq(GetTime(), 50)
  WOW.setServerTime(2000)
  T.eq(GetServerTime(), 2000)
  T.eq(GetTime(), 50)
end)

T.test("timers run in order of time, and see the clock at their own time", function()
  local log = {}
  local start = GetTime()
  -- string.format, not .., builds text from a number: 5.3 would print 10.0 where 5.1 prints 10 (README.md).
  C_Timer.After(30, function() log[#log + 1] = string.format("b@%d", GetTime() - start) end)
  C_Timer.After(10, function() log[#log + 1] = string.format("a@%d", GetTime() - start) end)
  C_Timer.After(30, function() log[#log + 1] = string.format("c@%d", GetTime() - start) end)
  T.eq(WOW.advance(9), 0)
  T.same(log, {})
  T.eq(WOW.advance(21), 3)
  T.same(log, { "a@10", "b@30", "c@30" })
  T.eq(GetTime(), start + 30)
end)

T.test("a ticker runs until cancelled or out of runs, and a timer once", function()
  local ticks, limited, once = 0, 0, 0
  local ticker = C_Timer.NewTicker(5, function() ticks = ticks + 1 end)
  C_Timer.NewTicker(5, function() limited = limited + 1 end, 3)
  C_Timer.NewTimer(5, function() once = once + 1 end)
  WOW.advance(50)
  T.eq(ticks, 10)
  T.eq(limited, 3)
  T.eq(once, 1)
  ticker:Cancel()
  T.truthy(ticker:IsCancelled())
  WOW.advance(50)
  T.eq(ticks, 10)
end)

T.test("a timer set from a timer runs when it falls due, and a zero delay runs on the next advance", function()
  local order = {}
  C_Timer.After(1, function()
    order[#order + 1] = "first"
    C_Timer.After(1, function() order[#order + 1] = "second" end)
  end)
  WOW.advance(1.5)
  T.same(order, { "first" })
  WOW.advance(1)
  T.same(order, { "first", "second" })
  C_Timer.After(0, function() order[#order + 1] = "now" end)
  T.eq(#order, 2)
  WOW.advance(0)
  T.eq(order[3], "now")
end)

T.test("frames get the events they registered for, in the order they were made", function()
  local got = {}
  local a, b = CreateFrame("Frame"), CreateFrame("Frame", "NamedFrame")
  T.eq(NamedFrame, b)
  T.eq(b:GetName(), "NamedFrame")
  a:RegisterEvent("PLAYER_LOGIN")
  b:RegisterEvent("PLAYER_LOGIN")
  b:RegisterEvent("GROUP_ROSTER_UPDATE")
  a:SetScript("OnEvent", function(self, event, ...) got[#got + 1] = "a:" .. event .. ":" .. select("#", ...) end)
  b:SetScript("OnEvent", function(self, event, x) got[#got + 1] = "b:" .. event .. ":" .. tostring(x) end)
  b:HookScript("OnEvent", function(self, event) got[#got + 1] = "hook:" .. event end)
  T.truthy(a:IsEventRegistered("PLAYER_LOGIN"))
  T.eq(WOW.fire("PLAYER_LOGIN"), 2)
  T.eq(WOW.fire("GROUP_ROSTER_UPDATE", 7), 1)
  a:UnregisterEvent("PLAYER_LOGIN")
  T.eq(WOW.fire("PLAYER_LOGIN"), 1)
  T.eq(WOW.fire("NOT_REGISTERED"), 0)
  T.same(got, { "a:PLAYER_LOGIN:0", "b:PLAYER_LOGIN:nil", "hook:PLAYER_LOGIN", "b:GROUP_ROSTER_UPDATE:7",
    "hook:GROUP_ROSTER_UPDATE", "b:PLAYER_LOGIN:nil", "hook:PLAYER_LOGIN" })
  T.truthy(b:GetScript("OnEvent"))
end)

T.test("an error in a handler reaches the test, or is recorded when catchErrors is on", function()
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("PLAYER_LOGIN")
  frame:SetScript("OnEvent", function() error("boom") end)
  T.raises(function() WOW.fire("PLAYER_LOGIN") end, "boom")
  WOW.catchErrors = true
  WOW.fire("PLAYER_LOGIN")
  T.eq(#WOW.errors, 1)
  T.truthy(WOW.errors[1]:find("boom", 1, true))
end)

T.test("a raid: roster rows, GUIDs, names, classes", function()
  WOW.setPlayer({ name = "Rhona Tester", class = "MAGE", guid = "Player-9001-0000AAAA" })
  WOW.setRoster({
    { name = "Tolvar Ashgrove", class = "WARRIOR", subgroup = 1 },
    { name = "Mirel Dawnwhisper", class = "PRIEST", subgroup = 2, online = false },
  })
  T.truthy(IsInRaid())
  T.truthy(IsInGroup())
  T.eq(GetNumGroupMembers(), 3)
  -- The player is added first, as the leader.
  local name, rank, _, _, class, fileName = GetRaidRosterInfo(1)
  T.eq(name, "Rhona Tester")
  T.eq(rank, 2)
  T.eq(fileName, "MAGE")
  T.eq(class, "Mage")
  T.eq(UnitGUID("raid1"), "Player-9001-0000AAAA")
  T.eq(UnitGUID("player"), "Player-9001-0000AAAA")
  local name2, _, sub2, _, _, file2, _, online2 = GetRaidRosterInfo(3)
  T.same({ name2, sub2, file2, online2 }, { "Mirel Dawnwhisper", 2, "PRIEST", false })
  T.truthy(UnitGUID("raid2"):find("^Player%-%d+%-%x+$"))
  T.truthy(UnitGUID("raid2") ~= UnitGUID("raid3"))
  local first, surname = UnitName("raid2")
  T.same({ first, surname }, { "Tolvar", "Ashgrove" })
  T.same({ UnitClass("raid3") }, { "Priest", "PRIEST", 5 })
  T.eq(GetRaidRosterInfo(4), nil)
  T.eq(UnitGUID("raid4"), nil)
  T.eq(UnitGUID("party1"), nil)
  WOW.setRoster(nil)
  T.eq(IsInGroup(), false)
  T.eq(GetNumGroupMembers(), 0)
end)

T.test("a party counts the player but numbers only the others", function()
  WOW.setRoster({ { name = "Tolvar Ashgrove", class = "WARRIOR" } }, "party")
  T.eq(IsInRaid(), false)
  T.truthy(IsInGroup())
  T.eq(GetNumGroupMembers(), 2)
  T.eq(UnitName("party1"), "Tolvar")
  T.eq(UnitName("party2"), nil)
  T.eq(GetRaidRosterInfo(1), nil)
end)

T.test("the instance, the guild, the build and the locale", function()
  T.eq(select(2, GetInstanceInfo()), "none")
  WOW.setInstance({ name = "Test Raid", type = "raid", difficultyID = 9, difficultyName = "40 Player", maxPlayers = 40,
    instanceID = 1234, instanceGroupSize = 25 })
  local name, kind, difficulty, difficultyName, maxPlayers, _, _, id, size = GetInstanceInfo()
  T.same({ name, kind, difficulty, difficultyName, maxPlayers, id, size },
    { "Test Raid", "raid", 9, "40 Player", 40, 1234, 25 })
  T.eq(GetGuildInfo("player"), nil)
  WOW.setGuild({ name = "Test Guild", rank = "Officer", rankIndex = 1, realm = "Test Subrealm" })
  T.same({ GetGuildInfo("player") }, { "Test Guild", "Officer", 1, "Test Subrealm" })
  local version, build, date, toc = GetBuildInfo()
  T.same({ version, build, date, toc }, { "1.60.1", "70532", "Oct 20 2026", 16001 })
  T.eq(GetLocale(), "enUS")
  T.eq(GetRealmName(), "Classic Beta PvP")
  T.eq(WOW_PROJECT_ID, 18)
end)

T.test("addon messages go to the outbox, and the limits are the game's", function()
  local R = Enum.SendAddonMessageResult
  T.truthy(C_ChatInfo.RegisterAddonMessagePrefix("GGTEST"))
  T.eq(C_ChatInfo.RegisterAddonMessagePrefix("A prefix longer than sixteen"), false)
  T.eq(C_ChatInfo.SendAddonMessage("GGTEST", "hi", "RAID"), R.NotInGroup)
  WOW.setRoster({ { name = "Tolvar Ashgrove" } })
  T.eq(C_ChatInfo.SendAddonMessage("GGTEST", "hi", "RAID"), R.Success)
  T.eq(C_ChatInfo.SendAddonMessage("GGTEST", string.rep("x", 256), "RAID"), R.InvalidMessage)
  T.eq(C_ChatInfo.SendAddonMessage("GGTEST", "hi", "WHISPER"), R.TargetRequired)
  T.eq(C_ChatInfo.SendAddonMessage("GGTEST", "hi", "WHISPER", "Tolvar Ashgrove"), R.Success)
  T.eq(C_ChatInfo.SendAddonMessage("GGTEST", "hi", "NOWHERE"), R.InvalidChatType)
  T.same(WOW.outbox, {
    { prefix = "GGTEST", text = "hi", chatType = "RAID", at = GetServerTime() },
    { prefix = "GGTEST", text = "hi", chatType = "WHISPER", target = "Tolvar Ashgrove", at = GetServerTime() },
  })
end)

T.test("a prefix is throttled to 10 messages, refilled one a second; a lockdown refuses all", function()
  local R = Enum.SendAddonMessageResult
  WOW.setRoster({ { name = "Tolvar Ashgrove" } })
  local sent = 0
  for _ = 1, 12 do
    if C_ChatInfo.SendAddonMessage("GGTEST", "x", "RAID") == R.Success then sent = sent + 1 end
  end
  T.eq(sent, 10)
  T.eq(C_ChatInfo.SendAddonMessage("GGTEST", "x", "RAID"), R.AddonMessageThrottle)
  WOW.advance(2)
  T.eq(C_ChatInfo.SendAddonMessage("GGTEST", "x", "RAID"), R.Success)
  WOW.lockdown = true
  T.eq(C_ChatInfo.SendAddonMessage("OTHER", "x", "RAID"), R.AddOnMessageLockdown)
  T.eq(#WOW.outbox, 11)
end)

T.test("WOW.receive fires CHAT_MSG_ADDON", function()
  local frame, got = CreateFrame("Frame"), nil
  frame:RegisterEvent("CHAT_MSG_ADDON")
  frame:SetScript("OnEvent", function(_, _, prefix, text, channel, sender) got = { prefix, text, channel, sender } end)
  WOW.receive("GGTEST", "hello", "RAID", "Tolvar Ashgrove")
  T.same(got, { "GGTEST", "hello", "RAID", "Tolvar Ashgrove" })
end)

T.test("print goes to the fake chat window, and slash commands run", function()
  print("a", 1, nil)
  DEFAULT_CHAT_FRAME:AddMessage("b")
  T.same(WOW.chat, { "a 1 nil", "b" })
  local got
  SLASH_TESTCMD1 = "/test"
  SLASH_TESTCMD2 = "/tst"
  SlashCmdList.TESTCMD = function(rest) got = rest end
  T.truthy(WOW.slash("/tst import now"))
  T.eq(got, "import now")
  T.eq(WOW.slash("/nothing"), false)
  WOW.reset()
  T.eq(SLASH_TESTCMD1, nil)
  T.eq(SlashCmdList.TESTCMD, nil)
end)

T.test("saved variables load at ADDON_LOADED and are written as Lua text at logout", function()
  WOW.declareSavedVariables("ProbeDB")
  WOW.saved.ProbeDB = { schema = 1, seen = { "a", "b" } }
  local seenAtLoad
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("ADDON_LOADED")
  frame:SetScript("OnEvent", function(_, _, name) if name == "Probe" then seenAtLoad = ProbeDB end end)
  WOW.loadAddon("Probe", {})
  T.same(seenAtLoad, { schema = 1, seen = { "a", "b" } })
  ProbeDB.schema = 2
  ProbeDB.scores = { [3] = 0.5, name = "x\ny", flag = false }
  ProbeDB.callback = function() end
  local saved = WOW.logout()
  T.same(saved.ProbeDB, { schema = 2, seen = { "a", "b" }, scores = { [3] = 0.5, name = "x\ny", flag = false } })
  T.truthy(WOW.savedFile:find("ProbeDB = {", 1, true))
  T.eq(WOW.saved.ProbeDB == ProbeDB, false)
  ProbeDB.bad = 0 / 0
  T.raises(function() WOW.logout() end, "cannot write")
end)
