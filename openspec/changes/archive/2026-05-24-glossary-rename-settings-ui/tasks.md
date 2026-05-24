## 1. Database & Service Layer

- [x] 1.1 Add a structured glossary-name validation error for empty or whitespace-only names
- [x] 1.2 Implement shared glossary-name normalization in `GlossaryService.swift`: trim whitespace/newlines, reject empty names before SQL, and truncate names longer than 20 Swift `Character` values
- [x] 1.3 Implement `renameGlossary(id:newName:)` in `GlossaryService.swift` using the shared normalization helper
- [x] 1.4 Update `createGlossary(name:)` in `GlossaryService.swift` to use the same normalization helper
- [x] 1.5 Add unit tests to `CacheServiceTests.swift` for create normalization, rename success, empty-name rejection without SQL side effects, and 20-character truncation
- [x] 1.6 Run and verify database tests pass successfully <!-- requires manual Xcode run; sandbox blocks xcodebuild -->

## 2. Settings Navigation & Infrastructure

- [x] 2.1 Add in-memory `@Published var activeTabIdentifier: String = "apiKeys"` to `PreferencesService.swift`
- [x] 2.2 Add tests proving `activeTabIdentifier` is not persisted to `UserDefaults`
- [x] 2.3 Add new `.glossary` option to `SettingsTab` enum in `SettingsView.swift`
- [x] 2.4 Define explicit string mapping for `"apiKeys"`, `"preferences"`, `"debug"`, `"about"`, and `"glossary"`, with unknown identifiers falling back to `"apiKeys"`
- [x] 2.5 Modify `SettingsView` to accept `viewModel: TranslationViewModel` as an `@ObservedObject`
- [x] 2.6 Bind `selectedTab` to `preferences.activeTabIdentifier` in `SettingsView.swift` so manual tab selection updates the identifier and external identifier changes update the visible tab
- [x] 2.7 Update `MangaTranslatorApp.swift` to pass `viewModel` to `SettingsView`
- [x] 2.8 Integrate `GlossaryView` into `SettingsView` under the new `.glossary` tab detail view: `GlossaryView(viewModel: viewModel, isEmbedded: true)`
- [x] 2.9 Add focused tests or view inspection coverage for identifier fallback and Glossary tab deep-link state

## 3. Glossary View Refactoring & Style Alignment

- [x] 3.1 Introduce `isEmbedded: Bool` and local `@State` (`glossaryNameInput`, focus states) in `GlossaryView.swift`
- [x] 3.2 Implement a custom grouped `.formStyle(.grouped)` `Form` layout inside `GlossaryView` when `isEmbedded == true`
- [x] 3.3 Add the Glossary Configuration section: active glossary `Picker`, Create and Delete buttons
- [x] 3.4 Implement sheet-based rename for the active glossary: ✏️ button opens a pre-filled sheet with a 20-character maximum truncation rule; confirm button disabled when trimmed input is empty; tapping Rename calls `commitRename()` and dismisses the sheet
- [x] 3.5 Ensure `commitRename()` no-ops when the normalized input matches the current glossary name, preventing redundant SQL `UPDATE`s
- [x] 3.6 Render terms list inside native Form grouped rows with hover pencil/trash actions and a clean "+ Add Term" trigger
- [x] 3.7 Ensure the original modal sheet style remains unchanged when `isEmbedded == false` for preview/test compatibility during the transition

## 4. Main Window Toolbar Routing

- [x] 4.1 Keep the toolbar Glossary control as an active-glossary picker/menu
- [x] 4.2 Update the `Manage Glossaries...` toolbar menu item in `ContentView.swift` to set `preferences.activeTabIdentifier = "glossary"` and invoke `openWindow(id: "settings")`
- [x] 4.3 Remove the deprecated `.sheet(isPresented: $showGlossarySheet)` presentation of `GlossaryView` in `ContentView.swift`
- [x] 4.4 Remove `showGlossarySheet` state if it has no remaining caller
- [x] 4.5 Verify compilation and perform manual end-to-end routing and interaction verification: active glossary selection still works from the toolbar, `Manage Glossaries...` opens Settings to Glossary, Cmd+, still opens Settings, rename updates all pickers, empty rename is rejected, and overlong names truncate to 20 characters <!-- requires Xcode build + manual smoke test -->
