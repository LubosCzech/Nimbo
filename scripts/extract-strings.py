#!/usr/bin/env python3
"""Sesbírá lokalizovatelné řetězce ze zdrojů do String Catalogu.

Klíčem je česky psaný originál: SwiftUI bere `Text("…")` jako LocalizedStringKey
a vyhledá ho sám, takže drtivá většina volání nepotřebuje žádnou úpravu.
Interpolace `\\(x)` se převádí na %@ / %lld podle typu, jak to dělá SwiftUI.
"""
import json, pathlib, re, sys

SOURCES = pathlib.Path("Sources")
CATALOG = pathlib.Path("Localization/Nimbo.xcstrings")
LANGUAGES = ["en", "de", "fr", "hi", "es"]
SOURCE_LANGUAGE = "cs"

CZECH = "áčďéěíňóřšťúůýžÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ"
# Řetězce, které vypadají jako text, ale textem pro uživatele nejsou.
SKIP = re.compile(
    r"^(?:[a-z0-9_.-]+/[\w./%-]*|[A-Za-z0-9_.]+\.[A-Za-z0-9_.]+|"
    r"https?://.*|~?/.*|[a-z][a-zA-Z0-9]*(?:\.[a-z][a-zA-Z0-9]*)+|%\w+|\s*)$"
)
# SF Symbols a systémové klíče: bez diakritiky, s tečkou nebo camelCase.
SYMBOLLIKE = re.compile(r"^[a-z][A-Za-z0-9.]*$")

def is_ui_string(value: str) -> bool:
    if not value or len(value) < 2:
        return False
    # Cesta v souborovém systému, ne text. Lomítko obklopené mezerami
    # ("Node / npm") je oddělovač ve jméně, ne cesta.
    if re.search(r"(?<! )/|/(?! )", value):
        return False
    if SKIP.match(value) or SYMBOLLIKE.match(value):
        return False
    if any(ch in CZECH for ch in value):
        return True
    # Text bez diakritiky se pozná podle velkého počátečního písmene a toho,
    # že nevypadá jako identifikátor. Jednoslovné popisky ("Aplikace") tím
    # projdou, názvy symbolů a klíčů ne.
    if not value[0].isupper():
        return False
    return all(ch.isalpha() or ch in " ·:()%@?!,.…&/-+" for ch in value)

def scan_strings(source: str):
    """Vrátí řetězcové literály včetně čísla řádku.

    Regulární výraz tu nestačí: interpolace může obsahovat další řetězec
    (`\\(id ?? "—")`) a naivní hledání uvozovek rozsekne literál uprostřed.
    Scanner proto sleduje hloubku interpolace a uvozovky uvnitř ní.
    """
    i, line = 0, 1
    n = len(source)
    while i < n:
        ch = source[i]
        if ch == "\n":
            line += 1
            i += 1
            continue
        if source.startswith("//", i):
            j = source.find("\n", i)
            i = n if j < 0 else j
            continue
        if source.startswith('"""', i):          # víceřádkový literál se přeskočí
            j = source.find('"""', i + 3)
            block = source[i:(n if j < 0 else j + 3)]
            line += block.count("\n")
            i = n if j < 0 else j + 3
            continue
        if ch != '"':
            i += 1
            continue
        # začátek jednořádkového literálu
        parts, i, start_line = [], i + 1, line
        while i < n:
            ch = source[i]
            if ch == "\\" and i + 1 < n:
                if source[i + 1] == "(":         # interpolace: přeskoč vyváženě
                    depth, j, inner = 1, i + 2, False
                    while j < n and depth:
                        c = source[j]
                        if c == "\\" and inner:
                            j += 2
                            continue
                        if c == '"':
                            inner = not inner
                        elif not inner:
                            depth += (c == "(") - (c == ")")
                        j += 1
                    parts.append("%@")
                    i = j
                    continue
                parts.append(source[i:i + 2])
                i += 2
                continue
            if ch == '"':
                i += 1
                break
            if ch == "\n":                       # nezavřený literál, bezpečně ukonči
                line += 1
                break
            parts.append(ch)
            i += 1
        yield start_line, "".join(parts)


def denylist() -> set[str]:
    path = pathlib.Path("Localization/not-localizable.txt")
    if not path.exists():
        return set()
    return {l.strip() for l in path.read_text().split("\n")
            if l.strip() and not l.startswith("#")}


def collect() -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}
    for path in sorted(SOURCES.glob("*.swift")):
        for line_no, value in scan_strings(path.read_text()):
            if is_ui_string(value):
                found.setdefault(value, []).append(f"{path.name}:{line_no}")
    return found


def main() -> int:
    found = collect()
    catalog = {"sourceLanguage": SOURCE_LANGUAGE, "version": "1.0", "strings": {}}
    if CATALOG.exists():
        catalog = json.loads(CATALOG.read_text())
    strings = catalog.setdefault("strings", {})

    blocked = denylist()
    found = {k: v for k, v in found.items()
             if k not in blocked and not any(k.startswith(b) for b in blocked)}
    for key in found:
        entry = strings.setdefault(key, {})
        entry.setdefault("extractionState", "manual")
        entry.setdefault("localizations", {})
    stale = [k for k in strings if k not in found]

    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    missing = {lang: sum(1 for k in found if lang not in strings[k]["localizations"]) for lang in LANGUAGES}
    print(f"nalezeno {len(found)} řetězců v {len({p.split(':')[0] for v in found.values() for p in v})} souborech")
    print("chybí překlady: " + ", ".join(f"{l}={n}" for l, n in missing.items()))
    if stale:
        print(f"v katalogu navíc (už nejsou ve zdroji): {len(stale)}")
        for k in stale[:5]:
            print("   ", k[:70])
    return 0

if __name__ == "__main__":
    sys.exit(main())
