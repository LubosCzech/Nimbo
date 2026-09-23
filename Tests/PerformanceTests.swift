import Foundation

// Vyhodnocení se ověřuje na vymyšleném snímku, ne na stavu stroje, aby výsledek
// nezávisel na tom, kolik má zrovna počítač volné paměti.
@main
enum PerformanceTests {
    static func snapshot(free: Int64 = 100_000_000_000, total: Int64 = 500_000_000_000,
                         swap: Int64 = 0, memory: Double = 0.5,
                         startup: Int = 5, uptime: TimeInterval = 3600) -> PerformanceSnapshot {
        PerformanceSnapshot(totalCapacity: total, freeCapacity: free, swapUsed: swap,
                            freeMemoryRatio: memory, startupItemCount: startup,
                            uptime: uptime, processes: [])
    }

    static func state(_ topic: PerformanceTopic, _ s: PerformanceSnapshot) -> PerformanceState {
        PerformanceReport.readings(for: s).first { $0.topic == topic }!.state
    }

    static func main() {
        let healthy = snapshot()
        precondition(PerformanceReport.needsAttention(PerformanceReport.readings(for: healthy)) == 0)
        precondition(PerformanceReport.readings(for: healthy).count == PerformanceTopic.allCases.count)

        // Volné místo: práh je desetina, ne pevný počet gigabajtů.
        precondition(state(.freeSpace, snapshot(free: 60_000_000_000, total: 500_000_000_000)) == .good)
        precondition(state(.freeSpace, snapshot(free: 40_000_000_000, total: 500_000_000_000)) == .attention)
        // Prázdný svazek nesmí skončit dělením nulou ani falešným poplachem.
        precondition(state(.freeSpace, snapshot(free: 0, total: 0)) == .good)

        precondition(state(.swap, snapshot(swap: 500_000_000)) == .good)
        precondition(state(.swap, snapshot(swap: 2_000_000_000)) == .attention)
        precondition(state(.freeMemory, snapshot(memory: 0.05)) == .attention)
        precondition(state(.freeMemory, snapshot(memory: 0.43)) == .good)
        precondition(state(.startupItems, snapshot(startup: 25)) == .attention)
        precondition(state(.uptime, snapshot(uptime: 9 * 86_400)) == .attention)
        precondition(state(.uptime, snapshot(uptime: 2 * 86_400)) == .good)

        // Obsazená paměť se nesmí hlásit jako závada: macOS ji drží schválně.
        let memoryReading = PerformanceReport.readings(for: snapshot(memory: 0.43))
            .first { $0.topic == .freeMemory }!
        precondition(memoryReading.detail.contains("není problém"))

        // Nabízet akci má smysl jen tam, kde Nimbo něco umí.
        precondition(PerformanceTopic.freeSpace.destination == .cleanup)
        precondition(PerformanceTopic.startupItems.destination == .startup)
        precondition(PerformanceTopic.freeMemory.destination == nil)
        precondition(PerformanceTopic.uptime.destination == nil)

        // Čtení procesů: parsování výstupu ps bez spouštění ps.
        let parsed = PerformanceProbe.topProcesses(limit: 3) { _, _ in
            "  501 121856  31.2 WindowServer\n 1234  89168  47.1 /Applications/Safari.app/Contents/MacOS/Safari\n"
        }
        precondition(parsed.count == 2)
        precondition(parsed[0] == ProcessUsage(pid: 501, name: "WindowServer",
                                               residentBytes: 121_856 * 1024, cpuPercent: 31.2))
        precondition(parsed[1].name.hasSuffix("Safari"))
        // Poškozený řádek se přeskočí, nespadne.
        precondition(PerformanceProbe.topProcesses { _, _ in "nesmysl\n\n42\n" }.isEmpty)
        precondition(PerformanceProbe.topProcesses { _, _ in nil }.isEmpty)

        print("PASS: thresholds on ratios not fixed sizes, empty volume safe, memory pressure not reported as a fault, ps parsing tolerant. Nothing measured on this machine.")
    }
}
