import Foundation

struct FinderTrashFailure: Sendable {
    let url: URL
    let message: String
}

struct FinderTrashOutcome: Sendable {
    var moved: [URL] = []
    var failed: [FinderTrashFailure] = []
}

/// Hands a removal to Finder instead of elevating Nimbo.
///
/// A root-owned bundle cannot be renamed by its owner-less user, so `trashItem`
/// fails with EACCES. Finder has the authenticated move macOS reserves for it:
/// it asks for administrator credentials itself and performs the move with its
/// own privileged helper. Nimbo therefore never runs anything as root, ships no
/// privileged helper and never learns the password — the whole elevation stays
/// inside macOS. Paths travel as process arguments, never interpolated into the
/// script, so no path can alter what the script does.
enum FinderTrashService {
    // The user may have to read the dialog and type a password, so this waits
    // far longer than an ordinary scripted call would.
    static let timeout: TimeInterval = 300

    private static let script = """
    function run(argv) {
        const finder = Application('Finder');
        const moved = [];
        const failed = [];
        argv.forEach(path => {
            try {
                finder.delete(Path(path));
                moved.push(path);
            } catch (error) {
                failed.push({ path: path, message: String((error && error.message) || error) });
            }
        });
        return JSON.stringify({ moved: moved, failed: failed });
    }
    """

    static func moveToTrash(_ urls: [URL],
                            run: (String, [String]) throws -> String = runOsascript) throws -> FinderTrashOutcome {
        guard !urls.isEmpty else { return FinderTrashOutcome() }
        let output = try run("/usr/bin/osascript", ["-l", "JavaScript", "-e", script] + urls.map(\.path))
        return try parse(output, requested: urls)
    }

    /// Finder answers with paths; they are matched back to the requested URLs so
    /// an unexpected answer can never introduce a path Nimbo did not ask about.
    static func parse(_ output: String, requested: [URL]) throws -> FinderTrashOutcome {
        struct Response: Decodable {
            struct Item: Decodable { let path: String; let message: String }
            let moved: [String]
            let failed: [Item]
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw NSError(domain: "Nimbo.FinderTrash", code: 1, userInfo: [
                NSLocalizedDescriptionKey: trimmed.isEmpty
                    ? String(localized: "Finder neodpověděl. Zkuste to znovu, nebo položku přesuňte ručně.")
                    : trimmed
            ])
        }
        let byPath = Dictionary(requested.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var outcome = FinderTrashOutcome()
        outcome.moved = response.moved.compactMap { byPath[$0] }
        outcome.failed = response.failed.compactMap { item in
            byPath[item.path].map { FinderTrashFailure(url: $0, message: item.message) }
        }
        let answered = Set(outcome.moved + outcome.failed.map(\.url))
        // Anything Finder did not mention stays a failure: silence is not success.
        outcome.failed += requested.filter { !answered.contains($0) }.map {
            FinderTrashFailure(url: $0, message: String(localized: "Finder k této položce nic nevrátil."))
        }
        return outcome
    }

    static func runOsascript(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer { deadline.cancel() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "Nimbo.FinderTrash", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: text.contains("-1743")
                    ? String(localized: "macOS odepřel automatizaci Finderu. Povolte Nimbo → Finder v Nastavení systému → Soukromí a zabezpečení → Automatizace.")
                    : (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Finder operaci nedokončil." : text)
            ])
        }
        return text
    }
}
