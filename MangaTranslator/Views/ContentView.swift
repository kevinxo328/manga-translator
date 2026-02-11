import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: TranslationViewModel
    @State private var showFileImporter = false

    var body: some View {
        HSplitView {
            // Left: Image viewer
            ZStack {
                if let page = viewModel.currentPage {
                    imageContent(for: page)
                } else {
                    dropZone
                }
            }
            .frame(minWidth: 500)

            // Right: Sidebar
            TranslationSidebar(
                translations: viewModel.currentTranslations,
                highlightedBubbleIndex: $viewModel.highlightedBubbleIndex,
                isProcessing: viewModel.isCurrentPageProcessing,
                onRetranslate: {
                    Task { await viewModel.retranslateFromOCR() }
                }
            )
        }
        .frame(minWidth: 800, minHeight: 600)
        .toolbar { toolbarContent }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let granted = url.startAccessingSecurityScopedResource()
                Task {
                    await handleInput(url)
                    if granted { url.stopAccessingSecurityScopedResource() }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .alert("Missing API Key", isPresented: $viewModel.showMissingKeyAlert) {
            Button("Open Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please add an API key for \(viewModel.preferences.translationEngine.displayName) in Settings.")
        }
        .onPasteCommand(of: [.fileURL, .png, .tiff]) { providers in
            handlePaste(providers)
        }
        .keyboardShortcut(.init("o"), modifiers: .command)
        // Bubble Navigation Shortcuts
        .background(
            Button("") {
                navigateBubbles(direction: 1)
            }
            .keyboardShortcut(.downArrow, modifiers: [])
            .hidden()
        )
        .background(
            Button("") {
                navigateBubbles(direction: -1)
            }
            .keyboardShortcut(.upArrow, modifiers: [])
            .hidden()
        )
    }

    private func navigateBubbles(direction: Int) {
        let translations = viewModel.currentTranslations
        guard !translations.isEmpty else { return }
        
        // Sort bubbles to ensure logical order matches visual order
        let sorted = translations.sorted(by: { $0.index < $1.index })
        let indices = sorted.map { $0.index }
        
        if let current = viewModel.highlightedBubbleIndex, let currentIndexInSorted = indices.firstIndex(of: current) {
            let nextIndexInSorted = currentIndexInSorted + direction
            if nextIndexInSorted >= 0 && nextIndexInSorted < indices.count {
                viewModel.highlightedBubbleIndex = indices[nextIndexInSorted]
            }
        } else {
            // If nothing selected, select first (for down) or last (for up)
            if direction > 0 {
                viewModel.highlightedBubbleIndex = indices.first
            } else {
                viewModel.highlightedBubbleIndex = indices.last
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
                imageURL: page.imageURL,
                translations: currentBubbles,
                highlightedBubbleIndex: $viewModel.highlightedBubbleIndex
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

                Text("Or press \u{2318}O to browse files")
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
            .padding(40)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: { showFileImporter = true }) {
                Label("Open", systemImage: "plus.rectangle.on.folder")
            }
            .help("Open image, folder or archive")
        }

        if viewModel.pages.count > 1 {
            ToolbarItem {
                ControlGroup {
                    Button(action: { viewModel.previousPage() }) {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .disabled(viewModel.currentPageIndex == 0)
                    .keyboardShortcut(.leftArrow, modifiers: [])

                    Button(action: { viewModel.nextPage() }) {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .disabled(viewModel.currentPageIndex >= viewModel.pages.count - 1)
                    .keyboardShortcut(.rightArrow, modifiers: [])
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
                .padding(.horizontal, 12) // Increased from 8
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }

            ToolbarItem {
                let (completed, total) = viewModel.batchProgress
                if total > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("\(completed)/\(total)")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
                }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 12) {
                // Language Pair
                HStack(spacing: 0) {
                    Menu {
                        Picker("Source", selection: $viewModel.preferences.sourceLanguage) {
                            ForEach(Language.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Text(viewModel.preferences.sourceLanguage.displayName)
                            .font(.subheadline)
                            .frame(width: 80, alignment: .center)
                    }
                    .buttonStyle(.plain)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 0)

                    Menu {
                        Picker("Target", selection: $viewModel.preferences.targetLanguage) {
                            ForEach(Language.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Text(viewModel.preferences.targetLanguage.displayName)
                            .font(.subheadline.bold())
                            .frame(width: 80, alignment: .center)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )

                // Engine
                HStack(spacing: 0) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.leading, 10)
                    
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
                            .frame(width: 85, alignment: .leading)
                            .padding(.leading, 4)
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 28)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
            }
            .controlSize(.small)
            .onChange(of: viewModel.preferences.translationEngine) { _ in
                Task { await viewModel.retranslateCurrentPage() }
            }
        }
    }

    private var allowedTypes: [UTType] {
        [.image, .folder, .zip, UTType(filenameExtension: "cbz") ?? .zip]
    }

    private func handleInput(_ url: URL) async {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let ext = url.pathExtension.lowercased()

        if isDirectory {
            await viewModel.loadFolder(url)
        } else if ext == "zip" || ext == "cbz" {
            await viewModel.loadArchive(url)
        } else {
            await viewModel.loadImage(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in await handleInput(url) }
        }
        return true
    }

    private func handlePaste(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in await handleInput(url) }
        }
    }
}