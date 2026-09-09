import SwiftUI

/// Edge-to-edge artwork extends behind navigation, but never mirrors the text.
struct OverviewHeader: View {
    var body: some View {
        GeometryReader { geometry in
            Image(nsImage: nimboImage(named: "nimbo-landscape-header"))
                .resizable().renderingMode(.original).scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.68)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .accessibilityHidden(true)
                .nimboBackgroundExtension()
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Vítejte v Nimbu").font(.subheadline.weight(.medium))
                        Text("Více místa. Méně starostí.")
                            .font(.system(size: 32, weight: .bold)).accessibilityAddTraits(.isHeader)
                        Text("Prostor pro to, na čem záleží.").font(.body)
                    }
                    .foregroundStyle(.white).padding(32)
                }
        }.frame(height: 300)
    }
}

private extension View {
    @ViewBuilder func nimboBackgroundExtension() -> some View {
        if #available(macOS 26.0, *) { self.backgroundExtensionEffect() }
        else { self }
    }
}
