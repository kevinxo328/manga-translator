## Purpose

App-owned persistent debug log capture, storage, querying, and lifecycle management.
## Requirements
### Requirement: Capture debug events in both development and production
The system SHALL capture app debug events through a shared logging path that writes each event to both `os.Logger` and an app-owned persistent log store. Each event SHALL include an app launch `session_id`, a five-level log level, a fixed category, and a log kind.

#### Scenario: Developer views logs in Xcode
- **WHEN** app code emits a debug event through the shared logging path
- **THEN** the event SHALL appear through the app's `os.Logger` output

#### Scenario: Production log is retained by the app
- **WHEN** app code emits a debug event through the shared logging path
- **THEN** the event SHALL be persisted in the app-owned log store for later inspection

#### Scenario: Event uses current app launch session
- **WHEN** app code emits multiple debug events during one app launch
- **THEN** each event SHALL use the same app launch `session_id`

#### Scenario: Next app launch uses new session
- **WHEN** the app starts after a previous launch ended
- **THEN** the app SHALL generate a new app launch `session_id`

### Requirement: Route production app logging through shared facade
The system SHALL route all production app logging under the `MangaTranslator/` app target through the shared debug logging facade.

#### Scenario: Existing direct Logger usage is migrated
- **WHEN** production app code needs to emit a diagnostic event
- **THEN** it SHALL use the shared debug logging facade instead of constructing `Logger(...)` directly

#### Scenario: Existing print usage is migrated or removed
- **WHEN** production app code contains an existing `print(...)` diagnostic
- **THEN** it SHALL be replaced with the shared debug logging facade or removed when it has low diagnostic value

#### Scenario: Existing NSLog usage is migrated or removed
- **WHEN** production app code contains an existing `NSLog(...)` diagnostic
- **THEN** it SHALL be replaced with the shared debug logging facade or removed when it has low diagnostic value

### Requirement: Prevent direct production logging drift
The system SHALL include an automated guard that rejects direct production app usage of bare `print(`, `NSLog(`, and direct `Logger(` construction unless explicitly whitelisted.

#### Scenario: Production app code adds bare print
- **WHEN** production app code under `MangaTranslator/` introduces a bare `print(`
- **THEN** the guard SHALL fail

#### Scenario: Production app code adds direct Logger construction
- **WHEN** production app code under `MangaTranslator/` introduces direct `Logger(` construction outside an approved whitelist
- **THEN** the guard SHALL fail

#### Scenario: Test and tooling logs are exempt
- **WHEN** test code, benchmark code, CLI-only tools, or vendor code use `print(` or direct `Logger(`
- **THEN** the production logging guard SHALL NOT fail solely because of those usages

### Requirement: Use fixed log levels and categories
The system SHALL classify debug events using exactly the V1 log levels `debug`, `info`, `warning`, `error`, and `fault`. The system SHALL classify event category using the V1 category dictionary.

#### Scenario: Filterable level value
- **WHEN** an event is persisted
- **THEN** its level SHALL be one of `debug`, `info`, `warning`, `error`, or `fault`

#### Scenario: Filterable category value
- **WHEN** an event is persisted
- **THEN** its category SHALL be one of `app.lifecycle`, `settings`, `file.input`, `ocr.router`, `ocr.manga`, `ocr.paddle`, `translation.openai`, `translation.google`, `translation.deepl`, `translation.copilot`, `cache`, `model.download`, `keychain`, `export`, `debug.log`, or `pipeline`

### Requirement: Persist content logs
The system SHALL support content logs for OCR source text and translated text. Content logs SHALL use the same retention policy as operational logs.

#### Scenario: OCR source text is logged
- **WHEN** OCR source text is logged through the shared logging path
- **THEN** the full OCR source text SHALL be persisted as a `content` log

#### Scenario: Translated text is logged
- **WHEN** translated text is logged through the shared logging path
- **THEN** the full translated text SHALL be persisted as a `content` log

