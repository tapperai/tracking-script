# Tracking Script — Testing Framework

> **Parent:** [tracking-script](SPEC.md)

This repo has no server, database, or queue — testing is (1) a static
CI validator that runs against `template.tpl` itself, and (2) GTM's own
built-in test scenario + Preview mode, since the only real "runtime" is
inside a customer's GTM sandbox.

---

## 1. CI validation gate (`scripts/validate_template.py`)

Runs automatically on every push/PR to `main` via
`.github/workflows/validate.yml`, and can be run locally with no
dependencies beyond `python3` stdlib:

```bash
python3 scripts/validate_template.py template.tpl
```

**What it checks:**

1. Every JSON-bearing section (`___INFO___`, `___TEMPLATE_PARAMETERS___`,
   `___WEB_PERMISSIONS___`) parses as valid JSON.
2. Every window-access API used in the sandboxed JS (`callInWindow`,
   `copyFromWindow`, `setInWindow`, `createQueue`, `aliasInWindow`) has its
   root identifier granted in the `access_globals` permission.
3. Every `require()`'d API that needs a permission has that permission
   granted — `injectScript` → `inject_script`, `callInWindow` →
   `access_globals`, `logToConsole` → `logging`.

Exits non-zero on any failure — this is the check that would have caught an
empty/missing `access_globals` grant before Google's Community Template
Gallery picked up the commit (that class of bug is why the script exists).

---

## 2. Built-in GTM test scenario (`___TESTS___` section of `template.tpl`)

`template.tpl` carries one GTM sandboxed-JS test scenario, run from inside
GTM's own template editor ("Testing" tab, not from this repo's CI):

```js
const mockData = {
  pk: 'pk_test_123456789',
  gtmOnSuccess: () => {},
  gtmOnFailure: () => fail('gtmOnFailure should not be called')
};

runCode(mockData);
assertApi('gtmOnSuccess').wasCalled();
```

To run it: open the template in GTM's template editor (import
`template.tpl` into a workspace, or paste it into gallery.google.com's
template preview), go to the **Testing** tab, and run the scenario. It
asserts the happy path — a valid `pk` leads to `gtmOnSuccess()` being
called and `gtmOnFailure()` never being called.

---

## 3. Manual end-to-end test in GTM Preview

There is no local dev server to run this against — verification happens
inside an actual GTM container.

1. Import `template.tpl` into a test GTM workspace (Templates → New →
   Import).
2. Create a tag from the template, enter a real `pk_test_...` Public Key,
   set the trigger to All Pages.
3. Enter **Preview** mode and load a page in the connected site/tab.
4. Verify in the Tag Assistant debug panel that the tag fired
   `gtmOnSuccess` (not `gtmOnFailure`).
5. Verify in the browser console/Network tab that
   `https://monitor.tapper.ai/bundle.js` loaded (200) and that
   `window.tapper.init` was called with the entered `pk`.

**Failure-path checks** (cover the two `Edge Cases` in SPEC.md):

- Leave `pk` empty in the tag config → GTM's own parameter validators
  (`NON_EMPTY` + regex) should block saving the tag before it can even fire.
- Point the injected URL at an unreachable host (temporarily, in a scratch
  copy of the template only — never commit this) to confirm the
  `injectScript` failure callback logs `'Failed to load Tapper script'` and
  calls `gtmOnFailure()`.
