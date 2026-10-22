import Foundation
import Testing
@testable import RepositoryValidation

struct RepositoryValidationTests {
    @Test("Project contracts require the macOS 15 app settings")
    func projectContractsRejectInvalidBuildSettings() throws {
        let root = try makeProjectContractFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let violations = RepositoryValidator.projectContractViolations(
            root: root,
            appBuildSettings: ["MACOSX_DEPLOYMENT_TARGET": "14.0"]
        )

        #expect(violations.map(\.code) == [
            "project.deployment-target",
            "project.info-plist",
            "project.entitlements",
            "sparkle.info-plist",
            "entitlements.file"
        ])
    }

    @Test("Project contracts accept configured release metadata")
    func projectContractsAcceptReleaseMetadata() throws {
        let root = try makeProjectContractFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try writePropertyList(
            [
                "SUEnableInstallerLauncherService": true,
                "SUEnableAutomaticChecks": true,
                "SUAutomaticallyUpdate": false,
                "SUAllowsAutomaticUpdates": false
            ],
            named: "MangaTranslator/Info.plist",
            at: root
        )
        try writePropertyList(
            [
                "com.apple.security.temporary-exception.mach-lookup.global-name": [
                    "$(PRODUCT_BUNDLE_IDENTIFIER)-spks",
                    "$(PRODUCT_BUNDLE_IDENTIFIER)-spki"
                ]
            ],
            named: "MangaTranslator/MangaTranslator.entitlements",
            at: root
        )

        #expect(RepositoryValidator.projectContractViolations(
            root: root,
            appBuildSettings: [
                "MACOSX_DEPLOYMENT_TARGET": "15.0",
                "INFOPLIST_FILE": "MangaTranslator/Info.plist",
                "CODE_SIGN_ENTITLEMENTS": "MangaTranslator/MangaTranslator.entitlements"
            ]
        ).isEmpty)
    }

    @Test("MLX implementation imports stay in the MLX target directory")
    func projectContractsRejectMLXImportsInAppSources() throws {
        let root = try makeProjectContractFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeSource("internal import MLX", named: "Feature.swift", at: root)

        #expect(RepositoryValidator.mlxOwnershipViolations(root: root).map(\.code) == [
            "project.mlx-import-boundary"
        ])
    }
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
        let result = try runCLI(root: repositoryRoot)

        #expect(result.status == 0)
        #expect(result.output.isEmpty)
    }

    @Test("The CLI fails with a logging violation")
    func commandLineFailsForDirectLogging() throws {
        let root = try makeFixture(withProject: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeSource("print(\"debug\")", named: "Feature.swift", at: root)

        let result = try runCLI(root: root)

        #expect(result.status != 0)
        let violations = try JSONDecoder().decode(ValidationResult.self, from: result.output).violations
        #expect(violations.map(\.code).contains("logging.direct-print"))
    }

    @Test("A missing production source directory fails closed")
    func missingSourceDirectoryFailsClosed() throws {
        let root = try makeFixture(withProject: true, withSourceDirectory: false)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(RepositoryValidator.validate(root: root).violations.map(\.code) == [
            "source.directory.unreadable"
        ])
    }

    @Test("Unreadable Swift source fails closed")
    func unreadableSourceFailsClosed() throws {
        let root = try makeFixture(withProject: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("MangaTranslator", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try Data([0xFF]).write(to: sourceDirectory.appendingPathComponent("Invalid.swift"))

        #expect(RepositoryValidator.validate(root: root).violations.map(\.code) == ["source.unreadable"])
    }

    @Test("Logging policy rejects executable direct logging but ignores comments and strings")
    func loggingPolicyFindsOnlyExecutableCalls() throws {
        let root = try makeFixture(withProject: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeSource(
            """
            let example = "print(\\\"not a call\\\")"
            let multiline = \"\"\"
            print("not a call")
            \"\"\"
            // NSLog("not a call")
            /* ignored logging example */
            print("debug")
            NSLog("debug")
            let logger = Logger(subsystem: "example", category: "example")
            """,
            named: "Feature.swift",
            at: root
        )
        let violations = RepositoryValidator.validate(root: root).violations

        #expect(violations.map(\.code) == [
            "logging.direct-print",
            "logging.direct-nslog",
            "logging.direct-logger"
        ])
    }

    @Test("Logging policy rejects qualified direct logging calls")
    func loggingPolicyFindsQualifiedCalls() throws {
        let root = try makeFixture(withProject: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeSource(
            """
            Swift.print("debug")
            Foundation.NSLog("debug")
            os.Logger(subsystem: "example", category: "example")
            """,
            named: "Qualified.swift",
            at: root
        )

        #expect(RepositoryValidator.validate(root: root).violations.map(\.code) == [
            "logging.direct-print",
            "logging.direct-nslog",
            "logging.direct-logger"
        ])
    }

    @Test("Only the explicit logging wrapper paths are exempt")
    func loggingPolicyDoesNotExemptSameNamedNestedFile() throws {
        let root = try makeFixture(withProject: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeSource("print(\"debug\")", named: "Nested/DebugLogger.swift", at: root)

        #expect(RepositoryValidator.validate(root: root).violations.map(\.code) == ["logging.direct-print"])
    }

    @Test("Explicit logging wrapper paths remain usable")
    func loggingPolicyExemptsOnlySupportedWrappers() throws {
        let root = try makeFixture(withProject: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeSource("print(\"debug\")", named: "Services/DebugLogger.swift", at: root)
        try writeSource("Logger(subsystem: \"example\", category: \"example\")", named: "Services/DebugLogStore.swift", at: root)

        #expect(RepositoryValidator.validate(root: root).violations.isEmpty)
    }

    private func makeFixture(withProject: Bool, withSourceDirectory: Bool = true) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepositoryValidationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if withProject {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("MangaTranslator.xcodeproj", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        if withSourceDirectory {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("MangaTranslator", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return root
    }

    private func makeProjectContractFixture() throws -> URL {
        let root = try makeFixture(withProject: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("MangaTranslatorMLX", isDirectory: true),
            withIntermediateDirectories: true
        )
        return root
    }

    private func writePropertyList(_ propertyList: [String: Any], named name: String, at root: URL) throws {
        let destination = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)
        try data.write(to: destination)
    }

    private func writeSource(_ source: String, named name: String, at root: URL) throws {
        let directory = root.appendingPathComponent("MangaTranslator", isDirectory: true)
        let destination = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try source.write(
            to: destination,
            atomically: true,
            encoding: .utf8
        )
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

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
