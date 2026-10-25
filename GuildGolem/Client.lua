-- The launch adapter: the ONLY file of the addon that names the game's functions (docs/PLAN.md; test/globals.test.mjs
-- checks it). Everything else asks the Client for plain data, so everything else runs in a test with no game at all,
-- and a change on the client is a change here.
--
-- Rules every function follows:
--   * The API is looked for before it is used (type(x) == "function"). A client without it gets nothing back, never
--     an error. Client.caps() says what is there.
--   * Every call to the game runs under pcall. An error is passed to Client.onError(where, message) and the function
--     gives back what it could. Nothing here raises.
--   * A secret value (issecretvalue, canaccessvalue, docs/RESEARCH.md "Corrections and additions") is never
--     compared, joined or kept: the field it came in is left out.
--   * What comes back is plain data: strings, numbers, booleans and tables of them.
--
-- A line marked "unverified on Forever" follows retail's documented shape, and Forever's client has not been seen
-- doing it: the launch-day probe pass (docs/RESEARCH.md, "Launch-day probe") checks each one, and a raid checks the
-- ones that need a raid.

local ADDON, ns = ...

local Client = {}
ns.Client = Client

local pcall, type, tostring, tonumber, select = pcall, type, tostring, tonumber, select
local format, lower, match, find, sub = string.format, string.lower, string.match, string.find, string.sub

-- Calling the game -----------------------------------------------------------------------------------------------

-- How many errors the game's functions have raised, and where the addon hears of them: set Client.onError to a
-- function(where, message). Main.lua points it at the saved variables' error list.
Client.errorCount = 0
Client.onError = nil

local function report(where, err)
  Client.errorCount = Client.errorCount + 1
  local handler = Client.onError
  if handler then
    -- The message may itself be a secret or a table: only text is passed on.
    local ok, text = pcall(tostring, err)
    pcall(handler, where, ok and text or "an error that is not text")
  end
end

local function finish(where, ok, ...)
  if not ok then
    report(where, (...))
    return false
  end
  return true, ...
end

-- Calls fn(...) if it is a function. Returns true and its results, or false (and no results) when it is missing or
-- raised an error.
local function call(where, fn, ...)
  if type(fn) ~= "function" then return false end
  return finish(where, pcall(fn, ...))
end

-- A function in a table the game may not have: member(C_ChatInfo, "SendAddonMessage").
local function member(tbl, key)
  if type(tbl) ~= "table" then return nil end
  local ok, value = pcall(function() return tbl[key] end)
  if ok then return value end
  return nil
end

local function isFunction(value) return type(value) == "function" end

-- Secret values ----------------------------------------------------------------------------------------------------

-- True when the game says `value` is secret, or that this code may not read it.
function Client.isSecret(value)
  if type(issecretvalue) == "function" then
    local ok, secret = pcall(issecretvalue, value)
    if ok and secret then return true end
  end
  if type(canaccessvalue) == "function" then
    local ok, can = pcall(canaccessvalue, value)
    if ok and can == false then return true end
  end
  return false
end

local isSecret = Client.isSecret

-- The value if it is a plain string, number or boolean that is not secret; otherwise nil.
local function plain(value)
  local t = type(value)
  if t ~= "string" and t ~= "number" and t ~= "boolean" then return nil end
  if isSecret(value) then return nil end
  return value
end

local function plainString(value)
  value = plain(value)
  if type(value) == "string" then return value end
  return nil
end

local function plainNumber(value)
  value = plain(value)
  if type(value) == "number" then return value end
  return nil
end

-- A copy of a table of plain values, two levels deep, with anything secret or not plain left out.
local function plainTable(value, depth)
  if type(value) ~= "table" or isSecret(value) then return nil end
  depth = depth or 0
  local out = {}
  local ok = pcall(function()
    for k, v in pairs(value) do
      local kt = type(k)
      if kt == "string" or kt == "number" then
        if type(v) == "table" then
          if depth < 1 then out[k] = plainTable(v, depth + 1) end
        else
          out[k] = plain(v)
        end
      end
    end
  end)
  if not ok then return nil end
  return out
