-- Runs the Lua tests on real Lua 5.1, the language the game runs. CI does this (.github/workflows/test.yml, the
-- job "lua51"), and it is the authority on what is in the 5.1 and 5.3 common subset: the same files run in Node
-- under fengari (test/lua-harness.test.mjs), which is Lua 5.3.
--
-- Run it from the repository's folder, naming the spec files:
--   lua5.1 test/lua/run51.lua test/lua/specs/*.lua
--
-- Written in Lua 5.1 syntax, like everything under test/lua/.

assert(_VERSION == "Lua 5.1", "run51.lua is for Lua 5.1, and this is " .. tostring(_VERSION))

local files = { ... }
if #files == 0 then
  io.stderr:write("usage: lua5.1 test/lua/run51.lua test/lua/specs/*.lua\n")
  os.exit(2)
end

GG_ROOT = "."

dofile("test/lua/compat51.lua")
dofile("test/lua/wow.lua")
dofile("test/lua/harness.lua")

for _, path in ipairs(files) do
  dofile(path)
end

local out = WOW.rawprint -- wow.lua turns print into the fake chat window
local results = T.run()
local failed = 0
out("TAP version 13")
for i, r in ipairs(results) do
  if r.ok then
    out("ok " .. i .. " - " .. r.name)
  else
    failed = failed + 1
    out("not ok " .. i .. " - " .. r.name)
    out("  " .. r.err)
  end
end
out("1.." .. #results)

if #results == 0 then
  out("no tests ran")
  os.exit(1)
end
if failed > 0 then
  out(failed .. " of " .. #results .. " failed")
  os.exit(1)
end
