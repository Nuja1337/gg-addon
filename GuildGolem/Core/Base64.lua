-- Standard base64 (RFC 4648 section 4): the alphabet A-Z a-z 0-9 + /, padded with = to a multiple of 4. This is the
-- packing contract/README.md specifies ("The string", step 3 of writing and of reading). Plain Lua, no game calls.
--
--   Base64.encode(bytes)        the text, padded
--   Base64.decode(text)         the bytes, or nil and "bad-text"
--
-- decode drops whitespace (space, tab, CR, LF), since chat boxes and editors wrap lines, and takes a string whose
-- padding was lost. It accepts at most two = at the end, and nothing outside the alphabet.

local ADDON, ns = ...

local Base64 = {}
ns.Base64 = Base64

local byte, char, sub, find, gsub = string.byte, string.char, string.sub, string.find, string.gsub
local floor, concat = math.floor, table.concat

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

-- Value (0 to 63) to its character, and a character's byte to its value.
local ENC = {}
local DEC = {}
for i = 0, 63 do
  ENC[i] = sub(ALPHABET, i + 1, i + 1)
  DEC[byte(ALPHABET, i + 1)] = i
end

function Base64.encode(bytes)
  if type(bytes) ~= "string" then error("Base64.encode needs a string", 2) end
  local len = #bytes
  local parts = {}
  local n = 0
  local i = 1
  while i + 2 <= len do
    local a, b, c = byte(bytes, i, i + 2)
    local v = a * 65536 + b * 256 + c
    n = n + 1
    parts[n] = ENC[floor(v / 262144)] .. ENC[floor(v / 4096) % 64] .. ENC[floor(v / 64) % 64] .. ENC[v % 64]
    i = i + 3
  end
  local left = len - i + 1
  if left == 1 then
    local a = byte(bytes, i)
    local v = a * 65536
    n = n + 1
    parts[n] = ENC[floor(v / 262144)] .. ENC[floor(v / 4096) % 64] .. "=="
  elseif left == 2 then
    local a, b = byte(bytes, i, i + 1)
    local v = a * 65536 + b * 256
    n = n + 1
    parts[n] = ENC[floor(v / 262144)] .. ENC[floor(v / 4096) % 64] .. ENC[floor(v / 64) % 64] .. "="
  end
  return concat(parts)
end

function Base64.decode(text)
  if type(text) ~= "string" then return nil, "bad-text" end
  local body = gsub(text, "[ \t\r\n]", "")
  local pad = #body
  body = gsub(body, "=+$", "")
  pad = pad - #body
  if pad > 2 then return nil, "bad-text" end
  if find(body, "[^A-Za-z0-9+/]") then return nil, "bad-text" end
  local len = #body
  -- A single leftover character holds only 6 bits, which is not a byte; nothing at all is no string.
  if len == 0 or len % 4 == 1 then return nil, "bad-text" end

  local parts = {}
  local n = 0
  local i = 1
  while i + 3 <= len do
    local a, b, c, d = byte(body, i, i + 3)
    local v = ((DEC[a] * 64 + DEC[b]) * 64 + DEC[c]) * 64 + DEC[d]
    n = n + 1
    parts[n] = char(floor(v / 65536), floor(v / 256) % 256, v % 256)
    i = i + 4
  end
  local left = len - i + 1
  if left == 2 then
    local a, b = byte(body, i, i + 1)
    local v = DEC[a] * 64 + DEC[b]
    n = n + 1
    parts[n] = char(floor(v / 16))
  elseif left == 3 then
    local a, b, c = byte(body, i, i + 2)
    local v = (DEC[a] * 64 + DEC[b]) * 64 + DEC[c]
    n = n + 1
    parts[n] = char(floor(v / 1024), floor(v / 4) % 256)
  end
  return concat(parts)
end
