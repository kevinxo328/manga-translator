import SwiftUI
import AppKit

struct ImageViewer: View {
    let imageURL: URL
    let translations: [TranslatedBubble]
    @Binding var highlightedBubbleIndex: Int?
    @State private var imageSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let image = NSImage(contentsOf: imageURL)
            let originalSize = image?.size ?? CGSize(width: 1, height: 1)
            let scale = min(
                geometry.size.width / originalSize.width,
                geometry.size.height / originalSize.height,
                1.0
            )
            let displaySize = CGSize(
                width: originalSize.width * scale,
                height: originalSize.height * scale
            )
            let offsetX = (geometry.size.width - displaySize.width) / 2
            let offsetY = (geometry.size.height - displaySize.height) / 2

            ZStack(alignment: .topLeading) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: displaySize.width, height: displaySize.height)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .onTapGesture {
                            highlightedBubbleIndex = nil
                        }
                }

                ForEach(translations) { bubble in
                    let rect = scaledRect(
                        bubble.bubble.boundingBox,
                        imageSize: originalSize,
                        displaySize: displaySize,
                        offset: CGPoint(x: offsetX, y: offsetY)
                    )

                    BubbleOverlay(
                        rect: rect,
                        index: bubble.index,
                        isHighlighted: highlightedBubbleIndex == bubble.index
                    )
                    .onTapGesture {
                        if highlightedBubbleIndex == bubble.index {
                            highlightedBubbleIndex = nil
                        } else {
                            highlightedBubbleIndex = bubble.index
                        }
                    }
                }
            }
        }
    }

    private func scaledRect(
        _ rect: CGRect,
        imageSize: CGSize,
        displaySize: CGSize,
        offset: CGPoint
    ) -> CGRect {
        let scaleX = displaySize.width / imageSize.width
        let scaleY = displaySize.height / imageSize.height

        return CGRect(
            x: rect.origin.x * scaleX + offset.x,
            y: rect.origin.y * scaleY + offset.y,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
    }
}

struct BubbleOverlay: View {
    let rect: CGRect
    let index: Int
    let isHighlighted: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Bubble Highlight Box
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHighlighted ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: isHighlighted ? 3 : 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHighlighted ? Color.accentColor.opacity(0.2) : Color.black.opacity(0.05))
                )
                .frame(width: rect.width, height: rect.height)
                .shadow(color: .black.opacity(isHighlighted ? 0.3 : 0), radius: 4, x: 0, y: 2)
                .animation(.easeInOut(duration: 0.2), value: isHighlighted)

            // Index Badge
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .bold)) // Slightly smaller font for better fit
                .foregroundColor(.white)
                .padding(.horizontal, 8) // Increased from 6
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(isHighlighted ? Color.accentColor : Color.secondary)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                )
                .offset(x: -12, y: -12)
                .scaleEffect(isHighlighted ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHighlighted)
        }
        .position(x: rect.midX, y: rect.midY)
    }
}
