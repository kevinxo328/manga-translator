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
// The text detector produces bounding boxes in pixel space,
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

// Inverse of `scaledBubbleRect` used by Edit Mode gestures: maps a single
// display-coordinate point back to image-pixel coordinates so newly drawn,
// moved, and resized bubbles persist their geometry in the same coordinate
// system as the OCR pipeline. Returns nil if `displaySize` has zero extent.
func imagePoint(
    fromDisplay point: CGPoint,
    imagePixelSize: CGSize,
    displaySize: CGSize,
    offset: CGPoint
) -> CGPoint? {
    guard displaySize.width > 0, displaySize.height > 0 else { return nil }
    let scaleX = imagePixelSize.width / displaySize.width
    let scaleY = imagePixelSize.height / displaySize.height
    return CGPoint(
        x: (point.x - offset.x) * scaleX,
        y: (point.y - offset.y) * scaleY
    )
}

// Clamps `rect` to the image's pixel bounds, preserving width/height when
// possible and shrinking when the rect would otherwise overflow. Used by
// Draw / Move / Resize gestures to enforce the "no overflow" rule.
func clampToImage(_ rect: CGRect, pixelSize: CGSize) -> CGRect {
    var clamped = rect
    if clamped.size.width > pixelSize.width { clamped.size.width = pixelSize.width }
    if clamped.size.height > pixelSize.height { clamped.size.height = pixelSize.height }
    if clamped.origin.x < 0 { clamped.origin.x = 0 }
    if clamped.origin.y < 0 { clamped.origin.y = 0 }
    if clamped.maxX > pixelSize.width { clamped.origin.x = pixelSize.width - clamped.size.width }
    if clamped.maxY > pixelSize.height { clamped.origin.y = pixelSize.height - clamped.size.height }
    return clamped
}

// Eight resize handles per selected bubble, named by the edge they pull.
// Corners pull two edges at once; edge handles pull a single edge.
enum ResizeHandle: Hashable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case top
    case bottom
    case left
    case right
}

// Minimum drawn-bubble dimensions in image pixels — spec requirement; below
// this threshold the Draw gesture is discarded without recording an undo.
let editModeMinimumBubblePixelSize: CGFloat = 20

struct ImageViewer: View {
    let page: MangaPage
    let translations: [TranslatedBubble]
    @Binding var highlightedBubbleId: UUID?

    // Edit Mode plumbing. All optional / defaulted so existing call sites
    // (no edit mode) keep working unchanged. When `isEditing` is false the
    // view behaves identically to the pre-edit-mode version: no overlay,
    // no edit gestures, no callbacks invoked. See
    // `openspec/changes/manual-bubble-editing/specs/image-viewer/spec.md`.
    var isEditing: Bool = false
    var editSession: EditSession? = nil
    // Forwarded to `TranslationViewModel.applyEditAction(_:)`. The view
    // never mutates the working copy directly — every gesture result flows
    // through this callback so the nearest-neighbour insertion path and the
    // undo stack stay authoritative.
    var onEditAction: ((EditAction) -> Void)? = nil
    // Bound back into `EditSession.selectedBubbleIds` so Esc / Cmd+A /
    // arrow-key handlers in ContentView can read and mutate the same set
    // the canvas is showing.
    var onSelectionChange: ((Set<UUID>) -> Void)? = nil
    // Reports whether a Draw / Move / Resize gesture is in progress. ContentView
    // uses this to make Esc routing single-source: in-flight gestures consume
    // Esc and prevent the parent cascade from clearing selection or cancelling.
    var onGestureInFlightChange: ((Bool) -> Void)? = nil

    @State private var dragState: EditDragState = .idle

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
            let offset = CGPoint(x: offsetX, y: offsetY)

