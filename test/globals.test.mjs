// The globals check (test/lua/globals-lib.mjs): outside GuildGolem/Client.lua and GuildGolem/Libs/, the addon's Lua may
// read and write only Lua's own globals and its own names. The check is also tested on the fixtures in
// test/lua/fixtures/, so a check that stopped catching things would fail here.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";
import { checkedFiles, findGlobals, report } from "./lua/globals-lib.mjs";

const ROOT = join(import.meta.dirname, "..");
const fixture = (name) => readFileSync(join(import.meta.dirname, "lua", "fixtures", name), "utf8");
const names = (source) => findGlobals(source).map((g) => g.name);

describe("the globals check, on fixtures", () => {
  it("passes a module that uses only Lua's globals and the addon's names", () => {
    assert.deepEqual(findGlobals(fixture("globals_ok.lua")), []);
  });

  it("fails a module that reads GetRaidRosterInfo, and says which line", () => {
    const found = findGlobals(fixture("globals_bad.lua"));
    assert.deepEqual(found.map((g) => g.name), ["GetRaidRosterInfo"]);
    assert.equal(found[0].line, 7);
    assert.match(report(found), /GetRaidRosterInfo \(line 7\)/);
  });

  it("fails the sample module, which calls the game directly", () => {
    const found = names(fixture("sample.lua"));
    for (const name of ["CreateFrame", "GetServerTime", "C_Timer", "SlashCmdList", "SampleDB"]) assert.ok(found.includes(name), name);
    assert.ok(!found.includes("table") && !found.includes("print"));
  });
});

describe("the globals check, on small cases", () => {
  it("ignores a name in a comment or a string", () => {
    assert.deepEqual(names('-- CreateFrame\nlocal s = "GetTime()"\n--[[ UnitName ]]\nreturn s'), []);
  });

  it("does not count a local, a parameter or a loop variable that shadows a game function", () => {
    const source = [
      "local GetTime = function() return 1 end",
      "local function f(UnitName, ...) return UnitName, GetTime() end",
      "for IsInRaid, CreateFrame in pairs({}) do local _ = IsInRaid, CreateFrame end",
      "for GetLocale = 1, 2 do local _ = GetLocale end",
      "local t = {}",
      "function t.GetRealmName() end",
      "function t:GetGuildInfo() return GetTime end",
    ].join("\n");
    assert.deepEqual(names(source), []);
  });

  it("counts a global that is only written, and one that a function declares", () => {
    assert.deepEqual(names("Foo = 1\nfunction Bar() end"), ["Foo", "Bar"]);
  });

  it("counts a game function used inside a nested function", () => {
    assert.deepEqual(names("local function f()\n  return function() return GetTime() end\nend"), ["GetTime"]);
  });

  it("reports each name once, at its first use", () => {
    const found = findGlobals("local a = GetTime()\nlocal b = GetTime()");
    assert.deepEqual(found.map((g) => [g.name, g.line]), [["GetTime", 1]]);
  });

  it("allows the addon's namespace and saved variables", () => {
    assert.deepEqual(names("GuildGolem = GuildGolem or {}\nGuildGolemDB = GuildGolemDB or {}"), []);
  });

  it("refuses the ways round the check, with the reason", () => {
    for (const name of ["_G", "getfenv", "setfenv", "load", "loadstring", "require", "io", "dofile"]) {
      const found = findGlobals(`local x = ${name}`);
      assert.deepEqual(found.map((g) => g.name), [name]);
      assert.ok(found[0].why, `${name} has a reason`);
    }
  });

  it("allows what Lua keeps in the game", () => {
    const source = "return pcall, select, setmetatable, unpack, string.format, table.concat, math.floor, os.time, coroutine.wrap, debug.traceback, print";
    assert.deepEqual(names(source), []);
  });

  it("takes an allowlist as an option", () => {
    assert.deepEqual(findGlobals("return Foo", { allow: new Set(["Foo"]) }), []);
  });
});

describe("GuildGolem/ keeps game calls in Client.lua", () => {
  const dir = join(ROOT, "GuildGolem");
  const files = checkedFiles(dir);

  it("has Lua files to check, and Client.lua is the one left out", () => {
    assert.ok(files.length >= 7, `${files.length} files are checked`);
    for (const name of ["Core/Codec.lua", "Core/Store.lua", "Core/Import.lua", "Core/Events.lua", "Main.lua"]) assert.ok(files.includes(name), name);
    assert.ok(!files.includes("Client.lua") && !files.some((f) => f.startsWith("Libs/")));
  });

  it("finds a game call in a file that is not Client.lua, so the check is not a pass for every file", () => {
    assert.ok(findGlobals("local ok = GetRaidRosterInfo(1)").length > 0);
  });

  for (const file of files) {
    it(`${file} uses no game globals`, () => {
      const found = findGlobals(readFileSync(join(dir, file), "utf8"));
      assert.deepEqual(found, [], `${file} uses ${report(found)}; the game's functions belong in Client.lua`);
    });
  }
});