#### Scenario: Content logs rotate with operational logs
- **WHEN** the retention process runs
- **THEN** `content` and `operational` logs SHALL be evaluated using the same 14-day and 10,000-entry thresholds

### Requirement: Query and filter persistent debug logs
The system SHALL provide query and filter capabilities over the persistent debug log store using structured fields. Query results SHALL be sorted by `timestamp DESC, id DESC`.

#### Scenario: Filter by level
- **WHEN** the user filters persistent logs to `error`
- **THEN** only `error` entries SHALL be returned

#### Scenario: Filter by category
- **WHEN** the user filters persistent logs to a specific category
- **THEN** only entries matching that category SHALL be returned

#### Scenario: Search by keyword
- **WHEN** the user searches persistent logs with a text query
- **THEN** only entries whose indexed searchable fields match the query SHALL be returned

#### Scenario: Search covers content and paths
- **WHEN** the user searches persistent logs with a text query
- **THEN** the query SHALL search message, category, metadata, content log message text, and absolute file path fields

#### Scenario: Filter by current app session
- **WHEN** the user filters persistent logs to the current session
- **THEN** only entries whose `session_id` matches the current app launch session SHALL be returned

#### Scenario: Filter by kind
- **WHEN** the user filters persistent logs to `content`
- **THEN** only entries whose kind is `content` SHALL be returned

#### Scenario: Filter by time range
- **WHEN** the user applies a time range filter
- **THEN** only entries whose timestamp is inside the selected time range SHALL be returned

### Requirement: Page debug log query results for SwiftUI
The system SHALL support paged query results so the Settings Debug UI can render a bounded result set.

#### Scenario: Initial page
- **WHEN** the Debug UI loads the first query page
- **THEN** the system SHALL return at most 100 entries

#### Scenario: Load more
- **WHEN** the user requests more results
- **THEN** the system SHALL load the next 100 entries matching the active query

#### Scenario: UI result cap
- **WHEN** the Debug UI already holds 500 entries for the active query
- **THEN** the Debug UI SHALL NOT append more entries to the visible result list

#### Scenario: Filter change resets pagination
- **WHEN** the active query filter changes
- **THEN** the Debug UI SHALL discard previous loaded entries and load the first page for the new filter

### Requirement: Clear persistent debug logs
The system SHALL allow users to delete app-owned persistent log entries without affecting Apple unified logging history.

#### Scenario: Clear all logs
- **WHEN** the user confirms a clear-all action from the Debug UI
- **THEN** all entries in the app-owned persistent log store SHALL be deleted

#### Scenario: Clear filtered logs
- **WHEN** the user confirms clearing while a filter is active
- **THEN** only entries matching the active filter SHALL be deleted

#### Scenario: Clearing logs does not clear Xcode history
- **WHEN** persistent logs are cleared from the app
- **THEN** the app SHALL NOT claim to delete prior `os.Logger` / Xcode / unified log history

### Requirement: Export persistent debug logs
The system SHALL allow export of filtered persistent log datasets from the app-owned log store as newline-delimited JSON (`.ndjson`).

#### Scenario: Export filtered result set
- **WHEN** the user exports logs while filters are active
- **THEN** only entries matching the current filter SHALL be included in the export

#### Scenario: Export all filtered rows
- **WHEN** the user exports logs while the UI has loaded only a page of results
- **THEN** the export SHALL include all rows matching the active filter, not only the currently loaded UI entries

#### Scenario: Export preserves query order
- **WHEN** logs are exported
- **THEN** exported entries SHALL be ordered by `timestamp DESC, id DESC`

#### Scenario: Export uses default filename
- **WHEN** the user opens the export save panel
- **THEN** the default filename SHALL match `manga-translator-debug-logs-YYYYMMDD-HHMMSS.ndjson`

#### Scenario: Export writes one event per line
- **WHEN** logs are exported
- **THEN** each line SHALL contain one JSON object representing one log event

