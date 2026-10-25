// The addon's codec (GuildGolem/Core/Codec.lua, run in fengari) against the reference JavaScript (contract-lib.mjs) and
// Node's own zlib: strings go both ways between them, a damaged string is refused for the same reason on both sides,
// and the small readers the codec leans on (base64, the zlib size count) agree with Node on streams from every level
// and strategy. The Lua specs (test/lua/specs/codec_spec.lua and the others) cover the rest.
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";
import { constants, deflateRawSync, deflateSync, gzipSync, inflateSync } from "node:zlib";
import { createLua } from "./lua/run.mjs";
import { MAX_JSON, PREFIX, decode, readString, validate } from "./contract-lib.mjs";

const DIR = join(import.meta.dirname, "..", "contract", "fixtures");
const names = readdirSync(DIR).filter((f) => f.endsWith(".json")).map((f) => f.replace(/\.json$/, "")).sort();
const jsonText = (name) => readFileSync(join(DIR, `${name}.json`), "utf8");
const gg1 = (name) => readFileSync(join(DIR, `${name}.gg1.txt`), "utf8");
const readerOf = (name) => (name.startsWith("import-") ? "addon" : "site");

// One Lua state with the addon loaded the way the game loads it, and four small helpers. Binary data crosses as hex
// or base64 text, since a JavaScript string cannot carry a byte string through.
function boot() {
  const lua = createLua();
  lua.run(`
    WOW.declareSavedVariables("GuildGolemDB")
    NS = WOW.loadAddon("GuildGolem")
    local json = LibStub("json.lua")
    local function hex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
    local function unhex(h) return (h:gsub("%x%x", function(x) return string.char(tonumber(x, 16)) end)) end
    -- A fixture's JSON text written as a string by the addon.
    function WRITE(text) return NS.Codec.encode(json.decode(text)) end
    -- A string read as the addon or the site would: the object as JSON text, or the reason.
    function READ(text, reader)
      local object, reason, says = NS.Codec.read(text, reader)
      if not object then return "ERR " .. reason .. " | " .. says end
      return json.encode(object)
    end
    function B64_ENCODE(h) return NS.Base64.encode(unhex(h)) end
    function B64_DECODE(text)
      local bytes, why = NS.Base64.decode(text)
      if not bytes then return "ERR " .. why end
      return hex(bytes)
    end
    function ZSIZE(b64, limit)
      local size, why = NS.ZlibSize.count(NS.Base64.decode(b64), limit)
      if not size then return "ERR " .. why end
      return size
    end
  `);
  return lua;
}

const lua = boot();
// json.lua writes an empty table as [] whether it was a list or an object, so an empty one compares as the same.
const plain = (value) => {
  if (Array.isArray(value)) return value.length ? value.map(plain) : {};
  // json.lua has no null: a null reads as a key that is not there.
  if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).filter(([, v]) => v !== null).map(([k, v]) => [k, plain(v)]));
  return value;
};
const read = (text, reader) => {
  const out = lua.call("READ", text, reader);
  return out.startsWith("ERR ") ? { ok: false, error: out.slice(4).split(" | ")[0] } : { ok: true, value: JSON.parse(out) };
};

describe("strings between the addon's codec and the reference", () => {
  for (const name of names) {
    describe(name, () => {
      it("the addon reads the fixture's string to its JSON", () => {
        const got = read(gg1(name), readerOf(name));
        assert.equal(got.ok, true, got.error);
        assert.deepEqual(got.value, JSON.parse(jsonText(name)));
      });

      it("the reference reads the addon's string to the fixture's JSON", () => {
        const written = lua.call("WRITE", jsonText(name));
        assert.ok(written.startsWith(PREFIX));
        const got = readString(written, readerOf(name));
        assert.equal(got.ok, true, got.error);
        assert.deepEqual(got.value, JSON.parse(jsonText(name)));
        assert.deepEqual(validate(got.value), [], "and it meets the spec's required fields and types");
        assert.ok(written.length <= 524288);
      });

      it("the string is the form the spec gives: padded standard base64 of a zlib stream, in one line", () => {
        const written = lua.call("WRITE", jsonText(name));
        assert.match(written, /^GG1:[A-Za-z0-9+/]+={0,2}$/);
        assert.equal((written.length - 4) % 4, 0);
        const packed = Buffer.from(written.slice(4), "base64");
        assert.equal(packed[0] & 0x0f, 8, "a zlib header");
        assert.deepEqual(JSON.parse(inflateSync(packed).toString("utf8")), JSON.parse(jsonText(name)));
      });
    });
  }
});

