-- Guild Golem Probe (milestone M0, docs/PLAN.md) answers, on WoW Forever's own client, the questions the Guild Golem
-- addon is planned around (docs/RESEARCH.md, "To test in game"). It reads, records what it saw in its saved variables
-- (GuildGolemProbeDB), and shows everything as text to copy with /ggprobe. Nothing it does stays changed. The combat
-- logging switch and one setting are flipped and put back. Every check runs in a protected call, so one the client
-- refuses is recorded as the answer and the rest still run. A value the client keeps secret is recorded as <secret>
-- without being touched.
--
-- Version 0.2 adds the launch-day tests, which live in Launch.lua and share this file's helpers through the table the
-- game passes to every file of an addon (ns below). The saved variables carry probeVersion and schema, so two runs can
-- be compared (tools/probe-diff.mjs). Their shape:
--   probeVersion, schema   the probe's version and the shape's number (2 from 0.2.0)
--   run                    the client's version, build and interface, and when this run began
--   answers[section][key]  { text, at, where }, as in 0.1
--   log                    the last answers in order (not compared)
--   counters               how many times each repeated event has been seen, so a wipe and a kill both keep a key
--   who                    every character, guild and realm name the probe saw, so the diff tool can replace them

local ADDON, ns = ...
ns = ns or {}
local PREFIX = "GGProbe"
local VERSION = "0.2.0"
local SCHEMA = 2
local LOG_MOST = 300
local TEXT_MOST = 700

local DB
local frame = CreateFrame("Frame")
local handlers = {}

-- Values ----------------------------------------------------------------------------------------------------------

local function isSecret(v)
  if type(issecretvalue) ~= "function" then return false end
  local ok, secret = pcall(issecretvalue, v)
  return ok and secret == true
end

local function pack(...)
  return { n = select("#", ...), ... }
end

