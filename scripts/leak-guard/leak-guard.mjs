#!/usr/bin/env node
// leak-guard.mjs: fails when anything public carries an internal name.
//
// CANON: design-system scripts/leak-guard/leak-guard.mjs. Every public-facing repo (front-end, landing, docs, support,
// conversion-script, tracking-script) vendors a BYTE-IDENTICAL copy of this file, leak-denylist.enc.json and
// leak-allow.json under scripts/leak-guard/ (design-system pins the encoded list to the plain one). Plain node, no
// dependencies, no network, about a second per run.
//
// What it checks, in every text file under the paths given:
//   1. the denylist (leak-denylist.enc.json): project ids, instance names, console links, keys;
//   2. every host under tapper.ai that leak-allow.json (plus the repo's optional leak-allow.local.json) does not list.
//
//   3. with --check-deps: the repo's package.json files and lockfiles in the current directory never name the
//      internal-tools package (@tapperai/internal), whose tool switcher carries every internal link.
//
// Usage: node scripts/leak-guard/leak-guard.mjs [--check-deps] [--redact] [--quiet] <dir-or-file>...
//        node scripts/leak-guard/leak-guard.mjs --emit-enc     (canon only: plain denylist -> encoded list on stdout)
// --redact prints the rule id and position, never the matched text: use it wherever the log is public.
// Exit 0 clean, 1 a hit, 2 a usage error or nothing scanned.
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SKIP_DIRS = new Set([".git", "node_modules", ".next", ".turbo", ".cache"]);
const MAX_BYTES = 200 * 1024 * 1024;
// The guard's own data files hold the rules; scanning them would flag the rules themselves.
const SELF = new Set(["leak-guard.mjs", "leak-denylist.json", "leak-denylist.enc.json", "leak-allow.json", "leak-allow.local.json"]);

const args = process.argv.slice(2);
if (args.includes("--emit-enc")) {
  const plain = JSON.parse(readFileSync(join(HERE, "leak-denylist.json"), "utf8"));
  const enc = {
    _doc: "Encoded copy of design-system scripts/leak-guard/leak-denylist.json (base64 so a public repo does not publish the names it forbids). Never edit by hand: regenerate with --emit-enc in design-system and vendor it.",
    rules: plain.rules.map((r) => ({ id: r.id, b64: Buffer.from(r.pattern, "utf8").toString("base64") })),
  };
  process.stdout.write(JSON.stringify(enc, null, 2) + "\n");
  process.exit(0);
}
const checkDeps = args.includes("--check-deps");
const redact = args.includes("--redact");
const quiet = args.includes("--quiet");
const targets = args.filter((a) => !a.startsWith("--"));
if (targets.length === 0 && !checkDeps) {
  console.error("usage: leak-guard.mjs [--check-deps] [--redact] [--quiet] <dir-or-file>...");
  process.exit(2);
}

// --check-deps: package.json (every dependency field, overrides included) and the lockfiles of the current directory.
if (checkDeps) {
  const NAME = "@tapperai/internal";
  const bad = [];
  for (const f of ["package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock"]) {
    if (!existsSync(f)) continue;
    const text = readFileSync(f, "utf8");
    if (f === "package.json") {
      const pkg = JSON.parse(text);
      for (const k of ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies", "overrides", "resolutions"]) {
        if (pkg[k] && JSON.stringify(pkg[k]).includes(NAME)) bad.push(`${f}: ${k} names ${NAME}`);
      }
    } else if (new RegExp(NAME.replace("/", "\\/") + "(?![A-Za-z0-9_-])").test(text)) bad.push(`${f}: names ${NAME}`);
  }
  if (bad.length > 0) {
    console.error(`leak-guard: this repo is public-facing and must never depend on ${NAME} (its tool switcher lists every internal link):`);
    for (const b of bad) console.error("  " + b);
    process.exit(1);
  }
  if (!quiet) console.log(`leak-guard: no dependency on ${NAME}`);
  if (targets.length === 0) process.exit(0);
}

