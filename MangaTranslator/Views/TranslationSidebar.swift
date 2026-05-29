import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Clipboard Abstraction

protocol ClipboardWriting {
    @discardableResult
    func write(_ string: String) -> Bool
}

struct NSPasteboardClipboard: ClipboardWriting {
    func write(_ string: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }
}

// Decoration applied to a TranslationCard while Edit Mode is active. See
// `openspec/changes/manual-bubble-editing/specs/manual-bubble-editing/spec.md`.
enum EditCardDecoration: Equatable {
    case unchanged
    case new
    case stale
    case pendingDelete

    // Derives the decoration from the bubble's identity-vs-snapshot status.
    // The same rule runs at commit time for OCR classification per
    // `design.md` §D3 — the source of truth is geometry-vs-snapshot, not
    // the UI dirty cache. We mirror that rule here so the badge cannot
    // drift from the commit outcome.
    static func resolve(
        bubble: TranslatedBubble,
        snapshot: [TranslatedBubble],
        deleted: Set<UUID>
    ) -> EditCardDecoration {
        if deleted.contains(bubble.bubble.id) { return .pendingDelete }
        guard let snapshotBubble = snapshot.first(where: { $0.bubble.id == bubble.bubble.id }) else {
            return .new
        }
        if snapshotBubble.bubble.boundingBox != bubble.bubble.boundingBox {
            return .stale
        }
        return .unchanged
    }
}

struct TranslationSidebar: View {
    let translations: [TranslatedBubble]
    @Binding var highlightedBubbleId: UUID?
    var pageId: UUID? = nil
    var isProcessing: Bool = false
    var onRetranslate: (() -> Void)? = nil

    // Edit Mode plumbing. All defaulted so non-edit call sites stay
    // unchanged. `editEnabled` controls the Edit button; it is true exactly
    // when the current page is `.translated` and no session is currently
    // active. `editSession` exposes the in-flight session so the sidebar
    // can show dirty decorations, route un-stage clicks, and surface
    // Done / Cancel controls. `isCommittingEditSession` is true for the
    // duration of the commit's OCR + translate work; while true the
    // Done / Cancel controls disable so the user cannot re-fire the
    // pipeline mid-flight.
    var editEnabled: Bool = false
    var editSession: EditSession? = nil
    var isCommittingEditSession: Bool = false
    var onEnterEdit: (() -> Void)? = nil
    var onCommitEdit: (() -> Void)? = nil
    var onCancelEdit: (() -> Void)? = nil
    var onApplyEditAction: ((EditAction) -> Void)? = nil
    var onSelectionChange: ((Set<UUID>) -> Void)? = nil

    // Source of truth for the in-edit list comes from EditSession when one
    // is open; outside edit mode we fall back to the committed translations.
    private var displayBubbles: [TranslatedBubble] {
        if let editSession {
            return editSession.workingBubbles.sorted { $0.index < $1.index }.map { bubble in
                if let snapshotBubble = editSession.originalSnapshot.first(where: { $0.bubble.id == bubble.id }) {
                    return TranslatedBubble(
                        bubble: bubble,
                        translatedText: snapshotBubble.translatedText,
                        index: bubble.index
                    )
                }
                return TranslatedBubble(bubble: bubble, translatedText: "", index: bubble.index)
            }
        }
        return translations.sortedByIndex
    }

    private var sortedTranslations: [(offset: Int, element: TranslatedBubble)] {
        Array(displayBubbles.enumerated())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Translations")
                    .font(.system(.title2, design: .rounded).bold())

                Spacer()

                editControls

                if let onRetranslate, editSession == nil {
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
            .background(Color(nsColor: .windowBackgroundColor))
            .zIndex(1)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        if displayBubbles.isEmpty {
                            emptyState
                        } else {
                            ForEach(sortedTranslations, id: \.element.id) { position, bubble in
                                let decoration = editDecoration(for: bubble)
                                let isCardSelected = editSession?.selectedBubbleIds.contains(bubble.bubble.id)
                                    ?? (highlightedBubbleId == bubble.id)
                                Button {
                                    if editSession != nil, decoration == .pendingDelete {
                                        // Click-to-unstage. Per
                                        // `design.md` §D2 this pushes a
                                        // NEW `.unstageDelete` action onto
                                        // the undo stack and clears redo —
                                        // it never rewrites the prior
                                        // `.delete` entry.
                                        onApplyEditAction?(.unstageDelete(bubble.bubble))
                                        return
                                    }
                                    if editSession != nil {
                                        onSelectionChange?([bubble.bubble.id])
                                        return
                                    }
                                    withAnimation(.spring(response: 0.3)) {
                                        if highlightedBubbleId == bubble.id {
                                            highlightedBubbleId = nil
                                        } else {
                                            highlightedBubbleId = bubble.id
                                        }
                                    }
                                } label: {
                                    TranslationCard(
                                        bubble: bubble,
                                        displayNumber: position + 1,
                                        isHighlighted: isCardSelected,
                                        decoration: decoration
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Bubble \(position + 1): \(bubble.translatedText)")
                                .if(editSession != nil) { view in
                                    view.onDrag {
                                        NSItemProvider(object: bubble.bubble.id.uuidString as NSString)
                                    }
                                    .onDrop(
                                        of: [UTType.plainText],
                                        delegate: ReorderDropDelegate(
                                            target: bubble.bubble.id,
                                            session: editSession,
                                            onReorder: { from, to in
                                                onApplyEditAction?(.reorder(from: from, to: to))
                                            }
                                        )
                                    )
                                }
                            }
                        }
                    }
                    .padding(16)
                    .id(0)
                }
                .onChange(of: highlightedBubbleId) { _, newId in
                    guard let targetId = newId else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(targetId, anchor: .center)
                    }
                }
                .onChange(of: pageId) { _, _ in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(0, anchor: .top)
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: ViewLayout.Sidebar.minWidth, idealWidth: ViewLayout.Sidebar.idealWidth)
    }

