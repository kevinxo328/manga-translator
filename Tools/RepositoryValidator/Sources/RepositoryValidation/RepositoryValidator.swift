import Foundation
import SwiftParser
import SwiftSyntax

public struct ValidationViolation: Codable, Equatable, Error, Sendable {
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
    private static let mlxPackageProducts: Set<String> = ["MLX", "MLXNN", "MLXFast", "MLXRandom", "Numerics", "PaddleOCRVL"]
    private static let mlxForkURL = "https://github.com/kevinxo328/mlx-swift"
    private static let mlxForkRevision = "4b421e0137a901855882abfea9e2296101cfc9c1"

    public static func appBuildSettings(
        root: URL,
        configuration: String
    ) -> Result<[String: String], ValidationViolation> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = [
            "-project", root.appendingPathComponent("MangaTranslator.xcodeproj").path,
            "-target", "MangaTranslator",
            "-configuration", configuration,
            "-showBuildSettings", "-json"
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let objects = try JSONSerialization.jsonObject(with: output.fileHandleForReading.readDataToEndOfFile()) as? [[String: Any]],
                  let settings = objects.first?["buildSettings"] as? [String: String] else {
                return .failure(ValidationViolation(
                    code: "project.build-settings",
                    message: "Cannot read MangaTranslator \(configuration) build settings"
                ))
            }
            return .success(settings)
        } catch {
            return .failure(ValidationViolation(
                code: "project.build-settings",
                message: "Cannot run xcodebuild for MangaTranslator \(configuration) settings"
            ))
        }
    }

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
        return ValidationResult(violations: loggingViolations(in: root) + qualityWorkflowViolations(root: root))
    }

    public static func qualityWorkflowViolations(root: URL) -> [ValidationViolation] {
        let workflows = root.appendingPathComponent(".github/workflows", isDirectory: true)
        let quality = workflow(at: workflows.appendingPathComponent("quality.yml"))
        let diagnostics = workflow(at: workflows.appendingPathComponent("ocr-diagnostics.yml"))
        var violations: [ValidationViolation] = []

        guard let quality else {
            violations.append(ValidationViolation(
                code: "quality.pr-workflow",
                message: "Missing .github/workflows/quality.yml"
            ))
            return violations + missingDiagnosticsViolation()
        }
        if !workflowTriggers(quality, event: "pull_request") {
            violations.append(ValidationViolation(
                code: "quality.pr-trigger",
                message: "quality.yml must run on pull_request"
            ))
        }
        let qualityCommands = workflowCommands(quality)
        if !qualityCommands.contains(where: { $0.contains("-scheme MangaTranslator") }) ||
            !qualityCommands.contains(where: { $0.contains("repository-validator") }) {
            violations.append(ValidationViolation(
                code: "quality.pr-checks",
                message: "quality.yml must run MangaTranslator tests and repository-validator"
            ))
        }
        if qualityCommands.contains(where: { $0.contains("OCRBenchmark") || $0.contains("PaddleOCRParityDiagnostic") }) {
            violations.append(ValidationViolation(
                code: "quality.pr-fast-lane",
                message: "quality.yml must not run OCR diagnostic schemes"
            ))
        }

        guard let diagnostics else {
            return violations + missingDiagnosticsViolation()
        }
        if !workflowTriggers(diagnostics, event: "workflow_dispatch") || !workflowTriggers(diagnostics, event: "schedule") {
            violations.append(ValidationViolation(
                code: "quality.diagnostics-triggers",
                message: "ocr-diagnostics.yml must support manual and scheduled execution"
            ))
        }
        let diagnosticCommands = workflowCommands(diagnostics)
        if !diagnosticCommands.contains(where: { $0.contains("-scheme OCRBenchmark") }) ||
            diagnosticCommands.contains(where: { $0.contains("-scheme PaddleOCRParityDiagnostic") }) {
            violations.append(ValidationViolation(
                code: "quality.diagnostics-schemes",
                message: "ocr-diagnostics.yml must run OCRBenchmark without hosted PaddleOCR parity"
            ))
        }
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent("docs/quality-diagnostics.md").path) {
            violations.append(ValidationViolation(
                code: "quality.diagnostics-documentation",
                message: "Missing docs/quality-diagnostics.md"
            ))
        }
        return violations
    }

    public static func projectContractViolations(
        root: URL,
        appBuildSettings: [String: String]
    ) -> [ValidationViolation] {
        var violations: [ValidationViolation] = []
        if appBuildSettings["MACOSX_DEPLOYMENT_TARGET"] != "15.0" {
            violations.append(ValidationViolation(
                code: "project.deployment-target",
                message: "MangaTranslator must target macOS 15.0"
            ))
        }
        if appBuildSettings["INFOPLIST_FILE"] != "MangaTranslator/Info.plist" {
            violations.append(ValidationViolation(
                code: "project.info-plist",
                message: "MangaTranslator must use MangaTranslator/Info.plist"
            ))
        }
        if appBuildSettings["CODE_SIGN_ENTITLEMENTS"] != "MangaTranslator/MangaTranslator.entitlements" {
            violations.append(ValidationViolation(
                code: "project.entitlements",
                message: "MangaTranslator must use MangaTranslator/MangaTranslator.entitlements"
            ))
        }
        violations += sparkleViolations(in: root)
        violations += entitlementViolations(in: root)
        violations += mlxOwnershipViolations(root: root)
        violations += projectTargetOwnershipViolations(root: root)
        return violations
    }

    public static func projectTargetOwnershipViolations(root: URL) -> [ValidationViolation] {
        let project = root.appendingPathComponent("MangaTranslator.xcodeproj/project.pbxproj")
        guard let objects = projectObjects(at: project),
              let appTarget = nativeTarget(named: "MangaTranslator", in: objects),
              let mlxTarget = nativeTarget(named: "MangaTranslatorMLX", in: objects) else {
            return [ValidationViolation(
                code: "project.target-ownership",
                message: "Cannot read MangaTranslator target ownership"
            )]
        }

        let appProducts = packageProducts(for: appTarget, in: objects)
        guard appProducts.isDisjoint(with: mlxPackageProducts) else {
            return [ValidationViolation(
                code: "project.target-ownership",
                message: "MangaTranslator must not link MLX or PaddleOCRVL package products directly"
            )]
        }

        let mlxProducts = packageProducts(for: mlxTarget, in: objects)
        guard mlxPackageProducts.isSubset(of: mlxProducts) else {
            return [ValidationViolation(
                code: "project.target-ownership",
                message: "MangaTranslatorMLX must link all MLX and PaddleOCRVL package products"
            )]
        }
        let packageReferences = objects.values.filter { $0["isa"] as? String == "XCRemoteSwiftPackageReference" }
        guard packageReferences.contains(where: { reference in
            reference["repositoryURL"] as? String == mlxForkURL &&
                (reference["requirement"] as? [String: Any])?["revision"] as? String == mlxForkRevision
        }) else {
            return [ValidationViolation(
                code: "project.mlx-package-reference",
                message: "MLX must use the patched fork revision"
            )]
        }
        return []
    }

    public static func mlxOwnershipViolations(root: URL) -> [ValidationViolation] {
        let appSources = root.appendingPathComponent("MangaTranslator", isDirectory: true)
        guard let appImports = imports(in: appSources) else {
            return [ValidationViolation(code: "project.mlx-import-boundary", message: "Cannot enumerate app sources")]
        }
        guard appImports.isDisjoint(with: mlxPackageProducts) else {
            return [ValidationViolation(
                code: "project.mlx-import-boundary",
                message: "MLX implementation imports belong in MangaTranslatorMLX"
            )]
        }

        let mlxSources = root.appendingPathComponent("MangaTranslatorMLX", isDirectory: true)
        guard let mlxImports = imports(in: mlxSources),
              Set(["MLX", "PaddleOCRVL"]).isSubset(of: mlxImports) else {
            return [ValidationViolation(
                code: "project.mlx-implementation-boundary",
                message: "MangaTranslatorMLX must own the MLX and PaddleOCRVL imports"
            )]
        }
        return []
    }

    public static func releaseArtifactViolations(appBundle: URL) -> [ValidationViolation] {
        let metallib = appBundle.appendingPathComponent(
            "Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
        )
        guard FileManager.default.fileExists(atPath: metallib.path) else {
            return [ValidationViolation(
                code: "release.mlx-metallib",
                message: "Release app bundle is missing mlx-swift_Cmlx.bundle/default.metallib"
            )]
        }
        return []
    }

    private static func sparkleViolations(in root: URL) -> [ValidationViolation] {
        let url = root.appendingPathComponent("MangaTranslator/Info.plist")
        guard let plist = propertyList(at: url) else {
            return [ValidationViolation(code: "sparkle.info-plist", message: "Cannot read MangaTranslator/Info.plist")]
        }
        let requiredValues: [(String, Bool)] = [
            ("SUEnableInstallerLauncherService", true),
            ("SUEnableAutomaticChecks", true),
            ("SUAutomaticallyUpdate", false),
            ("SUAllowsAutomaticUpdates", false)
        ]
        return requiredValues.compactMap { key, expected in
            guard plist[key] as? Bool != expected else { return nil }
            return ValidationViolation(code: "sparkle.\(key)", message: "Info.plist must set \(key) to \(expected)")
        }
    }

    private static func entitlementViolations(in root: URL) -> [ValidationViolation] {
        let url = root.appendingPathComponent("MangaTranslator/MangaTranslator.entitlements")
        guard let plist = propertyList(at: url) else {
            return [ValidationViolation(code: "entitlements.file", message: "Cannot read MangaTranslator.entitlements")]
        }
        let expected = ["$(PRODUCT_BUNDLE_IDENTIFIER)-spks", "$(PRODUCT_BUNDLE_IDENTIFIER)-spki"]
        guard plist["com.apple.security.temporary-exception.mach-lookup.global-name"] as? [String] == expected else {
            return [ValidationViolation(code: "entitlements.sparkle-mach-lookup", message: "Sparkle mach lookup entitlements are missing")]
        }
        return []
    }

    private static func propertyList(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    }

    private static func missingDiagnosticsViolation() -> [ValidationViolation] {
        [ValidationViolation(
            code: "quality.diagnostics-workflow",
            message: "Missing .github/workflows/ocr-diagnostics.yml"
        )]
    }

    private static func workflow(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let workflow = object as? [String: Any] else {
            return nil
        }
        return workflow
    }

    private static func workflowTriggers(_ workflow: [String: Any], event: String) -> Bool {
        guard let triggers = workflow["on"] as? [String: Any] else { return false }
        return triggers[event] != nil
    }

    private static func workflowCommands(_ workflow: [String: Any]) -> [String] {
        guard let jobs = workflow["jobs"] as? [String: Any] else { return [] }
        return jobs.values.flatMap { job in
            guard let job = job as? [String: Any],
                  let steps = job["steps"] as? [[String: Any]] else { return [String]() }
            return steps.compactMap { $0["run"] as? String }
        }
    }

    private static func imports(in directory: URL) -> Set<String>? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        var modules: Set<String> = []
        for file in enumerator.compactMap({ $0 as? URL }).filter({ $0.pathExtension == "swift" }) {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else {
                return nil
            }
            let visitor = ImportVisitor(viewMode: .sourceAccurate)
            visitor.walk(Parser.parse(source: source))
            modules.formUnion(visitor.modules)
        }
        return modules
    }

    private static func projectObjects(at project: URL) -> [String: [String: Any]]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        process.arguments = ["-convert", "json", "-o", "-", project.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let project = try JSONSerialization.jsonObject(
                    with: output.fileHandleForReading.readDataToEndOfFile()
                  ) as? [String: Any],
                  let objects = project["objects"] as? [String: [String: Any]] else {
                return nil
            }
            return objects
        } catch {
            return nil
        }
    }

    private static func nativeTarget(named name: String, in objects: [String: [String: Any]]) -> [String: Any]? {
        objects.values.first { object in
            object["isa"] as? String == "PBXNativeTarget" && object["name"] as? String == name
        }
    }

    private static func packageProducts(for target: [String: Any], in objects: [String: [String: Any]]) -> Set<String> {
        let references = target["packageProductDependencies"] as? [String] ?? []
        return Set(references.compactMap { objects[$0]?["productName"] as? String })
    }

    private static func loggingViolations(in root: URL) -> [ValidationViolation] {
        let sourceDirectory = root.appendingPathComponent("MangaTranslator", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sourceDirectory.path) else {
            return [
                ValidationViolation(
                    code: "source.directory.unreadable",
                    message: "Cannot enumerate MangaTranslator source directory"
                )
            ]
        }
        guard let enumerator = FileManager.default.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [
                ValidationViolation(
                    code: "source.directory.unreadable",
                    message: "Cannot enumerate MangaTranslator source directory"
                )
            ]
        }

        let exemptPaths = Set(["Services/DebugLogger.swift", "Services/DebugLogStore.swift"]
            .map { sourceDirectory.appendingPathComponent($0).standardizedFileURL.path })
        let files = enumerator.compactMap { $0 as? URL }
            .filter {
                $0.pathExtension == "swift" &&
                !exemptPaths.contains($0.standardizedFileURL.path)
            }
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
        } else if let callee = node.calledExpression.as(MemberAccessExprSyntax.self) {
            calls.insert(callee.declName.baseName.text)
        }
        return .visitChildren
    }
}

private final class ImportVisitor: SyntaxVisitor {
    var modules: Set<String> = []

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        modules.insert(node.path.description.trimmingCharacters(in: .whitespacesAndNewlines))
        return .skipChildren
    }
}
