import Foundation

enum GlossarySubstitution {
    // Single left-to-right scan: at each position wrap the longest matching
    // term and continue after it. Replacing term-by-term over the whole text
    // would re-match a term that is a substring of an already-wrapped longer
    // term, producing nested tags that survive revert as fragments.
    private static func wrapTerms(
        in text: String,
        terms: [GlossaryTerm],
        wrap: (String) -> String
    ) -> String {
        let sources = terms.map(\.sourceTerm)
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        guard !sources.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex
        while cursor < text.endIndex {
            var earliest: Range<String.Index>?
            for source in sources {
                guard let range = text.range(of: source, range: cursor..<text.endIndex) else { continue }
                // `sources` is longest-first, so on a tied start the longer term wins.
                if earliest == nil || range.lowerBound < earliest!.lowerBound {
                    earliest = range
                }
            }
            guard let match = earliest else { break }
            result += text[cursor..<match.lowerBound]
            result += wrap(String(text[match]))
            cursor = match.upperBound
        }
        result += text[cursor...]
        return result
    }

    // MARK: - DeepL: XML tag handling

    /// Wrap glossary source terms in <x> tags for DeepL's ignore_tags feature.
    /// DeepL preserves the tag content verbatim when tag_handling=xml and ignore_tags=x.
    static func applyXML(
        to text: String,
        terms: [GlossaryTerm]
    ) -> String {
        wrapTerms(in: text, terms: terms) { "<x>\($0)</x>" }
    }

    /// After DeepL translation, replace <x>SOURCE</x> with the target term.
    static func revertXML(_ text: String, terms: [GlossaryTerm]) -> String {
        var result = text
        for term in terms {
            let pattern = "<x>\(NSRegularExpression.escapedPattern(for: term.sourceTerm))</x>"
            result = result.replacingOccurrences(
                of: pattern,
                with: term.targetTerm,
                options: .regularExpression
            )
        }
        return result
    }

    // MARK: - Google: HTML translate="no"

    /// Wrap glossary source terms in <span translate="no"> for Google Translate.
    /// Google preserves these spans when format=html.
    static func applyHTML(
        to text: String,
        terms: [GlossaryTerm]
    ) -> String {
        wrapTerms(in: text, terms: terms) { "<span translate=\"no\">\($0)</span>" }
    }

    /// After Google translation, replace <span translate="no">SOURCE</span> with the target term.
    static func revertHTML(_ text: String, terms: [GlossaryTerm]) -> String {
        var result = text
        for term in terms {
            let pattern = "<span translate=\"no\">\(NSRegularExpression.escapedPattern(for: term.sourceTerm))</span>"
            result = result.replacingOccurrences(
                of: pattern,
                with: term.targetTerm,
                options: .regularExpression
            )
        }
        return result
    }
}