            ZStack(alignment: .topLeading) {
                // Layer 0: the manga page image.
                if let image {
                    if isEditing {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: displaySize.width, height: displaySize.height)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                            .allowsHitTesting(false)
                            .accessibilityLabel("Manga page image")
                    } else {
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
                }

                // Layer 1: edit-mode visual overlays (no hit-testing — every
                // click passes through to the transparent gesture surface).
                if isEditing, let editSession {
                    let workingOrdered = editSession.workingBubbles.sorted { $0.index < $1.index }
                    let selection = editSession.selectedBubbleIds
                    let deleted = editSession.deletedBubbleIds

                    ForEach(Array(workingOrdered.enumerated()), id: \.element.id) { position, bubble in
                        let rect = scaledBubbleRect(
                            previewBoundingBox(for: bubble) ?? bubble.boundingBox,
                            imagePixelSize: originalSize,
                            displaySize: displaySize,
                            offset: offset
                        )
                        EditBubbleOverlay(
                            rect: rect,
                            index: position,
                            isSelected: selection.contains(bubble.id),
                            isManual: bubble.isManual,
                            isPendingDelete: deleted.contains(bubble.id)
                        )
                    }

                    if case .drawing(let start, let current) = dragState {
                        let marqueeRect = CGRect(
                            x: min(start.x, current.x),
                            y: min(start.y, current.y),
                            width: abs(current.x - start.x),
                            height: abs(current.y - start.y)
                        )
                        Rectangle()
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .frame(width: marqueeRect.width, height: marqueeRect.height)
                            .position(x: marqueeRect.midX, y: marqueeRect.midY)
                            .allowsHitTesting(false)
                    }
                } else {
                    ForEach(sortedTranslations, id: \.element.id) { position, bubble in
                        let rect = scaledBubbleRect(
                            bubble.bubble.boundingBox,
                            imagePixelSize: originalSize,
                            displaySize: displaySize,
                            offset: offset
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

                // Layer 2: edit-mode gesture surface. This is intentionally
                // the topmost child so AppKit/SwiftUI hit routing cannot be
                // stolen by the image or overlay views. The content shape,
                // not a visible fill, defines the interactive canvas.
                if isEditing, let session = editSession {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { value in
                                    handleGestureChange(
                                        value: value,
                                        session: session,
                                        pixelSize: originalSize,
                                        displaySize: displaySize,
                                        offset: offset
                                    )
                                }
                                .onEnded { value in
                                    handleGestureEnd(
                                        value: value,
                                        session: session,
                                        pixelSize: originalSize,
                                        displaySize: displaySize,
                                        offset: offset
                                    )
                                }
                        )
                        .onExitCommand {
                            // Esc cascade level 1 — abort an in-flight
                            // gesture without recording an EditAction.
                            // Levels 2 + 3 live in ContentView.
                            if case .idle = dragState { return }
                            dragState = .idle
                            onGestureInFlightChange?(false)
                        }
                }
            }
        }
    }

    // MARK: - Gesture state machine

    private func handleGestureChange(
        value: DragGesture.Value,
        session: EditSession,
        pixelSize: CGSize,
        displaySize: CGSize,
        offset: CGPoint
    ) {
        let location = value.location

        switch dragState {
        case .idle:
            // Hit-test the start point — handles take priority over bodies,
            // bodies over empty canvas. See `image-viewer/spec.md`.
            let start = value.startLocation
            if let hit = hitTestHandle(at: start, session: session, pixelSize: pixelSize, displaySize: displaySize, offset: offset) {
                dragState = .resizing(
                    bubbleId: hit.bubbleId,
                    originalRect: hit.originalRect,
                    currentRect: hit.originalRect,
                    handle: hit.handle
                )
                onGestureInFlightChange?(true)
            } else if let hit = hitTestBody(at: start, session: session, pixelSize: pixelSize, displaySize: displaySize, offset: offset) {
                dragState = .moving(
                    bubbleId: hit.bubbleId,
                    originalRect: hit.originalRect,
                    currentRect: hit.originalRect
                )
                onGestureInFlightChange?(true)
            } else {
                dragState = .drawing(start: start, current: location)
                onGestureInFlightChange?(true)
            }

        case .drawing(let start, _):
            dragState = .drawing(start: start, current: location)

        case .moving(let bubbleId, let originalRect, _):
            guard let moved = movedRect(
                originalRect,
                from: value.startLocation,
                to: location,
                pixelSize: pixelSize,
                displaySize: displaySize,
                offset: offset
            ) else { return }
            dragState = .moving(bubbleId: bubbleId, originalRect: originalRect, currentRect: moved)

        case .resizing(let bubbleId, let originalRect, _, let handle):
            guard let resized = resizedRect(
                originalRect,
                handle: handle,
                from: value.startLocation,
                to: location,
                pixelSize: pixelSize,
                displaySize: displaySize,
                offset: offset
            ) else { return }
            dragState = .resizing(
                bubbleId: bubbleId,
                originalRect: originalRect,
                currentRect: resized,
                handle: handle
            )
        }
    }

