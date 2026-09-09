import AppKit
import SwiftUI

enum CleanerTheme {
    static let background = Color(nsColor: NSColor(name: "NimboContentBackground") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.115, alpha: 1) : NSColor(white: 0.96, alpha: 1)
    })
    static let sidebar = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: NSColor(name: "NimboContentSurface") { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let highContrast = appearance.name == .accessibilityHighContrastDarkAqua || appearance.name == .accessibilityHighContrastAqua
        return dark ? NSColor(white: highContrast ? 0.23 : 0.17, alpha: 1) : .controlBackgroundColor
    })
    static let panelStrong = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor).opacity(0.3)
    static let separator = Color(nsColor: .separatorColor)
    static let selection = Color.accentColor.opacity(0.12)
    static let selectedForeground = Color.primary
    static let recessed = Color.primary.opacity(0.035)
    // The brand tint has explicit contrast variants; secondary accents are semantic system colors.
    static let mint = Color(nsColor: NSColor(name: "NimboAccent") { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let highContrast = appearance.name == .accessibilityHighContrastDarkAqua || appearance.name == .accessibilityHighContrastAqua
        if dark { return NSColor(srgbRed: 0.38, green: 0.88, blue: 0.77, alpha: 1) }
        return NSColor(srgbRed: 0, green: highContrast ? 0.30 : 0.40, blue: highContrast ? 0.27 : 0.36, alpha: 1)
    })
    static let cyan = Color(nsColor: .systemBlue)
    static let violet = Color(nsColor: .systemPurple)
    static let orange = Color(nsColor: .systemOrange)
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var permissions: PermissionController
    @AppStorage("appAppearance") private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 250)
        } detail: {
            ZStack {
                CleanerTheme.background.ignoresSafeArea()
                DockIconUpdater()
                Group {
                    switch model.selectedSection {
                    case .overview: OverviewView()
                    case .cleanup: CleanupView()
                    case .largeFiles: LargeFilesView()
                    case .applications: ApplicationsView()
                    case .startup: StartupView()
                    case .leftovers: LeftoversView()
                    case .development: DeveloperDataView()
                    case .privacy: PrivacyView()
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(model.selectedSection.rawValue)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Picker("Vzhled", selection: $appearanceRaw) {
                        ForEach(AppAppearance.allCases) { item in
                            Label(item.title, systemImage: item.icon).tag(item.rawValue)
                        }
                    }
                    Divider()
                    SettingsLink { Label("Nastavení…", systemImage: "gearshape") }
                } label: {
                    Label("Vzhled a nastavení", systemImage: "circle.lefthalf.filled")
                }
                .help("Změnit vzhled nebo otevřít nastavení")
                .accessibilityLabel("Vzhled a nastavení")
            }
        }
        .alert("Nimbo", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .confirmationDialog(
            "Přesunout vybrané soubory do Koše?",
            isPresented: $model.pendingLargeFileRemoval,
            titleVisibility: .visible
        ) {
            Button("Přesunout do Koše", role: .destructive) { model.removeSelectedLargeFiles() }
            Button("Zrušit", role: .cancel) { }
        } message: {
            Text("Vybráno \(model.selectedLargeFilesSize.fileSizeText). Položky bude možné obnovit z Koše.")
        }
        .confirmationDialog(
            "Přesunout zbytky do Koše?",
            isPresented: $model.pendingOrphanRemoval,
            titleVisibility: .visible
        ) {
            Button("Přesunout do Koše", role: .destructive) { model.removeSelectedOrphans() }
            Button("Zrušit", role: .cancel) { }
        } message: {
            Text("Vybráno \(model.selectedOrphanSize.fileSizeText). Detekce je konzervativní, přesto doporučujeme seznam zkontrolovat.")
        }
        .confirmationDialog(
            "Odstranit vývojářská data?",
            isPresented: $model.pendingDeveloperRemoval,
            titleVisibility: .visible
        ) {
            Button("Přesunout do Koše", role: .destructive) { model.removeSelectedDeveloperArtifacts() }
            Button("Zrušit", role: .cancel) { }
        } message: {
            Text("Vybráno \(model.selectedDeveloperSize.fileSizeText). Cache lze znovu vytvořit, simulátory, runtime a SDK mohou vyžadovat nové stažení.")
        }
        .sheet(item: $model.removalPlan) { _ in UninstallSheet() }
        .sheet(item: $model.webLookup) { lookup in WebLookupSheet(lookup: lookup) }
        .sheet(item: $model.uninstallReport) { report in UninstallReportView(report: report) }
        .sheet(isPresented: $permissions.showDetails) { PermissionDetailsView() }
    }

}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    private var selection: Binding<SidebarSection?> {
        Binding(get: { model.selectedSection }, set: { if let value = $0 { model.selectedSection = value } })
    }

    var body: some View {
        List(selection: selection) {
            Section {
                navigationRow(.overview)
            }
            Section("Úložiště") {
                navigationRow(.cleanup)
                navigationRow(.largeFiles)
            }
            Section("Aplikace a nástroje") {
                navigationRow(.applications)
                navigationRow(.startup)
                navigationRow(.leftovers)
                navigationRow(.development)
            }
            Section {
                navigationRow(.privacy)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 8) {
            Image(nsImage: nimboImage(named: colorScheme == .dark ? "nimbo-logo-dark" : "nimbo-logo-light"))
                .resizable().scaledToFit().frame(width: 140, height: 48)
                .accessibilityLabel("Nimbo")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.top, 12)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive").foregroundStyle(.secondary)
                Text("Analýza zůstává na Macu").font(.caption).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func navigationRow(_ item: SidebarSection) -> some View {
        Label(item.rawValue, systemImage: item.icon)
            .symbolRenderingMode(.monochrome).symbolVariant(.none)
            .padding(.vertical, 5)
            .tag(item)
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var trailing: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 30, weight: .bold)).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolbar {
            if let trailing {
                ToolbarItem(placement: .primaryAction) { trailing }
            }
        }
    }
}

private struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
            OverviewHeader()
            VStack(alignment: .leading, spacing: 28) {
                PermissionSummaryView()
                heroCard
                HStack(spacing: 16) {
                    MetricCard(title: "Nainstalované aplikace",
                               value: !model.hasStartedInitialScan || model.isScanningApplications ? "Načítání…" : "\(model.applications.count)",
                               icon: SidebarSection.applications.icon, color: SidebarSection.applications.accent)
                    MetricCard(title: "Zkontrolované kategorie",
                               value: !model.hasStartedInitialScan || model.isScanningCleanup ? "Načítání…" : "\(model.cleanupGroups.count)",
                               icon: "checklist", color: CleanerTheme.mint)
                }
                Text("Prozkoumat Mac").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                    QuickAction(section: .cleanup, detail: "Mezipaměť, záznamy a Koš") { model.selectedSection = .cleanup }
                    QuickAction(section: .largeFiles, detail: "Najděte prostor k uvolnění") { model.selectedSection = .largeFiles; if model.largeFiles.isEmpty { model.scanLargeFiles() } }
                    QuickAction(section: .applications, detail: "Odinstalace i související data") { model.selectedSection = .applications }
                    QuickAction(section: .startup, detail: "Přihlašovací aplikace a služby") { model.selectedSection = .startup }
                    QuickAction(section: .leftovers, detail: "Co zůstalo po odinstalaci") { model.selectedSection = .leftovers }
                    QuickAction(section: .development, detail: "Xcode, Android a balíčky") { model.selectedSection = .development }
                }
                Label("Nic se neodstraní bez vašeho potvrzení.", systemImage: "checkmark.shield")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(32).frame(maxWidth: 1120).frame(maxWidth: .infinity)
            }
        }
    }

    private var heroCard: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Chytrý úklid", systemImage: "sparkles")
                    .font(.headline).foregroundStyle(CleanerTheme.mint)
                if !model.hasStartedInitialScan {
                    HStack { ProgressView().controlSize(.small); Text("Kontroluji oprávnění…").font(.title2) }
                } else if model.isScanningCleanup {
                    HStack { ProgressView().controlSize(.small); Text("Analyzuji úložiště…").font(.title2) }
                } else {
                    Text(model.totalCleanupSize.fileSizeText)
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                        .monospacedDigit().contentTransition(.numericText())
                }
                Text("Nalezeno v kategoriích úklidu. Před odstraněním zkontrolujte jejich obsah.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420, alignment: .leading)
                Button { model.selectedSection = .cleanup } label: {
                    Label("Prohlédnout výsledky", systemImage: "arrow.right")
                }.nimboPrimaryAction().padding(.top, 6)
            }
            Spacer(minLength: 8)
            Image(systemName: "internaldrive")
                .font(.system(size: 86, weight: .ultraLight))
                .foregroundStyle(CleanerTheme.mint.gradient)
                .frame(width: 130).accessibilityHidden(true)
        }
        .padding(28).frame(maxWidth: .infinity, minHeight: 250, alignment: .leading)
        .background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct LeftoversView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    eyebrow: "Hloubková kontrola",
                    title: "Zbytky aplikací",
                    subtitle: "Data s bundle ID, ke kterému už není nalezena žádná aplikace.",
                    trailing: AnyView(
                        Button { model.scanOrphanedData() } label: {
                            Label(model.orphanedData.isEmpty ? "Spustit sken" : "Skenovat znovu", systemImage: "sparkle.magnifyingglass")
                        }.nimboPrimaryAction().disabled(model.isScanningOrphans)
                    )
                )
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.shield.fill").foregroundStyle(CleanerTheme.orange)
                    Text("Výsledky nejsou automaticky vybrané. Některé doplňky mohou používat data bez vlastní aplikace.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                .background(CleanerTheme.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(CleanerTheme.orange.opacity(0.18)))

                if model.isScanningOrphans {
                    LoadingCard(text: "Porovnávám data s nainstalovanými aplikacemi…")
                } else if model.orphanedData.isEmpty {
                    EmptyState(icon: "puzzlepiece.extension", title: "Připraveno ke kontrole", text: "Prohledáme cache, nastavení, kontejnery, uložené stavy a webová data aplikací.")
                } else {
                    HStack {
                        Text("NALEZENO \(model.orphanedData.count) POLOŽEK").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(.secondary)
                        Spacer()
                        Text(model.orphanedData.reduce(Int64(0)) { $0 + $1.size }.fileSizeText).font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(model.orphanedData.enumerated()), id: \.element.id) { index, item in
                            OrphanRow(item: item)
                            if index < model.orphanedData.count - 1 { Divider().overlay(CleanerTheme.separator).padding(.leading, 56) }
                        }
                    }
                    .background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 17))

                }
            }.padding(32)
        }
        .nimboActionBar {
            if !model.orphanedData.isEmpty {
                BottomActionBar(label: "Přesunout do Koše · \(model.selectedOrphanSize.fileSizeText)", disabled: model.selectedOrphanSize == 0) {
                    model.pendingOrphanRemoval = true
                }
            }
        }
    }
}

