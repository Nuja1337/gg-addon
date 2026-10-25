// A scripted raid night through the addon (test/lua/fixtures/night.lua, run in fengari), and the string it exports read by the
// reference code: it validates under the contract, it is under the writers' limits, a second export holds nothing new, the
// strings pasted twice join into the same attendance, and the outbox is still there in the next session.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { createLua } from "./lua/run.mjs";
import { WRITE_JSON, WRITE_TEXT, decode, fit, presentIn, readString, runIsOpen, runsOf, upsertAttendance, validate } from "./contract-lib.mjs";

const lua = createLua();
lua.runFile("test/lua/fixtures/night.lua");
const night = lua.call("NIGHT.run");
const strings = night.export.map((e) => e.text);
const exported = strings.map((s) => {
  const got = readString(s, "site");
  assert.equal(got.ok, true, got.says);
  return got.value;
});
const snapshotsOf = (o) => o.attendance.flatMap((r) => r.snapshots);

describe("the scripted night's export", () => {
  it("is made, and is one string", (t) => {
    assert.equal(night.ok, true, night.why);
    assert.equal(strings.length, 1);
    const o = exported[0];
    t.diagnostic(`${snapshotsOf(o).length} snapshots in ${o.attendance.length} raids, ${strings[0].length} characters, ${Buffer.byteLength(JSON.stringify(o))} bytes of JSON, ${night.minutes} minutes played`);
    assert.equal(o.attendance.length, 3);
    assert.equal(snapshotsOf(o).length, 37);
  });

  it("validates under the reference validator", () => {
    for (const o of exported) assert.deepEqual(validate(o), []);
  });

  it("is under both writer limits", () => {
    for (const [i, s] of strings.entries()) {
      assert.ok(s.length <= WRITE_TEXT, `${s.length} characters`);
      assert.ok(Buffer.byteLength(JSON.stringify(exported[i])) <= WRITE_JSON);
    }
  });

  it("is already what the reference `fit` would make of it: one string, nothing cut", () => {
    const again = fit(exported[0]);
    assert.equal(again.length, 1);
    assert.deepEqual(decode(again[0]).value, exported[0]);
  });

  it("says who recorded it, on which client and for which guild and night", () => {
    const { meta } = exported[0];
    assert.match(meta.id, /^[0-9a-z]+\.[0-9a-f]{8}$/);
    assert.equal(meta.made, night.startMs + 235 * 60_000);
    assert.deepEqual(meta.by, { guid: night.people.recorder, name: "Rhona Tester" });
    assert.deepEqual(meta.client, { version: "1.60.1", build: 70532, interface: 16001, locale: "enUS" });
    assert.equal(meta.realm, "Classic Beta PvP");
    assert.equal(meta.guild, "abcd2345");
    assert.equal(meta.guildName, "Ashen Wardens");
    assert.equal(meta.night, "efgh6789");
    assert.equal(meta.skew, 0);
    assert.match(meta.addon, /^\d+\.\d+\.\d+(-[a-z0-9.]+)?$/);
  });

  it("has the three raids, each opened by a zone-in and closed by a leave, with the night's handle", () => {
    const raids = exported[0].attendance;
    assert.deepEqual(raids.map((r) => r.zone), [5011, 5012, 5013]);
    assert.deepEqual(raids.map((r) => r.name), ["Ember Vault", "Cinder Spire", "Glass Foundry"]);
    for (const r of raids) {
      assert.equal(r.night, "efgh6789");
      assert.equal(r.size, 40);
      assert.equal(r.difficulty, 9);
      assert.equal(r.leader, night.people.recorder);
      assert.equal(r.snapshots[0].why, "zonein");
      assert.equal(r.snapshots.at(-1).why, "leave");
      assert.match(r.id, new RegExp(`^${night.people.recorder}:${r.zone}:\\d+$`));
      assert.equal(Number(r.id.split(":")[2]) * 1000, r.snapshots[0].at, "the id names the first snapshot's second");
      assert.ok(r.snapshots.every((s, i, all) => i === 0 || s.at > all[i - 1].at));
      assert.ok(r.snapshots.every((s) => s.at % 1000 === 0));
    }
    assert.equal(raids[0].lockout, 770011);
    assert.equal(runIsOpen(raids.map((raid) => ({ raid }))), false, "a leave closes the run");
  });

  it("keeps a pull for every boss with its id, and a kill or a wipe after it", () => {
    const first = exported[0].attendance[0];
    const fights = first.snapshots.filter((s) => s.encounter).map((s) => `${s.why}:${s.encounter}`);
    assert.deepEqual(fights, ["pull:1101", "wipe:1101", "pull:1101", "kill:1101", "pull:1102", "kill:1102", "pull:1103", "wipe:1103", "pull:1103", "kill:1103"]);
  });

  it("shows the disconnect and the reconnect, the early leaver and the pug", () => {
    const [first, second, third] = exported[0].attendance;
    const member = (r, guid) => r.snapshots.map((s) => s.members.find((m) => m.guid === guid));
    const d = member(first, night.people.disconnecter);
    const offline = d.findIndex((m) => m && m.online === false);
    assert.ok(offline > 0 && d[offline].zone === undefined, "offline, with no zone");
    assert.ok(d.slice(offline).some((m) => m?.online === true), "and back");

    const l = member(first, night.people.leaver);
    assert.ok(l[0] && !l.at(-1), "present at zone-in, gone at the end");
    assert.ok([second, third].every((r) => member(r, night.people.leaver).every((m) => !m)));

    assert.ok(member(first, night.people.pug)[0] && member(second, night.people.pug)[0]);
    assert.ok(member(third, night.people.pug).every((m) => !m));
    assert.deepEqual(exported[0].pugs.map((p) => p.guid), [night.people.pug]);
    assert.equal(exported[0].pugs[0].at, first.snapshots[0].at);
  });

  it("names the bench as standby in the raid the plan benched them in, and not in any snapshot", () => {
    const [first, second, third] = exported[0].attendance;
    assert.deepEqual(first.standby.map((p) => p.guid), night.people.benched);
    assert.deepEqual(first.standby.map((p) => p.name), ["Ottoline Vale", "Wren Hollis"]);
    assert.equal(second.standby, undefined);
    assert.equal(third.standby, undefined);
    const inSnapshots = new Set(snapshotsOf(exported[0]).flatMap((s) => s.members.map((m) => m.guid)));
    for (const g of night.people.benched) assert.ok(!inSnapshots.has(g));
    // The contract counts the bench as there.
    const run = [{ by: night.people.recorder, raid: first }];
    for (const g of night.people.benched) assert.ok(presentIn(run).has(g));
  });

  it("holds no loot: that is M4", () => {
    assert.equal(exported[0].loot, undefined);
  });
});