-- Text for any value, shallow, safe: a secret is never compared, joined or turned into a string.
local function describe(v, depth, most)
  depth = depth or 0
  most = most or 3
  if isSecret(v) then return "<secret>" end
  local t = type(v)
  if t == "nil" then return "nil" end
  if t == "string" then return string.format("%q", v) end
  if t == "number" or t == "boolean" then return tostring(v) end
  if t ~= "table" then return "<" .. t .. ">" end
  if depth >= most then return "{...}" end
  local parts = {}
  if type(v.n) == "number" and v.n >= 0 and v.n < 64 then
    for i = 1, v.n do parts[#parts + 1] = describe(v[i], depth + 1, most) end
    return "(" .. table.concat(parts, ", ") .. ")"
  end
  -- Keys in a fixed order (numbers first), so the same table gives the same text in every run.
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  pcall(table.sort, keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta == tb and (ta == "number" or ta == "string") then return a < b end
    if ta ~= tb then return ta < tb end
    return tostring(a) < tostring(b)
  end)
  for count, k in ipairs(keys) do
    if count > 30 then
      parts[#parts + 1] = "..."
      break
    end
    parts[#parts + 1] = describe(k, depth + 1, most) .. "=" .. describe(v[k], depth + 1, most)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function now()
  if type(GetServerTime) == "function" then
    local ok, t = pcall(GetServerTime)
    if ok and type(t) == "number" then return t end
  end
  return time()
end

-- Where the player is, for every answer: some answers change inside raid zones.
local function where()
  local ok, inInstance, kind = pcall(IsInInstance)
  local zone = GetRealZoneText and GetRealZoneText() or "?"
  if isSecret(zone) then zone = "<secret>" end
  local combat = InCombatLockdown and InCombatLockdown() or false
  return string.format("%s|%s%s", tostring(zone), ok and tostring(kind) or "?", combat and "|combat" or "")
end

-- Recording -------------------------------------------------------------------------------------------------------

-- most is how deep a table is described, limit how many characters of text are kept (700 unless a payload needs more).
local function record(section, key, value, most, limit)
  if not DB then return end
  limit = limit or TEXT_MOST
  local text = type(value) == "string" and value or describe(value, 0, most)
  if #text > limit then text = text:sub(1, limit) .. "..." end
  DB.answers[section] = DB.answers[section] or {}
  DB.answers[section][key] = { text = text, at = now(), where = where() }
  table.insert(DB.log, { at = now(), section = section, key = key, text = #text > 200 and (text:sub(1, 200) .. "...") or text })
  while #DB.log > LOG_MOST do table.remove(DB.log, 1) end
end

-- How many times something repeated has happened in this saved file, for keys such as "ENCOUNTER_START #2".
local function nextN(name)
  if not DB then return 1 end
  DB.counters = DB.counters or {}
  DB.counters[name] = (DB.counters[name] or 0) + 1
  return DB.counters[name]
end

-- Every name that is a person, a guild or a realm goes in DB.who, so the diff tool knows what to replace before
-- anything is shared. A name arrives as "First Surname" or "First Surname-Realm"; each part is kept as well.
local function note(kind, value)
  if not DB or type(value) ~= "string" or isSecret(value) or value == "" then return end
  DB.who = DB.who or {}
  DB.who[kind] = DB.who[kind] or {}
  DB.who[kind][value] = true
end

local function noteName(value)
  note("names", value)
  if type(value) == "string" and not isSecret(value) then
    local name, realm = value:match("^(.-)%-(.+)$")
    if name then
      note("names", name)
      note("realms", realm)
    end
  end
end

-- A unit's name and the second value UnitName gives (the surname in Forever), and both together.
local function noteUnit(unit)
  local ok, name, second = pcall(UnitName, unit)
  if not ok then return end
  noteName(name)
  if type(second) == "string" and not isSecret(second) and second ~= "" then
    noteName(second)
    if type(name) == "string" and not isSecret(name) and not isSecret(second) then noteName(name .. " " .. second) end
  end
end

-- Names inside a table the client returned (loot history, for one): any field called ...name, except items, bosses and classes.
local function harvestNames(value, depth)
  depth = depth or 0
  if type(value) ~= "table" or depth > 6 or isSecret(value) then return end
  for k, v in pairs(value) do
    if type(v) == "table" then
      harvestNames(v, depth + 1)
    elseif type(k) == "string" and type(v) == "string" then
      local lower = k:lower()
      if lower:find("name", 1, true) and not (lower:find("item", 1, true) or lower:find("encounter", 1, true) or lower:find("class", 1, true) or lower:find("boss", 1, true) or lower:find("instance", 1, true) or lower:find("zone", 1, true)) then
        noteName(v)
      end
    end
  end
end

local function registerSelf()
  noteUnit("player")
  local ok, name, second = pcall(UnitName, "player")
  if ok and type(name) == "string" and not isSecret(name) then
    DB.who = DB.who or {}
    DB.who.self = type(second) == "string" and not isSecret(second) and second ~= "" and (name .. " " .. second) or name
  end
  if type(GetRealmName) == "function" then
    local got, realm = pcall(GetRealmName)
    if got then note("realms", realm) end
  end
  if type(GetNormalizedRealmName) == "function" then
    local got, realm = pcall(GetNormalizedRealmName)
    if got then note("realms", realm) end
  end
  if type(GetGuildInfo) == "function" then
    local got, guild, _, _, subRealm = pcall(GetGuildInfo, "player")
    if got then
      note("guilds", guild)
      note("realms", subRealm)
    end
  end
end

-- Runs a check; an error becomes its answer.
local function try(section, key, fn, ...)
  local result = pack(pcall(fn, ...))
  if result[1] then
    local values = pack(select(2, unpack(result, 1, result.n)))
    record(section, key, values.n <= 1 and values[1] or values)
    return values[1]
  end
  record(section, key, "error: " .. tostring(result[2]))
  return nil
end

-- A global by dotted name ("C_LootHistory.GetAllEncounterInfos"), or nil.
local function lookup(name)
  local value = _G
  for part in name:gmatch("[^%.]+") do
    if type(value) ~= "table" then return nil end
    value = value[part]
  end
  return value
end

local function after(seconds, fn)
  if C_Timer and C_Timer.After then
    C_Timer.After(seconds, function() pcall(fn) end)
  else
    pcall(fn)
  end
end

local function say(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cffd4a017Guild Golem Probe:|r " .. text)
end

-- The name of a value in an Enum table ("Enum.SendAddonMessageResult", 3 gives "AddonMessageThrottle"), or nil.
local function enumName(enumPath, value)
  local enum = lookup(enumPath)
  if type(enum) ~= "table" or isSecret(value) then return nil end
  for name, number in pairs(enum) do
    if number == value then return tostring(name) end
  end
  return nil
end

-- The state of every addon restriction type (combat, encounter, map, chat...), as far as this client has the API.
local function restrictionStates()
  local get = lookup("C_RestrictedActions.GetAddOnRestrictionState")
  local types = lookup("Enum.AddOnRestrictionType")
  if type(get) ~= "function" or type(types) ~= "table" then return "no API" end
  local out = {}
  for name, id in pairs(types) do
    local ok, state = pcall(get, id)
    out[#out + 1] = tostring(name) .. "=" .. (ok and (enumName("Enum.AddOnRestrictionState", state) or describe(state)) or "error")
  end
  table.sort(out)
  return table.concat(out, ", ")
end

-- Checks ----------------------------------------------------------------------------------------------------------

local API = {
  "C_AddOns.GetAddOnMetadata", "GetServerTime", "issecretvalue", "canaccessvalue", "C_Secrets.ShouldAurasBeSecret",
  "C_ChatInfo.InChatMessagingLockdown", "C_ChatInfo.SendAddonMessage", "C_ChatInfo.RegisterAddonMessagePrefix",
  "C_LootHistory.GetAllEncounterInfos", "C_LootHistory.GetSortedDropsForEncounter", "C_LootHistory.GetSortedInfoForDrop",
  "C_PartyInfo.GetLootMethod", "C_PartyInfo.GetAvailableLootMethods", "C_PartyInfo.InviteUnit", "GiveMasterLoot",
  "GetMasterLootCandidate", "SetRaidSubgroup", "SwapRaidSubgroup", "GetRaidRosterInfo", "C_GuildBank.IsGuildBankEnabled",
  "QueryGuildBankLog", "GetGuildBankTransaction", "GetNumGuildBankTransactions", "GetGuildBankMoneyTransaction",
  "GetGuildRosterInfo", "GetGuildRosterLastOnline", "C_GuildInfo.GuildRoster", "CanViewOfficerNote", "C_Club.GetGuildClubId",
  "NotifyInspect", "C_Traits.HasValidInspectData", "C_Traits.GenerateInspectImportString", "C_Traits.GenerateImportString",
  "C_ClassTalents.GetActiveConfigID", "C_UnitAuras.GetAuraDataByIndex", "GetSavedInstanceInfo", "C_RaidLocks.IsEncounterComplete",
  "C_QuestLog.IsQuestFlaggedCompleted", "GetProfessions", "GetProfessionInfo", "C_TradeSkillUI.GetAllRecipeIDs",
  "GetTradePlayerItemLink", "GetTradeTargetItemLink", "ReloadUI", "LoggingCombat", "C_CVar.GetCVar", "C_CVar.SetCVar",
  "debugprofilestop", "C_RestrictedActions.GetAddOnRestrictionState", "C_ChatInfo.IsAddonMessagePrefixRegistered",
  "GetLootThreshold", "IsEncounterInProgress",
}

local function checkClient()
  try("client", "build (version, build, date, interface)", GetBuildInfo)
  record("client", "WOW_PROJECT_ID", WOW_PROJECT_ID)
  record("client", "LE_EXPANSION_LEVEL_CURRENT", LE_EXPANSION_LEVEL_CURRENT)
  record("client", "locale", GetLocale and GetLocale() or nil)
  local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if meta then try("client", "TOC the game chose", meta, ADDON, "X-Probe-TOC") end
  local missing = {}
  for _, name in ipairs(API) do
    if type(lookup(name)) ~= "function" then missing[#missing + 1] = name end
  end
  record("client", "functions missing", #missing == 0 and "none" or table.concat(missing, ", "))
  record("time", "server time", now())
  record("time", "this PC's time", time())
  record("time", "PC minus server, seconds", time() - now())
  try("player", "UnitName", UnitName, "player")
  try("player", "UnitFullName", UnitFullName, "player")
  try("player", "UnitGUID", UnitGUID, "player")
  try("player", "realm", GetRealmName)
  try("player", "guild (name, rank, rank index)", GetGuildInfo, "player")
  registerSelf()
end

local function checkData()
  record("reload test", "Data.lua says", GuildGolemProbeData and GuildGolemProbeData.written or "nothing (Data.lua didn't load)")
end

local function lockdown()
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    return ok and describe(locked) or "error"
  end
  return "no API"
end

local sampledZones = {}

local function groupUnit(i)
  if IsInRaid() then return "raid" .. i end
  return i == 1 and "player" or ("party" .. (i - 1))
end

local function sampleGroup(reason)
  local zone = where()
  record("zone", zone, { instance = pack(pcall(GetInstanceInfo)), chatLockdown = lockdown() })
  if not IsInGroup() then return end
  local n = GetNumGroupMembers()
  local rows = {}
  for i = 1, n do
    local unit = groupUnit(i)
    noteUnit(unit)
    if i <= 4 then
      local row = { guid = UnitGUID(unit), name = pack(UnitName(unit)) }
      if IsInRaid() then row.roster = pack(GetRaidRosterInfo(i)) end
      rows[#rows + 1] = row
    end
    if IsInRaid() then
      local ok, rosterName = pcall(GetRaidRosterInfo, i)
      if ok then noteName(rosterName) end
    end
  end
  record("group", reason .. " @ " .. zone, { size = n, raid = IsInRaid(), members = rows }, 4)
  ns.readLootMethod()
end

local function sampleGuild(reason)
  if not IsInGuild() then return end
  local n = GetNumGuildMembers()
  local rows = {}
  for i = 1, math.min(n, 3) do
    local info = pack(GetGuildRosterInfo(i))
    noteName(info[1])
    rows[#rows + 1] = { info = info, lastOnline = pack(GetGuildRosterLastOnline(i)) }
  end
  record("guild roster", reason .. " @ " .. where(), { members = n, sample = rows, officerNotes = CanViewOfficerNote and CanViewOfficerNote() }, 4)
end

local function checkGuild()
  if C_GuildBank and C_GuildBank.IsGuildBankEnabled then try("guild bank", "enabled", C_GuildBank.IsGuildBankEnabled) end
  if IsInGuild() then
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
  end
end

local QUESTS = { [7848] = "Molten Core attunement", [7761] = "Blackwing Lair attunement", [6502] = "Onyxia key (Alliance)", [6602] = "Onyxia key (Horde)" }

local function checkCharacter()
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
    for id, label in pairs(QUESTS) do try("quests", label .. " (" .. id .. ")", C_QuestLog.IsQuestFlaggedCompleted, id) end
  end
  local profs = pack(pcall(GetProfessions))
  record("professions", "indexes", profs)
  if profs[1] then
    for i = 2, profs.n do
      if profs[i] then try("professions", "profession " .. (i - 1), GetProfessionInfo, profs[i]) end
    end
  end
  if C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GenerateImportString then
    local ok, config = pcall(C_ClassTalents.GetActiveConfigID)
    record("talents", "own config id", ok and config or "error")
    if ok and config then
      local made, text = pcall(C_Traits.GenerateImportString, config)
      record("talents", "own import string", made and type(text) == "string" and (#text .. " characters: " .. text:sub(1, 24) .. "...") or describe(text))
    end
  end
end

-- Addon messages -----------------------------------------------------------------------------------------------------

local function channel()
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
  if IsInGuild() then return "GUILD" end
  return nil
end

local function send(text, chatType, target)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return "no API" end
  if not chatType then return "not in a group or guild" end
  return describe(pack(pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, chatType, target)))
end

local replies = 0

-- Loot ---------------------------------------------------------------------------------------------------------------

local historyPending = false

-- The loot method, who the master looter is, and what the group offers, keyed by the kind of group so a 5-man and a
-- raid each keep their own answer.
local function readLootMethod()
  local kind = IsInRaid() and "raid" or (IsInGroup() and "party" or "solo")
  local get = lookup("C_PartyInfo.GetLootMethod")
  local source = "C_PartyInfo.GetLootMethod"
  if type(get) ~= "function" then
    get = lookup("GetLootMethod")
    source = "GetLootMethod"
  end
  if type(get) ~= "function" then
    record("loot", "method in a " .. kind .. " group", "missing: neither C_PartyInfo.GetLootMethod nor GetLootMethod")
    return
  end
  local got = pack(pcall(get))
  local out = { source = source, raw = got }
  if got[1] then
    out.method = enumName("Enum.LootMethod", got[2]) or describe(got[2])
    -- Retail returns the master looter as a party number (0 is you) and a raid number.
    local unit
    if type(got[3]) == "number" and not isSecret(got[3]) then
      unit = got[3] == 0 and "player" or ("party" .. got[3])
    elseif type(got[4]) == "number" and not isSecret(got[4]) then
      unit = "raid" .. got[4]
    end
    if unit then
      noteUnit(unit)
      local ok, name, second = pcall(UnitName, unit)
      out.masterLooter = { unit = unit, name = ok and name or "error", second = ok and second or nil, guid = select(2, pcall(UnitGUID, unit)) }
    end
  end
  if type(GetLootThreshold) == "function" then out.threshold = pack(pcall(GetLootThreshold)) end
  local methods = lookup("C_PartyInfo.GetAvailableLootMethods")
  if type(methods) == "function" then out.available = pack(pcall(methods)) end
  record("loot", "method in a " .. kind .. " group @ " .. where(), out, 4, 1500)
  -- 0.1 kept these two under other keys; they stay for runs that are compared with it.
  try("loot", "method (method, master looter party, raid)", get)
  if type(methods) == "function" then try("loot", "methods available", methods) end
end
ns.readLootMethod = readLootMethod

-- Loot history, whatever shape this client has: the encounter and drop calls Retail has, and the older item and
-- player calls. Each is checked before it is called.
local function readLootHistory()
  historyPending = false
  local H = C_LootHistory
  if type(H) ~= "table" then
    record("loot history", "api", "missing: C_LootHistory is " .. type(H))
    return
  end
  local getAll = H.GetAllEncounterInfos
  if type(getAll) == "function" then
    local ok, infos = pcall(getAll)
    record("loot history", "encounters", ok and infos or ("error: " .. tostring(infos)), 3, 2500)
    if ok then harvestNames(infos) end
    if ok and type(infos) == "table" then
      -- The newest three encounters; the list is oldest first.
      for i = math.max(1, #infos - 2), #infos do
        local info = infos[i]
        local id = type(info) == "table" and info.encounterID
        if id then
          if type(H.GetInfoForEncounter) == "function" then
            local got, detail = pcall(H.GetInfoForEncounter, id)
            record("loot history", "info of encounter " .. tostring(id), got and detail or ("error: " .. tostring(detail)), 4, 2000)
            if got then harvestNames(detail) end
          end
          if type(H.GetSortedDropsForEncounter) == "function" then
            local got, drops = pcall(H.GetSortedDropsForEncounter, id)
            record("loot history", "drops of encounter " .. tostring(id), got and drops or ("error: " .. tostring(drops)), 5, 3500)
            if got then harvestNames(drops) end
            if got and type(drops) == "table" and type(H.GetSortedInfoForDrop) == "function" then
              for d = 1, math.min(#drops, 4) do
                local drop = drops[d]
                local listID = type(drop) == "table" and drop.lootListID or nil
                if listID then
                  local fine, dropInfo = pcall(H.GetSortedInfoForDrop, id, listID)
                  record("loot history", "drop " .. tostring(listID) .. " of encounter " .. tostring(id), fine and dropInfo or ("error: " .. tostring(dropInfo)), 6, 3500)
                  if fine then harvestNames(dropInfo) end
                end
              end
            end
          end
        end
      end
    end
  else
    record("loot history", "encounters", "missing: C_LootHistory.GetAllEncounterInfos")
  end
  if type(H.GetNumItems) == "function" then
    local ok, count = pcall(H.GetNumItems)
    local out = { count = ok and count or ("error: " .. tostring(count)) }
    if ok and type(count) == "number" and type(H.GetItem) == "function" then
      for item = 1, math.min(count, 4) do
        local entry = pack(pcall(H.GetItem, item))
        out["item " .. item] = entry
        local players = type(entry[4]) == "number" and entry[4] or 0
        if type(H.GetPlayerInfo) == "function" then
          for p = 1, math.min(players, 6) do
            local info = pack(pcall(H.GetPlayerInfo, item, p))
            noteName(info[2])
            out["item " .. item .. " player " .. p] = info
          end
        end
      end
    end
    record("loot history", "older item calls (GetNumItems, GetItem, GetPlayerInfo)", out, 4, 3500)
  end
end
ns.readLootHistory = readLootHistory

local function readBank()
  if not GetNumGuildBankTabs then return end
  local tabs = GetNumGuildBankTabs()
  local out = { tabs = tabs, enabled = C_GuildBank and C_GuildBank.IsGuildBankEnabled and pack(pcall(C_GuildBank.IsGuildBankEnabled)) }
  for tab = 1, math.min(tabs, 3) do
    local n = GetNumGuildBankTransactions(tab)
    out["tab " .. tab .. " lines"] = n
    if n and n > 0 then out["tab " .. tab .. " newest"] = pack(GetGuildBankTransaction(tab, n)) end
  end
  if GetNumGuildBankMoneyTransactions then
    local m = GetNumGuildBankMoneyTransactions()
    out["money lines"] = m
    if m and m > 0 then out["money newest"] = pack(GetGuildBankMoneyTransaction(m)) end
  end
  record("guild bank", "log @ " .. where(), out, 4)
end

local function queryBank()
  if not (GetNumGuildBankTabs and QueryGuildBankLog) then return end
  for tab = 1, GetNumGuildBankTabs() do pcall(QueryGuildBankLog, tab) end
  if MAX_GUILDBANK_TABS then pcall(QueryGuildBankLog, MAX_GUILDBANK_TABS + 1) end
  after(2, readBank)
end

-- Inspect, auras, lockouts ----------------------------------------------------------------------------------------------

local inspecting

local function inspectTarget()
  if not UnitIsPlayer("target") then return say("target a player in range first.") end
  if CanInspect and not CanInspect("target") then return say("the game says you can't inspect that target now.") end
  inspecting = UnitGUID("target")
  try("inspect", "asked @ " .. where(), NotifyInspect, "target")
end

local function readInspect(guid)
  if not inspecting or guid ~= inspecting then return end
  inspecting = nil
  local slots, links = 0, {}
  for slot = 1, 19 do
    local link = GetInventoryItemLink("target", slot)
    if link and not isSecret(link) then
      slots = slots + 1
      if slot == 1 or slot == 5 or slot == 16 then links["slot " .. slot] = (link:match("|H(item:[^|]+)|h")) or link end
    end
  end
  local talents = "no API"
  if C_Traits and C_Traits.GenerateInspectImportString then
    local valid = C_Traits.HasValidInspectData and pack(pcall(C_Traits.HasValidInspectData)) or "no API"
    local ok, text = pcall(C_Traits.GenerateInspectImportString, "target")
    talents = { valid = valid, string = ok and type(text) == "string" and (#text .. " characters") or describe(text) }
  end
  record("inspect", "read @ " .. where(), { slotsWithItems = slots, items = links, talents = talents }, 4)
  if ClearInspectPlayer then pcall(ClearInspectPlayer) end
end

local function checkAuras()
  local units = { "player" }
  if IsInRaid() then
    for i = 1, math.min(GetNumGroupMembers(), 8) do units[#units + 1] = "raid" .. i end
  end
  local out = {}
  if C_Secrets and C_Secrets.ShouldAurasBeSecret then out.shouldBeSecret = pack(pcall(C_Secrets.ShouldAurasBeSecret)) end
  local getAura = lookup("C_UnitAuras.GetAuraDataByIndex")
  if not getAura then return record("auras", "buffs", "no API") end
  for _, unit in ipairs(units) do
    local total, secret = 0, 0
    for i = 1, 40 do
      local ok, aura = pcall(getAura, unit, i, "HELPFUL")
      if not ok or not aura then break end
      total = total + 1
      if isSecret(aura) or isSecret(aura.spellId) or isSecret(aura.name) then secret = secret + 1 end
    end
    out[unit] = total .. " buffs, " .. secret .. " secret"
  end
  record("auras", "buffs @ " .. where(), out)
end

local function readLockouts()
  if not GetNumSavedInstances then return end
  local n = GetNumSavedInstances()
  local rows = {}
  for i = 1, math.min(n, 4) do rows[#rows + 1] = pack(GetSavedInstanceInfo(i)) end
  record("lockouts", "saved", { count = n, sample = rows }, 4)
end

-- The window -------------------------------------------------------------------------------------------------------

local window

local function report()
  local lines = {
    "Guild Golem Probe " .. VERSION .. " (saved variables shape " .. SCHEMA .. "), made " .. date("%Y-%m-%d %H:%M") .. " (" .. where() .. ")",
    "Client " .. tostring(DB.run and DB.run.clientVersion) .. ", build " .. tostring(DB.run and DB.run.build) .. ", interface " .. tostring(DB.run and DB.run.interface) .. ".",
    "Copy all of this (Ctrl+A, then Ctrl+C) and send it to the site's owner.",
    "",
  }
  local sections = {}
  for section in pairs(DB.answers) do sections[#sections + 1] = section end
  table.sort(sections)
  for _, section in ipairs(sections) do
    lines[#lines + 1] = "[" .. section .. "]"
    local keys = {}
    for key in pairs(DB.answers[section]) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
      local a = DB.answers[section][key]
      lines[#lines + 1] = key .. " = " .. a.text .. "  (" .. date("%H:%M:%S", a.at) .. ", " .. a.where .. ")"
    end
    lines[#lines + 1] = ""
  end
  -- An edit box reads "|" as the start of a colour or a link: doubled, it shows as itself.
  return (table.concat(lines, "\n"):gsub("|", "||"))
end

-- A movable window; the game's own frame template when it has one, else a plain dark one.
local function newWindow(name, width, height, title)
  local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "BasicFrameTemplateWithInset")
  if not ok or not f then
    f = CreateFrame("Frame", name, UIParent)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.9)
  end
  f:SetSize(width, height)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.TitleText then f.TitleText:SetText(title) end
  tinsert(UISpecialFrames, name)
  return f
end

-- A multiline edit box inside a scroll frame. editWidth is the text's width. Returns the edit box and its scroll frame.
local function newTextBox(parent, scrollName, editWidth)
  local scroll = CreateFrame("ScrollFrame", scrollName, parent, "UIPanelScrollFrameTemplate")
  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(editWidth)
  edit:SetAutoFocus(false)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  scroll:SetScrollChild(edit)
  return edit, scroll
end
ns.newWindow, ns.newTextBox = newWindow, newTextBox

local function show()
  if not window then
    local f = newWindow("GuildGolemProbeWindow", 720, 480, "Guild Golem Probe: Ctrl+A, then Ctrl+C to copy")
    local edit, scroll = newTextBox(f, "GuildGolemProbeScroll", 660)
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    f.edit = edit
    window = f
  end
  window.edit:SetText(report())
  window.edit:HighlightText()
  window.edit:SetFocus()
  window:Show()
end

-- Events -----------------------------------------------------------------------------------------------------------

handlers.ADDON_LOADED = function(name)
  if name ~= ADDON then return end
  GuildGolemProbeDB = GuildGolemProbeDB or {}
  DB = GuildGolemProbeDB
  local previousVersion = DB.probeVersion or (DB.answers and "0.1.0 or earlier" or nil)
  DB.answers = DB.answers or {}
  DB.log = DB.log or {}
  DB.counters = DB.counters or {}
  DB.who = DB.who or {}
  DB.probeVersion = VERSION
  DB.schema = SCHEMA
  DB.loads = (DB.loads or 0) + 1
  local clientVersion, build, built, interface = GetBuildInfo()
  DB.run = DB.run or { startedAt = now(), startedAtText = date("%Y-%m-%d %H:%M:%S"), probeVersion = VERSION }
  DB.run.clientVersion, DB.run.build, DB.run.buildDate, DB.run.interface = clientVersion, build, built, interface
  DB.run.lastLoadAt = now()
  if previousVersion and previousVersion ~= VERSION then DB.run.upgradedFrom = previousVersion end
  registerSelf()
  record("saved variables", "times loaded", DB.loads)
  record("saved variables", "last written at logout or reload", DB.lastSaved and date("%Y-%m-%d %H:%M:%S", DB.lastSaved) or "never yet")
  record("saved variables", "last unload was", DB.lastUnload or "never yet")
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then try("addon messages", "prefix registered", C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
  checkData()
end

handlers.PLAYER_ENTERING_WORLD = function(initial, reloading)
  record("saved variables", "this load", initial and "login" or (reloading and "reload" or "zoning"))
  if initial or reloading then
    after(3, checkClient)
    after(4, checkGuild)
    after(6, checkCharacter)
    after(8, function() say("loaded. Type /ggprobe for the results, /ggprobe help for the tests.") end)
  end
  after(5, function() sampleGroup("entering") end)
end

handlers.ZONE_CHANGED_NEW_AREA = function()
  after(3, function()
    local zone = where()
    if sampledZones[zone] then return end
    sampledZones[zone] = true
    sampleGroup("zone")
    sampleGuild("zone")
  end)
end

handlers.GROUP_ROSTER_UPDATE = function()
  local zone = where()
  if sampledZones["group " .. zone] then return end
  sampledZones["group " .. zone] = true
  after(2, function() sampleGroup("joined") end)
end

handlers.GUILD_ROSTER_UPDATE = function()
  local zone = where()
  if sampledZones["guild " .. zone] then return end
  sampledZones["guild " .. zone] = true
  after(1, function() sampleGuild("roster") end)
end

-- type and state arrive as numbers; the names come from the client's own Enum tables when it has them.
handlers.ADDON_RESTRICTION_STATE_CHANGED = function(...)
  local args = pack(...)
  local typeName = enumName("Enum.AddOnRestrictionType", args[1]) or describe(args[1])
  local stateName = enumName("Enum.AddOnRestrictionState", args[2]) or describe(args[2])
  local n = nextN("restriction " .. typeName .. " " .. stateName)
  record("restrictions", typeName .. " " .. stateName .. " #" .. n, { args = args, chatLockdown = lockdown(), states = restrictionStates(), clock = date("%H:%M:%S") }, 3, 1500)
end

-- The client says an addon was stopped from doing something. Only this probe's own are kept.
local function actionStopped(event)
  return function(...)
    local args = pack(...)
    if args[1] ~= ADDON then return end
    record("restrictions", event .. " #" .. nextN(event), args)
  end
end
handlers.ADDON_ACTION_FORBIDDEN = actionStopped("ADDON_ACTION_FORBIDDEN")
handlers.ADDON_ACTION_BLOCKED = actionStopped("ADDON_ACTION_BLOCKED")

-- A pull and a wipe or kill both keep their own key (#1, #2...), with every argument the event carries.
handlers.ENCOUNTER_START = function(...)
  local args = pack(...)
  local n = nextN("ENCOUNTER_START")
  record("encounters", "start " .. describe(args[2]) .. " #" .. n, {
    args = args, instance = pack(pcall(GetInstanceInfo)), groupSize = GetNumGroupMembers(),
    chatLockdown = lockdown(), restrictions = restrictionStates(), clock = date("%H:%M:%S"),
  }, 4, 2500)
  record("addon messages", "chat lockdown at a pull", lockdown())
  record("addon messages", "send during a pull", send("pull", channel()))
  if ns.burst and IsInGroup() then ns.burst(IsInRaid() and "RAID" or "PARTY", 12, "pull #" .. n) end
end

handlers.ENCOUNTER_END = function(...)
  local args = pack(...)
  local n = nextN("ENCOUNTER_END")
  local inProgress = "no API"
  if type(IsEncounterInProgress) == "function" then inProgress = describe(select(2, pcall(IsEncounterInProgress))) end
  record("encounters", "end " .. describe(args[2]) .. " #" .. n, {
    args = args, inProgress = inProgress, chatLockdown = lockdown(), restrictions = restrictionStates(), clock = date("%H:%M:%S"),
  }, 4, 2500)
  after(3, function()
    record("addon messages", "chat lockdown after a pull", lockdown())
    record("addon messages", "send after a pull", send("after", channel()))
    if ns.burst and IsInGroup() then ns.burst(IsInRaid() and "RAID" or "PARTY", 12, "after pull #" .. n) end
  end)
  after(6, readLootHistory)
end

handlers.CHAT_MSG_ADDON = function(prefix, text, chatType, sender, ...)
  if prefix ~= PREFIX then return end
  noteName(sender)
  -- Burst messages ("b:...") are counted by Launch.lua, not logged one by one.
  if type(text) == "string" and not isSecret(text) and text:sub(1, 2) == "b:" then return end
  record("addon messages", "received on " .. tostring(chatType) .. " @ " .. where(), pack(text, chatType, sender, ...))
  if type(text) == "string" and not isSecret(text) and text:sub(1, 4) == "ping" and replies < 10 and not isSecret(sender) and sender ~= UnitName("player") then
    replies = replies + 1
    record("addon messages", "whisper reply to " .. describe(sender), send("pong", "WHISPER", sender))
  end
end

handlers.CHAT_MSG_LOOT = function(text)
  record("loot", "loot chat line is secret @ " .. where(), isSecret(text))
  if not isSecret(text) then record("loot", "loot chat line sample", text) end
end

local systemSeen = {}
handlers.CHAT_MSG_SYSTEM = function(text)
  local key = where()
  if systemSeen[key] then return end
  systemSeen[key] = true
  record("chat", "system line (rolls) is secret @ " .. key, isSecret(text))
end

-- Arguments, in Retail: encounter id, item id, item link, quantity, player name, class.
handlers.ENCOUNTER_LOOT_RECEIVED = function(...)
  local args = pack(...)
  noteName(args[5])
  record("loot", "encounter loot received #" .. nextN("ENCOUNTER_LOOT_RECEIVED"), { args = args, clock = date("%H:%M:%S") }, 3, 1500)
end

handlers.PARTY_LOOT_METHOD_CHANGED = function()
  after(1, readLootMethod)
end

-- After a group roll ends, the history has the winner and every roll.
handlers.LOOT_ROLLS_COMPLETE = function(...)
  record("loot", "rolls complete #" .. nextN("LOOT_ROLLS_COMPLETE"), pack(...))
  if not historyPending then
    historyPending = true
    after(2, readLootHistory)
  end
end

handlers.LOOT_ITEM_ROLL_WON = function(...)
  record("loot", "your roll won #" .. nextN("LOOT_ITEM_ROLL_WON"), pack(...))
end

handlers.START_LOOT_ROLL = function(rollID, ...)
  record("loot", "roll started #" .. nextN("START_LOOT_ROLL"), { args = pack(rollID, ...), link = GetLootRollItemLink and GetLootRollItemLink(rollID) })
end

handlers.LOOT_HISTORY_UPDATE_ENCOUNTER = function()
  if historyPending then return end
  historyPending = true
  after(2, readLootHistory)
end
handlers.LOOT_HISTORY_UPDATE_DROP = handlers.LOOT_HISTORY_UPDATE_ENCOUNTER

handlers.LOOT_OPENED = function()
  local n = GetNumLootItems()
  local out = { items = n }
  for slot = 1, math.min(n, 4) do out["slot " .. slot] = GetLootSlotLink(slot) end
  if GetMasterLootCandidate and n > 0 then
    local names = {}
    for i = 1, 5 do
      local ok, name = pcall(GetMasterLootCandidate, 1, i)
      if not ok or not name then break end
      names[#names + 1] = name
    end
    out.masterLootCandidates = names
  end
  record("loot", "loot window #" .. nextN("LOOT_OPENED"), out)
end

handlers.TRADE_ACCEPT_UPDATE = function(mine, theirs)
  local out = { accepted = pack(mine, theirs), with = pack(UnitName("NPC")), giving = {}, getting = {} }
  for i = 1, 7 do
    if GetTradePlayerItemLink then out.giving[#out.giving + 1] = GetTradePlayerItemLink(i) end
    if GetTradeTargetItemLink then out.getting[#out.getting + 1] = GetTradeTargetItemLink(i) end
  end
  record("trades", "accept " .. date("%H:%M:%S"), out)
end

handlers.UI_INFO_MESSAGE = function(_, message)
  if ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE then record("trades", "completed " .. date("%H:%M:%S"), true) end
end

handlers.PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(kind)
  if Enum and Enum.PlayerInteractionType and kind == Enum.PlayerInteractionType.GuildBanker then queryBank() end
end
handlers.GUILDBANKFRAME_OPENED = queryBank

handlers.GUILDBANKLOG_UPDATE = function()
  after(1, readBank)
end

handlers.INSPECT_READY = function(guid)
  readInspect(guid)
end

handlers.UPDATE_INSTANCE_INFO = readLockouts

handlers.TRADE_SKILL_SHOW = function()
  if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
    after(1, function()
      local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
      record("professions", "recipes in the open profession", ok and type(ids) == "table" and #ids or describe(ids))
    end)
  end
end

handlers.ADDONS_UNLOADING = function(closing)
  if DB then DB.lastUnload = closing and "closing the game" or "logout or reload" end
end

handlers.PLAYER_LOGOUT = function()
  if DB then DB.lastSaved = now() end
end

frame:SetScript("OnEvent", function(_, event, ...)
  local handler = handlers[event]
  if not handler then return end
  local ok, err = pcall(handler, ...)
  if not ok then record("errors", event, tostring(err)) end
end)

-- Registers every event in a handlers table and remembers which ones this client has (Launch.lua uses this too).
local eventStatus = {}
local function register(owner, table_)
  for event in pairs(table_) do
    eventStatus[event] = pcall(owner.RegisterEvent, owner, event) and true or false
  end
end
register(frame, handlers)
ns.register = register

-- What Launch.lua (the launch-day tests) uses from this file.
ns.PREFIX, ns.VERSION = PREFIX, VERSION
ns.record, ns.try, ns.describe, ns.isSecret, ns.pack = record, try, describe, isSecret, pack
ns.lookup, ns.after, ns.say, ns.where, ns.now = lookup, after, say, where, now
ns.nextN, ns.noteName, ns.noteUnit, ns.harvestNames = nextN, noteName, noteUnit, harvestNames
ns.enumName, ns.restrictionStates, ns.lockdown, ns.registerSelf = enumName, restrictionStates, lockdown, registerSelf
ns.db = function() return DB end
ns.commands = {}   -- extra /ggprobe commands: ns.commands.name = function(rest) ... end
ns.help = {}       -- their lines for /ggprobe help
ns.onReset = {}    -- functions run by /ggprobe reset

-- The commands -----------------------------------------------------------------------------------------------------

local HELP = {
  "/ggprobe - the results, to copy",
  "/ggprobe ping - an addon message to your raid, party or guild (others running the probe answer)",
  "/ggprobe inspect - inspect your target (a raid member, out of combat)",
  "/ggprobe auras - which raid buffs the probe can read here",
  "/ggprobe lockouts - your raid lockouts",
  "/ggprobe bank - read the guild bank's log (with the bank open)",
  "/ggprobe invite Name Surname - invite someone by full name",
  "/ggprobe group <raid number> <group> - move a raid member to a group (leader or assistant)",
  "/ggprobe roster - read the raid and the guild roster here",
  "/ggprobe reset - forget everything recorded (copy the saved file first if you want to keep it)",
}

SLASH_GGPROBE1 = "/ggprobe"
SlashCmdList.GGPROBE = function(message)
  if not DB then return say("not ready yet: try again in a moment.") end
  local command, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
  command = (command or ""):lower()
  if command == "" then
    show()
  elseif command == "help" then
    for _, line in ipairs(HELP) do say(line) end
    for _, line in ipairs(ns.help) do say(line) end
  elseif command == "ping" then
    local result = send("ping " .. now(), channel())
    record("addon messages", "ping sent on " .. tostring(channel()) .. " @ " .. where(), result)
    say("ping sent: " .. result)
  elseif command == "inspect" then
    inspectTarget()
  elseif command == "auras" then
    checkAuras()
    say("buffs read; see /ggprobe.")
  elseif command == "lockouts" then
    if RequestRaidInfo then RequestRaidInfo() end
    say("asked the game for your lockouts; see /ggprobe in a moment.")
  elseif command == "bank" then
    queryBank()
    say("reading the bank's log; see /ggprobe in a moment.")
  elseif command == "invite" then
    if rest == "" then return say("who? /ggprobe invite Name Surname") end
    try("group control", "invite '" .. rest .. "' @ " .. where(), lookup("C_PartyInfo.InviteUnit"), rest)
    say("invite sent to " .. rest .. ": did it arrive?")
  elseif command == "group" then
    local index, group = rest:match("^(%d+)%s+(%d+)$")
    if not index then return say("/ggprobe group <raid number> <group>, for example /ggprobe group 3 2") end
    try("group control", "move raid " .. index .. " to group " .. group .. " @ " .. where(), SetRaidSubgroup, tonumber(index), tonumber(group))
    say("asked; did they move?")
  elseif command == "roster" then
    sampleGroup("asked")
    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    after(2, function() sampleGuild("asked") end)
    say("read; see /ggprobe.")
  elseif command == "reset" then
    DB.answers, DB.log, DB.counters, DB.who = {}, {}, {}, {}
    DB.run = { startedAt = now(), startedAtText = date("%Y-%m-%d %H:%M:%S"), probeVersion = VERSION }
    local clientVersion, build, built, interface = GetBuildInfo()
    DB.run.clientVersion, DB.run.build, DB.run.buildDate, DB.run.interface = clientVersion, build, built, interface
    sampledZones, systemSeen = {}, {}
    for _, fn in ipairs(ns.onReset) do pcall(fn) end
    checkData()
    registerSelf()
    say("forgotten. Log out or /reload to start over.")
  elseif ns.commands[command] then
    local ok, err = pcall(ns.commands[command], rest)
    if not ok then say("that failed: " .. tostring(err)) end
  else
    say("unknown command; /ggprobe help lists them.")
  end
end

-- Which events this client has, for every event the probe listens to. An event the client lacks (BOSS_KILL, say) is
-- recorded as missing, not left out.
after(10, function()
  local unknown, names = {}, {}
  for event, ok in pairs(eventStatus) do
    names[#names + 1] = event
    if not ok then unknown[#unknown + 1] = event end
  end
  table.sort(names)
  table.sort(unknown)
  for _, event in ipairs(names) do record("events", event, eventStatus[event] and "registered" or "missing") end
  if #unknown > 0 then record("client", "events this client doesn't know", table.concat(unknown, ", ")) end
end)
