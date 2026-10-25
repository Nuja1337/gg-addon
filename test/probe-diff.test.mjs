// tools/probe-diff.mjs: the table of what changed between two probe runs, and the promise that no real name, guild,
// realm or GUID reaches it. The two files in test/fixtures are made up, as are all the names in them.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";
import { diffProbes, parseSavedVariables } from "../tools/probe-diff.mjs";

const ROOT = join(import.meta.dirname, "..");
const BEFORE = join(import.meta.dirname, "fixtures", "probe-before.lua");
const AFTER = join(import.meta.dirname, "fixtures", "probe-after.lua");
const before = readFileSync(BEFORE, "utf8");
const after = readFileSync(AFTER, "utf8");

// Everything in the fixtures that would identify someone, in the parts a reader could recognise.
const SECRETS = [
  "Quillon", "Brackenmoor", "Thessaly", "Orrin", "Dorian", "Vexley", "Marwick", "Dunleavy",
  "Velvet", "Lanterns", "Fabled Hollow", "FabledHollow", "Hollow Annex",
  "Player-9101", "Player-9102", "Player-9103", "0F00AA11", "0F00CC33", "0F00DD44",
];

function assertClean(text) {
  for (const secret of SECRETS) assert.ok(!text.includes(secret), `"${secret}" is still in the output`);
}

describe("probe-diff", () => {
  const output = diffProbes(before, after, { labels: ["probe-before.lua", "probe-after.lua"] });

  it("reads the Lua escapes a saved file uses", () => {
    const B = String.fromCharCode(92); // a backslash, spelled out so the escapes below are Lua's, not JavaScript's
    const lua = `X = { ["a"] = "caf${B}195${B}169 ${B}124 ${B}"q${B}"${B}n", ["n"] = -5, "first", [2] = false }`;
    const value = parseSavedVariables(lua).X;
    assert.equal(value.a, 'café | "q"\n');
    assert.equal(value.n, -5);
    assert.equal(value["1"], "first");
    assert.equal(value["2"], false);
  });

  it("starts with the two runs' versions and builds", () => {
    assert.match(output, /\| Probe version \| 0\.1\.0 or earlier \| 0\.2\.0 \|/);
    assert.match(output, /\| Build \| 70532 \| 70999 \|/);
    assert.match(output, /\| Run began \| not recorded \| 2026-11-04 18:00:00 \|/);
  });

  it("counts the rows that differ", () => {
    assert.match(output, /\d+ rows differ: 4 changed, 6 only in the second file, 3 only in the first\./);
  });

  it("prints one table per section that changed, and none for a section that did not", () => {
    const headings = [...output.matchAll(/^## (.+)$/gm)].map((m) => m[1]);
    assert.deepEqual(headings, ["addon messages", "client", "combat logging", "group", "loot", "loot history", "player"]);
    assert.ok(!output.includes("## time"));
    assert.ok(!output.includes("## saved variables"));
  });

  it("shows a changed row with both values, and a missing one as not in the run", () => {
    assert.match(output, /\| functions missing \| CanViewOfficerNote \| none \|/);
    assert.match(output, /\| LoggingCombat\(\) read @ Fabled Square\\|none \| _not in this run_ \| false \|/);
  });

  it("lines up the same event when only the clock time in its key differs", () => {
    assert.match(output, /\| your roll won \| .*88\) \| .*91\) \|/);
    assert.ok(!output.includes("20:15:05") && !output.includes("21:40:11"));
  });

  it("leaves out the clock readings that differ in every run", () => {
    assert.ok(!output.includes("server time"));
    assert.ok(!output.includes("times loaded"));
  });

  it("replaces every name, guild, realm and GUID with a placeholder", () => {
    assertClean(output);
    assert.match(output, /Player-S1-1/);
    assert.match(output, /Player-S2-\d/);
    assert.match(output, /"Player\d"/);
    assert.match(output, /Guild1/);
    assert.match(output, /Realm\d/);
  });

  it("gives the same name the same placeholder in both files and every table", () => {
    // The made-up friend appears as a whisper target, a loot winner and a master looter.
    const friend = /Player(\d+) sent 50 on PARTY/.exec(output)[1];
    assert.match(output, new RegExp(`"name"="Player${friend}", "second"="Player${friend}"`));
    assert.ok(output.includes(`"name"=("Player${friend}", "Player${friend}")`));
  });

  it("keeps the unchanged rows out, unless asked, and hides names there too", () => {
    assert.ok(!output.includes("| prefix registered |"));
    const everything = diffProbes(before, after, { all: true });
    assert.match(everything, /\| prefix registered \| true \| true \|/);
    assertClean(everything);
  });

  it("replaces one more name given on the command line", () => {
    const extra = diffProbes(before, after, { names: ["Lantern Staff"] });
    assert.ok(!extra.includes("Lantern Staff"));
    assert.match(extra, /\[Player\d\]/);
  });

  it("removes a folder on the owner's PC", () => {
    const B = String.fromCharCode(92);
    const inLua = `C:${B}${B}Users${B}${B}Someone${B}${B}Games${B}${B}Addon.lua:12`; // as a saved file writes the backslashes
    const withPath = after.replace('["text"] = "none"', `["text"] = "error: ${inLua}"`);
    assert.notEqual(withPath, after);
    const text = diffProbes(before, withPath);
    assert.ok(!text.includes("Someone") && !text.includes("Games"));
    assert.match(text, /\| functions missing \| CanViewOfficerNote \| error: <path>/);
  });

  it("gives the same text every time", () => {
    assert.equal(diffProbes(before, after, { labels: ["probe-before.lua", "probe-after.lua"] }), output);
  });

  it("says when nothing differs", () => {
    assert.match(diffProbes(after, after), /Nothing differs\./);
  });

  it("refuses a file that is not a saved probe", () => {
    assert.throws(() => diffProbes("x = 1", after), /no GuildGolemProbeDB table/);
    assert.throws(() => diffProbes("this is not lua (", after), /not a Lua saved variables file/);
  });

  it("runs from the command line", () => {
    const printed = execFileSync(process.execPath, [join(ROOT, "tools", "probe-diff.mjs"), BEFORE, AFTER], { encoding: "utf8" });
    assert.match(printed, /^# Probe comparison/);
    assert.match(printed, /\| File \| probe-before\.lua \| probe-after\.lua \|/);
    assertClean(printed);
  });
});
