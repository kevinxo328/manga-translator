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
        - Echo back the "index" field exactly as given — do not change the index values.

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

        The "index" field must match exactly the index value from the input — do not change it.
        The "detected_terms" field is optional — include it only in the FIRST element of the array, listing any NEW proper nouns (character names, place names, technique names) found in this page that are NOT already in the glossary above.
        Do not include any other text outside the JSON array.
        """

        return prompt
    }

    static func userPrompt(bubbles: [BubbleCluster]) -> String {
        let payload: [[String: Any]] = bubbles.map { bubble in
            [
                "index": bubble.index,
                "x": Int(bubble.boundingBox.origin.x),
                "y": Int(bubble.boundingBox.origin.y),
                "width": Int(bubble.boundingBox.width),
                "height": Int(bubble.boundingBox.height),
                "text": bubble.text
            ]
        }

        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
            let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        return json
    }

    // Batch system prompt: shares rule text with the per-page prompt but uses a dedicated
    // multi-page response instruction. The recent-context block, when present, applies once
    // to the whole batch (covering pages whose index is strictly less than the batch's first page).
    static func multiPageSystemPrompt(
        from source: Language,
        to target: Language,
        context: TranslationContext = .empty
    ) -> String {
        var prompt = """
        You are an expert manga translator. Translate speech bubble text from \(source.displayName) to \(target.displayName).

        Rules:
        - Translate naturally as a manga reader would expect, preserving tone, emotion, and character voice.
        - Maintain consistency in how characters address each other across pages in the same request.
        - Keep onomatopoeia translations natural in the target language.
        - Echo back the "index" field exactly as given for each bubble — do not change the index values.
        - Echo back the "page_id" field exactly as given for each page — do not change or omit any page_id.

        You will receive a JSON object with a "pages" array. Each page contains a stable "page_id" and a "bubbles" array with positions (x, y coordinates where origin is top-left).
        Manga reads right-to-left, top-to-bottom. Pages are listed in reading order.
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


        Respond with ONLY a JSON object in this exact format:
        {
          "pages": [
            {
              "page_id": "<echo of input page_id>",
              "bubbles": [
                {"index": 0, "translation": "translated text here"}
              ],
              "detected_terms": [
                {"source": "original proper noun", "target": "translated proper noun"}
              ]
            }
          ]
        }

        Every requested page_id MUST appear exactly once in the response "pages" array.
        Do not invent page_ids that were not requested.
        Each bubble's "index" must match exactly the index value from the input.
        The per-page "detected_terms" field is optional — include any NEW proper nouns (character names, place names, technique names) found in that page that are NOT already in the glossary above.
        Do not include any text outside the JSON object.
        """

        return prompt
    }

    // Batch user prompt: dedicated multi-page request body. Pages are listed in the order they
    // appear in `pageInputs`; the response contract requires every page_id to round-trip.
    static func multiPageUserPrompt(pageInputs: [BatchPageInput]) -> String {
        let payload: [String: Any] = [
            "pages": pageInputs.map { input -> [String: Any] in
                let bubbles: [[String: Any]] = input.bubbles.map { bubble in
                    [
                        "index": bubble.index,
                        "x": Int(bubble.boundingBox.origin.x),
                        "y": Int(bubble.boundingBox.origin.y),
                        "width": Int(bubble.boundingBox.width),
                        "height": Int(bubble.boundingBox.height),
                        "text": bubble.text
                    ]
                }
                return [
                    "page_id": input.pageId,
                    "bubbles": bubbles
                ]
            }
        ]

        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{\"pages\":[]}"
        }

        return json
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

struct LLMMultiPageBubble: Codable {
    let index: Int
    let translation: String
}

struct LLMMultiPagePage: Codable {
    let pageId: String
    let bubbles: [LLMMultiPageBubble]
    let detectedTerms: [LLMDetectedTerm]?

    enum CodingKeys: String, CodingKey {
        case pageId = "page_id"
        case bubbles
        case detectedTerms = "detected_terms"
    }
}

struct LLMMultiPageResponse: Codable {
    let pages: [LLMMultiPagePage]
}

enum LLMResponseParser {
    enum MultiPageParseError: Error, Equatable {
        case missingPage(id: String)
        case unexpectedPage(id: String)
        case duplicatePage(id: String)
        case missingBubble(pageId: String, index: Int)
        case unexpectedBubble(pageId: String, index: Int)
        case malformedJSON
    }

    // Parses a multi-page batch response and returns outputs in the order of `pageInputs`.
    // Throws MultiPageParseError when the response is malformed, missing a requested page,
    // contains an unexpected page, repeats a page id, or omits/duplicates/invents a bubble
    // index inside a page; the scheduler treats any of these as a retry/fallback trigger.
    static func parseMultiPage(_ responseText: String, pageInputs: [BatchPageInput]) throws -> [BatchPageOutput] {
        let cleaned = responseText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw MultiPageParseError.malformedJSON
        }

        let decoded: LLMMultiPageResponse
        do {
            decoded = try JSONDecoder().decode(LLMMultiPageResponse.self, from: data)
        } catch {
            throw MultiPageParseError.malformedJSON
        }

        let requestedIds = pageInputs.map { $0.pageId }
        let requestedIdSet = Set(requestedIds)

        // Detect duplicate page ids manually so a repeated id throws a fallback-triggering
        // error instead of trapping inside Dictionary(uniqueKeysWithValues:).
        var responseById: [String: LLMMultiPagePage] = [:]
        responseById.reserveCapacity(decoded.pages.count)
        for page in decoded.pages {
            if responseById[page.pageId] != nil {
                throw MultiPageParseError.duplicatePage(id: page.pageId)
            }
            responseById[page.pageId] = page
        }

        // Strict validation: every requested id must appear, and no extra ids allowed.
        for page in decoded.pages where !requestedIdSet.contains(page.pageId) {
            throw MultiPageParseError.unexpectedPage(id: page.pageId)
        }
        for id in requestedIds where responseById[id] == nil {
            throw MultiPageParseError.missingPage(id: id)
        }

        let inputById = Dictionary(uniqueKeysWithValues: pageInputs.map { ($0.pageId, $0) })

        return try requestedIds.map { id -> BatchPageOutput in
            let page = responseById[id]!
            let input = inputById[id]!
            let bubbleByIndex = Dictionary(uniqueKeysWithValues: input.bubbles.map { ($0.index, $0) })

            // Per-page bubble validation: reject extras, duplicates, and missing indexes so a
            // partial bubble response triggers fallback instead of silently dropping bubbles.
            var seenIndexes = Set<Int>()
            for item in page.bubbles {
                if bubbleByIndex[item.index] == nil {
                    throw MultiPageParseError.unexpectedBubble(pageId: id, index: item.index)
                }
                if !seenIndexes.insert(item.index).inserted {
                    throw MultiPageParseError.unexpectedBubble(pageId: id, index: item.index)
                }
            }
            for requestedBubble in input.bubbles where !seenIndexes.contains(requestedBubble.index) {
                throw MultiPageParseError.missingBubble(pageId: id, index: requestedBubble.index)
            }

            let translated = page.bubbles.compactMap { item -> TranslatedBubble? in
                guard let originalBubble = bubbleByIndex[item.index] else { return nil }
                return TranslatedBubble(
                    bubble: originalBubble,
                    translatedText: item.translation,
                    index: originalBubble.index
                )
            }
            let detected = (page.detectedTerms ?? []).map {
                GlossaryTerm(id: UUID().uuidString, sourceTerm: $0.source, targetTerm: $0.target, autoDetected: true)
            }
            return BatchPageOutput(pageId: id, bubbles: translated, detectedTerms: detected)
        }
    }

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

        let bubbleByIndex = Dictionary(uniqueKeysWithValues: bubbles.map { ($0.index, $0) })
        let bubbles = decoded.compactMap { item -> TranslatedBubble? in
            guard let originalBubble = bubbleByIndex[item.index] else { return nil }
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

        return (bubbles, detectedTerms)
    }

    static func fallbackParse(_ responseText: String, bubbles: [BubbleCluster]) -> ([TranslatedBubble], [GlossaryTerm]) {
        let lines = responseText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        let translatedBubbles = zip(lines, bubbles).enumerated().map { index, pair in
            TranslatedBubble(
                bubble: pair.1,
                translatedText: pair.0.trimmingCharacters(in: .whitespaces),
                index: index
            )
        }
        return (translatedBubbles, [])
    }
}
