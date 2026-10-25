-- The saved variables: GuildGolemDB, one table for the whole account (docs/PLAN.md, "Core"). It carries a `schema`
-- number, and a migration for every change to its shape. Migrations only go forward. A table from a newer addon is
-- left exactly as it is, with a warning, and this addon works on a scratch copy that is never saved, so going back to
-- an older version never loses what the newer one wrote.
--
-- The shape (schema 1):
--   schema      1
--   errors      { { at, where, message }, ... }  the last errors a handler raised, at most MAX_ERRORS
--   outbox      { { id, made, kind, text, pasted }, ... }  exports made and not yet pasted on the site. Never
--               dropped: only an entry marked pasted, and a month old, ever goes (outboxPrune)
--   guild       { handle, name }  from the last import
--   site        { version, latest, made }  from the last import
--   priorities  { [zone] = import }  the last priorities import for each raid
--   nights      { [handle] = night }  see Import.lua
--   settings    {}
--   unreadable  { [key] = value }  anything a migration could not read as the shape it should be, kept as it was
--
-- Plain Lua; the clock comes from ns.Client, so a test can leave it out.

local ADDON, ns = ...

local Store = {}
ns.Store = Store

Store.SCHEMA = 1
Store.MAX_ERRORS = 50
Store.MAX_MESSAGE = 600
-- A pasted export is kept this long (30 days, in milliseconds) in case the site needs it again. Written out, since
-- the test harness's integers are 32 bits and 30 * 24 * 3600 * 1000 would wrap there.
Store.KEEP_PASTED_MS = 2592000000

-- Where the table in use is, and why it is not the saved one if it is not.
local state = { db = nil, readOnly = false, warning = nil, pending = {} }
Store.state = state

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for k, v in pairs(value) do out[copy(k, seen)] = copy(v, seen) end
  return out
end

local function now()
  local client = ns.Client
  return client and client.serverTime and client.serverTime() or nil
end

local function nowMs()
  local client = ns.Client
  return client and client.serverTimeMs and client.serverTimeMs() or nil
end

-- The shape -------------------------------------------------------------------------------------------------------

-- A new table, the shape of the current schema.
function Store.default()
  return {
    schema = Store.SCHEMA,
    errors = {},
    outbox = {},
    priorities = {},
    nights = {},
    settings = {},
  }
end

-- MIGRATIONS[n] takes a table of schema n - 1 to schema n, in place. Add one with every new schema, and add that
-- schema's saved file to test/lua/fixtures/saved/ (the test fails until it is there). Never change a migration that
-- has shipped, since players' files are at every step.
local MIGRATIONS = {}

-- Schema 1 is the first. A table with no schema is a new one, or one from before the schema was written: whatever
-- it holds is kept, and what is missing is filled in. A key that holds the wrong kind of thing is moved to
-- `unreadable` instead of being thrown away.
MIGRATIONS[1] = function(db)
  local function table_(key)
    local value = db[key]
    if type(value) == "table" then return end
    if value ~= nil then
      db.unreadable = db.unreadable or {}
      db.unreadable[key] = value
    end
    db[key] = {}
  end
  for _, key in ipairs({ "errors", "outbox", "priorities", "nights", "settings" }) do table_(key) end
  for _, key in ipairs({ "guild", "site" }) do
    if db[key] ~= nil and type(db[key]) ~= "table" then
      db.unreadable = db.unreadable or {}
      db.unreadable[key] = db[key]
      db[key] = nil
    end
  end
end
Store.MIGRATIONS = MIGRATIONS

-- Brings a saved table to the current schema. Returns the table to use and a status:
--   "new"       there was none (or it was not a table: the old value is kept in `unreadable.saved`)
--   "current"   already the current schema, nothing changed
--   "migrated"  upgraded, from `from`; the third result
--   "newer"     from a newer addon: returned as it was, not touched, with a warning as the fourth result
--   "failed"    a migration raised an error: the original is returned as it was, with the warning
-- The table is changed on a copy, and the copy replaces the original only when every step has worked.
function Store.migrate(saved)
  if saved == nil then return Store.default(), "new" end
  if type(saved) ~= "table" then
    local db = Store.default()
    db.unreadable = { saved = saved }
    return db, "new"
  end

  local from = saved.schema
  if type(from) ~= "number" or from < 0 or from ~= math.floor(from) then from = 0 end

  if from > Store.SCHEMA then
    return saved, "newer", from, string.format(
      "Guild Golem's saved data is from a newer version of the addon (it is schema %.0f, this is %.0f). "
        .. "It is left as it is and this session's changes are not saved. Update the addon.",
      from, Store.SCHEMA)
  end
  if from == Store.SCHEMA then return saved, "current" end

  local work = copy(saved)
  for step = from + 1, Store.SCHEMA do
    local migration = MIGRATIONS[step]
    local ok, err = false, "there is no migration to schema " .. step
    if migration then ok, err = pcall(migration, work) end
    if not ok then
      return saved, "failed", from, string.format(
        "Guild Golem could not upgrade its saved data to schema %.0f (%s). It is left as it is and this session's "
          .. "changes are not saved.", step, tostring(err))
    end
    work.schema = step
  end
  return work, "migrated", from
