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

    func testMLXTargetsDeclareTransitivePackageProductsExplicitly() throws {
        let projectContents = try String(
            contentsOf: repositoryRoot.appendingPathComponent("MangaTranslator.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let requiredProducts = ["MLX", "MLXNN", "MLXFast", "MLXRandom", "Numerics"]

        let mlxTargetBlock = try XCTUnwrap(nativeTargetBlock(named: "MangaTranslatorMLX", in: projectContents))
        for product in requiredProducts {
            XCTAssertTrue(
                mlxTargetBlock.contains("/* \(product) */"),
                "MangaTranslatorMLX must explicitly declare package product \(product)"
            )
        }

        let appTargetBlock = try XCTUnwrap(nativeTargetBlock(named: "MangaTranslator", in: projectContents))
        for product in requiredProducts + ["PaddleOCRVL"] {
            XCTAssertFalse(
                appTargetBlock.contains("/* \(product) */"),
                "MangaTranslator must not directly link \(product); MangaTranslatorMLX owns the MLX stack"
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

    func testSandboxedSparkleInstallerServiceIsEnabled() throws {
        let infoPlist = try loadPropertyList(at: repositoryRoot.appendingPathComponent("MangaTranslator/Info.plist"))

        XCTAssertEqual(
            infoPlist["SUEnableInstallerLauncherService"] as? Bool,
            true,
            "Sandboxed Sparkle apps must enable the installer launcher service so downloaded updates can be installed outside the app sandbox."
        )
    }

    func testSandboxedSparkleInstallerMachLookupEntitlementsArePresent() throws {
        let entitlements = try loadPropertyList(at: repositoryRoot.appendingPathComponent("MangaTranslator/MangaTranslator.entitlements"))
        let machLookupNames = entitlements["com.apple.security.temporary-exception.mach-lookup.global-name"] as? [String]

        XCTAssertEqual(
            machLookupNames,
            [
                "$(PRODUCT_BUNDLE_IDENTIFIER)-spks",
                "$(PRODUCT_BUNDLE_IDENTIFIER)-spki"
            ],
            "Sparkle's sandboxed installer needs these mach lookup exceptions to report installation status back to the app."
        )
    }

    private func nativeTargetBlock(named targetName: String, in projectContents: String) -> String? {
        guard let nameRange = projectContents.range(of: "name = \(targetName);") else { return nil }
        guard let start = projectContents[..<nameRange.lowerBound].range(of: "\t\t", options: .backwards)?.lowerBound else {
            return nil
        }
        guard let end = projectContents[nameRange.upperBound...].range(of: "\n\t\t};")?.upperBound else {
            return nil
        }
        return String(projectContents[start..<end])
    }

    private func loadPropertyList(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )
    }
}
