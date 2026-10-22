import Foundation
import RepositoryValidation

let arguments = Array(CommandLine.arguments.dropFirst())
let rootPath = arguments.first ?? FileManager.default.currentDirectoryPath
let result = RepositoryValidator.validate(root: URL(fileURLWithPath: rootPath, isDirectory: true))

guard result.violations.isEmpty else {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(result)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(1)
}
