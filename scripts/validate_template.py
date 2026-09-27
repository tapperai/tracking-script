#!/usr/bin/env python3
"""Env-independent validity gate for the GTM template (.tpl).

Checks that would have caught the empty-access_globals / malformed-JSON class of
bug BEFORE the Community Template Gallery picks up a commit:

  1. Every JSON-bearing section (___INFO___, ___TEMPLATE_PARAMETERS___,
     ___WEB_PERMISSIONS___) parses as valid JSON.
  2. Every window-access API path used in the sandboxed JS
     (callInWindow / copyFromWindow / setInWindow / createQueue / aliasInWindow)
     has its FULL dotted path granted in access_globals with the operation that
     API needs (callInWindow -> execute, copyFromWindow -> read, setInWindow ->
     write, createQueue -> read+write, aliasInWindow -> write on the target and
     read on the source). GTM matches the full path EXACTLY: its runtime checker
     is `executeKeys.indexOf(path) > -1` (read verbatim from a live gtm.js on
     2026-09-28), so a grant on `tapper` does NOT cover `tapper.init`. The old
     root-only check passed a template that could never call tapper.init.
     A non-literal path argument fails, because it cannot be verified.
  3. Every require()'d API that needs a permission has that permission granted
     (injectScript -> inject_script, callInWindow -> access_globals,
      logToConsole -> logging).
  4. ___INFO___ carries 1-3 Community Template Gallery categories.
  5. With --metadata metadata.yaml: the version the Gallery serves (the FIRST
     `sha:` in metadata.yaml) is a commit reachable from HEAD whose
     template.tpl is byte-identical to the one being validated. A template
     change that never reaches metadata.yaml never reaches the Gallery (the
     2026-06-27 grant fix sat on main for three months that way).

Pure stdlib (python3 only). No network, no secrets, no npm. Safe as a CI gate.
Exits non-zero on any failure.
"""
import json
import re
import sys

import subprocess

ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
TPL = ARGS[0] if ARGS else "template.tpl"
METADATA = None
if "--metadata" in sys.argv:
    i = sys.argv.index("--metadata")
    METADATA = sys.argv[i + 1] if i + 1 < len(sys.argv) else "metadata.yaml"
    if METADATA in ARGS:
        ARGS.remove(METADATA)
        TPL = ARGS[0] if ARGS else "template.tpl"

# require()'d API -> permission publicId it needs (None = no permission needed).
REQUIRE_PERMISSION = {
    "injectScript": "inject_script",
    "callInWindow": "access_globals",
    "copyFromWindow": "access_globals",
    "setInWindow": "access_globals",
    "createQueue": "access_globals",
    "aliasInWindow": "access_globals",
    "logToConsole": "logging",
    "makeString": None,
    "makeNumber": None,
    "getType": None,
}

# window API -> the access_globals operation(s) GTM asserts on each path
# argument, in argument order.
WINDOW_API_OPS = {
    "callInWindow": [("execute",)],
    "copyFromWindow": [("read",)],
    "setInWindow": [("write",)],
    "createQueue": [("read", "write")],
    "aliasInWindow": [("write",), ("read",)],
}

WINDOW_CALL_RE = re.compile(
    r"\b(callInWindow|copyFromWindow|setInWindow|createQueue|aliasInWindow)\s*\(([^)]*)\)"
)
STRING_ARG_RE = re.compile(r"\s*(['\"])([^'\"]*)\1\s*$")

GALLERY_CATEGORIES = {
    "ADVERTISING", "AFFILIATE_MARKETING", "ANALYTICS", "ATTRIBUTION", "CHAT",
    "CONVERSIONS", "DATA_WAREHOUSING", "EMAIL_MARKETING", "EXPERIMENTATION",
    "HEAT_MAP", "LEAD_GENERATION", "MARKETING", "PERSONALIZATION",
    "REMARKETING", "SALES", "SESSION_RECORDING", "SOCIAL", "SURVEY",
    "TAG_MANAGEMENT", "UTILITY",
}


def split_sections(content):
    parts = re.split(r"^___([A-Z_]+)___$", content, flags=re.M)
    sections = {}
    for i in range(1, len(parts), 2):
        sections[parts[i]] = parts[i + 1].strip()
    return sections


