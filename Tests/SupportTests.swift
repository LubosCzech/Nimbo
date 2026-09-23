import Foundation

// Plánování se ověřuje na posunutém čase, ne čekáním. Předvolby jsou v izolované
// doméně, takže test nesahá na nastavení uživatele.
@main
enum SupportTests {
    static let calendar = Calendar(identifier: .gregorian)
    static func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: iso + "T12:00:00Z")!
    }

    static func shouldPrompt(_ now: String, first: String, last: String? = nil,
                             supported: Bool = false) -> Bool {
        SupportSchedule.shouldPrompt(now: date(now), firstLaunch: date(first),
                                     lastPrompt: last.map(date), hasSupported: supported,
                                     calendar: calendar)
    }

    static func main() {
        // Týden po prvním spuštění, ne dřív.
        precondition(!shouldPrompt("2026-01-01", first: "2026-01-01"))
        precondition(!shouldPrompt("2026-01-07", first: "2026-01-01"))
        precondition(shouldPrompt("2026-01-08", first: "2026-01-01"))

        // Pak měsíc od posledního dotazu, ne od instalace.
        precondition(!shouldPrompt("2026-02-01", first: "2026-01-01", last: "2026-01-08"))
        precondition(shouldPrompt("2026-02-08", first: "2026-01-01", last: "2026-01-08"))
        precondition(shouldPrompt("2026-03-08", first: "2026-01-01", last: "2026-02-08"))

        // Měsíc je kalendářní, ne 30 dní: po únorovém dotazu se čeká na březen.
        precondition(!shouldPrompt("2026-03-02", first: "2026-01-01", last: "2026-02-03"))
        precondition(shouldPrompt("2026-03-03", first: "2026-01-01", last: "2026-02-03"))

        // Kdo řekl, že přispěl, se nedozví už nic.
        precondition(!shouldPrompt("2027-01-01", first: "2026-01-01", last: "2026-01-08", supported: true))
        precondition(!shouldPrompt("2027-01-01", first: "2026-01-01", supported: true))

        // Posunuté hodiny nesmějí spustit dotaz znovu ani ho zablokovat navždy.
        precondition(!shouldPrompt("2026-01-05", first: "2026-01-01", last: "2026-01-08"))
        precondition(!shouldPrompt("2025-12-01", first: "2026-01-01"))
        precondition(shouldPrompt("2026-02-09", first: "2026-01-01", last: "2026-01-08"))

        // Uložení: první spuštění se zapamatuje, potvrzení je trvalé.
        let suite = "dev.svtk.nimbo.tests.support"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        var clock = date("2026-01-01")
        let service = MainActor.assumeIsolated {
            SupportService(defaults: defaults, now: { clock })
        }
        MainActor.assumeIsolated {
            service.promptIfDue()
            precondition(!service.isPrompting, "hned po instalaci se neptáme")
            clock = date("2026-01-09")
            service.promptIfDue()
            precondition(service.isPrompting, "po týdnu se zeptat máme")
            service.postpone()
            precondition(!service.isPrompting)
            service.promptIfDue()
            precondition(!service.isPrompting, "podruhé týž den ne")

            clock = date("2026-02-10")
            var opened: URL?
            service.support(open: { opened = $0; return true })
            precondition(opened == SupportLink.page)
            precondition(service.hasSupported)
            clock = date("2027-06-01")
            service.promptIfDue()
            precondition(!service.isPrompting, "po podpoře už nikdy")
        }

        // Adresa se ověřuje offline: že je to https a ten správný profil.
        // Překlep v odkazu na podporu by se jinak projevil až u uživatele.
        precondition(SupportLink.page.scheme == "https")
        precondition(SupportLink.page.host() == "buymeacoffee.com")
        precondition(SupportLink.page.path() == "/svtkdev")

        print("PASS: prompt after a week then monthly, calendar months, clock changes, acknowledgement is final, donation link points where it should. No user preferences touched.")
    }
}
