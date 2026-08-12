import Foundation
import XCTest
@testable import DayDrop

final class DownloadsBookmarkStoreTests: XCTestCase {
    func testBookmarkPersistsAndResolvesUsingIsolatedDefaultsSuite() throws {
        let suiteName = "DayDropTests.Bookmark.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Unable to create isolated UserDefaults suite.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDropBookmarkTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let writer = DownloadsBookmarkStore(defaults: defaults)
        XCTAssertFalse(writer.hasSavedBookmark)
        try writer.saveBookmark(for: directory)
        XCTAssertTrue(writer.hasSavedBookmark)

        let reader = DownloadsBookmarkStore(defaults: defaults)
        let resolution = try reader.resolveBookmark()
        XCTAssertEqual(
            resolution.url.resolvingSymlinksInPath().standardizedFileURL,
            directory.resolvingSymlinksInPath().standardizedFileURL
        )
        XCTAssertFalse(resolution.wasStale)
        XCTAssertFalse(resolution.rebuiltStaleBookmark)

        reader.clearBookmark()
        XCTAssertFalse(writer.hasSavedBookmark)
        XCTAssertThrowsError(try reader.resolveBookmark()) { error in
            guard case DownloadsBookmarkError.noSavedBookmark = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
