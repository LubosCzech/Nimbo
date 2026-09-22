import Foundation

@main enum StartupTests {
    static func main() throws {
        let parsed = StartupService.disabledOverrides("""
            disabled services = {
                "com.example.one" => disabled
                "com.example.two" => enabled
                "com.example.three" => true
                "com.example.four" => false
            }
        """)
        precondition(parsed == ["com.example.one": true, "com.example.two": false,
                                "com.example.three": true, "com.example.four": false])
        let system = StartupItem(name: "Test", path: "/fixture/test.plist", label: "com.test.service",
                                 kind: .systemDaemon, enabled: true)
        precondition(!system.canToggle)
        let unknown = StartupItem(name: "Test", path: "/fixture/test.plist", label: "com.test.service",
                                  kind: .userAgent, enabled: nil)
        precondition(!unknown.canToggle)
        // Systémové služby musí zůstat jen pro čtení ve všech jazycích: dřív o tom
        // rozhodovalo porovnání zobrazovaného textu.
        precondition(StartupKind.systemDaemon.isSystemDaemon && !StartupKind.loginItem.isSystemDaemon)
        precondition(StartupKind.loginItem.isLoginItem && !StartupKind.userAgent.isLoginItem)
        precondition(StartupKind.allCases.allSatisfy { !$0.rawValue.contains(" ") })

        // Uložený seznam vypnutých položek z verzí do 1.6.1 nesmí zmizet.
        for (legacy, expected) in [("Aplikace", StartupKind.loginItem),
                                   ("Uživatelská služba", .userAgent),
                                   ("Sdílený agent", .sharedAgent),
                                   ("Systémová služba", .systemDaemon)] {
            let json = Data("{\"name\":\"N\",\"path\":\"/p\",\"label\":\"l\",\"kind\":\"\(legacy)\"}".utf8)
            let decoded = try JSONDecoder().decode(StartupItem.self, from: json)
            precondition(decoded.kind == expected, "starý tvar \(legacy) se nenačetl")
        }
        let roundTrip = try JSONDecoder().decode(StartupItem.self, from: try JSONEncoder().encode(
            StartupItem(name: "N", path: "/p", label: "l", kind: .sharedAgent, enabled: false)))
        precondition(roundTrip.kind == .sharedAgent)

        let services = try StartupService.services()
        precondition(services.allSatisfy { $0.path.hasSuffix(".plist") })
        print("PASS: state parsing, read-only system services by case not by text, legacy saved items still decode; read-only scan: \(services.count) services. No startup settings changed.")
    }
}
