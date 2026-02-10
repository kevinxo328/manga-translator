import SwiftUI

struct TranslationSidebar: View {
    let translations: [TranslatedBubble]
    @Binding var highlightedBubbleIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Translations")
                .font(.headline)
                .padding()

            if translations.isEmpty {
                Text("No translations yet")
                    .foregroundColor(.secondary)
                    .padding()
                Spacer()
            } else {
                List(translations.sorted(by: { $0.index < $1.index })) { bubble in
                    TranslationRow(
                        bubble: bubble,
                        isHighlighted: highlightedBubbleIndex == bubble.index
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        highlightedBubbleIndex = highlightedBubbleIndex == bubble.index ? nil : bubble.index
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 250, idealWidth: 300)
    }
}

struct TranslationRow: View {
    let bubble: TranslatedBubble
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(bubble.index + 1)")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange))

                Text(bubble.bubble.text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Text(bubble.translatedText)
                .font(.body)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? Color.blue.opacity(0.1) : Color.clear)
        )
    }
}
