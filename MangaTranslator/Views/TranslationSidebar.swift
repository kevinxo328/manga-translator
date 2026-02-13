import SwiftUI

struct TranslationSidebar: View {
    let translations: [TranslatedBubble]
    @Binding var highlightedBubbleId: UUID?
    var pageId: UUID? = nil
    var isProcessing: Bool = false
    var onRetranslate: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Translations")
                    .font(.system(.title2, design: .rounded).bold())

                Spacer()

                if let onRetranslate {
                    Button(action: onRetranslate) {
                        if isProcessing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Re-translate", systemImage: "arrow.trianglehead.2.counterclockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isProcessing)
                    .help("Re-translate using current settings")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .zIndex(1)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        if translations.isEmpty {
                            emptyState
                        } else {
                            let sorted = translations.sorted(by: { $0.index < $1.index })
                            ForEach(Array(sorted.enumerated()), id: \.element.id) { position, bubble in
                                TranslationCard(
                                    bubble: bubble,
                                    displayNumber: position + 1,
                                    isHighlighted: highlightedBubbleId == bubble.id
                                )
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3)) {
                                        if highlightedBubbleId == bubble.id {
                                            highlightedBubbleId = nil
                                        } else {
                                            highlightedBubbleId = bubble.id
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .id(0)
                }
                .onChange(of: highlightedBubbleId) { newId in
                    guard let targetId = newId else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(targetId, anchor: .center)
                    }
                }
                .onChange(of: pageId) { _ in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(0, anchor: .top)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .frame(minWidth: 300, idealWidth: 350)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundColor(.secondary.opacity(0.5))
            Text("No translations yet")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

struct TranslationCard: View {
    let bubble: TranslatedBubble
    let displayNumber: Int
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Index Badge
            Text("\(displayNumber)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(isHighlighted ? .white : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isHighlighted ? Color.accentColor : Color.secondary.opacity(0.2))
                )

            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(bubble.translatedText)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                Text(bubble.bubble.text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(
                    color: .black.opacity(isHighlighted ? 0.15 : 0.05),
                    radius: isHighlighted ? 8 : 4,
                    x: 0,
                    y: isHighlighted ? 4 : 2
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHighlighted ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isHighlighted ? 1.02 : 1.0)
    }
}
