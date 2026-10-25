-- Fails the globals check (test/globals.test.mjs): the game's GetRaidRosterInfo belongs in Client.lua alone.

local ADDON, ns = ...

function ns.leader()
  for i = 1, 40 do
    local name, rank = GetRaidRosterInfo(i)
    if rank == 2 then return name end
  end
end
