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
                                 kind: "Systémová služba", enabled: true)
        precondition(!system.canToggle)
        let unknown = StartupItem(name: "Test", path: "/fixture/test.plist", label: "com.test.service",
                                  kind: "Uživatelská služba", enabled: nil)
        precondition(!unknown.canToggle)
        let services = try StartupService.services()
        precondition(services.allSatisfy { $0.path.hasSuffix(".plist") })
        print("PASS: state parsing, restricted and unknown states; read-only scan: \(services.count) services. No startup settings changed.")
    }
}
