#!/usr/bin/env python3
"""Ověří, že katalog odpovídá zdroji a že nic nezůstalo nepřeložené.

Chybějící překlad se v aplikaci neprojeví chybou — text prostě zůstane česky
a pozná se to až při ručním proklikání v daném jazyce. Tady z toho je selhání
testu.
"""
import json, pathlib, sys
sys.path.insert(0, "scripts")
from importlib import import_module
ex = import_module("extract-strings")

LANGUAGES = ["en", "de", "fr", "hi", "es"]

def main() -> int:
    catalog = json.loads(pathlib.Path("Localization/Localizable.xcstrings").read_text())
    strings = catalog["strings"]
    found = ex.collect()
    blocked = ex.denylist()
    prefixes = tuple(b[:-1] for b in blocked if b.endswith("*"))
    exact = {b for b in blocked if not b.endswith("*")}
    found = {k: v for k, v in found.items()
             if k not in exact and not (prefixes and k.startswith(prefixes))}

    problems = []
    for key in sorted(set(found) - set(strings)):
        problems.append(f"ve zdroji, ale ne v katalogu: {key[:70]}")
    for key in sorted(set(strings) - set(found)):
        problems.append(f"v katalogu, ale ne ve zdroji: {key[:70]}")
    for key in sorted(strings):
        missing = [l for l in LANGUAGES if l not in strings[key].get("localizations", {})]
        if missing:
            problems.append(f"chybí {','.join(missing)}: {key[:60]}")

    if problems:
        print(f"✗ {len(problems)} problémů:", file=sys.stderr)
        for p in problems[:12]:
            print("   ", p, file=sys.stderr)
        return 1
    print(f"PASS: {len(strings)} strings present in the source and translated into "
          f"{len(LANGUAGES)} languages. Nothing silently left in Czech.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
