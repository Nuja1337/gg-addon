// The contract with the site (contract/README.md): each fixture's string unpacks to its JSON, every fixture meets the
// spec's required fields and types, and the strings that must fail do (cut short, mistyped, newer, too big, the wrong
// way round). Nobody here runs the addon or the site; this is the spec's own check, and the same fixtures go to the
// site's tests.
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";
import { deflateRawSync, deflateSync, gzipSync, inflateRawSync, inflateSync } from "node:zlib";
import { FROM, MAX_JSON, MAX_TEXT, PREFIX, WRITE_JSON, WRITE_TEXT, decode, dedupeAll, dedupeKey, encode, fit, readString, validate } from "./contract-lib.mjs";

const DIR = join(import.meta.dirname, "..", "contract", "fixtures");
const names = readdirSync(DIR)
  .filter((f) => f.endsWith(".json"))
  .map((f) => f.replace(/\.json$/, ""))
  .sort();
const json = (name) => JSON.parse(readFileSync(join(DIR, `${name}.json`), "utf8"));
const text = (name) => readFileSync(join(DIR, `${name}.gg1.txt`), "utf8");
const imports = names.filter((n) => n.startsWith("import-"));
const exports_ = names.filter((n) => n.startsWith("export-"));
const clone = (o) => JSON.parse(JSON.stringify(o));
const pack = (bytes) => PREFIX + bytes.toString("base64");
const BIG = "export-night";

describe("the fixtures", () => {
  it("are one JSON file and one string each, for every import and export shape", () => {
    assert.deepEqual(
      readdirSync(DIR).sort(),
      names.flatMap((n) => [`${n}.gg1.txt`, `${n}.json`]).sort(),
    );
    assert.deepEqual(
      imports.map((n) => n.replace("import-", "")).sort(),
      ["night", "night-assignments", "night-loot", "priorities"],
    );
    assert.deepEqual(exports_, ["export-attendance", "export-empty", "export-loot", "export-night", "export-pugs"]);
    assert.deepEqual([...new Set(imports.map((n) => json(n).meta.from))].sort(), [...FROM].sort());
  });

  it("use made-up players only", () => {
    const guids = JSON.stringify(names.map(json)).match(/Player-\d+-[0-9A-F]+/g) ?? [];
    assert.ok(guids.length > 20);
    for (const g of new Set(guids)) assert.match(g, /^Player-910[123]-0F00(AA|BB)[0-9A-F]{2}$/, g);
  });

  for (const name of names) {
    describe(name, () => {
      it("has a string that unpacks to its JSON", () => {
        const got = decode(text(name));
        assert.equal(got.ok, true);
        assert.deepEqual(got.value, json(name));
      });

      it("is packed the way the spec says", () => {
        const body = text(name);
        assert.equal(body.endsWith("\n") && !body.slice(0, -1).includes("\n"), true, "one line");
        const line = body.trim();
        assert.ok(line.startsWith("GG1:"));
        assert.match(line.slice(4), /^[A-Za-z0-9+/]+={0,2}$/);
        assert.equal(line.slice(4).length % 4, 0, "padded");
        const packed = Buffer.from(line.slice(4), "base64");
        // A zlib stream: its header is a deflate stream with a 32 KB window, and its length check divides by 31.
        assert.equal(packed[0] & 0x0f, 8);
        assert.equal(((packed[0] << 8) | packed[1]) % 31, 0);
        assert.doesNotThrow(() => inflateSync(packed));
        assert.throws(() => inflateRawSync(packed), "not raw deflate");
        // UTF-8 with no byte order mark.
        const bytes = inflateSync(packed);
        assert.notEqual(bytes[0], 0xef);
        assert.ok(bytes.length < MAX_JSON);
        assert.ok(line.length <= WRITE_TEXT);
      });

      it("packs again to a string that reads back to the same JSON", () => {
        assert.deepEqual(decode(encode(json(name))).value, json(name));
      });

      it("meets the spec's required fields and types", () => {
        assert.deepEqual(validate(json(name)), []);
      });

      it("reads on the side it is for, and is refused on the other", () => {
        const forAddon = name.startsWith("import-");
        assert.equal(readString(text(name), "addon").ok, forAddon);
        assert.equal(readString(text(name), "site").ok, !forAddon);
        assert.equal(readString(text(name), forAddon ? "site" : "addon").error, "wrong-way");
      });
    });
  }

  it("show what the spec claims they do", () => {
    const night = json("import-night");
    assert.equal(night.raids.length, 3);
    assert.ok(night.raids[0].bench.length > 0, "a bench");
    assert.ok(night.raids.every((r) => r.groups.length <= 8));
    assert.deepEqual(night.raids.map((r) => r.effort.name), ["Locked in", "Steady", "Casual"]);
    assert.equal(night.raids[2].optional, true);
    const big = json(BIG);
    assert.equal(big.attendance.length, 3);
    for (const raid of big.attendance) assert.deepEqual(raid.snapshots.map((s) => s.at), raid.snapshots.map((s) => s.at).sort((a, b) => a - b));
    // A disconnect: online false, then online again, in the first raid.
    const states = big.attendance[0].snapshots.map((s) => s.members.find((m) => m.name === "Fenn Ashdown").online);
    assert.deepEqual(states, [true, true, true, false, false, true, true]);
    // Standby are never in the snapshots.
    for (const raid of big.attendance) for (const g of raid.standby ?? []) assert.ok(raid.snapshots.every((s) => s.members.every((m) => m.guid !== g)));
    assert.ok(big.loot.some((l) => !l.winner.guid), "a winner known by name only");
    assert.ok(big.loot.some((l) => l.how === "trade") && big.loot.some((l) => l.how === "disenchant"));
    assert.deepEqual(Object.keys(json("export-empty")).sort(), ["kind", "meta", "v"]);
  });
});

