## ADDED Requirements

### Requirement: Static cache access is synchronized
`KeychainService` SHALL synchronize every read and write of its process-wide static in-memory API-key cache. The synchronization SHALL cover cache lookup, cache insertion or replacement, cache eviction, and full cache clearing. The service SHALL keep its existing synchronous public API and SHALL NOT require callers to use async cache access.

#### Scenario: Bounded concurrent cache access during translation pipeline
- **WHEN** up to three async tasks concurrently call `store(_:for:)`, `retrieve(for:)`, `delete(for:)`, or `hasKey(for:)` for DeepL, Google, and OpenAI API keys
- **THEN** the in-memory cache access does not crash, corrupt the Swift `Dictionary`, or expose a data race in the cache access path

#### Scenario: Final deterministic operation wins after bounded concurrent access
- **WHEN** bounded concurrent cache operations complete and the caller then performs a deterministic final successful `store(_:for:)` for an engine
- **THEN** a subsequent `retrieve(for:)` for that engine returns the final stored value

#### Scenario: Cache clearing is synchronized
- **WHEN** `clearCache()` is called before, after, or between API-key cache operations
- **THEN** the full-cache mutation uses the same synchronization boundary as per-engine cache lookup, insertion, replacement, and eviction
