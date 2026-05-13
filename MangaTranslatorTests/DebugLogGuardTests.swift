import XCTest

// Guard that prevents production app code from using direct logging APIs.
// DebugLogger.swift is explicitly whitelisted since it wraps os.Logger internally.
final class DebugLogGuardTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private var productionSourceFiles: [URL] {
        let appDir = repoRoot.appendingPathComponent("MangaTranslator")
        guard let enumerator = FileManager.default.enumerator(
            at: appDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .filter { !isWhitelisted($0) }
    }

    private func isWhitelisted(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name == "DebugLogger.swift" || name == "DebugLogStore.swift"
    }

    func testNoBarePrintInProductionCode() throws {
        var violations: [String] = []
        for file in productionSourceFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let lines = contents.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                if trimmed.contains("print(") && !trimmed.contains("// allow-direct-print") {
                    violations.append("\(file.lastPathComponent):\(index + 1): bare print(")
                }
            }
        }
        XCTAssertTrue(violations.isEmpty,
            "Production app code must not use bare print(. Violations:\n" +
            violations.joined(separator: "\n"))
    }

    func testNoNSLogInProductionCode() throws {
        var violations: [String] = []
        for file in productionSourceFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let lines = contents.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                if trimmed.contains("NSLog(") {
                    violations.append("\(file.lastPathComponent):\(index + 1): NSLog(")
                }
            }
        }
        XCTAssertTrue(violations.isEmpty,
            "Production app code must not use NSLog(. Violations:\n" +
            violations.joined(separator: "\n"))
    }

    func testNoDirectLoggerConstructionInProductionCode() throws {
        var violations: [String] = []
        for file in productionSourceFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let lines = contents.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                if trimmed.contains("Logger(") && !trimmed.contains("// allow-direct-logger") {
                    violations.append("\(file.lastPathComponent):\(index + 1): direct Logger( construction")
                }
            }
        }
        XCTAssertTrue(violations.isEmpty,
            "Production app code must not construct Logger( directly. " +
            "Use DebugLogger.shared instead. Violations:\n" +
            violations.joined(separator: "\n"))
    }
}
