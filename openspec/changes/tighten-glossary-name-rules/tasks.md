## 1. Service Validation Tests

- [ ] 1.1 Add failing `GlossaryService` create tests for over-20-character names throwing `GlossaryValidationError.nameTooLong(max: 20)` and inserting no truncated row.
- [ ] 1.2 Add failing `GlossaryService` rename tests for over-20-character names throwing `GlossaryValidationError.nameTooLong(max: 20)` and preserving the existing name.
- [ ] 1.3 Add failing `GlossaryService` create tests for duplicate normalized names: `"Characters"` followed by `"  Characters  "` throws `GlossaryValidationError.duplicateName` and inserts no row.
- [ ] 1.4 Add failing `GlossaryService` rename tests for duplicate normalized names: renaming `"Places"` to `"  Characters  "` throws `GlossaryValidationError.duplicateName` and preserves both names.
- [ ] 1.5 Add failing `GlossaryService` tests proving duplicate comparison is case-sensitive: `"Characters"` and `"characters"` can coexist.
- [ ] 1.6 Add failing `GlossaryService` rename test proving renaming a glossary to its own normalized name is valid and ignores the row being renamed.
- [ ] 1.7 Keep existing empty-name tests and update any truncation-expectation tests to assert explicit validation failure instead.

## 2. Service Implementation

- [ ] 2.1 Extend `GlossaryValidationError` with `nameTooLong(max: Int)` and `duplicateName`, preserving existing `emptyName` behavior.
- [ ] 2.2 Replace truncating name normalization with validation that trims first, rejects empty, rejects names whose trimmed value exceeds 20 Swift `Character` values, and returns the trimmed name unchanged when valid.
- [ ] 2.3 Add duplicate-name validation before create SQL using exact case-sensitive comparison against persisted glossary names.
- [ ] 2.4 Add duplicate-name validation before rename SQL using exact case-sensitive comparison against persisted glossary names while excluding the row whose `id` is being renamed.
- [ ] 2.5 Ensure create and rename validation failures occur before SQL prepare/step and do not mutate database rows.

## 3. View Model and UI Tests

- [ ] 3.1 Add failing view-model tests proving failed create does not append a glossary, change `activeGlossaryID`, or report success for empty, overlong, or duplicate names.
- [ ] 3.2 Add failing view-model tests proving failed rename does not change the cached glossary name or active selection for empty, overlong, or duplicate names.
- [ ] 3.3 Add failing Settings Glossary tab tests or UI-adjacent unit tests for create sheet validation feedback and disabled confirmation for empty, overlong, and duplicate names.
- [ ] 3.4 Add failing Settings Glossary tab tests or UI-adjacent unit tests for rename sheet validation feedback and disabled confirmation for empty, overlong, and duplicate names.

## 4. View Model and UI Implementation

- [ ] 4.1 Map `GlossaryValidationError.emptyName`, `.nameTooLong(max:)`, and `.duplicateName` to specific user-facing validation messages for create and rename flows.
- [ ] 4.2 Update create flow so service validation errors are surfaced and no in-memory glossary list or active selection state is updated as if creation succeeded.
- [ ] 4.3 Update rename flow so service validation errors are surfaced and no in-memory glossary list entry is changed as if rename succeeded.
- [ ] 4.4 Update create and rename sheets to trim for validation preview, count Swift `Character` values, detect duplicate names with exact case-sensitive comparison, show specific validation feedback, and disable confirmation while invalid.
- [ ] 4.5 Ensure UI pre-validation mirrors service behavior but service validation remains authoritative for all persistence paths.

## 5. Verification

- [ ] 5.1 Run targeted glossary validation tests in `MangaTranslatorTests/CacheServiceTests`.
- [ ] 5.2 Run targeted glossary view-model and Settings Glossary tab tests.
- [ ] 5.3 Run the main `MangaTranslator` test scheme with `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -destination 'platform=macOS'`.
- [ ] 5.4 Run `openspec status --change "tighten-glossary-name-rules"` and confirm all artifacts are complete and ready for implementation.
- [ ] 5.5 Review proposal, design, spec, and tasks for consistency: no remaining truncation requirement, duplicate comparison is exact case-sensitive everywhere, rename excludes its own row, and no schema migration is required.