    @ViewBuilder
    private var editControls: some View {
        if editSession != nil {
            HStack(spacing: 6) {
                Button(action: { onCancelEdit?() }) {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(".", modifiers: .command)
                .disabled(isCommittingEditSession)
                .help("Cancel edits (⌘.)")

                Button(action: { onCommitEdit?() }) {
                    if isCommittingEditSession {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Done", systemImage: "checkmark")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isCommittingEditSession)
                .help("Commit edits and re-translate (⌘↩)")
            }
        } else if onEnterEdit != nil {
            Button(action: { onEnterEdit?() }) {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!editEnabled || isProcessing)
            .help(editEnabled ? "Edit bubbles on this page" : "Edit is available after translation completes")
        }
    }

    private func editDecoration(for bubble: TranslatedBubble) -> EditCardDecoration {
        guard let editSession else { return .unchanged }
        return EditCardDecoration.resolve(
            bubble: bubble,
            snapshot: editSession.originalSnapshot,
            deleted: editSession.deletedBubbleIds
        )
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

// Conditional view modifier so the edit-mode drag-source / drop-target
// modifiers can be applied only when an edit session is active, without
// branching the surrounding view hierarchy.
private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

// Drag-to-reorder delegate for sidebar cards. On drop, snapshots the full
// prior ordering of UUIDs and emits exactly one `.reorder(from:to:)` so
// the undo stack records the move as a single user-visible action.
private struct ReorderDropDelegate: DropDelegate {
    let target: UUID
    let session: EditSession?
    let onReorder: ([UUID], [UUID]) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let session,
              let item = info.itemProviders(for: [UTType.plainText]).first else { return false }
        item.loadObject(ofClass: NSString.self) { reading, _ in
            guard let raw = reading as? String,
                  let sourceId = UUID(uuidString: raw),
                  sourceId != target else { return }
            let ordered = session.workingBubbles.sorted { $0.index < $1.index }.map(\.id)
            guard let sourceIndex = ordered.firstIndex(of: sourceId),
                  let targetIndex = ordered.firstIndex(of: target) else { return }
            var newOrder = ordered
            newOrder.remove(at: sourceIndex)
            let insertIndex = targetIndex > sourceIndex ? targetIndex : targetIndex
            newOrder.insert(sourceId, at: insertIndex)
            Task { @MainActor in
                onReorder(ordered, newOrder)
            }
        }
        return true
    }
}

struct TranslationCard: View {
    let bubble: TranslatedBubble
    let displayNumber: Int
    let isHighlighted: Bool
    var clipboard: ClipboardWriting = NSPasteboardClipboard()
    // Edit Mode decoration. Defaults to `.unchanged` so viewing-mode call
    // sites render exactly as before.
    var decoration: EditCardDecoration = .unchanged

    private var pendingPlaceholder: String { "待處理" }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Index Badge with `+` superscript for new bubbles per spec.
            ZStack(alignment: .topTrailing) {
                Text("\(displayNumber)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(isHighlighted ? .white : .secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(isHighlighted ? Color.accentColor : Color.secondary.opacity(0.2))
                    )
                if decoration == .new {
                    Text("+")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.accentColor)
                        .offset(x: 6, y: -6)
                }
            }

            // Content
            VStack(alignment: .leading, spacing: 6) {
                translatedTextView
                originalTextView
                if decoration == .stale {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil.line")
                            .font(.system(size: 10))
                        Text("已修改")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.orange.opacity(0.18))
                    )
                    .foregroundColor(.orange)
                }
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
        .overlay(
            // Red wash + strikethrough overlay for staged-for-deletion cards.
            RoundedRectangle(cornerRadius: 12)
                .fill(decoration == .pendingDelete ? Color.red.opacity(0.18) : Color.clear)
        )
        .opacity(opacityForDecoration)
        .scaleEffect(isHighlighted ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isHighlighted)
        .contextMenu {
            Button("Copy Translation") { copyTranslation() }
            Button("Copy Original Text") { copyOriginalText() }
            Button("Copy Both") { copyBoth() }
        }
    }

    @ViewBuilder
    private var translatedTextView: some View {
        switch decoration {
        case .new:
            Text(pendingPlaceholder)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .stale:
            Text(bubble.translatedText)
                .font(.body)
                .foregroundColor(.primary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .pendingDelete:
            Text(bubble.translatedText)
                .font(.body)
                .strikethrough(true, color: .red)
                .foregroundColor(.primary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        case .unchanged:
            Text(bubble.translatedText)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var originalTextView: some View {
        switch decoration {
        case .new:
            Text(pendingPlaceholder)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        case .stale:
            Text(bubble.bubble.text)
                .font(.caption)
                .strikethrough(true, color: .secondary)
                .foregroundColor(.secondary)
                .lineLimit(2)
        case .pendingDelete:
            Text(bubble.bubble.text)
                .font(.caption)
                .strikethrough(true, color: .red)
                .foregroundColor(.secondary)
                .lineLimit(2)
        case .unchanged:
            Text(bubble.bubble.text)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
    }

    private var opacityForDecoration: Double {
        switch decoration {
        case .new: return 0.6
        case .pendingDelete: return 0.7
        case .stale, .unchanged: return 1.0
        }
    }

    func copyTranslation() {
        clipboard.write(bubble.translatedText)
    }

    func copyOriginalText() {
        clipboard.write(bubble.bubble.text)
    }

    func copyBoth() {
        clipboard.write("Original: \(bubble.bubble.text)\nTranslation: \(bubble.translatedText)")
    }
}
