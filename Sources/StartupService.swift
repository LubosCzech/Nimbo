import Foundation

/// What kind of startup entry this is. Behaviour keys off the case, never off
/// the displayed title: comparing translated text decided, until 1.7, whether a
/// system daemon could be toggled at all.
enum StartupKind: String, Codable, Hashable, CaseIterable {
    case loginItem, userAgent, sharedAgent, systemDaemon

    var title: String {
        switch self {
        case .loginItem: return String(localized: "Aplikace")
        case .userAgent: return String(localized: "Uživatelská služba")
        case .sharedAgent: return String(localized: "Sdílený agent")
        case .systemDaemon: return String(localized: "Systémová služba")
        }
    }

    /// Only login items go through System Events.
    var isLoginItem: Bool { self == .loginItem }
    /// System daemons stay read-only, whatever the interface language.
    var isSystemDaemon: Bool { self == .systemDaemon }

    // Versions up to 1.6.1 stored the Czech title. Reading it keeps the saved
    // list of switched-off items, which cannot be reconstructed from the system.
    private static let legacyTitles: [String: StartupKind] = [
        "Aplikace": .loginItem, "Uživatelská služba": .userAgent,
        "Sdílený agent": .sharedAgent, "Systémová služba": .systemDaemon
    ]

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = StartupKind(rawValue: raw) ?? StartupKind.legacyTitles[raw] else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: String(localized: "Neznámý druh položky: \(raw)")))
        }
        self = value
    }
}

struct StartupItem: Identifiable, Codable {
    let name: String
    let path: String
    let label: String
    let kind: StartupKind
    var enabled: Bool?
    var id: String { kind.rawValue + ":" + path }
    var canToggle: Bool { !kind.isSystemDaemon && enabled != nil && !label.hasPrefix("com.apple.") }
}

enum StartupService {
    static let savedKey = "disabledLoginItems"
    static func command(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: timeout)
        defer { timeout.cancel() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "Nimbo.Startup", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: text])
        }
        return text
    }

    static func loginItems() throws -> [StartupItem] {
        let script = """
        const items = Application('System Events').loginItems();
        JSON.stringify(items.map(i => ({name:i.name(),path:i.path(),label:'',kind:'loginItem',enabled:true})));
        """
        let text = try command("/usr/bin/osascript", ["-l", "JavaScript", "-e", script])
        let active = try JSONDecoder().decode([StartupItem].self, from: Data(text.utf8))
        let inactive = savedApps().filter { saved in !active.contains { $0.path == saved.path } }
        return (active + inactive).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func savedApps() -> [StartupItem] {
        guard let data = UserDefaults.standard.data(forKey: savedKey) else { return [] }
        return (try? JSONDecoder().decode([StartupItem].self, from: data)) ?? []
    }

    static func setLogin(_ item: StartupItem, enabled: Bool) throws {
        let script = """
        function run(argv) {
            const se = Application('System Events');
            const path = argv[0];
            const matching = se.loginItems().filter(i => i.path() === path);
            if (argv[1] === 'enable') {
                if (matching.length === 0) se.loginItems.push(se.LoginItem({path:path,hidden:false}));
            } else {
                matching.forEach(i => i.delete());
            }
        }
        """
        if enabled && !FileManager.default.fileExists(atPath: item.path) {
            throw NSError(domain: "Nimbo.Startup", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Aplikace již neexistuje: \(item.path)")])
        }
        // Save the restore target before removal, so interrupted operations remain reversible.
        var saved = savedApps().filter { $0.path != item.path }
        if !enabled { var copy = item; copy.enabled = false; saved.append(copy) }
        if !enabled { UserDefaults.standard.set(try JSONEncoder().encode(saved), forKey: savedKey) }
        _ = try command("/usr/bin/osascript", ["-l", "JavaScript", "-e", script, item.path, enabled ? "enable" : "disable"])
        UserDefaults.standard.set(try JSONEncoder().encode(saved), forKey: savedKey)
        let actual = try loginItems().first { $0.path == item.path }?.enabled ?? false
        guard actual == enabled else {
            throw NSError(domain: "Nimbo.Startup", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "macOS změnu nepotvrdil. Obnovte seznam nebo použijte Nastavení systému.")])
        }
    }

    static func disabledOverrides(_ output: String) -> [String: Bool] {
        var values: [String: Bool] = [:]
        for line in output.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let state = parts[1].trimmingCharacters(in: .whitespaces)
            if state == "disabled" || state == "true" { values[label] = true }
            if state == "enabled" || state == "false" { values[label] = false }
        }
        return values
    }

    static func services() throws -> [StartupItem] {
        let fm = FileManager.default
        let domain = "gui/\(getuid())"
        let overrides = disabledOverrides(try command("/bin/launchctl", ["print-disabled", domain]))
        let systemOverrides = (try? command("/bin/launchctl", ["print-disabled", "system"])).map(disabledOverrides)
        let roots = [(fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents").path, StartupKind.userAgent),
                     ("/Library/LaunchAgents", StartupKind.sharedAgent), ("/Library/LaunchDaemons", StartupKind.systemDaemon)]
        var items: [StartupItem] = []
        for (root, kind) in roots {
            guard fm.fileExists(atPath: root) else { continue }
            let files = try fm.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: file),
                      let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                      let label = plist["Label"] as? String else {
                    items.append(StartupItem(name: file.deletingPathExtension().lastPathComponent + String(localized: " (nelze načíst)"),
                        path: file.path, label: "", kind: kind, enabled: nil))
                    continue
                }
                let state = kind.isSystemDaemon ? systemOverrides : overrides
                let enabled = state.map { !($0[label] ?? (plist["Disabled"] as? Bool ?? false)) }
                items.append(StartupItem(name: label, path: file.path, label: label, kind: kind, enabled: enabled))
            }
        }
        return items.sorted { $0.name < $1.name }
    }

    static func setService(_ item: StartupItem, enabled: Bool) throws {
        let current = try services()
        guard let verified = current.first(where: { $0.id == item.id }), verified.canToggle,
              current.filter({ $0.label == verified.label && !$0.kind.isSystemDaemon }).count == 1 else {
            throw NSError(domain: "Nimbo.Startup", code: 3, userInfo: [NSLocalizedDescriptionKey: String(localized: "Položku nelze jednoznačně změnit. Použijte Nastavení systému.")])
        }
        let domain = "gui/\(getuid())"
        _ = try command("/bin/launchctl", [enabled ? "enable" : "disable", "\(domain)/\(verified.label)"])
        let state = disabledOverrides(try command("/bin/launchctl", ["print-disabled", domain]))
        guard state[verified.label] == !enabled else {
            throw NSError(domain: "Nimbo.Startup", code: 4, userInfo: [NSLocalizedDescriptionKey: String(localized: "Změnu povolení se nepodařilo ověřit.")])
        }
    }
}
