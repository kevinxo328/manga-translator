import XCTest

final class ProjectStructureTests: XCTestCase {
    private let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func testMangaTranslatorSchemeDoesNotReferenceStandaloneParityDiagnosticTarget() throws {
        let schemeContents = try String(
            contentsOf: repositoryRoot.appendingPathComponent("MangaTranslator.xcodeproj/xcshareddata/xcschemes/MangaTranslator.xcscheme")
        )

        XCTAssertFalse(schemeContents.contains("PaddleOCRParityDiagnosticTests.xctest"))
        XCTAssertFalse(schemeContents.contains("PaddleOCRParityDiagnosticTests"))
    }

    func testParityDiagnosticSuiteHasDedicatedScheme() throws {
        let schemeURL = repositoryRoot.appendingPathComponent(
            "MangaTranslator.xcodeproj/xcshareddata/xcschemes/PaddleOCRParityDiagnostic.xcscheme"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: schemeURL.path))

        let schemeContents = try String(contentsOf: schemeURL)
        XCTAssertTrue(schemeContents.contains("PaddleOCRParityDiagnosticTests.xctest"))
        XCTAssertTrue(schemeContents.contains("PaddleOCRParityDiagnostic.xctestplan"))
    }

    func testProjectMovesParityDiagnosticFileOutOfMainTestTarget() throws {
        let projectContents = try String(
            contentsOf: repositoryRoot.appendingPathComponent("MangaTranslator.xcodeproj/project.pbxproj")
        )

        XCTAssertTrue(projectContents.contains("PBXNativeTarget \"PaddleOCRParityDiagnosticTests\""))
        XCTAssertFalse(projectContents.contains("T1000001000000000000000B /* PaddleOCRProductionParityDiagnosticTests.swift in Sources */"))
    }
}
