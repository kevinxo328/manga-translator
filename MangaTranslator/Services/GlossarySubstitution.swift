import Foundation

enum GlossarySubstitution {
    /// Replace glossary source terms in bubble texts with placeholders.
    /// Returns the modified bubbles and a mapping of placeholder → target term.
    /// Longer source terms are replaced first to avoid partial matches.
    static func apply(
        to bubbles: [BubbleCluster],
        terms: [GlossaryTerm]
    ) -> (bubbles: [BubbleCluster], mapping: [String: String]) {
        guard !terms.isEmpty else { return (bubbles, [:]) }

        // Sort longest first to avoid partial-match issues
        let sorted = terms.sorted { $0.sourceTerm.count > $1.sourceTerm.count }

        var mapping: [String: String] = [:]
        let modifiedBubbles = bubbles.map { bubble -> BubbleCluster in
            var text = bubble.text
            for (i, term) in sorted.enumerated() {
                guard text.contains(term.sourceTerm) else { continue }
                let placeholder = "⟨T\(i)⟩"
                mapping[placeholder] = term.targetTerm
                text = text.replacingOccurrences(of: term.sourceTerm, with: placeholder)
            }
            guard text != bubble.text else { return bubble }
            return BubbleCluster(
                boundingBox: bubble.boundingBox,
                text: text,
                observations: bubble.observations,
                index: bubble.index
            )
        }

        return (modifiedBubbles, mapping)
    }

    /// Replace placeholders in a translated string with target terms.
    static func revert(_ text: String, mapping: [String: String]) -> String {
        guard !mapping.isEmpty else { return text }
        var result = text
        for (placeholder, targetTerm) in mapping {
            result = result.replacingOccurrences(of: placeholder, with: targetTerm)
        }
        return result
    }
}
