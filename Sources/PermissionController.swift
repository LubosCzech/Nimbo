import AppKit
import Combine
import Foundation

@MainActor
final class PermissionController: ObservableObject {
    @Published private(set) var checks: [PermissionCheck] = []
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked: Date?
    @Published var showDetails = false
    @Published private(set) var isRequestingAutomation = false
    @Published private(set) var requestMessage: String?

    private let probe: @Sendable (PermissionScope) -> PermissionCheck
    private let timeout: TimeInterval
    private var started = false
    private var runID: UUID?
    private var workers: Set<PermissionScope> = []
    private var pending: Set<PermissionScope> = []
    private var completion: (() -> Void)?
    private var announce = false

    var needsAttention: Bool { checks.contains { $0.state.needsAttention } }
    var attentionCount: Int { checks.filter { $0.state.needsAttention }.count }

    init(timeout: TimeInterval = 12,
         probe: @escaping @Sendable (PermissionScope) -> PermissionCheck = { PermissionChecks.check($0) }) {
        self.timeout = timeout
        self.probe = probe
    }

    func start(completion: @escaping () -> Void) {
        guard !started else { return }
        started = true
        recheck(announce: true, completion: completion)
    }

    func refreshAfterActivation() {
        guard started, !isChecking, !isRequestingAutomation,
              lastChecked.map({ Date().timeIntervalSince($0) > 5 }) ?? true else { return }
        recheck()
    }

    func recheck(announce: Bool = false, completion: (() -> Void)? = nil) {
        guard !isChecking else { return }
        self.announce = announce
        self.completion = completion
        isChecking = true
        let token = UUID()
        runID = token
        checks = PermissionScope.allCases.map { PermissionCheck(scope: $0, state: .checking) }
        pending = Set(PermissionScope.allCases)
        for scope in PermissionScope.allCases {
            // A blocked OS call must not produce an unbounded number of workers
            // when the user retries. The UI still times out and remains usable.
            guard !workers.contains(scope) else { continue }
            workers.insert(scope)
            let probe = self.probe
            Task {
                let result = await Task.detached(priority: .utility) { probe(scope) }.value
                workers.remove(scope)
                guard runID == token else { return }
                if let index = checks.firstIndex(where: { $0.scope == scope }) { checks[index] = result }
                pending.remove(scope)
                if pending.isEmpty { finish(token) }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(timeout))
            guard runID == token else { return }
            for scope in pending {
                if let index = checks.firstIndex(where: { $0.scope == scope }) {
                    checks[index] = PermissionCheck(scope: scope, state: .unknown,
                        note: "Kontrola překročila časový limit. Dokončete případný systémový dialog a zkuste ji znovu.")
                }
            }
            finish(token)
        }
    }

    private func finish(_ token: UUID) {
        guard runID == token else { return }
        runID = nil
        pending.removeAll()
        isChecking = false
        lastChecked = Date()
        if announce && needsAttention { showDetails = true }
        let callback = completion
        completion = nil
        callback?()
    }

    func requestAutomation() {
        guard !isRequestingAutomation, !isChecking else { return }
        isRequestingAutomation = true
        requestMessage = "Dokončete případný systémový dialog; okno Nimba můžete mezitím zavřít."
        Task {
            do {
                // The documented preflight requires a running target. Launch
                // System Events only after this explicit user action, not at boot.
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                _ = try await NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: "/System/Library/CoreServices/System Events.app"),
                    configuration: configuration)
                let result = await Task.detached(priority: .userInitiated) {
                    PermissionChecks.automation(askUser: true)
                }.value
                requestMessage = result.state == .available ? "Automatizace byla povolena." : result.note
            } catch {
                requestMessage = "System Events nelze spustit: \(error.localizedDescription)"
            }
            isRequestingAutomation = false
            recheck()
        }
    }
}
