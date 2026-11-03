#!/usr/bin/env node
// Builds the two ready-to-import GTM container files from template.tpl and gtm/custom-html-tag.html, so they cannot drift from
// them:
//   gtm/tapper-ecommerce-events.container.json            the "Tapper - E-commerce events" tag (this template, inline) + one Custom
//                                                         Event trigger per GA4 e-commerce event
//   gtm/tapper-ecommerce-events-custom-html.container.json the same triggers with the Custom HTML body instead of the template
//                                                         (for a container that cannot import the template), plus the
//                                                         "DLV - ecommerce" Data Layer Variable it reads
// Both carry the built-in "Event" variable. The customer imports the file once (Admin > Import Container > Merge, "Rename
// conflicting"), pastes the public key into the tag, and publishes.
// Usage: node scripts/build_gtm_container.mjs [--check]   (--check fails when the committed files are stale)
import { readFileSync, writeFileSync } from "node:fs";

const EVENTS = ["view_item", "view_item_list", "add_to_cart", "remove_from_cart", "view_cart", "begin_checkout", "add_payment_info", "purchase"];
const PK_PLACEHOLDER = "PASTE_YOUR_PUBLIC_KEY";
const check = process.argv.includes("--check");

const template = readFileSync("template.tpl", "utf8");
const html = readFileSync("gtm/custom-html-tag.html", "utf8");

const container = (name) => ({
  path: "accounts/0/containers/0", accountId: "0", containerId: "0", name, publicId: "GTM-XXXXXXX", usageContext: ["WEB"],
  fingerprint: "0", tagManagerUrl: "https://tagmanager.google.com/#/container/accounts/0/containers/0/workspaces?apiLink=container",
});

const triggers = EVENTS.map((event, i) => ({
  accountId: "0", containerId: "0", triggerId: String(i + 1), name: `Tapper - ${event}`, type: "CUSTOM_EVENT",
  customEventFilter: [{ type: "EQUALS", parameter: [{ type: "TEMPLATE", key: "arg0", value: "{{_event}}" }, { type: "TEMPLATE", key: "arg1", value: event }] }],
  fingerprint: "0",
}));
const triggerIds = triggers.map((t) => t.triggerId);

const t = (key, value) => ({ type: "TEMPLATE", key, value });
const common = { accountId: "0", containerId: "0", tagId: "1", fingerprint: "0", firingTriggerId: triggerIds, tagFiringOption: "ONCE_PER_EVENT", monitoringMetadata: { type: "MAP" }, consentSettings: { consentStatus: "NOT_SET" } };

const wrap = (name, body) => ({
  exportFormatVersion: 2,
  exportTime: "2026-11-03 00:00:00",
  containerVersion: {
    path: "accounts/0/containers/0/versions/0", accountId: "0", containerId: "0", containerVersionId: "0",
    container: container(name),
    builtInVariable: [{ accountId: "0", containerId: "0", type: "EVENT", name: "Event" }],
    ...body,
    fingerprint: "0",
    tagManagerUrl: "https://tagmanager.google.com/#/versions/accounts/0/containers/0/versions/0?apiLink=version",
  },
});

const templateFile = wrap("Tapper e-commerce events", {
  tag: [{
    ...common, name: "Tapper - E-commerce events", type: "cvt_0_1",
    parameter: [
      t("tagType", "ecommerce"), t("pk", PK_PLACEHOLDER), { type: "BOOLEAN", key: "recordPurchase", value: "true" },
      t("email", ""), t("phone", ""),
    ],
  }],
  trigger: triggers,
  customTemplate: [{ accountId: "0", containerId: "0", templateId: "1", name: "Tapper - Monitoring Script", fingerprint: "0", templateData: template.replace(/^﻿/, "") }],
});

const htmlFile = wrap("Tapper e-commerce events (Custom HTML)", {
  tag: [{
    ...common, name: "Tapper - E-commerce events (Custom HTML)", type: "html",
    parameter: [{ type: "TEMPLATE", key: "html", value: html.trim() }, { type: "BOOLEAN", key: "supportDocumentWrite", value: "false" }],
  }],
  trigger: triggers,
  variable: [{
    accountId: "0", containerId: "0", variableId: "1", name: "DLV - ecommerce", type: "v",
    parameter: [{ type: "INTEGER", key: "dataLayerVersion", value: "2" }, { type: "BOOLEAN", key: "setDefaultValue", value: "false" }, t("name", "ecommerce")],
    fingerprint: "0", formatValue: {},
  }],
});

const outputs = {
  "gtm/tapper-ecommerce-events.container.json": JSON.stringify(templateFile, null, 2) + "\n",
  "gtm/tapper-ecommerce-events-custom-html.container.json": JSON.stringify(htmlFile, null, 2) + "\n",
};
let stale = 0;
for (const [path, text] of Object.entries(outputs)) {
  if (check) {
    let have = "";
    try { have = readFileSync(path, "utf8"); } catch { /* missing */ }
    if (have !== text) { console.log(`STALE ${path} (run node scripts/build_gtm_container.mjs)`); stale++; } else { console.log(`OK    ${path}`); }
  } else {
    writeFileSync(path, text);
    console.log(`wrote ${path}`);
  }
}
process.exit(stale ? 1 : 0);