private struct OrphanRow: View {
    @EnvironmentObject private var model: AppModel
    let item: OrphanedAppData

    var body: some View {
        HStack(spacing: 13) {
            Button { model.toggleOrphan(item.id) } label: {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18)).foregroundStyle(item.isSelected ? CleanerTheme.mint : .secondary)
            }.buttonStyle(.plain).accessibilityLabel("Vybrat: \(item.bundleIdentifier)")
                .accessibilityValue(item.isSelected ? "Vybráno" : "Nevybráno")
            NimboIconBadge(symbol: sourceIcon, color: SidebarSection.leftovers.accent, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.bundleIdentifier).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                Text("\(item.source) · \(displayPath(item.url))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(item.size.fileSizeText).font(.system(size: 12.5, weight: .semibold, design: .monospaced))
            Button { model.showInfo(for: item) } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless).help("Vyhledat informace na Googlu").accessibilityLabel("Vyhledat informace na Googlu")
            Button { model.reveal(item.url) } label: { Image(systemName: "folder") }.buttonStyle(.borderless).help("Zobrazit ve Finderu").accessibilityLabel("Zobrazit ve Finderu")
        }.padding(.horizontal, 17).frame(height: 62)
    }

    private var sourceIcon: String {
        if item.source == "Cache" { return CleanupKind.caches.icon }
        if item.source == "Nastavení" { return "slider.horizontal.3" }
        if item.source == "Kontejner" { return "cube" }
        return "doc"
    }
}

