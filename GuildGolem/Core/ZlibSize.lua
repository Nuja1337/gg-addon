-- How many bytes a zlib stream (RFC 1950) would unpack to, counted without unpacking it, and stopped as soon as the
-- count passes a limit. contract/README.md says a reader stops at 1 MiB of JSON ("too-big"), and LibDeflate has no
-- such limit: a few hundred KB of text can unpack to hundreds of MB (a stream of zeros shrinks by a thousand to one),
-- which would freeze the game. Codec.lua asks this first, and only a stream it accepts goes to LibDeflate, which
-- stays exactly as its author published it.
--
--   ZlibSize.count(bytes, limit)   the size in bytes, or nil and "too-big" (the size passes `limit`), or nil and
--                                  "bad-zlib" (the stream is cut short or is not valid deflate)
--
-- It follows Mark Adler's puff.c, the reference small decoder: the same Huffman tables and the same checks. It keeps
-- no window, since it only counts, so it does not notice a distance that reaches back too far or the Adler-32
-- checksum; LibDeflate does, and its answer is the one that counts. Plain Lua, no game calls, and numbers kept far
-- below 2^31 so that Lua 5.1 and the 32-bit integers of the test harness agree.

local ADDON, ns = ...

local ZlibSize = {}
ns.ZlibSize = ZlibSize

local byte = string.byte
local floor = math.floor

local POW2 = {}
for i = 0, 24 do POW2[i] = 2 ^ i end

