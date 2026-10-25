-- Core/ZlibSize.lua: the size a zlib stream unpacks to, counted without unpacking it. test/zlib.test.mjs checks it
-- against Node's own zlib at every level and strategy; these tests use LibDeflate's streams and hand-made ones.

local function addon()
  WOW.declareSavedVariables("GuildGolemDB")
  return WOW.loadAddon("GuildGolem")
end

-- Text with repeats, so the compressor has matches to use, and some that doesn't repeat.
local function sample(n)
  local parts = {}
  local seed = 12345
  for i = 1, n do
    seed = (seed * 1103 + 12345) % 65536
    if i % 3 == 0 then
      parts[#parts + 1] = "Player-9101-0F00AA" .. string.format("%02X", seed % 256) .. ","
    else
      parts[#parts + 1] = string.char(32 + seed % 90)
    end
  end
  return table.concat(parts)
end

T.test("counts what LibDeflate's streams unpack to, at every level and strategy", function()
  local ns = addon()
  local LD = LibStub("LibDeflate")
  local text = sample(900)
  local configs = {
    { level = 0 }, { level = 1 }, { level = 6 }, { level = 9 },
    { strategy = "fixed" }, { strategy = "huffman_only" }, { strategy = "dynamic" },
  }
  for _, config in ipairs(configs) do
    local stream = LD:CompressZlib(text, config)
    T.eq(ns.ZlibSize.count(stream, 1000000), #text, "level " .. tostring(config.level) .. " " .. tostring(config.strategy))
  end
  T.eq(ns.ZlibSize.count(LD:CompressZlib(""), 10), 0)
  T.eq(ns.ZlibSize.count(LD:CompressZlib("a"), 10), 1)
end)

T.test("stops at the limit: a size over it is too-big, and exactly at it is fine", function()
  local ns = addon()
  local LD = LibStub("LibDeflate")
  local stream = LD:CompressZlib(string.rep("abc", 1000))
  T.eq(ns.ZlibSize.count(stream, 3000), 3000)
  local size, why = ns.ZlibSize.count(stream, 2999)
  T.eq(size, nil)
  T.eq(why, "too-big")
end)

T.test("a stream that unpacks to far more than it weighs is too-big without being unpacked", function()
  local ns = addon()
  local LD = LibStub("LibDeflate")
  local stream = LD:CompressZlib(string.rep("\0", 300000))
  T.truthy(#stream < 5000, "300 KB of zeros is a small stream: " .. #stream)
  local size, why = ns.ZlibSize.count(stream, 100000)
  T.eq(size, nil)
  T.eq(why, "too-big")
end)

T.test("a stored block counts its bytes", function()
  local ns = addon()
  -- Header 78 01, a final stored block of 5 bytes ("hello"), and any checksum: the count does not look at it.
  local stream = string.char(0x78, 0x01, 0x01, 0x05, 0x00, 0xFA, 0xFF) .. "hello" .. string.char(0, 0, 0, 0)
  T.eq(ns.ZlibSize.count(stream, 100), 5)
  -- NLEN that is not the complement of LEN.
  local size, why = ns.ZlibSize.count(string.char(0x78, 0x01, 0x01, 0x05, 0x00, 0xFA, 0xFE) .. "hello", 100)
  T.eq(size, nil)
  T.eq(why, "bad-zlib")
end)

T.test("a stream that is cut short, empty, or not deflate is bad-zlib", function()
  local ns = addon()
  local LD = LibStub("LibDeflate")
  local stream = LD:CompressZlib(sample(500))
  for _, cut in ipairs({ 0, 1, 2, 3, 10, math.floor(#stream / 2), #stream - 5 }) do
    local size, why = ns.ZlibSize.count(stream:sub(1, cut), 1000000)
    T.eq(size, nil, "cut at " .. cut)
    T.eq(why, "bad-zlib", "cut at " .. cut)
  end
  -- A block type of 3 is invalid.
  local size, why = ns.ZlibSize.count(string.char(0x78, 0x01, 0x07, 0x00), 100)
  T.eq(size, nil)
  T.eq(why, "bad-zlib")
  size, why = ns.ZlibSize.count(nil, 100)
  T.eq(size, nil)
  T.eq(why, "bad-zlib")
end)

T.test("random bytes never raise: they are a count or bad-zlib or too-big", function()
  local ns = addon()
  local seed = 7
  for round = 1, 60 do
    local bytes = { string.char(0x78, 0x9C) }
    for i = 1, 40 + round do
      seed = (seed * 1103 + 12345) % 65536
      bytes[#bytes + 1] = string.char(seed % 256)
    end
    local size, why = ns.ZlibSize.count(table.concat(bytes), 1000)
    T.truthy(size ~= nil or why == "bad-zlib" or why == "too-big", "round " .. round .. ": " .. tostring(why))
  end
end)
