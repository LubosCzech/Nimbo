import Darwin
import Foundation

// Classification is driven by injected filesystem facts, so the suite never
// touches real files and never needs elevated rights.
@main
enum RemovalDiagnosticsTests {
    static func facts(uid: uid_t = 501, gid: gid_t = 20, mode: mode_t = 0o755,
                      flags: UInt32 = 0, isDirectory: Bool = false) -> FileFacts {
        FileFacts(uid: uid, gid: gid, mode: mode, flags: flags, isDirectory: isDirectory)
    }

    static func environment(item: FileFacts?, parent: FileFacts?,
                            access: [String: Int32] = [:],
                            presence: ItemPresence = .present) -> RemovalDiagnostics.Environment {
        let itemPath = "/fixture/parent/item"
        return RemovalDiagnostics.Environment(
            facts: { url in url.path == itemPath ? item : parent },
            writeAccess: { url in access[url.path] ?? 0 },
            presence: { _ in presence })
    }

    static let item = URL(fileURLWithPath: "/fixture/parent/item")
    static let parentPath = "/fixture/parent"
    static let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
    static func posix(_ code: Int32) -> NSError {
        NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(code))])
    }

    static func classify(_ error: NSError, item itemFacts: FileFacts?, parent: FileFacts?,
                         access: [String: Int32] = [:]) -> RemovalDiagnosis {
        RemovalDiagnostics.classify(error, url: item,
                                    environment: environment(item: itemFacts, parent: parent, access: access))
    }

    static func main() {
        // A missing file is not a permission problem and must not be reported as one.
        let absent = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        precondition(classify(absent, item: nil, parent: facts()).obstacle == .none)

        // POSIX refuses the parent directory: administrator rights would help.
        precondition(classify(denied, item: facts(), parent: facts(uid: 0, mode: 0o755),
                              access: [parentPath: EACCES]).obstacle == .ownership)

        // POSIX allows the write, so the refusal came from TCC above it.
        precondition(classify(posix(EPERM), item: facts(), parent: facts()).obstacle == .privacy)
        precondition(classify(denied, item: facts(), parent: facts()).obstacle == .privacy)
        // access(2) itself blocked by TCC is a privacy denial, not ownership.
        precondition(classify(denied, item: facts(), parent: facts(),
                              access: [parentPath: EPERM]).obstacle == .privacy)

        // errno decides when POSIX has no objection of its own.
        precondition(classify(posix(EACCES), item: facts(), parent: facts()).obstacle == .ownership)

        // SIP and lock flags win over everything: no privilege level removes these.
        for flag in [RemovalFlags.restricted, 0x0000_0002 as UInt32, 0x0010_0000 as UInt32] {
            precondition(classify(denied, item: facts(flags: flag), parent: facts()).obstacle == .systemProtected)
        }
        precondition(classify(denied, item: facts(),
                              parent: facts(flags: RemovalFlags.restricted)).obstacle == .systemProtected)

        // /Applications carries SF_NOUNLINK yet admins may still remove entries,
        // so a nounlink parent must never be reported as system protected.
        precondition(classify(denied, item: facts(), parent: facts(flags: 0x0010_0000),
                              access: [parentPath: EACCES]).obstacle == .ownership)

        // Emptying a directory also needs write access on the directory itself.
        precondition(classify(denied, item: facts(isDirectory: true), parent: facts(),
                              access: [item.path: EACCES]).obstacle == .ownership)
        precondition(classify(denied, item: facts(isDirectory: false), parent: facts(),
                              access: [item.path: EACCES]).obstacle == .privacy)

        // Error chains are walked for the deepest errno.
        precondition(RemovalDiagnostics.posixCode(from: posix(EACCES)) == EACCES)
        precondition(RemovalDiagnostics.posixCode(from: denied) == nil)
        precondition(RemovalDiagnostics.isDenial(posix(EACCES)))
        precondition(!RemovalDiagnostics.isDenial(absent))

        // Only a privacy denial points at Full Disk Access.
        precondition(RemovalObstacle.privacy.needsFullDiskAccess)
        precondition(!RemovalObstacle.ownership.needsFullDiskAccess)
        precondition(!RemovalObstacle.systemProtected.needsFullDiskAccess)

        let diagnosis = classify(posix(EACCES), item: facts(uid: 0, gid: 0, mode: 0o644, flags: RemovalFlags.restricted),
                                 parent: facts())
        precondition(diagnosis.detail.contains("errno 13"))
        precondition(diagnosis.detail.contains("práva 644"))
        precondition(diagnosis.detail.contains("restricted"))

        // Aggregation picks the obstacle that explains most of the batch.
        let blocked = RemovalFailure(url: item, error: denied,
                                     environment: environment(item: facts(), parent: facts(),
                                                              access: [parentPath: EACCES]))
        let priv = RemovalFailure(url: item, error: denied,
                                  environment: environment(item: facts(), parent: facts()))
        let clean = RemovalFailure(url: item, error: absent,
                                   environment: environment(item: facts(), parent: facts()))
        precondition(blocked.permissionDenied && !clean.permissionDenied)
        precondition([blocked, priv, priv].dominantObstacle == .privacy)
        precondition([blocked].dominantObstacle == .ownership)
        precondition([clean].dominantObstacle == nil)
        precondition([RemovalFailure]().alertText().isEmpty)
        let text = [blocked, priv, priv].alertText(limit: 2)
        precondition(text.contains("… a další (1)"))
        precondition(text.contains(RemovalObstacle.privacy.advice))
        precondition(clean.reason == clean.message)

        // A denied lookup must never be mistaken for an already-removed item.
        // The operation must not run, and the item must still be reported.
        var attempted: [URL] = []
        let blockedLookup = FileScanner.remove(
            [item], environment: environment(item: facts(), parent: facts(), presence: .blocked(EPERM))
        ) { url in attempted.append(url) }
        precondition(attempted.isEmpty)
        precondition(blockedLookup.count == 1 && blockedLookup[0].permissionDenied)
        precondition(blockedLookup[0].diagnosis.posixCode == EPERM)

        // Genuinely missing items stay silent: nothing to remove, nothing to report.
        let gone = FileScanner.remove(
            [item], environment: environment(item: nil, parent: facts(), presence: .absent)
        ) { url in attempted.append(url) }
        precondition(gone.isEmpty && attempted.isEmpty)

        // Present items run the operation and report only what it throws.
        let present = environment(item: facts(), parent: facts(), presence: .present)
        precondition(FileScanner.remove([item], environment: present) { url in attempted.append(url) }.isEmpty)
        precondition(attempted == [item])
        let thrown = FileScanner.remove([item], environment: present) { _ in throw denied }
        precondition(thrown.count == 1 && thrown[0].obstacle == .privacy)

        // Nimbo must not offer its own data as someone else's leftover. The
        // bundle identifier changed in 1.6.1, so the former one counts too.
        precondition(NimboIdentity.all.contains(NimboIdentity.legacyBundleIdentifier))
        precondition(FileScanner.isRelated(NimboIdentity.legacyBundleIdentifier, toAny: NimboIdentity.all))
        precondition(FileScanner.isRelated("local.nimbo.app.helper", toAny: NimboIdentity.all))
        precondition(!FileScanner.isRelated("com.google.Keystone", toAny: NimboIdentity.all))

        print("PASS: privacy/ownership/SIP classification, nounlink parent, directory access, aggregation, denied lookup reported not skipped, own data not offered as a leftover. No files touched.")
    }
}
