import SwiftUI

// Glass belongs to the control layer, not to the data surfaces.
extension View {
    /// Bottom bar with its own glass. `safeAreaBar` only manages the safe area
    /// and the scroll edge effect, so the bar's background is ours to draw.
    /// `.soft` is the blur that belongs between scrolling content and controls.
    func nimboActionBar<Bar: View>(@ViewBuilder content: () -> Bar) -> some View {
        safeAreaBar(edge: .bottom, spacing: 0) {
            // Inset from the window edges: glass reads as glass when content
            // passes behind it, which a band flush to the edge never shows.
            content()
                .nimboGlass(interactive: true)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    /// Liquid Glass that steps aside when the system asks for less transparency.
    /// Reduce Transparency is a request not to draw translucency at all, so it
    /// is answered with an opaque surface rather than a thinner glass.
    func nimboGlass(interactive: Bool = false) -> some View {
        modifier(NimboGlass(interactive: interactive))
    }

    func nimboPrimaryAction() -> some View {
        buttonStyle(NimboProminentButtonStyle()).controlSize(.large)
    }
}

private struct NimboGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let interactive: Bool

    func body(content: Content) -> some View {
        // Corners follow the window's curvature instead of a hand-guessed
        // radius, with a floor so an inset bar stays visibly rounded.
        let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(18)))
        if reduceTransparency {
            content
                .background(CleanerTheme.panelStrong, in: shape)
                .overlay(shape.stroke(CleanerTheme.border))
        } else {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        }
    }
}

private struct NimboProminentButtonStyle: PrimitiveButtonStyle {
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.foregroundColor(isEnabled && activeState != .inactive ? .white : .secondary)
        }
        .tint(.accentColor)
        .buttonStyle(.glassProminent)
    }
}
