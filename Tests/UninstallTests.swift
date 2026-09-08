import Foundation

@main
enum UninstallTests {
    static func main() {
        let app = InstalledApplication(url: URL(fileURLWithPath: "/fixture/Test.app"), name: "Test",
            bundleIdentifier: "test.fixture.app", version: "1", size: 10, modifiedAt: .distantPast)
        let related = RelatedFile(url: URL(fileURLWithPath: "/fixture/data"), size: 5)
        let plan = AppRemovalPlan(app: app, relatedFiles: [related])
        var calls: [URL] = []
        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        let blocked = UninstallService.run(plan) { url in calls.append(url); throw denied }
        precondition(calls == [app.url])
        precondition(!blocked.appRemoved && blocked.moved.isEmpty && blocked.skipped == [related.url])
        precondition(blocked.failures.first?.permissionDenied == true)
        let partial = UninstallService.run(plan) { url in if url == related.url { throw denied } }
        precondition(partial.appRemoved && partial.moved == [app.url] && partial.failures.count == 1)
        let success = UninstallService.run(plan) { _ in }
        precondition(success.appRemoved && success.moved == plan.selectedURLs && success.failures.isEmpty)
        let wrapped = NSError(domain: "wrapper", code: 42,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 13)])
        precondition(UninstallService.isPermissionError(wrapped))
        precondition(!UninstallService.isPermissionError(NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)))
        print("PASS: blocked app preserves data; partial success; complete success; permission classification. No files removed.")
    }
}