-- Base values and extra bits for the length codes 257..285 and the distance codes 0..29 (RFC 1951, 3.2.5).
local LBASE = { [0] = 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEXT = { [0] = 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DBASE = { [0] = 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DEXT = { [0] = 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }

-- The order the code length code's own lengths come in.
local ORDER = { [0] = 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

-- Raised inside the scan and caught at the edge, so the loops need no checks after each read.
local TOOBIG = {}
local BAD = {}

-- Reads `need` bits (0 to 13), least significant first.
local function bits(st, need)
  local buf, cnt = st.buf, st.cnt
  while cnt < need do
    local b = byte(st.s, st.pos)
    if not b then error(BAD, 0) end
    st.pos = st.pos + 1
    buf = buf + b * POW2[cnt]
    cnt = cnt + 8
  end
  local value = buf % POW2[need]
  st.buf = (buf - value) / POW2[need]
  st.cnt = cnt - need
  return value
end

-- A Huffman table from a list of code lengths [0..n-1]: how many codes there are of each length, and the symbols in
-- code order. The second result is 0 for a complete code, above 0 for an incomplete one, below 0 for one with too
-- many codes.
local function construct(lengths, n)
  local count = {}
  for len = 0, 15 do count[len] = 0 end
  for symbol = 0, n - 1 do count[lengths[symbol]] = count[lengths[symbol]] + 1 end
  if count[0] == n then return { count = count, symbol = {} }, 0 end

  local left = 1
  for len = 1, 15 do
    left = left * 2 - count[len]
    if left < 0 then return nil, left end
  end

  local offs = { [1] = 0 }
  for len = 1, 14 do offs[len + 1] = offs[len] + count[len] end
  local symbol = {}
  for sym = 0, n - 1 do
    local len = lengths[sym]
    if len ~= 0 then
      symbol[offs[len]] = sym
      offs[len] = offs[len] + 1
    end
  end
  return { count = count, symbol = symbol }, left
end

-- The next symbol, read a bit at a time.
local function decode(st, h)
  local code, first, index = 0, 0, 0
  local count, symbol = h.count, h.symbol
  for len = 1, 15 do
    code = code + bits(st, 1)
    local c = count[len]
    if code - c < first then return symbol[index + (code - first)] end
    index = index + c
    first = (first + c) * 2
    code = code * 2
  end
  error(BAD, 0)
end

local function add(st, n)
  st.out = st.out + n
  if st.out > st.limit then error(TOOBIG, 0) end
end

local function codes(st, lencode, distcode)
  while true do
    local symbol = decode(st, lencode)
    if not symbol then error(BAD, 0) end
    if symbol < 256 then
      add(st, 1)
    elseif symbol == 256 then
      return
    else
      symbol = symbol - 257
      if symbol >= 29 then error(BAD, 0) end
      local len = LBASE[symbol] + bits(st, LEXT[symbol])
      local dsym = decode(st, distcode)
      if not dsym or dsym >= 30 then error(BAD, 0) end
      bits(st, DEXT[dsym])
      add(st, len)
    end
  end
end

local fixedLen, fixedDist
local function fixedTables()
  if not fixedLen then
    local lengths = {}
    for sym = 0, 143 do lengths[sym] = 8 end
    for sym = 144, 255 do lengths[sym] = 9 end
    for sym = 256, 279 do lengths[sym] = 7 end
    for sym = 280, 287 do lengths[sym] = 8 end
    fixedLen = construct(lengths, 288)
    local dist = {}
    for sym = 0, 29 do dist[sym] = 5 end
    fixedDist = construct(dist, 30)
  end
  return fixedLen, fixedDist
end

local function stored(st)
  -- The rest of the current byte is skipped. Bits are read a byte at a time, so fewer than 8 are ever left.
  st.buf, st.cnt = 0, 0
  local s, pos = st.s, st.pos
  local b1, b2, b3, b4 = byte(s, pos, pos + 3)
  if not b4 then error(BAD, 0) end
  local len = b1 + b2 * 256
  if len + b3 + b4 * 256 ~= 65535 then error(BAD, 0) end
  pos = pos + 4
  if pos + len - 1 > #s then error(BAD, 0) end
  st.pos = pos + len
  add(st, len)
end

local function dynamic(st)
  local nlen = bits(st, 5) + 257
  local ndist = bits(st, 5) + 1
  local ncode = bits(st, 4) + 4
  if nlen > 286 or ndist > 30 then error(BAD, 0) end

  local lengths = {}
  for i = 0, 18 do lengths[i] = 0 end
  for i = 0, ncode - 1 do lengths[ORDER[i]] = bits(st, 3) end
  local lencode, err = construct(lengths, 19)
  if err ~= 0 then error(BAD, 0) end

  local index = 0
  local total = nlen + ndist
  lengths = {}
  while index < total do
    local symbol = decode(st, lencode)
    if not symbol then error(BAD, 0) end
    if symbol < 16 then
      lengths[index] = symbol
      index = index + 1
    else
      local len, rep = 0, 0
      if symbol == 16 then
        if index == 0 then error(BAD, 0) end
        len = lengths[index - 1]
        rep = 3 + bits(st, 2)
      elseif symbol == 17 then
        rep = 3 + bits(st, 3)
      else
        rep = 11 + bits(st, 7)
      end
      if index + rep > total then error(BAD, 0) end
      for _ = 1, rep do
        lengths[index] = len
        index = index + 1
      end
    end
  end
  if lengths[256] == 0 then error(BAD, 0) end

  local lcodes, lerr = construct(lengths, nlen)
  -- An incomplete code is allowed only when it is the one code of length 1.
  if not lcodes or (lerr ~= 0 and nlen ~= lcodes.count[0] + lcodes.count[1]) then error(BAD, 0) end
  local dlengths = {}
  for i = 0, ndist - 1 do dlengths[i] = lengths[nlen + i] end
  local dcodes, derr = construct(dlengths, ndist)
  if not dcodes or (derr ~= 0 and ndist ~= dcodes.count[0] + dcodes.count[1]) then error(BAD, 0) end
  codes(st, lcodes, dcodes)
end

local function scan(st)
  -- The zlib header: two bytes. Their checksum and the method are LibDeflate's to check.
  bits(st, 8)
  bits(st, 8)
  local last
  repeat
    last = bits(st, 1)
    local kind = bits(st, 2)
    if kind == 0 then
      stored(st)
    elseif kind == 1 then
      local lencode, distcode = fixedTables()
      codes(st, lencode, distcode)
    elseif kind == 2 then
      dynamic(st)
    else
      error(BAD, 0)
    end
  until last == 1
end

function ZlibSize.count(bytes, limit)
  if type(bytes) ~= "string" then return nil, "bad-zlib" end
  local st = { s = bytes, pos = 1, buf = 0, cnt = 0, out = 0, limit = limit }
  local ok, err = pcall(scan, st)
  if ok then return st.out end
  if err == TOOBIG then return nil, "too-big" end
  if err == BAD then return nil, "bad-zlib" end
  -- Anything else is a mistake in this file, not in the string; report it as the string being unreadable.
  return nil, "bad-zlib", tostring(err)
end