private struct DeveloperDataView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    eyebrow: "Developer toolbox",
                    title: "Vývojářská data",
                    subtitle: "Cache, simulátory, SDK, runtime a balíčky na jednom místě.",
                    trailing: AnyView(
                        Button { model.scanDeveloperData() } label: {
                            Label(model.developerArtifacts.isEmpty ? "Analyzovat" : "Aktualizovat", systemImage: "terminal")
                        }.nimboPrimaryAction().disabled(model.isScanningDeveloper)
                    )
                )
                Picker("Prostředí", selection: $model.selectedDevelopmentCategory) {
                    ForEach(DevelopmentCategory.allCases) { category in
                        Label(category.rawValue, systemImage: category.icon).tag(category)
                    }
                }.pickerStyle(.segmented)

                if model.isScanningDeveloper {
                    LoadingCard(text: "Mapuji vývojářské nástroje a balíčky…")
                } else if model.developerArtifacts.isEmpty {
                    EmptyState(icon: "terminal", title: "Připraveno k analýze", text: "Najdeme Xcode data, Android SDK a emulátory, JDK, Node/npm/pnpm/Yarn i Homebrew balíčky.")
                } else if model.visibleDeveloperArtifacts.isEmpty {
                    EmptyState(icon: model.selectedDevelopmentCategory.icon, title: "Nic nenalezeno", text: "Pro prostředí \(model.selectedDevelopmentCategory.rawValue) nebyla nalezena žádná známá data.")
                } else {
                    let visible = model.visibleDeveloperArtifacts
                    HStack {
                        Text("\(model.selectedDevelopmentCategory.rawValue.uppercased()) · \(visible.count) POLOŽEK").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(.secondary)
                        Spacer()
                        Text(visible.reduce(Int64(0)) { $0 + $1.size }.fileSizeText).font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, artifact in
                            DeveloperArtifactRow(artifact: artifact)
                            if index < visible.count - 1 { Divider().overlay(CleanerTheme.separator).padding(.leading, 58) }
                        }
                    }
                    .background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 17))

                }
                HStack(spacing: 9) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(CleanerTheme.cyan)
                    Text("Nainstalované Homebrew a globální npm balíčky se pouze zobrazují. Odinstalujte je jejich správcem balíčků.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(32)
        }
        .nimboActionBar {
            if !model.developerArtifacts.isEmpty {
                BottomActionBar(label: "Přesunout do Koše · \(model.selectedDeveloperSize.fileSizeText)", disabled: model.selectedDeveloperSize == 0) {
                    model.pendingDeveloperRemoval = true
                }
            }
        }
    }
}

private struct DeveloperArtifactRow: View {
    @EnvironmentObject private var model: AppModel
    let artifact: DeveloperArtifact

