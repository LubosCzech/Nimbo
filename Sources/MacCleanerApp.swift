import SwiftUI

@main
struct NimboApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updates = UpdateService()
    @StateObject private var permissions = PermissionController()
    @AppStorage("appAppearance") private var appearanceRaw = AppAppearance.system.rawValue

    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .system }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(permissions)
                .frame(minWidth: 980, minHeight: 650)
                .preferredColorScheme(appearance.colorScheme)
                .onAppear { permissions.start { model.startInitialScan() } }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    permissions.refreshAfterActivation()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1160, height: 780)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Zkontrolovat aktualizace…", action: updates.check)
                    .disabled(!updates.canCheck)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(updates)
                .environmentObject(permissions)
                .frame(width: 580, height: 660)
        }
    }
}
