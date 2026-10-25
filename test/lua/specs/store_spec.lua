-- Core/Store.lua: GuildGolemDB, its schema and migrations, the capped error list and the outbox.

local function start(savedText)
  WOW.declareSavedVariables("GuildGolemDB")
  if savedText then WOW.readSavedFile(savedText) end
  local ns = WOW.loadAddon("GuildGolem")
  WOW.login()
  return ns
end

local function savedFixture(n)
  return assert(WOW.readFile("test/lua/fixtures/saved/schema-" .. n .. ".lua"))
end

T.test("a first run makes the table of the current schema, and logout saves it", function()
  local ns = start()
  T.eq(ns.loaded, "new")
  T.eq(GuildGolemDB.schema, ns.Store.SCHEMA)
  T.eq(GuildGolemDB.schema, 1)
  for _, key in ipairs({ "errors", "outbox", "priorities", "nights", "settings" }) do
    T.eq(type(GuildGolemDB[key]), "table", key)
  end
  T.eq(ns.Store.db(), GuildGolemDB)
  T.eq(ns.Store.readOnly(), false)
  local saved = WOW.logout()
  T.eq(saved.GuildGolemDB.schema, 1)
end)

T.test("every schema ever written still loads: each saved file is in test/lua/fixtures/saved", function()
  local ns = start()
  for n = 1, ns.Store.SCHEMA do
    local text = WOW.readFile("test/lua/fixtures/saved/schema-" .. n .. ".lua")
    T.truthy(text, "schema " .. n .. " has a saved file in test/lua/fixtures/saved/")
  end
  for n = 1, ns.Store.SCHEMA do
    WOW.reset()
    local loaded = start(savedFixture(n))
    local db = GuildGolemDB
    T.eq(db.schema, loaded.Store.SCHEMA, "schema " .. n .. " is brought to the current one")
    T.eq(loaded.Store.readOnly(), false)
    T.eq(#db.outbox, 2, "schema " .. n .. ": the outbox is whole")
    T.eq(db.outbox[1].id, "mgq1k2zt.4fa91c07")
    T.truthy(db.outbox[1].text:find("^GG1:eJx90MtuwjAQ"), "the text of the export is untouched")
    T.eq(db.outbox[2].pasted, 1796853900000)
    T.eq(#db.errors, 1)
    T.eq(db.guild.handle, "abcd2345")
    T.eq(db.site.latest, "0.1.0")
    T.eq(db.settings.pugWarnings, true)
    local saved = WOW.logout()
    T.eq(saved.GuildGolemDB.schema, loaded.Store.SCHEMA)
  end
end)

T.test("the current schema is loaded as it is, the very same table", function()
  local ns = start(savedFixture(1))
  T.eq(ns.loaded, "current")
end)

T.test("a table from before the schema was written is upgraded, keeping everything it holds", function()
  local ns = start('GuildGolemDB = { ["outbox"] = { { ["id"] = "old.1", ["text"] = "GG1:abcd" } }, ["extra"] = "kept" }\n')
  T.eq(ns.loaded, "migrated")
  local db = GuildGolemDB
  T.eq(db.schema, 1)
  T.eq(db.outbox[1].id, "old.1")
  T.eq(db.extra, "kept")
  T.same(db.errors, {})
  T.same(db.nights, {})
end)

T.test("a table of an odd shape is upgraded, and what could not be read is kept in unreadable", function()
  local ns = start('GuildGolemDB = { ["schema"] = "one", ["errors"] = "none", ["outbox"] = 5, ["guild"] = "Molten Raiders" }\n')
  local db = GuildGolemDB
  T.eq(ns.loaded, "migrated")
  T.eq(db.schema, 1)
  T.same(db.errors, {})
  T.same(db.outbox, {})
  T.eq(db.unreadable.errors, "none")
  T.eq(db.unreadable.outbox, 5)
  T.eq(db.unreadable.guild, "Molten Raiders")
  T.eq(db.guild, nil)
  -- A schema number that isn't a whole number, or is negative, counts as none.
  local fresh = ns.Store.migrate({ schema = -3.5 })
  T.eq(fresh.schema, 1)
end)

T.test("a saved variable that is not a table is kept, not thrown away", function()
  local ns = start('GuildGolemDB = "garbage"\n')
  T.eq(GuildGolemDB.schema, 1)
  T.eq(GuildGolemDB.unreadable.saved, "garbage")
  T.eq(ns.loaded, "new")
end)

T.test("a table from a newer addon is left untouched, with a warning, and nothing of this session is saved", function()
  local text = 'GuildGolemDB = { ["schema"] = 7, ["outbox"] = { { ["id"] = "future.1", ["text"] = "GG1:zzzz", ["v2"] = true } }, '
    .. '["brandNew"] = { ["a"] = 1 } }\n'
  local ns = start(text)
  T.eq(ns.loaded, "newer")
  T.eq(ns.Store.readOnly(), true)
  T.truthy(ns.Store.warning():find("newer version"), ns.Store.warning())
  T.truthy(WOW.chat[1] and WOW.chat[1]:find("newer version"), "the player is told")
  -- The table the game will save is exactly what it loaded.
  T.eq(GuildGolemDB.schema, 7)
  T.eq(GuildGolemDB.outbox[1].v2, true)
  T.eq(GuildGolemDB.brandNew.a, 1)
  -- This session works on a scratch table.
  T.truthy(ns.Store.db() ~= GuildGolemDB)
  T.eq(ns.Store.db().schema, 1)
  ns.Store.recordError("test", "an error in the scratch table")
  T.eq(#ns.Store.db().errors, 1)
  T.eq(GuildGolemDB.errors, nil, "the saved table has no errors added")
  local entry, why = ns.Store.outboxAdd({ id = "new.1", text = "GG1:abcd" })
  T.eq(entry, nil)
  T.eq(why, "read-only")
  T.eq(select(2, ns.Store.outboxMarkPasted("future.1")), "read-only")
  T.eq(ns.Store.outboxPrune(), 0)
  local saved = WOW.logout()
  T.same(saved.GuildGolemDB, { schema = 7, outbox = { { id = "future.1", text = "GG1:zzzz", v2 = true } }, brandNew = { a = 1 } })
end)

T.test("migrations only go forward, one step at a time, from any older schema", function()
  WOW.declareSavedVariables("GuildGolemDB")
  local ns = WOW.loadAddon("GuildGolem")
  local Store = ns.Store
  -- A pretend second schema: it adds a field and renames one.
  Store.SCHEMA = 2
  Store.MIGRATIONS[2] = function(db)
    db.settings.sound = db.settings.pugWarnings
    db.settings.pugWarnings = nil
  end
  local from1 = Store.migrate({ schema = 1, errors = {}, outbox = {}, priorities = {}, nights = {}, settings = { pugWarnings = true } })
  T.eq(from1.schema, 2)
  T.eq(from1.settings.sound, true)
  T.eq(from1.settings.pugWarnings, nil)
  local from0, status, was = Store.migrate({ settings = { pugWarnings = false } })
  T.eq(status, "migrated")
  T.eq(was, 0)
  T.eq(from0.schema, 2)
  T.eq(from0.settings.sound, false)
  -- Already there, and newer than this.
  T.eq(select(2, Store.migrate({ schema = 2 })), "current")
  T.eq(select(2, Store.migrate({ schema = 3 })), "newer")
end)

T.test("a migration that fails leaves the saved table as it was, with a warning", function()
  WOW.declareSavedVariables("GuildGolemDB")
  WOW.readSavedFile('GuildGolemDB = { ["schema"] = 1, ["outbox"] = { { ["id"] = "x.1", ["text"] = "GG1:abcd" } } }\n')
  local ns = WOW.loadAddon("GuildGolem")
  -- Loaded and current at schema 1. Now a second schema whose migration breaks half way.
  local Store = ns.Store
  Store.SCHEMA = 2
  Store.MIGRATIONS[2] = function(db)
    db.outbox = nil
    error("boom")
  end
  local original = GuildGolemDB
  local db, status, from, warning = Store.migrate(original)
  T.eq(status, "failed")
  T.eq(from, 1)
  T.eq(db, original, "the original table comes back")
  T.eq(original.schema, 1)
  T.eq(original.outbox[1].id, "x.1", "the half-done change was made on a copy")
  T.truthy(warning:find("boom"))
  Store.init()
  T.eq(Store.readOnly(), true)
  T.eq(GuildGolemDB, original)
  -- A step with no migration is a failure too.
  Store.MIGRATIONS[2] = function() end
  Store.SCHEMA = 3
  local _, why = Store.migrate({ schema = 1 })
  T.eq(why, "failed")
end)

T.test("the error list keeps the newest 50, with where and when, and cuts a long message", function()
  local ns = start()
  for i = 1, 60 do ns.Store.recordError("where " .. i, "message " .. i) end
  local errors = GuildGolemDB.errors
  T.eq(#errors, 50)
  T.eq(errors[1].where, "where 11")
  T.eq(errors[50].message, "message 60")
  T.eq(errors[50].at, GetServerTime())
  ns.Store.recordError("long", string.rep("x", 5000))
  T.eq(#GuildGolemDB.errors[50].message, 603)
  ns.Store.recordError("table", { 1, 2 })
  T.truthy(GuildGolemDB.errors[50].message:find("^table"))
end)

T.test("an error raised before the saved variables loaded is kept and joins the list", function()
  WOW.declareSavedVariables("GuildGolemDB")
  WOW.readSavedFile(savedFixture(1))
  local ns = {}
  WOW.dofile("GuildGolem/Core/Store.lua", "GuildGolem", ns)
  ns.Store.recordError("early", "before the table")
  T.eq(ns.Store.db(), nil)
  WOW.loadSavedVariables()
  ns.Store.init()
  T.eq(#GuildGolemDB.errors, 2)
  T.eq(GuildGolemDB.errors[2].where, "early")
end)

T.test("the outbox holds an export once, by its id, and keeps it until it has been pasted and a month has gone", function()
  local ns = start()
  local S = ns.Store
  local entry, added = S.outboxAdd({ id = "mgq1k2zt.4fa91c07", text = "GG1:abcd", kind = "export" })
  T.truthy(added)
  T.eq(entry.text, "GG1:abcd")
  T.eq(entry.made, GetServerTime() * 1000, "made now, from the server's clock")
  local again, addedAgain = S.outboxAdd({ id = "mgq1k2zt.4fa91c07", text = "GG1:other" })
  T.eq(addedAgain, false)
  T.eq(again.text, "GG1:abcd", "the first one stays")
  S.outboxAdd({ id = "second.2", text = "GG1:efgh" })
  T.eq(#S.outboxPending(), 2)
  T.eq(S.outboxPending()[1].id, "mgq1k2zt.4fa91c07")

  -- A year goes by: nothing that was not pasted is dropped.
  WOW.advance(365 * 24 * 3600)
  T.eq(S.outboxPrune(), 0)
  T.eq(#GuildGolemDB.outbox, 2)

  -- Pasted: no longer pending, kept for a month, then gone.
  S.outboxMarkPasted("mgq1k2zt.4fa91c07")
  T.eq(#S.outboxPending(), 1)
  T.eq(S.outboxPending()[1].id, "second.2")
  T.eq(S.outboxPrune(), 0, "a day later it is still there")
  WOW.advance(29 * 24 * 3600)
  T.eq(S.outboxPrune(), 0)
  WOW.advance(2 * 24 * 3600)
  T.eq(S.outboxPrune(), 1)
  T.eq(#GuildGolemDB.outbox, 1)
  T.eq(GuildGolemDB.outbox[1].id, "second.2")
end)

T.test("the outbox refuses a bad entry, and says when an id is unknown", function()
  local ns = start()
  for _, bad in ipairs({ {}, { id = "", text = "x" }, { id = "a" }, { id = 5, text = "x" }, "text" }) do
    T.eq(select(2, ns.Store.outboxAdd(bad)), "bad-entry")
  end
  T.eq(select(2, ns.Store.outboxMarkPasted("nobody")), "unknown")
end)

T.test("the outbox, the errors and the rest survive a logout and the next login", function()
  local ns = start()
  ns.Store.outboxAdd({ id = "keep.1", text = "GG1:abcd", kind = "export" })
  ns.Store.recordError("somewhere", "something")
  WOW.logout()
  local file = WOW.savedFile
  T.truthy(file:find("^GuildGolemDB = {"))
  WOW.reset()
  local again = start(file)
  T.eq(again.loaded, "current")
  T.eq(#again.Store.outboxPending(), 1)
  T.eq(again.Store.outboxPending()[1].text, "GG1:abcd")
  T.eq(GuildGolemDB.errors[1].message, "something")
end)

T.test("an outbox is not dropped by a migration, whatever it holds", function()
  local ns = start('GuildGolemDB = { ["schema"] = 0, ["outbox"] = { { ["id"] = "a", ["text"] = "GG1:1" }, "stray text", { ["id"] = "b" } } }\n')
  local outbox = GuildGolemDB.outbox
  T.eq(#outbox, 3)
  T.eq(outbox[2], "stray text")
  T.eq(outbox[3].id, "b")
  -- What isn't a table is left where it is, and is not an export waiting.
  T.eq(#ns.Store.outboxPending(), 2)
end)
