import AppKit
import SwiftUI

@MainActor
final class StartupModel: ObservableObject {
    @Published var items: [StartupItem] = []
    @Published var busy = false
    @Published var message: String?
    @Published var includeApps = false
    @Published var search = ""

    func refresh() {
        guard !busy else { return }
        busy = true
        let apps = includeApps
        Task {
            let result = await Task.detached { () -> ([StartupItem], [String]) in
                var list: [StartupItem] = [], errors: [String] = []
                do { list += try StartupService.services() } catch { errors.append("Služby: \(error.localizedDescription)") }
                if apps {
                    do { list += try StartupService.loginItems() }
                    catch { errors.append("Aplikace: povolte Nimbu ovládání System Events v Soukromí a zabezpečení → Automatizace.\n\(error.localizedDescription)") }
                }
                return (list, errors)
            }.value
            items = result.0
            message = result.1.isEmpty ? nil : result.1.joined(separator: "\n")
            busy = false
        }
    }

    func change(_ item: StartupItem, enabled: Bool) {
        guard !busy else { return }
        busy = true
        Task {
            let errorMessage = await Task.detached { () -> String? in
                do {
                    if item.kind == "Aplikace" { try StartupService.setLogin(item, enabled: enabled) }
                    else { try StartupService.setService(item, enabled: enabled) }
                    return nil
                } catch { return error.localizedDescription }
            }.value
            if let errorMessage { message = errorMessage }
            else {
                var updated = item; updated.enabled = enabled
                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = updated }
                else { items.insert(updated, at: 0) }
                message = item.kind == "Aplikace" ? "Změna pro příští přihlášení byla ověřena." : "Povolení služby bylo změněno. Projeví se při příštím přihlášení; aktuálně běžící proces pokračuje."
            }
            busy = false
        }
    }

    func addApp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Spouštět po přihlášení"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        includeApps = true
        change(StartupItem(name: url.deletingPathExtension().lastPathComponent, path: url.path,
                           label: "", kind: "Aplikace", enabled: false), enabled: true)
    }
}

struct StartupView: View {
    @StateObject private var model = StartupModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Po spuštění").font(.largeTitle.bold())
                    Text("Aplikace po přihlášení a služby na pozadí.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Obnovit", systemImage: "arrow.clockwise") { model.refresh() }.disabled(model.busy)
            }
            HStack {
                Button("Načíst přihlašovací aplikace") { model.includeApps = true; model.refresh() }.disabled(model.busy)
                Button("Přidat aplikaci…") { model.addApp() }.disabled(model.busy)
                Spacer()
                Button("Nastavení macOS") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                }
            }
            Text("Přepínače služeb určují povolení spuštění, nikoli to, zda proces právě běží. Služby se mohou spouštět také podle potřeby nebo plánu. Systémové služby a moderní položky na pozadí spravujte v Nastavení macOS.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Hledat název nebo cestu", text: $model.search).textFieldStyle(.roundedBorder)
            if model.busy { ProgressView().controlSize(.small) }
            if let message = model.message {
                Text(message).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.items.filter { model.search.isEmpty || $0.name.localizedCaseInsensitiveContains(model.search) || $0.path.localizedCaseInsensitiveContains(model.search) }) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.kind == "Aplikace" ? "app" : "gearshape.2")
                                .font(.title2).foregroundStyle(CleanerTheme.cyan).frame(width: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.headline).lineLimit(1)
                                Text(item.kind).font(.caption).foregroundStyle(.secondary)
                                Text(item.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1).help(item.path)
                            }
                            Spacer()
                            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) } label: {
                                Image(systemName: "folder")
                            }.buttonStyle(.borderless).help("Zobrazit ve Finderu")
                            if item.canToggle {
                                Toggle("Povoleno", isOn: Binding(get: { item.enabled == true }, set: { model.change(item, enabled: $0) }))
                                    .labelsHidden().toggleStyle(.switch).disabled(model.busy)
                                    .help("Povolit při příštím přihlášení")
                            } else {
                                Label(item.enabled.map { $0 ? "Povoleno" : "Zakázáno" } ?? "Neznámý stav", systemImage: "lock")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(16).background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                    }
                    if model.items.isEmpty && !model.busy { Text("Žádné položky nebyly načteny.").foregroundStyle(.secondary).padding() }
                }
            }
        }.padding(26).task { model.refresh() }
    }
}
