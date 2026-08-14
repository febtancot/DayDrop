import XCTest
@testable import DayDrop

final class HistoryClassificationTests: XCTestCase {
    func testClassifiesCommonFileTypesWithoutReadingContents() {
        let expectations: [(String, HistoryFileCategory)] = [
            ("report.pdf", .document),
            ("photo.HEIC", .image),
            ("recording.m4a", .audio),
            ("movie.mp4", .video),
            ("source.zip", .archive),
            ("installer.dmg", .diskImage),
            ("package.pkg", .application),
            ("main.swift", .code),
            ("metrics.csv", .data),
            ("README", .unknown)
        ]

        for (fileName, expectedCategory) in expectations {
            XCTAssertEqual(
                FileTypeClassifier.category(forFileName: fileName),
                expectedCategory,
                fileName
            )
        }
    }
}