describe("a string that must fail", () => {
  const good = text("import-night").trim();
  const fails = (s, error, reader = "addon") => {
    const got = readString(s, reader);
    assert.equal(got.ok, false, `${error}: ${s.slice(0, 40)}`);
    assert.equal(got.error, error);
    assert.ok(got.says);
    return got;
  };

  it("is not ours: another prefix, another case, nothing, or words", () => {
    fails("", "not-ours");
    fails("Vex, Kael", "not-ours");
    fails(good.replace("GG1:", "!Gargul:"), "not-ours");
    fails(good.replace("GG1:", "gg1:"), "not-ours");
    fails(good.replace("GG1:", "GG2:"), "not-ours");
    fails(good.slice(1), "not-ours");
  });

  it("is cut short", () => {
    for (const cut of [8, 12, 40, 200, good.length - 10]) fails(good.slice(0, good.length - cut), "bad-zlib");
    for (const keep of [10, 40, 100]) fails(good.slice(0, keep), "bad-zlib");
    assert.equal(fails("GG1:", "bad-text").says.length > 0, true);
  });

  it("has a mistyped character", () => {
    const big = text(BIG).trim();
    for (const at of [20, 60, 200, 500, 1000, 1500, big.length - 30]) {
      const was = big[at];
      for (const now of [was === "A" ? "B" : "A", "/", "z"].filter((c) => c !== was)) fails(big.slice(0, at) + now + big.slice(at + 1), "bad-zlib", "site");
    }
    for (const at of [30, 400, good.length - 30]) fails(good.slice(0, at) + (good[at] === "Q" ? "R" : "Q") + good.slice(at + 1), "bad-zlib");
  });

  it("has a character that isn't standard base64, or padding in the wrong place", () => {
    fails(good.slice(0, 40) + "-" + good.slice(41), "bad-text");
    fails(good.slice(0, 40) + "_" + good.slice(41), "bad-text");
    fails(good.slice(0, 40) + "$" + good.slice(41), "bad-text");
    fails(good.slice(0, 40) + "=" + good.slice(41), "bad-text");
    fails(`${good}====`, "bad-text");
    fails(good + "A", "bad-text");
  });

  it("is not a zlib stream: raw deflate or gzip", () => {
    const body = Buffer.from(JSON.stringify(json("import-night")));
    fails(pack(deflateRawSync(body)), "bad-zlib");
    fails(pack(gzipSync(body)), "bad-zlib");
    assert.equal(readString(pack(deflateSync(body)), "addon").ok, true);
    assert.throws(() => inflateSync(deflateRawSync(body)));
  });

  it("is not UTF-8 JSON of one object", () => {
    fails(pack(deflateSync(Buffer.from("not json"))), "bad-json");
    fails(pack(deflateSync(Buffer.from("[1,2]"))), "bad-json");
    fails(pack(deflateSync(Buffer.from("3"))), "bad-json");
    fails(pack(deflateSync(Buffer.from('{"v":1,"kind":"import","meta":{},"x":"\xff"}', "latin1"))), "bad-json");
  });

  it("lacks v, kind or meta, or has them wrong", () => {
    const make = (o) => pack(deflateSync(Buffer.from(JSON.stringify(o))));
    const ok = { v: 1, kind: "import", meta: {} };
    fails(make({ kind: "import", meta: {} }), "malformed");
    fails(make({ ...ok, v: "1" }), "malformed");
    fails(make({ ...ok, v: 0 }), "malformed");
    fails(make({ ...ok, v: 1.5 }), "malformed");
    fails(make({ ...ok, kind: "other" }), "malformed");
    fails(make({ v: 1, kind: "import" }), "malformed");
    fails(make({ ...ok, meta: [] }), "malformed");
    assert.equal(readString(make(ok), "addon").ok, true);
  });

  it("has v 2: the addon says to update, the site says it's behind", () => {
    const newer = (o) => encode({ ...clone(o), v: 2 });
    const importV2 = fails(newer(json("import-night")), "newer", "addon");
    assert.equal(importV2.says, "Update the addon");
    const exportV2 = fails(newer(json(BIG)), "newer", "site");
    assert.equal(exportV2.says, "The site is behind");
    // Even when v 2 has changed everything else.
    assert.equal(fails(encode({ v: 2, shape: "new" }), "newer").says, "Update the addon");
    // A newer v is refused before the way round is looked at.
    assert.equal(fails(newer(json("import-night")), "newer", "site").says, "The site is behind");
    assert.deepEqual(validate({ ...json("import-night"), v: 2 }).slice(0, 1), ["$.v: is not 1"]);
  });

  it("is too big: past 1 MiB unpacked, or too long as text", () => {
    const frame = { v: 1, kind: "import", meta: {}, pad: "" };
    const overhead = Buffer.byteLength(JSON.stringify(frame));
    const sized = (bytes) => encode({ ...frame, pad: "x".repeat(bytes - overhead) });
    // JSON compresses to almost nothing, so these are short strings that unpack huge.
    assert.ok(sized(MAX_JSON).length < 4000);
    assert.equal(decode(sized(MAX_JSON)).ok, true, "exactly 1 MiB reads");
    fails(sized(MAX_JSON + 1), "too-big");
    fails(sized(8 * MAX_JSON), "too-big");
    assert.equal(fails(`GG1:${"A".repeat(MAX_TEXT)}`, "too-long").error, "too-long");
    fails(`GG1:${"A".repeat(MAX_TEXT - 4)}`, "bad-zlib");
  });
});

