// Runs Lua files in a fresh Lua state in Node, with fengari (a Lua 5.3 VM written in JavaScript). Everything the addon
// will be tested with is loaded the same way as on real Lua 5.1 (test/lua/run51.lua): compat51.lua, wow.lua and
// harness.lua, then the files under test. README.md in this folder says what 5.3 cannot be made to do like 5.1.
//
//   const lua = createLua();                       // a fresh state with the shim, the stubs and the harness
//   lua.call("WOW.setRoster", [{ name: "Tolvar Ashgrove", class: "WARRIOR" }]);
//   lua.call("WOW.loadAddon", "Sample", ["test/lua/fixtures/sample.lua"]);
//   const saved = lua.call("WOW.logout");          // the saved variables as plain data
//
// Values cross as JSON-like data: nil is null, a Lua table with the keys 1..n only is an array, any other table is an
// object, and a function comes back as the string "<function>". JavaScript arrays and objects go in as tables.
import fengari from "fengari";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

export const ROOT = join(import.meta.dirname, "..", "..");

// Lua files, from the repository's root.
export const COMPAT = "test/lua/compat51.lua";
export const STUBS = "test/lua/wow.lua";
export const HARNESS = "test/lua/harness.lua";

const MAX_DEPTH = 32;

function push(L, value, depth = 0) {
  if (depth > MAX_DEPTH) throw new Error("lua.call: the value is nested too deep");
  if (value === null || value === undefined) return lua.lua_pushnil(L);
  switch (typeof value) {
    case "boolean":
      return lua.lua_pushboolean(L, value);
    case "number":
      // A whole number is a Lua integer, so %d and tostring behave as they would for a count the addon made.
      return Number.isSafeInteger(value) ? lua.lua_pushinteger(L, value) : lua.lua_pushnumber(L, value);
    case "string":
      return lua.lua_pushstring(L, to_luastring(value));
    case "object": {
      lua.lua_newtable(L);
      if (Array.isArray(value)) {
        value.forEach((v, i) => {
          push(L, v, depth + 1);
          lua.lua_rawseti(L, -2, i + 1);
        });
      } else {
        for (const [k, v] of Object.entries(value)) {
          push(L, v, depth + 1);
          lua.lua_setfield(L, -2, to_luastring(k));
        }
      }
      return;
    }
    default:
      throw new Error(`lua.call: cannot pass a ${typeof value} to Lua`);
  }
}

function pull(L, index, depth = 0) {
  if (depth > MAX_DEPTH) return "<too deep>";
  index = lua.lua_absindex(L, index);
  switch (lua.lua_type(L, index)) {
    case lua.LUA_TNIL:
    case lua.LUA_TNONE:
      return null;
    case lua.LUA_TBOOLEAN:
      return lua.lua_toboolean(L, index);
    case lua.LUA_TNUMBER:
      return lua.lua_tonumber(L, index);
    case lua.LUA_TSTRING:
      return to_jsstring(lua.lua_tolstring(L, index));
    case lua.LUA_TTABLE: {
      const entries = [];
      lua.lua_pushnil(L);
      while (lua.lua_next(L, index) !== 0) {
        // Keys are numbers or strings; copy the key before reading it, so lua_next's own key is left alone.
        lua.lua_pushvalue(L, -2);
        const key = lua.lua_type(L, -1) === lua.LUA_TNUMBER ? lua.lua_tonumber(L, -1) : pull(L, -1, depth + 1);
        lua.lua_pop(L, 1);
        entries.push([key, pull(L, -1, depth + 1)]);
        lua.lua_pop(L, 1);
      }
      const length = Number(lua.lua_rawlen(L, index));
      const isArray = entries.every(([k]) => Number.isInteger(k) && k >= 1 && k <= length) && entries.length === length;
      if (isArray) {
        const list = new Array(length);
        for (const [k, v] of entries) list[k - 1] = v;
        return list;
      }
      const object = {};
      for (const [k, v] of entries) object[String(k)] = v;
      return object;
    }
    default:
      return `<${to_jsstring(lua.lua_typename(L, lua.lua_type(L, index)))}>`;
  }
}

export class LuaError extends Error {}

export function createLua({ boot = true } = {}) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  // Errors come back with Lua's traceback.
  const traceback = (state) => {
    const message = lua.lua_tostring(state, 1);
    lauxlib.luaL_traceback(state, state, message === null ? to_luastring("(an error that is not text)") : message, 1);
    return 1;
  };

  // Runs a chunk of text with `args` and returns its first result as plain data.
  function execute(source, chunkName, args = []) {
    const bytes = to_luastring(source);
    const top = lua.lua_gettop(L);
    lua.lua_pushjsfunction(L, traceback);
    const handler = lua.lua_gettop(L);
    if (lauxlib.luaL_loadbuffer(L, bytes, bytes.length, to_luastring(chunkName)) !== lua.LUA_OK) {
      const message = to_jsstring(lua.lua_tostring(L, -1));
      lua.lua_settop(L, top);
      throw new LuaError(message);
    }
    for (const arg of args) push(L, arg);
    if (lua.lua_pcall(L, args.length, 1, handler) !== lua.LUA_OK) {
      const message = to_jsstring(lua.lua_tostring(L, -1));
      lua.lua_settop(L, top);
      throw new LuaError(message);
    }
    const result = pull(L, -1);
    lua.lua_settop(L, top);
    return result;
  }

  const state = {
    // Runs Lua text; `return x` gives x back as data.
    run(source, chunkName = "=run") {
      return execute(source, chunkName);
    },
    // Runs a file of the repository (a path from its root), under the name Lua shows in errors.
    runFile(path) {
      return execute(readFileSync(join(ROOT, path), "utf8"), `@${path}`);
    },
    // Calls the Lua function named by `path` (a global such as "WOW.fire") and returns its first result as data.
    call(path, ...args) {
      if (!/^[A-Za-z_][A-Za-z_0-9]*(\.[A-Za-z_][A-Za-z_0-9]*)*$/.test(path)) throw new Error(`lua.call: not a name: ${path}`);
      return execute(`local fn = ${path}; assert(type(fn) == "function", "${path} is not a function"); return fn(...)`, `=call ${path}`, args);
    },
    // Reads a global such as "WOW.saved" as data.
    get(path) {
      return execute(`return ${path}`, `=get ${path}`);
    },
    close() {
      lua.lua_close(L);
    },
  };

  if (boot) {
    execute(`GG_ROOT = ${JSON.stringify(ROOT.replaceAll("\\", "/"))}`, "=root");
    state.runFile(COMPAT);
    state.runFile(STUBS);
    state.runFile(HARNESS);
  }
  return state;
}

// Runs spec files (test/lua/specs/*.lua) in one fresh state and returns what the harness reports, one
// { name, ok, err } for each test.
export function runSpecs(files) {
  const state = createLua();
  try {
    for (const file of files) state.runFile(file);
    return state.call("T.run");
  } finally {
    state.close();
  }
}
