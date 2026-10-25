-- A small test framework that runs the same way on Lua 5.1 and in fengari, so a spec file (specs/*.lua) is one
-- source for both. A spec registers tests with T.test and checks with T.eq and friends; T.run runs them, each after
-- a fresh WOW.reset(), and returns one result per test. test/lua/run51.lua prints the results, and
-- test/lua-harness.test.mjs turns each into a Node test.
--
-- Written in Lua 5.1 syntax, like everything under test/lua/.

T = {}

local tests = {}

-- Text for any value, tables with sorted keys, so a failure message shows what differed.
local function show(value, depth)
  depth = depth or 0
  local t = type(value)
  if t == "string" then return string.format("%q", value) end
  if t ~= "table" then return tostring(value) end
  if depth > 4 then return "{...}" end
  local keys = {}
  for k in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta == "number" end
    if ta == "number" or ta == "string" then return a < b end
    return tostring(a) < tostring(b)
  end)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = "[" .. show(k, depth + 1) .. "]=" .. show(value[k], depth + 1)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end
T.show = show

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not same(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

function T.test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

function T.eq(actual, expected, message)
  if actual ~= expected then
    error((message and (message .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
  end
end

-- Equal as plain data: the same keys and equal values, tables compared by what they hold.
function T.same(actual, expected, message)
  if not same(actual, expected) then
    error((message and (message .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
  end
end

function T.truthy(value, message)
  if not value then error(message or ("expected a true value, got " .. show(value)), 2) end
end

-- fn must raise an error whose text contains `text` (plain, not a pattern).
function T.raises(fn, text)
  local ok, err = pcall(fn)
  if ok then error("expected an error, got none", 2) end
  if text and not tostring(err):find(text, 1, true) then
    error("expected an error with " .. show(text) .. ", got " .. show(tostring(err)), 2)
  end
end

-- Runs every registered test, each after WOW.reset(), and returns a list of { name, ok, err }. The tests are
-- cleared, so a state can load more specs and run again.
function T.run()
  local results = {}
  for i, test in ipairs(tests) do
    WOW.reset()
    local ok, err = pcall(test.fn)
    results[i] = { name = test.name, ok = ok, err = (not ok) and tostring(err) or nil }
  end
  tests = {}
  T.results = results
  return results
end
