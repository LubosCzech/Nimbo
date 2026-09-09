import SwiftUI

extension SidebarSection {
    var accent: Color {
        switch self {
        case .overview, .cleanup, .startup, .privacy: return CleanerTheme.mint
        case .largeFiles, .development: return CleanerTheme.cyan
        case .applications: return CleanerTheme.violet
        case .leftovers: return CleanerTheme.orange
        }
    }
}

/// Filled symbols are reserved for state; navigation badges share one geometry.
struct NimboIconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.monochrome).symbolVariant(.none)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(color).frame(width: size, height: size)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: size * 0.26))
            .accessibilityHidden(true)
    }
}