    var body: some View {
        HStack(spacing: 13) {
            Button { model.toggleDeveloperArtifact(artifact.id) } label: {
                Image(systemName: selectionIcon).font(.system(size: 18))
                    .foregroundStyle(artifact.isSelected ? CleanerTheme.mint : .secondary)
            }.buttonStyle(.plain).disabled(!artifact.canRemove)
                .accessibilityLabel("Vybrat: \(artifact.title)")
                .accessibilityValue(artifact.isSelected ? "Vybráno" : "Nevybráno")
            NimboIconBadge(symbol: artifact.category.icon, color: categoryColor, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(artifact.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    Text(artifact.kind.rawValue.uppercased()).font(.system(size: 8.5, weight: .bold)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(CleanerTheme.panelStrong, in: Capsule())
                    if artifact.isRecommended {
                        Text("DOPORUČENO").font(.system(size: 8.5, weight: .bold)).foregroundStyle(CleanerTheme.mint)
                    }
                }
                Text("\(artifact.detail) · \(displayPath(artifact.url))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !artifact.canRemove { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.tertiary).help("Spravujte původním nástrojem") }
            Text(artifact.size.fileSizeText).font(.system(size: 12.5, weight: .semibold, design: .monospaced))
            Button { model.showInfo(for: artifact) } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless).help("Vyhledat informace na Googlu").accessibilityLabel("Vyhledat informace na Googlu")
            Button { model.reveal(artifact.url) } label: { Image(systemName: "folder") }.buttonStyle(.borderless).help("Zobrazit ve Finderu").accessibilityLabel("Zobrazit ve Finderu")
        }.padding(.horizontal, 17).frame(height: 66)
    }

    private var selectionIcon: String {
        if !artifact.canRemove { return "lock.circle" }
        return artifact.isSelected ? "checkmark.circle.fill" : "circle"
    }

    private var categoryColor: Color {
        switch artifact.category {
        case .xcode: return CleanerTheme.cyan
        case .android: return CleanerTheme.mint
        case .node: return CleanerTheme.violet
        case .homebrew: return CleanerTheme.orange
        case .java: return Color.red.opacity(0.9)
        }
    }
}

private func displayPath(_ url: URL) -> String {
    url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
}

private struct MetricCard: View {
    let title: String; let value: String; let icon: String; let color: Color
    var body: some View {
        HStack(spacing: 14) {
            NimboIconBadge(symbol: icon, color: color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.system(size: 16, weight: .bold))
            }
            Spacer()
        }
        .padding(17).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 16))

    }
}

private struct QuickAction: View {
    let section: SidebarSection; let detail: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    NimboIconBadge(symbol: section.icon, color: section.accent)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.rawValue).font(.system(size: 14, weight: .semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 15))

        }.buttonStyle(.plain)
    }
}

private struct CleanupView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    eyebrow: "Bezpečné čištění", title: "Chytrý úklid",
                    subtitle: "Prohlédněte si jednotlivé kategorie a vyberte, co chcete odstranit.",
                    trailing: AnyView(Button { model.scanCleanup() } label: { Label("Skenovat znovu", systemImage: "arrow.clockwise") }.buttonStyle(.bordered).disabled(model.isScanningCleanup))
                )
                if model.isScanningCleanup && model.cleanupGroups.isEmpty {
                    LoadingCard(text: "Procházím bezpečná místa…")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.cleanupGroups.enumerated()), id: \.element.id) { index, group in
                            CleanupRow(group: group)
                            if index < model.cleanupGroups.count - 1 { Divider().overlay(CleanerTheme.separator).padding(.leading, 66) }
                        }
                    }
                    .background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 17))

                }
                HStack(spacing: 9) {
                    Image(systemName: "info.circle.fill").foregroundStyle(CleanerTheme.cyan)
                    Text("Cache a logy budou přesunuty do Koše. Obsah Koše je jediná nevratná operace.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(32)
        }
        .nimboActionBar {
            BottomActionBar(label: "Vyčistit \(model.selectedCleanupSize.fileSizeText)", disabled: model.selectedCleanupSize == 0 || model.isCleaning) {
                model.pendingCleanup = true
            }
        }
        .confirmationDialog("Provést úklid?", isPresented: $model.pendingCleanup, titleVisibility: .visible) {
            Button("Vyčistit \(model.selectedCleanupSize.fileSizeText)", role: .destructive) { model.cleanSelectedGroups() }
            Button("Zrušit", role: .cancel) { }
        } message: {
            Text("Obsah Koše bude smazán natrvalo. Ostatní vybrané položky se přesunou do Koše.")
        }
    }
}

private struct CleanupRow: View {
    @EnvironmentObject private var model: AppModel
    let group: CleanupGroup
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool { model.expandedCleanupKinds.contains(group.id) }