    private func handleGestureEnd(
        value: DragGesture.Value,
        session: EditSession,
        pixelSize: CGSize,
        displaySize: CGSize,
        offset: CGPoint
    ) {
        defer {
            dragState = .idle
            onGestureInFlightChange?(false)
        }

        let endDisplay = value.location
        let translation = value.translation

        switch dragState {
        case .drawing(let start, _):
            // Convert both endpoints to image coords, derive the rect, then
            // discard if below the 20×20 minimum. A zero-distance empty-canvas
            // gesture is a click, not a draw attempt; clear selection per the
            // selection model before returning.
            if isEffectiveClick(translation) {
                onSelectionChange?([])
                return
            }
            guard
                let startImage = imagePoint(fromDisplay: start, imagePixelSize: pixelSize, displaySize: displaySize, offset: offset),
                let endImage = imagePoint(fromDisplay: endDisplay, imagePixelSize: pixelSize, displaySize: displaySize, offset: offset)
            else { return }
            var rect = CGRect(
                x: min(startImage.x, endImage.x),
                y: min(startImage.y, endImage.y),
                width: abs(endImage.x - startImage.x),
                height: abs(endImage.y - startImage.y)
            )
            rect = clampToImage(rect, pixelSize: pixelSize)
            if rect.width < editModeMinimumBubblePixelSize || rect.height < editModeMinimumBubblePixelSize {
                return
            }
            let bubble = BubbleCluster(
                boundingBox: rect,
                text: "",
                observations: [],
                isManual: true
            )
            onEditAction?(.add(bubble))
            onSelectionChange?([bubble.id])

        case .moving(let bubbleId, let originalRect, let currentRect):
            // If the gesture was effectively a click (zero distance), update
            // selection per `image-viewer/spec.md` instead of recording a move.
            if isEffectiveClick(translation) {
                applyClickSelection(bubbleId: bubbleId, session: session)
                return
            }
            let moved = movedRect(
                originalRect,
                from: value.startLocation,
                to: endDisplay,
                pixelSize: pixelSize,
                displaySize: displaySize,
                offset: offset
            ) ?? currentRect
            if moved == originalRect { return }
            onEditAction?(.move(id: bubbleId, from: originalRect, to: moved))
            onSelectionChange?([bubbleId])

        case .resizing(let bubbleId, let originalRect, let currentRect, let handle):
            let resized = resizedRect(
                originalRect,
                handle: handle,
                from: value.startLocation,
                to: endDisplay,
                pixelSize: pixelSize,
                displaySize: displaySize,
                offset: offset
            ) ?? currentRect
            if resized == originalRect { return }
            onEditAction?(.resize(id: bubbleId, from: originalRect, to: resized))
            onSelectionChange?([bubbleId])

        case .idle:
            // A zero-distance gesture that never moved past .idle means the
            // user clicked on empty canvas (background hit, no bubble body).
            // Per `image-viewer/spec.md`: clear selection.
            onSelectionChange?([])
        }
    }

