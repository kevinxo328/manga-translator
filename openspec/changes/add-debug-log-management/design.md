## Context

The codebase already uses `Logger` in some services and `print` in others. `Logger` provides useful Xcode and Console visibility, but it is not an app-owned storage layer and does not provide clear semantics for app-level querying, clearing, or export.

The app already stores user data under `Application Support/MangaTranslator` and already uses SQLite through `CacheService`. That makes a persistent SQLite-backed debug log store a natural fit for production diagnostics and Settings-based inspection.

## Goals / Non-Goals

**Goals:**
- Preserve the existing development experience where logs appear in Xcode.
- Provide a production-safe, app-owned debug log store.
- Support query, filter, clear, and export from Settings.
- Define deterministic retention / rotation behavior owned by the app.
- Reduce accidental leakage of sensitive response bodies and credentials.
- Route all production app logging through the shared debug logging facade.

**Non-Goals:**
- Reading back arbitrary system-wide unified logs as the primary data source.
- Clearing or rotating Apple unified logging history.
- Capturing logs emitted by third-party processes outside the app's control.
- Building a remote log upload pipeline in this change.
- Migrating test-only, benchmark-only, CLI-only, or vendor logging unless it is part of the production app target.

## Decisions

### 1. Use a dual-sink logger with one canonical event

**Decision**: Introduce a shared debug logging facade that creates one structured event and fans it out to:

- `os.Logger` for Xcode / Console visibility
- a persistent app-owned log store for production inspection

**Why**: This preserves the current developer experience while giving the app deterministic control over querying, clearing, exporting, and retention.

**Why not use unified logging as the source of truth**: App-level features such as clear/export/retention should not depend on system-managed log storage policies or privileged readback behavior.

### 2. Make the persistent store the Settings data source

**Decision**: The Settings Debug tab reads only from the app-owned persistent log store.

**Why**: This gives stable semantics:

- query/filter operates on known structured fields
- clear only affects app-owned data
- export produces deterministic results

V1 migrates production app logging to the shared facade. Existing direct `Logger(...)`, `print(...)`, and `NSLog(...)` usage in production app code must be removed, replaced by the facade, or explicitly deleted when the log has low diagnostic value.

### 3. Store logs in SQLite under Application Support

**Decision**: Use a dedicated SQLite database at `Application Support/MangaTranslator/debug_logs.sqlite` for persistent debug logs.

**Why**:

- the app already uses SQLite successfully
- log retention, clear, and migration do not touch translation cache data
- filter/query/pagination are easier than with flat files
- retention and bulk delete operations are straightforward
- debug log database failures do not affect `cache.sqlite`

**Alternative considered**: NDJSON files with file rotation. Rejected because filtering and partial clear operations are clumsier, and schema evolution is less controlled.

**Alternative considered**: Reuse `cache.sqlite`. Rejected because log churn, retention, and failure handling should be isolated from translation cache storage.

The persistent store uses its own schema version. V1 initializes schema version `1`. Future schema changes should use forward migrations. If opening the database or applying a migration fails, the persistent sink is disabled for that launch and the app continues to emit `os.Logger` events.

### 4. Define retention as app-owned rotation, not system-owned retention

**Decision**: The persistent log store will implement automatic eviction using dual thresholds:

- time-based retention: keep only the most recent 14 days
- count-based retention: keep at most the newest 10,000 entries

**Why**: Time-based retention prevents indefinite accumulation. Count-based retention protects against bursts. Together they keep storage bounded without depending on file size heuristics alone.

**Operational semantics**:

- rotation runs on app launch and after each 100 persisted inserts
- clearing logs from Settings deletes matching rows from the persistent store only
- `os.Logger` history is unaffected
- content logs use the same 14-day / 10,000-entry retention policy as operational logs
- export does not trigger rotation, so the exported dataset matches the user's current query result

### 5. Use asynchronous persistent writes

**Decision**: The persistent sink writes through a single background writer actor or equivalent serial executor.

**Why**:

- app code that emits logs should not block user-facing work on SQLite I/O
- a single writer avoids concurrent access problems on one SQLite connection
- queries, deletes, exports, and inserts go through one serialized store boundary

The logging facade emits to `os.Logger` immediately and queues persistent writes. If a persistent write fails, the failure is logged to `os.Logger` and does not fail the caller's feature workflow.

Flush behavior is best-effort:

- pending logs should be flushed periodically by the writer
- app termination should attempt to flush pending logs
- crashes may lose the last queued entries
- V1 does not trade main-flow responsiveness for crash-safe logging

### 6. Define a structured log schema

**Decision**: Each persisted event includes at minimum:

- timestamp
- level
- category
- message
- metadata blob
- session identifier
- source context
- log kind
- absolute file path when a file path is relevant

**Why**: This supports filtering, export, and future diagnostic correlations without requiring free-form string parsing.

The session identifier is an app launch session. A new `session_id` is generated when the app starts, and every debug event emitted during that run uses that same value. V1 does not define per-translation job sessions.

V1 uses five log levels:

- `debug`: detailed diagnostics and development tracing
- `info`: normal workflow events
- `warning`: recoverable abnormal conditions, retries, and fallback paths
- `error`: user-visible or feature-level failures
- `fault`: severe errors or states that should be impossible

V1 uses a fixed category dictionary:

- `app.lifecycle`
- `settings`
- `file.input`
- `ocr.router`
- `ocr.manga`
- `ocr.paddle`
- `translation.openai`
- `translation.google`
- `translation.deepl`
- `translation.copilot`
- `cache`
- `model.download`
- `keychain`
- `export`
- `debug.log`

