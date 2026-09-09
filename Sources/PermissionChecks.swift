import AppKit
import CoreServices
import Darwin
import Foundation

enum PermissionState: String, Sendable {
    case checking, available, denied, notRequested, notApplicable, unknown

    var needsAttention: Bool { self == .denied || self == .notRequested || self == .unknown }
    var title: String {
        switch self {
        case .checking: return "Kontroluji…"
        case .available: return "Dostupné"
        case .denied: return "Omezený přístup"
        case .notRequested: return "Čeká na souhlas"
        case .notApplicable: return "Nenalezeno"
        case .unknown: return "Nelze ověřit"
        }
    }
}

enum PermissionScope: String, CaseIterable, Identifiable, Sendable {
    case personalFiles, cleanup, appData, development, applications, startup, automation
    var id: String { rawValue }

    var title: String {
        switch self {
        case .personalFiles: return "Osobní složky"
        case .cleanup: return "Úklid a Koš"
        case .appData: return "Data aplikací"
        case .development: return "Vývojářské nástroje"
        case .applications: return "Seznam aplikací"
        case .startup: return "Služby po spuštění"
        case .automation: return "Automatizace System Events"
        }
    }

    var purpose: String {
        switch self {
        case .personalFiles: return "Hledání velkých souborů na Ploše, ve Stažených souborech a dalších osobních složkách."
        case .cleanup: return "Čtení mezipaměti, záznamů, Koše a dat Xcode."
        case .appData: return "Hledání souvisejících dat a zbytků odinstalovaných aplikací."
        case .development: return "Xcode, Android, Java, Node a Homebrew; existující kořenové složky."
        case .applications: return "Načtení aplikací. Přesun konkrétní aplikace může později vyžadovat správce."
        case .startup: return "Čtení konfigurací služeb. Systémové služby zůstávají pouze pro čtení."
        case .automation: return "Volitelné: potřebné pro čtení a změnu přihlašovacích aplikací, ne pro úklid."
        }
    }

    // Only directories already used by Nimbo. Never probe TCC databases, Mail,
    // browser history or other unrelated private data to guess FDA entitlement.
    var relativePaths: [String] {
        switch self {
        case .personalFiles: return ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"]
        case .cleanup: return ["Library/Caches", "Library/Logs", ".Trash",
                               "Library/Developer/Xcode/DerivedData", "Library/Developer/Xcode/Archives"]
        case .appData: return ["Library/Application Support", "Library/Preferences", "Library/Containers",
                               "Library/Saved Application State", "Library/HTTPStorages", "Library/WebKit"]
        case .development: return [
            "Library/Developer/Xcode/iOS DeviceSupport", "Library/Developer/CoreSimulator/Caches",
            "Library/Developer/CoreSimulator/Devices", "Library/Android/sdk/system-images",
            "Library/Android/sdk/platforms", "Library/Android/sdk/build-tools",
            ".gradle/caches", ".gradle/daemon", ".gradle/wrapper/dists", ".android/cache", ".android/avd",
            ".npm/_cacache", ".npm/_logs", ".node-gyp", ".pnpm-store", ".nvm/versions/node", ".m2/repository",
            "Library/Caches/Yarn", "Library/Caches/Homebrew", "Library/Logs/Homebrew",
            "Library/Java/JavaVirtualMachines", "/Library/Java/JavaVirtualMachines",
            "/opt/homebrew/lib/node_modules", "/usr/local/lib/node_modules",
            "/opt/homebrew/Cellar", "/opt/homebrew/Caskroom", "/usr/local/Cellar", "/usr/local/Caskroom"
        ]
        case .applications: return ["/Applications", "/System/Applications", "Applications"]
        case .startup: return ["Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"]
        case .automation: return []
        }
    }
}

struct PermissionProbe: Equatable, Sendable {
    let path: String
    let state: PermissionState
    let code: Int32?
}

struct PermissionCheck: Identifiable, Sendable {
    let scope: PermissionScope
    let state: PermissionState
    var probes: [PermissionProbe] = []
    var note: String? = nil
    var id: PermissionScope { scope }
    var issues: [PermissionProbe] { probes.filter { $0.state.needsAttention } }
}

enum PermissionChecks {
    static func classifyDirectoryError(_ code: Int32) -> PermissionState {
        switch code {
        case EPERM, EACCES: return .denied
        case ENOENT: return .notApplicable
        default: return .unknown
        }
    }

    static func directory(_ url: URL) -> PermissionProbe {
        // A real read-access attempt, unlike fileExists/access(2), which cannot
        // reliably detect TCC restrictions. No names or file contents are read.
        // macOS may display its own Files & Folders consent dialog here.
        let handle = url.withUnsafeFileSystemRepresentation { path in
            path.flatMap { opendir($0) }
        }
        guard let handle else {
            let code = errno
            return PermissionProbe(path: url.path, state: classifyDirectoryError(code), code: code)
        }
        closedir(handle)
        return PermissionProbe(path: url.path, state: .available, code: nil)
    }

    static func aggregate(_ scope: PermissionScope, probes: [PermissionProbe]) -> PermissionCheck {
        let state: PermissionState
        if probes.contains(where: { $0.state == .denied }) { state = .denied }
        else if probes.contains(where: { $0.state == .unknown }) { state = .unknown }
        else if probes.contains(where: { $0.state == .available }) { state = .available }
        else { state = .notApplicable }
        return PermissionCheck(scope: scope, state: state, probes: probes)
    }

    static func automationResult(_ status: OSStatus) -> PermissionCheck {
        switch status {
        case noErr: return PermissionCheck(scope: .automation, state: .available)
        case OSStatus(errAEEventNotPermitted):
            return PermissionCheck(scope: .automation, state: .denied,
                note: "macOS odepřel automatizaci. Povolte Nimbo → System Events v Nastavení systému → Soukromí a zabezpečení → Automatizace.")
        case OSStatus(errAEEventWouldRequireUserConsent):
            return PermissionCheck(scope: .automation, state: .notRequested,
                note: "Souhlas ještě nebyl udělen. O systémový dialog požádáte tlačítkem Povolit automatizaci.")
        case OSStatus(procNotFound):
            return PermissionCheck(scope: .automation, state: .unknown,
                note: "System Events neběží, proto stav nelze zjistit. Není to důkaz zamítnutí oprávnění.")
        default:
            return PermissionCheck(scope: .automation, state: .unknown,
                note: "macOS nevrátil jednoznačný stav automatizace (kód \(status)).")
        }
    }

    static func automation(askUser: Bool = false) -> PermissionCheck {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        return automationResult(AEDeterminePermissionToAutomateTarget(
            target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), askUser))
    }

    static func check(_ scope: PermissionScope, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                      probe: (URL) -> PermissionProbe = directory) -> PermissionCheck {
        if scope == .automation { return automation() }
        return aggregate(scope, probes: scope.relativePaths.map {
            probe($0.hasPrefix("/") ? URL(fileURLWithPath: $0) : home.appendingPathComponent($0))
        })
    }
}