#### Scenario: Export contains event context
- **WHEN** a log event is exported
- **THEN** the exported object SHALL include id, timestamp, level, category, kind, message, metadata, session_id, source, and file_path

#### Scenario: Export content warning
- **WHEN** the filtered export dataset includes `content` logs
- **THEN** the UI SHALL warn that the export includes OCR or translated text before writing the file

#### Scenario: Sensitive payloads are not exported raw
- **WHEN** a log event contains sensitive metadata classified as non-exportable
- **THEN** the exported dataset SHALL omit or redact those sensitive fields

### Requirement: Exclude credentials and raw API response bodies
The system SHALL NOT persist API keys, bearer tokens, authorization header values, or raw API response bodies by default. API diagnostics SHALL use bounded metadata instead of raw response payloads.

#### Scenario: Authorization header is logged
- **WHEN** a call site attempts to log an authorization header
- **THEN** the persisted log SHALL omit the credential value

#### Scenario: API response diagnostics are logged
- **WHEN** API response diagnostics are logged
- **THEN** the persisted log SHALL include metadata such as endpoint, status code, response size, parse result, or item count instead of the raw response body

### Requirement: Store local file paths as absolute paths
The system SHALL persist complete absolute local file paths when a debug event is associated with a user-selected or app-managed file path.

#### Scenario: File input path is logged
- **WHEN** a debug event includes a local file path
- **THEN** the persistent log entry SHALL store the absolute path

### Requirement: Apply automatic retention and rotation
The system SHALL automatically evict old persistent log entries using app-owned retention rules.

#### Scenario: Time-based retention
- **WHEN** persistent log entries are older than 14 days
- **THEN** those entries SHALL be eligible for automatic deletion by the retention process

#### Scenario: Count-based retention
- **WHEN** the persistent log store exceeds 10,000 entries
- **THEN** the oldest excess entries SHALL be deleted automatically

#### Scenario: Rotation affects only persistent logs
- **WHEN** the retention process removes old persistent log entries
- **THEN** the app SHALL continue to emit new events to both sinks
- **THEN** Apple unified logging history SHALL remain outside the app's rotation scope

#### Scenario: Rotation runs on launch
- **WHEN** the app starts
- **THEN** the persistent log store SHALL run retention before the Debug UI queries logs

#### Scenario: Rotation runs after insert batches
- **WHEN** the persistent log store has accepted 100 persisted inserts since the last retention run
- **THEN** the persistent log store SHALL run retention

#### Scenario: Export does not rotate first
- **WHEN** the user exports the current filtered log result set
- **THEN** the system SHALL NOT run retention immediately before export
- **THEN** the exported dataset SHALL match the current filtered result set

### Requirement: Store persistent logs in an isolated database
The system SHALL store persistent debug logs in a dedicated SQLite database at `Application Support/MangaTranslator/debug_logs.sqlite`.

#### Scenario: Debug logs do not share translation cache database
- **WHEN** debug logs are persisted
- **THEN** they SHALL be written to `debug_logs.sqlite`
- **THEN** they SHALL NOT be written to `cache.sqlite`

#### Scenario: Debug log schema is initialized
- **WHEN** the persistent log store is created for V1
- **THEN** it SHALL initialize schema version `1`

#### Scenario: Schema migration fails
- **WHEN** the persistent log store cannot apply its required schema migration
- **THEN** persistent logging SHALL be disabled for that launch
- **THEN** the app SHALL continue operating and emitting `os.Logger` events

### Requirement: Write persistent logs asynchronously
The system SHALL write persistent debug logs through a single background writer actor or equivalent serial executor so log calls do not block user-facing workflows on SQLite I/O.

#### Scenario: Log call queues persistent write
- **WHEN** app code emits a debug event through the shared logging path
- **THEN** the event SHALL be emitted to `os.Logger`
- **THEN** the persistent write SHALL be queued through the serialized persistent store boundary

