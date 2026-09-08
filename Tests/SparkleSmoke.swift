import Foundation
import CryptoKit

// Isolated smoke test: never touches the login Keychain or publishes an update.
func run(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else { throw NSError(domain: output, code: Int(process.terminationStatus)) }
    return output
}

func smokeTest() throws {
let fm = FileManager.default
let root = fm.currentDirectoryPath
let temporary = fm.temporaryDirectory.appendingPathComponent("nimbo-sparkle-test-\(UUID().uuidString)")
try fm.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
defer { try? fm.removeItem(at: temporary) }
let key = Curve25519.Signing.PrivateKey()
let keyPath = temporary.appendingPathComponent("ephemeral-key")
try key.rawRepresentation.base64EncodedString().write(to: keyPath, atomically: true, encoding: .utf8)
try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyPath.path)
let app = temporary.appendingPathComponent("Nimbo.app")
_ = try run("/usr/bin/ditto", [root + "/build/Nimbo.app", app.path])
let plistPath = app.appendingPathComponent("Contents/Info.plist")
var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistPath), format: nil) as! [String: Any]
plist["SUFeedURL"] = "https://example.invalid/appcast.xml"
plist["SUPublicEDKey"] = key.publicKey.rawRepresentation.base64EncodedString()
plist["SURequireSignedFeed"] = true
plist["SUVerifyUpdateBeforeExtraction"] = true
try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistPath)
_ = try run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
let archives = temporary.appendingPathComponent("archives")
try fm.createDirectory(at: archives, withIntermediateDirectories: false)
let archive = archives.appendingPathComponent("Nimbo-test.zip")
_ = try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, archive.path])
let bin = root + "/Vendor/Sparkle-2.9.6/bin/"
let prefix = "https://example.invalid/releases/"
_ = try run(bin + "generate_appcast", ["--ed-key-file", keyPath.path, "--download-url-prefix", prefix, "--maximum-deltas", "0", archives.path])
let feed = archives.appendingPathComponent("appcast.xml")
_ = try run(bin + "sign_update", ["--ed-key-file", keyPath.path, "--verify", feed.path])
let signature = try run("/usr/bin/python3", [root + "/scripts/validate-appcast.py", feed.path, archive.path,
                                          plist["CFBundleVersion"] as! String,
                                          plist["CFBundleShortVersionString"] as! String, prefix])
    .trimmingCharacters(in: .whitespacesAndNewlines)
_ = try run(bin + "sign_update", ["--ed-key-file", keyPath.path, "--verify", archive.path, signature])
print("PASS: appcast generation, signed feed verification, archive signature, version, URL and size")

// Corruption of the archive must fail cryptographic verification.
let handle = try FileHandle(forWritingTo: archive)
try handle.seekToEnd()
try handle.write(contentsOf: Data("corrupt".utf8))
try handle.close()
var rejected = false
do { _ = try run(bin + "sign_update", ["--ed-key-file", keyPath.path, "--verify", archive.path, signature]) }
catch { rejected = true }
precondition(rejected, "Tampered archive accepted")
print("PASS: tampered archive rejected")

var xml = try String(contentsOf: feed, encoding: .utf8)
xml = xml.replacingOccurrences(of: "Nimbo-test.zip", with: "Nimbo-evil.zip")
try xml.write(to: feed, atomically: true, encoding: .utf8)
rejected = false
do { _ = try run(bin + "sign_update", ["--ed-key-file", keyPath.path, "--verify", feed.path]) }
catch { rejected = true }
precondition(rejected, "Tampered feed accepted")
print("PASS: tampered feed rejected; no production keys created")
}

do { try smokeTest() }
catch {
    FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
    exit(1)
}
