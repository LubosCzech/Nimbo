import AppKit
import SwiftUI

enum CleanerTheme {
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    static let background = adaptive(
        light: NSColor(srgbRed: 0.965, green: 0.978, blue: 0.978, alpha: 1),
        dark: NSColor(srgbRed: 0.035, green: 0.047, blue: 0.075, alpha: 1)
    )
    static let sidebar = adaptive(
        light: NSColor(white: 1, alpha: 1),
        dark: NSColor(srgbRed: 0.055, green: 0.075, blue: 0.085, alpha: 1)
    )
    static let panel = adaptive(
        light: NSColor(white: 1, alpha: 0.78),
        dark: NSColor(white: 1, alpha: 0.055)
    )
    static let panelStrong = adaptive(
        light: NSColor(white: 1, alpha: 0.96),
        dark: NSColor(white: 1, alpha: 0.08)
    )
    static let border = adaptive(
        light: NSColor(white: 0, alpha: 0.085),
        dark: NSColor(white: 1, alpha: 0.09)
    )
    static let separator = adaptive(
        light: NSColor(white: 0, alpha: 0.07),
        dark: NSColor(white: 1, alpha: 0.06)
    )
    static let selection = adaptive(
        light: NSColor(srgbRed: 0.04, green: 0.40, blue: 0.36, alpha: 0.10),
        dark: NSColor(white: 1, alpha: 0.09)
    )
    static let selectedForeground = adaptive(
        light: NSColor(srgbRed: 0.025, green: 0.22, blue: 0.20, alpha: 1),
        dark: NSColor.white
    )
    static let recessed = adaptive(
        light: NSColor(white: 0, alpha: 0.035),
        dark: NSColor(white: 0, alpha: 0.15)
    )
    static let mint = Color(red: 0.21, green: 0.91, blue: 0.68)
    static let cyan = Color(red: 0.22, green: 0.70, blue: 0.96)
    static let violet = Color(red: 0.57, green: 0.44, blue: 0.98)
    static let orange = Color(red: 1.0, green: 0.61, blue: 0.25)
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 250)
        } detail: {
            ZStack {
                CleanerTheme.background.ignoresSafeArea()
                subtleBackground
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
    }

    private var subtleBackground: some View {
        GeometryReader { geometry in
            Circle()
                .fill(CleanerTheme.violet.opacity(0.09))
                .frame(width: 430, height: 430)
                .blur(radius: 90)
                .offset(x: geometry.size.width - 260, y: -230)
            Circle()
                .fill(CleanerTheme.mint.opacity(0.055))
                .frame(width: 350, height: 350)
                .blur(radius: 100)
                .offset(x: -170, y: geometry.size.height - 160)
        }
        .allowsHitTesting(false)
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appAppearance") private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        ZStack {
            Color.clear.background(.regularMaterial).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Image(nsImage: nimboImage(named: colorScheme == .dark ? "nimbo-logo-dark" : "nimbo-logo-light"))
                    .resizable().scaledToFit()
                    .frame(width: 174, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .padding(.horizontal, 18).padding(.top, 17).padding(.bottom, 22)

                Text("NÁSTROJE").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(.tertiary)
                    .padding(.horizontal, 20).padding(.bottom, 8)
                ForEach(SidebarSection.allCases) { item in
                    Button { model.selectedSection = item } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon).frame(width: 20)
                            Text(item.rawValue).font(.system(size: 13.5, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(model.selectedSection == item ? CleanerTheme.selectedForeground : Color.secondary)
                        .padding(.horizontal, 13).frame(height: 40)
                        .background(model.selectedSection == item ? CleanerTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain).padding(.horizontal, 8)
                }
                Spacer()
                HStack(spacing: 9) {
                    Image(systemName: (AppAppearance(rawValue: appearanceRaw) ?? .system).icon)
                        .foregroundStyle(CleanerTheme.cyan).frame(width: 20)
                    Text("Vzhled").font(.caption).fontWeight(.medium)
                    Spacer()
                    Picker("Vzhled", selection: $appearanceRaw) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Label(appearance.title, systemImage: appearance.icon).tag(appearance.rawValue)
                        }
                    }.labelsHidden().pickerStyle(.menu).frame(maxWidth: 105)
                }
                .padding(.horizontal, 13).frame(height: 40)
                .nimboGlass(interactive: true, radius: 10)
                .padding(.horizontal, 12).padding(.bottom, 6)
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(CleanerTheme.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bezpečný režim").font(.caption).fontWeight(.semibold)
                        Text("Vždy nejprve do Koše").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                .background(CleanerTheme.recessed, in: RoundedRectangle(cornerRadius: 11))
                .padding(12)
            }
        }
    }
}

private struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(CleanerTheme.mint)
                Text(title).font(.system(size: 29, weight: .bold, design: .rounded))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

private struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(eyebrow: "Dobrý den", title: "Váš Mac v kondici", subtitle: "Rychlý přehled úložiště a bezpečných doporučení")
                HStack(spacing: 16) {
                    heroCard
                    VStack(spacing: 16) {
                        MetricCard(title: "K úklidu", value: model.totalCleanupSize.fileSizeText, icon: "sparkles", color: CleanerTheme.mint)
                        MetricCard(title: "Nainstalováno", value: "\(model.applications.count) aplikací", icon: "square.stack.3d.up.fill", color: CleanerTheme.violet)
                    }
                    .frame(width: 245)
                }
                Text("RYCHLÉ AKCE").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    QuickAction(title: "Chytrý úklid", detail: "Cache, logy a Koš", icon: "wand.and.stars", color: CleanerTheme.mint) { model.selectedSection = .cleanup }
                    QuickAction(title: "Velké soubory", detail: "Najděte žrouty místa", icon: "doc.badge.magnifyingglass", color: CleanerTheme.cyan) { model.selectedSection = .largeFiles; if model.largeFiles.isEmpty { model.scanLargeFiles() } }
                    QuickAction(title: "Odinstalátor", detail: "Aplikace beze zbytků", icon: "app.badge.checkmark", color: CleanerTheme.violet) { model.selectedSection = .applications }
                }
            }
            .padding(30)
        }
    }

    private var heroCard: some View {
        HStack(spacing: 28) {
            ZStack {
                Circle().stroke(CleanerTheme.border, lineWidth: 13)
                Circle().trim(from: 0, to: model.isScanningCleanup ? 0.25 : min(max(Double(model.totalCleanupSize) / 15_000_000_000, 0.12), 0.82))
                    .stroke(LinearGradient(colors: [CleanerTheme.mint, CleanerTheme.cyan], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 13, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Image(systemName: model.isScanningCleanup ? "arrow.triangle.2.circlepath" : "checkmark").font(.system(size: 26, weight: .bold)).foregroundStyle(CleanerTheme.mint)
                    Text(model.isScanningCleanup ? "Skenuji" : "Dobrá").font(.caption).fontWeight(.semibold)
                }
            }
            .frame(width: 132, height: 132)
            VStack(alignment: .leading, spacing: 9) {
                Text("Stav systému").font(.title3).fontWeight(.bold)
                Text(model.totalCleanupSize > 0 ? "Našli jsme prostor pro lehký úklid." : "Váš Mac vypadá čistě.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { model.selectedSection = .cleanup } label: {
                    Label("Zkontrolovat", systemImage: "arrow.right").labelStyle(.titleAndIcon)
                }.buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(26).frame(maxWidth: .infinity, minHeight: 205, alignment: .leading)
        .background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(CleanerTheme.border))
    }
}

private struct LeftoversView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PageHeader(
                        eyebrow: "Hloubková kontrola",
                        title: "Zbytky aplikací",
                        subtitle: "Data s bundle ID, ke kterému už není nalezena žádná aplikace.",
                        trailing: AnyView(
                            Button { model.scanOrphanedData() } label: {
                                Label(model.orphanedData.isEmpty ? "Spustit sken" : "Skenovat znovu", systemImage: "sparkle.magnifyingglass")
                            }.buttonStyle(PrimaryButtonStyle()).disabled(model.isScanningOrphans)
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
                        .overlay(RoundedRectangle(cornerRadius: 17).stroke(CleanerTheme.border))
                    }
                }.padding(30)
            }
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
            }.buttonStyle(.plain)
            Image(systemName: sourceIcon).font(.system(size: 15, weight: .semibold)).foregroundStyle(CleanerTheme.violet)
                .frame(width: 34, height: 34).background(CleanerTheme.violet.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.bundleIdentifier).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                Text("\(item.source) · \(displayPath(item.url))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(item.size.fileSizeText).font(.system(size: 12.5, weight: .semibold, design: .monospaced))
            Button { model.showInfo(for: item) } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless).help("Vyhledat informace na Googlu")
            Button { model.reveal(item.url) } label: { Image(systemName: "folder") }.buttonStyle(.borderless).help("Zobrazit ve Finderu")
        }.padding(.horizontal, 17).frame(height: 62)
    }

    private var sourceIcon: String {
        if item.source == "Cache" { return "shippingbox.fill" }
        if item.source == "Nastavení" { return "slider.horizontal.3" }
        if item.source == "Kontejner" { return "cube.fill" }
        return "doc.fill"
    }
}

