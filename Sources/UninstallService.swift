import Foundation

/// Uninstall failures share the classification used by the cleanup flow.
typealias UninstallFailure = RemovalFailure

struct UninstallReport: Identifiable {
    // Stable across a Finder retry, so updating the report does not dismiss
    // and re-present the sheet the user is looking at.
    var id = UUID()
    let appName: String
    let appURL: URL
    var appRemoved = false
    var moved: [URL] = []
    var failures: [UninstallFailure] = []
    var skipped: [URL] = []
}

enum UninstallService {
    static func run(_ plan: AppRemovalPlan,
                    trash: (URL) throws -> Void = { url in
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    }) -> UninstallReport {
        var report = UninstallReport(appName: plan.app.name, appURL: plan.app.url)
        for (index, url) in plan.selectedURLs.enumerated() {
            do {
                try trash(url)
                report.moved.append(url)
                if index == 0 { report.appRemoved = true }
            } catch {
                report.failures.append(RemovalFailure(url: url, error: error))
                if index == 0 {
                    report.skipped = Array(plan.selectedURLs.dropFirst())
                    break
                }
            }
        }
        return report
    }

    static func isPermissionError(_ error: NSError, depth: Int = 0) -> Bool {
        RemovalDiagnostics.isDenial(error, depth: depth)
    }

    /// Items worth handing to Finder: what Nimbo could not move because the
    /// item belongs to someone else, plus what it never attempted because the
    /// application itself was blocked.
    static func finderTargets(_ report: UninstallReport) -> [URL] {
        report.failures.map(\.url) + report.skipped
    }

    /// macOS 13+ refuses to let one application modify another until the user
    /// grants App Management. TCC blames the responsible process, so asking
    /// Finder to do it does not help either — the grant has to come first.
    /// There is no API to read the current status, so this reports what the
    /// blocked items are, not what TCC decided.
    static func mayNeedAppManagement(_ report: UninstallReport) -> Bool {
        report.failures.contains { $0.permissionDenied && $0.url.pathExtension == "app" }
    }

    static func canRetryViaFinder(_ report: UninstallReport) -> Bool {
        report.failures.contains { $0.obstacle == .ownership }
    }

    /// Folds Finder's result back into the report. Items Nimbo had already
    /// diagnosed keep that diagnosis when Finder fails too; items that were
    /// only skipped carry Finder's own words.
    static func applying(_ outcome: FinderTrashOutcome, to report: UninstallReport) -> UninstallReport {
        var updated = report
        let moved = Set(outcome.moved)
        let messages = Dictionary(outcome.failed.map { ($0.url, $0.message) },
                                  uniquingKeysWith: { first, _ in first })

        updated.moved += report.failures.map(\.url).filter(moved.contains)
        updated.moved += report.skipped.filter(moved.contains)
        if moved.contains(report.appURL) { updated.appRemoved = true }

        var failures: [RemovalFailure] = []
        for failure in report.failures where !moved.contains(failure.url) {
            // Keep the diagnosis, add what Finder said. Discarding Finder's
            // wording here would hide the reason the handoff did not work.
            guard let finderMessage = messages[failure.url] else {
                failures.append(failure)
                continue
            }
            failures.append(RemovalFailure(url: failure.url,
                                           message: failure.message + " · Finder: " + finderMessage,
                                           diagnosis: failure.diagnosis))
        }
        for url in report.skipped where !moved.contains(url) {
            failures.append(RemovalFailure(url: url,
                                           message: messages[url] ?? String(localized: "Finder položku nepřesunul.")))
        }
        updated.failures = failures
        updated.skipped = []
        return updated
    }
}
