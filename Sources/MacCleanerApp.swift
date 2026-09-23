import SwiftUI

@main
struct NimboApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updates = UpdateService()
    @StateObject private var permissions = PermissionController()
    @StateObject private var support = SupportService()
    @AppStorage("appAppearance") private var appearanceRaw = AppAppearance.system.rawValue

    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .system }

    // Before any stored preference is read: the bundle identifier changed in
    // 1.6 and settings live in a file named after it.
    init() { PreferencesMigration.run() }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(permissions)
                .environmentObject(support)
                .frame(minWidth: 980, minHeight: 650)
                .preferredColorScheme(appearance.colorScheme)
                .onAppear {
                    permissions.start {
                        model.startInitialScan()
                        // Nikdy přes list s oprávněními: ten řeší funkčnost aplikace.
                        // Když je otevřený, dotaz se jen odloží — jinak by ho na
                        // Macu s trvalým upozorněním uživatel nikdy neviděl.
                        if !permissions.showDetails { support.promptIfDue() }
                    }
                }
                .sheet(isPresented: $support.isPrompting) { SupportPromptView(support: support) }
                .onChange(of: permissions.showDetails) { _, isShowing in
                    if !isShowing { support.promptIfDue() }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    permissions.refreshAfterActivation()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1160, height: 780)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("O aplikaci Nimbo") { AboutWindow.shared.show() }
            }
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
