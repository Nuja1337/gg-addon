-- Passes the globals check (test/globals.test.mjs): it reads Lua's own globals, its own namespace and the locals it
-- makes, and nothing the game provides.

local ADDON, ns = ...

local Codec = {}
ns.Codec = Codec

local function count(list)
  local n = 0
  for _ in pairs(list) do n = n + 1 end
  return n
end

function Codec.describe(rows)
  local names = {}
  for i, row in ipairs(rows) do
    names[i] = string.format("%s (%d)", tostring(row.name), row.group or 0)
  end
  table.sort(names)
  return table.concat(names, ", ") .. " / " .. count(rows) .. " of " .. math.max(#rows, 1)
end

GuildGolem = GuildGolem or ns
GuildGolemDB = GuildGolemDB or {}
GuildGolemDB.schema = select("#", unpack({ 1 }))
