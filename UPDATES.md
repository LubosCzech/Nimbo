# Aktualizace Nimba přes Sparkle a GitHub Releases

## Co je hotové

Sparkle 2.9.6 je připnuté v `scripts/fetch-sparkle.sh`, stažený archiv se kontroluje pomocí SHA-256. Framework a jeho licence se kopírují do `.app`, včetně instalačních pomocníků. Nimbo má „Zkontrolovat aktualizace…“ v menu a sekci Aktualizace v Nastavení. Automatická kontrola jednou za 24 hodin je volitelná, ve výchozím stavu vypnutá. Stahování/instalace vyžaduje potvrzení uživatele. Sparkle řeší průběh, chyby, ověření stažení, instalaci a opětovné spuštění.

Aktualizační archiv i appcast mají Ed25519 podpis. Kontrola archivu proběhne před rozbalením. Neposíláme systémový profil; skenování souborů zůstává lokální. Síťové kontroly kontaktují GitHub (a jeho CDN), kterému je viditelná obvyklá síťová metadata včetně IP adresy.

Release používá Hardened Runtime bez vypínání library validation. `Nimbo.entitlements` povoluje pouze Apple Events pro již existující správu přihlašovacích aplikací; systémový souhlas Automatizace zůstává vyžadovaný. Aplikace není sandboxovaná (pracuje s uživatelem vybranými soubory a instalacemi).

Repozitář je nastaven na `LubosCzech/Nimbo`. Feed bude dostupný na `https://github.com/LubosCzech/Nimbo/releases/latest/download/appcast.xml` po prvním zveřejněném vydání. Veřejný podpisový klíč ještě není doplněný.

Pokud chybí veřejný klíč, updater se nespouští, tlačítko je neaktivní a Nastavení vysvětluje proč. Vývojový build je možný i s nastaveným repozitářem bez klíče; release skript takovou konfiguraci odmítne. Nesprávný formát neprázdné hodnoty zastaví build.

## 1. Jednorázové nastavení

Potřebujete macOS, aktuální Xcode se SDK 26+, Python 3 z Command Line Tools a GitHub CLI (`gh`, přihlášené přes `gh auth login`). Pro veřejnou distribuci potřebujete Apple Developer Program, certifikát **Developer ID Application** s privátním klíčem v Klíčence a profil notarizace.

1. **Veřejný** GitHub repozitář `LubosCzech/Nimbo` je již nastaven pro zdrojový kód i binární vydání. Soukromý repozitář bez přihlašování updater nepřečte; token se nikdy nevkládá do aplikace.
2. V kořeni projektu spusťte `bash scripts/init-update-key.sh`. Nástroj vytvoří klíč v přihlašovací Klíčence pod účtem `nimbo-updates`. Existující klíč zachová. Mac může vyžádat povolení přístupu do Klíčenky.
3. Do `release.env` vložte `GITHUB_REPOSITORY="owner/repository"` a zobrazený veřejný klíč `SPARKLE_PUBLIC_ED_KEY="…"`. Soukromý klíč tam nepatří! Účet `SPARKLE_KEY_ACCOUNT` pak neměňte bez plánované migrace.
4. Vytvořte ignorovaný soubor `release.local.env` pouze s názvy lokálních podpisových prostředků:

```bash
NIMBO_SIGN_IDENTITY="Developer ID Application: Vaše jméno (TEAMID)"
NIMBO_NOTARY_PROFILE="nimbo-notary"
```

Nastavení přihlašovacích údajů pro notarizaci proveďte interaktivně (heslo neposílejte do chatu ani neukládejte do projektu):

```bash
xcrun notarytool store-credentials nimbo-notary
security find-identity -v -p codesigning
```

