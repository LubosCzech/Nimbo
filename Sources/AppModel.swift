import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: SidebarSection = .overview
    @Published var cleanupGroups: [CleanupGroup] = []
    @Published var largeFiles: [LargeFile] = []
    @Published var applications: [InstalledApplication] = []
    @Published var orphanedData: [OrphanedAppData] = []
    @Published var developerArtifacts: [DeveloperArtifact] = []
    @Published var appSearch = ""
    @Published var isScanningCleanup = false
    @Published var isScanningLargeFiles = false
    @Published var isScanningApplications = false
    @Published var isScanningOrphans = false
    @Published var isScanningDeveloper = false
    @Published var isCleaning = false
    @Published var largeFileThreshold: Int64 = 100_000_000
    @Published var removalPlan: AppRemovalPlan?
    @Published var uninstallReport: UninstallReport?
    @Published var isUninstalling = false
    @Published var webLookup: WebLookup?
    @Published var pendingCleanup = false
    @Published var pendingLargeFileRemoval = false
    @Published var pendingOrphanRemoval = false
    @Published var pendingDeveloperRemoval = false
    @Published var selectedDevelopmentCategory: DevelopmentCategory = .xcode
    @Published var expandedCleanupKinds: Set<CleanupKind> = []
    @Published var alertMessage: String?
    @Published var lastCleanedBytes: Int64 = 0

    var selectedCleanupSize: Int64 {
        cleanupGroups.filter(\.isSelected).reduce(0) { $0 + $1.size }
    }

    var totalCleanupSize: Int64 { cleanupGroups.reduce(0) { $0 + $1.size } }
    var selectedLargeFilesSize: Int64 { largeFiles.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    var selectedOrphanSize: Int64 { orphanedData.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    var selectedDeveloperSize: Int64 { developerArtifacts.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    var visibleDeveloperArtifacts: [DeveloperArtifact] { developerArtifacts.filter { $0.category == selectedDevelopmentCategory } }

    var filteredApplications: [InstalledApplication] {
        guard !appSearch.isEmpty else { return applications }
        return applications.filter {
            $0.name.localizedCaseInsensitiveContains(appSearch)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(appSearch) ?? false)
        }
    }

    func startInitialScan() {
        scanCleanup()
        scanApplications()
    }

    func scanCleanup() {
        guard !isScanningCleanup else { return }
        isScanningCleanup = true
        Task {
            let groups = await Task.detached(priority: .userInitiated) { FileScanner.scanCleanup() }.value
            cleanupGroups = groups
            isScanningCleanup = false
        }
    }

    func scanLargeFiles() {
        guard !isScanningLargeFiles else { return }
        isScanningLargeFiles = true
        let threshold = largeFileThreshold
        Task {
            let files = await Task.detached(priority: .userInitiated) {
                FileScanner.scanLargeFiles(minimumSize: threshold)
            }.value
            largeFiles = files
            isScanningLargeFiles = false
        }
    }

    func scanApplications() {
        guard !isScanningApplications else { return }
        isScanningApplications = true
        Task {
            let apps = await Task.detached(priority: .utility) { FileScanner.scanApplications() }.value
            applications = apps
            isScanningApplications = false
        }
    }

    func scanOrphanedData() {
        guard !isScanningOrphans else { return }
        isScanningOrphans = true
        Task {
            orphanedData = await Task.detached(priority: .userInitiated) { FileScanner.scanOrphanedAppData() }.value
            isScanningOrphans = false
        }
    }

    func scanDeveloperData() {
        guard !isScanningDeveloper else { return }
        isScanningDeveloper = true
        Task {
            developerArtifacts = await Task.detached(priority: .userInitiated) { FileScanner.scanDeveloperArtifacts() }.value
            isScanningDeveloper = false
        }
    }

    func toggleCleanup(_ id: CleanupKind) {
        guard let index = cleanupGroups.firstIndex(where: { $0.id == id }) else { return }
        cleanupGroups[index].isSelected.toggle()
    }

    func toggleCleanupDetails(_ id: CleanupKind) {
        if expandedCleanupKinds.contains(id) { expandedCleanupKinds.remove(id) }
        else { expandedCleanupKinds.insert(id) }
    }

    func toggleLargeFile(_ id: URL) {
        guard let index = largeFiles.firstIndex(where: { $0.id == id }) else { return }
        largeFiles[index].isSelected.toggle()
    }

    func toggleOrphan(_ id: URL) {
        guard let index = orphanedData.firstIndex(where: { $0.id == id }) else { return }
        orphanedData[index].isSelected.toggle()
    }

    func toggleDeveloperArtifact(_ id: URL) {
        guard let index = developerArtifacts.firstIndex(where: { $0.id == id }), developerArtifacts[index].canRemove else { return }
        developerArtifacts[index].isSelected.toggle()
    }

    func cleanSelectedGroups() {
        let selected = cleanupGroups.filter(\.isSelected)
        let bytes = selected.reduce(Int64(0)) { $0 + $1.size }
        isCleaning = true
        Task {
            let errors = await Task.detached(priority: .userInitiated) {
                var allErrors: [String] = []
                for group in selected {
                    if group.kind == .trash {
                        allErrors += FileScanner.emptyUserTrash(group.urls)
                    } else {
                        allErrors += FileScanner.moveToTrash(group.urls)
                    }
                }
                return allErrors
            }.value
            isCleaning = false
            lastCleanedBytes = errors.isEmpty ? bytes : 0
            alertMessage = errors.isEmpty
                ? "Hotovo. Uvolněno \(bytes.fileSizeText)."
                : "Některé položky se nepodařilo odstranit:\n\(errors.prefix(4).joined(separator: "\n"))"
            scanCleanup()
        }
    }

    func removeSelectedLargeFiles() {
        let selected = largeFiles.filter(\.isSelected)
        let urls = selected.map(\.url)
        Task {
            let errors = await Task.detached { FileScanner.moveToTrash(urls) }.value
            if errors.isEmpty {
                largeFiles.removeAll { urls.contains($0.url) }
                alertMessage = "Vybrané soubory byly přesunuty do Koše."
            } else {
                alertMessage = "Některé soubory se nepodařilo přesunout:\n\(errors.prefix(4).joined(separator: "\n"))"
            }
        }
    }

    func removeSelectedOrphans() {
        let selected = orphanedData.filter(\.isSelected)
        let urls = selected.map(\.url)
        Task {
            let errors = await Task.detached { FileScanner.moveToTrash(urls) }.value
            if errors.isEmpty {
                orphanedData.removeAll { urls.contains($0.url) }
                alertMessage = "Vybrané zbytky aplikací byly přesunuty do Koše."
            } else {
                alertMessage = "Některé zbytky se nepodařilo přesunout:\n\(errors.prefix(4).joined(separator: "\n"))"
            }
        }
    }

    func removeSelectedDeveloperArtifacts() {
        let selected = developerArtifacts.filter { $0.isSelected && $0.canRemove }
        let urls = selected.map(\.url)
        Task {
            let errors = await Task.detached { FileScanner.moveToTrash(urls) }.value
            if errors.isEmpty {
                developerArtifacts.removeAll { urls.contains($0.url) }
                alertMessage = "Vybraná vývojářská data byla přesunuta do Koše."
            } else {
                alertMessage = "Některá data se nepodařilo přesunout:\n\(errors.prefix(4).joined(separator: "\n"))"
            }
        }
    }

    func prepareRemoval(of app: InstalledApplication) {
        Task {
            removalPlan = await Task.detached(priority: .userInitiated) {
                FileScanner.removalPlan(for: app)
            }.value
        }
    }

    func showInfo(for app: InstalledApplication) {
        let identifier = app.bundleIdentifier.map { " bundle identifier \($0)" } ?? ""
        webLookup = WebLookup(
            title: app.name,
            query: "\(app.name) macOS application\(identifier)",
            context: "Aplikace · verze \(app.version)"
        )
    }

    func showInfo(for item: OrphanedAppData) {
        webLookup = WebLookup(
            title: item.bundleIdentifier,
            query: "\(item.bundleIdentifier) macOS application bundle identifier",
            context: "Možný zbytek aplikace · \(item.source)"
        )
    }

    func showInfo(for artifact: DeveloperArtifact) {
        webLookup = WebLookup(
            title: artifact.title,
            query: "\(artifact.title) \(artifact.category.rawValue) \(artifact.kind.rawValue) macOS",
            context: "\(artifact.category.rawValue) · \(artifact.kind.rawValue) · \(artifact.detail)"
        )
    }

    func toggleRelatedFile(_ id: URL) {
        guard var plan = removalPlan,
              let index = plan.relatedFiles.firstIndex(where: { $0.id == id }) else { return }
        plan.relatedFiles[index].isSelected.toggle()
        removalPlan = plan
    }

    func uninstallPreparedApp() {
        guard let plan = removalPlan, !isUninstalling else { return }
        isUninstalling = true
        removalPlan = nil
        Task {
            let report = await Task.detached(priority: .userInitiated) { UninstallService.run(plan) }.value
            isUninstalling = false
            if report.appRemoved {
                applications.removeAll { $0.id == plan.app.id }
            }
            if report.failures.isEmpty {
                alertMessage = "\(plan.app.name) byla přesunuta do Koše včetně vybraných zbytků."
            } else {
                uninstallReport = report
            }
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
