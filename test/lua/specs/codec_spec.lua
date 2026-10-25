-- Core/Codec.lua: the strings the site and the addon trade (contract/README.md, "The string"). Every fixture is read
-- and written here; test/codec.test.mjs runs the same fixtures through the reference JavaScript as well.

local FIXTURES = {
  "export-attendance", "export-empty", "export-loot", "export-night", "export-night-second-recorder",
  "export-night-split-1", "export-night-split-2", "export-night-split-3", "export-night-split-4", "export-pugs",
  "import-night", "import-night-assignments", "import-night-loot", "import-priorities",
}

-- The writer packs at level 8 in the game (Codec.LEVEL). These tests pack a lot of data and do not care how well, and
-- fengari is slow at the higher levels.
local function addon()
  WOW.declareSavedVariables("GuildGolemDB")
  local ns = WOW.loadAddon("GuildGolem")
  ns.Codec.LEVEL = 1
  return ns
end

local function fixture(name, ext)
  return assert(WOW.readFile("contract/fixtures/" .. name .. ext))
end

local function readerOf(name)
  return name:find("^import") and "addon" or "site"
end

-- A string made from JSON text, by the libraries directly, so a test can write what Codec.encode never would.
local function pack(jsonText)
  local LD = LibStub("LibDeflate")
  return "GG1:" .. addon().Base64.encode(LD:CompressZlib(jsonText))
end

local VALID = '{"v":1,"kind":"import","meta":{"made":1796843700000}}'

T.test("every fixture's string unpacks to its JSON", function()
  local ns = addon()
  local json = LibStub("json.lua")
  for _, name in ipairs(FIXTURES) do
    local got, why = ns.Codec.read(fixture(name, ".gg1.txt"), readerOf(name))
    T.truthy(got, name .. ": " .. tostring(why))
    T.same(got, json.decode(fixture(name, ".json")), name)
  end
end)