// Damaged strings: both sides must refuse them for the same reason (contract/README.md, "Reading a string").
describe("a damaged string is refused for the same reason by the addon and the reference", () => {
  const same = (text, reader, label) => {
    const theirs = readString(text, reader);
    const ours = read(text, reader);
    assert.equal(ours.ok, theirs.ok, `${label}: ok (theirs ${theirs.error}, ours ${ours.error})`);
    if (!theirs.ok) assert.equal(ours.error, theirs.error, label);
    else assert.deepEqual(plain(ours.value), plain(theirs.value), label);
  };

  const small = ["export-pugs", "import-priorities", "export-empty"];

  for (const name of small) {
    it(`${name}: cut short at every length, with its padding lost or kept`, () => {
      const text = gg1(name).trim();
      for (let keep = 0; keep < text.length; keep += 17) same(text.slice(0, keep), readerOf(name), `cut to ${keep}`);
    });

    it(`${name}: one character changed, at each place`, () => {
      const text = gg1(name).trim();
      for (let i = 4; i < text.length; i += 13) {
        const c = text[i] === "A" ? "B" : "A";
        same(text.slice(0, i) + c + text.slice(i + 1), readerOf(name), `changed at ${i}`);
      }
    });

    it(`${name}: whitespace, a trailing newline and extra characters`, () => {
      const text = gg1(name).trim();
      same(`\n  ${text}\r\n`, readerOf(name), "padded with whitespace");
      same(text.replace(/(.{40})/g, "$1\n"), readerOf(name), "wrapped");
      same(text.replace(/=+$/, ""), readerOf(name), "padding lost");
      same(`${text}A`, readerOf(name), "one character more");
      same(`${text}====`, readerOf(name), "too much padding");
      same(text.replace("GG1:", "GG1: "), readerOf(name), "a space after the prefix");
      same(text.replace("GG1:", "GG2:"), readerOf(name), "another generation");
      same(text.toLowerCase(), readerOf(name), "in lower case");
    });
  }

  const pack = (bytes) => PREFIX + Buffer.from(bytes).toString("base64");
  const zlibOf = (object) => deflateSync(Buffer.from(typeof object === "string" ? object : JSON.stringify(object), "utf8"));

  it("what is not a zlib stream: raw deflate, gzip, plain text", () => {
    const body = Buffer.from(jsonText("export-pugs"), "utf8");
    same(pack(deflateRawSync(body)), "site", "raw deflate");
    same(pack(gzipSync(body)), "site", "gzip");
    same(pack(body), "site", "uncompressed");
  });

  it("what unpacks to something that is not our JSON", () => {
    const cases = ["not json", "", "[1]", "[]", "7", "{", '{"v":1,"kind":"export","meta":{}}x', '{"v":1,"kind":"export","meta":{}}'];
    for (const c of cases) same(pack(zlibOf(c)), "site", JSON.stringify(c));
    same(pack(zlibOf(Buffer.from([0x7b, 0x22, 0xff, 0x22, 0x7d]))), "site", "bytes that are not UTF-8");
    same(pack(zlibOf(Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from('{"v":1,"kind":"export","meta":{}}')]))), "site", "a byte order mark");
  });

  it("v, kind and meta: missing, wrong, newer, and the wrong way round", () => {
    const base = { v: 1, kind: "export", meta: { made: 1796843700000 } };
    const variants = [
      {}, { ...base, v: undefined }, { ...base, v: "1" }, { ...base, v: 0 }, { ...base, v: -3 }, { ...base, v: 1.5 }, { ...base, v: 2 },
      { ...base, v: 7, kind: 3 }, { ...base, kind: undefined }, { ...base, kind: "other" }, { ...base, meta: undefined },
      { ...base, meta: "x" }, { ...base, kind: "import" }, base, { ...base, extra: [1, { a: null }] },
    ];
    for (const [i, variant] of variants.entries()) {
      same(pack(zlibOf(variant)), "site", `variant ${i}`);
      same(pack(zlibOf(variant)), "addon", `variant ${i} on the addon`);
    }
  });

  it("a stream that unpacks to more than a MiB: refused as too-big, by both, without unpacking it all", () => {
    const bomb = pack(zlibOf(`{"v":1,"kind":"export","meta":{},"pad":"${" ".repeat(MAX_JSON)}"}`));
    assert.ok(bomb.length < 4000);
    same(bomb, "site", "just over");
    assert.equal(read(bomb, "site").error, "too-big");
    const huge = pack(deflateSync(Buffer.alloc(64 * 1024 * 1024, 0x20), { level: 9 }));
    assert.ok(huge.length < 524288, "small enough to be tried");
    assert.equal(read(huge, "site").error, "too-big");
    same(huge, "site", "64 MiB");
  });

  it("text over 524,288 characters: too-long, before it is looked at", () => {
    same(PREFIX + "A".repeat(524288 - 4 + 1), "site", "one over");
    same(PREFIX + "!".repeat(600000), "site", "over and not base64");
    same(PREFIX + "A".repeat(524288 - 4), "site", "exactly at the limit");
  });
});

