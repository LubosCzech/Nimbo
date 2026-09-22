# Nimbo 1.6

## Podepsané a notarizované vydání

- Nimbo je nově podepsané Apple Developer ID a ověřené notarizací u Applu. macOS už při první instalaci nepožaduje ruční povolení.
- Udělená oprávnění nově přežijí aktualizaci. U dřívějších ad-hoc verzí se po každé aktualizaci ztrácela, protože macOS považoval novou verzi za jinou aplikaci.
- Při aktualizaci z verze 1.5 požádá macOS o oprávnění ještě jednou naposledy, protože se mění podpis aplikace a její identifikátor. Od 1.6 dál už zůstanou zachovaná.
- Identifikátor aplikace se sjednotil se studiem na dev.svtk.nimbo. Nastavení vzhledu i seznam vypnutých přihlašovacích položek se přenesou automaticky, takže vypnuté položky lze i po aktualizaci obnovit.

## Srozumitelné odstraňování

- Nimbo nyní rozliší, proč macOS položku odmítl odstranit: chybějící Úplný přístup k disku, vlastnictví jiným uživatelem nebo ochrana systému. U každé příčiny nabídne jen to řešení, které skutečně pomůže; dřív se všechny případy sloučily do jedné obecné rady.
- Aplikace patřící roota jde dokončit tlačítkem „Dokončit přes Finder“. Ověření správce si vyžádá Finder. Nimbo heslo nevidí a nic nespouští s právy roota.
- Pokud macOS brání v úpravě jiných aplikací, Nimbo na to upozorní a otevře Správu aplikací v nastavení. Bez tohoto souhlasu odmítne macOS odinstalaci bez ohledu na to, kdo ji provádí.
- U položky, ke které macOS odepře i pouhé zjištění existence, se dřív operace tiše přeskočila a započítala jako uklizená. Nově je vždy nahlášená.
- Úklidové sekce hlásí důvod selhání stejně podrobně jako odinstalace, včetně vlastníka, práv a systémových příznaků v technickém detailu.

## O aplikaci

- Nové okno „O aplikaci Nimbo“ s verzí sestavení a odkazem na studio svtk.dev.
