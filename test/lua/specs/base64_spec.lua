-- Core/Base64.lua: standard base64 with padding (RFC 4648 section 4), as contract/README.md specifies.

local function addon()
  WOW.declareSavedVariables("GuildGolemDB")
  return WOW.loadAddon("GuildGolem")
end

-- RFC 4648 section 10.
local VECTORS = {
  { "", "" }, { "f", "Zg==" }, { "fo", "Zm8=" }, { "foo", "Zm9v" }, { "foob", "Zm9vYg==" }, { "fooba", "Zm9vYmE=" },
  { "foobar", "Zm9vYmFy" },
}

T.test("encodes the RFC 4648 vectors, with padding", function()
  local B = addon().Base64
  for _, v in ipairs(VECTORS) do T.eq(B.encode(v[1]), v[2], v[1]) end
end)

T.test("decodes the RFC 4648 vectors, with and without padding", function()
  local B = addon().Base64
  for _, v in ipairs(VECTORS) do
    if v[1] ~= "" then
      T.eq(B.decode(v[2]), v[1], v[2])
      T.eq(B.decode((v[2]:gsub("=", ""))), v[1], "without padding: " .. v[2])
    end
  end
end)

T.test("uses the standard alphabet, + and /, never - or _", function()
  local B = addon().Base64
  T.eq(B.encode(string.char(251, 255, 191)), "+/+/")
  T.eq(B.decode("+/+/"), string.char(251, 255, 191))
  local text, why = B.decode("-_-_")
  T.eq(text, nil)
  T.eq(why, "bad-text")
end)

T.test("every byte value survives, at every length from 0 to 5 past a multiple of 3", function()
  local B = addon().Base64
  local all = {}
  for i = 0, 255 do all[#all + 1] = string.char(i) end
  local bytes = table.concat(all)
  for extra = 0, 5 do
    local s = bytes:sub(1, 240 + extra)
    local back = B.decode(B.encode(s))
    T.truthy(back == s, "round trip of " .. #s .. " bytes")
  end
  T.eq(B.decode(B.encode(bytes)), bytes)
end)

T.test("drops whitespace between the characters, since chat boxes and editors wrap lines", function()
  local B = addon().Base64
  T.eq(B.decode("Zm9v\nYmFy"), "foobar")
  T.eq(B.decode("  Zm9v \r\n YmFy\t"), "foobar")
  T.eq(B.decode("Zm 9v Yg =\n="), "foob")
end)

T.test("refuses what is not base64", function()
  local B = addon().Base64
  for _, bad in ipairs({ "", "====", "Z", "Zm9vY", "Zm=9v", "Zm9v!", "Zm9v===", "Zm9v\0", "Zm9vé" }) do
    local text, why = B.decode(bad)
    T.eq(text, nil, bad)
    T.eq(why, "bad-text", bad)
  end
  local text, why = B.decode(nil)
  T.eq(text, nil)
  T.eq(why, "bad-text")
end)

T.test("encode wants a string", function()
  local B = addon().Base64
  T.raises(function() B.encode(12) end, "needs a string")
end)
