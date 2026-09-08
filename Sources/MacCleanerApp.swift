import SwiftUI

@main
struct NimboApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updates = UpdateService()
    @AppStorage("appAppearance") private var appearanceRaw = AppAppearance.system.rawValue

    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .system }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 650)
                .preferredColorScheme(appearance.colorScheme)
                .onAppear { model.startInitialScan() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Zkontrolovat aktualizace…", action: updates.check)
                    .disabled(!updates.canCheck)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(updates)
                .frame(width: 520, height: 600)
        }
    }
}
