import Foundation

// A dictionary stands in for the preferences domain: no real defaults are read
// or written, so the suite leaves no file behind.
final class FakeStore: PreferenceStore {
    var values: [String: Any]
    init(_ values: [String: Any] = [:]) { self.values = values }
    func object(forKey defaultName: String) -> Any? { values[defaultName] }
    func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
}

@main
enum PreferencesMigrationTests {
    static let appearance = "appAppearance"
    static let loginItems = StartupService.savedKey

    static func legacy(_ pairs: [String: Any]) -> (String) -> Any? { { pairs[$0] } }

    static func main() {
        precondition(PreferencesMigration.migratedKeys.contains(loginItems),
                     "Disabled login items must survive; they cannot be reconstructed.")

        // A fresh install under the new identifier inherits the old settings.
        let fresh = FakeStore()
        PreferencesMigration.run(store: fresh,
                                 legacy: legacy([appearance: "dark", loginItems: Data([1, 2, 3])]))
        precondition(fresh.values[appearance] as? String == "dark")
        precondition(fresh.values[loginItems] as? Data == Data([1, 2, 3]))
        precondition(fresh.values[PreferencesMigration.markerKey] as? Bool == true)

        // It never runs twice, so a later deliberate change is not undone.
        fresh.values[appearance] = "light"
        PreferencesMigration.run(store: fresh, legacy: legacy([appearance: "dark"]))
        precondition(fresh.values[appearance] as? String == "light")

        // A value already set under the new identifier wins over the old one.
        let existing = FakeStore([appearance: "light"])
        PreferencesMigration.run(store: existing, legacy: legacy([appearance: "dark"]))
        precondition(existing.values[appearance] as? String == "light")

        // Nothing to inherit is still a completed migration, not a retry loop.
        let empty = FakeStore()
        PreferencesMigration.run(store: empty, legacy: legacy([:]))
        precondition(empty.values[PreferencesMigration.markerKey] as? Bool == true)
        precondition(empty.values[appearance] == nil)

        // Only Nimbo's own keys travel; window frames and Sparkle stay behind.
        let selective = FakeStore()
        let copied = PreferencesMigration.keysToCopy(
            legacy: legacy([appearance: "dark", "SUSkippedVersion": "9", "NSWindow Frame Main": "0 0"]),
            store: selective)
        precondition(copied == [appearance])

        print("PASS: settings inherited once, user's own values win, login-item restore list preserved. No real preferences touched.")
    }
}
