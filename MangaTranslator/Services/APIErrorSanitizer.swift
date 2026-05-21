import Foundation

// MARK: - SanitizedAPIError

/// Structured, UI-safe representation of a translation provider non-2xx HTTP response.
/// Construction goes through ``APIErrorSanitizer`` so the raw response body cannot be
/// reintroduced through this type. All fields are already redacted and length-bounded.
struct SanitizedAPIError: Equatable, Sendable {
    /// Display name of the translation provider (e.g. "OpenAI Compatible", "DeepL").
    let provider: String
    /// HTTP status code reported by the provider.
    let statusCode: Int
    /// Provider-supplied machine-readable code, when one could be parsed safely.
    let code: String?
    /// Provider-supplied error message after redaction and 200-char truncation.
    let message: String?

    /// UI-facing description following the contract:
    /// - `<Provider> request failed with HTTP <status> (<code>): <message>`
    /// - `<Provider> request failed with HTTP <status>: <message>`
    /// - `<Provider> request failed with HTTP <status>`
    var localizedSummary: String {
        let prefix = "\(provider) request failed with HTTP \(statusCode)"
        if let code = code, !code.isEmpty, let message = message, !message.isEmpty {
            return "\(prefix) (\(code)): \(message)"
        }
        if let message = message, !message.isEmpty {
            return "\(prefix): \(message)"
        }
        return prefix
    }
}

// MARK: - APIErrorSanitizer

enum APIErrorSanitizer {
    /// Per-provider parsing rules. The display name carried in
    /// ``SanitizedAPIError.provider`` is supplied separately so call sites can
    /// keep using `TranslationEngine.displayName`.
    enum Provider {
        case openAI
        case copilot
        case google
        case deepL
        case generic
    }

    /// Maximum length of the sanitized provider message after redaction.
    static let maxMessageLength = 200

    /// Builds a sanitized provider API error from a non-2xx HTTP response.
    /// Parsing failures never throw — the worst case still yields a structured
    /// error carrying provider + status only.
    static func sanitize(
        provider: Provider,
        providerDisplayName: String,
        statusCode: Int,
        responseData: Data
    ) -> SanitizedAPIError {
        let parsed = parse(provider: provider, responseData: responseData)
        let safeMessage = parsed.rawMessage.flatMap { redact($0) }
        let safeCode = parsed.code.flatMap { sanitizeCode($0) }
        return SanitizedAPIError(
            provider: providerDisplayName,
            statusCode: statusCode,
            code: safeCode,
            message: safeMessage
        )
    }

