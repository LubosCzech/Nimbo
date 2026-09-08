import SwiftUI

extension View {
    @ViewBuilder
    func nimboGlass(interactive: Bool = false, tint: Color? = nil, radius: CGFloat = 16) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(interactive), in: RoundedRectangle(cornerRadius: radius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
        }
    }
}