Soukromý Sparkle klíč bezpečně zálohujte mimo repozitář podle [návodu Sparkle](https://sparkle-project.org/documentation/#eddsa-ed25519-signatures). Skripty ho neexportují ani nevypisují. Ztráta klíče může zablokovat další aktualizace; neměňte zároveň EdDSA klíč a Developer ID identitu. Aktuální bundle ID `local.nimbo.app` je zachované kvůli kontinuitě; po prvním vydání jej neměňte.

## 2. Příprava každého vydání

V `release.env` zvyšte **obě** hodnoty: `APP_VERSION` je viditelná verze (např. 1.3), `APP_BUILD` je stále rostoucí kladné celé číslo (např. 13). Sparkle porovnává build. Upravte `RELEASE_NOTES.md` a otestujte aplikaci. V release repozitáři vytvořte a pushněte tag `v<APP_VERSION>` pro schválené vydání. Skript tag sám nevytváří a zdrojové změny sám necommituje.

První Sparkle vydání:

```bash
bash scripts/release.sh prepare --first-release
```

Další vydání:

```bash
bash scripts/release.sh prepare
```

Příprava ověří veřejný repozitář, existenci tagu, shodu veřejného klíče s Klíčenkou a rostoucí build proti podepsanému aktuálnímu appcastu. Pak sestaví **universal** aplikaci pro Apple Silicon i Intel, podepíše všechny části Developer ID, notarizuje a stapluje aplikaci, vytvoří DMG, podepíše/notarizuje/stapluje i DMG, vygeneruje podepsaný appcast a ověří podpisy, URL i délku archivu. Poznámky k vydání jsou vložené přímo do podepsaného feedu. Delta aktualizace jsou zatím vypnuté; posílá se celý DMG.

Výsledek je v `dist/releases/v<verze>/`. Existující složka ani DMG se nepřepisují. Pokud příprava selže (např. notarizace), zůstane neúplný výstup pro diagnostiku. Před opakováním ho přesuňte stranou; nikdy nezveřejňujte neúplné vydání. Při zamítnutí notarizace stáhněte log pomocí `xcrun notarytool log <submission-id> --keychain-profile nimbo-notary` a chybu opravte.

## 3. Nahrání a zveřejnění

```bash
bash scripts/release.sh upload
```

Vytvoří nový **draft**, nahraje DMG, appcast, poznámky a SHA256SUMS. Už existující vydání skript nepřepíše. Pokud přenos selže, zkontrolujte draft na GitHubu; opravu či odstranění nedokončeného draftu proveďte vědomě, skript ho automaticky nemaže.

Zkontrolujte draft a hotový obsah. Potom explicitně:

```bash
bash scripts/release.sh publish
```

Skript znovu stáhne soubory draftu, porovná je s lokálními, ověří, že od přípravy nebyl zveřejněn novější build, a nastaví vydání jako **Latest**. Nakonec ověří veřejný feed. Selhání poslední síťové kontroly může znamenat, že vydání už je zveřejněné, ale CDN ještě neaktualizovala přesměrování — nejprve zkontrolujte GitHub, nic znovu nepřepisujte.

Stabilní adresa feedu vložená do každé aplikace:

```text
https://github.com/OWNER/REPO/releases/latest/download/appcast.xml
```

DMG v appcastu odkazuje na neměnný tag, nikoliv na `latest`. Každé stabilní vydání tohoto repozitáře musí obsahovat `appcast.xml` a musí být publikované tímto flow. Starší release soubory zachovejte, odkazy z historie na ně mohou stále mířit. Předchozí podepsané položky appcastu se zachovávají podle pravidel Sparkle. Pokud už repozitář obsahuje jiné stabilní vydání bez appcastu, použijte čistý repozitář určený pro Nimbo nebo proveďte vědomou migraci — skript nepřeskočí chybějící feed.

## 4. Ověření skutečné aktualizace

Stará verze 1.2 bez Sparkle se **sama neaktualizuje**. První nakonfigurované vydání musí uživatel jednou nainstalovat ručně přetažením do Applications a spustit odtud (ne přímo z DMG).

1. V testovacím veřejném repozitáři nastavte samostatný feed a vydejte dva testovací buildy s rostoucím `APP_BUILD`.
2. Nainstalujte první notarizovaný build do Applications. Ověřte menu i Nastavení, vypnuté/zapnuté automatické kontroly a persistenci po restartu.
3. Vydejte druhý build. V prvním zvolte „Zkontrolovat aktualizace…“, zkontrolujte poznámky, stažení a potvrďte instalaci a restart. Ověřte verzi a zachování nastavení.
4. Ověřte „máte aktuální verzi“, nedostupnou síť, zrušené stažení a instalaci z read-only DMG. Na kopii feedu/archivu ověřte, že změněný podpis aktualizaci odmítne. Nikdy neměňte produkční archiv kvůli testu.
5. S reálnými vydávacími certifikáty otestujte Apple Silicon i Intel a nejstarší podporovaný macOS. Samotný lokální ad-hoc test neprokazuje chování Gatekeeperu, notarizace ani celý restart/instalaci.

Lokální kryptografický smoke test bez produkčního klíče:

```bash
./build.sh
xcrun swift -module-cache-path build/ModuleCache Tests/SparkleSmoke.swift
```

Test používá dočasný klíč mimo Klíčenku a kopii aplikace, vytvoří a ověří podepsaný feed/ZIP a ověří odmítnutí změněného archivu i feedu. Nic nepublikuje a neinstaluje. `generate_appcast` může vytvořit vlastní běžnou cache v `~/Library/Caches/Sparkle_generate_appcast`.

## Obnova po vadném vydání

Neměňte obsah již publikovaného DMG ani podepsaný appcast ručně. Připravte opravenou verzi s vyšším `APP_BUILD` a novým tagem. Při kritické chybě lze na GitHubu dočasně vrátit Latest na předchozí kompletní vydání; klienti už aktualizovaní na vadný build se sami nedowngradují, potřebují nový vyšší build.

## Zdroje

- [Oficiální nastavení Sparkle](https://sparkle-project.org/documentation/)
- [SwiftUI integrace](https://sparkle-project.org/documentation/programmatic-setup/)
- [Podepisování pomocníků Sparkle](https://sparkle-project.org/documentation/sandboxing/#code-signing)
- [GitHub CLI: vytvoření vydání](https://cli.github.com/manual/gh_release_create)
