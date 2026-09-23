import AppKit
import Foundation

// Run from the repository root on the supported macOS SDK/runtime.
// Verifies literal UI symbols without launching the app or touching user data.
@main enum DesignTests {
    static func main() throws {
        let expression = try NSRegularExpression(pattern: #"(?:systemName|systemImage|icon): "([a-zA-Z0-9.]+)""#)
        let files = try FileManager.default.contentsOfDirectory(atPath: "Sources").filter { $0.hasSuffix(".swift") }
        var checked = Set<String>()
        for symbol in SidebarSection.allCases.map(\.icon) + CleanupKind.allCases.map(\.icon) + DevelopmentCategory.allCases.map(\.icon) {
            precondition(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "Unavailable category symbol: \(symbol)")
            checked.insert(symbol)
        }
        // rawValue je identita, ne text. Zobrazit ho znamená ukázat uživateli
        // "cleanup" místo "Chytrý úklid" — a v cizím jazyce se to nepozná.
        for file in files {
            let source = try String(contentsOfFile: "Sources/\(file)", encoding: .utf8)
            for line in source.split(separator: "\n") where line.contains(".rawValue") {
                let text = String(line)
                let displays = ["Text(", "Label(", "title:", "text:", "label:", "subtitle:"]
                    .contains { text.contains($0) }
                precondition(!displays || text.contains("tag("),
                             "rawValue se zobrazuje uživateli v \(file): \(text.trimmingCharacters(in: .whitespaces))")
            }
        }

        for file in files {
            let source = try String(contentsOfFile: "Sources/\(file)", encoding: .utf8)
            for match in expression.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                let symbol = String(source[Range(match.range(at: 1), in: source)!])
                precondition(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil,
                             "Unavailable SF Symbol: \(symbol) in \(file)")
                checked.insert(symbol)
            }
        }
        print("PASS: \(checked.count) literal UI symbols are available on this macOS runtime.")
    }
}
