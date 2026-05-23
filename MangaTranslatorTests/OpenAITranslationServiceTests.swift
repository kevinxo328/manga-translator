import Testing
import Foundation
@testable import MangaTranslator

@Suite("OpenAITranslationService")
struct OpenAITranslationServiceTests {

    // MARK: - Base URL validation (happens before keychain check)

    @Test("translate throws BaseURLValidatorError when base URL has a query string")
    func throwsOnQueryStringBaseURL() async {
        let service = OpenAITranslationService(model: "gpt-5", baseURL: "https://api.openai.com/v1?inject=1")
        await #expect(throws: BaseURLValidatorError.self) {
            _ = try await service.translate(bubbles: [], from: .ja, to: .zhHant, context: .empty)
        }
    }

    @Test("translate throws BaseURLValidatorError when base URL has a fragment")
    func throwsOnFragmentBaseURL() async {
        let service = OpenAITranslationService(model: "gpt-5", baseURL: "https://api.openai.com/v1#frag")
        await #expect(throws: BaseURLValidatorError.self) {
            _ = try await service.translate(bubbles: [], from: .ja, to: .zhHant, context: .empty)
        }
    }

    @Test("translate throws BaseURLValidatorError when base URL uses HTTP with remote host")
    func throwsOnHTTPRemoteBaseURL() async {
        let service = OpenAITranslationService(model: "gpt-5", baseURL: "http://api.openai.com/v1")
        await #expect(throws: BaseURLValidatorError.self) {
            _ = try await service.translate(bubbles: [], from: .ja, to: .zhHant, context: .empty)
        }
    }

    @Test("translate throws BaseURLValidatorError when base URL is empty")
    func throwsOnEmptyBaseURL() async {
        let service = OpenAITranslationService(model: "gpt-5", baseURL: "")
        await #expect(throws: BaseURLValidatorError.self) {
            _ = try await service.translate(bubbles: [], from: .ja, to: .zhHant, context: .empty)
        }
    }
}

// MARK: - Non-2xx provider error tests

@Suite("OpenAITranslationService non-2xx")
struct OpenAITranslationServiceErrorTests {

    private func makeService(session: URLSession) -> OpenAITranslationService {
        OpenAITranslationService(
            model: "gpt-5",
            baseURL: "https://api.openai.com/v1",
            keychainService: .mocked(returning: "sk-test-key"),
            urlSession: session
        )
    }

    private func makeBubble() -> BubbleCluster {
        BubbleCluster(boundingBox: .zero, text: "こんにちは", observations: [])
    }

