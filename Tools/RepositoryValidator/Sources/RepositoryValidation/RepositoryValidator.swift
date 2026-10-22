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
    public static func appBuildSettings(root: URL) -> Result<[String: String], ValidationViolation> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = [
            "-project", root.appendingPathComponent("MangaTranslator.xcodeproj").path,
            "-target", "MangaTranslator",
            "-configuration", "Debug",
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
                    message: "Cannot read MangaTranslator build settings"
                ))
            }
            return .success(settings)
        } catch {
            return .failure(ValidationViolation(
                code: "project.build-settings",
                message: "Cannot run xcodebuild for MangaTranslator settings"
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
        return ValidationResult(violations: loggingViolations(in: root))
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
        return violations
    }

    public static func mlxOwnershipViolations(root: URL) -> [ValidationViolation] {
        let appSources = root.appendingPathComponent("MangaTranslator", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil) else {
            return [ValidationViolation(code: "project.mlx-import-boundary", message: "Cannot enumerate app sources")]
        }
        let forbidden = Set(["MLX", "MLXNN", "MLXFast", "MLXRandom", "Numerics", "PaddleOCRVL"])
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        for file in files {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let visitor = ImportVisitor(viewMode: .sourceAccurate)
            visitor.walk(Parser.parse(source: source))
            if !visitor.modules.isDisjoint(with: forbidden) {
                return [ValidationViolation(
                    code: "project.mlx-import-boundary",
                    message: "MLX implementation imports belong in MangaTranslatorMLX"
                )]
            }
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
