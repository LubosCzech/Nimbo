import Darwin
import Foundation

/// Why macOS refused to remove an item. Every case needs a different remedy and
/// only `.ownership` is something administrator rights could ever fix: privacy
/// denials come from TCC, which root does not bypass, and protected items are
/// off limits at any privilege level.
enum RemovalObstacle: String, Sendable, CaseIterable {
    case none, privacy, ownership, systemProtected, undetermined

    var title: String {
        switch self {
        case .none: return ""
        case .privacy: return String(localized: "Chybí Úplný přístup k disku")
        case .ownership: return String(localized: "Položka patří jinému uživateli")
        case .systemProtected: return String(localized: "Položku chrání systém")
        case .undetermined: return String(localized: "macOS odepřel přístup")
        }
    }

    var advice: String {
        switch self {
        case .none: return ""
        case .privacy:
            return String(localized: "macOS blokuje přístup kvůli ochraně soukromí. Povolte Nimbo v Nastavení systému → Soukromí a zabezpečení → Úplný přístup k disku a spusťte Nimbo znovu. Oprávnění správce tuto ochranu neobchází.")
        case .ownership:
            return String(localized: "Položku vlastní jiný uživatel nebo root a Nimbo na ni nemá právo zápisu. Přesuňte ji do Koše ve Finderu; macOS si sám vyžádá ověření správce.")
        case .systemProtected:
            return String(localized: "Položka je chráněná integritou systému (SIP) nebo příznakem jen pro čtení. Odstranit ji nelze ani s oprávněním správce; použijte odinstalátor výrobce.")
        case .undetermined:
            return String(localized: "macOS odepřel přístup a důvod se nepodařilo jednoznačně určit. Technický detail u položky pomůže při hlášení chyby.")
        }
    }

    /// Only a privacy denial is fixed by granting Full Disk Access.
    var needsFullDiskAccess: Bool { self == .privacy }
}

/// The filesystem facts a diagnosis is built from. Kept separate from the
/// syscalls so classification stays testable without touching real files.
struct FileFacts: Sendable, Equatable {
    var uid: uid_t
    var gid: gid_t
    var mode: mode_t
    var flags: UInt32
    var isDirectory: Bool
}

/// Whether an item is still there. `fileExists` cannot express the middle
/// case: a denied `stat` looks exactly like a missing file, which would drop
/// the item from both the removed and the failed list.
enum ItemPresence: Sendable, Equatable {
    case present
    case absent            // Nothing to remove and nothing to report.
    case blocked(Int32)    // macOS refused to say; never silently skipped.
}

enum RemovalFlags {
    static let immutable: UInt32 = 0x0000_0002 | 0x0002_0000  // UF_IMMUTABLE | SF_IMMUTABLE
    static let noUnlink: UInt32 = 0x0000_0010 | 0x0010_0000   // UF_NOUNLINK | SF_NOUNLINK
    static let restricted: UInt32 = 0x0008_0000               // SF_RESTRICTED (SIP)
}

struct RemovalDiagnosis: Sendable, Equatable {
    var obstacle: RemovalObstacle = .none
    var posixCode: Int32? = nil
    var uid: uid_t?
    var gid: gid_t?
    var mode: mode_t?
    var flags: UInt32 = 0

    /// Technical one-liner for the details disclosure and bug reports.
    var detail: String {
        var parts: [String] = []
        if let posixCode { parts.append("errno \(posixCode) (\(String(cString: strerror(posixCode))))") }
        if let uid, let gid { parts.append(String(localized: "vlastník \(RemovalDiagnosis.userName(uid)):\(RemovalDiagnosis.groupName(gid))")) }
        if let mode { parts.append(String(localized: "práva \(String(format: "%03o", mode & 0o777))")) }
        let names = RemovalDiagnosis.flagNames(flags)
        if !names.isEmpty { parts.append(String(localized: "příznaky \(names.joined(separator: ", "))")) }
        return parts.joined(separator: " · ")
    }

    static func flagNames(_ flags: UInt32) -> [String] {
        var names: [String] = []
        if flags & RemovalFlags.restricted != 0 { names.append("restricted") }
        if flags & RemovalFlags.immutable != 0 { names.append("immutable") }
        if flags & RemovalFlags.noUnlink != 0 { names.append("nounlink") }
        return names
    }

    static func userName(_ uid: uid_t) -> String {
        guard let entry = getpwuid(uid), let name = entry.pointee.pw_name else { return String(uid) }
        return String(cString: name)
    }

    static func groupName(_ gid: gid_t) -> String {
        guard let entry = getgrgid(gid), let name = entry.pointee.gr_name else { return String(gid) }
        return String(cString: name)
    }
}

/// A removal that did not happen, with the reason classified.
struct RemovalFailure: Identifiable, Sendable {
    let url: URL
    let message: String
    let diagnosis: RemovalDiagnosis
    var id: URL { url }

    var obstacle: RemovalObstacle { diagnosis.obstacle }
    var permissionDenied: Bool { diagnosis.obstacle != .none }
    var reason: String { permissionDenied ? diagnosis.obstacle.title : message }
    var summary: String { "\(url.lastPathComponent): \(reason)" }

    init(url: URL, error: Error, environment: RemovalDiagnostics.Environment = .live) {
        self.url = url
        self.message = error.localizedDescription
        self.diagnosis = RemovalDiagnostics.classify(error, url: url, environment: environment)
    }

    /// For a refusal reported by another program in its own words. A diagnosis
    /// Nimbo already made is kept: Finder's wording is extra evidence, not a
    /// replacement for what the filesystem already told us.
    init(url: URL, message: String, diagnosis: RemovalDiagnosis = RemovalDiagnosis()) {
        self.url = url
        self.message = message
        self.diagnosis = diagnosis
    }

