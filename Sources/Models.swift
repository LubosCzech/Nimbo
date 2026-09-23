import Foundation

/// Who Nimbo is, for code that must not treat the app's own data as someone
/// else's. 1.6.1 renamed the bundle, so the former identifier counts too.
enum NimboIdentity {
    static let legacyBundleIdentifier = "local.nimbo.app"
    static var all: Set<String> {
        Set([Bundle.main.bundleIdentifier, legacyBundleIdentifier].compactMap { $0 })
    }
}


// Raw values are identity: they end up in tags, selections and comparisons.
// Titles are what the user reads, and change with the interface language.
enum SidebarSection: String, CaseIterable, Identifiable {
    case overview, performance, cleanup, largeFiles, applications, startup, leftovers, development, privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return String(localized: "Přehled")
        case .performance: return String(localized: "Výkon")
        case .cleanup: return String(localized: "Chytrý úklid")
        case .largeFiles: return String(localized: "Velké soubory")
        case .applications: return String(localized: "Aplikace")
        case .startup: return String(localized: "Po spuštění")
        case .leftovers: return String(localized: "Zbytky aplikací")
        case .development: return String(localized: "Vývojářská data")
        case .privacy: return String(localized: "Soukromí")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .performance: return "speedometer"
        case .cleanup: return "sparkles"
        case .largeFiles: return "doc.text.magnifyingglass"
        case .applications: return "app"
        case .startup: return "power"
        case .leftovers: return "puzzlepiece.extension"
        case .development: return "terminal"
        case .privacy: return "checkmark.shield"
        }
    }
}

enum CleanupKind: String, CaseIterable, Identifiable, Hashable {
    case caches
    case logs
    case trash
    case developer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caches: return String(localized: "Mezipaměť aplikací")
        case .logs: return String(localized: "Systémové záznamy")
        case .trash: return String(localized: "Koš")
        case .developer: return String(localized: "Vývojářská data")
        }
    }

    var subtitle: String {
        switch self {
        case .caches: return String(localized: "Dočasná data, která aplikace znovu vytvoří")
        case .logs: return String(localized: "Starší diagnostické a provozní záznamy")
        case .trash: return String(localized: "Položky, které už jsou v Koši")
        case .developer: return "DerivedData a archivy Xcode"
        }
    }

    var icon: String {
        switch self {
        case .caches: return "shippingbox"
        case .logs: return "doc.text"
        case .trash: return "trash"
        case .developer: return "hammer"
        }
    }
}

struct CleanupGroup: Identifiable, Hashable {
    let kind: CleanupKind
    let items: [CleanupItem]
    let size: Int64
    var isSelected: Bool

    var id: CleanupKind { kind }
    var urls: [URL] { items.map(\.url) }
}

struct CleanupItem: Identifiable, Hashable {
    let url: URL
    let size: Int64

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct LargeFile: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let modifiedAt: Date
    var isSelected: Bool = false

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var folder: String { url.deletingLastPathComponent().path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~") }
}

struct InstalledApplication: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleIdentifier: String?
    let version: String
    let size: Int64
    let modifiedAt: Date

    var id: URL { url }
}

struct AppRemovalPlan: Identifiable {
    let app: InstalledApplication
    var relatedFiles: [RelatedFile]
    var id: URL { app.url }

    var selectedURLs: [URL] {
        [app.url] + relatedFiles.filter(\.isSelected).map(\.url)
    }

    var selectedSize: Int64 {
        app.size + relatedFiles.filter(\.isSelected).reduce(0) { $0 + $1.size }
    }
}

struct RelatedFile: Identifiable, Hashable {
    let url: URL
    let size: Int64
    var isSelected: Bool = true
    var id: URL { url }
}

struct OrphanedAppData: Identifiable, Hashable {
    let url: URL
    let bundleIdentifier: String
    let source: OrphanSource
    let size: Int64
    let modifiedAt: Date
    var isSelected: Bool = false

    var id: URL { url }
}

enum DevelopmentCategory: String, CaseIterable, Identifiable, Hashable {
    case xcode, android, node, homebrew, java

    // Product names, so the title is the same in every language.
    var title: String {
        switch self {
        case .xcode: return "Xcode"
        case .android: return "Android"
        case .node: return "Node / npm"
        case .homebrew: return "Homebrew"
        case .java: return "Java / JDK"
        }
    }

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .xcode: return "hammer"
        case .android: return "cpu"
        case .node: return "shippingbox"
        case .homebrew: return "mug"
        case .java: return "cup.and.saucer"
        }
    }
}

enum ArtifactKind: String, Hashable {
    case cache, archive, simulator, sdk, runtime, package, logs

    var title: String {
        switch self {
        case .cache: return String(localized: "Cache")
        case .archive: return String(localized: "Archiv")
        case .simulator: return String(localized: "Simulátor")
        case .sdk: return "SDK"
        case .runtime: return "Runtime"
        case .package: return String(localized: "Balíček")
        case .logs: return String(localized: "Logy")
        }
    }
}

struct DeveloperArtifact: Identifiable, Hashable {
    let url: URL
    let title: String
    let detail: String
    let category: DevelopmentCategory
    let kind: ArtifactKind
    let size: Int64
    let isRecommended: Bool
    let canRemove: Bool
    var isSelected: Bool

    var id: URL { url }
}

struct WebLookup: Identifiable {
    let id = UUID()
    let title: String
    let query: String
    let context: String

    func searchURL(for mode: GoogleSearchMode) -> URL {
        var components = URLComponents(string: "https://www.google.com/search")!
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "hl", value: "cs")
        ]
        if mode == .ai { items.append(URLQueryItem(name: "udm", value: "50")) }
        components.queryItems = items
        return components.url!
    }
}

enum GoogleSearchMode: String, CaseIterable, Identifiable {
    case ai, standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ai: return String(localized: "AI režim")
        case .standard: return String(localized: "Výsledky")
        }
    }

    var icon: String {
        switch self {
        case .ai: return "sparkles"
        case .standard: return "list.bullet"
        }
    }
}

extension Int64 {
    var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

/// Where a leftover was found. The icon lives here rather than being chosen by
/// comparing the displayed text, which stopped working in any other language.
enum OrphanSource: String, CaseIterable, Hashable {
    case applicationSupport, caches, preferences, savedState, container, httpStorage, webKit

    var title: String {
        switch self {
        case .applicationSupport: return String(localized: "Data aplikace")
        case .caches: return String(localized: "Mezipaměť")
        case .preferences: return String(localized: "Nastavení")
        case .savedState: return String(localized: "Uložený stav")
        case .container: return String(localized: "Kontejner")
        case .httpStorage: return String(localized: "HTTP úložiště")
        case .webKit: return String(localized: "WebKit data")
        }
    }

    var icon: String {
        switch self {
        case .caches: return CleanupKind.caches.icon
        case .preferences: return "slider.horizontal.3"
        case .container: return "cube"
        default: return "doc"
        }
    }
}
