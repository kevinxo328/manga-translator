## Context

`GlossaryService` currently normalizes glossary names by trimming leading and trailing whitespace/newlines, rejecting empty names, and silently truncating names longer than 20 Swift `Character` values. This normalization is used by both create and rename persistence paths.

The current behavior leaves two product issues:

- Multiple glossaries can share the same displayed name, making menu and settings pickers ambiguous.
- Overlong names are persisted as a value the user did not explicitly confirm.

The change affects service validation, caller error handling, and the Settings Glossary tab. It does not require a schema migration because duplicate prevention can be enforced before executing create or rename SQL.

## Goals / Non-Goals

**Goals:**

- Define one canonical validation contract for glossary names used by both create and rename.
- Reject empty, overlong, and duplicate normalized names before mutating SQLite state.
- Keep duplicate comparison deterministic and testable: exact, case-sensitive match of the normalized persisted name.
- Make validation failures visible to users in create and rename flows without changing selection state as if the operation succeeded.
- Preserve existing glossary rows unless the user explicitly performs a valid create, rename, or delete.

**Non-Goals:**

- No database schema migration or unique SQLite index.
- No case-insensitive, locale-aware, or Unicode-normalized duplicate matching.
- No automatic migration, renaming, merging, or deletion of existing duplicate glossary rows.
- No changes to glossary term validation, term ordering, translation context injection, or LLM auto-detected term behavior.

## Decisions

1. Keep `GlossaryService` as the source of truth for validation.

   `createGlossary(name:)` and `renameGlossary(id:newName:)` will both call a shared validation path before preparing SQL. UI-level checks are only early feedback and must not be relied on for correctness. This keeps non-UI callers and tests under the same contract.

   Alternative considered: validate only in view models or SwiftUI forms. That would leave direct service callers able to create invalid rows.

2. Replace truncation with explicit `nameTooLong(max: 20)`.

   A name longer than 20 Swift `Character` values after trimming will throw `GlossaryValidationError.nameTooLong(max: 20)`. The service will not persist a shortened value. This makes the stored value match the user's confirmed input.

   Alternative considered: keep truncation in the service and only show a UI character counter. That still permits silent truncation from tests or non-UI callers.

3. Reject duplicate normalized names with exact case-sensitive comparison.

   Duplicate checks compare the trimmed candidate name to existing persisted names using Swift `String` equality. `Characters` and `characters` are distinct names. Leading/trailing whitespace does not make a name unique because it is removed before comparison.

   Alternative considered: case-insensitive or localized duplicate matching. That creates language and Unicode edge cases outside the current feature scope.

4. Allow a rename to keep the same normalized name for the same glossary.

   `renameGlossary(id:newName:)` must not fail as duplicate when the only matching glossary row has the same `id`. This preserves no-op and whitespace-only normalization flows such as renaming `Characters` to ` Characters `.

   Alternative considered: treat same-name rename as duplicate. That would make harmless edits fail and complicate the rename sheet.

5. Preserve existing duplicate rows until touched.

   No migration will scan or rewrite existing duplicate names. The new rule applies to create and rename requests after implementation. Existing duplicates remain listable/selectable by id, but future create or rename calls cannot introduce a duplicate normalized name.

   Alternative considered: migrate existing duplicates. That risks surprising users by renaming or merging data without an explicit user action.

6. Surface validation errors consistently in UI state.

   Create and rename flows will show a user-facing validation message for `emptyName`, `nameTooLong(max:)`, and `duplicateName`. On failure, the view model will not append a glossary, change `activeGlossaryID`, or update cached glossary names as if persistence succeeded.

   Alternative considered: log service errors only. That leaves the user without a clear recovery path.

## Risks / Trade-offs

- Existing duplicates can remain visible → Mitigation: the rule is enforced on all future create/rename mutations, and existing rows stay addressable by stable ids.
- Exact case-sensitive duplicate matching may still permit visually similar names → Mitigation: this is explicitly out of scope and avoids locale/Unicode ambiguity.
- Removing truncation can reject names that previously succeeded → Mitigation: the error is structured, UI can provide immediate feedback, and the proposal marks this as a breaking caller behavior change.
- Duplicate checks outside a SQLite unique index are not a hard database constraint → Mitigation: the app owns glossary mutations through `GlossaryService`; adding a schema migration is intentionally out of scope for this small validation tightening.