    private var color: Color {
        switch group.kind { case .caches: return CleanerTheme.mint; case .logs: return CleanerTheme.cyan; case .trash: return CleanerTheme.orange; case .developer: return CleanerTheme.violet }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { model.toggleCleanup(group.id) } label: {
                    Image(systemName: group.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19)).foregroundStyle(group.isSelected ? color : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Vybrat: \(group.kind.title)")
                .accessibilityValue(group.isSelected ? "Vybráno" : "Nevybráno")
                .help(group.isSelected ? "Odebrat sekci z výběru" : "Vybrat celou sekci")

                Button { model.toggleCleanupDetails(group.id) } label: {
                    HStack(spacing: 14) {
                        NimboIconBadge(symbol: group.kind.icon, color: color, size: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.kind.title).font(.system(size: 14, weight: .semibold))
                            Text("\(group.kind.subtitle) · \(group.items.count) položek").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(group.size.fileSizeText).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(group.size > 0 ? .primary : .tertiary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18).frame(height: 70)

            if isExpanded {
                Divider().overlay(CleanerTheme.separator).padding(.leading, 66)
                if group.items.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle").foregroundStyle(color)
                        Text("Sekce je prázdná").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }.padding(.leading, 69).padding(.trailing, 18).frame(height: 46)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                            CleanupDetailRow(item: item, color: color)
                            if index < group.items.count - 1 {
                                Divider().overlay(CleanerTheme.separator.opacity(0.7)).padding(.leading, 102)
                            }
                        }
                    }
                    .background(CleanerTheme.recessed)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isExpanded)
    }
}

private struct CleanupDetailRow: View {
    @EnvironmentObject private var model: AppModel
    let item: CleanupItem
    let color: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 25, height: 25)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text(displayPath(item.url.deletingLastPathComponent()))
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            Text(item.size.fileSizeText).font(.system(size: 11.5, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            Button { model.reveal(item.url) } label: {
                Image(systemName: "folder").font(.system(size: 11))
            }.buttonStyle(.borderless).help("Zobrazit ve Finderu").accessibilityLabel("Zobrazit ve Finderu")
        }
        .padding(.leading, 68).padding(.trailing, 18).frame(height: 48)
    }
}

private struct LargeFilesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    eyebrow: "Analyzátor úložiště", title: "Velké soubory",
                    subtitle: "Skenuje pouze vaše osobní složky, nikdy systémová data.",
                    trailing: AnyView(Button { model.scanLargeFiles() } label: { Label(model.largeFiles.isEmpty ? "Spustit sken" : "Skenovat znovu", systemImage: "magnifyingglass") }.nimboPrimaryAction().disabled(model.isScanningLargeFiles))
                )
                Picker("Minimální velikost", selection: $model.largeFileThreshold) {
                    Text("100 MB+").tag(Int64(100_000_000)); Text("500 MB+").tag(Int64(500_000_000)); Text("1 GB+").tag(Int64(1_000_000_000))
                }.pickerStyle(.segmented).frame(width: 330)
                if model.isScanningLargeFiles {
                    LoadingCard(text: "Hledám velké soubory…")
                } else if model.largeFiles.isEmpty {
                    EmptyState(icon: "doc.text.magnifyingglass", title: "Připraveno ke skenování", text: "Prohledáme Plochu, Dokumenty, Stažené soubory, Filmy, Hudbu a Obrázky.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.largeFiles.enumerated()), id: \.element.id) { index, file in
                            LargeFileRow(file: file)
                            if index < model.largeFiles.count - 1 { Divider().overlay(CleanerTheme.separator).padding(.leading, 58) }
                        }
                    }.background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 17))
                }
            }.padding(32)
        }
        .nimboActionBar {
            if !model.largeFiles.isEmpty {
                BottomActionBar(label: "Přesunout do Koše · \(model.selectedLargeFilesSize.fileSizeText)", disabled: model.selectedLargeFilesSize == 0) { model.pendingLargeFileRemoval = true }
            }
        }
    }
}

