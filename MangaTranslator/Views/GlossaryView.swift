import SwiftUI

struct GlossaryView: View {
    @ObservedObject var viewModel: TranslationViewModel
    // When true, renders as a native grouped Form inside SettingsView.
    // When false (default), renders as a standalone modal sheet.
    var isEmbedded: Bool = false

    @Environment(\.dismiss) private var dismiss

    // Shared state for both embedded and sheet layouts
    @State private var showNewGlossarySheet = false
    @State private var newGlossaryName = ""
    @State private var showDeleteGlossaryAlert = false
    @State private var terms: [GlossaryTerm] = []
    @State private var showAddTermSheet = false
    @State private var editingTerm: GlossaryTerm? = nil
    @State private var editSourceTerm = ""
    @State private var editTargetTerm = ""

    // Embedded-only: rename sheet state
    @State private var showRenameSheet = false
    @State private var glossaryNameInput: String = ""

    private var glossaryService: GlossaryService {
        viewModel.glossaryServiceForView
    }

    var body: some View {
        if isEmbedded {
            embeddedLayout
        } else {
            sheetLayout
        }
    }

    // MARK: - Embedded layout (Settings tab, grouped form style)

    private var embeddedLayout: some View {
        Form {
            // Section 1: Glossary selector — single row with picker + action buttons
            // No section header: page title "Glossary" already provides context.
            Section {
                HStack(spacing: 8) {
                    // Glossary picker — shows placeholder text when nothing is selected
                    Menu {
                        ForEach(viewModel.glossaries) { glossary in
                            Button(glossary.name) {
                                viewModel.activeGlossaryID = glossary.id
                                reloadTerms()
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if let active = viewModel.activeGlossary {
                                Text(active.name)
                            } else {
                                Text("Select a Glossary…")
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().frame(height: 16)

                    // Rename (pencil) — only enabled when a glossary is active
                    Button {
                        glossaryNameInput = viewModel.activeGlossary?.name ?? ""
                        showRenameSheet = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.activeGlossaryID == nil)
                    .help("Rename glossary")

                    // Add glossary
                    Button {
                        newGlossaryName = ""
                        showNewGlossarySheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New glossary")

                    // Delete active glossary (red trash)
                    Button(role: .destructive) {
                        showDeleteGlossaryAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(viewModel.activeGlossaryID == nil ? Color.secondary : Color.red)
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.activeGlossaryID == nil)
                    .help("Delete glossary")
                }
            }

            // Section 2: Terms list (only when a glossary is active)
            if viewModel.activeGlossaryID != nil {
                Section {
                    if terms.isEmpty {
                        Text("No terms yet")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(terms) { term in
                            embeddedTermRow(term)
                        }
                    }
                } header: {
                    // "Terms (15)" label on the left, + button on the right
                    HStack {
                        Text("Terms (\(terms.count))")
                        Spacer()
                        Button {
                            editingTerm = nil
                            editSourceTerm = ""
                            editTargetTerm = ""
                            showAddTermSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("Add term")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            reloadTerms()
            syncNameInput()
        }
        .onChange(of: viewModel.activeGlossaryID) { _, _ in
            reloadTerms()
            syncNameInput()
        }
        .alert("Delete Glossary", isPresented: $showDeleteGlossaryAlert) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the glossary and all its terms. This action cannot be undone.")
        }
        .sheet(isPresented: $showNewGlossarySheet) { newGlossarySheet }
        .sheet(isPresented: $showRenameSheet) { renameGlossarySheet }
        .sheet(isPresented: $showAddTermSheet) { termEditSheet }
    }

    @ViewBuilder
    private func embeddedTermRow(_ term: GlossaryTerm) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(term.sourceTerm).font(.body)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    Text(term.targetTerm).font(.body)
                }
                if term.autoDetected {
                    Text("Auto-detected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
            }
            Spacer()
            // Hover actions: edit pencil and trash
            Button {
                editingTerm = term
                editSourceTerm = term.sourceTerm
                editTargetTerm = term.targetTerm
                showAddTermSheet = true
            } label: {
                Image(systemName: "pencil").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                do {
                    try glossaryService.deleteTerm(id: term.id)
                } catch {
                    handleGlossaryFailure(error, operation: "GlossaryView.deleteTerm")
                }
                reloadTerms()
            } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Rename helpers

    // Syncs the name text field to the current active glossary name.
    private func syncNameInput() {
        glossaryNameInput = viewModel.activeGlossary?.name ?? ""
    }

    // Commits a rename only when the normalized input differs from the current name.
    // Returns true on success or no-op (safe to close sheet); false on SQLite failure (keep sheet open).
    @discardableResult
    private func commitRename() -> Bool {
        guard let id = viewModel.activeGlossaryID else { return true }
        let normalized = glossaryNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            syncNameInput() // Reject empty: restore existing name
            return true
        }
        let truncated = normalized.count > 20 ? String(normalized.prefix(20)) : normalized
        guard truncated != viewModel.activeGlossary?.name else { return true } // No-op if unchanged
        do {
            try glossaryService.renameGlossary(id: id, newName: truncated)
            viewModel.loadGlossaries()
            return true
        } catch {
            handleGlossaryFailure(error, operation: "GlossaryView.renameGlossary")
            syncNameInput() // Restore on failure
            return false
        }
    }

    // MARK: - Sheet layout (standalone modal, isEmbedded == false)
    // Unchanged from the original implementation.

    private var sheetLayout: some View {
        VStack(spacing: 0) {
            // Header: glossary picker
            HStack {
                Text("Glossary")
                    .font(.headline)

                Spacer()

                Menu {
                    Button("No Glossary") { viewModel.activeGlossaryID = nil; terms = [] }
                    Divider()
                    ForEach(viewModel.glossaries) { glossary in
                        Button(glossary.name) {
                            viewModel.activeGlossaryID = glossary.id
                            reloadTerms()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.activeGlossary?.name ?? "No Glossary")
                            .font(.subheadline)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Button {
                    newGlossaryName = ""
                    showNewGlossarySheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Create new glossary")

                if viewModel.activeGlossaryID != nil {
                    Button {
                        showDeleteGlossaryAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .foregroundColor(.red)
                    .help("Delete current glossary")
                }

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            if viewModel.activeGlossaryID == nil {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.book.closed")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Select or create a glossary")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                // Term list
                List {
                    ForEach(terms) { term in
                        termRow(term)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            do {
                                try glossaryService.deleteTerm(id: terms[index].id)
                            } catch {
                                handleGlossaryFailure(error, operation: "GlossaryView.deleteTerm")
                            }
                        }
                        reloadTerms()
                    }
                }
                .listStyle(.inset)

                Divider()

                // Add term button
                HStack {
                    Button {
                        editingTerm = nil
                        editSourceTerm = ""
                        editTargetTerm = ""
                        showAddTermSheet = true
                    } label: {
                        Label("Add Term", systemImage: "plus")
                    }
                    Spacer()
                    Text("\(terms.count) term\(terms.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 420, minHeight: 380)
        .onAppear { reloadTerms() }
        .alert("Delete Glossary", isPresented: $showDeleteGlossaryAlert) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the glossary and all its terms. This action cannot be undone.")
        }
        .sheet(isPresented: $showNewGlossarySheet) { newGlossarySheet }
        .sheet(isPresented: $showAddTermSheet) { termEditSheet }
    }

    @ViewBuilder
    private func termRow(_ term: GlossaryTerm) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(term.sourceTerm)
                        .font(.body)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(term.targetTerm)
                        .font(.body)
                }
                if term.autoDetected {
                    Text("Auto-detected")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
            }

            Spacer()

            Button {
                editingTerm = term
                editSourceTerm = term.sourceTerm
                editTargetTerm = term.targetTerm
                showAddTermSheet = true
            } label: {
                Image(systemName: "pencil")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Shared helpers

    private func performDelete() {
        guard let id = viewModel.activeGlossaryID else { return }
        do {
            try glossaryService.deleteGlossary(id: id)
            viewModel.activeGlossaryID = nil
            viewModel.loadGlossaries()
            terms = []
        } catch {
            handleGlossaryFailure(error, operation: "GlossaryView.deleteGlossary")
        }
    }

    private var renameGlossarySheet: some View {
        VStack(spacing: 16) {
            Text("Rename Glossary")
                .font(.headline)

            TextField("Glossary name", text: $glossaryNameInput)
                .textFieldStyle(.roundedBorder)
                .onChange(of: glossaryNameInput) { _, newValue in
                    if newValue.count > 20 { glossaryNameInput = String(newValue.prefix(20)) }
                }

            HStack {
                Button("Cancel") { showRenameSheet = false }
                Spacer()
                Button("Rename") {
                    if commitRename() { showRenameSheet = false }
                }
                .disabled(glossaryNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 280)
    }

    private var newGlossarySheet: some View {
        VStack(spacing: 16) {
            Text("New Glossary")
                .font(.headline)

            TextField("Glossary name", text: $newGlossaryName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: newGlossaryName) { _, newValue in
                    if newValue.count > 20 { newGlossaryName = String(newValue.prefix(20)) }
                }

            HStack {
                Button("Cancel") { showNewGlossarySheet = false }
                Spacer()
                Button("Create") {
                    do {
                        let g = try glossaryService.createGlossary(name: newGlossaryName)
                        viewModel.loadGlossaries()
                        viewModel.activeGlossaryID = g.id
                        reloadTerms()
                        syncNameInput()
                    } catch {
                        handleGlossaryFailure(error, operation: "GlossaryView.createGlossary")
                    }
                    showNewGlossarySheet = false
                }
                .disabled(newGlossaryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 280)
    }

    private var termEditSheet: some View {
        VStack(spacing: 16) {
            Text(editingTerm == nil ? "Add Term" : "Edit Term")
                .font(.headline)

            HStack {
                TextField("Original", text: $editSourceTerm)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                TextField("Translation", text: $editTargetTerm)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { showAddTermSheet = false }
                Spacer()
                Button("Save") {
                    let src = editSourceTerm.trimmingCharacters(in: .whitespacesAndNewlines)
                    let tgt = editTargetTerm.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !src.isEmpty, !tgt.isEmpty else { return }
                    do {
                        if let existing = editingTerm {
                            try glossaryService.updateTerm(id: existing.id, sourceTerm: src, targetTerm: tgt)
                        } else if let glossaryID = viewModel.activeGlossaryID {
                            _ = try glossaryService.addTerm(
                                glossaryID: glossaryID,
                                sourceTerm: src,
                                targetTerm: tgt,
                                autoDetected: false
                            )
                        }
                    } catch {
                        handleGlossaryFailure(error, operation: "GlossaryView.saveTerm")
                    }
                    reloadTerms()
                    showAddTermSheet = false
                }
                .disabled(
                    editSourceTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    editTargetTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 380)
    }

    private func reloadTerms() {
        guard let id = viewModel.activeGlossaryID else {
            terms = []
            return
        }
        terms = glossaryService.listTerms(glossaryID: id)
    }

    // Surfaces glossary mutation failures via the existing errorMessage modal,
    // and routes the underlying SQLite text to DebugLogger so the UI stays
    // free of database-internal strings.
    private func handleGlossaryFailure(_ error: Error, operation: String) {
        viewModel.errorMessage = "Failed to update glossary. Please try again, or restart the app if the problem persists."
        if let cacheError = error as? CacheError {
            switch cacheError {
            case .unavailable:
                DebugLogger.shared.log(
                    "\(operation): cache unavailable",
                    level: .error,
                    category: .cache
                )
            case .sqlite(let code, let message, let op):
                DebugLogger.shared.log(
                    "\(operation): SQLite error (code \(code)) in \(op): \(message)",
                    level: .error,
                    category: .cache
                )
            }
        } else {
            DebugLogger.shared.log(
                "\(operation): \(error.localizedDescription)",
                level: .error,
                category: .cache
            )
        }
    }
}
