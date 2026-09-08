import AppKit
import SwiftUI

@MainActor
final class DiskAccessHelp {
    static let shared = DiskAccessHelp()
    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 470),
                styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            window.title = "Přístup k disku — Nimbo"
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: DiskAccessHelpView())
            window.center()
            panel = window
        }
        panel?.makeKeyAndOrderFront(nil)
    }

    func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
}

private struct DiskAccessHelpView: View {
    @AppStorage("appAppearance") private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        DiskAccessHelpContent()
            .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .system).colorScheme)
    }
}

private struct DiskAccessHelpContent: View {
    @Environment(\.colorScheme) private var colorScheme
    private let appURL = Bundle.main.bundleURL

    var body: some View {
        VStack(spacing: 14) {
            Text("Povolte Nimbu přístup k disku")
                .font(.title3.bold())
            Text("1. Otevřete nastavení tlačítkem níže.\n2. Přetáhněte ikonu Nimba do seznamu aplikací.\n3. Zapněte přepínač a Nimbo znovu spusťte.")
                .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 4) {
                Image(nsImage: nimboImage(named: colorScheme == .dark ? "nimbo-icon-dark" : "nimbo-icon-light"))
                    .resizable().scaledToFit().frame(width: 88, height: 88)
                Text("Nimbo.app").font(.headline)
                Label("Přetáhněte do nastavení", systemImage: "hand.draw")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(10)
            .contentShape(Rectangle())
            .onDrag { NSItemProvider(object: appURL as NSURL) }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityLabel("Nimbo.app — přetáhnout do Úplného přístupu k disku")
            Text(appURL.path).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            Button("Otevřít Úplný přístup k disku") { DiskAccessHelp.shared.openSettings() }
                .buttonStyle(.borderedProminent)
            Button("Zobrazit tuto kopii Nimba ve Finderu") {
                NSWorkspace.shared.activateFileViewerSelecting([appURL])
            }.buttonStyle(.link)
            Text("Pokud přetažení nefunguje, přidejte aplikaci tlačítkem +. Toto okno zůstane viditelné i nad Nastavením systému.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(width: 420, height: 470)
    }
}
