// The globals check. Only GuildGolem/Client.lua may call the game's functions (docs/PLAN.md), so every other file of
// the addon, apart from the libraries in GuildGolem/Libs/, may use only Lua's own globals and the addon's own names.
// A file that reaches for anything else (GetRaidRosterInfo, CreateFrame, C_Timer, a Blizzard constant) fails, and so
// does one that could reach it round the check (_G, getfenv, loadstring). It reads each file's syntax tree with
// luaparse, so a name in a comment or a string is not a use, and a local that shadows a global is not one either.
import { existsSync, readdirSync, statSync } from "node:fs";
import { createRequire } from "node:module";
import { join, relative } from "node:path";

const require = createRequire(import.meta.url);
const luaparse = require("luaparse");

// What Lua 5.1 provides and the game's copy of it keeps: the base functions, and the libraries. `os` and `debug` are
// whole here but the game keeps only part of them, so use what the game has (os.time, os.date, os.clock,
// debug.traceback); Client.lua is the one to wrap anything else.
export const LUA_GLOBALS = [
  "assert", "collectgarbage", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "print", "rawequal",
  "rawget", "rawset", "select", "setmetatable", "tonumber", "tostring", "type", "unpack", "xpcall", "_VERSION",
  "coroutine", "debug", "math", "os", "string", "table",
];

// The addon's own names: its shared namespace and its saved variables (the TOC's ## SavedVariables line), and
// LibStub, the loader of the libraries in Libs/ (the addon asks it for LibDeflate and json.lua; it is not a game
// function). Add one here when the addon makes another global; every file may use them.
export const ADDON_GLOBALS = ["GuildGolem", "GuildGolemDB", "LibStub"];

// Lua 5.1 globals that are left out on purpose. The game has no io, package, require or dofile, and the others let
// code look up a game function by name, which the check could not see.
export const FORBIDDEN = {
  _G: "reads any global by name, past this check",
  getfenv: "reads any global by name, past this check",
  setfenv: "changes which globals a function sees",
  load: "runs text as code, which could use any global",
  loadstring: "runs text as code, which could use any global",
  loadfile: "the game has no files to load",
  dofile: "the game has no files to load",
  require: "the game has no require",
  module: "the game has no module",
  package: "the game has no package",
  io: "the game has no io",
  gcinfo: "the game has collectgarbage",
};

export const DEFAULT_ALLOW = new Set([...LUA_GLOBALS, ...ADDON_GLOBALS]);

// The globals a file uses that are not allowed: a list of { name, line, why }, each name once, at its first use.
// A write counts as a use, since a global the addon makes is one more name to collide with the game's.
export function findGlobals(source, { allow = DEFAULT_ALLOW } = {}) {
  const tree = luaparse.parse(source, { luaVersion: "5.1", scope: true, locations: true });
  const found = [];
  for (const id of tree.globals) {
    if (allow.has(id.name)) continue;
    found.push({ name: id.name, line: id.loc.start.line, why: FORBIDDEN[id.name] });
  }
  return found;
}

// The Lua files of an addon folder that must stay clear of the game: every one except Client.lua and what is under
// Libs/. Paths are relative to `dir`, with forward slashes.
export function checkedFiles(dir) {
  const out = [];
  const walk = (folder) => {
    for (const name of readdirSync(folder)) {
      const path = join(folder, name);
      const rel = relative(dir, path).replaceAll("\\", "/");
      if (statSync(path).isDirectory()) {
        if (rel !== "Libs") walk(path);
      } else if (name.endsWith(".lua") && rel !== "Client.lua") {
        out.push(rel);
      }
    }
  };
  if (existsSync(dir)) walk(dir);
  return out.sort();
}

export function report(found) {
  return found.map((g) => `${g.name} (line ${g.line}${g.why ? `: ${g.why}` : ""})`).join(", ");
}
