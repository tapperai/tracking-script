#!/usr/bin/env node
// Tests for gtm/custom-html-tag.html: the fallback body a customer pastes into a GTM Custom HTML tag. GTM replaces {{Event}} and
// {{DLV - ecommerce}} with the values at fire time; here the same two substitutions are made by hand and the script runs in a
// plain Node vm with a fake window. Pure Node, no dependencies. Exits non-zero on any failure.
import { readFileSync } from "node:fs";
import vm from "node:vm";

const html = readFileSync(process.argv[2] || "gtm/custom-html-tag.html", "utf8");
const body = html.replace(/^<script>\s*/, "").replace(/\s*<\/script>\s*$/, "");

function run({ event, ecommerce, window: win = {}, edit = (s) => s }) {
  const store = new Map();
  const calls = [];
  const w = {
    localStorage: { getItem: (k) => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)) },
    ...win,
  };
  if (w.tapper && !Array.isArray(w.tapper)) {
    for (const m of ["track", "push"]) {
      if (typeof w.tapper[m] === "function") {
        const real = w.tapper[m];
        w.tapper[m] = (...a) => { calls.push([`tapper.${m}`, ...a]); return real(...a); };
      }
    }
  }
  const code = edit(body).replace("{{Event}}", JSON.stringify(event)).replace("{{DLV - ecommerce}}", JSON.stringify(ecommerce ?? null));
  vm.runInNewContext(code, { window: w, String, Object, Number, JSON, Array });
  return { w, calls, store };
}
const live = () => { const t = { track() {}, push() {} }; return t; };

const PURCHASE = {
  transaction_id: "T-1001", value: 59.8, currency: "EUR", tax: 4.5, shipping: 5, coupon: "SPRING",
  items: [{ item_id: "SKU_1", item_name: "Trail Shoe", item_brand: "Acme", price: 49.9, quantity: 1, secret: "x" }, { item_id: "SKU_2", quantity: 2 }],
};
const TRACKED = {
  value: 59.8, currency: "EUR", transaction_id: "T-1001", coupon: "SPRING", shipping: 5, tax: 4.5,
  items: [{ item_id: "SKU_1", item_name: "Trail Shoe", item_brand: "Acme", price: 49.9, quantity: 1 }, { item_id: "SKU_2", quantity: 2 }],
};
const eq = (a, b, m) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${m}\n   got      ${JSON.stringify(a)}\n   expected ${JSON.stringify(b)}`); };

const scenarios = {
  "add_to_cart sends tapper.track with the GA4 fields and no secret field": () => {
    const { calls } = run({ event: "add_to_cart", ecommerce: PURCHASE, window: { tapper: live() } });
    eq(calls, [["tapper.track", "add_to_cart", TRACKED]], "calls");
  },
  "purchase sends the event and records the conversion in the conversion tag's argument order": () => {
    const { calls } = run({ event: "purchase", ecommerce: PURCHASE, window: { tapper: live() } });
    eq(calls, [["tapper.track", "purchase", TRACKED], ["tapper.push", 59.8, "EUR", "T-1001"]], "calls");
  },
  "customer e-mail and phone are the 5th push argument and never in tapper.track": () => {
    const hash = "a".repeat(64);
    const { calls } = run({ event: "purchase", ecommerce: PURCHASE, window: { tapper: live() },
      edit: (s) => s.replace("var CUSTOMER_EMAIL = '';", "var CUSTOMER_EMAIL = 'ann@example.com';").replace("var CUSTOMER_PHONE = '';", `var CUSTOMER_PHONE = '${hash}';`) });
    eq(calls[1], ["tapper.push", 59.8, "EUR", "T-1001", undefined, { email: "ann@example.com", phone: hash }], "push");
    if (JSON.stringify(calls[0]).includes("ann@example.com") || JSON.stringify(calls[0]).includes(hash)) throw new Error("identity leaked into tapper.track");
  },
  "RECORD_PURCHASE false sends the event only": () => {
    const { calls } = run({ event: "purchase", ecommerce: PURCHASE, window: { tapper: live() }, edit: (s) => s.replace("var RECORD_PURCHASE = true;", "var RECORD_PURCHASE = false;") });
    eq(calls, [["tapper.track", "purchase", TRACKED]], "calls");
  },
  "the same order id is sent once, across page loads (localStorage)": () => {
    const first = run({ event: "purchase", ecommerce: PURCHASE, window: { tapper: live() } });
    const second = run({ event: "purchase", ecommerce: PURCHASE, window: { tapper: live(), localStorage: { getItem: (k) => first.store.get(k) ?? null, setItem() {} } } });
    eq(second.calls, [], "second page load");
  },
  "an ecommerce object left over from a different event is ignored": () => {
    const win = { tapper: live() };
    const a = run({ event: "view_item", ecommerce: PURCHASE, window: win });
    win.__tapperEcom = a.w.__tapperEcom;
    const b = run({ event: "begin_checkout", ecommerce: PURCHASE, window: win });
    eq(b.calls, [["tapper.track", "begin_checkout", {}]], "stale");
  },
  "an amount without a currency is not sent to tapper.track, the conversion keeps it": () => {
    const { calls } = run({ event: "purchase", ecommerce: { transaction_id: "T-9", value: 30, items: [{ item_id: "A" }] }, window: { tapper: live() } });
    eq(calls, [["tapper.track", "purchase", { transaction_id: "T-9", items: [{ item_id: "A" }] }], ["tapper.push", 30, undefined, "T-9"]], "calls");
  },
  "an event outside the vocabulary sends nothing": () => {
    const { calls, w } = run({ event: "gtm.js", ecommerce: PURCHASE, window: { tapper: live() } });
    eq(calls, [], "calls");
    eq(w.__tapperEcom, undefined, "state");
  },
  "before the script has loaded the loader stub's buffer takes the calls": () => {
    const { w } = run({ event: "purchase", ecommerce: PURCHASE });
    eq(w.tapper.slice(), [["track", "purchase", TRACKED], 59.8, "EUR", "T-1001"], "buffer");
    eq(typeof w.tapper.track, "function", "stub");
  },
  "a loaded script without tapper.track (an older cached bundle) gets no stub and no mis-read call": () => {
    const t = { push() {} };
    const { calls } = run({ event: "add_to_cart", ecommerce: PURCHASE, window: { tapper: t } });
    eq(calls, [], "calls");
    eq(t.track, undefined, "no track stub on the live instance");
  },
};

let failed = 0;
for (const [name, fn] of Object.entries(scenarios)) {
  try { fn(); console.log(`PASS ${name}`); } catch (e) { failed++; console.log(`FAIL ${name}\n     ${e.message}`); }
}
console.log(`\n${Object.keys(scenarios).length - failed}/${Object.keys(scenarios).length} custom HTML scenarios passed`);
process.exit(failed ? 1 : 0);
