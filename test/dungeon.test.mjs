// The scripted 5-man dungeon (test/lua/fixtures/dungeon.lua, run in fengari): recorded and exported only while the addon's
// test recording is on, and the export read by the reference validator.
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { createLua } from "./lua/run.mjs";
import { WRITE_JSON, WRITE_TEXT, decode, normalize, readString, validate } from "./contract-lib.mjs";

const play = (on) => {
  const lua = createLua();
  lua.runFile("test/lua/fixtures/dungeon.lua");
  const result = lua.call("DUNGEON.run", on);
  lua.close();
  return result;
};

describe("a 5-man dungeon with test recording off", () => {
  const off = play(false);
  it("records nothing and has nothing to export", () => {
    assert.deepEqual(off.raids, []);
    assert.equal(off.made, false);
    assert.equal(off.why, "nothing");
    assert.deepEqual(off.export, []);
  });
});

describe("a 5-man dungeon with test recording on", () => {
  const on = play(true);
  const exported = on.export.map((s) => {
    const got = readString(s, "site");
    assert.equal(got.ok, true, got.says);
    return got.value;
  });

  it("is exported as one string, within the writers' limits", () => {
    assert.equal(on.made, true);
    assert.equal(on.export.length, 1);
    assert.ok(on.export[0].length <= WRITE_TEXT);
    assert.ok(Buffer.byteLength(JSON.stringify(decode(on.export[0]).value)) <= WRITE_JSON);
  });

  it("validates under the reference validator", () => {
    assert.deepEqual(validate(exported[0]), []);
  });

  it("has one raid entry, marked as a test, with the pull, the wipe, the second pull and the kill", () => {
    const [raid] = exported[0].attendance;
    assert.equal(exported[0].attendance.length, 1);
    assert.equal(raid.test, true);
    assert.equal(raid.zone, 801);
    assert.equal(raid.name, "Cinder Hollow");
    assert.equal(raid.size, 5);
    assert.deepEqual(raid.snapshots.map((s) => s.why), ["zonein", "pull", "wipe", "pull", "kill", "leave"]);
    assert.deepEqual(raid.snapshots.map((s) => s.encounter ?? 0), [0, 9001, 9001, 9001, 9001, 0]);
    assert.ok(raid.snapshots.every((s) => s.members.length === 5 || s.why === "leave"));
    const wipe = raid.snapshots[2].members.find((m) => m.online === false);
    assert.ok(wipe && wipe.zone === undefined, "the disconnect shows");
  });

  it("is read by the reference as the same entry, the flag kept", () => {
    assert.equal(normalize(exported[0]).attendance[0].test, true);
  });
});
