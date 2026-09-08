import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview = "Přehled"
    case cleanup = "Chytrý úklid"
    case largeFiles = "Velké soubory"
    case applications = "Aplikace"
    case startup = "Po spuštění"
    case leftovers = "Zbytky aplikací"
    case development = "Vývojářská data"
    case privacy = "Soukromí"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .cleanup: return "sparkles"
        case .largeFiles: return "externaldrive.fill"
        case .applications: return "app.dashed"
        case .startup: return "power"
        case .leftovers: return "puzzlepiece.extension.fill"
        case .development: return "terminal.fill"
        case .privacy: return "shield.lefthalf.filled"
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
        case .caches: return "Mezipaměť aplikací"
        case .logs: return "Systémové záznamy"
        case .trash: return "Koš"
        case .developer: return "Vývojářská data"
        }
    }

    var subtitle: String {
        switch self {
        case .caches: return "Dočasná data, která aplikace znovu vytvoří"
        case .logs: return "Starší diagnostické a provozní záznamy"
        case .trash: return "Položky, které už jsou v Koši"
        case .developer: return "DerivedData a archivy Xcode"
        }
    }

    var icon: String {
        switch self {
        case .caches: return "shippingbox.fill"
        case .logs: return "doc.text.fill"
        case .trash: return "trash.fill"
        case .developer: return "hammer.fill"
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
    let source: String
    let size: Int64
    let modifiedAt: Date
    var isSelected: Bool = false

    var id: URL { url }
}

enum DevelopmentCategory: String, CaseIterable, Identifiable, Hashable {
    case xcode = "Xcode"
    case android = "Android"
    case node = "Node / npm"
    case homebrew = "Homebrew"
    case java = "Java / JDK"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .xcode: return "hammer.fill"
        case .android: return "cpu.fill"
        case .node: return "shippingbox.fill"
        case .homebrew: return "mug.fill"
        case .java: return "cup.and.saucer.fill"
        }
    }
}

enum ArtifactKind: String, Hashable {
    case cache = "Cache"
    case archive = "Archiv"
    case simulator = "Simulátor"
    case sdk = "SDK"
    case runtime = "Runtime"
    case package = "Balíček"
    case logs = "Logy"
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
    case ai = "AI režim"
    case standard = "Výsledky"

    var id: String { rawValue }

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
