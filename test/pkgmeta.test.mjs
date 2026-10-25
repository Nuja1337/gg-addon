// The release zip's file list, worked out from .pkgmeta the way the BigWigs packager works it out (release.yml runs
// the packager; it can't run here, since it needs bash, git, zip and a tag, so this mirrors its rules):
//   1. It walks the repository and skips every name that starts with a dot.
//   2. It skips every path .pkgmeta lists under "ignore" (a folder, or a file).
//   3. It copies what is left into .release/<package-as>/.
//   4. "move-folders" moves the contents of one folder to another, and everything else in the package folder stays.
//   5. The zip holds the package folder.
// The packager also adds a CHANGELOG.md it writes from the commits; that is not in this list.
// A top-level file nobody put in "ignore" would be moved into the addon's folder with the addon, so the test below
// that the zip holds nothing but GuildGolem/'s own files is the one that fails when someone adds a root file.
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";

const ROOT = join(import.meta.dirname, "..");
const PKGMETA = readFileSync(join(ROOT, ".pkgmeta"), "utf8");

// The packager reads .pkgmeta line by line (no YAML library): "key:" starts a section, "- item" is a list item,
// "from: to" under move-folders is a move. This reads the same three shapes.
function parsePkgmeta(text) {
  const meta = { ignore: [], moves: [], packageAs: null };
  let phase = null;
  for (const line of text.split(/\r?\n/)) {
    if (/^\s*#/.test(line) || !line.trim()) continue;
    const key = line.match(/^([^\s:][^:]*):\s*(.*)$/);
    if (key) {
      phase = key[1];
      if (phase === "package-as") meta.packageAs = key[2].trim();
      continue;
    }
    const item = line.match(/^\s+-\s+(.*?)\s*$/);
    if (item && phase === "ignore") meta.ignore.push(item[1].replace(/^['"]|['"]$/g, "").replace(/\/\*$/, ""));
    const move = line.match(/^\s+([^\s:]+):\s*(\S+)\s*$/);
    if (move && phase === "move-folders") meta.moves.push([move[1], move[2]]);
  }
  return meta;
}

function walk(dir = ROOT, prefix = "") {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    if (e.name.startsWith(".")) return []; // the packager prunes dot files and folders
    if (e.isDirectory()) return walk(join(dir, e.name), `${prefix}${e.name}/`);
    return [`${prefix}${e.name}`];
  });
}

// The files the zip would hold, as paths inside the zip.
function zipFiles() {
  const meta = parsePkgmeta(PKGMETA);
  const ignored = (path) => meta.ignore.some((i) => path === i || path.startsWith(`${i}/`));
  let files = walk().filter((f) => !ignored(f)).map((f) => `${meta.packageAs}/${f}`);
  for (const [from, to] of meta.moves) {
    files = files.map((f) => (f.startsWith(`${from}/`) ? `${to}/${f.slice(from.length + 1)}` : f));
  }
  return files.sort();
}

describe(".pkgmeta", () => {
  const meta = parsePkgmeta(PKGMETA);

  it("names the addon's folder and moves GuildGolem/ up into it", () => {
    assert.equal(meta.packageAs, "GuildGolem");
    assert.deepEqual(meta.moves, [["GuildGolem/GuildGolem", "GuildGolem"]]);
  });

  it("has no tab indentation, which the packager refuses", () => {
    assert.ok(!/^[ ]*\t/m.test(PKGMETA));
  });

  it("ignores every top-level file and folder but GuildGolem/ itself", () => {
    const top = readdirSync(ROOT).filter((n) => !n.startsWith("."));
    const missing = top.filter((n) => n !== "GuildGolem" && !meta.ignore.includes(n));
    assert.deepEqual(missing, [], "add these to ignore in .pkgmeta, or they ship inside the addon's folder");
    assert.ok(!meta.ignore.includes("GuildGolem"), "GuildGolem/ is the addon, not ignored");
  });
});

describe("the release zip's file list", () => {
  const files = zipFiles();
  const source = walk(join(ROOT, "GuildGolem"), "GuildGolem/");

  it("holds the GuildGolem/ folder alone, with exactly the files GuildGolem/ has", () => {
    assert.ok(files.every((f) => f.startsWith("GuildGolem/")), "every path is inside GuildGolem/");
    assert.deepEqual(files, source.sort());
  });

  it("has the license, the notices, every TOC and the libraries with their licenses", () => {
    for (const f of [
      "GuildGolem/LICENSE.txt",
      "GuildGolem/NOTICES.txt",
      "GuildGolem/GuildGolem.toc",
      "GuildGolem/GuildGolem_Camelot.toc",
      "GuildGolem/GuildGolem_Forever.toc",
      "GuildGolem/Libs/README.md",
      "GuildGolem/Libs/LibStub/LICENSE.txt",
      "GuildGolem/Libs/LibDeflate/LICENSE.txt",
      "GuildGolem/Libs/json/LICENSE",
    ]) {
      assert.ok(files.includes(f), `${f} is in the zip`);
    }
    const tocs = readdirSync(join(ROOT, "GuildGolem")).filter((n) => n.endsWith(".toc"));
    for (const t of tocs) assert.ok(files.includes(`GuildGolem/${t}`), `${t} is in the zip`);
  });

  it("holds no test, tool, doc, contract, probe or node file", () => {
    const folders = /^GuildGolem\/(test|tools|docs|contract|GuildGolemProbe|node_modules)\//;
    const names = /(^|\/)(package(-lock)?\.json|LISTING\.md|\.pkgmeta)$/;
    const stray = files.filter((f) => folders.test(f) || names.test(f) || /(_spec\.lua|\.test\.mjs)$/.test(f));
    assert.deepEqual(stray, []);
  });

  it("keeps each TOC's files in the zip", () => {
    for (const t of ["GuildGolem.toc", "GuildGolem_Camelot.toc", "GuildGolem_Forever.toc"]) {
      const lines = readFileSync(join(ROOT, "GuildGolem", t), "utf8").split(/\r?\n/);
      for (const l of lines.filter((x) => x.trim() && !x.startsWith("#"))) {
        assert.ok(files.includes(`GuildGolem/${l.trim().replaceAll("\\", "/")}`), `${t} lists ${l.trim()}`);
      }
    }
  });
});