describe("a string that must read", () => {
  const good = text("import-night").trim();

  it("has line breaks, spaces, or a surrounding newline", () => {
    const wrapped = good.slice(0, 4) + good.slice(4).replace(/(.{60})/g, "$1\n");
    assert.deepEqual(readString(`  ${wrapped}\r\n`, "addon").value, json("import-night"));
    assert.deepEqual(readString(`${good.slice(0, 30)} \t ${good.slice(30)}`, "addon").value, json("import-night"));
  });

  it("lost its padding", () => {
    assert.deepEqual(readString(good.replace(/=+$/, ""), "addon").value, json("import-night"));
  });

  it("holds fields nobody knows, at any depth, and null for a field with no value", () => {
    const o = clone(json("import-night"));
    o.future = { a: 1 };
    o.meta.something = [1, 2];
    o.raids[0].picks[0].talents = "x";
    o.raids[0].loot.items[0].tier = 5;
    o.people[0].chars[0].guid = null;
    o.raids[0].effort.hint = "x";
    o.raids[1].optional = null;
    assert.equal(readString(encode(o), "addon").ok, true);
    assert.deepEqual(validate(o), []);
    const e = clone(json(BIG));
    e.attendance[0].future = true;
    e.attendance[0].snapshots[0].members[0].role = "tank";
    e.loot[0].note = null;
    e.loot[0].quality = null;
    e.pugs[0].cls = null;
    e.meta.extra = "x";
    assert.deepEqual(validate(e), []);
  });

  it("is an import with a from nobody knows", () => {
    const o = clone(json("import-priorities"));
    o.meta.from = "tomorrow";
    delete o.raids;
    assert.deepEqual(validate(o), []);
  });
});

