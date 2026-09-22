import Foundation

/// Minimal surface of `UserDefaults` the migration needs, so it can be tested
/// without writing to a real preferences domain.
protocol PreferenceStore {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: PreferenceStore {}

/// Carries settings across the change of bundle identifier.
///
/// Preferences live in a file named after the bundle identifier, so renaming it
/// would silently reset everything. Losing `appAppearance` would be cosmetic;
/// losing the disabled login items would not — that list is how Nimbo restores
/// what the user switched off, and without it those items cannot be brought
/// back. Window frames and Sparkle's own bookkeeping are deliberately left
/// behind: they belong to the old bundle and are cheap to rebuild.
enum PreferencesMigration {
    static var legacyDomain: String { NimboIdentity.legacyBundleIdentifier }
    static let markerKey = "migratedFromLegacyDomain"
    static let migratedKeys = ["appAppearance", StartupService.savedKey]

    /// Runs once, and never overwrites a value the user already set under the
    /// new identifier.
    static func keysToCopy(legacy: (String) -> Any?, store: PreferenceStore) -> [String] {
        guard store.object(forKey: markerKey) == nil else { return [] }
        return migratedKeys.filter { store.object(forKey: $0) == nil && legacy($0) != nil }
    }

    static func run(store: PreferenceStore = UserDefaults.standard,
                    legacy: (String) -> Any? = legacyValue) {
        guard store.object(forKey: markerKey) == nil else { return }
        for key in keysToCopy(legacy: legacy, store: store) {
            store.set(legacy(key), forKey: key)
        }
        store.set(true, forKey: markerKey)
    }

    // CFPreferencesCopyAppValue reads that domain exactly, unlike a UserDefaults
    // suite, which would also answer from the global domain.
    static func legacyValue(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, legacyDomain as CFString)
    }
}