end

-- What is available -----------------------------------------------------------------------------------------------

-- A table of booleans: true when the client has that API. A caller checks before it relies on one.
function Client.caps()
  return {
    buildInfo = isFunction(GetBuildInfo),
    locale = isFunction(GetLocale),
    serverTime = isFunction(GetServerTime),
    uptime = isFunction(GetTime),
    unitGUID = isFunction(UnitGUID),
    unitName = isFunction(UnitName),
    raidRoster = isFunction(GetRaidRosterInfo) and isFunction(GetNumGroupMembers) and isFunction(IsInRaid),
    group = isFunction(IsInGroup) and isFunction(GetNumGroupMembers),
    instance = isFunction(GetInstanceInfo),
    guild = isFunction(GetGuildInfo),
    savedInstances = isFunction(GetNumSavedInstances) and isFunction(GetSavedInstanceInfo),
    lootHistory = type(C_LootHistory) == "table",
    addonMessages = isFunction(member(C_ChatInfo, "SendAddonMessage")),
    messagePrefix = isFunction(member(C_ChatInfo, "RegisterAddonMessagePrefix")) or isFunction(RegisterAddonMessagePrefix),
    chatLockdown = isFunction(member(C_ChatInfo, "InChatMessagingLockdown")),
    secretValues = isFunction(issecretvalue),
    canAccessValue = isFunction(canaccessvalue),
    encounterInProgress = isFunction(IsEncounterInProgress),
    timers = isFunction(member(C_Timer, "After")),
    frames = isFunction(CreateFrame),
    metadata = isFunction(member(C_AddOns, "GetAddOnMetadata")) or isFunction(GetAddOnMetadata),
    loggingCombat = isFunction(LoggingCombat),
    raidInfo = isFunction(RequestRaidInfo),
    slashCommands = type(SlashCmdList) == "table",
    windows = isFunction(CreateFrame) and type(UIParent) == "table",
  }
end

-- The client, the clock, the player --------------------------------------------------------------------------------

-- The server's clock in whole seconds, or nil. Times in the contract come from here and never from time(), since
-- the computer's clock can be wrong (contract/README.md, "Times").
function Client.serverTime()
  local ok, t = call("GetServerTime", GetServerTime)
  t = ok and plainNumber(t) or nil
  return t
end

-- The same in epoch milliseconds, which is what every time in the contract is.
function Client.serverTimeMs()
  local t = Client.serverTime()
  if t then return t * 1000 end
  return nil
end

-- How far the computer's clock was from the server's, in milliseconds: the server's time less time(). Negative when the
-- computer runs ahead. It is the export's meta.skew (contract/README.md). Nil when either clock is missing.
function Client.skewMs()
  local server = Client.serverTimeMs()
  local ok, local_ = call("time", time)
  local_ = ok and plainNumber(local_) or nil
  if not server or not local_ then return nil end
  return server - local_ * 1000
end

-- The game's uptime clock in seconds (GetTime), for measuring gaps; not a date.
function Client.uptime()
  local ok, t = call("GetTime", GetTime)
  return ok and plainNumber(t) or nil
end

-- GetBuildInfo and GetLocale as an export's meta.client wants them (contract/README.md): version "1.60.1", build 70532
-- as a number (the game returns it as text), interface 16001 and locale "enUS". Also the realm and the game type.
function Client.build()
  local out = {}
  local ok, version, build, date, toc = call("GetBuildInfo", GetBuildInfo)
  if ok then
    out.version = plainString(version)
    out.build = tonumber(plain(build))
    out.date = plainString(date)
    out.interface = tonumber(plain(toc))
  end
  local okLocale, locale = call("GetLocale", GetLocale)
  if okLocale then out.locale = plainString(locale) end
  local okRealm, realm = call("GetRealmName", GetRealmName)
  if okRealm then out.realm = plainString(realm) end
  if type(WOW_PROJECT_ID) == "number" then out.project = WOW_PROJECT_ID end
  return out
