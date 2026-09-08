# Nimbo

Zdrojový repozitář: [LubosCzech/Nimbo](https://github.com/LubosCzech/Nimbo). Hlavní větev je `main`; instalační balíčky patří do GitHub Releases, ne do zdrojového Gitu.

```bash
git clone https://github.com/LubosCzech/Nimbo.git
cd Nimbo
./build.sh
```

Na macOS 26 používají ovládací prvky nativní Liquid Glass (`glassEffect`); na macOS 14–15 standardní materiál. Build používá aktuálně zvolené Xcode SDK, nikoli pevné SDK 15. Obsahové karty mají čitelné podklady, sklo je vyhrazené ovládání a navigaci.

Transparentní varianty značky jsou v `Assets/*-transparent.png`. Lze je znovu vytvořit z originálů příkazem `xcrun swift PrepareAssets.swift`. Originály zůstávají zachované. Vestavěný Google prohlížeč používá Safari identifikaci, aby Google poskytoval moderní AI rozhraní; k dispozici je také otevření oficiálního AI Mode v systémovém prohlížeči.

Nativní macOS aplikace v SwiftUI pro bezpečnou údržbu počítače. Podporuje světlý a tmavý vzhled i automatické přizpůsobení systému.

## Funkce

- chytrý úklid uživatelských cache, logů, Koše a Xcode dat,
- rozbalovací detail každé úklidové sekce se jménem, cestou a velikostí jednotlivých položek,
- hledání velkých souborů v osobních složkách,
- přehled nainstalovaných aplikací podle velikosti,
- odinstalace aplikace včetně přesně identifikovaných zbytků,
- hledání osiřelých cache, nastavení, kontejnerů a uložených stavů po odinstalovaných aplikacích,
- detailní analýza zbytků Xcode, DerivedData, archivů a simulátorů,
- přehled Android SDK, AVD/emulátorů, Gradle cache a build tools,
- kontrola JDK, Node.js runtime, npm/pnpm/Yarn cache a globálních balíčků,
- inventář Homebrew formulí, casků, cache a logů,
- informační tlačítko ⓘ s vloženými Google výsledky pro aplikace, osiřelá data a vývojářské balíčky,
- lokální skenování bez síťové komunikace.

## Po spuštění

Sekce načítá LaunchAgents aktuálního uživatele a sdílené LaunchAgents, plus přehled systémových LaunchDaemons. Přepínače používají trvalé povolení `launchctl enable/disable` pro přihlášeného uživatele; běžící procesy neukončují. Stav „Povoleno“ neznamená „právě běží“. Systémové služby jsou pouze pro čtení.

Tlačítko „Načíst přihlašovací aplikace“ používá System Events; macOS může požádat o povolení Automatizace. Aplikace lze přidat, vypnout a znovu zapnout. Nimbo si vypnuté přihlašovací položky pamatuje pro obnovení; při opětovném zapnutí je přidá jako viditelné. Moderní položky na pozadí spravované aplikacemi přes ServiceManagement nemusí být v tomto seznamu: pro ně slouží tlačítko „Nastavení macOS“.

Cache doporučené k bezpečnému vyčištění jsou předvybrané. Simulátory, SDK, runtime a archivy vyžadují ruční výběr. Homebrew formule, casky a systémové/globální balíčky jsou pouze informativní a aplikace je nemaže mimo jejich správce balíčků.

Samotné skenování zůstává offline. Google se kontaktuje až po kliknutí na informační ikonu; dotaz obsahuje pouze název, bundle ID a typ položky, nikoli cestu k souboru. Okno nabízí AI režim i běžné výsledky. Google cookies jsou uložené v odděleném WebKit úložišti aplikace, aby nebylo nutné opakovaně potvrzovat souhlas nebo přihlášení.

## Sestavení

Aktualizace aplikace přes Sparkle: kompletní konfigurace, podepisování, notarizace a GitHub Releases jsou popsané v [UPDATES.md](UPDATES.md). První build stáhne připnuté Sparkle s ověřením SHA-256. Verze aplikace se nastavuje v `release.env`. Bez nakonfigurovaného repozitáře a veřejného klíče jsou aktualizace neaktivní.

```bash
chmod +x build.sh
./build.sh
open "build/Nimbo.app"
```

Vyžaduje macOS 14 nebo novější pro běh a Xcode se SDK 26+ pro sestavení Liquid Glass. Kvůli ochraně macOS může být pro skenování některých osobních složek potřeba udělit aplikaci přístup v Nastavení systému → Soukromí a zabezpečení.

## Instalační DMG

```bash
./create-dmg.sh
```

Skript sestaví aplikaci a vytvoří komprimovaný obraz `dist/Nimbo-<verze>-<architektura>.dmg` s aplikací a odkazem na Applications. Verzi a architekturu načítá z aplikace. Existující DMG nepřepisuje; před opakováním ho přesuňte nebo přejmenujte. Skript lze spustit z libovolné pracovní složky.

Pro zabalení již sestavené aplikace použijte `./create-dmg.sh --no-build`. Skript ověří podpis aplikace a integritu obrazu, po dokončení odstraní vlastní dočasné soubory. Samotný balicí skript používá nástroje dodané s macOS a nepřidává Developer ID podpis ani notarizaci. Běžný build je ad-hoc; pro veřejné vydání a Sparkle aktualizace použijte `bash scripts/release.sh prepare` podle [UPDATES.md](UPDATES.md).
