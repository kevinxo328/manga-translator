import Testing
import SwiftUI
@testable import MangaTranslator

@Suite("DebugLogView UI Tests")
@MainActor
struct DebugLogViewTests {

    // MARK: 4.8 Debug tab happy paths

    @Test("ViewModel loads entries on refresh")
    func viewModelLoadsEntriesOnRefresh() async throws {
        let store = makeStore()
        await store.insert(makeEntry(message: "first log"))
        await store.insert(makeEntry(message: "second log"))

        let vm = DebugLogViewModel(store: store, sessionID: "test-session")
        await vm.refresh()

        #expect(vm.entries.count == 2)
    }

    @Test("ViewModel query returns newest first")
    func viewModelQueryReturnsNewestFirst() async throws {
        let store = makeStore()
        let base = Date()
        await store.insert(makeEntry(message: "older", timestamp: base))
        await store.insert(makeEntry(message: "newer", timestamp: base.addingTimeInterval(1)))

        let vm = DebugLogViewModel(store: store, sessionID: "test-session")
        await vm.refresh()

        #expect(vm.entries.first?.message == "newer")
    }

    @Test("ViewModel filters by level")
    func viewModelFiltersByLevel() async throws {
        let store = makeStore()
        await store.insert(makeEntry(message: "error msg", level: .error))
        await store.insert(makeEntry(message: "info msg", level: .info))

        let vm = DebugLogViewModel(store: store, sessionID: "test-session")
        vm.filter.level = .error
        await vm.refresh()

        #expect(vm.entries.count == 1)
        #expect(vm.entries.first?.level == .error)
    }

    @Test("ViewModel loads first page of 100")
    func viewModelLoadsFirstPageOf100() async throws {
        let store = makeStore()
        let base = Date()
        for i in 0..<150 {
            await store.insert(makeEntry(message: "entry \(i)", timestamp: base.addingTimeInterval(Double(i))))
        }

        let vm = DebugLogViewModel(store: store, sessionID: "test-session")
        await vm.refresh()

        #expect(vm.entries.count == 100)
        #expect(vm.hasMore == true)
    }

    @Test("ViewModel respects 500-entry UI cap")
    func viewModelRespectsUICap() async throws {
        let store = makeStore()
        let base = Date()
        for i in 0..<600 {
            await store.insert(makeEntry(message: "entry \(i)", timestamp: base.addingTimeInterval(Double(i))))
        }

        let vm = DebugLogViewModel(store: store, sessionID: "test-session")
        await vm.refresh()
        // Load more until cap
        while vm.hasMore {
            await vm.loadMore()
        }

        #expect(vm.entries.count <= DebugLogStore.uiCap)
        #expect(vm.hasMore == false)
    }

    @Test("ViewModel load more appends next page")
    func viewModelLoadMoreAppendsNextPage() async throws {
        let store = makeStore()
        let base = Date()
        for i in 0..<210 {
            await store.insert(makeEntry(message: "entry \(i)", timestamp: base.addingTimeInterval(Double(i))))
        }

        let vm = DebugLogViewModel(store: store, sessionID: "test-session")
        await vm.refresh()
        #expect(vm.entries.count == 100)

        await vm.loadMore()
        #expect(vm.entries.count == 200)
    }

    @Test("ViewModel filter change resets pagination")
    func viewModelFilterChangeResetsPagination() async throws {
        let store = makeStore()
        let base = Date()
        for i in 0..<150 {
            await store.insert(makeEntry(message: "entry \(i)", level: .info, timestamp: base.addingTimeInterval(Double(i))))
        }
        await store.insert(makeEntry(message: "error entry", level: .error))

        let vm = DebugLogViewModel(store: store, sessionID: "test-session")
        await vm.refresh()
        #expect(vm.entries.count == 100)

        vm.filter.level = .error
        await vm.refresh()
        #expect(vm.entries.count == 1)
        #expect(vm.entries.first?.level == .error)
    }

    @Test("ViewModel clear deletes matching entries and reloads")
    func viewModelClearDeletesMatchingEntries() async throws {
        let store = makeStore()
        await store.insert(makeEntry(message: "keep", level: .info))
        await store.insert(makeEntry(message: "delete", level: .error))

        let vm = DebugLogViewModel(store: store, sessionID: "test-session")
        vm.filter.level = .error
        await vm.refresh()
        #expect(vm.entries.count == 1)

        await vm.clearLogs()
        #expect(vm.entries.isEmpty)

        // Verify only error entry was deleted
        vm.filter.level = nil
        await vm.refresh()
        #expect(vm.entries.count == 1)
        #expect(vm.entries.first?.message == "keep")
    }

    @Test("ViewModel clear preserves active filter")
    func viewModelClearPreservesActiveFilter() async throws {
        let store = makeStore()
        await store.insert(makeEntry(message: "error one", level: .error))
        await store.insert(makeEntry(message: "error two", level: .error))
        await store.insert(makeEntry(message: "info entry", level: .info))

        let vm = DebugLogViewModel(store: store, sessionID: "test-session")
        vm.filter.level = .error
        await vm.clearLogs()

        // Filter should still be .error after clear
        #expect(vm.filter.level == .error)
        #expect(vm.entries.isEmpty)
    }

