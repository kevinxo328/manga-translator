## 1. Add `.pipeline` log category

- [ ] 1.1 In `MangaTranslator/Services/DebugLogger.swift`, add `case pipeline` to `DebugLogCategory` after `case debugLog = "debug.log"` (raw value defaults to `"pipeline"`)
- [ ] 1.2 Build the project to confirm no compiler errors: `xcodebuild build -scheme MangaTranslator -destination 'platform=macOS' 2>&1 | tail -5`

## 2. TDD — Same-language OCR skip

- [ ] 2.1 Create `MangaTranslatorTests/TranslationViewModelTests.swift` with `@testable import MangaTranslator`. Add helper types:
  - `ThrowingOCRRecognizer` — always throws `PaddleOCRError.inferenceFailed("forced")`, proves OCR was reached
  - `MockComicTextDetectorSingle` — returns one `DetectedTextRegion(boundingBox: CGRect(x:0,y:0,width:10,height:10), confidence:1.0, classIndex:0)`
  - `TrackingTranslationService` — records whether `translate(bubbles:from:to:context:)` was called; passthrough for any bubbles it receives
  - `MockCapabilityChecker`, `MockDownloadManager` — same as in `OCRRouterTests.swift`
  - `makeTestImage()` — 100×100 bitmap-backed `NSImage`

  Add test `testSameLanguageSkipsOCRAndTranslation`:
  ```swift
  @MainActor
  func testSameLanguageSkipsOCRAndTranslation() async {
      // If OCR is reached, the throwing recognizer makes the page error out.
      let recognizer = ThrowingOCRRecognizer()
      let service = MangaOCRService(detector: MockComicTextDetectorSingle())
      await service.setRecognizer(recognizer)
      let router = OCRRouter(
          mangaOCRService: service,
          capabilityChecker: MockCapabilityChecker(.unsupported),
          downloadManager: MockDownloadManager(state: .notDownloaded, enabled: false),
          paddleOCRFactory: { throw PaddleOCRError.modelUnavailable }
      )
      var translationCalled = false
      let translationService = TrackingTranslationService(onTranslate: { translationCalled = true })

      let prefs = PreferencesService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
      prefs.targetLanguage = .ja  // same as default source (.ja)
      let vm = TranslationViewModel(preferences: prefs, ocrRouter: router, translationService: translationService)
      var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/same-lang.jpg"))
      page.image = makeTestImage()
      vm.pages = [page]

      await vm.translatePage(at: 0, bypassCache: true)

      // OCR skipped → state is .translated, not .error
      guard case .translated(let bubbles) = vm.pages[0].state else {
          return XCTFail("Expected .translated([]), got \(vm.pages[0].state)")
      }
      XCTAssertTrue(bubbles.isEmpty, "Same-language page must produce no translated bubbles")
      XCTAssertFalse(translationCalled, "Translation must not be called for same-language page")
      // Guard fires before image-hash computation → imageHash stays nil
      XCTAssertNil(vm.pages[0].imageHash, "imageHash must not be set when same-language guard fires first")
  }
  ```
- [ ] 2.2 Run the test and confirm it fails: `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -destination 'platform=macOS' -only-testing:MangaTranslatorTests/TranslationViewModelTests/testSameLanguageSkipsOCRAndTranslation 2>&1 | grep -E "passed|failed|error"`
- [ ] 2.3 In `TranslationViewModel.translatePage(at:bypassCache:)`, add the early-exit guard as the first statement after `pages[index].state = .processing`, before image loading or hash computation:
  ```swift
  guard preferences.sourceLanguage != preferences.targetLanguage else {
      DebugLogger.shared.log(
          "Page \(index): skipped OCR and translation — source == target",
          level: .info,
          category: .pipeline,
          metadata: [
              "page_index": "\(index)",
              "source_language": preferences.sourceLanguage.rawValue,
              "target_language": preferences.targetLanguage.rawValue,
              "reason": "same_language"
          ]
      )
      pages[index].state = .translated([])
      return
  }
  ```
- [ ] 2.4 Remove the `let needsTranslation = preferences.sourceLanguage != preferences.targetLanguage` line and update the API key guard condition from `if needsTranslation && ...` to `if translationServiceOverride == nil && ...`
- [ ] 2.5 Run the test and confirm it passes

## 3. TDD — Meaningless bubble filter