describe("the validator", () => {
  const without = (name, path) => {
    const o = clone(json(name));
    const keys = path.split(".");
    let at = o;
    for (const k of keys.slice(0, -1)) at = at[/^\d+$/.test(k) ? Number(k) : k];
    delete at[keys.at(-1)];
    return o;
  };
  const setting = (name, path, value) => {
    const o = clone(json(name));
    const keys = path.split(".");
    let at = o;
    for (const k of keys.slice(0, -1)) at = at[/^\d+$/.test(k) ? Number(k) : k];
    at[keys.at(-1)] = value;
    return o;
  };
  const problem = (o, part) => assert.ok(validate(o).some((e) => e.includes(part)), `${part} in ${JSON.stringify(validate(o))}`);

  it("wants every required top-level and meta field", () => {
    for (const [name, field] of [["import-night", "site"], ["import-night", "made"], ["import-night", "latest"], ["import-night", "from"], ["export-night", "id"], ["export-night", "made"], ["export-night", "addon"], ["export-night", "client"], ["export-night", "by"]])
      problem(without(name, `meta.${field}`), `$.meta.${field}: is required`);
    problem(without("export-empty", "meta"), "$.meta: is required");
    problem(without("export-empty", "kind"), "$.kind");
    problem(setting("export-empty", "meta.made", 1.5), "$.meta.made");
    problem(setting("export-empty", "meta.made", "1796864400000"), "$.meta.made");
    problem(setting("export-empty", "meta.id", "has space"), "$.meta.id");
    problem(setting("export-empty", "meta.client.build", "70532"), "$.meta.client.build");
    problem(setting("import-night", "meta.latest", "new"), "$.meta.latest");
  });

  it("wants each import's own parts", () => {
    problem(without("import-priorities", "raids"), "$.raids: is required");
    problem(without("import-priorities", "people"), "$.people: is required");
    problem(without("import-priorities", "guild"), "$.guild: is required");
    problem(without("import-priorities", "raids.0.zone"), "$.raids[0].zone: is required");
    problem(without("import-priorities", "raids.0.loot"), "$.raids[0].loot: is required");
    problem(without("import-night-loot", "night"), "$.night: is required");
    problem(without("import-night-loot", "raids.0.loot"), "loot: is required");
    problem(without("import-night-assignments", "raids.0.assignments"), "assignments: is required");
    problem(setting("import-night", "raids", []), "needs at least 1");
    problem(without("import-night", "raids.0.name"), "$.raids[0].name: is required");
    problem(without("import-night", "people.0.chars"), "chars: is required");
  });

  it("checks the shape of a night's raids", () => {
    problem(setting("import-night", "raids.0.picks.0.p", 99), "names a person who isn't in people");
    problem(setting("import-night", "raids.0.groups", [[1], [2], [3], [4], [5], [6], [7], [8], [9]]), "more than 8 subgroups");
    problem(setting("import-night", "raids.0.bench", [99]), "isn't in people");
    problem(setting("import-night", "raids.0.effort.expects", ["tea"]), "is not one of flask");
    problem(setting("import-night", "raids.0.size", 25.5), "size");
    problem(setting("import-night", "raids.0.optional", "yes"), "optional");
    problem(setting("import-night", "raids.0.picks.0.guid", "Pet-0-1"), "guid");
    problem(setting("import-night", "raids.0.loot.items.0.key", false), "only ever true");
    problem(setting("import-night", "raids.0.loot.items.0.specs", [["mage"]]), "class:tab");
    problem(setting("import-night", "raids.0.loot.items.0.order", [[]]), "needs at least 1");
    problem(setting("import-night", "raids.0.loot.items.2.hard", 99), "isn't in people");
    problem(without("import-night", "raids.0.assignments.0.lists.0.slots.0.p"), "p: is required");
    assert.deepEqual(validate(setting("import-night", "raids.0.loot.items.2.hard", 0)), []);
  });

  it("wants every part of an export to have its fields", () => {
    problem(without(BIG, "attendance.0.zone"), "zone: is required");
    problem(without(BIG, "attendance.0.difficulty"), "difficulty: is required");
    problem(without(BIG, "attendance.0.snapshots.0.at"), "at: is required");
    problem(setting(BIG, "attendance.0.snapshots.0.why", "now"), "why");
    problem(without(BIG, "attendance.0.snapshots.1.encounter"), "encounter: is required");
    problem(setting(BIG, "attendance.0.snapshots", []), "needs at least 1");
    problem(without(BIG, "attendance.0.snapshots.0.members.0.online"), "online: is required");
    problem(setting(BIG, "attendance.0.snapshots.0.members.0.guid", "Vex"), "guid");
    problem(setting(BIG, "attendance.0.snapshots.0.members.0.grp", 9), "grp");
    problem(setting(BIG, "attendance.0.snapshots.0.at", 1796856700000), "earlier than the snapshot before");
    problem(without(BIG, "loot.0.item"), "item: is required");
    problem(without(BIG, "loot.0.winner"), "winner: is required");
    problem(without(BIG, "loot.0.winner.name"), "name: is required");
    problem(setting(BIG, "loot.0.how", "stolen"), "how");
    problem(setting(BIG, "loot.0.at", 1796847760500), "not a whole second");
    problem(setting(BIG, "loot.0.link", "item:1:0:0"), "another item's");
    problem(without(BIG, "pugs.0.name"), "name: is required");
    problem(without(BIG, "pugs.0.guid"), "guid: is required");
  });

  it("holds a loot key to the recipe", () => {
    problem(setting(BIG, "loot.0.dedupe", "L2|288101|Player-9101-0F00AA11|1796847760|90101|1"), "recipe");
    problem(setting(BIG, "loot.0.dedupe", "L1|288101|Player-9101-0F00AA11|1796847760|90101|0"), "recipe");
    problem(setting(BIG, "loot.1.dedupe", json(BIG).loot[0].dedupe), "repeats");
    // A later export may hold only the second of two like awards: n stays what it was, counted over all recorded.
    assert.deepEqual(validate(setting(BIG, "loot.0.dedupe", "L1|288101|Player-9101-0F00AA11|1796847760|90101|2")), []);
    const o = clone(json(BIG));
    o.loot = o.loot.filter((l) => l.dedupe.endsWith("|2") || !l.dedupe.includes("288110"));
    assert.deepEqual(validate(o), []);
  });
});

