## Context

The current glossary system stores named translation lists inside an SQLite database managed by `GlossaryService`. Users manage these lists using a toolbar modal sheet (`GlossaryView`) that houses a list of terms and options to create/delete glossaries.
However, there is no way to rename an existing glossary. To provide a premium macOS experience, we want to add a rename capability and migrate the entire glossary editing/viewing UI into the centralized macOS `SettingsView` (accessible via Cmd+,).

## Goals / Non-Goals

**Goals:**
- Implement `renameGlossary` in the database and service layer.
- Enforce a deterministic glossary-name normalization contract: trim leading/trailing whitespace, reject empty or whitespace-only names, and truncate names longer than 20 characters before saving.
- Update `SettingsView` with a dedicated **Glossary** tab styled natively in a grouped `.formStyle(.grouped)` layout.
- Bind the selected settings tab to a shared in-memory identifier in `PreferencesService` to enable toolbar deep-linking.
- Implement inline renaming (Option B) with `@FocusState` management directly in the settings panel.

**Non-Goals:**
- Restructuring the database schema (no migration needed; `name` field in `glossaries` is already a variable-length text field).
- Introducing persistent tab selection state to `UserDefaults` (it should reset to API Keys tab on fresh app launch).

## Decisions

### Decision 1: Shared-State Navigation Bridge
We will use a shared in-memory `@Published var activeTabIdentifier: String` inside `PreferencesService` to communicate tab selection between the main window (`ContentView`) and the settings window.
- **Alternative 1 (NotificationCenter)**: Dispatch custom NotificationCenter notifications.
  - *Trade-off*: Disparate listener registration, boilerplate-heavy, and non-reactive in SwiftUI.
- **Alternative 2 (Direct bindings)**: Pass bindings across the Window scenes.
  - *Trade-off*: Unsupported in SwiftUI 4+ since Window scenes are declared independently at the root App level.
- **Rationale**: Both views already share the same injected instance of `PreferencesService`, making it the perfect single source of truth for routing.

The identifier contract is explicit:
- Supported values are `"apiKeys"`, `"preferences"`, `"debug"`, `"about"`, and `"glossary"`.
- `PreferencesService.activeTabIdentifier` defaults to `"apiKeys"` at process start and is never persisted to `UserDefaults`.
- `SettingsView` maps identifiers to `SettingsTab` values. Unknown identifiers fall back to `.apiKeys` and should write `"apiKeys"` back to `activeTabIdentifier` so the shared state is normalized.
- Manual tab selection inside `SettingsView` updates `activeTabIdentifier` so the shared routing state matches the visible tab.
- Main-window glossary management sets `activeTabIdentifier = "glossary"` before invoking `openWindow(id: "settings")`. An already-open Settings window must react to the published change and switch to the Glossary tab.

### Decision 2: Embedded Reusability via `GlossaryView` Refactoring
We will refactor `GlossaryView` by introducing an `isEmbedded: Bool` parameter instead of creating a separate, duplicate view.
- **Alternative 1 (Duplicate Settings view)**: Write `SettingsGlossaryView.swift` from scratch.
  - *Trade-off*: Replicates 250+ lines of term lists, CRUD sheet logic, deletion swipes, and SQLite error handling, creating a maintenance nightmare.
- **Rationale**: Adding `isEmbedded` allows reusing all term management sheets and CRUD handlers, and simply toggling between a standalone Sheet layout and a polished, Grouped Form settings tab layout. The production entry point moves to Settings, but `isEmbedded == false` remains as a compatibility branch for previews, tests, and any existing direct construction during the transition.

### Decision 3: Character Limit & Validation Enforcement
A 20-character limit and non-empty check will be enforced at both the UI and service levels using the same normalization rules.
- **Normalization**: `trimmingCharacters(in: .whitespacesAndNewlines)` runs first. If the trimmed value is empty, the mutation throws a validation error and the database is not touched. If the trimmed value exceeds 20 characters, the value is truncated to its first 20 Swift `Character` values before persistence.
- **UI Level**: Text inputs (`.onChange(of: name)`) mirror this behavior for immediate feedback: keep the editable value within 20 characters and disable create/save when the trimmed value is empty.
- **Service Level**: `GlossaryService.createGlossary(name:)` and `GlossaryService.renameGlossary(id:newName:)` apply the same normalization before firing SQL. This protects programmatic callers and tests.
- **Validation Error**: Empty names should throw a structured non-SQLite validation error, not a SQLite error, because SQLite is not rejecting the value.
- **Rationale**: This keeps UI behavior and service behavior aligned: overlong names are accepted after deterministic truncation; empty names are rejected.

### Decision 4: Toolbar Management Entry Point
The main toolbar Glossary control remains a picker/menu for quickly choosing the active glossary. The deep-link behavior applies to the `Manage Glossaries...` menu item, not to opening the picker itself.
- **Rationale**: Users still need fast access to select `None` or switch active glossaries without leaving the main window. Management actions move to Settings.

## Risks / Trade-offs

- **[Risk] Multiple Settings window instances**
  - *Mitigation*: SwiftUI's `openWindow(id:)` is natively idempotent on macOS. Invoking it multiple times with the same ID automatically focuses and brings the existing settings window to the foreground without spawning duplicates.
- **[Risk] Input commit timing on rename**
  - *Mitigation*: Re-commit the rename both on Enter submission (`onSubmit`) and when the text field loses focus (`.onChange(of: isNameFieldFocused)`). This ensures any edits are safely stored when clicking away.
- **[Risk] Duplicate rename commits**
  - *Mitigation*: The commit helper should compare the normalized input to the current active glossary name and no-op when unchanged. This prevents Enter and focus loss from issuing duplicate `UPDATE`s.
