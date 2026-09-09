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