#### Scenario: Persistent write fails
- **WHEN** the persistent store fails to write a queued log event
- **THEN** the failure SHALL be emitted to `os.Logger`
- **THEN** the original app workflow SHALL continue without receiving the persistence failure

#### Scenario: Store access is serialized
- **WHEN** inserts, queries, deletes, or exports access the persistent log store
- **THEN** access SHALL be coordinated through one serialized store boundary

### Requirement: Flush queued logs best-effort
The system SHALL attempt to flush queued persistent logs without guaranteeing crash-safe persistence for the last queued entries.

#### Scenario: App terminates normally
- **WHEN** the app receives a normal termination path
- **THEN** the persistent writer SHALL attempt a best-effort flush of pending log entries

#### Scenario: App crashes
- **WHEN** the app crashes before queued writes are flushed
- **THEN** the system MAY lose the last queued persistent log entries
- **THEN** the system SHALL NOT block normal app workflows to guarantee crash-safe log persistence

### Requirement: Debug tab UI in Settings
The Settings view SHALL provide a dedicated Debug tab for inspection and management of app-owned persistent debug logs. The tab SHALL display log results in a SwiftUI list with at most 100 initially loaded rows, support filtering by level, category, session, and free text, support paged loading up to a 500-row visible cap, debounce search input, surface log details via a detail sheet, keep full content text out of list rows, present clear confirmations with match counts, preserve active filters across clear actions, and export through an `NSSavePanel` with a default `.ndjson` filename. This requirement owns the Settings-tab user flow; data-layer concerns (pagination, retention, isolation, sensitive-payload exclusion) are owned by the other requirements in this capability.

#### Scenario: Open Debug tab
- **WHEN** user opens Settings and selects the Debug tab
- **THEN** the app SHALL display controls to inspect app-owned persistent debug logs

#### Scenario: Filter logs from Settings
- **WHEN** user applies a level, category, session, or text filter in the Debug tab
- **THEN** the displayed log list SHALL update to match the active filter

#### Scenario: Debug tab uses bounded list
- **WHEN** user opens the Debug tab
- **THEN** the app SHALL display log results in a SwiftUI list with at most 100 initially loaded rows

#### Scenario: Debug tab preserves Settings window size
- **WHEN** the Debug tab is added to Settings
- **THEN** V1 SHALL preserve the existing Settings window dimensions
- **THEN** the Debug tab SHALL use compact controls, bounded results, and detail sheets to fit the existing window

#### Scenario: Load more logs
- **WHEN** user clicks Load More in the Debug tab
- **THEN** the app SHALL append the next 100 matching rows up to a visible cap of 500 rows

#### Scenario: Open log detail
- **WHEN** user selects a log row
- **THEN** the app SHALL open a detail sheet with full message, metadata, file path, session id, and source context

#### Scenario: Content text stays out of rows
- **WHEN** a content log appears in the list
- **THEN** the row SHALL show only a compact summary
- **THEN** full OCR or translated text SHALL be shown in the detail sheet

#### Scenario: Search is debounced
- **WHEN** user types into the Debug tab search field
- **THEN** the app SHALL debounce query reloads before reading the persistent log store

#### Scenario: Clear logs from Settings
- **WHEN** user confirms clearing logs from the Debug tab
- **THEN** the matching app-owned persistent log entries SHALL be deleted

#### Scenario: Clear confirmation shows count
- **WHEN** user starts a clear action from the Debug tab
- **THEN** the confirmation SHALL show the number of matching persistent log entries that will be deleted

#### Scenario: Clear preserves filters
- **WHEN** user clears matching logs from the Debug tab
- **THEN** the app SHALL keep the active filters and reload the result list

#### Scenario: Export logs from Settings
- **WHEN** user requests export from the Debug tab
- **THEN** the app SHALL export the currently selected persistent log dataset

#### Scenario: Export uses save panel
- **WHEN** user requests export from the Debug tab
- **THEN** the app SHALL present an `NSSavePanel` with a default `.ndjson` filename

