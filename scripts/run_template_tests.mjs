#!/usr/bin/env node
// Local runner for the ___TESTS___ scenarios in template.tpl.
//
// WHY: GTM runs these scenarios only inside its web template editor, so CI had
// no way to execute them. This runner executes the template's sandboxed JS and
// every scenario in plain Node with the GTM semantics that matter for the
// failure class we shipped twice (2026-05-15 and 2026-06-27): a window API
// called on a path the template's permissions do not grant.
//
// PERMISSION SEMANTICS are copied from Google's own runtime, not guessed. The
// access_globals checker compiled into every gtm.js that carries it (read from
// live containers on 2026-09-28) is:
//
//   for (...) { k.read && e.push(key); k.write && f.push(key); k.execute && g.push(key) }
//   assert(p, op, path) { ... op === "execute" ? g.indexOf(path) > -1 ... ;
//                         throw "Prohibited " + op + " on global variable: " + path }
//
// i.e. an EXACT match on the full dotted path; a grant on `tapper` does not
// cover `tapper.init`. callInWindow asserts ("access_globals", "execute", path)
// before resolving the path, then calls the function with `this` bound to its
// parent object. As in GTM, MOCKED APIs skip the permission check
// (developers.google.com/tag-platform/tag-manager/templates/tests,
// "Limitations").
//
// This is an emulator, not GTM: it covers the APIs this template uses
// (injectScript, callInWindow, logToConsole) and the test APIs its scenarios
// use (mock, runCode, assertApi, assertThat, fail). A scenario that requires
// anything else fails loudly rather than passing vacuously.
//
// Usage: node scripts/run_template_tests.mjs [template.tpl]
// Pure Node, no dependencies. Exits non-zero on any failure.

import { readFileSync } from "node:fs";

const TPL = process.argv[2] || "template.tpl";
const content = readFileSync(TPL, "utf8").replace(/^﻿/, "");

function sections(text) {
  const parts = text.split(/^___([A-Z_]+)___$/m);
  const out = {};
  for (let i = 1; i < parts.length; i += 2) out[parts[i]] = parts[i + 1].trim();
  return out;
}

const S = sections(content);
const sandboxJs = S.SANDBOXED_JS_FOR_WEB_TEMPLATE;
if (!sandboxJs) throw new Error("no ___SANDBOXED_JS_FOR_WEB_TEMPLATE___ section");
const permissions = JSON.parse(S.WEB_PERMISSIONS);

// ---- permissions, in the shape GTM compiles them to -----------------------
function grantsFor(publicId) {
  return permissions.filter((g) => g.instance.key.publicId === publicId);
}
function paramValue(grant, key) {
  const p = (grant.instance.param || []).find((x) => x.key === key);
  return p ? p.value : undefined;
}
const globals = { read: [], write: [], execute: [] };
for (const g of grantsFor("access_globals")) {
  const keys = paramValue(g, "keys");
  for (const li of (keys && keys.listItem) || []) {
    const row = {};
    li.mapKey.forEach((k, i) => {
      const v = li.mapValue[i];
      row[k.string] = "string" in v ? v.string : v.boolean;
    });
    for (const op of ["read", "write", "execute"]) if (row[op]) globals[op].push(row.key);
  }
}
const injectUrls = [];
for (const g of grantsFor("inject_script")) {
  const urls = paramValue(g, "urls");
  for (const li of (urls && urls.listItem) || []) injectUrls.push(li.string);
}
const hasLogging = grantsFor("logging").length > 0;

class PermissionError extends Error {}
function assertGlobals(op, path) {
  if (globals[op].indexOf(path) > -1) return;
  throw new PermissionError(`Prohibited ${op} on global variable: ${path}.`);
}

