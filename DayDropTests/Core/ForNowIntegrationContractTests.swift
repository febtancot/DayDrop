import XCTest
@testable import DayDrop

final class ForNowIntegrationContractTests: XCTestCase {
    func testUsesRequestedDisplayName() {
        XCTAssertEqual(ForNowIntegrationContract.displayName, "搁这儿-ForNow")
        XCTAssertEqual(
            ForNowIntegrationContract.homepageURL.absoluteString,
            "https://fornow.liveby.app"
        )
    }

    func testReadyRequiresMatchingBundleAndCapabilityVersion() {
        let applicationURL = URL(fileURLWithPath: "/Applications/ForNow.app")

        XCTAssertEqual(
            ForNowIntegrationContract.availability(
                resolvedApplicationURL: applicationURL,
                resolvedBundleIdentifier: ForNowIntegrationContract.bundleIdentifier,
                externalFileImportVersion: 1
            ),
            .ready(applicationURL: applicationURL)
        )
    }

    func testMissingApplicationIsNotInstalled() {
        XCTAssertEqual(
            ForNowIntegrationContract.availability(
                resolvedApplicationURL: nil,
                resolvedBundleIdentifier: nil,
                externalFileImportVersion: nil
            ),
            .notInstalled
        )
    }

    func testOldOrUnexpectedApplicationRequiresUpdate() {
        let applicationURL = URL(fileURLWithPath: "/Applications/ForNow.app")

        XCTAssertEqual(
            ForNowIntegrationContract.availability(
                resolvedApplicationURL: applicationURL,
                resolvedBundleIdentifier: ForNowIntegrationContract.bundleIdentifier,
                externalFileImportVersion: nil
            ),
            .updateRequired
        )
        XCTAssertEqual(
            ForNowIntegrationContract.availability(
                resolvedApplicationURL: applicationURL,
                resolvedBundleIdentifier: "com.example.other",
                externalFileImportVersion: 1
            ),
            .updateRequired
        )
    }

    func testSelectionKeepsUniqueFileURLsInOrder() {
        let first = URL(fileURLWithPath: "/tmp/first.txt")
        let second = URL(fileURLWithPath: "/tmp/second.pdf")

        XCTAssertEqual(
            ForNowIntegrationContract.normalizedFileURLs([
                first,
                URL(string: "https://example.com")!,
                first,
                second
            ]),
            [first, second]
        )
    }
}
