-- Client.lua: the one file that names the game's functions. These tests feed it the stubs' payloads (which follow
-- docs/RESEARCH.md), take APIs away, make them raise errors and hand it secret values, and check that it always
-- answers with plain data.

local function client()
  local ns = {}
  WOW.dofile("GuildGolem/Client.lua", "GuildGolem", ns)
  ns.Client.errors = {}
  ns.Client.onError = function(where, message)
    ns.Client.errors[#ns.Client.errors + 1] = { where = where, message = message }
  end
  return ns.Client
end

-- Replaces a game function for the rest of the test (WOW.reset puts the original back).
local function replace(name, fn)
  WOW.hide(name)
  if name:find("%.") then
    local head, tail = name:match("^(.-)%.(.+)$")
    _G[head][tail] = fn
  else
    _G[name] = fn
  end
end

local RAID = {
  { name = "Tolvar Ashgrove", class = "WARRIOR", subgroup = 1, guid = "Player-9101-0F00AA01" },
  { name = "Mirel Dawnwhisper", class = "PRIEST", subgroup = 2, guid = "Player-9102-0F00AA02", online = false, zone = "Elsewhere" },
  { name = "Quill Brightwater", class = "DEATHKNIGHT", subgroup = 3, guid = "Player-9101-0F00AA03", zone = "Ember Vault" },
}

T.test("caps says what the client has, and changes when an API goes", function()
  local C = client()
  local caps = C.caps()
  for _, key in ipairs({ "buildInfo", "locale", "serverTime", "uptime", "unitGUID", "raidRoster", "group", "instance", "guild",
    "savedInstances", "addonMessages", "messagePrefix", "chatLockdown", "secretValues", "canAccessValue", "timers", "frames", "metadata" }) do
    T.eq(caps[key], true, key)
  end
  T.eq(caps.lootHistory, false, "the stubs have no C_LootHistory")
  T.eq(caps.encounterInProgress, false)
  WOW.hide("GetRaidRosterInfo")
  WOW.hide("C_ChatInfo.SendAddonMessage")
  WOW.hide("issecretvalue")
  caps = C.caps()
  T.eq(caps.raidRoster, false)
  T.eq(caps.addonMessages, false)
  T.eq(caps.secretValues, false)
  T.eq(caps.canAccessValue, true)
  WOW.hide("C_ChatInfo")
  T.eq(C.caps().messagePrefix, false)
end)

T.test("the build, the locale, the realm and the addon's version come as the contract's meta.client wants them", function()
  local C = client()
  T.same(C.build(), { version = "1.60.1", build = 70532, date = "Oct 20 2026", interface = 16001, locale = "enUS", realm = "Classic Beta PvP", project = 18 })
  T.eq(C.addonVersion(), "0.1.0-beta")
  local versions = {
    { "v1.2.3", "1.2.3" }, { "1.2.3", "1.2.3" }, { "v0.1.0-beta", "0.1.0-beta" }, { "v2.0.0-Alpha", "2.0.0-alpha" },
    { "v0.1.0-3-gabc123", "0.1.0-3" }, { "@project-version@", "0.0.0-dev" }, { "dev", "0.0.0-dev" }, { "", "0.0.0-dev" },
  }
  for _, v in ipairs(versions) do
    WOW.metadata.GuildGolem.Version = v[1]
    T.eq(C.addonVersion(), v[2], v[1])
  end
  WOW.metadata.GuildGolem = nil
  T.eq(C.addonVersion(), "0.0.0-dev")
  WOW.hide("C_AddOns")
  T.eq(C.addonVersion(), "0.0.0-dev")
end)

T.test("the server's clock is in whole seconds, and in milliseconds a multiple of 1000", function()
  local C = client()
  T.eq(C.serverTime(), GetServerTime())
  T.eq(C.serverTimeMs(), GetServerTime() * 1000)
  T.eq(C.serverTimeMs() % 1000, 0)
  WOW.setServerTime(1796846700)
  T.eq(C.serverTimeMs(), 1796846700000)
  T.eq(C.uptime(), GetTime())
  WOW.hide("GetServerTime")
  T.eq(C.serverTime(), nil)
  T.eq(C.serverTimeMs(), nil)
end)

T.test("the player: GUID, full name and class", function()
  local C = client()
  WOW.setPlayer({ name = "Rhona Tester", class = "MAGE", guid = "Player-9001-0000AAAA" })
  T.same(C.player(), { guid = "Player-9001-0000AAAA", name = "Rhona Tester", cls = "mage" })
end)

T.test("a raid roster: name, GUID, class, group, online and zone, with the zone left out for someone offline", function()
  local C = client()
  WOW.setRoster(RAID, "raid")
  local rows, kind = C.roster()
  T.eq(kind, "raid")
  T.eq(#rows, 4, "the player first, then the others")
  T.same(rows[1], { unit = "raid1", guid = "Player-9001-0000AAAA", name = "Rhona Tester", cls = "mage", group = 1, online = true, rank = 2, level = 60, zone = "Test Zone" })
  T.same(rows[2], { unit = "raid2", guid = "Player-9101-0F00AA01", name = "Tolvar Ashgrove", cls = "warrior", group = 1, online = true, rank = 0, level = 60, zone = "Test Zone" })
  T.eq(rows[3].name, "Mirel Dawnwhisper")
  T.eq(rows[3].online, false)
  T.eq(rows[3].zone, nil, "an offline member has no zone")
  T.eq(rows[3].group, 2)
  T.eq(rows[4].cls, "deathknight")
  T.eq(rows[4].zone, "Ember Vault")
end)

T.test("a party is all in group 1, with the player first; alone is none", function()
  local C = client()
  WOW.setRoster({ { name = "Tolvar Ashgrove", class = "WARRIOR", guid = "Player-9101-0F00AA01" }, { name = "Mirel Dawnwhisper", class = "PRIEST", guid = "Player-9102-0F00AA02", online = false } }, "party")
  local rows, kind = C.roster()
  T.eq(kind, "party")
  T.eq(#rows, 3)
  T.same(rows[1], { unit = "player", guid = "Player-9001-0000AAAA", name = "Rhona Tester", cls = "mage", group = 1, online = true })
  T.eq(rows[2].name, "Tolvar Ashgrove")
  T.eq(rows[3].online, false)
  WOW.setRoster(nil)
  rows, kind = C.roster()
  T.eq(kind, "none")
  T.same(rows, {})
end)

T.test("a name is first name and surname joined with a space, from the two values UnitName gives", function()
  local C = client()
  WOW.setRoster({ { name = "Tolvar Ashgrove", class = "WARRIOR" } }, "party")
  T.eq(C.roster()[2].name, "Tolvar Ashgrove")
  replace("UnitName", function() return "Solo", nil end)
  T.eq(C.player().name, "Solo")
  replace("UnitName", function() return "Solo", "" end)
  T.eq(C.player().name, "Solo")
end)

T.test("a missing API gives nothing and raises nothing", function()
  local C = client()
  WOW.setRoster(RAID, "raid")
  for _, name in ipairs({ "GetRaidRosterInfo", "UnitGUID", "GetInstanceInfo", "GetGuildInfo", "GetBuildInfo", "GetLocale", "GetRealmName",
    "GetNumSavedInstances", "GetServerTime", "UnitName", "UnitClass" }) do
    WOW.hide(name)
  end
  local rows, kind = C.roster()
  T.eq(kind, "raid")
  T.same(rows, {})
  T.eq(C.instance(), nil)
  T.eq(C.guild(), nil)
  T.same(C.build(), { project = 18 })
  T.same(C.lockouts(), {})
  T.same(C.player(), {})
  T.eq(C.serverTime(), nil)
  T.eq(#C.errors, 0, "a missing API is not an error")
  T.eq(C.errorCount, 0)
end)

T.test("an API that raises an error is caught, reported, and the rest still answers", function()
  local C = client()
  WOW.setRoster(RAID, "raid")
  replace("GetRaidRosterInfo", function(i)
    if i == 2 then error("boom at " .. i) end
    return "Name" .. i, 0, 1, 60, "Mage", "MAGE", "Zone", true
  end)
  local rows = C.roster()
  T.eq(#rows, 3, "the member that raised an error is left out, the others are not")
  T.eq(rows[1].name, "Name1")
  T.eq(rows[2].name, "Name3")
  T.eq(#C.errors, 1)
  T.eq(C.errors[1].where, "GetRaidRosterInfo")
  T.truthy(C.errors[1].message:find("boom at 2"), C.errors[1].message)
  T.eq(C.errorCount, 1)

  replace("GetInstanceInfo", function() error({ not_text = true }) end)
  T.eq(C.instance(), nil)
  T.eq(#C.errors, 2)
  T.truthy(C.errors[2].message:find("table"), "an error that isn't text is still reported as text")

  -- Even a handler that fails does not break the call.
  C.onError = function() error("the handler is broken too") end
  replace("GetGuildInfo", function() error("again") end)
  T.eq(C.guild(), nil)
end)

T.test("a secret value is never kept: its field is left out", function()
  local C = client()
  WOW.setRoster(RAID, "raid")
  replace("GetRaidRosterInfo", function(i)
    return WOW.secret("name"), 0, 2, 60, "Mage", "MAGE", WOW.secret("zone"), true
  end)
  replace("UnitGUID", function(unit)
    if unit == "raid2" then return WOW.secret("guid") end
    return "Player-9101-0F00AA0" .. unit:sub(5)
  end)
  local rows = C.roster()
  T.eq(#rows, 3, "a member with neither a name nor a GUID to give is left out")
  T.eq(rows[1].unit, "raid1")
  T.eq(rows[2].unit, "raid3")
  T.eq(rows[1].name, nil)
  T.eq(rows[1].zone, nil)
  T.eq(rows[1].guid, "Player-9101-0F00AA01")
  T.eq(rows[1].group, 2)
  T.eq(rows[2].guid, "Player-9101-0F00AA03")
  for _, row in ipairs(rows) do
    for k, v in pairs(row) do T.truthy(type(v) ~= "table", k .. " is plain data") end
  end
  T.eq(C.isSecret(WOW.secret()), true)
  T.eq(C.isSecret("text"), false)
  T.eq(C.isSecret(nil), false)
  -- With only canaccessvalue, a value it refuses counts as secret too.
  WOW.hide("issecretvalue")
  T.eq(C.isSecret(WOW.secret()), true)
  WOW.hide("canaccessvalue")
  T.eq(C.isSecret(WOW.secret()), false, "a client with neither has no secrets")
end)

T.test("the instance: the id the contract calls the zone, the difficulty and the size", function()
  local C = client()
  WOW.setInstance({ name = "Ember Vault", type = "raid", difficultyID = 14, difficultyName = "Normal", maxPlayers = 10, instanceID = 5011, instanceGroupSize = 9 })
  T.same(C.instance(), { name = "Ember Vault", type = "raid", difficulty = 14, difficultyName = "Normal", maxPlayers = 10, instanceID = 5011, groupSize = 9 })
  WOW.setInstance(nil)
  local open = C.instance()
  T.eq(open.type, "none")
  T.eq(open.instanceID, 0)
end)

T.test("the saved lockouts: the id that goes in an export, and whether it is a raid", function()
  local C = client()
  T.same(C.lockouts(), {})
  WOW.setSavedInstances({
    { name = "Ember Vault", id = 77123456, difficulty = 14, locked = true, instanceID = 5011, maxPlayers = 10 },
    { name = "Old Cellar", id = 1, difficulty = 1, locked = false, raid = false },
  })
  local rows = C.lockouts()
  T.eq(#rows, 2)
  T.same(rows[1], { name = "Ember Vault", id = 77123456, difficulty = 14, locked = true, raid = true, maxPlayers = 10 })
  T.eq(rows[2].locked, false)
  T.eq(rows[2].raid, false)
end)

T.test("the guild: name, rank and sub-realm, or nothing when the player has none", function()
  local C = client()
  T.eq(C.guild(), nil)
  WOW.setGuild({ name = "Molten Raiders", rank = "Officer", rankIndex = 1, realm = "Sub Realm" })
  T.same(C.guild(), { name = "Molten Raiders", rank = "Officer", rankIndex = 1, realm = "Sub Realm" })
  WOW.setRoster({ { name = "Tolvar Ashgrove", class = "WARRIOR", guild = { name = "Other Guild", rank = "Member", rankIndex = 4 } } }, "raid")
  T.eq(C.guild("raid2").name, "Other Guild")
  T.eq(C.guild("raid9"), nil)
end)

T.test("an encounter starting: id, name, difficulty and size", function()
  local C = client()
  T.same(C.encounterStart(90101, "Cinderjaw", 14, 10), { id = 90101, name = "Cinderjaw", difficulty = 14, size = 10 })
  T.same(C.encounterStart(WOW.secret(), "Cinderjaw", 14, nil), { name = "Cinderjaw", difficulty = 14 })
  T.same(C.encounterStart(), {})
end)

T.test("an encounter ending: success is a number, 1 is a kill, and the health left at a wipe comes as plain data", function()
  local C = client()
  local kill = C.encounterEnd(90101, "Cinderjaw", 14, 10, 1)
  T.same(kill, { id = 90101, name = "Cinderjaw", difficulty = 14, size = 10, success = 1, kill = true })
  local wipe = C.encounterEnd(90101, "Cinderjaw", 14, 10, 0, { creatureID = 7001, name = "Cinderjaw", healthPercent = 23, nested = { a = 1, deeper = { b = 2 } }, bad = function() end })
  T.eq(wipe.kill, false)
  T.eq(wipe.success, 0)
  T.eq(wipe.unitStatus.healthPercent, 23)
  T.eq(wipe.unitStatus.nested.a, 1)
  T.eq(wipe.unitStatus.nested.deeper, nil, "two levels are kept")
  T.eq(wipe.unitStatus.bad, nil)
  T.eq(C.encounterEnd(1, "x", 1, 1, true).success, 1, "a boolean true reads as 1")
  T.eq(C.encounterEnd(1, "x", 1, 1, WOW.secret()).success, nil)
  T.eq(C.encounterEnd(1, "x", 1, 1, 1, WOW.secret()).unitStatus, nil)
  T.eq(C.encounterEnd(1, "x", 1, 1, 0, "text").unitStatus, nil)
end)

T.test("an item link gives its payload without colors, its id, name and quality", function()
  local C = client()
  local link = "|cffa335ee|Hitem:288123::::::::60:::::|h[Sword of Embers]|h|r"
  T.same(C.parseItemLink(link), { link = "item:288123::::::::60:::::", item = 288123, name = "Sword of Embers", quality = 4 })
  T.eq(C.parseItemLink("|cff0070dd|Hitem:288200:1491:::::|h[Ring]|h|r").quality, 3)
  T.eq(C.parseItemLink("|cff1eff00|Hitem:5|h[Thing]|h|r").quality, 2)
  T.eq(C.parseItemLink("|cffff8000|Hitem:5|h[Thing]|h|r").quality, 5)
  T.eq(C.parseItemLink("|Hitem:5:0|h[No Color]|h").quality, nil)
  T.same(C.parseItemLink("item:123:45"), { link = "item:123:45", item = 123 })
  T.eq(C.parseItemLink("|cffffffff|Hspell:123|h[A Spell]|h|r"), nil)
  T.eq(C.parseItemLink("plain text"), nil)
  T.eq(C.parseItemLink(nil), nil)
  T.eq(C.parseItemLink(12), nil)
  T.eq(C.parseItemLink(WOW.secret()), nil)
end)

T.test("loot received: the winner's name, the item, how many, and the class only as a token", function()
  local C = client()
  local link = "|cffa335ee|Hitem:288123::::::::60:::::|h[Sword of Embers]|h|r"
  T.same(C.lootReceived(90101, 288123, link, 1, "Tolvar Ashgrove", "WARRIOR"), {
    encounter = 90101, item = 288123, count = 1, winner = "Tolvar Ashgrove", cls = "warrior",
    link = "item:288123::::::::60:::::", name = "Sword of Embers", quality = 4,
  })
  local local_ = C.lootReceived(90101, 288123, link, 3, "Mirel Dawnwhisper", "Priester")
  T.eq(local_.cls, nil)
  T.eq(local_.className, "Priester")
  T.eq(local_.count, 3)
  -- The id comes from the link when the event leaves it out; a secret winner is left out.
  local fromLink = C.lootReceived(90101, nil, link, 1, WOW.secret(), nil)
  T.eq(fromLink.item, 288123)
  T.eq(fromLink.winner, nil)
  T.eq(C.lootReceived(nil, nil, WOW.secret(), nil, nil, nil).link, nil)
  T.same(C.lootReceived(), {})
end)

T.test("sending an addon message: sent, held by the client, too fast, or refused", function()
  local C = client()
  WOW.setRoster(RAID, "raid")
  T.eq(C.registerPrefix("GGTEST"), true)
  T.eq(select(1, C.send("GGTEST", "hello", "RAID")), true)
  T.eq(WOW.outbox[1].text, "hello")
  WOW.lockdown = true
  local ok, why = C.send("GGTEST", "held", "RAID")
  T.eq(ok, false)
  T.eq(why, "lockdown")
  T.eq(C.chatLockdown(), true)
  WOW.lockdown = false
  T.eq(C.chatLockdown(), false)
  for i = 1, 12 do ok, why = C.send("GGTEST", "burst" .. i, "RAID") end
  T.eq(ok, false)
  T.eq(why, "throttled")
  ok, why = C.send("GGTEST", "x", "BOGUS")
  T.eq(ok, false)
  T.eq(why, "InvalidChatType")
  ok, why = C.send("", "x", "RAID")
  T.eq(why, "InvalidPrefix")
  WOW.hide("C_ChatInfo.SendAddonMessage")
  ok, why = C.send("GGTEST", "gone", "RAID")
  T.eq(why, "no-api")
  T.eq(C.registerPrefix("GGTEST2"), true)
  WOW.hide("C_ChatInfo.InChatMessagingLockdown")
  T.eq(C.chatLockdown(), nil)
end)

T.test("sending when the call raises an error, and when the client answers with nothing", function()
  local C = client()
  replace("C_ChatInfo.SendAddonMessage", function() error("no way") end)
  local ok, why = C.send("GGTEST", "x", "RAID")
  T.eq(ok, false)
  T.eq(why, "error")
  T.eq(#C.errors, 1)
  -- Older clients return nothing, or true.
  replace("C_ChatInfo.SendAddonMessage", function() end)
  T.eq(C.send("GGTEST", "x", "RAID"), true)
  replace("C_ChatInfo.SendAddonMessage", function() return true end)
  T.eq(C.send("GGTEST", "x", "RAID"), true)
  replace("C_ChatInfo.SendAddonMessage", function() return 77 end)
  ok, why = C.send("GGTEST", "x", "RAID")
  T.eq(ok, false)
  T.eq(why, "refused")
end)

T.test("a restriction event is named when the client's enums are there, and says when it has cleared", function()
  local C = client()
  T.same(C.restriction(1, 1), { type = "Encounter", state = "Activating", cleared = false })
  T.same(C.restriction(1, 2), { type = "Encounter", state = "Active", cleared = false })
  T.same(C.restriction(1, 0), { type = "Encounter", state = "Inactive", cleared = true })
  T.same(C.restriction(5, 0), { type = "Chat", state = "Inactive", cleared = true })
  WOW.hide("Enum")
  T.same(C.restriction(1, 0), { type = 1, state = 0, cleared = true })
  T.same(C.restriction(1, 2), { type = 1, state = 2, cleared = false })
end)

T.test("frames, events and timers", function()
  local C = client()
  local frame = C.createFrame()
  T.truthy(frame)
  T.eq(C.registerEvent(frame, "GROUP_ROSTER_UPDATE"), true)
  local seen = {}
  T.eq(C.setEventHandler(frame, function(_, event, ...) seen[#seen + 1] = event end), true)
  WOW.fire("GROUP_ROSTER_UPDATE")
  T.same(seen, { "GROUP_ROSTER_UPDATE" })
  T.eq(C.unregisterEvent(frame, "GROUP_ROSTER_UPDATE"), true)
  WOW.fire("GROUP_ROSTER_UPDATE")
  T.eq(#seen, 1)

  local ran = false
  T.eq(C.after(5, function() ran = true end), true)
  WOW.advance(5)
  T.eq(ran, true)

  -- A frame that cannot register an event, and one that is not a frame.
  local bad = { RegisterEvent = function() error("unknown event") end }
  T.eq(C.registerEvent(bad, "NO_SUCH_EVENT"), false)
  T.eq(#C.errors, 1)
  T.eq(C.registerEvent(nil, "X"), false)
  T.eq(C.registerEvent({}, "X"), false)
  T.eq(C.setEventHandler("frame", print), false)

  WOW.hide("CreateFrame")
  T.eq(C.createFrame(), nil)
  WOW.hide("C_Timer")
  T.eq(C.after(1, function() end), false)
end)

T.test("the encounter in progress, where the client can say", function()
  local C = client()
  T.eq(C.encounterInProgress(), nil)
  _G.IsEncounterInProgress = function() return true end
  T.eq(C.encounterInProgress(), true)
  _G.IsEncounterInProgress = function() return false end
  T.eq(C.encounterInProgress(), false)
  _G.IsEncounterInProgress = nil
end)

T.test("nothing in Client.lua raises when every game API is gone", function()
  local C = client()
  local keep = { assert = true, error = true, pcall = true, xpcall = true, type = true, tostring = true, tonumber = true, pairs = true,
    ipairs = true, select = true, next = true, unpack = true, string = true, table = true, math = true, os = true, debug = true,
    coroutine = true, print = true, setmetatable = true, getmetatable = true, rawget = true, rawset = true, rawequal = true,
    collectgarbage = true, _G = true, _VERSION = true, T = true, WOW = true, GG_ROOT = true, GG_READ = true,
    loadfile = true, loadstring = true, dofile = true, load = true, getfenv = true, setfenv = true, gcinfo = true,
    newproxy = true, module = true, require = true, package = true, io = true, arg = true, jit = true, utf8 = true, bit32 = true }
  for name in pairs(_G) do
    if type(name) == "string" and not keep[name] then WOW.hide(name) end
  end
  T.same(C.caps().raidRoster, false)
  C.roster()
  C.instance()
  C.lockouts()
  C.guild()
  C.build()
  C.player()
  C.serverTime()
  C.encounterStart(1, "x", 1, 1)
  C.encounterEnd(1, "x", 1, 1, 1)
  C.lootReceived(1, 2, "|Hitem:2|h[x]|h", 1, "Name", "MAGE")
  C.send("P", "t", "RAID")
  C.chatLockdown()
  C.restriction(1, 0)
  C.createFrame()
  C.after(1, function() end)
  C.addonVersion()
  C.registerPrefix("P")
  T.eq(C.errorCount, 0)
end)