describe("the loot dedupe key", () => {
  it("is the same recipe in every fixture: L1, item, winner, seconds, encounter, n", () => {
    for (const name of exports_) {
      const loot = json(name).loot ?? [];
      assert.deepEqual(dedupeAll(loot), loot.map((l) => l.dedupe), name);
    }
    const loot = json(BIG).loot;
    assert.equal(loot[0].dedupe, "L1|288101|Player-9101-0F00AA11|1796847760|90101|1");
  });

  it("counts awards that match in everything else, and only those", () => {
    const keys = json(BIG).loot.map((l) => l.dedupe);
    const tokens = json(BIG).loot.filter((l) => l.item === 288110);
    assert.equal(tokens.length, 2);
    assert.equal(tokens[0].at, tokens[1].at);
    assert.deepEqual(tokens.map((l) => l.dedupe), [1, 2].map((n) => `L1|288110|Player-9101-0F00AA13|${tokens[0].at / 1000}|90101|${n}`));
    assert.equal(new Set(keys).size, keys.length);
    // The trade of the first item later is another award, with no boss: its encounter part is 0.
    const trade = json(BIG).loot.find((l) => l.how === "trade");
    assert.equal(trade.dedupe, `L1|288101|Player-9101-0F00AA17|${trade.at / 1000}|0|1`);
    assert.notEqual(trade.dedupe, json(BIG).loot[0].dedupe);
  });

  it("uses a tilde and the name exactly as given when there is no GUID", () => {
    const key = dedupeKey({ item: 288301, winner: { name: "Zed Thornwick" }, at: 1796852630000 }, 1);
    assert.equal(key, "L1|288301|~Zed Thornwick|1796852630|0|1");
    const named = json(BIG).loot.find((l) => !l.winner.guid);
    assert.equal(named.dedupe, `L1|288301|~Zed Thornwick|${named.at / 1000}|90301|1`);
    // No case change: the key differs for a different case.
    assert.notEqual(dedupeKey({ item: 1, winner: { name: "zed" }, at: 1000 }, 1), dedupeKey({ item: 1, winner: { name: "Zed" }, at: 1000 }, 1));
  });

  it("is not hashed, and short", () => {
    for (const l of json(BIG).loot) {
      assert.ok(l.dedupe.length <= 80);
      assert.match(l.dedupe, /^L1\|\d+\|(Player-\d+-[0-9A-F]+|~[^|]+)\|\d+\|\d+\|\d+$/);
    }
  });
});

