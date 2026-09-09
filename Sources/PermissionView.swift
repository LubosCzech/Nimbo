import AppKit
import SwiftUI

extension PermissionScope {
    var icon: String {
        switch self {
        case .personalFiles: return SidebarSection.largeFiles.icon
        case .cleanup: return SidebarSection.cleanup.icon
        case .appData: return SidebarSection.leftovers.icon
        case .development: return SidebarSection.development.icon
        case .applications: return SidebarSection.applications.icon
        case .startup: return SidebarSection.startup.icon
        case .automation: return "gearshape.2"
        }
    }
}

private extension PermissionState {
    var color: Color {
        switch self {
        case .available: return CleanerTheme.mint
        case .denied: return CleanerTheme.orange
        case .notRequested, .unknown: return CleanerTheme.cyan
        case .checking, .notApplicable: return .secondary
        }
    }
    var symbol: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .denied: return "exclamationmark.triangle.fill"
        case .notRequested: return "hand.raised"
        case .unknown: return "questionmark.circle"
        case .checking: return "arrow.clockwise"
        case .notApplicable: return "minus.circle"
        }
    }
}

struct PermissionSummaryView: View {
    @EnvironmentObject private var permissions: PermissionController
    var openDetails: (() -> Void)? = nil

    var body: some View {
        Button {
            if let openDetails { openDetails() } else { permissions.showDetails = true }
        } label: {
            HStack(spacing: 12) {
                NimboIconBadge(symbol: permissions.needsAttention ? "exclamationmark.shield" : SidebarSection.privacy.icon,
                               color: permissions.needsAttention ? CleanerTheme.orange : CleanerTheme.mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(permissions.isChecking ? "Kontroluji oprávnění…" : "Přístup Nimba").font(.headline)
                    Text(permissions.isChecking ? "Ověřuji složky a stav automatizace."
                         : permissions.needsAttention ? "Oblasti vyžadující pozornost: \(permissions.attentionCount). Některé výsledky mohou být neúplné."
                         : "Kontrolované složky jsou dostupné. Zobrazit podrobnosti.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if permissions.isChecking { ProgressView().controlSize(.small) }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(16).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityHint("Otevře podrobnosti kontroly oprávnění")
    }
}

struct PermissionDetailsView: View {
    @EnvironmentObject private var permissions: PermissionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                NimboIconBadge(symbol: "checkmark.shield", color: CleanerTheme.mint, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Přístup a oprávnění").font(.title2.bold())
                    Text("Nimbo kontroluje potřebný přístup při každém spuštění.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if permissions.needsAttention {
                        Label("Některé funkce mají omezení nebo jejich přístup nelze ověřit. Můžete pokračovat a oprávnění vyřešit později.",
                              systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(permissions.checks) { check in PermissionCheckRow(check: check) }
                    if let message = permissions.requestMessage {
                        Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Text("„Dostupné“ potvrzuje čtení kontrolovaných složek, nikoli úplný přístup k celému disku. Podsložky a přesun konkrétních položek mohou mít další omezení. Chybějící volitelné nástroje nejsou chybou. Nimbo nevyžaduje přístup ke kameře, mikrofonu, obrazovce ani Zpřístupnění.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let date = permissions.lastChecked {
                        Text("Poslední kontrola: \(date.formatted(date: .omitted, time: .standard))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(24)
            }
            Divider()
            HStack {
                Button { permissions.recheck() } label: {
                    Label("Zkontrolovat znovu", systemImage: "arrow.clockwise")
                }.disabled(permissions.isChecking || permissions.isRequestingAutomation)
                if permissions.isChecking { ProgressView().controlSize(.small) }
                Spacer()
                Button(permissions.needsAttention ? "Pokračovat s omezením" : "Hotovo") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }.padding(20)
        }.frame(width: 690, height: 640)
    }
}

private struct PermissionCheckRow: View {
    @EnvironmentObject private var permissions: PermissionController
    let check: PermissionCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                NimboIconBadge(symbol: check.scope.icon, color: check.state.color, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(check.scope.title).font(.headline)
                    Text(check.scope.purpose).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Label(check.state.title, systemImage: check.state.symbol)
                    .font(.caption).foregroundStyle(check.state.color).fixedSize()
            }
            if let note = check.note { Text(note).font(.caption).foregroundStyle(.secondary) }
            if check.state.needsAttention {
                if check.scope == .automation {
                    HStack {
                        Button("Povolit automatizaci…") { permissions.requestAutomation() }
                            .disabled(permissions.isChecking || permissions.isRequestingAutomation)
                        Button("Nastavení automatizace") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                        }
                    }
                } else {
                    HStack {
                        Button("Nastavit přístup k disku…") {
                            DiskAccessHelp.shared.show()
                            DiskAccessHelp.shared.openSettings()
                        }
                        if check.scope == .personalFiles {
                            Button("Soubory a složky") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
                            }
                        }
                    }
                    Text("Odepření může způsobit ochrana soukromí i oprávnění souborového systému. Nimbo nic nemění automaticky.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !check.probes.isEmpty {
                DisclosureGroup("Kontrolované složky (\(check.probes.count))") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(check.probes, id: \.path) { probe in
                            HStack {
                                Text((probe.path as NSString).abbreviatingWithTildeInPath)
                                    .lineLimit(2).textSelection(.enabled)
                                Spacer()
                                Label(probe.state == .notApplicable ? "Neexistuje" : probe.state.title,
                                      systemImage: probe.state.symbol).foregroundStyle(probe.state.color)
                            }.font(.caption)
                        }
                    }.padding(.top, 8)
                }.font(.caption)
            }
        }.padding(16).background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 16))
    }
}