private struct LargeFileRow: View {
    @EnvironmentObject private var model: AppModel
    let file: LargeFile
    var body: some View {
        HStack(spacing: 13) {
            Button { model.toggleLargeFile(file.id) } label: {
                Image(systemName: file.isSelected ? "checkmark.circle.fill" : "circle").font(.system(size: 18)).foregroundStyle(file.isSelected ? CleanerTheme.mint : .secondary)
            }.buttonStyle(.plain).accessibilityLabel("Vybrat: \(file.name)")
                .accessibilityValue(file.isSelected ? "Vybráno" : "Nevybráno")
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable().frame(width: 31, height: 31)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                Text(file.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(file.size.fileSizeText).font(.system(size: 12.5, weight: .semibold, design: .monospaced))
            Button { model.reveal(file.url) } label: { Image(systemName: "folder") }.buttonStyle(.borderless).help("Zobrazit ve Finderu").accessibilityLabel("Zobrazit ve Finderu")
        }.padding(.horizontal, 17).frame(height: 61)
    }
}

private struct ApplicationsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: "Kompletní odstranění", title: "Aplikace",
                           subtitle: "Odinstalujte aplikace spolu s jejich cache a nastavením.",
                           trailing: AnyView(Button { model.scanApplications() } label: {
                               Label("Obnovit aplikace", systemImage: "arrow.clockwise")
                           }.disabled(model.isScanningApplications)))
                if model.isScanningApplications && model.applications.isEmpty {
                    LoadingCard(text: "Načítám nainstalované aplikace…")
                } else if model.filteredApplications.isEmpty {
                    EmptyState(icon: "magnifyingglass", title: "Žádné aplikace", text: "Zkuste jiný název nebo obnovte seznam.")
                } else {
                    Text("\(model.filteredApplications.count) aplikací").font(.subheadline).foregroundStyle(.secondary)
                    LazyVStack(spacing: 0) {
                        ForEach(model.filteredApplications) { app in
                            AppRow(app: app)
                            Divider().padding(.leading, 76)
                        }
                    }.background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 20))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }.padding(32)
        }
        .searchable(text: $model.appSearch, placement: .toolbar, prompt: "Hledat aplikaci")
    }
}

private struct AppRow: View {
    @EnvironmentObject private var model: AppModel
    let app: InstalledApplication
    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 45, height: 45)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.system(size: 14, weight: .semibold))
                Text("Verze \(app.version)  ·  \(app.bundleIdentifier ?? "Bez identifikátoru")").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(app.size.fileSizeText).font(.system(size: 12.5, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            Button { model.showInfo(for: app) } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless).help("Vyhledat informace na Googlu").accessibilityLabel("Vyhledat informace na Googlu")
            Button("Odinstalovat") { model.prepareRemoval(of: app) }.buttonStyle(.bordered)
                .disabled(model.isUninstalling)
        }
        .padding(.horizontal, 17).frame(height: 75)
    }
}

private struct UninstallSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        if let plan = model.removalPlan {
            VStack(spacing: 0) {
                HStack(spacing: 15) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: plan.app.url.path)).resizable().frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Odinstalovat \(plan.app.name)?").font(.title2).fontWeight(.bold)
                        Text("Aplikace i vybrané zbytky se přesunou do Koše.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(24)
                Divider().overlay(CleanerTheme.separator)
                ScrollView {
                    VStack(alignment: .leading, spacing: 11) {
                        removalItem(url: plan.app.url, size: plan.app.size, selected: true, enabled: false)
                        if plan.relatedFiles.isEmpty {
                            Text("Nebyly nalezeny žádné související soubory.").font(.caption).foregroundStyle(.secondary).padding(.vertical, 16)
                        } else {
                            Text("SOUVISEJÍCÍ SOUBORY").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(.secondary).padding(.top, 8)
                            ForEach(plan.relatedFiles) { file in
                                Button { model.toggleRelatedFile(file.id) } label: { removalItem(url: file.url, size: file.size, selected: file.isSelected, enabled: true) }.buttonStyle(.plain)
                            }
                        }
                    }.padding(24)
                }
                Divider().overlay(CleanerTheme.separator)
                HStack {
                    Text("Celkem \(plan.selectedSize.fileSizeText)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Zrušit") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Přesunout do Koše", role: .destructive) { model.uninstallPreparedApp() }.keyboardShortcut(.defaultAction)
                }.padding(18)
            }.frame(width: 620, height: min(600, 330 + CGFloat(plan.relatedFiles.count) * 48))
        }
    }

    private func removalItem(url: URL, size: Int64, selected: Bool, enabled: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? CleanerTheme.mint : .secondary).opacity(enabled ? 1 : 0.65)
            Image(systemName: url.pathExtension == "app" ? "app.fill" : "doc.fill").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(url.deletingLastPathComponent().path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(); Text(size.fileSizeText).font(.caption).foregroundStyle(.secondary)
        }.padding(10).background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(eyebrow: "Transparentní ochrana", title: "Soukromí", subtitle: "Vaše data zůstávají na vašem Macu.")
                PermissionSummaryView()
                VStack(spacing: 0) {
                    PrivacyRow(icon: "network.slash", title: "Offline skenování", text: "Analýza disku probíhá lokálně. Pouze po kliknutí na ⓘ se Googlu odešle název a technický kontext položky, nikdy její cesta. Google cookies se uchovají kvůli souhlasu a přihlášení. Kontrola aktualizací se připojuje k GitHubu.", color: CleanerTheme.mint)
                    Divider().overlay(CleanerTheme.separator).padding(.leading, 68)
                    PrivacyRow(icon: "trash.slash.fill", title: "Obnovitelné kroky", text: "Aplikace, velké soubory, cache a logy se nejprve přesouvají do Koše.", color: CleanerTheme.cyan)
                    Divider().overlay(CleanerTheme.separator).padding(.leading, 68)
                    PrivacyRow(icon: "person.crop.circle.badge.checkmark", title: "Vy rozhodujete", text: "Před každým odstraněním vidíte velikost i přesný seznam vybraných položek.", color: CleanerTheme.violet)
                }.background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 17))
            }.padding(32)
        }
    }
}