private struct DeveloperDataView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PageHeader(
                        eyebrow: "Developer toolbox",
                        title: "Vývojářská data",
                        subtitle: "Cache, simulátory, SDK, runtime a balíčky na jednom místě.",
                        trailing: AnyView(
                            Button { model.scanDeveloperData() } label: {
                                Label(model.developerArtifacts.isEmpty ? "Analyzovat" : "Aktualizovat", systemImage: "terminal")
                            }.buttonStyle(PrimaryButtonStyle()).disabled(model.isScanningDeveloper)
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
                        .overlay(RoundedRectangle(cornerRadius: 17).stroke(CleanerTheme.border))
                    }
                    HStack(spacing: 9) {
                        Image(systemName: "lock.shield.fill").foregroundStyle(CleanerTheme.cyan)
                        Text("Nainstalované Homebrew a globální npm balíčky se pouze zobrazují. Odinstalujte je jejich správcem balíčků.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(30)
            }
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
            Image(systemName: artifact.category.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(categoryColor)
                .frame(width: 35, height: 35).background(categoryColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
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
                .buttonStyle(.borderless).help("Vyhledat informace na Googlu")
            Button { model.reveal(artifact.url) } label: { Image(systemName: "folder") }.buttonStyle(.borderless).help("Zobrazit ve Finderu")
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
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(color)
                .frame(width: 42, height: 42).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.system(size: 16, weight: .bold))
            }
            Spacer()
        }
        .padding(17).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CleanerTheme.border))
    }
}

private struct QuickAction: View {
    let title: String; let detail: String; let icon: String; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(color)
                        .frame(width: 42, height: 42).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(CleanerTheme.border))
        }.buttonStyle(.plain)
    }
}

private struct CleanupView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeader(
                        eyebrow: "Bezpečné čištění", title: "Chytrý úklid",
                        subtitle: "Vyberte, co chcete odstranit. Aplikace nikdy nemaže vaše dokumenty.",
                        trailing: AnyView(Button { model.scanCleanup() } label: { Label("Skenovat znovu", systemImage: "arrow.clockwise") }.buttonStyle(SecondaryButtonStyle()).disabled(model.isScanningCleanup))
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
                        .overlay(RoundedRectangle(cornerRadius: 17).stroke(CleanerTheme.border))
                    }
                    HStack(spacing: 9) {
                        Image(systemName: "info.circle.fill").foregroundStyle(CleanerTheme.cyan)
                        Text("Cache a logy budou přesunuty do Koše. Obsah Koše je jediná nevratná operace.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(30)
            }
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
                .help(group.isSelected ? "Odebrat sekci z výběru" : "Vybrat celou sekci")

                Button { model.toggleCleanupDetails(group.id) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: group.kind.icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
                            .frame(width: 38, height: 38).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
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
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
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
            }.buttonStyle(.borderless).help("Zobrazit ve Finderu")
        }
        .padding(.leading, 68).padding(.trailing, 18).frame(height: 48)
    }
}

