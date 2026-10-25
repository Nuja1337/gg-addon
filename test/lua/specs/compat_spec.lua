-- What compat51.lua gives a Lua 5.3 state, checked with the answers Lua 5.1 gives. On real Lua 5.1 the shim does
-- nothing and these check 5.1 itself, so a wrong expectation here shows up in CI.

T.test("unpack, table.getn and table.maxn", function()
  local a, b, c = unpack({ 10, 20, 30 })
  T.same({ a, b, c }, { 10, 20, 30 })
  T.eq(table.getn({ 1, 2, 3 }), 3)
  T.eq(table.maxn({ 1, 2, [7] = 7 }), 7)
end)

T.test("math.mod, math.pow, math.log10 and math.ldexp", function()
  T.eq(math.mod(7, 3), 1)
  T.eq(math.pow(2, 10), 1024)
  T.eq(math.log10(1000), 3)
  T.eq(math.ldexp(0.5, 4), 8)
end)

T.test("string.gfind reads like gmatch", function()
  local words = {}
  for w in string.gfind("one two three", "%a+") do words[#words + 1] = w end
  T.same(words, { "one", "two", "three" })
end)

T.test("loadstring returns a function, or nil and a message", function()
  local f = loadstring("return 1 + 1")
  T.eq(f(), 2)
  local g, err = loadstring("return +")
  T.eq(g, nil)
  T.eq(type(err), "string")
end)

T.test("setfenv and getfenv change what a function reads as globals", function()
  local f = loadstring("seen = y; return y")
  local env = { y = 5 }
  T.eq(setfenv(f, env), f)
  T.eq(getfenv(f), env)
  T.eq(f(), 5)
  T.eq(env.seen, 5)
  T.eq(rawget(_G, "seen"), nil)
end)

T.test("setfenv(1, env) changes the calling function", function()
  local function inside()
    setfenv(1, { v = 9, getfenv = getfenv })
    return v, getfenv(1).v
  end
  local a, b = inside()
  T.eq(a, 9)
  T.eq(b, 9)
  T.eq(getfenv(0), _G)
end)

T.test("tostring prints a whole number without .0, as 5.1 does", function()
  T.eq(tostring(10 / 2), "5")
  T.eq(tostring(0.1), "0.1")
  T.eq(tostring(3), "3")
  T.eq(tostring(2 ^ 10), "1024")
  T.eq(tostring(nil), "nil")
  T.eq(tostring(true), "true")
  T.eq(tostring(-0.5), "-0.5")
end)

T.test("the common subset: what 5.1 and 5.3 give alike", function()
  T.eq(7 / 2, 3.5)
  T.eq(math.floor(7 / 2), 3)
  T.eq(string.format("%d", 4), "4")
  T.eq(string.format("%.14g", 10 / 4), "2.5")
  T.eq(select("#", nil, nil), 2)
  T.eq(#{ 1, 2, 3 }, 3)
  T.eq(("x"):rep(3), "xxx")
end)
