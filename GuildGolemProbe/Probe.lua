-- Guild Golem Probe (milestone M0, docs/PLAN.md): answers, on WoW Forever's own client, the questions the
-- Guild Golem addon is planned around (docs/RESEARCH.md, "To test in game"). It changes nothing in the game: it
-- reads, records what it saw in its saved variables (GuildGolemProbeDB), and shows everything as text to copy with
-- /ggprobe. Every check runs in a protected call, so one the client refuses is recorded as the answer instead of
-- stopping the rest, and a value the client keeps secret is recorded as <secret> without being touched.

local ADDON = ...
local PREFIX = "GGProbe"
local VERSION = "0.1.0"
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
  local count = 0
  for k, val in pairs(v) do
    count = count + 1
    if count > 30 then
      parts[#parts + 1] = "..."
      break
    end
    parts[#parts + 1] = describe(k, depth + 1, most) .. "=" .. describe(val, depth + 1, most)
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

local function record(section, key, value, most)
  if not DB then return end
  local text = type(value) == "string" and value or describe(value, 0, most)
  if #text > TEXT_MOST then text = text:sub(1, TEXT_MOST) .. "..." end
  DB.answers[section] = DB.answers[section] or {}
  DB.answers[section][key] = { text = text, at = now(), where = where() }
  table.insert(DB.log, { at = now(), section = section, key = key, text = text })
  while #DB.log > LOG_MOST do table.remove(DB.log, 1) end
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
  "GetTradePlayerItemLink", "GetTradeTargetItemLink", "ReloadUI",
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
  for i = 1, math.min(n, 4) do
    local unit = groupUnit(i)
    local row = { guid = UnitGUID(unit), name = pack(UnitName(unit)) }
    if IsInRaid() then row.roster = pack(GetRaidRosterInfo(i)) end
    rows[#rows + 1] = row
  end
  record("group", reason .. " @ " .. zone, { size = n, raid = IsInRaid(), members = rows }, 4)
  try("loot", "method (method, master looter party, raid)", lookup("C_PartyInfo.GetLootMethod"))
  try("loot", "methods available", lookup("C_PartyInfo.GetAvailableLootMethods"))
end

local function sampleGuild(reason)
  if not IsInGuild() then return end
  local n = GetNumGuildMembers()
  local rows = {}
  for i = 1, math.min(n, 3) do
    rows[#rows + 1] = { info = pack(GetGuildRosterInfo(i)), lastOnline = pack(GetGuildRosterLastOnline(i)) }
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

local function readLootHistory()
  historyPending = false
  if not (C_LootHistory and C_LootHistory.GetAllEncounterInfos) then return end
  local ok, infos = pcall(C_LootHistory.GetAllEncounterInfos)
  record("loot history", "encounters", ok and infos or "error", 3)
  if not ok or type(infos) ~= "table" or #infos == 0 then return end
  local last = infos[#infos]
  local id = last and last.encounterID
  if id then
    local got, drops = pcall(C_LootHistory.GetSortedDropsForEncounter, id)
    record("loot history", "drops of encounter " .. tostring(id), got and drops or "error", 5)
  end
end

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
    "Guild Golem Probe " .. VERSION .. ", made " .. date("%Y-%m-%d %H:%M") .. " (" .. where() .. ")",
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

local function show()
  if not window then
    local ok, f = pcall(CreateFrame, "Frame", "GuildGolemProbeWindow", UIParent, "BasicFrameTemplateWithInset")
    if not ok or not f then
      f = CreateFrame("Frame", "GuildGolemProbeWindow", UIParent)
      local bg = f:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      bg:SetColorTexture(0, 0, 0, 0.9)
    end
    f:SetSize(720, 480)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.TitleText then f.TitleText:SetText("Guild Golem Probe: Ctrl+A, then Ctrl+C to copy") end
    local scroll = CreateFrame("ScrollFrame", "GuildGolemProbeScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(660)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(edit)
    f.edit = edit
    tinsert(UISpecialFrames, "GuildGolemProbeWindow")
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
  DB.answers = DB.answers or {}
  DB.log = DB.log or {}
  DB.loads = (DB.loads or 0) + 1
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

handlers.ADDON_RESTRICTION_STATE_CHANGED = function(...)
  record("restrictions", "changed " .. date("%H:%M:%S") .. " @ " .. where(), pack(...))
end

handlers.ENCOUNTER_START = function(...)
  local args = pack(...)
  record("encounters", "start " .. describe(args[2]), args)
  record("addon messages", "chat lockdown at a pull", lockdown())
  record("addon messages", "send during a pull", send("pull", channel()))
end

handlers.ENCOUNTER_END = function(...)
  local args = pack(...)
  record("encounters", "end " .. describe(args[2]) .. " " .. date("%H:%M:%S"), args, 4)
  after(3, function()
    record("addon messages", "chat lockdown after a pull", lockdown())
    record("addon messages", "send after a pull", send("after", channel()))
  end)
  after(6, readLootHistory)
end

handlers.CHAT_MSG_ADDON = function(prefix, text, chatType, sender, ...)
  if prefix ~= PREFIX then return end
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

handlers.ENCOUNTER_LOOT_RECEIVED = function(...)
  record("loot", "encounter loot received " .. date("%H:%M:%S"), pack(...))
end

handlers.LOOT_ITEM_ROLL_WON = function(...)
  record("loot", "your roll won " .. date("%H:%M:%S"), pack(...))
end

handlers.START_LOOT_ROLL = function(rollID, ...)
  record("loot", "roll started " .. date("%H:%M:%S"), { args = pack(rollID, ...), link = GetLootRollItemLink and GetLootRollItemLink(rollID) })
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
  record("loot", "loot window " .. date("%H:%M:%S"), out)
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

local unknown = {}
for event in pairs(handlers) do
  if not pcall(frame.RegisterEvent, frame, event) then unknown[#unknown + 1] = event end
end

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
  "/ggprobe reset - forget everything recorded",
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
    DB.answers, DB.log = {}, {}
    sampledZones, systemSeen = {}, {}
    checkData()
    say("forgotten. Log out or /reload to start over.")
  else
    say("unknown command; /ggprobe help lists them.")
  end
end

if #unknown > 0 then
  after(10, function() record("client", "events this client doesn't know", table.concat(unknown, ", ")) end)
end