describe("after the first export", () => {
  it("a second export holds nothing new, and adds nothing to the outbox", () => {
    assert.equal(night.secondMade, false);
    assert.equal(night.secondWhy, "nothing");
    assert.equal(night.outboxAfterSecond, 1);
  });

  it("an export of everything is the same attendance, so pasting both adds nothing the first did not", () => {
    assert.equal(night.allTexts.length, 1);
    const all = readString(night.allTexts[0], "site").value;
    assert.deepEqual(validate(all), []);
    assert.notEqual(all.meta.id, exported[0].meta.id);
    const store = upsertAttendance(upsertAttendance(new Map(), exported[0]), all);
    const once = upsertAttendance(new Map(), exported[0]);
    assert.equal(store.size, 3);
    for (const [key, entry] of once) assert.deepEqual(store.get(key).raid.snapshots, entry.raid.snapshots);
  });

  it("the three raids are three runs, not one", () => {
    const runs = runsOf(exported[0].attendance.map((raid) => ({ by: exported[0].meta.by.guid, raid })));
    assert.equal(runs.length, 3, "a recorder's own entries are never joined");
  });
});

describe("the next session", () => {
  // Logout writes the saved variables; a new Lua state reads that file as the game would at the next login.
  it("finds the outbox as it was, and exports nothing again", () => {
    lua.call("WOW.logout");
    const file = lua.get("WOW.savedFile");
    assert.match(file, /^GuildGolemDB = \{/);

    const next = createLua();
    next.call("WOW.declareSavedVariables", "GuildGolemDB");
    next.call("WOW.readSavedFile", file);
    next.run(`WOW.loadAddon("GuildGolem"); WOW.login(true); return true`);
    const outbox = next.run(`local out = {}; for i, e in ipairs(GuildGolemDB.outbox) do out[i] = { id = e.id, text = e.text, pasted = e.pasted } end; return out`);
    assert.equal(outbox.length, 2);
    assert.equal(outbox[0].text, strings[0]);
    assert.equal(outbox[0].id, exported[0].meta.id);
    assert.equal(outbox[1].text, night.allTexts[0]);

    const again = next.run(`local made, why = GuildGolem.Export.make(); return { made = made ~= nil, why = why }`);
    assert.deepEqual(again, { made: false, why: "nothing" });
    const everything = next.run(`local made = GuildGolem.Export.make({ all = true }); return { snapshots = made.snapshots, raids = made.raids }`);
    assert.deepEqual(everything, { snapshots: 37, raids: 3 });
    next.close();
  });
});

describe("the same night, through the fixtures' own reader", () => {
  it("the strings of the fixtures and of the night are the same kind of thing", () => {
    const fixture = readFileSync(new URL("../contract/fixtures/export-night.gg1.txt", import.meta.url), "utf8");
    assert.equal(readString(fixture, "site").value.kind, exported[0].kind);
    assert.deepEqual(Object.keys(exported[0].meta).sort().filter((k) => !["guildName", "guild", "night", "skew"].includes(k)), ["addon", "client", "by", "id", "made", "realm"].sort());
  });
});
