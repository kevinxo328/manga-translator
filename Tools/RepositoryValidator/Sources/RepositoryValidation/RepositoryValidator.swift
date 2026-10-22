import Foundation
import SwiftParser
import SwiftSyntax

public struct ValidationViolation: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct ValidationResult: Codable, Sendable {
    public let violations: [ValidationViolation]

    public init(violations: [ValidationViolation]) {
        self.violations = violations
    }
}

public enum RepositoryValidator {
    public static func validate(root: URL) -> ValidationResult {
        let project = root.appendingPathComponent("MangaTranslator.xcodeproj", isDirectory: true)
        guard FileManager.default.fileExists(atPath: project.path) else {
            return ValidationResult(violations: [
                ValidationViolation(
                    code: "repository.project.missing",
                    message: "Missing MangaTranslator.xcodeproj"
                )
            ])
        }
        return ValidationResult(violations: loggingViolations(in: root))
    }

    private static func loggingViolations(in root: URL) -> [ValidationViolation] {
        let sourceDirectory = root.appendingPathComponent("MangaTranslator", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let exemptFiles: Set<String> = ["DebugLogger.swift", "DebugLogStore.swift"]
        let files = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && !exemptFiles.contains($0.lastPathComponent) }
            .sorted { $0.path < $1.path }

        var violations: [ValidationViolation] = []
        for file in files {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else {
                violations.append(
                    ValidationViolation(
                        code: "source.unreadable",
                        message: "Cannot read \(file.lastPathComponent) as UTF-8"
                    )
                )
                continue
            }
            for call in directLoggingCalls(in: source) {
                violations.append(
                ValidationViolation(
                    code: "logging.direct-\(call.lowercased())",
                    message: "\(file.lastPathComponent) directly calls \(call)"
                )
                )
            }
        }
        return violations
    }

    private static func directLoggingCalls(in source: String) -> [String] {
        let visitor = DirectLoggingCallVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: source))
        let calls = visitor.calls
        return ["print", "NSLog", "Logger"].filter(calls.contains)
    }
}

private final class DirectLoggingCallVisitor: SyntaxVisitor {
    var calls: Set<String> = []

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            calls.insert(callee.baseName.text)
        }
        return .visitChildren
    }
}
