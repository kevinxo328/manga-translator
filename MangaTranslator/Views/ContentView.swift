import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: TranslationViewModel
    @Environment(\.openWindow) private var openWindow

    // Stored handle for the NSEvent local monitor that catches Edit Mode
    // keys whose SwiftUI keyboardShortcut routing is focus-dependent.
    @State private var editKeyMonitor: EditKeyMonitorBox = EditKeyMonitorBox()
    @State private var editGestureInFlight = false
    @State private var showNewGlossarySheet = false
    @State private var newGlossaryName = ""
    @State private var newGlossaryNameWasEdited = false

    private var isEditing: Bool { viewModel.editSession != nil }
    private var newGlossaryValidation: GlossaryNameValidation {
        GlossaryNameValidation.validate(
            newGlossaryName,
            existingGlossaries: viewModel.glossaries,
            hasUserEdited: newGlossaryNameWasEdited
        )
    }

    // Edit button is enabled only when the current page sits in
    // `.translated` state per `manual-bubble-editing` spec — the gating
    // rule that guarantees Edit Mode opens against fully-translated content.
    private var isEditEnabledForCurrentPage: Bool {
        guard let page = viewModel.currentPage else { return false }
        if case .translated = page.state { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Image viewer
            ZStack {
                if let page = viewModel.currentPage {
                    imageContent(for: page)
                } else {
                    dropZone
                }
            }
            .frame(minWidth: ViewLayout.MainWindow.imageColumnMinWidth)

            Divider()

            // Right: Sidebar
            TranslationSidebar(
                translations: viewModel.currentTranslations,
                highlightedBubbleId: $viewModel.highlightedBubbleId,
                pageId: viewModel.currentPage?.id,
                isProcessing: viewModel.isCurrentPageProcessing,
                onRetranslate: {
                    Task { await viewModel.retranslateCurrentPage() }
                },
                editEnabled: isEditEnabledForCurrentPage,
                editSession: viewModel.editSession,
                isCommittingEditSession: viewModel.isCommittingEditSession,
                onEnterEdit: {
                    if let pageId = viewModel.currentPage?.id {
                        viewModel.openEditSession(pageId: pageId)
                    }
                },
                onCommitEdit: {
                    Task { await viewModel.commitEditSession() }
                },
                onCancelEdit: {
                    viewModel.cancelEditSession()
                },
                onApplyEditAction: { action in
                    viewModel.applyEditAction(action)
                },
                onSelectionChange: { ids in
                    viewModel.setSelection(ids)
                }
            )
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.preferences.showPathBar, let path = viewModel.sourcePath {
                pathBar(path: path)
            }
        }
        .frame(minWidth: ViewLayout.MainWindow.minWidth, minHeight: ViewLayout.MainWindow.minHeight)
        .toolbar { toolbarContent }
        .fileImporter(
            isPresented: $viewModel.showFileImporter,
            allowedContentTypes: viewModel.allowedTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let granted = url.startAccessingSecurityScopedResource()
                Task {
                    await viewModel.handleInput(url)
                    if granted { url.stopAccessingSecurityScopedResource() }
                }
            }
        }
        .sheet(isPresented: $showNewGlossarySheet) { newGlossarySheet }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .alert("Missing API Key", isPresented: $viewModel.showMissingKeyAlert) {
            Button("Open Settings") {
                viewModel.preferences.activeTabIdentifier = "apiKeys"
                openWindow(id: "settings")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please add an API key for \(viewModel.preferences.translationEngine.displayName) in Settings.")
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            ),
            presenting: viewModel.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .onPasteCommand(of: [.fileURL, .png, .tiff]) { providers in
            handlePaste(providers)
        }
        .background(KeyboardShortcutLayer(viewModel: viewModel, isEditing: isEditing, navigateBubbles: navigateBubbles))
        .background(WindowCloseInterceptor(isEditing: isEditing))
        .onAppear { installEditKeyMonitor() }
        .onDisappear { removeEditKeyMonitor() }
        .onExitCommand {
            // Esc cascade levels 2 + 3 — selection clear, then Cancel.
            // Level 1 (abort in-flight gesture) is handled inside
            // ImageViewer because the gesture state machine is local
            // to that view. See `manual-bubble-editing/spec.md` lifecycle.
            guard !editGestureInFlight else { return }
            viewModel.handleEscapeCascade()
        }
    }

    // Catches Edit Mode keys via NSEvent's local monitor rather than a
    // focusable SwiftUI surface. The focusable route intercepted mouse
    // events meant for ImageViewer gestures and drew a phantom focus box.
    // Arrow keys also need to work when focus sits in the sidebar.
    private func installEditKeyMonitor() {
        guard editKeyMonitor.monitor == nil else { return }
        editKeyMonitor.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Don't steal Delete from text fields (sidebar search, settings
            // panes, etc.). Only act when Edit Mode is active and the event
            // isn't directed at a TextField-like first responder.
            guard viewModel.editSession != nil else { return event }
            if let nudge = editNudgeDelta(for: event) {
                Task { @MainActor in
                    viewModel.nudgeSelection(dx: nudge.dx, dy: nudge.dy)
                }
                return nil
            }
            if event.keyCode == 51 || event.keyCode == 117 {
                // Skip when a text input is the responder — let it backspace
                // its own content instead of deleting our selection.
                if isTextInputFirstResponder() {
                    return event
                }
                Task { @MainActor in
                    viewModel.stageDeleteSelected()
                }
                return nil
            }
            return event
        }
    }

    private func removeEditKeyMonitor() {
        if let m = editKeyMonitor.monitor {
            NSEvent.removeMonitor(m)
            editKeyMonitor.monitor = nil
        }
    }

    private func editNudgeDelta(for event: NSEvent) -> (dx: CGFloat, dy: CGFloat)? {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 123: return (-step, 0)
        case 124: return (step, 0)
        case 125: return (0, step)
        case 126: return (0, -step)
        default: return nil
        }
    }

    private func isTextInputFirstResponder() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder.isKind(of: NSText.self)
            || NSStringFromClass(type(of: responder)).contains("TextInput")
    }

    private func navigateBubbles(direction: Int) {
        let translations = viewModel.currentTranslations
        guard !translations.isEmpty else { return }

        let sorted = translations.sortedByIndex

        if let currentId = viewModel.highlightedBubbleId,
           let currentPos = sorted.firstIndex(where: { $0.id == currentId }) {
            let nextPos = currentPos + direction
            if nextPos >= 0 && nextPos < sorted.count {
                viewModel.highlightedBubbleId = sorted[nextPos].id
            }
        } else {
            // If nothing selected, select first (for down) or last (for up)
            if direction > 0 {
                viewModel.highlightedBubbleId = sorted.first?.id
            } else {
                viewModel.highlightedBubbleId = sorted.last?.id
            }
        }
    }

    @ViewBuilder
    private func imageContent(for page: MangaPage) -> some View {
        let currentBubbles: [TranslatedBubble] = {
            if case .translated(let bubbles) = page.state {
                return bubbles
            }
            return []
        }()

        ZStack {
            // Base Image Layer
            ImageViewer(
                page: page,
                translations: currentBubbles,
                highlightedBubbleId: $viewModel.highlightedBubbleId,
                isEditing: isEditing,
                editSession: viewModel.editSession,
                onEditAction: { action in
                    viewModel.applyEditAction(action)
                },
                onSelectionChange: { ids in
                    viewModel.setSelection(ids)
                },
                onGestureInFlightChange: { inFlight in
                    editGestureInFlight = inFlight
                }
            )

            // Overlays
            switch page.state {
            case .processing:
                ZStack {
                    Color.black.opacity(0.3)
                    
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Translating...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                }
            
            case .error(let message):
                VStack(spacing: 8) {
                    HStack(alignment: .top) {
                        Spacer()
                        Button {
                            viewModel.dismissError(at: viewModel.currentPageIndex)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Translation Failed")
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(.regularMaterial)
                .cornerRadius(12)
                .padding()
                
            default:
                EmptyView()
            }
        }
    }

    private var dropZone: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
                .ignoresSafeArea()

            Button {
                guard !isEditing else { return }
                viewModel.showFileImporter = true
            } label: {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 120, height: 120)

                        Image(systemName: "arrow.up.doc.on.clipboard")
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                    }

                    VStack(spacing: 8) {
                        Text("Drag and Drop Manga Here")
                            .font(.title2.bold())
                            .foregroundColor(.primary)

                        Text("Supports Images, Folders, CBZ, and ZIP")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    Text("Click here or press \u{2318}O to browse files")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .padding(40)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10]))
                        .foregroundColor(.secondary.opacity(0.3))
                )
                .contentShape(Rectangle())
                .padding(40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open manga file")
        }
    }

    private var newGlossarySheet: some View {
        VStack(spacing: 16) {
            Text("New Glossary")
                .font(.headline)

            TextField("Glossary name", text: $newGlossaryName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: newGlossaryName) { _, _ in
                    newGlossaryNameWasEdited = true
                }

            if let message = newGlossaryValidation.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Cancel") { showNewGlossarySheet = false }
                Spacer()
                Button("Create") {
                    do {
                        try viewModel.createAndSelectGlossary(named: newGlossaryName)
                        showNewGlossarySheet = false
                    } catch {
                        if let validationError = error as? GlossaryValidationError {
                            viewModel.errorMessage = GlossaryNameValidation.message(for: validationError)
                        } else {
                            viewModel.errorMessage = "Failed to update glossary. Please try again, or restart the app if the problem persists."
                        }
                        DebugLogger.shared.log(
                            "ContentView.createGlossary: \(error.localizedDescription)",
                            level: .error,
                            category: .cache
                        )
                    }
                }
                .disabled(!newGlossaryValidation.isValid)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 280)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: {
                guard !isEditing else { return }
                viewModel.showFileImporter = true
            }) {
                Label("Open", systemImage: "plus.rectangle.on.folder")
            }
            .help("Open image, folder or archive")
            .keyboardShortcut("o", modifiers: .command)
            .disabled(isEditing)
        }

        if viewModel.pages.count > 1 {
            ToolbarItem {
                ControlGroup {
                    Button(action: { viewModel.previousPage() }) {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .disabled(viewModel.currentPageIndex == 0 || isEditing)

                    Button(action: { viewModel.nextPage() }) {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .disabled(viewModel.currentPageIndex >= viewModel.pages.count - 1 || isEditing)
                }
            }

            ToolbarItem {
                HStack(spacing: 4) {
                    Text("\(viewModel.currentPageIndex + 1)")
                        .fontWeight(.bold)
                    Text("/")
                        .foregroundColor(.secondary)
                    Text("\(viewModel.pages.count)")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline.monospacedDigit())
                .padding(.horizontal, 8)
                .controlSize(.small)
            }


        }

        ToolbarItem(placement: .primaryAction) {
            // Glossary picker
            Menu {
                Button("No Glossary") { viewModel.activeGlossaryID = nil }
                Divider()
                ForEach(viewModel.glossaries) { glossary in
                    Button(glossary.name) { viewModel.activeGlossaryID = glossary.id }
                }
                Divider()
                Button {
                    newGlossaryName = ""
                    newGlossaryNameWasEdited = false
                    showNewGlossarySheet = true
                } label: {
                    Label("Add Glossary...", systemImage: "plus")
                }
                Button {
                    viewModel.preferences.activeTabIdentifier = "glossary"
                    openWindow(id: "settings")
                } label: {
                    Label("Manage Glossaries...", systemImage: "text.book.closed")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(viewModel.activeGlossary?.name ?? "Glossary")
                        .font(.subheadline)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 8)
            .controlSize(.small)
            .help(viewModel.activeGlossaryID != nil ? "Active glossary: \(viewModel.activeGlossary?.name ?? "")" : "No glossary selected")
        }

        ToolbarItem(placement: .primaryAction) {
            // Language Pair
            HStack(spacing: 4) {
                Menu {
                    Picker("Source", selection: $viewModel.preferences.sourceLanguage) {
                        ForEach(Language.sourceLanguages) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(viewModel.preferences.sourceLanguage.displayName)
                        .font(.subheadline)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)

                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)

                Menu {
                    Picker("Target", selection: $viewModel.preferences.targetLanguage) {
                        ForEach(Language.targetLanguages) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(viewModel.preferences.targetLanguage.displayName)
                        .font(.subheadline.bold())
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .controlSize(.small)
        }

        ToolbarItem(placement: .primaryAction) {
            // Engine
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Menu {
                    Picker("Engine", selection: $viewModel.preferences.translationEngine) {
                        ForEach(TranslationEngine.allCases) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(viewModel.preferences.translationEngine.displayName)
                        .font(.subheadline)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .controlSize(.small)
        }

        ToolbarItem(placement: .primaryAction) {
            // Re-translate All
            Button {
                guard !isEditing else { return }
                Task { await viewModel.retranslateAllPages() }
            } label: {
                Image(systemName: "arrow.trianglehead.2.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isProcessing || isEditing)
            .help("Re-translate all pages using current settings")
            .onChange(of: viewModel.preferences.translationEngine) { _, _ in
                guard !isEditing else { return }
                Task { await viewModel.switchEngineForCurrentPage() }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !isEditing else { return false }
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in await viewModel.handleInput(url) }
        }
        return true
    }

    private func handlePaste(_ providers: [NSItemProvider]) {
        guard !isEditing else { return }
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in await viewModel.handleInput(url) }
        }
    }

    @ViewBuilder
    private func pathBar(path: String) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(path)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 20) // Extra horizontal padding to clear the rounded corners
            .padding(.vertical, 8)   // Extra vertical padding for breathing room
            .background(.ultraThinMaterial)
        }
    }
}

// Box holding the NSEvent local-monitor handle for Edit Mode keyboard
// routing. Lives as `@State` on ContentView; mutated only on the main actor
// by `.onAppear` / `.onDisappear`. The reference-type wrapper lets us mutate
// `monitor` without SwiftUI treating the `@State` value as changed every
// frame.
@MainActor
private final class EditKeyMonitorBox {
    var monitor: Any?
    init() { self.monitor = nil }
}

// Hidden-button keyboard-shortcut surface, extracted into its own view so
// the ContentView body's type-check time stays bounded. Each shortcut is
// gated on `isEditing` where appropriate. Arrow keys route through
// `nudgeOrNavigate` so they nudge selected bubbles inside Edit Mode and
// navigate pages / bubbles outside it — page navigation is NEVER fired
// while editing, per `manual-bubble-editing/spec.md`.
private struct KeyboardShortcutLayer: View {
    @ObservedObject var viewModel: TranslationViewModel
    let isEditing: Bool
    let navigateBubbles: (Int) -> Void

    var body: some View {
        Group {
            arrowGroup
            editGroup
        }
    }

    private var arrowGroup: some View {
        Group {
            shortcut(.leftArrow, []) { nudgeOrNavigate(dx: -1, dy: 0) }
            shortcut(.rightArrow, []) { nudgeOrNavigate(dx: 1, dy: 0) }
            shortcut(.upArrow, []) { nudgeOrNavigate(dx: 0, dy: -1) }
            shortcut(.downArrow, []) { nudgeOrNavigate(dx: 0, dy: 1) }
            shortcut(.leftArrow, .shift) { nudgeOrNavigate(dx: -10, dy: 0) }
            shortcut(.rightArrow, .shift) { nudgeOrNavigate(dx: 10, dy: 0) }
            shortcut(.upArrow, .shift) { nudgeOrNavigate(dx: 0, dy: -10) }
            shortcut(.downArrow, .shift) { nudgeOrNavigate(dx: 0, dy: 10) }
        }
    }

    private var editGroup: some View {
        Group {
            shortcut("z", .command, enabled: isEditing) { viewModel.undo() }
            shortcut("z", [.command, .shift], enabled: isEditing) { viewModel.redo() }
            // Delete / Backspace and Edit Mode arrow keys are intentionally
            // NOT routed through hidden `.keyboardShortcut(...)` Buttons.
            // They need focus-independent AppKit routing, handled by
            // `installEditKeyMonitor()`.
            shortcut("a", .command, enabled: isEditing) { viewModel.selectAllBubbles() }
            shortcut(.tab, [], enabled: isEditing) { viewModel.cycleSelection(direction: 1) }
            shortcut(.tab, .shift, enabled: isEditing) { viewModel.cycleSelection(direction: -1) }
        }
    }

    private func nudgeOrNavigate(dx: CGFloat, dy: CGFloat) {
        if isEditing {
            viewModel.nudgeSelection(dx: dx, dy: dy)
            return
        }
        if dx != 0 {
            if dx < 0 { viewModel.previousPage() } else { viewModel.nextPage() }
        } else if dy != 0 {
            navigateBubbles(dy > 0 ? 1 : -1)
        }
    }

    @ViewBuilder
    private func shortcut(
        _ key: KeyEquivalent,
        _ modifiers: EventModifiers,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button("", action: action)
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(!enabled)
            .hidden()
    }
}

// Installs an NSWindowDelegate bridge for the main SwiftUI window so an active
// Edit Mode session can block window close. This is intentionally non-modal:
// the close is rejected, the window shakes, and the system alert sound gives
// the user a lightweight cue to use Done or Cancel first.
private struct WindowCloseInterceptor: NSViewRepresentable {
    let isEditing: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
            context.coordinator.isEditing = isEditing
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEditing = isEditing
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window)
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        weak var window: NSWindow?
        weak var previousDelegate: NSWindowDelegate?
        var isEditing = false

        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else { return }
            self.window = window
            previousDelegate = window.delegate
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if isEditing {
                sender.shake()
                NSSound.beep()
                return false
            }
            return previousDelegate?.windowShouldClose?(sender) ?? true
        }
    }
}

private extension NSWindow {
    func shake() {
        let animation = CAKeyframeAnimation(keyPath: "position.x")
        animation.values = [0, -8, 8, -6, 6, -3, 3, 0]
        animation.keyTimes = [0, 0.12, 0.24, 0.38, 0.52, 0.68, 0.84, 1]
        animation.duration = 0.35
        animation.isAdditive = true
        animations = ["shake": animation]
        animator().setFrameOrigin(frame.origin)
    }
}
