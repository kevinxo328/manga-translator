## 1. Modify translatePage to support cache bypass

- [x] 1.1 Add `bypassCache: Bool = false` parameter to `translatePage(at:)` in `TranslationViewModel.swift`
- [x] 1.2 When `bypassCache` is `true`, skip the cache lookup early return but keep the cache store at the end

## 2. Update retranslate entry point

- [x] 2.1 Update `retranslateCurrentPage()` to call `translatePage(at: currentPageIndex, bypassCache: true)`
- [x] 2.2 Remove the `retranslateFromOCR()` method entirely

## 3. Verify UI integration

- [x] 3.1 Confirm `TranslationSidebar` re-translate button calls `retranslateCurrentPage()` (no UI changes needed)
- [x] 3.2 Verify loading state and error handling work correctly with the full OCR + translate pipeline
