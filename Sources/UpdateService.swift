import Combine
import Sparkle
import SwiftUI

@MainActor
final class UpdateService: ObservableObject {
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var lastCheck: Date?
    @Published private(set) var configurationMessage: String?
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        let info = Bundle.main.infoDictionary ?? [:]
        guard let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              let key = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32 else {
            configurationMessage = "Aktualizace zatím nejsou nakonfigurované. Chybí GitHub repozitář nebo veřejný podpisový klíč."
            return
        }
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticChecks)
        updater.publisher(for: \.lastUpdateCheckDate).assign(to: &$lastCheck)
        do { try updater.start() }
        catch {
            canCheck = false
            configurationMessage = "Aktualizace nelze spustit: \(error.localizedDescription)"
        }
    }

    func check() { if canCheck && configurationMessage == nil { controller.checkForUpdates(nil) } }
    func setAutomaticChecks(_ enabled: Bool) {
        guard configurationMessage == nil else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}

struct UpdateSettingsView: View {
    @EnvironmentObject private var updates: UpdateService
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Aktualizace", systemImage: "arrow.triangle.2.circlepath").font(.headline)
            if let message = updates.configurationMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Toggle("Automaticky kontrolovat aktualizace", isOn: Binding(
                    get: { updates.automaticChecks }, set: updates.setAutomaticChecks))
                Text("Kontrola jednou denně. Stažení a instalaci potvrdíte v dialogu Sparkle.")
                    .font(.caption).foregroundStyle(.secondary)
                if let date = updates.lastCheck {
                    Text("Poslední kontrola: \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("Zkontrolovat aktualizace…", action: updates.check).disabled(!updates.canCheck)
        }
    }
}
