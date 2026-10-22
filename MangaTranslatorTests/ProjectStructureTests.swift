import XCTest

final class ProjectStructureTests: XCTestCase {
    private let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func testMangaTranslatorSchemeDoesNotReferenceStandaloneParityDiagnosticTarget() throws {
        let schemeContents = try String(
            contentsOf: repositoryRoot.appendingPathComponent("MangaTranslator.xcodeproj/xcshareddata/xcschemes/MangaTranslator.xcscheme"),
            encoding: .utf8
        )

        XCTAssertFalse(schemeContents.contains("PaddleOCRParityDiagnosticTests.xctest"))
        XCTAssertFalse(schemeContents.contains("PaddleOCRParityDiagnosticTests"))
    }

    func testParityDiagnosticSuiteHasDedicatedScheme() throws {
        let schemeURL = repositoryRoot.appendingPathComponent(
            "MangaTranslator.xcodeproj/xcshareddata/xcschemes/PaddleOCRParityDiagnostic.xcscheme"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: schemeURL.path))

        let schemeContents = try String(contentsOf: schemeURL, encoding: .utf8)
        XCTAssertTrue(schemeContents.contains("PaddleOCRParityDiagnosticTests.xctest"))
        XCTAssertTrue(schemeContents.contains("PaddleOCRParityDiagnostic.xctestplan"))
    }

    func testProjectMovesParityDiagnosticFileOutOfMainTestTarget() throws {
        let projectContents = try String(
            contentsOf: repositoryRoot.appendingPathComponent("MangaTranslator.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        XCTAssertTrue(projectContents.contains("PBXNativeTarget \"PaddleOCRParityDiagnosticTests\""))
        XCTAssertFalse(projectContents.contains("T1000001000000000000000B /* PaddleOCRProductionParityDiagnosticTests.swift in Sources */"))
    }

    func testGlobalAccentColorBuildSettingReferencesExistingColorset() throws {
        let projectContents = try String(
            contentsOf: repositoryRoot.appendingPathComponent("MangaTranslator.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let assetCatalog = repositoryRoot.appendingPathComponent("MangaTranslator/Assets.xcassets")

        let regex = try NSRegularExpression(pattern: #"ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = ([^;]+);"#)
        let range = NSRange(projectContents.startIndex..<projectContents.endIndex, in: projectContents)
        let matches = regex.matches(in: projectContents, range: range)

        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: projectContents) else { continue }
            let colorName = String(projectContents[nameRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let colorsetURL = assetCatalog.appendingPathComponent("\(colorName).colorset")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: colorsetURL.path),
                "Global accent color \(colorName) must exist as \(colorName).colorset"
            )
        }
    }

    func testMLXPackageUsesPatchedForkRevision() throws {
        let projectContents = try String(
            contentsOf: repositoryRoot.appendingPathComponent("MangaTranslator.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let paddlePackageContents = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Vendor/paddleocr-vl.swift/Package.swift"),
            encoding: .utf8
        )
        let patchedRevision = "4b421e0137a901855882abfea9e2296101cfc9c1"

        XCTAssertTrue(projectContents.contains(#"repositoryURL = "https://github.com/kevinxo328/mlx-swift";"#))
        XCTAssertTrue(projectContents.contains("revision = \(patchedRevision);"))
        XCTAssertTrue(paddlePackageContents.contains(#".package(url: "https://github.com/kevinxo328/mlx-swift", revision: "\#(patchedRevision)")"#))
        XCTAssertFalse(projectContents.contains(#"relativePath = "Vendor/mlx-swift";"#))
        XCTAssertFalse(projectContents.contains(#"repositoryURL = "https://github.com/ml-explore/mlx-swift";"#))
        XCTAssertFalse(paddlePackageContents.contains(#"https://github.com/ml-explore/mlx-swift"#))
    }

    func testUpdateSettingControlsOnlyAutomaticChecks() throws {
        let settingsSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("MangaTranslator/Views/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(settingsSource.contains("updater.automaticallyChecksForUpdates = $0"))
        XCTAssertFalse(
            settingsSource.contains("updater.automaticallyDownloadsUpdates"),
            "The automatic-check preference must not opt the user into background downloads."
        )
    }

}
