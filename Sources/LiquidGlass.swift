import SwiftUI

// Glass belongs to the control layer, not to the data surfaces.
extension View {
    @ViewBuilder
    func nimboActionBar<Bar: View>(@ViewBuilder content: () -> Bar) -> some View {
        if #available(macOS 26.0, *) {
            self.safeAreaBar(edge: .bottom, spacing: 0, content: content)
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0, content: content)
        }
    }
    func nimboPrimaryAction() -> some View {
        self.buttonStyle(NimboProminentButtonStyle()).controlSize(.large)
    }
}

private struct NimboProminentButtonStyle: PrimitiveButtonStyle {
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            nativeButton(configuration).buttonStyle(.glassProminent)
        } else {
            nativeButton(configuration).buttonStyle(.borderedProminent)
        }
    }

    private func nativeButton(_ configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.foregroundColor(isEnabled && activeState != .inactive ? .white : .secondary)
        }
        .tint(.accentColor)
    }
}
