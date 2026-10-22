import Foundation
import Testing
@testable import RepositoryValidation

struct RepositoryValidationTests {
    @Test("A MangaTranslator repository root passes foundation validation")
    func validRepositoryRootPasses() throws {
        let root = try makeFixture(withProject: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(RepositoryValidator.validate(root: root).violations.isEmpty)
    }

    @Test("A directory without the Xcode project fails foundation validation")
    func directoryWithoutProjectFails() throws {
        let root = try makeFixture(withProject: false)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(RepositoryValidator.validate(root: root).violations == [
            ValidationViolation(code: "repository.project.missing", message: "Missing MangaTranslator.xcodeproj")
        ])
    }

    @Test("Validation results encode stable machine-readable violations")
    func resultsEncodeAsJSON() throws {
        let result = ValidationResult(violations: [
            ValidationViolation(code: "repository.project.missing", message: "Missing MangaTranslator.xcodeproj")
        ])

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ValidationResult.self, from: data)

        #expect(decoded.violations == result.violations)
    }

    private func makeFixture(withProject: Bool) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepositoryValidationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if withProject {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("MangaTranslator.xcodeproj", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return root
    }
}
