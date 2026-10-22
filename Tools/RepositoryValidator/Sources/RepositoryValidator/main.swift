import Foundation
import RepositoryValidation

let arguments = Array(CommandLine.arguments.dropFirst())
let rootPath = arguments.first ?? FileManager.default.currentDirectoryPath
let root = URL(fileURLWithPath: rootPath, isDirectory: true)
var violations = RepositoryValidator.validate(root: root).violations
if violations.first?.code != "repository.project.missing" {
    switch RepositoryValidator.appBuildSettings(root: root) {
    case let .success(settings):
        violations += RepositoryValidator.projectContractViolations(root: root, appBuildSettings: settings)
    case let .failure(violation):
        violations.append(violation)
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
