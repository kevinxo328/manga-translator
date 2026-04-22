import SwiftUI
import AppKit

// Returns the image's actual pixel dimensions from NSBitmapImageRep.
// NSImage.size reports points (pixels × 72 / DPI), which is smaller than pixel count
// for high-DPI images (e.g. 600 DPI scans). Using pixel dimensions ensures zoom-to-fit
// works correctly and bubble overlay coordinates align with the OCR pipeline output.
func imagePixelSize(of image: NSImage) -> CGSize {
    if let rep = image.representations.first as? NSBitmapImageRep,
       rep.pixelsWide > 0, rep.pixelsHigh > 0 {
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
    return image.size
}

// Pure scale-and-offset mapping from image pixel coordinates to display coordinates.
// Both OCR pipelines (Vision and ComicTextDetector) produce bounding boxes in pixel space,
// so imagePixelSize must be used as the reference when computing overlay positions.
func scaledBubbleRect(
    _ rect: CGRect,
    imagePixelSize: CGSize,
    displaySize: CGSize,
    offset: CGPoint
) -> CGRect {
    let scaleX = displaySize.width / imagePixelSize.width
    let scaleY = displaySize.height / imagePixelSize.height
    return CGRect(
        x: rect.origin.x * scaleX + offset.x,
        y: rect.origin.y * scaleY + offset.y,
        width: rect.width * scaleX,
        height: rect.height * scaleY
    )
}

struct ImageViewer: View {
    let page: MangaPage
    let translations: [TranslatedBubble]
    @Binding var highlightedBubbleId: UUID?

    private var sortedTranslations: [(offset: Int, element: TranslatedBubble)] {
        Array(translations.sorted { $0.index < $1.index }.enumerated())
    }

    var body: some View {
        GeometryReader { geometry in
            let image = page.image
            let originalSize = image.map { imagePixelSize(of: $0) } ?? CGSize(width: 1, height: 1)
            let scale = min(
                geometry.size.width / originalSize.width,
                geometry.size.height / originalSize.height
            )
            let displaySize = CGSize(
                width: originalSize.width * scale,
                height: originalSize.height * scale
            )
            let offsetX = (geometry.size.width - displaySize.width) / 2
            let offsetY = (geometry.size.height - displaySize.height) / 2

            ZStack(alignment: .topLeading) {
                if let image {
                    Button {
                        highlightedBubbleId = nil
                    } label: {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: displaySize.width, height: displaySize.height)
                    }
                    .buttonStyle(.plain)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .accessibilityLabel("Manga page image")
                    .accessibilityHint("Tap to deselect bubble")
                }

                ForEach(sortedTranslations, id: \.element.id) { position, bubble in
                    let rect = scaledBubbleRect(
                        bubble.bubble.boundingBox,
                        imagePixelSize: originalSize,
                        displaySize: displaySize,
                        offset: CGPoint(x: offsetX, y: offsetY)
                    )

                    Button {
                        if highlightedBubbleId == bubble.id {
                            highlightedBubbleId = nil
                        } else {
                            highlightedBubbleId = bubble.id
                        }
                    } label: {
                        BubbleOverlay(
                            rect: rect,
                            index: position,
                            isHighlighted: highlightedBubbleId == bubble.id
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bubble \(position + 1)")
                }
            }
        }
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