    /// Public for testing: applies the redaction patterns and 200-char bound
    /// to an already-extracted provider message. Returns nil if nothing useful
    /// remains after redaction.
    static func redact(_ raw: String) -> String? {
        var s = raw

        // Normalize whitespace and control characters first so regex patterns
        // operating on `\S+` don't accidentally span line breaks.
        s = s.replacingOccurrences(of: "\r\n", with: " ")
        s = s.replacingOccurrences(of: "\n", with: " ")
        s = s.replacingOccurrences(of: "\r", with: " ")
        s = s.replacingOccurrences(of: "\t", with: " ")

        // 1. Authorization header values: "Authorization: Bearer xxx",
        //    "authorization: DeepL-Auth-Key xxx", "Authorization=xxx".
        //    Match the header name, optional whitespace, ':' or '=',
        //    then up to two whitespace-separated tokens (scheme + value).
        //    Replace the entire phrase so the empty-after-redaction guard can
        //    omit messages that contained nothing but auth material.
        s = replacingMatches(
            in: s,
            pattern: #"(?i)authorization\s*[:=]\s*\S+(?:\s+\S+)?"#,
            with: "[REDACTED]"
        )

        // 2. Bearer tokens: "Bearer <token>" (case-insensitive). Replace the
        //    entire phrase including the scheme keyword.
        s = replacingMatches(
            in: s,
            pattern: #"(?i)\bbearer\s+[A-Za-z0-9._\-+/=]+"#,
            with: "[REDACTED]"
        )

        // 3. DeepL-style auth scheme.
        s = replacingMatches(
            in: s,
            pattern: #"(?i)\bDeepL-Auth-Key\s+\S+"#,
            with: "[REDACTED]"
        )

        // 4. Email addresses.
        s = replacingMatches(
            in: s,
            pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
            with: "[REDACTED]"
        )

        // 5. Common API-key / token prefixes (OpenAI, GitHub, Google).
        s = replacingMatches(
            in: s,
            pattern: #"\b(?:sk|ghp|gho|ghs|ghu|github_pat|AIza)[_\-]?[A-Za-z0-9_\-]{16,}"#,
            with: "[REDACTED]",
            options: []
        )

        // 6. URL query secrets — strip values for sensitive parameter names.
        s = replacingMatches(
            in: s,
            pattern: #"(?i)(api[_\-]?key|access[_\-]?token|refresh[_\-]?token|client[_\-]?secret|token|key|password|secret|auth)=([^&\s"']+)"#,
            with: "$1=[REDACTED]"
        )

        // 7. Long opaque token-like substrings (base64/JWT/random IDs of >= 24 chars).
        //    Run last so labelled patterns above had first chance.
        s = replacingMatches(
            in: s,
            pattern: #"[A-Za-z0-9_\-+/=]{24,}"#,
            with: "[REDACTED]"
        )

        // Collapse repeated whitespace produced by replacements.
        s = replacingMatches(in: s, pattern: #"\s+"#, with: " ")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // Apply the 200-character bound after redaction.
        if s.count > maxMessageLength {
            let endIndex = s.index(s.startIndex, offsetBy: maxMessageLength)
            s = String(s[..<endIndex])
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // If only redaction placeholders / punctuation remain, omit the message.
        let stripped = replacingMatches(in: s, pattern: #"\[REDACTED\]"#, with: "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines
                .union(CharacterSet(charactersIn: ":,;.-_()[]{}")))
        if stripped.isEmpty { return nil }

        return s
    }

    // MARK: - Code sanitization

    /// Trims and length-bounds provider codes so they are safe to render in UI.
    /// Codes are not subject to long-token redaction because they are
    /// machine-readable identifiers like "rate_limited" or "PERMISSION_DENIED".
    private static func sanitizeCode(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Bound code length so a hostile body cannot inflate the UI string.
        if trimmed.count > 64 {
            return String(trimmed.prefix(64))
        }
        return trimmed
    }

    // MARK: - Parsing

    private struct Parsed {
        let code: String?
        let rawMessage: String?
    }

    private static func parse(provider: Provider, responseData: Data) -> Parsed {
        // Try JSON object first. Fall back to plain text for malformed bodies.
        let dict = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any]

        switch provider {
        case .openAI:
            if let dict { return parseOpenAI(dict) }
        case .copilot:
            if let dict {
                let primary = parseOpenAI(dict)
                if primary.code != nil || primary.rawMessage != nil {
                    return primary
                }
                let topCode = (dict["code"] as? String) ?? stringFromAny(dict["code"])
                let topMessage = (dict["message"] as? String)
                if topCode != nil || topMessage != nil {
                    return Parsed(code: topCode, rawMessage: topMessage)
                }
                return parseGenericDict(dict)
            }
        case .google:
            if let dict { return parseGoogle(dict) }
        case .deepL:
            if let dict { return parseDeepL(dict) }
        case .generic:
            if let dict { return parseGenericDict(dict) }
        }

        // Fallback: malformed JSON — try sanitized text from the body.
        let fallbackText = String(data: responseData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Parsed(code: nil, rawMessage: (fallbackText?.isEmpty == false) ? fallbackText : nil)
    }

    private static func parseOpenAI(_ dict: [String: Any]) -> Parsed {
        let errorObj = dict["error"] as? [String: Any]
        let code = (errorObj?["code"] as? String)
            ?? stringFromAny(errorObj?["code"])
            ?? (errorObj?["type"] as? String)
        let message = errorObj?["message"] as? String
        return Parsed(code: code, rawMessage: message)
    }

    private static func parseGoogle(_ dict: [String: Any]) -> Parsed {
        let errorObj = dict["error"] as? [String: Any]
        let status = errorObj?["status"] as? String
        let firstReason: String? = {
            guard let errors = errorObj?["errors"] as? [[String: Any]] else { return nil }
            return errors.first?["reason"] as? String
        }()
        let numericCode = stringFromAny(errorObj?["code"])
        let code = status ?? firstReason ?? numericCode
        let message = errorObj?["message"] as? String
        return Parsed(code: code, rawMessage: message)
    }

    private static func parseDeepL(_ dict: [String: Any]) -> Parsed {
        // DeepL puts the human-readable error at the top-level `message` key.
        // The spec only accepts a string `code` field if present (not numeric).
        let code = dict["code"] as? String
        let message = dict["message"] as? String
        return Parsed(code: code, rawMessage: message)
    }

    private static func parseGenericDict(_ dict: [String: Any]) -> Parsed {
        let code = (dict["code"] as? String)
            ?? stringFromAny(dict["code"])
            ?? (dict["error_code"] as? String)
            ?? stringFromAny(dict["error_code"])
        let message = (dict["message"] as? String)
            ?? (dict["error_description"] as? String)
        return Parsed(code: code, rawMessage: message)
    }

    private static func stringFromAny(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let s = value as? String { return s }
        if let n = value as? Int { return String(n) }
        if let n = value as? Int64 { return String(n) }
        if let n = value as? Double {
            // Avoid trailing .0 for integral doubles.
            if n.truncatingRemainder(dividingBy: 1) == 0 {
                return String(Int64(n))
            }
            return String(n)
        }
        return nil
    }

    // MARK: - Regex helper

    /// Applies an `NSRegularExpression` replacement and returns the input unchanged
    /// if the pattern fails to compile (defensive — none of the patterns above
    /// should ever fail).
    private static func replacingMatches(
        in input: String,
        pattern: String,
        with template: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return input
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(
            in: input,
            options: [],
            range: range,
            withTemplate: template
        )
    }
}