    /// For a refusal that surfaced as a bare errno instead of an `Error`.
    init(url: URL, posixCode: Int32, environment: RemovalDiagnostics.Environment = .live) {
        self.init(url: url, error: NSError(domain: NSPOSIXErrorDomain, code: Int(posixCode)),
                  environment: environment)
    }
}

extension Array where Element == RemovalFailure {
    /// The obstacle to explain when several items failed at once.
    var dominantObstacle: RemovalObstacle? {
        let blocked = filter(\.permissionDenied).map(\.obstacle)
        guard !blocked.isEmpty else { return nil }
        let counts = blocked.reduce(into: [RemovalObstacle: Int]()) { $0[$1, default: 0] += 1 }
        return counts.max { left, right in
            left.value == right.value ? left.key.rawValue > right.key.rawValue : left.value < right.value
        }?.key
    }

    /// Alert body: the first few items, then what the user can actually do.
    func alertText(limit: Int = 4) -> String {
        var lines = prefix(limit).map(\.summary)
        if count > limit { lines.append(String(localized: "… a další (\(count - limit))")) }
        var text = lines.joined(separator: "\n")
        if let dominantObstacle { text += "\n\n" + dominantObstacle.advice }
        return text
    }
}

enum RemovalDiagnostics {
    /// Filesystem access behind classification, injectable for tests.
    struct Environment: Sendable {
        var facts: @Sendable (URL) -> FileFacts?
        /// 0 when writing is allowed, otherwise the `access(2)` errno.
        var writeAccess: @Sendable (URL) -> Int32
        var presence: @Sendable (URL) -> ItemPresence

        static let live = Environment(facts: liveFacts, writeAccess: liveWriteAccess,
                                      presence: livePresence)
    }

    static func classify(_ error: Error, url: URL,
                         environment: Environment = .live) -> RemovalDiagnosis {
        let nsError = error as NSError
        let code = posixCode(from: nsError)
        guard isDenial(nsError) else { return RemovalDiagnosis(obstacle: .none, posixCode: code) }

        let item = environment.facts(url)
        var diagnosis = RemovalDiagnosis(obstacle: .undetermined, posixCode: code,
                                         uid: item?.uid, gid: item?.gid, mode: item?.mode,
                                         flags: item?.flags ?? 0)

        // SIP, locked and undeletable items: no privilege level removes these.
        let blocking = RemovalFlags.restricted | RemovalFlags.immutable | RemovalFlags.noUnlink
        if let item, item.flags & blocking != 0 {
            diagnosis.obstacle = .systemProtected
            return diagnosis
        }
        // A restricted parent protects its contents. Its nounlink flag does not:
        // /Applications carries SF_NOUNLINK yet admins may still remove entries.
        let parentURL = url.deletingLastPathComponent()
        let parent = environment.facts(parentURL)
        if let parent, parent.flags & RemovalFlags.restricted != 0 {
            diagnosis.obstacle = .systemProtected
            return diagnosis
        }

        // Unlinking needs write access on the parent directory; emptying a
        // directory needs write access on the directory itself.
        var probes = [environment.writeAccess(parentURL)]
        if item?.isDirectory == true { probes.append(environment.writeAccess(url)) }
        if probes.contains(EACCES) {
            diagnosis.obstacle = .ownership
            return diagnosis
        }
        if probes.contains(EPERM) {
            diagnosis.obstacle = .privacy
            return diagnosis
        }

        // POSIX permits the change, so the refusal comes from a layer above it.
        switch code {
        case .some(EACCES): diagnosis.obstacle = .ownership
        case .some(EPERM), .none: diagnosis.obstacle = .privacy
        default: diagnosis.obstacle = .undetermined
        }
        return diagnosis
    }

    /// Deepest POSIX errno in the error chain, if the chain carries one.
    static func posixCode(from error: NSError, depth: Int = 0) -> Int32? {
        if error.domain == NSPOSIXErrorDomain { return Int32(error.code) }
        if depth < 8, let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return posixCode(from: underlying, depth: depth + 1)
        }
        return nil
    }

    static func isDenial(_ error: NSError, depth: Int = 0) -> Bool {
        if error.domain == NSCocoaErrorDomain,
           [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(error.code) { return true }
        if error.domain == NSPOSIXErrorDomain, [Int(EPERM), Int(EACCES)].contains(error.code) { return true }
        if depth < 8, let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isDenial(underlying, depth: depth + 1)
        }
        return false
    }
}

/// `lstat` so a symlink is judged by itself, not by what it points at.
@Sendable private func liveFacts(_ url: URL) -> FileFacts? {
    var info = stat()
    guard url.withUnsafeFileSystemRepresentation({ path in
        path.map { lstat($0, &info) } ?? -1
    }) == 0 else { return nil }
    return FileFacts(uid: info.st_uid, gid: info.st_gid, mode: info.st_mode,
                     flags: info.st_flags, isDirectory: (info.st_mode & S_IFMT) == S_IFDIR)
}

/// `lstat` rather than `fileExists`, so a broken symlink is still removable and
/// a denied lookup is reported instead of being mistaken for a missing file.
@Sendable private func livePresence(_ url: URL) -> ItemPresence {
    var info = stat()
    let result = url.withUnsafeFileSystemRepresentation { path in
        path.map { lstat($0, &info) } ?? -1
    }
    if result == 0 { return .present }
    let code = errno
    return code == ENOENT || code == ENOTDIR ? .absent : .blocked(code)
}

@Sendable private func liveWriteAccess(_ url: URL) -> Int32 {
    let result = url.withUnsafeFileSystemRepresentation { path in
        path.map { access($0, W_OK) } ?? -1
    }
    return result == 0 ? 0 : errno
}