end

-- The addon's version as the contract writes it (1.2.3 or 1.2.3-beta). The packager puts the release tag in the TOC,
-- which may begin with a v. A copy that was never packaged shows the placeholder, and reads as 0.0.0-dev.
function Client.addonVersion()
  local ok, raw = call("GetAddOnMetadata", member(C_AddOns, "GetAddOnMetadata") or GetAddOnMetadata, ADDON, "Version")
  raw = ok and plainString(raw) or nil
  local core, rest = match(raw or "", "^v?(%d+%.%d+%.%d+)(.*)$")
  if not core then return "0.0.0-dev" end
  -- One suffix word is kept (1.2.3-beta); a build count after it (-3-gabc123) is not part of the contract's form.
  local suffix = match(rest, "^%-([%a%d%.]+)")
  if suffix then return core .. "-" .. lower(suffix) end
  return core
end

-- A unit's full name, "First Surname". On Forever UnitName gives the first name and the surname as two values, and
-- the roster gives them already joined (docs/RESEARCH.md, "Probe results").
local function fullName(unit)
  local ok, first, surname = call("UnitName", UnitName, unit)
  if not ok then return nil end
  first = plainString(first)
  surname = plainString(surname)
  if not first then return nil end
  if surname and surname ~= "" then return first .. " " .. surname end
  return first
end

local function classOf(unit)
  local ok, _, token = call("UnitClass", UnitClass, unit)
  token = ok and plainString(token) or nil
  return token and lower(token) or nil
end

local function guidOf(unit)
  local ok, guid = call("UnitGUID", UnitGUID, unit)
  return ok and plainString(guid) or nil
end

-- The player running the addon: { guid, name, cls }.
function Client.player()
  return { guid = guidOf("player"), name = fullName("player"), cls = classOf("player") }
end

-- The group -------------------------------------------------------------------------------------------------------

