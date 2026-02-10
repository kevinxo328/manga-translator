import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = TranslationViewModel()
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
                highlightedBubbleIndex: $viewModel.highlightedBubbleIndex
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
                Task { await handleInput(url) }
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
    }

    @ViewBuilder
    private func imageContent(for page: MangaPage) -> some View {
        switch page.state {
        case .pending, .processing:
            VStack {
                ImageViewer(
                    imageURL: page.imageURL,
                    translations: [],
                    highlightedBubbleIndex: $viewModel.highlightedBubbleIndex
                )
                if case .processing = page.state {
                    ProgressView("Translating...")
                        .padding()
                }
            }
        case .translated(let bubbles):
            ImageViewer(
                imageURL: page.imageURL,
                translations: bubbles,
                highlightedBubbleIndex: $viewModel.highlightedBubbleIndex
            )
        case .error(let message):
            VStack {
                ImageViewer(
                    imageURL: page.imageURL,
                    translations: [],
                    highlightedBubbleIndex: $viewModel.highlightedBubbleIndex
                )
                Text(message)
                    .foregroundColor(.red)
                    .padding()
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Drop image, folder, or archive here")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Or press \u{2318}O to open")
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: { showFileImporter = true }) {
                Label("Open", systemImage: "folder")
            }
        }

        if viewModel.pages.count > 1 {
            ToolbarItem {
                HStack {
                    Button(action: { viewModel.previousPage() }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(viewModel.currentPageIndex == 0)
                    .keyboardShortcut(.leftArrow, modifiers: [])

                    Text("Page \(viewModel.currentPageIndex + 1)/\(viewModel.pages.count)")
                        .monospacedDigit()

                    Button(action: { viewModel.nextPage() }) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(viewModel.currentPageIndex >= viewModel.pages.count - 1)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                }
            }

            ToolbarItem {
                let (completed, total) = viewModel.batchProgress
                if total > 0 {
                    Text("\(completed)/\(total) translated")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }

        ToolbarItem {
            Picker("From", selection: $viewModel.preferences.sourceLanguage) {
                ForEach(Language.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .frame(width: 140)
        }

        ToolbarItem {
            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
        }

        ToolbarItem {
            Picker("To", selection: $viewModel.preferences.targetLanguage) {
                ForEach(Language.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .frame(width: 140)
        }

        ToolbarItem {
            Picker("Engine", selection: $viewModel.preferences.translationEngine) {
                ForEach(TranslationEngine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .frame(width: 120)
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