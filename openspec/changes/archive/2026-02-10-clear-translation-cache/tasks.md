## 1. CacheService

- [x] 1.1 Add `clearAll()` method to `CacheService` that executes `DELETE FROM translation_cache`

## 2. TranslationViewModel

- [x] 2.1 Add `clearCacheAndResetPages()` method that calls `cacheService.clearAll()` and resets all `pages[].state` to `.pending`

## 3. SettingsView

- [x] 3.1 Add `onClearCache: (() -> Void)?` parameter to `SettingsView`
- [x] 3.2 Add "Clear Cache" button with confirmation alert in the Preferences tab
- [x] 3.3 Wire up the closure from the call site where `SettingsView` is opened
