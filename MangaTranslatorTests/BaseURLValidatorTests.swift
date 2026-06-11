import Testing
import Foundation
@testable import MangaTranslator

@Suite("BaseURLValidator")
struct BaseURLValidatorTests {

    // MARK: - Valid HTTPS

    @Test("HTTPS with standard OpenAI endpoint is valid")
    func httpsOpenAI() throws {
        let url = try BaseURLValidator.validate("https://api.openai.com/v1")
        #expect(url.scheme == "https")
    }

    @Test("HTTPS with custom remote host is valid")
    func httpsCustomRemote() throws {
        _ = try BaseURLValidator.validate("https://my-proxy.example.com/v1")
    }

    @Test("HTTPS with port is valid")
    func httpsWithPort() throws {
        _ = try BaseURLValidator.validate("https://proxy.internal:8443/v1")
    }

    // MARK: - Valid HTTP localhost

    @Test("HTTP localhost is valid for Ollama")
    func httpLocalhost() throws {
        _ = try BaseURLValidator.validate("http://localhost:11434/v1")
    }

    @Test("HTTP 127.0.0.1 is valid")
    func http127() throws {
        _ = try BaseURLValidator.validate("http://127.0.0.1:11434/v1")
    }

    @Test("HTTP 0.0.0.0 is valid")
    func http0000() throws {
        _ = try BaseURLValidator.validate("http://0.0.0.0:11434/v1")
    }

    @Test("HTTP IPv6 loopback is valid")
    func httpIPv6Loopback() throws {
        _ = try BaseURLValidator.validate("http://[::1]:11434/v1")
    }

    // MARK: - Invalid: HTTP remote

    @Test("HTTP with remote host is rejected")
    func httpRemoteHost() {
        #expect(throws: BaseURLValidatorError.self) {
            try BaseURLValidator.validate("http://api.openai.com/v1")
        }
    }

    @Test("HTTP with arbitrary remote host is rejected")
    func httpArbitraryRemote() {
        #expect(throws: BaseURLValidatorError.self) {
            try BaseURLValidator.validate("http://evil.example.com/collect")
        }
    }

    // MARK: - Invalid: wrong scheme

    @Test("FTP scheme is rejected")
    func ftpScheme() {
        #expect(throws: BaseURLValidatorError.self) {
            try BaseURLValidator.validate("ftp://api.openai.com/v1")
        }
    }

    @Test("No scheme is rejected")
    func noScheme() {
        #expect(throws: BaseURLValidatorError.self) {
            try BaseURLValidator.validate("api.openai.com/v1")
        }
    }

    // MARK: - Invalid: malformed / empty

    @Test("Empty string is rejected")
    func emptyString() {
        #expect(throws: BaseURLValidatorError.self) {
            try BaseURLValidator.validate("")
        }
    }

    @Test("Whitespace-only string is rejected")
    func whitespaceOnly() {
        #expect(throws: BaseURLValidatorError.self) {
            try BaseURLValidator.validate("   ")
        }
    }

    @Test("HTTPS with empty host is rejected")
    func httpsEmptyHost() {
        #expect(throws: BaseURLValidatorError.self) {
            try BaseURLValidator.validate("https:///v1")
        }
    }

    // MARK: - Invalid: query / fragment

    @Test("URL with query string is rejected")
    func queryString() {
        #expect(throws: BaseURLValidatorError.self) {
            try BaseURLValidator.validate("https://api.openai.com/v1?key=secret")
        }
    }

    @Test("URL with fragment is rejected")
    func fragment() {
        #expect(throws: BaseURLValidatorError.self) {
            try BaseURLValidator.validate("https://api.openai.com/v1#section")
        }
    }

    @Test("Localhost URL with query string is rejected")
    func localhostQueryString() {
        #expect(throws: BaseURLValidatorError.self) {
            try BaseURLValidator.validate("http://localhost:11434/v1?inject=1")
        }
    }

    // MARK: - Trailing-slash sanitization

    @Test("sanitized strips trailing slashes so appendingPathComponent yields no double slash")
    func sanitizedStripsTrailingSlashes() {
        #expect(BaseURLValidator.sanitized("https://api.openai.com/v1/") == "https://api.openai.com/v1")
        #expect(BaseURLValidator.sanitized("https://api.openai.com/v1///") == "https://api.openai.com/v1")
    }

    @Test("sanitized leaves URL without trailing slash unchanged")
    func sanitizedLeavesCleanURLUnchanged() {
        #expect(BaseURLValidator.sanitized("https://api.openai.com/v1") == "https://api.openai.com/v1")
    }

    // MARK: - URL construction

    @Test("validate returns URL that can be extended with /chat/completions")
    func chatCompletionsPath() throws {
        let base = try BaseURLValidator.validate("https://api.openai.com/v1")
        let full = base.appendingPathComponent("chat/completions")
        #expect(full.absoluteString == "https://api.openai.com/v1/chat/completions")
    }
}