    private func movedRect(
        _ originalRect: CGRect,
        from startDisplay: CGPoint,
        to currentDisplay: CGPoint,
        pixelSize: CGSize,
        displaySize: CGSize,
        offset: CGPoint
    ) -> CGRect? {
        guard
            let startImage = imagePoint(fromDisplay: startDisplay, imagePixelSize: pixelSize, displaySize: displaySize, offset: offset),
            let currentImage = imagePoint(fromDisplay: currentDisplay, imagePixelSize: pixelSize, displaySize: displaySize, offset: offset)
        else { return nil }
        let dx = currentImage.x - startImage.x
        let dy = currentImage.y - startImage.y
        var moved = originalRect
        moved.origin.x += dx
        moved.origin.y += dy
        return clampToImage(moved, pixelSize: pixelSize)
    }

    private func resizedRect(
        _ originalRect: CGRect,
        handle: ResizeHandle,
        from startDisplay: CGPoint,
        to currentDisplay: CGPoint,
        pixelSize: CGSize,
        displaySize: CGSize,
        offset: CGPoint
    ) -> CGRect? {
        guard
            let startImage = imagePoint(fromDisplay: startDisplay, imagePixelSize: pixelSize, displaySize: displaySize, offset: offset),
            let currentImage = imagePoint(fromDisplay: currentDisplay, imagePixelSize: pixelSize, displaySize: displaySize, offset: offset)
        else { return nil }
        let dx = currentImage.x - startImage.x
        let dy = currentImage.y - startImage.y
        return clampToImage(
            resize(originalRect, handle: handle, dx: dx, dy: dy),
            pixelSize: pixelSize
        )
    }

    private func previewBoundingBox(for bubble: BubbleCluster) -> CGRect? {
        switch dragState {
        case .moving(let bubbleId, _, let currentRect),
             .resizing(let bubbleId, _, let currentRect, _):
            return bubbleId == bubble.id ? currentRect : nil
        case .idle, .drawing:
            return nil
        }
    }

    // MARK: - Hit tests

    private struct HandleHit {
        let bubbleId: UUID
        let originalRect: CGRect
        let handle: ResizeHandle
    }

    private struct BodyHit {
        let bubbleId: UUID
        let originalRect: CGRect
    }

    // Handle hit-test zones: 16×16 pt corners, 16×8 pt top/bottom edges,
    // 8×16 pt left/right edges — constant point sizes regardless of zoom
    // per `image-viewer/spec.md`.
    private func hitTestHandle(
        at point: CGPoint,
        session: EditSession,
        pixelSize: CGSize,
        displaySize: CGSize,
        offset: CGPoint
    ) -> HandleHit? {
        // Only selected bubbles have handles. If the spec is later relaxed
        // to surface handles on hover, this is the place to extend.
        for bubble in session.workingBubbles where session.selectedBubbleIds.contains(bubble.id) {
            let rect = scaledBubbleRect(
                bubble.boundingBox,
                imagePixelSize: pixelSize,
                displaySize: displaySize,
                offset: offset
            )
            let candidates: [(ResizeHandle, CGRect)] = [
                (.topLeft, CGRect(x: rect.minX - 8, y: rect.minY - 8, width: 16, height: 16)),
                (.topRight, CGRect(x: rect.maxX - 8, y: rect.minY - 8, width: 16, height: 16)),
                (.bottomLeft, CGRect(x: rect.minX - 8, y: rect.maxY - 8, width: 16, height: 16)),
                (.bottomRight, CGRect(x: rect.maxX - 8, y: rect.maxY - 8, width: 16, height: 16)),
                (.top, CGRect(x: rect.midX - 8, y: rect.minY - 4, width: 16, height: 8)),
                (.bottom, CGRect(x: rect.midX - 8, y: rect.maxY - 4, width: 16, height: 8)),
                (.left, CGRect(x: rect.minX - 4, y: rect.midY - 8, width: 8, height: 16)),
                (.right, CGRect(x: rect.maxX - 4, y: rect.midY - 8, width: 8, height: 16))
            ]
            for (handle, zone) in candidates {
                if zone.contains(point) {
                    return HandleHit(bubbleId: bubble.id, originalRect: bubble.boundingBox, handle: handle)
                }
            }
        }
        return nil
    }

