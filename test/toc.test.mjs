// The addon's TOC files (GuildGolem/): the three the Forever client may load, kept in step with each other, with the
// interface number from tools/interface.json, the ids of the two project pages, and the license the README promises a
// release carries. addons.test.mjs checks every addon's TOCs for files that exist; this checks what is particular to
// GuildGolem.
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, sep } from "node:path";
import { describe, it } from "node:test";

const ROOT = join(import.meta.dirname, "..");
const DIR = join(ROOT, "GuildGolem");
const read = (path) => readFileSync(join(ROOT, path), "utf8");
const INTERFACE = JSON.parse(read("tools/interface.json")).interface;

// docs/RESEARCH.md ("The client"): the client looks for <Addon>_Forever.toc or <Addon>_Camelot.toc, then a plain
// <Addon>.toc. The probe found Camelot loads (Oct 22), so all three ship; a _Mainline.toc is not needed.
const TOCS = ["GuildGolem.toc", "GuildGolem_Camelot.toc", "GuildGolem_Forever.toc"];

function parse(name) {
  const lines = read(`GuildGolem/${name}`).split(/\r?\n/);
  const fields = {};
  for (const line of lines) {
    const m = line.match(/^##\s*([A-Za-z0-9-]+)\s*:\s*(.*?)\s*$/);
    if (m) fields[m[1]] = m[2];
  }
  const files = lines.filter((l) => l.trim() && !l.startsWith("#")).map((l) => l.trim());
  return { fields, files };
}

describe("the TOC files", () => {
  it("are the three the Forever client may load, and no others", () => {
    const tocs = readdirSync(DIR).filter((f) => f.endsWith(".toc")).sort();
    assert.deepEqual(tocs, [...TOCS].sort());
  });

  it("have one interface number between them, the one in tools/interface.json", () => {
    assert.ok(Number.isInteger(INTERFACE) && INTERFACE > 0, "tools/interface.json holds the interface number");
    const numbers = TOCS.map((t) => parse(t).fields.Interface);
    assert.equal(new Set(numbers).size, 1, `the TOCs disagree on ## Interface: ${numbers.join(", ")}`);
    for (const t of TOCS) assert.equal(parse(t).fields.Interface, String(INTERFACE), `${t}: ## Interface`);
  });

  it("agree on everything else, and list the same files in the same order", () => {
    const first = parse(TOCS[0]);
    for (const t of TOCS.slice(1)) {
      const other = parse(t);
      assert.deepEqual(other.fields, first.fields, `${t} differs from ${TOCS[0]} in its ## lines`);
      assert.deepEqual(other.files, first.files, `${t} lists other files than ${TOCS[0]}`);
    }
  });

  it("name the addon, its author, its saved variables and the two project pages", () => {
    const { fields } = parse("GuildGolem.toc");
    assert.equal(fields.Title, "Guild Golem");
    assert.equal(fields.Author, "Guild Golem");
    assert.equal(fields.SavedVariables, "GuildGolemDB");
    assert.equal(fields.Version, "@project-version@", "the packager puts the release tag here");
    assert.match(fields.Notes, /^[A-Z].*\.$/, "Notes is plain sentences");
    assert.ok(fields.Notes.length > 40 && fields.Notes.length < 300);
    assert.equal(fields["X-Curse-Project-ID"], "1757198");
    assert.equal(fields["X-Wago-ID"], "v63QDLGb");
  });

  it("carry the same project ids as the release workflow and the listing", () => {
    const { fields } = parse("GuildGolem.toc");
    const workflow = read(".github/workflows/release.yml");
    assert.ok(workflow.includes(`-p ${fields["X-Curse-Project-ID"]} -a ${fields["X-Wago-ID"]}`), "release.yml packages for these ids");
    const listing = read("LISTING.md");
    assert.ok(listing.includes(`## X-Curse-Project-ID: ${fields["X-Curse-Project-ID"]}`));
    assert.ok(listing.includes(`## X-Wago-ID: ${fields["X-Wago-ID"]}`));
  });

  it("load the libraries first, then the core, with Main.lua last", () => {
    const { files } = parse("GuildGolem.toc");
    const index = (f) => files.indexOf(f);
    const libs = files.filter((f) => f.startsWith("Libs\\"));
    assert.deepEqual(files.slice(0, libs.length), libs, "Libs come first");
    assert.ok(index("Libs\\LibStub\\LibStub.lua") < index("Libs\\LibDeflate\\LibDeflate.lua"));
    assert.ok(index("Libs\\LibStub\\LibStub.lua") < index("Libs\\json\\json.lua"));
    assert.ok(index("Core\\Base64.lua") < index("Core\\Codec.lua"));
    assert.ok(index("Core\\ZlibSize.lua") < index("Core\\Codec.lua"));
    assert.equal(files.at(-1), "Main.lua", "Main.lua wires the rest and loads last");
  });

  it("list every Lua file of the addon, and each once", () => {
    const { files } = parse("GuildGolem.toc");
    assert.equal(new Set(files).size, files.length, "a file is listed twice");
    const onDisk = [];
    const walk = (dir) => {
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const path = join(dir, entry.name);
        if (entry.isDirectory()) walk(path);
        else if (entry.name.endsWith(".lua")) onDisk.push(path.slice(DIR.length + 1).split(sep).join("\\"));
      }
    };
    walk(DIR);
    assert.deepEqual([...files].sort(), onDisk.sort());
  });
});

describe("the license in the release folder", () => {
  it("is the same text as LICENSE.txt, since the README promises a release carries it", () => {
    assert.ok(existsSync(join(DIR, "LICENSE.txt")));
    assert.equal(read("GuildGolem/LICENSE.txt"), read("LICENSE.txt"));
  });

  it("is named by NOTICES.txt along with each library", () => {
    const notices = read("GuildGolem/NOTICES.txt");
    for (const word of ["LibStub", "LibDeflate", "json.lua", "LICENSE.txt"]) assert.ok(notices.includes(word), word);
  });
});
