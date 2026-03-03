import SwiftUI

struct GlossaryView: View {
    @ObservedObject var viewModel: TranslationViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showNewGlossarySheet = false
    @State private var newGlossaryName = ""
    @State private var showDeleteGlossaryAlert = false
    @State private var terms: [GlossaryTerm] = []
    @State private var showAddTermSheet = false
    @State private var editingTerm: GlossaryTerm? = nil
    @State private var editSourceTerm = ""
    @State private var editTargetTerm = ""

    private var glossaryService: GlossaryService {
        // Expose through a helper on ViewModel
        viewModel.glossaryServiceForView
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: glossary picker
            HStack {
                Text("Glossary")
                    .font(.headline)

                Spacer()

                Menu {
                    Button("None") { viewModel.activeGlossaryID = nil; terms = [] }
                    Divider()
                    ForEach(viewModel.glossaries) { glossary in
                        Button(glossary.name) {
                            viewModel.activeGlossaryID = glossary.id
                            reloadTerms()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.activeGlossary?.name ?? "None")
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
                            glossaryService.deleteTerm(id: terms[index].id)
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
            Button("Delete", role: .destructive) {
                if let id = viewModel.activeGlossaryID {
                    glossaryService.deleteGlossary(id: id)
                    viewModel.activeGlossaryID = nil
                    viewModel.loadGlossaries()
                    terms = []
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the glossary and all its terms. This action cannot be undone.")
        }
        .sheet(isPresented: $showNewGlossarySheet) {
            newGlossarySheet
        }
        .sheet(isPresented: $showAddTermSheet) {
            termEditSheet
        }
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

    private var newGlossarySheet: some View {
        VStack(spacing: 16) {
            Text("New Glossary")
                .font(.headline)

            TextField("Glossary name", text: $newGlossaryName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { showNewGlossarySheet = false }
                Spacer()
                Button("Create") {
                    let name = newGlossaryName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    if let g = glossaryService.createGlossary(name: name) {
                        viewModel.loadGlossaries()
                        viewModel.activeGlossaryID = g.id
                        reloadTerms()
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
                    if let existing = editingTerm {
                        glossaryService.updateTerm(id: existing.id, sourceTerm: src, targetTerm: tgt)
                    } else if let glossaryID = viewModel.activeGlossaryID {
                        _ = glossaryService.insertTerm(
                            glossaryID: glossaryID,
                            sourceTerm: src,
                            targetTerm: tgt,
                            autoDetected: false
                        )
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
}
