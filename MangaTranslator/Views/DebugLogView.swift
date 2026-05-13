import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - ViewModel

@MainActor
final class DebugLogViewModel: ObservableObject {
    @Published var entries: [DebugLogEntry] = []
    @Published var filter = DebugLogFilter()
    @Published var isLoading = false
    @Published var hasMore = false
    @Published var matchingDeleteCount: Int = 0

    private let store: DebugLogStore
    private let currentSessionID: String
    private var debounceTask: Task<Void, Never>?
    private var loadedCount = 0

    init(store: DebugLogStore = DebugLogStore.shared, sessionID: String = DebugLogger.shared.sessionID) {
        self.store = store
        self.currentSessionID = sessionID
    }

    // MARK: - Queries

    func refresh() async {
        await store.awaitInitialRotation()
        loadedCount = 0
        entries = []
        await loadPage()
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        await loadPage()
    }

    func applyFilterChange() {
        debounceTask?.cancel()
        debounceTask = Task {
            if !filter.textQuery.isEmpty {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    func refreshMatchingCount() async {
        matchingDeleteCount = await store.count(filter: filter)
    }

    // MARK: - Actions

    func clearLogs() async {
        await store.delete(filter: filter)
        await refresh()
    }

    func exportNDJSON() async -> String {
        await store.exportNDJSON(filter: filter)
    }

    func hasContentLogs() async -> Bool {
        var contentFilter = filter
        contentFilter.kind = .content
        contentFilter.exportableOnly = true
        return await store.count(filter: contentFilter) > 0
    }

    // MARK: - Private

    private func loadPage() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let page = await store.query(filter: filter, offset: loadedCount)
        let newTotal = loadedCount + page.count
        let capped = newTotal > DebugLogStore.uiCap
        let toAppend = capped ? Array(page.prefix(DebugLogStore.uiCap - loadedCount)) : page

        entries.append(contentsOf: toAppend)
        loadedCount = entries.count
        hasMore = page.count == DebugLogStore.pageSize && loadedCount < DebugLogStore.uiCap
    }

    // MARK: - Session filter helper

    func toggleSessionFilter(currentOnly: Bool) {
        filter.sessionIDFilter = currentOnly ? .session(currentSessionID) : .all
        applyFilterChange()
    }
}

// MARK: - Debug Log View

struct DebugLogView: View {
    @StateObject private var viewModel: DebugLogViewModel
    @State private var showClearConfirm = false
    @State private var showExportContentWarning = false
    @State private var exportNDJSON: String = ""
    @State private var selectedEntry: DebugLogEntry?
    @State private var currentSessionOnly = false

    init(store: DebugLogStore = DebugLogStore.shared, sessionID: String = DebugLogger.shared.sessionID) {
        _viewModel = StateObject(wrappedValue: DebugLogViewModel(store: store, sessionID: sessionID))
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            logList
            Divider()
            actionBar
        }
        .task { await viewModel.refresh() }
        .sheet(item: $selectedEntry) { entry in
            DebugLogDetailSheet(entry: entry)
        }
        .alert("Clear Logs", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear \(viewModel.matchingDeleteCount) entries", role: .destructive) {
                Task { await viewModel.clearLogs() }
            }
        } message: {
            Text("This will permanently delete \(viewModel.matchingDeleteCount) matching entries from the app log store. This does not affect Xcode or system logs.")
        }
        .alert("Export Includes Content Logs", isPresented: $showExportContentWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Export Anyway") { performExport() }
        } message: {
            Text("The filtered export includes OCR source text and translated text. Make sure you intended to share this content.")
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                TextField("Search logs…", text: $viewModel.filter.textQuery)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: viewModel.filter.textQuery) { _, _ in
                        viewModel.applyFilterChange()
                    }

                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }

            HStack(spacing: 8) {
                levelPicker
                categoryPicker
                kindPicker
                sessionToggle
                    .fixedSize()
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var levelPicker: some View {
        Picker("Level", selection: $viewModel.filter.level) {
            Text("All Levels").tag(Optional<DebugLogLevel>.none)
            ForEach(DebugLogLevel.allCases, id: \.self) { level in
                Text(level.displayName).tag(Optional(level))
            }
        }
        .labelsHidden()
        .frame(maxWidth: 100)
        .onChange(of: viewModel.filter.level) { _, _ in viewModel.applyFilterChange() }
    }

    private var categoryPicker: some View {
        Picker("Category", selection: $viewModel.filter.category) {
            Text("All Categories").tag(Optional<DebugLogCategory>.none)
            ForEach(DebugLogCategory.allCases, id: \.self) { cat in
                Text(cat.displayName).tag(Optional(cat))
            }
        }
        .labelsHidden()
        .frame(maxWidth: 130)
        .onChange(of: viewModel.filter.category) { _, _ in viewModel.applyFilterChange() }
    }

    private var kindPicker: some View {
        Picker("Kind", selection: $viewModel.filter.kind) {
            Text("All").tag(Optional<DebugLogKind>.none)
            ForEach(DebugLogKind.allCases, id: \.self) { kind in
                Text(kind.rawValue.capitalized).tag(Optional(kind))
            }
        }
        .labelsHidden()
        .frame(maxWidth: 90)
        .onChange(of: viewModel.filter.kind) { _, _ in viewModel.applyFilterChange() }
    }

    private var sessionToggle: some View {
        Toggle("Current Session", isOn: $currentSessionOnly)
            .toggleStyle(.checkbox)
            .onChange(of: currentSessionOnly) { _, newValue in
                viewModel.toggleSessionFilter(currentOnly: newValue)
            }
    }

    // MARK: - Log list

    private var logList: some View {
        Group {
            if viewModel.isLoading && viewModel.entries.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.entries.isEmpty {
                Text("No log entries match the current filter.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.entries) { entry in
                    DebugLogRowView(entry: entry)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedEntry = entry }
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                }
                .listStyle(.plain)
                if viewModel.hasMore {
                    loadMoreButton
                }
            }
        }
    }

    private var loadMoreButton: some View {
        Button("Load More") {
            Task { await viewModel.loadMore() }
        }
        .buttonStyle(.borderless)
        .padding(8)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(viewModel.entries.count) entries loaded")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                Task {
                    await viewModel.refreshMatchingCount()
                    showClearConfirm = true
                }
            } label: {
                DebugLogActionButtonLabel(systemImage: "trash", title: "Clear")
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .foregroundStyle(.red)

            Button {
                Task { await initiateExport() }
            } label: {
                DebugLogActionButtonLabel(systemImage: "square.and.arrow.up", title: "Export", iconYOffset: -1)
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Export

    private func initiateExport() async {
        let hasContent = await viewModel.hasContentLogs()
        exportNDJSON = await viewModel.exportNDJSON()
        if hasContent {
            showExportContentWarning = true
        } else {
            performExport()
        }
    }

    private func performExport() {
        let panel = NSSavePanel()
        if let ndjsonType = UTType(filenameExtension: "ndjson") {
            panel.allowedContentTypes = [ndjsonType]
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        panel.nameFieldStringValue = "manga-translator-debug-logs-\(formatter.string(from: Date())).ndjson"
        let saveData = Data(exportNDJSON.utf8)
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            try? saveData.write(to: url)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
}

struct DebugLogActionButtonLabel: View {
    let systemImage: String
    let title: String
    var iconYOffset: CGFloat = 0

    var body: some View {
        Text(title)
            .lineLimit(1)
            .padding(.leading, 20)
            .overlay(alignment: .leading) {
                Image(systemName: systemImage)
                    .frame(width: 16, height: 16, alignment: .center)
                    .offset(y: iconYOffset)
            }
    }
}

// MARK: - Row View

struct DebugLogRowView: View {
    let entry: DebugLogEntry

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(entry.formattedTimestamp)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            LevelBadge(level: entry.level)

            Text(entry.category.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)

            Text(entry.firstLineOfMessage)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Level Badge

struct LevelBadge: View {
    let level: DebugLogLevel

    var body: some View {
        Text(level.rawValue.prefix(4).uppercased())
            .font(.system(.caption2, design: .monospaced).bold())
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(badgeColor.opacity(0.2))
            .foregroundStyle(badgeColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .frame(width: 34)
    }

    private var badgeColor: Color {
        switch level {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .fault: return .purple
        }
    }
}

// MARK: - Detail Sheet

struct DebugLogDetailSheet: View {
    let entry: DebugLogEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                LevelBadge(level: entry.level)
                Text(entry.category.rawValue)
                    .font(.subheadline.bold())
                Spacer()
                Button("Done") { dismiss() }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    DetailField(label: "Message", value: entry.message)
                    DetailField(label: "Timestamp", value: entry.timestamp.formatted(.iso8601))
                    DetailField(label: "Kind", value: entry.kind.rawValue)
                    DetailField(label: "Session ID", value: entry.sessionID)
                    DetailField(label: "Source", value: entry.sourceFileOrComponent)
                    if let fp = entry.filePath {
                        DetailField(label: "File Path", value: fp)
                    }
                    if entry.metadataJSON != "{}" {
                        DetailField(label: "Metadata", value: entry.metadataJSON)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(width: 500, height: 380)
    }
}

private struct DetailField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
