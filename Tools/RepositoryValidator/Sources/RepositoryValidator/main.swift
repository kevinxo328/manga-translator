import Foundation
import RepositoryValidation

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--release-app", let appPath = arguments.dropFirst().first {
    let result = ValidationResult(violations: RepositoryValidator.releaseArtifactViolations(
        appBundle: URL(fileURLWithPath: appPath, isDirectory: true)
    ))
    guard result.violations.isEmpty else {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(result))
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(1)
    }
    exit(0)
}
let rootPath = arguments.first ?? FileManager.default.currentDirectoryPath
let root = URL(fileURLWithPath: rootPath, isDirectory: true)
var violations = RepositoryValidator.validate(root: root).violations
if violations.first?.code != "repository.project.missing" {
    for configuration in ["Debug", "Release"] {
        switch RepositoryValidator.appBuildSettings(root: root, configuration: configuration) {
        case let .success(settings):
            violations += RepositoryValidator.projectContractViolations(root: root, appBuildSettings: settings)
        case let .failure(violation):
            violations.append(violation)
        }
    }
}
let result = ValidationResult(violations: violations)

guard result.violations.isEmpty else {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(result)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(1)
}
