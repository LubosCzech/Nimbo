import Darwin
import Foundation

@main enum PermissionTests {
    @MainActor static func main() async throws {
        precondition(PermissionChecks.classifyDirectoryError(EPERM) == .denied)
        precondition(PermissionChecks.classifyDirectoryError(EACCES) == .denied)
        precondition(PermissionChecks.classifyDirectoryError(ENOENT) == .notApplicable)
        precondition(PermissionChecks.classifyDirectoryError(EIO) == .unknown)
        precondition(PermissionChecks.classifyDirectoryError(ENOTDIR) == .unknown)
        for (code, expected): (Int32, PermissionState) in [(0, .available), (-1743, .denied), (-1744, .notRequested), (-600, .unknown), (-1, .unknown)] {
            precondition(PermissionChecks.automationResult(code).state == expected)
        }
        func aggregate(_ states: [PermissionState]) -> PermissionState {
            PermissionChecks.aggregate(.cleanup, probes: states.map {
                PermissionProbe(path: "/fixture", state: $0, code: nil)
            }).state
        }
        precondition(aggregate([.available, .denied]) == .denied)
        precondition(aggregate([.available, .unknown]) == .unknown)
        precondition(aggregate([.available, .notApplicable]) == .available)
        precondition(aggregate([.notApplicable]) == .notApplicable)
        let optional = PermissionChecks.check(.development, home: URL(fileURLWithPath: "/fixture")) {
            PermissionProbe(path: $0.path, state: .notApplicable, code: ENOENT)
        }
        precondition(!optional.state.needsAttention)
        precondition(!optional.probes.contains { $0.path.contains("TCC") })

        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("nimbo-permissions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: fixture) }
        precondition(PermissionChecks.directory(fixture).state == .available)
        precondition(PermissionChecks.directory(fixture.appendingPathComponent("absent")).state == .notApplicable)

        var starts = 0
        let allowed = PermissionController(timeout: 1) { PermissionCheck(scope: $0, state: .available) }
        allowed.start { starts += 1 }
        while allowed.isChecking { try await Task.sleep(for: .milliseconds(5)) }
        precondition(starts == 1 && !allowed.showDetails && !allowed.needsAttention)
        allowed.start { starts += 1 }
        precondition(starts == 1)

        let denied = PermissionController(timeout: 1) {
            PermissionCheck(scope: $0, state: $0 == .cleanup ? .denied : .available)
        }
        denied.start { }
        while denied.isChecking { try await Task.sleep(for: .milliseconds(5)) }
        precondition(denied.showDetails && denied.attentionCount == 1)
        denied.showDetails = false
        denied.recheck()
        while denied.isChecking { try await Task.sleep(for: .milliseconds(5)) }
        precondition(!denied.showDetails, "Silent rechecks must not repeatedly interrupt the user")

        var timeoutCallbacks = 0
        let slow = PermissionController(timeout: 0.02) {
            Thread.sleep(forTimeInterval: 0.1) // Injected worker only; never blocks the UI.
            return PermissionCheck(scope: $0, state: .available)
        }
        slow.start { timeoutCallbacks += 1 }
        while slow.isChecking { try await Task.sleep(for: .milliseconds(5)) }
        precondition(slow.showDetails && slow.checks.allSatisfy { $0.state == .unknown })
        try await Task.sleep(for: .milliseconds(150))
        precondition(timeoutCallbacks == 1 && slow.checks.allSatisfy { $0.state == .unknown }, "Ignore late results from expired runs")
        print("PASS: permission classification, directory probes, startup warning, once-only scan, silent retry and timeout safety")
    }
}