// ---- one scenario ---------------------------------------------------------
function runScenario(name, code, setup) {
  const mocks = {};
  const apiCalls = {};
  const fakeWindow = {};
  let ranCode = false;

  const record = (api, args) => {
    (apiCalls[api] = apiCalls[api] || []).push(args);
  };

  const realApis = {
    injectScript(url, onSuccess, onFailure) {
      // Permission check as GTM's inject_script: exact URL in the allow list
      // (this template grants one literal URL, no wildcards).
      if (injectUrls.indexOf(url) < 0) {
        throw new PermissionError(`Prohibited URL for injectScript: ${url}`);
      }
      // The GTM test sandbox does not load real scripts; neither callback runs.
    },
    callInWindow(path, ...args) {
      assertGlobals("execute", path);
      const parts = path.split(".");
      let parent = fakeWindow;
      let fn = parent[parts[0]];
      for (let i = 1; fn && i < parts.length; i++) {
        parent = fn;
        fn = fn[parts[i]];
      }
      if (typeof fn !== "function") return undefined;
      return fn.apply(parent, args);
    },
    logToConsole() {
      if (!hasLogging) throw new PermissionError("Prohibited logging");
    },
  };

  const requireApi = (api) => {
    if (!(api in realApis) && !(api in mocks)) {
      throw new Error(`runner does not emulate require('${api}'); extend scripts/run_template_tests.mjs`);
    }
    return (...args) => {
      record(api, args);
      if (api in mocks) return mocks[api](...args);
      return realApis[api](...args);
    };
  };

  const testApis = {
    mock(api, impl) {
      mocks[api] = typeof impl === "function" ? impl : () => impl;
    },
    runCode(data) {
      ranCode = true;
      const d = Object.assign({}, data, {
        gtmOnSuccess: () => record("gtmOnSuccess", []),
        gtmOnFailure: () => record("gtmOnFailure", []),
      });
      // eslint-disable-next-line no-new-func
      new Function("require", "data", sandboxJs)(requireApi, d);
    },
    assertApi(api) {
      const calls = () => apiCalls[api] || [];
      return {
        wasCalled() {
          if (!calls().length) throw new Error(`expected ${api} to be called`);
        },
        wasNotCalled() {
          if (calls().length) throw new Error(`expected ${api} NOT to be called`);
        },
        wasCalledWith(...expected) {
          const hit = calls().some((a) => JSON.stringify(a) === JSON.stringify(expected));
          if (!hit) throw new Error(`expected ${api} to be called with ${JSON.stringify(expected)}`);
        },
      };
    },
    assertThat(actual) {
      return {
        isStrictlyEqualTo(e) {
          if (actual !== e) throw new Error(`expected ${JSON.stringify(e)}, got ${JSON.stringify(actual)}`);
        },
        isEqualTo(e) {
          if (JSON.stringify(actual) !== JSON.stringify(e)) {
            throw new Error(`expected ${JSON.stringify(e)}, got ${JSON.stringify(actual)}`);
          }
        },
        isTrue() {
          if (actual !== true) throw new Error(`expected true, got ${JSON.stringify(actual)}`);
        },
        isFalse() {
          if (actual !== false) throw new Error(`expected false, got ${JSON.stringify(actual)}`);
        },
        isUndefined() {
          if (actual !== undefined) throw new Error(`expected undefined, got ${JSON.stringify(actual)}`);
        },
      };
    },
    fail(msg) {
      throw new Error(msg || "fail() called");
    },
  };

  const names = Object.keys(testApis);
  const body = `${setup || ""}\n${code}`;
  // Test code may itself require() sandbox APIs (GTM allows it).
  // eslint-disable-next-line no-new-func
  new Function("require", ...names, body)(requireApi, ...names.map((n) => testApis[n]));
  if (!ranCode) throw new Error("scenario never called runCode()");
}

// ---- parse the ___TESTS___ YAML (the exact shape GTM exports) -------------
// scenarios:
// - name: <text>
//   code: |-
//     <indented block>
// setup: '' | |-
//   <indented block>
function parseTests(text) {
  const lines = text.split("\n");
  const scenarios = [];
  let setup = "";
  let i = 0;
  const block = (start, indent) => {
    const out = [];
    let j = start;
    for (; j < lines.length; j++) {
      const l = lines[j];
      if (l.trim() === "") { out.push(""); continue; }
      if (!l.startsWith(" ".repeat(indent))) break;
      out.push(l.slice(indent));
    }
    while (out.length && out[out.length - 1] === "") out.pop();
    return [out.join("\n"), j];
  };
  while (i < lines.length) {
    const l = lines[i];
    let m;
    if ((m = l.match(/^- name: (.*)$/))) {
      const name = m[1].replace(/^['"]|['"]$/g, "");
      const c = lines[i + 1] || "";
      if (!/^ {2}code: \|-?\s*$/.test(c)) {
        throw new Error(`scenario "${name}": expected a '  code: |-' block (runner only parses block scalars)`);
      }
      const [code, next] = block(i + 2, 4);
      scenarios.push({ name, code });
      i = next;
    } else if ((m = l.match(/^setup: (.*)$/))) {
      if (/^\|-?\s*$/.test(m[1])) {
        const [code, next] = block(i + 1, 2);
        setup = code;
        i = next;
      } else {
        setup = m[1].replace(/^''$/, "");
        i++;
      }
    } else i++;
  }
  return { scenarios, setup };
}

const { scenarios, setup } = parseTests(S.TESTS || "");
if (!scenarios.length) {
  console.error("FAIL: template.tpl has no ___TESTS___ scenarios");
  process.exit(1);
}
let failed = 0;
for (const s of scenarios) {
  try {
    runScenario(s.name, s.code, setup);
    console.log(`PASS ${s.name}`);
  } catch (e) {
    failed++;
    console.log(`FAIL ${s.name}\n     ${e.message}`);
  }
}
console.log(`\n${scenarios.length - failed}/${scenarios.length} scenarios passed`);
process.exit(failed ? 1 : 0);