    private func hitTestBody(
        at point: CGPoint,
        session: EditSession,
        pixelSize: CGSize,
        displaySize: CGSize,
        offset: CGPoint
    ) -> BodyHit? {
        // Iterate in reverse-index order so a bubble drawn on top wins the
        // hit-test when boxes overlap.
        for bubble in session.workingBubbles.sorted(by: { $0.index > $1.index }) {
            let rect = scaledBubbleRect(
                bubble.boundingBox,
                imagePixelSize: pixelSize,
                displaySize: displaySize,
                offset: offset
            )
            if rect.contains(point) {
                return BodyHit(bubbleId: bubble.id, originalRect: bubble.boundingBox)
            }
        }
        return nil
    }

    // MARK: - Resize geometry

    private func resize(_ rect: CGRect, handle: ResizeHandle, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        switch handle {
        case .topLeft:     minX += dx; minY += dy
        case .topRight:    maxX += dx; minY += dy
        case .bottomLeft:  minX += dx; maxY += dy
        case .bottomRight: maxX += dx; maxY += dy
        case .top:         minY += dy
        case .bottom:      maxY += dy
        case .left:        minX += dx
        case .right:       maxX += dx
        }

        // Enforce 20×20 minimum by clamping the moving edge.
        if maxX - minX < editModeMinimumBubblePixelSize {
            switch handle {
            case .topLeft, .bottomLeft, .left:
                minX = maxX - editModeMinimumBubblePixelSize
            default:
                maxX = minX + editModeMinimumBubblePixelSize
            }
        }
        if maxY - minY < editModeMinimumBubblePixelSize {
            switch handle {
            case .topLeft, .topRight, .top:
                minY = maxY - editModeMinimumBubblePixelSize
            default:
                maxY = minY + editModeMinimumBubblePixelSize
            }
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Click vs. drag

    // Treats sub-3-pt translations as clicks — accommodates the tiny
    // jitter that even a mouse-button-down produces without movement.
    private func isEffectiveClick(_ translation: CGSize) -> Bool {
        abs(translation.width) < 3 && abs(translation.height) < 3
    }

    private func applyClickSelection(bubbleId: UUID, session: EditSession) {
        // Modifier state is read from NSEvent because SwiftUI's DragGesture
        // value doesn't carry it. See `manual-bubble-editing/spec.md`:
        // Shift+click adds, Cmd+click toggles, plain click replaces.
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) {
            var next = session.selectedBubbleIds
            next.insert(bubbleId)
            onSelectionChange?(next)
        } else if modifiers.contains(.command) {
            var next = session.selectedBubbleIds
            if next.contains(bubbleId) { next.remove(bubbleId) } else { next.insert(bubbleId) }
            onSelectionChange?(next)
        } else {
            onSelectionChange?([bubbleId])
        }
    }
}

// Internal state of the unified DragGesture state machine. `idle` is the
// resting state; one of the three active states is entered on `onChanged`
// based on a hit-test of the gesture's first event.
private enum EditDragState: Equatable {
    case idle
    case drawing(start: CGPoint, current: CGPoint)
    case moving(bubbleId: UUID, originalRect: CGRect, currentRect: CGRect)
    case resizing(bubbleId: UUID, originalRect: CGRect, currentRect: CGRect, handle: ResizeHandle)
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
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .position(x: rect.midX, y: rect.midY)
    }
}

// Edit-mode bubble overlay: uses the normal bubble colour vocabulary with
// thicker selected borders and per-edge resize handles when selected.
struct EditBubbleOverlay: View {
    let rect: CGRect
    let index: Int
    let isSelected: Bool
    let isManual: Bool
    let isPendingDelete: Bool

