-- A small addon module that proves the harness: it registers for events, schedules a timer, sends an addon message,
-- answers a slash command and writes to its saved variables. It stands in for the addon, which will keep game calls
-- in GuildGolem/Client.lua (docs/PLAN.md); this file calls them directly, so the globals check
-- (test/globals.test.mjs) is not run on it.

local ADDON, ns = ...
local PREFIX = "SAMPLE"
local SNAPSHOT_AFTER = 60

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_LOGOUT")

-- One row for each member of the raid, keyed by GUID, as the addon's attendance will do.
local function snapshot(why)
  local rows = {}
  for i = 1, GetNumGroupMembers() do
    local name, _, subgroup, _, _, class, _, online = GetRaidRosterInfo(i)
    rows[#rows + 1] = { guid = UnitGUID("raid" .. i), name = name, class = class, group = subgroup, online = online }
  end
  local db = SampleDB
  db.snapshots[#db.snapshots + 1] = { at = GetServerTime(), why = why, members = rows }
  if IsInRaid() then
    C_ChatInfo.SendAddonMessage(PREFIX, "snapshot " .. #db.snapshots, "RAID")
  end
  return #rows
end
ns.snapshot = snapshot

frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    SampleDB = SampleDB or {}
    SampleDB.schema = 1
    SampleDB.snapshots = SampleDB.snapshots or {}
    SampleDB.loads = (SampleDB.loads or 0) + 1
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  elseif event == "GROUP_ROSTER_UPDATE" then
    snapshot("roster")
    C_Timer.After(SNAPSHOT_AFTER, function() snapshot("interval") end)
  elseif event == "PLAYER_LOGOUT" then
    SampleDB.lastSeen = GetServerTime()
  end
end)

SLASH_SAMPLE1 = "/sample"
SlashCmdList.SAMPLE = function(rest)
  if rest == "snap" then
    print("Sample: " .. snapshot("slash") .. " in the raid")
  else
    print("Sample: " .. #SampleDB.snapshots .. " snapshots")
  end
end
