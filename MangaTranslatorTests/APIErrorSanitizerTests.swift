import Testing
import Foundation
@testable import MangaTranslator

@Suite("APIErrorSanitizer")
struct APIErrorSanitizerTests {

    // MARK: - 1.1 Redaction patterns

    @Test("redact removes Authorization header values")
    func redactAuthorizationHeader() throws {
        let raw = "Request failed because Authorization: Bearer abcd1234abcd1234abcd1234abcd is invalid"
        let result = try #require(APIErrorSanitizer.redact(raw))
        #expect(!result.contains("abcd1234abcd1234abcd1234abcd"))
        #expect(result.contains("[REDACTED]"))
    }

    @Test("redact removes bearer tokens")
    func redactBearerToken() throws {
        let raw = "credentials rejected by upstream because bearer sk-1234567890abcdef1234567890abcdef expired"
        let result = try #require(APIErrorSanitizer.redact(raw))
        #expect(!result.contains("sk-1234567890abcdef1234567890abcdef"))
        #expect(result.contains("[REDACTED]"))
    }

    @Test("redact removes OpenAI-style API keys")
    func redactOpenAIKey() throws {
        let raw = "Invalid key sk-proj-abcdefghijklmnopqrstuvwxyz0123456789 provided"
        let result = try #require(APIErrorSanitizer.redact(raw))
        #expect(!result.contains("sk-proj-abcdefghijklmnopqrstuvwxyz0123456789"))
        #expect(result.contains("[REDACTED]"))
    }

    @Test("redact removes GitHub PAT-style tokens")
    func redactGitHubToken() throws {
        let raw = "Token ghp_1234567890abcdef1234567890abcdef1234 invalid"
        let result = try #require(APIErrorSanitizer.redact(raw))
        #expect(!result.contains("ghp_1234567890abcdef1234567890abcdef1234"))
    }

    @Test("redact removes Google API keys")
    func redactGoogleKey() throws {
        let raw = "key AIzaSyA-1234567890abcdefghijklmnopqrst rejected"
        let result = try #require(APIErrorSanitizer.redact(raw))
        #expect(!result.contains("AIzaSyA-1234567890abcdefghijklmnopqrst"))
    }

    @Test("redact removes long opaque token-like strings")
    func redactLongOpaqueToken() throws {
        let raw = "Failed with token ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef0123456789 attached"
        let result = try #require(APIErrorSanitizer.redact(raw))
        #expect(!result.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef0123456789"))
        #expect(result.contains("[REDACTED]"))
    }

    @Test("redact removes URL query secrets")
    func redactQuerySecret() throws {
        let raw = "Request https://example.com/v2?key=verysecret123&q=foo failed"
        let result = try #require(APIErrorSanitizer.redact(raw))
        #expect(!result.contains("verysecret123"))
        #expect(result.contains("key=[REDACTED]"))
    }

    @Test("redact removes access_token query parameter")
    func redactAccessTokenQuery() throws {
        let raw = "url ?access_token=topsecrettokenvalue99 expired"
        let result = try #require(APIErrorSanitizer.redact(raw))
        #expect(!result.contains("topsecrettokenvalue99"))
    }

    @Test("redact removes email addresses")
    func redactEmail() throws {
        let raw = "User user.name+tag@example.com is not authorized"
        let result = try #require(APIErrorSanitizer.redact(raw))
        #expect(!result.contains("user.name+tag@example.com"))
        #expect(result.contains("[REDACTED]"))
    }

    // MARK: - 1.2 Normalization and truncation

    @Test("redact normalizes whitespace")
    func redactNormalizesWhitespace() throws {
        let raw = "Error\n\noccurred\tunexpectedly  with\rdetails"
        let result = try #require(APIErrorSanitizer.redact(raw))
        #expect(!result.contains("\n"))
        #expect(!result.contains("\t"))
        #expect(!result.contains("\r"))
        #expect(!result.contains("  "))
    }

    @Test("redact truncates to 200 characters after redaction")
    func redactTruncates() throws {
        // Use real-looking sentence fragments so the long-opaque-token rule
        // does not collapse the whole message into [REDACTED].
        let fragment = "the model returned an unexpected error and the request will not be retried. "
        let raw = String(repeating: fragment, count: 20)
        let result = try #require(APIErrorSanitizer.redact(raw))
        #expect(result.count <= APIErrorSanitizer.maxMessageLength)
    }

