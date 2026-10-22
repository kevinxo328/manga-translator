## Problem Statement

MangaTranslator's automated quality boundary is incomplete and uneven. Pull requests have no CI gate, the local pre-push hook only transfers Git LFS objects, and several test files verify Swift source text or reimplement standard-library logic instead of exercising product behaviour. Project configuration and logging policies are protected by brittle string scans rather than structured checks. Important invariants such as cache identity, secret handling, translation-engine capabilities, target ownership, and batch concurrency remain partly textual conventions instead of enforceable contracts.

## Solution

Create a fail-closed quality system for pull requests. It will run the normal application suite plus repository-local structured validators, replace implementation-text assertions with unit or macOS UI behaviour tests, and establish explicit domain types and registries where they prevent invalid states. OCR quality benchmarks and PaddleOCR parity diagnostics remain independently runnable, scheduled or manually dispatched checks rather than PR blockers. GitHub required checks will protect the main branch.

## User Stories

1. As a contributor, I want every pull request to receive a deterministic application-test and policy result, so that regressions are found before merge.
2. As a maintainer, I want main-branch merging to require successful quality checks, so that CI results cannot be ignored.
3. As a contributor, I want a fast feedback lane, so that normal code changes do not wait on model-heavy OCR diagnostics.
4. As an OCR maintainer, I want benchmark and parity diagnostics to remain runnable separately, so that quality investigation is not lost when PR CI is kept fast.
5. As a maintainer, I want tests to prove user-observable behaviour, so that harmless refactors do not fail merely because implementation spelling changed.
6. As a user, I want toolbar cancellation to work during processing, so that I can stop a batch rather than wait for it to finish.
7. As a user, I want Copilot settings to present the controls appropriate to the current loading state, so that retry and model selection remain usable.
8. As a maintainer, I want logging-policy violations to fail deterministically, so that secrets and diagnostics follow the supported logging path.
9. As a maintainer, I want Xcode target ownership and release configuration validated structurally, so that MLX and Sparkle configuration regressions are caught without hard-coded project-object IDs.
10. As a user, I want credentials never to be persisted or logged outside Keychain, so that provider secrets remain protected.
11. As a developer, I want cache operations to require complete cache identity, so that entries cannot accidentally cross image, language, or engine contexts.
12. As a user, I want translation engines to have one authoritative capability definition, so that settings, service construction, and UI do not drift.
13. As a user, I want batch translation to remain limited to three concurrent pages, so that provider rate limits and application responsiveness are protected.
14. As a maintainer, I want every new static rule to be a blocking rule from its first merge, so that temporary warnings do not become permanent debt.
15. As a reviewer, I want each retired test to have a demonstrated replacement, so that test cleanup cannot silently reduce coverage.
16. As a maintainer, I want every migration slice to demonstrate an intentional product break, a red replacement check, restoration, and a green suite, so that the new protection is credible.

## Implementation Decisions

- The repository remains dependency-light: validators are versioned local Swift tooling or scripts. The validator package alone may depend on pinned SwiftSyntax/SwiftParser for source-accurate AST analysis; no third-party lint or dependency-graph package is introduced into the app target.
- The PR lane runs the normal MangaTranslator test scheme, repository-local policy/config validation, and the focused macOS UI tests. It does not run OCRBenchmark or PaddleOCRParityDiagnostic.
- OCRBenchmark and PaddleOCR parity diagnostics are exposed as scheduled and manually dispatched GitHub Actions workflows with their existing data/artifact prerequisites made explicit.
- A local validator owns source-policy and project-policy checks. It parses structured inputs where available and avoids line-oriented substring scanning as the policy mechanism.
- Direct logging, secret persistence, target ownership, deployment/release configuration, and forbidden dependency directions become fail-closed validator rules.
- A small macOS UI-test target verifies critical interactive controls through stable accessibility identifiers. Pure state-to-action decisions are extracted behind a narrow seam and tested in the existing fast test target.
- Implementation-text tests are replaced only after their replacement proves a deliberately introduced product regression. Tests that validate runtime output, database state, request payloads, security redaction, or diagnostic artifacts are retained.
- Cache identity becomes a dedicated value object built from an image-content hash and translation context. Service APIs cease to accept an unstructured hash/context combination where the value object can express the contract.
- Provider credentials use a dedicated secret/API-key type at Keychain and logging boundaries. Raw secret strings must not be accepted by persistence or diagnostic APIs.
- Translation-engine metadata is centralized in one registry used by UI and service selection. The registry owns capabilities such as credential requirements and supported service behaviour.
- The three-page batch limit is a named pipeline limit with one authority, used by every batch scheduling path.
- The dependency direction is enforced as Views to ViewModels/Models, ViewModels to Services/Models, and service implementation details below those layers. The application target must not directly own MLX/PaddleOCRVL linkage that belongs to the MLX target.
- GitHub Actions configuration is committed to the repository. Main-branch rulesets/branch protection require the resulting PR checks. If the authenticated account cannot change repository rules, the implementation records the exact remaining external action rather than claiming completion.

## Testing Decisions

- A good test calls a product seam and observes state, output, accessibility-visible controls, requests, or persisted data; it does not assert incidental source text, layout implementation primitives, or standard-library behaviour.
- Existing service, cache, view-model, and URLProtocol seams are preferred for unit and integration coverage.
- The macOS UI-test seam is reserved for a small critical set: cancellation action availability and Copilot loading/model/retry controls.
- The validator has fixture-based tests for accepted and rejected source/config examples, plus intentional mutation verification against the repository before an old guard test is removed.
- Every ticket contains the red-break/restore-green sequence and runs the relevant focused checks before the main suite.
- The normal MangaTranslator scheme is the required application regression suite. OCRBenchmark and PaddleOCRParityDiagnostic are separate quality/diagnostic suites and are not treated as fast feedback tests.

## Out of Scope

- Changing OCR recognition algorithms, model weights, translation-provider semantics, or release signing credentials.
- Replacing all SwiftUI coverage with screenshots or adding a broad visual-regression framework.
- Altering user-facing product copy except where an accessibility identifier or a behaviour-focused assertion requires stable semantics.
- Automatically changing GitHub organization policy outside this repository's branch protection/ruleset.

## Further Notes

- The source-text tests identified in the audit are migration candidates, not proof that every negative assertion is invalid. Secret-redaction, request-payload, cache, and persisted-output negative assertions remain valid runtime contracts.
- The plan is intentionally fail-closed only after the relevant replacement is demonstrated red against a deliberate regression and green after restoration.
