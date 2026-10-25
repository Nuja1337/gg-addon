-- Lua 5.1 functions for a Lua 5.3 state (fengari). The game runs Lua 5.1, and this file gives a 5.3 state what 5.1
-- had and 5.3 dropped, so a test written for 5.1 runs in Node. On real Lua 5.1 it does nothing.
--
-- It cannot make 5.3 behave like 5.1 where the language itself differs (integers, `#` on tables with holes, goto):
-- test/lua/README.md lists those. The rule is that code stays in what 5.1 and 5.3 agree on, and the Lua 5.1 job in CI
-- (test/lua/run51.lua) has the last word.
--
-- This file is written in Lua 5.1 syntax, like everything else under test/lua/.

if _VERSION ~= "Lua 5.1" then
  local floor = math.floor

  unpack = unpack or table.unpack

  -- loadstring(text, chunkname) returns nil and a message on a syntax error, as load does.
  loadstring = loadstring or function(text, chunkname)
    return load(text, chunkname)
  end

  gcinfo = gcinfo or function()
    return floor(collectgarbage("count"))
  end

  -- table ------------------------------------------------------------------------------------------------------
  table.getn = table.getn or function(t)
    return #t
  end

  table.setn = table.setn or function()
    error("'setn' is obsolete", 2)
  end

  table.maxn = table.maxn or function(t)
    local most = 0
    for k in pairs(t) do
      if type(k) == "number" and k > most then most = k end
    end
    return most
  end

  -- math -------------------------------------------------------------------------------------------------------
  math.mod = math.mod or math.fmod
  math.pow = math.pow or function(x, y) return x ^ y end
  math.log10 = math.log10 or function(x) return math.log(x, 10) end
  math.ldexp = math.ldexp or function(m, e) return m * 2.0 ^ e end
  math.cosh = math.cosh or function(x) return (math.exp(x) + math.exp(-x)) / 2 end
  math.sinh = math.sinh or function(x) return (math.exp(x) - math.exp(-x)) / 2 end
  math.tanh = math.tanh or function(x)
    local a, b = math.exp(x), math.exp(-x)
    return (a - b) / (a + b)
  end
  math.frexp = math.frexp or function(x)
    if x == 0 or x ~= x or x == math.huge or x == -math.huge then return x, 0 end
    local e = floor(math.log(math.abs(x), 2)) + 1
    local m = x / 2.0 ^ e
    -- math.log can be a hair off near a power of two, so settle m into [0.5, 1).
    if math.abs(m) >= 1 then m, e = m / 2, e + 1 end
    if math.abs(m) < 0.5 then m, e = m * 2, e - 1 end
    return m, e
  end

  -- string -----------------------------------------------------------------------------------------------------
  string.gfind = string.gfind or string.gmatch

  -- Lua 5.1 prints a number with %.14g, so 10 / 2 is "5". Lua 5.3 prints the float 5.0 as "5.0". This brings
  -- tostring() back to 5.1. It cannot reach `..` or the %s of string.format, which still print "5.0": build
  -- text from numbers with string.format("%d") or ("%.14g") (README.md, "What cannot be shimmed").
  local rawtostring = tostring
  local numberType = math.type
  tostring = function(...)
    if select("#", ...) == 0 then return rawtostring() end
    local v = ...
    if numberType(v) == "float" then return string.format("%.14g", v) end
    return rawtostring(v)
  end

  -- Environments -----------------------------------------------------------------------------------------------
  -- Lua 5.1 gives each function an environment table. Lua 5.3 has the _ENV upvalue instead, and these two work by
  -- finding it. A function that never touches a global has no _ENV, so setfenv has nothing to change on it and
  -- getfenv returns _G. A function made inside one that setfenv already changed keeps the old environment if it was
  -- made before the change.
  local function envIndex(fn)
    local i = 1
    while true do
      local name = debug.getupvalue(fn, i)
      if name == nil then return nil end
      if name == "_ENV" then return i end
      i = i + 1
    end
  end

  -- `level` counts from the function that called getfenv or setfenv, as in 5.1: 1 is that function.
  local function functionAt(level, caller)
    if type(level) ~= "number" or level < 0 then
      error("bad argument #1 to '" .. caller .. "' (number expected, got " .. type(level) .. ")", 3)
    end
    if level == 0 then return nil end
    -- The levels are: 1 functionAt, 2 getfenv or setfenv, 3 the caller.
    local info = debug.getinfo(level + 2, "f")
    if not info then error("bad argument #1 to '" .. caller .. "' (invalid level)", 3) end
    return info.func
  end

  getfenv = getfenv or function(f)
    if f == nil then f = 1 end
    local fn = f
    if type(f) ~= "function" then fn = functionAt(f, "getfenv") end
    if fn == nil then return _G end
    local i = envIndex(fn)
    if not i then return _G end
    local _, env = debug.getupvalue(fn, i)
    return env
  end

  setfenv = setfenv or function(f, env)
    if type(env) ~= "table" then
      error("bad argument #2 to 'setfenv' (table expected, got " .. type(env) .. ")", 2)
    end
    local fn = f
    if type(f) ~= "function" then fn = functionAt(f, "setfenv") end
    if fn == nil then error("cannot change the environment of the main thread", 2) end
    local i = envIndex(fn)
    if i then
      debug.upvaluejoin(fn, i, function() return env end, 1)
    end
    return fn
  end
end
