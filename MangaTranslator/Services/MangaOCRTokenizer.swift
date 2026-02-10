import Foundation

final class MangaOCRTokenizer {
    private let vocab: [String]   // id -> token
    private let idMap: [String: Int] // token -> id

    // Special token IDs (from generation_config.json)
    static let padTokenId = 0     // [PAD]
    static let unkTokenId = 1     // [UNK]
    static let clsTokenId = 2     // [CLS] = decoder_start_token_id
    static let sepTokenId = 3     // [SEP] = eos_token_id

    init() throws {
        guard let vocabURL = Bundle.main.url(forResource: "vocab", withExtension: "txt", subdirectory: nil) else {
            // Try Models subdirectory
            guard let vocabURL = Bundle.main.url(forResource: "vocab", withExtension: "txt") else {
                throw MangaOCRError.vocabNotFound
            }
            let content = try String(contentsOf: vocabURL, encoding: .utf8)
            let tokens = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            self.vocab = tokens
            var map = [String: Int]()
            for (i, token) in tokens.enumerated() {
                map[token] = i
            }
            self.idMap = map
            return
        }
        let content = try String(contentsOf: vocabURL, encoding: .utf8)
        let tokens = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        self.vocab = tokens
        var map = [String: Int]()
        for (i, token) in tokens.enumerated() {
            map[token] = i
        }
        self.idMap = map
    }

    func decode(_ tokenIds: [Int]) -> String {
        var text = ""
        for id in tokenIds {
            // Skip special tokens
            if id == Self.padTokenId || id == Self.clsTokenId || id == Self.sepTokenId {
                continue
            }
            guard id >= 0, id < vocab.count else { continue }
            let token = vocab[id]
            if token == "[UNK]" { continue }
            // WordPiece tokens starting with ## are subword continuations
            if token.hasPrefix("##") {
                text += String(token.dropFirst(2))
            } else {
                text += token
            }
        }
        return postProcess(text)
    }

    private func postProcess(_ text: String) -> String {
        // Remove whitespace (manga OCR output should be continuous Japanese text)
        var clean = text.filter { !$0.isWhitespace }
        // Replace ellipsis character with dots
        clean = clean.replacingOccurrences(of: "\u{2026}", with: "...")
        return clean
    }
}

enum MangaOCRError: LocalizedError {
    case vocabNotFound
    case modelNotFound(String)
    case inferenceError(String)

    var errorDescription: String? {
        switch self {
        case .vocabNotFound: return "vocab.txt not found in app bundle"
        case .modelNotFound(let name): return "\(name) not found in app bundle"
        case .inferenceError(let msg): return "MangaOCR inference error: \(msg)"
        }
    }
}
