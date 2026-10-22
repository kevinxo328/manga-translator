# 04: Replace project-text tests with structured project contracts

**What to build:** Release and target-boundary requirements are verified through structured project/configuration checks rather than hard-coded project text and object IDs.

**Blocked by:** 02: Build the repository-local validator foundation.

**Status:** resolved

- [x] MLX and PaddleOCRVL target ownership is checked without PBX object-ID assertions.
- [x] Deployment, entitlement, Sparkle, and required resource contracts are validated structurally.
- [x] A deliberate target/configuration violation fails the replacement check and restoration passes.
- [x] Obsolete project-string tests are removed only where the validator covers their contract.

## Comments

- Red/green evidence: `releaseArtifactRejectsMissingMetalLibrary` first failed to compile because the validator had no release-artifact contract. It now proves the CLI returns `release.mlx-metallib` for a missing Metal library and succeeds after restoring `default.metallib`. `projectContractsRequireMLXImplementationImports` rejects a fixture missing the MLX/PaddleOCRVL imports, and `projectContractsRejectDirectMLXTargetLinkage` rejects a fixture where the app target links MLX directly; both succeed after restoration.
- Verification: `swift test --package-path Tools/RepositoryValidator`; `swift run --package-path Tools/RepositoryValidator repository-validator .`; `swift run --package-path Tools/RepositoryValidator repository-validator --release-app .xcodebuild-env/DerivedData/Build/Products/Release/MangaTranslator.app`; and the focused `ProjectStructureTests` Xcode run passed.