- [ ] 3.1 In `TranslationViewModelTests.swift`, add:
  - `MockOCRRecognizer(text:)` — returns a fixed `text` string for every `recognizeText` call
  - `MockComicTextDetectorDouble` — returns two `DetectedTextRegion` each with `CGRect(x:0,y:0,width:10,height:10)`
  - `SequentialOCRRecognizer(texts:)` — returns `texts[0]` on first call, `texts[1]` on second call, etc.
  - `makeRouter(recognizerText:)` — helper that builds an `OCRRouter` using `MangaOCRService(detector: MockComicTextDetectorSingle())` + `MockOCRRecognizer(text:recognizerText)`, MangaOCR path only
  - `makeRouterSequential(texts:)` — same but uses `MockComicTextDetectorDouble` + `SequentialOCRRecognizer(texts:texts)`
  - `makePrefs(source:target:)` — returns `PreferencesService` with isolated `UserDefaults` and the given language pair

  Add three tests:

  **Test A** — punct-only bubbles excluded from sidebar:
  ```swift
  @MainActor
  func testPunctuationOnlyBubblesNotInSidebar() async {
      let router = makeRouter(recognizerText: "。")
      let prefs = makePrefs(source: .ja, target: .zhHant)
      let vm = TranslationViewModel(preferences: prefs, ocrRouter: router, translationService: TrackingTranslationService())
      var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/punct.jpg"))
      page.image = makeTestImage()
      vm.pages = [page]
      await vm.translatePage(at: 0, bypassCache: true)
      guard case .translated(let bubbles) = vm.pages[0].state else {
          return XCTFail("Expected .translated, got \(vm.pages[0].state)")
      }
      XCTAssertTrue(bubbles.isEmpty, "Punct-only bubbles must not appear in sidebar")
  }
  ```

  **Test B** — all-meaningless page produces empty sidebar and skips translation:
  ```swift
  @MainActor
  func testAllMeaninglessBubblesProducesEmptySidebarAndSkipsTranslation() async {
      var translationCalled = false
      let router = makeRouter(recognizerText: "—")
      let prefs = makePrefs(source: .ja, target: .zhHant)
      let vm = TranslationViewModel(
          preferences: prefs,
          ocrRouter: router,
          translationService: TrackingTranslationService(onTranslate: { translationCalled = true })
      )
      var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/all-meaningless.jpg"))
      page.image = makeTestImage()
      vm.pages = [page]
      await vm.translatePage(at: 0, bypassCache: true)
      // Current code passthroughs punct bubbles into .translated → this assert goes red first
      guard case .translated(let bubbles) = vm.pages[0].state else {
          return XCTFail("Expected .translated, got \(vm.pages[0].state)")
      }
      XCTAssertTrue(bubbles.isEmpty, "All-meaningless page must produce no sidebar entries")
      XCTAssertFalse(translationCalled, "Translation must not be called when all bubbles are meaningless")
  }
  ```

  **Test C** — mixed bubbles: only meaningful ones reach sidebar:
  ```swift
  @MainActor
  func testMixedBubblesOnlyMeaningfulInSidebar() async {
      // Region 0 → "こんにちは" (meaningful), Region 1 → "。" (punct-only)
      let router = makeRouterSequential(texts: ["こんにちは", "。"])
      let prefs = makePrefs(source: .ja, target: .zhHant)
      let vm = TranslationViewModel(preferences: prefs, ocrRouter: router, translationService: TrackingTranslationService())
      var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/mixed.jpg"))
      page.image = makeTestImage()
      vm.pages = [page]
      await vm.translatePage(at: 0, bypassCache: true)
      guard case .translated(let bubbles) = vm.pages[0].state else {
          return XCTFail("Expected .translated, got \(vm.pages[0].state)")
      }
      XCTAssertEqual(bubbles.count, 1)
      XCTAssertEqual(bubbles[0].bubble.text, "こんにちは")
  }
  ```

- [ ] 3.2 Run all three tests and confirm they fail: `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -destination 'platform=macOS' -only-testing:MangaTranslatorTests/TranslationViewModelTests 2>&1 | grep -E "passed|failed|error"`
- [ ] 3.3 In `translatePage`, replace the existing `if preferences.sourceLanguage == preferences.targetLanguage || ordered.allSatisfy(...)` block and the `else` block with:
  ```swift
  let meaningful = ordered.filter { !$0.text.allSatisfy { $0.isPunctuation || $0.isWhitespace } }
  let skippedCount = ordered.count - meaningful.count
  if skippedCount > 0 {
      DebugLogger.shared.log(
          "Page \(index): filtered \(skippedCount) of \(ordered.count) meaningless bubble(s)",
          level: .info,
          category: .pipeline,
          metadata: [
              "page_index": "\(index)",
              "filtered_count": "\(skippedCount)",
              "total_count": "\(ordered.count)"
          ]
      )
  }
  let translated: [TranslatedBubble]
  if meaningful.isEmpty {
      DebugLogger.shared.log(
          "Page \(index): no meaningful bubbles after OCR — skipping translation",
          level: .info,
          category: .pipeline,
          metadata: ["page_index": "\(index)", "reason": "all_bubbles_meaningless"]
      )
      translated = []
  } else {
      let context = buildTranslationContext()
      let output = try await selectedTranslationService.translate(
          bubbles: meaningful,
          from: preferences.sourceLanguage,
          to: preferences.targetLanguage,
          context: context
      )
      if let glossaryID = activeGlossaryID, !output.detectedTerms.isEmpty {
          glossaryService.insertDetectedTerms(output.detectedTerms, glossaryID: glossaryID)
          glossaries = glossaryService.listGlossaries()
      }
      translated = output.bubbles.sorted { $0.index < $1.index }
  }
  ```
- [ ] 3.4 Run all three tests — confirm they pass
- [ ] 3.5 Run the full test suite: `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -destination 'platform=macOS' 2>&1 | grep -E "passed|failed|error"`

## 4. Cleanup and commit

- [ ] 4.1 Verify `needsTranslation` variable is fully removed from `translatePage` and no dead code remains from the old `if/else` block
- [ ] 4.2 Build and run the app manually: set source == target language, open an image, confirm the debug log view shows a `pipeline` category entry with `reason: same_language` metadata
- [ ] 4.3 Commit: `git add MangaTranslator/Services/DebugLogger.swift MangaTranslator/ViewModels/TranslationViewModel.swift MangaTranslatorTests/TranslationViewModelTests.swift && git commit -m "feat(pipeline): skip OCR for same-language, filter meaningless bubbles, log skip reasons"`