private struct PrivacyRow: View {
    let icon: String; let title: String; let text: String; let color: Color
    var body: some View {
        HStack(spacing: 15) {
            NimboIconBadge(symbol: icon, color: color)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 14, weight: .semibold)); Text(text).font(.caption).foregroundStyle(.secondary) }
        }.padding(19).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var permissions: PermissionController
    @State private var showPermissions = false
    @AppStorage("appAppearance") private var appearanceRaw = AppAppearance.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: nimboImage(named: colorScheme == .dark ? "nimbo-icon-dark" : "nimbo-icon-light"))
                        .resizable().scaledToFit().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nimbo").font(.title2.bold())
                        Text("Péče o váš Mac").foregroundStyle(.secondary)
                        Text("Verze \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 4)
            }
            Section("Vzhled") {
                Picker("Barevný režim", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { item in
                        Label(item.title, systemImage: item.icon).tag(item.rawValue)
                    }
                }.pickerStyle(.segmented)
                Text("Volba Podle systému respektuje vzhled macOS. Průhlednost a pohyb se přizpůsobují nastavení zpřístupnění.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Soukromí a oprávnění") {
                PermissionSummaryView(openDetails: { showPermissions = true })
                LabeledContent("Analýza souborů", value: "Lokálně na Macu")
                Button("Nastavit úplný přístup k disku…") { DiskAccessHelp.shared.show() }
                Text("Soubory se standardně přesouvají do Koše. Vyprázdnění Koše je nevratné.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                UpdateSettingsView()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Nastavení")
        .sheet(isPresented: $showPermissions) { PermissionDetailsView() }
        .tint(CleanerTheme.mint)
        .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .system).colorScheme)
    }
}

private struct LoadingCard: View {
    let text: String
    var body: some View {
        HStack(spacing: 13) { ProgressView().controlSize(.small); Text(text).font(.system(size: 13)).foregroundStyle(.secondary); Spacer() }
            .padding(20).background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct EmptyState: View {
    let icon: String; let title: String; let text: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 35, weight: .light)).foregroundStyle(CleanerTheme.cyan)
            Text(title).font(.headline)
            Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }.frame(maxWidth: .infinity, minHeight: 230).background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 17))
    }
}

private struct BottomActionBar: View {
    let label: String; let disabled: Bool; let action: () -> Void
    var body: some View {
        HStack {
            Label("Před odstraněním vždy uvidíte potvrzení", systemImage: "shield.checkered").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(label, action: action).nimboPrimaryAction().disabled(disabled)
        }.padding(.horizontal, 28).padding(.vertical, 16)
    }
}