describe("a long night", () => {
  // A 40-player roster, three raids of 100 snapshots, every fourth a pull: made-up names.
  let seed = 11;
  const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  const word = (n) => Array.from({ length: n }, () => "abcdefghijklmnopqrstuvwxyz"[Math.floor(rnd() * 26)]).join("");
  const hex = () => Array.from({ length: 8 }, () => "0123456789ABCDEF"[Math.floor(rnd() * 16)]).join("");
  const players = Array.from({ length: 40 }, (_, i) => ({ guid: `Player-9101-${hex()}`, name: `${word(5)} ${word(8)}`, cls: ["mage", "warrior", "priest", "rogue"][i % 4] }));
  const raid = (zone, count, churn) => ({
    id: `${players[0].guid}:${zone}:1796846700`,
    zone,
    difficulty: 9,
    size: 40,
    snapshots: Array.from({ length: count }, (_, k) => ({
      at: 1796846700000 + k * 300000,
      why: k === 0 ? "zonein" : k === count - 1 ? "leave" : k % 4 === 0 ? "pull" : "interval",
      ...(k > 0 && k < count - 1 && k % 4 === 0 ? { encounter: 1 + (k % 5) } : {}),
      members: players.map((p, i) => ({ ...p, grp: 1 + Math.floor(i / 5), online: !(churn && k % 3 === 0 && i === 5), ...(churn && k % 3 === 0 && i === 5 ? {} : { zone: "Test Hold" }) })),
    })),
  });
  const night = (count, churn) => ({
    v: 1,
    kind: "export",
    meta: { id: "mgq1k2zt.00000001", made: 1796864400000, addon: "0.1.0", client: { version: "1.60.1", build: 70532, interface: 16001 }, by: { guid: players[0].guid, name: players[0].name } },
    attendance: [raid(5011, count, churn), raid(5012, count, churn), raid(5013, count, churn)],
    loot: json(BIG).loot,
    pugs: json(BIG).pugs,
  });
  const snapshotsOf = (o) => (o.attendance ?? []).flatMap((r) => r.snapshots);

  it("fits as it is when it is short enough", () => {
    const o = night(40, false);
    assert.ok(Buffer.byteLength(JSON.stringify(o)) < WRITE_JSON);
    assert.equal(fit(o).length, 1);
    assert.deepEqual(decode(fit(o)[0]).value, o);
  });

  it("drops repeated interval snapshots first, then thins, and keeps every other kind", () => {
    const o = night(100, false);
    assert.ok(Buffer.byteLength(JSON.stringify(o)) > WRITE_JSON, "too long to send whole");
    const strings = fit(o);
    assert.equal(strings.length, 1);
    assert.ok(strings[0].length <= WRITE_TEXT);
    const got = decode(strings[0]).value;
    assert.ok(Buffer.byteLength(JSON.stringify(got)) <= WRITE_JSON);
    assert.deepEqual(validate(got), []);
    const not = (s) => s.why !== "interval";
    assert.deepEqual(snapshotsOf(got).filter(not), snapshotsOf(o).filter(not));
    assert.deepEqual(got.loot, o.loot);
    assert.deepEqual(got.pugs, o.pugs);
    // The roster never changed, so no interval snapshot added anything.
    assert.equal(snapshotsOf(got).filter((s) => s.why === "interval").length, 0);
  });

  it("thins interval snapshots that did change, oldest to newest evenly", () => {
    const o = night(100, true);
    const strings = fit(o);
    assert.equal(strings.length, 1);
    const got = decode(strings[0]).value;
    assert.deepEqual(validate(got), []);
    assert.ok(Buffer.byteLength(JSON.stringify(got)) <= WRITE_JSON);
    assert.ok(snapshotsOf(got).length < snapshotsOf(o).length);
    assert.deepEqual(snapshotsOf(got).filter((s) => s.why !== "interval"), snapshotsOf(o).filter((s) => s.why !== "interval"));
  });

  it("splits into one string for each raid, and one for loot and pugs, each readable alone", () => {
    const o = night(100, true);
    const strings = fit(o, 5000);
    assert.equal(strings.length, 4);
    const parts = strings.map((s) => readString(s, "site"));
    assert.ok(parts.every((p) => p.ok));
    assert.deepEqual(parts.map((p) => validate(p.value)), [[], [], [], []]);
    assert.equal(new Set(parts.map((p) => p.value.meta.id)).size, 4, "each has its own id");
    assert.deepEqual(parts.slice(0, 3).map((p) => p.value.attendance.map((r) => r.id)), o.attendance.map((r) => [r.id]));
    assert.equal(parts[3].value.attendance, undefined);
    assert.deepEqual(parts[3].value.loot, o.loot);
    assert.deepEqual(parts[3].value.pugs, o.pugs);
    assert.ok(parts.every((p) => p.value.meta.by.guid === o.meta.by.guid));
  });
});
