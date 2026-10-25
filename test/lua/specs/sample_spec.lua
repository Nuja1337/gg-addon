-- The sample addon (fixtures/sample.lua) driven the way a test of the real addon will drive it.

local SAMPLE = "test/lua/fixtures/sample.lua"

local function raid()
  WOW.setPlayer({ name = "Rhona Tester", class = "MAGE", guid = "Player-9001-0000AAAA" })
  WOW.setInstance({ name = "Test Raid", type = "raid", difficultyID = 9, maxPlayers = 40, instanceID = 1234 })
  WOW.setRoster({
    { name = "Tolvar Ashgrove", class = "WARRIOR", guid = "Player-9001-0000BBBB" },
    { name = "Mirel Dawnwhisper", class = "PRIEST", guid = "Player-9002-0000CCCC", online = false },
  })
end

T.test("a roster change snapshots the raid, the timer snapshots it again, and logout saves both", function()
  WOW.declareSavedVariables("SampleDB")
  raid()
  WOW.loadAddon("Sample", { SAMPLE })
  WOW.login()
  local start = GetServerTime()

  WOW.fire("GROUP_ROSTER_UPDATE")
  WOW.advance(59)
  T.eq(#SampleDB.snapshots, 1)
  WOW.advance(1)
  T.eq(#SampleDB.snapshots, 2)

  local saved = WOW.logout()
  local db = saved.SampleDB
  T.eq(db.schema, 1)
  T.eq(db.loads, 1)
  T.eq(db.lastSeen, start + 60)
  T.same(db.snapshots[1], {
    at = start, why = "roster",
    members = {
      { guid = "Player-9001-0000AAAA", name = "Rhona Tester", class = "MAGE", group = 1, online = true },
      { guid = "Player-9001-0000BBBB", name = "Tolvar Ashgrove", class = "WARRIOR", group = 1, online = true },
      { guid = "Player-9002-0000CCCC", name = "Mirel Dawnwhisper", class = "PRIEST", group = 1, online = false },
    },
  })
  T.eq(db.snapshots[2].why, "interval")
  T.eq(db.snapshots[2].at, start + 60)
end)

T.test("it sends one addon message for each snapshot", function()
  WOW.declareSavedVariables("SampleDB")
  raid()
  WOW.loadAddon("Sample", { SAMPLE })
  WOW.fire("GROUP_ROSTER_UPDATE")
  WOW.advance(60)
  T.eq(#WOW.outbox, 2)
  T.eq(WOW.outbox[1].prefix, "SAMPLE")
  T.eq(WOW.outbox[2].text, "snapshot 2")
  T.truthy(C_ChatInfo.IsAddonMessagePrefixRegistered("SAMPLE"))
end)

T.test("a second session starts from the file the first one wrote", function()
  WOW.declareSavedVariables("SampleDB")
  raid()
  WOW.loadAddon("Sample", { SAMPLE })
  WOW.fire("GROUP_ROSTER_UPDATE")
  WOW.logout()
  local file = WOW.savedFile

  -- A reload: a new game, with the file the first one wrote.
  WOW.reset()
  WOW.declareSavedVariables("SampleDB")
  WOW.readSavedFile(file)
  WOW.loadAddon("Sample", { SAMPLE })
  T.eq(SampleDB.loads, 2)
  T.eq(#SampleDB.snapshots, 1)
end)

T.test("the slash command prints to the chat window", function()
  WOW.declareSavedVariables("SampleDB")
  raid()
  WOW.loadAddon("Sample", { SAMPLE })
  T.truthy(WOW.slash("/sample"))
  T.truthy(WOW.slash("/sample snap"))
  T.same(WOW.chat, { "Sample: 0 snapshots", "Sample: 3 in the raid" })
end)
