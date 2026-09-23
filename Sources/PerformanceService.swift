import Darwin
import Foundation

/// Co Nimbo o výkonu měří. Vše jen pro čtení a bez práv správce.
struct ProcessUsage: Identifiable, Sendable, Equatable {
    let pid: Int32
    let name: String
    let residentBytes: Int64
    let cpuPercent: Double
    var id: Int32 { pid }
}

struct PerformanceSnapshot: Sendable, Equatable {
    var totalCapacity: Int64 = 0
    var freeCapacity: Int64 = 0
    var swapUsed: Int64 = 0
    var freeMemoryRatio: Double = 0
    var startupItemCount: Int = 0
    var uptime: TimeInterval = 0
    var processes: [ProcessUsage] = []
}

enum PerformanceState: Sendable { case good, attention }

enum PerformanceTopic: String, CaseIterable, Identifiable, Sendable {
    case freeSpace, swap, freeMemory, startupItems, uptime
    var id: String { rawValue }

    var title: String {
        switch self {
        case .freeSpace: return String(localized: "Volné místo")
        case .swap: return String(localized: "Odkládací soubor")
        case .freeMemory: return String(localized: "Volná paměť")
        case .startupItems: return String(localized: "Položky po spuštění")
        case .uptime: return String(localized: "Doba běhu")
        }
    }

    var icon: String {
        switch self {
        case .freeSpace: return "internaldrive"
        case .swap: return "arrow.left.arrow.right"
        case .freeMemory: return "memorychip"
        case .startupItems: return "power"
        case .uptime: return "clock.arrow.circlepath"
        }
    }

    /// Kam poslat uživatele, když má smysl něco udělat.
    var destination: SidebarSection? {
        switch self {
        case .freeSpace: return .cleanup
        case .startupItems: return .startup
        default: return nil
        }
    }
}

struct PerformanceReading: Identifiable, Sendable {
    let topic: PerformanceTopic
    let state: PerformanceState
    let value: String
    let detail: String
    var id: String { topic.rawValue }
}

/// Prahy na jednom místě, ať se nerozlezou po rozhraní.
enum PerformanceThresholds {
    /// Pod desetinu volného místa začne APFS svazovat swap i snapshoty.
    static let lowFreeSpaceRatio = 0.10
    /// Gigabajt odloženého znamená, že se paměť nevešla.
    static let highSwapUsed: Int64 = 1_073_741_824
    static let lowFreeMemoryRatio = 0.10
    static let manyStartupItems = 15
    static let longUptime: TimeInterval = 7 * 24 * 3600
}

enum PerformanceReport {
    static func readings(for s: PerformanceSnapshot) -> [PerformanceReading] {
        let freeRatio = s.totalCapacity > 0 ? Double(s.freeCapacity) / Double(s.totalCapacity) : 1
        let days = Int(s.uptime / 86_400)

        return [
            PerformanceReading(
                topic: .freeSpace,
                state: freeRatio < PerformanceThresholds.lowFreeSpaceRatio ? .attention : .good,
                value: "\(s.freeCapacity.fileSizeText) (\(Int((freeRatio * 100).rounded())) %)",
                detail: freeRatio < PerformanceThresholds.lowFreeSpaceRatio
                    ? String(localized: "Pod desetinou volného místa si macOS hůř poradí s odkládáním i snímky disku.")
                    : String(localized: "Místa je dost. Nízké volné místo je nejčastější skutečná příčina zpomalení.")),
            PerformanceReading(
                topic: .swap,
                state: s.swapUsed > PerformanceThresholds.highSwapUsed ? .attention : .good,
                value: s.swapUsed.fileSizeText,
                detail: s.swapUsed > PerformanceThresholds.highSwapUsed
                    ? String(localized: "Část paměti se odkládá na disk. Pomůže zavřít aplikace, které jí drží nejvíc.")
                    : String(localized: "Odkládá se málo, paměť stačí.")),
            PerformanceReading(
                topic: .freeMemory,
                state: s.freeMemoryRatio < PerformanceThresholds.lowFreeMemoryRatio ? .attention : .good,
                value: "\(Int((s.freeMemoryRatio * 100).rounded())) %",
                detail: String(localized: "Obsazená paměť sama o sobě není problém: macOS v ní drží data, aby je nemusel číst z disku.")),
            PerformanceReading(
                topic: .startupItems,
                state: s.startupItemCount > PerformanceThresholds.manyStartupItems ? .attention : .good,
                value: "\(s.startupItemCount)",
                detail: String(localized: "Co startuje s Macem, zpomaluje ho po celou dobu běhu. Tohle bývá největší rozdíl.")),
            PerformanceReading(
                topic: .uptime,
                state: s.uptime > PerformanceThresholds.longUptime ? .attention : .good,
                value: days == 0 ? "Méně než den" : String(localized: "\(days) dní"),
                detail: s.uptime > PerformanceThresholds.longUptime
                    ? String(localized: "Po delším běhu se vyplatí Mac restartovat.")
                    : String(localized: "Mac běží krátce."))
        ]
    }

    static func needsAttention(_ readings: [PerformanceReading]) -> Int {
        readings.filter { $0.state == .attention }.count
    }
}

enum PerformanceProbe {
    /// Měří se na vyžádání. Panel, který čte statistiky průběžně, by výkon
    /// sám ubíral — u sekce o výkonu obzvlášť nemístné.
    static func snapshot(startupItemCount: Int) -> PerformanceSnapshot {
        var s = PerformanceSnapshot()
        s.startupItemCount = startupItemCount

        let root = URL(fileURLWithPath: "/")
        if let values = try? root.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]) {
            s.totalCapacity = Int64(values.volumeTotalCapacity ?? 0)
            s.freeCapacity = values.volumeAvailableCapacityForImportantUsage ?? 0
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            s.swapUsed = Int64(swap.xsu_used)
        }

        var boot = timeval()
        var bootSize = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &boot, &bootSize, nil, 0) == 0, boot.tv_sec > 0 {
            s.uptime = Date().timeIntervalSince1970 - Double(boot.tv_sec)
        }

        s.freeMemoryRatio = freeMemoryRatio()
        s.processes = topProcesses()
        return s
    }

    private static func freeMemoryRatio() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        // Neaktivní stránky jsou volné v tom smyslu, že je systém kdykoli vezme.
        let available = Double(stats.free_count + stats.inactive_count + stats.purgeable_count)
        let total = available + Double(stats.active_count + stats.wire_count + stats.compressor_page_count)
        return total > 0 ? available / total : 0
    }

    static func topProcesses(limit: Int = 5, run: (String, [String]) -> String? = shell) -> [ProcessUsage] {
        guard let output = run("/bin/ps", ["-Aco", "pid=,rss=,pcpu=,comm=", "-m"]) else { return [] }
        return output.split(separator: "\n").prefix(limit).compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let rss = Int64(parts[1]),
                  let cpu = Double(parts[2]) else { return nil }
            return ProcessUsage(pid: pid, name: String(parts[3]).trimmingCharacters(in: .whitespaces),
                                residentBytes: rss * 1024, cpuPercent: cpu)
        }
    }

    private static func shell(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