private struct LargeFilesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PageHeader(
                        eyebrow: "Analyzátor úložiště", title: "Velké soubory",
                        subtitle: "Skenuje pouze vaše osobní složky, nikdy systémová data.",
                        trailing: AnyView(Button { model.scanLargeFiles() } label: { Label(model.largeFiles.isEmpty ? "Spustit sken" : "Skenovat znovu", systemImage: "magnifyingglass") }.buttonStyle(PrimaryButtonStyle()).disabled(model.isScanningLargeFiles))
                    )
                    Picker("Minimální velikost", selection: $model.largeFileThreshold) {
                        Text("100 MB+").tag(Int64(100_000_000)); Text("500 MB+").tag(Int64(500_000_000)); Text("1 GB+").tag(Int64(1_000_000_000))
                    }.pickerStyle(.segmented).frame(width: 330)
                    if model.isScanningLargeFiles {
                        LoadingCard(text: "Hledám velké soubory…")
                    } else if model.largeFiles.isEmpty {
                        EmptyState(icon: "externaldrive.badge.magnifyingglass", title: "Připraveno ke skenování", text: "Prohledáme Plochu, Dokumenty, Stažené soubory, Filmy, Hudbu a Obrázky.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(model.largeFiles.enumerated()), id: \.element.id) { index, file in
                                LargeFileRow(file: file)
                                if index < model.largeFiles.count - 1 { Divider().overlay(CleanerTheme.separator).padding(.leading, 58) }
                            }
                        }.background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).stroke(CleanerTheme.border))
                    }
                }.padding(30)
            }
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
            }.buttonStyle(.plain)
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable().frame(width: 31, height: 31)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                Text(file.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(file.size.fileSizeText).font(.system(size: 12.5, weight: .semibold, design: .monospaced))
            Button { model.reveal(file.url) } label: { Image(systemName: "folder") }.buttonStyle(.borderless).help("Zobrazit ve Finderu")
        }.padding(.horizontal, 17).frame(height: 61)
    }
}

private struct ApplicationsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(eyebrow: "Kompletní odstranění", title: "Aplikace", subtitle: "Odinstalujte aplikace spolu s jejich cache a nastavením.")
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Hledat aplikaci…", text: $model.appSearch).textFieldStyle(.plain)
                    }.padding(.horizontal, 12).frame(height: 36).background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(CleanerTheme.border))
                    Button { model.scanApplications() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(SecondaryButtonStyle()).disabled(model.isScanningApplications)
                }
            }.padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 18)
            if model.isScanningApplications && model.applications.isEmpty {
                LoadingCard(text: "Načítám nainstalované aplikace…").padding(.horizontal, 30)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.filteredApplications) { app in AppRow(app: app) }
                    }.padding(.horizontal, 30).padding(.bottom, 30)
                }
            }
        }
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
                .buttonStyle(.borderless).help("Vyhledat informace na Googlu")
            Button("Odinstalovat") { model.prepareRemoval(of: app) }.buttonStyle(SecondaryButtonStyle())
                .disabled(model.isUninstalling)
        }
        .padding(.horizontal, 17).frame(height: 75)
        .background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CleanerTheme.border))
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
            }.frame(width: 590, height: min(560, 300 + CGFloat(plan.relatedFiles.count) * 48)).background(CleanerTheme.background)
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
                VStack(spacing: 0) {
                    PrivacyRow(icon: "network.slash", title: "Offline skenování", text: "Analýza disku probíhá lokálně. Pouze po kliknutí na ⓘ se Googlu odešle název a technický kontext položky, nikdy její cesta. Google cookies se uchovají kvůli souhlasu a přihlášení.", color: CleanerTheme.mint)
                    Divider().overlay(CleanerTheme.separator).padding(.leading, 68)
                    PrivacyRow(icon: "trash.slash.fill", title: "Obnovitelné kroky", text: "Aplikace, velké soubory, cache a logy se nejprve přesouvají do Koše.", color: CleanerTheme.cyan)
                    Divider().overlay(CleanerTheme.separator).padding(.leading, 68)
                    PrivacyRow(icon: "person.crop.circle.badge.checkmark", title: "Vy rozhodujete", text: "Před každým odstraněním vidíte velikost i přesný seznam vybraných položek.", color: CleanerTheme.violet)
                }.background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).stroke(CleanerTheme.border))
            }.padding(30)
        }
    }
}