const readJson = (p) => JSON.parse(readFileSync(p, "utf8"));
const encFile = join(HERE, "leak-denylist.enc.json");
const rawRules = existsSync(encFile)
  ? readJson(encFile).rules.map((r) => ({ id: r.id, source: Buffer.from(r.b64, "base64").toString("utf8") }))
  : readJson(join(HERE, "leak-denylist.json")).rules.map((r) => ({ id: r.id, source: r.pattern }));
const rules = rawRules.map((r) => ({ id: r.id, re: new RegExp(r.source, "gi") }));

const allowHosts = [...readJson(join(HERE, "leak-allow.json")).hosts];
const local = join(HERE, "leak-allow.local.json");
if (existsSync(local)) allowHosts.push(...readJson(local).hosts);
const hostAllowed = (host) => allowHosts.some((a) => host === a.host || (a.subdomains && host.endsWith("." + a.host)));
const HOST_RE = /(?<![A-Za-z0-9-])((?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)*tapper\.ai)(?![A-Za-z0-9-])/gi;

function* walk(p) {
  const st = statSync(p);
  if (st.isDirectory()) {
    for (const name of readdirSync(p)) {
      if (SKIP_DIRS.has(name)) continue;
      yield* walk(join(p, name));
    }
  } else if (st.isFile()) yield p;
}

const hits = [];
let files = 0;
const lineCol = (text, index) => {
  let line = 1;
  let last = -1;
  for (let i = text.indexOf("\n"); i !== -1 && i < index; i = text.indexOf("\n", i + 1)) {
    line++;
    last = i;
  }
  return { line, col: index - last };
};
const context = (text, index, len) => text.slice(Math.max(0, index - 30), index + len + 30).replace(/\s+/g, " ");

for (const t of targets) {
  if (!existsSync(t)) {
    console.error(`leak-guard: ${t} does not exist`);
    process.exit(2);
  }
  for (const f of walk(t)) {
    if (SELF.has(f.split("/").pop()) && dirname(resolve(f)) === HERE) continue;
    const st = statSync(f);
    if (st.size > MAX_BYTES) continue;
    const buf = readFileSync(f);
    if (buf.includes(0)) continue; // binary
    files++;
    const text = buf.toString("utf8");
    for (const r of rules) {
      r.re.lastIndex = 0;
      for (let m = r.re.exec(text); m; m = r.re.exec(text)) {
        hits.push({ file: f, ...lineCol(text, m.index), rule: r.id, match: m[0], ctx: context(text, m.index, m[0].length) });
        if (m[0].length === 0) r.re.lastIndex++;
      }
    }
    HOST_RE.lastIndex = 0;
    for (let m = HOST_RE.exec(text); m; m = HOST_RE.exec(text)) {
      const host = m[1].toLowerCase();
      if (!hostAllowed(host)) hits.push({ file: f, ...lineCol(text, m.index), rule: "tapper-host-not-public", match: m[1], ctx: context(text, m.index, m[1].length) });
    }
  }
}

if (files === 0) {
  console.error("leak-guard: no text file was scanned (wrong path, or the build produced nothing)");
  process.exit(2);
}
if (hits.length === 0) {
  if (!quiet) console.log(`leak-guard: clean, ${files} files scanned`);
  process.exit(0);
}
const cwd = process.cwd();
console.error(`leak-guard: ${hits.length} internal name${hits.length === 1 ? "" : "s"} in public output (${files} files scanned)`);
for (const h of hits.slice(0, 200)) {
  const where = `${relative(cwd, resolve(h.file))}:${h.line}:${h.col}`;
  console.error(redact ? `  ${where}  [${h.rule}]` : `  ${where}  [${h.rule}]  ${h.match}   ...${h.ctx}...`);
}
if (hits.length > 200) console.error(`  ... and ${hits.length - 200} more`);
console.error("A hit is either a real leak (remove it) or a host that is public on purpose (add it to scripts/leak-guard/leak-allow.local.json).");
process.exit(1);
