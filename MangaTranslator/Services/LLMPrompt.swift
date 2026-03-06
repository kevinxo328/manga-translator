import Foundation

struct LLMPrompt {
    static func systemPrompt(
        from source: Language,
        to target: Language,
        context: TranslationContext = .empty
    ) -> String {
        var prompt = """
        You are an expert manga translator. Translate speech bubble text from \(source.displayName) to \(target.displayName).

        Rules:
        - Translate naturally as a manga reader would expect, preserving tone, emotion, and character voice.
        - Maintain consistency in how characters address each other.
        - Keep onomatopoeia translations natural in the target language.

        You will receive a JSON array of bubbles with their positions (x, y coordinates where origin is top-left).
        Manga reads right-to-left, top-to-bottom.
        """

        if !context.glossaryTerms.isEmpty {
            let termLines = context.glossaryTerms
                .map { "  \($0.sourceTerm) → \($0.targetTerm)" }
                .joined(separator: "\n")
            prompt += """


        ## Glossary (MUST follow exactly)
        \(termLines)
        """
        }

        if !context.recentPageSummaries.isEmpty {
            let summaries = context.recentPageSummaries.enumerated()
                .map { i, text in "  Page \(i + 1): \(text)" }
                .joined(separator: "\n")
            prompt += """


        ## Recent context (previous pages)
        \(summaries)
        """
        }

        prompt += """


        Respond with ONLY a JSON array in this exact format:
        [
          {"index": 0, "translation": "translated text here", "detected_terms": [{"source": "original proper noun", "target": "translated proper noun"}]},
          {"index": 1, "translation": "translated text here"}
        ]

        The "index" field must match the index from the input bubble exactly — do not change it.
        The "detected_terms" field is optional — include it only in the FIRST element of the array, listing any NEW proper nouns (character names, place names, technique names) found in this page that are NOT already in the glossary above.
        Do not include any other text outside the JSON array.
        """

        return prompt
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

struct LLMDetectedTerm: Codable {
    let source: String
    let target: String
}

struct LLMTranslationResponse: Codable {
    let index: Int
    let translation: String
    let detectedTerms: [LLMDetectedTerm]?

    enum CodingKeys: String, CodingKey {
        case index
        case translation
        case detectedTerms = "detected_terms"
    }
}

enum LLMResponseParser {
    static func parse(_ responseText: String, bubbles: [BubbleCluster]) throws -> ([TranslatedBubble], [GlossaryTerm]) {
        let cleaned = responseText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw TranslationError.invalidResponse
        }

        let decoded = try JSONDecoder().decode([LLMTranslationResponse].self, from: data)

        let translatedBubbles = decoded.compactMap { item -> TranslatedBubble? in
            guard item.index < bubbles.count else { return nil }
            let originalBubble = bubbles[item.index]
            return TranslatedBubble(
                bubble: originalBubble,
                translatedText: item.translation,
                index: originalBubble.index
            )
        }

        let detectedTerms = decoded
            .compactMap { $0.detectedTerms }
            .flatMap { $0 }
            .map { GlossaryTerm(id: UUID().uuidString, sourceTerm: $0.source, targetTerm: $0.target, autoDetected: true) }

        return (translatedBubbles, detectedTerms)
    }

    static func fallbackParse(_ responseText: String, bubbles: [BubbleCluster]) -> ([TranslatedBubble], [GlossaryTerm]) {
        let lines = responseText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        let translatedBubbles = zip(lines, bubbles).map { (line, bubble) in
            TranslatedBubble(
                bubble: bubble,
                translatedText: line.trimmingCharacters(in: .whitespaces),
                index: bubble.index
            )
        }
        return (translatedBubbles, [])
    }
}
