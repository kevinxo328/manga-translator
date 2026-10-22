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

    @Test("The CLI emits JSON and exits nonzero for an invalid repository")
    func commandLineFailsForMissingProject() throws {
        let root = try makeFixture(withProject: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try runCLI(root: root)

        #expect(result.status != 0)
        #expect(try JSONDecoder().decode(ValidationResult.self, from: result.output).violations == [
            ValidationViolation(code: "repository.project.missing", message: "Missing MangaTranslator.xcodeproj")
        ])
    }

    @Test("The CLI succeeds for a valid repository")
    func commandLineSucceedsForValidProject() throws {
        let root = try makeFixture(withProject: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try runCLI(root: root)

        #expect(result.status == 0)
        #expect(result.output.isEmpty)
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

    private func runCLI(root: URL) throws -> (status: Int32, output: Data) {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let process = Process()
        process.executableURL = packageRoot
            .appendingPathComponent(".build/out/Products/Debug/repository-validator")
        process.arguments = [root.path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, output.fileHandleForReading.readDataToEndOfFile())
    }
}
