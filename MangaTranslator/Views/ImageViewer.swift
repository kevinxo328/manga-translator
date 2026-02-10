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
            RoundedRectangle(cornerRadius: 4)
                .stroke(isHighlighted ? Color.blue : Color.orange, lineWidth: isHighlighted ? 3 : 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.orange.opacity(isHighlighted ? 0.2 : 0.1))
                )
                .frame(width: rect.width, height: rect.height)

            Text("\(index + 1)")
                .font(.caption2.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange))
                .offset(x: -8, y: -8)
        }
        .position(x: rect.midX, y: rect.midY)
    }
}
