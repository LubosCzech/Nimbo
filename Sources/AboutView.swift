import AppKit
import SwiftUI

@MainActor
final class AboutWindow {
    static let shared = AboutWindow()
    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 410),
                styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            window.title = "O aplikaci Nimbo"
            window.isReleasedWhenClosed = false
            // NSPanel hides itself when the app deactivates; an About window
            // must stay put when the user switches away and back.
            window.hidesOnDeactivate = false
            window.contentView = NSHostingView(rootView: AboutHostView())
            window.center()
            panel = window
        }
        panel?.makeKeyAndOrderFront(nil)
    }
}

private struct AboutHostView: View {
    @AppStorage("appAppearance") private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        AboutContent()
            .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .system).colorScheme)
    }
}

private struct AboutContent: View {
    @Environment(\.colorScheme) private var colorScheme

    private static let studioURL = URL(string: "https://svtk.dev")!

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Verze \(version) (\(build))"
    }

    private var year: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: nimboImage(named: colorScheme == .dark ? "nimbo-icon-dark" : "nimbo-icon-light"))
                    .resizable().scaledToFit().frame(width: 96, height: 96)
                    .accessibilityHidden(true)
                Text("Nimbo").font(.title.bold())
                Text(versionText).font(.callout).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Bezpečná údržba Macu. Skenování probíhá lokálně, bez odesílání dat.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)

            Divider().padding(.vertical, 20)

            // The studio mark is bundled, not fetched: Nimbo makes no network
            // request the user did not ask for, and this window is no exception.
            HStack(spacing: 14) {
                Image(nsImage: nimboImage(named: "svtk-mark"))
                    .resizable().scaledToFit().frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(CleanerTheme.border))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 0) {
                        Text("svtk").font(.title3.weight(.semibold))
                        Text(".dev").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text("Nezávislé softwarové studio")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Link(destination: Self.studioURL) {
                Label("Otevřít svtk.dev", systemImage: "safari")
            }
            .nimboPrimaryAction()
            .padding(.top, 16)
            .accessibilityLabel("Otevřít svtk.dev v prohlížeči")

            Spacer(minLength: 12)

            Text("© \(String(year)) svtk.dev")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 380, height: 410)
    }
}