    @Test("redact returns nil when only redaction placeholders remain")
    func redactReturnsNilWhenOnlyPlaceholdersRemain() {
        let raw = "Bearer sk-1234567890abcdef1234567890abcdef"
        let result = APIErrorSanitizer.redact(raw)
        #expect(result == nil)
    }

    @Test("redact returns nil for empty input")
    func redactReturnsNilForEmpty() {
        #expect(APIErrorSanitizer.redact("") == nil)
        #expect(APIErrorSanitizer.redact("   \n\t  ") == nil)
    }

    // MARK: - 1.3 OpenAI parsing

    @Test("parses OpenAI error.code and error.message")
    func parsesOpenAICodeAndMessage() {
        let body = #"{"error":{"message":"Rate limit reached","type":"rate_limit","code":"rate_limited"}}"#
        let data = Data(body.utf8)
        let result = APIErrorSanitizer.sanitize(
            provider: .openAI,
            providerDisplayName: "OpenAI Compatible",
            statusCode: 429,
            responseData: data
        )
        #expect(result.code == "rate_limited")
        #expect(result.message == "Rate limit reached")
    }

    @Test("falls back to error.type when error.code missing")
    func openAIFallsBackToType() {
        let body = #"{"error":{"message":"Invalid request","type":"invalid_request_error"}}"#
        let data = Data(body.utf8)
        let result = APIErrorSanitizer.sanitize(
            provider: .openAI,
            providerDisplayName: "OpenAI Compatible",
            statusCode: 400,
            responseData: data
        )
        #expect(result.code == "invalid_request_error")
        #expect(result.message == "Invalid request")
    }

    @Test("OpenAI parser includes provider and status when message empty after sanitization")
    func openAIDropsEmptyMessage() {
        let body = #"{"error":{"message":"Bearer sk-1234567890abcdef1234567890abcdef","code":"unauthorized"}}"#
        let data = Data(body.utf8)
        let result = APIErrorSanitizer.sanitize(
            provider: .openAI,
            providerDisplayName: "OpenAI Compatible",
            statusCode: 401,
            responseData: data
        )
        #expect(result.message == nil)
        #expect(result.code == "unauthorized")
        #expect(result.provider == "OpenAI Compatible")
        #expect(result.statusCode == 401)
    }

    // MARK: - 1.4 Google parsing

    @Test("parses Google error.status as code")
    func parsesGoogleStatus() {
        let body = #"{"error":{"code":403,"message":"The request is missing a valid API key.","errors":[{"reason":"FORBIDDEN"}],"status":"PERMISSION_DENIED"}}"#
        let data = Data(body.utf8)
        let result = APIErrorSanitizer.sanitize(
            provider: .google,
            providerDisplayName: "Google Translate",
            statusCode: 403,
            responseData: data
        )
        #expect(result.code == "PERMISSION_DENIED")
        #expect(result.message == "The request is missing a valid API key.")
    }

    @Test("Google falls back to first errors[].reason when status missing")
    func googleFallsBackToReason() {
        let body = #"{"error":{"code":400,"message":"Bad request","errors":[{"reason":"badRequest"}]}}"#
        let data = Data(body.utf8)
        let result = APIErrorSanitizer.sanitize(
            provider: .google,
            providerDisplayName: "Google Translate",
            statusCode: 400,
            responseData: data
        )
        #expect(result.code == "badRequest")
    }

    @Test("Google falls back to numeric error.code when status and reason missing")
    func googleFallsBackToNumericCode() {
        let body = #"{"error":{"code":429,"message":"Resource exhausted"}}"#
        let data = Data(body.utf8)
        let result = APIErrorSanitizer.sanitize(
            provider: .google,
            providerDisplayName: "Google Translate",
            statusCode: 429,
            responseData: data
        )
        #expect(result.code == "429")
        #expect(result.message == "Resource exhausted")
    }

    // MARK: - 1.5 DeepL parsing

