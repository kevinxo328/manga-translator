## 1. ViewModel: Re-translate Logic

- [ ] 1.1 Add `retranslateFromOCR()` method to `TranslationViewModel` that extracts `BubbleCluster` array from current `TranslatedBubble` state, calls `translationService.translate()`, stores result via `cacheService.store()`, and updates page state
- [ ] 1.2 Handle error case in `retranslateFromOCR()`: on failure, preserve previous translations and set error message

## 2. UI: Re-translate Button

- [ ] 2.1 Add a re-translate button to `TranslationSidebar` header area, passing a closure from the parent view
- [ ] 2.2 Wire the button action in `ContentView` to call `viewModel.retranslateFromOCR()`
- [ ] 2.3 Disable/hide the button when current page is not in `.translated` state
- [ ] 2.4 Show processing indicator while re-translation is in progress (page state is `.processing`)
