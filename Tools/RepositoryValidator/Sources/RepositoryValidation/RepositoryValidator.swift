import Foundation

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
        return ValidationResult(violations: [])
    }
}
