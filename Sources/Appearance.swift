import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Podle systému"
        case .light: return "Světlý"
        case .dark: return "Tmavý"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

func nimboImage(named name: String) -> NSImage {
    guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
          let image = NSImage(contentsOf: url) else { return NSImage() }
    return image
}

struct DockIconUpdater: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { updateIcon() }
            .onChange(of: colorScheme) { _, _ in updateIcon() }
    }

    private func updateIcon() {
        let resource = colorScheme == .dark ? "nimbo-icon-dark" : "nimbo-icon-light"
        let image = nimboImage(named: resource)
        guard image.size.width > 0 else { return }
        NSApplication.shared.applicationIconImage = image
    }
}