describe("the base64 reader and writer agree with Node's", () => {
  let seed = 99;
  const random = (n) => {
    const out = Buffer.alloc(n);
    for (let i = 0; i < n; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      out[i] = (seed >> 16) & 0xff;
    }
    return out;
  };

  it("writes the same text for any bytes, at every length to 40 and some longer", () => {
    for (const n of [...Array(41).keys(), 255, 256, 1000, 5001]) {
      const bytes = random(n);
      assert.equal(lua.call("B64_ENCODE", bytes.toString("hex")), bytes.toString("base64"), `${n} bytes`);
    }
  });

  it("reads Node's text to the same bytes, with the padding kept or lost", () => {
    for (const n of [...Array(41).keys()].slice(1).concat([255, 1000, 5001])) {
      const bytes = random(n);
      const text = bytes.toString("base64");
      assert.equal(lua.call("B64_DECODE", text), bytes.toString("hex"), `${n} bytes`);
      assert.equal(lua.call("B64_DECODE", text.replace(/=+$/, "")), bytes.toString("hex"), `${n} bytes, unpadded`);
    }
  });

  it("refuses what Node's reader would skip over", () => {
    for (const bad of ["Zm9v!", "Zm9v-_", "Zm=9v", "Z", "Zm9vY", "====", "Zm9v==="]) assert.match(lua.call("B64_DECODE", bad), /^ERR bad-text$/, bad);
  });
});

describe("the zlib size count agrees with Node's zlib", () => {
  const { Z_DEFAULT_STRATEGY, Z_FILTERED, Z_HUFFMAN_ONLY, Z_RLE, Z_FIXED } = constants;
  let seed = 4242;
  const random = (n, range = 256) => {
    const out = Buffer.alloc(n);
    for (let i = 0; i < n; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      out[i] = ((seed >> 16) & 0xff) % range;
    }
    return out;
  };
  const inputs = {
    empty: Buffer.alloc(0),
    one: Buffer.from("a"),
    "a fixture": Buffer.from(jsonText("export-pugs")),
    "a long fixture": Buffer.from(jsonText("export-night-split-3")),
    "random bytes": random(6000),
    "few symbols": random(12000, 3),
    zeros: Buffer.alloc(30000),
    "a run then text": Buffer.concat([Buffer.alloc(20000, 0x61), Buffer.from(jsonText("import-night"))]),
  };

  for (const [label, data] of Object.entries(inputs)) {
    it(`counts ${data.length} bytes of ${label} at every level and strategy`, () => {
      // The count is a bit at a time, so a long input is tried at fewer levels.
      const levels = data.length > 10000 ? [0, 6] : [0, 1, 3, 6, 9];
      for (const level of levels) {
        for (const strategy of [Z_DEFAULT_STRATEGY, Z_FILTERED, Z_HUFFMAN_ONLY, Z_RLE, Z_FIXED]) {
          const stream = deflateSync(data, { level, strategy });
          const got = lua.call("ZSIZE", stream.toString("base64"), 10_000_000);
          assert.equal(got, data.length, `level ${level}, strategy ${strategy}`);
        }
      }
    });
  }

  it("stops at the limit, and says too-big only when the size is over it", () => {
    const data = Buffer.from(jsonText("export-night-split-3"));
    const stream = deflateSync(data).toString("base64");
    assert.equal(lua.call("ZSIZE", stream, data.length), data.length);
    assert.equal(lua.call("ZSIZE", stream, data.length - 1), "ERR too-big");
  });
});
