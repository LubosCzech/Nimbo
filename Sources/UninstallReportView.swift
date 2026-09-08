import SwiftUI
import AppKit

struct UninstallReportView: View {
    let report: UninstallReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(report.appRemoved ? "Aplikace odstraněna, některá data zůstala" : "Aplikaci se nepodařilo přesunout")
                .font(.title2.bold())
            Text(report.appName).font(.headline)
            if !report.skipped.isEmpty {
                Text("Související data jsme ponechali beze změny, protože přesun aplikace selhal.")
                    .foregroundStyle(.secondary)
            }
            if report.failures.contains(where: \.permissionDenied) {
                Text("Aplikace v /Applications může vyžadovat oprávnění správce. Zobrazte ji ve Finderu a přesuňte do Koše; macOS si případné ověření vyžádá. U chráněných dat v Library může být potřeba povolit Nimbo v Nastavení systému → Soukromí a zabezpečení → Úplný přístup k disku a Nimbo znovu spustit.")
                    .font(.callout)
                Button("Otevřít nastavení přístupu k disku") {
                    DiskAccessHelp.shared.show()
                    DiskAccessHelp.shared.openSettings()
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
                            Text(failure.permissionDenied ? "macOS odepřel přístup k této položce." : failure.message)
                                .foregroundStyle(.secondary).font(.caption)
                            DisclosureGroup("Technický detail") {
                                Text(failure.message).font(.caption).textSelection(.enabled)
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
        }.padding(24).frame(width: 650, height: 500)
    }
}
