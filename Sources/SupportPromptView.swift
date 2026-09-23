import SwiftUI

/// Prosba, ne vymáhání: zavřít ji jde třemi způsoby a jeden z nich ji umlčí navždy.
struct SupportPromptView: View {
    // Předané přímo, ne z prostředí: obsah listu prostředí prezentujícího
    // pohledu nezdědil a stisk tlačítka aplikaci shodil.
    @ObservedObject var support: SupportService

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 34)).foregroundStyle(CleanerTheme.mint)
                .accessibilityHidden(true)
            Text("Slouží vám Nimbo dobře?").font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Nimbo dělá nezávislé studio bez reklam a bez odesílání vašich dat. Když vám šetří místo i čas, můžete nás pozvat na kávu.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button { support.support() } label: {
                Label("Koupit kávu", systemImage: "cup.and.saucer")
            }
            .nimboPrimaryAction()

            VStack(spacing: 6) {
                Button("Už jsem přispěl") { support.acknowledge() }
                    .buttonStyle(.link)
                Button("Teď ne, zeptejte se později") { support.postpone() }
                    .buttonStyle(.link)
            }
            Text("Zeptáme se nanejvýš jednou za měsíc. Po vašem potvrzení už nikdy.")
                .font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 380)
        .onDisappear { support.isPrompting = false }
    }
}
