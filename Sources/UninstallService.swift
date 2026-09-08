import Foundation

struct UninstallFailure: Identifiable {
    let url: URL
    let message: String
    let permissionDenied: Bool
    var id: URL { url }
}

struct UninstallReport: Identifiable {
    let id = UUID()
    let appName: String
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
        var report = UninstallReport(appName: plan.app.name)
        for (index, url) in plan.selectedURLs.enumerated() {
            do {
                try trash(url)
                report.moved.append(url)
                if index == 0 { report.appRemoved = true }
            } catch {
                report.failures.append(UninstallFailure(url: url, message: error.localizedDescription,
                                                        permissionDenied: isPermissionError(error as NSError)))
                if index == 0 {
                    report.skipped = Array(plan.selectedURLs.dropFirst())
                    break
                }
            }
        }
        return report
    }

    static func isPermissionError(_ error: NSError, depth: Int = 0) -> Bool {
        if error.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(error.code) { return true }
        if error.domain == NSPOSIXErrorDomain && [1, 13].contains(error.code) { return true }
        if depth < 8, let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isPermissionError(underlying, depth: depth + 1)
        }
        return false
    }
}
