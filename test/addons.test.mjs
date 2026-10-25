// Every addon folder here (GuildGolemProbe now, GuildGolem once built): nobody can run them outside the game, so each
// Lua file must at least be Lua 5.1 the game can read (luaparse, the language the game runs), and each TOC file must
// name the client's interface and only files that exist, and be named after its folder (the client loads no other).
// Moved with the addon from the site's repo (its test/node/addon-lua.spec.ts), Oct 22.
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { createRequire } from "node:module";
import { basename, join } from "node:path";
import { describe, it } from "node:test";

const require = createRequire(import.meta.url);
const luaparse = require("luaparse");

const ROOT = join(import.meta.dirname, "..");
// The client's interface number lives in one place, tools/interface.json.
const INTERFACE = String(JSON.parse(readFileSync(join(ROOT, "tools", "interface.json"), "utf8")).interface);

function files(dir) {
  return readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    return statSync(p).isDirectory() ? files(p) : [p];
  });
}

// An addon is a top-level folder holding a TOC named after itself.
const folders = readdirSync(ROOT).filter((f) => !f.startsWith(".") && f !== "node_modules" && statSync(join(ROOT, f)).isDirectory() && existsSync(join(ROOT, f, `${f}.toc`)));

it("finds the addons", () => assert.ok(folders.includes("GuildGolemProbe")));

for (const folder of folders) {
  describe(`the addon ${folder}`, () => {
    const dir = join(ROOT, folder);
    const all = files(dir);
    const tocs = all.filter((f) => f.endsWith(".toc"));

    it("has TOCs named after its folder", () => {
      for (const toc of tocs) assert.match(basename(toc), new RegExp(`^${folder}(_(Forever|Camelot|Mainline))?\\.toc$`));
    });

    for (const toc of tocs) {
      it(`${basename(toc)} names the client's interface and only files that exist`, () => {
        const lines = readFileSync(toc, "utf8").split(/\r?\n/);
        const iface = lines.find((l) => l.startsWith("## Interface:"));
        assert.ok(iface?.split(":")[1]?.split(",").map((s) => s.trim()).includes(INTERFACE), `${basename(toc)}: ## Interface: ${INTERFACE}`);
        const listed = lines.filter((l) => l.trim() && !l.startsWith("#"));
        assert.ok(listed.length > 0);
        for (const file of listed) assert.ok(existsSync(join(dir, file.trim().replace(/\\/g, "/"))), `${basename(toc)} lists ${file.trim()}, which isn't there`);
      });
    }

    for (const file of all.filter((f) => f.endsWith(".lua"))) {
      it(`${file.slice(dir.length + 1)} is Lua 5.1`, () => {
        assert.doesNotThrow(() => luaparse.parse(readFileSync(file, "utf8"), { luaVersion: "5.1" }));
      });
    }
  });
}
