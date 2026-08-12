import XCTest
@testable import DayDrop

final class DownloadCandidatePolicyTests: XCTestCase {
    private let policy = DownloadCandidatePolicy()

    func testOrdinaryTopLevelFileIsEligible() {
        XCTAssertEqual(
            policy.evaluate(fileName: "report.pdf", isHidden: false, isDirectory: false),
            .eligible
        )
    }

    func testAllBrowserTemporarySuffixesAreRejectedCaseInsensitively() {
        let namesAndSuffixes = [
            ("video.mp4.crdownload", ".crdownload"),
            ("document.pdf.download", ".download"),
            ("archive.zip.part", ".part"),
            ("export.TMP", ".tmp")
        ]

        for (name, suffix) in namesAndSuffixes {
            XCTAssertEqual(
                policy.evaluate(fileName: name, isHidden: false, isDirectory: false),
                .rejected(.temporarySuffix(suffix)),
                name
            )
        }
    }

    func testFinderHiddenMetadataIsRejected() {
        XCTAssertEqual(
            policy.evaluate(fileName: "report.pdf", isHidden: true, isDirectory: false),
            .rejected(.hidden)
        )
    }

    func testDotfileIsRejectedEvenWithoutHiddenMetadata() {
        XCTAssertEqual(
            policy.evaluate(fileName: ".env", isHidden: false, isDirectory: false),
            .rejected(.hidden)
        )
        XCTAssertFalse(policy.isEligible(fileName: ".report.pdf", isHidden: false, isDirectory: false))
    }

    func testDirectoryIsRejected() {
        XCTAssertEqual(
            policy.evaluate(fileName: "Existing Folder", isHidden: false, isDirectory: true),
            .rejected(.directory)
        )
    }

    func testTemporaryMarkerInsideACompletedFileNameDoesNotRejectIt() {
        XCTAssertTrue(
            policy.isEligible(fileName: "notes.tmp.txt", isHidden: false, isDirectory: false)
        )
    }
}