end

-- Loads the saved variables. Call it once, when the addon's saved variables have loaded (ADDON_LOADED for this
-- addon). Sets the global GuildGolemDB, unless the saved table is from a newer addon (or could not be upgraded), in
-- which case the global stays exactly as it was and a scratch table is used. Returns the status and the warning.
function Store.init()
  local db, status, from, warning = Store.migrate(GuildGolemDB)
  state.readOnly = false
  state.warning = nil
  if status == "newer" or status == "failed" then
    state.readOnly = true
    state.warning = warning
    state.db = Store.default()
  else
    GuildGolemDB = db
    state.db = db
  end
  -- Errors raised before the table was there.
  for _, entry in ipairs(state.pending) do Store.recordError(entry.where, entry.message, entry.at) end
  state.pending = {}
  return status, state.warning, from
end

-- The table the addon reads and writes. Nil before Store.init.
function Store.db()
  return state.db
end

-- True when this session's changes are not being saved (the saved data is from a newer addon).
function Store.readOnly()
  return state.readOnly
end

function Store.warning()
  return state.warning
end

-- Errors -----------------------------------------------------------------------------------------------------------

-- Records an error from a handler: { at, where, message }, the newest last, at most MAX_ERRORS kept (the oldest go).
function Store.recordError(where, message, at)
  message = tostring(message)
  if #message > Store.MAX_MESSAGE then message = string.sub(message, 1, Store.MAX_MESSAGE) .. "..." end
  local entry = { at = at or now(), where = tostring(where), message = message }
  local db = state.db
  if not db then
    -- Before Store.init: kept in memory, with the same cap.
    state.pending[#state.pending + 1] = entry
    if #state.pending > Store.MAX_ERRORS then table.remove(state.pending, 1) end
    return entry
  end
  local errors = db.errors
  errors[#errors + 1] = entry
  while #errors > Store.MAX_ERRORS do table.remove(errors, 1) end
  return entry
end

-- The outbox ---------------------------------------------------------------------------------------------------------

-- Adds an export that is waiting to be pasted: { id, text, kind?, made? }. `id` is the export's meta.id, so the
-- same export added twice is held once. Returns the entry and true when it was added, the entry and false when one
-- with that id was there already, or nil and why. This is the one place an export is kept, so it is never dropped
-- by anything but outboxPrune, and that only for one pasted a month ago.
function Store.outboxAdd(entry)
  if type(entry) ~= "table" or type(entry.id) ~= "string" or entry.id == "" or type(entry.text) ~= "string" then
    return nil, "bad-entry"
  end
  if state.readOnly then return nil, "read-only" end
  local db = state.db
  if not db then return nil, "not-ready" end
  for _, have in ipairs(db.outbox) do
    if have.id == entry.id then return have, false end
  end
  local stored = { id = entry.id, text = entry.text, kind = entry.kind, made = entry.made or nowMs() }
  db.outbox[#db.outbox + 1] = stored
  return stored, true
end

-- The exports not yet pasted, oldest first.
function Store.outboxPending()
  local out = {}
  if not state.db then return out end
  for _, entry in ipairs(state.db.outbox) do
    if type(entry) == "table" and not entry.pasted then out[#out + 1] = entry end
  end
  return out
end

-- Marks an export as pasted on the site (the officer says so). It stays for a month, then outboxPrune takes it.
function Store.outboxMarkPasted(id, at)
  if state.readOnly then return nil, "read-only" end
  if not state.db then return nil, "not-ready" end
  for _, entry in ipairs(state.db.outbox) do
    if entry.id == id then
      entry.pasted = entry.pasted or at or nowMs()
      return entry
    end
  end
  return nil, "unknown"
end

-- Removes the exports that were pasted more than KEEP_PASTED ago, and nothing else. An export not yet pasted stays
-- however old it is. Returns how many went.
function Store.outboxPrune(atMs)
  if state.readOnly or not state.db then return 0 end
  atMs = atMs or nowMs()
  if not atMs then return 0 end
  local keep, removed = {}, 0
  for _, entry in ipairs(state.db.outbox) do
    if type(entry.pasted) == "number" and atMs - entry.pasted > Store.KEEP_PASTED_MS then
      removed = removed + 1
    else
      keep[#keep + 1] = entry
    end
  end
  if removed > 0 then state.db.outbox = keep end
  return removed
end
