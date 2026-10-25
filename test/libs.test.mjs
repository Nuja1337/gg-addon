// The libraries in GuildGolem/Libs/: each file matches the checksum Libs/README.md records, each library keeps its
// license beside it, and the one change to json.lua is the marked block and nothing else.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";

const LIBS = join(import.meta.dirname, "..", "GuildGolem", "Libs");
const bytes = (path) => readFileSync(join(LIBS, path));
const sha = (buffer) => createHash("sha256").update(buffer).digest("hex");

// The two lists of checksums in the README: "## Checksums" and "## As published". Lines look like sha256sum's.
function checksums(heading) {
  const readme = readFileSync(join(LIBS, "README.md"), "utf8");
  const start = readme.indexOf(`## ${heading}`);
  assert.ok(start >= 0, `README.md has a "${heading}" section`);
  const next = readme.indexOf("\n## ", start + 1);
  const section = readme.slice(start, next < 0 ? undefined : next);
  const out = {};
  for (const m of section.matchAll(/^([0-9a-f]{64}) {2}(\S+)$/gm)) out[m[2]] = m[1];
  return out;
}

function allFiles(dir = LIBS, prefix = "") {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? allFiles(join(dir, e.name), `${prefix}${e.name}/`) : [`${prefix}${e.name}`],
  );
}

describe("GuildGolem/Libs", () => {
  const now = checksums("Checksums");
  const published = checksums("As published");

  it("has a checksum in the README for every file but the README, and none for a file that isn't there", () => {
    assert.deepEqual(Object.keys(now).sort(), allFiles().filter((f) => f !== "README.md").sort());
  });

  for (const [file, expected] of Object.entries(now)) {
    it(`${file} is the file the README names (SHA-256)`, () => {
      assert.equal(sha(bytes(file)), expected);
    });
  }

  it("keeps a license beside each library", () => {
    for (const lib of ["LibStub", "LibDeflate", "json"]) {
      const licenses = readdirSync(join(LIBS, lib)).filter((f) => /^LICENSE/.test(f));
      assert.ok(licenses.length > 0, `${lib} has a LICENSE file`);
    }
  });

  it("uses the licenses their authors published", () => {
    assert.match(bytes("LibDeflate/LICENSE.txt").toString("utf8"), /zlib License/);
    assert.match(bytes("json/LICENSE").toString("utf8"), /Permission is hereby granted, free of charge/);
    assert.match(bytes("LibStub/LICENSE.txt").toString("utf8"), /public domain/i);
  });

  it("changes nothing in LibStub or LibDeflate, and in json.lua only the marked block", () => {
    for (const file of ["LibStub/LibStub.lua", "LibDeflate/LibDeflate.lua", "LibDeflate/LICENSE.txt", "json/LICENSE"]) {
      assert.equal(sha(bytes(file)), published[file], `${file} is as published`);
    }
    const text = bytes("json/json.lua").toString("utf8");
    const begin = text.indexOf("-- BEGIN GUILD GOLEM CHANGE\n");
    const endMarker = "-- END GUILD GOLEM CHANGE\n\n";
    const end = text.indexOf(endMarker);
    assert.ok(begin > 0 && end > begin, "json.lua has the marked block");
    assert.equal(text.indexOf("-- BEGIN GUILD GOLEM CHANGE", begin + 1), -1, "and only one");
    const original = text.slice(0, begin) + text.slice(end + endMarker.length);
    assert.equal(sha(Buffer.from(original, "utf8")), published["json/json.lua"]);
  });

  it("says where each library came from", () => {
    const readme = readFileSync(join(LIBS, "README.md"), "utf8");
    for (const word of ["WoWUIDev/Ace3", "SafeteeWoW/LibDeflate", "rxi/json.lua", "1.0.2-release"]) assert.ok(readme.includes(word), word);
    assert.match(readme, /commit `[0-9a-f]{40}`/);
    assert.ok(existsSync(join(LIBS, "..", "NOTICES.txt")));
  });
});
