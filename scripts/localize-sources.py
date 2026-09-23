#!/usr/bin/env python3
"""Obalí `return "…"` do String(localized:) tam, kde jde o text pro uživatele.

Kritérium není heuristika: řetězec musí být v katalogu. Ten už prošel
denylistem, takže cesty, klíče plistů ani jména produktů se sem nedostanou.
Text(String) se nelokalizuje — lokalizuje se jen literál — takže modelová
vrstva si překlad musí udělat sama.
"""
import json, pathlib, re, sys
sys.path.insert(0, "scripts")
from importlib import import_module
ex = import_module("extract-strings")

catalog = json.loads(pathlib.Path("Localization/Localizable.xcstrings").read_text())
keys = set(catalog["strings"])

# Modelová vrstva: tady se překlad musí udělat ručně, protože String
# se na rozdíl od literálu v Text() nelokalizuje.
MODEL = {"AppModel", "FileScanner", "RemovalDiagnostics", "PermissionChecks", "StartupService",
         "UninstallService", "FinderTrashService", "UpdateService", "PermissionController",
         "Models", "PerformanceService", "Appearance", "SupportService"}

def wrap_all(line: str) -> tuple[str, int]:
    """Obalí každý katalogový literál na řádku. Klíč slovníku ponechá: obalit
    `"Aplikace": .loginItem` by rozbilo čtení dříve uložených položek."""
    out, i, hits = [], 0, 0
    while i < len(line):
        if line[i] != '"':
            out.append(line[i]); i += 1; continue
        # Konec literálu se hledá s vědomím interpolace: `\(String(format: "%03o", x))`
        # obsahuje uvozovky, které literál neukončují.
        j = i + 1
        while j < len(line):
            if line[j] == "\\" and j + 1 < len(line):
                if line[j + 1] == "(":
                    depth, k, inner = 1, j + 2, False
                    while k < len(line) and depth:
                        c = line[k]
                        if c == "\\" and inner: k += 2; continue
                        if c == '"': inner = not inner
                        elif not inner: depth += (c == "(") - (c == ")")
                        k += 1
                    if depth: j = len(line); break
                    j = k
                    continue
                j += 2
                continue
            if line[j] == '"': break
            j += 1
        if j >= len(line):
            out.append(line[i:]); break
        literal = line[i + 1:j]
        rest = line[j + 1:]
        scanned = list(ex.scan_strings(f'"{literal}"'))
        is_key = rest.lstrip().startswith(":")
        if scanned and scanned[0][1] in keys and not is_key:
            out.append(f'String(localized: "{literal}")'); hits += 1
        else:
            out.append(line[i:j + 1])
        i = j + 1
    return "".join(out), hits

changed = {}
for path in sorted(pathlib.Path("Sources").glob("*.swift")):
    lines = path.read_text().split("\n")
    hits = 0
    for i, line in enumerate(lines):
        if "String(localized:" in line or "NSLocalizedString" in line:
            continue
        # jen návratové hodnoty a přiřazení, ne volání s popiskem
        m = re.match(r'^(.*(?:\breturn\b|=)\s*)"((?:[^"\\]|\\.)*)"(\s*)$', line)
        if not m:
            continue
        literal = m.group(2)
        # Klíč se odvodí stejným skenerem jako při extrakci, ať se nerozejdou.
        scanned = list(ex.scan_strings(f'"{literal}"'))
        if not scanned:
            continue
        key = scanned[0][1]
        if key not in keys:
            continue
        lines[i] = f'{m.group(1)}String(localized: "{literal}"){m.group(3)}'
        hits += 1
    if path.stem in MODEL:
        for i, line in enumerate(lines):
            if "String(localized:" in line or line.lstrip().startswith("//"):
                continue
            new_line, n = wrap_all(line)
            if n:
                lines[i] = new_line
                hits += n
    if hits:
        path.write_text("\n".join(lines))
        changed[path.name] = hits

for name, n in sorted(changed.items(), key=lambda kv: -kv[1]):
    print(f"  {name:28} {n}")
print(f"celkem obaleno: {sum(changed.values())}")