def validate(content, label):
    """Return a list of failures for one template's text (prints OK lines)."""
    failures = []
    sections = split_sections(content)

    # 1. JSON sections parse.
    json_sections = {}
    for name in ("INFO", "TEMPLATE_PARAMETERS", "WEB_PERMISSIONS"):
        if name not in sections:
            failures.append(f"missing section ___{name}___")
            continue
        try:
            json_sections[name] = json.loads(sections[name])
            print(f"OK   JSON parse: {name}")
        except Exception as e:  # noqa: BLE001
            failures.append(f"___{name}___ is not valid JSON: {e}")

    js = sections.get("SANDBOXED_JS_FOR_WEB_TEMPLATE", "")

    granted_perms = set()
    granted_globals = {"read": set(), "write": set(), "execute": set()}
    if "WEB_PERMISSIONS" in json_sections:
        for grant in json_sections["WEB_PERMISSIONS"]:
            pub = grant["instance"]["key"]["publicId"]
            granted_perms.add(pub)
            if pub == "access_globals":
                for p in grant["instance"].get("param", []):
                    if p.get("key") != "keys":
                        continue
                    for li in p["value"].get("listItem", []):
                        mk = [k["string"] for k in li["mapKey"]]
                        mv = li["mapValue"]
                        row = dict(zip(mk, [v.get("string", v.get("boolean")) for v in mv]))
                        if "key" not in row:
                            continue
                        for op in ("read", "write", "execute"):
                            if row.get(op) is True:
                                granted_globals[op].add(row["key"])

    # 2. every window-API path granted EXACTLY, with the operation it needs.
    for api, raw_args in WINDOW_CALL_RE.findall(js):
        args = raw_args.split(",")
        for idx, ops in enumerate(WINDOW_API_OPS[api]):
            m = STRING_ARG_RE.match(args[idx]) if idx < len(args) else None
            if not m:
                failures.append(
                    f"{api}(...) argument {idx + 1} is not a string literal; "
                    "its access_globals grant cannot be verified"
                )
                continue
            path = m.group(2)
            missing = [op for op in ops if path not in granted_globals[op]]
            if missing:
                have = sorted(k for op in ops for k in granted_globals[op])
                failures.append(
                    f"{api}('{path}') needs access_globals {'+'.join(ops)} on the exact key "
                    f"'{path}' (GTM matches the full dotted path); granted for "
                    f"{'+'.join(ops)}: {have or 'nothing'}"
                )
            else:
                print(f"OK   {api}('{path}') -> access_globals {'+'.join(ops)} on '{path}' granted")

    # 3. require()'d APIs have their permission.
    for api in re.findall(r"require\(['\"]([^'\"]+)['\"]\)", js):
        need = REQUIRE_PERMISSION.get(api, "__UNKNOWN__")
        if need == "__UNKNOWN__":
            failures.append(
                f"require('{api}') is not in the known-API permission map; "
                "extend REQUIRE_PERMISSION in this script"
            )
        elif need is None:
            print(f"OK   require('{api}') needs no permission")
        elif need in granted_perms:
            print(f"OK   require('{api}') -> permission '{need}' granted")
        else:
            failures.append(f"require('{api}') needs permission '{need}' which is not granted")

    # 4. Gallery categories.
    cats = json_sections.get("INFO", {}).get("categories")
    if not isinstance(cats, list) or not 1 <= len(cats) <= 3:
        failures.append("___INFO___.categories must be a list of 1-3 Gallery categories")
    else:
        bad = [c for c in cats if c not in GALLERY_CATEGORIES]
        if bad:
            failures.append(f"___INFO___.categories has unsupported values: {bad}")
        else:
            print(f"OK   Gallery categories: {cats}")

    return [f"[{label}] {f_}" for f_ in failures]


def git(*args):
    return subprocess.run(["git", *args], capture_output=True)


def gallery_sha(metadata_path):
    with open(metadata_path) as f:
        text = f.read()
    shas = re.findall(r"^\s*-\s*sha:\s*['\"]?([0-9a-f]{40})['\"]?\s*$", text, flags=re.M)
    return shas


def check_metadata(metadata_path, head_content):
    failures = []
    shas = gallery_sha(metadata_path)
    if not shas:
        return [f"{metadata_path} has no 40-hex `- sha:` entries under versions"]
    for sha in shas:
        if git("cat-file", "-e", f"{sha}^{{commit}}").returncode != 0:
            failures.append(f"{metadata_path} lists {sha}, which is not a commit in this clone "
                            "(fetch full history: actions/checkout fetch-depth: 0)")
    served = shas[0]
    if failures:
        return failures
    if git("merge-base", "--is-ancestor", served, "HEAD").returncode != 0:
        failures.append(
            f"Gallery-served sha {served} (first entry in {metadata_path}) is not an ancestor of "
            "HEAD. Merge template PRs with a MERGE COMMIT: squash/rebase rewrite the sha "
            "metadata.yaml points at."
        )
    shown = git("show", f"{served}:template.tpl")
    if shown.returncode != 0:
        failures.append(f"{served} has no template.tpl")
        return failures
    served_content = shown.stdout.decode("utf-8")
    if served_content != head_content:
        failures.append(
            f"template.tpl differs from the version the Gallery serves ({served}). Commit the "
            "template change, then add its sha as the FIRST entry of metadata.yaml versions "
            "in a follow-up commit on the same branch."
        )
    else:
        print(f"OK   Gallery-served sha {served} carries this exact template.tpl")
    failures += validate(served_content, f"gallery {served[:8]}")
    return failures


def main():
    with open(TPL, encoding="utf-8") as f:
        content = f.read()
    failures = validate(content, TPL)
    if METADATA:
        failures += check_metadata(METADATA, content)

    if failures:
        print("\nFAILURES:")
        for f_ in failures:
            print(f"  - {f_}")
        return 1
    print("\nAll template validity checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
