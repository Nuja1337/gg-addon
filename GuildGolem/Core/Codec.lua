-- Reads and writes the strings the site and the addon trade, exactly as contract/README.md says ("The string"):
-- GG1: then standard base64 of the zlib-wrapped deflate of the UTF-8 JSON of one object. test/contract-lib.mjs is the
-- same rules in JavaScript, and the tests run every fixture through both.
--
--   Codec.encode(object)           the string and the JSON's length, or nil, a refusal and a detail
--   Codec.json(object)             the JSON text alone, checked the same way, and Codec.pack(text) the string for it
--                                  (encode is the two together; a writer with a size limit measures the JSON first)
--   Codec.decode(text)             the object, or nil and the reason it can't be (steps 1 to 5 of reading)
--   Codec.read(text, reader)       decode, then the checks on v, kind, meta and direction (steps 6 to 9). `reader` is
--                                  "addon" (reads imports) or "site" (reads exports). Gives the object, or nil, the
--                                  reason and the words to show
--   Codec.says(reason, reader)     the words for a reason
--
-- The reasons a string is refused: not-ours, too-long, bad-text, bad-zlib, too-big, bad-json, malformed, newer,
-- wrong-way. Writing refuses with bad-number (a number the contract doesn't allow), bad-utf8, unwritable (a table
-- json.lua can't write), too-big and too-long.
--
-- The libraries come through LibStub. Plain Lua otherwise, no game calls.

local ADDON, ns = ...

local Codec = {}
ns.Codec = Codec

local Base64 = ns.Base64
local ZlibSize = ns.ZlibSize

local LibDeflate = LibStub("LibDeflate")
local json = LibStub("json.lua")

local byte, sub, find, gsub = string.byte, string.sub, string.find, string.gsub
local floor, abs = math.floor, math.abs

Codec.PREFIX = "GG1:"
Codec.VERSION = 1

-- The limits of contract/README.md ("Size"). Readers refuse more than the first two; writers keep to the second two
-- (proposals there, until the launch-day paste test).
Codec.MAX_JSON = 1048576
Codec.MAX_TEXT = 524288
Codec.WRITE_JSON = 786432
Codec.WRITE_TEXT = 65536

-- A number in the JSON is an integer with an absolute value under 10^14, since json.lua writes 14 digits.
Codec.MAX_NUMBER = 1e14

Codec.SAYS = {
  ["not-ours"] = "That isn't a Guild Golem string.",
  ["bad-text"] = "The string has a character that isn't base64. Copy it again.",
  ["too-long"] = "The string is too long to be one of ours.",
  ["bad-zlib"] = "The string is cut short or mistyped. Copy it again.",
  ["too-big"] = "The string unpacks to more than 1 MiB.",
  ["bad-json"] = "The string doesn't hold a Guild Golem object.",
  malformed = "The string is missing v, kind or meta.",
  ["wrong-way"] = "That is an export; paste it on the site.",
  newer = "Update the addon",
}

-- The site is told "The site is behind" for a newer v, and "That is an import; paste it in the addon" for the wrong
-- way round. The addon only ever reads imports, but the words for both ways are kept with the code that picks them.
local SAYS_SITE = {
  newer = "The site is behind",
  ["wrong-way"] = "That is an import; paste it in the addon.",
}

function Codec.says(reason, reader)
  if reader == "site" and SAYS_SITE[reason] then return SAYS_SITE[reason] end
  return Codec.SAYS[reason] or reason
end

-- UTF-8 ---------------------------------------------------------------------------------------------------------

-- True when `s` is well-formed UTF-8 as a strict decoder takes it: no overlong forms, no surrogates, nothing above
-- U+10FFFF. Ascii runs are skipped with one find.
local function validUtf8(s)
  local i = 1
  while true do
    local j = find(s, "[\128-\255]", i)
    if not j then return true end
    local b = byte(s, j)
    if b < 194 then
      return false
    elseif b < 224 then
      local c = byte(s, j + 1)
      if not c or c < 128 or c > 191 then return false end
      i = j + 2
    elseif b < 240 then
      local c, d = byte(s, j + 1, j + 2)
      if not d or c < 128 or c > 191 or d < 128 or d > 191 then return false end
      if b == 224 and c < 160 then return false end
      if b == 237 and c > 159 then return false end
      i = j + 3
    elseif b < 245 then
      local c, d, e = byte(s, j + 1, j + 3)
      if not e or c < 128 or c > 191 or d < 128 or d > 191 or e < 128 or e > 191 then return false end
      if b == 240 and c < 144 then return false end
      if b == 244 and c > 143 then return false end
      i = j + 4
    else
      return false
    end
  end
end
Codec.validUtf8 = validUtf8

-- Writing -------------------------------------------------------------------------------------------------------

-- Walks the object for a number the contract doesn't allow, and returns its path. `seen` stops a table that holds
-- itself.
local function badNumber(value, path, seen)
  local t = type(value)
  if t == "number" then
    if value ~= value or value ~= floor(value) or abs(value) >= Codec.MAX_NUMBER then return path end
  elseif t == "table" then
    if seen[value] then return path .. " (a table that holds itself)" end
    seen[value] = true
    for k, v in pairs(value) do
      local found = badNumber(v, path .. "." .. tostring(k), seen)
      if found then return found end
    end
    seen[value] = nil
  end
  return nil
end

-- The JSON text of an object, checked as the contract wants it written: or nil, a refusal and a detail. A writer that
-- must stay under a size limit (Export.lua) measures this before it packs anything, since packing is the slow part.
function Codec.json(object)
  if type(object) ~= "table" then return nil, "unwritable", "a string is made from one table" end
  local bad = badNumber(object, "$", {})
  if bad then return nil, "bad-number", bad end

  local ok, text = pcall(json.encode, object)
  if not ok then return nil, "unwritable", tostring(text) end
  if not validUtf8(text) then return nil, "bad-utf8" end
  if #text > Codec.MAX_JSON then return nil, "too-big" end
  return text
end

-- The string for JSON text that Codec.json made: and the JSON's length.
function Codec.pack(text)
  local packed = LibDeflate:CompressZlib(text)
  local out = Codec.PREFIX .. Base64.encode(packed)
  if #out > Codec.MAX_TEXT then return nil, "too-long" end
  return out, #text
end

function Codec.encode(object)
  local text, reason, detail = Codec.json(object)
  if not text then return nil, reason, detail end
  return Codec.pack(text)
end

-- Reading -------------------------------------------------------------------------------------------------------

-- A table that came from a JSON object. json.lua gives an array and an object the same kind of table, but an array
-- has a [1] unless it is empty.
local function isObject(t)
  return type(t) == "table" and rawget(t, 1) == nil
end

function Codec.decode(text)
  if type(text) ~= "string" then return nil, "not-ours" end
  local body = gsub(gsub(text, "^[ \t\r\n]+", ""), "[ \t\r\n]+$", "")
  if sub(body, 1, 4) ~= Codec.PREFIX then return nil, "not-ours" end
  if #body > Codec.MAX_TEXT then return nil, "too-long" end

  local packed, why = Base64.decode(sub(body, 5))
  if not packed then return nil, why end

  -- LibDeflate unpacks all of a stream before it gives anything back, so the size is counted first.
  local size, reason = ZlibSize.count(packed, Codec.MAX_JSON)
  if not size then return nil, reason end

  local ok, unpacked = pcall(LibDeflate.DecompressZlib, LibDeflate, packed)
  if not ok or not unpacked then return nil, "bad-zlib" end
  if #unpacked > Codec.MAX_JSON then return nil, "too-big" end

  if not validUtf8(unpacked) then return nil, "bad-json" end
  -- The top level must be an object. An array would come back from json.lua as a table too, so look at the text.
  if not find(unpacked, "^[ \t\r\n]*{") then return nil, "bad-json" end
  local parsed, value = pcall(json.decode, unpacked)
  if not parsed or not isObject(value) then return nil, "bad-json" end
  return value
end

function Codec.read(text, reader)
  if reader ~= "addon" and reader ~= "site" then error("Codec.read: the reader is \"addon\" or \"site\"", 2) end
  local value, reason = Codec.decode(text)
  if not value then return nil, reason, Codec.says(reason, reader) end

  local v = value.v
  if type(v) ~= "number" or v ~= floor(v) or v < 1 then return nil, "malformed", Codec.says("malformed", reader) end
  -- A newer v may have changed every other field, so nothing else is looked at.
  if v > Codec.VERSION then return nil, "newer", Codec.says("newer", reader) end
  local kind = value.kind
  if kind ~= "import" and kind ~= "export" then return nil, "malformed", Codec.says("malformed", reader) end
  if not isObject(value.meta) then return nil, "malformed", Codec.says("malformed", reader) end
  if (reader == "addon") ~= (kind == "import") then return nil, "wrong-way", Codec.says("wrong-way", reader) end
  return value
end