    @Test("parses DeepL top-level message")
    func parsesDeepLMessage() {
        let body = #"{"message":"Quota for this billing period has been exceeded."}"#
        let data = Data(body.utf8)
        let result = APIErrorSanitizer.sanitize(
            provider: .deepL,
            providerDisplayName: "DeepL",
            statusCode: 456,
            responseData: data
        )
        #expect(result.message == "Quota for this billing period has been exceeded.")
        #expect(result.code == nil)
    }

    @Test("DeepL accepts string code when present")
    func deepLAcceptsStringCode() {
        let body = #"{"code":"quota_exceeded","message":"Quota exceeded"}"#
        let data = Data(body.utf8)
        let result = APIErrorSanitizer.sanitize(
            provider: .deepL,
            providerDisplayName: "DeepL",
            statusCode: 456,
            responseData: data
        )
        #expect(result.code == "quota_exceeded")
    }

    // MARK: - 1.6 Copilot parsing and generic fallback

    @Test("parses Copilot OpenAI-compatible body")
    func parsesCopilotOpenAIBody() {
        let body = #"{"error":{"message":"model_not_found","code":"model_not_found","type":"invalid_request_error"}}"#
        let data = Data(body.utf8)
        let result = APIErrorSanitizer.sanitize(
            provider: .copilot,
            providerDisplayName: "GitHub Copilot",
            statusCode: 404,
            responseData: data
        )
        #expect(result.code == "model_not_found")
        #expect(result.message == "model_not_found")
    }

    @Test("Copilot falls back to top-level code and message")
    func copilotFallsBackToTopLevel() {
        let body = #"{"code":"forbidden","message":"Subscription required"}"#
        let data = Data(body.utf8)
        let result = APIErrorSanitizer.sanitize(
            provider: .copilot,
            providerDisplayName: "GitHub Copilot",
            statusCode: 403,
            responseData: data
        )
        #expect(result.code == "forbidden")
        #expect(result.message == "Subscription required")
    }

    @Test("Copilot generic malformed text falls back safely")
    func copilotMalformedTextFallback() {
        let raw = "<html>Service Unavailable</html>"
        let data = Data(raw.utf8)
        let result = APIErrorSanitizer.sanitize(
            provider: .copilot,
            providerDisplayName: "GitHub Copilot",
            statusCode: 503,
            responseData: data
        )
        #expect(result.provider == "GitHub Copilot")
        #expect(result.statusCode == 503)
        // Either nil or a sanitized fragment, but never the raw HTML untouched.
        if let message = result.message {
            #expect(message.count <= APIErrorSanitizer.maxMessageLength)
        }
    }

    @Test("unparseable JSON returns provider and status with optional safe message")
    func unparseableJSONFallsBackSafely() {
        let data = Data("{not valid json".utf8)
        let result = APIErrorSanitizer.sanitize(
            provider: .openAI,
            providerDisplayName: "OpenAI Compatible",
            statusCode: 500,
            responseData: data
        )
        #expect(result.provider == "OpenAI Compatible")
        #expect(result.statusCode == 500)
    }

    // MARK: - UI summary formatting

    @Test("localizedSummary includes provider, status, code, and message")
    func summaryCodeAndMessage() {
        let err = SanitizedAPIError(
            provider: "OpenAI Compatible",
            statusCode: 429,
            code: "rate_limited",
            message: "Rate limit reached"
        )
        #expect(err.localizedSummary ==
                "OpenAI Compatible request failed with HTTP 429 (rate_limited): Rate limit reached")
    }

    @Test("localizedSummary omits parentheses when code missing")
    func summaryMessageOnly() {
        let err = SanitizedAPIError(
            provider: "DeepL",
            statusCode: 456,
            code: nil,
            message: "Quota exceeded"
        )
        #expect(err.localizedSummary == "DeepL request failed with HTTP 456: Quota exceeded")
    }

    @Test("localizedSummary omits colon when message missing")
    func summaryStatusOnly() {
        let err = SanitizedAPIError(
            provider: "Google Translate",
            statusCode: 500,
            code: nil,
            message: nil
        )
        #expect(err.localizedSummary == "Google Translate request failed with HTTP 500")
    }
}
