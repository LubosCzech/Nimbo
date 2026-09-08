import AppKit
import Foundation

enum FileScanner {
    private static let sizeKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
        .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey
    ]

    static func allocatedSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: sizeKeys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        if values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        guard values.isDirectory == true else { return 0 }
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(sizeKeys),
            options: options,
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let childValues = try? child.resourceValues(forKeys: sizeKeys),
                  childValues.isRegularFile == true,
                  childValues.isSymbolicLink != true else { continue }
            total += Int64(childValues.totalFileAllocatedSize ?? childValues.fileSize ?? 0)
        }
        return total
    }

    static func scanCleanup() -> [CleanupGroup] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let definitions: [(CleanupKind, [URL])] = [
            (.caches, [home.appendingPathComponent("Library/Caches", isDirectory: true)]),
            (.logs, [home.appendingPathComponent("Library/Logs", isDirectory: true)]),
            (.trash, [home.appendingPathComponent(".Trash", isDirectory: true)]),
            (.developer, [
                home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true),
                home.appendingPathComponent("Library/Developer/Xcode/Archives", isDirectory: true)
            ])
        ]

        return definitions.map { kind, roots in
            let existingRoots = roots.filter { FileManager.default.fileExists(atPath: $0.path) }
            let contents = existingRoots.flatMap { root in
                (try? FileManager.default.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsSubdirectoryDescendants]
                )) ?? []
            }
            let items = contents
                .map { CleanupItem(url: $0, size: allocatedSize(of: $0)) }
                .sorted { $0.size > $1.size }
            let size = items.reduce(Int64(0)) { $0 + $1.size }
            return CleanupGroup(kind: kind, items: items, size: size, isSelected: size > 0)
        }
    }

    static func scanLargeFiles(minimumSize: Int64) -> [LargeFile] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        var files: [LargeFile] = []

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(sizeKeys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: sizeKeys),
                      values.isRegularFile == true,
                      values.isSymbolicLink != true else { continue }
                let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                guard size >= minimumSize else { continue }
                files.append(LargeFile(url: url, size: size, modifiedAt: values.contentModificationDate ?? .distantPast))
            }
        }
        return files.sorted { $0.size > $1.size }
    }

    static func scanApplications() -> [InstalledApplication] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var seen = Set<String>()
        var apps: [InstalledApplication] = []

        for root in roots where fm.fileExists(atPath: root.path) {
            guard let urls = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in urls where url.pathExtension.lowercased() == "app" {
                guard seen.insert(url.standardizedFileURL.path).inserted else { continue }
                let bundle = Bundle(url: url)
                let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let version = (bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                apps.append(InstalledApplication(
                    url: url,
                    name: displayName,
                    bundleIdentifier: bundle?.bundleIdentifier,
                    version: version,
                    size: allocatedSize(of: url),
                    modifiedAt: modified
                ))
            }
        }
        return apps.sorted { $0.size > $1.size }
    }

    static func removalPlan(for app: InstalledApplication) -> AppRemovalPlan {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let bundleID = app.bundleIdentifier, !bundleID.isEmpty else {
            return AppRemovalPlan(app: app, relatedFiles: [])
        }
        let candidates = [
            "Library/Application Support/\(bundleID)",
            "Library/Caches/\(bundleID)",
            "Library/Preferences/\(bundleID).plist",
            "Library/Saved Application State/\(bundleID).savedState",
            "Library/Containers/\(bundleID)",
            "Library/HTTPStorages/\(bundleID)",
            "Library/WebKit/\(bundleID)"
        ].map { home.appendingPathComponent($0) }

        let related = candidates
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { RelatedFile(url: $0, size: allocatedSize(of: $0)) }
        return AppRemovalPlan(app: app, relatedFiles: related)
    }

    static func scanOrphanedAppData() -> [OrphanedAppData] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let installedIDs = installedBundleIdentifiers()
        let locations: [(String, URL, String)] = [
            ("Application Support", home.appendingPathComponent("Library/Application Support"), ""),
            ("Cache", home.appendingPathComponent("Library/Caches"), ""),
            ("Nastavení", home.appendingPathComponent("Library/Preferences"), ".plist"),
            ("Uložený stav", home.appendingPathComponent("Library/Saved Application State"), ".savedState"),
            ("Kontejner", home.appendingPathComponent("Library/Containers"), ""),
            ("HTTP úložiště", home.appendingPathComponent("Library/HTTPStorages"), ""),
            ("WebKit data", home.appendingPathComponent("Library/WebKit"), "")
        ]
        var seen = Set<String>()
        var results: [OrphanedAppData] = []

        for (source, root, suffix) in locations {
            guard let children = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in children {
                var candidate = url.lastPathComponent
                if !suffix.isEmpty {
                    guard candidate.hasSuffix(suffix) else { continue }
                    candidate.removeLast(suffix.count)
                }
                guard looksLikeBundleIdentifier(candidate),
                      !isRelated(candidate, toAny: installedIDs),
                      seen.insert(url.standardizedFileURL.path).inserted else { continue }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                results.append(OrphanedAppData(
                    url: url,
                    bundleIdentifier: candidate,
                    source: source,
                    size: allocatedSize(of: url),
                    modifiedAt: modified
                ))
            }
        }
        return results.sorted { $0.size > $1.size }
    }

    static func scanDeveloperArtifacts() -> [DeveloperArtifact] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var results: [DeveloperArtifact] = []

        func add(_ relativePath: String, title: String, detail: String, category: DevelopmentCategory, kind: ArtifactKind, recommended: Bool, canRemove: Bool = true) {
            let url: URL
            if relativePath.hasPrefix("/") { url = URL(fileURLWithPath: relativePath) }
            else { url = home.appendingPathComponent(relativePath) }
            guard fm.fileExists(atPath: url.path) else { return }
            results.append(DeveloperArtifact(
                url: url, title: title, detail: detail, category: category, kind: kind,
                size: allocatedSize(of: url), isRecommended: recommended,
                canRemove: canRemove, isSelected: recommended && canRemove
            ))
        }

        func addChildren(of relativePath: String, category: DevelopmentCategory, kind: ArtifactKind, detail: String, canRemove: Bool = true) {
            let root = relativePath.hasPrefix("/") ? URL(fileURLWithPath: relativePath) : home.appendingPathComponent(relativePath)
            guard let children = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            for url in children {
                results.append(DeveloperArtifact(
                    url: url,
                    title: url.deletingPathExtension().lastPathComponent,
                    detail: detail,
                    category: category,
                    kind: kind,
                    size: allocatedSize(of: url),
                    isRecommended: false,
                    canRemove: canRemove,
                    isSelected: false
                ))
            }
        }

        add("Library/Developer/Xcode/DerivedData", title: "DerivedData", detail: "Indexy a výsledky sestavení; Xcode je znovu vytvoří", category: .xcode, kind: .cache, recommended: true)
        add("Library/Developer/Xcode/Archives", title: "Archivy aplikací", detail: "Historické distribuční buildy a dSYM", category: .xcode, kind: .archive, recommended: false)
        add("Library/Developer/Xcode/iOS DeviceSupport", title: "Podpora iOS zařízení", detail: "Symboly dříve připojených verzí iOS", category: .xcode, kind: .cache, recommended: true)
        add("Library/Developer/CoreSimulator/Caches", title: "Cache simulátorů", detail: "Dočasná data CoreSimulatoru", category: .xcode, kind: .cache, recommended: true)
        addChildren(of: "Library/Developer/CoreSimulator/Devices", category: .xcode, kind: .simulator, detail: "Zařízení Apple Simulator")

        add(".gradle/caches", title: "Gradle cache", detail: "Stažené závislosti a výsledky sestavení", category: .android, kind: .cache, recommended: true)
        add(".gradle/daemon", title: "Gradle daemon", detail: "Dočasná data a logy Gradle procesů", category: .android, kind: .cache, recommended: true)
        add(".android/cache", title: "Android cache", detail: "Dočasná data Android nástrojů", category: .android, kind: .cache, recommended: true)
        addChildren(of: ".android/avd", category: .android, kind: .simulator, detail: "Android Virtual Device")
        addChildren(of: "Library/Android/sdk/system-images", category: .android, kind: .runtime, detail: "Obraz systému Android Emulatoru")
        addChildren(of: "Library/Android/sdk/platforms", category: .android, kind: .sdk, detail: "Android SDK Platform")
        addChildren(of: "Library/Android/sdk/build-tools", category: .android, kind: .sdk, detail: "Android SDK Build Tools")

        add(".npm/_cacache", title: "npm cache", detail: "Cache stažených npm balíčků", category: .node, kind: .cache, recommended: true)
        add(".npm/_logs", title: "npm logy", detail: "Diagnostické záznamy npm", category: .node, kind: .logs, recommended: true)
        add(".node-gyp", title: "node-gyp cache", detail: "Hlavičky pro kompilaci nativních modulů", category: .node, kind: .cache, recommended: true)
        add(".pnpm-store", title: "pnpm store", detail: "Globální úložiště balíčků pnpm", category: .node, kind: .cache, recommended: false)
        add("Library/Caches/Yarn", title: "Yarn cache", detail: "Cache balíčků Yarn", category: .node, kind: .cache, recommended: true)
        addChildren(of: ".nvm/versions/node", category: .node, kind: .runtime, detail: "Node.js runtime spravovaný přes nvm")
        addChildren(of: "/opt/homebrew/lib/node_modules", category: .node, kind: .package, detail: "Globální npm balíček", canRemove: false)
        addChildren(of: "/usr/local/lib/node_modules", category: .node, kind: .package, detail: "Globální npm balíček", canRemove: false)

        add("Library/Caches/Homebrew", title: "Homebrew cache", detail: "Stažené archivy a metadata Homebrew", category: .homebrew, kind: .cache, recommended: true)
        add("Library/Logs/Homebrew", title: "Homebrew logy", detail: "Logy instalací a sestavení", category: .homebrew, kind: .logs, recommended: true)
        addChildren(of: "/opt/homebrew/Cellar", category: .homebrew, kind: .package, detail: "Nainstalovaná Homebrew formule", canRemove: false)
        addChildren(of: "/opt/homebrew/Caskroom", category: .homebrew, kind: .package, detail: "Nainstalovaný Homebrew cask", canRemove: false)
        addChildren(of: "/usr/local/Cellar", category: .homebrew, kind: .package, detail: "Nainstalovaná Homebrew formule", canRemove: false)
        addChildren(of: "/usr/local/Caskroom", category: .homebrew, kind: .package, detail: "Nainstalovaný Homebrew cask", canRemove: false)

        add(".m2/repository", title: "Maven repository", detail: "Lokální cache Maven závislostí", category: .java, kind: .cache, recommended: false)
        add(".gradle/wrapper/dists", title: "Gradle distribuce", detail: "Stažené verze Gradle", category: .java, kind: .runtime, recommended: false)
        addChildren(of: "Library/Java/JavaVirtualMachines", category: .java, kind: .runtime, detail: "Uživatelská instalace JDK")
        addChildren(of: "/Library/Java/JavaVirtualMachines", category: .java, kind: .runtime, detail: "Systémová instalace JDK", canRemove: false)

        var unique: [URL: DeveloperArtifact] = [:]
        for artifact in results { unique[artifact.url.standardizedFileURL] = artifact }
        return unique.values.sorted {
            if $0.category != $1.category { return $0.category.rawValue < $1.category.rawValue }
            return $0.size > $1.size
        }
    }

    private static func installedBundleIdentifiers() -> Set<String> {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices"),
            home.appendingPathComponent("Applications")
        ]
        var identifiers = Set<String>()
        for root in roots where fm.fileExists(atPath: root.path) {
            if let rootID = Bundle(url: root)?.bundleIdentifier { identifiers.insert(rootID) }
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                if let identifier = Bundle(url: url)?.bundleIdentifier { identifiers.insert(identifier) }
                enumerator.skipDescendants()
            }
        }
        return identifiers
    }

    private static func looksLikeBundleIdentifier(_ value: String) -> Bool {
        let protectedPrefixes = ["com.apple.", "group.", "systemgroup."]
        guard !protectedPrefixes.contains(where: value.hasPrefix) else { return false }
        let parts = value.split(separator: ".")
        guard parts.count >= 3, value.count >= 6, !value.contains(" ") else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }

    private static func isRelated(_ candidate: String, toAny installedIDs: Set<String>) -> Bool {
        installedIDs.contains { installed in
            candidate == installed || candidate.hasPrefix(installed + ".") || installed.hasPrefix(candidate + ".")
        }
    }

    static func moveToTrash(_ urls: [URL]) -> [String] {
        var errors: [String] = []
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            do {
                _ = try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return errors
    }

    static func emptyUserTrash(_ urls: [URL]) -> [String] {
        var errors: [String] = []
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.removeItem(at: url) }
            catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        return errors
    }
}
