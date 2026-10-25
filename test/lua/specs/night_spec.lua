-- A whole raid night through the stubs (test/lua/fixtures/night.lua): forty players, three raids, about four hours, then the
-- export. test/night.test.mjs reads the same night's strings with the reference validator.
--
-- Playing the night takes a few seconds under fengari, so it is played once and the tests read a copy of what it left
-- (the stubs are reset between tests). The one test that logs out and in again plays its own.

WOW.dofile("test/lua/fixtures/night.lua")

local played

local function night()
  if not played then
    local result = NIGHT.run()
    played = {
      result = result,
      db = WOW.copy(GuildGolemDB),
      loggingCalls = WOW.copy(WOW.loggingCalls),
      chat = WOW.copy(WOW.chat),
      codec = GuildGolem.Codec,
    }
  end
  return played
end

local function field(list, key)
  local out = {}
  for i, v in ipairs(list) do out[i] = v[key] end
  return out
end

-- Every member row of a raid's snapshots, with the snapshot it is in.
local function present(raid, guid)
  local out = {}
  for _, s in ipairs(raid.snapshots) do
    for _, m in ipairs(s.members) do
      if m.guid == guid then out[#out + 1] = { snapshot = s, member = m } end
    end
  end
  return out
end

T.test("the night is recorded as three raids, in the order they were played, and exported as one string", function()
  local n = night()
  local r, db = n.result, n.db
  T.eq(r.minutes, 235, "about four hours of the fake clock")
  T.eq(r.ok, true, tostring(r.why))
  T.eq(#db.raids, 3)
  T.same(field(r.raids, "zone"), { 5011, 5012, 5013 })
  T.same(field(r.raids, "closed"), { true, true, true })
  T.same(field(r.raids, "night"), { "efgh6789", "efgh6789", "efgh6789" })
  T.eq(r.raids[1].lockout, 770011, "the lockout came with the first kill")
  T.eq(r.raids[2].lockout, nil)
  T.eq(r.stored, 37)
  T.eq(r.exported, 37)
  T.eq(#r.export, 1, "a night of this size is one string")
  T.truthy(r.export[1].characters < n.codec.WRITE_TEXT, r.export[1].characters .. " characters")
  T.eq(r.pugs, 1)
  for _, raid in ipairs(r.raids) do
    T.truthy(raid.whys:find("^zonein,"), raid.whys)
    T.truthy(raid.whys:find(",leave$"), raid.whys)
  end
end)

T.test("each raid shows its pulls, wipes and kills in the order they happened", function()
  local n = night()
  local r = n.result
  T.eq(r.raids[1].whys, "zonein,interval,pull,wipe,pull,kill,interval,pull,kill,interval,pull,wipe,pull,kill,leave")
  T.eq(r.raids[2].whys, "zonein,pull,kill,interval,pull,wipe,pull,kill,interval,leave")
  T.eq(r.raids[3].whys, "zonein,pull,kill,pull,wipe,pull,kill,pull,wipe,pull,kill,leave")
  local encounters = {}
  for _, s in ipairs(n.db.raids[2].snapshots) do encounters[#encounters + 1] = s.encounter or 0 end
  T.same(encounters, { 0, 2201, 2201, 0, 2202, 2202, 2202, 2202, 0, 0 })
end)

T.test("the times are the server's, whole seconds, in order, and the first raid begins ten minutes in", function()
  local n = night()
  local db, r = n.db, n.result
  for _, raid in ipairs(db.raids) do
    local last
    for _, s in ipairs(raid.snapshots) do
      T.eq(s.at % 1000, 0)
      if last then T.truthy(s.at > last, "in order") end
      last = s.at
    end
  end
  T.eq(db.raids[1].snapshots[1].at, r.startMs + 10 * 60000)
  T.eq(db.raids[2].snapshots[1].at, r.startMs + 85 * 60000)
  T.eq(db.raids[3].snapshots[1].at, r.startMs + 145 * 60000)
  -- The disbanded group's leave snapshot is at minute 235, with nobody in it.
  local leave = db.raids[3].snapshots[#db.raids[3].snapshots]
  T.eq(leave.at, r.startMs + 235 * 60000)
  T.same(leave.members, {})
end)

T.test("the disconnect shows as offline and then online, with no zone while offline", function()
  local n = night()
  local rows = present(n.db.raids[1], n.result.people.disconnecter)
  local offline, back = 0, false
  for _, row in ipairs(rows) do
    if row.member.online == false then
      offline = offline + 1
      T.eq(row.member.zone, nil)
    elseif offline > 0 then
      back = true
    end
  end
  T.truthy(offline >= 1, "seen offline")
  T.eq(back, true, "and back")
end)

T.test("the player who left early is in the first raid until he goes, and in neither of the others", function()
  local n = night()
  local raids, r = n.db.raids, n.result
  local first = present(raids[1], r.people.leaver)
  T.truthy(#first >= 8 and #first < #raids[1].snapshots, #first .. " of " .. #raids[1].snapshots)
  T.eq(#present(raids[2], r.people.leaver), 0)
  T.eq(#present(raids[3], r.people.leaver), 0)
  local sizes = {}
  for i, s in ipairs(raids[1].snapshots) do sizes[i] = #s.members end
  T.eq(sizes[1], 40)
  T.eq(sizes[#sizes], 39)
end)

T.test("the bench is standby in the first raid, never in a snapshot, and the pug is there until he leaves", function()
  local n = night()
  local raids, r = n.db.raids, n.result
  T.eq(#raids[1].standby, 2)
  T.same({ raids[1].standby[1].guid, raids[1].standby[2].guid }, r.people.benched)
  for _, g in ipairs(r.people.benched) do T.eq(#present(raids[1], g), 0) end
  T.eq(raids[2].standby, nil)
  T.eq(#present(raids[1], r.people.pug) > 0, true)
  T.eq(#present(raids[2], r.people.pug) > 0, true)
  T.eq(#present(raids[3], r.people.pug), 0)
end)

T.test("a second export repeats nothing: the raids are marked, and the outbox holds the one string", function()
  local n = night()
  local r, db = n.result, n.db
  T.eq(r.secondMade, false)
  T.eq(r.secondWhy, "nothing")
  T.eq(r.outboxAfterSecond, 1)
  for _, raid in ipairs(db.raids) do T.eq(raid.sent, #raid.snapshots) end
  -- 'all' makes one more, with every snapshot again.
  T.eq(#r.allTexts, 1)
  T.eq(#db.outbox, 2)
  local again = n.codec.read(r.allTexts[1], "site")
  local first = n.codec.read(r.export[1].text, "site")
  T.eq(#again.attendance, #first.attendance)
  T.truthy(again.meta.id ~= first.meta.id)
end)

T.test("combat logging was turned on once, at the first zone-in, and said so once", function()
  local n = night()
  T.same(n.loggingCalls, { true })
  local said = 0
  for _, line in ipairs(n.chat) do
    if line:find("Combat logging is on") then said = said + 1 end
  end
  T.eq(said, 1)
  T.eq(#n.db.errors, 0, "and nothing went wrong along the way")
end)

T.test("the outbox survives a logout and a reload, and the reload does not export the night again", function()
  local r = NIGHT.run()
  local saved = WOW.logout()
  T.eq(#saved.GuildGolemDB.outbox, 2)
  T.eq(saved.GuildGolemDB.outbox[1].text, r.export[1].text)
  local text = WOW.savedFile

  WOW.reset()
  WOW.declareSavedVariables("GuildGolemDB")
  WOW.readSavedFile(text)
  local ns = WOW.loadAddon("GuildGolem")
  WOW.login(true)
  T.eq(#GuildGolemDB.outbox, 2)
  T.eq(GuildGolemDB.outbox[1].text, r.export[1].text)
  T.eq(#ns.Store.outboxPending(), 2, "nothing was pasted")
  local made, why = ns.Export.make()
  T.eq(made, nil)
  T.eq(why, "nothing")
  T.eq(#GuildGolemDB.raids, 3)
  -- Pasting marks one, and it stays for a month.
  ns.Store.outboxMarkPasted(GuildGolemDB.outbox[1].id)
  T.eq(#ns.Store.outboxPending(), 1)
  T.eq(ns.Store.outboxPrune(GetServerTime() * 1000 + 40 * 86400000.0), 1)
  T.eq(#GuildGolemDB.outbox, 1)
end)
