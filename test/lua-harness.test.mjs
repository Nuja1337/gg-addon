// The Lua harness (test/lua/README.md): the Lua 5.1 shim, the game's stubs and a sample module, run in Node with
// fengari. The specs in test/lua/specs/ are Lua files that CI also runs on real Lua 5.1 (test/lua/run51.lua); each
// test in them is one test here. The last block drives the sample from Node, the way the addon's tests will.
import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { createRequire } from "node:module";
import { join } from "node:path";
import { describe, it } from "node:test";
import { createLua, LuaError, ROOT, runSpecs } from "./lua/run.mjs";

const require = createRequire(import.meta.url);
const luaparse = require("luaparse");

function luaFiles(dir) {
  return readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    return statSync(p).isDirectory() ? luaFiles(p) : p.endsWith(".lua") ? [p] : [];
  });
}

describe("the harness files are Lua 5.1", () => {
  for (const file of luaFiles(join(ROOT, "test", "lua"))) {
    it(file.slice(ROOT.length + 1).replaceAll("\\", "/"), () => {
      assert.doesNotThrow(() => luaparse.parse(readFileSync(file, "utf8"), { luaVersion: "5.1" }));
    });
  }
});

// Each spec file runs in a state of its own, and each of its tests is a test here.
const specs = readdirSync(join(ROOT, "test", "lua", "specs")).filter((f) => f.endsWith(".lua")).sort();
it("finds the specs", () => assert.ok(specs.length >= 3, `${specs.length} spec files`));

for (const spec of specs) {
  describe(`${spec} under fengari`, () => {
    let results;
    let loadError;
    try {
      results = runSpecs([`test/lua/specs/${spec}`]);
    } catch (error) {
      loadError = error;
    }
    if (loadError) {
      it("loads", () => { throw loadError; });
    } else {
      it("has tests", () => assert.ok(results.length > 0));
      for (const result of results) {
        it(result.name, () => assert.ok(result.ok, result.err));
      }
    }
  });
}

describe("driving the sample module from Node", () => {
  const SAMPLE = "test/lua/fixtures/sample.lua";

  function raidNight() {
    const lua = createLua();
    lua.call("WOW.declareSavedVariables", "SampleDB");
    lua.call("WOW.setPlayer", { name: "Rhona Tester", class: "MAGE", guid: "Player-9001-0000AAAA" });
    lua.call("WOW.setRoster", [
      { name: "Tolvar Ashgrove", class: "WARRIOR", guid: "Player-9001-0000BBBB" },
      { name: "Mirel Dawnwhisper", class: "PRIEST", guid: "Player-9002-0000CCCC", online: false },
    ]);
    return lua;
  }

  it("fires the event, advances the clock, fakes a logout and leaves the saved table", () => {
    const lua = raidNight();
    lua.call("WOW.loadAddon", "Sample", [SAMPLE]);
    lua.call("WOW.login");
    const start = lua.call("GetServerTime");

    assert.equal(lua.call("WOW.fire", "GROUP_ROSTER_UPDATE"), 1);
    assert.equal(lua.call("WOW.advance", 59), 0, "nothing is due before the timer");
    assert.equal(lua.call("WOW.advance", 1), 1, "the timer runs at 60 seconds");
    const saved = lua.call("WOW.logout");

    const members = [
      { guid: "Player-9001-0000AAAA", name: "Rhona Tester", class: "MAGE", group: 1, online: true },
      { guid: "Player-9001-0000BBBB", name: "Tolvar Ashgrove", class: "WARRIOR", group: 1, online: true },
      { guid: "Player-9002-0000CCCC", name: "Mirel Dawnwhisper", class: "PRIEST", group: 1, online: false },
    ];
    assert.deepEqual(saved, {
      SampleDB: {
        schema: 1,
        loads: 1,
        lastSeen: start + 60,
        snapshots: [
          { at: start, why: "roster", members },
          { at: start + 60, why: "interval", members },
        ],
      },
    });
    assert.match(lua.get("WOW.savedFile"), /^SampleDB = \{/);
    lua.close();
  });

  it("reads what the addon sent", () => {
    const lua = raidNight();
    lua.call("WOW.loadAddon", "Sample", [SAMPLE]);
    lua.call("WOW.fire", "GROUP_ROSTER_UPDATE");
    const outbox = lua.get("WOW.outbox");
    assert.equal(outbox.length, 1);
    assert.deepEqual({ ...outbox[0], at: undefined }, { prefix: "SAMPLE", text: "snapshot 1", chatType: "RAID", at: undefined });
    lua.close();
  });

  it("starts a session from a saved file written by an older one", () => {
    const lua = createLua();
    lua.call("WOW.declareSavedVariables", "SampleDB");
    lua.call("WOW.readSavedFile", 'SampleDB = { ["loads"] = 4, ["snapshots"] = {}, }\n');
    lua.call("WOW.loadAddon", "Sample", [SAMPLE]);
    assert.equal(lua.get("SampleDB.loads"), 5);
    lua.close();
  });

  it("shows a Lua error with its traceback", () => {
    const lua = createLua();
    assert.throws(() => lua.run("error('boom')"), (error) => error instanceof LuaError && /boom/.test(error.message) && /stack traceback/.test(error.message));
    assert.throws(() => lua.run("return +"), LuaError);
    lua.close();
  });

  it("gives each state its own globals", () => {
    const a = createLua();
    const b = createLua();
    a.run("Leaked = 1");
    assert.equal(a.get("Leaked"), 1);
    assert.equal(b.get("Leaked"), null);
    a.close();
    b.close();
  });
});