-- Everyone in the group as plain rows, and the kind of group: "raid", "party" or "none" (alone). A row is
--   { unit, guid, name, cls, group, online, zone, rank, level }
-- `cls` is the class token in lowercase and `group` the subgroup 1 to 8 (a party is all in 1). `zone` is the
-- roster's zone label as the client writes it, left out for someone offline. A field the client would not give, or
-- gave as a secret, is nil.
-- (unverified on Forever inside a raid instance, where chat and some values turn secret. Outside one the probe saw the
-- roster's names, zones and GUIDs, and a party's units)
function Client.roster()
  local rows = {}
  local okRaid, inRaid = call("IsInRaid", IsInRaid)
  local okGroup, inGroup = call("IsInGroup", IsInGroup)
  local okCount, count = call("GetNumGroupMembers", GetNumGroupMembers)
  count = okCount and plainNumber(count) or 0

  if okRaid and inRaid == true then
    for i = 1, count do
      local unit = format("raid%d", i)
      -- name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole
      local ok, name, rank, subgroup, level, _, fileName, zone, online = call("GetRaidRosterInfo", GetRaidRosterInfo, i)
      if ok then
        name = plainString(name)
        fileName = plainString(fileName)
        online = plain(online)
        local row = {
          unit = unit,
          guid = guidOf(unit),
          name = name,
          cls = fileName and lower(fileName) or nil,
          group = plainNumber(subgroup),
          online = online == true,
          rank = plainNumber(rank),
          level = plainNumber(level),
        }
        if online == true then row.zone = plainString(zone) end
        if name or row.guid then rows[#rows + 1] = row end
      end
    end
    return rows, "raid"
  end

  if okGroup and inGroup == true then
    local units = { "player" }
    for i = 1, count - 1 do units[#units + 1] = format("party%d", i) end
    for _, unit in ipairs(units) do
      local okConn, connected = call("UnitIsConnected", UnitIsConnected, unit)
      local row = {
        unit = unit,
        guid = guidOf(unit),
        name = fullName(unit),
        cls = classOf(unit),
        group = 1,
        online = (not okConn) or plain(connected) ~= false,
      }
      if row.name or row.guid then rows[#rows + 1] = row end
    end
    return rows, "party"
  end

  return rows, "none"
end

-- "raid", "party" or "none" (alone): the kind of group, without reading anyone's row. A handler that only needs to know
-- whether there is a group asks this, since the roster costs a call for every member.
function Client.groupKind()
  local okRaid, inRaid = call("IsInRaid", IsInRaid)
  if okRaid and inRaid == true then return "raid" end
  local okGroup, inGroup = call("IsInGroup", IsInGroup)
  if okGroup and inGroup == true then return "party" end
  return "none"
end

-- The instance the player is in ----------------------------------------------------------------------------------

-- { name, type, difficulty, difficultyName, maxPlayers, instanceID, groupSize }, or nil without the API. `instanceID`
-- is the contract's `zone` and `difficulty` its `difficulty`. In the open world instanceID is 0 and type is "none".
-- (unverified on Forever inside an instance: the launch-day probe records what GetInstanceInfo gives in a dungeon)
function Client.instance()
  -- name, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceID,
  -- instanceGroupSize, LfgDungeonID
  local ok, name, kind, difficulty, difficultyName, maxPlayers, _, _, instanceID, groupSize = call("GetInstanceInfo", GetInstanceInfo)
  if not ok then return nil end
  return {
    name = plainString(name),
    type = plainString(kind),
    difficulty = plainNumber(difficulty),
    difficultyName = plainString(difficultyName),
    maxPlayers = plainNumber(maxPlayers),
    instanceID = plainNumber(instanceID),
    groupSize = plainNumber(groupSize),
  }
end

-- The saved lockouts: a list of { name, id, difficulty, locked, raid, maxPlayers }. `id` is the lockout id the
-- contract's attendance `lockout` carries. Empty without the API.
function Client.lockouts()
  local rows = {}
  local ok, count = call("GetNumSavedInstances", GetNumSavedInstances)
  count = ok and plainNumber(count) or 0
  for i = 1, count do
    -- name, lockoutId, reset, difficultyId, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName
    -- (unverified on Forever: the probe records the first eight; the ninth is retail's)
    local got, name, id, _, difficulty, locked, _, _, isRaid, maxPlayers = call("GetSavedInstanceInfo", GetSavedInstanceInfo, i)
    if got then
      rows[#rows + 1] = {
        name = plainString(name),
        id = plainNumber(id),
        difficulty = plainNumber(difficulty),
        locked = plain(locked) == true,
        raid = plain(isRaid) == true,
        maxPlayers = plainNumber(maxPlayers),
      }
    end
  end
  return rows
end

-- Asks the game to refresh its list of saved instances; it answers with UPDATE_INSTANCE_INFO, after which
-- Client.lockouts() has the lockout a kill just made. False when the client has no such call.
-- (unverified on Forever: the probe records the lockout ids; RequestRaidInfo is retail's)
function Client.requestRaidInfo()
  local ok = call("RequestRaidInfo", RequestRaidInfo)
  return ok
end

-- Combat logging -----------------------------------------------------------------------------------------------------

-- True when the client is writing the combat log, false when it is not, nil when the client cannot say. (The probe
-- reads it: retail gives a boolean, older clients 1 or nil.)
function Client.loggingCombat()
  local ok, value = call("LoggingCombat", LoggingCombat)
  if not ok then return nil end
  value = plain(value)
  return value == true or value == 1
end

-- Turns combat logging on and says whether it is on now. There is no function here that turns it off: the addon never
-- does (docs/PLAN.md, "Attendance"). False and why when the client has no LoggingCombat or it did not take.
function Client.enableCombatLogging()
  if type(LoggingCombat) ~= "function" then return false, "no-api" end
  if not call("LoggingCombat", LoggingCombat, true) then return false, "error" end
  if Client.loggingCombat() == true then return true end
  return false, "refused"
end

-- The guild --------------------------------------------------------------------------------------------------------

-- { name, rank, rankIndex, realm } for a unit (the player by default), or nil when it is in no guild. The fourth
-- value names a sub-realm on Forever (docs/RESEARCH.md, "Probe results").
function Client.guild(unit)
  local ok, name, rank, rankIndex, realm = call("GetGuildInfo", GetGuildInfo, unit or "player")
  name = ok and plainString(name) or nil
  if not name then return nil end
  return { name = name, rank = plainString(rank), rankIndex = plainNumber(rankIndex), realm = plainString(realm) }
end

-- Encounters ---------------------------------------------------------------------------------------------------------

-- ENCOUNTER_START(encounterID, encounterName, difficultyID, groupSize) as a row { id, name, difficulty, size }.
-- (unverified on Forever: the probe's launch-day pass records the arguments; this is retail's order)
function Client.encounterStart(id, name, difficulty, size)
  return {
    id = plainNumber(id),
    name = plainString(name),
    difficulty = plainNumber(difficulty),
    size = plainNumber(size),
  }
end

-- ENCOUNTER_END(encounterID, encounterName, difficultyID, groupSize, success, ...) as a row { id, name, difficulty,
-- size, success, kill, unitStatus }. `success` is a number on Forever (docs/RESEARCH.md); `kill` is true for 1.
-- `unitStatus` is the creature health left at a wipe, if the client sends it, copied as plain data.
-- (unverified on Forever: the order of the arguments, and the shape of the status after `success`)
function Client.encounterEnd(id, name, difficulty, size, success, status)
  local row = Client.encounterStart(id, name, difficulty, size)
  row.success = plainNumber(success)
  if row.success == nil and plain(success) == true then row.success = 1 end
  row.kill = row.success == 1
  row.unitStatus = plainTable(status)
  return row
end

-- Whether the client says an encounter is going on now, or nil if it cannot say. (unverified on Forever: the probe
-- calls it at ENCOUNTER_END only)
function Client.encounterInProgress()
  local ok, going = call("IsEncounterInProgress", IsEncounterInProgress)
  if not ok then return nil end
  return plain(going) == true
end

-- Loot ---------------------------------------------------------------------------------------------------------------

-- The colors of an item link, to the game's quality numbers (2 uncommon, 3 rare, 4 epic, 5 legendary).
local QUALITY = {
  ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5, ffe6cc80 = 6, ff00ccff = 7,
}

-- The parts of an item link the contract's loot award keeps: `link` is the payload as the game wrote it, from
-- "item:" up to but not including the closing "|h", without color codes; `item` its id; `name` the name between the
-- brackets; `quality` from the color. Anything that is not an item link gives nil.
function Client.parseItemLink(text)
  if type(text) ~= "string" or isSecret(text) then return nil end
  local payload = match(text, "|H(item:[^|]*)|h")
  if not payload then
    if match(text, "^item:%d") then payload = text else return nil end
  end
  local id = tonumber(match(payload, "^item:(%d+)"))
  if not id then return nil end
  local color = match(text, "|c(%x%x%x%x%x%x%x%x)|H")
  return {
    link = payload,
    item = id,
    name = match(text, "|h%[(.-)%]|h"),
    quality = color and QUALITY[lower(color)] or nil,
  }
end

-- ENCOUNTER_LOOT_RECEIVED(encounterID, itemID, itemLink, quantity, playerName, className) as a row
--   { encounter, item, link, name, quality, count, winner, cls, className }
-- `winner` is the player's name (the game gives a name here and no GUID; the winner's GUID comes from C_LootHistory
-- or an exact roster match, contract/README.md "The winner's GUID"). `cls` is set only when the class comes as a
-- token ("MAGE"); a localized name stays in `className`.
-- (unverified on Forever: the probe saw the link and the winner outside an instance. The order of the arguments is
-- retail's, and so is className being a token)
function Client.lootReceived(encounterID, itemID, itemLink, quantity, playerName, className)
  local row = {
    encounter = plainNumber(encounterID),
    item = plainNumber(itemID),
    count = plainNumber(quantity),
    winner = plainString(playerName),
  }
  local parsed = Client.parseItemLink(itemLink)
  if parsed then
    row.link, row.name, row.quality = parsed.link, parsed.name, parsed.quality
    row.item = row.item or parsed.item
  end
  className = plainString(className)
  if className then
    if match(className, "^%u+$") then row.cls = lower(className) else row.className = className end
  end
  return row
end

-- Addon messages and restrictions ----------------------------------------------------------------------------------

-- The names of Enum.SendAddonMessageResult, by value.
local function enumName(enum, value)
  if type(enum) ~= "table" then return nil end
  local ok, found = pcall(function()
    for name, v in pairs(enum) do
      if v == value then return name end
    end
  end)
  if ok then return found end
  return nil
end

-- Registers a prefix for addon messages. True when it took.
function Client.registerPrefix(prefix)
  local fn = member(C_ChatInfo, "RegisterAddonMessagePrefix") or RegisterAddonMessagePrefix
  local ok, result = call("RegisterAddonMessagePrefix", fn, prefix)
  return ok and result ~= false
end

-- Sends an addon message. Gives true when it was sent, or false and why: "lockdown" (the client is holding addon
-- messages, as during an encounter), "throttled" (too many, try again in a second), "no-api", "error", or the name
-- the client gave the refusal.
-- (unverified on Forever: that SendAddonMessage returns Enum.SendAddonMessageResult here, and in a raid; the probe
-- recorded sends outside instances)
function Client.send(prefix, text, chatType, target)
  local fn = member(C_ChatInfo, "SendAddonMessage")
  if type(fn) ~= "function" then return false, "no-api" end
  local ok, result = call("SendAddonMessage", fn, prefix, text, chatType, target)
  if not ok then return false, "error" end
  result = plain(result)
  local results = member(Enum, "SendAddonMessageResult")
  local success = member(results, "Success") or 0
  if result == nil or result == true or result == success then return true end
  local name = enumName(results, result)
  if name == "AddOnMessageLockdown" then return false, "lockdown" end
  if name == "AddonMessageThrottle" or name == "ChannelThrottle" then return false, "throttled" end
  return false, name or "refused"
end

-- True while the client keeps chat and addon messages back (an encounter, or a restricted map), false when it does
-- not, nil when it cannot say. (unverified on Forever: InChatMessagingLockdown exists in the 70450 UI source)
function Client.chatLockdown()
  local ok, locked = call("InChatMessagingLockdown", member(C_ChatInfo, "InChatMessagingLockdown"))
  if not ok then return nil end
  return plain(locked) == true
end

-- ADDON_RESTRICTION_STATE_CHANGED(type, state) as { type, state, cleared }: the names of the enums when the client
-- has them (type "Encounter", state "Inactive"), the numbers otherwise, and `cleared`, true once the restriction is
-- over. The state first goes Activating, which is the moment to snapshot before the restriction starts.
-- (unverified on Forever: the event and the enums are in the 70450 UI source and not yet seen firing)
function Client.restriction(kind, state)
  kind, state = plain(kind), plain(state)
  local typeName = enumName(member(Enum, "AddOnRestrictionType"), kind)
  local stateName = enumName(member(Enum, "AddOnRestrictionState"), state)
  local inactive = member(member(Enum, "AddOnRestrictionState"), "Inactive") or 0
  return { type = typeName or kind, state = stateName or state, cleared = state == inactive }
end

-- Frames, events, timers -----------------------------------------------------------------------------------------

-- A frame for events, or nil.
function Client.createFrame()
  local ok, frame = call("CreateFrame", CreateFrame, "Frame")
  if ok and frame ~= nil then return frame end
  return nil
end

-- Registers a frame for a game event. False when the client has no such event (it raises an error for one it does
-- not know) or the frame cannot.
function Client.registerEvent(frame, event)
  if type(frame) ~= "table" and type(frame) ~= "userdata" then return false end
  local fn = frame.RegisterEvent
  local ok = call("RegisterEvent " .. tostring(event), fn, frame, event)
  return ok
end

function Client.unregisterEvent(frame, event)
  if type(frame) ~= "table" and type(frame) ~= "userdata" then return false end
  local ok = call("UnregisterEvent " .. tostring(event), frame.UnregisterEvent, frame, event)
  return ok
end

-- Sets what runs on every event the frame is registered for: fn(frame, event, ...).
function Client.setEventHandler(frame, fn)
  if type(frame) ~= "table" and type(frame) ~= "userdata" then return false end
  local ok = call("SetScript", frame.SetScript, frame, "OnEvent", fn)
  return ok
end

-- Runs fn after `seconds`. False when the client has no timers.
function Client.after(seconds, fn)
  local ok = call("C_Timer.After", member(C_Timer, "After"), seconds, fn)
  return ok
end

-- Slash commands ---------------------------------------------------------------------------------------------------

-- Makes `commands` (a list like { "/gg", "/guildgolem" }) run handler(rest) with the text after the command. `key` names
-- the entry in SlashCmdList, so it must be one nobody else uses. False when the client has no slash commands.
function Client.registerSlash(key, commands, handler)
  if type(SlashCmdList) ~= "table" or type(handler) ~= "function" then return false end
  local ok = pcall(function()
    for i, command in ipairs(commands) do _G["SLASH_" .. key .. i] = command end
    SlashCmdList[key] = handler
  end)
  return ok
end

-- The window -----------------------------------------------------------------------------------------------------

-- The addon's one window, built from a description so that UI.lua names no frame, template or font. `spec`:
--   name        the window's global name; its parts are named after it (<name>Paste, <name>Copy, <name>Button<key>)
--   title       its title bar
--   width, height
--   pasteLabel, copyLabel   what is written over the two text boxes
--   buttons     a list of { key, label, width }, laid out in a row under the copy box
-- Returns a handle, or nil and a message when the client would not build it:
--   w.show(), w.hide(), w.toggle(), w.isShown()
--   w.setStatus(text)        the line under the title
--   w.setNote(text)          the line under the paste box (what was read, or why not)
--   w.setCopyLabel(text)
--   w.setPaste(text), w.paste()   the paste box's text, set or read
--   w.setCopy(text)          fills the copy box, selects it all and focuses it, so Ctrl+C copies it. The box gives
--                            back what it held if the player types in it
--   w.setEnabled(key, flag), w.setButtonText(key, text)
--   w.onPaste(fn)            fn(text) runs half a second after the player stops changing the paste box
--   w.onClick(key, fn)       fn() runs when the button is pressed
-- (unverified on Forever: the templates are retail's; BasicFrameTemplateWithInset, UIPanelScrollFrameTemplate and
-- UIPanelButtonTemplate are what the probe's window uses. Each falls back to a plain frame if the client lacks it.
-- Whether an edit box takes and gives 65,536 characters is the launch-day probe's paste-box test.)

local function newFrame(kind, name, parent, template)
  if template then
    local ok, frame = pcall(CreateFrame, kind, name, parent, template)
    if ok and frame then return frame, true end
  end
  return CreateFrame(kind, name, parent), false
end

local function backdrop(frame)
  local texture = frame:CreateTexture(nil, "BACKGROUND")
  texture:SetAllPoints()
  texture:SetColorTexture(0, 0, 0, 0.9)
end

local function label(parent, x, y, width, text, font)
  local line = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  line:SetPoint("TOPLEFT", x, y)
  line:SetWidth(width)
  line:SetJustifyH("LEFT")
  line:SetText(text or "")
  return line
end

-- A multi-line edit box in a scroll frame, `height` tall. Returns the edit box.
local function textBox(parent, name, x, y, width, height)
  local scroll = newFrame("ScrollFrame", name .. "Scroll", parent, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", x, y)
  scroll:SetSize(width - 24, height)
  local edit = CreateFrame("EditBox", name, scroll)
  edit:SetMultiLine(true)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(width - 28)
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(0)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  scroll:SetScrollChild(edit)
  return edit
end

local function buildWindow(spec)
  local width, height = spec.width or 580, spec.height or 470
  local frame = newFrame("Frame", spec.name, UIParent, "BasicFrameTemplateWithInset")
  if not frame.TitleText then backdrop(frame) end
  frame:SetSize(width, height)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  if frame.TitleText then frame.TitleText:SetText(spec.title or "") end
  -- Escape closes it.
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, spec.name) end

  local inner = width - 28
  local status = label(frame, 14, -32, inner, "")
  label(frame, 14, -62, inner, spec.pasteLabel or "", "GameFontNormal")
  local paste = textBox(frame, spec.name .. "Paste", 14, -82, inner, 80)
  local note = label(frame, 14, -170, inner, "")
  local copyLabel = label(frame, 14, -214, inner, spec.copyLabel or "", "GameFontNormal")
  local copy = textBox(frame, spec.name .. "Copy", 14, -234, inner, 80)

  local buttons, clicks = {}, {}
  local x = 14
  for _, def in ipairs(spec.buttons or {}) do
    local button = newFrame("Button", spec.name .. "Button" .. def.key, frame, "UIPanelButtonTemplate")
    if not button.GetFontString then backdrop(button) end
    button:SetSize(def.width or 90, 22)
    button:SetPoint("TOPLEFT", x, -340)
    button:SetText(def.label or def.key)
    button:SetScript("OnClick", function()
      local fn = clicks[def.key]
      if fn then fn() end
    end)
    buttons[def.key] = button
    x = x + (def.width or 90) + 6
  end

  -- What the copy box holds is read-only: a keystroke puts it back, and focus selects it all.
  local shown = ""
  copy:SetScript("OnTextChanged", function(self, byPlayer)
    if byPlayer and self:GetText() ~= shown then
      self:SetText(shown)
      self:HighlightText()
    end
  end)
  copy:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

  -- The paste box's callback waits for the paste to settle, and only the last change counts.
  local onPaste
  local changes = 0
  paste:SetScript("OnTextChanged", function(self, byPlayer)
    if not byPlayer or not onPaste then return end
    changes = changes + 1
    local mine = changes
    Client.after(0.5, function()
      if mine == changes and onPaste then onPaste(self:GetText()) end
    end)
  end)

  local w = {}
  function w.show() frame:Show() end
  function w.hide() frame:Hide() end
  function w.isShown() return frame:IsShown() == true end
  function w.toggle() if frame:IsShown() then frame:Hide() else frame:Show() end end
  function w.setStatus(text) status:SetText(text or "") end
  function w.setNote(text) note:SetText(text or "") end
  function w.setCopyLabel(text) copyLabel:SetText(text or "") end
  function w.setPaste(text) paste:SetText(text or "") end
  function w.paste() return paste:GetText() end
  function w.setCopy(text)
    shown = text or ""
    copy:SetText(shown)
    if shown ~= "" then
      copy:SetFocus()
      copy:HighlightText()
    end
  end
  function w.setEnabled(key, flag)
    local button = buttons[key]
    if not button then return end
    if flag then button:Enable() else button:Disable() end
  end
  function w.setButtonText(key, text)
    if buttons[key] then buttons[key]:SetText(text) end
  end
  function w.onPaste(fn) onPaste = fn end
  function w.onClick(key, fn) clicks[key] = fn end
  frame:Hide()
  return w
end

function Client.window(spec)
  if not isFunction(CreateFrame) or type(UIParent) ~= "table" and type(UIParent) ~= "userdata" then
    return nil, "this client has no frames to build a window from"
  end
  local ok, result = pcall(buildWindow, spec)
  if not ok then
    report("window", result)
    return nil, "the client would not build the window"
  end
  return result
end
