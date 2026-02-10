import Foundation

struct LLMPrompt {
    static func systemPrompt(from source: Language, to target: Language) -> String {
        """
        You are an expert manga translator. Translate speech bubble text from \(source.displayName) to \(target.displayName).

        Rules:
        - Translate naturally as a manga reader would expect, preserving tone, emotion, and character voice.
        - Maintain consistency in how characters address each other.
        - Keep onomatopoeia translations natural in the target language.
        - If the reading order of bubbles seems incorrect based on dialogue flow (e.g., an answer appears before its question), reorder them.

        You will receive a JSON array of bubbles with their positions (x, y coordinates where origin is top-left).
        Manga reads right-to-left, top-to-bottom.

        Respond with ONLY a JSON array in this exact format:
        [
          {"index": 0, "translation": "translated text here"},
          {"index": 1, "translation": "translated text here"}
        ]

        The "index" field should reflect the corrected reading order (0 = first to read).
        Do not include any other text outside the JSON array.
        """
    }

    static func userPrompt(bubbles: [BubbleCluster]) -> String {
        let bubblesJSON = bubbles.enumerated().map { i, bubble in
            """
            {"index": \(i), "x": \(Int(bubble.boundingBox.origin.x)), "y": \(Int(bubble.boundingBox.origin.y)), "width": \(Int(bubble.boundingBox.width)), "height": \(Int(bubble.boundingBox.height)), "text": "\(bubble.text.replacingOccurrences(of: "\"", with: "\\\""))"}
            """
        }.joined(separator: ",\n  ")

        return "[\n  \(bubblesJSON)\n]"
    }
}

struct LLMTranslationResponse: Codable {
    let index: Int
    let translation: String
}

enum LLMResponseParser {
    static func parse(_ responseText: String, bubbles: [BubbleCluster]) throws -> [TranslatedBubble] {
        let cleaned = responseText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw TranslationError.invalidResponse
        }

        let decoded = try JSONDecoder().decode([LLMTranslationResponse].self, from: data)

        return decoded.compactMap { item in
            guard item.index < bubbles.count else { return nil }
            return TranslatedBubble(
                bubble: bubbles[item.index],
                translatedText: item.translation,
                index: item.index
            )
        }
    }

    static func fallbackParse(_ responseText: String, bubbles: [BubbleCluster]) -> [TranslatedBubble] {
        let lines = responseText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return zip(lines, bubbles).enumerated().map { index, pair in
            TranslatedBubble(
                bubble: pair.1,
                translatedText: pair.0.trimmingCharacters(in: .whitespaces),
                index: index
            )
        }
    }
}