T.test("every fixture's JSON writes a string that reads back equal", function()
  local ns = addon()
  local json = LibStub("json.lua")
  for _, name in ipairs(FIXTURES) do
    local object = json.decode(fixture(name, ".json"))
    local text, size = ns.Codec.encode(object)
    T.truthy(text, name .. ": " .. tostring(size))
    T.truthy(size > 100 or name == "export-empty", name)
    T.eq(text:sub(1, 4), "GG1:", name)
    local body = text:sub(5)
    T.truthy(body:find("^[A-Za-z0-9+/]+=?=?$"), name .. ": standard base64")
    T.eq(#body % 4, 0, name .. ": padded")
    local back, why = ns.Codec.read(text, readerOf(name))
    T.truthy(back, name .. ": " .. tostring(why))
    T.same(back, object, name)
  end
end)

T.test("a string of ours has no line breaks, and reads with its lines wrapped or its edges padded with space", function()
  local ns = addon()
  local text = ns.Codec.encode({ v = 1, kind = "import", meta = { made = 1796843700000 }, filler = string.rep("abcdefghij", 40) })
  T.truthy(not text:find("%s"))
  local wrapped = text:gsub("(" .. string.rep(".", 60) .. ")", "%1\n")
  T.truthy(wrapped:find("\n"))
  T.truthy(ns.Codec.read("  \t" .. wrapped:gsub("\n", "\r\n") .. "\r\n  ", "addon"))
  -- The padding may be lost in a paste.
  T.truthy(ns.Codec.read((text:gsub("=+$", "")), "addon"))
end)

T.test("not-ours: no GG1: at the front, or not text at all", function()
  local ns = addon()
  for _, s in ipairs({ "", "hello", "GG2:abcd", "gg1:abcd", "GG1", " xGG1:abcd", "GG:1abc" }) do
    local got, why = ns.Codec.decode(s)
    T.eq(got, nil, s)
    T.eq(why, "not-ours", s)
  end
  T.eq(select(2, ns.Codec.decode(nil)), "not-ours")
  T.eq(select(2, ns.Codec.decode(42)), "not-ours")
end)

T.test("too-long: over 524,288 characters, before anything is unpacked", function()
  local ns = addon()
  local long = "GG1:" .. string.rep("A", 524288 - 4)
  T.eq(select(2, ns.Codec.decode(long)), "bad-zlib", "exactly at the limit goes on to be unpacked")
  T.eq(select(2, ns.Codec.decode(long .. "A")), "too-long")
  T.eq(select(2, ns.Codec.decode("GG1:" .. string.rep("!", 600000))), "too-long", "too long comes before bad text")
end)

T.test("bad-text: a character that is not base64, or a bad padding", function()
  local ns = addon()
  for _, s in ipairs({ "GG1:", "GG1:    ", "GG1:Zm9v!", "GG1:Zm=v", "GG1:Zm9v===", "GG1:-_-_", "GG1:Zm9vY" }) do
    T.eq(select(2, ns.Codec.decode(s)), "bad-text", s)
  end
end)

T.test("bad-zlib: cut short, a changed character, or a checksum that doesn't match", function()
  local ns = addon()
  local text = ns.Codec.encode({ v = 1, kind = "import", meta = { made = 1796843700000 }, filler = string.rep("some text ", 80) })
  local body = text:sub(5)
  -- Cut short, at several places, with the padding fixed so only the stream is damaged.
  for _, keep in ipairs({ 8, 20, 40, #body - 20, #body - 8 }) do
    local cut = body:sub(1, keep - keep % 4)
    T.eq(select(2, ns.Codec.decode("GG1:" .. cut)), "bad-zlib", "cut to " .. keep)
  end
  -- A different character in the middle of the data.
  local mid = math.floor(#body / 2)
  local was = body:sub(mid, mid)
  local swapped = was == "A" and "B" or "A"
  local damaged = body:sub(1, mid - 1) .. swapped .. body:sub(mid + 1)
  T.eq(select(2, ns.Codec.decode("GG1:" .. damaged)), "bad-zlib")
  -- The last base64 group holds the Adler-32: change it.
  local tail = body:sub(-8)
  local altered = tail:sub(1, 4) .. (tail:sub(5, 5) == "A" and "B" or "A") .. tail:sub(6)
  T.eq(select(2, ns.Codec.decode("GG1:" .. body:sub(1, -9) .. altered)), "bad-zlib")
  -- Raw deflate is not a zlib stream.
  local LD = LibStub("LibDeflate")
  local raw = "GG1:" .. ns.Base64.encode(LD:CompressDeflate(VALID))
  T.eq(select(2, ns.Codec.decode(raw)), "bad-zlib")
end)

T.test("too-big: JSON that unpacks past the limit, however small the string", function()
  local ns = addon()
  local text = ns.Codec.encode({ v = 1, kind = "import", meta = { made = 1796843700000 }, filler = string.rep("0", 5000) })
  ns.Codec.MAX_JSON = 4000
  T.eq(select(2, ns.Codec.decode(text)), "too-big")
  ns.Codec.MAX_JSON = 6000
  T.truthy(ns.Codec.decode(text))
  ns.Codec.MAX_JSON = 1048576
end)

T.test("too-big: a thousand to one is refused without being unpacked", function()
  local ns = addon()
  local LD = LibStub("LibDeflate")
  local bomb = "GG1:" .. ns.Base64.encode(LD:CompressZlib(string.rep(" ", 1200000)))
  T.truthy(#bomb < 20000, "a bomb is a small string: " .. #bomb)
  T.eq(select(2, ns.Codec.decode(bomb)), "too-big")
end)

T.test("bad-json: not JSON, not an object, not UTF-8, or with a byte order mark", function()
  local ns = addon()
  local bad = {
    "not json", "", "[1,2]", "[]", "42", "\"v\"", "null", "{\"v\":1", VALID .. "x", "\239\187\191" .. VALID,
    '{"v":1,"kind":"import","meta":{"made":1},"x":"\255"}', -- not UTF-8
    '{"v":1,"kind":"import","meta":{"made":1},"x":"\237\160\128"}', -- a surrogate
    '{"v":1,"kind":"import","meta":{"made":1},"x":"\192\128"}', -- an overlong NUL
    '{"v":1,"kind":"import","meta":{"made":1},"x":"\244\144\128\128"}', -- past U+10FFFF
  }
  for _, jsonText in ipairs(bad) do
    T.eq(select(2, ns.Codec.decode(pack(jsonText))), "bad-json", jsonText)
  end
  T.truthy(ns.Codec.decode(pack('  \n{"v":1,"kind":"import","meta":{"made":1},"x":"Zo\195\171 \226\130\172 \240\159\152\128"}')))
  -- Deep nesting is an error in the parser, not a crash.
  T.eq(select(2, ns.Codec.decode(pack(string.rep("[", 100000)))), "bad-json")
  T.eq(select(2, ns.Codec.decode(pack('{"a":' .. string.rep("[", 100000)))), "bad-json")
end)

T.test("malformed: no v, a v that isn't a whole number from 1, no kind, a kind that isn't one, or no meta", function()
  local ns = addon()
  local cases = {
    '{}', '{"kind":"import","meta":{}}', '{"v":"1","kind":"import","meta":{}}', '{"v":0,"kind":"import","meta":{}}',
    '{"v":-1,"kind":"import","meta":{}}', '{"v":1.5,"kind":"import","meta":{}}', '{"v":true,"kind":"import","meta":{}}',
    '{"v":1,"meta":{}}', '{"v":1,"kind":"other","meta":{}}', '{"v":1,"kind":7,"meta":{}}', '{"v":1,"kind":"import"}',
    '{"v":1,"kind":"import","meta":"x"}', '{"v":1,"kind":"import","meta":[1]}', '{"v":1,"kind":"import","meta":null}',
  }
  for _, jsonText in ipairs(cases) do
    local got, why = ns.Codec.read(pack(jsonText), "addon")
    T.eq(got, nil, jsonText)
    T.eq(why, "malformed", jsonText)
  end
end)

T.test("newer: a v above 1 is refused first, whatever else is wrong with it", function()
  local ns = addon()
  for _, jsonText in ipairs({ '{"v":2,"kind":"import","meta":{}}', '{"v":2}', '{"v":99,"kind":false,"meta":3}', '{"v":1e3}' }) do
    local got, why, says = ns.Codec.read(pack(jsonText), "addon")
    T.eq(got, nil, jsonText)
    T.eq(why, "newer", jsonText)
    T.eq(says, "Update the addon")
  end
  local _, why, says = ns.Codec.read(pack('{"v":2,"kind":"export","meta":{}}'), "site")
  T.eq(why, "newer")
  T.eq(says, "The site is behind")
end)

T.test("wrong-way: an export pasted into the addon, an import pasted on the site", function()
  local ns = addon()
  local export = ns.Codec.encode({ v = 1, kind = "export", meta = { made = 1796843700000 } })
  local import = ns.Codec.encode({ v = 1, kind = "import", meta = { made = 1796843700000 } })
  local got, why, says = ns.Codec.read(export, "addon")
  T.eq(got, nil)
  T.eq(why, "wrong-way")
  T.eq(says, "That is an export; paste it on the site.")
  got, why, says = ns.Codec.read(import, "site")
  T.eq(why, "wrong-way")
  T.eq(says, "That is an import; paste it in the addon.")
  T.truthy(ns.Codec.read(import, "addon"))
  T.truthy(ns.Codec.read(export, "site"))
  T.raises(function() ns.Codec.read(import, "robot") end, "reader")
end)

T.test("every refusal has words to show", function()
  local ns = addon()
  for _, reason in ipairs({ "not-ours", "too-long", "bad-text", "bad-zlib", "too-big", "bad-json", "malformed", "newer", "wrong-way" }) do
    T.truthy(ns.Codec.says(reason, "addon") ~= reason, reason)
  end
  T.eq(ns.Codec.says("something-new", "addon"), "something-new")
end)

T.test("unknown fields are carried through, not refused", function()
  local ns = addon()
  local text = ns.Codec.encode({ v = 1, kind = "import", meta = { made = 1796843700000, later = "yes" }, extra = { 1, 2, 3 } })
  local got = ns.Codec.read(text, "addon")
  T.same(got.extra, { 1, 2, 3 })
  T.eq(got.meta.later, "yes")
end)

T.test("numbers stay whole: 13-digit times and 14-digit counts are written as integers", function()
  local ns = addon()
  local LD = LibStub("LibDeflate")
  local object = { v = 1, kind = "export", meta = { made = 1796843700000, big = 99999999999999, small = 0, neg = -5 } }
  local text = ns.Codec.encode(object)
  local jsonText = LD:DecompressZlib(ns.Base64.decode(text:sub(5)))
  T.truthy(jsonText:find('"made":1796843700000', 1, true), jsonText)
  T.truthy(jsonText:find('"big":99999999999999', 1, true), jsonText)
  T.truthy(not jsonText:find("[eE]%+"), "no exponent: " .. jsonText)
  T.truthy(not jsonText:find("%.0"), "no fraction: " .. jsonText)
  T.same(ns.Codec.read(text, "site"), object)
end)

T.test("a number the contract doesn't allow is refused when writing, with its path", function()
  local ns = addon()
  local cases = {
    { 1e14, "$.meta.made" }, { 1.5, "$.meta.made" }, { 0 / 0, "$.meta.made" }, { math.huge, "$.meta.made" },
    { -1e15, "$.meta.made" }, { 123456789012345, "$.meta.made" },
  }
  for _, case in ipairs(cases) do
    local text, why, where = ns.Codec.encode({ v = 1, kind = "export", meta = { made = case[1] } })
    T.eq(text, nil, tostring(case[1]))
    T.eq(why, "bad-number", tostring(case[1]))
    T.eq(where, case[2])
  end
  local _, why, where = ns.Codec.encode({ v = 1, kind = "export", meta = { made = 1 }, attendance = { { snapshots = { { at = 2.5 } } } } })
  T.eq(why, "bad-number")
  T.eq(where, "$.attendance.1.snapshots.1.at")
end)

T.test("writing refuses what json.lua can't write, text that isn't UTF-8, and anything that isn't a table", function()
  local ns = addon()
  local _, why = ns.Codec.encode("text")
  T.eq(why, "unwritable")
  _, why = ns.Codec.encode({ v = 1, kind = "export", meta = { made = 1, f = function() end } })
  T.eq(why, "unwritable")
  _, why = ns.Codec.encode({ v = 1, kind = "export", meta = { made = 1 }, sparse = { [1] = "a", [3] = "c" } })
  T.eq(why, "unwritable")
  _, why = ns.Codec.encode({ v = 1, kind = "export", meta = { made = 1 }, mixed = { "a", b = 1 } })
  T.eq(why, "unwritable")
  _, why = ns.Codec.encode({ v = 1, kind = "export", meta = { made = 1, name = "bad \255 byte" } })
  T.eq(why, "bad-utf8")
  local loop = { v = 1, kind = "export", meta = { made = 1 } }
  loop.again = loop
  _, why = ns.Codec.encode(loop)
  T.eq(why, "bad-number", "a table that holds itself is found before it is written")
end)

T.test("names with accents, quotes, a bar and control characters come back exactly as they went", function()
  local ns = addon()
  local names = { "Zo\195\171 M\195\188ller", 'Say "hi"', "back\\slash", "a|cffff0000red|r", "tab\there", "line\nbreak", "\226\130\172 \240\159\152\128" }
  local object = { v = 1, kind = "export", meta = { made = 1796843700000 }, names = names }
  local back = ns.Codec.read(ns.Codec.encode(object), "site")
  T.same(back.names, names)
end)

T.test("an empty list is written [], and true stays true", function()
  local ns = addon()
  local LD = LibStub("LibDeflate")
  local text = ns.Codec.encode({ v = 1, kind = "import", meta = { made = 1 }, list = {}, flag = true })
  local jsonText = LD:DecompressZlib(ns.Base64.decode(text:sub(5)))
  T.truthy(jsonText:find('"list":[]', 1, true), jsonText)
  T.truthy(jsonText:find('"flag":true', 1, true), jsonText)
end)

T.test("writing stops at the limits a reader would refuse", function()
  local ns = addon()
  ns.Codec.MAX_JSON = 100
  local text, why = ns.Codec.encode({ v = 1, kind = "import", meta = { made = 1 }, filler = string.rep("x", 200) })
  T.eq(text, nil)
  T.eq(why, "too-big")
  ns.Codec.MAX_JSON = 1048576
  ns.Codec.MAX_TEXT = 40
  text, why = ns.Codec.encode({ v = 1, kind = "import", meta = { made = 1 }, filler = "x" })
  T.eq(text, nil)
  T.eq(why, "too-long")
  ns.Codec.MAX_TEXT = 524288
  T.eq(ns.Codec.WRITE_JSON, 786432)
  T.eq(ns.Codec.WRITE_TEXT, 65536)
end)
