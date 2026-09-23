#!/usr/bin/env python3
"""Zapíše překlady do String Catalogu.

Vstup na stdin: JSON {"jazyk": {"klíč": "překlad"}}. Pro množná čísla je
hodnotou objekt s kategoriemi CLDR, např. {"one": "…", "few": "…", "other": "…"}.
Klíč, který není ve zdroji, skript odmítne — překlep by jinak zmizel beze stopy.
"""
import json, pathlib, sys

CATALOG = pathlib.Path("Localization/Localizable.xcstrings")

def unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}

def main() -> int:
    catalog = json.loads(CATALOG.read_text())
    strings = catalog["strings"]
    incoming = json.load(sys.stdin)
    unknown, written = [], 0
    for lang, entries in incoming.items():
        for key, value in entries.items():
            if key not in strings:
                unknown.append(key)
                continue
            loc = strings[key].setdefault("localizations", {})
            if isinstance(value, dict):
                loc[lang] = {"variations": {"plural": {c: unit(v) for c, v in value.items()}}}
            else:
                loc[lang] = unit(value)
            written += 1
    if unknown:
        print(f"✗ {len(unknown)} neznámých klíčů, nic nezapsáno:", file=sys.stderr)
        for k in unknown[:8]:
            print("   ", k[:74], file=sys.stderr)
        return 1
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    done = {l: sum(1 for k in strings if l in strings[k].get("localizations", {}))
            for l in ["en", "de", "fr", "hi", "es"]}
    print(f"zapsáno {written} překladů; hotovo: " +
          ", ".join(f"{l}={n}/{len(strings)}" for l, n in done.items()))
    return 0

if __name__ == "__main__":
    sys.exit(main())