    @Test("ViewModel matching delete count reflects filter")
    func viewModelMatchingDeleteCountReflectsFilter() async throws {
        let store = makeStore()
        await store.insert(makeEntry(message: "e1", level: .error))
        await store.insert(makeEntry(message: "e2", level: .error))
        await store.insert(makeEntry(message: "info", level: .info))

        let vm = DebugLogViewModel(store: store, sessionID: "test-session")
        vm.filter.level = .error
        await vm.refreshMatchingCount()

        #expect(vm.matchingDeleteCount == 2)
    }

    @Test("ViewModel export NDJSON respects filter")
    func viewModelExportNDJSONRespectsFilter() async throws {
        let store = makeStore()
        await store.insert(makeEntry(message: "error log", level: .error))
        await store.insert(makeEntry(message: "info log", level: .info))

        let vm = DebugLogViewModel(store: store, sessionID: "test-session")
        vm.filter.level = .error
        let ndjson = await vm.exportNDJSON()

        #expect(ndjson.contains("error log"))
        #expect(!ndjson.contains("info log"))
    }

    @Test("ViewModel detail sheet contains full entry fields")
    func entryDetailFieldsAreComplete() async throws {
        let store = makeStore()
        await store.insert(makeEntry(
            message: "Full message here\nLine 2",
            level: .warning,
            category: .keychain,
            sessionID: "sess-abc",
            source: "KeychainService.swift",
            filePath: "/Users/user/image.png"
        ))

        let vm = DebugLogViewModel(store: store, sessionID: "sess-abc")
        await vm.refresh()

        let entry = try #require(vm.entries.first)
        #expect(entry.message == "Full message here\nLine 2")
        #expect(entry.firstLineOfMessage == "Full message here")
        #expect(entry.level == .warning)
        #expect(entry.category == .keychain)
        #expect(entry.sessionID == "sess-abc")
        #expect(entry.sourceFileOrComponent == "KeychainService.swift")
        #expect(entry.filePath == "/Users/user/image.png")
    }

    @Test("ViewModel session filter shows only current session")
    func viewModelSessionFilterShowsCurrentSession() async throws {
        let store = makeStore()
        await store.insert(makeEntry(message: "current", sessionID: "current-session"))
        await store.insert(makeEntry(message: "old", sessionID: "old-session"))

        let vm = DebugLogViewModel(store: store, sessionID: "current-session")
        vm.toggleSessionFilter(currentOnly: true)
        await vm.refresh()

        #expect(vm.entries.count == 1)
        #expect(vm.entries.first?.message == "current")
    }

    @Test("ViewModel detects content logs for export warning")
    func viewModelDetectsContentLogsForExportWarning() async throws {
        let store = makeStore()
        await store.insert(makeEntry(message: "operational log", kind: .operational))
        await store.insert(makeEntry(message: "ocr text here", kind: .content))

        let vm = DebugLogViewModel(store: store, sessionID: "test-session")
        let hasContent = await vm.hasContentLogs()
        #expect(hasContent == true)
    }

    @Test("DebugLogView tab exists in SettingsView")
    func debugTabExistsInSettingsView() {
        // Compile-time check: DebugLogView is a valid SwiftUI View
        let _: any View.Type = DebugLogView.self
        let _: any View.Type = DebugLogRowView.self
        let _: any View.Type = DebugLogDetailSheet.self
        let _: any View.Type = LevelBadge.self
    }

    @Test("Action buttons share baseline-aligned labels")
    func actionButtonsShareBaselineAlignedLabels() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MangaTranslator/Views/DebugLogView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let labelStart = try #require(source.range(of: "struct DebugLogActionButtonLabel"))
        let labelEnd = try #require(source.range(of: "// MARK: - Row View", range: labelStart.upperBound..<source.endIndex))
        let labelSource = String(source[labelStart.lowerBound..<labelEnd.lowerBound])

        #expect(source.contains("DebugLogActionButtonLabel(systemImage: \"trash\", title: \"Clear\")"))
        #expect(source.contains("DebugLogActionButtonLabel(systemImage: \"square.and.arrow.up\", title: \"Export\", iconYOffset: -1)"))
        #expect(labelSource.contains("Text(title)"))
        #expect(labelSource.contains(".overlay(alignment: .leading)"))
        #expect(labelSource.contains(".frame(width: 16, height: 16, alignment: .center)"))
        #expect(labelSource.contains(".offset(y: iconYOffset)"))
        #expect(!labelSource.contains("HStack(alignment: .firstTextBaseline, spacing: 4)"))
        #expect(!source.contains("label: {\n                HStack(spacing: 4)"))
    }

    // MARK: - Helpers

    private func makeStore() -> DebugLogStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        return DebugLogStore(databaseURL: url)
    }

    private func makeEntry(
        message: String,
        level: DebugLogLevel = .info,
        category: DebugLogCategory = .cache,
        kind: DebugLogKind = .operational,
        sessionID: String = "test-session",
        source: String = "TestFile.swift",
        filePath: String? = nil,
        timestamp: Date = Date()
    ) -> DebugLogEntry {
        DebugLogEntry(
            id: 0,
            timestamp: timestamp,
            level: level,
            category: category,
            kind: kind,
            message: message,
            metadataJSON: "{}",
            sessionID: sessionID,
            sourceFileOrComponent: source,
            filePath: filePath,
            exportable: true
        )
    }
}
