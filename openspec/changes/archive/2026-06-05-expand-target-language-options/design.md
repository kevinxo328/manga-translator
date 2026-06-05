## Context

`Language` currently contains Japanese, English, and Traditional Chinese. Source pickers already use `Language.sourceLanguages`, but target pickers use `Language.allCases`, which couples UI behavior to every enum case. Translation provider integrations also map `Language` values to provider-specific codes in `GoogleTranslationService` and `DeepLTranslationService`.

The OCR pipeline only supports English and Japanese as source languages, so this change expands only target languages.

## Goals / Non-Goals

**Goals:**

- Add common target languages without changing OCR source-language support.
- Keep source and target pickers sorted A-Z by English display name.
- Make target-language availability explicit through `Language.targetLanguages`.
- Keep Google Translate, DeepL, OpenAI Compatible, and GitHub Copilot usable for the expanded target-language list.

**Non-Goals:**

- Add OCR support for additional source languages.
- Add per-engine language availability filtering in the picker.
- Dynamically fetch language lists from translation providers.

## Decisions

1. Define source and target picker order in the model layer.

   `Language.sourceLanguages` will become `[.en, .ja]`, and a new `Language.targetLanguages` will define `[.en, .fr, .de, .id, .ja, .ko, .ptBR, .zhHans, .es, .zhHant, .vi]`. This keeps toolbar and settings picker behavior consistent and testable. The alternative was sorting inside each view, but that duplicates behavior and makes ordering easier to drift.

2. Keep provider mappings static.

   Google and DeepL already use static language-code switches. Extending those switches keeps implementation small and matches the existing provider pattern. The alternative was calling provider language-list APIs, but that adds network behavior, caching, and engine-specific picker filtering that is larger than this change.

3. Use English display names with flag emoji.

   The existing picker style uses flag emoji plus English language names. New languages will follow the same display convention, including `"🇧🇷 Portuguese (Brazil)"` for the Portuguese target variant.

## Risks / Trade-offs

- [Risk] A provider changes language-code support after release. → Mitigation: use documented provider codes and keep mappings isolated in provider services for quick updates.
- [Risk] DeepL support can differ by language variant or account capability. → Mitigation: keep provider error handling unchanged so unsupported-language responses surface as sanitized provider API errors.
- [Risk] Adding more picker items makes toolbar menus longer. → Mitigation: keep the initial expansion to eight additional target languages and preserve source-language constraints.
