import Foundation

enum GlossarySubstitution {
    // MARK: - DeepL: XML tag handling

    /// Wrap glossary source terms in <x> tags for DeepL's ignore_tags feature.
    /// DeepL preserves the tag content verbatim when tag_handling=xml and ignore_tags=x.
    static func applyXML(
        to text: String,
        terms: [GlossaryTerm]
    ) -> String {
        guard !terms.isEmpty else { return text }
        var result = text
        for term in terms.sorted(by: { $0.sourceTerm.count > $1.sourceTerm.count }) {
            guard result.contains(term.sourceTerm) else { continue }
            result = result.replacingOccurrences(
                of: term.sourceTerm,
                with: "<x>\(term.sourceTerm)</x>"
            )
        }
        return result
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
        guard !terms.isEmpty else { return text }
        var result = text
        for term in terms.sorted(by: { $0.sourceTerm.count > $1.sourceTerm.count }) {
            guard result.contains(term.sourceTerm) else { continue }
            result = result.replacingOccurrences(
                of: term.sourceTerm,
                with: "<span translate=\"no\">\(term.sourceTerm)</span>"
            )
        }
        return result
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
