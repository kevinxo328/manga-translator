## 1. Database & Service Layer

- [ ] 1.1 Add a structured glossary-name validation error for empty or whitespace-only names
- [ ] 1.2 Implement shared glossary-name normalization in `GlossaryService.swift`: trim whitespace/newlines, reject empty names before SQL, and truncate names longer than 20 Swift `Character` values
- [ ] 1.3 Implement `renameGlossary(id:newName:)` in `GlossaryService.swift` using the shared normalization helper
- [ ] 1.4 Update `createGlossary(name:)` in `GlossaryService.swift` to use the same normalization helper
- [ ] 1.5 Add unit tests to `CacheServiceTests.swift` for create normalization, rename success, empty-name rejection without SQL side effects, and 20-character truncation
- [ ] 1.6 Run and verify database tests pass successfully

## 2. Settings Navigation & Infrastructure

- [ ] 2.1 Add in-memory `@Published var activeTabIdentifier: String = "apiKeys"` to `PreferencesService.swift`
- [ ] 2.2 Add tests proving `activeTabIdentifier` is not persisted to `UserDefaults`
- [ ] 2.3 Add new `.glossary` option to `SettingsTab` enum in `SettingsView.swift`
- [ ] 2.4 Define explicit string mapping for `"apiKeys"`, `"preferences"`, `"debug"`, `"about"`, and `"glossary"`, with unknown identifiers falling back to `"apiKeys"`
- [ ] 2.5 Modify `SettingsView` to accept `viewModel: TranslationViewModel` as an `@ObservedObject`
- [ ] 2.6 Bind `selectedTab` to `preferences.activeTabIdentifier` in `SettingsView.swift` so manual tab selection updates the identifier and external identifier changes update the visible tab
- [ ] 2.7 Update `MangaTranslatorApp.swift` to pass `viewModel` to `SettingsView`
- [ ] 2.8 Integrate `GlossaryView` into `SettingsView` under the new `.glossary` tab detail view: `GlossaryView(viewModel: viewModel, isEmbedded: true)`
- [ ] 2.9 Add focused tests or view inspection coverage for identifier fallback and Glossary tab deep-link state

## 3. Glossary View Refactoring & Style Alignment

- [ ] 3.1 Introduce `isEmbedded: Bool` and local `@State` (`glossaryNameInput`, focus states) in `GlossaryView.swift`
- [ ] 3.2 Implement a custom grouped `.formStyle(.grouped)` `Form` layout inside `GlossaryView` when `isEmbedded == true`
- [ ] 3.3 Add the Glossary Configuration section: active glossary `Picker`, Create and Delete buttons
- [ ] 3.4 Implement inline renaming `TextField` for the active glossary with a 20-character maximum truncation rule and `@FocusState` handling (submitting or losing focus triggers `renameGlossary`)
- [ ] 3.5 Ensure the rename commit helper no-ops when the normalized input matches the current glossary name, preventing duplicate commits from Enter plus focus loss
- [ ] 3.6 Render terms list inside native Form grouped rows with hover pencil/trash actions and a clean "+ Add Term" trigger
- [ ] 3.7 Ensure the original modal sheet style remains unchanged when `isEmbedded == false` for preview/test compatibility during the transition

## 4. Main Window Toolbar Routing

- [ ] 4.1 Keep the toolbar Glossary control as an active-glossary picker/menu
- [ ] 4.2 Update the `Manage Glossaries...` toolbar menu item in `ContentView.swift` to set `preferences.activeTabIdentifier = "glossary"` and invoke `openWindow(id: "settings")`
- [ ] 4.3 Remove the deprecated `.sheet(isPresented: $showGlossarySheet)` presentation of `GlossaryView` in `ContentView.swift`
- [ ] 4.4 Remove `showGlossarySheet` state if it has no remaining caller
- [ ] 4.5 Verify compilation and perform manual end-to-end routing and interaction verification: active glossary selection still works from the toolbar, `Manage Glossaries...` opens Settings to Glossary, Cmd+, still opens Settings, rename updates all pickers, empty rename is rejected, and overlong names truncate to 20 characters