    private var borderColor: Color {
        if isPendingDelete { return .red }
        if isSelected { return .accentColor }
        return Color.secondary.opacity(0.5)
    }

    private var fillColor: Color {
        if isPendingDelete { return Color.red.opacity(0.20) }
        if isSelected { return Color.accentColor.opacity(0.18) }
        return Color.black.opacity(0.05)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Keep unselected edit boxes visually aligned with the normal
            // bubble overlay so Edit Mode stays readable without adding
            // extra colour categories for manual-vs-auto state.
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    borderColor,
                    lineWidth: isSelected ? 3 : 1.75
                )
            .frame(width: rect.width, height: rect.height)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(fillColor)
                    .frame(width: rect.width, height: rect.height)
            )

            // Index badge — same visual language as viewing mode so the
            // user's mental model of order carries over.
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(borderColor)
                )
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                .offset(x: -12, y: -12)

            // Handles for selected bubbles only. Sizes match the spec —
            // 16×16 pt corner squares, 16×8 pt top/bottom edge handles,
            // 8×16 pt left/right edge handles. White fill + accent-colour
            // border is the macOS editor-standard look (Pages / Keynote /
            // Sketch use the same vocabulary).
            if isSelected {
                ForEach(ResizeHandle.allCorners, id: \.self) { handle in
                    handleChip(size: CGSize(width: 16, height: 16))
                        .position(handle.cornerPosition(in: rect))
                }
                ForEach(ResizeHandle.allEdges, id: \.self) { handle in
                    handleChip(size: handle.edgeSize)
                        .position(handle.edgePosition(in: rect))
                }
            }
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func handleChip(size: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white)
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.accentColor, lineWidth: 1.5)
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: .black.opacity(0.15), radius: 1.5, x: 0, y: 1)
    }
}

extension ResizeHandle {
    static let allCorners: [ResizeHandle] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    static let allEdges: [ResizeHandle] = [.top, .bottom, .left, .right]

    fileprivate var edgeSize: CGSize {
        switch self {
        case .top, .bottom: return CGSize(width: 16, height: 8)
        case .left, .right: return CGSize(width: 8, height: 16)
        default: return .zero
        }
    }

    fileprivate func cornerPosition(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .topRight: return CGPoint(x: rect.width, y: 0)
        case .bottomLeft: return CGPoint(x: 0, y: rect.height)
        case .bottomRight: return CGPoint(x: rect.width, y: rect.height)
        default: return .zero
        }
    }

    fileprivate func edgePosition(in rect: CGRect) -> CGPoint {
        switch self {
        case .top: return CGPoint(x: rect.width / 2, y: 0)
        case .bottom: return CGPoint(x: rect.width / 2, y: rect.height)
        case .left: return CGPoint(x: 0, y: rect.height / 2)
        case .right: return CGPoint(x: rect.width, y: rect.height / 2)
        default: return .zero
        }
    }
}

#Preview("EditBubbleOverlay matrix") {
    let demoRect = CGRect(x: 0, y: 0, width: 140, height: 90)
    return VStack(spacing: 24) {
        HStack(spacing: 24) {
            EditBubbleOverlay(rect: demoRect, index: 0, isSelected: false, isManual: false, isPendingDelete: false)
                .frame(width: demoRect.width, height: demoRect.height)
            EditBubbleOverlay(rect: demoRect, index: 1, isSelected: true, isManual: false, isPendingDelete: false)
                .frame(width: demoRect.width, height: demoRect.height)
        }
        HStack(spacing: 24) {
            EditBubbleOverlay(rect: demoRect, index: 2, isSelected: false, isManual: true, isPendingDelete: false)
                .frame(width: demoRect.width, height: demoRect.height)
            EditBubbleOverlay(rect: demoRect, index: 3, isSelected: true, isManual: true, isPendingDelete: true)
                .frame(width: demoRect.width, height: demoRect.height)
        }
    }
    .padding(40)
    .background(Color(white: 0.95))
}