    @Test("non-2xx throws sanitized provider API error with parsed code and message")
    func nonSuccessThrowsSanitizedError() async throws {
        let body = Data(#"""
        {"error":{"message":"Invalid API key sk-secret1234567890abcdef1234567890","type":"invalid_request_error","code":"invalid_api_key"}}
        """#.utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        do {
            _ = try await service.translate(bubbles: [makeBubble()], from: .ja, to: .zhHant, context: .empty)
            Issue.record("Expected translate to throw")
        } catch let TranslationError.apiError(sanitized) {
            #expect(sanitized.provider == "OpenAI Compatible")
            #expect(sanitized.statusCode == 401)
            #expect(sanitized.code == "invalid_api_key")
            let message = try #require(sanitized.message)
            #expect(!message.contains("sk-secret1234567890abcdef1234567890"))
        } catch {
            Issue.record("Expected TranslationError.apiError, got \(error)")
        }
    }

    @Test("localizedDescription excludes raw sensitive body content")
    func localizedDescriptionExcludesSensitiveContent() async throws {
        let body = Data(#"""
        {"error":{"message":"Token leaked: Bearer ghp_1234567890abcdef1234567890abcdef1234 user a@b.com","code":"unauthorized"}}
        """#.utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        do {
            _ = try await service.translate(bubbles: [makeBubble()], from: .ja, to: .zhHant, context: .empty)
            Issue.record("Expected throw")
        } catch let error as TranslationError {
            let description = try #require(error.errorDescription)
            #expect(description.contains("OpenAI Compatible"))
            #expect(description.contains("401"))
            #expect(!description.contains("ghp_1234567890abcdef1234567890abcdef1234"))
            #expect(!description.contains("a@b.com"))
        }
    }
}

// MARK: - Multi-page batch tests

@Suite("OpenAITranslationService translateBatch")
struct OpenAITranslationServiceBatchTests {

    private func makeService(session: URLSession) -> OpenAITranslationService {
        OpenAITranslationService(
            model: "gpt-5",
            baseURL: "https://api.openai.com/v1",
            keychainService: .mocked(returning: "sk-test-key"),
            urlSession: session
        )
    }

    private func makeBubble(index: Int = 0, text: String = "src") -> BubbleCluster {
        var b = BubbleCluster(boundingBox: .zero, text: text, observations: [])
        b.index = index
        return b
    }

    private func makeInputs(_ pageIds: [String]) -> [BatchPageInput] {
        pageIds.map { BatchPageInput(pageId: $0, bubbles: [makeBubble(index: 0, text: "src-\($0)")]) }
    }

    private func validResponseBody(translations: [(pageId: String, text: String)]) -> Data {
        let pages = translations
            .map { "{\"page_id\":\"\($0.pageId)\",\"bubbles\":[{\"index\":0,\"translation\":\"\($0.text)\"}]}" }
            .joined(separator: ",")
        let content = "{\"pages\":[\(pages)]}"
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return Data("{\"choices\":[{\"message\":{\"content\":\"\(escaped)\"}}]}".utf8)
    }

    @Test("translateBatch sends multi-page request with recent context block")
    func sendsMultiPageRequest() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(body: request.readMockBody())
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, self.validResponseBody(translations: [("1", "T1"), ("2", "T2")]))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        let priorContext = TranslationContext(glossaryTerms: [], recentPageSummaries: ["page-A-summary"])

        _ = try await service.translateBatch(
            pageInputs: makeInputs(["1", "2"]),
            from: .ja,
            to: .en,
            priorContext: priorContext
        )

        let body = try #require(counter.capturedBodies.first)
        let bodyString = String(decoding: body, as: UTF8.self)
        #expect(bodyString.contains("page_id"))
        #expect(bodyString.contains("Recent context"))
        #expect(bodyString.contains("page-A-summary"))
    }

    @Test("translateBatch returns outputs in requested order regardless of response order")
    func returnsOutputsInRequestedOrder() async throws {
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, self.validResponseBody(translations: [("3", "T3"), ("1", "T1"), ("2", "T2")]))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        let outputs = try await service.translateBatch(
            pageInputs: makeInputs(["1", "2", "3"]),
            from: .ja,
            to: .en,
            priorContext: .empty
        )

        #expect(outputs.map { $0.pageId } == ["1", "2", "3"])
    }

    @Test("translateBatch retries once on HTTP 500 then succeeds")
    func retriesOnceOnHTTP500() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let attempt = counter.record(body: request.readMockBody())
            if attempt == 1 {
                let resp = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (resp, Data("internal error".utf8))
            } else {
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, self.validResponseBody(translations: [("1", "T1")]))
            }
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        let outputs = try await service.translateBatch(
            pageInputs: makeInputs(["1"]),
            from: .ja,
            to: .en,
            priorContext: .empty
        )

        #expect(outputs.count == 1)
        #expect(counter.count == 2)
    }

    @Test("translateBatch throws after second HTTP 500 (fallback trigger)")
    func throwsAfterSecondHTTP500() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(body: request.readMockBody())
            let resp = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (resp, Data("internal error".utf8))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        var caught: Error?
        do {
            _ = try await service.translateBatch(
                pageInputs: makeInputs(["1"]),
                from: .ja,
                to: .en,
                priorContext: .empty
            )
            Issue.record("Expected throw")
        } catch {
            caught = error
        }

        #expect(counter.count == 2)
        let error = try #require(caught)
        #expect(!(error is CancellationError))
        if let urlError = error as? URLError {
            #expect(urlError.code != .cancelled)
        }
    }

    @Test("translateBatch throws on missing page id after retry (fallback trigger)")
    func throwsOnMissingPageId() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(body: request.readMockBody())
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, self.validResponseBody(translations: [("1", "T1"), ("3", "T3")]))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        var caught: Error?
        do {
            _ = try await service.translateBatch(
                pageInputs: makeInputs(["1", "2", "3"]),
                from: .ja,
                to: .en,
                priorContext: .empty
            )
            Issue.record("Expected throw")
        } catch {
            caught = error
        }

        #expect(counter.count == 2)
        let parseError = try #require(caught as? LLMResponseParser.MultiPageParseError)
        if case .missingPage(let id) = parseError {
            #expect(id == "2")
        } else {
            Issue.record("Expected .missingPage, got \(parseError)")
        }
    }

    @Test("translateBatch accepts any 2xx response status (e.g. 201)")
    func acceptsAny2xxStatus() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(body: request.readMockBody())
            let resp = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (resp, self.validResponseBody(translations: [("1", "T1")]))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        let outputs = try await service.translateBatch(
            pageInputs: makeInputs(["1"]),
            from: .ja,
            to: .en,
            priorContext: .empty
        )

        #expect(outputs.count == 1)
        #expect(counter.count == 1)
    }

    @Test("translateBatch propagates cancellation without retry or fallback")
    func doesNotRetryOrFallbackOnCancellation() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request -> Result<(HTTPURLResponse, Data), URLError> in
            _ = counter.record(body: request.readMockBody())
            return .failure(URLError(.cancelled))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        var caught: Error?
        do {
            _ = try await service.translateBatch(
                pageInputs: makeInputs(["1"]),
                from: .ja,
                to: .en,
                priorContext: .empty
            )
            Issue.record("Expected throw")
        } catch {
            caught = error
        }

        #expect(counter.count == 1)
        let urlError = try #require(caught as? URLError)
        #expect(urlError.code == .cancelled)
    }
}
