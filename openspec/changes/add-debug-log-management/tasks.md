## 1. Logging Architecture

- [ ] 1.1 Introduce a shared debug logging facade that writes each structured event to both `os.Logger` and a persistent store
- [ ] 1.2 Define log event schema using app launch sessions, five log levels, fixed V1 categories, log kind, and absolute file path support
- [ ] 1.3 Define credential exclusion rules and raw API response metadata rules
- [ ] 1.4 Add content logging support for OCR source text and translated text
- [ ] 1.5 Migrate all production app `Logger(...)`, `print(...)`, and `NSLog(...)` diagnostics to the shared facade or remove low-value logs
- [ ] 1.6 Add an automated guard that rejects direct production app `print(`, `NSLog(`, and non-whitelisted `Logger(` usage

## 2. Persistent Log Store

- [ ] 2.1 Add a persistent debug log store at `Application Support/MangaTranslator/debug_logs.sqlite`
- [ ] 2.2 Initialize schema version `1` and handle migration failure by disabling only the persistent sink
- [ ] 2.3 Implement a single background writer actor or serial executor for inserts, queries, deletes, and exports
- [ ] 2.4 Implement query APIs for search across message/category/metadata/content/file path
- [ ] 2.5 Implement level/category/kind/session/time filters with newest-first ordering
- [ ] 2.6 Implement pagination APIs with 100-entry pages and support for a 500-entry UI cap
- [ ] 2.7 Implement automatic retention / rotation with 14-day and 10,000-entry thresholds
- [ ] 2.8 Trigger rotation on app launch and after each 100 persisted inserts
- [ ] 2.9 Implement best-effort flush on normal app termination
- [ ] 2.10 Implement delete APIs for clear-all and clear-filtered-results
- [ ] 2.11 Implement NDJSON export APIs for full filtered log datasets without pre-export rotation

## 3. Settings Debug UI

- [ ] 3.1 Add a Debug tab to `SettingsView`
- [ ] 3.2 Add SwiftUI list-based results with compact rows, detail sheet, and Load More
- [ ] 3.3 Add controls for level/category/kind/session/time/text filters, refresh, clear, and export
- [ ] 3.4 Debounce text search before reloading query results
- [ ] 3.5 Add clear confirmation with matching row count and preserve filters after clear
- [ ] 3.6 Add `NSSavePanel` export flow with `.ndjson` filename and content-log warning
- [ ] 3.7 Surface retention semantics clearly so users know clearing affects only app-owned persistent logs
- [ ] 3.8 Preserve existing Settings window dimensions for V1

## 4. Verification

- [ ] 4.1 Add unit tests for schema initialization and migration failure fallback
- [ ] 4.2 Add unit tests for insert/query/filter/pagination behavior
- [ ] 4.3 Add unit tests for retention by 14-day age, 10,000-entry cap, and 100-insert trigger
- [ ] 4.4 Add unit tests for content logs being persisted and exported
- [ ] 4.5 Add unit tests for credential/raw-response exclusion
- [ ] 4.6 Add unit tests for DB failure fallback to `os.Logger`
- [ ] 4.7 Add automated guard coverage for direct production logging APIs
- [ ] 4.8 Add UI tests for Debug tab query, detail sheet, clear, and export happy paths
