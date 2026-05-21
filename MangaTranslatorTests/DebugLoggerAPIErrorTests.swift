import XCTest
@testable import MangaTranslator

/// Covers `DebugLogger.logAPIError`: ensures sanitized provider error metadata
/// is persisted while raw response data, credentials, and personal identifiers
/// stay out of the log store.
final class DebugLoggerAPIErrorTests: XCTestCase {
    private var store: DebugLogStore!
    private var logger: DebugLogger!
    private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        store = DebugLogStore(databaseURL: tempURL)
        logger = DebugLogger(store: store)
    }

    override func tearDown() async throws {
        store = nil
        logger = nil
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    // MARK: - 6.2 Persisted diagnostics

    func testLogAPIErrorPersistsSanitizedProviderFields() async throws {
        let sanitized = SanitizedAPIError(
            provider: "OpenAI Compatible",
            statusCode: 429,
            code: "rate_limited",
            message: "Rate limit reached for org"
        )
        logger.logAPIError(
            sanitized,
            category: .translationOpenAI,
            model: "gpt-5",
            endpoint: "https://api.openai.com/v1"
        )
        await logger.flush()

        let entries = await store.query(filter: DebugLogFilter())
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.category, .translationOpenAI)
        XCTAssertEqual(entry.level, .error)

        let metadata = try parseMetadata(entry.metadataJSON)
        XCTAssertEqual(metadata["provider"], "OpenAI Compatible")
        XCTAssertEqual(metadata["status_code"], "429")
        XCTAssertEqual(metadata["provider_code"], "rate_limited")
        XCTAssertEqual(metadata["provider_message"], "Rate limit reached for org")
        XCTAssertEqual(metadata["model"], "gpt-5")
        XCTAssertEqual(metadata["endpoint"], "https://api.openai.com/v1")
    }

    // MARK: - 6.3 Sensitive content is not persisted

    func testLogAPIErrorEndpointStripsCredentialsQueryAndFragment() async throws {
        let sanitized = SanitizedAPIError(
            provider: "Google Translate",
            statusCode: 401,
            code: "UNAUTHENTICATED",
            message: "API key invalid"
        )
        logger.logAPIError(
            sanitized,
            category: .translationGoogle,
            endpoint: "https://user:pass@translation.googleapis.com/v2?key=AIza-secret-123456&q=hi#frag"
        )
        await logger.flush()

        let entries = await store.query(filter: DebugLogFilter())
        let entry = try XCTUnwrap(entries.first)
        let metadata = try parseMetadata(entry.metadataJSON)
        let endpoint = try XCTUnwrap(metadata["endpoint"])
        XCTAssertFalse(endpoint.contains("AIza-secret-123456"))
        XCTAssertFalse(endpoint.contains("user:pass"))
        XCTAssertFalse(endpoint.contains("?"))
        XCTAssertFalse(endpoint.contains("#"))
    }

    func testLogAPIErrorMetadataRedactionStripsSensitiveKeys() async throws {
        // Even though logAPIError builds its own metadata keys, the underlying
        // `log()` path still runs them through `redactMetadata`. This test
        // proves that path remains active so future callers cannot smuggle
        // raw bodies in via the public log function.
        logger.log(
            "raw body smuggled in",
            level: .error,
            category: .translationOpenAI,
            metadata: [
                "response_body": "Bearer sk-leaked1234567890abcdef1234567890",
                "authorization": "Bearer secret-12345",
                "raw_response": "API key sk-real",
                "model": "gpt-5"
            ]
        )
        await logger.flush()

        let entries = await store.query(filter: DebugLogFilter())
        let entry = try XCTUnwrap(entries.first)
        let metadata = try parseMetadata(entry.metadataJSON)
        XCTAssertEqual(metadata["response_body"], "[REDACTED]")
        XCTAssertEqual(metadata["authorization"], "[REDACTED]")
        XCTAssertEqual(metadata["raw_response"], "[REDACTED]")
        XCTAssertEqual(metadata["model"], "gpt-5")
    }

    func testLogAPIErrorSanitizedMessageStaysWithin200Chars() async throws {
        let longMessage = String(repeating: "the upstream gateway returned an unexpected response. ", count: 20)
        let sanitized = SanitizedAPIError(
            provider: "DeepL",
            statusCode: 503,
            code: nil,
            message: APIErrorSanitizer.redact(longMessage)
        )
        logger.logAPIError(sanitized, category: .translationDeepL)
        await logger.flush()

        let entries = await store.query(filter: DebugLogFilter())
        let entry = try XCTUnwrap(entries.first)
        let metadata = try parseMetadata(entry.metadataJSON)
        let stored = try XCTUnwrap(metadata["provider_message"])
        XCTAssertLessThanOrEqual(stored.count, APIErrorSanitizer.maxMessageLength)
    }

    // MARK: - Helpers

    private func parseMetadata(_ json: String) throws -> [String: String] {
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode([String: String].self, from: data)
        return decoded
    }
}
