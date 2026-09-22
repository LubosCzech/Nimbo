import Darwin
import Foundation

// Finder is never contacted: the osascript runner is injected. No file is
// touched and no Apple Event is sent.
@main
enum FinderTrashTests {
    static let app = URL(fileURLWithPath: "/fixture/Applications/Test.app")
    static let leftover = URL(fileURLWithPath: "/fixture/Library/Preferences/test.plist")
    static let other = URL(fileURLWithPath: "/fixture/Library/Caches/test")

    static func ownershipEnvironment(_ url: URL) -> RemovalDiagnostics.Environment {
        let parent = url.deletingLastPathComponent().path
        return RemovalDiagnostics.Environment(
            facts: { _ in FileFacts(uid: 0, gid: 0, mode: 0o755, flags: 0, isDirectory: true) },
            writeAccess: { probe in probe.path == parent ? EACCES : 0 },
            presence: { _ in .present })
    }

    static func blockedReport() -> UninstallReport {
        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        var report = UninstallReport(appName: "Test", appURL: app)
        report.failures = [RemovalFailure(url: app, error: denied, environment: ownershipEnvironment(app))]
        report.skipped = [leftover, other]
        return report
    }

    static func main() throws {
        let report = blockedReport()
        precondition(report.failures[0].obstacle == .ownership)
        precondition(UninstallService.canRetryViaFinder(report))
        precondition(UninstallService.finderTargets(report) == [app, leftover, other])

        // A report blocked only by privacy or SIP must not offer Finder.
        var privacyReport = UninstallReport(appName: "Test", appURL: app)
        privacyReport.failures = [RemovalFailure(url: app, error: NSError(domain: NSCocoaErrorDomain,
            code: NSFileWriteNoPermissionError))]
        precondition(privacyReport.failures[0].obstacle != .ownership)
        precondition(!UninstallService.canRetryViaFinder(privacyReport))

        // Paths travel as arguments, never inside the script text.
        var captured: [String] = []
        let outcome = try FinderTrashService.moveToTrash([app, leftover]) { executable, arguments in
            captured = arguments
            precondition(executable == "/usr/bin/osascript")
            return #"{"moved":["\#(app.path)"],"failed":[{"path":"\#(leftover.path)","message":"Finder odmítl"}]}"#
        }
        precondition(captured.prefix(3) == ["-l", "JavaScript", "-e"])
        precondition(Array(captured.dropFirst(4)) == [app.path, leftover.path])
        precondition(!captured[3].contains(app.path))
        precondition(outcome.moved == [app])
        precondition(outcome.failed.count == 1 && outcome.failed[0].url == leftover)
        precondition(outcome.failed[0].message == "Finder odmítl")

        // No items means no subprocess at all.
        var ran = false
        _ = try FinderTrashService.moveToTrash([]) { _, _ in ran = true; return "" }
        precondition(!ran)

        // A path Nimbo never asked about is ignored rather than acted on.
        let foreign = try FinderTrashService.parse(
            #"{"moved":["/etc/passwd"],"failed":[]}"#, requested: [app])
        precondition(foreign.moved.isEmpty)
        precondition(foreign.failed.count == 1 && foreign.failed[0].url == app)

        // Silence is not success: an unmentioned item stays a failure.
        let partial = try FinderTrashService.parse(#"{"moved":[],"failed":[]}"#, requested: [app, leftover])
        precondition(partial.moved.isEmpty && partial.failed.count == 2)

        // Unparseable output is an error, never an assumed success.
        var threw = false
        do { _ = try FinderTrashService.parse("Finder got an error: -1743", requested: [app]) }
        catch { threw = true }
        precondition(threw)

        // Folding Finder's result back into the report.
        let merged = UninstallService.applying(
            FinderTrashOutcome(moved: [app, leftover],
                               failed: [FinderTrashFailure(url: other, message: "Položka se používá")]),
            to: report)
        precondition(merged.id == report.id)  // same sheet, not a new one
        precondition(merged.appRemoved)
        precondition(merged.moved == [app, leftover])
        precondition(merged.skipped.isEmpty)
        precondition(merged.failures.count == 1 && merged.failures[0].url == other)
        precondition(merged.failures[0].message == "Položka se používá")
        precondition(!merged.failures[0].permissionDenied)

        // When Finder cannot move the application either, the original
        // diagnosis is kept rather than replaced by Finder's wording.
        let stillBlocked = UninstallService.applying(
            FinderTrashOutcome(moved: [], failed: [FinderTrashFailure(url: app, message: "Zrušeno")]),
            to: report)
        precondition(!stillBlocked.appRemoved)
        precondition(stillBlocked.failures.first?.obstacle == .ownership)
        precondition(stillBlocked.failures.count == 3)
        // Finder's wording is added as evidence, the diagnosis is not replaced.
        precondition(stillBlocked.failures[0].message.contains("Zrušeno"))
        precondition(stillBlocked.failures[0].reason == RemovalObstacle.ownership.title)

        // An application bundle points at App Management; a plain file does not.
        precondition(UninstallService.mayNeedAppManagement(report))
        var plistOnly = UninstallReport(appName: "Test", appURL: app)
        plistOnly.failures = [RemovalFailure(url: leftover,
            error: NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError),
            environment: ownershipEnvironment(leftover))]
        precondition(!UninstallService.mayNeedAppManagement(plistOnly))
        // A non-permission failure on a bundle is not an App Management case.
        var missing = UninstallReport(appName: "Test", appURL: app)
        missing.failures = [RemovalFailure(url: app, message: "Položka se používá")]
        precondition(!UninstallService.mayNeedAppManagement(missing))

        print("PASS: Finder handoff — argument passing, foreign paths ignored, silence is failure, report merge keeps diagnosis. No Apple Event sent, no files touched.")
    }
}
