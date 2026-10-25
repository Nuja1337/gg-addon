-- Core/Events.lua: the event bus. Handlers run under pcall and a failure is recorded without breaking the others;
-- addon messages wait out an encounter and go after ENCOUNTER_END or when a restriction clears.

local function start()
  WOW.declareSavedVariables("GuildGolemDB")
  local ns = WOW.loadAddon("GuildGolem")
  WOW.login()
  return ns
end

local function raid()
  WOW.setRoster({ { name = "Tolvar Ashgrove", class = "WARRIOR" }, { name = "Mirel Dawnwhisper", class = "PRIEST" } }, "raid")
end

local function texts()
  local out = {}
  for i, m in ipairs(WOW.outbox) do out[i] = m.text end
  return out
end

-- Enum.AddOnRestrictionType.Encounter and the states, as the stubs number them.
local ENCOUNTER, INACTIVE, ACTIVATING, ACTIVE = 1, 0, 1, 2

T.test("a game event reaches every handler for it, in order, with the event and its arguments", function()
  local ns = start()
  local log = {}
  ns.Events.on("GROUP_ROSTER_UPDATE", function(event, a, b) log[#log + 1] = "one:" .. event .. ":" .. tostring(a) .. ":" .. tostring(b) end, "test")
  ns.Events.on("GROUP_ROSTER_UPDATE", function(event) log[#log + 1] = "two:" .. event end, "test")
  ns.Events.on("PLAYER_REGEN_ENABLED", function(event) log[#log + 1] = "regen" end, "test")
  WOW.fire("GROUP_ROSTER_UPDATE", "x", nil)
  WOW.fire("PLAYER_REGEN_ENABLED")
  WOW.fire("SOMETHING_NOBODY_LISTENS_TO")
  T.same(log, { "one:GROUP_ROSTER_UPDATE:x:nil", "two:GROUP_ROSTER_UPDATE", "regen" })
end)

T.test("arguments with holes in them arrive as they were", function()
  local ns = start()
  local got
  ns.Events.on("ENCOUNTER_LOOT_RECEIVED", function(_, ...) got = { n = select("#", ...), ... } end, "test")
  WOW.fire("ENCOUNTER_LOOT_RECEIVED", 1, nil, "link", nil, nil, "MAGE")
  T.eq(got.n, 6)
  T.eq(got[3], "link")
  T.eq(got[6], "MAGE")
end)

T.test("a handler that fails is recorded, and the others still run", function()
  local ns = start()
  local ran = {}
  ns.Events.on("GROUP_ROSTER_UPDATE", function() ran[#ran + 1] = "first" end, "alpha")
  ns.Events.on("GROUP_ROSTER_UPDATE", function() error("handler broke") end, "attendance")
  ns.Events.on("GROUP_ROSTER_UPDATE", function() ran[#ran + 1] = "third" end, "omega")
  WOW.fire("GROUP_ROSTER_UPDATE")
  T.same(ran, { "first", "third" })
  local errors = GuildGolemDB.errors
  T.eq(#errors, 1)
  T.eq(errors[1].where, "handler GROUP_ROSTER_UPDATE (attendance)")
  T.truthy(errors[1].message:find("handler broke"), errors[1].message)
  T.truthy(errors[1].message:find("traceback"), "with where it happened")
  T.eq(errors[1].at, GetServerTime())
  -- The next event still works.
  WOW.fire("GROUP_ROSTER_UPDATE")
  T.same(ran, { "first", "third", "first", "third" })
  T.eq(#GuildGolemDB.errors, 2)
end)

T.test("an error that is not text, and an error inside the recording, do not stop anything", function()
  local ns = start()
  local ran = 0
  ns.Events.on("X_EVENT", function() error({ code = 5 }) end, "table")
  ns.Events.on("X_EVENT", function() error() end, "nothing")
  ns.Events.on("X_EVENT", function() ran = ran + 1 end, "ok")
  WOW.fire("X_EVENT")
  T.eq(ran, 1)
  T.eq(#GuildGolemDB.errors, 2)
  T.truthy(GuildGolemDB.errors[1].message:find("table"))
  -- The store itself breaks: the bus still carries on.
  ns.Store.recordError = function() error("store is broken") end
  WOW.fire("X_EVENT")
  T.eq(ran, 2)
end)

T.test("the error list is capped at 50, newest kept", function()
  local ns = start()
  ns.Events.on("LOOP_EVENT", function(_, n) error("failure " .. n) end, "loop")
  for i = 1, 70 do WOW.fire("LOOP_EVENT", i) end
  local errors = GuildGolemDB.errors
  T.eq(#errors, 50)
  T.truthy(errors[50].message:find("failure 70"))
  T.truthy(errors[1].message:find("failure 21"))
end)

T.test("a handler can add or remove handlers while an event is being handled", function()
  local ns = start()
  local log = {}
  local second
  local function first()
    log[#log + 1] = "first"
    ns.Events.off("TICK", second)
    ns.Events.on("TICK", function() log[#log + 1] = "late" end, "test")
  end
  second = function() log[#log + 1] = "second" end
  ns.Events.on("TICK", first, "test")
  ns.Events.on("TICK", second, "test")
  WOW.fire("TICK")
  T.same(log, { "first", "second" }, "the ones there when the event came run, even the one just removed")
  log = {}
  WOW.fire("TICK")
  T.same(log, { "first", "late" })
  T.raises(function() ns.Events.on("X", "not a function") end, "Events.on")
  T.raises(function() ns.Events.on(nil, function() end) end, "Events.on")
end)

T.test("an event of the addon's own is emitted without being registered with the game", function()
  local ns = start()
  local got
  T.eq(ns.Events.on("GG_IMPORTED", function(_, summary) got = summary end, "test"), true)
  ns.Events.emit("GG_IMPORTED", "three raids")
  T.eq(got, "three raids")
  T.eq(WOW.frames[1]:IsEventRegistered("GG_IMPORTED"), false)
  T.eq(WOW.frames[1]:IsEventRegistered("ADDON_LOADED"), true)
end)

T.test("an event the client doesn't know is noted, not raised", function()
  local ns = start()
  local real = ns.Client.registerEvent
  ns.Client.registerEvent = function(frame, event)
    if event == "NO_SUCH_EVENT" then return false end
    return real(frame, event)
  end
  T.eq(ns.Events.on("NO_SUCH_EVENT", function() end, "test"), false)
  T.eq(ns.Events.unknown.NO_SUCH_EVENT, true)
  T.eq(ns.Events.on("GROUP_ROSTER_UPDATE", function() end, "test"), true)
end)

T.test("without a frame the bus still takes handlers and dispatch still runs them", function()
  WOW.declareSavedVariables("GuildGolemDB")
  WOW.hide("CreateFrame")
  local ns = {}
  for _, path in ipairs({ "Client", "Core/Store", "Core/Events" }) do WOW.dofile("GuildGolem/" .. path .. ".lua", "GuildGolem", ns) end
  T.eq(ns.Events.init(), false)
  local got
  ns.Events.on("PLAYER_LOGIN", function() got = true end, "test")
  ns.Events.dispatch("PLAYER_LOGIN")
  T.eq(got, true)
end)

-- Addon messages --------------------------------------------------------------------------------------------------

T.test("a message goes out at once when nothing holds it back", function()
  local ns = start()
  raid()
  T.eq(ns.Client.registerPrefix("GGTEST"), true)
  T.eq(ns.Events.send("GGTEST", "one", "RAID"), true)
  T.same(texts(), { "one" })
  T.eq(ns.Events.queued(), 0)
  T.eq(ns.Events.holding(), false)
end)

T.test("messages are queued during an encounter, in order, and go out after ENCOUNTER_END", function()
  local ns = start()
  raid()
  ns.Events.send("GGTEST", "before", "RAID")
  WOW.fire("ENCOUNTER_START", 90101, "Cinderjaw", 14, 10)
  T.eq(ns.Events.holding(), true)
  local ok, why = ns.Events.send("GGTEST", "during 1", "RAID")
  T.eq(ok, false)
  T.eq(why, "queued")
  ns.Events.send("GGTEST", "during 2", "RAID")
  ns.Events.send("GGTEST", "during 3", "RAID")
  T.same(texts(), { "before" }, "nothing is sent while the boss is up")
  T.eq(ns.Events.queued(), 3)
  WOW.fire("ENCOUNTER_END", 90101, "Cinderjaw", 14, 10, 1)
  T.same(texts(), { "before", "during 1", "during 2", "during 3" })
  T.eq(ns.Events.queued(), 0)
  T.eq(ns.Events.holding(), false)
  T.eq(ns.Events.send("GGTEST", "after", "RAID"), true)
  T.eq(texts()[5], "after")
end)

T.test("a message sent while the client says lockdown is queued, and goes when the restriction clears", function()
  local ns = start()
  raid()
  WOW.lockdown = true
  T.eq(select(2, ns.Events.send("GGTEST", "held 1", "RAID")), "queued")
  T.eq(select(2, ns.Events.send("GGTEST", "held 2", "RAID")), "queued")
  T.eq(ns.Events.queued(), 2)
  T.same(texts(), {})
  -- A flush while the client still refuses sends nothing and keeps the queue.
  T.eq(ns.Events.flush(), 0)
  T.eq(ns.Events.queued(), 2)
  WOW.lockdown = false
  WOW.fire("ADDON_RESTRICTION_STATE_CHANGED", ENCOUNTER, INACTIVE)
  T.same(texts(), { "held 1", "held 2" })
  T.eq(ns.Events.queued(), 0)
end)

T.test("a restriction that is activating holds messages, and one that has not cleared keeps them held", function()
  local ns = start()
  raid()
  WOW.fire("ADDON_RESTRICTION_STATE_CHANGED", ENCOUNTER, ACTIVATING)
  ns.Events.send("GGTEST", "a", "RAID")
  WOW.fire("ADDON_RESTRICTION_STATE_CHANGED", ENCOUNTER, ACTIVE)
  ns.Events.send("GGTEST", "b", "RAID")
  T.same(texts(), {})
  -- Another kind of restriction clearing does not release an encounter's.
  WOW.fire("ADDON_RESTRICTION_STATE_CHANGED", 5, INACTIVE)
  T.same(texts(), {})
  T.eq(ns.Events.queued(), 2)
  WOW.fire("ADDON_RESTRICTION_STATE_CHANGED", ENCOUNTER, INACTIVE)
  T.same(texts(), { "a", "b" })
end)

T.test("a message sent behind a queue waits its turn, so order is kept", function()
  local ns = start()
  raid()
  WOW.fire("ENCOUNTER_START", 1, "Boss", 14, 10)
  ns.Events.send("GGTEST", "1", "RAID")
  WOW.fire("ENCOUNTER_END", 1, "Boss", 14, 10, 0)
  ns.Events.send("GGTEST", "2", "RAID")
  WOW.fire("ENCOUNTER_START", 2, "Boss", 14, 10)
  ns.Events.send("GGTEST", "3", "RAID")
  ns.Events.send("GGTEST", "4", "RAID")
  WOW.fire("ENCOUNTER_END", 2, "Boss", 14, 10, 1)
  T.same(texts(), { "1", "2", "3", "4" })
end)

T.test("too many messages at once: the client's limit queues the rest, and a timer sends them a second later", function()
  local ns = start()
  raid()
  for i = 1, 13 do ns.Events.send("GGTEST", "m" .. i, "RAID") end
  T.eq(#WOW.outbox, 10, "ten go out, then the client says too fast")
  T.eq(ns.Events.queued(), 3)
  WOW.advance(1)
  T.eq(#WOW.outbox, 11)
  WOW.advance(1)
  WOW.advance(1)
  T.eq(#WOW.outbox, 13)
  T.eq(ns.Events.queued(), 0)
  local names = texts()
  for i = 1, 13 do T.eq(names[i], "m" .. i, "message " .. i .. " in its place") end
  -- Nothing more is scheduled.
  T.eq(WOW.advance(60), 0)
end)

T.test("a message the client refuses for good is dropped and recorded, and the ones behind it still go", function()
  local ns = start()
  raid()
  T.same({ ns.Events.send("GGTEST", "x", "BOGUS") }, { false, "InvalidChatType" })
  -- Queued first, then refused when it comes up.
  WOW.fire("ENCOUNTER_START", 1, "Boss", 14, 10)
  ns.Events.send("GGTEST", "bad", "BOGUS")
  ns.Events.send("GGTEST", "good", "RAID")
  WOW.fire("ENCOUNTER_END", 1, "Boss", 14, 10, 1)
  T.same(texts(), { "good" })
  T.eq(#GuildGolemDB.errors, 1)
  T.eq(GuildGolemDB.errors[1].where, "send")
  T.truthy(GuildGolemDB.errors[1].message:find("InvalidChatType"))
end)

T.test("the queue keeps 200 messages, drops the oldest and says so", function()
  local ns = start()
  raid()
  WOW.fire("ENCOUNTER_START", 1, "Boss", 14, 10)
  for i = 1, 205 do ns.Events.send("GGTEST", "m" .. i, "RAID") end
  T.eq(ns.Events.queued(), 200)
  T.eq(#GuildGolemDB.errors, 5)
  T.truthy(GuildGolemDB.errors[1].message:find("200"))
  WOW.fire("ENCOUNTER_END", 1, "Boss", 14, 10, 1)
  -- Ten go out at once and the rest follow as the client lets them.
  T.eq(texts()[1], "m6")
  WOW.advance(300)
  T.eq(ns.Events.queued(), 0)
  T.eq(#WOW.outbox, 200)
  T.eq(texts()[200], "m205")
end)

T.test("a client without the send API refuses for good, without raising", function()
  local ns = start()
  raid()
  WOW.hide("C_ChatInfo.SendAddonMessage")
  T.same({ ns.Events.send("GGTEST", "x", "RAID") }, { false, "no-api" })
  T.eq(ns.Events.queued(), 0)
end)
