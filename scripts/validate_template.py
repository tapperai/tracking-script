#!/usr/bin/env python3
"""Env-independent validity gate for the GTM template (.tpl).

Checks that would have caught the empty-access_globals / malformed-JSON class of
bug BEFORE the Community Template Gallery picks up a commit:

  1. Every JSON-bearing section (___INFO___, ___TEMPLATE_PARAMETERS___,
     ___WEB_PERMISSIONS___) parses as valid JSON.
  2. Every window-access API path used in the sandboxed JS
     (callInWindow / copyFromWindow / setInWindow / createQueue / aliasInWindow)
     has its ROOT identifier granted in the access_globals permission.
  3. Every require()'d API that needs a permission has that permission granted
     (injectScript -> inject_script, callInWindow -> access_globals,
      logToConsole -> logging).

Pure stdlib (python3 only). No network, no secrets, no npm. Safe as a CI gate.
Exits non-zero on any failure.
"""
import json
import re
import sys

TPL = sys.argv[1] if len(sys.argv) > 1 else "template.tpl"

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

WINDOW_API_RE = re.compile(
    r"(?:callInWindow|copyFromWindow|setInWindow|createQueue|aliasInWindow)"
    r"\(\s*['\"]([^'\"]+)['\"]"
)


def split_sections(content):
    parts = re.split(r"^___([A-Z_]+)___$", content, flags=re.M)
    sections = {}
    for i in range(1, len(parts), 2):
        sections[parts[i]] = parts[i + 1].strip()
    return sections


def main():
    failures = []
    with open(TPL) as f:
        content = f.read()
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
    granted_globals = set()
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
                        if "key" in row:
                            granted_globals.add(row["key"])

    # 2. window-API root identifiers granted.
    for path in WINDOW_API_RE.findall(js):
        root = path.split(".")[0]
        if root in granted_globals:
            print(f"OK   window path '{path}' (root '{root}') granted in access_globals")
        else:
            failures.append(
                f"window path '{path}' uses global '{root}' not granted in access_globals"
            )

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

    if failures:
        print("\nFAILURES:")
        for f_ in failures:
            print(f"  - {f_}")
        return 1
    print("\nAll template validity checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
