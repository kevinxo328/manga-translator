import Foundation

enum GlossarySubstitution {
    /// Returns the terms whose source occurs in at least one of `texts`,
    /// preserving the original term order. The glossary accumulates
    /// auto-detected terms across a whole series; prompts must only carry
    /// the subset relevant to the texts being translated. Japanese has no
    /// word boundaries, so substring containment is the criterion — the
    /// same matching `wrapTerms` uses.
    static func relevantTerms(_ terms: [GlossaryTerm], in texts: [String]) -> [GlossaryTerm] {
        guard !terms.isEmpty else { return [] }
        let combined = texts.joined(separator: "\n")
        return terms.filter { combined.contains($0.sourceTerm) }
    }

    // Single left-to-right scan: at each position wrap the longest matching
    // term and continue after it. Replacing term-by-term over the whole text
    // would re-match a term that is a substring of an already-wrapped longer
    // term, producing nested tags that survive revert as fragments.
    private static func wrapTerms(
        in text: String,
        terms: [GlossaryTerm],
        wrap: (GlossaryTerm, String) -> String
    ) -> String {
        let sortedTerms = terms
            .filter { !$0.sourceTerm.isEmpty }
            .sorted { $0.sourceTerm.count > $1.sourceTerm.count }
        guard !sortedTerms.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex
        while cursor < text.endIndex {
            var earliest: (term: GlossaryTerm, range: Range<String.Index>)?
            for term in sortedTerms {
                guard let range = text.range(of: term.sourceTerm, range: cursor..<text.endIndex) else { continue }
                // `sortedTerms` is longest-first, so on a tied start the longer term wins.
                if earliest == nil || range.lowerBound < earliest!.range.lowerBound {
                    earliest = (term, range)
                }
            }
            guard let match = earliest else { break }
            result += text[cursor..<match.range.lowerBound]
            result += wrap(match.term, String(text[match.range]))
            cursor = match.range.upperBound
        }
        result += text[cursor...]
        return result
    }

    private static func attributeEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func attributeValue(_ name: String, in attributes: String) -> String? {
        let pattern = #"(?i)\b\#(NSRegularExpression.escapedPattern(for: name))\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
        guard let match = regex.firstMatch(in: attributes, range: range) else { return nil }
        for index in 1..<match.numberOfRanges {
            let captureRange = match.range(at: index)
            guard captureRange.location != NSNotFound, let range = Range(captureRange, in: attributes) else { continue }
            return attributeUnescaped(String(attributes[range]))
        }
        return nil
    }

    private static func attributeUnescaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func replaceMatches(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators],
        replacement: (NSTextCheckingResult, String) -> String?
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        var result = text
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: fullRange)
        for match in matches.reversed() {
            guard
                let matchRange = Range(match.range, in: result),
                let replacementText = replacement(match, text)
            else { continue }
            result.replaceSubrange(matchRange, with: replacementText)
        }
        return result
    }

    private static func capturedString(_ index: Int, in match: NSTextCheckingResult, source: String) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        guard range.location != NSNotFound, let stringRange = Range(range, in: source) else { return nil }
        return String(source[stringRange])
    }

    private static func targetForSource(_ source: String, terms: [GlossaryTerm]) -> String? {
        terms.first { $0.sourceTerm == source }?.targetTerm
    }

    private static func targetForID(_ id: String, terms: [GlossaryTerm]) -> String? {
        terms.first { $0.id == id }?.targetTerm
    }

    // MARK: - DeepL: XML tag handling

    /// Wrap glossary source terms in <x> tags for DeepL's ignore_tags feature.
    /// DeepL preserves the tag content verbatim when tag_handling=xml and ignore_tags=x.
    static func applyXML(
        to text: String,
        terms: [GlossaryTerm]
    ) -> String {
        wrapTerms(in: text, terms: terms) { term, source in
            "<x id=\"\(attributeEscaped(term.id))\">\(source)</x>"
        }
    }

    /// After DeepL translation, replace <x>SOURCE</x> with the target term.
    static func revertXML(_ text: String, terms: [GlossaryTerm]) -> String {
        replaceMatches(in: text, pattern: #"<x\b([^>]*)>(.*?)</x>"#) { match, source in
            guard
                let attributes = capturedString(1, in: match, source: source),
                let innerText = capturedString(2, in: match, source: source)
            else { return nil }

            if let id = attributeValue("id", in: attributes), let target = targetForID(id, terms: terms) {
                return target
            }
            if let target = targetForSource(innerText, terms: terms) {
                return target
            }
            return innerText
        }
    }

    // MARK: - Google: HTML translate="no"

    /// Wrap glossary source terms in <span translate="no"> for Google Translate.
    /// Google preserves these spans when format=html.
    static func applyHTML(
        to text: String,
        terms: [GlossaryTerm]
    ) -> String {
        wrapTerms(in: text, terms: terms) { term, source in
            "<span translate=\"no\" data-mt-glossary=\"\(attributeEscaped(term.id))\">\(source)</span>"
        }
    }

    /// After Google translation, replace <span translate="no">SOURCE</span> with the target term.
    static func revertHTML(_ text: String, terms: [GlossaryTerm]) -> String {
        replaceMatches(in: text, pattern: #"<span\b([^>]*)>(.*?)</span>"#) { match, source in
            guard
                let attributes = capturedString(1, in: match, source: source),
                let innerText = capturedString(2, in: match, source: source)
            else { return nil }

            let translateValue = attributeValue("translate", in: attributes)?.lowercased()
            let classValue = attributeValue("class", in: attributes)?.lowercased()
            let isGlossaryMarker = translateValue == "no" || classValue?.split(whereSeparator: \.isWhitespace).contains("notranslate") == true
            guard isGlossaryMarker else { return nil }

            if let id = attributeValue("data-mt-glossary", in: attributes), let target = targetForID(id, terms: terms) {
                return target
            }
            if let target = targetForSource(innerText, terms: terms) {
                return target
            }
            return innerText
        }
    }
}
