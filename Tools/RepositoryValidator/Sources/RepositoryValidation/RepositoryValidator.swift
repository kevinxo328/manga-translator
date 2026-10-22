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

        return files.flatMap { file in
            guard let source = try? String(contentsOf: file, encoding: .utf8) else {
                return [ValidationViolation]()
            }
            return directLoggingCalls(in: source).map { call in
                ValidationViolation(
                    code: "logging.direct-\(call.lowercased())",
                    message: "\(file.lastPathComponent) directly calls \(call)"
                )
            }
        }
    }

    private static func directLoggingCalls(in source: String) -> [String] {
        let calls = Set(SwiftCallLexer.callIdentifiers(in: source))
        return ["print", "NSLog", "Logger"].filter(calls.contains)
    }
}

private enum SwiftCallLexer {
    static func callIdentifiers(in source: String) -> [String] {
        let characters = Array(source)
        var index = 0
        var identifiers: [String] = []

        while index < characters.count {
            if startsLineComment(characters, at: index) {
                index = skipLineComment(characters, from: index + 2)
            } else if startsBlockComment(characters, at: index) {
                index = skipBlockComment(characters, from: index + 2)
            } else if characters[index] == "\"" {
                index = skipString(characters, from: index + 1)
            } else if isIdentifierStart(characters[index]) {
                let start = index
                index += 1
                while index < characters.count && isIdentifierContinuation(characters[index]) {
                    index += 1
                }
                let identifier = String(characters[start..<index])
                var next = index
                while next < characters.count && characters[next].isWhitespace {
                    next += 1
                }
                if next < characters.count && characters[next] == "(" {
                    identifiers.append(identifier)
                }
            } else {
                index += 1
            }
        }
        return identifiers
    }

    private static func startsLineComment(_ characters: [Character], at index: Int) -> Bool {
        index + 1 < characters.count && characters[index] == "/" && characters[index + 1] == "/"
    }

    private static func startsBlockComment(_ characters: [Character], at index: Int) -> Bool {
        index + 1 < characters.count && characters[index] == "/" && characters[index + 1] == "*"
    }

    private static func skipLineComment(_ characters: [Character], from index: Int) -> Int {
        var index = index
        while index < characters.count && characters[index] != "\n" {
            index += 1
        }
        return index
    }

    private static func skipBlockComment(_ characters: [Character], from index: Int) -> Int {
        var index = index
        while index + 1 < characters.count {
            if characters[index] == "*" && characters[index + 1] == "/" {
                return index + 2
            }
            index += 1
        }
        return characters.count
    }

    private static func skipString(_ characters: [Character], from index: Int) -> Int {
        var index = index
        while index < characters.count {
            if characters[index] == "\\" {
                index += 2
            } else if characters[index] == "\"" {
                return index + 1
            } else {
                index += 1
            }
        }
        return characters.count
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private static func isIdentifierContinuation(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }
}
