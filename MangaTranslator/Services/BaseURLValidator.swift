import Foundation

enum BaseURLValidatorError: LocalizedError {
    case empty
    case malformed
    case unsupportedScheme
    case httpNotAllowedForRemoteHost
    case queryNotAllowed
    case fragmentNotAllowed

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Base URL cannot be empty."
        case .malformed:
            return "Base URL is not a valid URL."
        case .unsupportedScheme:
            return "Base URL must use https (or http for localhost)."
        case .httpNotAllowedForRemoteHost:
            return "http is only allowed for local endpoints (localhost, 127.0.0.1, 0.0.0.0, ::1)."
        case .queryNotAllowed:
            return "Base URL must not contain a query string."
        case .fragmentNotAllowed:
            return "Base URL must not contain a fragment."
        }
    }
}

enum BaseURLValidator {
    private static let localHosts: Set<String> = ["localhost", "127.0.0.1", "0.0.0.0", "::1"]

    // Strips trailing slashes so `appendingPathComponent("chat/completions")`
    // on the validated URL never produces a double slash.
    static func sanitized(_ urlString: String) -> String {
        String(urlString.reversed().drop(while: { $0 == "/" }).reversed())
    }

    @discardableResult
    static func validate(_ urlString: String) throws -> URL {
        let trimmed = urlString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw BaseURLValidatorError.empty }

        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else {
            throw BaseURLValidatorError.malformed
        }

        guard url.query == nil else { throw BaseURLValidatorError.queryNotAllowed }
        guard url.fragment == nil else { throw BaseURLValidatorError.fragmentNotAllowed }

        switch url.scheme {
        case "https":
            return url
        case "http":
            guard localHosts.contains(host) else {
                throw BaseURLValidatorError.httpNotAllowedForRemoteHost
            }
            return url
        default:
            throw BaseURLValidatorError.unsupportedScheme
        }
    }
}
