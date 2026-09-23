import SwiftUI

struct PerformanceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(eyebrow: "Co zpomaluje Mac", title: "Výkon",
                           subtitle: "Nimbo ukáže, co má na rychlost skutečný vliv. Měří se při otevření sekce.",
                           trailing: AnyView(
                            Button { model.measurePerformance() } label: {
                                Label("Změřit znovu", systemImage: "arrow.clockwise")
                            }.disabled(model.isMeasuringPerformance)))

                VStack(spacing: 0) {
                    ForEach(Array(model.performanceReadings.enumerated()), id: \.element.id) { index, reading in
                        PerformanceRow(reading: reading) { section in
                            model.selectedSection = section
                        }
                        if index < model.performanceReadings.count - 1 {
                            Divider().overlay(CleanerTheme.separator).padding(.leading, 56)
                        }
                    }
                }
                .background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 17))

                if !model.performanceProcesses.isEmpty {
                    Text("NEJNÁROČNĚJŠÍ PROCESY")
                        .font(.system(size: 10, weight: .bold)).tracking(1.2)
                        .foregroundStyle(.secondary).padding(.top, 4)
                    VStack(spacing: 0) {
                        ForEach(model.performanceProcesses) { process in
                            HStack(spacing: 12) {
                                NimboIconBadge(symbol: "cpu", color: CleanerTheme.cyan, size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(process.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text("PID \(process.pid)").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(process.residentBytes.fileSizeText).font(.system(size: 12, design: .monospaced))
                                Text(String(format: "%.0f %% CPU", process.cpuPercent))
                                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                                    .frame(width: 78, alignment: .trailing)
                            }.padding(.horizontal, 17).frame(height: 54)
                            if process.id != model.performanceProcesses.last?.id {
                                Divider().overlay(CleanerTheme.separator).padding(.leading, 56)
                            }
                        }
                    }
                    .background(CleanerTheme.panel, in: RoundedRectangle(cornerRadius: 17))

                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                    } label: {
                        Label("Otevřít Monitor aktivity", systemImage: "chart.line.uptrend.xyaxis")
                    }.buttonStyle(.link)
                }

                DisclosureGroup("Co Nimbo záměrně nedělá") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(PerformanceView.omissions, id: \.self) { line in
                            Label(line, systemImage: "minus.circle")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(.top, 8)
                }
                .padding(17)
                .background(CleanerTheme.recessed, in: RoundedRectangle(cornerRadius: 15))
            }.padding(32)
        }
        .task { if model.performanceReadings.isEmpty { model.measurePerformance() } }
    }

    // Sepsané schválně: nástroje, které tohle slibují, většinou neřeknou proč ne.
    static let omissions = [
        "Neuvolňuje paměť. macOS v ní drží data, aby je nemusel číst z disku; vyprázdnit ji znamená příští čtení zpomalit.",
        "Nespouští periodické skripty. Na dnešním macOS už neexistují.",
        "Neopravuje oprávnění disku. Od macOS 10.11 se o systémové soubory stará sám systém.",
        "Neukončuje procesy. Ukáže je; ukončení patří do Monitoru aktivity."
    ]
}

private struct PerformanceRow: View {
    let reading: PerformanceReading
    let open: (SidebarSection) -> Void

    var body: some View {
        HStack(spacing: 12) {
            NimboIconBadge(symbol: reading.topic.icon,
                           color: reading.state == .attention ? CleanerTheme.orange : CleanerTheme.mint)
            VStack(alignment: .leading, spacing: 3) {
                Text(reading.topic.title).font(.system(size: 14, weight: .semibold))
                Text(reading.detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Text(reading.value).font(.system(size: 13, weight: .medium, design: .monospaced))
            if let destination = reading.topic.destination, reading.state == .attention {
                Button(destination.title) { open(destination) }.buttonStyle(.link)
            }
        }
        .padding(.horizontal, 17).padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityValue(reading.state == .attention ? "Vyžaduje pozornost" : "V pořádku")
    }
}