private struct PrivacyRow: View {
    let icon: String; let title: String; let text: String; let color: Color
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(color).frame(width: 40, height: 40).background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 14, weight: .semibold)); Text(text).font(.caption).foregroundStyle(.secondary) }
        }.padding(19).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsView: View {
    @AppStorage("appAppearance") private var appearanceRaw = AppAppearance.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .system }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: nimboImage(named: colorScheme == .dark ? "nimbo-icon-dark" : "nimbo-icon-light"))
                    .resizable().scaledToFit().frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nimbo").font(.title).fontWeight(.bold)
                    Text("Čistší. Rychlejší.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Bezpečný lokální nástroj pro údržbu macOS.").foregroundStyle(.secondary)
            Divider()
            HStack {
                Label("Vzhled", systemImage: "paintbrush.fill")
                Spacer()
                Picker("Vzhled", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { item in
                        Label(item.title, systemImage: item.icon).tag(item.rawValue)
                    }
                }.labelsHidden().frame(width: 180)
            }
            Label("Všechny analýzy probíhají offline", systemImage: "checkmark.shield.fill").foregroundStyle(CleanerTheme.mint)
            Label("Soubory se standardně přesouvají do Koše", systemImage: "trash.fill").foregroundStyle(CleanerTheme.cyan)
            Button("Nastavit přístup k disku…") { DiskAccessHelp.shared.show() }
            Divider()
            UpdateSettingsView()
            Spacer()
            Text("Verze \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"))")
                .font(.caption).foregroundStyle(.tertiary)
        }.padding(30).background(CleanerTheme.background)
            .preferredColorScheme(appearance.colorScheme)
    }
}

private struct LoadingCard: View {
    let text: String
    var body: some View {
        HStack(spacing: 13) { ProgressView().controlSize(.small); Text(text).font(.system(size: 13)).foregroundStyle(.secondary); Spacer() }
            .padding(20).background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(CleanerTheme.border))
    }
}

private struct EmptyState: View {
    let icon: String; let title: String; let text: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 35, weight: .light)).foregroundStyle(CleanerTheme.cyan)
            Text(title).font(.headline)
            Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }.frame(maxWidth: .infinity, minHeight: 230).background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).stroke(CleanerTheme.border))
    }
}

private struct BottomActionBar: View {
    let label: String; let disabled: Bool; let action: () -> Void
    var body: some View {
        HStack {
            Label("Před odstraněním vždy uvidíte potvrzení", systemImage: "shield.checkered").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(label, action: action).buttonStyle(PrimaryButtonStyle()).disabled(disabled)
        }.padding(.horizontal, 20).frame(height: 62).nimboGlass(radius: 20).padding(12)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.primary)
            .padding(.horizontal, 15).frame(height: 34)
            .nimboGlass(interactive: true, tint: CleanerTheme.mint, radius: 9)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12.5, weight: .medium)).foregroundStyle(.primary)
            .padding(.horizontal, 13).frame(height: 32)
            .nimboGlass(interactive: true, radius: 8)
    }
}
