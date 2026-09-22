import SwiftUI
import AppKit

struct UninstallReportView: View {
    let report: UninstallReport
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Výsledek odinstalace", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.medium)).foregroundStyle(CleanerTheme.orange)
            Text(report.appRemoved ? "Aplikace odstraněna, některá data zůstala" : "Aplikaci se nepodařilo přesunout")
                .font(.title2.bold())
            Text(report.appName).font(.headline)
            if !report.skipped.isEmpty {
                Text("Související data jsme ponechali beze změny, protože přesun aplikace selhal.")
                    .foregroundStyle(.secondary)
            }
            if let obstacle = report.failures.dominantObstacle {
                Text(obstacle.advice).font(.callout)
                // App Management comes first: while it is denied, macOS refuses
                // the move whoever performs it, so the Finder handoff fails too.
                if UninstallService.mayNeedAppManagement(report) {
                    Text("macOS navíc brání Nimbu v úpravě jiných aplikací, dokud ho nepovolíte v Nastavení systému → Soukromí a zabezpečení → Správa aplikací. Do té doby odmítne i přesun přes Finder.")
                        .font(.callout)
                    Button("Otevřít Správu aplikací") {
                        DiskAccessHelp.shared.openAppManagement()
                    }
                }
                HStack(spacing: 10) {
                    // Finder can finish an ownership block; nothing else can,
                    // short of a privileged helper Nimbo deliberately does not ship.
                    if UninstallService.canRetryViaFinder(report) {
                        Button {
                            model.retryViaFinder()
                        } label: {
                            Label("Dokončit přes Finder", systemImage: "folder.badge.person.crop")
                        }
                        .disabled(model.isRetryingViaFinder)
                    }
                    // Only a privacy denial is fixed by Full Disk Access; offering
                    // it for an ownership or SIP block would send the user nowhere.
                    if report.failures.contains(where: { $0.obstacle.needsFullDiskAccess }) {
                        Button("Otevřít nastavení přístupu k disku") {
                            DiskAccessHelp.shared.show()
                            DiskAccessHelp.shared.openSettings()
                        }
                    }
                    if model.isRetryingViaFinder {
                        ProgressView().controlSize(.small)
                        Text("Čekám na Finder a ověření správce…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if UninstallService.canRetryViaFinder(report) {
                    Text("Finder si vyžádá heslo správce. Nimbo heslo nevidí a nic nespouští s právy roota.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let message = model.finderRetryMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(CleanerTheme.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(report.failures) { failure in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(failure.url.lastPathComponent).bold()
                                Spacer()
                                Button("Zobrazit ve Finderu") {
                                    NSWorkspace.shared.activateFileViewerSelecting([failure.url])
                                }
                            }
                            Text(failure.url.path).font(.caption).textSelection(.enabled)
                            Text(failure.reason)
                                .foregroundStyle(.secondary).font(.caption)
                            DisclosureGroup("Technický detail") {
                                VStack(alignment: .leading, spacing: 4) {
                                    if !failure.diagnosis.detail.isEmpty {
                                        Text(failure.diagnosis.detail).font(.caption).textSelection(.enabled)
                                    }
                                    Text(failure.message).font(.caption).textSelection(.enabled)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        Divider()
                    }
                }
            }
            HStack {
                Text("Přesunuto do Koše: \(report.moved.count) · Ponecháno: \(report.failures.count + report.skipped.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Zavřít") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(28).frame(width: 680, height: 540).tint(CleanerTheme.mint)
    }
}