Log kind distinguishes:

- `operational`: system behavior, state transitions, and failures
- `content`: OCR source text and translated text

Content logs are recorded by default in V1. OCR source text and translated text may be persisted and exported, and they use the same retention policy as operational logs.

### 7. Handle sensitive credentials and response payloads before writing either sink

**Decision**: The shared facade will treat tokens and credential-like values as non-loggable. Raw API response bodies are not logged by default. When diagnostics are needed for API calls, log bounded metadata such as status code, endpoint, response size, parse success, or item count.

**Why**: The current `print` of raw Copilot model payloads is exactly the class of issue this system should prevent from spreading into both console and exported diagnostics.

Path handling is intentionally complete for local diagnostics: file paths are recorded as absolute paths when relevant. Base URLs are recorded in sanitized form, excluding query string, fragment, and embedded credentials.

### 8. Add a dedicated Debug tab in Settings

**Decision**: Add a Debug tab to `SettingsView` for log inspection and management instead of mixing log controls into the existing Preferences tab.

**Why**:

- keeps operational tooling separate from user preferences
- avoids overcrowding the existing Preferences tab
- makes future diagnostic tools easier to group

### 9. Query with bounded SwiftUI pagination

**Decision**: Query results are sorted newest-first and presented in bounded pages.

Query semantics:

- default sort: `timestamp DESC, id DESC`
- first page size: 100 entries
- Load More page size: 100 entries
- maximum entries held by the SwiftUI result list: 500
- filter changes reset pagination and reload from the first page
- export is not limited by the UI-loaded entries

**Why**: Debug logs can include full OCR and translated text. Keeping the SwiftUI list to a small working set avoids making the Settings window responsible for rendering large content-heavy datasets.

V1 filters include:

- level
- category
- kind (`operational` or `content`)
- session (`current` or `all`)
- time range
- text query

Text search covers:

- message
- category
- metadata JSON
- content log message text
- absolute file path

Text search should be debounced, with 300 ms as the target debounce interval.

### 10. Export filtered logs as NDJSON

**Decision**: Export uses newline-delimited JSON (`.ndjson`) and exports the full filtered dataset, not only the entries currently loaded in the SwiftUI list.

**Why**: Logs are naturally one event per line. NDJSON supports streaming output, is convenient for command-line tools, and avoids requiring one large JSON array in memory.

Export semantics:

- default filename: `manga-translator-debug-logs-YYYYMMDD-HHMMSS.ndjson`
- save flow: `NSSavePanel`
- exported rows match the active filters
- export preserves query ordering
- export does not add a separate header row
- each event includes its own context fields
- export runs asynchronously and does not block the Settings UI
- if the filtered result contains content logs, the UI warns that the export includes OCR / translated text

Each exported event includes:

- `id`
- `timestamp`
- `level`
- `category`
- `kind`
- `message`
- `metadata`
- `session_id`
- `source`
- `file_path`

### 11. Use a SwiftUI List with detail sheet for V1

**Decision**: V1 uses a compact SwiftUI `List` for results and a detail sheet for full log content.

**Why**: The Settings window is narrow, and `List` is a better fit than a wide `Table` for the existing layout. Full OCR and translated text should not expand inside each row.

Row content:

- timestamp
- level badge
- category
- first line of message

Detail sheet content:

- full message
- metadata
- file path
- session id
- source context

V1 does not include live streaming. Users refresh or change filters to reload logs. Clear and export actions operate on the active filter. Clear confirmation shows the number of matching rows that will be deleted, and clearing preserves the active filter before reloading results.

The existing Settings window size is preserved for V1. The Debug tab must fit the existing compact window by using bounded lists, compact filter controls, detail sheets, and explicit Load More behavior.

### 12. Enforce facade-only production logging

**Decision**: Add a test or script guard that prevents production app code under `MangaTranslator/` from introducing direct logging APIs.

Forbidden in production app code:

- bare `print(`
- `NSLog(`
- direct construction of `Logger(`

Allowed scopes:

- tests
- benchmark targets
- CLI-only tools
- vendor code
- explicit whitelist entries when a direct system logger is required

**Why**: The debug system only remains useful if production app logs consistently flow through the facade. A guard prevents drift after the initial migration.

## Data Model Sketch

```text
debug_log_entries
  id
  timestamp
  level
  category
  kind
  message
  metadata_json
  session_id
  source_file_or_component
  file_path
  exportable
```

Notes:

- `metadata_json` is intentionally structured so filters can evolve without re-parsing message text.
- `exportable` allows future exclusion of internal-only or privacy-sensitive events from Settings export.
- `file_path` stores an absolute local path when the event is file-specific.

## Settings Debug UX

The Debug tab should support:

- text search over message/category/metadata/content/file path
- filtering by level
- filtering by category
- filtering by kind
- filtering by current session vs all sessions
- filtering by time range
- clear all logs
- clear filtered results
- export filtered results
- loading more results up to the UI cap

The first implementation does not include live streaming. A refresh-based experience is acceptable.

## Risks / Trade-offs

- [Migration scope] V1 touches all production app logging, so implementation must distinguish app target code from tests, tools, and vendor code.
- [Storage growth] Without aggressive enough retention, production logs could still grow too quickly.
- [Credential leakage] Structured logging helps, but only if call sites avoid logging tokens, authorization headers, and raw API response bodies.
- [UI density] The current Settings window is small, so the Debug tab may need pagination, truncation, or a secondary sheet for export options.

## Deferred

- User-configurable retention thresholds are deferred. V1 uses fixed 14-day and 10,000-entry thresholds.
